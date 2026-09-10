function modelResult = parameterizePowerSpectrum(freq, power, fooofCfg)
%PARAMETERIZEPOWERSPECTRUM Fit fixed/knee aperiodic and Gaussian peaks.
%   MODELRESULT = PARAMETERIZEPOWERSPECTRUM(FREQ, POWER, CFG) accepts
%   linear-frequency and linear-power arrays (frequency x channels). It
%   excludes 0 Hz and non-positive/non-finite power, fits
%   log10(P)=offset-exponent*log10(F), detects residual peaks, estimates
%   Gaussian peaks by a bounded grid search, and refits the aperiodic model
%   after subtracting the fitted peaks in log space. No Python is called.

arguments
    freq (:,1) double
    power double
    fooofCfg (1,1) struct
end

required = {'frequencyRange', 'aperiodicMode', 'peakWidthLimits', ...
    'maxNumberPeaks', 'minPeakHeight', 'peakThreshold', 'fitErrorMetric'};
for index = 1:numel(required)
    if ~isfield(fooofCfg, required{index})
        error('LFP:InvalidFooofConfig', 'fooofCfg.%s is required.', required{index});
    end
end
mode = lower(string(fooofCfg.aperiodicMode));
if ~ismember(mode, ["fixed" "knee"])
    error('LFP:UnsupportedAperiodicMode', 'aperiodicMode must be fixed or knee.');
end
if numel(fooofCfg.frequencyRange) ~= 2 || fooofCfg.frequencyRange(2) <= fooofCfg.frequencyRange(1)
    error('LFP:InvalidFitRange', 'fooofCfg.frequencyRange must be increasing.');
end
if isvector(power) && numel(power) == numel(freq)
    power = power(:);
elseif size(power, 1) ~= numel(freq) && size(power, 2) == numel(freq)
    % Accept channels-by-frequency input and normalize to frequency-by-channel.
    power = power.';
end
if size(power, 1) ~= numel(freq)
    error('LFP:InvalidSpectrum', ...
        'POWER must be frequency-by-channel (or channel-by-frequency); got [%d %d] for %d frequencies.', ...
        size(power, 1), size(power, 2), numel(freq));
end
if any(~isfinite(freq)) || any(diff(freq) <= 0) || any(freq < 0)
    error('LFP:InvalidSpectrum', 'FREQ must be finite, nonnegative and strictly increasing.');
end

% The PSD grid is used exactly as returned by the estimator.  In particular,
% no line-noise interpolation, frequency densification, or gap filling is
% performed here.  Legacy interpolation fields are accepted only so old
% configurations remain loadable.
fitPower = power;
legacyInterpolation = isfield(fooofCfg, 'interpolateLineNoise');
lineNoise = struct('enabled', false, 'interpolatedMask', false(numel(freq), 1), ...
    'rangesHz', zeros(0, 2), 'method', "not applied", ...
    'warning', ternary_text(legacyInterpolation, ...
    "Legacy interpolateLineNoise ignored; PSD grid used without interpolation.", ""));
frequencyResolution = median(diff(freq));
fitRange = [max(fooofCfg.frequencyRange(1), min(freq(freq > 0))), ...
    min(fooofCfg.frequencyRange(2), freq(end))];
if fitRange(2) <= fitRange(1)
    error('LFP:InvalidFitRange', 'fooofCfg.frequencyRange does not overlap FREQ.');
end

nChannels = size(power, 2);
modelResult = repmat(empty_result(), 1, nChannels);
progress = get_field(fooofCfg, 'progressCallback', @(fraction, message)[]);
cancel = get_field(fooofCfg, 'cancellationCheck', @()[]);
if ~isa(progress, 'function_handle'), progress = @(fraction, message)[]; end
if ~isa(cancel, 'function_handle'), cancel = @()[]; end
storedCfg = strip_runtime_fields(fooofCfg);
for channel = 1:nChannels
    cancel();
    progress((channel - 1) / max(nChannels, 1), ...
        sprintf('specparam fitting: channel %d/%d', channel, nChannels));
    modelResult(channel) = fit_channel(freq, power(:, channel), fitPower(:, channel), ...
        storedCfg, fitRange, frequencyResolution, lineNoise);
end
progress(1, "specparam fitting complete");
end

function result = fit_channel(freq, inputPower, fittingPower, cfg, fitRange, frequencyResolution, lineNoise)
result = empty_result();
result.freq = freq;
result.inputPower = inputPower;
result.fittingPower = fittingPower;
result.lineNoise = lineNoise;
result.interpolationApplied = false;
result.frequencyResolution = frequencyResolution;
result.fitRange = fitRange;
result.settings = cfg;
result.warnings = strings(0, 1);
if cfg.peakWidthLimits(1) < 2 * frequencyResolution
    result.warnings(end + 1) = "Lower peak width limit is below twice the frequency resolution.";
end
if cfg.peakWidthLimits(2) <= cfg.peakWidthLimits(1) || any(cfg.peakWidthLimits <= 0)
    result.fitStatus = "failed";
    result.warnings(end + 1) = "peakWidthLimits must be positive and increasing.";
    return;
end

valid = freq > 0 & freq >= fitRange(1) & freq <= fitRange(2) & isfinite(fittingPower) & fittingPower > 0;
if nnz(valid) < 5
    result.fitStatus = "insufficient_data";
    result.warnings(end + 1) = "Fewer than five valid positive-power points in fit range.";
    return;
end
logFrequency = log10(freq(valid));
logPower = log10(fittingPower(valid));
[initialParams, initialModelValid, initialKeep, initialOk, initialWarning] = ...
    fit_aperiodic(freq(valid), logPower, cfg, cfg.peakThreshold);
if ~initialOk
    result.fitStatus = "failed";
    result.warnings(end + 1) = initialWarning;
    return;
end
if strlength(initialWarning) > 0, result.warnings(end + 1) = initialWarning; end
initialAperiodicLog = evaluate_aperiodic(freq, initialParams, cfg);
flattenedInitial = logPower - initialModelValid;
threshold = max(cfg.minPeakHeight, cfg.peakThreshold * robust_scale(flattenedInitial));
candidateIndices = find_candidates(freq(valid), flattenedInitial, threshold, ...
    get_field(cfg, 'minPeakDistanceHz', max(cfg.peakWidthLimits(1), 2 * frequencyResolution)));

gaussianParams = empty_gaussians();
gaussianLog = zeros(size(logPower));
for candidate = 1:numel(candidateIndices)
    if numel(gaussianParams) >= cfg.maxNumberPeaks, break; end
    peak = fit_gaussian(freq(valid), flattenedInitial, candidateIndices(candidate), cfg.peakWidthLimits, frequencyResolution);
    if peak.amplitudeLog10 < cfg.minPeakHeight, continue; end
    gaussianParams(end + 1) = peak; %#ok<AGROW>
    gaussianLog = gaussianLog + peak.amplitudeLog10 * exp(-0.5 * ...
        ((freq(valid) - peak.centerFrequencyHz) / peak.sigmaHz).^2);
end

finalLogPower = logPower - gaussianLog;
[finalParams, ~, ~, finalOk, finalWarning] = ...
    fit_aperiodic(freq(valid), finalLogPower, cfg, cfg.peakThreshold);
if ~finalOk
    result.fitStatus = "failed";
    result.warnings(end + 1) = "Final aperiodic refit failed: " + finalWarning;
    return;
end
if strlength(finalWarning) > 0, result.warnings(end + 1) = finalWarning; end
offset = finalParams.offset;
exponent = finalParams.exponent;
aperiodicLog = evaluate_aperiodic(freq, finalParams, cfg);
aperiodicFit = 10 .^ aperiodicLog;
gaussianTotalLog = zeros(size(freq));
for peakIndex = 1:numel(gaussianParams)
    gaussianTotalLog = gaussianTotalLog + gaussianParams(peakIndex).amplitudeLog10 * exp(-0.5 * ...
        ((freq - gaussianParams(peakIndex).centerFrequencyHz) / gaussianParams(peakIndex).sigmaHz).^2);
end
fullModelFit = 10 .^ (aperiodicLog + gaussianTotalLog);
periodicFit = max(fullModelFit - aperiodicFit, 0);
flattenedSpectrum = NaN(size(freq));
flattenedSpectrum(valid) = logPower - aperiodicLog(valid);
modelLog = log10(max(fullModelFit(valid), realmin));
rSquared = 1 - sum((logPower - modelLog).^2) / max(sum((logPower - mean(logPower)).^2), eps);
fitError = sqrt(mean((logPower - modelLog).^2));

peakParams = repmat(struct('CF', NaN, 'PW', NaN, 'BW', NaN, 'peakBand', "", ...
    'centerFrequencyHz', NaN, 'powerLog10', NaN, 'bandwidthHz', NaN), numel(gaussianParams), 1);
for index = 1:numel(gaussianParams)
    peakParams(index).CF = gaussianParams(index).centerFrequencyHz;
    peakParams(index).PW = gaussianParams(index).amplitudeLog10;
    peakParams(index).BW = gaussianParams(index).bandwidthHz;
    peakParams(index).centerFrequencyHz = gaussianParams(index).centerFrequencyHz;
    peakParams(index).powerLog10 = gaussianParams(index).amplitudeLog10;
    peakParams(index).bandwidthHz = gaussianParams(index).bandwidthHz;
    peakParams(index).peakBand = classify_band(gaussianParams(index).centerFrequencyHz);
end
result.logPower = NaN(size(freq));
result.logPower(valid) = logPower;
result.aperiodicParams = finalParams;
result.aperiodicFit = aperiodicFit;
result.periodicFit = periodicFit;
result.fullModelFit = fullModelFit;
result.flattenedSpectrum = flattenedSpectrum;
result.peakParams = peakParams;
result.gaussianParams = gaussianParams;
result.rSquared = rSquared;
result.fitError = fitError;
result.nPeaks = numel(gaussianParams);
result.fitStatus = "ok";
if ~isfinite(rSquared) || ~isfinite(fitError)
    result.fitStatus = "failed";
    result.warnings(end + 1) = "Fit quality is not finite.";
end
end

function [params, modelLog, keep, ok, warningText] = fit_aperiodic(freq, logPower, cfg, threshold)
%FIT_APERIODIC Fit the selected native fixed or knee background model.
freq = freq(:); logPower = logPower(:);
logFrequency = log10(freq);
[coefficients, keep] = robust_background(logFrequency, logPower, threshold);
if nnz(keep) < 3
    params = struct('offset', NaN, 'exponent', NaN, 'knee', NaN, ...
        'mode', lower(string(cfg.aperiodicMode)));
    modelLog = NaN(size(logPower)); ok = false;
    warningText = "Aperiodic fit has fewer than three robust points.";
    return;
end
mode = lower(string(cfg.aperiodicMode));
if mode == "fixed"
    params = struct('offset', coefficients(1), 'exponent', -coefficients(2), ...
        'knee', NaN, 'mode', "fixed");
    modelLog = evaluate_aperiodic(freq, params, cfg);
    ok = all(isfinite(modelLog)); warningText = "";
    if ~ok, warningText = "Fixed aperiodic model is non-finite."; end
    return;
end

% Knee is estimated in log10(knee) coordinates to guarantee a positive knee
% while allowing the fit to use only base MATLAB (fminsearch).
initialExponent = max(0.05, min(8, -coefficients(2)));
initialKnee = max((median(freq(keep)) / 2) .^ initialExponent, 1e-8);
initialOffset = median(logPower(keep) + log10(initialKnee + freq(keep) .^ initialExponent));
start = [initialOffset, initialExponent, log10(initialKnee)];
objective = @(p) knee_objective(p, freq(keep), logPower(keep));
options = optimset('Display', 'off', 'MaxIter', 2000, 'MaxFunEvals', 8000, ...
    'TolX', 1e-7, 'TolFun', 1e-9);
warningText = "";
try
    [fitParameters, ~, exitFlag] = fminsearch(objective, start, options);
catch exception
    fitParameters = [NaN NaN NaN]; exitFlag = -1;
    warningText = "Knee optimizer error: " + string(exception.message);
end
if exitFlag <= 0 || any(~isfinite(fitParameters)) || fitParameters(2) <= 0
    params = struct('offset', NaN, 'exponent', NaN, 'knee', NaN, 'mode', "knee");
    modelLog = NaN(size(logPower)); ok = false;
    if strlength(warningText) == 0, warningText = "Knee optimizer did not converge."; end
    return;
end
params = struct('offset', fitParameters(1), 'exponent', fitParameters(2), ...
    'knee', 10 .^ fitParameters(3), 'mode', "knee");
modelLog = evaluate_aperiodic(freq, params, cfg);
ok = all(isfinite(modelLog));
if ~ok, warningText = "Knee aperiodic model is non-finite."; end
end

function value = knee_objective(parameters, freq, logPower)
if numel(parameters) ~= 3 || any(~isfinite(parameters)) || parameters(2) <= 0 || ...
        parameters(2) > 12 || parameters(3) < -12 || parameters(3) > 12
    value = 1e12; return;
end
model = parameters(1) - log10(10 .^ parameters(3) + freq .^ parameters(2));
residual = logPower - model;
value = mean(residual .^ 2);
if ~isfinite(value), value = 1e12; end
end

function modelLog = evaluate_aperiodic(freq, params, cfg)
if lower(string(cfg.aperiodicMode)) == "knee"
    modelLog = params.offset - log10(max(params.knee, realmin) + max(freq, eps) .^ params.exponent);
else
    modelLog = params.offset - params.exponent * log10(max(freq, eps));
end
end

function value = ternary_text(condition, first, second)
if condition, value = first; else, value = second; end
end

function [coefficients, keep] = robust_background(logFrequency, logPower, threshold)
keep = true(size(logPower));
coefficients = [0; 0];
for iteration = 1:4
    coefficients = [ones(nnz(keep), 1), logFrequency(keep)] \ logPower(keep);
    residual = logPower - [ones(numel(logFrequency), 1), logFrequency] * coefficients;
    scale = robust_scale(residual);
    if ~(isfinite(scale) && scale > 0), break; end
    candidate = residual <= threshold * scale;
    if nnz(candidate) < 3 || isequal(candidate, keep), break; end
    keep = candidate;
end
end

function indices = find_candidates(freq, residual, threshold, minDistance)
candidate = false(size(residual));
if numel(residual) >= 3
    candidate(2:end-1) = residual(2:end-1) >= residual(1:end-2) & ...
        residual(2:end-1) >= residual(3:end) & residual(2:end-1) >= threshold;
end
raw = find(candidate);
[~, order] = sort(residual(raw), 'descend');
indices = zeros(0, 1);
for index = order(:)'
    if isempty(indices) || all(abs(freq(raw(index)) - freq(indices)) >= minDistance)
        indices(end + 1, 1) = raw(index); %#ok<AGROW>
    end
end
end

function peak = fit_gaussian(freq, residual, index, widthLimits, frequencyResolution)
peak = struct('amplitudeLog10', 0, 'centerFrequencyHz', freq(index), ...
    'sigmaHz', widthLimits(1)/2, 'bandwidthHz', widthLimits(1));
range = abs(freq - freq(index)) <= widthLimits(2);
frequencies = freq(range);
values = residual(range);
if numel(frequencies) < 3, return; end
centerGrid = freq(index) + (-1:1) * max(frequencyResolution, (freq(2)-freq(1)));
centerGrid = centerGrid(centerGrid >= frequencies(1) & centerGrid <= frequencies(end));
sigmaGrid = linspace(widthLimits(1)/2, widthLimits(2)/2, 20);
bestError = Inf;
for center = centerGrid
    for sigma = sigmaGrid
        basis = exp(-0.5 * ((frequencies - center) / sigma).^2);
        amplitude = max(0, basis \ values);
        errorValue = sum((values - amplitude*basis).^2);
        if errorValue < bestError
            bestError = errorValue;
            peak.amplitudeLog10 = amplitude;
            peak.centerFrequencyHz = center;
            peak.sigmaHz = sigma;
            peak.bandwidthHz = 2*sigma;
        end
    end
end
end

function result = empty_result()
result = struct('freq', [], 'inputPower', [], 'logPower', [], ...
    'fittingPower', [], 'lineNoise', struct('enabled', false), 'interpolationApplied', false, ...
    'aperiodicParams', struct('offset', NaN, 'exponent', NaN, 'knee', NaN, 'mode', "fixed"), ...
    'aperiodicFit', [], 'periodicFit', [], 'fullModelFit', [], ...
    'flattenedSpectrum', [], 'peakParams', empty_peaks(), ...
    'gaussianParams', empty_gaussians(), 'rSquared', NaN, 'fitError', NaN, ...
    'nPeaks', 0, 'frequencyResolution', NaN, 'fitRange', [NaN NaN], ...
    'settings', struct(), 'fitStatus', "not_fitted", 'warnings', strings(0, 1));
end

function peaks = empty_peaks()
peaks = struct('CF', {}, 'PW', {}, 'BW', {}, 'peakBand', {}, ...
    'centerFrequencyHz', {}, 'powerLog10', {}, 'bandwidthHz', {});
end

function peaks = empty_gaussians()
peaks = struct('amplitudeLog10', {}, 'centerFrequencyHz', {}, 'sigmaHz', {}, 'bandwidthHz', {});
end

function name = classify_band(frequency)
if frequency >= 1 && frequency < 4, name = "delta";
elseif frequency < 8, name = "theta";
elseif frequency < 13, name = "alpha";
elseif frequency < 30, name = "beta";
elseif frequency < 55, name = "low-gamma";
elseif frequency <= 100, name = "high-gamma";
else, name = "out-of-default-bands"; end
end

function value = get_field(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = defaultValue; end
end

function cfg = strip_runtime_fields(cfg)
fields = intersect(fieldnames(cfg), {'progressCallback', 'cancellationCheck'});
if ~isempty(fields), cfg = rmfield(cfg, fields); end
end

function value = robust_scale(values)
values = values(isfinite(values));
if isempty(values), value = 0; return; end
value = 1.4826 * median(abs(values - median(values)));
if ~(isfinite(value) && value > 0), value = std(values, 0); end
if ~isfinite(value), value = 0; end
end

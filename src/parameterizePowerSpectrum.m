function modelResult = parameterizePowerSpectrum(freq, power, fooofCfg)
%PARAMETERIZEPOWERSPECTRUM Fit fixed/no-knee aperiodic and Gaussian peaks.
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
if lower(string(fooofCfg.aperiodicMode)) ~= "fixed"
    error('LFP:UnsupportedAperiodicMode', 'Native parameterization currently supports only a fixed/no-knee mode.');
end
if numel(fooofCfg.frequencyRange) ~= 2 || fooofCfg.frequencyRange(2) <= fooofCfg.frequencyRange(1)
    error('LFP:InvalidFitRange', 'fooofCfg.frequencyRange must be increasing.');
end
if isvector(power), power = power(:); end
if size(power, 1) ~= numel(freq)
    error('LFP:InvalidSpectrum', 'POWER rows must match FREQ.');
end
if any(~isfinite(freq)) || any(diff(freq) <= 0) || any(freq < 0)
    error('LFP:InvalidSpectrum', 'FREQ must be finite, nonnegative and strictly increasing.');
end

% Keep the supplied PSD untouched.  The line-noise interpolation is applied
% only to a fitting copy, matching fooof.utils.interpolate_spectrum semantics.
fitPower = power;
lineNoise = struct('enabled', false, 'interpolatedMask', false(numel(freq), 1), ...
    'rangesHz', zeros(0, 2), 'method', "not applied");
if get_field(fooofCfg, 'interpolateLineNoise', true)
    fittingSpectrum = lfp_interpolate_line_noise(struct( ...
        'frequencyHz', freq, 'psd', power), ...
        LineFrequencyHz=get_field(fooofCfg, 'lineFrequencyHz', 40), ...
        InterpolationHalfWidthHz=get_field(fooofCfg, 'lineInterpolationHalfWidthHz', 2), ...
        BufferSamples=get_field(fooofCfg, 'lineInterpolationBufferSamples', 3), ...
        IncludeHarmonics=get_field(fooofCfg, 'lineIncludeHarmonics', true));
    fitPower = fittingSpectrum.psdForFitting;
    lineNoise = fittingSpectrum.lineNoise;
    lineNoise.enabled = true;
end
frequencyResolution = median(diff(freq));
fitRange = [max(fooofCfg.frequencyRange(1), min(freq(freq > 0))), ...
    min(fooofCfg.frequencyRange(2), freq(end))];
if fitRange(2) <= fitRange(1)
    error('LFP:InvalidFitRange', 'fooofCfg.frequencyRange does not overlap FREQ.');
end

nChannels = size(power, 2);
modelResult = repmat(empty_result(), 1, nChannels);
for channel = 1:nChannels
    modelResult(channel) = fit_channel(freq, power(:, channel), fitPower(:, channel), ...
        fooofCfg, fitRange, frequencyResolution, lineNoise);
end
end

function result = fit_channel(freq, inputPower, fittingPower, cfg, fitRange, frequencyResolution, lineNoise)
result = empty_result();
result.freq = freq;
result.inputPower = inputPower;
result.fittingPower = fittingPower;
result.lineNoise = lineNoise;
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
[initialCoefficients, initialKeep] = robust_background(logFrequency, logPower, cfg.peakThreshold);
initialAperiodicLog = initialCoefficients(1) + initialCoefficients(2) * log10(max(freq, eps));
flattenedInitial = logPower - ([ones(nnz(valid), 1), logFrequency] * initialCoefficients);
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
finalCoefficients = [ones(nnz(initialKeep), 1), logFrequency(initialKeep)] \ finalLogPower(initialKeep);
if any(~isfinite(finalCoefficients))
    finalCoefficients = initialCoefficients;
    result.warnings(end + 1) = "Final aperiodic refit was ill-conditioned; initial fit retained.";
end
offset = finalCoefficients(1);
exponent = -finalCoefficients(2);
aperiodicLog = offset - exponent * log10(max(freq, eps));
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
result.aperiodicParams = struct('offset', offset, 'exponent', exponent, 'mode', "fixed");
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
    'fittingPower', [], 'lineNoise', struct('enabled', false), ...
    'aperiodicParams', struct('offset', NaN, 'exponent', NaN, 'mode', "fixed"), ...
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

function value = robust_scale(values)
values = values(isfinite(values));
if isempty(values), value = 0; return; end
value = 1.4826 * median(abs(values - median(values)));
if ~(isfinite(value) && value > 0), value = std(values, 0); end
if ~isfinite(value), value = 0; end
end

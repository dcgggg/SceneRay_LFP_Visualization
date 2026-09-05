function data = lfp_fit_spectral_parameters(data, options)
%LFP_FIT_SPECTRAL_PARAMETERS Fit fixed aperiodic and periodic spectra.
%   DATA = LFP_FIT_SPECTRAL_PARAMETERS(DATA) fits
%   log10(P)=offset-exponent*log10(f) to DATA.spectrum.psdForFitting (or
%   DATA.spectrum.psd when no interpolation has been requested). Positive
%   residual groups are reported as periodic peaks. Original PSD values,
%   fitting PSD values, and all fit diagnostics are retained separately.

arguments
    data (1,1) struct
    options.FitRangeHz (1,2) double {mustBeFinite, mustBeNonnegative} = [3 150]
    options.RobustIterations (1,1) double {mustBeInteger, mustBeNonnegative} = 3
    options.PeakThresholdStd (1,1) double {mustBeFinite, mustBeNonnegative} = 2.5
    options.MinPeakProminenceLog10 (1,1) double {mustBeFinite, mustBeNonnegative} = 0.10
    options.MinPeakDistanceHz (1,1) double {mustBeFinite, mustBeNonnegative} = 2
    options.MaxPeaks (1,1) double {mustBeInteger, mustBePositive} = 100
end

if options.FitRangeHz(2) <= options.FitRangeHz(1)
    error('LFP:InvalidFitRange', 'FitRangeHz must be increasing.');
end
if ~isfield(data, 'spectrum') || ~isfield(data.spectrum, 'frequencyHz') || ...
        ~isfield(data.spectrum, 'psd')
    error('LFP:InvalidSpectrum', 'Run lfp_compute_psd before spectral parameterization.');
end

spectrum = data.spectrum;
frequencyHz = double(spectrum.frequencyHz(:));
originalPsd = double(spectrum.psd);
if isfield(spectrum, 'psdForFitting')
    fittingPsd = double(spectrum.psdForFitting);
else
    fittingPsd = originalPsd;
end
if ~isequal(size(originalPsd), size(fittingPsd)) || size(originalPsd, 1) ~= numel(frequencyHz)
    error('LFP:InvalidSpectrum', 'PSD arrays must have matching frequency dimensions.');
end
fitRange = [max(options.FitRangeHz(1), min(frequencyHz(frequencyHz > 0))), ...
    min(options.FitRangeHz(2), frequencyHz(end))];
if fitRange(2) <= fitRange(1)
    error('LFP:InvalidFitRange', 'Fit range does not overlap the spectrum.');
end

nChannels = size(originalPsd, 2);
channelResults = repmat(empty_channel_result(), 1, nChannels);
aperiodicPsd = NaN(size(fittingPsd));
periodicResidualLog10 = NaN(size(fittingPsd));
periodicPowerAboveAperiodic = NaN(size(fittingPsd));
for channelIndex = 1:nChannels
    positive = frequencyHz > 0 & frequencyHz >= fitRange(1) & frequencyHz <= fitRange(2);
    valid = positive & isfinite(fittingPsd(:, channelIndex)) & fittingPsd(:, channelIndex) > 0;
    if nnz(valid) < 3
        channelResults(channelIndex).status = "insufficient_data";
        continue;
    end
    logFrequency = log10(frequencyHz(valid));
    logPower = log10(fittingPsd(valid, channelIndex));
    keep = true(size(logPower));
    coefficients = [NaN; NaN];
    for iteration = 1:max(1, options.RobustIterations)
        coefficients = [ones(nnz(keep), 1), logFrequency(keep)] \ logPower(keep);
        residual = logPower - [ones(numel(logFrequency), 1), logFrequency] * coefficients;
        robustSigma = 1.4826 * median(abs(residual - median(residual)));
        if ~(isfinite(robustSigma) && robustSigma > 0)
            robustSigma = std(residual, 0);
        end
        if ~(isfinite(robustSigma) && robustSigma > 0)
            break;
        end
        candidateKeep = residual <= options.PeakThresholdStd * robustSigma;
        if nnz(candidateKeep) < 3 || isequal(candidateKeep, keep)
            break;
        end
        keep = candidateKeep;
    end
    offset = coefficients(1);
    exponent = -coefficients(2);
    modelLog = offset - exponent * log10(max(frequencyHz, eps));
    modelPsd = 10 .^ modelLog;
    residualAll = log10(max(fittingPsd(:, channelIndex), realmin)) - modelLog;
    residualFit = residualAll(valid);
    r2 = 1 - sum((logPower - ([ones(numel(logFrequency), 1), logFrequency] * coefficients)).^2) / ...
        max(sum((logPower - mean(logPower)).^2), eps);
    rmse = sqrt(mean(residualFit .^ 2));
    peakThreshold = max(options.MinPeakProminenceLog10, options.PeakThresholdStd * robust_std(residualFit));
    peaks = find_peaks_base(frequencyHz, residualAll, positive & isfinite(residualAll), ...
        peakThreshold, options.MinPeakDistanceHz, options.MaxPeaks);

    aperiodicPsd(:, channelIndex) = modelPsd;
    periodicResidualLog10(:, channelIndex) = residualAll;
    periodicPowerAboveAperiodic(:, channelIndex) = max(fittingPsd(:, channelIndex) - modelPsd, 0);
    channelResults(channelIndex) = struct( ...
        'status', "ok", 'offset', offset, 'exponent', exponent, ...
        'r2', r2, 'rmseLog10', rmse, 'fitRangeHz', fitRange, ...
        'fitPointCount', nnz(valid), 'aperiodicPsd', modelPsd, ...
        'periodicResidualLog10', residualAll, ...
        'periodicPowerAboveAperiodic', periodicPowerAboveAperiodic(:, channelIndex), ...
        'peaks', peaks);
end

parameters = struct();
parameters.mode = "fixed";
parameters.frequencyHz = frequencyHz;
parameters.originalPsd = originalPsd;
parameters.fittingPsd = fittingPsd;
parameters.aperiodicPsd = aperiodicPsd;
parameters.periodicResidualLog10 = periodicResidualLog10;
parameters.periodicPowerAboveAperiodic = periodicPowerAboveAperiodic;
parameters.channels = channelResults;
parameters.fitRangeHz = fitRange;
parameters.settings = struct('robustIterations', options.RobustIterations, ...
    'peakThresholdStd', options.PeakThresholdStd, ...
    'minPeakProminenceLog10', options.MinPeakProminenceLog10, ...
    'minPeakDistanceHz', options.MinPeakDistanceHz, ...
    'maxPeaks', options.MaxPeaks);
data.spectralParameters = parameters;
entry = struct('operation', "fixed_spectral_parameterization", ...
    'parameters', parameters.settings, ...
    'notes', "Aperiodic offset/exponent and periodic residuals kept separate; fitting PSD may be line-noise interpolated.");
data.processingHistory(end + 1) = entry;
end

function result = empty_channel_result()
result = struct('status', "not_fitted", 'offset', NaN, 'exponent', NaN, ...
    'r2', NaN, 'rmseLog10', NaN, 'fitRangeHz', [NaN NaN], 'fitPointCount', 0, ...
    'aperiodicPsd', [], 'periodicResidualLog10', [], ...
    'periodicPowerAboveAperiodic', [], 'peaks', empty_peaks());
end

function peaks = empty_peaks()
peaks = struct('centerFrequencyHz', {}, 'powerLog10', {}, 'bandwidthHz', {}, 'leftFrequencyHz', {}, 'rightFrequencyHz', {});
end

function peaks = find_peaks_base(frequencyHz, residual, valid, threshold, minDistance, maxPeaks)
candidate = valid;
candidate(1) = false;
candidate(end) = false;
candidate(2:end-1) = candidate(2:end-1) & residual(2:end-1) >= residual(1:end-2) & ...
    residual(2:end-1) >= residual(3:end) & residual(2:end-1) >= threshold;
indices = find(candidate);
if isempty(indices)
    peaks = empty_peaks();
    return;
end
[~, order] = sort(residual(indices), 'descend');
selected = zeros(0, 1);
for orderIndex = 1:numel(order)
    index = indices(order(orderIndex));
    if isempty(selected) || all(abs(frequencyHz(index) - frequencyHz(selected)) >= minDistance)
        selected(end + 1, 1) = index; %#ok<AGROW>
    end
    if numel(selected) >= maxPeaks
        break;
    end
end
selected = sort(selected);
peaks = repmat(struct('centerFrequencyHz', NaN, 'powerLog10', NaN, ...
    'bandwidthHz', NaN, 'leftFrequencyHz', NaN, 'rightFrequencyHz', NaN), numel(selected), 1);
for peakIndex = 1:numel(selected)
    index = selected(peakIndex);
    halfHeight = max(threshold, residual(index) / 2);
    left = index;
    while left > 1 && valid(left - 1) && residual(left - 1) >= halfHeight
        left = left - 1;
    end
    right = index;
    while right < numel(residual) && valid(right + 1) && residual(right + 1) >= halfHeight
        right = right + 1;
    end
    peaks(peakIndex).centerFrequencyHz = frequencyHz(index);
    peaks(peakIndex).powerLog10 = residual(index);
    peaks(peakIndex).leftFrequencyHz = frequencyHz(left);
    peaks(peakIndex).rightFrequencyHz = frequencyHz(right);
    peaks(peakIndex).bandwidthHz = frequencyHz(right) - frequencyHz(left);
end
end

function value = robust_std(values)
values = values(isfinite(values));
if isempty(values)
    value = 0;
else
    value = 1.4826 * median(abs(values - median(values)));
    if ~(isfinite(value) && value > 0)
        value = std(values, 0);
    end
    if ~isfinite(value), value = 0; end
end
end

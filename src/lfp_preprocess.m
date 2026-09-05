function data = lfp_preprocess(data, options)
%LFP_PREPROCESS Mark movement-like artifacts without destroying raw data.
%   DATA = LFP_PREPROCESS(DATA) detects robust amplitude, derivative/step,
%   and rail/saturation artifacts independently for each channel. The raw
%   DATA.signal array is never modified. A cleaned copy is returned in
%   DATA.preprocessedSignal only when ReplaceArtifacts=true.
%
%   Detection is intentionally independent of line-frequency filtering:
%   40-Hz harmonics are retained for later spectral interpolation before
%   aperiodic/periodic fitting.

arguments
    data (1,1) struct
    options.AmplitudeZ (1,1) double {mustBeFinite, mustBeNonnegative} = 8
    options.DerivativeZ (1,1) double {mustBeFinite, mustBeNonnegative} = 8
    options.SaturationAbsoluteThresholdUV (1,1) double {mustBeFinite, mustBeNonnegative} = 5000
    options.SaturationRunLength (1,1) double {mustBeInteger, mustBePositive} = 5
    options.IntervalPaddingSeconds (1,1) double {mustBeFinite, mustBeNonnegative} = 0.010
    options.ReplaceArtifacts (1,1) logical = false
end

validate_data(data);
signal = double(data.signal);
[nSamples, nChannels] = size(signal);
fs = double(data.fs);
mask = false(nSamples, nChannels);
reasonMasks = struct('amplitude', false(nSamples, nChannels), ...
    'derivative', false(nSamples, nChannels), ...
    'saturation', false(nSamples, nChannels));

for channelIndex = 1:nChannels
    x = signal(:, channelIndex);
    finiteValues = x(isfinite(x));
    if isempty(finiteValues)
        continue;
    end
    center = median(finiteValues);
    robustSigma = 1.4826 * median(abs(finiteValues - center));
    if ~(isfinite(robustSigma) && robustSigma > 0)
        robustSigma = std(finiteValues, 0);
    end
    if isfinite(robustSigma) && robustSigma > 0 && options.AmplitudeZ > 0
        reasonMasks.amplitude(:, channelIndex) = abs(x - center) > options.AmplitudeZ * robustSigma;
    end

    dx = [0; diff(x)];
    finiteDerivative = dx(isfinite(dx));
    derivativeCenter = median(finiteDerivative);
    derivativeSigma = 1.4826 * median(abs(finiteDerivative - derivativeCenter));
    if ~(isfinite(derivativeSigma) && derivativeSigma > 0)
        derivativeSigma = std(finiteDerivative, 0);
    end
    if isfinite(derivativeSigma) && derivativeSigma > 0 && options.DerivativeZ > 0
        reasonMasks.derivative(:, channelIndex) = ...
            abs(dx - derivativeCenter) > options.DerivativeZ * derivativeSigma;
    end

    reasonMasks.saturation(:, channelIndex) = detect_saturation_runs( ...
        x, options.SaturationAbsoluteThresholdUV, options.SaturationRunLength);
end

paddingSamples = round(options.IntervalPaddingSeconds * fs);
if paddingSamples > 0
    mask = expand_mask(mask | reasonMasks.amplitude | reasonMasks.derivative | reasonMasks.saturation, paddingSamples);
else
    mask = reasonMasks.amplitude | reasonMasks.derivative | reasonMasks.saturation;
end

data.artifacts.channelMask = mask;
data.artifacts.reasonMasks = reasonMasks;
data.artifacts.intervals_s = mask_to_intervals(mask, fs);
data.artifacts.channelIntervals_s = channel_masks_to_intervals(mask, fs);
data.artifacts.labels = interval_labels(mask, reasonMasks, fs);
data.artifacts.method = "robust_amplitude_derivative_saturation";
data.artifacts.parameters = struct( ...
    'amplitudeZ', options.AmplitudeZ, ...
    'derivativeZ', options.DerivativeZ, ...
    'saturationAbsoluteThresholdUV', options.SaturationAbsoluteThresholdUV, ...
    'saturationRunLength', options.SaturationRunLength, ...
    'intervalPaddingSeconds', options.IntervalPaddingSeconds, ...
    'paddingSamples', paddingSamples);

data.preprocessedSignal = signal;
if options.ReplaceArtifacts
    cleaned = signal;
    cleaned(mask) = NaN;
    data.preprocessedSignal = cleaned;
end

entry = struct('operation', "artifact_detection", ...
    'parameters', data.artifacts.parameters, ...
    'notes', "Raw signal retained; artifacts marked in data.artifacts.channelMask.");
data.processingHistory(end + 1) = entry;
end

function validate_data(data)
required = ["signal", "fs"];
for index = 1:numel(required)
    if ~isfield(data, required(index))
        error('LFP:InvalidData', 'DATA.%s is required.', required(index));
    end
end
if ~isnumeric(data.signal) || ndims(data.signal) ~= 2 || isempty(data.signal)
    error('LFP:InvalidData', 'DATA.signal must be a non-empty samples-by-channels matrix.');
end
if ~isscalar(data.fs) || ~isfinite(data.fs) || data.fs <= 0
    error('LFP:InvalidData', 'DATA.fs must be a positive finite scalar.');
end
if ~isfield(data, 'artifacts') || ~isstruct(data.artifacts)
    data.artifacts = struct(); %#ok<NASGU>
end
if ~isfield(data, 'processingHistory') || ~isstruct(data.processingHistory)
    error('LFP:InvalidData', 'DATA.processingHistory must be a struct array.');
end
end

function mask = detect_saturation_runs(x, threshold, runLength)
candidate = isfinite(x) & abs(x) >= threshold;
mask = false(size(x));
startIndex = find(diff([false; candidate; false]) == 1);
endIndex = find(diff([false; candidate; false]) == -1) - 1;
for index = 1:numel(startIndex)
    segment = x(startIndex(index):endIndex(index));
    if numel(segment) >= runLength && all(segment == segment(1))
        mask(startIndex(index):endIndex(index)) = true;
    end
end
end

function expanded = expand_mask(mask, paddingSamples)
expanded = mask;
for channelIndex = 1:size(mask, 2)
    indices = find(mask(:, channelIndex));
    for index = 1:numel(indices)
        left = max(1, indices(index) - paddingSamples);
        right = min(size(mask, 1), indices(index) + paddingSamples);
        expanded(left:right, channelIndex) = true;
    end
end
end

function intervals = mask_to_intervals(mask, fs)
unionMask = any(mask, 2);
intervals = logical_to_intervals(unionMask, fs);
end

function intervals = channel_masks_to_intervals(mask, fs)
intervals = cell(1, size(mask, 2));
for channelIndex = 1:size(mask, 2)
    intervals{channelIndex} = logical_to_intervals(mask(:, channelIndex), fs);
end
end

function intervals = logical_to_intervals(logicalMask, fs)
startIndex = find(diff([false; logicalMask; false]) == 1);
endIndex = find(diff([false; logicalMask; false]) == -1) - 1;
intervals = [(startIndex - 1) ./ fs, endIndex ./ fs];
end

function labels = interval_labels(mask, reasons, fs)
unionMask = any(mask, 2);
startIndex = find(diff([false; unionMask; false]) == 1);
endIndex = find(diff([false; unionMask; false]) == -1) - 1;
labels = strings(numel(startIndex), 1);
for intervalIndex = 1:numel(startIndex)
    range = startIndex(intervalIndex):endIndex(intervalIndex);
    names = strings(0, 1);
    if any(reasons.amplitude(range, :), 'all'), names(end + 1) = "amplitude"; end %#ok<AGROW>
    if any(reasons.derivative(range, :), 'all'), names(end + 1) = "derivative"; end %#ok<AGROW>
    if any(reasons.saturation(range, :), 'all'), names(end + 1) = "saturation"; end %#ok<AGROW>
    labels(intervalIndex) = strjoin(names, "+");
end
end

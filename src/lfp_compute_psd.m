function data = lfp_compute_psd(data, options)
%LFP_COMPUTE_PSD Compute a one-sided Welch PSD using base MATLAB operations.
%   DATA = LFP_COMPUTE_PSD(DATA) stores a spectrum in DATA.spectrum. The
%   input signal is not filtered and line-frequency peaks are retained.
%   Windows with too many artifact or non-finite samples are excluded.

arguments
    data (1,1) struct
    options.WindowSeconds (1,1) double {mustBeFinite, mustBePositive} = 4
    options.OverlapFraction (1,1) double {mustBeFinite, mustBeGreaterThanOrEqual(options.OverlapFraction, 0), mustBeLessThan(options.OverlapFraction, 1)} = 0.5
    options.Nfft (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.MaxArtifactFraction (1,1) double {mustBeFinite, mustBeGreaterThanOrEqual(options.MaxArtifactFraction, 0), mustBeLessThanOrEqual(options.MaxArtifactFraction, 1)} = 0
    options.DetrendConstant (1,1) logical = true
    options.ExcludeArtifacts (1,1) logical = true
    options.AggregationMethod (1,1) string {mustBeMember(options.AggregationMethod, ["mean" "median"])} = "mean"
    options.Taper (1,1) string {mustBeMember(options.Taper, "hann")} = "hann"
    options.FrequencyRangeHz (1,2) double {mustBeNonnegative} = [1 40]
end

validate_data(data);
signal = double(data.signal);
[nSamples, nChannels] = size(signal);
fs = double(data.fs);
windowSamples = max(1, round(options.WindowSeconds * fs));
windowSamples = min(windowSamples, nSamples);
stepSamples = max(1, round(windowSamples * (1 - options.OverlapFraction)));
if options.Nfft == 0
    nfft = 2 ^ nextpow2(windowSamples);
else
    nfft = max(windowSamples, options.Nfft);
end
if options.FrequencyRangeHz(2) <= options.FrequencyRangeHz(1)
    error('LFP:InvalidFrequencyRange', 'FrequencyRangeHz must be increasing.');
end
window = hann_vector(windowSamples);
normalization = fs * sum(window .^ 2);
fullFrequencyHz = (0:floor(nfft / 2))' * fs / nfft;
frequencyMask = fullFrequencyHz >= options.FrequencyRangeHz(1) & ...
    fullFrequencyHz <= min(options.FrequencyRangeHz(2), fs/2);
frequencyHz = fullFrequencyHz(frequencyMask);
psd = NaN(numel(frequencyHz), nChannels);
acceptedWindows = cell(1, nChannels);
windowStarts = 1:stepSamples:max(1, nSamples - windowSamples + 1);
if windowStarts(end) + windowSamples - 1 < nSamples
    windowStarts(end + 1) = nSamples - windowSamples + 1;
end
windowPsd = NaN(numel(frequencyHz), numel(windowStarts), nChannels);
filledSampleCount = zeros(1, nChannels);

artifactMask = false(nSamples, nChannels);
if isfield(data, 'artifacts') && isfield(data.artifacts, 'channelMask')
    candidateMask = data.artifacts.channelMask;
    if isequal(size(candidateMask), size(signal))
        artifactMask = logical(candidateMask);
    end
end

for channelIndex = 1:nChannels
    accumulated = zeros(numel(frequencyHz), 1);
    accepted = false(numel(windowStarts), 1);
    count = 0;
    for windowIndex = 1:numel(windowStarts)
        first = windowStarts(windowIndex);
        last = first + windowSamples - 1;
        segment = signal(first:last, channelIndex);
        invalid = ~isfinite(segment) | artifactMask(first:last, channelIndex);
        if options.ExcludeArtifacts && any(invalid)
            continue;
        end
        if mean(invalid) > options.MaxArtifactFraction
            continue;
        end
        filledSampleCount(channelIndex) = filledSampleCount(channelIndex) + nnz(invalid);
        segment(invalid) = NaN;
        if any(isnan(segment))
            segment = fill_linear(segment);
        end
        if options.DetrendConstant
            segment = segment - mean(segment);
        end
        transformed = fft(segment .* window, nfft);
        power = abs(transformed(1:floor(nfft / 2) + 1)) .^ 2 / normalization;
        if rem(nfft, 2) == 0
            power(2:end-1) = 2 * power(2:end-1);
        else
            power(2:end) = 2 * power(2:end);
        end
        power = power(frequencyMask);
        windowPsd(:, windowIndex, channelIndex) = power;
        accumulated = accumulated + power;
        count = count + 1;
        accepted(windowIndex) = true;
    end
    if count > 0
        if options.AggregationMethod == "median"
            psd(:, channelIndex) = median(windowPsd(:, accepted, channelIndex), 2, 'omitnan');
        else
            psd(:, channelIndex) = accumulated / count;
        end
    end
    acceptedWindows{channelIndex} = windowStarts(accepted(:))';
end

spectrum = struct();
spectrum.frequencyHz = frequencyHz;
spectrum.psd = psd;
spectrum.psdUnits = string(data.units) + "^2/Hz";
spectrum.method = "Welch (manual base MATLAB)";
spectrum.windowSeconds = windowSamples / fs;
spectrum.overlapFraction = options.OverlapFraction;
spectrum.nfft = nfft;
spectrum.windowCount = cellfun(@numel, acceptedWindows);
spectrum.acceptedWindowStarts = acceptedWindows;
spectrum.allWindowStarts = windowStarts(:);
spectrum.windowPsd = windowPsd;
spectrum.validWindowCountPerFrequency = sum(isfinite(windowPsd), 2);
spectrum.frequencyResolutionHz = fs / nfft;
spectrum.excludedWindowCount = numel(windowStarts) - spectrum.windowCount;
spectrum.filledSampleCount = filledSampleCount;
spectrum.includesLineNoise = true;
spectrum.parameters = struct('windowSeconds', options.WindowSeconds, ...
    'windowSamples', windowSamples, 'overlapFraction', options.OverlapFraction, ...
    'nfft', nfft, 'maxArtifactFraction', options.MaxArtifactFraction, ...
    'detrendConstant', options.DetrendConstant, 'excludeArtifacts', options.ExcludeArtifacts, ...
    'aggregationMethod', options.AggregationMethod, 'taper', options.Taper, ...
    'frequencyRangeHz', options.FrequencyRangeHz);
data.spectrum = spectrum;
entry = struct('operation', "psd", 'parameters', spectrum.parameters, ...
    'notes', "Manual Welch PSD from raw signal; artifact-heavy windows excluded; 40-Hz harmonics retained.");
data.processingHistory(end + 1) = entry;
end

function validate_data(data)
if ~isfield(data, 'signal') || ~isfield(data, 'fs') || ~isfield(data, 'units')
    error('LFP:InvalidData', 'DATA.signal, DATA.fs, and DATA.units are required.');
end
if ~isnumeric(data.signal) || ndims(data.signal) ~= 2 || isempty(data.signal)
    error('LFP:InvalidData', 'DATA.signal must be a non-empty samples-by-channels matrix.');
end
if ~isscalar(data.fs) || ~isfinite(data.fs) || data.fs <= 0
    error('LFP:InvalidData', 'DATA.fs must be a positive finite scalar.');
end
if ~isfield(data, 'processingHistory') || ~isstruct(data.processingHistory)
    error('LFP:InvalidData', 'DATA.processingHistory must be a struct array.');
end
end

function values = hann_vector(n)
if n == 1
    values = 1;
else
    index = (0:n-1)';
    values = 0.5 - 0.5 * cos(2*pi*index/(n-1));
end
end

function values = fill_linear(values)
finite = isfinite(values);
if ~any(finite)
    values(:) = 0;
elseif nnz(finite) == 1
    values(~finite) = values(find(finite, 1));
else
    index = (1:numel(values))';
    values(~finite) = interp1(index(finite), values(finite), index(~finite), 'linear', 'extrap');
end
end

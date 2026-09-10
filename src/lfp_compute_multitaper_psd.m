function data = lfp_compute_multitaper_psd(data, options)
%LFP_COMPUTE_MULTITAPER_PSD Artifact-aware DPSS multitaper PSD.
%   Each continuous valid window is tapered with K DPSS sequences, the
%   one-sided linear PSDs are averaged with equal weights, then windows are
%   aggregated using the requested mean or median.  No Welch fallback is
%   performed when DPSS generation fails.

arguments
    data (1,1) struct
    options.WindowSeconds (1,1) double {mustBeFinite, mustBePositive} = 4
    options.OverlapFraction (1,1) double {mustBeFinite, mustBeGreaterThanOrEqual(options.OverlapFraction, 0), mustBeLessThan(options.OverlapFraction, 1)} = 0.5
    options.Nfft (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.MaxArtifactFraction (1,1) double {mustBeFinite, mustBeGreaterThanOrEqual(options.MaxArtifactFraction, 0), mustBeLessThanOrEqual(options.MaxArtifactFraction, 1)} = 0
    options.ExcludeArtifacts (1,1) logical = true
    options.AggregationMethod (1,1) string {mustBeMember(options.AggregationMethod, ["mean" "median"])} = "mean"
    options.DetrendMode (1,1) string {mustBeMember(options.DetrendMode, ["none" "constant" "linear"])} = "constant"
    options.TimeBandwidthProduct (1,1) double {mustBeFinite, mustBeGreaterThan(options.TimeBandwidthProduct, 0.5)} = 3.5
    options.TaperCount (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.TaperWeighting (1,1) string {mustBeMember(options.TaperWeighting, "equal")} = "equal"
    options.FrequencyRangeHz (1,2) double {mustBeNonnegative} = [1 40]
end

validate_data(data);
signal = double(data.signal);
[nSamples, nChannels] = size(signal);
fs = double(data.fs);
windowSamples = min(max(2, round(options.WindowSeconds * fs)), nSamples);
if options.FrequencyRangeHz(2) <= options.FrequencyRangeHz(1)
    error('LFP:InvalidFrequencyRange', 'FrequencyRangeHz must be increasing.');
end
if options.Nfft == 0, nfft = 2 ^ nextpow2(windowSamples); else, nfft = max(windowSamples, options.Nfft); end
nw = options.TimeBandwidthProduct;
if options.TaperCount == 0, taperCount = max(1, floor(2 * nw) - 1); else, taperCount = options.TaperCount; end
[tapers, eigenvalues] = lfp_dpss(windowSamples, nw, taperCount);
fullFrequencyHz = (0:floor(nfft / 2))' * fs / nfft;
frequencyMask = fullFrequencyHz >= options.FrequencyRangeHz(1) & ...
    fullFrequencyHz <= min(options.FrequencyRangeHz(2), fs / 2);
frequencyHz = fullFrequencyHz(frequencyMask);
windowStarts = make_window_starts(nSamples, windowSamples, options.OverlapFraction);
windowPsd = NaN(numel(frequencyHz), numel(windowStarts), nChannels);
acceptedWindows = cell(1, nChannels);
filledSampleCount = zeros(1, nChannels);
if isfield(data, 'time') && numel(data.time) == nSamples && all(isfinite(data.time))
    timeVector = double(data.time(:));
else
    timeVector = (0:nSamples - 1)' / fs;
end
timeGapRejected = false(numel(windowStarts), 1);
artifactMask = false(nSamples, nChannels);
if isfield(data, 'artifacts') && isfield(data.artifacts, 'channelMask') && ...
        isequal(size(data.artifacts.channelMask), size(signal))
    artifactMask = logical(data.artifacts.channelMask);
end

for channelIndex = 1:nChannels
    accepted = false(numel(windowStarts), 1);
    for windowIndex = 1:numel(windowStarts)
        first = windowStarts(windowIndex); last = first + windowSamples - 1;
        segment = signal(first:last, channelIndex);
        invalid = ~isfinite(segment) | artifactMask(first:last, channelIndex);
        if any(abs(diff(timeVector(first:last)) - 1 / fs) > max(1e-9, 1e-3 / fs))
            timeGapRejected(windowIndex) = true;
            continue;
        end
        if options.ExcludeArtifacts && mean(invalid) > options.MaxArtifactFraction, continue; end
        if any(invalid)
            filledSampleCount(channelIndex) = filledSampleCount(channelIndex) + nnz(invalid);
            segment(invalid) = NaN; segment = fill_linear(segment);
        end
        segment = detrend_segment(segment, options.DetrendMode);
        taperPower = NaN(numel(frequencyHz), taperCount);
        for taperIndex = 1:taperCount
            taper = tapers(:, taperIndex);
            transformed = fft(segment .* taper, nfft);
            oneSided = abs(transformed(1:floor(nfft / 2) + 1)) .^ 2 / (fs * sum(taper .^ 2));
            if rem(nfft, 2) == 0, oneSided(2:end-1) = 2 * oneSided(2:end-1); else, oneSided(2:end) = 2 * oneSided(2:end); end
            taperPower(:, taperIndex) = oneSided(frequencyMask);
        end
        windowPsd(:, windowIndex, channelIndex) = mean(taperPower, 2);
        accepted(windowIndex) = true;
    end
    acceptedWindows{channelIndex} = windowStarts(accepted)';
end

psd = NaN(numel(frequencyHz), nChannels);
for channelIndex = 1:nChannels
    validWindows = isfinite(windowPsd(:, :, channelIndex));
    if options.AggregationMethod == "median"
        psd(:, channelIndex) = median(windowPsd(:, :, channelIndex), 2, 'omitnan');
    else
        psd(:, channelIndex) = mean(windowPsd(:, :, channelIndex), 2, 'omitnan');
    end
    noData = ~any(validWindows, 2); psd(noData, channelIndex) = NaN;
end

spectrum = struct();
spectrum.frequencyHz = frequencyHz; spectrum.psd = psd;
spectrum.psdUnits = string(data.units) + "^2/Hz"; spectrum.fs = fs;
spectrum.units = string(data.units); spectrum.channelLabels = get_channel_labels(data, nChannels);
spectrum.channelNames = spectrum.channelLabels; spectrum.channelCount = nChannels;
spectrum.method = "Multitaper (DPSS, base MATLAB)"; spectrum.methodCanonical = "multitaper";
spectrum.windowSeconds = windowSamples / fs; spectrum.overlapFraction = options.OverlapFraction;
spectrum.nfft = nfft; spectrum.windowCount = cellfun(@numel, acceptedWindows);
spectrum.acceptedWindowStarts = acceptedWindows; spectrum.allWindowStarts = windowStarts(:);
spectrum.windowPsd = windowPsd; spectrum.validWindowCountPerFrequency = sum(isfinite(windowPsd), 2);
spectrum.frequencyResolutionHz = fs / nfft; spectrum.excludedWindowCount = numel(windowStarts) - spectrum.windowCount;
spectrum.filledSampleCount = filledSampleCount; spectrum.includesLineNoise = true;
spectrum.timeGapRejected = timeGapRejected;
spectrum.taperCount = taperCount; spectrum.dpssEigenvalues = eigenvalues(:)';
spectrum.timeBandwidthProduct = nw; spectrum.halfBandwidthHz = nw / (windowSamples / fs);
spectrum.smoothingBandwidthHz = 2 * spectrum.halfBandwidthHz;
spectrum.parameters = struct('method', "multitaper", 'windowSeconds', options.WindowSeconds, ...
    'windowSamples', windowSamples, 'overlapFraction', options.OverlapFraction, 'nfft', nfft, ...
    'maxArtifactFraction', options.MaxArtifactFraction, 'excludeArtifacts', options.ExcludeArtifacts, ...
    'aggregationMethod', options.AggregationMethod, 'detrend', options.DetrendMode, ...
    'timeBandwidthProduct', nw, 'taperCount', taperCount, 'taperWeighting', options.TaperWeighting, ...
    'halfBandwidthHz', spectrum.halfBandwidthHz, 'smoothingBandwidthHz', spectrum.smoothingBandwidthHz, ...
    'frequencyRangeHz', options.FrequencyRangeHz);
data.spectrum = spectrum;
entry = struct('operation', "psd", 'parameters', spectrum.parameters, ...
    'notes', "Artifact-aware DPSS multitaper PSD; equal taper weights; 40-Hz harmonics retained.");
data.processingHistory(end + 1) = entry;
end

function starts = make_window_starts(nSamples, windowSamples, overlap)
step = max(1, round(windowSamples * (1 - overlap)));
starts = 1:step:max(1, nSamples - windowSamples + 1);
if starts(end) + windowSamples - 1 < nSamples, starts(end + 1) = nSamples - windowSamples + 1; end
end

function value = detrend_segment(value, mode)
switch mode
    case "constant", value = value - mean(value);
    case "linear", value = detrend(value, 'linear');
end
end

function values = fill_linear(values)
finite = isfinite(values);
if ~any(finite), values(:) = 0;
elseif nnz(finite) == 1, values(~finite) = values(find(finite, 1));
else, idx = (1:numel(values))'; values(~finite) = interp1(idx(finite), values(finite), idx(~finite), 'linear', 'extrap');
end
end

function validate_data(data)
if ~isfield(data, 'signal') || ~isfield(data, 'fs') || ~isfield(data, 'units') || ...
        ~isnumeric(data.signal) || ndims(data.signal) ~= 2 || isempty(data.signal)
    error('LFP:InvalidData', 'DATA.signal, DATA.fs, and DATA.units are required.');
end
if ~isscalar(data.fs) || ~isfinite(data.fs) || data.fs <= 0, error('LFP:InvalidData', 'DATA.fs must be positive.'); end
if ~isfield(data, 'processingHistory') || ~isstruct(data.processingHistory), error('LFP:InvalidData', 'DATA.processingHistory must be a struct array.'); end
end

function labels = get_channel_labels(data, nChannels)
if isfield(data, 'channelLabels') && numel(data.channelLabels) == nChannels, labels = string(data.channelLabels(:))';
elseif isfield(data, 'channelNames') && numel(data.channelNames) == nChannels, labels = string(data.channelNames(:))';
else, labels = "channel_" + string(1:nChannels); end
end

function data = lfp_compute_psd(data, options)
%LFP_COMPUTE_PSD Compute a one-sided Welch or DPSS multitaper PSD.
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
    options.Method (1,1) string {mustBeMember(options.Method, ["welch" "multitaper"])} = "multitaper"
    options.DetrendMode (1,1) string {mustBeMember(options.DetrendMode, ["" "none" "constant" "linear"])} = ""
    options.TimeBandwidthProduct (1,1) double {mustBeFinite, mustBeGreaterThan(options.TimeBandwidthProduct, 0.5)} = 3.5
    options.TaperCount (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.TaperWeighting (1,1) string {mustBeMember(options.TaperWeighting, "equal")} = "equal"
    options.FrequencyRangeHz (1,2) double {mustBeNonnegative} = [1 35]
    options.ProgressCallback = []
    options.CancellationCheck = []
end

validate_data(data);
progress = callback_or_default(options.ProgressCallback, @(fraction, message)[]);
cancel = callback_or_default(options.CancellationCheck, @()[]);
cancel(); progress(0, "Preparing PSD windows");
if options.Method == "multitaper"
    data = lfp_compute_multitaper_psd(data, ...
        WindowSeconds=options.WindowSeconds, ...
        OverlapFraction=options.OverlapFraction, Nfft=options.Nfft, ...
        MaxArtifactFraction=options.MaxArtifactFraction, ...
        ExcludeArtifacts=options.ExcludeArtifacts, ...
        AggregationMethod=options.AggregationMethod, ...
        DetrendMode=resolve_detrend_mode(options.DetrendMode, options.DetrendConstant), ...
        TimeBandwidthProduct=options.TimeBandwidthProduct, ...
        TaperCount=options.TaperCount, TaperWeighting=options.TaperWeighting, ...
        FrequencyRangeHz=options.FrequencyRangeHz, ...
        ProgressCallback=progress, CancellationCheck=cancel);
    return;
end
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
if isfield(data, 'time') && numel(data.time) == nSamples && all(isfinite(data.time))
    timeVector = double(data.time(:));
else
    timeVector = (0:nSamples - 1)' / fs;
end
timeGapRejected = false(numel(windowStarts), 1);

artifactMask = false(nSamples, nChannels);
if isfield(data, 'artifacts') && isfield(data.artifacts, 'channelMask')
    candidateMask = data.artifacts.channelMask;
    if isequal(size(candidateMask), size(signal))
        artifactMask = logical(candidateMask);
    end
end

for channelIndex = 1:nChannels
    cancel();
    progress((channelIndex - 1) / max(nChannels, 1), ...
        sprintf('Welch PSD: channel %d/%d', channelIndex, nChannels));
    accumulated = zeros(numel(frequencyHz), 1);
    accepted = false(numel(windowStarts), 1);
    count = 0;
    for windowIndex = 1:numel(windowStarts)
        if mod(windowIndex - 1, 100) == 0
            cancel();
            localFraction = (windowIndex - 1) / max(numel(windowStarts), 1);
            progress(((channelIndex - 1) + localFraction) / max(nChannels, 1), ...
                sprintf('Welch PSD: channel %d/%d', channelIndex, nChannels));
        end
        first = windowStarts(windowIndex);
        last = first + windowSamples - 1;
        segment = signal(first:last, channelIndex);
        invalid = ~isfinite(segment) | artifactMask(first:last, channelIndex);
        if any(abs(diff(timeVector(first:last)) - 1 / fs) > max(1e-9, 1e-3 / fs))
            timeGapRejected(windowIndex) = true;
            continue;
        end
        artifactFraction = mean(invalid);
        % MaxArtifactFraction is the explicit tolerance for a window. With
        % the default 0, any invalid/artifact sample rejects the window. A
        % positive value permits a small contaminated portion and records
        % the local linear fill in filledSampleCount.
        if options.ExcludeArtifacts && artifactFraction > options.MaxArtifactFraction
            continue;
        end
        if any(invalid)
            filledSampleCount(channelIndex) = filledSampleCount(channelIndex) + nnz(invalid);
            segment(invalid) = NaN;
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
spectrum.fs = fs;
spectrum.units = string(data.units);
spectrum.channelLabels = get_channel_labels(data, nChannels);
spectrum.channelNames = spectrum.channelLabels;
spectrum.channelCount = nChannels;
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
spectrum.timeGapRejected = timeGapRejected;
spectrum.includesLineNoise = true;
spectrum.parameters = struct('windowSeconds', options.WindowSeconds, ...
    'windowSamples', windowSamples, 'overlapFraction', options.OverlapFraction, ...
    'nfft', nfft, 'maxArtifactFraction', options.MaxArtifactFraction, ...
    'detrendConstant', options.DetrendConstant, 'excludeArtifacts', options.ExcludeArtifacts, ...
    'aggregationMethod', options.AggregationMethod, 'taper', options.Taper, ...
    'method', "welch", 'detrend', resolve_detrend_mode(options.DetrendMode, options.DetrendConstant), ...
    'frequencyRangeHz', options.FrequencyRangeHz);
data.spectrum = spectrum;
entry = struct('operation', "psd", 'parameters', spectrum.parameters, ...
    'notes', "Manual Welch PSD from raw signal; artifact-heavy windows excluded; 40-Hz harmonics retained.");
data.processingHistory(end + 1) = entry;
progress(1, "Welch PSD complete");
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

function value = resolve_detrend_mode(mode, detrendConstant)
if strlength(mode) == 0
    if detrendConstant, value = "constant"; else, value = "none"; end
else
    value = mode;
end
end

function labels = get_channel_labels(data, nChannels)
if isfield(data, 'channelLabels') && numel(data.channelLabels) == nChannels
    labels = string(data.channelLabels(:))';
elseif isfield(data, 'channelNames') && numel(data.channelNames) == nChannels
    labels = string(data.channelNames(:))';
else
    labels = "channel_" + string(1:nChannels);
end
end

function callback = callback_or_default(candidate, defaultCallback)
if isa(candidate, 'function_handle'), callback = candidate; else, callback = defaultCallback; end
end

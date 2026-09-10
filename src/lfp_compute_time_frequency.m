function data = lfp_compute_time_frequency(data, options)
%LFP_COMPUTE_TIME_FREQUENCY Compute artifact-aware STFT or sliding DPSS power.
%   DATA = LFP_COMPUTE_TIME_FREQUENCY(DATA) stores DATA.timeFrequency with
%   frequency x time x channel power. The raw signal is not filtered and
%   40-Hz harmonics remain visible. Windows exceeding the artifact limit
%   are returned as NaN columns.

arguments
    data (1,1) struct
    options.WindowSeconds (1,1) double {mustBeFinite, mustBePositive} = 1
    options.StepSeconds (1,1) double {mustBeFinite, mustBePositive} = 0.25
    options.Nfft (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.FrequencyRangeHz (1,2) double {mustBeNonnegative} = [0 Inf]
    options.MaxArtifactFraction (1,1) double {mustBeFinite, mustBeInRange(options.MaxArtifactFraction, 0, 1)} = 0.10
    options.ExcludeArtifacts (1,1) logical = true
    options.Method (1,1) string {mustBeMember(options.Method, ["welch" "multitaper"])} = "welch"
    options.TimeBandwidthProduct (1,1) double {mustBeFinite, mustBeGreaterThan(options.TimeBandwidthProduct, 0.5)} = 3.5
    options.TaperCount (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.PowerScale (1,1) string {mustBeMember(options.PowerScale, ["linear" "log10" "dB"])} = "linear"
    options.ProgressCallback = []
    options.CancellationCheck = []
end

if ~isfield(data, 'signal') || ~isfield(data, 'fs') || ~isfield(data, 'processingHistory')
    error('LFP:InvalidData', 'DATA.signal, DATA.fs, and DATA.processingHistory are required.');
end
signal = double(data.signal);
[nSamples, nChannels] = size(signal);
fs = double(data.fs);
windowSamples = min(nSamples, max(1, round(options.WindowSeconds * fs)));
stepSamples = max(1, round(options.StepSeconds * fs));
if options.Nfft == 0
    nfft = 2 ^ nextpow2(windowSamples);
else
    nfft = max(windowSamples, options.Nfft);
end
if options.Method == "multitaper"
    nw = options.TimeBandwidthProduct;
    if options.TaperCount == 0, taperCount = max(1, floor(2 * nw) - 1); else, taperCount = options.TaperCount; end
    [tapers, taperEigenvalues] = lfp_dpss(windowSamples, nw, taperCount);
else
    window = hann_vector(windowSamples);
    normalization = fs * sum(window .^ 2);
    taperCount = 1; nw = NaN; taperEigenvalues = NaN;
end
progress = callback_or_default(options.ProgressCallback, @(fraction, message)[]);
cancel = callback_or_default(options.CancellationCheck, @()[]);
cancel(); progress(0, "Preparing time-frequency windows");
frequencyHz = (0:floor(nfft / 2))' * fs / nfft;
frequencyMask = frequencyHz >= options.FrequencyRangeHz(1) & ...
    frequencyHz <= min(options.FrequencyRangeHz(2), frequencyHz(end));
frequencyHz = frequencyHz(frequencyMask);

starts = 1:stepSamples:max(1, nSamples - windowSamples + 1);
if starts(end) + windowSamples - 1 < nSamples
    starts(end + 1) = nSamples - windowSamples + 1;
end
power = NaN(numel(frequencyHz), numel(starts), nChannels);
if isfield(data, 'time') && numel(data.time) == nSamples && all(isfinite(data.time))
    timeVector = double(data.time(:));
    timeSeconds = (timeVector(starts) + timeVector(starts + windowSamples - 1)) / 2;
else
    timeVector = (0:nSamples-1)' / fs;
    timeSeconds = (starts(:) + (windowSamples - 1) / 2 - 1) / fs;
end
timeSeconds = timeSeconds(:);
timeGapRejected = false(numel(starts), 1);
artifactMask = false(size(signal));
if isfield(data, 'artifacts') && isfield(data.artifacts, 'channelMask') && ...
        isequal(size(data.artifacts.channelMask), size(signal))
    artifactMask = logical(data.artifacts.channelMask);
end
for channelIndex = 1:nChannels
    for windowIndex = 1:numel(starts)
        if mod(windowIndex - 1, 50) == 0
            cancel();
            localFraction = (windowIndex - 1) / max(numel(starts), 1);
            progress(((channelIndex - 1) + localFraction) / max(nChannels, 1), ...
                sprintf('Time-frequency: channel %d/%d', channelIndex, nChannels));
        end
        first = starts(windowIndex);
        last = first + windowSamples - 1;
        segment = signal(first:last, channelIndex);
        invalid = ~isfinite(segment) | artifactMask(first:last, channelIndex);
        if options.ExcludeArtifacts && mean(invalid) > options.MaxArtifactFraction
            continue;
        end
        if any(~isfinite(diff(timeVector(first:last)))) || ...
                any(abs(diff(timeVector(first:last)) - 1 / fs) > max(1e-9, 1e-3 / fs))
            timeGapRejected(windowIndex) = true;
            continue;
        end
        segment(invalid) = NaN;
        segment = fill_linear(segment);
        segment = segment - mean(segment);
        if options.Method == "multitaper"
            taperPower = NaN(numel(frequencyHz), taperCount);
            for taperIndex = 1:taperCount
                taper = tapers(:, taperIndex);
                transformed = fft(segment .* taper, nfft);
                oneSided = abs(transformed(1:floor(nfft / 2) + 1)) .^ 2 / (fs * sum(taper .^ 2));
                if rem(nfft, 2) == 0, oneSided(2:end-1) = 2 * oneSided(2:end-1); else, oneSided(2:end) = 2 * oneSided(2:end); end
                taperPower(:, taperIndex) = oneSided(frequencyMask);
            end
            power(:, windowIndex, channelIndex) = mean(taperPower, 2);
        else
            transformed = fft(segment .* window, nfft);
            oneSided = abs(transformed(1:floor(nfft / 2) + 1)) .^ 2 / normalization;
            if rem(nfft, 2) == 0
                oneSided(2:end-1) = 2 * oneSided(2:end-1);
            else
                oneSided(2:end) = 2 * oneSided(2:end);
            end
            power(:, windowIndex, channelIndex) = oneSided(frequencyMask);
        end
    end
end

if options.Method == "multitaper"
    methodName = "sliding DPSS multitaper (base MATLAB)";
    halfBandwidth = nw / (windowSamples / fs);
    smoothingBandwidth = 2 * halfBandwidth;
else
    methodName = "manual STFT/Welch (base MATLAB)";
    halfBandwidth = NaN;
    smoothingBandwidth = NaN;
end
validWindowMask = squeeze(any(any(isfinite(power), 1), 3));
data.timeFrequency = struct('frequencyHz', frequencyHz, 'timeSeconds', timeSeconds, ...
    'power', power, 'powerUnits', string(data.units) + "^2/Hz", ...
    'windowSeconds', windowSamples / fs, 'stepSeconds', stepSamples / fs, ...
    'nfft', nfft, 'maxArtifactFraction', options.MaxArtifactFraction, ...
    'excludeArtifacts', options.ExcludeArtifacts, 'method', methodName, ...
    'methodCanonical', options.Method, 'validWindowMask', validWindowMask(:), ...
    'windowStarts', starts(:), 'windowEnds', (starts(:) + windowSamples - 1), ...
    'timeGapRejected', timeGapRejected, 'taperCount', taperCount, ...
    'timeBandwidthProduct', nw, 'taperEigenvalues', taperEigenvalues(:)', ...
    'halfBandwidthHz', halfBandwidth, 'smoothingBandwidthHz', smoothingBandwidth, ...
    'powerScale', options.PowerScale);
entry = struct('operation', "time_frequency", 'parameters', struct( ...
    'windowSeconds', options.WindowSeconds, 'stepSeconds', options.StepSeconds, ...
    'nfft', nfft, 'frequencyRangeHz', options.FrequencyRangeHz, ...
    'maxArtifactFraction', options.MaxArtifactFraction, 'excludeArtifacts', options.ExcludeArtifacts, ...
    'method', options.Method, 'taperCount', taperCount, 'timeBandwidthProduct', nw), ...
    'notes', "Invalid or discontinuous windows set to NaN; no line-frequency notch applied.");
data.processingHistory(end + 1) = entry;
progress(1, "Time-frequency calculation complete");
end

function values = hann_vector(n)
if n == 1
    values = 1;
else
    index = (0:n-1)';
    values = 0.5 - 0.5*cos(2*pi*index/(n-1));
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

function callback = callback_or_default(candidate, defaultCallback)
if isa(candidate, 'function_handle'), callback = candidate; else, callback = defaultCallback; end
end

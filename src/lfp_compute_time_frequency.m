function data = lfp_compute_time_frequency(data, options)
%LFP_COMPUTE_TIME_FREQUENCY Compute an artifact-aware STFT spectrogram.
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
window = hann_vector(windowSamples);
normalization = fs * sum(window .^ 2);
frequencyHz = (0:floor(nfft / 2))' * fs / nfft;
frequencyMask = frequencyHz >= options.FrequencyRangeHz(1) & ...
    frequencyHz <= min(options.FrequencyRangeHz(2), frequencyHz(end));
frequencyHz = frequencyHz(frequencyMask);

starts = 1:stepSamples:max(1, nSamples - windowSamples + 1);
if starts(end) + windowSamples - 1 < nSamples
    starts(end + 1) = nSamples - windowSamples + 1;
end
power = NaN(numel(frequencyHz), numel(starts), nChannels);
timeSeconds = (starts(:) + (windowSamples - 1) / 2 - 1) / fs;
artifactMask = false(size(signal));
if isfield(data, 'artifacts') && isfield(data.artifacts, 'channelMask') && ...
        isequal(size(data.artifacts.channelMask), size(signal))
    artifactMask = logical(data.artifacts.channelMask);
end
for channelIndex = 1:nChannels
    for windowIndex = 1:numel(starts)
        first = starts(windowIndex);
        last = first + windowSamples - 1;
        segment = signal(first:last, channelIndex);
        invalid = ~isfinite(segment) | artifactMask(first:last, channelIndex);
        if mean(invalid) > options.MaxArtifactFraction
            continue;
        end
        segment(invalid) = NaN;
        segment = fill_linear(segment);
        segment = segment - mean(segment);
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

data.timeFrequency = struct('frequencyHz', frequencyHz, 'timeSeconds', timeSeconds, ...
    'power', power, 'powerUnits', string(data.units) + "^2/Hz", ...
    'windowSeconds', windowSamples / fs, 'stepSeconds', stepSamples / fs, ...
    'nfft', nfft, 'maxArtifactFraction', options.MaxArtifactFraction, ...
    'method', "manual STFT (base MATLAB)");
entry = struct('operation', "time_frequency", 'parameters', struct( ...
    'windowSeconds', options.WindowSeconds, 'stepSeconds', options.StepSeconds, ...
    'nfft', nfft, 'frequencyRangeHz', options.FrequencyRangeHz, ...
    'maxArtifactFraction', options.MaxArtifactFraction), ...
    'notes', "Artifact-heavy STFT windows set to NaN; no line-frequency notch applied.");
data.processingHistory(end + 1) = entry;
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

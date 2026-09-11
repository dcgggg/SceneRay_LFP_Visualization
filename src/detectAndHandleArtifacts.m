function [cleanData, artifactResult] = detectAndHandleArtifacts(data, artifactCfg)
%DETECTANDHANDLEARTIFACTS Detect and annotate common LFP artifacts.
%   [CLEANDATA, ARTIFACTRESULT] = DETECTANDHANDLEARTIFACTS(DATA, CFG)
%   preserves DATA.signal and returns a NaN-marked display/analysis copy in
%   CLEANDATA.cleanedSignal. The default native backend detects artifacts
%   independently per channel. FieldTrip remains an explicit optional
%   backend; its returned intervals are global because ft_artifact_zvalue
%   reports time intervals rather than channel-specific masks. Line noise is
%   not a time-domain artifact by default: 40-Hz harmonics remain available
%   for fitting-only interpolation later in the pipeline.

arguments
    data (1,1) struct
    artifactCfg (1,1) struct
end

validate_input(data, artifactCfg);
runtime = runtime_callbacks(artifactCfg);
runtime.cancel();
runtime.progress(0, "Preparing artifact detection");
signal = double(data.signal);
[nSamples, nChannels] = size(signal);
fs = double(data.fs);
methodRequested = lower(string(artifactCfg.method));
if artifactCfg.reconstruct
    error('LFP:ReconstructionUnavailable', ...
        'Artifact reconstruction is not implemented; use mask-only handling or set reconstruct=false.');
end

reasonMasks = struct();
nativeEvents = empty_event_arrays();
methodUsed = methodRequested;
warnings = strings(0, 1);

if methodRequested == "fieldtrip"
    runtime.cancel();
    [fieldtripMask, fieldtripEvents, fieldtripWarnings, fieldtripAvailable] = ...
        run_fieldtrip_backend(data, artifactCfg);
    warnings = [warnings; fieldtripWarnings]; %#ok<AGROW>
    if fieldtripAvailable
        reasonMasks.fieldtrip = fieldtripMask;
        nativeEvents = append_events(nativeEvents, fieldtripEvents);
    elseif artifactCfg.nativeFallback
        methodUsed = "native_fallback";
    else
        error('LFP:FieldTripUnavailable', 'FieldTrip backend unavailable and nativeFallback=false.');
    end
elseif methodRequested == "asr"
    error('LFP:ASRUnavailable', 'ASR backend is not included; provide a validated MATLAB ASR implementation before enabling it.');
elseif methodRequested ~= "native"
    error('LFP:InvalidArtifactMethod', 'Supported methods are fieldtrip, native, and asr.');
end

skipNativeJump = methodRequested == "fieldtrip" && isfield(reasonMasks, 'fieldtrip');
[nativeMask, nativeEvents] = run_native_backend(signal, fs, artifactCfg, nativeEvents, skipNativeJump, runtime);
if methodRequested == "fieldtrip" && isfield(reasonMasks, 'fieldtrip')
    combinedMask = nativeMask | reasonMasks.fieldtrip;
else
    combinedMask = nativeMask;
end

[manualMask, manualEvents] = manual_intervals(data, artifactCfg, fs, nSamples, nChannels);
combinedMask = combinedMask | manualMask;
nativeEvents = append_events(nativeEvents, manualEvents);

paddingSamples = round(get_field(artifactCfg, 'paddingSeconds', 0) * fs);
if paddingSamples > 0
    combinedMask = expand_mask(combinedMask, paddingSamples);
end

globalMask = any(combinedMask, 2);
events = events_to_table(nativeEvents, fs, nChannels);
cleanedSignal = signal;
cleanedSignal(combinedMask) = NaN;

artifactResult = struct();
artifactResult.sampleMask = globalMask;
artifactResult.channelMask = combinedMask;
artifactResult.globalMask = globalMask;
artifactResult.events = events;
artifactResult.badChannels = find_bad_channels(combinedMask, signal, artifactCfg);
artifactResult.method = methodUsed;
artifactResult.methodRequested = methodRequested;
storedCfg = strip_runtime_fields(artifactCfg);
artifactResult.parameters = storedCfg;
artifactResult.summary = summarize_events(events, artifactResult.badChannels, nSamples, nChannels, fs, combinedMask);
artifactResult.retainedDuration = nnz(~globalMask) / fs;
artifactResult.rejectedDuration = nnz(globalMask) / fs;
artifactResult.rejectedPercentage = 100 * nnz(globalMask) / max(nSamples, 1);
artifactResult.warnings = warnings;
artifactResult.processingHistory = append_history(data, methodUsed, storedCfg, warnings);

cleanData = data;
cleanData.cleanedSignal = cleanedSignal;
cleanData.artifacts = artifactResult;
cleanData.processingHistory = artifactResult.processingHistory;
runtime.progress(1, "Artifact detection complete");
end

function validate_input(data, cfg)
if ~isfield(data, 'signal') || ~isfield(data, 'fs') || ~isnumeric(data.signal) || ndims(data.signal) ~= 2
    error('LFP:InvalidData', 'DATA.signal and DATA.fs must define a numeric samples-by-channels matrix.');
end
if ~isscalar(data.fs) || ~isfinite(data.fs) || data.fs <= 0
    error('LFP:InvalidData', 'DATA.fs must be positive and finite.');
end
required = {'method', 'nativeFallback', 'reconstruct'};
for index = 1:numel(required)
    if ~isfield(cfg, required{index})
        error('LFP:InvalidArtifactConfig', 'artifactCfg.%s is required.', required{index});
    end
end
if ~isfield(data, 'processingHistory') || ~isstruct(data.processingHistory)
    error('LFP:InvalidData', 'DATA.processingHistory must be a struct array.');
end
end

function [mask, events, warnings, available] = run_fieldtrip_backend(data, cfg)
signal = double(data.signal);
[nSamples, nChannels] = size(signal);
fs = double(data.fs);
mask = false(nSamples, nChannels);
events = empty_event_arrays();
warnings = strings(0, 1);
available = exist('ft_artifact_zvalue', 'file') == 2;
if ~available
    warnings(end + 1) = "FieldTrip ft_artifact_zvalue not found; native fallback used.";
    return;
end
try
    labels = get_labels(data, nChannels);
    ftData = struct('trial', {{signal.'}}, 'time', {{(0:nSamples-1) ./ fs}}, ...
        'label', {cellstr(labels(:))}, 'fsample', fs, 'sampleinfo', [1 nSamples]);
    ftCfg = [];
    ftCfg.trl = [1 nSamples 0];
    ftCfg.continuous = 'yes';
    ftCfg.artfctdef.zvalue.channel = 'all';
    ftCfg.artfctdef.zvalue.cutoff = get_field(cfg, 'fieldtripCutoff', 6);
    ftCfg.artfctdef.zvalue.trlpadding = 0;
    ftCfg.artfctdef.zvalue.fltpadding = 0;
    ftCfg.artfctdef.zvalue.artpadding = 0;
    ftCfg.artfctdef.zvalue.absdiff = 'yes';
    [~, artifact] = ft_artifact_zvalue(ftCfg, ftData);
    if ~isempty(artifact)
        warnings(end + 1) = "FieldTrip intervals are applied to all channels; use method='native' for channel-specific masks.";
        for index = 1:size(artifact, 1)
            first = max(1, round(artifact(index, 1)));
            last = min(nSamples, round(artifact(index, 2)));
            mask(first:last, :) = true;
            events = append_event(events, "jump", first, last, 0, ...
                get_field(cfg, 'fieldtripCutoff', 6), "fieldtrip.ft_artifact_zvalue");
        end
    end
catch exception
    available = false;
    warnings(end + 1) = "FieldTrip backend failed: " + string(exception.message);
end
end

function [mask, events] = run_native_backend(signal, fs, cfg, events, skipJump, runtime)
[nSamples, nChannels] = size(signal);
if nargin < 5, skipJump = false; end
mask = false(nSamples, nChannels);
for channel = 1:nChannels
    runtime.cancel();
    runtime.progress((channel - 1) / max(nChannels, 1), ...
        sprintf('Detecting artifacts: channel %d/%d', channel, nChannels));
    x = signal(:, channel);
    finite = isfinite(x);
    values = x(finite);
    if isempty(values)
        mask(:, channel) = true;
        events = append_event(events, "bad_channel", 1, nSamples, channel, Inf, "native.nonfinite");
        continue;
    end
    center = median(values);
    sigma = robust_scale(values - center);
    amplitude = finite & sigma > 0 & abs(x - center) > get_field(cfg, 'amplitudeZ', 8) * sigma;
    [mask, events] = merge_reason(mask, events, amplitude, channel, "high_amplitude", ...
        get_field(cfg, 'amplitudeZ', 8), "native.robust_amplitude");

    if ~skipJump
        dx = [0; diff(x)];
        dFinite = dx(isfinite(dx));
        dCenter = median(dFinite);
        dSigma = robust_scale(dFinite - dCenter);
        jump = isfinite(dx) & dSigma > 0 & abs(dx - dCenter) > get_field(cfg, 'derivativeZ', 8) * dSigma;
        [mask, events] = merge_reason(mask, events, jump, channel, "jump_spike", ...
            get_field(cfg, 'derivativeZ', 8), "native.robust_derivative");
    end

    saturation = detect_saturation(x, get_field(cfg, 'saturationAbsoluteThresholdUV', 5000), ...
        get_field(cfg, 'saturationRunLength', 5));
    [mask, events] = merge_reason(mask, events, saturation, channel, "saturation", ...
        get_field(cfg, 'saturationAbsoluteThresholdUV', 5000), "native.rail_run");

    flatline = detect_flatline(x, fs, get_field(cfg, 'flatlineRunSeconds', 0.25), ...
        get_field(cfg, 'flatlineToleranceUV', 1e-6));
    [mask, events] = merge_reason(mask, events, flatline, channel, "flatline", ...
        get_field(cfg, 'flatlineToleranceUV', 1e-6), "native.flatline");

    highFrequency = detect_high_frequency(x, fs, cfg);
    [mask, events] = merge_reason(mask, events, highFrequency, channel, "high_frequency_burst", ...
        get_field(cfg, 'highFrequencyZ', 8), "native.high_frequency_envelope");

    if get_field(cfg, 'strictMode', false)
        strictBurst = detect_strict_burst(x, fs, cfg, runtime, channel, nChannels);
        [mask, events] = merge_reason(mask, events, strictBurst, channel, "strict_burst", ...
            get_field(cfg, 'strictHighFrequencyZ', 4), "native.strict_window_features");
    end

    % 40-Hz interference is preserved for fitting-only interpolation unless
    % a user explicitly enables time-domain line-noise rejection.
    if get_field(cfg, 'lineNoiseDetection', false)
        lineNoise = detect_line_noise(x, fs, cfg);
        [mask, events] = merge_reason(mask, events, lineNoise, channel, "line_noise", ...
            get_field(cfg, 'lineNoiseRatioThreshold', 0.5), "native.line_projection");
    end
end
end

function [mask, events] = merge_reason(mask, events, reasonMask, channel, kind, threshold, method)
if ~any(reasonMask), return; end
mask(:, channel) = mask(:, channel) | reasonMask;
starts = find(diff([false; reasonMask; false]) == 1);
ends = find(diff([false; reasonMask; false]) == -1) - 1;
for index = 1:numel(starts)
    score = max(reasonMask(starts(index):ends(index)));
    events = append_event(events, kind, starts(index), ends(index), channel, score, method, threshold);
end
end

function events = append_event(events, kind, first, last, channel, score, method, threshold)
if nargin < 8, threshold = NaN; end
events.artifactType(end + 1, 1) = string(kind);
events.startSample(end + 1, 1) = first;
events.endSample(end + 1, 1) = last;
events.channel(end + 1, 1) = channel;
events.detectionScore(end + 1, 1) = score;
events.threshold(end + 1, 1) = threshold;
events.detectionMethod(end + 1, 1) = string(method);
end

function events = append_events(events, other)
for index = 1:numel(other.startSample)
    events = append_event(events, other.artifactType(index), other.startSample(index), ...
        other.endSample(index), other.channel(index), other.detectionScore(index), ...
        other.detectionMethod(index), other.threshold(index));
end
end

function events = empty_event_arrays()
events = struct('artifactType', strings(0, 1), 'startSample', zeros(0, 1), ...
    'endSample', zeros(0, 1), 'channel', zeros(0, 1), ...
    'detectionScore', zeros(0, 1), 'threshold', NaN(0, 1), ...
    'detectionMethod', strings(0, 1));
end

function tableEvents = events_to_table(events, fs, nChannels)
count = numel(events.startSample);
if count == 0
    tableEvents = table(strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), ...
        'VariableNames', {'artifactType','startSample','endSample','startTime','endTime', ...
        'channel','detectionScore','threshold','detectionMethod'});
    return;
end
channel = events.channel;
channel(channel == 0) = NaN;
tableEvents = table(events.artifactType, events.startSample, events.endSample, ...
    (events.startSample - 1) ./ fs, events.endSample ./ fs, channel, ...
    events.detectionScore, events.threshold, events.detectionMethod, ...
    'VariableNames', {'artifactType','startSample','endSample','startTime','endTime', ...
    'channel','detectionScore','threshold','detectionMethod'});
end

function [mask, events] = manual_intervals(data, cfg, fs, nSamples, nChannels)
mask = false(nSamples, nChannels);
events = empty_event_arrays();
if isfield(cfg, 'manualIntervalsSamples') && ~isempty(cfg.manualIntervalsSamples)
    intervals = cfg.manualIntervalsSamples;
    for index = 1:size(intervals, 1)
        first = max(1, round(intervals(index, 1)));
        last = min(nSamples, round(intervals(index, 2)));
        if first <= last
            mask(first:last, :) = true;
            events = append_event(events, "manual", first, last, 0, 1, "user.manualIntervalsSamples", 1);
        end
    end
end
if isfield(cfg, 'manualIntervalsSeconds') && ~isempty(cfg.manualIntervalsSeconds)
    intervals = cfg.manualIntervalsSeconds;
    for index = 1:size(intervals, 1)
        first = max(1, round(intervals(index, 1) * fs) + 1);
        last = min(nSamples, round(intervals(index, 2) * fs));
        if first <= last
            mask(first:last, :) = true;
            events = append_event(events, "manual", first, last, 0, 1, "user.manualIntervalsSeconds", 1);
        end
    end
end
end

function mask = expand_mask(mask, padding)
for channel = 1:size(mask, 2)
    indices = find(mask(:, channel));
    for index = 1:numel(indices)
        mask(max(1, indices(index)-padding):min(size(mask,1), indices(index)+padding), channel) = true;
    end
end
end

function mask = detect_saturation(x, threshold, runLength)
candidate = isfinite(x) & abs(x) >= threshold;
mask = false(size(x));
starts = find(diff([false; candidate; false]) == 1);
ends = find(diff([false; candidate; false]) == -1) - 1;
for index = 1:numel(starts)
    segment = x(starts(index):ends(index));
    if numel(segment) >= runLength && all(segment == segment(1))
        mask(starts(index):ends(index)) = true;
    end
end
end

function mask = detect_flatline(x, fs, runSeconds, tolerance)
runLength = max(2, round(runSeconds * fs));
candidate = isfinite(x);
if numel(x) > 1
    candidate(2:end) = candidate(2:end) & abs(diff(x)) <= tolerance;
end
mask = false(size(x));
starts = find(diff([false; candidate; false]) == 1);
ends = find(diff([false; candidate; false]) == -1) - 1;
for index = 1:numel(starts)
    if ends(index) - starts(index) + 1 >= runLength
        mask(starts(index):ends(index)) = true;
    end
end
end

function mask = detect_high_frequency(x, fs, cfg)
window = max(3, round(get_field(cfg, 'highFrequencyWindowSeconds', 0.25) * fs));
envelope = conv(abs([0; diff(x)]), ones(window, 1) / window, 'same');
finite = isfinite(envelope);
values = envelope(finite);
mask = false(size(x));
if isempty(values), return; end
sigma = robust_scale(values - median(values));
if sigma > 0
    candidate = finite & envelope > median(values) + get_field(cfg, 'highFrequencyZ', 8) * sigma;
    % A single-sample excursion in a smooth low-frequency sinusoid is not a
    % high-frequency burst.  Require a short contiguous run so numerical
    % derivative round-off cannot reject an otherwise clean PSD window.
    minRun = max(2, round(get_field(cfg, 'highFrequencyMinRunSeconds', 0.01) * fs));
    starts = find(diff([false; candidate; false]) == 1);
    ends = find(diff([false; candidate; false]) == -1) - 1;
    for index = 1:numel(starts)
        if ends(index) - starts(index) + 1 >= minRun
            mask(starts(index):ends(index)) = true;
        end
    end
end
end

function mask = detect_strict_burst(x, fs, cfg, runtime, channel, nChannels)
% Detect sustained abnormal windows using high-frequency energy, derivative
% energy, and local range. Complete short windows are marked so a burst with
% moderate amplitude is not reduced to a few missed samples.
mask = false(size(x));
finite = isfinite(x);
if nnz(finite) < 5
    return;
end
filled = x;
filled(~finite) = fill_nonfinite(x, finite);
cutoffHz = get_field(cfg, 'strictHighpassHz', 100);
windowSamples = max(5, round(get_field(cfg, 'strictWindowSeconds', 0.1) * fs));
windowSamples = min(windowSamples, numel(x));
stepSamples = max(1, round(get_field(cfg, 'strictStepSeconds', 0.05) * fs));
starts = 1:stepSamples:max(1, numel(x) - windowSamples + 1);
if starts(end) + windowSamples - 1 < numel(x)
    starts(end + 1) = numel(x) - windowSamples + 1;
end
hfRms = NaN(numel(starts), 1);
derivativeRms = hfRms;
localRange = hfRms;
validWindow = false(numel(starts), 1);
nfft = 2 ^ nextpow2(windowSamples);
frequency = (0:floor(nfft/2))' * fs / nfft;
highFrequencyBins = frequency >= cutoffHz & frequency <= fs/2;
for index = 1:numel(starts)
    if mod(index - 1, 100) == 0
        runtime.cancel();
        channelFraction = (index - 1) / max(numel(starts), 1);
        runtime.progress(((channel - 1) + channelFraction) / max(nChannels, 1), ...
            sprintf('Strict burst detection: channel %d/%d', channel, nChannels));
    end
    first = starts(index); last = first + windowSamples - 1;
    if nnz(finite(first:last)) < 0.8 * windowSamples
        continue;
    end
    segment = filled(first:last);
    segment = segment - mean(segment);
    spectrum = fft(segment, nfft);
    oneSidedPower = abs(spectrum(1:floor(nfft/2)+1)).^2 / max(windowSamples, 1);
    if rem(nfft, 2) == 0
        oneSidedPower(2:end-1) = 2 * oneSidedPower(2:end-1);
    else
        oneSidedPower(2:end) = 2 * oneSidedPower(2:end);
    end
    hfRms(index) = sqrt(sum(oneSidedPower(highFrequencyBins)) / max(windowSamples, 1));
    d = diff(filled(first:last));
    derivativeRms(index) = sqrt(mean(d .^ 2));
    localRange(index) = max(segment) - min(segment);
    validWindow(index) = true;
end
if ~any(validWindow), return; end
hfValues = hfRms(validWindow);
dValues = derivativeRms(validWindow);
rangeValues = localRange(validWindow);
hfThreshold = strict_threshold(hfValues, get_field(cfg, 'strictHighFrequencyZ', 4));
dThreshold = strict_threshold(dValues, get_field(cfg, 'strictDerivativeZ', 4));
rangeThreshold = strict_threshold(rangeValues, get_field(cfg, 'strictRangeZ', 4));
candidate = validWindow & ((hfRms >= hfThreshold) | ...
    (derivativeRms >= dThreshold) | (localRange >= rangeThreshold));
for index = find(candidate(:))'
    first = starts(index); last = min(numel(x), starts(index) + windowSamples - 1);
    mask(first:last) = true;
end

% Join nearby candidate windows so burst trains are represented as one
% continuous artifact instead of many gaps at zero crossings.
gapSamples = max(0, round(get_field(cfg, 'strictMergeGapSeconds', 0.2) * fs));
if gapSamples > 0
    startsMask = find(diff([false; mask; false]) == 1);
    endsMask = find(diff([false; mask; false]) == -1) - 1;
    for index = 1:numel(startsMask)-1
        if startsMask(index+1) - endsMask(index) - 1 <= gapSamples
            mask(endsMask(index):startsMask(index+1)) = true;
        end
    end
end
mask(~finite) = true;
end

function values = fill_nonfinite(x, finite)
values = x(finite);
if isempty(values)
    values = 0;
elseif numel(values) == 1
    values = values(1);
else
    index = (1:numel(x))';
    values = interp1(index(finite), x(finite), index(~finite), 'linear', 'extrap');
end
end

function threshold = strict_threshold(values, z)
center = median(values, 'omitnan');
scale = robust_scale(values - center);
% Numerical round-off in a stationary sinusoid can produce a tiny non-zero
% MAD. Treat it as constant rather than flagging a few arbitrary windows.
scaleFloor = 1e-6 * max(abs(center), 1);
if ~(isfinite(scale) && scale > scaleFloor)
    threshold = center + max(0.5 * abs(center), eps);
else
    threshold = center + z * scale;
end
end

function mask = detect_line_noise(x, fs, cfg)
mask = false(size(x));
lineFrequency = get_field(cfg, 'lineFrequencyHz', 40);
if ~get_field(cfg, 'lineHarmonics', true) || lineFrequency <= 0, return; end
window = max(8, round(get_field(cfg, 'lineWindowSeconds', 1) * fs));
if numel(x) < window, return; end
centers = lineFrequency:lineFrequency:(fs/2 - lineFrequency/2);
starts = 1:window:(numel(x) - window + 1);
for start = starts
    segment = x(start:start+window-1);
    if any(~isfinite(segment)), continue; end
    time = (0:window-1)' / fs;
    design = zeros(window, 2*numel(centers));
    for h = 1:numel(centers)
        design(:, 2*h-1) = sin(2*pi*centers(h)*time);
        design(:, 2*h) = cos(2*pi*centers(h)*time);
    end
    fitted = design * (design \ segment);
    ratio = var(fitted, 1) / max(var(segment, 1), eps);
    if ratio >= get_field(cfg, 'lineNoiseRatioThreshold', 0.5)
        mask(start:start+window-1) = true;
    end
end
end

function bad = find_bad_channels(mask, signal, cfg)
bad = find(mean(mask, 1) >= get_field(cfg, 'badChannelFraction', 0.5) | ...
    mean(~isfinite(signal), 1) >= get_field(cfg, 'badChannelFraction', 0.5));
bad = bad(:);
end

function summary = summarize_events(events, badChannels, nSamples, nChannels, fs, channelMask)
summary = struct('eventCount', height(events), 'badChannelCount', numel(badChannels), ...
    'channelArtifactPercentage', zeros(1, nChannels), 'countsByType', struct(), ...
    'durationByTypeSeconds', struct());
for channel = 1:nChannels
    summary.channelArtifactPercentage(channel) = 100 * nnz(channelMask(:, channel)) / max(nSamples, 1);
end
types = unique(events.artifactType);
for index = 1:numel(types)
    name = matlab.lang.makeValidName(char(types(index)));
    rows = events.artifactType == types(index);
    summary.countsByType.(name) = nnz(rows);
    summary.durationByTypeSeconds.(name) = sum(events.endSample(rows) - events.startSample(rows) + 1) / fs;
end
end

function history = append_history(data, method, cfg, warnings)
history = data.processingHistory;
entry = struct('operation', "artifact_detection", 'parameters', cfg, ...
    'notes', "Mask-only artifact detection; raw signal retained; method=" + method + ...
    "; warnings=" + strjoin(warnings, " | "));
history(end + 1) = entry;
end

function labels = get_labels(data, nChannels)
if isfield(data, 'channelLabels') && numel(data.channelLabels) >= nChannels
    labels = string(data.channelLabels(:));
else
    labels = "channel_" + string((1:nChannels)');
end
end

function value = get_field(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function runtime = runtime_callbacks(cfg)
runtime.progress = get_field(cfg, 'progressCallback', @(fraction, message)[]); %#ok<NASGU>
runtime.cancel = get_field(cfg, 'cancellationCheck', @()[]);
if ~isa(runtime.progress, 'function_handle'), runtime.progress = @(fraction, message)[]; end
if ~isa(runtime.cancel, 'function_handle'), runtime.cancel = @()[]; end
end

function cfg = strip_runtime_fields(cfg)
fields = intersect(fieldnames(cfg), {'progressCallback', 'cancellationCheck'});
if ~isempty(fields), cfg = rmfield(cfg, fields); end
end

function sigma = robust_scale(values)
values = values(isfinite(values));
if isempty(values)
    sigma = 0;
else
    sigma = 1.4826 * median(abs(values - median(values)));
    if ~(isfinite(sigma) && sigma > 0), sigma = std(values, 0); end
    if ~isfinite(sigma), sigma = 0; end
end
end

function history = append_history_unused(varargin) %#ok<DEFNU>
history = varargin; %#ok<NASGU>
end

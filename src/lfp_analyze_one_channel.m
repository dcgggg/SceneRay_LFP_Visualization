function result = lfp_analyze_one_channel(data, cfg, options)
%LFP_ANALYZE_ONE_CHANNEL Run the standard pipeline for one independent channel.
%   DATA remains samples-by-1; no padding, resampling or cross-channel
%   concatenation is performed. RESULT.status is explicit for each module so
%   one channel can fail without suppressing other channels in a Session.

arguments
    data (1,1) struct
    cfg (1,1) struct
    options.ComputeSpecparam (1,1) logical = true
    options.ComputeBandPower (1,1) logical = true
end
data = standardize_data(data);
result = struct('artifactResult', struct(), 'cleanData', struct(), 'psdResult', struct(), ...
    'modelResult', struct([]), 'bandResult', struct(), 'moduleStatus', struct(), ...
    'warnings', strings(0,1), 'status', "running");
try
    [result.cleanData, result.artifactResult] = detectAndHandleArtifacts(data, cfg.artifact);
    result.moduleStatus.artifact = "ok";
    result.psdResult = computeLfpPsd(result.cleanData, result.artifactResult, cfg.psd);
    result.moduleStatus.psd = "ok";
catch exception
    result.status = "failed"; result.moduleStatus.artifact = get_status(result.moduleStatus, 'artifact', "failed");
    result.moduleStatus.psd = "failed"; result.warnings(end+1,1) = "PSD: " + string(exception.message); return;
end
if options.ComputeSpecparam
    try
        result.modelResult = parameterizePowerSpectrum(result.psdResult.frequencyHz, result.psdResult.psd, cfg.fooof);
        result.moduleStatus.specparam = "ok";
    catch exception
        result.moduleStatus.specparam = "failed"; result.warnings(end+1,1) = "specparam: " + string(exception.message);
    end
else
    result.moduleStatus.specparam = "not_requested";
end
if options.ComputeBandPower
    try
        % Ordinary band power only requires a valid PSD. A failed specparam
        % result therefore does not prevent total/relative band metrics.
        result.bandResult = computeBandPower(result.psdResult, result.modelResult, cfg.bands);
        result.moduleStatus.band_power = "ok";
    catch exception
        result.moduleStatus.band_power = "failed"; result.warnings(end+1,1) = "band power: " + string(exception.message);
    end
else
    result.moduleStatus.band_power = "not_requested";
end
states = string(struct2cell(result.moduleStatus));
if any(states == "failed"), result.status = "partial_failure"; else, result.status = "ok"; end
end

function value = get_status(s, name, fallback)
if isfield(s, name), value = s.(name); else, value = fallback; end
end

function data = standardize_data(data)
data.time = double(data.time(:)); data.signal = double(data.signal);
if ~isfield(data, 'channelLabels') || numel(data.channelLabels) ~= size(data.signal, 2), data.channelLabels = "channel_1"; end
if ~isfield(data, 'units') || isempty(data.units), data.units = "unknown"; end
if ~isfield(data, 'metadata') || ~isstruct(data.metadata), data.metadata = struct(); end
if ~isfield(data, 'processingHistory') || isempty(data.processingHistory)
    data.processingHistory = struct('operation', "import", 'parameters', struct(), 'notes', "Independent channel analysis input.");
end
end

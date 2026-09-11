function [data, channel, session] = lfp_project_get_channel_data(project, sessionId, channelId)
%LFP_PROJECT_GET_CHANNEL_DATA Load one channel from the project cache.
%   The project root plus Session/Channel metadata determine the cache path;
%   MATLAB's current folder is never consulted. The returned signal is an
%   N-by-1 double and metadata records the resolved source path.

arguments
    project (1,1) struct
    sessionId (1,1) string
    channelId (1,1) string
end
[session, ~] = lfp_project_find_session(project, sessionId);
if isempty(session), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
if isempty(session.channels), error('LFP:ChannelNotFound', 'Session has no channels: %s', sessionId); end
index = find(string({session.channels.channel_id}) == channelId, 1);
if isempty(index), error('LFP:ChannelNotFound', 'Channel ID not found: %s', channelId); end
channel = session.channels(index);

[cachePath, cacheRelative, referenceState] = resolve_cache_reference(project, session, channel, channelId);
if referenceState == "missing_reference"
    data = load_legacy_session_channel(project, session, channel, index, channelId);
    return;
end
if ~isfile(cachePath)
    error('LFP:ChannelCacheMissing', 'Channel cache file does not exist. Session=%s Channel=%s Path=%s', ...
        sessionId, channelId, cachePath);
end
try
    loaded = load(cachePath, 'payload');
catch exception
    error('LFP:ChannelCacheReadFailed', 'Cannot read channel cache. Session=%s Channel=%s Path=%s Cause=%s', ...
        sessionId, channelId, cachePath, exception.message);
end
if ~isfield(loaded, 'payload') || ~isstruct(loaded.payload)
    error('LFP:ChannelCacheVariableMissing', 'Channel cache payload variable is missing. Session=%s Channel=%s Path=%s', ...
        sessionId, channelId, cachePath);
end
payload = loaded.payload;
cacheVersion = string(get_field(payload, 'cache_version', '1'));
if cacheVersion ~= "1"
    error('LFP:ChannelCacheVersionUnsupported', 'Unsupported channel cache version %s. Session=%s Channel=%s Path=%s', ...
        cacheVersion, sessionId, channelId, cachePath);
end
if ~isfield(payload, 'time') || ~isfield(payload, 'signal')
    error('LFP:ChannelCacheVariableMissing', 'Channel cache must contain time and signal. Session=%s Channel=%s Path=%s', ...
        sessionId, channelId, cachePath);
end
if isfield(payload, 'channel') && isstruct(payload.channel) && isfield(payload.channel, 'channel_id') && ...
        string(payload.channel.channel_id) ~= channelId
    error('LFP:ChannelCacheChannelMismatch', 'Channel cache ID does not match requested channel. Session=%s Channel=%s Path=%s', ...
        sessionId, channelId, cachePath);
end
rawTime = payload.time;
rawSignal = payload.signal;
if ~isnumeric(rawTime) || ~isvector(rawTime) || ~isnumeric(rawSignal) || ~isvector(rawSignal)
    error('LFP:ChannelCacheDimension', 'Channel cache time/signal must each be a numeric vector. Session=%s Channel=%s Path=%s', ...
        sessionId, channelId, cachePath);
end
t = double(rawTime(:)); y = double(rawSignal(:));
if numel(t) ~= numel(y)
    error('LFP:ChannelCacheDimension', 'Channel cache time/signal lengths differ (%d vs %d). Session=%s Channel=%s Path=%s', ...
        numel(t), numel(y), sessionId, channelId, cachePath);
end
if any(~isfinite(t)) || any(diff(t) < 0)
    error('LFP:ChannelCacheTime', 'Channel cache time is not finite and monotonic. Session=%s Channel=%s Path=%s', ...
        sessionId, channelId, cachePath);
end
if any(isinf(y))
    error('LFP:ChannelCacheSignal', 'Channel cache signal contains Inf. Session=%s Channel=%s Path=%s', ...
        sessionId, channelId, cachePath);
end
units = string(get_field(channel, 'unit', get_field(payload, 'units', 'unknown')));
fs = double(get_field(channel, 'sampling_rate_hz', get_field(payload, 'fs', NaN)));
if ~isscalar(fs) || ~isfinite(fs) || fs <= 0
    error('LFP:ChannelCacheMetadata', 'Channel cache has no valid sampling rate. Session=%s Channel=%s Path=%s', ...
        sessionId, channelId, cachePath);
end
metadata = get_field(payload, 'metadata', struct());
if ~isstruct(metadata), metadata = struct(); end
metadata.channel_id = channelId;
metadata.cache_relative_path = cacheRelative;
metadata.cache_absolute_path = string(cachePath);
metadata.cache_version = cacheVersion;
metadata.cache_source = "channel_cache";
metadata.data_revision = string(get_field(channel, 'data_revision', get_field(payload, 'data_version', "")));
metadata.data_version = metadata.data_revision;
if isfield(channel, 'source_metadata') && isstruct(channel.source_metadata), metadata.channel = channel.source_metadata; end
data = struct('time', t, 'signal', y, 'fs', fs, ...
    'channelLabels', string(get_field(channel, 'original_label', channelId)), ...
    'units', units, 'metadata', metadata, 'processingHistory', struct([]));
end

function [path, relativePath, state] = resolve_cache_reference(project, session, channel, channelId)
% Prefer the channel index, but recover a valid reference recorded by the
% older data_ref index when a rename left the channel path stale.
relativeCandidates = strings(0,1);
primary = string(get_field(channel, 'cache_relative_path', ""));
if strlength(primary) > 0, relativeCandidates(end+1,1) = primary; end
for k = 1:numel(session.data_refs)
    ref = session.data_refs(k);
    if ~isfield(ref, 'channel_ids') || isempty(ref.channel_ids), continue; end
    idx = find(string(ref.channel_ids(:)) == channelId, 1);
    if ~isempty(idx) && isfield(ref, 'cache_relative_paths') && numel(ref.cache_relative_paths) >= idx
        candidate = string(ref.cache_relative_paths(idx));
        if strlength(candidate) > 0 && ~any(relativeCandidates == candidate)
            relativeCandidates(end+1,1) = candidate; %#ok<AGROW>
        end
    end
end
if isempty(relativeCandidates)
    path = ""; relativePath = ""; state = "missing_reference"; return;
end
root = string(project.rootPath);
for k = 1:numel(relativeCandidates)
    candidatePath = fullfile(root, relativeCandidates(k));
    if isfile(candidatePath)
        path = candidatePath; relativePath = relativeCandidates(k); state = "channel_reference"; return;
    end
end
% Keep the primary path in the error when every candidate is missing. This
% preserves the actionable reference that the index currently contains.
relativePath = relativeCandidates(1);
path = fullfile(root, relativePath); state = "channel_reference";
end

function data = load_legacy_session_channel(project, session, channel, index, channelId)
if isempty(session.data_refs) || ~isfield(session.data_refs(1), 'relative_path') || ...
        strlength(string(session.data_refs(1).relative_path)) == 0
    error('LFP:ChannelCacheReferenceMissing', 'No channel cache reference exists. Session=%s Channel=%s', session.session_id, channelId);
end
legacyRelative = string(session.data_refs(1).relative_path);
legacyPath = fullfile(string(project.rootPath), legacyRelative);
if ~isfile(legacyPath)
    error('LFP:ChannelCacheMissing', 'Legacy Session cache file does not exist. Session=%s Channel=%s Path=%s', ...
        session.session_id, channelId, legacyPath);
end
try
    loaded = load(legacyPath, 'payload');
catch exception
    error('LFP:ChannelCacheReadFailed', 'Cannot read legacy Session cache. Session=%s Channel=%s Path=%s Cause=%s', ...
        session.session_id, channelId, legacyPath, exception.message);
end
if ~isfield(loaded,'payload') || ~isstruct(loaded.payload) || ~isfield(loaded.payload,'data') || ~isstruct(loaded.payload.data)
    error('LFP:ChannelCacheVariableMissing', 'Legacy Session cache payload is invalid. Session=%s Channel=%s Path=%s', ...
        session.session_id, channelId, legacyPath);
end
sessionData = loaded.payload.data;
if ~isfield(sessionData, 'signal') || ~isnumeric(sessionData.signal) || ndims(sessionData.signal) ~= 2
    error('LFP:ChannelCacheDimension', 'Legacy Session signal is not a 2-D numeric matrix. Session=%s Channel=%s Path=%s', ...
        session.session_id, channelId, legacyPath);
end
sourceIndex = index;
ref = session.data_refs(1);
if isfield(ref,'channel_ids') && ~isempty(ref.channel_ids)
    mapped = find(string(ref.channel_ids(:)) == channelId, 1); if ~isempty(mapped), sourceIndex = mapped; end
end
if sourceIndex == index && isfield(ref,'channel_labels') && ~isempty(ref.channel_labels)
    mapped = find(string(ref.channel_labels(:)) == string(channel.original_label), 1); if ~isempty(mapped), sourceIndex = mapped; end
end
if sourceIndex == index && isfield(sessionData,'channelLabels')
    mapped = find(string(sessionData.channelLabels(:)) == string(channel.original_label), 1); if ~isempty(mapped), sourceIndex = mapped; end
end
if sourceIndex > size(sessionData.signal, 2)
    error('LFP:ChannelCacheDimension', 'Legacy Session cache has no column for channel. Session=%s Channel=%s Path=%s', ...
        session.session_id, channelId, legacyPath);
end
data = sessionData;
data.signal = double(sessionData.signal(:, sourceIndex));
if ~isfield(data,'time') || ~isnumeric(data.time) || ~isvector(data.time) || numel(data.time) ~= size(sessionData.signal,1)
    error('LFP:ChannelCacheDimension', 'Legacy Session time does not match signal rows. Session=%s Channel=%s Path=%s', ...
        session.session_id, channelId, legacyPath);
end
data.time = double(data.time(:));
if any(~isfinite(data.time)) || any(diff(data.time) < 0)
    error('LFP:ChannelCacheTime', 'Legacy Session time is not finite and monotonic. Session=%s Channel=%s Path=%s', ...
        session.session_id, channelId, legacyPath);
end
legacyFs = double(get_field(data, 'fs', get_field(channel, 'sampling_rate_hz', get_field(ref, 'fs', NaN))));
if ~isscalar(legacyFs) || ~isfinite(legacyFs) || legacyFs <= 0
    error('LFP:ChannelCacheMetadata', 'Legacy Session cache has no valid sampling rate. Session=%s Channel=%s Path=%s', ...
        session.session_id, channelId, legacyPath);
end
data.fs = legacyFs;
data.channelLabels = string(get_field(channel, 'original_label', channelId));
if ~isfield(data, 'metadata') || ~isstruct(data.metadata), data.metadata = struct(); end
data.metadata.channel_id = channelId;
data.metadata.cache_relative_path = legacyRelative;
data.metadata.cache_absolute_path = legacyPath;
data.metadata.cache_source = "legacy_session";
data.metadata.data_version = string(get_field(channel, 'data_revision', get_field(session, 'data_version', "")));
data.metadata.data_revision = data.metadata.data_version;
end

function value = get_field(source, name, fallback)
if isstruct(source) && isfield(source, name) && ~isempty(source.(name)), value = source.(name); else, value = fallback; end
end

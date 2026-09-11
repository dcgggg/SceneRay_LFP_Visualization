function [data, channel, session] = lfp_project_get_channel_data(project, sessionId, channelId)
%LFP_PROJECT_GET_CHANNEL_DATA Load one channel without aligning other channels.
%   Missing/corrupt per-channel caches are reported explicitly. Legacy
%   Session files remain readable through a validated matrix-column fallback.

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
if isfield(channel, 'cache_relative_path') && strlength(string(channel.cache_relative_path)) > 0
    path = fullfile(string(project.rootPath), string(channel.cache_relative_path));
    if ~isfile(path), error('LFP:ChannelCacheMissing', 'Channel cache is missing: %s', path); end
    try
        loaded = load(path, 'payload');
    catch exception
        error('LFP:ChannelCacheCorrupt', 'Cannot load channel cache %s: %s', path, exception.message);
    end
    if ~isfield(loaded, 'payload') || ~isstruct(loaded.payload) || ...
            ~isfield(loaded.payload, 'time') || ~isfield(loaded.payload, 'signal')
        error('LFP:ChannelCacheCorrupt', 'Channel cache payload is invalid: %s', path);
    end
    t = double(loaded.payload.time(:)); y = double(loaded.payload.signal(:));
    if numel(t) ~= numel(y) || any(~isfinite(t)) || any(diff(t) < 0) || any(isinf(y))
        error('LFP:ChannelCacheCorrupt', 'Channel cache has invalid time/signal values: %s', path);
    end
    data = struct('time', t, 'signal', y, 'fs', double(get_field(channel, 'sampling_rate_hz', get_field(loaded.payload, 'fs', NaN))), ...
        'channelLabels', string(get_field(channel, 'original_label', channelId)), 'units', string(get_field(channel, 'unit', 'unknown')), ...
        'metadata', get_field(loaded.payload, 'metadata', struct()), 'processingHistory', struct([]));
    if isfield(channel, 'source_metadata') && isstruct(channel.source_metadata)
        data.metadata.channel = channel.source_metadata;
    end
    return;
end
% Legacy fallback. It intentionally does not invent a time axis when the
% canonical session payload is malformed.
[sessionData, ~] = lfp_project_get_session_data(project, sessionId);
if index > size(sessionData.signal, 2), error('LFP:ChannelCacheCorrupt', 'Legacy data has no column for channel %s.', channelId); end
data = sessionData;
data.signal = double(sessionData.signal(:, index));
data.channelLabels = string(get_field(channel, 'original_label', channelId));
if isfield(sessionData, 'metadata') && isstruct(sessionData.metadata)
    sessionData.metadata.channel_id = channelId;
end
data.metadata = get_field(sessionData, 'metadata', struct());
end

function value = get_field(source, name, fallback)
if isstruct(source) && isfield(source, name) && ~isempty(source.(name)), value = source.(name); else, value = fallback; end
end

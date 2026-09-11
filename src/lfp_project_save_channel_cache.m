function relativePath = lfp_project_save_channel_cache(project, session, channel, time, signal, metadata)
%LFP_PROJECT_SAVE_CHANNEL_CACHE Atomically persist one channel's raw samples.
%   The cache is independent from the source CSV and from other channels, so
%   channels with different lengths or time axes never need padding or
%   resampling. RELATIVEPATH is portable within the project root.

arguments
    project (1,1) struct
    session (1,1) struct
    channel (1,1) struct
    time (:,1) double
    signal (:,1) double
    metadata (1,1) struct = struct()
end
if numel(time) ~= numel(signal), error('LFP:ChannelCacheShape', 'time and signal must have equal length.'); end
if any(~isfinite(time)) || any(diff(time) < 0), error('LFP:ChannelCacheTime', 'Channel time must be finite and monotonic.'); end
if any(isinf(signal)), error('LFP:ChannelCacheSignal', 'Channel signal cannot contain Inf.'); end
if isfield(session, 'folder_relative_path') && strlength(string(session.folder_relative_path)) > 0
    relativeFolder = fullfile(string(session.folder_relative_path), 'data', 'channels');
else
    relativeFolder = fullfile('data', 'channels');
end
relativePath = fullfile(relativeFolder, string(channel.channel_id) + '_r' + string(get_field(channel, 'data_revision', '1')) + '.mat');
absolutePath = fullfile(string(project.rootPath), relativePath);
if ~isfolder(fileparts(absolutePath)), mkdir(fileparts(absolutePath)); end
payload = struct('time', time, 'signal', signal, 'fs', double(get_field(channel, 'sampling_rate_hz', NaN)), ...
    'channel', channel, 'metadata', metadata, 'saved_at', string(datestr(now, 31)), 'cache_version', '1'); %#ok<NASGU>
tempPath = absolutePath + '.tmp_' + lfp_make_id('channel');
cleanup = onCleanup(@() delete_if_present(tempPath)); %#ok<NASGU>
save(tempPath, 'payload', '-v7');
if ~movefile(tempPath, absolutePath, 'f'), error('LFP:ChannelCacheWriteFailed', 'Cannot replace channel cache: %s', absolutePath); end
end

function value = get_field(source, name, fallback)
if isfield(source, name) && ~isempty(source.(name)), value = source.(name); else, value = fallback; end
end
function delete_if_present(path)
if isfile(path), delete(path); end
end

function [project, report] = lfp_project_repair_channel_caches(project, sessionId, channelIds, options)
%LFP_PROJECT_REPAIR_CHANNEL_CACHES Validate and repair indexed raw caches.
%   The function never edits source CSV files and never invents samples. It
%   first validates an indexed/per-import cache, then falls back to a
%   canonical Session payload when that payload can be mapped unambiguously.
%   REPORT contains one row per requested stable channel ID.

arguments
    project (1,1) struct
    sessionId (1,1) string
    channelIds string = strings(0,1)
    options.Save (1,1) logical = true
end

[session, ~, subjectIndex, sessionIndex] = lfp_project_find_session(project, sessionId);
if isempty(session), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
if isempty(channelIds), channelIds = string({session.channels.channel_id})'; end
channelIds = unique(string(channelIds(:)), 'stable');
report = repmat(struct('channel_id', "", 'status', "", 'cache_relative_path', "", ...
    'message', "", 'error_identifier', ""), numel(channelIds), 1);
changed = false;

for row = 1:numel(channelIds)
    id = channelIds(row);
    report(row).channel_id = id;
    index = find(string({session.channels.channel_id}) == id, 1);
    if isempty(index)
        report(row).status = "not_found";
        report(row).message = "Channel ID is not present in the Session.";
        report(row).error_identifier = "LFP:ChannelNotFound";
        continue;
    end
    channel = session.channels(index);
    oldPath = string(get_field(channel, 'cache_relative_path', ""));
    try
        [loaded, ~, ~] = lfp_project_get_channel_data(project, sessionId, id);
        resolvedPath = string(get_field(loaded.metadata, 'cache_relative_path', oldPath));
        if string(get_field(loaded.metadata, 'cache_source', "channel_cache")) == "legacy_session"
            error('LFP:LegacySessionOnly', 'Only a legacy Session cache is available; a per-channel cache will be rebuilt.');
        end
        if strlength(resolvedPath) > 0 && oldPath ~= resolvedPath
            channel.cache_relative_path = resolvedPath;
            session.channels(index) = channel;
            session = update_ref_cache_path(session, id, resolvedPath);
            changed = true;
            report(row).status = "repaired_reference";
            report(row).message = "A valid cache was found through a legacy reference; the channel index was repaired.";
        else
            report(row).status = "valid";
            report(row).message = "Indexed channel cache is valid.";
        end
        report(row).cache_relative_path = resolvedPath;
        continue;
    catch exception
        firstError = exception;
    end

    try
        [time, signal, sourceMetadata, canonicalRelative] = read_canonical_channel(project, session, channel, id);
        cacheRelative = lfp_project_save_channel_cache(project, session, channel, time, signal, sourceMetadata);
        channel.cache_relative_path = cacheRelative;
        session.channels(index) = channel;
        session = update_ref_cache_path(session, id, cacheRelative);
        changed = true;
        report(row).status = "rebuilt";
        report(row).cache_relative_path = cacheRelative;
        report(row).message = "Rebuilt from the archived canonical Session cache: " + canonicalRelative;
    catch exception
        canonicalError = exception;
        try
            [time, signal, sourceMetadata, sourceRelative] = read_archived_source_channel(project, session, channel, id);
            cacheRelative = lfp_project_save_channel_cache(project, session, channel, time, signal, sourceMetadata);
            channel.cache_relative_path = cacheRelative;
            session.channels(index) = channel;
            session = update_ref_cache_path(session, id, cacheRelative);
            changed = true;
            report(row).status = "rebuilt_from_source";
            report(row).cache_relative_path = cacheRelative;
            report(row).message = "Rebuilt from the archived source CSV: " + sourceRelative;
        catch sourceException
            report(row).status = "unavailable";
            report(row).cache_relative_path = oldPath;
            report(row).error_identifier = string(firstError.identifier);
            report(row).message = "Indexed cache: " + string(firstError.message) + " | Canonical: " + string(canonicalError.message) + " | Archived source: " + string(sourceException.message);
        end
    end
end

if changed
    project.subjects(subjectIndex).sessions(sessionIndex) = session;
    lfp_project_write_channel_manifest(project, session);
    if isfield(session, 'folder_relative_path') && strlength(string(session.folder_relative_path)) > 0
        write_session_metadata(fullfile(string(project.rootPath), session.folder_relative_path), session);
    end
    if options.Save, lfp_save_project(project); end
end
end

function session = update_ref_cache_path(session, channelId, relativePath)
for k = 1:numel(session.data_refs)
    ref = session.data_refs(k);
    if ~isfield(ref, 'channel_ids') || isempty(ref.channel_ids), continue; end
    idx = find(string(ref.channel_ids(:)) == channelId, 1);
    if isempty(idx), continue; end
    paths = string(get_field(ref, 'cache_relative_paths', strings(0,1)));
    if numel(paths) < numel(ref.channel_ids), paths(end+1:numel(ref.channel_ids),1) = ""; end
    paths(idx) = relativePath;
    ref.cache_relative_paths = paths;
    session.data_refs(k) = ref;
end
end

function [time, signal, metadata, relativePath] = read_canonical_channel(project, session, channel, channelId)
time = []; signal = []; metadata = struct(); relativePath = "";
lastError = [];
for k = 1:numel(session.data_refs)
    ref = session.data_refs(k);
    candidate = string(get_field(ref, 'relative_path', ""));
    if strlength(candidate) == 0 || ~isfile(fullfile(string(project.rootPath), candidate)), continue; end
    try
        loaded = load(fullfile(string(project.rootPath), candidate), 'payload');
        if ~isfield(loaded, 'payload') || ~isstruct(loaded.payload) || ...
                ~isfield(loaded.payload, 'data') || ~isstruct(loaded.payload.data)
            error('LFP:ChannelCacheVariableMissing', 'Canonical payload has no data field: %s', candidate);
        end
        sessionData = loaded.payload.data;
        if ~isfield(sessionData, 'signal') || ~isnumeric(sessionData.signal) || ndims(sessionData.signal) ~= 2
            error('LFP:ChannelCacheDimension', 'Canonical signal is not a 2-D numeric matrix: %s', candidate);
        end
        column = map_column(ref, sessionData, channel, channelId, size(sessionData.signal, 2));
        if isempty(column), error('LFP:ChannelCacheChannelMismatch', 'Canonical cache cannot map channel %s: %s', channelId, candidate); end
        n = size(sessionData.signal, 1);
        if isfield(sessionData, 'time') && isnumeric(sessionData.time) && isvector(sessionData.time) && numel(sessionData.time) == n
            time = double(sessionData.time(:));
        else
            fs = double(get_field(channel, 'sampling_rate_hz', get_field(ref, 'fs', NaN)));
            if ~isfinite(fs) || fs <= 0, error('LFP:ChannelCacheTime', 'Canonical cache has no usable time or sampling rate: %s', candidate); end
            time = (0:n-1)' / fs;
        end
        signal = double(sessionData.signal(:, column));
        if any(~isfinite(time)) || any(diff(time) < 0), error('LFP:ChannelCacheTime', 'Canonical cache time is invalid: %s', candidate); end
        if any(isinf(signal)), error('LFP:ChannelCacheSignal', 'Canonical cache signal contains Inf: %s', candidate); end
        metadata = get_field(sessionData, 'metadata', struct());
        if ~isstruct(metadata), metadata = struct(); end
        metadata.rebuilt_from = candidate;
        metadata.channel_id = channelId;
        relativePath = candidate;
        return;
    catch exception
        lastError = exception;
    end
end
if ~isempty(lastError), rethrow(lastError); end
error('LFP:ChannelCacheReferenceMissing', 'No archived canonical Session cache is available for channel %s.', channelId);
end

function [time, signal, metadata, relativePath] = read_archived_source_channel(project, session, channel, channelId)
% Re-import only when the user explicitly requests cache repair. Mapping is
% taken from the saved import configuration and stable source column.
time=[];signal=[];metadata=struct();relativePath="";lastError=[];
for k=1:numel(session.data_refs)
    ref=session.data_refs(k);ids=get_field(ref,'channel_ids',strings(0,1));
    if ~any(string(ids(:))==channelId),continue;end
    relativePath=string(get_field(ref,'project_copy_relative_path',""));
    if strlength(relativePath)==0 || ~isfile(fullfile(string(project.rootPath),relativePath)),continue;end
    settings=get_field(ref,'import_config',struct());
    if ~isstruct(settings) || isempty(fieldnames(settings)),error('LFP:ArchivedSourceMappingMissing','Archived source has no saved import configuration.');end
    try
        args=namedargs2cell(settings);
        [sourceData,~]=lfp_import_csv_configured(fullfile(string(project.rootPath),relativePath),args{:});
        column=map_imported_column(sourceData,ref,channel,channelId,size(sourceData.signal,2));
        if isempty(column),error('LFP:ChannelCacheChannelMismatch','Saved import mapping cannot locate channel %s.',channelId);end
        time=double(sourceData.time(:));signal=double(sourceData.signal(:,column));
        metadata=get_field(sourceData,'metadata',struct());if ~isstruct(metadata),metadata=struct();end
        metadata.rebuilt_from=relativePath;metadata.channel_id=channelId;return;
    catch exception
        lastError=exception;
    end
end
if ~isempty(lastError),rethrow(lastError);end
error('LFP:ArchivedSourceMissing','No archived source CSV is available for channel %s.',channelId);
end

function column=map_imported_column(sourceData,ref,channel,channelId,columnCount)
column=[];sourceColumn=double(get_field(channel,'source_column',NaN));
if isfield(sourceData,'metadata')&&isstruct(sourceData.metadata)&&isfield(sourceData.metadata,'signalColumns')&&isfinite(sourceColumn)
    mapped=find(double(sourceData.metadata.signalColumns(:))==sourceColumn,1);if ~isempty(mapped),column=mapped;end
end
if isempty(column)&&isfield(sourceData,'channelLabels')&&~isempty(sourceData.channelLabels)
    mapped=find(string(sourceData.channelLabels(:))==string(get_field(channel,'original_label',channelId)),1);if ~isempty(mapped),column=mapped;end
end
if isempty(column)
    ids=get_field(ref,'channel_ids',strings(0,1));mapped=find(string(ids(:))==channelId,1);
    if ~isempty(mapped)&&numel(ids)==columnCount,column=mapped;end
end
if isempty(column)||column<1||column>columnCount,column=[];end
end

function column = map_column(ref, data, channel, channelId, columnCount)
column = [];
if isfield(ref, 'channel_ids') && ~isempty(ref.channel_ids)
    column = find(string(ref.channel_ids(:)) == channelId, 1);
end
if isempty(column) && isfield(ref, 'channel_labels') && ~isempty(ref.channel_labels)
    column = find(string(ref.channel_labels(:)) == string(get_field(channel, 'original_label', channelId)), 1);
end
if isempty(column) && isfield(data, 'channelLabels') && ~isempty(data.channelLabels)
    column = find(string(data.channelLabels(:)) == string(get_field(channel, 'original_label', channelId)), 1);
end
if isempty(column)
    sourceColumn = double(get_field(channel, 'source_column', NaN));
    refIds = get_field(ref, 'channel_ids', strings(0,1));
    if isfinite(sourceColumn) && sourceColumn >= 1 && sourceColumn <= columnCount && ...
            (isempty(refIds) || numel(refIds) == columnCount)
        column = round(sourceColumn);
    end
end
if isempty(column) || column < 1 || column > columnCount, column = []; end
end

function value = get_field(source, name, fallback)
if isstruct(source) && isfield(source, name) && ~isempty(source.(name)), value = source.(name); else, value = fallback; end
end

function write_session_metadata(folder, session)
if ~isfolder(folder), mkdir(folder); end
sessionMetadata = session; %#ok<NASGU>
save(fullfile(folder, 'session.mat'), 'sessionMetadata', '-v7');
end

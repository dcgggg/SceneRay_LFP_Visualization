function [project, report] = lfp_project_remove_channels(project, sessionId, channelIds, options)
%LFP_PROJECT_REMOVE_CHANNELS Remove channels from the active Session index.
%   Shared raw/channel cache files are intentionally retained. Existing
%   AnalysisRuns and comparison plans are marked stale through the report;
%   callers may decide whether to remove those references explicitly.

arguments
    project (1,1) struct
    sessionId (1,1) string
    channelIds string
    options.Save (1,1) logical = true
    options.LockToken (1,1) struct = struct()
end
lock=options.LockToken; if isempty(fieldnames(lock)), lock=lfp_project_acquire_lock(string(project.rootPath)); cleanupLock=onCleanup(@()lfp_project_release_lock(lock)); end %#ok<NASGU>
channelIds = unique(string(channelIds(:)), 'stable');
[si, ki] = locate_session(project, sessionId);
if isempty(si), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
session = project.subjects(si).sessions(ki);
ids = string({session.channels.channel_id});
mask = ismember(ids, channelIds);
if ~any(mask), error('LFP:ChannelNotFound', 'No requested channel IDs exist in Session %s.', sessionId); end
removed = ids(mask);
session.channels(mask) = [];
session.data_version = string(session.data_version) + "_channels_removed_" + string(datestr(now, 'yyyymmddHHMMSS'));
session.status = 'imported';
project.subjects(si).sessions(ki) = session;
lfp_project_write_channel_manifest(project, session);
% Keep historical run files, but make their active channel set explicit.
for k = 1:numel(project.analysisRuns)
    if string(project.analysisRuns(k).session_id) == sessionId
        project.analysisRuns(k).status = 'stale_channels';
    end
end
affectedComparisons = strings(0,1);
for k = 1:numel(project.comparisons)
    mapping = get_field(project.comparisons(k), 'channel_mapping', struct([]));
    if isempty(mapping), continue; end
    touched = false;
    for m = 1:numel(mapping)
        if isfield(mapping(m),'session_id') && string(mapping(m).session_id) == sessionId && ...
                isfield(mapping(m),'channel_id') && any(removed == string(mapping(m).channel_id))
            touched = true; break;
        end
    end
    if touched
        project.comparisons(k).status = 'stale_channels';
        project.comparisons(k).warnings = [string(get_field(project.comparisons(k),'warnings',strings(0,1))); ...
            "A channel used by this comparison was removed from its Session."];
        affectedComparisons(end+1,1) = string(project.comparisons(k).comparison_id); %#ok<AGROW>
    end
end
report = struct('sessionId', sessionId, 'removedChannelIds', removed, ...
    'cacheFilesRetained', true, 'affectedRunIds', strings(0,1), 'affectedComparisonIds', affectedComparisons, ...
    'warnings', "Existing analysis/comparison references are retained as historical records and marked stale.");
if ~isempty(project.analysisRuns)
    report.affectedRunIds = string({project.analysisRuns(string({project.analysisRuns.session_id}) == sessionId).run_id})';
end
if options.Save, [~, project] = lfp_save_project(project, LockToken=lock); end
end

function [si, ki] = locate_session(project, id)
si = []; ki = [];
for s = 1:numel(project.subjects)
    k = find(string({project.subjects(s).sessions.session_id}) == id, 1);
    if ~isempty(k), si = s; ki = k; return; end
end
end

function value = get_field(source, name, fallback)
if isstruct(source) && isfield(source, name) && ~isempty(source.(name)), value = source.(name); else, value = fallback; end
end

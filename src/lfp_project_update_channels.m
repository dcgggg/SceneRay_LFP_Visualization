function [project, channels] = lfp_project_update_channels(project, sessionId, channelRows, options)
%LFP_PROJECT_UPDATE_CHANNELS Update editable labels without changing IDs.
%   CHANNELROWS may be a table with channel_id and any of display_label,
%   side, region, contacts, reference. Original labels and raw data remain
%   unchanged.

arguments
    project (1,1) struct
    sessionId (1,1) string
    channelRows table
    options.Save (1,1) logical = true
    options.LockToken (1,1) struct = struct()
end
lock=options.LockToken; if isempty(fieldnames(lock)), lock=lfp_project_acquire_lock(string(project.rootPath)); cleanupLock=onCleanup(@()lfp_project_release_lock(lock)); end %#ok<NASGU>
[subjectIndex, sessionIndex] = locate(project, sessionId);
if isempty(subjectIndex), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
if ~ismember('channel_id', channelRows.Properties.VariableNames)
    error('LFP:InvalidChannelTable', 'channelRows must contain channel_id.');
end
channels = project.subjects(subjectIndex).sessions(sessionIndex).channels;
editable = ["display_label" "side" "region" "contacts" "reference" "enabled" "quality_status"];
enabledChanged = false;
for row = 1:height(channelRows)
    index = find(string({channels.channel_id}) == string(channelRows.channel_id(row)), 1);
    if isempty(index), error('LFP:ChannelNotFound', 'Unknown channel ID: %s', string(channelRows.channel_id(row))); end
    for name = editable
        fieldName = char(name);
        if ismember(fieldName, channelRows.Properties.VariableNames)
            value = channelRows.(fieldName)(row);
            if strcmp(fieldName, 'enabled')
                newValue = logical(value); oldValue = true;
                if isfield(channels(index),'enabled'), oldValue = logical(channels(index).enabled); end
                enabledChanged = enabledChanged || (newValue ~= oldValue);
                channels(index).enabled = newValue;
            else
                channels(index).(fieldName) = string(value);
            end
        end
    end
end
project.subjects(subjectIndex).sessions(sessionIndex).channels = channels;
if enabledChanged && isfield(project,'analysisRuns') && ~isempty(project.analysisRuns)
    for runIndex = 1:numel(project.analysisRuns)
        if string(project.analysisRuns(runIndex).session_id) == sessionId
            project.analysisRuns(runIndex).status = "stale_channels";
            if ~isfield(project.analysisRuns(runIndex),'warnings') || isempty(project.analysisRuns(runIndex).warnings)
                project.analysisRuns(runIndex).warnings = "Enabled-channel selection changed after this run.";
            else
                project.analysisRuns(runIndex).warnings(end+1,1) = "Enabled-channel selection changed after this run.";
            end
        end
    end
end
lfp_project_write_channel_manifest(project, project.subjects(subjectIndex).sessions(sessionIndex));
if options.Save, [~, project] = lfp_save_project(project, LockToken=lock); end
end

function [subjectIndex, sessionIndex] = locate(project, sessionId)
subjectIndex = []; sessionIndex = [];
for s = 1:numel(project.subjects)
    match = find(string({project.subjects(s).sessions.session_id}) == sessionId, 1);
    if ~isempty(match), subjectIndex = s; sessionIndex = match; return; end
end
end

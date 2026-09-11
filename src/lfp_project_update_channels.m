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
end
[subjectIndex, sessionIndex] = locate(project, sessionId);
if isempty(subjectIndex), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
if ~ismember('channel_id', channelRows.Properties.VariableNames)
    error('LFP:InvalidChannelTable', 'channelRows must contain channel_id.');
end
channels = project.subjects(subjectIndex).sessions(sessionIndex).channels;
editable = ["display_label" "side" "region" "contacts" "reference"];
for row = 1:height(channelRows)
    index = find(string({channels.channel_id}) == string(channelRows.channel_id(row)), 1);
    if isempty(index), error('LFP:ChannelNotFound', 'Unknown channel ID: %s', string(channelRows.channel_id(row))); end
    for name = editable
        fieldName = char(name);
        if ismember(fieldName, channelRows.Properties.VariableNames)
            channels(index).(fieldName) = string(channelRows.(fieldName)(row));
        end
    end
end
project.subjects(subjectIndex).sessions(sessionIndex).channels = channels;
if options.Save, lfp_save_project(project); end
end

function [subjectIndex, sessionIndex] = locate(project, sessionId)
subjectIndex = []; sessionIndex = [];
for s = 1:numel(project.subjects)
    match = find(string({project.subjects(s).sessions.session_id}) == sessionId, 1);
    if ~isempty(match), subjectIndex = s; sessionIndex = match; return; end
end
end

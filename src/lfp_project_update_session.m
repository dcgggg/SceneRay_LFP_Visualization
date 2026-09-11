function [project, session] = lfp_project_update_session(project, sessionId, updates, options)
%LFP_PROJECT_UPDATE_SESSION Update editable Session metadata by stable ID.

arguments
    project (1,1) struct
    sessionId (1,1) string
    updates (1,1) struct
    options.Save (1,1) logical = true
end
[subjectIndex, sessionIndex] = locate(project, sessionId);
if isempty(subjectIndex), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
for name = ["visit_label" "acquisition_date" "medication_state" "stimulation_state" "repeat_label" "notes"]
    fieldName = char(name);
    if isfield(updates, fieldName), project.subjects(subjectIndex).sessions(sessionIndex).(fieldName) = string(updates.(fieldName)); end
end
session = project.subjects(subjectIndex).sessions(sessionIndex);
if options.Save, lfp_save_project(project); end
end

function [subjectIndex, sessionIndex] = locate(project, sessionId)
subjectIndex = []; sessionIndex = [];
for s = 1:numel(project.subjects)
    match = find(string({project.subjects(s).sessions.session_id}) == sessionId, 1);
    if ~isempty(match), subjectIndex = s; sessionIndex = match; return; end
end
end

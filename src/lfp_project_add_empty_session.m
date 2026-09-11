function [project, session] = lfp_project_add_empty_session(project, subjectId, sessionInfo, options)
%LFP_PROJECT_ADD_EMPTY_SESSION Add Session metadata before data import.
%   This supports the GUI workflow in which a user creates a Session and
%   attaches one synchronized LFP recording later. No source or result file
%   is created until data are attached.

arguments
    project (1,1) struct
    subjectId (1,1) string
    sessionInfo (1,1) struct = struct()
    options.Save (1,1) logical = true
end

subjectIndex = find_subject(project, subjectId);
if isempty(subjectIndex)
    error('LFP:SubjectNotFound', 'Subject ID not found: %s', subjectId);
end
[~, ~, sessionTemplate, ~, ~, ~] = lfp_project_schema();
session = sessionTemplate;
session.session_id = get_string(sessionInfo, 'session_id', lfp_make_id("session"));
session.subject_id = subjectId;
session.visit_label = get_string(sessionInfo, 'visit_label', "");
session.acquisition_date = get_string(sessionInfo, 'acquisition_date', "");
session.medication_state = get_string(sessionInfo, 'medication_state', "");
session.stimulation_state = get_string(sessionInfo, 'stimulation_state', "");
session.repeat_label = get_string(sessionInfo, 'repeat_label', "");
session.notes = get_string(sessionInfo, 'notes', "");
session.status = "no_data";
if session_exists(project, session.session_id)
    error('LFP:DuplicateSession', 'Session ID already exists in this project: %s', session.session_id);
end
project.subjects(subjectIndex).sessions(end + 1) = session;
if options.Save, lfp_save_project(project); end
end

function index = find_subject(project, subjectId)
index = [];
if isfield(project, 'subjects') && ~isempty(project.subjects)
    index = find(string({project.subjects.subject_id}) == subjectId, 1);
end
end

function tf = session_exists(project, sessionId)
tf = false;
for subjectIndex = 1:numel(project.subjects)
    if any(string({project.subjects(subjectIndex).sessions.session_id}) == sessionId)
        tf = true; return;
    end
end
end

function value = get_string(source, name, fallback)
if isfield(source, name) && ~isempty(source.(name)), value = string(source.(name));
else, value = string(fallback); end
end

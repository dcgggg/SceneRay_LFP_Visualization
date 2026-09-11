function [session, subject, subjectIndex, sessionIndex] = lfp_project_find_session(project, sessionId)
%LFP_PROJECT_FIND_SESSION Resolve a Session by stable ID.

arguments
    project (1,1) struct
    sessionId (1,1) string
end
session = []; subject = []; subjectIndex = []; sessionIndex = [];
if ~isfield(project, 'subjects') || isempty(project.subjects), return; end
for s = 1:numel(project.subjects)
    if isempty(project.subjects(s).sessions), continue; end
    index = find(string({project.subjects(s).sessions.session_id}) == sessionId, 1);
    if ~isempty(index)
        subjectIndex = s; sessionIndex = index;
        subject = project.subjects(s); session = subject.sessions(index);
        return;
    end
end
end

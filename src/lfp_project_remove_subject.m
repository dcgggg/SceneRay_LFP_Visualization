function [project, impact] = lfp_project_remove_subject(project, subjectId, options)
%LFP_PROJECT_REMOVE_SUBJECT Remove Subject metadata without deleting files.

arguments
    project (1,1) struct
    subjectId (1,1) string
    options.Save (1,1) logical = true
end
index = find(string({project.subjects.subject_id}) == subjectId, 1);
if isempty(index), error('LFP:SubjectNotFound', 'Subject ID not found: %s', subjectId); end
subject = project.subjects(index);
sessionIds = strings(0,1);
if ~isempty(subject.sessions), sessionIds = string({subject.sessions.session_id})'; end
impact = struct('subjectId', subjectId, 'sessionIds', sessionIds, ...
    'projectDataFilesRetained', true, 'sourceFilesUntouched', true);
project.subjects(index) = [];
if options.Save, lfp_save_project(project); end
end

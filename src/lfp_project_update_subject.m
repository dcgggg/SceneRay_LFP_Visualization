function [project, subject] = lfp_project_update_subject(project, subjectId, updates, options)
%LFP_PROJECT_UPDATE_SUBJECT Update editable Subject metadata by stable ID.

arguments
    project (1,1) struct
    subjectId (1,1) string
    updates (1,1) struct
    options.Save (1,1) logical = true
end
index = find(string({project.subjects.subject_id}) == subjectId, 1);
if isempty(index), error('LFP:SubjectNotFound', 'Subject ID not found: %s', subjectId); end
for name = ["display_name" "group" "notes"]
    fieldName = char(name);
    if isfield(updates, fieldName), project.subjects(index).(fieldName) = string(updates.(fieldName)); end
end
subject = project.subjects(index);
if options.Save, lfp_save_project(project); end
end

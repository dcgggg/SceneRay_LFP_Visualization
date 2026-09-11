function [project, subject] = lfp_project_add_subject(project, subjectInfo, options)
%LFP_PROJECT_ADD_SUBJECT Add a Subject with a stable ID.

arguments
    project (1,1) struct
    subjectInfo (1,1) struct
    options.Save (1,1) logical = true
end
[~, template, ~, ~, ~, ~] = lfp_project_schema();
subject = template;
subject.subject_id = get_string(subjectInfo, 'subject_id', lfp_make_id("subject"));
subject.display_name = get_string(subjectInfo, 'display_name', subject.subject_id);
subject.group = get_string(subjectInfo, 'group', "");
subject.notes = get_string(subjectInfo, 'notes', "");
subject.sessions = template.sessions;
if any(string({project.subjects.subject_id}) == subject.subject_id)
    error('LFP:DuplicateSubject', 'Subject ID already exists: %s', subject.subject_id);
end
project.subjects(end + 1) = subject;
if options.Save, lfp_save_project(project); end
end

function value = get_string(s, name, fallback)
if isfield(s, name) && ~isempty(s.(name)), value = string(s.(name)); else, value = string(fallback); end
end

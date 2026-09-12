function [project, subject] = lfp_project_add_subject(project, subjectInfo, options)
%LFP_PROJECT_ADD_SUBJECT Add a Subject with a stable ID.

arguments
    project (1,1) struct
    subjectInfo (1,1) struct
    options.Save (1,1) logical = true
    options.LockToken (1,1) struct = struct()
end
lock=options.LockToken; if isempty(fieldnames(lock)), lock=lfp_project_acquire_lock(string(project.rootPath)); cleanupLock=onCleanup(@()lfp_project_release_lock(lock)); end %#ok<NASGU>
[~, template, ~, ~, ~, ~] = lfp_project_schema();
subject = template;
subject.subject_id = get_string(subjectInfo, 'subject_id', lfp_make_id("subject"));
subject.display_name = get_string(subjectInfo, 'display_name', subject.subject_id);
subject.group = get_string(subjectInfo, 'group', "");
subject.notes = get_string(subjectInfo, 'notes', "");
subject.folder_relative_path = "";
subject.sessions = template.sessions;
transaction = lfp_project_begin_transaction(string(project.rootPath), "add_subject");
if ~isempty(project.subjects) && any(string({project.subjects.subject_id}) == subject.subject_id)
    error('LFP:DuplicateSubject', 'Subject ID already exists: %s', subject.subject_id);
end
project.subjects(end + 1) = subject;
if use_nested_layout(project)
    folderName = lfp_project_folder_name(subject.display_name, subject.subject_id, "被试");
    subject.folder_relative_path = fullfile(string(project.paths.subjects), folderName);
    if any(string({project.subjects(1:end-1).folder_relative_path}) == subject.folder_relative_path)
        error('LFP:DuplicateSubjectFolder', '被试文件夹名称已存在：%s。', subject.folder_relative_path);
    end
    folder = fullfile(string(project.rootPath), subject.folder_relative_path);
    if isfolder(folder) || isfile(folder), error('LFP:SubjectFolderExists', '被试文件夹已存在：%s。', folder); end
    if ~mkdir(folder), error('LFP:SubjectFolderCreateFailed', '无法创建被试文件夹：%s。', folder); end
    project.subjects(end).folder_relative_path = subject.folder_relative_path;
    write_subject_metadata(folder, project.subjects(end));
end
if options.Save, [~, project] = lfp_save_project(project, LockToken=lock); end
lfp_project_end_transaction(transaction, "committed");
end

function tf = use_nested_layout(project)
tf = isfield(project, 'storage_mode') && string(project.storage_mode) == "subject_session";
end

function value = get_string(s, name, fallback)
if isfield(s, name) && ~isempty(s.(name)), value = string(s.(name)); else, value = string(fallback); end
end

function write_subject_metadata(folder, subject)
subjectMetadata = subject; %#ok<NASGU>
save(fullfile(folder, 'subject.mat'), 'subjectMetadata', '-v7');
end

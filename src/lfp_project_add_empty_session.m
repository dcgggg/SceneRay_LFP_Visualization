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
    options.LockToken (1,1) struct = struct()
end
lock=options.LockToken; if isempty(fieldnames(lock)), lock=lfp_project_acquire_lock(string(project.rootPath)); cleanupLock=onCleanup(@()lfp_project_release_lock(lock)); end %#ok<NASGU>

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
% Keep an empty Session override until the user runs/saves analysis.  The GUI
% resolves this as an inherited copy of project.defaultConfig, so later edits
% to the project template still affect untouched Sessions without modifying
% an explicit Session-specific snapshot.
session.analysis_config = struct();
session.folder_relative_path = "";
session.status = "no_data";
transaction = lfp_project_begin_transaction(string(project.rootPath), "add_empty_session");
if session_exists(project, session.session_id)
    error('LFP:DuplicateSession', 'Session ID already exists in this project: %s', session.session_id);
end
project.subjects(subjectIndex).sessions(end + 1) = session;
if isfield(project, 'storage_mode') && string(project.storage_mode) == "subject_session"
    subject = project.subjects(subjectIndex);
    if strlength(string(subject.folder_relative_path)) == 0
        subjectFolder = lfp_project_folder_name(subject.display_name, subject.subject_id, "被试");
        subject.folder_relative_path = fullfile(string(project.paths.subjects), subjectFolder);
        project.subjects(subjectIndex).folder_relative_path = subject.folder_relative_path;
    end
    folderLabel = session.visit_label;
    if strlength(folderLabel) == 0, folderLabel = session.session_id; end
    folderName = lfp_project_folder_name(folderLabel, session.session_id, "Session");
    session.folder_relative_path = fullfile(subject.folder_relative_path, folderName);
    if ~isempty(project.subjects(subjectIndex).sessions(1:end-1)) && ...
            any(string({project.subjects(subjectIndex).sessions(1:end-1).folder_relative_path}) == session.folder_relative_path)
        error('LFP:DuplicateSessionFolder', 'Session文件夹名称已存在：%s。', session.folder_relative_path);
    end
    subjectFolder = fullfile(string(project.rootPath), subject.folder_relative_path);
    sessionFolder = fullfile(string(project.rootPath), session.folder_relative_path);
    if ~isfolder(subjectFolder) && ~mkdir(subjectFolder), error('LFP:SubjectFolderCreateFailed', '无法创建被试文件夹：%s。', subjectFolder); end
    if isfolder(sessionFolder) || isfile(sessionFolder), error('LFP:SessionFolderExists', 'Session文件夹已存在：%s。', sessionFolder); end
    if ~mkdir(sessionFolder), error('LFP:SessionFolderCreateFailed', '无法创建Session文件夹：%s。', sessionFolder); end
    for directory = ["data" "configs" "results" "exports"]
        if ~mkdir(fullfile(sessionFolder, directory)), error('LFP:SessionSubfolderCreateFailed', '无法创建Session子目录：%s。', directory); end
    end
    project.subjects(subjectIndex).sessions(end).folder_relative_path = session.folder_relative_path;
    write_session_metadata(sessionFolder, project.subjects(subjectIndex).sessions(end));
end
if options.Save, [~, project] = lfp_save_project(project, LockToken=lock); end
lfp_project_end_transaction(transaction, "committed");
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

function write_session_metadata(folder, session)
sessionMetadata = session; %#ok<NASGU>
save(fullfile(folder, 'session.mat'), 'sessionMetadata', '-v7');
end

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
originalProject = project;
oldSession = project.subjects(subjectIndex).sessions(sessionIndex);
newVisit = oldSession.visit_label;
if isfield(updates, 'visit_label'), newVisit = string(updates.visit_label); end
oldFolder = string(get_field(oldSession, 'folder_relative_path', ""));
newFolder = oldFolder;
moved = false;
try
    if strlength(oldFolder) > 0 && newVisit ~= oldSession.visit_label
        folderLabel = newVisit;
        if strlength(folderLabel) == 0, folderLabel = sessionId; end
        newFolder = fullfile(string(project.subjects(subjectIndex).folder_relative_path), ...
            lfp_project_folder_name(folderLabel, sessionId, "Session"));
        relocate_folder(project, oldFolder, newFolder);
        moved = true;
    end
    for name = ["visit_label" "acquisition_date" "medication_state" "stimulation_state" "repeat_label" "notes"]
        fieldName = char(name);
        if isfield(updates, fieldName), project.subjects(subjectIndex).sessions(sessionIndex).(fieldName) = string(updates.(fieldName)); end
    end
    project.subjects(subjectIndex).sessions(sessionIndex).folder_relative_path = newFolder;
    if strlength(newFolder) > 0
        session = project.subjects(subjectIndex).sessions(sessionIndex);
        for refIndex = 1:numel(session.data_refs)
            ref = session.data_refs(refIndex);
            ref.relative_path = replace_prefix(string(ref.relative_path), oldFolder, newFolder);
            if isfield(ref, 'project_copy_relative_path')
                ref.project_copy_relative_path = replace_prefix(string(ref.project_copy_relative_path), oldFolder, newFolder);
            end
            session.data_refs(refIndex) = ref;
        end
        project.subjects(subjectIndex).sessions(sessionIndex) = session;
        for runIndex = 1:numel(project.analysisRuns)
            if string(project.analysisRuns(runIndex).session_id) == sessionId && isfield(project.analysisRuns(runIndex), 'result_ref')
                project.analysisRuns(runIndex).result_ref = replace_prefix(string(project.analysisRuns(runIndex).result_ref), oldFolder, newFolder);
            end
        end
        write_session_metadata(fullfile(string(project.rootPath), newFolder), session);
    end
    session = project.subjects(subjectIndex).sessions(sessionIndex);
    if options.Save, lfp_save_project(project); end
catch exception
    if moved
        rollback_folder(project, oldFolder, newFolder);
        if strlength(oldFolder) > 0 && isfolder(fullfile(string(project.rootPath), oldFolder))
            try, write_session_metadata(fullfile(string(project.rootPath), oldFolder), oldSession); catch, end
        end
    end
    if options.Save
        try, lfp_save_project(originalProject); catch, end
    end
    rethrow(exception);
end
end

function relocate_folder(project, oldFolder, newFolder)
oldAbsolute = fullfile(string(project.rootPath), oldFolder);
newAbsolute = fullfile(string(project.rootPath), newFolder);
if oldFolder == newFolder, return; end
if isfolder(newAbsolute) || isfile(newAbsolute), error('LFP:SessionFolderExists', 'Session文件夹已存在：%s。', newAbsolute); end
if isfolder(oldAbsolute)
    if ~movefile(oldAbsolute, newAbsolute, 'f'), error('LFP:SessionFolderMoveFailed', '无法移动Session文件夹。'); end
else
    if ~mkdir(newAbsolute), error('LFP:SessionFolderCreateFailed', '无法创建Session文件夹。'); end
end
end

function value = replace_prefix(value, oldPrefix, newPrefix)
if strlength(oldPrefix) > 0 && (value == oldPrefix || startsWith(value, oldPrefix + filesep) || startsWith(value, oldPrefix + "/"))
    value = newPrefix + extractAfter(value, strlength(oldPrefix));
end
end

function value = get_field(s, name, fallback)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = fallback; end
end

function rollback_folder(project, oldFolder, newFolder)
if strlength(newFolder)==0, return; end
oldAbsolute=fullfile(string(project.rootPath),oldFolder);
newAbsolute=fullfile(string(project.rootPath),newFolder);
if isfolder(newAbsolute) && ~isfolder(oldAbsolute)
    try, movefile(newAbsolute,oldAbsolute,'f'); catch, end
end
end

function write_session_metadata(folder, session)
if ~isfolder(folder), mkdir(folder); end
sessionMetadata = session; %#ok<NASGU>
save(fullfile(folder, 'session.mat'), 'sessionMetadata', '-v7');
end

function [subjectIndex, sessionIndex] = locate(project, sessionId)
subjectIndex = []; sessionIndex = [];
for s = 1:numel(project.subjects)
    match = find(string({project.subjects(s).sessions.session_id}) == sessionId, 1);
    if ~isempty(match), subjectIndex = s; sessionIndex = match; return; end
end
end

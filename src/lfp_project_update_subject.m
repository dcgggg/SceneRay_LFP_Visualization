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
originalProject = project;
oldSubject = project.subjects(index);
newDisplay = oldSubject.display_name;
if isfield(updates, 'display_name'), newDisplay = string(updates.display_name); end
oldFolder = string(get_field(oldSubject, 'folder_relative_path', ""));
newFolder = oldFolder;
moved = false;
try
    if strlength(oldFolder) > 0 && newDisplay ~= oldSubject.display_name
        newFolder = fullfile(string(project.paths.subjects), lfp_project_folder_name(newDisplay, subjectId, "被试"));
        relocate_folder(project, oldFolder, newFolder, "被试");
        moved = true;
    end
    for name = ["display_name" "group" "notes"]
        fieldName = char(name);
        if isfield(updates, fieldName), project.subjects(index).(fieldName) = string(updates.(fieldName)); end
    end
    project.subjects(index).folder_relative_path = newFolder;
    if strlength(newFolder) > 0
        for sessionIndex = 1:numel(project.subjects(index).sessions)
            oldSessionFolder = string(get_field(project.subjects(index).sessions(sessionIndex), 'folder_relative_path', ""));
            if strlength(oldSessionFolder) > 0
                project.subjects(index).sessions(sessionIndex).folder_relative_path = replace_prefix(oldSessionFolder, oldFolder, newFolder);
                for refIndex = 1:numel(project.subjects(index).sessions(sessionIndex).data_refs)
                    ref = project.subjects(index).sessions(sessionIndex).data_refs(refIndex);
                    if isfield(ref, 'relative_path')
                        ref.relative_path = replace_prefix(string(ref.relative_path), oldFolder, newFolder);
                    end
                    if isfield(ref, 'project_copy_relative_path')
                        ref.project_copy_relative_path = replace_prefix(string(ref.project_copy_relative_path), oldFolder, newFolder);
                    end
                    if isfield(ref, 'cache_relative_paths') && ~isempty(ref.cache_relative_paths)
                        ref.cache_relative_paths = arrayfun(@(p) replace_prefix(string(p), oldFolder, newFolder), string(ref.cache_relative_paths));
                    end
                    project.subjects(index).sessions(sessionIndex).data_refs(refIndex) = ref;
                end
                for channelIndex = 1:numel(project.subjects(index).sessions(sessionIndex).channels)
                    if isfield(project.subjects(index).sessions(sessionIndex).channels(channelIndex), 'cache_relative_path')
                        project.subjects(index).sessions(sessionIndex).channels(channelIndex).cache_relative_path = replace_prefix( ...
                            string(project.subjects(index).sessions(sessionIndex).channels(channelIndex).cache_relative_path), oldFolder, newFolder);
                    end
                end
                lfp_project_write_channel_manifest(project, project.subjects(index).sessions(sessionIndex));
            end
        end
        project = update_run_paths(project, oldFolder, newFolder);
        write_subject_metadata(fullfile(string(project.rootPath), newFolder), project.subjects(index));
    end
    if options.Save, lfp_save_project(project); end
catch exception
    if moved
        rollback_folder(project, oldFolder, newFolder);
        if strlength(oldFolder) > 0 && isfolder(fullfile(string(project.rootPath), oldFolder))
            try, write_subject_metadata(fullfile(string(project.rootPath), oldFolder), oldSubject); catch, end
        end
    end
    if options.Save
        try, lfp_save_project(originalProject); catch, end
    end
    rethrow(exception);
end
subject = project.subjects(index);
end

function relocate_folder(project, oldFolder, newFolder, label)
oldAbsolute = fullfile(string(project.rootPath), oldFolder);
newAbsolute = fullfile(string(project.rootPath), newFolder);
if oldFolder == newFolder, return; end
if isfolder(newAbsolute) || isfile(newAbsolute)
    error('LFP:FolderExists', '%s文件夹已存在：%s。', label, newAbsolute);
end
if isfolder(oldAbsolute)
    if ~movefile(oldAbsolute, newAbsolute, 'f'), error('LFP:FolderMoveFailed', '无法移动%s文件夹。', label); end
else
    if ~mkdir(newAbsolute), error('LFP:FolderCreateFailed', '无法创建%s文件夹。', label); end
end
end

function project = update_run_paths(project, oldFolder, newFolder)
for runIndex = 1:numel(project.analysisRuns)
    if isfield(project.analysisRuns(runIndex), 'result_ref')
        project.analysisRuns(runIndex).result_ref = replace_prefix(string(project.analysisRuns(runIndex).result_ref), oldFolder, newFolder);
    end
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

function write_subject_metadata(folder, subject)
if ~isfolder(folder), mkdir(folder); end
subjectMetadata=subject; %#ok<NASGU>
save(fullfile(folder,'subject.mat'),'subjectMetadata','-v7');
end

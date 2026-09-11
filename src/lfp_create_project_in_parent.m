function [project, projectRoot] = lfp_create_project_in_parent(parentRoot, name, options)
%LFP_CREATE_PROJECT_IN_PARENT Create a project folder below a parent folder.
%   The destination is parentRoot/name. Existing directories are never
%   reused unless they contain a valid project.mat; unrelated folders cause
%   an error. A failed index save removes only the newly-created destination.

arguments
    parentRoot (1,1) string
    name (1,1) string
    options.Description (1,1) string = ""
    options.Config (1,1) struct = struct()
end

if ~isfolder(parentRoot)
    error('LFP:InvalidProjectParent', '项目父目录不存在：%s。', parentRoot);
end
name = lfp_validate_folder_name(name, "项目名称");
projectRoot = fullfile(parentRoot, name);
if isfolder(projectRoot) || isfile(projectRoot)
    if isfolder(projectRoot) && isfile(fullfile(projectRoot, "project.mat"))
        error('LFP:ProjectAlreadyExists', '目标目录已是一个项目：%s。', projectRoot);
    end
    error('LFP:ProjectFolderExists', '目标目录已存在且不是可复用项目：%s。', projectRoot);
end
if ~can_write(parentRoot)
    error('LFP:ProjectParentNotWritable', '没有权限写入项目父目录：%s。', parentRoot);
end
if ~mkdir(projectRoot)
    error('LFP:ProjectCreateFailed', '无法创建项目目录：%s。', projectRoot);
end
try
    project = lfp_create_project(projectRoot, name, Description=options.Description, Config=options.Config);
    project.storage_mode = "subject_session";
    lfp_save_project(project);
catch exception
    if isfolder(projectRoot) && ~isfile(fullfile(projectRoot, "project.mat")), rmdir(projectRoot, 's'); end
    rethrow(exception);
end
end

function tf = can_write(folder)
probe = fullfile(folder, ".lfp_write_probe_" + lfp_make_id("probe"));
tf = false;
fid = -1;
try
    fid = fopen(probe, 'w');
    if fid >= 0
        fclose(fid); fid = -1;
        delete(probe); tf = true;
    end
catch
    if fid >= 0, fclose(fid); end
    if isfile(probe), delete(probe); end
end
end

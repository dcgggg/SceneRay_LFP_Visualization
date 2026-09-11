function projectFile = lfp_save_project(project)
%LFP_SAVE_PROJECT Atomically save a Project index.
%   PROJECTFILE = LFP_SAVE_PROJECT(PROJECT) writes project.mat through a
%   temporary file and replaces the index only after save succeeds.

arguments
    project (1,1) struct
end
if ~isfield(project, 'rootPath') || strlength(string(project.rootPath)) == 0
    error('LFP:InvalidProject', 'Project.rootPath is required.');
end
projectRoot = string(project.rootPath);
if ~isfolder(projectRoot), mkdir(projectRoot); end
projectFile = fullfile(projectRoot, "project.mat");
project.updatedAt = string(datestr(now, 31));
tempFile = projectFile + ".tmp_" + lfp_make_id("save");
cleanup = onCleanup(@() delete_if_present(tempFile)); %#ok<NASGU>
save(tempFile, 'project', '-v7');
movefile(tempFile, projectFile, 'f');
end

function delete_if_present(filename)
if isfile(filename), delete(filename); end
end

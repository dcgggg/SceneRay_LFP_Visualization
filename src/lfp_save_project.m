function [projectFile, project] = lfp_save_project(project, options)
%LFP_SAVE_PROJECT Atomically save a Project index.
%   PROJECTFILE = LFP_SAVE_PROJECT(PROJECT) writes project.mat through a
%   temporary file and replaces the index only after save succeeds.

arguments
    project (1,1) struct
    options.LockToken (1,1) struct = struct()
    options.RequireRevision (1,1) logical = false
end
if ~isfield(project, 'rootPath') || strlength(string(project.rootPath)) == 0
    error('LFP:InvalidProject', 'Project.rootPath is required.');
end
projectRoot = string(project.rootPath);
if ~isfolder(projectRoot), mkdir(projectRoot); end
lock = options.LockToken;
ownedLock = isempty(fieldnames(lock));
if ownedLock
    lock = lfp_project_acquire_lock(projectRoot);
    cleanupLock = onCleanup(@() lfp_project_release_lock(lock)); %#ok<NASGU>
else
    expectedLockPath = fullfile(projectRoot, '.lfp_write.lock');
    if ~isfield(lock,'path') || string(lock.path) ~= string(expectedLockPath) || ~isfolder(string(lock.path))
        error('LFP:InvalidProjectLock', 'LockToken is not an active project lock.');
    end
    ownerFile = fullfile(string(lock.path), 'owner.mat');
    if ~isfile(ownerFile)
        error('LFP:InvalidProjectLock', 'LockToken owner metadata is missing.');
    end
    ownerLoaded = load(ownerFile, 'owner');
    if ~isfield(ownerLoaded,'owner') || ~isstruct(ownerLoaded.owner) || ...
            ~isfield(ownerLoaded.owner,'token') || string(ownerLoaded.owner.token) ~= string(lock.token)
        error('LFP:InvalidProjectLock', 'LockToken does not own the active project lock.');
    end
end
projectFile = fullfile(projectRoot, "project.mat");
project.updatedAt = string(datestr(now, 31));
if ~isfield(project,'project_revision') || ~isscalar(project.project_revision) || ~isfinite(project.project_revision)
    project.project_revision = 0;
end
% Serialize a monotonic revision. Callers that need optimistic conflict
% detection can set RequireRevision=true (the batch runner enables this on its
% lock); the default remains backward compatible with scripts that ignore the
% optional returned project revision.
currentRevision = 0;
existing = struct();
if isfile(projectFile)
    try
        existing = load(projectFile, 'project');
        if isfield(existing,'project') && isstruct(existing.project) && ...
                isfield(existing.project,'project_revision') && isfinite(existing.project.project_revision)
            currentRevision = double(existing.project.project_revision);
        end
    catch exception
        error('LFP:ProjectRevisionReadFailed', '无法读取项目版本以执行并发保护：%s', exception.message);
    end
end
inputRevision = double(project.project_revision);
requireRevision = options.RequireRevision || (isfield(lock,'enforceRevision') && logical(lock.enforceRevision));
if requireRevision && inputRevision > 0 && inputRevision ~= currentRevision
    % Older callers commonly ignore the optional second output of this
    % function. If the disk index is otherwise byte-for-byte equivalent, it
    % is safe to treat that as an idempotent repeat save. A real concurrent
    % update changes project content and is rejected instead of overwritten.
    equivalent = false;
    try
        if isfield(existing,'project') && isstruct(existing.project)
            equivalent = isequaln(revision_compare_view(project), revision_compare_view(existing.project));
        end
    catch
        equivalent = false;
    end
    if ~equivalent
        error('LFP:ProjectRevisionConflict', ...
            '项目索引已由其他写入者更新（内存版本 %.0f，磁盘版本 %.0f）；请重新加载项目后再保存。', ...
            inputRevision, currentRevision);
    end
end
project.project_revision = currentRevision + 1;
tempFile = projectFile + ".tmp_" + lfp_make_id("save");
cleanup = onCleanup(@() delete_if_present(tempFile)); %#ok<NASGU>
save(tempFile, 'project', '-v7');
movefile(tempFile, projectFile, 'f');
end

function delete_if_present(filename)
if isfile(filename), delete(filename); end
end

function value = revision_compare_view(value)
% Remove fields maintained by the store itself before idempotence checking.
for name = {'project_revision','updatedAt'}
    if isstruct(value) && isfield(value, name{1}), value = rmfield(value, name{1}); end
end
end

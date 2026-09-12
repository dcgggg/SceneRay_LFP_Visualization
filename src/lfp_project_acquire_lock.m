function lock = lfp_project_acquire_lock(projectRoot)
%LFP_PROJECT_ACQUIRE_LOCK Acquire the common project write lock.
%   LOCK = ... claims a lock directory using mkdir's create/race message.
%   Existing locks are never removed automatically;
%   callers must inspect the owner metadata and explicitly recover a stale
%   lock. Use lfp_project_release_lock in cleanup code.

arguments
    projectRoot (1,1) string
end
if ~isfolder(projectRoot), error('LFP:InvalidProjectRoot', 'Project root does not exist: %s', projectRoot); end
lockPath = fullfile(projectRoot, '.lfp_write.lock');
if isfolder(lockPath)
    error('LFP:ProjectLocked', 'Project is already being written: %s', lockPath);
end
[created, message] = mkdir(lockPath);
% MATLAB's mkdir reports status=1 even when a directory already exists.  A
% non-empty message is the documented signal for that race, so do not treat
% it as ownership; otherwise two writers could overwrite owner.mat.
if ~created || strlength(strtrim(string(message))) > 0 || ~isfolder(lockPath)
    error('LFP:ProjectLocked', 'Project is already being written: %s (%s)', lockPath, string(message));
end
baseRevision = 0;
projectFile = fullfile(projectRoot, 'project.mat');
if isfile(projectFile)
    try
        loaded = load(projectFile, 'project');
        if isfield(loaded,'project') && isstruct(loaded.project) && ...
                isfield(loaded.project,'project_revision') && isfinite(loaded.project.project_revision)
            baseRevision = double(loaded.project.project_revision);
        end
    catch
        % The lock is still useful when the index cannot be read; the save
        % operation will report the concrete revision/read error.
        baseRevision = NaN;
    end
end
processId = "unknown";
try, processId = string(feature('getpid')); catch, end %#ok<CTCH>
lock = struct('path', string(lockPath), 'token', lfp_make_id('lock'), ...
    'createdAt', string(datestr(now,31)), 'host', string(computer), ...
    'processId', processId, 'baseRevision', baseRevision, 'enforceRevision', false);
owner = lock; %#ok<NASGU>
try
    save(fullfile(lockPath, 'owner.mat'), 'owner', '-v7');
catch exception
    rmdir(lockPath, 's');
    rethrow(exception);
end
end

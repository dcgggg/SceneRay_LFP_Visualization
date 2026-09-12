function lfp_project_release_lock(lock)
%LFP_PROJECT_RELEASE_LOCK Release a lock returned by lfp_project_acquire_lock.
arguments
    lock (1,1) struct
end
if ~isfield(lock,'path') || strlength(string(lock.path))==0, return; end
lockPath = string(lock.path);
if isfile(fullfile(lockPath,'owner.mat')), delete(fullfile(lockPath,'owner.mat')); end
if isfolder(lockPath), rmdir(lockPath, 's'); end
end

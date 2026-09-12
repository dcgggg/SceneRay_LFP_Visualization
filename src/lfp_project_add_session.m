function [project, session] = lfp_project_add_session(project, subjectId, data, sessionInfo, options)
%LFP_PROJECT_ADD_SESSION Add one imported record as a Session.
%   DATA must be a standard LFP struct with samples-by-channels signal.
%   The raw DATA is stored in a per-Session file for nested projects (or in
%   the legacy project/data/<session_id>.mat layout); the Project index
%   stores only metadata and a relative data reference. No samples are
%   cropped, padded, interpolated, or concatenated.

arguments
    project (1,1) struct
    subjectId (1,1) string
    data (1,1) struct
    sessionInfo (1,1) struct = struct()
    options.Save (1,1) logical = true
    options.LockToken (1,1) struct = struct()
end

lock = options.LockToken;
if isempty(fieldnames(lock))
    lock = lfp_project_acquire_lock(string(project.rootPath));
    cleanupLock = onCleanup(@()lfp_project_release_lock(lock)); %#ok<NASGU>
end
[project, session] = lfp_project_add_empty_session(project, subjectId, sessionInfo, Save=false, LockToken=lock);
mapping = struct([]);
if isfield(sessionInfo, 'channel_mapping'), mapping = sessionInfo.channel_mapping; end
[project, session] = lfp_project_attach_data(project, session.session_id, data, ...
    ChannelMapping=mapping, Save=options.Save, LockToken=lock);
end

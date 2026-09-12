function [project, impact] = lfp_project_remove_session(project, sessionId, options)
%LFP_PROJECT_REMOVE_SESSION Remove a Session from the project index only.
%   Raw/result files and the original CSV are deliberately retained.

arguments
    project (1,1) struct
    sessionId (1,1) string
    options.Save (1,1) logical = true
    options.LockToken (1,1) struct = struct()
end
lock=options.LockToken; if isempty(fieldnames(lock)), lock=lfp_project_acquire_lock(string(project.rootPath)); cleanupLock=onCleanup(@()lfp_project_release_lock(lock)); end %#ok<NASGU>
[subjectIndex, sessionIndex] = locate(project, sessionId);
if isempty(subjectIndex), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
session = project.subjects(subjectIndex).sessions(sessionIndex);
runIds = strings(0,1);
if isfield(session, 'analysis_run_ids'), runIds = string(session.analysis_run_ids(:)); end
impact = struct('sessionId', sessionId, 'dataReferencesRetained', string({session.data_refs.relative_path})', ...
    'analysisRunsRetained', runIds, 'sourceFilesUntouched', true);
project.subjects(subjectIndex).sessions(sessionIndex) = [];
if options.Save, [~, project] = lfp_save_project(project, LockToken=lock); end
end

function [subjectIndex, sessionIndex] = locate(project, sessionId)
subjectIndex = []; sessionIndex = [];
for s = 1:numel(project.subjects)
    match = find(string({project.subjects(s).sessions.session_id}) == sessionId, 1);
    if ~isempty(match), subjectIndex = s; sessionIndex = match; return; end
end
end

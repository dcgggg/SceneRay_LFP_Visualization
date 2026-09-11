function [data, session] = lfp_project_get_session_data(project, sessionId)
%LFP_PROJECT_GET_SESSION_DATA Load raw data for a Session by stable ID.

arguments
    project (1,1) struct
    sessionId (1,1) string
end
[session, ~] = find_session(project, sessionId);
if isempty(session), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
if isempty(session.data_refs) || ~isfield(session.data_refs(1), 'relative_path')
    error('LFP:MissingDataReference', 'Session has no data reference: %s', sessionId);
end
path = fullfile(string(project.rootPath), string(session.data_refs(1).relative_path));
if ~isfile(path), error('LFP:SourceDataMissing', 'Session data file is missing: %s', path); end
loaded = load(path, 'payload');
if ~isfield(loaded, 'payload') || ~isfield(loaded.payload, 'data')
    error('LFP:InvalidSessionData', 'Session data file is invalid: %s', path);
end
data = loaded.payload.data;
end

function [session, subjectIndex] = find_session(project, sessionId)
session = [];
subjectIndex = [];
for index = 1:numel(project.subjects)
    matches = find(string({project.subjects(index).sessions.session_id}) == string(sessionId), 1);
    if ~isempty(matches), session = project.subjects(index).sessions(matches); subjectIndex = index; return; end
end
end

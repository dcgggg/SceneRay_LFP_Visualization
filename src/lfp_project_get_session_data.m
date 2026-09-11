function [data, session] = lfp_project_get_session_data(project, sessionId)
%LFP_PROJECT_GET_SESSION_DATA Load raw data for a Session by stable ID.

arguments
    project (1,1) struct
    sessionId (1,1) string
end
[session, ~] = find_session(project, sessionId);
if isempty(session), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
if isempty(session.data_refs) && isempty(session.channels)
    error('LFP:MissingDataReference', 'Session has no data reference: %s', sessionId);
end
% The original synchronized session cache remains the preferred fast path.
% Appended heterogeneous channels are loaded below from their independent
% caches rather than being forced into a common time axis.
if numel(session.data_refs) == 1 && isfield(session.data_refs(1), 'relative_path')
    path = fullfile(string(project.rootPath), string(session.data_refs(1).relative_path));
    if isfile(path)
        try, loaded = load(path, 'payload'); catch, loaded = struct(); end
        if isfield(loaded, 'payload') && isfield(loaded.payload, 'data')
            candidate = loaded.payload.data;
            % A canonical matrix is safe only while its columns still map
            % one-to-one to the active Session channels.  After channel
            % removal, fall through to per-channel caches so a removed
            % column cannot shift the meaning of the remaining channels.
            activeLabels = string({session.channels.original_label})';
            candidateLabels = string(get_field(candidate, 'channelLabels', strings(0,1))); candidateLabels = candidateLabels(:);
            compatible = isfield(candidate, 'signal') && size(candidate.signal,2) == numel(session.channels);
            if compatible && ~isempty(candidateLabels), compatible = numel(candidateLabels) == numel(activeLabels) && all(candidateLabels == activeLabels); end
            if compatible, data = candidate; return; end
        end
    end
end
if isempty(session.channels), error('LFP:SourceDataMissing', 'Session data file is missing: %s', sessionId); end
labels = string({session.channels.original_label})';
channelData = cell(numel(session.channels), 1);
for k = 1:numel(session.channels)
    channelData{k} = lfp_project_get_channel_data(project, sessionId, string(session.channels(k).channel_id));
end
lengths = cellfun(@(item) numel(item.signal), channelData); maxLength = max(lengths);
time = channelData{1}.time(:); fs = channelData{1}.fs; units = channelData{1}.units;
signal = NaN(maxLength, numel(channelData));
sameAxis = true;
for k = 1:numel(channelData)
    n = numel(channelData{k}.signal); signal(1:n,k) = channelData{k}.signal(:);
    otherTime = channelData{k}.time(:);
    if numel(otherTime) ~= numel(time) || any(abs(otherTime(1:min(end,numel(time))) - time(1:min(end,numel(otherTime)))) > 1e-9)
        sameAxis = false;
    end
end
if ~sameAxis || numel(time) ~= maxLength, time = (0:maxLength-1)' / double(fs); end
data = struct('time', time, 'signal', signal, 'fs', double(fs), 'channelLabels', labels, ...
    'units', units, 'metadata', struct('heterogeneousChannels', ~sameAxis, 'channelData', {channelData}), ...
    'processingHistory', struct('operation', "load_channel_caches", 'parameters', struct('channel_count', numel(channelData)), ...
    'notes', "Independent channel caches were loaded; padded NaN values are display-only and are not analysis samples."));
end

function [session, subjectIndex] = find_session(project, sessionId)
session = [];
subjectIndex = [];
for index = 1:numel(project.subjects)
    matches = find(string({project.subjects(index).sessions.session_id}) == string(sessionId), 1);
    if ~isempty(matches), session = project.subjects(index).sessions(matches); subjectIndex = index; return; end
end
end

function value = get_field(source, name, fallback)
if isstruct(source) && isfield(source, name) && ~isempty(source.(name)), value = source.(name); else, value = fallback; end
end

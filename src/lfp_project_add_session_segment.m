function [project, session] = lfp_project_add_session_segment(project, sessionId, data, segmentInfo, options)
%LFP_PROJECT_ADD_SESSION_SEGMENT Add a synchronized file as a Session segment.
%   The existing and new records must have equal length, sampling rate and
%   sample-by-sample time vectors.  Signals are joined by columns only after
%   these checks pass.  A time gap or independent recording must instead be
%   represented by a separate Session; this function never inserts samples.

arguments
    project (1,1) struct
    sessionId (1,1) string
    data (1,1) struct
    segmentInfo (1,1) struct = struct()
    options.Save (1,1) logical = true
end
validate_segment(data);
[subjectIndex, sessionIndex] = locate_session(project, sessionId);
if isempty(subjectIndex), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
[existingData, session] = lfp_project_get_session_data(project, sessionId);
if double(existingData.fs) ~= double(data.fs) || size(existingData.signal,1) ~= size(data.signal,1)
    error('LFP:SessionSegmentMismatch', 'Segment sampling rate and sample count must match exactly.');
end
oldTime = double(existingData.time(:)); newTime = double(data.time(:));
if numel(oldTime) ~= numel(newTime) || any(abs(oldTime - newTime) > max(1e-9, 1e-6 / double(data.fs)))
    error('LFP:SessionSegmentMismatch', 'Segment time axes are not identical; no alignment or interpolation was applied.');
end
oldLabels = string(get_field(existingData, 'channelLabels', "channel_" + string((1:size(existingData.signal,2))')));
newLabels = string(get_field(data, 'channelLabels', "channel_" + string((1:size(data.signal,2))')));
if any(ismember(newLabels, oldLabels)), error('LFP:DuplicateChannel', 'Segment contains a channel already in the Session.'); end
merged = existingData;
merged.signal = [double(existingData.signal), double(data.signal)];
merged.channelLabels = [oldLabels(:); newLabels(:)]';
merged.channelNames = merged.channelLabels;
if isfield(merged, 'metadata') && isstruct(merged.metadata)
    merged.metadata.sourceFileName = string(get_field(merged.metadata, 'sourceFileName', "")) + ";" + string(get_source_name(data));
end
if ~isfield(merged, 'processingHistory') || isempty(merged.processingHistory)
    merged.processingHistory = struct('operation', "import", 'parameters', struct(), 'notes', "Session segment base record.");
end
merged.processingHistory(end+1) = struct('operation', "session_segment_append", ...
    'parameters', struct('session_id', sessionId, 'segment_id', get_string(segmentInfo, 'segment_id', "segment_" + string(numel(session.data_refs)+1))), ...
    'notes', "Synchronized segment appended by exact time-axis validation.");
session.data_version = lfp_data_version(merged);
relativePath = string(session.data_refs(1).relative_path);
absolutePath = fullfile(string(project.rootPath), relativePath);
payload = struct('data', merged, 'session_id', sessionId, 'saved_at', string(datestr(now,31)), 'data_version', session.data_version);
temp = absolutePath + ".tmp_" + lfp_make_id("segment"); cleanup = onCleanup(@() delete_if_present(temp)); %#ok<NASGU>
save(temp, 'payload', '-v7'); movefile(temp, absolutePath, 'f');
newRef = struct('relative_path', relativePath, 'source_path', get_source_path(data), ...
    'project_copy_relative_path', "", ...
    'source_file_name', get_source_name(data), 'segment_id', get_string(segmentInfo, 'segment_id', "segment_" + string(numel(session.data_refs)+1)), ...
    'sample_count', size(data.signal,1), 'channel_count', size(data.signal,2), 'fs', double(data.fs), ...
    'time_start', newTime(1), 'time_end', newTime(end), 'channel_labels', newLabels(:), ...
    'channel_ids', strings(numel(newLabels),1), 'cache_relative_paths', strings(numel(newLabels),1), ...
    'source_file_id', "", 'source_file_fingerprint', "", 'import_config', struct(), ...
    'time_unit', "s", 'signal_unit', string(get_field(data, 'units', "unknown")), ...
    'imported_at', string(datestr(now,31)), 'cache_version', "1");
session.data_refs(end+1) = newRef;
[~, ~, ~, channelTemplate, ~, ~] = lfp_project_schema();
newIds = strings(numel(newLabels),1); newCaches = strings(numel(newLabels),1);
for index = 1:numel(newLabels)
    channel = channelTemplate; channel.original_label = newLabels(index); channel.display_label = newLabels(index);
    channel.channel_id = make_channel_id(newLabels(index), index, session.channels); channel.unit = string(get_field(data, 'units', "unknown"));
    channel.session_id = sessionId; channel.source_column = index; channel.sampling_rate_hz = double(data.fs); channel.sample_count = size(data.signal,1);
    channel.time_start = newTime(1); channel.time_end = newTime(end); channel.enabled = true;
    channel.data_revision = lfp_data_version(struct('signal',data.signal(:,index),'fs',data.fs,'time',data.time,'channelLabels',newLabels(index)));
    channel.source_metadata = struct('source_file_name', get_source_name(data), 'source_file_path', get_source_path(data), 'source_column', index);
    newIds(index)=channel.channel_id; newCaches(index)=lfp_project_save_channel_cache(project,session,channel,newTime,double(data.signal(:,index)),channel.source_metadata); channel.cache_relative_path=newCaches(index);
    session.channels(end+1) = channel; %#ok<AGROW>
end
session.data_refs(end).channel_ids = newIds; session.data_refs(end).cache_relative_paths = newCaches;
project.subjects(subjectIndex).sessions(sessionIndex) = session;
lfp_project_write_channel_manifest(project, session);
if options.Save, lfp_save_project(project); end
end

function validate_segment(data)
if ~isfield(data,'signal') || ~isnumeric(data.signal) || isempty(data.signal) || ndims(data.signal) ~= 2
    error('LFP:InvalidData', 'Segment signal must be a non-empty numeric matrix.');
end
if ~isfield(data,'time') || numel(data.time) ~= size(data.signal,1), error('LFP:InvalidData', 'Segment time must match signal rows.'); end
if ~isfield(data,'fs') || ~isscalar(data.fs) || ~isfinite(data.fs) || data.fs <= 0, error('LFP:InvalidData', 'Segment fs must be positive.'); end
if any(isinf(double(data.signal)), 'all'), error('LFP:InvalidData', 'Segment signal cannot contain Inf.'); end
end

function [subjectIndex, sessionIndex] = locate_session(project, sessionId)
subjectIndex=[]; sessionIndex=[];
for s=1:numel(project.subjects)
    k=find(string({project.subjects(s).sessions.session_id})==string(sessionId),1);
    if ~isempty(k), subjectIndex=s; sessionIndex=k; return; end
end
end

function id = make_channel_id(label, index, existing)
id = regexprep("channel_" + label, '[^A-Za-z0-9_\-]', '_');
if ~isempty(existing) && any(string({existing.channel_id}) == id), id = id + "_" + string(index); end
end

function value = get_field(s,name,fallback)
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), value=s.(name); else, value=fallback; end
end
function value = get_string(s,name,fallback)
value=string(get_field(s,name,fallback));
end
function value = get_source_path(data)
value=""; if isfield(data,'metadata') && isfield(data.metadata,'sourceFilePath'), value=string(data.metadata.sourceFilePath); end
end
function value = get_source_name(data)
value=""; if isfield(data,'metadata') && isfield(data.metadata,'sourceFileName'), value=string(data.metadata.sourceFileName); end
end
function delete_if_present(filename)
if isfile(filename), delete(filename); end
end

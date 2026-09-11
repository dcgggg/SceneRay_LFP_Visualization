function [project, session] = lfp_project_add_session(project, subjectId, data, sessionInfo, options)
%LFP_PROJECT_ADD_SESSION Add one imported record as a Session.
%   DATA must be a standard LFP struct with samples-by-channels signal.
%   The raw DATA is stored in project/data/<session_id>.mat; the Project
%   index stores only metadata and a relative data reference.  No samples
%   are cropped, padded, interpolated, or concatenated.

arguments
    project (1,1) struct
    subjectId (1,1) string
    data (1,1) struct
    sessionInfo (1,1) struct = struct()
    options.Save (1,1) logical = true
end

validate_data(data);
subjectIndex = find_subject(project, subjectId);
if isempty(subjectIndex), error('LFP:SubjectNotFound', 'Subject ID not found: %s', subjectId); end
[~, ~, sessionTemplate, channelTemplate, ~, ~] = lfp_project_schema();
session = sessionTemplate;
session.session_id = get_string(sessionInfo, 'session_id', lfp_make_id("session"));
session.subject_id = subjectId;
session.visit_label = get_string(sessionInfo, 'visit_label', "");
session.acquisition_date = get_string(sessionInfo, 'acquisition_date', "");
session.medication_state = get_string(sessionInfo, 'medication_state', "");
session.stimulation_state = get_string(sessionInfo, 'stimulation_state', "");
session.repeat_label = get_string(sessionInfo, 'repeat_label', "");
session.notes = get_string(sessionInfo, 'notes', "");
existing = project.subjects(subjectIndex).sessions;
if ~isempty(existing) && any(string({existing.session_id}) == session.session_id)
    error('LFP:DuplicateSession', 'Session ID already exists: %s', session.session_id);
end
labels = string(get_field(data, 'channelLabels', "channel_" + string((1:size(data.signal,2))')));
labels = labels(:);
session.channels = channelTemplate([]);
for index = 1:size(data.signal, 2)
    channel = channelTemplate;
    channel.original_label = labels(index);
    channel.display_label = get_channel_display(sessionInfo, labels(index), index);
    channel.channel_id = make_channel_id(labels(index), index, session.channels);
    channel.unit = string(get_field(data, 'units', "unknown"));
    mapping = get_mapping(sessionInfo, labels(index));
    channel.side = get_string(mapping, 'side', "");
    channel.region = get_string(mapping, 'region', "");
    channel.contacts = get_string(mapping, 'contacts', "");
    channel.reference = get_string(mapping, 'reference', "");
    session.channels(end + 1) = channel; %#ok<AGROW>
end
session.data_version = lfp_data_version(data);
relativeDataPath = fullfile("data", session.session_id + ".mat");
absoluteDataPath = fullfile(string(project.rootPath), relativeDataPath);
if ~isfolder(fileparts(absoluteDataPath)), mkdir(fileparts(absoluteDataPath)); end
payload = struct('data', data, 'session_id', session.session_id, ...
    'saved_at', string(datestr(now, 31)), 'data_version', session.data_version);
tempFile = absoluteDataPath + ".tmp_" + lfp_make_id("data");
cleanup = onCleanup(@() delete_if_present(tempFile)); %#ok<NASGU>
save(tempFile, 'payload', '-v7');
movefile(tempFile, absoluteDataPath, 'f');
ref = struct('relative_path', relativeDataPath, 'source_path', get_source_path(data), ...
    'source_file_name', get_source_name(data), 'segment_id', "segment_1", ...
    'sample_count', size(data.signal,1), 'channel_count', size(data.signal,2), ...
    'fs', double(data.fs), 'time_start', double(data.time(1)), ...
    'time_end', double(data.time(end)), 'channel_labels', labels);
session.data_refs = ref;
project.subjects(subjectIndex).sessions(end + 1) = session;
if options.Save, lfp_save_project(project); end
end

function validate_data(data)
if ~isfield(data, 'signal') || ~isnumeric(data.signal) || ndims(data.signal) ~= 2 || isempty(data.signal)
    error('LFP:InvalidData', 'data.signal must be a non-empty numeric samples-by-channels matrix.');
end
if ~isfield(data, 'fs') || ~isscalar(data.fs) || ~isfinite(data.fs) || data.fs <= 0
    error('LFP:InvalidData', 'data.fs must be a positive finite scalar.');
end
if ~isfield(data, 'time') || numel(data.time) ~= size(data.signal, 1)
    error('LFP:InvalidData', 'data.time must contain one value per sample.');
end
if any(isinf(double(data.signal)), 'all')
    error('LFP:InvalidData', 'data.signal cannot contain Inf.');
end
end

function index = find_subject(project, subjectId)
index = [];
if isfield(project, 'subjects') && ~isempty(project.subjects)
    index = find(string({project.subjects.subject_id}) == string(subjectId), 1);
end
end

function value = get_field(s, name, fallback)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = fallback; end
end

function value = get_string(s, name, fallback)
if isfield(s, name) && ~isempty(s.(name)), value = string(s.(name)); else, value = string(fallback); end
end

function mapping = get_mapping(info, label)
mapping = struct();
if isfield(info, 'channel_mapping') && isstruct(info.channel_mapping)
    mappings = info.channel_mapping;
    for index = 1:numel(mappings)
        if isfield(mappings(index), 'original_label') && string(mappings(index).original_label) == label
            mapping = mappings(index); return;
        end
    end
end
end

function label = get_channel_display(info, original, index)
label = original;
if isfield(info, 'channel_mapping') && isstruct(info.channel_mapping)
    mappings = info.channel_mapping;
    for k = 1:numel(mappings)
        if isfield(mappings(k), 'original_label') && string(mappings(k).original_label) == original
            if isfield(mappings(k), 'display_label') && ~isempty(mappings(k).display_label), label = string(mappings(k).display_label); end
            return;
        end
    end
end
if strlength(label) == 0, label = "channel" + string(index); end
end

function id = make_channel_id(label, index, existing)
base = "channel_" + label;
base = regexprep(base, '[^A-Za-z0-9_\-]', '_');
if strlength(base) == 0, base = "channel_" + string(index); end
id = base;
if ~isempty(existing)
    old = string({existing.channel_id});
    if any(old == id), id = base + "_" + string(index); end
end
end

function value = get_source_path(data)
value = "";
if isfield(data, 'metadata') && isstruct(data.metadata) && isfield(data.metadata, 'sourceFilePath')
    value = string(data.metadata.sourceFilePath);
end
end

function value = get_source_name(data)
value = "";
if isfield(data, 'metadata') && isstruct(data.metadata) && isfield(data.metadata, 'sourceFileName')
    value = string(data.metadata.sourceFileName);
end
end

function delete_if_present(filename)
if isfile(filename), delete(filename); end
end

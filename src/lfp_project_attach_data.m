function [project, session] = lfp_project_attach_data(project, sessionId, data, options)
%LFP_PROJECT_ATTACH_DATA Attach canonical LFP data to an existing Session.
%   The canonical samples-by-channels DATA is copied into the project data
%   directory. Original source files are never modified or removed.

arguments
    project (1,1) struct
    sessionId (1,1) string
    data (1,1) struct
    options.ChannelMapping struct = struct([])
    options.Replace (1,1) logical = false
    options.Save (1,1) logical = true
end

validate_data(data);
[subjectIndex, sessionIndex] = locate_session(project, sessionId);
if isempty(subjectIndex), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
session = project.subjects(subjectIndex).sessions(sessionIndex);
if ~isempty(session.data_refs) && ~options.Replace
    error('LFP:SessionHasData', 'Session %s already has data; explicitly enable replacement to attach different data.', sessionId);
end
[~, ~, ~, channelTemplate, ~, ~] = lfp_project_schema();
labels = string(get_field(data, 'channelLabels', "channel_" + string((1:size(data.signal,2))')));
labels = labels(:);
channels = channelTemplate([]);
for channelIndex = 1:size(data.signal, 2)
    channel = channelTemplate;
    channel.original_label = labels(channelIndex);
    channel.display_label = labels(channelIndex);
    channel.channel_id = make_channel_id(labels(channelIndex), channelIndex, channels);
    channel.unit = string(get_field(data, 'units', "unknown"));
    mapping = find_mapping(options.ChannelMapping, labels(channelIndex));
    for name = ["display_label" "side" "region" "contacts" "reference"]
        fieldName = char(name);
        if isfield(mapping, fieldName) && strlength(string(mapping.(fieldName))) > 0
            channel.(fieldName) = string(mapping.(fieldName));
        end
    end
    channels(end + 1) = channel; %#ok<AGROW>
end
session.channels = channels;
session.data_version = lfp_data_version(data);
if isfield(project, 'storage_mode') && string(project.storage_mode) == "subject_session" && ...
        isfield(session, 'folder_relative_path') && strlength(string(session.folder_relative_path)) > 0
    relativeDataPath = fullfile(string(session.folder_relative_path), "data", "session_data.mat");
else
    % Legacy sessions retain their existing root-level data layout.
    relativeDataPath = fullfile("data", session.session_id + ".mat");
end
absoluteDataPath = fullfile(string(project.rootPath), relativeDataPath);
if ~isfolder(fileparts(absoluteDataPath)), mkdir(fileparts(absoluteDataPath)); end
payload = struct('data', data, 'session_id', session.session_id, ...
    'saved_at', string(datestr(now, 31)), 'data_version', session.data_version);
tempFile = absoluteDataPath + ".tmp_" + lfp_make_id("data");
cleanup = onCleanup(@() delete_if_present(tempFile)); %#ok<NASGU>
save(tempFile, 'payload', '-v7'); movefile(tempFile, absoluteDataPath, 'f');
sourcePath = get_source(data, 'sourceFilePath');
projectCopyPath = copy_source_file(project, session, sourcePath);
ref = struct('relative_path', relativeDataPath, 'source_path', sourcePath, ...
    'project_copy_relative_path', projectCopyPath, ...
    'source_file_name', get_source(data, 'sourceFileName'), 'segment_id', "segment_1", ...
    'sample_count', size(data.signal,1), 'channel_count', size(data.signal,2), ...
    'fs', double(data.fs), 'time_start', double(data.time(1)), ...
    'time_end', double(data.time(end)), 'channel_labels', labels);
session.data_refs = ref;
session.status = "imported";
project.subjects(subjectIndex).sessions(sessionIndex) = session;
if isfield(project, 'storage_mode') && string(project.storage_mode) == "subject_session" && ...
        isfield(session, 'folder_relative_path') && strlength(string(session.folder_relative_path)) > 0
    write_session_metadata(fullfile(string(project.rootPath), session.folder_relative_path), session);
end
if options.Save, lfp_save_project(project); end
end

function validate_data(data)
if ~isfield(data, 'signal') || ~isnumeric(data.signal) || isempty(data.signal) || ndims(data.signal) ~= 2
    error('LFP:InvalidData', 'data.signal must be a non-empty samples-by-channels numeric matrix.');
end
if ~isfield(data, 'fs') || ~isscalar(data.fs) || ~isfinite(data.fs) || data.fs <= 0
    error('LFP:InvalidData', 'data.fs must be a positive finite scalar.');
end
if ~isfield(data, 'time') || numel(data.time) ~= size(data.signal,1)
    error('LFP:InvalidData', 'data.time must contain one value per signal row.');
end
if any(isinf(double(data.signal)), 'all')
    error('LFP:InvalidData', 'data.signal cannot contain Inf.');
end
end

function [subjectIndex, sessionIndex] = locate_session(project, sessionId)
subjectIndex = []; sessionIndex = [];
for s = 1:numel(project.subjects)
    match = find(string({project.subjects(s).sessions.session_id}) == sessionId, 1);
    if ~isempty(match), subjectIndex = s; sessionIndex = match; return; end
end
end

function id = make_channel_id(label, index, existing)
base = regexprep("channel_" + label, '[^A-Za-z0-9_\-]', '_');
if strlength(base) == 0, base = "channel_" + string(index); end
id = base;
if ~isempty(existing) && any(string({existing.channel_id}) == id), id = base + "_" + string(index); end
end

function mapping = find_mapping(mappings, label)
mapping = struct();
for index = 1:numel(mappings)
    if isfield(mappings(index), 'original_label') && string(mappings(index).original_label) == label
        mapping = mappings(index); return;
    end
end
end

function value = get_field(source, name, fallback)
if isfield(source, name) && ~isempty(source.(name)), value = source.(name); else, value = fallback; end
end

function value = get_source(data, name)
value = "";
if isfield(data, 'metadata') && isstruct(data.metadata) && isfield(data.metadata, name)
    value = string(data.metadata.(name));
end
end

function relativePath = copy_source_file(project, session, sourcePath)
relativePath = "";
if strlength(string(sourcePath)) == 0 || ~isfile(sourcePath) || ...
        ~isfield(session, 'folder_relative_path') || strlength(string(session.folder_relative_path)) == 0
    return;
end
targetFolder = fullfile(string(project.rootPath), string(session.folder_relative_path), "data");
if ~isfolder(targetFolder), mkdir(targetFolder); end
[~, base, ext] = fileparts(char(sourcePath));
targetName = string(base) + string(ext);
target = fullfile(targetFolder, targetName);
suffix = 1;
while isfile(target)
    targetName = string(base) + "_" + string(suffix) + string(ext);
    target = fullfile(targetFolder, targetName); suffix = suffix + 1;
end
if ~copyfile(sourcePath, target, 'f')
    error('LFP:SourceCopyFailed', '无法复制源 CSV 到 Session/data：%s。', sourcePath);
end
relativePath = string(fullfile(string(session.folder_relative_path), "data", targetName));
end

function write_session_metadata(folder, session)
if ~isfolder(folder), mkdir(folder); end
sessionMetadata = session; %#ok<NASGU>
save(fullfile(folder, 'session.mat'), 'sessionMetadata', '-v7');
end

function delete_if_present(path)
if isfile(path), delete(path); end
end

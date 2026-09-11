function [project, report] = lfp_project_append_data(project, sessionId, data, options)
%LFP_PROJECT_APPEND_DATA Append new CSV-derived channels to a Session.
%   Each channel is cached independently. Existing channels and result files
%   are never overwritten. Duplicate source-file/column pairs and duplicate
%   labels are rejected unless the caller explicitly opts in to replacement.

arguments
    project (1,1) struct
    sessionId (1,1) string
    data (1,1) struct
    options.ChannelMapping struct = struct([])
    options.SourceFileId (1,1) string = ""
    options.SourceFileFingerprint (1,1) string = ""
    options.ImportConfig (1,1) struct = struct()
    options.AllowDuplicateLabel (1,1) logical = false
    options.ReplaceDuplicateSource (1,1) logical = false
    options.Save (1,1) logical = true
end
validate_data(data);
[subjectIndex, sessionIndex] = locate_session(project, sessionId);
if isempty(subjectIndex), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
session = project.subjects(subjectIndex).sessions(sessionIndex);
labels = string(get_field(data, 'channelLabels', "channel_" + string((1:size(data.signal,2))')));
labels = labels(:);
sourcePath = get_source(data, 'sourceFilePath');
fingerprint = options.SourceFileFingerprint;
if strlength(fingerprint) == 0 && strlength(sourcePath) > 0 && isfile(sourcePath)
    fingerprint = lfp_file_fingerprint(sourcePath);
end
sourceId = options.SourceFileId;
if strlength(sourceId) == 0
    if strlength(fingerprint) > 0
        sourceId = "file_" + extractBefore(fingerprint, min(strlength(fingerprint), 13));
    else
        sourceId = "file_" + lfp_make_id('source');
    end
end
sourceColumns = 1:size(data.signal, 2);
if isfield(data, 'metadata') && isstruct(data.metadata) && isfield(data.metadata, 'sourceColumns')
    candidate = double(data.metadata.sourceColumns(:)');
    if numel(candidate) == numel(sourceColumns) && all(isfinite(candidate)), sourceColumns = candidate; end
end
existing = session.channels;
newChannels = existing([]); cachePaths = strings(0,1); newIds = strings(0,1);
for k = 1:numel(labels)
    sameSource = false;
    if ~isempty(existing) && isfield(existing, 'source_file_id') && isfield(existing, 'source_column')
        sameSource = any(string({existing.source_file_id}) == sourceId & [existing.source_column] == sourceColumns(k));
    end
    if sameSource && ~options.ReplaceDuplicateSource
        error('LFP:DuplicateChannelSource', 'Source %s column %d is already imported in Session %s.', sourceId, sourceColumns(k), sessionId);
    end
    sameLabel = (~isempty(existing) && any(string({existing.original_label}) == labels(k))) || ...
        (~isempty(newChannels) && any(string({newChannels.original_label}) == labels(k)));
    if sameLabel && ~options.AllowDuplicateLabel
        error('LFP:DuplicateChannelLabel', 'Channel label %s already exists; explicit duplicate-label permission is required.', labels(k));
    end
    channel = channel_template();
    channel.session_id = sessionId; channel.original_label = labels(k); channel.display_label = labels(k);
    channel.channel_id = make_channel_id(labels(k), k, [existing newChannels]);
    channel.source_file_id = sourceId; channel.source_column = sourceColumns(k);
    channel.sampling_rate_hz = double(data.fs); channel.sample_count = size(data.signal,1);
    channel.time_start = double(data.time(1)); channel.time_end = double(data.time(end));
    channel.unit = string(get_field(data, 'units', 'unknown')); channel.enabled = true;
    channel.data_revision = lfp_data_version(struct('signal', data.signal(:,k), 'fs', data.fs, 'time', data.time, 'channelLabels', labels(k)));
    channel.quality_status = "unassessed";
    mapping = find_mapping(options.ChannelMapping, labels(k));
    for name = ["display_label" "side" "region" "contacts" "reference"]
        if isfield(mapping, char(name)) && strlength(string(mapping.(char(name)))) > 0
            channel.(char(name)) = string(mapping.(char(name)));
        end
    end
    channel.source_metadata = struct('source_file_name', get_source(data, 'sourceFileName'), ...
        'source_file_path', sourcePath, 'source_column', sourceColumns(k), 'source_file_id', sourceId, ...
        'source_file_fingerprint', fingerprint);
    cache = lfp_project_save_channel_cache(project, session, channel, double(data.time(:)), double(data.signal(:,k)), channel.source_metadata);
    channel.cache_relative_path = cache;
    newChannels(end+1) = channel; %#ok<AGROW>
    cachePaths(end+1,1) = cache; %#ok<AGROW>
    newIds(end+1,1) = channel.channel_id; %#ok<AGROW>
end
% If a replacement was requested, this function still refuses to destroy an
% existing cache. The caller must remove the old channel explicitly first.
session.channels = [existing newChannels];
session.data_version = combine_versions(session.data_version, string({newChannels.data_revision}));
session.status = "imported";
ref = data_ref_template();
ref.relative_path = cachePaths(1); ref.source_path = sourcePath;
ref.project_copy_relative_path = copy_source_file(project, session, sourcePath);
ref.source_file_name = get_source(data, 'sourceFileName'); ref.segment_id = "import_" + string(numel(session.data_refs)+1);
ref.sample_count = size(data.signal,1); ref.channel_count = size(data.signal,2); ref.fs = double(data.fs);
ref.time_start = double(data.time(1)); ref.time_end = double(data.time(end)); ref.channel_labels = labels;
ref.channel_ids = newIds; ref.cache_relative_paths = cachePaths; ref.source_file_id = sourceId;
ref.source_file_fingerprint = fingerprint; ref.import_config = options.ImportConfig; ref.time_unit = "s";
ref.signal_unit = string(get_field(data, 'units', 'unknown')); ref.imported_at = string(datestr(now, 31));
if isempty(session.data_refs), session.data_refs = ref; else, session.data_refs(end+1) = ref; end
project.subjects(subjectIndex).sessions(sessionIndex) = session;
lfp_project_write_channel_manifest(project, session);
if isfield(project, 'storage_mode') && string(project.storage_mode) == "subject_session" && strlength(string(session.folder_relative_path)) > 0
    write_session_metadata(fullfile(string(project.rootPath), session.folder_relative_path), session);
end
report = struct('sessionId', sessionId, 'sourceFileId', sourceId, 'sourceFingerprint', fingerprint, ...
    'addedChannelIds', newIds, 'addedChannelLabels', labels, 'cacheRelativePaths', cachePaths, ...
    'reusedExisting', false, 'warnings', strings(0,1));
if options.Save, lfp_save_project(project); end
end

function channel = channel_template()
[~,~,~,channel,~,~] = lfp_project_schema();
end
function ref = data_ref_template()
% Explicit fields keep this function compatible with pre-v4 in-memory projects.
ref = struct('relative_path',"",'source_path',"",'project_copy_relative_path',"",'source_file_name',"",'segment_id',"",'sample_count',0,'channel_count',0,'fs',NaN,'time_start',NaN,'time_end',NaN,'channel_labels',strings(0,1),'channel_ids',strings(0,1),'cache_relative_paths',strings(0,1),'source_file_id',"",'source_file_fingerprint',"",'import_config',struct(),'time_unit',"s",'signal_unit',"",'imported_at',"",'cache_version',"1");
end
function validate_data(data)
if ~isfield(data,'signal') || ~isnumeric(data.signal) || isempty(data.signal) || ndims(data.signal) ~= 2, error('LFP:InvalidData','data.signal must be a non-empty matrix.'); end
if ~isfield(data,'time') || numel(data.time) ~= size(data.signal,1), error('LFP:InvalidData','data.time must match signal rows.'); end
if ~isfield(data,'fs') || ~isscalar(data.fs) || ~isfinite(data.fs) || data.fs<=0, error('LFP:InvalidData','data.fs must be positive.'); end
if any(isinf(data.signal),'all') || any(~isfinite(data.time(:))) || any(diff(double(data.time(:)))<0), error('LFP:InvalidData','Signal/time contains invalid values.'); end
end
function [si,ki] = locate_session(project,id)
si=[];ki=[];for s=1:numel(project.subjects),k=find(string({project.subjects(s).sessions.session_id})==id,1);if ~isempty(k),si=s;ki=k;return;end,end
end
function value = combine_versions(old, new)
value = string(old); for k=1:numel(new), value = value + "_" + string(new(k)); end
end
function id = make_channel_id(label,index,existing)
base=regexprep("channel_"+label,'[^A-Za-z0-9_\-]','_');if strlength(base)==0,base="channel_"+string(index);end;id=base;counter=index;while ~isempty(existing)&&any(string({existing.channel_id})==id),counter=counter+1;id=base+"_"+string(counter);end
end
function mapping=find_mapping(mappings,label)
mapping=struct();for k=1:numel(mappings),if isfield(mappings(k),'original_label')&&string(mappings(k).original_label)==label,mapping=mappings(k);return;end,end
end
function value=get_field(s,n,f),if isstruct(s)&&isfield(s,n)&&~isempty(s.(n)),value=s.(n);else,value=f;end,end
function value=get_source(data,name),value="";if isfield(data,'metadata')&&isstruct(data.metadata)&&isfield(data.metadata,name),value=string(data.metadata.(name));end,end
function value=copy_source_file(project,session,sourcePath)
value="";if strlength(sourcePath)==0||~isfile(sourcePath)||~isfield(session,'folder_relative_path')||strlength(string(session.folder_relative_path))==0,return;end
folder=fullfile(string(project.rootPath),string(session.folder_relative_path),'data');if ~isfolder(folder),mkdir(folder);end
[~,base,ext]=fileparts(char(sourcePath));target=fullfile(folder,string(base)+string(ext));suffix=1;while isfile(target),target=fullfile(folder,string(base)+"_"+string(suffix)+string(ext));suffix=suffix+1;end
if ~copyfile(sourcePath,target,'f'),error('LFP:SourceCopyFailed','Cannot copy source CSV: %s',sourcePath);end
value=string(fullfile(string(session.folder_relative_path),'data',string(base)+ternary(suffix==1,"", "_"+string(suffix-1))+string(ext)));
end
function value=ternary(condition,a,b),if condition,value=a;else,value=b;end,end
function write_session_metadata(folder,session),if ~isfolder(folder),mkdir(folder);end;sessionMetadata=session;save(fullfile(folder,'session.mat'),'sessionMetadata','-v7');end

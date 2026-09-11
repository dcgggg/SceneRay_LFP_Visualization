function preview = lfp_preview_legacy_dataset(filePath)
%LFP_PREVIEW_LEGACY_DATASET Inspect a legacy analysis_results.mat file.
%   This function never guesses a Subject or Session identity and never
%   writes files.  Use lfp_migrate_legacy_dataset after explicit assignment.

arguments
    filePath (1,1) string
end
if ~isfile(filePath), error('LFP:LegacyFileNotFound', 'File not found: %s', filePath); end
loaded = load(filePath);
if isfield(loaded, 'data'), data = loaded.data;
elseif isfield(loaded, 'payload') && isfield(loaded.payload, 'data'), data = loaded.payload.data;
else, error('LFP:LegacyDataNotFound', 'No data variable found in legacy file.'); end
preview = struct('filePath', filePath, 'sourceFileName', "", 'sampleCount', 0, ...
    'channelCount', 0, 'channelLabels', strings(0,1), 'fs', NaN, ...
    'hasAnalysisResults', false, 'warnings', strings(0,1));
preview.sampleCount = size(data.signal,1); preview.channelCount = size(data.signal,2);
preview.fs = double(get_field(data, 'fs', NaN));
preview.channelLabels = string(get_field(data, 'channelLabels', "channel_" + string((1:preview.channelCount)')));
if isfield(data, 'metadata') && isfield(data.metadata, 'sourceFileName'), preview.sourceFileName = string(data.metadata.sourceFileName); end
preview.hasAnalysisResults = isfield(data, 'spectrum') || isfield(data, 'bandPower') || isfield(data, 'spectralParameters');
preview.warnings(end+1) = "需要用户明确指定 subject_id、session_id 和 visit_label；不会从文件名自动推断。";
end

function value = get_field(s,name,fallback)
if isfield(s,name) && ~isempty(s.(name)), value=s.(name); else, value=fallback; end
end

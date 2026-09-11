function summary = lfp_build_psd_comparison(project, runIds, channelMapping, groupDefs)
%LFP_BUILD_PSD_COMPARISON Collect compatible Session PSDs for comparison.
%   PSDs are kept linear in the returned matrix.  Group means use equal
%   subject weighting: Session PSDs are averaged within each subject before
%   the group mean is calculated.  No frequency interpolation or extrapolation
%   is performed; mismatched grids are reported as incompatible.

arguments
    project (1,1) struct
    runIds string
    channelMapping struct = struct([])
    groupDefs struct = struct([])
end

runIds = string(runIds(:));
summary = struct('status', "ok", 'message', "", 'frequencyHz', zeros(0,1), ...
    'psd', zeros(0,0), 'session_ids', strings(0,1), 'subject_ids', strings(0,1), ...
    'channel_labels', strings(0,1), 'group_labels', strings(0,1), ...
    'method', strings(0,1), 'psd_units', strings(0,1), 'parameter_signature', "", ...
    'aggregation', "linear_psd_then_log_if_displayed", ...
    'group_labels_unique', strings(0,1), 'group_mean_psd', zeros(0,0), ...
    'group_sd_psd', zeros(0,0), 'group_subject_count', zeros(0,1), ...
    'group_subject_ids', {{}}, 'errorDefinition', "SD across subject-level representative PSDs");

for k = 1:numel(runIds)
    if strlength(runIds(k)) == 0, continue; end
    try
        [run, results] = lfp_load_analysis_run(project, runIds(k));
        if ~isfield(results, 'psdResult') || ~isstruct(results.psdResult), continue; end
        psdResult = results.psdResult;
        f = double(psdResult.frequencyHz(:)); p = double(psdResult.psd);
        if size(p,1) ~= numel(f) && size(p,2) == numel(f), p = p.'; end
        if size(p,1) ~= numel(f), summary.status = "incompatible_dimensions"; summary.message = "PSD维度与频率轴不一致。"; continue; end
        [session, subject] = find_session(project, run.session_id);
        if isempty(session), continue; end
        [channelIndex, label] = mapped_channel_index(run, session, channelMapping);
        if isempty(channelIndex) || channelIndex > size(p,2), continue; end
        signature = psd_signature(psdResult);
        units = string(get_field(psdResult, 'psdUnits', "unknown"));
        if isempty(summary.frequencyHz)
            summary.frequencyHz = f; summary.method = string(get_field(psdResult, 'method', "unknown"));
            summary.psd_units = units; summary.parameter_signature = signature;
        elseif numel(f) ~= numel(summary.frequencyHz) || any(abs(f-summary.frequencyHz) > max(eps(max(abs(f))),1e-12))
            summary.status = "incompatible_frequency_grid";
            summary.message = "选定 PSD 的频率网格不一致；请统一 PSD 窗长/NFFT 后重算。";
            continue;
        elseif signature ~= summary.parameter_signature || units ~= summary.psd_units
            summary.status = "incompatible_parameters";
            summary.message = "选定 PSD 的方法、窗参数或功率单位不一致；请统一参数后重算。";
            continue;
        end
        group = mapping_group(channelMapping, run.session_id);
        if strlength(group) == 0, group = string(subject.group); end
        if strlength(group) == 0, group = string(session.visit_label); end
        if strlength(group) == 0, group = "未分组"; end
        summary.psd(:,end+1) = p(:,channelIndex); %#ok<AGROW>
        summary.session_ids(end+1,1) = string(session.session_id); %#ok<AGROW>
        summary.subject_ids(end+1,1) = string(subject.subject_id); %#ok<AGROW>
        summary.channel_labels(end+1,1) = label; %#ok<AGROW>
        summary.group_labels(end+1,1) = group; %#ok<AGROW>
    catch exception
        summary.status = "failed";
        summary.message = string(exception.message);
    end
end
if isempty(summary.psd)
    if summary.status == "ok", summary.status = "empty"; summary.message = "没有可用 PSD 结果。"; end
    return;
end
summary.group_labels_unique = unique(summary.group_labels, 'stable');
summary.group_mean_psd = NaN(numel(summary.frequencyHz), numel(summary.group_labels_unique));
summary.group_sd_psd = NaN(size(summary.group_mean_psd));
summary.group_subject_count = zeros(numel(summary.group_labels_unique),1);
summary.group_subject_ids = cell(numel(summary.group_labels_unique),1);
for groupIndex = 1:numel(summary.group_labels_unique)
    group = summary.group_labels_unique(groupIndex);
    subjects = unique(summary.subject_ids(summary.group_labels == group), 'stable');
    representatives = NaN(numel(summary.frequencyHz), numel(subjects));
    for subjectIndex = 1:numel(subjects)
        columns = summary.group_labels == group & summary.subject_ids == subjects(subjectIndex);
        representatives(:,subjectIndex) = mean(summary.psd(:,columns), 2, 'omitnan');
    end
    summary.group_mean_psd(:,groupIndex) = mean(representatives, 2, 'omitnan');
    if numel(subjects) > 1, summary.group_sd_psd(:,groupIndex) = std(representatives, 0, 2, 'omitnan'); end
    summary.group_subject_count(groupIndex) = numel(subjects);
    summary.group_subject_ids{groupIndex} = subjects;
end
if isempty(groupDefs), groupDefs = repmat(struct('group_label', ""), numel(summary.group_labels_unique), 1); end %#ok<NASGU>
end

function [session, subject] = find_session(project, sessionId)
session = []; subject = [];
for subjectIndex = 1:numel(project.subjects)
    k = find(string({project.subjects(subjectIndex).sessions.session_id}) == string(sessionId), 1);
    if ~isempty(k), session = project.subjects(subjectIndex).sessions(k); subject = project.subjects(subjectIndex); return; end
end
end

function [index, label] = mapped_channel_index(run, session, mapping)
index = 1; label = "channel 1";
entry = struct();
for k = 1:numel(mapping)
    if isfield(mapping(k), 'session_id') && string(mapping(k).session_id) == string(session.session_id), entry = mapping(k); break; end
end
if ~isempty(fieldnames(entry)) && isfield(entry, 'channel_id') && strlength(string(entry.channel_id)) > 0
    index = find(string(run.channel_ids) == string(entry.channel_id), 1);
end
if isempty(index) && ~isempty(fieldnames(entry)) && isfield(entry, 'channel_label')
    index = find(string(run.channel_labels) == string(entry.channel_label), 1);
end
if isempty(index), index = []; return; end
if index <= numel(session.channels), label = string(session.channels(index).display_label); if strlength(label)==0, label=string(session.channels(index).original_label); end
elseif index <= numel(run.channel_labels), label = string(run.channel_labels(index)); end
end

function group = mapping_group(mapping, sessionId)
group = "";
for k = 1:numel(mapping)
    if isfield(mapping(k), 'session_id') && string(mapping(k).session_id) == string(sessionId) && isfield(mapping(k), 'group_label')
        group = string(mapping(k).group_label); return;
    end
end
end

function value = get_field(s, name, fallback)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = fallback; end
end

function signature = psd_signature(psdResult)
% Keep comparison aggregation scientific: mismatched estimators/settings are
% never merged merely because their frequency vectors happen to match.
params=get_field(psdResult,'parameters',struct());
method=get_field(psdResult,'methodCanonical',"");
if strlength(string(method))==0, method=get_field(psdResult,'method',"unknown"); end
window=get_field(psdResult,'windowSeconds',get_field(params,'windowSeconds',NaN));
overlap=get_field(psdResult,'overlapFraction',get_field(params,'overlapFraction',NaN));
nfft=get_field(psdResult,'nfft',get_field(params,'nfft',NaN));
nw=get_field(psdResult,'timeBandwidthProduct',get_field(params,'timeBandwidthProduct',NaN));
k=get_field(psdResult,'taperCount',get_field(params,'taperCount',NaN));
aggregation=get_field(psdResult,'aggregationMethod',get_field(params,'aggregationMethod',"unknown"));
signature=string(method)+"|"+string(window)+"|"+string(overlap)+"|"+string(nfft)+"|"+string(nw)+"|"+string(k)+"|"+string(aggregation);
end

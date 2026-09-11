function [project, comparison] = lfp_compare_project(project, comparisonSpec, options)
%LFP_COMPARE_PROJECT Query saved Session results without merging raw data.
%   [PROJECT,COMPARISON] = LFP_COMPARE_PROJECT(PROJECT,SPEC) creates a
%   reproducible comparison record and a long table.  SPEC.type is
%   "within_subject", "between_subjects", or "custom"; SPEC.session_ids
%   explicitly identifies records.  Missing results can be computed by
%   setting ComputeMissing=true.  Parameter-incompatible runs are reported
%   instead of silently mixed.

arguments
    project (1,1) struct
    comparisonSpec (1,1) struct
    options.Config (1,1) struct = struct()
    options.ComputeMissing (1,1) logical = false
    options.UnifyParameters (1,1) logical = false
    options.Save (1,1) logical = true
end

[~, ~, ~, ~, ~, template] = lfp_project_schema();
comparison = template;
comparison.comparison_id = lfp_make_id("comparison");
comparison.type = lower(string(get_field(comparisonSpec, 'type', "custom")));
comparison.session_ids = string(get_field(comparisonSpec, 'session_ids', strings(0,1))); comparison.session_ids = comparison.session_ids(:);
if isempty(comparison.session_ids), error('LFP:NoSessionsSelected', 'comparisonSpec.session_ids is required.'); end
comparison.metric = string(get_field(comparisonSpec, 'metric', "totalPower"));
comparison.bands = string(get_field(comparisonSpec, 'bands', strings(0,1))); comparison.bands = comparison.bands(:);
comparison.aggregation = string(get_field(comparisonSpec, 'aggregation', "session"));
comparison.plot_settings = get_field(comparisonSpec, 'plot_settings', struct());
comparison.channel_mapping = get_field(comparisonSpec, 'channel_mapping', struct([]));
comparison.grouping_basis = string(get_field(comparisonSpec, 'grouping_basis', "custom"));
comparison.group_defs = get_field(comparisonSpec, 'group_defs', struct([]));
comparison.created_at = string(datestr(now, 31));
cfg = project.defaultConfig; if ~isempty(fieldnames(options.Config)), cfg = options.Config; end
targetConfigId = lfp_config_fingerprint(cfg); comparison.target_config_id = targetConfigId;

runIds = strings(numel(comparison.session_ids),1); missing = strings(0,1);
for index = 1:numel(comparison.session_ids)
    sessionId = comparison.session_ids(index); session = find_session(project, sessionId);
    if isempty(session), comparison.warnings(end+1,1) = "Session not found: " + sessionId; continue; end %#ok<AGROW>
    run = find_latest_run(project, session, targetConfigId);
    if isempty(run), missing(end+1,1) = sessionId; else, runIds(index) = run.run_id; end %#ok<AGROW>
end
if ~isempty(missing) && options.ComputeMissing
    [project, ~] = lfp_analyze_project(project, missing, Config=cfg, Force=options.UnifyParameters, Save=options.Save);
    for index = 1:numel(missing)
        session = find_session(project, missing(index)); run = find_latest_run(project, session, targetConfigId);
        if ~isempty(run), runIds(comparison.session_ids == missing(index)) = run.run_id; end
    end
end
if any(strlength(runIds)==0)
    comparison.status = "incomplete";
    comparison.warnings(end+1,1) = "部分 Session 缺少目标配置的有效 AnalysisRun；请启用补算或统一参数重新分析。";
else
    comparison.status = "ok";
end
comparison.run_ids = runIds;
comparison.subject_ids = strings(0,1);
comparison.session_count = nnz(strlength(runIds) > 0);
rows = empty_long_table();
configIds = strings(0,1);
for index = 1:numel(runIds)
    if strlength(runIds(index)) == 0, continue; end
    [run, results] = lfp_load_analysis_run(project, runIds(index));
    configIds(end+1,1) = string(run.config_id); %#ok<AGROW>
    [session, subject] = find_session(project, run.session_id); subjectId = session.subject_id;
    session.subject_group = string(subject.group);
    comparison.subject_ids(end+1,1) = subjectId; %#ok<AGROW>
    if ~isfield(results, 'bandResult') || ~isstruct(results.bandResult) || ~isfield(results.bandResult, 'table'), continue; end
    rows = append_band_rows(rows, results.bandResult.table, session, run, comparison.metric, ...
        comparison.bands, comparison.channel_mapping, comparison.grouping_basis);
end
if numel(unique(configIds)) > 1
    comparison.status = "incompatible_parameters";
    comparison.warnings(end+1,1) = "选定结果的计算配置不一致；请统一参数后再比较。";
end
comparison.result_table = rows;
comparison.subject_ids = unique(comparison.subject_ids, 'stable');
comparison.subject_count = numel(comparison.subject_ids);
if isempty(comparison.group_defs)
    comparison.group_defs = infer_group_defs(project, comparison.session_ids, comparison.channel_mapping, comparison.grouping_basis);
end
comparison.psd_summary = lfp_build_psd_comparison(project, runIds, comparison.channel_mapping, comparison.group_defs);
if options.Save
    if ~isfield(project, 'comparisons') || isempty(project.comparisons), project.comparisons = template([]); end
    project.comparisons(end+1) = comparison;
    comparisonFolder = "comparisons";
    if isfield(project,'paths') && isfield(project.paths,'comparisons') && strlength(string(project.paths.comparisons))>0
        comparisonFolder=string(project.paths.comparisons);
    end
    target = fullfile(string(project.rootPath), comparisonFolder, comparison.comparison_id + ".mat");
    if ~isfolder(fileparts(target)), mkdir(fileparts(target)); end
    savedComparison = comparison; %#ok<NASGU>
    save(target, 'savedComparison', '-v7');
    lfp_save_project(project);
end
end

function rows = append_band_rows(rows, tableData, session, run, metric, selectedBands, channelMapping, groupingBasis)
if isempty(tableData), return; end
if isempty(selectedBands), selectedBands = string(tableData.band); end
for index = 1:height(tableData)
    band = string(tableData.band(index)); if ~any(selectedBands == band), continue; end
    if ~ismember(metric, string(tableData.Properties.VariableNames)), continue; end
    channelIndex = tableData.channelIndex(index); channelId = ""; label = string(tableData.channelLabel(index));
    if channelIndex <= numel(session.channels), channelId = string(session.channels(channelIndex).channel_id); end
    [include, targetLabel, groupLabel] = mapped_channel(channelMapping, session.session_id, channelId, label);
    if ~include, continue; end
    if strlength(groupLabel) == 0, groupLabel = default_group_label(session, groupingBasis); end
    value = tableData.(char(metric))(index);
    qc = "ok";
    if ismember('status', tableData.Properties.VariableNames), qc = string(tableData.status(index)); end
    one = table(string(session.subject_id), string(session.session_id), string(session.visit_label), ...
        channelId, targetLabel, string(run.run_id), "", band, metric, value, metric_unit(metric, session), ...
        "session", string(run.config_id), qc, groupLabel, default_subject_group(session), ...
        'VariableNames', rows.Properties.VariableNames);
    rows = [rows; one]; %#ok<AGROW>
end

function [include, targetLabel, groupLabel] = mapped_channel(mapping, sessionId, channelId, originalLabel)
include = true; targetLabel = originalLabel; groupLabel = "";
if isempty(mapping), return; end
include = false;
% This helper is nested in append_band_rows.  Do not reuse the parent's
% row-loop variable: nested MATLAB functions share captured variables.
for mappingIndex = 1:numel(mapping)
    entry = mapping(mappingIndex);
    if isfield(entry, 'session_id') && string(entry.session_id) ~= string(sessionId), continue; end
    idMatches = isfield(entry, 'channel_id') && strlength(string(entry.channel_id)) > 0 && string(entry.channel_id) == channelId;
    labelMatches = isfield(entry, 'channel_label') && strlength(string(entry.channel_label)) > 0 && string(entry.channel_label) == originalLabel;
    if idMatches || labelMatches
        include = true;
        if isfield(entry, 'target_label') && strlength(string(entry.target_label)) > 0
            targetLabel = string(entry.target_label);
        end
        if isfield(entry, 'group_label'), groupLabel = string(entry.group_label); end
        return;
    end
end
end
end

function unit = metric_unit(metric, session)
unit = "uV^2";
if contains(lower(string(metric)), "relative"), unit = "fraction";
elseif contains(lower(string(metric)), "log"), unit = "log10(uV^2)";
elseif contains(lower(string(metric)), "aperiodic") || contains(lower(string(metric)), "periodic")
    unit = "uV^2";
end
if ~isempty(session.channels) && isfield(session.channels(1), 'unit') && strlength(string(session.channels(1).unit)) > 0
    base = string(session.channels(1).unit);
    if unit == "uV^2", unit = base + "^2"; elseif unit == "log10(uV^2)", unit = "log10(" + base + "^2)"; end
end
end

function rows = empty_long_table()
names = {'subject_id','session_id','visit_label','channel_id','channel_label', ...
    'run_id','epoch_id','band','metric','value','unit','aggregation','config_id','qc_status', ...
    'group_label','subject_group'};
types = {'string','string','string','string','string','string','string','string', ...
    'string','double','string','string','string','string','string','string'};
rows = table('Size', [0 numel(names)], 'VariableTypes', types, 'VariableNames', names);
end

function value = default_group_label(session, groupingBasis)
switch lower(string(groupingBasis))
    case "subject_group", value = default_subject_group(session);
    case "visit", value = string(session.visit_label);
    otherwise, value = "Group 1";
end
if strlength(value) == 0, value = "未分组"; end
end

function value = default_subject_group(session)
value = "";
if isfield(session, 'subject_group'), value = string(session.subject_group); end
% The caller supplies only Session metadata; subject group is filled by the
% explicit mapping in the GUI or falls back to the visit/custom label.
if strlength(value) == 0, value = "未分组"; end
end

function defs = infer_group_defs(project, sessionIds, mapping, groupingBasis)
labels = strings(0,1);
for k = 1:numel(sessionIds)
    [session,subject] = find_session(project, sessionIds(k));
    if isempty(session), continue; end
    label = "";
    for m = 1:numel(mapping)
        if isfield(mapping(m), 'session_id') && string(mapping(m).session_id) == string(session.session_id) && isfield(mapping(m), 'group_label')
            label = string(mapping(m).group_label); break;
        end
    end
    if strlength(label) == 0
        switch lower(string(groupingBasis))
            case "subject_group", label = string(subject.group);
            case "visit", label = string(session.visit_label);
            otherwise, label = "Group 1";
        end
    end
    if strlength(label) == 0, label = "未分组"; end
    labels(end+1,1) = label; %#ok<AGROW>
end
labels = unique(labels, 'stable');
defs = repmat(struct('group_label', "", 'basis', string(groupingBasis), ...
    'session_ids', strings(0,1), 'subject_ids', strings(0,1)), numel(labels), 1);
for k = 1:numel(labels)
    defs(k).group_label = labels(k);
    mask = false(numel(sessionIds),1);
    for sessionIndex = 1:numel(sessionIds)
        [session,subject] = find_session(project, sessionIds(sessionIndex));
        if isempty(session), continue; end
        label = "";
        for mappingIndex = 1:numel(mapping)
            if isfield(mapping(mappingIndex), 'session_id') && string(mapping(mappingIndex).session_id) == string(session.session_id) && isfield(mapping(mappingIndex), 'group_label')
                label = string(mapping(mappingIndex).group_label); break;
            end
        end
        if strlength(label) == 0
            switch lower(string(groupingBasis)), case "subject_group", label=string(subject.group); case "visit", label=string(session.visit_label); otherwise, label="Group 1"; end
        end
        if strlength(label)==0, label="未分组"; end
        mask(sessionIndex)=label==labels(k);
    end
    defs(k).session_ids = string(sessionIds(mask));
    subjectIds = strings(0,1);
    for sessionIndex = find(mask(:))'
        [~,subject] = find_session(project, sessionIds(sessionIndex)); if ~isempty(subject), subjectIds(end+1,1)=string(subject.subject_id); end %#ok<AGROW>
    end
    defs(k).subject_ids = unique(subjectIds, 'stable');
end
end

function [session, subject] = find_session(project, sessionId)
session = []; subject = [];
for s=1:numel(project.subjects)
    idx=find(string({project.subjects(s).sessions.session_id})==string(sessionId),1);
        if ~isempty(idx), session=project.subjects(s).sessions(idx); subject=project.subjects(s); return; end
end
end

function run = find_latest_run(project, session, configId)
run=[]; if isempty(session) || isempty(project.analysisRuns), return; end
for k=numel(project.analysisRuns):-1:1
    candidate=project.analysisRuns(k);
    if string(candidate.session_id)==string(session.session_id) && string(candidate.config_id)==string(configId) && ...
            isfile(fullfile(string(project.rootPath), string(candidate.result_ref))) && string(candidate.status) ~= "failed"
        run=candidate; return;
    end
end
end

function value = get_field(s,name,fallback)
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), value=s.(name); else, value=fallback; end
end

function [project, summary] = lfp_analyze_project(project, sessionIds, options)
%LFP_ANALYZE_PROJECT Analyze independent Sessions with result reuse.
%   [PROJECT,SUMMARY] = LFP_ANALYZE_PROJECT(PROJECT, SESSIONIDS) loads each
%   Session's raw data, runs the existing artifact -> PSD -> specparam ->
%   band-power pipeline, and saves a versioned AnalysisRun.  A valid run is
%   reused when input data and computation configuration fingerprints match.
%   Sessions are never concatenated; one failure does not stop other ones.

arguments
    project (1,1) struct
    sessionIds string = strings(0, 1)
    options.Config (1,1) struct = struct()
    options.Force (1,1) logical = false
    options.ComputeSpecparam (1,1) logical = true
    options.ComputeBandPower (1,1) logical = true
    options.Save (1,1) logical = true
    options.ProgressCallback = []
    options.LockToken (1,1) struct = struct()
end

if isempty(sessionIds), sessionIds = all_session_ids(project); end
sessionIds = string(sessionIds(:));
cfg = project.defaultConfig;
if ~isempty(fieldnames(options.Config)), cfg = options.Config; end
requestedModules = struct('specparam', logical(options.ComputeSpecparam), ...
    'band_power', logical(options.ComputeBandPower));
configId = lfp_analysis_config_fingerprint(cfg, requestedModules);
% Result payloads are written even when Save=false (that option controls the
% project index only), therefore the whole analysis transaction must hold the
% same project lock.  Batch/compare callers can pass their existing token.
lock = options.LockToken;
if isempty(fieldnames(lock))
    lock = lfp_project_acquire_lock(string(project.rootPath));
    cleanupLock = onCleanup(@()lfp_project_release_lock(lock)); %#ok<NASGU>
end
summary = empty_summary(sessionIds);
for index = 1:numel(sessionIds)
    if ~isempty(options.ProgressCallback), options.ProgressCallback((index-1)/max(numel(sessionIds),1), "Session " + sessionIds(index)); end
    sessionIndex = locate_session(project, sessionIds(index));
    if isempty(sessionIndex)
        summary(index).status = "failed"; summary(index).errorMessage = "Session not found"; continue;
    end
    [subjectIndex, localSessionIndex] = deal(sessionIndex(1), sessionIndex(2));
    session = project.subjects(subjectIndex).sessions(localSessionIndex);
    try
        if should_analyze_channels(session)
            [project, independentRun, ~, independentSummary] = lfp_analyze_independent_channels(project, session.session_id, cfg, ...
                ComputeSpecparam=options.ComputeSpecparam, ComputeBandPower=options.ComputeBandPower, Save=options.Save, ...
                Force=options.Force, ProgressCallback=options.ProgressCallback, LockToken=lock);
            summary(index) = independentSummary;
            continue;
        end
        existing = find_reusable_run(project, session, cfg, requestedModules, options.Force);
        if ~isempty(existing)
            summary(index).status = "reused"; summary(index).runId = existing.run_id; summary(index).configId = configId;
            continue;
        end
        [data, ~] = lfp_project_get_session_data(project, session.session_id);
        data = standardize_analysis_data(data);
        run = make_run(session, data, cfg, configId, requestedModules);
        [artifactResult, cleanData] = run_artifact(data, cfg.artifact);
        run.module_status.artifact = "ok";
        psdResult = computeLfpPsd(cleanData, artifactResult, cfg.psd);
        validPsd = get_field_local(psdResult, 'validChannelMask', true(1,size(data.signal,2)));
        if all(validPsd), run.module_status.psd = "ok"; else, run.module_status.psd = "failed"; end
        modelResult = struct([]);
        if options.ComputeSpecparam && all(validPsd)
            try
                modelResult = parameterizePowerSpectrum(psdResult.frequencyHz, psdResult.psd, cfg.fooof);
                run.module_status.specparam = summarize_model_status(modelResult);
            catch exception
                run.module_status.specparam = "failed";
                run.warnings(end + 1) = "specparam: " + string(exception.message); %#ok<AGROW>
            end
        elseif options.ComputeSpecparam
            run.module_status.specparam = "not_run_psd_invalid";
            run.warnings(end + 1) = "specparam skipped because one or more channels has no valid PSD windows."; %#ok<AGROW>
        else
            run.module_status.specparam = "not_requested";
        end
        bandResult = struct();
        if options.ComputeBandPower && all(validPsd)
            try
                bandResult = computeBandPower(psdResult, modelResult, cfg.bands);
                run.module_status.band_power = "ok";
            catch exception
                run.module_status.band_power = "failed";
                run.warnings(end + 1) = "band power: " + string(exception.message); %#ok<AGROW>
            end
        elseif options.ComputeBandPower
            run.module_status.band_power = "not_run_psd_invalid";
            run.warnings(end + 1) = "band power skipped because one or more channels has no valid PSD windows."; %#ok<AGROW>
        else
            run.module_status.band_power = "not_requested";
        end
        run.status = stage_status(run.module_status);
        run.summary = struct('channel_count', size(data.signal, 2), ...
            'sample_count', size(data.signal, 1), 'frequency_count', numel(psdResult.frequencyHz), ...
            'specparam_peak_counts', peak_counts(modelResult), ...
            'band_power_rows', get_band_rows(bandResult));
        if isfield(project, 'storage_mode') && string(project.storage_mode) == "subject_session" && ...
                isfield(session, 'folder_relative_path') && strlength(string(session.folder_relative_path)) > 0
            run.result_ref = fullfile(string(session.folder_relative_path), "results", run.run_id + ".mat");
        else
            % Legacy projects retain the root-level results layout.
            run.result_ref = fullfile("results", run.run_id + ".mat");
        end
        payload = struct('run', run, 'artifactResult', artifactResult, ...
            'psdResult', psdResult, 'modelResult', modelResult, ...
            'bandResult', bandResult, 'metadata', data.metadata, ...
            'processingHistory', get_field(data, 'processingHistory', struct()));
        resultPath = fullfile(string(project.rootPath), run.result_ref);
        if ~isfolder(fileparts(resultPath)), mkdir(fileparts(resultPath)); end
        tempPath = resultPath + ".tmp_" + lfp_make_id("result");
        cleanup = onCleanup(@() delete_if_present(tempPath)); %#ok<NASGU>
        save(tempPath, 'payload', '-v7'); movefile(tempPath, resultPath, 'f');
        project.analysisRuns(end + 1) = run;
        project.subjects(subjectIndex).sessions(localSessionIndex).analysis_run_ids(end+1,1) = run.run_id;
        project.subjects(subjectIndex).sessions(localSessionIndex).status = "analyzed";
        summary(index).status = run.status; summary(index).runId = run.run_id; summary(index).configId = configId;
        summary(index).warnings = run.warnings;
        if options.Save, [~, project] = lfp_save_project(project, LockToken=lock); end
    catch exception
        summary(index).status = "failed"; summary(index).errorMessage = string(exception.message);
        summary(index).errorIdentifier = string(exception.identifier);
    end
end
if ~isempty(options.ProgressCallback), options.ProgressCallback(1, "Project analysis complete"); end
end

function run = make_run(session, data, cfg, configId, requestedModules)
[~, ~, ~, ~, template, ~] = lfp_project_schema();
run = template;
run.run_id = lfp_make_id("run"); run.session_id = session.session_id;
run.input_data_version = session.data_version;
run.channel_ids = string({session.channels.channel_id})';
run.channel_revisions = string({session.channels.data_revision})';
run.channel_labels = string({session.channels.original_label})';
run.analysis_time_range = [double(data.time(1)), double(data.time(end))];
run.config = cfg; run.config_id = configId; run.software_version = "SceneRay-LFP v" + string(cfg.version);
run.created_at = string(datestr(now, 31));
run.module_status = struct('artifact', "pending", 'psd', "pending", ...
    'specparam', "pending", 'band_power', "pending");
run.requested_modules = requestedModules;
run.status = "running"; run.warnings = strings(0, 1);
end

function [artifactResult, cleanData] = run_artifact(data, artifactCfg)
[cleanData, artifactResult] = detectAndHandleArtifacts(data, artifactCfg);
end

function status = summarize_model_status(model)
if isempty(model), status = "ok_no_channels"; return; end
states = string({model.fitStatus});
if all(states == "ok"), status = "ok"; elseif any(states == "ok"), status = "partial"; else, status = "failed"; end
end

function status = stage_status(moduleStatus)
values = string(struct2cell(moduleStatus));
if any(values == "failed"), status = "partial_failure"; elseif all(values == "not_requested" | values == "ok" | values == "ok_no_channels"), status = "ok"; else, status = "partial_failure"; end
end

function counts = peak_counts(model)
if isempty(model), counts = zeros(0,1); return; end
counts = zeros(numel(model),1); for k=1:numel(model), counts(k)=get_field(model(k),'nPeaks',0); end
end

function count = get_band_rows(band)
if isstruct(band) && isfield(band, 'table'), count = height(band.table); else, count = 0; end
end

function run = find_reusable_run(project, session, cfg, requestedModules, force)
run = [];
if force || ~isfield(project, 'analysisRuns') || isempty(project.analysisRuns), return; end
for index = numel(project.analysisRuns):-1:1
    candidate = project.analysisRuns(index);
    if string(candidate.session_id) ~= string(session.session_id)
        continue;
    end
    identity = lfp_result_identity(project, session, candidate, Config=cfg, RequiredModules=requestedModules);
    if identity.isCurrent && string(candidate.status) ~= "failed"
        run = candidate; return;
    end
end
end

function ids = all_session_ids(project)
ids = strings(0,1); for s=1:numel(project.subjects), ids=[ids; string({project.subjects(s).sessions.session_id})']; end %#ok<AGROW>
end

function pair = locate_session(project, sessionId)
pair = [];
for s=1:numel(project.subjects)
    for k=1:numel(project.subjects(s).sessions)
        if string(project.subjects(s).sessions(k).session_id) == sessionId, pair=[s k]; return; end
    end
end
end

function summary = empty_summary(ids)
summary = repmat(struct('sessionId', "", 'status', "pending", 'runId', "", 'configId', "", ...
    'errorMessage', "", 'errorIdentifier', "", 'warnings', strings(0,1), 'summary', struct()), numel(ids), 1);
for k=1:numel(ids), summary(k).sessionId=ids(k); end
end

function value = get_field(s, name, fallback)
if isfield(s, name) && ~isempty(s.(name)), value=s.(name); else, value=fallback; end
end

function value = get_field_local(s, name, fallback)
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), value=s.(name); else, value=fallback; end
end

function delete_if_present(filename)
if isfile(filename), delete(filename); end
end

function data = standardize_analysis_data(data)
if ~isfield(data, 'time') || numel(data.time) ~= size(data.signal,1)
    data.time = (0:size(data.signal,1)-1)' / double(data.fs);
end
if ~isfield(data, 'channelLabels') || numel(data.channelLabels) ~= size(data.signal,2)
    data.channelLabels = "channel_" + string((1:size(data.signal,2))');
end
if ~isfield(data, 'units') || isempty(data.units), data.units = "unknown"; end
if ~isfield(data, 'metadata') || ~isstruct(data.metadata), data.metadata = struct(); end
if ~isfield(data, 'processingHistory') || isempty(data.processingHistory)
    data.processingHistory = struct('operation', "import", 'parameters', struct(), 'notes', "Project session analysis input.");
end
end

function tf = should_analyze_channels(session)
% Independent caches are required once multiple imports are attached to one
% Session. A single synchronized legacy Session keeps the original matrix
% pipeline and result format for backward compatibility.
tf = numel(session.data_refs) > 1;
if ~tf && ~isempty(session.channels) && isfield(session.channels, 'enabled')
    tf = any(~logical([session.channels.enabled]));
end
end

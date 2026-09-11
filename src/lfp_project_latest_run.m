function [run, results, isCurrent] = lfp_project_latest_run(project, sessionId, options)
%LFP_PROJECT_LATEST_RUN Load the newest available result for one Session.

arguments
    project (1,1) struct
    sessionId (1,1) string
    options.Config (1,1) struct = struct()
end
run = []; results = struct(); isCurrent = false;
if ~isfield(project, 'analysisRuns') || isempty(project.analysisRuns), return; end
targetConfig = project.defaultConfig;
if ~isempty(fieldnames(options.Config)), targetConfig = options.Config; end
targetId = lfp_config_fingerprint(targetConfig);
for index = numel(project.analysisRuns):-1:1
    candidate = project.analysisRuns(index);
    if string(candidate.session_id) ~= sessionId, continue; end
    resultPath = fullfile(string(project.rootPath), string(candidate.result_ref));
    if ~isfile(resultPath), continue; end
    [run, results] = lfp_load_analysis_run(project, string(candidate.run_id));
    isCurrent = string(candidate.config_id) == targetId && ~startsWith(string(candidate.status), "stale");
    return;
end
end

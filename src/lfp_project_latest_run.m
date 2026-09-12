function [run, results, isCurrent] = lfp_project_latest_run(project, sessionId, options)
%LFP_PROJECT_LATEST_RUN Load the newest available result for one Session.

arguments
    project (1,1) struct
    sessionId (1,1) string
    options.Config (1,1) struct = struct()
    options.RequiredModules (1,1) struct = struct()
end
run = []; results = struct(); isCurrent = false;
if ~isfield(project, 'analysisRuns') || isempty(project.analysisRuns), return; end
targetConfig = project.defaultConfig;
if ~isempty(fieldnames(options.Config)), targetConfig = options.Config; end
if any(struct2array(options.RequiredModules))
    targetId = lfp_analysis_config_fingerprint(targetConfig, options.RequiredModules);
else
    targetId = lfp_config_fingerprint(targetConfig);
end
[session,~] = lfp_project_find_session(project, sessionId);
if isempty(session), return; end
for index = numel(project.analysisRuns):-1:1
    candidate = project.analysisRuns(index);
    if string(candidate.session_id) ~= sessionId, continue; end
    resultPath = fullfile(string(project.rootPath), string(candidate.result_ref));
    if ~isfile(resultPath), continue; end
    [run, results] = lfp_load_analysis_run(project, string(candidate.run_id));
    identity = lfp_result_identity(project, session, run, Config=targetConfig, RequiredModules=options.RequiredModules);
    if any(struct2array(options.RequiredModules))
        isCurrent = identity.isCurrent;
    else
        isCurrent = identity.isCurrent && string(run.config_id) == targetId;
    end
    return;
end
end

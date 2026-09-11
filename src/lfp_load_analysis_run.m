function [run, results] = lfp_load_analysis_run(project, runId)
%LFP_LOAD_ANALYSIS_RUN Load a saved AnalysisRun and its derived results.

arguments
    project (1,1) struct
    runId (1,1) string
end
index = find(string({project.analysisRuns.run_id}) == runId, 1);
if isempty(index), error('LFP:AnalysisRunNotFound', 'Analysis run not found: %s', runId); end
run = project.analysisRuns(index);
path = fullfile(string(project.rootPath), string(run.result_ref));
if ~isfile(path), error('LFP:AnalysisResultMissing', 'Analysis result file is missing: %s', path); end
loaded = load(path, 'payload');
if ~isfield(loaded, 'payload'), error('LFP:InvalidAnalysisResult', 'Result payload is missing.'); end
results = loaded.payload;
end

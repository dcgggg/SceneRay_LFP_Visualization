function batch = lfp_run_batch(task)
%LFP_RUN_BATCH Run project analysis/comparison from a MATLAB task struct/MAT.
%   TASK contains projectRoot, optional sessionIds, optional analysisConfig,
%   optional comparisonSpec, and optional outputFolder.  GUI is not used.
%   A project lock prevents two batch jobs from writing the same index.

arguments
    task
end
if isstring(task) || ischar(task)
    loaded = load(string(task));
    names = fieldnames(loaded);
    if numel(names) ~= 1 || ~isstruct(loaded.(names{1}))
        error('LFP:InvalidBatchTask', 'Task MAT must contain one task struct.');
    end
    task = loaded.(names{1});
end
if ~isstruct(task) || ~isfield(task, 'projectRoot')
    error('LFP:InvalidBatchTask', 'task.projectRoot is required.');
end
project = lfp_load_project(string(task.projectRoot));
lockFile = fullfile(string(project.rootPath), '.lfp_batch.lock');
if isfile(lockFile), error('LFP:ProjectLocked', 'Project is already being written: %s', lockFile); end
fid = fopen(lockFile, 'w'); if fid < 0, error('LFP:ProjectLocked', 'Cannot create project lock.'); end
cleanup = onCleanup(@() release_lock(lockFile, fid)); %#ok<NASGU>
cfg = get_field(task, 'analysisConfig', project.defaultConfig);
sessionIds = string(get_field(task, 'sessionIds', strings(0,1)));
[project, analysisSummary] = lfp_analyze_project(project, sessionIds, Config=cfg, ...
    Force=logical(get_field(task, 'force', false)), Save=true);
batch = struct('status', "ok", 'analysis', analysisSummary, 'comparison', struct(), ...
    'projectRoot', string(project.rootPath), 'startedAt', string(datestr(now,31)), ...
    'finishedAt', "", 'errorMessage', "");
if isfield(task, 'comparisonSpec') && ~isempty(task.comparisonSpec)
    try
        [project, comparison] = lfp_compare_project(project, task.comparisonSpec, Config=cfg, ComputeMissing=false, Save=true);
        batch.comparison = comparison;
        if comparison.status ~= "ok", batch.status = "incomplete"; end
    catch exception
        batch.status = "partial_failure"; batch.errorMessage = string(exception.message);
    end
end
batch.finishedAt = string(datestr(now,31));
if isfield(task, 'outputFolder') && strlength(string(task.outputFolder)) > 0
    folder = string(task.outputFolder); if ~isfolder(folder), mkdir(folder); end
    batchFile = fullfile(folder, "batch_" + string(datestr(now,'yyyymmdd_HHMMSS')) + ".mat");
    save(batchFile, 'batch', '-v7'); batch.outputFile = batchFile;
end
end

function value = get_field(s, name, fallback)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name)), value=s.(name); else, value=fallback; end
end

function release_lock(lockFile, fid)
if fid > 0, fclose(fid); end
if isfile(lockFile), delete(lockFile); end
end

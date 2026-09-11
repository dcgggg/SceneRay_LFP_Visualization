function tests = test_lfp_project_platform
%TEST_LFP_PROJECT_PLATFORM Project/Subject/Session/Channel platform tests.
tests = functiontests(localfunctions);
end

function testProjectStoresIndependentSessionsAndStableChannelIds(testCase)
ensure_src_on_path(testCase);
root = string(tempname); mkdir(root); testCase.addTeardown(@() cleanup(root));
project = lfp_create_project(root, "Synthetic LFP", Save=true);
[project, ~] = lfp_project_add_subject(project, struct('subject_id', "P01", 'display_name', "Patient 01"));
data1 = fixture_data(8, 10, "session1.csv"); data2 = fixture_data(8, 12, "session2.csv");
[project, session1] = lfp_project_add_session(project, "P01", data1, struct('session_id', "S01", 'visit_label', "Baseline"));
[project, session2] = lfp_project_add_session(project, "P01", data2, struct('session_id', "S02", 'visit_label', "Day07"));
verifyEqual(testCase, numel(project.subjects(1).sessions), 2);
verifyEqual(testCase, string(session1.channels(1).original_label), "channel01");
verifyEqual(testCase, string(session2.channels(2).original_label), "channel12");
verifyTrue(testCase, isfile(fullfile(root, "data", "S01.mat")));
verifyTrue(testCase, isfile(fullfile(root, "data", "S02.mat")));
loaded = lfp_load_project(root);
[loadedData, loadedSession] = lfp_project_get_session_data(loaded, "S01");
verifyEqual(testCase, loadedData.signal, data1.signal);
verifyEqual(testCase, string(loadedSession.visit_label), "Baseline");
[project, mergedSession] = lfp_project_add_session_segment(project, "S01", fixture_segment(8, 15, "segment.csv"), struct('segment_id', "segment_2"));
verifyEqual(testCase, size(mergedSession.channels, 2), 3);
[mergedData, ~] = lfp_project_get_session_data(project, "S01");
verifySize(testCase, mergedData.signal, [8000 3]);
verifyError(testCase, @()lfp_project_add_session_segment(project, "S01", fixture_segment(7, 16, "bad.csv")), 'LFP:SessionSegmentMismatch');
end

function testAnalysisCreatesRunsAndSecondCallReuses(testCase)
ensure_src_on_path(testCase);
root = string(tempname); mkdir(root); testCase.addTeardown(@() cleanup(root));
project = lfp_create_project(root, "Synthetic LFP");
[project, ~] = lfp_project_add_subject(project, struct('subject_id', "P01"));
cfg = lfpDefaultConfig(); cfg.artifact.method = "native"; cfg.artifact.strictMode = false;
cfg.psd.windowLengthSec = 1; cfg.psd.frequencyRange = [1 35]; cfg.fooof.frequencyRange = [1 35];
project.defaultConfig = cfg; lfp_save_project(project);
[project, ~] = lfp_project_add_session(project, "P01", fixture_data(8, 10, "a.csv"), struct('session_id', "S01", 'visit_label', "Baseline"));
[project, ~] = lfp_project_add_session(project, "P01", fixture_data(8, 12, "b.csv"), struct('session_id', "S02", 'visit_label', "Day07"));
[project, first] = lfp_analyze_project(project, ["S01" "S02"], Config=cfg);
verifyEqual(testCase, numel(project.analysisRuns), 2);
verifyTrue(testCase, all(ismember(string({first.status}), ["ok" "partial_failure"])));
ids = string({project.analysisRuns.run_id});
[project, second] = lfp_analyze_project(project, ["S01" "S02"], Config=cfg);
verifyEqual(testCase, numel(project.analysisRuns), 2);
verifyEqual(testCase, string({second.status}), ["reused" "reused"]);
verifyEqual(testCase, string({second.runId}), ids);
end

function testComparisonUsesVisitAndLongTable(testCase)
ensure_src_on_path(testCase);
root = string(tempname); mkdir(root); testCase.addTeardown(@() cleanup(root));
project = lfp_create_project(root, "Synthetic LFP");
[project, ~] = lfp_project_add_subject(project, struct('subject_id', "P01"));
[project, ~] = lfp_project_add_subject(project, struct('subject_id', "P02"));
cfg = lfpDefaultConfig(); cfg.artifact.method = "native"; cfg.artifact.strictMode = false;
cfg.psd.windowLengthSec = 1; cfg.psd.frequencyRange = [1 35]; cfg.fooof.frequencyRange = [1 35];
project.defaultConfig = cfg;
[project, ~] = lfp_project_add_session(project, "P01", fixture_data(8, 10, "p01.csv"), struct('session_id', "P01_B", 'visit_label', "Baseline"));
[project, ~] = lfp_project_add_session(project, "P02", fixture_data(8, 10, "p02.csv"), struct('session_id', "P02_B", 'visit_label', "Baseline"));
[project, ~] = lfp_analyze_project(project, ["P01_B" "P02_B"], Config=cfg);
spec = struct('type', "between_subjects", 'session_ids', ["P01_B" "P02_B"], ...
    'bands', "alpha", 'metric', "totalPower");
[project, comparison] = lfp_compare_project(project, spec, Config=cfg);
verifyEqual(testCase, string(comparison.status), "ok");
verifyEqual(testCase, height(comparison.result_table), 4);
verifyEqual(testCase, unique(string(comparison.result_table.visit_label)), "Baseline");
verifyTrue(testCase, isfile(fullfile(root, "comparisons", comparison.comparison_id + ".mat")));
handles = plotProjectComparison(comparison, Visible="off", Band="alpha", Metric="totalPower");
testCase.addTeardown(@() close_if_valid(handles.figure));
verifyTrue(testCase, isgraphics(handles.axes));
end

function data = fixture_data(seconds, frequency, fileName)
fs = 1000; time = (0:(seconds*fs-1))' / fs;
data = struct('signal', [sin(2*pi*frequency*time), cos(2*pi*(frequency+2)*time)], ...
    'fs', fs, 'time', time, 'channelLabels', ["channel01" "channel12"], 'units', "uV", ...
    'metadata', struct('sourceFileName', fileName, 'sourceFilePath', fileName), ...
    'processingHistory', struct('operation', "import", 'parameters', struct(), 'notes', "fixture"));
end

function data = fixture_segment(seconds, frequency, fileName)
data = fixture_data(seconds, frequency, fileName);
data.signal = data.signal(:,1); data.channelLabels = "channel23"; data.channelNames = data.channelLabels;
end

function cleanup(root)
if isfolder(root), rmdir(root, 's'); end
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(projectRoot, 'src'));
testCase.addTeardown(@() rmpath(fullfile(projectRoot, 'src')));
end

function close_if_valid(handle)
if ~isempty(handle) && isgraphics(handle), close(handle); end
end

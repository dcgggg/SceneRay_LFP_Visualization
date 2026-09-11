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
exportFolder = fullfile(root, "comparison_export"); files = lfp_export_comparison(comparison, exportFolder);
verifyTrue(testCase, isfile(files.csv)); verifyTrue(testCase, isfile(files.mat));
end

function testConfiguredCsvBridgeAndBatchEntryPoint(testCase)
ensure_src_on_path(testCase);
root = string(tempname); mkdir(root); testCase.addTeardown(@() cleanup(root));
project = lfp_create_project(root, "CSV project");
[project, ~] = lfp_project_add_subject(project, struct('subject_id', "P01"));
csvFile = fullfile(root, "input.csv"); t=(0:999)'/1000; writetable(table(t, sin(2*pi*10*t), 'VariableNames', {'time','channel01'}), csvFile);
settings = struct('HeaderRow', 1, 'DataStartRow', 2, 'TimeColumn', 1, 'SignalColumns', 2, ...
    'SamplingRateHz', 1000, 'TimeUnit', "s", 'UseSceneRay', false);
[project, session, importInfo] = lfp_project_add_csv_session(project, "P01", csvFile, ...
    struct('session_id', "S01", 'visit_label', "Baseline"), ImportMode="configured", ImportSettings=settings);
verifyEqual(testCase, string(importInfo.format), "configured"); verifyEqual(testCase, session.channels(1).original_label, "channel01");
task = struct('projectRoot', root, 'sessionIds', "S01", 'outputFolder', fullfile(root, "batch"));
batch = lfp_run_batch(task);
verifyTrue(testCase, any(string({batch.analysis.status}) == "ok" | string({batch.analysis.status}) == "partial_failure"));
verifyTrue(testCase, isfield(batch, 'outputFile') && isfile(batch.outputFile));
end

function testMetadataFirstSessionAndNonDestructiveRemoval(testCase)
ensure_src_on_path(testCase);
root = string(tempname); mkdir(root); testCase.addTeardown(@() cleanup(root));
project = lfp_create_project(root, "Metadata workflow", Description="GUI managed project");
[project, ~] = lfp_project_add_subject(project, struct('subject_id', "P01"));
[project, emptySession] = lfp_project_add_empty_session(project, "P01", ...
    struct('session_id', "P01_D07", 'visit_label', "Day07"));
verifyEqual(testCase, string(emptySession.status), "no_data");
[project, session] = lfp_project_attach_data(project, "P01_D07", fixture_data(4, 12, "day07.csv"));
verifyEqual(testCase, string(session.status), "imported");
rows = struct2table(session.channels);
rows.display_label(1) = "Left STN 0-1"; rows.region(1) = "STN";
[project, channels] = lfp_project_update_channels(project, "P01_D07", rows, Save=false);
verifyEqual(testCase, string(channels(1).display_label), "Left STN 0-1");
dataPath = fullfile(root, project.subjects(1).sessions(1).data_refs(1).relative_path);
[project, impact] = lfp_project_remove_session(project, "P01_D07", Save=false);
verifyEmpty(testCase, project.subjects(1).sessions);
verifyTrue(testCase, isfile(dataPath));
verifyEqual(testCase, impact.sessionId, "P01_D07");
end

function testComparisonChannelMappingFiltersRows(testCase)
ensure_src_on_path(testCase);
root = string(tempname); mkdir(root); testCase.addTeardown(@() cleanup(root));
project = lfp_create_project(root, "Mapping project");
[project, ~] = lfp_project_add_subject(project, struct('subject_id', "P01"));
cfg = lfpDefaultConfig(); cfg.artifact.strictMode = false; cfg.psd.windowLengthSec = 1;
project.defaultConfig = cfg;
[project, ~] = lfp_project_add_session(project, "P01", fixture_data(8, 10, "a.csv"), struct('session_id', "S01"));
[project, ~] = lfp_analyze_project(project, "S01", Config=cfg);
session = project.subjects(1).sessions(1);
mapping = struct('session_id', "S01", 'channel_id', string(session.channels(1).channel_id), ...
    'channel_label', "", 'target_label', "Comparable STN");
spec = struct('type', "custom", 'session_ids', "S01", 'bands', "alpha", ...
    'metric', "totalPower", 'channel_mapping', mapping);
[project, comparison] = lfp_compare_project(project, spec, Config=cfg);
verifyEqual(testCase, height(comparison.result_table), 1);
verifyEqual(testCase, string(comparison.result_table.channel_label), "Comparable STN");
end

function testGroupedPsdAndBandComparisonsUseSubjectWeighting(testCase)
ensure_src_on_path(testCase);
root = string(tempname); mkdir(root); testCase.addTeardown(@() cleanup(root));
project = lfp_create_project(root, "Grouped project");
[project, ~] = lfp_project_add_subject(project, struct('subject_id', "P01", 'group', "Control"));
[project, ~] = lfp_project_add_subject(project, struct('subject_id', "P02", 'group', "Treatment"));
cfg = lfpDefaultConfig(); cfg.artifact.strictMode = false; cfg.psd.windowLengthSec = 1; cfg.psd.frequencyRange = [1 35]; project.defaultConfig = cfg;
[project, s1] = lfp_project_add_session(project, "P01", fixture_data(4, 10, "p01.csv"), struct('session_id', "P01_B", 'visit_label', "Baseline"));
[project, s2] = lfp_project_add_session(project, "P02", fixture_data(4, 12, "p02.csv"), struct('session_id', "P02_B", 'visit_label', "Baseline"));
[project, ~] = lfp_analyze_project(project, [s1.session_id s2.session_id], Config=cfg);
mapping(1) = struct('session_id', s1.session_id, 'channel_id', s1.channels(1).channel_id, 'channel_label', "", 'target_label', "STN", 'group_label', "Control");
mapping(2) = struct('session_id', s2.session_id, 'channel_id', s2.channels(1).channel_id, 'channel_label', "", 'target_label', "STN", 'group_label', "Treatment");
spec = struct('type', "between_subjects", 'session_ids', [s1.session_id s2.session_id], 'bands', "alpha", ...
    'metric', "totalPower", 'channel_mapping', mapping, 'grouping_basis', "custom");
[~, comparison] = lfp_compare_project(project, spec, Config=cfg);
verifyEqual(testCase, string(comparison.psd_summary.status), "ok");
verifyEqual(testCase, numel(comparison.psd_summary.group_labels_unique), 2);
verifyEqual(testCase, string(comparison.result_table.group_label), ["Control"; "Treatment"]);
h1 = plotGroupedPsdComparison(comparison.psd_summary, Visible="off"); testCase.addTeardown(@() close_if_valid(h1.figure));
h2 = plotGroupedBandPower(comparison, Visible="off"); testCase.addTeardown(@() close_if_valid(h2.figure));
verifyTrue(testCase, isgraphics(h1.axes)); verifyTrue(testCase, isgraphics(h2.axes));
end

function testSpecparamFailureDoesNotBlockOrdinaryBandPower(testCase)
ensure_src_on_path(testCase);
root = string(tempname); mkdir(root); testCase.addTeardown(@() cleanup(root));
project = lfp_create_project(root, "failure isolation"); [project,~] = lfp_project_add_subject(project, struct('subject_id', "P01"));
cfg = lfpDefaultConfig(); cfg.artifact.method="native"; cfg.artifact.strictMode=false; cfg.psd.windowLengthSec=1; cfg.psd.frequencyRange=[1 35]; cfg.fooof.frequencyRange=[1 35]; cfg.fooof.peakWidthLimits=[0 0];
project.defaultConfig=cfg; [project,~]=lfp_project_add_session(project,"P01",fixture_data(8,10,"badmodel.csv"),struct('session_id',"S01"));
[project,summary]=lfp_analyze_project(project,"S01",Config=cfg); %#ok<ASGLU>
run=project.analysisRuns(1); verifyEqual(testCase,string(run.module_status.specparam),"failed"); verifyEqual(testCase,string(run.module_status.band_power),"ok");
[~,results]=lfp_load_analysis_run(project,run.run_id); verifyTrue(testCase,isfield(results.bandResult,'table')); verifyTrue(testCase,any(results.bandResult.table.computable));
end

function testConfigFingerprintChangesWithAnalysisParameters(testCase)
ensure_src_on_path(testCase);
first = lfpDefaultConfig();
second = first; second.psd.frequencyRange = [1 30];
third = first; third.plot.frequencyRange = [1 20];
verifyNotEqual(testCase, lfp_config_fingerprint(first), lfp_config_fingerprint(second));
verifyEqual(testCase, lfp_config_fingerprint(first), lfp_config_fingerprint(third));
end

function testProjectParentCreatesNestedStorageAndRelocates(testCase)
ensure_src_on_path(testCase);
parent = string(tempname); mkdir(parent); testCase.addTeardown(@() cleanup(parent));
[project, projectRoot] = lfp_create_project_in_parent(parent, "DBS Study");
verifyEqual(testCase, string(project.storage_mode), "subject_session");
verifyTrue(testCase, isfile(fullfile(projectRoot, "project.mat")));
verifyTrue(testCase, isfolder(fullfile(projectRoot, "subjects")));
verifyError(testCase, @()lfp_create_project_in_parent(parent, "DBS/Study"), 'LFP:InvalidFolderName');
mkdir(fullfile(parent, "Existing"));
verifyError(testCase, @()lfp_create_project_in_parent(parent, "Existing"), 'LFP:ProjectFolderExists');
[project, subject] = lfp_project_add_subject(project, struct('subject_id', "P01", 'display_name', "Patient 01"));
subjectFolder = fullfile(projectRoot, subject.folder_relative_path);
verifyTrue(testCase, isfolder(subjectFolder)); verifyTrue(testCase, isfile(fullfile(subjectFolder, "subject.mat")));
[project, session] = lfp_project_add_empty_session(project, "P01", struct('session_id', "S01", 'visit_label', "Baseline"));
sessionFolder = fullfile(projectRoot, session.folder_relative_path);
verifyTrue(testCase, isfolder(fullfile(sessionFolder, "data")));
source = fullfile(parent, "source.csv"); t=(0:99)'/100; writetable(table(t,sin(2*pi*10*t),'VariableNames',{'time','channel01'}),source);
data = struct('signal', sin(2*pi*10*t), 'time', t, 'fs', 100, 'channelLabels', "channel01", 'units', "uV", ...
    'metadata', struct('sourceFilePath', source, 'sourceFileName', "source.csv"));
[project, session] = lfp_project_attach_data(project, "S01", data, Save=false);
stored = fullfile(projectRoot, session.data_refs(1).relative_path);
copied = fullfile(projectRoot, session.data_refs(1).project_copy_relative_path);
verifyTrue(testCase, isfile(stored)); verifyTrue(testCase, isfile(copied)); verifyTrue(testCase, isfile(source));
[project, ~] = lfp_project_update_subject(project, "P01", struct('display_name', "Patient Renamed"), Save=false);
newSubjectFolder = fullfile(projectRoot, project.subjects(1).folder_relative_path);
verifyTrue(testCase, isfolder(newSubjectFolder)); verifyFalse(testCase, isfolder(subjectFolder));
[project, session] = lfp_project_update_session(project, "S01", struct('visit_label', "Post"), Save=false);
newSessionFolder = fullfile(projectRoot, session.folder_relative_path);
verifyTrue(testCase, isfolder(newSessionFolder)); verifyFalse(testCase, isfolder(sessionFolder));
verifyTrue(testCase, isfile(fullfile(projectRoot, session.data_refs(1).relative_path)));
lfp_save_project(project);
movedRoot = fullfile(parent, "MovedStudy"); movefile(projectRoot, movedRoot);
reopened = lfp_load_project(movedRoot); [reopenedData, ~] = lfp_project_get_session_data(reopened, "S01");
verifyEqual(testCase, reopenedData.signal, data.signal); verifyEqual(testCase, string(reopened.rootPath), movedRoot);
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

function tests = test_lfp_gui_dataset_manager
%TEST_LFP_GUI_DATASET_MANAGER Verify independent multi-CSV session handling.
tests = functiontests(localfunctions);
end

function testMultipleDatasetsRemainIndependent(testCase)
ensure_src_on_path(testCase);
fs = 1000; t = (0:3999)'/fs; labels = string({'1-2','5-6'});
dataA = fixture_data(t, labels, 10, 'PD01.csv');
dataB = fixture_data(t, labels, 20, 'PD02.csv');
app = launchLfpApp(Visible="off");
testCase.addTeardown(@() delete(app));
app.setData(dataA);
app.setData(dataB);
verifyEqual(testCase, numel(app.Datasets), 2);
verifyEqual(testCase, string(app.Datasets(1).fileName), "PD01.csv");
verifyEqual(testCase, string(app.Datasets(2).fileName), "PD02.csv");
verifySize(testCase, app.Datasets(1).signal, [4000 2]);
verifySize(testCase, app.Datasets(2).signal, [4000 2]);
verifyNotEqual(testCase, app.Datasets(1).signal(:,1), app.Datasets(2).signal(:,1));
app.selectAllDatasets([], []);
verifyEqual(testCase, app.AppState.selectedDatasets, [1 2]);
app.Controls.ArtifactCheck.Value = false;
app.Controls.FooofCheck.Value = false;
app.Controls.BandCheck.Value = false;
app.onRun([], []);
verifyTrue(testCase, app.Cache.psdValid);
verifyEqual(testCase, string(app.Datasets(1).status), "已完成");
verifyEqual(testCase, string(app.Datasets(2).status), "已完成");
verifySize(testCase, app.Datasets(1).analysisResults.psdResult.psd, ...
    [numel(app.Datasets(1).analysisResults.psdResult.frequencyHz) 2]);
verifySize(testCase, app.Datasets(2).analysisResults.psdResult.psd, ...
    [numel(app.Datasets(2).analysisResults.psdResult.frequencyHz) 2]);
end

function data = fixture_data(t, labels, frequency, fileName)
signal = [sin(2*pi*frequency*t), cos(2*pi*(frequency+3)*t)];
data = struct('signal', signal, 'fs', 1000, 'time', t, ...
    'channelLabels', labels, 'channelNames', labels, 'channelCount', 2, ...
    'units', "uV", 'metadata', struct('sourceFileName', fileName, ...
    'sourceFilePath', fileName, 'displayName', fileName, ...
    'timeValidation', struct('valid', true, 'isIrregular', false)), ...
    'processingHistory', struct('operation', "import", ...
    'parameters', struct(), 'notes', "fixture"));
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

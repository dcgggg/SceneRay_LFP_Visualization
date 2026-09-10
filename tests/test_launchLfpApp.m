function tests = test_launchLfpApp
%TEST_LAUNCHLFPAPP Smoke test for the MATLAB-native GUI.
tests = functiontests(localfunctions);
end

function testGuiBuildsWithoutVisibleWindow(testCase)
ensure_src_on_path(testCase);
app = launchLfpApp(Visible="off");
testCase.addTeardown(@() delete(app));
verifyClass(testCase, app, 'LfpApp');
verifyTrue(testCase, isgraphics(app.Figure));
verifyTrue(testCase, isgraphics(app.Controls.RawAxes));
verifyTrue(testCase, isgraphics(app.Controls.PsdAxes));
verifyEqual(testCase, string(app.Controls.ArtifactMethod.Value), "native");
verifyFalse(testCase, isfield(app.Controls, 'SummaryPsdAxes'));
verifyEqual(testCase, string(app.Controls.FooofMode.Value), "fixed");
verifyEqual(testCase, string(app.Controls.PsdMethod.Value), "welch");
verifyTrue(testCase, isgraphics(app.Controls.PsdTimeFrequencyAxes));
end

function testGuiRunsSyntheticPipeline(testCase)
ensure_src_on_path(testCase);
fs = 1000; t = (0:3999)' / fs;
signal = [sin(2*pi*10*t), sin(2*pi*20*t)];
data = struct('signal', signal, 'fs', fs, 'time', t, ...
    'channelLabels', ["1-2" "5-6"], 'channelNames', ["1-2" "5-6"], ...
    'channelCount', 2, 'units', "uV", ...
    'metadata', struct('sourceFileName', "synthetic.csv", ...
        'displayName', "synthetic.csv | IPG SN TEST", 'ipgSN', "TEST", ...
        'timeValidation', struct('valid', true, 'isIrregular', false)), ...
    'processingHistory', struct('operation', "import", ...
        'parameters', struct(), 'notes', "test fixture"));
app = launchLfpApp(Visible="off");
testCase.addTeardown(@() delete(app));
app.Data = data;
app.Controls.ChannelList.Items = cellstr(data.channelLabels);
app.Controls.ChannelList.Value = cellstr(data.channelLabels);
app.Controls.AnalysisEnd.Value = (size(signal, 1) - 1) / fs;
app.Controls.DisplayEnd.Value = (size(signal, 1) - 1) / fs;
app.onRun([], []);
verifySize(testCase, app.PsdResult.psd, [159 2]);
verifyNumElements(testCase, app.ModelResult, 2);
verifyEqual(testCase, height(app.BandResult.table), 12);
verifyTrue(testCase, app.Cache.psdValid);
verifyTrue(testCase, app.Cache.modelValid);
verifyTrue(testCase, app.Cache.bandValid);
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

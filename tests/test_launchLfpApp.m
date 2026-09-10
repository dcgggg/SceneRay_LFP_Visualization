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
verifyEqual(testCase, string(app.Controls.PsdMethod.Value), "multitaper");
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
verifySize(testCase, app.PsdResult.psd, [numel(app.PsdResult.frequencyHz) 2]);
verifyNumElements(testCase, app.ModelResult, 2);
verifyEqual(testCase, height(app.BandResult.table), 12);
verifyTrue(testCase, app.Cache.psdValid);
verifyTrue(testCase, app.Cache.modelValid);
verifyTrue(testCase, app.Cache.bandValid);
% Selecting the specparam tab must render the separated model and peak views
% without re-running analysis or creating placeholder legend entries.
tabs = app.Tabs.Results.Children;
specTab = tabs(contains(string({tabs.Title}), "specparam"));
app.Tabs.Results.SelectedTab = specTab;
drawnow;
verifyTrue(testCase, isgraphics(app.Controls.FooofModelAxes));
verifyTrue(testCase, isgraphics(app.Controls.FooofPeaksAxes));
verifyTrue(testCase, isgraphics(app.Controls.FooofTable));
verifyEqual(testCase, string(app.LastPlotError), "");
end

function testGuiTimeFrequencyDisplayAndIdleClose(testCase)
ensure_src_on_path(testCase);
fs = 1000; t = (0:2999)' / fs;
% A burst at a known time/frequency exercises the real stored TF matrix and
% the GUI renderer rather than a placeholder or copied PSD.
burst = double(t >= 1.0 & t < 1.5) .* sin(2*pi*18*t);
data = struct('signal', burst, 'fs', fs, 'time', t, ...
    'channelLabels', "5-6", 'channelNames', "5-6", 'channelCount', 1, 'units', "uV", ...
    'metadata', struct('sourceFileName', "tf_gui.csv", 'displayName', "tf_gui.csv | IPG SN TEST"));
app = launchLfpApp(Visible="off");
testCase.addTeardown(@() delete(app));
app.setData(data);
app.Controls.ArtifactCheck.Value = false;
app.Controls.PsdExclude.Value = false;
app.Controls.AnalysisEnd.Value = t(end);
app.Controls.DisplayEnd.Value = t(end);
app.onRun([], []);
tabs = app.Tabs.Results.Children;
tfTab = tabs(contains(string({tabs.Title}), "时频"));
app.Tabs.Results.SelectedTab = tfTab;
% Hidden uifigure instances may defer SelectionChangedFcn until visible;
% invoke the registered callback explicitly to exercise the same path.
feval(app.Tabs.Results.SelectionChangedFcn, app.Tabs.Results, []);
drawnow;
verifyTrue(testCase, isfield(app.PsdResult, 'timeFrequency'));
verifyTrue(testCase, isgraphics(app.Controls.PsdTimeFrequencyAxes));
verifyTrue(testCase, contains(string(app.Controls.TfInfoResult.Text), "时频结果已计算"));
verifyEqual(testCase, string(app.LastPlotError), "");
app.closeApp([], []);
verifyFalse(testCase, isgraphics(app.Figure));
% Repeated close requests must remain harmless and must not resurrect UI.
app.closeApp([], []);
verifyFalse(testCase, isgraphics(app.Figure));
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

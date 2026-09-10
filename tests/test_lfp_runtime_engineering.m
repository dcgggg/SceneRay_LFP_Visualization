function tests = test_lfp_runtime_engineering
%TEST_LFP_RUNTIME_ENGINEERING Progress, cancellation, caching and display QA.
tests = functiontests(localfunctions);
end

function testDisplayEnvelopePreservesSpikeAndInputs(testCase)
ensure_src_on_path(testCase);
time = (0:99999)' / 1000;
signal = zeros(numel(time), 2);
signal(54321, 1) = 100;
signal(40000:40100, 2) = NaN;
original = signal;
[displayTime, displaySignal, info] = lfp_downsample_envelope(time, signal, 2000);
verifyLessThanOrEqual(testCase, size(displaySignal, 1), 2000);
verifyEqual(testCase, max(displaySignal(:,1), [], 'omitnan'), 100);
verifyTrue(testCase, any(isnan(displaySignal(:,2))));
verifyEqual(testCase, signal, original);
verifyEqual(testCase, numel(displayTime), size(displaySignal,1));
verifyTrue(testCase, info.downsampled);
end

function testTaskManagerCancellationAndRecovery(testCase)
ensure_src_on_path(testCase);
progress = zeros(0,1);
manager = LfpAnalysisTaskManager(@recordProgress, []);
manager.start(2); manager.beginStage("stage one", 1, 2); manager.update(0.5, "half");
manager.finishStage("completed"); manager.beginStage("stage two", 2, 2);
manager.requestCancel();
verifyError(testCase, @()manager.checkCancelled(), 'LFP:UserCancelled');
try
    manager.checkCancelled();
catch exception
    manager.fail(exception);
end
verifyFalse(testCase, manager.IsRunning);
manager.reset(); manager.start(1); manager.beginStage("recovery", 1, 1);
manager.complete();
verifyFalse(testCase, manager.IsRunning);
verifyGreaterThanOrEqual(testCase, manager.TotalSeconds, 0);
verifyGreaterThanOrEqual(testCase, numel(progress), 3);

    function recordProgress(value, ~)
        progress(end+1,1) = value; %#ok<AGROW>
    end
end

function testRuntimeCallbacksAreCooperativeAndNotPersisted(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig();
data = fixture_data(2, 2);
cfg.artifact.progressCallback = @(~,~)[];
cfg.artifact.cancellationCheck = @()[];
[~, artifact] = detectAndHandleArtifacts(data, cfg.artifact);
verifyFalse(testCase, isfield(artifact.parameters, 'progressCallback'));
verifyFalse(testCase, isfield(artifact.parameters, 'cancellationCheck'));

cancelCfg = cfg.artifact;
cancelCfg.cancellationCheck = @raise_cancel;
verifyError(testCase, @()detectAndHandleArtifacts(data, cancelCfg), 'LFP:UserCancelled');

    function raise_cancel()
        error('LFP:UserCancelled', 'cancelled by test');
    end
end

function testGuiReusesPsdCacheAndRecordsTiming(testCase)
ensure_src_on_path(testCase);
app = launchLfpApp(Visible="off");
testCase.addTeardown(@()delete(app));
app.setData(fixture_data(4, 2));
app.Controls.ArtifactCheck.Value = false;
app.Controls.FooofCheck.Value = false;
app.Controls.BandCheck.Value = false;
app.Controls.TfEnable.Value = false;
app.onRun([], []);
verifyTrue(testCase, app.Cache.psdValid);
verifyTrue(testCase, isfield(app.AnalysisData.metadata, 'performance'));
app.onRun([], []);
messages = string(app.Controls.LogArea.Value);
verifyTrue(testCase, any(contains(messages, "PSD：使用有效缓存")));
verifyTrue(testCase, isfield(app.Performance, 'lastAnalysis'));
end

function data = fixture_data(seconds, channels)
fs = 1000; time = (0:(seconds*fs-1))' / fs;
signal = zeros(numel(time), channels);
for channel = 1:channels
    signal(:,channel) = sin(2*pi*(8+channel)*time);
end
labels = "channel_" + string(1:channels);
data = struct('signal', signal, 'fs', fs, 'time', time, ...
    'channelLabels', labels, 'channelNames', labels, 'channelCount', channels, ...
    'units', "uV", 'metadata', struct('sourceFileName', "runtime.csv", ...
    'sourceFilePath', "runtime.csv", 'displayName', "runtime.csv", ...
    'timeValidation', struct('valid', true, 'isIrregular', false)), ...
    'processingHistory', struct('operation', "import", 'parameters', struct(), 'notes', "fixture"));
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@()rmpath(srcRoot));
end

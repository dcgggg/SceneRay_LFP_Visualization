function tests = test_detectAndHandleArtifacts
%TEST_DETECTANDHANDLEARTIFACTS Tests the unified artifact contract.
tests = functiontests(localfunctions);
end

function testNativeDetectsCommonArtifactsAndPreservesRaw(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig();
cfg.artifact.method = "native";
cfg.artifact.paddingSeconds = 0;
cfg.artifact.lineNoiseRatioThreshold = 0.30;
fs = 1000;
t = (0:3999)'/fs;
x = 0.5*sin(2*pi*10*t);
x(500) = 100;
x(1000:1008) = 5000;
x(1800:2200) = 2;
x(3000:3500) = 40*sin(2*pi*40*t(3000:3500));
data = fixture_data(x, fs);
[cleanData, result] = detectAndHandleArtifacts(data, cfg.artifact);
verifyEqual(testCase, cleanData.signal, data.signal);
verifyTrue(testCase, isfield(cleanData, 'cleanedSignal'));
verifyTrue(testCase, any(result.sampleMask));
verifyGreaterThanOrEqual(testCase, height(result.events), 3);
verifyTrue(testCase, any(result.events.artifactType == "high_amplitude"));
verifyTrue(testCase, any(result.events.artifactType == "saturation"));
verifyTrue(testCase, any(result.events.artifactType == "flatline"));
verifyTrue(testCase, isfield(result, 'badChannels'));
verifyEqual(testCase, result.processingHistory(end).operation, "artifact_detection");
end

function testManualIntervalsAndFieldTripFallback(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig();
cfg.artifact.method = "fieldtrip";
cfg.artifact.paddingSeconds = 0;
cfg.artifact.manualIntervalsSamples = [10 20];
cfg.artifact.nativeFallback = true;
data = fixture_data(zeros(100, 2), 1000);
[~, result] = detectAndHandleArtifacts(data, cfg.artifact);
verifyTrue(testCase, all(result.globalMask(10:20)));
verifyTrue(testCase, any(result.events.artifactType == "manual"));
verifyTrue(testCase, any(contains(result.warnings, "FieldTrip")) || result.method == "fieldtrip");
end

function testLineNoiseIsRetainedByDefault(testCase)
ensure_src_on_path(testCase);
fs = 1000;
t = (0:3999)' / fs;
data = fixture_data(sin(2*pi*40*t), fs);
cfg = lfpDefaultConfig();
cfg.artifact.method = "native";
cfg.artifact.paddingSeconds = 0;
[~, result] = detectAndHandleArtifacts(data, cfg.artifact);
verifyFalse(testCase, any(result.events.artifactType == "line_noise"));
verifyLessThan(testCase, nnz(result.channelMask), 0.1*numel(t));
end

function testStrictModeMarksSustainedHighFrequencyBurst(testCase)
ensure_src_on_path(testCase);
fs = 1000;
t = (0:4999)' / fs;
x = 0.5 * sin(2*pi*10*t);
x(1801:2400) = x(1801:2400) + 5*sin(2*pi*250*t(1801:2400));
data = fixture_data(x, fs);
cfg = lfpDefaultConfig();
cfg.artifact.method = "native";
cfg.artifact.paddingSeconds = 0;
[~, result] = detectAndHandleArtifacts(data, cfg.artifact);
strictRows = result.events.artifactType == "strict_burst";
verifyTrue(testCase, any(strictRows));
verifyGreaterThan(testCase, nnz(result.channelMask(1801:2400)), 0.8*600);
end

function data = fixture_data(signal, fs)
data = struct('signal', signal, 'fs', fs, 'time', (0:size(signal,1)-1)'/fs, ...
    'channelLabels', "ch1", 'units', "uV", 'metadata', struct(), ...
    'processingHistory', struct('operation', "import", 'parameters', struct(), 'notes', "fixture"));
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

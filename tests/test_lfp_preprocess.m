function tests = test_lfp_preprocess
%TEST_LFP_PREPROCESS Tests for non-destructive artifact annotation.
tests = functiontests(localfunctions);
end

function testMarksHighAmplitudeStepAndSaturation(testCase)
ensure_src_on_path(testCase);
fs = 1000;
t = (0:1999)' / fs;
x = 20 * sin(2*pi*10*t);
x(500) = 2000;
x(900:905) = 10000;
x(1300:end) = x(1300:end) + 1000;
data = base_data(x, fs);
raw = data.signal;
out = lfp_preprocess(data, AmplitudeZ=6, DerivativeZ=6, ...
    SaturationAbsoluteThresholdUV=5000, SaturationRunLength=5, ...
    IntervalPaddingSeconds=0, ReplaceArtifacts=true);
verifyEqual(testCase, out.signal, raw);
verifyTrue(testCase, out.artifacts.channelMask(500));
verifyTrue(testCase, all(out.artifacts.channelMask(900:905)));
verifyTrue(testCase, any(out.artifacts.reasonMasks.saturation(900:905)));
verifyTrue(testCase, any(isnan(out.preprocessedSignal)));
verifyGreaterThanOrEqual(testCase, numel(out.artifacts.intervals_s), 1);
verifyEqual(testCase, out.processingHistory(end).operation, "artifact_detection");
end

function testMultichannelAndNoArtifactSignal(testCase)
ensure_src_on_path(testCase);
fs = 1000;
t = (0:999)' / fs;
data = base_data([sin(2*pi*8*t), 2*sin(2*pi*12*t)], fs);
out = lfp_preprocess(data, IntervalPaddingSeconds=0, SaturationAbsoluteThresholdUV=5000);
verifyFalse(testCase, any(out.artifacts.channelMask, 'all'));
verifyEqual(testCase, out.preprocessedSignal, data.signal);
verifySize(testCase, out.artifacts.channelMask, [1000 2]);
end

function testInvalidDataFails(testCase)
ensure_src_on_path(testCase);
verifyError(testCase, @() lfp_preprocess(struct('signal', ones(4,1))), 'LFP:InvalidData');
end

function data = base_data(signal, fs)
data = struct('signal', signal, 'fs', fs, 'time', (0:size(signal,1)-1)'/fs, ...
    'channelLabels', "ch1", 'units', "uV", 'metadata', struct(), ...
    'artifacts', struct(), 'processingHistory', struct( ...
    'operation', "import", 'parameters', struct(), 'notes', "fixture"));
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

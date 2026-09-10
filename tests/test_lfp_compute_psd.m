function tests = test_lfp_compute_psd
%TEST_LFP_COMPUTE_PSD Tests for the base-MATLAB PSD implementation.
tests = functiontests(localfunctions);
end

function testIdentifiesSingleFrequency(testCase)
ensure_src_on_path(testCase);
rng(7, 'twister');
fs = 1000;
t = (0:3999)' / fs;
x = 2*sin(2*pi*10*t) + 0.05*randn(size(t));
data = base_data(x, fs);
out = lfp_compute_psd(data, WindowSeconds=2, OverlapFraction=0.5);
[~, peakIndex] = max(out.spectrum.psd);
verifyEqual(testCase, out.spectrum.frequencyHz(peakIndex), 10, 'AbsTol', 0.6);
verifyTrue(testCase, out.spectrum.includesLineNoise);
verifySize(testCase, out.spectrum.windowPsd, [numel(out.spectrum.frequencyHz), 3, 1]);
verifyTrue(testCase, all(out.spectrum.validWindowCountPerFrequency == 3));
verifyEqual(testCase, out.processingHistory(end).operation, "psd");
end

function testExcludesArtifactHeavyWindow(testCase)
ensure_src_on_path(testCase);
fs = 1000;
t = (0:3999)' / fs;
x = sin(2*pi*12*t);
data = base_data(x, fs);
data.artifacts = struct('channelMask', false(size(x)));
data.artifacts.channelMask(1:2000) = true;
out = lfp_compute_psd(data, WindowSeconds=1, OverlapFraction=0, MaxArtifactFraction=0.1);
verifyEqual(testCase, out.spectrum.windowCount, 2);
verifyEqual(testCase, out.spectrum.acceptedWindowStarts{1}, [2001; 3001]);
end

function testAllowsConfiguredSmallArtifactFraction(testCase)
ensure_src_on_path(testCase);
fs = 1000;
t = (0:3999)' / fs;
x = sin(2*pi*12*t);
data = base_data(x, fs);
data.artifacts = struct('channelMask', false(size(x)));
data.artifacts.channelMask(101:110) = true;
out = lfp_compute_psd(data, WindowSeconds=1, OverlapFraction=0, ...
    MaxArtifactFraction=0.05);
verifyEqual(testCase, out.spectrum.windowCount, 4);
verifyEqual(testCase, out.spectrum.filledSampleCount, 10);
end

function testShortSignalAndInvalidData(testCase)
ensure_src_on_path(testCase);
data = base_data(sin((1:100)'), 1000);
out = lfp_compute_psd(data, WindowSeconds=4);
verifyEqual(testCase, out.spectrum.windowCount, 1);
verifyError(testCase, @() lfp_compute_psd(struct('signal', ones(3,1), 'fs', 1000)), 'LFP:InvalidData');
end

function testConfigCompatibilityEntryPoint(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig();
data = base_data(sin(2*pi*10*(0:1999)'/1000), 1000);
artifactResult = struct('channelMask', false(size(data.signal)));
result = computeLfpPsd(data, artifactResult, cfg.psd);
verifyEqual(testCase, result.frequencyHz(1), 1, 'AbsTol', result.frequencyResolutionHz);
verifyLessThanOrEqual(testCase, result.frequencyHz(end), 40);
verifyTrue(testCase, isfield(result, 'windowPsd'));
verifyEqual(testCase, result.channelLabels, "ch1");
end

function testRejectsFrequencyAboveNyquist(testCase)
ensure_src_on_path(testCase);
data = base_data(sin(2*pi*10*(0:999)'/100), 100);
verifyError(testCase, @() lfp_compute_psd(data, FrequencyRangeHz=[1 60]), ...
    'LFP:FrequencyAboveNyquist');
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

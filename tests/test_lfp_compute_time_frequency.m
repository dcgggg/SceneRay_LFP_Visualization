function tests = test_lfp_compute_time_frequency
%TEST_LFP_COMPUTE_TIME_FREQUENCY Tests for base-MATLAB STFT output.
tests = functiontests(localfunctions);
end

function testTracksFrequencyAcrossTime(testCase)
ensure_src_on_path(testCase);
fs = 1000;
t = (0:3999)' / fs;
x = sin(2*pi*10*t);
x(2501:end) = sin(2*pi*20*t(2501:end));
data = base_data(x, fs);
out = lfp_compute_time_frequency(data, WindowSeconds=1, StepSeconds=0.5, FrequencyRangeHz=[1 40]);
[~, firstTime] = min(abs(out.timeFrequency.timeSeconds - 1));
[~, lastTime] = min(abs(out.timeFrequency.timeSeconds - 3));
[~, firstPeak] = max(out.timeFrequency.power(:, firstTime, 1));
[~, lastPeak] = max(out.timeFrequency.power(:, lastTime, 1));
verifyEqual(testCase, out.timeFrequency.frequencyHz(firstPeak), 10, 'AbsTol', 1);
verifyEqual(testCase, out.timeFrequency.frequencyHz(lastPeak), 20, 'AbsTol', 1);
verifyEqual(testCase, size(out.timeFrequency.power, 3), 1);
verifyEqual(testCase, out.processingHistory(end).operation, "time_frequency");
end

function data = base_data(signal, fs)
data = struct('signal', signal, 'fs', fs, 'units', "uV", ...
    'artifacts', struct('channelMask', false(size(signal))), ...
    'processingHistory', struct('operation', "import", 'parameters', struct(), 'notes', "fixture"));
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

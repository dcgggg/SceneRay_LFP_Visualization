function tests = test_lfp_multitaper_and_specparam
%TEST_LFP_MULTITAPER_AND_SPECPARAM Regression tests for new analysis paths.
tests = functiontests(localfunctions);
end

function testMultitaperPeakAndParameters(testCase)
ensure_src_on_path(testCase);
rng(41, 'twister'); fs = 1000; t = (0:3999)' / fs;
data = base_data(sin(2*pi*12*t) + 0.02*randn(size(t)), fs);
out = lfp_compute_psd(data, Method="multitaper", WindowSeconds=2, ...
    TimeBandwidthProduct=3.5, FrequencyRangeHz=[1 40]);
[~, index] = max(out.spectrum.psd);
verifyEqual(testCase, out.spectrum.frequencyHz(index), 12, 'AbsTol', 1);
verifyEqual(testCase, out.spectrum.taperCount, 6);
verifyEqual(testCase, out.spectrum.halfBandwidthHz, 1.75, 'AbsTol', 1e-12);
verifyEqual(testCase, out.spectrum.parameters.taperWeighting, "equal");
end

function testKneeModelHasDistinctField(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig(); cfg.fooof.aperiodicMode = "knee";
freq = (1:0.25:35)'; offset = 1.3; exponent = 1.1; knee = 4;
power = 10 .^ (offset - log10(knee + freq .^ exponent));
result = parameterizePowerSpectrum(freq, power, cfg.fooof);
verifyEqual(testCase, result.aperiodicParams.mode, "knee");
verifyTrue(testCase, isfinite(result.aperiodicParams.knee));
verifyEqual(testCase, result.fittingPower, result.inputPower);
verifyFalse(testCase, result.interpolationApplied);
end

function testBandPowerRunsWithoutSpecparam(testCase)
ensure_src_on_path(testCase);
freq = (1:10)';
psd = ones(numel(freq), 1);
psdResult = struct('frequencyHz', freq, 'psd', psd, 'channelLabels', "ch1", ...
    'fs', 1000, 'units', "uV");
result = computeBandPower(psdResult, [], struct('delta', [1 4], 'highGamma', [65 100]));
verifyTrue(testCase, result.hasParameterization == false);
verifyTrue(testCase, result.table.computable(1));
verifyEqual(testCase, result.table.status(1), "ok");
verifyFalse(testCase, result.table.computable(2));
verifyEqual(testCase, result.table.status(2), "outside_psd_range");
end

function data = base_data(signal, fs)
data = struct('signal', signal, 'fs', fs, 'time', (0:size(signal,1)-1)'/fs, ...
    'channelLabels', "ch1", 'units', "uV", 'artifacts', struct('channelMask', false(size(signal))), ...
    'processingHistory', struct('operation', "import", 'parameters', struct(), 'notes', "fixture"));
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src'); addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

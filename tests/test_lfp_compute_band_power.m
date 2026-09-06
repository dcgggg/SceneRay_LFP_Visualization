function tests = test_lfp_compute_band_power
%TEST_LFP_COMPUTE_BAND_POWER Tests for configurable band integration.
tests = functiontests(localfunctions);
end

function testComputesAllPowerTypes(testCase)
ensure_src_on_path(testCase);
frequencyHz = (1:100)';
total = ones(100, 2);
aperiodic = 0.25 * ones(100, 2);
periodic = 0.75 * ones(100, 2);
data = base_data(frequencyHz, total);
data.spectralParameters = struct('aperiodicPsd', aperiodic, ...
    'periodicPowerAboveAperiodic', periodic);
out = lfp_compute_band_power(data, ReferenceRangeHz=[1 100]);
rows = out.bandPower.table;
deltaChannel1 = rows(rows.band == "delta" & rows.channelIndex == 1, :);
verifyEqual(testCase, deltaChannel1.totalPower, 3, 'AbsTol', 1e-12);
verifyEqual(testCase, deltaChannel1.logTotalPower, log10(3), 'AbsTol', 1e-12);
verifyEqual(testCase, deltaChannel1.relativePower, 3/99, 'AbsTol', 1e-12);
verifyEqual(testCase, deltaChannel1.aperiodicPower, 0.75, 'AbsTol', 1e-12);
verifyEqual(testCase, deltaChannel1.periodicPower, 2.25, 'AbsTol', 1e-12);
verifyEqual(testCase, height(rows), 12);
verifyEqual(testCase, out.processingHistory(end).operation, "band_power");
end

function testCustomBandsAndMissingParameterization(testCase)
ensure_src_on_path(testCase);
frequencyHz = (1:100)';
data = base_data(frequencyHz, ones(100, 1));
custom = struct('name', {"custom"}, 'rangeHz', {[10 20]});
out = lfp_compute_band_power(data, Bands=custom);
verifyEqual(testCase, out.bandPower.table.band, "custom");
verifyEqual(testCase, out.bandPower.table.totalPower, 10, 'AbsTol', 1e-12);
verifyTrue(testCase, isnan(out.bandPower.table.periodicPower));
end

function testConfigCompatibilityEntryPoint(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig();
frequencyHz = (1:40)';
psd = ones(40, 1);
psdResult = struct('frequencyHz', frequencyHz, 'psd', psd, 'units', "uV", 'fs', 1000);
model = struct('aperiodicFit', 0.5*ones(40,1), 'periodicFit', 0.5*ones(40,1));
result = computeBandPower(psdResult, model, cfg.bands);
verifyEqual(testCase, result.table.band(1), "delta");
verifyTrue(testCase, all(result.table.totalPower(result.table.band ~= "highGamma") >= 0));
verifyTrue(testCase, all(isnan(result.table.totalPower(result.table.band == "highGamma"))));
end

function data = base_data(frequencyHz, psd)
nSamples = 100;
data = struct('signal', zeros(nSamples, size(psd, 2)), 'fs', 1000, 'units', "uV", ...
    'channelLabels', ["1-2", "5-6"], 'spectrum', struct( ...
    'frequencyHz', frequencyHz, 'psd', psd), ...
    'processingHistory', struct('operation', "psd", 'parameters', struct(), 'notes', "fixture"));
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

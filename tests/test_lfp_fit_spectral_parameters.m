function tests = test_lfp_fit_spectral_parameters
%TEST_LFP_FIT_SPECTRAL_PARAMETERS Tests for fixed 1/f and peak separation.
tests = functiontests(localfunctions);
end

function testRecoversExponentAndPeriodicPeak(testCase)
ensure_src_on_path(testCase);
frequencyHz = (1:0.5:100)';
rng(11, 'twister');
aperiodic = 10 .^ (2 - 1.5*log10(frequencyHz));
psd = aperiodic .* 10 .^ (0.03*randn(size(frequencyHz)));
[~, peakIndex] = min(abs(frequencyHz - 10));
psd(peakIndex-2:peakIndex+2) = psd(peakIndex-2:peakIndex+2) .* [2 4 8 4 2]';
spectrum = struct('frequencyHz', frequencyHz, 'psd', psd, 'psdForFitting', psd);
data = base_data(spectrum);
out = lfp_fit_spectral_parameters(data, FitRangeHz=[3 80], ...
    PeakThresholdStd=2, MinPeakProminenceLog10=0.08);
result = out.spectralParameters.channels(1);
verifyEqual(testCase, result.status, "ok");
verifyEqual(testCase, result.exponent, 1.5, 'AbsTol', 0.15);
verifyGreaterThan(testCase, result.r2, 0.9);
verifyTrue(testCase, any(abs([result.peaks.centerFrequencyHz] - 10) < 1));
verifySize(testCase, out.spectralParameters.aperiodicPsd, size(psd));
verifyEqual(testCase, out.processingHistory(end).operation, "fixed_spectral_parameterization");
end

function testLegacyFittingCopyIsIgnored(testCase)
ensure_src_on_path(testCase);
frequencyHz = (1:100)';
psd = 100 ./ frequencyHz;
psd(frequencyHz == 40) = 1000;
spectrum = struct('frequencyHz', frequencyHz, 'psd', psd);
spectrum = lfp_interpolate_line_noise(spectrum);
data = base_data(spectrum);
out = lfp_fit_spectral_parameters(data, FitRangeHz=[3 90]);
verifyEqual(testCase, out.spectralParameters.originalPsd(40), 1000);
verifyEqual(testCase, out.spectralParameters.fittingPsd(40), 1000);
end

function data = base_data(spectrum)
data = struct('signal', zeros(10, 1), 'fs', 1000, 'units', "uV", ...
    'spectrum', spectrum, 'processingHistory', struct( ...
    'operation', "psd", 'parameters', struct(), 'notes', "fixture"));
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

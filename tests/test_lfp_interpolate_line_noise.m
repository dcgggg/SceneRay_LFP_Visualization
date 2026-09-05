function tests = test_lfp_interpolate_line_noise
%TEST_LFP_INTERPOLATE_LINE_NOISE Tests for fitting-only line-noise interpolation.
tests = functiontests(localfunctions);
end

function testInterpolatesFortyHertzAndHarmonic(testCase)
ensure_src_on_path(testCase);
frequencyHz = (1:150)';
baseline = 100 ./ frequencyHz;
psd = baseline;
psd(frequencyHz == 40) = 1000;
psd(frequencyHz == 80) = 700;
spectrum = struct('frequencyHz', frequencyHz, 'psd', psd);
out = lfp_interpolate_line_noise(spectrum, LineFrequencyHz=40, ...
    InterpolationHalfWidthHz=2, BufferSamples=3);
verifyEqual(testCase, out.psd, psd);
verifyLessThan(testCase, out.psdForFitting(frequencyHz == 40), 10);
verifyLessThan(testCase, out.psdForFitting(frequencyHz == 80), 10);
verifyEqual(testCase, numel(out.lineNoise.harmonicCentersHz), 3);
verifyEqual(testCase, nnz(out.lineNoise.interpolatedMask), 15);
end

function testCanDisableHarmonics(testCase)
ensure_src_on_path(testCase);
spectrum = struct('frequencyHz', (1:100)', 'psd', ones(100, 1));
spectrum.psd(40) = 50;
spectrum.psd(80) = 50;
out = lfp_interpolate_line_noise(spectrum, IncludeHarmonics=false);
verifyEqual(testCase, out.psdForFitting(80), 50);
verifyEqual(testCase, out.psdForFitting(40), 1, 'AbsTol', 1e-12);
end

function testDataWrapperRecordsProcessingHistory(testCase)
ensure_src_on_path(testCase);
spectrum = struct('frequencyHz', (1:100)', 'psd', ones(100, 1));
data = struct('signal', zeros(10, 1), 'fs', 1000, 'units', "uV", ...
    'spectrum', spectrum, 'processingHistory', struct( ...
    'operation', "psd", 'parameters', struct(), 'notes', "fixture"));
out = lfp_prepare_spectrum_for_fitting(data);
verifyEqual(testCase, out.processingHistory(end).operation, "line_noise_interpolation");
verifyTrue(testCase, isfield(out.spectrum, 'psdForFitting'));
verifyEqual(testCase, out.spectrum.psd, spectrum.psd);
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

function tests = test_parameterizePowerSpectrum
%TEST_PARAMETERIZEPOWERSPECTRUM Tests fixed/no-knee model structure and Gaussian peaks.
tests = functiontests(localfunctions);
end

function testRecoversFixedExponentAndPeak(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig();
freq = (1:0.25:40)';
rng(22, 'twister');
background = 10 .^ (1.5 - 1.2*log10(freq));
power = background .* 10 .^ (0.01*randn(size(freq)));
peak = 0.55 * exp(-0.5*((freq-10)/1.5).^2);
power = power .* 10.^peak;
result = parameterizePowerSpectrum(freq, power, cfg.fooof);
verifyEqual(testCase, result.fitStatus, "ok");
verifyEqual(testCase, result.aperiodicParams.exponent, 1.2, 'AbsTol', 0.15);
verifyGreaterThan(testCase, result.rSquared, 0.95);
verifyEqual(testCase, result.nPeaks, 1);
verifyEqual(testCase, result.peakParams.CF, 10, 'AbsTol', 0.5);
verifyEqual(testCase, result.peakParams.BW, 3, 'AbsTol', 1.5);
verifyEqual(testCase, result.gaussianParams.sigmaHz, result.peakParams.BW/2, 'AbsTol', 1e-12);
end

function testSupportsKneeAndNonpositivePower(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig();
cfg.fooof.aperiodicMode = "knee";
resultKnee = parameterizePowerSpectrum((1:10)', ones(10,1), cfg.fooof);
verifyEqual(testCase, resultKnee.aperiodicParams.mode, "knee");
verifyTrue(testCase, isfield(resultKnee.aperiodicParams, 'knee'));
cfg.fooof.aperiodicMode = "fixed";
power = ones(10,1); power(5) = 0;
result = parameterizePowerSpectrum((1:10)', power, cfg.fooof);
verifyEqual(testCase, result.fitStatus, "ok");
verifyTrue(testCase, isfinite(result.aperiodicParams.offset));
end

function testAcceptsChannelByFrequencyInput(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig();
freq = (1:40)';
power = [10 .^ (1 - log10(freq)), 10 .^ (0.5 - 0.7*log10(freq))].';
result = parameterizePowerSpectrum(freq, power, cfg.fooof);
verifyEqual(testCase, numel(result), 2);
verifyEqual(testCase, numel(result(1).aperiodicFit), numel(freq));
verifyEqual(testCase, numel(result(2).aperiodicFit), numel(freq));
end

function testDoesNotInterpolateLineNoise(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig();
freq = (1:0.25:100)';
base = 10 .^ (1.2 - 1.0*log10(freq));
power = base;
power(abs(freq-40) <= 2) = power(abs(freq-40) <= 2) * 100;
power(abs(freq-80) <= 2) = power(abs(freq-80) <= 2) * 100;
result = parameterizePowerSpectrum(freq, power, cfg.fooof);
verifyFalse(testCase, result.lineNoise.enabled);
verifyFalse(testCase, any(result.lineNoise.interpolatedMask));
verifyEqual(testCase, result.inputPower, power);
verifyEqual(testCase, result.fittingPower, power);
verifyFalse(testCase, result.interpolationApplied);
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

function tests = test_lfp_default_config
%TEST_LFP_DEFAULT_CONFIG Tests the GUI-independent configuration contract.
tests = functiontests(localfunctions);
end

function testContainsExplicitAnalysisDefaults(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig();
verifyEqual(testCase, cfg.artifact.method, "native");
verifyFalse(testCase, cfg.artifact.lineNoiseDetection);
verifyEqual(testCase, cfg.plot.maxPlotSeconds, Inf);
verifyEqual(testCase, cfg.psd.maxArtifactFraction, 0);
verifyEqual(testCase, cfg.psd.frequencyRange, [1 40]);
verifyEqual(testCase, cfg.fooof.frequencyRange, [1 35]);
verifyEqual(testCase, cfg.fooof.aperiodicMode, "fixed");
verifyEqual(testCase, cfg.bands.delta, [1 4]);
verifyEqual(testCase, cfg.bands.highGamma, [65 100]);
verifyGreaterThanOrEqual(testCase, numel(cfg.parameterMetadata), 10);
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

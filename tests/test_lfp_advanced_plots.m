function tests = test_lfp_advanced_plots
%TEST_LFP_ADVANCED_PLOTS Tests comparison and model summary plotting.
tests = functiontests(localfunctions);
end

function testPlotsReturnHandles(testCase)
ensure_src_on_path(testCase);
cfg = lfpDefaultConfig();
cfg.plot.visible = "off";
cfg.plot.channelIndex = 1;
data = fixture_data();
[cleanData, artifacts] = detectAndHandleArtifacts(data, set_native(cfg.artifact));
psdData = lfp_compute_psd(cleanData, WindowSeconds=0.5, FrequencyRangeHz=[1 40]);
model = parameterizePowerSpectrum(psdData.spectrum.frequencyHz, psdData.spectrum.psd(:,1), cfg.fooof);
bandData = lfp_compute_band_power(psdData);
h1 = plotArtifactComparison(data, cleanData, artifacts, cfg.plot);
h2 = plotSpectralModel(model, cfg.plot);
h3 = plotAnalysisSummary(artifacts, psdData.spectrum, model, bandData.bandPower, cfg.plot);
h4 = plotPsdComparison(psdData.spectrum, psdData.spectrum, cfg.plot);
h5 = plotBandPowerComparison(bandData.bandPower, bandData.bandPower, cfg.plot);
parent = figure('Visible', 'off');
cfgParent = cfg.plot; cfgParent.parent = parent;
hParent = plotSpectralModel(model, cfgParent);
verifyTrue(testCase, isgraphics(h1.figure));
verifyTrue(testCase, isgraphics(h2.figure));
verifyTrue(testCase, isgraphics(h3.figure));
verifyTrue(testCase, isgraphics(h4.figure));
verifyTrue(testCase, isgraphics(h5.figure));
verifyEqual(testCase, hParent.figure, parent);
failedModel = parameterizePowerSpectrum((1:40)', NaN(40,1), cfg.fooof);
hFailed = plotSpectralModel(failedModel, cfg.plot);
verifyEqual(testCase, failedModel.fitStatus, "insufficient_data");
verifyTrue(testCase, isgraphics(hFailed.figure));
close([h1.figure h2.figure h3.figure h4.figure h5.figure parent hFailed.figure]);
end

function cfg = set_native(cfg)
cfg.method = "native";
cfg.paddingSeconds = 0;
end

function data = fixture_data()
fs = 1000; t = (0:1999)'/fs;
signal = sin(2*pi*10*t); signal(500) = 100;
data = struct('signal', signal, 'fs', fs, 'time', t, 'channelLabels', "ch1", ...
    'units', "uV", 'metadata', struct(), 'processingHistory', struct( ...
    'operation', "import", 'parameters', struct(), 'notes', "fixture"));
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

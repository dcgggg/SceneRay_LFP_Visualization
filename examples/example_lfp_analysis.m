%EXAMPLE_LFP_ANALYSIS Run the script/API LFP workflow.
% Edit inputFile and outputFolder before running. No data are hard-coded.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
inputFile = "path/to/recording.csv";
outputFolder = "results";

data = lfp_import_scenray_csv(inputFile, SamplingRateHz=1000, Units="uV");
cfg = lfpDefaultConfig();
[cleanData, artifactResult] = detectAndHandleArtifacts(data, cfg.artifact);
psdResult = computeLfpPsd(cleanData, artifactResult, cfg.psd);
modelResult = parameterizePowerSpectrum(psdResult.frequencyHz, psdResult.psd, cfg.fooof);
bandResult = computeBandPower(psdResult, modelResult, cfg.bands);
cleanData.spectrum = psdResult;
cleanData.spectralParameters = struct('aperiodicPsd', horzcat(modelResult.aperiodicFit), ...
    'periodicPowerAboveAperiodic', horzcat(modelResult.periodicFit));
cleanData.bandPower = bandResult;
plotArtifactComparison(data, cleanData, artifactResult, cfg.plot);
plotSpectralModel(modelResult(1), cfg.plot);
plotAnalysisSummary(artifactResult, psdResult, modelResult, bandResult, cfg.plot);
files = lfp_export_results(cleanData, outputFolder);
disp(files);

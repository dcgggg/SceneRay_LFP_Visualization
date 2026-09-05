%EXAMPLE_LFP_ANALYSIS Run the script/API LFP workflow.
% Edit inputFile and outputFolder before running. No data are hard-coded.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
inputFile = "path/to/recording.csv";
outputFolder = "results";

data = lfp_import_scenray_csv(inputFile, SamplingRateHz=1000, Units="uV");
data = lfp_preprocess(data, ReplaceArtifacts=false);
data = lfp_compute_psd(data, WindowSeconds=4, OverlapFraction=0.5);
data = lfp_prepare_spectrum_for_fitting(data, LineFrequencyHz=40, ...
    InterpolationHalfWidthHz=2, BufferSamples=3);
data = lfp_fit_spectral_parameters(data, FitRangeHz=[3 150]);
data = lfp_compute_band_power(data);
lfp_plot_results(data);
files = lfp_export_results(data, outputFolder);
disp(files);

function tests = test_lfp_plot_export
%TEST_LFP_PLOT_EXPORT Tests non-GUI plotting and result export.
tests = functiontests(localfunctions);
end

function testPlotAndExport(testCase)
ensure_src_on_path(testCase);
fs = 1000;
t = (0:999)' / fs;
data = struct('signal', [sin(2*pi*10*t), cos(2*pi*12*t)], 'fs', fs, ...
    'time', t, 'channelLabels', ["1-2", "5-6"], 'units', "uV", ...
    'artifacts', struct('channelMask', false(1000, 2)), ...
    'processingHistory', struct('operation', "import", 'parameters', struct(), 'notes', "fixture"));
data = lfp_compute_psd(data, WindowSeconds=0.5);
data.spectrum = lfp_interpolate_line_noise(data.spectrum);
data = lfp_compute_band_power(data, Bands=struct('name', {"alpha"}, 'rangeHz', {[8 13]}));
figureHandle = lfp_plot_results(data, Visible="off");
verifyTrue(testCase, isgraphics(figureHandle));
close(figureHandle);
outputFolder = string(tempname);
files = lfp_export_results(data, outputFolder);
testCase.addTeardown(@() cleanup_folder(outputFolder));
verifyTrue(testCase, isfile(files.mat));
verifyTrue(testCase, isfile(files.bandPowerCsv));
verifyTrue(testCase, isfile(files.processingLogCsv));
verifyTrue(testCase, isfile(files.figurePng));
loaded = load(files.mat, 'data');
verifyEqual(testCase, loaded.data.signal, data.signal);
end

function cleanup_folder(folder)
if isfolder(folder)
    rmdir(folder, 's');
end
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

function files = lfp_export_results(data, outputFolder, options)
%LFP_EXPORT_RESULTS Export analysis data, tables, logs, and an overview PNG.
%   FILES = LFP_EXPORT_RESULTS(DATA, OUTPUTFOLDER) writes only analysis
%   results present in DATA. Existing files with the same names are
%   replaced because OUTPUTFOLDER is an explicit user-selected destination.

arguments
    data (1,1) struct
    outputFolder (1,1) string
    options.ExportFigure (1,1) logical = true
    options.FigureResolution (1,1) double {mustBeFinite, mustBePositive} = 300
    options.FigurePosition double = []
end

if strlength(strtrim(outputFolder)) == 0
    error('LFP:InvalidOutputFolder', 'Output folder must not be empty.');
end
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

files = struct('mat', "", 'bandPowerCsv', "", 'processingLogCsv', "", 'figurePng', "", ...
    'signalCsv', "", 'psdCsv', "");
files.mat = fullfile(outputFolder, 'analysis_results.mat');
save(files.mat, 'data', '-v7');

% Export the canonical time/signal arrays without changing the MAT session.
if isfield(data, 'signal') && isnumeric(data.signal)
    if isfield(data, 'time') && numel(data.time) == size(data.signal, 1)
        timeSeconds = double(data.time(:));
    elseif isfield(data, 'fs') && isfinite(data.fs) && data.fs > 0
        timeSeconds = (0:size(data.signal, 1)-1)' / double(data.fs);
    else
        timeSeconds = (0:size(data.signal, 1)-1)';
    end
    labels = get_labels(data, size(data.signal, 2));
    variableNames = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(cellstr(labels)));
    signalTable = array2table(double(data.signal), 'VariableNames', variableNames);
    signalTable = addvars(signalTable, timeSeconds, 'Before', 1, 'NewVariableNames', 'timeSeconds');
    files.signalCsv = fullfile(outputFolder, 'signal_data.csv');
    writetable(signalTable, files.signalCsv);
end

if isfield(data, 'spectrum') && isfield(data.spectrum, 'frequencyHz') && isfield(data.spectrum, 'psd')
    labels = get_labels(data.spectrum, size(data.spectrum.psd, 2));
    variableNames = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(cellstr(labels)));
    psdTable = array2table(double(data.spectrum.psd), 'VariableNames', variableNames);
    psdTable = addvars(psdTable, double(data.spectrum.frequencyHz(:)), 'Before', 1, 'NewVariableNames', 'frequencyHz');
    files.psdCsv = fullfile(outputFolder, 'psd.csv');
    writetable(psdTable, files.psdCsv);
end

if isfield(data, 'bandPower') && isfield(data.bandPower, 'table')
    files.bandPowerCsv = fullfile(outputFolder, 'band_power.csv');
    writetable(data.bandPower.table, files.bandPowerCsv);
end

if isfield(data, 'processingHistory')
    history = data.processingHistory;
    operation = strings(numel(history), 1);
    notes = strings(numel(history), 1);
    parametersJson = strings(numel(history), 1);
    for index = 1:numel(history)
        operation(index) = string(history(index).operation);
        notes(index) = string(history(index).notes);
        parametersJson(index) = string(jsonencode(history(index).parameters));
    end
    files.processingLogCsv = fullfile(outputFolder, 'processing_history.csv');
    writetable(table(operation, parametersJson, notes), files.processingLogCsv);
end

if options.ExportFigure
    files.figurePng = fullfile(outputFolder, 'analysis_overview.png');
    figureHandle = lfp_plot_results(data, Visible="off", FigurePosition=options.FigurePosition);
    cleanup = onCleanup(@() close_if_valid(figureHandle)); %#ok<NASGU>
    try
        exportgraphics(figureHandle, files.figurePng, 'Resolution', options.FigureResolution);
    catch
        saveas(figureHandle, files.figurePng);
    end
end
end

function close_if_valid(handle)
if ~isempty(handle) && isgraphics(handle)
    close(handle);
end
end

function labels = get_labels(data, nChannels)
if isfield(data, 'channelLabels') && numel(data.channelLabels) == nChannels
    labels = string(data.channelLabels(:));
elseif isfield(data, 'channelNames') && numel(data.channelNames) == nChannels
    labels = string(data.channelNames(:));
else
    labels = "channel_" + string((1:nChannels)');
end
end

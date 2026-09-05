function files = lfp_export_results(data, outputFolder, options)
%LFP_EXPORT_RESULTS Export analysis data, tables, logs, and an overview PNG.
%   FILES = LFP_EXPORT_RESULTS(DATA, OUTPUTFOLDER) writes only analysis
%   results present in DATA. Existing files with the same names are
%   replaced because OUTPUTFOLDER is an explicit user-selected destination.

arguments
    data (1,1) struct
    outputFolder (1,1) string
    options.ExportFigure (1,1) logical = true
end

if strlength(strtrim(outputFolder)) == 0
    error('LFP:InvalidOutputFolder', 'Output folder must not be empty.');
end
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

files = struct('mat', "", 'bandPowerCsv', "", 'processingLogCsv', "", 'figurePng', "");
files.mat = fullfile(outputFolder, 'analysis_results.mat');
save(files.mat, 'data', '-v7');

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
    figureHandle = lfp_plot_results(data, Visible="off");
    cleanup = onCleanup(@() close_if_valid(figureHandle)); %#ok<NASGU>
    try
        exportgraphics(figureHandle, files.figurePng, 'Resolution', 150);
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

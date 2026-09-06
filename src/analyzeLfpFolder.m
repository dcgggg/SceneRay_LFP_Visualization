function batchResult = analyzeLfpFolder(inputFolder, cfg, options)
%ANALYZELFPFOLDER Analyze every CSV in a folder with one shared pipeline.
%   BATCHRESULT = ANALYZELFPFOLDER(INPUTFOLDER) scans INPUTFOLDER/*.csv and
%   runs import, artifact annotation, PSD, fixed spectral parameterization,
%   and band-power analysis once per file. Each file may contain one or more
%   repeated Channel blocks; channels remain separate columns throughout.
%   BATCHRESULT.files is a struct array with data, artifactResult,
%   psdResult, modelResult, bandResult, status and errorMessage fields.
%
%   Optional CFG defaults to lfpDefaultConfig(). Set MakeFigures=true to
%   create diagnostic figures. Set ExportResults=true and OutputFolder to
%   write one subfolder per input CSV using lfp_export_results.

arguments
    inputFolder (1,1) string
    cfg (1,1) struct = lfpDefaultConfig()
    options.OutputFolder (1,1) string = ""
    options.MakeFigures (1,1) logical = false
    options.ExportResults (1,1) logical = false
    options.StopOnError (1,1) logical = false
end

if ~isfolder(inputFolder)
    error('LFP:InputFolderNotFound', 'Input folder does not exist: %s', inputFolder);
end
csvFiles = dir(fullfile(inputFolder, '*.csv'));
if isempty(csvFiles)
    error('LFP:NoCsvFiles', 'No CSV files found in: %s', inputFolder);
end
[~, order] = sort(lower(string({csvFiles.name})));
csvFiles = csvFiles(order);
if (options.MakeFigures || options.ExportResults) && strlength(options.OutputFolder) == 0
    error('LFP:OutputFolderRequired', 'OutputFolder is required when figures or exports are enabled.');
end
if options.ExportResults && ~isfolder(options.OutputFolder)
    mkdir(options.OutputFolder);
end

fileResults = repmat(empty_file_result(), numel(csvFiles), 1);
for fileIndex = 1:numel(csvFiles)
    inputFile = string(fullfile(csvFiles(fileIndex).folder, csvFiles(fileIndex).name));
    fileResults(fileIndex).fileName = string(csvFiles(fileIndex).name);
    fileResults(fileIndex).filePath = inputFile;
    try
        data = lfp_import_scenray_csv(inputFile);
        data.metadata.sourceFilePath = inputFile;
        data.metadata.displayName = make_display_name(data);
        [cleanData, artifactResult] = detectAndHandleArtifacts(data, cfg.artifact);
        psdResult = computeLfpPsd(cleanData, artifactResult, cfg.psd);
        modelResult = parameterizePowerSpectrum(psdResult.frequencyHz, psdResult.psd, cfg.fooof);
        modelResult = add_model_context(modelResult, data);
        bandResult = computeBandPower(psdResult, modelResult, cfg.bands);

        cleanData.spectrum = psdResult;
        cleanData.spectralParameters = struct( ...
            'aperiodicPsd', collect_model_field(modelResult, 'aperiodicFit'), ...
            'periodicPowerAboveAperiodic', collect_model_field(modelResult, 'periodicFit'));
        cleanData.bandPower = bandResult;
        cleanData.metadata = data.metadata;

        fileResults(fileIndex).data = cleanData;
        fileResults(fileIndex).artifactResult = artifactResult;
        fileResults(fileIndex).psdResult = psdResult;
        fileResults(fileIndex).modelResult = modelResult;
        fileResults(fileIndex).bandResult = bandResult;
        fileResults(fileIndex).channelLabels = data.channelLabels;
        fileResults(fileIndex).ipgSN = get_metadata(data, 'ipgSN', "unknown");
        fileResults(fileIndex).channelCount = size(data.signal, 2);
        fileResults(fileIndex).status = "ok";

        if options.MakeFigures
            outputFolder = fullfile(options.OutputFolder, safe_name(fileResults(fileIndex).fileName));
            if ~isfolder(outputFolder), mkdir(outputFolder); end
            create_figures(data, cleanData, artifactResult, psdResult, modelResult, bandResult, cfg.plot, outputFolder);
        end
        if options.ExportResults
            outputFolder = fullfile(options.OutputFolder, safe_name(fileResults(fileIndex).fileName));
            if ~isfolder(outputFolder), mkdir(outputFolder); end
            fileResults(fileIndex).exportedFiles = lfp_export_results(cleanData, outputFolder);
        end
    catch exception
        fileResults(fileIndex).status = "failed";
        fileResults(fileIndex).errorMessage = string(exception.message);
        fileResults(fileIndex).errorIdentifier = string(exception.identifier);
        if options.StopOnError
            rethrow(exception);
        end
    end
end

batchResult = struct('inputFolder', inputFolder, 'fileCount', numel(csvFiles), ...
    'files', fileResults, 'successfulCount', nnz([fileResults.status] == "ok"), ...
    'failedCount', nnz([fileResults.status] == "failed"), ...
    'processingHistory', struct('operation', "folder_analysis", ...
    'parameters', struct('inputFolder', inputFolder, 'fileCount', numel(csvFiles)), ...
    'notes', "Each CSV was processed once through the shared multi-channel pipeline."));
end

function result = empty_file_result()
result = struct('fileName', "", 'filePath', "", 'status', "pending", ...
    'errorMessage', "", 'errorIdentifier', "", 'channelCount', 0, ...
    'channelLabels', strings(0,1), 'ipgSN', "", 'data', struct(), ...
    'artifactResult', struct(), 'psdResult', struct(), 'modelResult', struct(), ...
    'bandResult', struct(), 'exportedFiles', struct());
end

function name = make_display_name(data)
ipg = get_metadata(data, 'ipgSN', "unknown");
name = string(get_filename(data.metadata.sourceFileName)) + " | IPG SN " + string(ipg);
end

function value = get_metadata(data, fieldName, defaultValue)
value = defaultValue;
if isfield(data, 'metadata') && isfield(data.metadata, fieldName) && ~isempty(data.metadata.(fieldName))
    value = string(data.metadata.(fieldName));
end
end

function models = add_model_context(models, data)
labels = string(data.channelLabels(:));
for index = 1:numel(models)
    models(index).channelIndex = index;
    models(index).channelLabel = labels(index);
    models(index).ipgSN = get_metadata(data, 'ipgSN', "unknown");
    models(index).sourceFileName = string(data.metadata.sourceFileName);
end
end

function matrix = collect_model_field(models, fieldName)
if isempty(models)
    matrix = [];
    return;
end
nFrequencies = numel(models(1).freq);
matrix = NaN(nFrequencies, numel(models));
for index = 1:numel(models)
    values = models(index).(fieldName);
    if ~isempty(values) && numel(values) == nFrequencies
        matrix(:, index) = values(:);
    end
end
end

function create_figures(data, cleanData, artifactResult, psdResult, modelResult, bandResult, plotCfg, outputFolder)
displayName = string(data.metadata.displayName);
localCfg = plotCfg;
localCfg.visible = "off";
h = plotArtifactComparison(data, cleanData, artifactResult, localCfg);
save_figure(h.figure, fullfile(outputFolder, 'artifact_comparison.png'), displayName);
close(h.figure);
h = plotAnalysisSummary(artifactResult, psdResult, modelResult, bandResult, localCfg);
save_figure(h.figure, fullfile(outputFolder, 'analysis_summary.png'), displayName);
close(h.figure);
for index = 1:numel(modelResult)
    h = plotSpectralModel(modelResult(index), localCfg);
    save_figure(h.figure, fullfile(outputFolder, sprintf('spectral_model_ch%02d.png', index)), ...
        displayName + " | " + modelResult(index).channelLabel);
    close(h.figure);
end
end

function save_figure(figureHandle, filename, displayName)
sgtitle(figureHandle, displayName, 'Interpreter', 'none');
try
    exportgraphics(figureHandle, filename, 'Resolution', 150);
catch
    saveas(figureHandle, filename);
end
end

function value = safe_name(filename)
[~, stem] = fileparts(filename);
value = regexprep(stem, '[^A-Za-z0-9._-]', '_');
if isempty(value), value = 'file'; end
end

function value = get_filename(filename)
[~, name, extension] = fileparts(filename);
value = name + extension;
end

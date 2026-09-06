%EXAMPLE_LFP_BATCH Analyze every CSV in a folder.
% Edit inputFolder and outputFolder before running. The batch function
% identifies repeated Channel blocks, preserves channelLabel and IPG SN, and
% runs each analysis stage once per file without mixing files or channels.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));

inputFolder = "path/to/test";
outputFolder = "results";
cfg = lfpDefaultConfig();

batch = analyzeLfpFolder(inputFolder, cfg, ...
    OutputFolder=outputFolder, MakeFigures=true, ExportResults=true);

for fileIndex = 1:batch.fileCount
    item = batch.files(fileIndex);
    fprintf('%s | IPG SN %s | %d channels | %s\n', ...
        item.fileName, item.ipgSN, item.channelCount, item.status);
    if item.status == "ok"
        disp(item.channelLabels);
    else
        fprintf('  error: %s\n', item.errorMessage);
    end
end

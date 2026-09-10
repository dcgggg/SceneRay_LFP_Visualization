function [cells, info] = lfp_read_csv_preview(filename, options)
%LFP_READ_CSV_PREVIEW Read only the first rows of a delimited text file.
%   This avoids loading a large CSV into a heterogeneous cell matrix merely
%   to populate the import-preview table. The returned row count is exact
%   only when EOF is reached; otherwise an estimate based on bytes read is
%   provided separately.

arguments
    filename (1,1) string
    options.Delimiter {mustBeTextScalar} = ','
    options.MaxRows (1,1) double {mustBeInteger, mustBePositive} = 200
end

if ~isfile(filename)
    error('LFP:FileNotFound', 'Input CSV does not exist: %s', filename);
end
fileInfo = dir(filename);
fileId = fopen(filename, 'r');
if fileId < 0
    error('LFP:CsvReadFailed', 'Could not open CSV for preview: %s', filename);
end
cleanup = onCleanup(@() fclose(fileId)); %#ok<NASGU>

rows = cell(options.MaxRows, 1);
rowCount = 0;
maxColumns = 0;
reachedEof = false;
while rowCount < options.MaxRows
    line = fgetl(fileId);
    if ~ischar(line)
        reachedEof = true;
        break;
    end
    rowCount = rowCount + 1;
    rows{rowCount} = lfp_parse_delimited_line(line, options.Delimiter);
    maxColumns = max(maxColumns, numel(rows{rowCount}));
end
bytesRead = max(0, ftell(fileId));
rows = rows(1:rowCount);
cells = cell(rowCount, maxColumns);
cells(:) = {''};
for row = 1:rowCount
    values = rows{row};
    cells(row, 1:numel(values)) = values;
end

if reachedEof
    estimatedRows = rowCount;
else
    meanBytesPerRow = bytesRead / max(rowCount, 1);
    estimatedRows = max(rowCount, round(double(fileInfo.bytes) / max(meanBytesPerRow, 1)));
end
info = struct('fileSizeBytes', double(fileInfo.bytes), 'previewRowCount', rowCount, ...
    'columnCount', maxColumns, 'reachedEof', reachedEof, ...
    'exactRowCount', ternary(reachedEof, rowCount, NaN), ...
    'estimatedRowCount', estimatedRows, 'bytesRead', bytesRead, ...
    'readStrategy', "streamed_preview");
end

function value = ternary(condition, first, second)
if condition, value = first; else, value = second; end
end

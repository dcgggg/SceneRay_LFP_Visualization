function inspection = lfp_inspect_csv(filename, options)
%LFP_INSPECT_CSV Inspect a CSV before importing it into the LFP data model.
%   INSPECTION = LFP_INSPECT_CSV(FILENAME) reads a small, non-destructive
%   preview and returns automatic suggestions for header/data/time/signal
%   rows and columns.  The suggestions are advisory: a GUI or script should
%   present them for confirmation when the layout is ambiguous.
%
%   This function does not modify the source file and does not interpolate,
%   resample, or otherwise alter signal values.  It supports SceneRay files
%   with repeated Channel blocks as well as generic rectangular CSV files.

arguments
    filename (1,1) string
    options.Delimiter (1,1) string = ","
    options.PreviewRows (1,1) double {mustBeInteger, mustBePositive} = 20
    options.ScanRows (1,1) double {mustBeInteger, mustBePositive} = 200
end

if ~isfile(filename)
    error('LFP:FileNotFound', 'Input CSV does not exist: %s', filename);
end
delimiter = char(options.Delimiter);
try
    started = tic;
    [cells, previewInfo] = lfp_read_csv_preview(filename, Delimiter=delimiter, ...
        MaxRows=max(options.PreviewRows, options.ScanRows));
    inspectionSeconds = toc(started);
catch exception
    error('LFP:CsvReadFailed', 'Could not read CSV %s: %s', filename, exception.message);
end
if isempty(cells)
    error('LFP:EmptyCsv', 'CSV is empty: %s', filename);
end

nRows = size(cells, 1);
nColumns = size(cells, 2);
firstColumn = strings(nRows, 1);
for row = 1:nRows
    firstColumn(row) = normalize_token(cells{row, 1});
end
isSceneRay = any(firstColumn == "channel") && any(firstColumn == "timeindex");

[headerRow, dataStartRow] = suggest_rows(cells);
channelNames = suggest_channel_names(cells, headerRow, nColumns);
timeColumn = suggest_time_column(cells, headerRow, dataStartRow, nColumns);
signalColumns = suggest_signal_columns(cells, dataStartRow, nColumns, timeColumn);
[estimatedFs, timeValidation] = estimate_time(cells, dataStartRow, timeColumn);

previewRows = min(nRows, options.PreviewRows);
inspection = struct();
inspection.filename = filename;
inspection.delimiter = string(options.Delimiter);
% CELLS now contains only the bounded scan used for layout suggestions. It
% must never be treated as the complete imported dataset unless EOF was
% reached within ScanRows.
inspection.cells = cells;
inspection.cellsContainFullFile = previewInfo.reachedEof;
% Keep the raw cells unchanged for import, but expose a uitable-safe copy for
% GUI preview.  MATLAB uitable accepts only numeric, logical, or char values
% inside a cell array; readcell may return string, missing, datetime, or other
% scalar types depending on the CSV content.
inspection.preview = preview_for_uitable(cells(1:previewRows, :));
inspection.rowCount = previewInfo.exactRowCount;
inspection.estimatedRowCount = previewInfo.estimatedRowCount;
inspection.columnCount = nColumns;
inspection.fileSizeBytes = previewInfo.fileSizeBytes;
inspection.previewRowCount = previewInfo.previewRowCount;
inspection.readStrategy = previewInfo.readStrategy;
inspection.inspectionSeconds = inspectionSeconds;
inspection.isSceneRay = isSceneRay;
inspection.formatSuggestion = ternary(isSceneRay, "SceneRay", "generic");
inspection.headerRowSuggestion = headerRow;
inspection.dataStartRowSuggestion = dataStartRow;
inspection.timeColumnSuggestion = timeColumn;
inspection.signalColumnsSuggestion = signalColumns;
inspection.channelNamesSuggestion = channelNames;
inspection.estimatedSamplingRateHz = estimatedFs;
inspection.timeValidation = timeValidation;
inspection.warnings = build_warnings(isSceneRay, headerRow, dataStartRow, timeColumn, ...
    signalColumns, estimatedFs, timeValidation);
end

function [headerRow, dataStartRow] = suggest_rows(cells)
nRows = size(cells, 1);
headerRow = 0;
dataStartRow = 0;
numericCounts = zeros(nRows, 1);
for row = 1:nRows
    numericCounts(row) = nnz(cellfun(@is_numeric_scalar, cells(row, :)));
end
candidate = find(numericCounts >= 2, 1, 'first');
if isempty(candidate)
    dataStartRow = nRows + 1;
    return;
end
dataStartRow = candidate;
if candidate > 1
    previous = cells(candidate - 1, :);
    textCount = nnz(cellfun(@is_text_cell, previous));
    if textCount > 0 && textCount >= nnz(cellfun(@is_numeric_scalar, previous))
        headerRow = candidate - 1;
    end
end
end

function names = suggest_channel_names(cells, headerRow, nColumns)
names = "channel_" + string(1:nColumns);
if headerRow <= 0 || headerRow > size(cells, 1)
    return;
end
for column = 1:nColumns
    token = string_or_empty(cells{headerRow, column});
    if strlength(strtrim(token)) > 0
        names(column) = strtrim(token);
    end
end
end

function timeColumn = suggest_time_column(cells, headerRow, dataStartRow, nColumns)
timeColumn = 0;
if headerRow > 0
    for column = 1:nColumns
        token = lower(strtrim(string_or_empty(cells{headerRow, column})));
        if contains(token, ["time" "timestamp" "sample" "index"]) && ...
                ~contains(token, ["voltage" "signal" "lfp"])
            timeColumn = column;
            return;
        end
    end
end
if dataStartRow > size(cells, 1)
    return;
end
% A time column is usually finite, strictly increasing and independent of
% signal scale.  Only use this as a suggestion; the GUI allows confirmation.
for column = 1:nColumns
    values = numeric_column(cells, dataStartRow, column);
    values = values(isfinite(values));
    if numel(values) >= 4
        delta = diff(values);
        if all(delta > 0) && median(delta) > 0
            timeColumn = column;
            return;
        end
    end
end
end

function signalColumns = suggest_signal_columns(cells, dataStartRow, nColumns, timeColumn)
signalColumns = zeros(1, 0);
if dataStartRow > size(cells, 1)
    return;
end
for column = 1:nColumns
    values = numeric_column(cells, dataStartRow, column);
    if nnz(isfinite(values)) >= 2 && column ~= timeColumn
        signalColumns(end + 1) = column; %#ok<AGROW>
    end
end
end

function [estimatedFs, validation] = estimate_time(cells, dataStartRow, timeColumn)
estimatedFs = NaN;
validation = struct('hasTimeColumn', timeColumn > 0, 'valid', true, ...
    'isMonotonic', true, 'hasDuplicates', false, 'isIrregular', false, ...
    'medianStep', NaN, 'coefficientOfVariation', NaN, 'message', "");
if timeColumn <= 0 || dataStartRow > size(cells, 1)
    validation.message = "No time column detected; sampling rate must be supplied.";
    return;
end
values = numeric_column(cells, dataStartRow, timeColumn);
values = values(isfinite(values));
if numel(values) < 3
    validation.valid = false;
    validation.message = "Time column has fewer than three finite values.";
    return;
end
delta = diff(values);
validation.medianStep = median(delta);
validation.hasDuplicates = any(delta == 0);
validation.isMonotonic = all(delta > 0);
positiveDelta = delta(delta > 0);
if isempty(positiveDelta) || ~isfinite(validation.medianStep) || validation.medianStep <= 0
    validation.valid = false;
    validation.isMonotonic = false;
    validation.message = "Time values are not strictly increasing.";
    return;
end
validation.coefficientOfVariation = std(positiveDelta) / max(mean(positiveDelta), eps);
validation.isIrregular = validation.coefficientOfVariation > 1e-3 || validation.hasDuplicates;
validation.valid = validation.isMonotonic && ~validation.hasDuplicates;
estimatedFs = 1 / validation.medianStep;
if validation.isIrregular
    validation.message = "Time spacing is irregular; uniform-sampling analysis must be confirmed or stopped.";
else
    validation.message = "Time column is strictly increasing with regular spacing.";
end
end

function warnings = build_warnings(isSceneRay, headerRow, dataStartRow, timeColumn, signalColumns, fs, validation)
warnings = strings(0, 1);
if isSceneRay
    warnings(end + 1) = "SceneRay layout detected; the dedicated multi-block importer will preserve Channel/IPG metadata."; %#ok<AGROW>
end
if headerRow == 0
    warnings(end + 1) = "No header row was confidently detected; channel names will be generated unless confirmed."; %#ok<AGROW>
end
if isempty(signalColumns)
    warnings(end + 1) = "No numeric signal columns were detected."; %#ok<AGROW>
end
if timeColumn == 0 || ~validation.hasTimeColumn
    warnings(end + 1) = "No usable time column was detected; provide a sampling rate before analysis."; %#ok<AGROW>
elseif ~validation.valid || validation.isIrregular
    warnings(end + 1) = validation.message; %#ok<AGROW>
elseif isfinite(fs) && fs > 0
    warnings(end + 1) = sprintf('Estimated sampling rate: %.6g Hz.', fs); %#ok<AGROW>
end
if dataStartRow > 1 && headerRow == 0
    warnings(end + 1) = sprintf('The first numeric row is %d; preceding rows will be treated as metadata/ignored.', dataStartRow); %#ok<AGROW>
end
end

function data = numeric_column(cells, firstRow, column)
data = NaN(size(cells, 1) - firstRow + 1, 1);
for index = firstRow:size(cells, 1)
    data(index - firstRow + 1) = to_number(cells{index, column});
end
end

function tf = is_numeric_scalar(value)
if isnumeric(value) && isscalar(value)
    tf = isfinite(value);
else
    tf = isfinite(str2double(strtrim(string_or_empty(value))));
end
end

function tf = is_text_cell(value)
tf = ischar(value) || isstring(value) || (iscell(value) && ~isempty(value));
end

function value = normalize_token(raw)
value = lower(string_or_empty(raw));
value = erase(value, [" " "_" "-" char(9)]);
end

function value = to_number(raw)
if isnumeric(raw) && isscalar(raw)
    value = double(raw);
else
    value = str2double(strtrim(string_or_empty(raw)));
end
end

function value = string_or_empty(raw)
if isempty(raw)
    value = "";
elseif isstring(raw) || ischar(raw)
    value = string(raw);
elseif isnumeric(raw) && isscalar(raw) && isfinite(raw)
    value = string(raw);
else
    value = "";
end
end

function value = ternary(condition, first, second)
if condition, value = first; else, value = second; end
end

function preview = preview_for_uitable(rawCells)
%PREVIEW_FOR_UITABLE Convert only the display copy to uitable-safe values.
preview = cell(size(rawCells));
for row = 1:size(rawCells, 1)
    for column = 1:size(rawCells, 2)
        value = rawCells{row, column};
        if isnumeric(value) && isscalar(value)
            preview{row, column} = value;
        elseif islogical(value) && isscalar(value)
            preview{row, column} = value;
        elseif ischar(value)
            preview{row, column} = value;
        elseif isstring(value) && isscalar(value)
            if ismissing(value)
                preview{row, column} = '';
            else
                preview{row, column} = char(value);
            end
        elseif isempty(value)
            preview{row, column} = '';
        else
            % This fallback keeps the preview robust for uncommon scalar
            % values without changing the raw cell stored in inspection.cells.
            try
                token = string(value);
                if ismissing(token)
                    preview{row, column} = '';
                else
                    preview{row, column} = char(token);
                end
            catch
                preview{row, column} = '';
            end
        end
    end
end
end

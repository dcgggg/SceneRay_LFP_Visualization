function [data, importInfo] = lfp_import_csv_configured(filename, options)
%LFP_IMPORT_CSV_CONFIGURED Import SceneRay or generic CSV with explicit layout.
%   DATA = LFP_IMPORT_CSV_CONFIGURED(FILENAME) uses conservative automatic
%   suggestions from LFP_INSPECT_CSV.  DATA = ... (FILENAME, options) accepts
%   HeaderRow, DataStartRow, TimeColumn, SignalColumns, SamplingRateHz,
%   Units, AmplitudeScale, TimeUnit, Delimiter, DataDirection and an optional
%   precomputed Inspection structure.  A GUI
%   should show these values and let the user confirm them before calling.
%
%   The source file is never modified. Missing numeric cells remain NaN and
%   are reported in DATA.metadata; no silent interpolation or resampling is
%   performed. Uniform-sampling analysis is blocked by the GUI when the time
%   column is invalid or irregular. SceneRay files are delegated to the
%   existing block-aware importer so Channel/IPG metadata and row indices are
%   preserved.

arguments
    filename (1,1) string
    options.Delimiter (1,1) string = ","
    options.HeaderRow (1,1) double = NaN
    options.DataStartRow (1,1) double = NaN
    options.TimeColumn (1,1) double = NaN
    options.SignalColumns double = []
    options.DataDirection (1,1) string {mustBeMember(options.DataDirection, ["samples_by_channels" "channels_by_samples"])} = "samples_by_channels"
    options.SamplingRateHz (1,1) double = NaN
    options.Units (1,1) string = "uV"
    options.AmplitudeScale (1,1) double = 1
    options.TimeUnit (1,1) string {mustBeMember(options.TimeUnit, ["s" "ms"])} = "s"
    options.UseSceneRay (1,1) logical = true
    options.Inspection struct = struct()
end

inspection = options.Inspection;
reuseInspection = ~isempty(fieldnames(inspection)) && isfield(inspection, 'delimiter') && ...
    string(inspection.delimiter) == options.Delimiter && isfield(inspection, 'cells');
if ~reuseInspection
    inspection = lfp_inspect_csv(filename, Delimiter=options.Delimiter);
end
if inspection.isSceneRay && options.UseSceneRay
    fs = options.SamplingRateHz;
    if ~isfinite(fs) || fs <= 0, fs = 1000; end
    data = lfp_import_scenray_csv(filename, SamplingRateHz=fs, Units=options.Units, Cells=inspection.cells);
    data.metadata.sourceFilePath = filename;
    data.metadata.importSettings = struct('format', "SceneRay", 'delimiter', options.Delimiter, ...
        'headerRow', NaN, 'dataStartRow', NaN, 'timeColumn', 1, ...
        'signalColumns', 2, 'dataDirection', "samples_by_channels", ...
        'samplingRateHz', fs, 'units', options.Units, 'amplitudeScale', 1, 'timeUnit', "index");
    data.metadata.displayName = make_display_name(data);
    importInfo = inspection;
    importInfo.usedFormat = "SceneRay";
    return;
end

cells = inspection.cells;
nRows = size(cells, 1);
nColumns = size(cells, 2);
headerRow = options.HeaderRow;
if ~isfinite(headerRow), headerRow = inspection.headerRowSuggestion; end
dataStartRow = options.DataStartRow;
if ~isfinite(dataStartRow), dataStartRow = inspection.dataStartRowSuggestion; end
timeColumn = options.TimeColumn;
if ~isfinite(timeColumn), timeColumn = inspection.timeColumnSuggestion; end
headerRow = round(headerRow);
dataStartRow = round(dataStartRow);
timeColumn = round(timeColumn);
if dataStartRow < 1 || dataStartRow > nRows
    error('LFP:InvalidDataStartRow', 'DataStartRow must identify a row between 1 and %d.', nRows);
end
if timeColumn < 0 || timeColumn > nColumns
    error('LFP:InvalidTimeColumn', 'TimeColumn must be 0 (none) or a valid column index.');
end

signalColumns = options.SignalColumns;
if isempty(signalColumns), signalColumns = inspection.signalColumnsSuggestion; end
signalColumns = unique(round(signalColumns(:)'));
signalColumns = signalColumns(signalColumns >= 1 & signalColumns <= nColumns & signalColumns ~= timeColumn);
if isempty(signalColumns)
    error('LFP:NoSignalColumns', 'No numeric signal columns remain after excluding the time column.');
end

rowIndices = dataStartRow:nRows;
if options.DataDirection == "channels_by_samples"
    % In this explicit orientation, each source row is one channel and the
    % selected columns are samples.  The canonical model remains
    % samples-by-channels after transposition.  A time column is ambiguous in
    % this layout, so require an explicit sampling rate instead.
    if timeColumn > 0
        error('LFP:TimeColumnUnsupportedForOrientation', ...
            'For channels_by_samples input, set TimeColumn to 0 and provide SamplingRateHz.');
    end
    signal = NaN(numel(signalColumns), numel(rowIndices));
    for channel = 1:numel(rowIndices)
        for sample = 1:numel(signalColumns)
            signal(sample, channel) = to_number(cells{rowIndices(channel), signalColumns(sample)});
        end
    end
else
    nSamples = numel(rowIndices);
    signal = NaN(nSamples, numel(signalColumns));
    for channel = 1:numel(signalColumns)
        column = signalColumns(channel);
        for row = 1:nSamples
            signal(row, channel) = to_number(cells{rowIndices(row), column});
        end
    end
end
signal = signal .* options.AmplitudeScale;

nSamples = size(signal, 1);
timeValues = NaN(nSamples, 1);
estimatedFs = NaN;
timeValidation = struct('hasTimeColumn', timeColumn > 0, 'valid', true, ...
    'isMonotonic', true, 'hasDuplicates', false, 'isIrregular', false, ...
    'medianStep', NaN, 'coefficientOfVariation', NaN, 'message', "");
if timeColumn > 0
    for row = 1:nSamples
        timeValues(row) = to_number(cells{rowIndices(row), timeColumn});
    end
    if options.TimeUnit == "ms", timeValues = timeValues / 1000; end
    [estimatedFs, timeValidation] = validate_time_values(timeValues);
    fs = options.SamplingRateHz;
    if ~isfinite(fs) || fs <= 0, fs = estimatedFs; end
    if ~isfinite(fs) || fs <= 0
        error('LFP:SamplingRateRequired', 'A valid sampling rate is required when no usable time column is available.');
    end
else
    fs = options.SamplingRateHz;
    if ~isfinite(fs) || fs <= 0
        error('LFP:SamplingRateRequired', 'SamplingRateHz must be supplied when TimeColumn is 0.');
    end
    timeValues = (0:nSamples - 1)' / fs;
    timeValidation.message = "No time column; time generated from confirmed sampling rate.";
end

channelLabels = "channel_" + string(1:size(signal, 2));
if options.DataDirection == "channels_by_samples"
    channelLabels = "channel_" + string(1:size(signal, 2));
    % If the first non-signal column contains one label per channel row,
    % preserve it.  Otherwise generated names make the ambiguity explicit.
    labelColumn = setdiff(1:nColumns, signalColumns);
    if ~isempty(labelColumn)
        labelColumn = labelColumn(1);
        for channel = 1:numel(rowIndices)
            candidate = string_or_empty(cells{rowIndices(channel), labelColumn});
            if strlength(strtrim(candidate)) > 0 && ~isfinite(str2double(candidate))
                channelLabels(channel) = strtrim(candidate);
            end
        end
    end
elseif headerRow >= 1 && headerRow <= nRows
    channelLabels = "channel_" + string(1:numel(signalColumns));
    for channel = 1:numel(signalColumns)
        candidate = string_or_empty(cells{headerRow, signalColumns(channel)});
        if strlength(strtrim(candidate)) > 0
            channelLabels(channel) = strtrim(candidate);
        end
    end
end

metadata = struct();
metadata.sourceFileName = string(get_filename(filename));
metadata.sourceFilePath = filename;
metadata.sourceFormat = "Generic CSV";
metadata.samplingRateHz = fs;
metadata.units = options.Units;
metadata.headerRow = headerRow;
metadata.dataStartRow = dataStartRow;
metadata.timeColumn = timeColumn;
metadata.signalColumns = signalColumns;
metadata.ignoredColumns = setdiff(1:nColumns, [timeColumn signalColumns]);
metadata.dataDirection = options.DataDirection;
metadata.timeUnit = options.TimeUnit;
metadata.timeValidation = timeValidation;
metadata.estimatedSamplingRateHz = estimatedFs;
metadata.amplitudeScale = options.AmplitudeScale;
metadata.missingValueCount = nnz(~isfinite(signal));
metadata.displayName = string(get_filename(filename));
metadata.importSettings = struct('format', "generic", 'delimiter', options.Delimiter, ...
    'headerRow', headerRow, 'dataStartRow', dataStartRow, 'timeColumn', timeColumn, ...
    'signalColumns', signalColumns, 'dataDirection', options.DataDirection, ...
    'samplingRateHz', fs, 'units', options.Units, 'amplitudeScale', options.AmplitudeScale, ...
    'timeUnit', options.TimeUnit);

data = struct();
data.signal = signal;
data.fs = fs;
data.time = timeValues;
data.channelLabels = channelLabels;
data.channelNames = channelLabels;
data.channelCount = size(signal, 2);
data.units = options.Units;
data.metadata = metadata;
data.artifacts = struct('intervals_s', zeros(0, 2), 'channelMask', false(size(signal)), ...
    'labels', strings(0, 1), 'method', "not_detected");
data.processingHistory = struct('operation', "import", 'parameters', metadata.importSettings, ...
    'notes', "Generic CSV imported without modifying source data; missing values retained as NaN.");

importInfo = inspection;
importInfo.usedFormat = "generic";
importInfo.actualHeaderRow = headerRow;
importInfo.actualDataStartRow = dataStartRow;
importInfo.actualTimeColumn = timeColumn;
importInfo.actualSignalColumns = signalColumns;
importInfo.actualSamplingRateHz = fs;
end

function [estimatedFs, validation] = validate_time_values(timeValues)
estimatedFs = NaN;
finite = isfinite(timeValues);
validation = struct('hasTimeColumn', true, 'valid', true, 'isMonotonic', true, ...
    'hasDuplicates', false, 'isIrregular', false, 'medianStep', NaN, ...
    'coefficientOfVariation', NaN, 'message', "");
if nnz(finite) < 3
    validation.valid = false;
    validation.message = "Time column has fewer than three finite values.";
    return;
end
values = timeValues(finite);
delta = diff(values);
validation.medianStep = median(delta);
validation.hasDuplicates = any(delta == 0);
validation.isMonotonic = all(delta > 0);
positive = delta(delta > 0);
if isempty(positive) || ~isfinite(validation.medianStep) || validation.medianStep <= 0
    validation.valid = false;
    validation.isMonotonic = false;
    validation.message = "Time values are not strictly increasing.";
    return;
end
validation.coefficientOfVariation = std(positive) / max(mean(positive), eps);
validation.isIrregular = validation.coefficientOfVariation > 1e-3 || validation.hasDuplicates;
validation.valid = validation.isMonotonic && ~validation.hasDuplicates;
estimatedFs = 1 / validation.medianStep;
if validation.isIrregular
    validation.message = "Time spacing is irregular; uniform-sampling analysis must be confirmed or stopped.";
else
    validation.message = "Time column validated as strictly increasing and regularly sampled.";
end
end

function name = make_display_name(data)
source = string(data.metadata.sourceFileName);
ipg = "";
if isfield(data.metadata, 'ipgSN'), ipg = string(data.metadata.ipgSN); end
if strlength(ipg) > 0
    name = source + " | IPG SN " + ipg;
else
    name = source;
end
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

function name = get_filename(filename)
[~, stem, extension] = fileparts(filename);
name = stem + extension;
end

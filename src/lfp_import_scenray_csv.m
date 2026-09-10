function data = lfp_import_scenray_csv(filename, options)
%LFP_IMPORT_SCENRAY_CSV Import one or more SceneRay CSV data blocks.
%   DATA = LFP_IMPORT_SCENRAY_CSV(FILENAME) reads repeated SceneRay blocks
%   containing metadata and Time Index / Voltage / Tag Code rows. Repeated
%   blocks become columns in DATA.signal (samples x channels).
%   DATA = LFP_IMPORT_SCENRAY_CSV(FILENAME, options) accepts SamplingRateHz,
%   Units, and an optional preloaded Cells matrix. Passing Cells avoids a
%   second disk read when the GUI has already inspected the file.
%
%   The source file is never modified. Non-numeric rows inside data blocks
%   are skipped and counted in DATA.metadata.skippedDataRows. The original
%   time indices and tag codes are retained in metadata.

arguments
    filename (1,1) string
    options.SamplingRateHz (1,1) double {mustBeFinite, mustBePositive} = 1000
    options.Units (1,1) string = "uV"
    options.Cells cell = {}
    options.ProgressCallback = []
    options.CancellationCheck = []
end

if ~isfile(filename)
    error('LFP:FileNotFound', 'Input CSV does not exist: %s', filename);
end

if isempty(options.Cells)
    [blocks, signals, timeIndices, tags, channelRows, blockStarts, blockEnds, ...
        headerRows, totalSkippedRows, sourceRowCount] = read_streamed(filename, ...
        options.ProgressCallback, options.CancellationCheck);
    importStrategy = "streamed_scenray";
else
    cells = options.Cells;
    if isempty(cells) || size(cells, 2) < 2
        error('LFP:EmptyCsv', 'CSV is empty or has no signal columns: %s', filename);
    end
    [blocks, signals, timeIndices, tags, channelRows, blockStarts, blockEnds, ...
        headerRows, totalSkippedRows] = read_preloaded_cells(cells, filename);
    sourceRowCount = size(cells, 1);
    importStrategy = "preloaded_cells";
end

nBlocks = numel(channelRows);
sampleCounts = cellfun(@numel, signals);
if any(sampleCounts ~= sampleCounts(1))
    error('LFP:InconsistentChannelLength', ...
        'SceneRay blocks have inconsistent sample counts: %s.', mat2str(sampleCounts));
end

signal = horzcat(signals{:});
timeIndex = horzcat(timeIndices{:});
tagCode = strings(sampleCounts(1), nBlocks);
for blockIndex = 1:nBlocks
    tagCode(:, blockIndex) = tags{blockIndex};
end

metadata = struct();
metadata.sourceFileName = string(get_filename(filename));
metadata.sourceFormat = "SceneRay CSV";
metadata.samplingRateHz = options.SamplingRateHz;
metadata.units = options.Units;
metadata.blockCount = nBlocks;
metadata.channelCount = nBlocks;
metadata.channelRows = channelRows;
metadata.blockStarts = blockStarts;
metadata.blockEnds = blockEnds;
metadata.headerRows = headerRows;
metadata.skippedDataRows = totalSkippedRows;
metadata.blocks = blocks;
metadata.timeIndex = timeIndex;
metadata.tagCode = tagCode;
metadata.channelRaw = reshape(string({blocks.channelRaw}), 1, []);
metadata.channelLabel = reshape(string({blocks.channelLabel}), 1, []);
metadata.channelNames = metadata.channelLabel;
metadata.contactIndices = {blocks.contactIndices};
metadata.electrodeGroup = reshape(string({blocks.electrodeGroup}), 1, []);
metadata.deviceType = string(blocks(1).deviceType);
metadata.ipgSN = string(blocks(1).ipgSN);
metadata.collectTimeSeconds = blocks(1).collectTimeSeconds;
metadata.gain = blocks(1).gain;
fileInfo = dir(filename);
metadata.fileSizeBytes = double(fileInfo.bytes);
metadata.sourceRowCount = sourceRowCount;
metadata.importStrategy = importStrategy;
metadata.estimatedMemoryBytes = 8 * (numel(signal) + size(signal, 1));

data = struct();
data.signal = signal;
data.fs = options.SamplingRateHz;
data.time = (0:size(signal, 1) - 1)' ./ data.fs;
data.channelLabels = metadata.channelLabel;
data.channelNames = metadata.channelLabel;
data.channelCount = nBlocks;
data.units = options.Units;
data.metadata = metadata;
data.artifacts = struct( ...
    'intervals_s', zeros(0, 2), ...
    'channelMask', false(size(signal)), ...
    'labels', strings(0, 1), ...
    'method', "not_detected");
data.processingHistory = struct( ...
    'operation', "import", ...
    'parameters', struct('samplingRateHz', options.SamplingRateHz, ...
        'units', options.Units, 'blockCount', nBlocks), ...
    'notes', "SceneRay CSV imported without modifying source data.");
notify(options.ProgressCallback, 1, "SceneRay CSV ready.");
end

function [blocks, signals, timeIndices, tags, channelRows, blockStarts, blockEnds, headerRows, totalSkippedRows] = read_preloaded_cells(cells, filename)
normalizedFirstColumn = strings(size(cells, 1), 1);
for rowIndex = 1:size(cells, 1)
    normalizedFirstColumn(rowIndex) = normalize_token(cells{rowIndex, 1});
end
channelRows = find(normalizedFirstColumn == "channel");
if isempty(channelRows)
    error('LFP:MissingChannelMetadata', 'Could not find any Channel metadata rows in %s.', filename);
end
nBlocks = numel(channelRows);
blockStarts = zeros(nBlocks, 1); blockEnds = zeros(nBlocks, 1); headerRows = zeros(nBlocks, 1);
for blockIndex = 1:nBlocks
    if blockIndex == 1, lowerBound = 1; else, lowerBound = channelRows(blockIndex - 1) + 1; end
    blockStarts(blockIndex) = find_block_start(normalizedFirstColumn, channelRows(blockIndex), lowerBound);
end
blocks = repmat(empty_block(), nBlocks, 1); signals = cell(nBlocks, 1); timeIndices = cell(nBlocks, 1); tags = cell(nBlocks, 1); totalSkippedRows = 0;
for blockIndex = 1:nBlocks
    blockStart = blockStarts(blockIndex);
    if blockIndex < nBlocks, blockEnd = blockStarts(blockIndex + 1) - 1; else, blockEnd = size(cells, 1); end
    blockEnds(blockIndex) = blockEnd;
    headerCandidates = find(normalizedFirstColumn(blockStart:blockEnd) == "timeindex") + blockStart - 1;
    if isempty(headerCandidates), error('LFP:MissingDataHeader', 'Could not find a Time Index header for Channel row %d.', channelRows(blockIndex)); end
    headerRow = headerCandidates(1); headerRows(blockIndex) = headerRow;
    if normalize_token(cells{headerRow, 2}) ~= "voltage", error('LFP:MissingVoltageColumn', 'Expected Voltage as the second data column in block %d.', blockIndex); end
    blocks(blockIndex) = parse_block_metadata(cells, normalizedFirstColumn, blockStart, headerRow);
    [timeIndices{blockIndex}, signals{blockIndex}, tags{blockIndex}, skippedRows] = parse_signal_rows(cells, headerRow + 1, blockEnd);
    totalSkippedRows = totalSkippedRows + skippedRows;
    if isempty(signals{blockIndex}), error('LFP:NoNumericSamples', 'No numeric samples found in SceneRay block %d.', blockIndex); end
end
end

function [blocks, signals, timeIndices, tags, channelRows, blockStarts, blockEnds, headerRows, totalSkippedRows, rowCount] = read_streamed(filename, progressCallback, cancellationCheck)
fileInfo = dir(filename);
fileId = fopen(filename, 'r');
if fileId < 0, error('LFP:CsvReadFailed', 'Could not open CSV: %s', filename); end
cleanup = onCleanup(@() fclose(fileId)); %#ok<NASGU>

blocks = repmat(empty_block(), 0, 1); signals = cell(0, 1); timeIndices = cell(0, 1); tags = cell(0, 1);
channelRows = zeros(0, 1); blockStarts = zeros(0, 1); blockEnds = zeros(0, 1); headerRows = zeros(0, 1);
pending = empty_block(); pendingStart = 1; currentBlock = 0; inData = false; rowCount = 0; totalSkippedRows = 0;
capacity = 0; sampleCount = 0; signalBuffer = zeros(0, 1); timeBuffer = zeros(0, 1); tagBuffer = strings(0, 1);

while true
    line = fgetl(fileId);
    if ~ischar(line), break; end
    rowCount = rowCount + 1;
    fields = lfp_parse_delimited_line(line, ',');
    if isempty(fields), continue; end
    key = normalize_token(fields{1});
    values = fields(2:end);
    switch key
        case "devicetype"
            if currentBlock > 0 && inData
                [signals, timeIndices, tags] = finalize_buffer(signals, timeIndices, tags, currentBlock, signalBuffer, timeBuffer, tagBuffer, sampleCount);
                inData = false; sampleCount = 0; capacity = 0;
            end
            pending = empty_block(); pending.deviceType = first_text(values); pendingStart = rowCount;
        case "ipgsn"
            if currentBlock > 0 && ~inData && headerRows(currentBlock) == 0
                blocks(currentBlock).ipgSN = first_text(values);
            else
                pending.ipgSN = first_text(values);
            end
        case "channel"
            if currentBlock > 0 && sampleCount > 0
                [signals, timeIndices, tags] = finalize_buffer(signals, timeIndices, tags, currentBlock, signalBuffer, timeBuffer, tagBuffer, sampleCount);
            end
            newBlockStart = pendingStart;
            if currentBlock > 0 && newBlockStart <= channelRows(currentBlock), newBlockStart = rowCount; end
            if currentBlock > 0, blockEnds(currentBlock, 1) = newBlockStart - 1; end
            currentBlock = currentBlock + 1;
            block = pending; block.channelRaw = first_text(values); block.channelLabel = replace(block.channelRaw, "~", "-");
            block.contactIndices = parse_contacts(block.channelRaw); block.electrodeGroup = infer_electrode_group(block.contactIndices);
            if strlength(block.channelLabel) == 0, block.channelLabel = "channel_" + string(rowCount); end
            blocks(currentBlock, 1) = block; channelRows(currentBlock, 1) = rowCount; blockStarts(currentBlock, 1) = min(newBlockStart, rowCount); headerRows(currentBlock, 1) = 0;
            signals{currentBlock, 1} = zeros(0, 1); timeIndices{currentBlock, 1} = zeros(0, 1); tags{currentBlock, 1} = strings(0, 1);
            pending = empty_block(); pendingStart = rowCount; inData = false; sampleCount = 0; capacity = 0;
        case "collecttime"
            if currentBlock > 0 && ~inData && headerRows(currentBlock) == 0, blocks(currentBlock).collectTimeSeconds = parse_collect_time(values); else, pending.collectTimeSeconds = parse_collect_time(values); end
        case "gain"
            if currentBlock > 0 && ~inData && headerRows(currentBlock) == 0, blocks(currentBlock).gain = first_number(values); else, pending.gain = first_number(values); end
        case "timeindex"
            if currentBlock == 0, error('LFP:MissingChannelMetadata', 'Time Index appeared before Channel metadata at row %d.', rowCount); end
            if numel(fields) < 2 || normalize_token(fields{2}) ~= "voltage", error('LFP:MissingVoltageColumn', 'Expected Voltage as the second data column in block %d.', currentBlock); end
            headerRows(currentBlock, 1) = rowCount; inData = true; capacity = 65536; sampleCount = 0;
            signalBuffer = zeros(capacity, 1); timeBuffer = zeros(capacity, 1); tagBuffer = strings(capacity, 1);
        otherwise
            if inData
                indexValue = to_number(fields{1}); signalValue = NaN; if numel(fields) >= 2, signalValue = to_number(fields{2}); end
                if isfinite(indexValue) && isfinite(signalValue)
                    sampleCount = sampleCount + 1;
                    if sampleCount > capacity
                        newCapacity = max(sampleCount, 2 * capacity); signalBuffer(newCapacity, 1) = 0; timeBuffer(newCapacity, 1) = 0; tagBuffer(newCapacity, 1) = ""; capacity = newCapacity;
                    end
                    timeBuffer(sampleCount) = indexValue; signalBuffer(sampleCount) = signalValue;
                    if numel(fields) >= 3, tagBuffer(sampleCount) = string_or_empty(fields{3}); end
                elseif any(~cellfun(@is_empty_cell, fields(1:min(2, numel(fields)))))
                    totalSkippedRows = totalSkippedRows + 1;
                end
            end
    end
    if rem(rowCount, 10000) == 0
        check_cancel(cancellationCheck);
        notify(progressCallback, min(0.95, ftell(fileId) / max(double(fileInfo.bytes), 1)), "Reading SceneRay CSV...");
    end
end
if currentBlock == 0, error('LFP:MissingChannelMetadata', 'Could not find any Channel metadata rows in %s.', filename); end
if sampleCount > 0, [signals, timeIndices, tags] = finalize_buffer(signals, timeIndices, tags, currentBlock, signalBuffer, timeBuffer, tagBuffer, sampleCount); end
blockEnds(currentBlock, 1) = rowCount;
for blockIndex = 1:currentBlock
    if headerRows(blockIndex) == 0, error('LFP:MissingDataHeader', 'Could not find a Time Index header for Channel row %d.', channelRows(blockIndex)); end
    if isempty(signals{blockIndex}), error('LFP:NoNumericSamples', 'No numeric samples found in SceneRay block %d.', blockIndex); end
end
check_cancel(cancellationCheck);
end

function [signals, timeIndices, tags] = finalize_buffer(signals, timeIndices, tags, blockIndex, signalBuffer, timeBuffer, tagBuffer, sampleCount)
signals{blockIndex, 1} = signalBuffer(1:sampleCount);
timeIndices{blockIndex, 1} = timeBuffer(1:sampleCount);
tags{blockIndex, 1} = tagBuffer(1:sampleCount);
end

function notify(callback, fraction, message)
if isempty(callback), return; end
callback(max(0, min(1, fraction)), string(message));
end

function check_cancel(callback)
if isempty(callback), return; end
callback();
end

function block = empty_block()
block = struct('deviceType', "", 'ipgSN', "", 'channelRaw', "", ...
    'channelLabel', "", 'contactIndices', zeros(1, 0), ...
    'electrodeGroup', "unknown", 'collectTimeSeconds', NaN, 'gain', NaN);
end

function blockStart = find_block_start(normalizedFirstColumn, channelRow, lowerBound)
candidate = find(normalizedFirstColumn(lowerBound:channelRow) == "devicetype", 1, 'last') + lowerBound - 1;
if isempty(candidate)
    blockStart = channelRow;
else
    blockStart = candidate;
end
end

function block = parse_block_metadata(cells, normalizedFirstColumn, blockStart, headerRow)
block = empty_block();
for rowIndex = blockStart:headerRow - 1
    key = normalizedFirstColumn(rowIndex);
    values = cells(rowIndex, 2:end);
    switch key
        case "devicetype"
            block.deviceType = first_text(values);
        case "ipgsn"
            block.ipgSN = first_text(values);
        case "channel"
            block.channelRaw = first_text(values);
            block.channelLabel = replace(block.channelRaw, "~", "-");
            block.contactIndices = parse_contacts(block.channelRaw);
            block.electrodeGroup = infer_electrode_group(block.contactIndices);
        case "collecttime"
            block.collectTimeSeconds = parse_collect_time(values);
        case "gain"
            block.gain = first_number(values);
    end
end
if strlength(block.channelLabel) == 0
    block.channelLabel = "channel_" + string(headerRow);
end
end

function [timeIndex, signal, tags, skippedRows] = parse_signal_rows(cells, firstRow, lastRow)
nRows = max(0, lastRow - firstRow + 1);
timeIndex = zeros(nRows, 1);
signal = zeros(nRows, 1);
tags = strings(nRows, 1);
skippedRows = 0;
keptRows = 0;
for rowIndex = firstRow:lastRow
    indexValue = to_number(cells{rowIndex, 1});
    signalValue = to_number(cells{rowIndex, 2});
    if ~isfinite(indexValue) || ~isfinite(signalValue)
        if any(~cellfun(@is_empty_cell, cells(rowIndex, 1:min(2, size(cells, 2)))))
            skippedRows = skippedRows + 1;
        end
        continue;
    end
    keptRows = keptRows + 1;
    timeIndex(keptRows, 1) = indexValue;
    signal(keptRows, 1) = signalValue;
    if size(cells, 2) >= 3
        tags(keptRows, 1) = string_or_empty(cells{rowIndex, 3});
    else
        tags(keptRows, 1) = "";
    end
end
timeIndex = timeIndex(1:keptRows);
signal = signal(1:keptRows);
tags = tags(1:keptRows);
end

function value = normalize_token(raw)
value = lower(string_or_empty(raw));
value = erase(value, [" ", "_", "-", char(9)]);
end

function value = first_text(values)
value = "";
for index = 1:numel(values)
    candidate = string_or_empty(values{index});
    if strlength(strtrim(candidate)) > 0
        value = strtrim(candidate);
        return;
    end
end
end

function value = first_number(values)
value = NaN;
for index = 1:numel(values)
    candidate = to_number(values{index});
    if isfinite(candidate)
        value = candidate;
        return;
    end
end
end

function value = parse_collect_time(values)
value = 0;
found = false;
for index = 1:numel(values)
    token = lower(strtrim(string_or_empty(values{index})));
    if strlength(token) == 0
        continue;
    end
    amount = str2double(extractBefore(token, strlength(token)));
    suffix = extractAfter(token, strlength(token) - 1);
    if ~isfinite(amount)
        continue;
    end
    switch suffix
        case "h"
            value = value + amount * 3600;
            found = true;
        case "m"
            value = value + amount * 60;
            found = true;
        case "s"
            value = value + amount;
            found = true;
    end
end
if ~found
    value = NaN;
end
end

function contacts = parse_contacts(label)
tokens = regexp(char(label), '\d+', 'match');
contacts = zeros(1, numel(tokens));
for index = 1:numel(tokens)
    contacts(index) = str2double(tokens{index});
end
end

function group = infer_electrode_group(contacts)
if isempty(contacts)
    group = "unknown";
elseif all(contacts >= 0 & contacts <= 3)
    group = "contacts_0_3";
elseif all(contacts >= 4 & contacts <= 7)
    group = "contacts_4_7";
else
    group = "mixed_or_extended";
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

function value = is_empty_cell(raw)
value = isempty(raw) || (isstring(raw) && (ismissing(raw) || strlength(raw) == 0));
end

function name = get_filename(filename)
[~, name, extension] = fileparts(filename);
name = name + extension;
end

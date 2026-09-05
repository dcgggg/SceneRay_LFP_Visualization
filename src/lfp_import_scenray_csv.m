function data = lfp_import_scenray_csv(filename, options)
%LFP_IMPORT_SCENRAY_CSV Import one or more SceneRay CSV data blocks.
%   DATA = LFP_IMPORT_SCENRAY_CSV(FILENAME) reads repeated SceneRay blocks
%   containing metadata and Time Index / Voltage / Tag Code rows. Repeated
%   blocks become columns in DATA.signal (samples x channels).
%   DATA = LFP_IMPORT_SCENRAY_CSV(FILENAME, options) accepts SamplingRateHz
%   and Units fields. The confirmed defaults are 1000 Hz and microvolts.
%
%   The source file is never modified. Non-numeric rows inside data blocks
%   are skipped and counted in DATA.metadata.skippedDataRows. The original
%   time indices and tag codes are retained in metadata.

arguments
    filename (1,1) string
    options.SamplingRateHz (1,1) double {mustBeFinite, mustBePositive} = 1000
    options.Units (1,1) string = "uV"
end

if ~isfile(filename)
    error('LFP:FileNotFound', 'Input CSV does not exist: %s', filename);
end

try
    cells = readcell(filename, 'FileType', 'text', 'Delimiter', ',');
catch exception
    error('LFP:CsvReadFailed', 'Could not read CSV %s: %s', filename, exception.message);
end

if isempty(cells) || size(cells, 2) < 2
    error('LFP:EmptyCsv', 'CSV is empty or has no signal columns: %s', filename);
end

normalizedFirstColumn = strings(size(cells, 1), 1);
for rowIndex = 1:size(cells, 1)
    normalizedFirstColumn(rowIndex) = normalize_token(cells{rowIndex, 1});
end

channelRows = find(normalizedFirstColumn == "channel");
if isempty(channelRows)
    error('LFP:MissingChannelMetadata', 'Could not find any Channel metadata rows in %s.', filename);
end

nBlocks = numel(channelRows);
blockStarts = zeros(nBlocks, 1);
blockEnds = zeros(nBlocks, 1);
headerRows = zeros(nBlocks, 1);
for blockIndex = 1:nBlocks
    if blockIndex == 1
        lowerBound = 1;
    else
        lowerBound = channelRows(blockIndex - 1) + 1;
    end
    blockStarts(blockIndex) = find_block_start(normalizedFirstColumn, channelRows(blockIndex), lowerBound);
end
blocks = repmat(empty_block(), nBlocks, 1);
signals = cell(nBlocks, 1);
timeIndices = cell(nBlocks, 1);
tags = cell(nBlocks, 1);
totalSkippedRows = 0;

for blockIndex = 1:nBlocks
    blockStart = blockStarts(blockIndex);
    if blockIndex < nBlocks
        blockEnd = blockStarts(blockIndex + 1) - 1;
    else
        blockEnd = size(cells, 1);
    end
    blockEnds(blockIndex) = blockEnd;
    headerCandidates = find(normalizedFirstColumn(blockStart:blockEnd) == "timeindex") + blockStart - 1;
    if isempty(headerCandidates)
        error('LFP:MissingDataHeader', ...
            'Could not find a Time Index header for Channel row %d.', channelRows(blockIndex));
    end
    headerRow = headerCandidates(1);
    headerRows(blockIndex) = headerRow;
    if normalize_token(cells{headerRow, 2}) ~= "voltage"
        error('LFP:MissingVoltageColumn', ...
            'Expected Voltage as the second data column in block %d.', blockIndex);
    end

    blocks(blockIndex) = parse_block_metadata(cells, normalizedFirstColumn, blockStart, headerRow);
    firstRowAfterHeader = headerRow + 1;
    lastRowInBlock = blockEnd;
    [timeIndices{blockIndex}, signals{blockIndex}, tags{blockIndex}, skippedRows] = ...
        parse_signal_rows(cells, firstRowAfterHeader, lastRowInBlock);
    totalSkippedRows = totalSkippedRows + skippedRows;
    if isempty(signals{blockIndex})
        error('LFP:NoNumericSamples', 'No numeric samples found in SceneRay block %d.', blockIndex);
    end
end

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
metadata.contactIndices = {blocks.contactIndices};
metadata.electrodeGroup = reshape(string({blocks.electrodeGroup}), 1, []);
metadata.deviceType = string(blocks(1).deviceType);
metadata.ipgSN = string(blocks(1).ipgSN);
metadata.collectTimeSeconds = blocks(1).collectTimeSeconds;
metadata.gain = blocks(1).gain;

data = struct();
data.signal = signal;
data.fs = options.SamplingRateHz;
data.time = (0:size(signal, 1) - 1)' ./ data.fs;
data.channelLabels = metadata.channelLabel;
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
timeIndex = zeros(0, 1);
signal = zeros(0, 1);
tags = strings(0, 1);
skippedRows = 0;
for rowIndex = firstRow:lastRow
    indexValue = to_number(cells{rowIndex, 1});
    signalValue = to_number(cells{rowIndex, 2});
    if ~isfinite(indexValue) || ~isfinite(signalValue)
        if any(~cellfun(@is_empty_cell, cells(rowIndex, 1:min(2, size(cells, 2)))))
            skippedRows = skippedRows + 1;
        end
        continue;
    end
    timeIndex(end + 1, 1) = indexValue; %#ok<AGROW>
    signal(end + 1, 1) = signalValue; %#ok<AGROW>
    if size(cells, 2) >= 3
        tags(end + 1, 1) = string_or_empty(cells{rowIndex, 3}); %#ok<AGROW>
    else
        tags(end + 1, 1) = ""; %#ok<AGROW>
    end
end
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

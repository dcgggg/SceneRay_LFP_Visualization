function handles = plotArtifactComparison(data, cleanData, artifactResult, plotCfg)
%PLOTARTIFACTCOMPARISON Plot raw/clean traces and artifact diagnostics.
%   HANDLES = PLOTARTIFACTCOMPARISON(DATA, CLEANDATA, ARTIFACTRESULT, CFG)
%   creates an interactive MATLAB figure. Each selected channel is shown as
%   two vertically adjacent panels (raw, then NaN-marked clean data) in one
%   column. Raw samples are never modified; artifact intervals are shaded
%   only on the raw panel and the display signal uses NaN values.

arguments
    data (1,1) struct
    cleanData (1,1) struct
    artifactResult (1,1) struct
    plotCfg (1,1) struct
end

signal = double(data.signal);
[nSamples, nChannels] = size(signal);
if ~isfield(cleanData, 'cleanedSignal')
    error('LFP:MissingCleanSignal', 'cleanData.cleanedSignal is required.');
end
cleanedSignal = double(cleanData.cleanedSignal);
if ~isequal(size(cleanedSignal), size(signal))
    error('LFP:InvalidCleanSignal', 'cleanedSignal must match data.signal dimensions.');
end
fs = double(data.fs);
channels = get_field(plotCfg, 'channelIndex', 1:nChannels);
if isempty(channels), channels = 1:nChannels; end
channels = unique(channels(:)');
channels = channels(channels >= 1 & channels <= nChannels);
if isempty(channels), error('LFP:InvalidChannelIndex', 'No valid channels selected.'); end

time = (0:nSamples-1)' / fs;
maxSeconds = get_field(plotCfg, 'maxPlotSeconds', Inf);
sampleLimit = min(nSamples, max(1, round(maxSeconds * fs)));
timePlot = time(1:sampleLimit);
parent = get_field(plotCfg, 'parent', []);
visible = char(get_field(plotCfg, 'visible', "on"));
if isempty(parent)
    figureHandle = figure('Visible', visible, 'Color', 'w', ...
        'Name', 'Artifact comparison', 'NumberTitle', 'off');
else
    figureHandle = ancestor(parent, 'figure');
    if isempty(figureHandle)
        figureHandle = figure('Visible', visible, 'Color', 'w', ...
            'Name', 'Artifact comparison', 'NumberTitle', 'off');
    end
end

% Two trace panels per channel plus four compact diagnostic panels.
nRows = 2 * numel(channels) + 4;
layout = tiledlayout(figureHandle, nRows, 1, 'TileSpacing', 'loose', 'Padding', 'loose');
handles = struct('figure', figureHandle, 'layout', layout, ...
    'axes', gobjects(nRows, 1), 'rawLines', gobjects(numel(channels), 1), ...
    'cleanLines', gobjects(numel(channels), 1), 'patches', gobjects(0), ...
    'histograms', gobjects(0), 'typeBars', gobjects(0));

globalMask = false(nSamples, 1);
if isfield(artifactResult, 'globalMask') && numel(artifactResult.globalMask) == nSamples
    globalMask = logical(artifactResult.globalMask(:));
end
channelMask = false(nSamples, nChannels);
if isfield(artifactResult, 'channelMask') && isequal(size(artifactResult.channelMask), size(signal))
    channelMask = logical(artifactResult.channelMask);
end

for index = 1:numel(channels)
    channel = channels(index);
    label = channel_label(data, channel);
    raw = signal(1:sampleLimit, channel);
    clean = cleanedSignal(1:sampleLimit, channel);
    rawMask = channelMask(1:sampleLimit, channel) | globalMask(1:sampleLimit);

    rawAxis = nexttile(layout);
    handles.axes(2*index-1) = rawAxis;
    handles.rawLines(index) = plot(rawAxis, timePlot, raw, 'k', ...
        'LineWidth', 0.8, 'DisplayName', 'Raw');
    hold(rawAxis, 'on');
    limits = finite_limits(raw);
    if all(isfinite(limits)) && limits(1) < limits(2)
        ylim(rawAxis, limits);
    end
    intervals = logical_to_intervals(rawMask, fs);
    yLimits = ylim(rawAxis);
    for intervalIndex = 1:size(intervals, 1)
        handles.patches(end+1, 1) = patch(rawAxis, ...
            [intervals(intervalIndex,1) intervals(intervalIndex,2) ...
             intervals(intervalIndex,2) intervals(intervalIndex,1)], ...
            [yLimits(1) yLimits(1) yLimits(2) yLimits(2)], ...
            [1 0.6 0.6], 'FaceAlpha', 0.35, 'EdgeColor', 'none', ...
            'DisplayName', 'Artifact interval'); %#ok<AGROW>
    end
    hold(rawAxis, 'off');
    xlabel(rawAxis, 'Time (s)'); ylabel(rawAxis, string(data.units));
    title(rawAxis, sprintf('Raw | %s', label), 'Interpreter', 'none');
    grid(rawAxis, 'on');
    if index == 1
        legend(rawAxis, 'Location', 'best');
    end

    cleanAxis = nexttile(layout);
    handles.axes(2*index) = cleanAxis;
    handles.cleanLines(index) = plot(cleanAxis, timePlot, clean, 'b', ...
        'LineWidth', 0.8, 'DisplayName', 'Clean display (NaN excluded)');
    if all(isfinite(limits)) && limits(1) < limits(2)
        ylim(cleanAxis, limits); % same scale as the corresponding raw panel
    end
    xlabel(cleanAxis, 'Time (s)'); ylabel(cleanAxis, string(data.units));
    title(cleanAxis, sprintf('Clean/display | %s (artifact samples = NaN)', label), ...
        'Interpreter', 'none');
    grid(cleanAxis, 'on');
    if index == 1
        legend(cleanAxis, 'Location', 'best');
    end
end

% Diagnostics use all selected channels and therefore do not repeat analysis.
rawValues = signal(:, channels); rawValues = rawValues(isfinite(rawValues));
cleanValues = cleanedSignal(:, channels); cleanValues = cleanValues(isfinite(cleanValues));
allValues = [rawValues; cleanValues];
histAxis = nexttile(layout); handles.axes(2*numel(channels)+1) = histAxis;
if numel(allValues) >= 2 && min(allValues) < max(allValues)
    edges = linspace(min(allValues), max(allValues), 51);
    handles.histograms(1) = histogram(histAxis, rawValues, edges, ...
        'Normalization', 'probability', 'DisplayStyle', 'stairs', ...
        'LineWidth', 1.2, 'EdgeColor', [0.1 0.1 0.1], 'DisplayName', 'Raw');
    hold(histAxis, 'on');
    if ~isempty(cleanValues)
        handles.histograms(2) = histogram(histAxis, cleanValues, edges, ...
            'Normalization', 'probability', 'DisplayStyle', 'stairs', ...
            'LineWidth', 1.2, 'EdgeColor', [0.0 0.3 0.8], ...
            'DisplayName', 'Clean finite samples');
    end
    hold(histAxis, 'off');
else
    text(histAxis, 0.1, 0.5, 'Insufficient finite samples for amplitude histogram.');
end
xlabel(histAxis, string(data.units)); ylabel(histAxis, 'Probability');
title(histAxis, 'Amplitude distributions before/after masking');
legend(histAxis, 'Location', 'best'); grid(histAxis, 'on');

fractionAxis = nexttile(layout); handles.axes(2*numel(channels)+2) = fractionAxis;
channelPercentage = get_summary_field(artifactResult, ...
    'channelArtifactPercentage', zeros(1, nChannels));
bar(fractionAxis, channels, channelPercentage(channels));
xlabel(fractionAxis, 'Channel'); ylabel(fractionAxis, 'Artifact samples (%)');
title(fractionAxis, 'Artifact fraction by channel'); grid(fractionAxis, 'on');

typeAxis = nexttile(layout); handles.axes(2*numel(channels)+3) = typeAxis;
[typeNames, typeCounts, typeDurations] = type_summary(artifactResult);
if isempty(typeNames)
    text(typeAxis, 0.1, 0.5, 'No artifact events.'); axis(typeAxis, 'off');
else
    yyaxis(typeAxis, 'left');
    handles.typeBars = bar(typeAxis, categorical(typeNames), typeCounts);
    ylabel(typeAxis, 'Event count');
    yyaxis(typeAxis, 'right');
    plot(typeAxis, categorical(typeNames), typeDurations, 'o-', 'LineWidth', 1.2);
    ylabel(typeAxis, 'Total duration (s)');
    title(typeAxis, 'Artifact types and duration'); grid(typeAxis, 'on');
end

summaryAxis = nexttile(layout); handles.axes(2*numel(channels)+4) = summaryAxis;
retained = get_field(artifactResult, 'retainedDuration', NaN);
rejected = get_field(artifactResult, 'rejectedDuration', NaN);
rejectedPercentage = get_field(artifactResult, 'rejectedPercentage', NaN);
bar(summaryAxis, categorical({'Retained'; 'Rejected'}), [retained; rejected]);
ylabel(summaryAxis, 'Duration (s)');
title(summaryAxis, sprintf('Data retention | rejected %.2f%%', rejectedPercentage));
grid(summaryAxis, 'on');

displayName = data_display_name(data);
if strlength(displayName) > 0
    sgtitle(figureHandle, displayName, 'Interpreter', 'none');
end
lfp_apply_plot_config(figureHandle, plotCfg, layout);
end

function intervals = logical_to_intervals(mask, fs)
starts = find(diff([false; mask(:); false]) == 1);
ends = find(diff([false; mask(:); false]) == -1) - 1;
intervals = [(starts-1)/fs, ends/fs];
end

function limits = finite_limits(values)
values = values(isfinite(values));
if isempty(values)
    limits = [NaN NaN];
else
    limits = [min(values) max(values)];
    if limits(1) == limits(2)
        delta = max(abs(limits(1))*0.05, 1);
        limits = limits + [-delta delta];
    end
end
end

function label = channel_label(data, channel)
if isfield(data, 'channelLabels') && numel(data.channelLabels) >= channel
    label = string(data.channelLabels(channel));
else
    label = "channel_" + string(channel);
end
end

function name = data_display_name(data)
name = "";
if isfield(data, 'metadata') && isfield(data.metadata, 'displayName') && ...
        ~isempty(data.metadata.displayName)
    name = string(data.metadata.displayName);
    return;
end
source = ""; ipg = "";
if isfield(data, 'metadata')
    if isfield(data.metadata, 'sourceFileName'), source = string(data.metadata.sourceFileName); end
    if isfield(data.metadata, 'ipgSN'), ipg = string(data.metadata.ipgSN); end
end
if strlength(source) > 0 && strlength(ipg) > 0
    name = source + " | IPG SN " + ipg;
elseif strlength(source) > 0
    name = source;
elseif strlength(ipg) > 0
    name = "IPG SN " + ipg;
end
end

function [names, counts, durations] = type_summary(artifactResult)
names = strings(0,1); counts = zeros(0,1); durations = zeros(0,1);
if ~isfield(artifactResult, 'summary') || ~isfield(artifactResult.summary, 'countsByType')
    return;
end
fields = fieldnames(artifactResult.summary.countsByType);
names = string(fields(:)); counts = zeros(numel(fields), 1); durations = counts;
for index = 1:numel(fields)
    names(index) = string(fields{index});
    counts(index) = artifactResult.summary.countsByType.(fields{index});
    if isfield(artifactResult.summary, 'durationByTypeSeconds') && ...
            isfield(artifactResult.summary.durationByTypeSeconds, fields{index})
        durations(index) = artifactResult.summary.durationByTypeSeconds.(fields{index});
    end
end
end

function value = get_field(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = defaultValue; end
end

function value = get_summary_field(artifactResult, name, defaultValue)
value = defaultValue;
if isfield(artifactResult, 'summary') && isfield(artifactResult.summary, name) && ...
        ~isempty(artifactResult.summary.(name))
    value = artifactResult.summary.(name);
end
end

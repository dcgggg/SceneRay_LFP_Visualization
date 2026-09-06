function handles = plotArtifactComparison(data, cleanData, artifactResult, plotCfg)
%PLOTARTIFACTCOMPARISON Plot artifact overlays and before/after diagnostics.
%   HANDLES = PLOTARTIFACTCOMPARISON(DATA, CLEANDATA, ARTIFACTRESULT, CFG)
%   shows raw signal, NaN-marked signal, a common-scale zoom, amplitude
%   distributions, and per-channel artifact percentages. It never creates
%   a reconstructed continuous trace.

arguments
    data (1,1) struct
    cleanData (1,1) struct
    artifactResult (1,1) struct
    plotCfg (1,1) struct
end

signal = double(data.signal);
[nSamples, nChannels] = size(signal);
fs = double(data.fs);
channels = get_field(plotCfg, 'channelIndex', 1:nChannels);
if isempty(channels), channels = 1:nChannels; end
channels = channels(channels >= 1 & channels <= nChannels);
if isempty(channels), error('LFP:InvalidChannelIndex', 'No valid channels selected.'); end
time = (0:nSamples-1)' / fs;
maxSeconds = get_field(plotCfg, 'maxPlotSeconds', Inf);
sampleLimit = min(nSamples, max(1, round(maxSeconds*fs)));
parent = get_field(plotCfg, 'parent', []);
visible = char(get_field(plotCfg, 'visible', "on"));
if isempty(parent)
    figureHandle = figure('Visible', visible, 'Color', 'w', 'Name', 'Artifact comparison');
else
    figureHandle = ancestor(parent, 'figure');
    if isempty(figureHandle), figureHandle = figure('Visible', visible, 'Color', 'w'); end
end
layout = tiledlayout(figureHandle, 3, 2, 'TileSpacing', 'compact');
handles = struct('figure', figureHandle, 'layout', layout, 'axes', gobjects(6,1), ...
    'rawLines', gobjects(0), 'cleanLines', gobjects(0), 'patches', gobjects(0), ...
    'histograms', gobjects(0), 'typeBars', gobjects(0));

handles.axes(1) = nexttile(layout);
handles.rawLines = plot(handles.axes(1), time(1:sampleLimit), signal(1:sampleLimit, channels), 'k');
hold(handles.axes(1), 'on');
mask = artifactResult.globalMask(1:sampleLimit);
ylimValue = ylim(handles.axes(1));
intervals = logical_to_intervals(mask, fs);
for index = 1:size(intervals,1)
    patch(handles.axes(1), [intervals(index,1) intervals(index,2) intervals(index,2) intervals(index,1)], ...
        [ylimValue(1) ylimValue(1) ylimValue(2) ylimValue(2)], [1 0.6 0.6], ...
        'FaceAlpha', 0.35, 'EdgeColor', 'none');
end
hold(handles.axes(1), 'off');
xlabel(handles.axes(1), 'Time (s)'); ylabel(handles.axes(1), string(data.units));
title(handles.axes(1), 'Raw signal with artifact intervals'); grid(handles.axes(1), 'on');

handles.axes(2) = nexttile(layout);
handles.cleanLines = plot(handles.axes(2), time(1:sampleLimit), cleanData.cleanedSignal(1:sampleLimit, channels));
xlabel(handles.axes(2), 'Time (s)'); ylabel(handles.axes(2), string(data.units));
title(handles.axes(2), 'Analysis/display signal (artifact samples are NaN)'); grid(handles.axes(2), 'on');

handles.axes(3) = nexttile(layout);
zoomSamples = find(mask, 1, 'first');
if isempty(zoomSamples), zoomSamples = min(sampleLimit, round(0.5*fs)); end
zoomHalf = max(1, round(1*fs));
zoomRange = max(1, zoomSamples-zoomHalf):min(sampleLimit, zoomSamples+zoomHalf);
rawZoom = signal(zoomRange, channels);
cleanZoom = cleanData.cleanedSignal(zoomRange, channels);
plot(handles.axes(3), time(zoomRange), rawZoom, 'k', 'LineWidth', 0.9); hold(handles.axes(3), 'on');
plot(handles.axes(3), time(zoomRange), cleanZoom, 'b', 'LineWidth', 0.9); hold(handles.axes(3), 'off');
commonY = [min(rawZoom(:), [], 'omitnan'), max(rawZoom(:), [], 'omitnan')];
if all(isfinite(commonY)) && commonY(1) < commonY(2), ylim(handles.axes(3), commonY); end
xlabel(handles.axes(3), 'Time (s)'); ylabel(handles.axes(3), string(data.units));
title(handles.axes(3), 'Local zoom (same time and y-axis scale)'); grid(handles.axes(3), 'on');

handles.axes(4) = nexttile(layout);
rawValues = signal(:, channels); rawValues = rawValues(isfinite(rawValues));
cleanValues = cleanData.cleanedSignal(:, channels); cleanValues = cleanValues(isfinite(cleanValues));
allValues = [rawValues; cleanValues];
if numel(allValues) >= 2 && min(allValues) < max(allValues)
    edges = linspace(min(allValues), max(allValues), 51);
    handles.histograms(1) = histogram(handles.axes(4), rawValues, edges, ...
        'Normalization', 'probability', 'DisplayStyle', 'stairs', ...
        'LineWidth', 1.2, 'EdgeColor', [0.1 0.1 0.1], 'DisplayName', 'Raw');
    hold(handles.axes(4), 'on');
    if ~isempty(cleanValues)
        handles.histograms(2) = histogram(handles.axes(4), cleanValues, edges, ...
            'Normalization', 'probability', 'DisplayStyle', 'stairs', ...
            'LineWidth', 1.2, 'EdgeColor', [0.0 0.3 0.8], 'DisplayName', 'After mask (finite samples)');
    end
    hold(handles.axes(4), 'off');
else
    text(handles.axes(4), 0.1, 0.5, 'Insufficient finite samples for amplitude histogram.');
end
xlabel(handles.axes(4), string(data.units)); ylabel(handles.axes(4), 'Probability');
title(handles.axes(4), 'Amplitude distributions before/after masking');
legend(handles.axes(4), 'Location', 'best'); grid(handles.axes(4), 'on');

handles.axes(5) = nexttile(layout);
channelPercentage = get_summary_field(artifactResult, 'channelArtifactPercentage', zeros(1, nChannels));
bar(handles.axes(5), 1:nChannels, channelPercentage);
xlabel(handles.axes(5), 'Channel'); ylabel(handles.axes(5), 'Artifact samples (%)');
title(handles.axes(5), 'Artifact fraction by channel'); grid(handles.axes(5), 'on');

handles.axes(6) = nexttile(layout);
typeNames = strings(0, 1); typeCounts = zeros(0, 1); typeDurations = zeros(0, 1);
if isfield(artifactResult, 'summary') && isfield(artifactResult.summary, 'countsByType')
    names = fieldnames(artifactResult.summary.countsByType);
    typeNames = string(names(:));
    typeCounts = zeros(numel(names), 1); typeDurations = zeros(numel(names), 1);
    for index = 1:numel(names)
        typeCounts(index) = artifactResult.summary.countsByType.(names{index});
        if isfield(artifactResult.summary, 'durationByTypeSeconds') && ...
                isfield(artifactResult.summary.durationByTypeSeconds, names{index})
            typeDurations(index) = artifactResult.summary.durationByTypeSeconds.(names{index});
        end
    end
end
if isempty(typeNames)
    text(handles.axes(6), 0.1, 0.5, 'No artifact events.'); axis(handles.axes(6), 'off');
else
    yyaxis(handles.axes(6), 'left');
    handles.typeBars = bar(handles.axes(6), categorical(typeNames), typeCounts);
    ylabel(handles.axes(6), 'Event count');
    yyaxis(handles.axes(6), 'right');
    plot(handles.axes(6), categorical(typeNames), typeDurations, 'o-', 'LineWidth', 1.2);
    ylabel(handles.axes(6), 'Total duration (s)');
    title(handles.axes(6), 'Artifact types and duration'); grid(handles.axes(6), 'on');
end
end

function intervals = logical_to_intervals(mask, fs)
starts = find(diff([false; mask; false]) == 1);
ends = find(diff([false; mask; false]) == -1) - 1;
intervals = [(starts-1)/fs, ends/fs];
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

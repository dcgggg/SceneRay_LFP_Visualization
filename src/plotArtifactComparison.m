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
layout = tiledlayout(figureHandle, 4, 1, 'TileSpacing', 'compact');
handles = struct('figure', figureHandle, 'layout', layout, 'axes', gobjects(4,1), ...
    'rawLines', gobjects(0), 'cleanLines', gobjects(0), 'patches', gobjects(0));

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
hold(handles.axes(4), 'on');
for channel = channels
    histogram(handles.axes(4), signal(:,channel), 'Normalization', 'probability', ...
        'DisplayStyle', 'stairs', 'LineWidth', 1.0);
end
hold(handles.axes(4), 'off'); xlabel(handles.axes(4), string(data.units)); ylabel('Probability');
title(handles.axes(4), 'Raw amplitude distributions'); grid(handles.axes(4), 'on');
end

function intervals = logical_to_intervals(mask, fs)
starts = find(diff([false; mask; false]) == 1);
ends = find(diff([false; mask; false]) == -1) - 1;
intervals = [(starts-1)/fs, ends/fs];
end

function value = get_field(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = defaultValue; end
end

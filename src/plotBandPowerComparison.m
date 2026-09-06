function handles = plotBandPowerComparison(beforeBand, afterBand, plotCfg)
%PLOTBANDPOWERCOMPARISON Compare two band-power tables on common scales.

arguments
    beforeBand (1,1) struct
    afterBand (1,1) struct
    plotCfg (1,1) struct
end
if ~isfield(beforeBand, 'table') || ~isfield(afterBand, 'table')
    error('LFP:InvalidBandResult', 'Both inputs need a bandPower.table.');
end
before = beforeBand.table; after = afterBand.table;
names = unique(before.band, 'stable');
channels = unique(before.channelIndex, 'stable');
valuesBefore = NaN(numel(channels), numel(names));
valuesAfter = valuesBefore;
for channel = 1:numel(channels)
    for band = 1:numel(names)
        rowBefore = before.channelIndex == channels(channel) & before.band == names(band);
        rowAfter = after.channelIndex == channels(channel) & after.band == names(band);
        if any(rowBefore), valuesBefore(channel,band) = before.totalPower(find(rowBefore,1)); end
        if any(rowAfter), valuesAfter(channel,band) = after.totalPower(find(rowAfter,1)); end
    end
end
visible = char(get_field(plotCfg, 'visible', "on"));
figureHandle = figure('Visible', visible, 'Color', 'w', 'Name', 'Band-power artifact comparison');
layout = tiledlayout(1, 2, 'TileSpacing', 'compact');
handles = struct('figure', figureHandle, 'layout', layout, 'axes', gobjects(1,2));
handles.axes(1) = nexttile(layout); bar(handles.axes(1), categorical(names), valuesBefore'); title(handles.axes(1), 'Before exclusion'); ylabel(handles.axes(1), 'Total power'); grid(handles.axes(1), 'on');
handles.axes(2) = nexttile(layout); bar(handles.axes(2), categorical(names), valuesAfter'); title(handles.axes(2), 'After exclusion'); ylabel(handles.axes(2), 'Total power'); grid(handles.axes(2), 'on');
end

function value = get_field(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = defaultValue; end
end

function handles = plotPsdComparison(beforePsd, afterPsd, plotCfg)
%PLOTPSDCOMPARISON Compare PSDs before and after artifact-window exclusion.
%   BEFOREPSD and AFTERPSD are spectrum structs returned by lfp_compute_psd.
%   Both curves use the same frequency limits and linear-frequency/log-power
%   convention, so exclusion effects are not hidden by rescaling.

arguments
    beforePsd (1,1) struct
    afterPsd (1,1) struct
    plotCfg (1,1) struct
end
if ~isfield(beforePsd, 'frequencyHz') || ~isfield(afterPsd, 'frequencyHz')
    error('LFP:InvalidSpectrum', 'Both PSD results need frequencyHz and psd fields.');
end
channels = get_field(plotCfg, 'channelIndex', 1:min(size(beforePsd.psd,2), size(afterPsd.psd,2)));
if isempty(channels), channels = 1:min(size(beforePsd.psd,2), size(afterPsd.psd,2)); end
visible = char(get_field(plotCfg, 'visible', "on"));
figureHandle = figure('Visible', visible, 'Color', 'w', 'Name', 'PSD artifact comparison');
layout = tiledlayout(figureHandle, numel(channels), 1, 'TileSpacing', 'compact');
handles = struct('figure', figureHandle, 'layout', layout, 'axes', gobjects(numel(channels),1));
for index = 1:numel(channels)
    channel = channels(index);
    handles.axes(index) = nexttile(layout);
    plot(handles.axes(index), beforePsd.frequencyHz, 10*log10(max(beforePsd.psd(:,channel), realmin)), 'k', 'DisplayName', 'Before exclusion'); hold(handles.axes(index), 'on');
    plot(handles.axes(index), afterPsd.frequencyHz, 10*log10(max(afterPsd.psd(:,channel), realmin)), 'b', 'DisplayName', 'After exclusion'); hold(handles.axes(index), 'off');
    xlabel(handles.axes(index), 'Frequency (Hz)'); ylabel(handles.axes(index), 'Power (dB)');
    title(handles.axes(index), sprintf('Channel %d', channel)); legend(handles.axes(index), 'Location', 'best'); grid(handles.axes(index), 'on');
end
end

function value = get_field(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = defaultValue; end
end

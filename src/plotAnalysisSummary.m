function handles = plotAnalysisSummary(artifactResult, psdResult, modelResult, bandResult, plotCfg)
%PLOTANALYSISSUMMARY Plot multi-channel quality, spectra, peaks and bands.
%   This function consumes already computed structures and returns figure and
%   axes handles for later GUI integration.

arguments
    artifactResult (1,1) struct
    psdResult (1,1) struct
    modelResult struct
    bandResult (1,1) struct
    plotCfg (1,1) struct
end
visible = char(get_field(plotCfg, 'visible', "on"));
figureHandle = figure('Visible', visible, 'Color', 'w', 'Name', 'LFP analysis summary');
layout = tiledlayout(figureHandle, 2, 2, 'TileSpacing', 'compact');
handles = struct('figure', figureHandle, 'layout', layout, 'axes', gobjects(4,1));

handles.axes(1) = nexttile(layout);
plot(handles.axes(1), psdResult.frequencyHz, 10*log10(max(psdResult.psd, realmin)), 'LineWidth', 0.8);
xlabel(handles.axes(1), 'Frequency (Hz)'); ylabel(handles.axes(1), 'Power (dB)');
title(handles.axes(1), 'PSD by channel'); grid(handles.axes(1), 'on');

handles.axes(2) = nexttile(layout);
nChannels = numel(modelResult);
exponent = NaN(1,nChannels); rSquared = NaN(1,nChannels); fitError = NaN(1,nChannels);
for index = 1:nChannels
    exponent(index) = modelResult(index).aperiodicParams.exponent;
    rSquared(index) = modelResult(index).rSquared;
    fitError(index) = modelResult(index).fitError;
end
yyaxis(handles.axes(2), 'left'); bar(handles.axes(2), exponent); ylabel(handles.axes(2), 'Exponent');
yyaxis(handles.axes(2), 'right'); plot(handles.axes(2), rSquared, 'o-', 'LineWidth', 1); ylabel(handles.axes(2), 'R^2');
xlabel(handles.axes(2), 'Channel'); title(handles.axes(2), 'Aperiodic parameters and fit quality'); grid(handles.axes(2), 'on');

handles.axes(3) = nexttile(layout);
if isfield(bandResult, 'table') && ~isempty(bandResult.table)
    tbl = bandResult.table;
    names = unique(tbl.band, 'stable');
    channels = unique(tbl.channelIndex, 'stable');
    values = NaN(numel(channels), numel(names));
    for channel = 1:numel(channels)
        for band = 1:numel(names)
            row = tbl.channelIndex == channels(channel) & tbl.band == names(band);
            if any(row), values(channel,band) = tbl.totalPower(find(row,1)); end
        end
    end
    imagesc(handles.axes(3), values); colorbar(handles.axes(3));
    set(handles.axes(3), 'XTick', 1:numel(names), 'XTickLabel', names, ...
        'YTick', 1:numel(channels), 'YTickLabel', channels);
    xlabel(handles.axes(3), 'Band'); ylabel(handles.axes(3), 'Channel'); title(handles.axes(3), 'Total band power');
else
    text(handles.axes(3), 0.1, 0.5, 'No band-power table available.'); axis(handles.axes(3), 'off');
end

handles.axes(4) = nexttile(layout);
if isfield(artifactResult, 'summary') && isfield(artifactResult.summary, 'channelArtifactPercentage')
    bar(handles.axes(4), artifactResult.summary.channelArtifactPercentage);
    xlabel(handles.axes(4), 'Channel'); ylabel(handles.axes(4), 'Artifact samples (%)');
    title(handles.axes(4), sprintf('Retained %.1f%% / rejected %.1f%%', ...
        100-artifactResult.rejectedPercentage, artifactResult.rejectedPercentage)); grid(handles.axes(4), 'on');
else
    text(handles.axes(4), 0.1, 0.5, 'No artifact summary available.'); axis(handles.axes(4), 'off');
end
end

function value = get_field(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = defaultValue; end
end

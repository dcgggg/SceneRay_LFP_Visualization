function lfp_apply_plot_config(figureHandle, plotCfg, layout)
%LFP_APPLY_PLOT_CONFIG Apply shared interactive/export-friendly plot settings.
%   Plot functions remain independent of a GUI: FIGUREHANDLE is returned by
%   the caller and can be inspected, zoomed, panned, and edited interactively.
%   FIGUREPOSITION is in pixels.  The optional tiled layout receives looser
%   spacing so axis labels do not cover neighboring panels.

if nargin < 3
    layout = [];
end
if ~isgraphics(figureHandle, 'figure')
    return;
end

position = get_plot_field(plotCfg, 'figurePosition', [80 80 1600 1000]);
if isnumeric(position) && numel(position) == 4 && all(isfinite(position)) && all(position(3:4) > 0)
    figureHandle.Position = double(position(:)');
end

if ~isempty(layout) && isgraphics(layout)
    tileSpacing = string(get_plot_field(plotCfg, 'tileSpacing', "loose"));
    tilePadding = string(get_plot_field(plotCfg, 'tilePadding', "loose"));
    try layout.TileSpacing = tileSpacing; catch, end
    try layout.Padding = tilePadding; catch, end
end

fontSize = get_plot_field(plotCfg, 'fontSize', 10);
if isnumeric(fontSize) && isscalar(fontSize) && isfinite(fontSize) && fontSize > 0
    axesHandles = findall(figureHandle, 'Type', 'axes');
    if ~isempty(axesHandles)
        set(axesHandles, 'FontSize', double(fontSize));
    end
end
end

function value = get_plot_field(plotCfg, name, defaultValue)
if isstruct(plotCfg) && isfield(plotCfg, name) && ~isempty(plotCfg.(name))
    value = plotCfg.(name);
else
    value = defaultValue;
end
end

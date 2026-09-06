function handles = plotSpectralModel(modelResult, plotCfg)
%PLOTSPECTRALMODEL Plot a FOOOF-style fixed model and its decomposition.
%   The y-axis is log10(power), while model arrays remain linear power in
%   MODELRESULT. Gaussian BW is plotted and reported as 2*sigma.

arguments
    modelResult (1,1) struct
    plotCfg (1,1) struct
end
if ~isfield(modelResult, 'freq') || ~isfield(modelResult, 'inputPower')
    error('LFP:InvalidModelResult', 'modelResult.freq and modelResult.inputPower are required.');
end
visible = char(get_field(plotCfg, 'visible', "on"));
parent = get_field(plotCfg, 'parent', []);
if isempty(parent)
    figureHandle = figure('Visible', visible, 'Color', 'w', 'Name', 'Spectral model');
    layout = tiledlayout(figureHandle, 2, 1, 'TileSpacing', 'compact');
else
    parentType = get_graphics_type(parent);
    if any(parentType == ["figure" "uipanel" "uitab"])
        figureHandle = ancestor(parent, 'figure');
        layout = tiledlayout(parent, 2, 1, 'TileSpacing', 'compact');
    else
        figureHandle = ancestor(parent, 'figure');
        layout = tiledlayout(figureHandle, 2, 1, 'TileSpacing', 'compact');
    end
end
handles = struct('figure', figureHandle, 'layout', layout, 'axes', gobjects(2,1), ...
    'peakLines', gobjects(0));
freq = modelResult.freq;
valid = freq > 0 & isfinite(modelResult.inputPower) & modelResult.inputPower > 0;
fullModel = get_curve(modelResult, 'fullModelFit', numel(freq));
aperiodic = get_curve(modelResult, 'aperiodicFit', numel(freq));
periodic = get_curve(modelResult, 'periodicFit', numel(freq));
handles.axes(1) = nexttile(layout);
plotFrequency(handles.axes(1), freq(valid), log10(modelResult.inputPower(valid)), plotCfg, 'k', 'Original PSD'); hold(handles.axes(1), 'on');
if any(isfinite(fullModel)), plotFrequency(handles.axes(1), freq, log10(max(fullModel, realmin)), plotCfg, 'r', 'Full model'); end
if any(isfinite(aperiodic)), plotFrequency(handles.axes(1), freq, log10(max(aperiodic, realmin)), plotCfg, 'b--', 'Aperiodic fit'); end
periodicInclusive = aperiodic + periodic;
if any(isfinite(periodicInclusive)), plotFrequency(handles.axes(1), freq, log10(max(periodicInclusive, realmin)), plotCfg, 'g:', 'Periodic-inclusive model'); end
xline(handles.axes(1), modelResult.fitRange, ':', 'Color', [0.4 0.4 0.4]);
if isfield(modelResult, 'peakParams') && ~isempty(modelResult.peakParams)
    centers = [modelResult.peakParams.CF];
    handles.peakLines = xline(handles.axes(1), centers, '--', 'Color', [0.1 0.6 0.1]);
    for index = 1:numel(centers)
        text(handles.axes(1), centers(index), max(ylim(handles.axes(1)))-0.05*range(ylim(handles.axes(1))), ...
            sprintf('CF %.2f Hz', centers(index)), 'Rotation', 90, 'Color', [0.1 0.5 0.1]);
    end
end
hold(handles.axes(1), 'off'); xlabel(handles.axes(1), 'Frequency (Hz)'); ylabel(handles.axes(1), 'log10(power)');
title(handles.axes(1), sprintf('Fixed model [%s]: offset %.3f, exponent %.3f, R^2 %.3f, error %.3f', ...
    get_field(modelResult, 'fitStatus', "unknown"), modelResult.aperiodicParams.offset, ...
    modelResult.aperiodicParams.exponent, modelResult.rSquared, modelResult.fitError));
legend(handles.axes(1), 'Location', 'best'); grid(handles.axes(1), 'on');

handles.axes(2) = nexttile(layout);
flattened = get_curve(modelResult, 'flattenedSpectrum', numel(freq));
if any(isfinite(flattened))
    plotFrequency(handles.axes(2), freq, flattened, plotCfg, 'k', 'Flattened spectrum'); hold(handles.axes(2), 'on');
end
if any(isfinite(fullModel)) && any(isfinite(aperiodic))
    gaussianLog = log10(max(fullModel, realmin)) - log10(max(aperiodic, realmin));
    plotFrequency(handles.axes(2), freq, gaussianLog, plotCfg, 'g', 'Gaussian periodic sum');
end
hold(handles.axes(2), 'off');
xlabel(handles.axes(2), 'Frequency (Hz)'); ylabel(handles.axes(2), 'log10 residual');
title(handles.axes(2), sprintf('Periodic decomposition (%d peaks)', modelResult.nPeaks)); grid(handles.axes(2), 'on');
end

function plotFrequency(ax, frequency, values, cfg, style, displayName)
scale = get_field(cfg, 'frequencyScale', "linear");
if string(scale) == "log", semilogx(ax, frequency, values, style, 'DisplayName', displayName, 'LineWidth', 1.0);
else, plot(ax, frequency, values, style, 'DisplayName', displayName, 'LineWidth', 1.0); end
end

function value = get_field(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = defaultValue; end
end

function value = get_graphics_type(handleValue)
if isgraphics(handleValue)
    value = string(get(handleValue, 'Type'));
else
    value = "";
end
end

function curve = get_curve(modelResult, fieldName, nPoints)
curve = NaN(nPoints, 1);
if ~isfield(modelResult, fieldName) || isempty(modelResult.(fieldName))
    return;
end
values = modelResult.(fieldName);
if numel(values) ~= nPoints
    error('LFP:InvalidModelResult', '%s has %d elements; expected %d.', fieldName, numel(values), nPoints);
end
curve(:) = values(:);
end

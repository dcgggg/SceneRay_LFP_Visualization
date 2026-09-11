function handles = plotProjectComparison(comparison, options)
%PLOTPROJECTCOMPARISON Plot a saved Project comparison long table.
%   Each point represents one explicit Session/channel/band result.  The
%   function does not calculate statistics and never invents error bars.

arguments
    comparison (1,1) struct
    options.Visible (1,1) string = "on"
    options.FigurePosition double = []
    options.Parent = []
    options.Band (1,1) string = ""
    options.Metric (1,1) string = ""
end
if ~isfield(comparison, 'result_table') || ~istable(comparison.result_table)
    error('LFP:InvalidComparison', 'comparison.result_table is required.');
end
tbl = comparison.result_table;
if strlength(options.Band) > 0 && ismember('band', tbl.Properties.VariableNames)
    tbl = tbl(string(tbl.band) == options.Band, :);
end
if strlength(options.Metric) > 0 && ismember('metric', tbl.Properties.VariableNames)
    tbl = tbl(string(tbl.metric) == options.Metric, :);
end
if isempty(options.Parent)
    fig = figure('Visible', options.Visible, 'Color', 'w', 'Name', 'LFP Project comparison');
    if ~isempty(options.FigurePosition), fig.Position = options.FigurePosition; end
    ax = axes(fig);
else
    ax = options.Parent; fig = ancestor(ax, 'figure');
end
cla(ax); hold(ax, 'on');
if isempty(tbl)
    text(ax, 0.5, 0.5, 'No comparable results', 'HorizontalAlignment', 'center');
    axis(ax, 'off');
else
    labels = string(tbl.session_id);
    [uniqueLabels, ~, group] = unique(labels, 'stable');
    values = double(tbl.value);
    scatter(ax, group, values, 45, group, 'filled', 'HandleVisibility', 'off');
    if strcmpi(string(comparison.type), "within_subject") && numel(uniqueLabels) > 1
        means = NaN(numel(uniqueLabels),1);
        for k=1:numel(uniqueLabels), means(k)=mean(values(group==k), 'omitnan'); end
        plot(ax, 1:numel(uniqueLabels), means, '-k', 'LineWidth', 1.2, 'DisplayName', 'Session mean');
    end
    xticks(ax, 1:numel(uniqueLabels)); xticklabels(ax, cellstr(uniqueLabels));
    xtickangle(ax, 30); grid(ax, 'on');
    xlabel(ax, 'Session'); ylabel(ax, 'Value');
    title(ax, string(get_field(comparison, 'type', "comparison")), 'Interpreter', 'none');
    legend(ax, 'Location', 'best', 'Interpreter', 'none');
end
handles = struct('figure', fig, 'axes', ax);
end

function value = get_field(s, name, fallback)
if isfield(s, name) && ~isempty(s.(name)), value=s.(name); else, value=fallback; end
end

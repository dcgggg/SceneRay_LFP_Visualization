function handles = plotGroupedPsdComparison(summary, options)
%PLOTGROUPEDPSDCOMPARISON Plot curves using the recorded aggregation rule.

arguments
    summary (1,1) struct
    options.Parent = []
    options.ErrorMode (1,1) string = "sd"
    options.ShowIndividuals (1,1) logical = true
    options.Visible (1,1) string = "on"
end
if ~isfield(summary, 'frequencyHz') || isempty(summary.frequencyHz) || isempty(summary.psd)
    error('LFP:EmptyPsdComparison', '没有可绘制的 PSD 比较结果。');
end
if isempty(options.Parent)
    fig = figure('Visible',char(options.Visible),'Color','w','Name','Grouped PSD comparison');
    ax = axes(fig);
else
    ax = options.Parent; fig = ancestor(ax,'figure');
end
cla(ax,'reset'); hold(ax,'on');
groups = string(summary.group_labels_unique); colors = lines(max(1,numel(groups)));
for groupIndex = 1:numel(groups)
    columns = summary.group_labels == groups(groupIndex);
    if options.ShowIndividuals
        faded = 0.75 + 0.25*colors(groupIndex,:);
        individual = summary.psd(:,columns);
        for individualIndex = 1:size(individual,2)
            plot(ax,summary.frequencyHz,10*log10(max(individual(:,individualIndex),realmin)), ...
                'Color',faded, 'HandleVisibility','off');
        end
    end
    meanCurve = summary.group_mean_psd(:,groupIndex);
    plot(ax,summary.frequencyHz,10*log10(max(meanCurve,realmin)), ...
        'Color',colors(groupIndex,:),'LineWidth',2,'DisplayName',groups(groupIndex));
    if lower(options.ErrorMode) ~= "none" && isfield(summary,'group_sd_psd')
        spread = summary.group_sd_psd(:,groupIndex);
        if any(isfinite(spread))
            lowerCurve=10*log10(max(meanCurve-spread,realmin));upperCurve=10*log10(max(meanCurve+spread,realmin));
            fill(ax,[summary.frequencyHz;flipud(summary.frequencyHz)],[lowerCurve;flipud(upperCurve)],colors(groupIndex,:), ...
                'FaceAlpha',.12,'EdgeColor','none','HandleVisibility','off');
        end
    end
end
grid(ax,'on'); xlabel(ax,'频率 (Hz)'); ylabel(ax,'PSD (dB, 10log10(linear PSD))');
aggregation = "subject"; if isfield(summary,'aggregation'), aggregation=lower(string(summary.aggregation)); end
if aggregation == "session"
    title(ax,'分组 PSD 比较 | 个体曲线 + Session 等权组均值','Interpreter','none');
else
    title(ax,'分组 PSD 比较 | 个体曲线 + 被试等权组均值','Interpreter','none');
end
legend(ax,'Location','best','Interpreter','none');
if isfield(summary,'aggregation'), ax.UserData=struct('aggregation',summary.aggregation,'errorMode',options.ErrorMode); end
handles=struct('figure',fig,'axes',ax);
end

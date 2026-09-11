function handles = plotGroupedBandPower(comparison, options)
%PLOTGROUPEDBANDPOWER Plot group means with subject-level points.
%   Subject values are averaged within subject before group means/SD are
%   calculated, so repeated Sessions do not receive extra between-subject
%   weight. Missing values remain missing and are never replaced by zero.

arguments
    comparison (1,1) struct
    options.Parent = []
    options.Metric (1,1) string = "totalPower"
    options.Visible (1,1) string = "on"
end
if ~isfield(comparison,'result_table') || ~istable(comparison.result_table)
    error('LFP:InvalidComparison','comparison.result_table is required.');
end
tbl=comparison.result_table;
if ismember('metric',tbl.Properties.VariableNames)
    tbl=tbl(string(tbl.metric)==string(options.Metric),:);
end
if ~ismember('value',tbl.Properties.VariableNames), error('LFP:InvalidComparisonMetric','比较结果中没有指标值：%s。',options.Metric); end
if ~ismember('group_label',tbl.Properties.VariableNames), tbl.group_label=repmat("Group 1",height(tbl),1); end
if isempty(options.Parent)
    fig=figure('Visible',char(options.Visible),'Color','w','Name','Grouped band-power comparison');
    ax=axes(fig);
else
    ax=options.Parent;fig=ancestor(ax,'figure');
end
cla(ax,'reset');
bands=unique(string(tbl.band),'stable');groups=unique(string(tbl.group_label),'stable');
values=NaN(numel(groups),numel(bands));sd=values;subjectPoints=cell(numel(groups),numel(bands));
for g=1:numel(groups)
    for b=1:numel(bands)
        rows=string(tbl.group_label)==groups(g)&string(tbl.band)==bands(b);
        sub=unique(string(tbl.subject_id(rows)),'stable'); reps=NaN(numel(sub),1);
        for s=1:numel(sub), reps(s)=mean(double(tbl.value(rows&string(tbl.subject_id)==sub(s))),'omitnan'); end
        reps=reps(isfinite(reps));subjectPoints{g,b}=reps;
        if ~isempty(reps),values(g,b)=mean(reps,'omitnan');if numel(reps)>1,sd(g,b)=std(reps,0,'omitnan');end,end
    end
end
bars=bar(ax,values','grouped');hold(ax,'on');
for b=1:numel(bands)
    for g=1:numel(groups)
        points=subjectPoints{g,b};if isempty(points),continue;end
        x=b+((g-(numel(groups)+1)/2)*min(.8/numel(groups),.2));
        scatter(ax,repmat(x,numel(points),1),points,28,'k','filled','HandleVisibility','off');
        if isfinite(sd(g,b)),errorbar(ax,x,values(g,b),sd(g,b),'k','LineStyle','none','HandleVisibility','off');end
    end
end
grid(ax,'on');xticks(ax,1:numel(bands));xticklabels(ax,cellstr(bands));xlabel(ax,'频段');ylabel(ax,char(options.Metric));
title(ax,'分组频带功率 | 条形=被试等权均值，点=被试代表值，误差=SD','Interpreter','none');
if numel(bars) == numel(groups), legend(ax,bars,cellstr(groups),'Location','best','Interpreter','none');
else, legend(ax,cellstr(groups),'Location','best','Interpreter','none'); end
handles=struct('figure',fig,'axes',ax,'values',values,'sd',sd,'groups',groups,'bands',bands);
end

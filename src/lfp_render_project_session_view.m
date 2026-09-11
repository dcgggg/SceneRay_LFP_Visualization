function state = lfp_render_project_session_view(viewName, view, data, results, session, channelIndex, options)
%LFP_RENDER_PROJECT_SESSION_VIEW Draw cached Session results into GUI axes.
%   This function only renders existing data/results and never runs an
%   analysis. It clears stale graphics before showing an empty state.

arguments
    viewName (1,1) string {mustBeMember(viewName,["raw" "psd" "specparam" "band"])}
    view (1,1) struct
    data (1,1) struct
    results (1,1) struct
    session (1,1) struct
    channelIndex (1,1) double {mustBeInteger,mustBePositive}
    options.MaxDisplayPoints (1,1) double = 12000
    options.BandMetric (1,1) string = "totalPower"
end
state = struct('status', "ok", 'message', "");
if channelIndex > size(data.signal,2)
    state.status = "empty"; state.message = "所选通道不存在。"; return;
end
label = channel_label(session, data, channelIndex);
switch viewName
    case "raw"
        state = draw_raw(view, data, results, channelIndex, label, options.MaxDisplayPoints);
    case "psd"
        state = draw_psd(view, results, channelIndex, label);
    case "specparam"
        state = draw_specparam(view, results, channelIndex, label);
    case "band"
        state = draw_band(view, results, channelIndex, label, options.BandMetric);
end
end

function state = draw_raw(view, data, results, channel, label, maxPoints)
axesList = [view.rawAxes view.cleanAxes]; clear_axes(axesList);
raw = double(data.signal(:,channel)); time = double(data.time(:)); clean = raw;
artifactMask = false(size(raw));
if isfield(results,'artifactResult') && isstruct(results.artifactResult)
    ar = results.artifactResult;
    if isfield(ar,'channelMask') && size(ar.channelMask,1)==numel(raw) && size(ar.channelMask,2)>=channel
        artifactMask = artifactMask | logical(ar.channelMask(:,channel));
    end
    if isfield(ar,'globalMask') && numel(ar.globalMask)==numel(raw)
        artifactMask = artifactMask | logical(ar.globalMask(:));
    end
end
clean(artifactMask) = NaN;
[tRaw,yRaw] = lfp_downsample_envelope(time,raw,maxPoints);
[tClean,yClean] = lfp_downsample_envelope(time,clean,maxPoints);
plot(view.rawAxes,tRaw,yRaw,'Color',[0.15 0.15 0.15],'LineWidth',0.7); grid(view.rawAxes,'on');
plot(view.cleanAxes,tClean,yClean,'Color',[0.05 0.35 0.85],'LineWidth',0.7); grid(view.cleanAxes,'on');
y = raw(isfinite(raw));
if ~isempty(y) && min(y)<max(y), ylim(view.rawAxes,[min(y) max(y)]); ylim(view.cleanAxes,[min(y) max(y)]); end
xlim(view.rawAxes,[time(1) time(end)]); xlim(view.cleanAxes,[time(1) time(end)]);
title(view.rawAxes,"原始信号 | "+label,'Interpreter','none');
title(view.cleanAxes,"保留信号（伪影为 NaN） | "+label,'Interpreter','none');
ylabel(view.rawAxes,string(data.units)); ylabel(view.cleanAxes,string(data.units)); xlabel(view.cleanAxes,'时间 (s)');
linkaxes(axesList,'x');
state = struct('status',"ok",'message',sprintf('完整记录 %.3f–%.3f s；分析仍使用全部样本。',time(1),time(end)));
end

function state = draw_psd(view, results, channel, label)
clear_axes(view.axes);
if ~isfield(results,'psdResult') || ~isfield(results.psdResult,'psd')
    state = empty_axis(view.axes,'尚无 PSD 结果。'); return;
end
psd = results.psdResult; frequency = double(psd.frequencyHz(:)); power = double(psd.psd);
if size(power,1)~=numel(frequency) && size(power,2)==numel(frequency), power=power.'; end
if size(power,1)~=numel(frequency) || size(power,2)<channel
    state = empty_axis(view.axes,'PSD 维度与通道不匹配。'); return;
end
valid = isfinite(frequency) & isfinite(power(:,channel)) & power(:,channel)>0;
if nnz(valid)<2, state=empty_axis(view.axes,'PSD 没有足够的有效正功率值。'); return; end
plot(view.axes,frequency(valid),10*log10(power(valid,channel)),'Color',[0.05 0.35 0.85],'LineWidth',1.2);
grid(view.axes,'on'); xlabel(view.axes,'频率 (Hz)'); ylabel(view.axes,'功率谱密度 (dB)');
title(view.axes,"PSD | "+label,'Interpreter','none'); xlim(view.axes,[min(frequency(valid)) max(frequency(valid))]);
method = string(get_field(psd,'method','unknown'));
state=struct('status',"ok",'message',"PSD 方法："+method+"；有效窗口："+string(get_field(psd,'validWindowCount',NaN)));
end

function state = draw_specparam(view, results, channel, label)
clear_axes([view.modelAxes view.peakAxes]);
if isfield(view,'qualityTable') && isgraphics(view.qualityTable), view.qualityTable.Data=cell(0,2); end
if ~isfield(results,'modelResult') || isempty(results.modelResult) || numel(results.modelResult)<channel
    state=empty_two(view,'尚无 specparam 结果。'); return;
end
model=results.modelResult(channel);
if ~isfield(model,'freq') || isempty(model.freq)
    message="specparam 未生成模型曲线。";
    if isfield(model,'warnings') && ~isempty(model.warnings), message=message+" "+join(string(model.warnings),"；"); end
    state=empty_two(view,message); return;
end
f=double(model.freq(:)); input=column(model.inputPower,numel(f)); ap=column(get_field(model,'aperiodicFit',[]),numel(f)); full=column(get_field(model,'fullModelFit',[]),numel(f));
valid=isfinite(f)&f>0&isfinite(input)&input>0;
if nnz(valid)<2, state=empty_two(view,'specparam 输入谱无有效正功率。'); return; end
plot(view.modelAxes,f(valid),log10(input(valid)),'k','LineWidth',1,'DisplayName','PSD'); hold(view.modelAxes,'on');
if any(isfinite(ap)), plot(view.modelAxes,f,log10(max(ap,realmin)),'b--','LineWidth',1.1,'DisplayName','Aperiodic'); end
if any(isfinite(full)), plot(view.modelAxes,f,log10(max(full,realmin)),'r','LineWidth',1.1,'DisplayName','Full model'); end
hold(view.modelAxes,'off'); grid(view.modelAxes,'on'); legend(view.modelAxes,'Location','best');
xlabel(view.modelAxes,'频率 (Hz)'); ylabel(view.modelAxes,'log10(power)'); title(view.modelAxes,"模型拟合 | "+label,'Interpreter','none');
flattened=column(get_field(model,'flattenedSpectrum',[]),numel(f));
if any(isfinite(flattened)), plot(view.peakAxes,f,flattened,'k','LineWidth',1,'DisplayName','Flattened'); hold(view.peakAxes,'on'); end
gaussians=get_field(model,'gaussianParams',struct([])); colors=lines(max(1,numel(gaussians))); total=zeros(size(f));
for k=1:numel(gaussians)
    component=double(gaussians(k).amplitudeLog10).*exp(-0.5*((f-double(gaussians(k).centerFrequencyHz))./double(gaussians(k).sigmaHz)).^2);
    total=total+component; plot(view.peakAxes,f,component,'-.','Color',colors(k,:),'DisplayName',sprintf('Peak %.2f Hz',gaussians(k).centerFrequencyHz));
end
if ~isempty(gaussians), plot(view.peakAxes,f,total,'g','LineWidth',1.2,'DisplayName','Gaussian sum'); else, text(view.peakAxes,0.5,0.5,'未检测到峰','Units','normalized','HorizontalAlignment','center'); end
hold(view.peakAxes,'off'); grid(view.peakAxes,'on'); xlabel(view.peakAxes,'频率 (Hz)'); ylabel(view.peakAxes,'log10 residual'); title(view.peakAxes,'峰分解');
if ~isempty(gaussians), legend(view.peakAxes,'Location','best'); end
params=get_field(model,'aperiodicParams',struct()); quality={... 
    '状态',char(string(get_field(model,'fitStatus','unknown'))); '模型',char(string(get_field(params,'mode','fixed'))); ...
    'Offset',numeric_text(get_field(params,'offset',NaN)); 'Exponent',numeric_text(get_field(params,'exponent',NaN)); ...
    'Knee',numeric_text(get_field(params,'knee',NaN)); 'R²',numeric_text(get_field(model,'rSquared',NaN)); ...
    '拟合误差',numeric_text(get_field(model,'fitError',NaN)); '峰数量',numeric_text(get_field(model,'nPeaks',0))};
if isfield(view,'qualityTable') && isgraphics(view.qualityTable), view.qualityTable.Data=quality; end
state=struct('status',string(get_field(model,'fitStatus','unknown')),'message',"specparam | "+string(get_field(model,'fitStatus','unknown')));
end

function state = draw_band(view, results, channel, label, metric)
clear_axes(view.axes);
if isfield(view,'table') && isgraphics(view.table), view.table.Data=cell(0,1); end
if ~isfield(results,'bandResult') || ~isstruct(results.bandResult) || ~isfield(results.bandResult,'table')
    state=empty_axis(view.axes,'尚无频带功率结果。'); return;
end
tbl=results.bandResult.table;
if ~ismember(metric,string(tbl.Properties.VariableNames))
    state=empty_axis(view.axes,"结果中没有指标 "+metric+"。"); return;
end
rows=tbl.channelIndex==channel; selected=tbl(rows,:);
if isempty(selected), state=empty_axis(view.axes,'所选通道没有频带结果。'); return; end
values=double(selected.(char(metric))); labels=string(selected.band);
scatter(view.axes,1:numel(values),values,55,[0.05 0.35 0.85],'filled'); grid(view.axes,'on');
xticks(view.axes,1:numel(values)); xticklabels(view.axes,cellstr(labels)); xtickangle(view.axes,25);
xlabel(view.axes,'频带'); ylabel(view.axes,metric); title(view.axes,"频带功率 | "+label,'Interpreter','none');
if isfield(view,'table') && isgraphics(view.table), view.table.Data=lfp_table_to_uitable_data(selected); view.table.ColumnName=selected.Properties.VariableNames; end
state=struct('status',"ok",'message',sprintf('%d 个频带结果；点代表该 Session/通道的汇总值。',height(selected)));
end

function state = empty_axis(ax,message)
cla(ax,'reset'); text(ax,0.5,0.5,message,'Units','normalized','HorizontalAlignment','center','Color',[0.4 0.4 0.4]); axis(ax,'off');
state=struct('status',"empty",'message',string(message));
end

function state = empty_two(view,message)
empty_axis(view.modelAxes,message); empty_axis(view.peakAxes,'');
state=struct('status',"empty",'message',string(message));
end

function clear_axes(axesList)
for index=1:numel(axesList), if isgraphics(axesList(index)), cla(axesList(index),'reset'); end, end
end

function values = column(values,n)
if isempty(values), values=NaN(n,1); return; end
if numel(values)~=n, values=NaN(n,1); else, values=double(values(:)); end
end

function value = get_field(source,name,fallback)
if isstruct(source) && isfield(source,name) && ~isempty(source.(name)), value=source.(name); else, value=fallback; end
end

function textValue = numeric_text(value)
if isnumeric(value) && isscalar(value) && isfinite(value), textValue=sprintf('%.5g',value); else, textValue='—'; end
end

function label = channel_label(session,data,index)
if isfield(session,'channels') && numel(session.channels)>=index
    label=string(session.channels(index).display_label);
    if strlength(label)==0, label=string(session.channels(index).original_label); end
elseif isfield(data,'channelLabels') && numel(data.channelLabels)>=index
    label=string(data.channelLabels(index));
else
    label="channel "+string(index);
end
end

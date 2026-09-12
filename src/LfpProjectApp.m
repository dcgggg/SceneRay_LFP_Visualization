classdef LfpProjectApp < handle
    %LFPPROJECTAPP MATLAB-native Project/Subject/Session workspace.

    properties
        Figure
        Project = struct()
        CurrentSubjectId = ""
        CurrentSessionId = ""
        CurrentChannelIndex = 1
        CurrentViewedChannelId = ""
        SelectedChannelRows = []
        SelectedChannelIds = strings(0,1)
        SelectedBandRows = []
        DisplayChannelIds = strings(0,1)
        DisplaySelectionExplicit = false
        AnalysisSnapshot = struct()
        CurrentRun = struct()
        CurrentResults = struct()
        CurrentData = struct()
        CurrentComparison = struct()
        CompareSelectedSessionIds = strings(0,1)
        CompareSelectedChannelKeys = strings(0,1)
        CompareGroupLabels = strings(0,1)
        Controls = struct()
        Dirty = false
        Busy = false
        CancelRequested = false
        ClosingRequested = false
        PendingCloseSave = false
        UiInitialized = false
        LayoutBusy = false
        CompactMode = false
        NavigationOnly = false
        NavigationCollapsed = false
        LogMessages = strings(0,1)
    end

    methods
        function app = LfpProjectApp(visible)
            if nargin < 1, visible = "on"; end
            app.buildUi(string(visible));
            app.showWelcome();
            app.setStatus("就绪", "尚未打开项目。", 0);
        end

        function delete(app), app.close(true); end

        function close(app, force)
            if nargin < 2, force = false; end
            if app.ClosingRequested && ~force, return; end
            fig=app.Figure;
            figureIsValid=isscalar(fig) && isgraphics(fig);
            if ~force && figureIsValid && strcmp(fig.Visible,'on')
                if app.Busy
                    answer=uiconfirm(app.Figure,'当前计算块结束后才能安全退出。是否请求取消并关闭？','关闭', ...
                        'Options',{'请求关闭','取消'},'DefaultOption',2,'CancelOption',2);
                    if strcmp(answer,'取消'), return; end
                    app.CancelRequested=true;
                    app.PendingCloseSave=app.Dirty;
                    app.ClosingRequested=true;
                    app.updateBusyState();
                    % Do not delete the figure while a synchronous analysis
                    % can still call progressUpdate/onCleanup. The cleanup
                    % path finalizes the close after the next safe checkpoint.
                    fig.Visible='off';
                    return;
                end
                if app.Dirty
                    answer=uiconfirm(app.Figure,'项目有未保存修改。','保存项目', ...
                        'Options',{'保存并关闭','不保存','取消'},'DefaultOption',1,'CancelOption',3);
                    if strcmp(answer,'取消'), return; end
                    if strcmp(answer,'保存并关闭')
                        try
                            if ~app.saveProject(), return; end
                        catch e, app.showError(e,'保存失败'); return; end
                    end
                end
            end
            app.ClosingRequested=true;
            app.finalizeClose();
        end

        function finalizeClose(app)
            app.ClosingRequested=true;
            fig=app.Figure;
            figureIsValid=isscalar(fig) && isgraphics(fig);
            if figureIsValid
                % Detach callbacks before deletion so queued resize events do
                % not re-enter layout while the window is being destroyed.
                fig.SizeChangedFcn=[];
                fig.CloseRequestFcn=[];
                delete(fig);
            end
        end

        function createProjectAt(app,root,name,description)
            if nargin<4, description=""; end
            app.Project=lfp_create_project(string(root),string(name),Description=string(description));
            app.Dirty=false; app.resetSelection(); app.refreshProject(); app.showWorkspace("data");
            app.setStatus("就绪","项目已创建；下一步请添加被试。",0);
        end

        function createProjectInParent(app,parent,name,description)
            if nargin<4, description=""; end
            project=lfp_create_project_in_parent(string(parent),string(name),Description=string(description));
            app.Project=project; app.Dirty=false; app.resetSelection(); app.refreshProject(); app.showWorkspace("data");
            app.setStatus("就绪","项目已创建；下一步请添加被试。",0);
        end

        function loadProjectFrom(app,root)
            app.Project=lfp_load_project(string(root)); app.Dirty=false;
            app.resetSelection(); app.refreshProject(); app.restoreLatestComparison(); app.showWorkspace("data");
            app.setStatus("就绪","项目已打开。",0);
        end

        function addSubjectRecord(app,info)
            [app.Project,subject]=lfp_project_add_subject(app.Project,info,Save=false);
            app.CurrentSubjectId=string(subject.subject_id); app.markDirty(); app.refreshProject();
        end

        function addSessionRecord(app,subjectId,info)
            [app.Project,session]=lfp_project_add_empty_session(app.Project,string(subjectId),info,Save=false);
            app.CurrentSubjectId=string(subjectId); app.CurrentSessionId=string(session.session_id);
            app.markDirty(); app.refreshProject(); app.selectSession(app.CurrentSessionId);
        end

        function attachDataToSession(app,sessionId,data)
            [app.Project,~]=lfp_project_attach_data(app.Project,string(sessionId),data,Save=false);
            app.CurrentSessionId=string(sessionId); app.markDirty(); app.refreshProject(); app.selectSession(app.CurrentSessionId);
        end

        function [data,importInfo]=importCsvToSession(app,sessionId,path,settings)
            %IMPORTCSVTOSESSION Non-interactive bridge used by the GUI dialog
            % and automated GUI workflows after import settings are confirmed.
            arguments
                app
                sessionId (1,1) string
                path (1,1) string
                settings (1,1) struct
            end
            [session,~]=lfp_project_find_session(app.Project,sessionId);
            if isempty(session),error('LFP:SessionNotFound','Session ID not found: %s',sessionId);end
            args=namedargs2cell(settings);[data,importInfo]=lfp_import_csv_configured(path,args{:});
            data.metadata.sourceFilePath=path; data.metadata.sourceFileName=string(get_filename_local(path));
            if isfield(data.metadata,'signalColumns'),data.metadata.sourceColumns=double(data.metadata.signalColumns(:)');end
            if isempty(session.data_refs)
                app.attachDataToSession(sessionId,data);
                importInfo.appended=false; [sessionNow,~]=lfp_project_find_session(app.Project,sessionId); importInfo.addedChannelIds=string({sessionNow.channels.channel_id})';
            else
                [app.Project,report]=lfp_project_append_data(app.Project,sessionId,data,ImportConfig=settings,Save=false);
                app.CurrentSessionId=string(sessionId); app.markDirty(); app.refreshProject(); app.selectSession(sessionId);
                importInfo.appended=true; importInfo.addedChannelIds=report.addedChannelIds;
            end
            app.setStatus('就绪',sprintf('已导入 %d 通道、%d 样本%s。',size(data.signal,2),size(data.signal,1),local_append_suffix(importInfo.appended)),0);
        end

        function selectSession(app,sessionId)
            if app.Busy || app.ClosingRequested, return; end
            [session,subject]=lfp_project_find_session(app.Project,string(sessionId));
            if isempty(session), return; end
            app.CurrentSessionId=string(sessionId); app.CurrentSubjectId=string(subject.subject_id); app.CurrentChannelIndex=1; app.CurrentViewedChannelId=""; app.DisplayChannelIds=strings(0,1); app.DisplaySelectionExplicit=false;
            app.loadCurrentSession(); app.updateSessionContext(session,subject); app.refreshAnalysisView();
        end

        function summary=runSelectedAnalysis(app)
            if app.Busy, error('LFP:AnalysisBusy','已有分析任务正在运行，请等待其结束或先取消。'); end
            if strlength(app.CurrentSessionId)==0, error('LFP:NoSessionSelected','请先选择 Session。'); end
            [session,~,~,~]=lfp_project_find_session(app.Project,app.CurrentSessionId);
            if isempty(session)||isempty(session.data_refs), error('LFP:SessionHasNoData','当前 Session 尚未导入数据。'); end
            enabledMask=true(1,numel(session.channels));
            if ~isempty(session.channels)&&isfield(session.channels,'enabled'), enabledMask=logical([session.channels.enabled]); end
            enabledIds=string({session.channels(enabledMask).channel_id})';
            if isempty(enabledIds), error('LFP:NoEnabledChannels','当前 Session 没有启用通道。请先在数据管理页启用至少一个通道。'); end
            cfg=app.readAnalysisConfig();
            [app.Project,~]=lfp_project_update_session(app.Project,app.CurrentSessionId,struct('analysis_config',cfg),Save=false);
            app.Busy=true; app.CancelRequested=false; app.updateBusyState();
            app.AnalysisSnapshot=struct('subject_id',app.CurrentSubjectId,'session_id',app.CurrentSessionId, ...
                'channel_ids',enabledIds,'data_version',string(session.data_version),'config_id',lfp_config_fingerprint(cfg), ...
                'created_at',string(datestr(now,31)));
            cleanup=onCleanup(@()app.finishTask()); %#ok<NASGU>
            app.setStatus("运行中","正在分析 "+app.CurrentSessionId+"（"+string(numel(enabledIds))+" 个启用通道）",.02); drawnow;
            [app.Project,summary]=lfp_analyze_project(app.Project,app.CurrentSessionId,Config=cfg, ...
                ComputeSpecparam=app.Controls.ModuleSpecparam.Value,ComputeBandPower=app.Controls.ModuleBand.Value, ...
                Save=true,ProgressCallback=@(p,m)app.progressUpdate(p,m));
            if app.ClosingRequested, return; end
            [~, app.Project] = lfp_save_project(app.Project); app.Dirty=false;
            app.loadCurrentSession(); app.refreshProject(); app.refreshAnalysisView();
            status=string(summary(1).status);
            if status=="failed", app.setStatus("失败",summary(1).errorMessage,1);
            elseif status=="partial_failure"
                warnings=string(summary(1).warnings);warnings=warnings(~ismissing(warnings)&strlength(warnings)>0);
                message="部分模块未完成；详情见结果版本和日志。";if ~isempty(warnings),message=join(warnings,"；");end
                app.setStatus("部分失败",message,1);
            else
                suffix="";
                if isfield(summary(1),'summary') && isstruct(summary(1).summary)
                    s=summary(1).summary; if isfield(s,'successful_channel_count'),suffix="；成功 "+string(s.successful_channel_count)+"，复用 "+string(get_field_local(s,'reused_channel_count',0))+"，失败 "+string(get_field_local(s,'failed_channel_count',0));end
                end
                app.setStatus("完成","结果已自动保存（"+status+"）"+suffix+"。",1);
            end
        end

        function comparison=compareSelected(app,unify)
            if nargin<2,unify=false;end
            if isempty(app.CompareSelectedSessionIds),error('LFP:NoSessionsSelected','请在候选表中勾选至少一个 Session。');end
            spec=app.readComparisonSpec(); app.Busy=true; app.updateBusyState(); cleanup=onCleanup(@()app.finishTask()); %#ok<NASGU>
            app.setStatus("运行中","正在读取比较结果。",.1); drawnow;
            % A normal comparison only reads compatible current results.  It
            % never silently applies the currently viewed Session's config to
            % other Sessions; unified reanalysis is an explicit action.
            compareCfg = struct();
            if unify, compareCfg = app.currentSessionConfig(); end
            [app.Project,comparison]=lfp_compare_project(app.Project,spec,Config=compareCfg, ...
                ComputeMissing=logical(unify),UnifyParameters=logical(unify),Save=true);
            if app.ClosingRequested, return; end
            app.CurrentComparison=comparison; app.Dirty=false; app.renderComparison(); app.refreshProject();
            app.setStatus("完成","比较状态："+string(comparison.status),1);
        end

        function exportSnapshot(app,path)
            if ~isgraphics(app.Figure),error('LFP:GuiClosed','GUI is closed.');end
            exportapp(app.Figure,string(path));
        end
    end

    methods (Access=private)
        function buildUi(app,visible)
            % Keep the figure hidden and do not attach the resize callback
            % until all controls have been assigned. uifigure can emit a size
            % event during construction, before app.Figure/BodyGrid exist.
            app.Figure=uifigure('Name','SceneRay LFP 项目分析','Visible','off', ...
                'Position',[80 60 1500 900],'CloseRequestFcn',@(~,~)app.close(false), ...
                'AutoResizeChildren','off');
            host=uipanel(app.Figure,'BorderType','none','Units','pixels','Position',[1 1 1500 900]);app.Controls.HostPanel=host;
            root=uigridlayout(host,[3 1]);app.Controls.RootGrid=root;root.RowHeight={54,'1x',32};root.Padding=[8 8 8 8];root.RowSpacing=6;
            app.buildToolbar(root);body=uigridlayout(root,[1 2]);body.Layout.Row=2;body.ColumnWidth={285,'1x'};body.Padding=[0 0 0 0];body.ColumnSpacing=8;app.Controls.BodyGrid=body;
            app.buildNavigation(body);app.buildWorkspace(body);app.buildStatusbar(root);
            app.UiInitialized=true;
            app.Figure.SizeChangedFcn=@(~,~)app.applyResponsiveLayout();
            app.applyResponsiveLayout();
            app.Figure.Visible=char(visible);
        end

        function buildToolbar(app,parent)
            bar=uipanel(parent,'BorderType','none');bar.Layout.Row=1;g=uigridlayout(bar,[1 9]);g.ColumnWidth={108,108,108,82,16,'1x',120,100,100};g.Padding=[4 4 4 4];
            app.Controls.NewProject=uibutton(g,'Text','新建项目','ButtonPushedFcn',@(~,~)app.newProjectDialog());
            app.Controls.OpenProject=uibutton(g,'Text','打开项目','ButtonPushedFcn',@(~,~)app.openProjectDialog());
            app.Controls.SaveProject=uibutton(g,'Text','保存项目','Enable','off','ButtonPushedFcn',@(~,~)app.saveProject());
            app.Controls.ToggleNavigation=uibutton(g,'Text','收起导航','ButtonPushedFcn',@(~,~)app.toggleNavigation());
            uilabel(g,'Text','');app.Controls.ProjectTitle=uilabel(g,'Text','未打开项目','FontWeight','bold','HorizontalAlignment','center');
            app.Controls.SaveState=uilabel(g,'Text','—','HorizontalAlignment','center');
            app.Controls.ShowLog=uibutton(g,'Text','查看日志','ButtonPushedFcn',@(~,~)app.showLog());
            app.Controls.CloseButton=uibutton(g,'Text','关闭','ButtonPushedFcn',@(~,~)app.close(false));
        end

        function buildNavigation(app,parent)
            panel=uipanel(parent,'Title','项目导航');panel.Layout.Column=1;app.Controls.NavigationPanel=panel;g=uigridlayout(panel,[3 1]);g.RowHeight={'1x',36,54};g.Padding=[6 6 6 6];
            app.Controls.ProjectTree=uitree(g,'SelectionChangedFcn',@(~,~)app.onTreeSelection());
            p=uigridlayout(g,[1 3]);p.ColumnWidth={'1x','1x','1x'};p.Padding=[0 0 0 0];
            uibutton(p,'Text','数据管理','ButtonPushedFcn',@(~,~)app.showWorkspace("data"));
            uibutton(p,'Text','分析参数与结果','ButtonPushedFcn',@(~,~)app.showWorkspace("analysis"));
            uibutton(p,'Text','结果比较','ButtonPushedFcn',@(~,~)app.showWorkspace("compare"));
            app.Controls.NavigationHint=uilabel(g,'Text','请先新建或打开项目。','WordWrap','on','FontColor',[.35 .35 .35]);
        end

        function buildWorkspace(app,parent)
            holder=uipanel(parent,'BorderType','none');holder.Layout.Column=2;app.Controls.WorkspacePanel=holder;
            hg=uigridlayout(holder,[1 1]);hg.Padding=[0 0 0 0];
            app.Controls.Welcome=uipanel(hg,'BorderType','none');
            app.Controls.Welcome.Layout.Row=1;app.Controls.Welcome.Layout.Column=1;
            wg=uigridlayout(app.Controls.Welcome,[5 3]);wg.RowHeight={'1x',120,44,44,'1x'};wg.ColumnWidth={'1x',420,'1x'};
            logo=uipanel(wg,'Title','LOGO','BorderType','line','ForegroundColor',[.75 .75 .75]);logo.Layout.Row=2;logo.Layout.Column=2;
            lg=uigridlayout(logo,[1 1]);lg.Padding=[12 12 12 12];uilabel(lg,'Text','SceneRay LFP 项目分析','FontSize',22,'FontWeight','bold','HorizontalAlignment','center','FontColor',[.45 .45 .45]);
            n=uilabel(wg,'Text','请使用顶部“新建项目”或“打开项目”。启动时不会自动导入数据。','HorizontalAlignment','center','WordWrap','on');n.Layout.Row=3;n.Layout.Column=2;
            hint=uilabel(wg,'Text','项目将按 Subject → Session → Channel 组织，并保留原始数据。','HorizontalAlignment','center','WordWrap','on','FontColor',[.45 .45 .45]);hint.Layout.Row=4;hint.Layout.Column=2;
            app.Controls.WorkspaceTabs=uitabgroup(hg,'Visible','off','SelectionChangedFcn',@(~,~)app.onWorkspaceTabChanged());
            app.Controls.WorkspaceTabs.Layout.Row=1;app.Controls.WorkspaceTabs.Layout.Column=1;
            app.Controls.DataTab=uitab(app.Controls.WorkspaceTabs,'Title','数据管理');app.Controls.AnalysisTab=uitab(app.Controls.WorkspaceTabs,'Title','分析参数与结果');app.Controls.CompareTab=uitab(app.Controls.WorkspaceTabs,'Title','结果比较');
            app.buildDataPage(app.Controls.DataTab);app.buildAnalysisPage(app.Controls.AnalysisTab);app.buildComparePage(app.Controls.CompareTab);
        end

        function buildDataPage(app,parent)
            g=uigridlayout(parent,[3 1]);g.RowHeight={44,150,'1x'};g.Padding=[8 8 8 8];
            a=uigridlayout(g,[1 6]);a.ColumnWidth={110,110,110,110,110,'1x'};a.Padding=[0 0 0 0];
            app.Controls.AddSubject=uibutton(a,'Text','添加被试','ButtonPushedFcn',@(~,~)app.addSubjectDialog());
            app.Controls.AddSession=uibutton(a,'Text','添加 Session','ButtonPushedFcn',@(~,~)app.addSessionDialog());
            app.Controls.ImportData=uibutton(a,'Text','导入/追加数据','ButtonPushedFcn',@(~,~)app.importCsvDialog());
            app.Controls.EditMetadata=uibutton(a,'Text','编辑信息','ButtonPushedFcn',@(~,~)app.editMetadataDialog());
            app.Controls.RemoveNode=uibutton(a,'Text','移除','ButtonPushedFcn',@(~,~)app.removeSelectedNode());
            app.Controls.DataContext=uilabel(a,'Text','选择项目节点开始。','HorizontalAlignment','right');
            app.Controls.Metadata=uitextarea(g,'Editable','off','Value',{'尚未选择对象。'},'WordWrap','on');
            content=uigridlayout(g,[1 2]);content.ColumnWidth={520,'1x'};content.Padding=[0 0 0 0];
            cp=uipanel(content,'Title','通道信息（原始名称和 ID 不可修改）');cg=uigridlayout(cp,[2 1]);cg.RowHeight={'1x',32};cg.Padding=[4 4 4 4];
            app.Controls.ChannelTable=uitable(cg,'Data',cell(0,13),'ColumnName',{'启用','ID','原始名称','显示名称','侧别','脑区','触点','参考','采样率(Hz)','样本数','时长(s)','单位','来源文件'}, ...
                'ColumnEditable',[true false false true true true true true false false false false false],'RowName',[],'CellSelectionCallback',@(~,e)app.selectChannelRows(e),'CellEditCallback',@(~,~)app.saveChannelEdits());
            foot=uigridlayout(cg,[1 5]);foot.ColumnWidth={90,90,90,120,'1x'};foot.Padding=[0 0 0 0];app.Controls.EnableChannels=uibutton(foot,'Text','启用所选','ButtonPushedFcn',@(~,~)app.setSelectedChannelsEnabled(true));app.Controls.DisableChannels=uibutton(foot,'Text','停用所选','ButtonPushedFcn',@(~,~)app.setSelectedChannelsEnabled(false));app.Controls.RemoveChannels=uibutton(foot,'Text','移除所选','ButtonPushedFcn',@(~,~)app.removeSelectedChannels());app.Controls.RebuildChannels=uibutton(foot,'Text','重建所选缓存','ButtonPushedFcn',@(~,~)app.rebuildSelectedChannelCaches());app.Controls.ChannelHint=uilabel(foot,'Text','停用不删除数据；移除仅更新活动通道索引，缓存保留。','FontColor',[.35 .35 .35]);
            pp=uipanel(content,'Title','启用通道完整记录预览');pg=uigridlayout(pp,[2 1]);pg.RowHeight={34,'1x'};pg.Padding=[4 4 4 4];
            top=uigridlayout(pg,[1 2]);top.ColumnWidth={'1x','1x'};top.Padding=[0 0 0 0];
            app.Controls.DataPreviewInfo=uilabel(top,'Text','暂无启用通道','HorizontalAlignment','left','WordWrap','on');
            app.Controls.DataPreviewHint=uilabel(top,'Text','每个通道使用自己的时间轴；仅显示抽稀，不改变分析数据。','HorizontalAlignment','right','WordWrap','on','FontColor',[.35 .35 .35]);
            app.Controls.DataPreviewPanel=uipanel(pg,'BorderType','none');
            if isprop(app.Controls.DataPreviewPanel,'Scrollable'),app.Controls.DataPreviewPanel.Scrollable='on';end
            app.Controls.DataPreviewGrid=uigridlayout(app.Controls.DataPreviewPanel,[1 1]);app.Controls.DataPreviewGrid.Padding=[2 2 2 2];
            app.Controls.DataPreviewAxes=gobjects(0);app.Controls.DataPreviewAxesPool=gobjects(0);
            % Retained as a compatibility handle for scripts written against older releases.
            app.Controls.DataPreviewChannel=uidropdown(pp,'Items',{'(全部启用通道)'},'Value','(全部启用通道)','Visible','off','Position',[0 0 1 1]);
        end

        function buildAnalysisPage(app,parent)
            g=uigridlayout(parent,[5 1]);g.RowHeight={34,38,132,42,'1x'};g.Padding=[8 8 8 8];g.RowSpacing=5;
            app.Controls.AnalysisContext=uilabel(g,'Text','请选择包含数据的 Session。','FontWeight','bold','WordWrap','on');
            m=uigridlayout(g,[1 6]);m.ColumnWidth={95,95,110,110,'1x',170};m.Padding=[0 0 0 0];
            app.Controls.ModuleArtifact=uicheckbox(m,'Text','伪影处理','Value',true,'Enable','off','Tooltip','固定前置步骤');
            app.Controls.ModulePsd=uicheckbox(m,'Text','PSD','Value',true,'Enable','off','Tooltip','固定前置步骤');
            app.Controls.ModuleSpecparam=uicheckbox(m,'Text','specparam','Value',true);app.Controls.ModuleBand=uicheckbox(m,'Text','频带功率','Value',true);uilabel(m,'Text','');
            app.Controls.AnalysisChannel=uidropdown(m,'Items',{'(无)'},'ValueChangedFcn',@(~,~)app.onAnalysisChannelChanged());
            app.buildAnalysisSettings(g);
            r=uigridlayout(g,[1 8]);r.ColumnWidth={170,80,90,110,110,150,'1x',150};r.Padding=[0 0 0 0];
            app.Controls.RunSession=uibutton(r,'Text','分析全部启用通道','ButtonPushedFcn',@(~,~)app.onRun(),'Tooltip','按当前 Session 中启用的通道 ID 批量分析，不受当前查看通道影响。');
            app.Controls.Cancel=uibutton(r,'Text','取消','Enable','off','ButtonPushedFcn',@(~,~)app.requestCancel());
            uibutton(r,'Text','查看日志','ButtonPushedFcn',@(~,~)app.showLog());
            app.Controls.SaveFigure=uibutton(r,'Text','保存图片','ButtonPushedFcn',@(~,~)app.saveCurrentFigure());app.Controls.SaveResult=uibutton(r,'Text','保存数据','ButtonPushedFcn',@(~,~)app.saveCurrentData());
            app.Controls.AnalysisState=uilabel(r,'Text','未运行','HorizontalAlignment','right','WordWrap','on');app.Controls.ResultVersion=uilabel(r,'Text','结果：无','HorizontalAlignment','right','WordWrap','on');
            app.Controls.AnalysisEnabledCount=uilabel(r,'Text','启用 0 通道','HorizontalAlignment','right','WordWrap','on');
            app.buildAnalysisResults(g);
        end

        function buildAnalysisSettings(app,parent)
            tabs=uitabgroup(parent);app.Controls.SettingsTabs=tabs;
            at=uitab(tabs,'Title','伪影');a=uigridlayout(at,[2 6]);a.RowHeight={34,34};a.ColumnWidth={80,90,80,90,100,90};
            uilabel(a,'Text','振幅 z');app.Controls.ArtifactZ=uieditfield(a,'numeric','Value',8);uilabel(a,'Text','跳变 z');app.Controls.JumpZ=uieditfield(a,'numeric','Value',8);uilabel(a,'Text','扩展 (s)');app.Controls.Padding=uieditfield(a,'numeric','Value',.01);
            pt=uitab(tabs,'Title','PSD');p=uigridlayout(pt,[2 8]);p.RowHeight={34,34};p.ColumnWidth={70,115,75,80,70,80,70,80};
            uilabel(p,'Text','方法');app.Controls.PsdMethod=uidropdown(p,'Items',{'multitaper','welch'},'Value','multitaper');uilabel(p,'Text','窗长 (s)');app.Controls.PsdWindow=uieditfield(p,'numeric','Value',4);uilabel(p,'Text','下限 Hz');app.Controls.PsdLow=uieditfield(p,'numeric','Value',1);uilabel(p,'Text','上限 Hz');app.Controls.PsdHigh=uieditfield(p,'numeric','Value',35);
            uilabel(p,'Text','NW');app.Controls.PsdNW=uieditfield(p,'numeric','Value',3.5);uilabel(p,'Text','K');app.Controls.PsdK=uieditfield(p,'numeric','Value',6);uilabel(p,'Text','重叠');app.Controls.PsdOverlap=uieditfield(p,'numeric','Value',.5);
            st=uitab(tabs,'Title','specparam');s=uigridlayout(st,[2 8]);s.RowHeight={34,34};s.ColumnWidth={70,80,70,80,70,80,80,90};
            uilabel(s,'Text','模型');app.Controls.SpecMode=uidropdown(s,'Items',{'fixed','knee'},'Value','fixed');uilabel(s,'Text','下限 Hz');app.Controls.SpecLow=uieditfield(s,'numeric','Value',1);uilabel(s,'Text','上限 Hz');app.Controls.SpecHigh=uieditfield(s,'numeric','Value',35);uilabel(s,'Text','最大峰数');app.Controls.SpecPeaks=uieditfield(s,'numeric','Value',6);
            bt=uitab(tabs,'Title','频带功率');b=uigridlayout(bt,[4 1]);b.RowHeight={180,36,110,36};b.Padding=[4 4 4 4];b.RowSpacing=4;
            app.Controls.BandTable=uitable(b,'Data',band_table_data(lfpDefaultConfig().bandDefinitions),'ColumnName',{'启用','频段名称','下限 (Hz)','上限 (Hz)'},'ColumnEditable',[true true true true],'RowName',[],'CellSelectionCallback',@(~,e)app.selectBandRows(e),'CellEditCallback',@(~,~)app.markDirty());
            ops=uigridlayout(b,[1 7]);ops.ColumnWidth={75,85,95,95,110,130,'1x'};ops.Padding=[0 0 0 0];
            app.Controls.BandAdd=uibutton(ops,'Text','新增频段','ButtonPushedFcn',@(~,~)app.addBandRow());app.Controls.BandDelete=uibutton(ops,'Text','删除所选','ButtonPushedFcn',@(~,~)app.deleteBandRows());app.Controls.BandSelectAll=uibutton(ops,'Text','全选启用','ButtonPushedFcn',@(~,~)app.setAllBandsEnabled(true));app.Controls.BandSelectNone=uibutton(ops,'Text','全不选','ButtonPushedFcn',@(~,~)app.setAllBandsEnabled(false));app.Controls.ResetBands=uibutton(ops,'Text','恢复默认','ButtonPushedFcn',@(~,~)app.resetBandTable());app.Controls.SaveBandTemplate=uibutton(ops,'Text','保存为项目默认','ButtonPushedFcn',@(~,~)app.saveBandTemplate());app.Controls.BandHint=uilabel(ops,'Text','可重叠；重叠频段不会自动相加。','FontColor',[.35 .35 .35],'HorizontalAlignment','right','WordWrap','on');
            dcp=uipanel(b,'Title','频带图显示通道（不改变启用状态）');dg=uigridlayout(dcp,[1 3]);dg.ColumnWidth={'1x',100,100};dg.Padding=[4 4 4 4];
            app.Controls.DisplayChannelList=uilistbox(dg,'Items',{'(无)'},'Value',{'(无)'},'Multiselect','on','ValueChangedFcn',@(~,~)app.onDisplayChannelsChanged());
            app.Controls.DisplayAllChannels=uibutton(dg,'Text','全选有效','ButtonPushedFcn',@(~,~)app.selectAllDisplayChannels());
            app.Controls.ClearDisplayChannels=uibutton(dg,'Text','清空显示','ButtonPushedFcn',@(~,~)app.clearDisplayChannels());
            bb=uigridlayout(b,[1 4]);bb.ColumnWidth={80,170,120,'1x'};bb.Padding=[0 0 0 0];uilabel(bb,'Text','显示指标');app.Controls.BandMetric=uidropdown(bb,'Items',{'totalPower','relativePower','logTotalPower','aperiodicPower','periodicPower'},'Value','totalPower','ValueChangedFcn',@(~,~)app.refreshAnalysisView());uilabel(bb,'Text','编辑仅影响当前 Session；保存模板才更新项目默认值。','FontColor',[.35 .35 .35],'WordWrap','on');
        end

        function buildAnalysisResults(app,parent)
            tabs=uitabgroup(parent,'SelectionChangedFcn',@(~,~)app.refreshAnalysisView());tabs.Layout.Row=5;app.Controls.AnalysisResultTabs=tabs;
            app.Controls.RawResultTab=uitab(tabs,'Title','原始信号与伪影');r=uigridlayout(app.Controls.RawResultTab,[2 1]);r.RowHeight={'1x','1x'};app.Controls.RawAxes=uiaxes(r);app.Controls.CleanAxes=uiaxes(r);
            app.Controls.PsdResultTab=uitab(tabs,'Title','PSD');pg=uigridlayout(app.Controls.PsdResultTab,[1 1]);pg.Padding=[8 8 8 8];app.Controls.PsdAxes=uiaxes(pg);
            app.Controls.SpecResultTab=uitab(tabs,'Title','specparam');s=uigridlayout(app.Controls.SpecResultTab,[2 2]);s.RowHeight={'1x','1x'};s.ColumnWidth={'1x',240};app.Controls.SpecModelAxes=uiaxes(s);app.Controls.SpecPeakAxes=uiaxes(s);app.Controls.SpecPeakAxes.Layout.Row=2;app.Controls.SpecQuality=uitable(s,'Data',cell(0,2),'ColumnName',{'参数','值'},'RowName',[]);app.Controls.SpecQuality.Layout.Row=[1 2];app.Controls.SpecQuality.Layout.Column=2;
            app.Controls.BandResultTab=uitab(tabs,'Title','频带功率');b=uigridlayout(app.Controls.BandResultTab,[1 2]);b.ColumnWidth={'1x',420};app.Controls.BandPlotPanel=uipanel(b,'BorderType','none');app.Controls.BandPlotGrid=uigridlayout(app.Controls.BandPlotPanel,[1 1]);app.Controls.BandAxes=gobjects(0);app.Controls.BandResultTable=uitable(b,'Data',cell(0,1),'RowName',[]);
        end

        function buildComparePage(app,parent)
            g=uigridlayout(parent,[4 1]);app.Controls.CompareGrid=g;g.RowHeight={220,220,78,'1x'};g.Padding=[8 8 8 8];g.RowSpacing=6;
            cp=uipanel(g,'Title','比较候选（筛选不会清除已选择对象）');c=uigridlayout(cp,[2 8]);c.RowHeight={32,'1x'};c.ColumnWidth={45,110,45,110,65,110,110,'1x'};
            uilabel(c,'Text','被试');app.Controls.FilterSubject=uidropdown(c,'Items',{'全部'},'ValueChangedFcn',@(~,~)app.refreshComparisonCandidates());uilabel(c,'Text','访视');app.Controls.FilterVisit=uidropdown(c,'Items',{'全部'},'ValueChangedFcn',@(~,~)app.refreshComparisonCandidates());uilabel(c,'Text','分析状态');app.Controls.FilterStatus=uidropdown(c,'Items',{'全部'},'ValueChangedFcn',@(~,~)app.refreshComparisonCandidates());app.Controls.SelectFiltered=uibutton(c,'Text','全选筛选结果','ButtonPushedFcn',@(~,~)app.selectFiltered());app.Controls.ClearComparison=uibutton(c,'Text','清空选择','ButtonPushedFcn',@(~,~)app.clearComparisonSelection());
            app.Controls.CandidateTable=uitable(c,'Data',cell(0,7),'ColumnName',{'选择','被试','Session','访视','条件','结果状态','稳定 ID'},'ColumnEditable',[true false false false false false false],'RowName',[],'CellEditCallback',@(~,e)app.onCandidateEdited(e));app.Controls.CandidateTable.Layout.Row=2;app.Controls.CandidateTable.Layout.Column=[1 8];
            sp=uipanel(g,'Title','已选择对象与通道映射');s=uigridlayout(sp,[1 2]);s.ColumnWidth={280,'1x'};left=uigridlayout(s,[2 1]);left.RowHeight={'1x',34};left.Padding=[0 0 0 0];app.Controls.SelectedSessions=uilistbox(left,'Items',{'(未选择)'},'Value',{'(未选择)'},'Multiselect','on');lb=uigridlayout(left,[1 4]);lb.ColumnWidth={88,120,120,'1x'};lb.Padding=[0 0 0 0];app.Controls.RemoveSelectedComparison=uibutton(lb,'Text','移除所选','ButtonPushedFcn',@(~,~)app.removeSelectedComparison());app.Controls.CompareChannelLabel=uidropdown(lb,'Items',{'(通道标签)'},'Value','(通道标签)');app.Controls.AddMatchingChannels=uibutton(lb,'Text','按标签添加','ButtonPushedFcn',@(~,~)app.addMatchingChannels());app.Controls.SelectedCount=uilabel(lb,'Text','已选择 0 条','HorizontalAlignment','right');right=uigridlayout(s,[2 1]);right.RowHeight={'1x',90};right.Padding=[0 0 0 0];app.Controls.SelectedObjectTable=uitable(right,'Data',cell(0,8),'ColumnName',{'被试','Session','访视','条件','通道','结果状态','比较组','稳定 ID'},'ColumnEditable',[false false false false false false true false],'RowName',[],'CellEditCallback',@(~,e)app.onSelectedObjectEdited(e));app.Controls.MappingTable=uitable(right,'Data',cell(0,3),'ColumnName',{'Session ID','选用通道','比较标签'},'ColumnEditable',[false true true],'RowName',[]);
            x=uigridlayout(g,[2 8]);x.RowHeight={32,32};x.ColumnWidth={55,110,65,110,70,120,110,'1x'};x.Padding=[0 0 0 0];
            uilabel(x,'Text','指标');app.Controls.CompareMetric=uidropdown(x,'Items',{'totalPower','relativePower','logTotalPower','aperiodicPower','periodicPower'},'Value','totalPower');uilabel(x,'Text','频段');app.Controls.CompareBand=uidropdown(x,'Items',{'delta','theta','alpha','beta','lowGamma','highGamma'},'Value','alpha');uilabel(x,'Text','分组依据');app.Controls.CompareGroupingBasis=uidropdown(x,'Items',{'custom','subject_group','visit'},'Value','custom');app.Controls.CompareButton=uibutton(x,'Text','生成比较','ButtonPushedFcn',@(~,~)app.onCompare(false));app.Controls.CompareStatus=uilabel(x,'Text','未比较');
            uilabel(x,'Text','图形');app.Controls.ComparePlot=uidropdown(x,'Items',{'点图','柱状图','分组 PSD','分组频带柱图'},'Value','分组频带柱图','ValueChangedFcn',@(~,~)app.renderComparison());uilabel(x,'Text','汇总');app.Controls.CompareAggregation=uidropdown(x,'Items',{'session','subject'},'Value','session');uilabel(x,'Text','');app.Controls.UnifyCompare=uibutton(x,'Text','统一参数重算','ButtonPushedFcn',@(~,~)app.onCompare(true));
            res=uigridlayout(g,[1 2]);res.ColumnWidth={'1x',190};app.Controls.CompareAxes=uiaxes(res);tools=uigridlayout(res,[6 1]);tools.RowHeight={38,38,38,38,'1x',60};app.Controls.CompareSaveImage=uibutton(tools,'Text','保存图片','ButtonPushedFcn',@(~,~)app.saveComparisonImage());app.Controls.CompareExportData=uibutton(tools,'Text','导出比较数据','ButtonPushedFcn',@(~,~)app.exportComparisonData());app.Controls.CompareSavePlan=uibutton(tools,'Text','保存比较方案','ButtonPushedFcn',@(~,~)app.saveComparisonPlan());app.Controls.CompareDetails=uilabel(tools,'Text','缺失值不补零；跨被试不会连接为同一患者。','WordWrap','on','FontColor',[.35 .35 .35]);
        end

        function buildStatusbar(app,parent)
            p=uipanel(parent,'BorderType','none');p.Layout.Row=3;g=uigridlayout(p,[1 4]);g.ColumnWidth={90,'1x',230,90};g.Padding=[2 0 2 0];app.Controls.TaskStatus=uilabel(g,'Text','就绪','FontWeight','bold');app.Controls.StageStatus=uilabel(g,'Text','');app.Controls.Progress=uigauge(g,'linear','Limits',[0 1],'Value',0,'MajorTicks',[],'MinorTicks',[]);app.Controls.Percent=uilabel(g,'Text','0%','HorizontalAlignment','right');
        end

        function newProjectDialog(app)
            dg=uifigure('Name','新建项目','WindowStyle','modal','Position',[360 300 620 300]);
            g=uigridlayout(dg,[5 3]);g.RowHeight={34,34,34,70,42};g.ColumnWidth={100,'1x',100};g.Padding=[16 16 16 16];
            uilabel(g,'Text','项目名称');name=uieditfield(g,'text','Value','Human LFP project');
            uilabel(g,'Text','父目录');parent=uieditfield(g,'text','Value',char(pwd));browse=uibutton(g,'Text','浏览…','ButtonPushedFcn',@browseParent);
            uilabel(g,'Text','保存路径预览');preview=uilabel(g,'Text','','Interpreter','none','WordWrap','on');preview.Layout.Column=[2 3];
            uilabel(g,'Text','说明');description=uieditfield(g,'text','Value','');description.Layout.Column=[2 3];
            buttons=uigridlayout(g,[1 2]);buttons.Layout.Row=5;buttons.Layout.Column=[2 3];buttons.ColumnWidth={'1x','1x'};uibutton(buttons,'Text','取消','ButtonPushedFcn',@cancel);uibutton(buttons,'Text','创建','ButtonPushedFcn',@accept);
            name.ValueChangedFcn=@updatePreview;parent.ValueChangedFcn=@updatePreview;dg.CloseRequestFcn=@cancel;updatePreview();uiwait(dg);
            if isgraphics(dg),result=dg.UserData;delete(dg);else,result=[];end
            if ~isempty(result)
                try,app.createProjectInParent(result.parent,result.name,result.description);catch e,app.showError(e,'新建项目失败');end
            end
            function updatePreview(~,~)
                if strlength(strtrim(string(parent.Value)))==0||strlength(strtrim(string(name.Value)))==0,preview.Text='请输入父目录和项目名称';else,preview.Text=char(fullfile(string(parent.Value),string(name.Value)));end
            end
            function browseParent(~,~)
                selected=uigetdir(char(parent.Value),'选择项目父目录');if ~isequal(selected,0),parent.Value=char(selected);updatePreview();end
            end
            function cancel(~,~),if isgraphics(dg),dg.UserData=[];uiresume(dg);end,end
            function accept(~,~)
                try
                    parentRoot=string(parent.Value);projectName=string(name.Value);lfp_validate_folder_name(projectName,"项目名称");
                    if ~isfolder(parentRoot),error('LFP:InvalidProjectParent','项目父目录不存在。');end
                    dg.UserData=struct('parent',parentRoot,'name',projectName,'description',string(description.Value));uiresume(dg);
                catch e,uialert(dg,string(e.message),'项目设置');
                end
            end
        end

        function openProjectDialog(app)
            root=uigetdir('','选择包含 project.mat 的项目目录');if isequal(root,0),return;end
            try,app.loadProjectFrom(root);catch e,app.showError(e,'打开项目失败');end
        end

        function success = saveProject(app)
            success = true;
            if app.noProject(),return;end
            if strlength(app.CurrentSessionId)>0 && ~app.Busy
                try
                    cfg=app.readAnalysisConfig();[app.Project,~]=lfp_project_update_session(app.Project,app.CurrentSessionId,struct('analysis_config',cfg),Save=false);
                catch exception
                    app.LogMessages(end+1,1)="Session 参数未更新 | Session="+app.CurrentSessionId+" | "+string(exception.identifier)+" | "+string(exception.message);
                    app.setStatus('保存失败','当前 Session 参数无效，已保留未保存状态：'+string(exception.message),0);
                    if isgraphics(app.Figure)&&strcmp(app.Figure.Visible,'on'),uialert(app.Figure,string(exception.message),'无法保存');end
                    success = false;
                    return;
                end
            end
            try
                [~, app.Project] = lfp_save_project(app.Project);
            catch exception
                app.LogMessages(end+1,1)="项目保存失败 | "+string(exception.identifier)+" | "+string(exception.message);
                app.setStatus('保存失败',string(exception.message),0);
                rethrow(exception);
            end
            app.Dirty=false;app.updateProjectHeader();app.setStatus('就绪','项目已保存。',0);
        end

        function addSubjectDialog(app)
            if app.noProject(),app.warn('请先创建或打开项目。');return;end
            a=inputdlg({'被试编号','显示名称','分组（可选）','备注（可选）'},'添加被试',[1 32;1 32;1 32;3 32],{'P01','P01','',''});if isempty(a),return;end
            try,app.addSubjectRecord(struct('subject_id',string(a{1}),'display_name',string(a{2}),'group',string(a{3}),'notes',string(a{4})));catch e,app.showError(e,'添加被试失败');end
        end

        function addSessionDialog(app)
            if strlength(app.CurrentSubjectId)==0,app.warn('请先在左侧选择所属被试。');return;end
            a=inputdlg({'Session 稳定 ID','Session 名称/访视','日期','药物状态','刺激状态','备注'},'添加 Session',[1 34;1 34;1 34;1 34;1 34;3 34], ...
                {char(app.CurrentSubjectId+"_Baseline"),'Baseline','','','',''});if isempty(a),return;end
            info=struct('session_id',string(a{1}),'visit_label',string(a{2}),'acquisition_date',string(a{3}), ...
                'medication_state',string(a{4}),'stimulation_state',string(a{5}),'notes',string(a{6}));
            try,app.addSessionRecord(app.CurrentSubjectId,info);catch e,app.showError(e,'添加 Session 失败');end
        end

        function importCsvDialog(app)
            if strlength(app.CurrentSessionId)==0,app.warn('请先创建并选择 Session。');return;end
            [session,subject]=lfp_project_find_session(app.Project,app.CurrentSessionId);
            [file,folder]=uigetfile({'*.csv','CSV 文件'},'选择 LFP CSV（可多选）','MultiSelect','on');if isequal(file,0),return;end
            if iscell(file),paths=string(fullfile(folder,file));else,paths=string(fullfile(folder,file));end
            try
                totalChannels=0;totalSamples=0;
                for index=1:numel(paths)
                    app.setStatus('导入','正在检查 CSV '+string(index)+'/'+string(numel(paths))+'…',.05+(index-1)/max(numel(paths),1)*.8);drawnow;
                    inspection=lfp_inspect_csv(paths(index));settings=app.csvSettingsDialog(inspection,subject,session);
                    if isempty(settings),app.setStatus('就绪','已取消剩余导入。',0);return;end
                    [data,~]=app.importCsvToSession(app.CurrentSessionId,paths(index),settings);totalChannels=totalChannels+size(data.signal,2);totalSamples=max(totalSamples,size(data.signal,1));
                end
                app.setStatus('就绪',sprintf('已导入 %d 个文件、%d 通道（最长 %d 样本）。',numel(paths),totalChannels,totalSamples),0);
            catch e,app.showError(e,'导入失败');end
        end

        function settings=csvSettingsDialog(app,inspection,subject,session)
            settings=[];dg=uifigure('Name','确认 CSV 导入','WindowStyle','modal','Position',[220 140 900 650]);
            g=uigridlayout(dg,[4 1]);g.RowHeight={36,'1x',130,42};g.Padding=[8 8 8 8];
            uilabel(g,'Text',"归属："+app.Project.name+" / "+subject.subject_id+" / "+session.session_id,'FontWeight','bold');
            uitable(g,'Data',inspection.preview,'ColumnEditable',false,'RowName',[]);
            f=uigridlayout(g,[4 8]);f.RowHeight={34,34,34,42};f.ColumnWidth={80,95,80,95,80,95,95,'1x'};
            uilabel(f,'Text','格式');format=uidropdown(f,'Items',{'自动','SceneRay','通用 CSV'},'Value','自动');uilabel(f,'Text','采样率 Hz');fs=uieditfield(f,'numeric','Value',1000);uilabel(f,'Text','单位');units=uieditfield(f,'text','Value','uV');uilabel(f,'Text','时间单位');timeUnit=uidropdown(f,'Items',{'s','ms'},'Value','s');
            uilabel(f,'Text','表头行');header=uieditfield(f,'numeric','Value',inspection.headerRowSuggestion);uilabel(f,'Text','数据起始行');start=uieditfield(f,'numeric','Value',inspection.dataStartRowSuggestion);uilabel(f,'Text','时间列(0=无)');time=uieditfield(f,'numeric','Value',inspection.timeColumnSuggestion);uilabel(f,'Text','信号列');signal=uieditfield(f,'text','Value',strjoin(string(inspection.signalColumnsSuggestion),','));
            uilabel(f,'Text','通道名称');defaultNames=string(inspection.channelNamesSuggestion);if ~isempty(inspection.signalColumnsSuggestion)&&numel(defaultNames)>=max(inspection.signalColumnsSuggestion),defaultNames=defaultNames(inspection.signalColumnsSuggestion);end;channelNames=uieditfield(f,'text','Value',strjoin(defaultNames,','));channelNames.Layout.Column=[2 8];
            tip=uilabel(f,'Text',join(string(inspection.warnings),'；'),'WordWrap','on','FontColor',[.5 .3 0]);tip.Layout.Row=4;tip.Layout.Column=[1 8];
            b=uigridlayout(g,[1 3]);b.ColumnWidth={'1x',100,100};spacer=uibutton(b,'Text','');spacer.Visible='off';uibutton(b,'Text','取消','ButtonPushedFcn',@cancel);uibutton(b,'Text','确认导入','ButtonPushedFcn',@accept);
            dg.CloseRequestFcn=@cancel;uiwait(dg);if isgraphics(dg),settings=dg.UserData;delete(dg);end
            function cancel(~,~),if isgraphics(dg),dg.UserData=[];uiresume(dg);end,end
            function accept(~,~)
                cols=str2double(split(string(signal.Value),','));cols=cols(isfinite(cols));if isempty(cols),uialert(dg,'至少选择一个信号列。','导入设置');return;end
                useScene=inspection.isSceneRay;if string(format.Value)=="SceneRay",useScene=true;elseif string(format.Value)=="通用 CSV",useScene=false;end
                if ~useScene && time.Value>0 && isfinite(inspection.estimatedSamplingRateHz) && ...
                        abs(fs.Value-inspection.estimatedSamplingRateHz)/inspection.estimatedSamplingRateHz>0.01
                    choice=uiconfirm(dg,sprintf('时间列推算为 %.6g Hz，与输入的 %.6g Hz 不一致。请选择实际分析采样率。',inspection.estimatedSamplingRateHz,fs.Value), ...
                        '采样率不一致','Options',{'使用时间列推算值','保留输入值','返回修改'},'DefaultOption',1,'CancelOption',3);
                    if strcmp(choice,'返回修改'),return;elseif strcmp(choice,'使用时间列推算值'),fs.Value=inspection.estimatedSamplingRateHz;end
                end
                names=strtrim(string(split(string(channelNames.Value),',')));names=names(strlength(names)>0);
                if ~isempty(names) && numel(names)~=numel(cols),uialert(dg,'通道名称数量必须与信号列数量一致。','导入设置');return;end
                dg.UserData=struct('Inspection',inspection,'SamplingRateHz',fs.Value,'Units',string(units.Value),'TimeUnit',string(timeUnit.Value), ...
                    'HeaderRow',header.Value,'DataStartRow',start.Value,'TimeColumn',time.Value,'SignalColumns',cols(:)','ChannelLabels',names(:)','UseSceneRay',useScene);
                uiresume(dg);
            end
        end

        function editMetadataDialog(app)
            if strlength(app.CurrentSessionId)>0
                [s,~]=lfp_project_find_session(app.Project,app.CurrentSessionId);a=inputdlg({'访视标签','日期','药物状态','刺激状态','备注'},'编辑 Session',[1 36;1 36;1 36;1 36;3 36],{char(s.visit_label),char(s.acquisition_date),char(s.medication_state),char(s.stimulation_state),char(s.notes)});if isempty(a),return;end
                [app.Project,~]=lfp_project_update_session(app.Project,app.CurrentSessionId,struct('visit_label',string(a{1}),'acquisition_date',string(a{2}),'medication_state',string(a{3}),'stimulation_state',string(a{4}),'notes',string(a{5})),Save=false);
            elseif strlength(app.CurrentSubjectId)>0
                i=find(string({app.Project.subjects.subject_id})==app.CurrentSubjectId,1);s=app.Project.subjects(i);a=inputdlg({'显示名称','分组','备注'},'编辑被试',[1 36;1 36;3 36],{char(s.display_name),char(s.group),char(s.notes)});if isempty(a),return;end
                [app.Project,~]=lfp_project_update_subject(app.Project,app.CurrentSubjectId,struct('display_name',string(a{1}),'group',string(a{2}),'notes',string(a{3})),Save=false);
            else,app.warn('请选择被试或 Session。');return;end
            app.markDirty();app.refreshProject();
        end

        function removeSelectedNode(app)
            if strlength(app.CurrentSessionId)>0
                a=uiconfirm(app.Figure,'仅从项目索引移除此 Session；原始 CSV 和项目数据文件均保留。','移除 Session','Options',{'移除','取消'},'DefaultOption',2,'CancelOption',2);if strcmp(a,'取消'),return;end
                [app.Project,~]=lfp_project_remove_session(app.Project,app.CurrentSessionId,Save=false);app.CurrentSessionId="";
            elseif strlength(app.CurrentSubjectId)>0
                a=uiconfirm(app.Figure,'移除被试及其 Session 索引；所有数据文件仍保留。','移除被试','Options',{'移除','取消'},'DefaultOption',2,'CancelOption',2);if strcmp(a,'取消'),return;end
                [app.Project,~]=lfp_project_remove_subject(app.Project,app.CurrentSubjectId,Save=false);app.CurrentSubjectId="";
            else,app.warn('请选择被试或 Session。');return;end
            app.markDirty();app.refreshProject();app.clearSessionDisplay();
        end

        function saveChannelEdits(app)
            if strlength(app.CurrentSessionId)==0,return;end
            raw=app.Controls.ChannelTable.Data;if isempty(raw),return;end
            tbl=table('Size',[size(raw,1) 9],'VariableTypes',{'logical','string','string','string','string','string','string','string','string'}, ...
                'VariableNames',{'enabled','channel_id','display_label','side','region','contacts','reference','unit','quality_status'});
            for row=1:size(raw,1)
                tbl.enabled(row)=logical(raw{row,1}); tbl.channel_id(row)=string(raw{row,2}); tbl.display_label(row)=string(raw{row,4});
                tbl.side(row)=string(raw{row,5}); tbl.region(row)=string(raw{row,6}); tbl.contacts(row)=string(raw{row,7}); tbl.reference(row)=string(raw{row,8}); tbl.unit(row)=string(raw{row,12}); tbl.quality_status(row)=string(get_cell_local(raw,row,13,"unassessed"));
            end
            [app.Project,~]=lfp_project_update_channels(app.Project,app.CurrentSessionId,tbl,Save=false);app.markDirty();app.loadCurrentSession();app.refreshProject();
        end

        function selectChannelRows(app, event)
            if isempty(event.Indices)
                app.SelectedChannelRows=[]; app.SelectedChannelIds=strings(0,1);
            else
                app.SelectedChannelRows=unique(event.Indices(:,1)); rows=app.Controls.ChannelTable.Data;
                valid=app.SelectedChannelRows>=1 & app.SelectedChannelRows<=size(rows,1);
                app.SelectedChannelRows=app.SelectedChannelRows(valid);
                app.SelectedChannelIds=string(rows(app.SelectedChannelRows,2));
            end
        end

        function setSelectedChannelsEnabled(app, enabled)
            if strlength(app.CurrentSessionId)==0, app.warn('请先选择 Session。'); return; end
            ids=app.SelectedChannelIds;
            if isempty(ids) && ~isempty(app.SelectedChannelRows)
                rows=app.Controls.ChannelTable.Data;ids=string(rows(app.SelectedChannelRows,2));
            end
            if isempty(ids), app.warn('请先在通道表中选择一个或多个通道。'); return; end
            tbl=table(ids,'VariableNames',{'channel_id'}); tbl.enabled=repmat(logical(enabled),numel(ids),1);
            [app.Project,~]=lfp_project_update_channels(app.Project,app.CurrentSessionId,tbl,Save=false); app.markDirty(); app.loadCurrentSession(); app.refreshProject();
        end

        function removeSelectedChannels(app)
            if strlength(app.CurrentSessionId)==0, app.warn('请先选择 Session。'); return; end
            ids=app.SelectedChannelIds;
            if isempty(ids) && ~isempty(app.SelectedChannelRows),rows=app.Controls.ChannelTable.Data;ids=string(rows(app.SelectedChannelRows,2));end
            if isempty(ids), app.warn('请先在通道表中选择一个或多个通道。'); return; end
            answer=uiconfirm(app.Figure,'移除只会更新活动通道列表；原始缓存、CSV和历史结果会保留。','移除通道','Options',{'移除','取消'},'DefaultOption',2,'CancelOption',2);if answer~="移除",return;end
            [app.Project,~]=lfp_project_remove_channels(app.Project,app.CurrentSessionId,ids,Save=false);app.SelectedChannelRows=[];app.markDirty();app.loadCurrentSession();app.refreshProject();
        end

        function rebuildSelectedChannelCaches(app)
            if strlength(app.CurrentSessionId)==0, app.warn('请先选择 Session。'); return; end
            ids=app.SelectedChannelIds;
            if isempty(ids) && ~isempty(app.SelectedChannelRows)
                rows=app.Controls.ChannelTable.Data;ids=string(rows(app.SelectedChannelRows,2));
            end
            if isempty(ids), app.warn('请先在通道表中选择一个或多个通道。'); return; end
            try
                [app.Project,report]=lfp_project_repair_channel_caches(app.Project,app.CurrentSessionId,ids,Save=true);
                for k=1:numel(report)
                    app.LogMessages(end+1,1)="缓存修复 | Session="+app.CurrentSessionId+" Channel="+report(k).channel_id+" | "+report(k).status+" | "+report(k).message;
                end
                states=string({report.status});ok=nnz(ismember(states,["valid" "repaired_reference" "rebuilt" "rebuilt_from_source"]));
                app.Dirty=false;app.refreshProject();app.loadCurrentSession();app.refreshAnalysisView();
                app.setStatus('就绪',sprintf('缓存修复完成：%d/%d 个通道可用。',ok,numel(report)),0);
            catch e
                app.LogMessages(end+1,1)="缓存修复失败 | Session="+app.CurrentSessionId+" | "+string(e.identifier)+" | "+string(e.message);
                app.showError(e,'缓存修复失败');
            end
        end

        function onTreeSelection(app)
            if app.Busy || app.ClosingRequested, return; end
            node=app.Controls.ProjectTree.SelectedNodes;if isempty(node),return;end;info=node(1).NodeData;if ~isstruct(info)||~isfield(info,'kind'),return;end
            switch string(info.kind)
                case "project",app.CurrentSubjectId="";app.CurrentSessionId="";app.showProjectDetails();
                case "subject",app.CurrentSubjectId=string(info.id);app.CurrentSessionId="";app.showSubjectDetails();
                case "session",app.selectSession(string(info.id));
            end
            if app.CompactMode,app.NavigationOnly=false;app.applyResponsiveLayout();end
        end

        function refreshProject(app)
            if app.noProject(),app.showWelcome();return;end
            delete(app.Controls.ProjectTree.Children);root=uitreenode(app.Controls.ProjectTree,'Text',char(app.Project.name),'NodeData',struct('kind','project','id',app.Project.project_id));
            for i=1:numel(app.Project.subjects)
                subject=app.Project.subjects(i);sn=uitreenode(root,'Text',char(subject.display_name),'NodeData',struct('kind','subject','id',subject.subject_id));
                for j=1:numel(subject.sessions),session=subject.sessions(j);label=session.visit_label;if strlength(label)==0,label=session.session_id;end;uitreenode(sn,'Text',char(label+"  ["+session.status+"]"),'NodeData',struct('kind','session','id',session.session_id));end
            end
            expand(root);app.updateProjectHeader();app.refreshComparisonFilters();app.refreshComparisonBands();app.refreshComparisonCandidates();
        end

        function showProjectDetails(app)
            app.CurrentData=struct();app.CurrentRun=struct();app.CurrentResults=struct();app.Controls.Metadata.Value={char("项目："+app.Project.name);char("说明："+string(app.Project.description));char("位置："+app.Project.rootPath);sprintf('被试数：%d',numel(app.Project.subjects))};app.Controls.ChannelTable.Data=cell(0,13);app.Controls.DataContext.Text='当前：项目';app.refreshDataPreview();
        end

        function showSubjectDetails(app)
            app.CurrentData=struct();app.CurrentRun=struct();app.CurrentResults=struct();i=find(string({app.Project.subjects.subject_id})==app.CurrentSubjectId,1);if isempty(i),return;end;s=app.Project.subjects(i);app.Controls.Metadata.Value={char("被试 ID："+s.subject_id);char("显示名称："+s.display_name);char("分组："+s.group);char("备注："+s.notes);sprintf('Session 数：%d',numel(s.sessions))};app.Controls.ChannelTable.Data=cell(0,13);app.Controls.DataContext.Text=char("当前被试："+s.subject_id);app.refreshDataPreview();
        end

        function updateSessionContext(app,session,subject)
            [fsSummary,sampleSummary,durationSummary] = app.sessionSummaries(session);
            app.Controls.Metadata.Value={char("被试："+subject.subject_id);char("Session："+session.session_id);char("访视："+session.visit_label);char("状态："+session.status);char("规格："+fsSummary);char("样本："+sampleSummary+" | 时长："+durationSummary);char("日期："+session.acquisition_date+" | 药物："+session.medication_state+" | 刺激："+session.stimulation_state)};
            rows=cell(numel(session.channels),13);for k=1:numel(session.channels),c=session.channels(k);source="";if isfield(c,'source_metadata')&&isstruct(c.source_metadata)&&isfield(c.source_metadata,'source_file_name'),source=char(string(c.source_metadata.source_file_name));end;rows(k,:)={logical(get_field_local(c,'enabled',true)),char(c.channel_id),char(c.original_label),char(c.display_label),char(c.side),char(c.region),char(c.contacts),char(c.reference),double(get_field_local(c,'sampling_rate_hz',NaN)),double(get_field_local(c,'sample_count',0)),double(get_field_local(c,'time_end',NaN)-get_field_local(c,'time_start',NaN)),char(c.unit),source};end;app.Controls.ChannelTable.Data=rows;app.Controls.DataContext.Text=char(subject.subject_id+" / "+session.session_id);
            labels=app.channelLabels(session); ids=string({session.channels.channel_id})';
            enabledMask=app.sessionEnabledMask(session); enabledIds=ids(enabledMask); enabledLabels=labels(enabledMask);
            if isempty(enabledIds), enabledLabels="(无启用通道)"; end
            app.Controls.DataPreviewChannel.Items=cellstr(enabledLabels);app.Controls.DataPreviewChannel.Value=char(enabledLabels(1));
            app.refreshAnalysisChannelItems(session,labels,ids);
            app.refreshDisplayChannelList(session,ids,labels);
            app.Controls.AnalysisContext.Text=char(subject.subject_id+" / "+session.visit_label+" / "+string(numel(session.channels))+" 通道（启用 "+string(nnz(enabledMask))+"） / "+durationSummary);
            app.Controls.AnalysisEnabledCount.Text=char("启用 "+string(nnz(enabledMask))+" 通道");
            if ~app.Busy,app.Controls.RunSession.Enable=local_choice(nnz(enabledMask)>0,'on','off');end
            app.refreshDataPreview();
        end

        function [fsSummary,sampleSummary,durationSummary]=sessionSummaries(~,session)
            channels=session.channels;fs=NaN(0,1);samples=NaN(0,1);durations=NaN(0,1);
            for k=1:numel(channels)
                fs(end+1,1)=double(get_field_local(channels(k),'sampling_rate_hz',NaN)); %#ok<AGROW>
                samples(end+1,1)=double(get_field_local(channels(k),'sample_count',NaN)); %#ok<AGROW>
                durations(end+1,1)=double(get_field_local(channels(k),'time_end',NaN)-get_field_local(channels(k),'time_start',NaN)); %#ok<AGROW>
            end
            fs=unique(fs(isfinite(fs)));samples=samples(isfinite(samples));durations=durations(isfinite(durations));
            if isempty(fs),fsSummary="采样率：未知";elseif numel(fs)==1,fsSummary=string(sprintf('采样率：%.6g Hz',fs));else,fsSummary="采样率："+join(compose('%.6g',fs),'、')+" Hz（异构）";end
            if isempty(samples),sampleSummary='未知';elseif numel(unique(samples))==1,sampleSummary=string(sprintf('%.0f',samples(1)));else,sampleSummary=string(sprintf('%.0f–%.0f（异构）',min(samples),max(samples)));end
            if isempty(durations),durationSummary='未知';elseif numel(unique(durations))==1,durationSummary=string(sprintf('%.3f s',durations(1)));else,durationSummary=string(sprintf('%.3f–%.3f s（异构）',min(durations),max(durations)));end
        end

        function loadCurrentSession(app)
            app.CurrentData=struct();app.CurrentRun=struct();app.CurrentResults=struct();[session,subject]=lfp_project_find_session(app.Project,app.CurrentSessionId);if isempty(session),return;end
            app.applyConfigToControls();
            if ~isempty(session.data_refs)
                try
                    app.CurrentData=lfp_project_get_session_data(app.Project,app.CurrentSessionId);
                catch exception
                    app.LogMessages(end+1,1)="Session 数据读取失败 | Subject="+string(subject.subject_id)+" Session="+app.CurrentSessionId+" | "+string(exception.identifier)+" | "+string(exception.message);
                    % Keep a lightweight model so per-channel preview and
                    % analysis can continue through the stable channel API.
                    app.CurrentData=struct('time',[],'signal',[],'fs',NaN,'channelLabels',strings(0,1),'units',"unknown",'metadata',struct());
                end
            end
            [run,results,isCurrent]=lfp_project_latest_run(app.Project,app.CurrentSessionId,Config=app.currentSessionConfig());if ~isempty(run),app.CurrentRun=run;app.CurrentResults=results;label="结果："+run.run_id;if ~isCurrent,label=label+"（参数已过期）";end;app.Controls.ResultVersion.Text=char(label);else,app.Controls.ResultVersion.Text='结果：无';end
            app.updateSessionContext(session,subject);
        end

        function refreshDataPreview(app)
            app.clearDataPreviewAxes();
            if strlength(app.CurrentSessionId)==0 || isempty(fieldnames(app.CurrentData))
                app.Controls.DataPreviewInfo.Text='当前对象没有可预览数据。'; return;
            end
            [session,~]=lfp_project_find_session(app.Project,app.CurrentSessionId);
            if isempty(session),app.Controls.DataPreviewInfo.Text='Session 不存在。';return;end
            enabledMask=app.sessionEnabledMask(session); ids=string({session.channels.channel_id})'; labels=app.channelLabels(session);
            ids=ids(enabledMask); labels=labels(enabledMask);
            if isempty(ids)
                app.Controls.DataPreviewInfo.Text='暂无启用通道。';
                pool=app.Controls.DataPreviewAxesPool;if isempty(pool)||~isgraphics(pool(1)),pool(end+1)=uiaxes(app.Controls.DataPreviewGrid);end
                ax=pool(1);ax.Visible='on'; app.Controls.DataPreviewAxesPool=pool;app.Controls.DataPreviewAxes=ax; ax.Layout.Row=1; ax.Layout.Column=1; text(ax,.5,.5,'暂无启用通道','Units','normalized','HorizontalAlignment','center'); axis(ax,'off'); return;
            end
            n=numel(ids); grid=app.Controls.DataPreviewGrid; grid.RowHeight=repmat({125},1,n); grid.ColumnWidth={'1x'}; grid.RowSpacing=4;
            axesList=app.Controls.DataPreviewAxesPool;
            if numel(axesList)<n, axesList(end+1:n,1)=gobjects(n-numel(axesList),1); end
            errors=strings(0,1); totalSamples=0; wasDownsampled=false;
            for k=1:n
                if ~isscalar(axesList(k)) || ~isgraphics(axesList(k)), axesList(k)=uiaxes(grid); end
                ax=axesList(k); ax.Visible='on'; ax.Layout.Row=k; ax.Layout.Column=1; cla(ax,'reset');
                try
                    channelData=lfp_project_get_channel_data(app.Project,app.CurrentSessionId,ids(k));
                    t=double(channelData.time(:)); y=double(channelData.signal(:)); totalSamples=totalSamples+numel(y);
                    if isempty(t)||isempty(y), error('LFP:EmptyChannel','通道没有有效样本。'); end
                    t=t-t(1); [tPlot,yPlot,info]=lfp_downsample_envelope(t,y,12000); wasDownsampled=wasDownsampled||info.downsampled;
                    plot(ax,tPlot,yPlot,'Color',[.08 .18 .55],'LineWidth',.7); grid(ax,'on');
                    xlabel(ax,'时间 (s)'); ylabel(ax,string(get_field_local(channelData,'units',app.CurrentData.units)));
                    title(ax,string(labels(k))+" | "+sprintf('%.3f s, %d samples',t(end),numel(y)),'Interpreter','none'); xlim(ax,[t(1) t(end)]);
                catch exception
                    subjectId="";if isfield(session,'subject_id'),subjectId=string(session.subject_id);end
                    app.LogMessages(end+1,1)="通道缓存读取失败 | Subject="+subjectId+" Session="+app.CurrentSessionId+" Channel="+ids(k)+" | "+string(exception.identifier)+" | "+string(exception.message);
                    reason=app.cacheErrorSummary(exception);errors(end+1,1)=labels(k)+"："+reason;
                    text(ax,.5,.5,"缓存读取失败："+reason,'Units','normalized','HorizontalAlignment','center','Interpreter','none'); axis(ax,'off');
                end
            end
            for k=n+1:numel(axesList), if isgraphics(axesList(k)), axesList(k).Visible='off'; end, end
            app.Controls.DataPreviewAxesPool=axesList;app.Controls.DataPreviewAxes=axesList(1:n);
            suffix="";if wasDownsampled,suffix="；显示采用 min–max 抽稀";end
            message="已显示 "+string(n)+" 个启用通道，共 "+string(totalSamples)+" samples"+suffix+"。";if ~isempty(errors),message=message+" 缓存错误 "+string(numel(errors))+" 个。";end
            app.Controls.DataPreviewInfo.Text=char(message);
        end

        function refreshAnalysisView(app)
            if isempty(fieldnames(app.CurrentData)),app.clearAnalysisAxes('请选择已导入数据的 Session。');return;end
            tab=app.Controls.AnalysisResultTabs.SelectedTab;
            if tab==app.Controls.BandResultTab,name="band";elseif tab==app.Controls.SpecResultTab,name="specparam";elseif tab==app.Controls.PsdResultTab,name="psd";else,name="raw";end
            [session,~]=lfp_project_find_session(app.Project,app.CurrentSessionId);
            if isempty(session),app.clearAnalysisAxes('请选择有效 Session。');return;end
            if name=="psd", state=app.renderAllChannelPsd(session);
            elseif name=="band", state=app.renderAllChannelBands(session);
            else
                idx=app.currentChannelIndex(session); ids=string({session.channels.channel_id})';id=ids(idx);
                try
                    one=app.channelResultForId(id,idx);viewData=app.channelDataForId(id,idx);viewSession=session;viewSession.channels=session.channels(idx);
                    viewResults=struct('artifactResult',get_field_local(one,'artifactResult',struct()),'psdResult',get_field_local(one,'psdResult',struct()), ...
                        'modelResult',get_field_local(one,'modelResult',struct([])),'bandResult',get_field_local(one,'bandResult',struct()));
                    state=lfp_render_project_session_view(name,app.viewHandles(name),viewData,viewResults,viewSession,1, ...
                        MaxDisplayPoints=12000,BandMetric=string(app.Controls.BandMetric.Value));
                catch exception
                    app.LogMessages(end+1,1)="通道视图读取失败 | Session="+app.CurrentSessionId+" Channel="+id+" | "+string(exception.identifier)+" | "+string(exception.message);
                    axesToClear=[app.Controls.RawAxes app.Controls.CleanAxes app.Controls.SpecModelAxes app.Controls.SpecPeakAxes];
                    for ax=axesToClear,if isgraphics(ax),cla(ax,'reset');text(ax,.5,.5,app.cacheErrorSummary(exception),'Units','normalized','HorizontalAlignment','center','Interpreter','none');axis(ax,'off');end,end
                    state=struct('status',"error",'message',app.cacheErrorSummary(exception));
                end
            end
            app.Controls.AnalysisState.Text=char(state.message);
        end

        function view=viewHandles(app,name)
            switch name
                case "raw",view=struct('rawAxes',app.Controls.RawAxes,'cleanAxes',app.Controls.CleanAxes);
                case "psd",view=struct('axes',app.Controls.PsdAxes);
                case "specparam",view=struct('modelAxes',app.Controls.SpecModelAxes,'peakAxes',app.Controls.SpecPeakAxes,'qualityTable',app.Controls.SpecQuality);
                otherwise,view=struct('axes',app.Controls.BandAxes,'table',app.Controls.BandResultTable);
            end
        end

        function state=renderAllChannelPsd(app,session)
            ax=app.Controls.PsdAxes; cla(ax,'reset'); hold(ax,'on'); grid(ax,'on');
            ids=string({session.channels.channel_id})'; labels=app.channelLabels(session); enabled=app.sessionEnabledMask(session);
            displayIds=app.effectiveDisplayChannelIds(session);
            colors=lines(max(1,numel(displayIds))); plotted=0; invalid=strings(0,1);
            for k=1:numel(displayIds)
                id=displayIds(k); idx=find(ids==id,1); if isempty(idx)||~enabled(idx),continue;end
                one=app.channelResultForId(id,idx);
                if isempty(one)||~isfield(one,'psdResult')||~isstruct(one.psdResult)||~isfield(one.psdResult,'psd'),invalid(end+1,1)=labels(idx)+"（无 PSD）";continue;end
                psd=one.psdResult; f=double(get_field_local(psd,'frequencyHz',[])); p=double(get_field_local(psd,'psd',[]));
                if isempty(f)||isempty(p),invalid(end+1,1)=labels(idx)+"（空 PSD）";continue;end
                if size(p,1)~=numel(f)&&size(p,2)==numel(f),p=p.';end
                if size(p,1)~=numel(f),invalid(end+1,1)=labels(idx)+"（维度不匹配）";continue;end
                col=min(idx,size(p,2)); valid=isfinite(f)&f>0&isfinite(p(:,col))&p(:,col)>0;
                if nnz(valid)<2,invalid(end+1,1)=labels(idx)+"（无有效正功率）";continue;end
                plot(ax,f(valid),10*log10(p(valid,col)),'LineWidth',1.1,'Color',colors(k,:),'DisplayName',char(labels(idx)));plotted=plotted+1;
            end
            hold(ax,'off'); xlabel(ax,'频率 (Hz)'); ylabel(ax,'PSD (dB/Hz)'); title(ax,'PSD | 启用通道','Interpreter','none');
            if plotted>0,legend(ax,'show','Location','best','Interpreter','none');else, text(ax,.5,.5,'暂无可用 PSD 结果','Units','normalized','HorizontalAlignment','center');axis(ax,'off');end
            msg="已显示 "+string(plotted)+" 个通道的独立 PSD（未跨通道平均）。";if ~isempty(invalid),msg=msg+" 无效 "+string(numel(invalid))+" 个。";end
            state=struct('status',local_choice(plotted>0,"ok","empty"),'message',msg);
        end

        function state=renderAllChannelBands(app,session)
            app.clearBandAxes();
            ids=string({session.channels.channel_id})'; labels=app.channelLabels(session); enabled=app.sessionEnabledMask(session); displayIds=app.effectiveDisplayChannelIds(session);
            metric=string(app.Controls.BandMetric.Value); tables=cell(0,1);
            for k=1:numel(displayIds)
                id=displayIds(k);idx=find(ids==id,1);if isempty(idx)||~enabled(idx),continue;end;one=app.channelResultForId(id,idx);
                if isempty(one)||~isfield(one,'bandResult')||~isstruct(one.bandResult)||~isfield(one.bandResult,'table'),continue;end
                tbl=one.bandResult.table;if ~ismember(metric,string(tbl.Properties.VariableNames)),continue;end
                tbl.channelIndex(:)=idx;tbl.channelLabel(:)=labels(idx);tables{end+1,1}=tbl; %#ok<AGROW>
            end
            if isempty(tables), app.setBandEmptyState('暂无可用频带功率结果。'); app.Controls.BandResultTable.Data=cell(0,1); state=struct('status',"empty",'message',"暂无可用频带功率结果。");return;end
            allTbl=tables{1};for k=2:numel(tables),allTbl=[allTbl;tables{k}];end %#ok<AGROW>
            bandNames=unique(string(allTbl.band),'stable');n=numel(bandNames);layoutGrid=app.Controls.BandPlotGrid;layoutGrid.RowHeight=repmat({180},1,n);layoutGrid.ColumnWidth={'1x'};axesList=app.Controls.BandAxes;
            if numel(axesList)<n, axesList(end+1:n,1)=gobjects(n-numel(axesList),1); end
            colors=lines(max(1,height(allTbl)));
            for b=1:n
                if ~isscalar(axesList(b)) || ~isgraphics(axesList(b)), axesList(b)=uiaxes(layoutGrid); end
                ax=axesList(b);ax.Visible='on';cla(ax,'reset');ax.Layout.Row=b;ax.Layout.Column=1;rows=string(allTbl.band)==bandNames(b);vals=double(allTbl.(char(metric))(rows));ch=string(allTbl.channelLabel(rows));ok=isfinite(vals)&logical(allTbl.computable(rows));
                if any(ok),bar(ax,1:nnz(ok),vals(ok),'FaceColor','flat','CData',colors(1:nnz(ok),:));set(ax,'XTick',1:nnz(ok),'XTickLabel',cellstr(ch(ok)));xtickangle(ax,30);grid(ax,'on');else,text(ax,.5,.5,'该频段没有可计算值','Units','normalized','HorizontalAlignment','center');axis(ax,'off');end
                title(ax,bandNames(b)+" ["+string(allTbl.lowHz(find(rows,1)))+"–"+string(allTbl.highHz(find(rows,1)))+" Hz]",'Interpreter','none');ylabel(ax,metric,'Interpreter','none');xlabel(ax,'通道');
            end
            for b=n+1:numel(axesList), if isgraphics(axesList(b)), axesList(b).Visible='off'; end, end
            app.Controls.BandAxes=axesList;app.Controls.BandResultTable.Data=lfp_table_to_uitable_data(allTbl);app.Controls.BandResultTable.ColumnName=allTbl.Properties.VariableNames;
            state=struct('status',"ok",'message',string(numel(bandNames))+" 个频段；每个点/柱代表一个启用通道汇总值。");
        end

        function one=channelResultForId(app,id,index)
            one=[];r=app.CurrentResults;if isfield(r,'channelResults')&&~isempty(r.channelResults)
                idx=find(string({r.channelResults.channel_id})==id,1);if ~isempty(idx),one=r.channelResults(idx);return;end
            end
            if isfield(r,'psdResult')&&isstruct(r.psdResult)
                one=struct('psdResult',r.psdResult,'modelResult',r.modelResult,'bandResult',r.bandResult,'artifactResult',r.artifactResult);
                if isfield(one,'modelResult')&&numel(one.modelResult)>=index,one.modelResult=one.modelResult(index);end
            end
        end
        function data=channelDataForId(app,id,index)
            %#ok<INUSD> Index is retained for compatibility with older scripts.
            data=lfp_project_get_channel_data(app.Project,app.CurrentSessionId,id);
        end

        function cfg=readAnalysisConfig(app)
            cfg=app.currentSessionConfig();
            cfg.artifact.amplitudeZ=app.Controls.ArtifactZ.Value;cfg.artifact.derivativeZ=app.Controls.JumpZ.Value;cfg.artifact.paddingSeconds=app.Controls.Padding.Value;
            cfg.psd.method=string(app.Controls.PsdMethod.Value);cfg.psd.windowLengthSec=app.Controls.PsdWindow.Value;cfg.psd.frequencyRange=[app.Controls.PsdLow.Value app.Controls.PsdHigh.Value];cfg.psd.overlapFraction=app.Controls.PsdOverlap.Value;cfg.psd.multitaper.timeBandwidthProduct=app.Controls.PsdNW.Value;
            cfg.psd.multitaper.taperCount=round(app.Controls.PsdK.Value);cfg.fooof.aperiodicMode=string(app.Controls.SpecMode.Value);cfg.fooof.frequencyRange=[app.Controls.SpecLow.Value app.Controls.SpecHigh.Value];cfg.fooof.maxNumberPeaks=round(app.Controls.SpecPeaks.Value);
            definitions=app.readBandDefinitionsFromTable();[~,cfg.bands]=lfp_get_band_definitions(struct('bandDefinitions',definitions));cfg.bandDefinitions=definitions;cfg.bandConfigVersion="1.0";
            if isempty(cfg.bands),error('LFP:InvalidBands','至少启用一个频段。');end
            nyquist=app.sessionNyquist();
            if isfinite(nyquist) && cfg.psd.frequencyRange(2)>nyquist,error('LFP:FrequencyAboveNyquist','PSD 上限 %.3g Hz 超过启用通道的最低 Nyquist %.3g Hz。',cfg.psd.frequencyRange(2),nyquist);end
            for k=1:numel(definitions)
                if definitions(k).enabled && definitions(k).rangeHz(2)>nyquist,error('LFP:FrequencyAboveNyquist','频段 %s 上限 %.3g Hz 超过启用通道的最低 Nyquist %.3g Hz。',definitions(k).name,definitions(k).rangeHz(2));end
            end
        end

        function definitions=readBandDefinitionsFromTable(app)
            raw=app.Controls.BandTable.Data;if isempty(raw),error('LFP:InvalidBands','至少保留一个频段。');end
            definitions=repmat(struct('name',"",'rangeHz',[NaN NaN],'enabled',true),size(raw,1),1);names=strings(0,1);
            for i=1:size(raw,1)
                enabled=logical(raw{i,1});name=strtrim(string(raw{i,2}));low=double(raw{i,3});high=double(raw{i,4});
                if strlength(name)==0||any(strcmpi(names,name)),error('LFP:InvalidBands','频段名称不能为空且不能重复（不区分大小写）。');end
                if ~isfinite(low)||~isfinite(high)||low<0||high<=low,error('LFP:InvalidBands','频段 %s 的边界必须满足 0≤下限<上限。',name);end
                names(end+1,1)=name;definitions(i)=struct('name',name,'rangeHz',[low high],'enabled',enabled); %#ok<AGROW>
            end
            overlaps=strings(0,1);
            for i=1:numel(definitions)
                for j=i+1:numel(definitions)
                    if definitions(i).enabled&&definitions(j).enabled&&definitions(i).rangeHz(1)<definitions(j).rangeHz(2)&&definitions(j).rangeHz(1)<definitions(i).rangeHz(2)
                        overlaps(end+1,1)=definitions(i).name+"/"+definitions(j).name; %#ok<AGROW>
                    end
                end
            end
            if isfield(app.Controls,'BandHint')&&isgraphics(app.Controls.BandHint)
                if isempty(overlaps),app.Controls.BandHint.Text='可重叠；重叠频段不会自动相加。';
                else,app.Controls.BandHint.Text=char("提示：存在重叠频段（"+join(overlaps,", ")+"），不会自动相加。");end
            end
        end

        function c=currentSessionConfig(app)
            c=lfpDefaultConfig();
            if ~app.noProject()
                c=app.Project.defaultConfig;
                [session,~]=lfp_project_find_session(app.Project,app.CurrentSessionId);
                if ~isempty(session)&&isfield(session,'analysis_config')&&isstruct(session.analysis_config)&&~isempty(fieldnames(session.analysis_config)),c=session.analysis_config;end
            end
            if ~isfield(c,'bandDefinitions')||isempty(c.bandDefinitions),[d,~]=lfp_get_band_definitions(c);c.bandDefinitions=d;end
        end

        function nyquist=sessionNyquist(app)
            nyquist=NaN;
            if strlength(app.CurrentSessionId)>0
                [session,~]=lfp_project_find_session(app.Project,app.CurrentSessionId);if ~isempty(session),mask=app.sessionEnabledMask(session);fs=double([session.channels(mask).sampling_rate_hz]);fs=fs(isfinite(fs)&fs>0);if ~isempty(fs),nyquist=min(fs)/2;return;end,end
            end
            if isfield(app.CurrentData,'fs')&&isscalar(app.CurrentData.fs),nyquist=double(app.CurrentData.fs)/2;end
        end

        function applyConfigToControls(app)
            if app.noProject(),return;end;c=app.currentSessionConfig();app.Controls.ArtifactZ.Value=c.artifact.amplitudeZ;app.Controls.JumpZ.Value=c.artifact.derivativeZ;app.Controls.Padding.Value=c.artifact.paddingSeconds;
            app.Controls.PsdMethod.Value=char(c.psd.method);app.Controls.PsdWindow.Value=c.psd.windowLengthSec;app.Controls.PsdLow.Value=c.psd.frequencyRange(1);app.Controls.PsdHigh.Value=c.psd.frequencyRange(2);app.Controls.PsdOverlap.Value=c.psd.overlapFraction;app.Controls.PsdNW.Value=c.psd.multitaper.timeBandwidthProduct;app.Controls.PsdK.Value=c.psd.multitaper.taperCount;
            app.Controls.SpecMode.Value=char(c.fooof.aperiodicMode);app.Controls.SpecLow.Value=c.fooof.frequencyRange(1);app.Controls.SpecHigh.Value=c.fooof.frequencyRange(2);app.Controls.SpecPeaks.Value=c.fooof.maxNumberPeaks;
            [definitions,~]=lfp_get_band_definitions(c);app.Controls.BandTable.Data=band_table_data(definitions);app.SelectedBandRows=[];
        end

        function resetBandTable(app)
            d=lfpDefaultConfig();[definitions,~]=lfp_get_band_definitions(d);app.Controls.BandTable.Data=band_table_data(definitions);app.SelectedBandRows=[];if ~app.noProject(),app.refreshComparisonBands();app.markDirty();end
        end

        function saveBandTemplate(app)
            if app.noProject(),app.warn('请先创建或打开项目。');return;end
            try
                definitions=app.readBandDefinitionsFromTable();c=app.Project.defaultConfig;c.bandDefinitions=definitions;[~,c.bands]=lfp_get_band_definitions(c);c.bandConfigVersion="1.0";app.Project.defaultConfig=c;app.refreshComparisonBands();app.markDirty();app.saveProject();
            catch e,app.showError(e,'保存频段模板失败');
            end
        end

        function selectBandRows(app,event)
            if isempty(event.Indices),app.SelectedBandRows=[];else,app.SelectedBandRows=unique(event.Indices(:,1));end
        end

        function addBandRow(app)
            rows=app.Controls.BandTable.Data;name="Band "+string(size(rows,1)+1);names=string(rows(:,2));counter=1;while any(names==name),counter=counter+1;name="Band "+string(size(rows,1)+counter);end
            rows(end+1,:)={true,char(name),1,4};app.Controls.BandTable.Data=rows;app.SelectedBandRows=size(rows,1);app.markDirty();
        end

        function deleteBandRows(app)
            rows=app.Controls.BandTable.Data;idx=app.SelectedBandRows;idx=idx(idx>=1&idx<=size(rows,1));
            if isempty(idx),app.warn('请先在频段表中选择要删除的行。');return;end
            if numel(idx)>=size(rows,1),app.warn('至少保留一行频段定义。');return;end
            rows(idx,:)=[];app.Controls.BandTable.Data=rows;app.SelectedBandRows=[];app.markDirty();
        end

        function setAllBandsEnabled(app,enabled)
            rows=app.Controls.BandTable.Data;if isempty(rows),return;end
            for k=1:size(rows,1),rows{k,1}=logical(enabled);end
            app.Controls.BandTable.Data=rows;app.markDirty();
        end

        function onRun(app),try,app.runSelectedAnalysis();catch e,app.showError(e,'分析失败');end,end
        function requestCancel(app),app.CancelRequested=true;app.setStatus('正在取消','将在当前计算块结束后停止。',app.Controls.Progress.Value);end
        function progressUpdate(app,p,message),if app.CancelRequested,error('LFP:UserCancelled','用户已取消分析。');end;app.setStatus('运行中',string(message),p);drawnow limitrate;end
        function finishTask(app)
            app.Busy=false;
            if ~app.ClosingRequested
                app.updateBusyState();
            else
                fig=app.Figure;
                if app.PendingCloseSave && app.Dirty && isscalar(fig) && isgraphics(fig)
                    fig.Visible='on';
                    answer=uiconfirm(fig,'项目有未保存修改。','保存项目', ...
                        'Options',{'保存并关闭','不保存','取消'},'DefaultOption',1,'CancelOption',3);
                    if answer=="取消"
                        app.ClosingRequested=false; app.PendingCloseSave=false; app.CancelRequested=false; app.updateBusyState(); return;
                    elseif answer=="保存并关闭"
                        try
                            if ~app.saveProject()
                                app.ClosingRequested=false; app.PendingCloseSave=false; app.CancelRequested=false; app.updateBusyState(); return;
                            end
                        catch exception, app.LogMessages(end+1,1)="关闭前保存失败 | "+string(exception.identifier)+" | "+string(exception.message); app.ClosingRequested=false; app.PendingCloseSave=false; app.updateBusyState(); return; end
                    end
                end
                app.finalizeClose();
            end
        end
        function updateBusyState(app)
            enabled=local_choice(app.Busy,'off','on');
            runEnabled=enabled;
            if ~app.Busy && strlength(app.CurrentSessionId)>0
                [session,~]=lfp_project_find_session(app.Project,app.CurrentSessionId);
                if isempty(session) || ~any(app.sessionEnabledMask(session)), runEnabled='off'; end
            elseif ~app.Busy
                runEnabled='off';
            end
            app.Controls.RunSession.Enable=runEnabled;app.Controls.CompareButton.Enable=enabled;app.Controls.UnifyCompare.Enable=enabled;app.Controls.NewProject.Enable=enabled;app.Controls.OpenProject.Enable=enabled;app.Controls.Cancel.Enable=local_choice(app.Busy,'on','off');
            if isfield(app.Controls,'ProjectTree') && isgraphics(app.Controls.ProjectTree), app.Controls.ProjectTree.Enable=enabled; end
            for name=["ChannelTable" "EnableChannels" "DisableChannels" "RemoveChannels" "RebuildChannels" "ImportData" "EditMetadata" ...
                    "BandTable" "BandAdd" "BandDelete" "BandSelectAll" "BandSelectNone" "ResetBands" "SaveBandTemplate" ...
                    "ArtifactZ" "JumpZ" "Padding" "PsdMethod" "PsdWindow" "PsdLow" "PsdHigh" "PsdOverlap" "PsdNW" "PsdK" ...
                    "SpecMode" "SpecLow" "SpecHigh" "SpecPeaks" "ModuleArtifact" "ModulePsd" "ModuleSpecparam" "ModuleBand" ...
                    "AnalysisChannel" "CandidateTable" "MappingTable" "FilterSubject" "FilterVisit" "FilterStatus" ...
                    "CompareChannelLabel" "CompareGroupingBasis" "CompareMetric" "CompareBand" "CompareAggregation" "SelectFiltered" ...
                    "ClearComparison" "RemoveSelectedComparison" "AddMatchingChannels" "CompareSavePlan" "CompareSaveImage" "CompareExportData"]
                if isfield(app.Controls,char(name))&&isgraphics(app.Controls.(char(name))),app.Controls.(char(name)).Enable=enabled;end
            end
        end
        function onAnalysisChannelChanged(app)
            if app.Busy || app.ClosingRequested, return; end
            if strlength(app.CurrentSessionId)>0
                [session,~]=lfp_project_find_session(app.Project,app.CurrentSessionId); labels=app.channelLabels(session); ids=string({session.channels.channel_id})'; enabled=app.sessionEnabledMask(session); enabledIds=ids(enabled); enabledLabels=labels(enabled);
                value=string(app.Controls.AnalysisChannel.Value); idx=find(enabledLabels==value,1);
                if isempty(idx),idx=1;end
                if ~isempty(enabledIds), app.CurrentViewedChannelId=enabledIds(idx); app.CurrentChannelIndex=find(ids==app.CurrentViewedChannelId,1); else, app.CurrentChannelIndex=1; app.CurrentViewedChannelId=""; end
            else
                app.CurrentChannelIndex=1; app.CurrentViewedChannelId="";
            end
            app.refreshAnalysisView();
        end

        function refreshComparisonFilters(app)
            if app.noProject(),return;end
            subjects=string({app.Project.subjects.subject_id});visits=strings(0,1);statuses=strings(0,1);for i=1:numel(app.Project.subjects),visits=[visits;string({app.Project.subjects(i).sessions.visit_label})'];statuses=[statuses;string({app.Project.subjects(i).sessions.status})'];end %#ok<LFPS>
            app.setDropdownItems(app.Controls.FilterSubject,["全部";unique(subjects(:),'stable')]);app.setDropdownItems(app.Controls.FilterVisit,["全部";unique(visits(strlength(visits)>0),'stable')]);app.setDropdownItems(app.Controls.FilterStatus,["全部";unique(statuses(strlength(statuses)>0),'stable')]);
        end

        function refreshComparisonBands(app)
            if ~isfield(app.Controls,'CompareBand'),return;end
            names=project_band_names(app.Project);
            if isempty(names),names="beta";end
            current=string(app.Controls.CompareBand.Value);match=find(lower(names)==lower(current),1);
            if isempty(match),match=find(lower(names)=="beta",1);end
            app.Controls.CompareBand.Items=cellstr(names);app.Controls.CompareBand.Value=char(names(max(1,match)));
        end

        function refreshComparisonCandidates(app)
            if app.noProject(),app.Controls.CandidateTable.Data=cell(0,7);return;end
            app.refreshComparisonChannelLabels();
            rows=cell(0,7);sf=string(app.Controls.FilterSubject.Value);vf=string(app.Controls.FilterVisit.Value);rf=string(app.Controls.FilterStatus.Value);
            for i=1:numel(app.Project.subjects),subject=app.Project.subjects(i);if sf~="全部"&&subject.subject_id~=sf,continue;end
                for j=1:numel(subject.sessions),session=subject.sessions(j);if vf~="全部"&&session.visit_label~=vf,continue;end;if rf~="全部"&&session.status~=rf,continue;end
                    selected=any(app.CompareSelectedSessionIds==session.session_id);condition=strtrim(session.medication_state+" "+session.stimulation_state);
                    rows(end+1,:)={selected,char(subject.subject_id),char(session.session_id),char(session.visit_label),char(condition),char(session.status),char(session.session_id)}; %#ok<AGROW>
                end
            end
            app.Controls.CandidateTable.Data=rows;app.refreshSelectedSessions();
        end

        function refreshComparisonChannelLabels(app)
            if ~isfield(app.Controls,'CompareChannelLabel') || app.noProject(), return; end
            labels=strings(0,1);
            for s=1:numel(app.Project.subjects)
                for k=1:numel(app.Project.subjects(s).sessions)
                    session=app.Project.subjects(s).sessions(k);if isempty(session.channels),continue;end
                    labels=[labels;string({session.channels.original_label})']; %#ok<AGROW>
                    if isfield(session.channels,'display_label'),labels=[labels;string({session.channels.display_label})'];end %#ok<AGROW>
                end
            end
            labels=unique(labels(strlength(labels)>0),'stable');if isempty(labels),labels="(通道标签)";end
            app.setDropdownItems(app.Controls.CompareChannelLabel,labels);
        end

        function addMatchingChannels(app)
            if app.noProject() || isempty(app.CompareSelectedSessionIds), app.warn('请先选择至少一个 Session。'); return; end
            label=string(app.Controls.CompareChannelLabel.Value);if startsWith(label,'('),app.warn('请选择通道标签。');return;end
            report=lfp_match_channel_labels_across_sessions(app.Project,app.CompareSelectedSessionIds,label);
            found=report.entries(string({report.entries.status})=="found");if isempty(found),app.warn('未找到唯一匹配：缺失 '+string(report.missingCount)+'，歧义 '+string(report.ambiguousCount)+'。');return;end
            rows=app.Controls.MappingTable.Data;for k=1:numel(found),entry=found(k);same=~isempty(rows)&&any(string(rows(:,1))==entry.session_id&string(rows(:,2))==entry.channel_label);if ~same,rows(end+1,:)={char(entry.session_id),char(entry.channel_label),char(entry.channel_label)};end,end;app.Controls.MappingTable.Data=rows;
            app.setStatus('就绪',sprintf('按标签添加 %d 个通道；缺失 %d、歧义 %d。',report.foundCount,report.missingCount,report.ambiguousCount),0);
        end

        function onCandidateEdited(app,event)
            row=event.Indices(1);data=app.Controls.CandidateTable.Data;id=string(data{row,7});if logical(data{row,1}),app.CompareSelectedSessionIds=unique([app.CompareSelectedSessionIds;id],'stable');else,app.CompareSelectedSessionIds(app.CompareSelectedSessionIds==id)=[];end;app.refreshSelectedSessions();
        end
        function selectFiltered(app),data=app.Controls.CandidateTable.Data;if isempty(data),return;end;app.CompareSelectedSessionIds=unique([app.CompareSelectedSessionIds;string(data(:,7))],'stable');app.refreshComparisonCandidates();end
        function clearComparisonSelection(app),app.CompareSelectedSessionIds=strings(0,1);app.CompareGroupLabels=strings(0,1);app.refreshComparisonCandidates();end
        function removeSelectedComparison(app),selected=string(app.Controls.SelectedSessions.Value);selected=selected(selected~="(未选择)");keep=~ismember(app.CompareSelectedSessionIds,selected);app.CompareSelectedSessionIds=app.CompareSelectedSessionIds(keep);app.CompareGroupLabels=app.CompareGroupLabels(keep);app.refreshComparisonCandidates();end

        function refreshSelectedSessions(app)
            ids=app.CompareSelectedSessionIds(:);mappingCount=size(app.Controls.MappingTable.Data,1);app.Controls.SelectedCount.Text=char("已选择 "+string(mappingCount)+" 个通道条目（"+string(numel(ids))+" 个 Session，"+string(numel(unique(app.subject_ids_for_sessions(ids))))+" 个被试）");
            if isempty(ids)
                app.Controls.SelectedSessions.Items={'(未选择)'};app.Controls.SelectedSessions.Value={'(未选择)'};app.Controls.MappingTable.Data=cell(0,3);app.Controls.SelectedObjectTable.Data=cell(0,8);app.CompareGroupLabels=strings(0,1);return;
            end
            app.Controls.SelectedSessions.Items=cellstr(ids);app.Controls.SelectedSessions.Value=char(ids(1));old=app.Controls.MappingTable.Data;oldObjects=app.Controls.SelectedObjectTable.Data;mappingRows=cell(0,3);objectRows=cell(numel(ids),8);groups=strings(numel(ids),1);
            for i=1:numel(ids)
                id=ids(i);[session,subject]=lfp_project_find_session(app.Project,id);channel="";visit="";condition="";status="";subjectId="";group="Group 1";
                if ~isempty(session)
                    subjectId=string(subject.subject_id);visit=string(session.visit_label);condition=strtrim(string(session.medication_state)+" "+string(session.stimulation_state));status=string(session.status);
                    if ~isempty(session.channels),channel=string(session.channels(1).original_label);end
                    group=default_compare_group(app,session,subject);
                end
                matches=[];if ~isempty(old),matches=find(string(old(:,1))==id);end
                if isempty(matches)
                    mappingRows(end+1,:)={char(id),char(channel),char(channel)};
                else
                    for match=matches(:)', mappingRows(end+1,:)={char(id),char(old{match,2}),char(old{match,3})}; end
                end
                if ~isempty(oldObjects),match=find(string(oldObjects(:,8))==id,1);if ~isempty(match)&&size(oldObjects,2)>=7,group=string(oldObjects{match,7});end;end
                if strlength(group)==0,group="Group 1";end;groups(i)=group;objectRows(i,:)={char(subjectId),char(id),char(visit),char(condition),char(channel),char(status),char(group),char(id)};
            end
            app.CompareGroupLabels=groups;app.Controls.MappingTable.Data=mappingRows;app.Controls.SelectedObjectTable.Data=objectRows;
        end

        function onSelectedObjectEdited(app,event)
            if isempty(event.Indices),return;end;row=event.Indices(1);if size(app.Controls.SelectedObjectTable.Data,2)<8,return;end
            id=string(app.Controls.SelectedObjectTable.Data{row,8});group=string(app.Controls.SelectedObjectTable.Data{row,7});idx=find(app.CompareSelectedSessionIds==id,1);if ~isempty(idx),app.CompareGroupLabels(idx)=group;end
        end

        function ids=subject_ids_for_sessions(app,ids)
            ids=string(ids(:));out=strings(0,1);for k=1:numel(ids),[~,subject]=lfp_project_find_session(app.Project,ids(k));if ~isempty(subject),out(end+1,1)=string(subject.subject_id);end,end;ids=out;
        end

        function group=default_compare_group(app,session,subject)
            basis="custom";if isfield(app.Controls,'CompareGroupingBasis'),basis=string(app.Controls.CompareGroupingBasis.Value);end
            switch lower(basis),case "subject_group",group=string(subject.group);case "visit",group=string(session.visit_label);otherwise,group="Group 1";end
            if strlength(group)==0,group="未分组";end
        end

        function spec=readComparisonSpec(app)
            sessionIds=unique(app.CompareSelectedSessionIds(:),'stable');
            if isempty(sessionIds),error('LFP:NoSessionsSelected','请在候选表中勾选至少一个 Session。');end
            rows=app.Controls.MappingTable.Data;
            if isempty(rows),error('LFP:NoComparisonChannels','请至少添加一个 Session–Channel 比较条目。');end
            mapping=repmat(struct('session_id',"",'channel_id',"",'channel_label',"",'target_label',"",'group_label',""),0,1);
            mappedSessionIds=strings(0,1);mappingSubjects=strings(0,1);basis=string(app.Controls.CompareGroupingBasis.Value);
            for row=1:size(rows,1)
                sid=strtrim(string(rows{row,1}));
                if ~any(sessionIds==sid),continue;end
                [session,subject]=lfp_project_find_session(app.Project,sid);
                if isempty(session),error('LFP:SessionNotFound','Session ID not found: %s',sid);end
                chosen=strtrim(string(rows{row,2}));target=strtrim(string(rows{row,3}));
                if strlength(chosen)==0,error('LFP:ChannelMappingMissing','Session %s 尚未选择通道。',sid);end
                labels=string({session.channels.original_label});display=string({session.channels.display_label});idx=find(labels==chosen|display==chosen);
                if isempty(idx),error('LFP:ChannelMappingMissing','Session %s 中不存在通道 %s。',sid,chosen);end
                if numel(idx)>1,error('LFP:ChannelMappingAmbiguous','Session %s 中通道标签 %s 对应多个通道，请使用稳定 ID 或修改显示名称。',sid,chosen);end
                if isfield(session.channels(idx),'enabled') && ~session.channels(idx).enabled,error('LFP:ChannelDisabled','Session %s 的通道 %s 已停用，不能加入比较。',sid,chosen);end
                channelId=string(session.channels(idx).channel_id);
                if any(string({mapping.session_id})==sid & string({mapping.channel_id})==channelId),continue;end
                group="Group 1";sessionIndex=find(sessionIds==sid,1);if numel(app.CompareGroupLabels)>=sessionIndex,group=strtrim(string(app.CompareGroupLabels(sessionIndex)));end
                if strlength(group)==0,group="Group 1";end
                if strlength(target)==0,target=string(session.channels(idx).original_label);end
                mapping(end+1,1)=struct('session_id',sid,'channel_id',channelId,'channel_label',string(session.channels(idx).original_label),'target_label',target,'group_label',group); %#ok<AGROW>
                mappedSessionIds(end+1,1)=sid;mappingSubjects(end+1,1)=string(subject.subject_id); %#ok<AGROW>
            end
            if isempty(mapping),error('LFP:NoComparisonChannels','请至少添加一个有效的 Session–Channel 比较条目。');end
            sessionIds=unique(mappedSessionIds,'stable');subjects=unique(mappingSubjects,'stable');type="between_subjects";if numel(subjects)==1,type="within_subject";end
            groups=unique(string({mapping.group_label})','stable');defs=repmat(struct('group_label',"",'basis',basis,'session_ids',strings(0,1),'subject_ids',strings(0,1)),numel(groups),1);
            for k=1:numel(groups),mask=string({mapping.group_label})'==groups(k);defs(k).group_label=groups(k);defs(k).session_ids=unique(string({mapping(mask).session_id})','stable');defs(k).subject_ids=unique(mappingSubjects(mask),'stable');end
            spec=struct('type',type,'session_ids',sessionIds,'subject_ids',subjects,'bands',string(app.Controls.CompareBand.Value),'metric',string(app.Controls.CompareMetric.Value),'aggregation',string(app.Controls.CompareAggregation.Value),'channel_mapping',mapping,'grouping_basis',basis,'group_defs',defs,'plot_settings',struct('type',string(app.Controls.ComparePlot.Value)));
        end

        function onCompare(app,unify),try,app.compareSelected(unify);catch e,app.showError(e,'比较失败');end,end
        function renderComparison(app)
            ax=app.Controls.CompareAxes;cla(ax,'reset');if isempty(fieldnames(app.CurrentComparison)),text(ax,.5,.5,'请选择比较对象并运行比较','Units','normalized','HorizontalAlignment','center');axis(ax,'off');return;end
            mode=string(app.Controls.ComparePlot.Value);
            if mode=="分组 PSD"
                if ~isfield(app.CurrentComparison,'psd_summary')||~isstruct(app.CurrentComparison.psd_summary)||isempty(app.CurrentComparison.psd_summary.psd),text(ax,.5,.5,'没有可用 PSD 比较结果','Units','normalized','HorizontalAlignment','center');axis(ax,'off');return;end
                plotGroupedPsdComparison(app.CurrentComparison.psd_summary,Parent=ax,Visible="off");app.Controls.CompareStatus.Text=char(string(app.CurrentComparison.status)+" | 分组 PSD");return;
            elseif mode=="分组频带柱图"
                if ~isfield(app.CurrentComparison,'result_table')||isempty(app.CurrentComparison.result_table),text(ax,.5,.5,'没有可比较的频带结果','Units','normalized','HorizontalAlignment','center');axis(ax,'off');return;end
                plotGroupedBandPower(app.CurrentComparison,Parent=ax,Metric=string(app.Controls.CompareMetric.Value),Aggregation=string(app.CurrentComparison.aggregation),Visible="off");app.Controls.CompareStatus.Text=char(string(app.CurrentComparison.status)+" | 分组频带");return;
            end
            tbl=app.CurrentComparison.result_table;if isempty(tbl),text(ax,.5,.5,'没有可比较的有效结果','Units','normalized','HorizontalAlignment','center');axis(ax,'off');return;end
            labels=string(tbl.subject_id)+" / "+string(tbl.visit_label)+" / "+string(tbl.channel_label);values=double(tbl.value(:));x=(1:numel(values))';if string(app.Controls.ComparePlot.Value)=="柱状图",bar(ax,x,values,'FaceColor',[.15 .45 .75]);else,scatter(ax,x,values,60,[.1 .4 .8],'filled');end
            xticks(ax,x);xlim(ax,[.5 numel(values)+.5]);xticklabels(ax,cellstr(labels));xtickangle(ax,25);grid(ax,'on');ylabel(ax,string(tbl.metric(1))+" ("+string(tbl.unit(1))+")",'Interpreter','none');title(ax,string(app.CurrentComparison.type)+" | "+string(tbl.band(1)),'Interpreter','none');app.Controls.CompareStatus.Text=char(string(app.CurrentComparison.status)+" | "+string(height(tbl))+" 点");
        end

        function restoreLatestComparison(app)
            if ~isfield(app.Project,'comparisons')||isempty(app.Project.comparisons),return;end
            saved=app.Project.comparisons(end);app.CompareSelectedSessionIds=string(saved.session_ids(:));
            if isfield(saved,'metric')&&any(string(app.Controls.CompareMetric.Items)==string(saved.metric)),app.Controls.CompareMetric.Value=char(saved.metric);end
            if isfield(saved,'bands')&&~isempty(saved.bands)&&any(string(app.Controls.CompareBand.Items)==string(saved.bands(1))),app.Controls.CompareBand.Value=char(saved.bands(1));end
            if isfield(saved,'grouping_basis')&&any(string(app.Controls.CompareGroupingBasis.Items)==string(saved.grouping_basis)),app.Controls.CompareGroupingBasis.Value=char(saved.grouping_basis);end
            app.refreshComparisonCandidates();
            if isfield(saved,'channel_mapping')&&~isempty(saved.channel_mapping)
                rows=cell(numel(saved.channel_mapping),3);
                for i=1:numel(saved.channel_mapping),m=saved.channel_mapping(i);label="";if isfield(m,'channel_label'),label=string(m.channel_label);end;target=label;if isfield(m,'target_label')&&strlength(string(m.target_label))>0,target=string(m.target_label);end;rows(i,:)={char(string(m.session_id)),char(label),char(target)};if isfield(m,'group_label')&&i<=numel(app.CompareGroupLabels),app.CompareGroupLabels(i)=string(m.group_label);end;end
                app.refreshSelectedSessions();
                app.Controls.MappingTable.Data=rows;
            end
            if isfield(saved,'result_table')&&istable(saved.result_table)&&~isempty(saved.result_table),app.CurrentComparison=saved;app.renderComparison();end
        end

        function saveComparisonPlan(app),try,spec=app.readComparisonSpec();[app.Project,plan]=lfp_save_comparison_plan(app.Project,spec);app.Dirty=false;app.setStatus('就绪','比较方案已保存：'+plan.comparison_id,0);catch e,app.showError(e,'保存比较方案失败');end,end
        function saveComparisonImage(app),if isempty(fieldnames(app.CurrentComparison)),app.warn('尚无比较图。');return;end;[f,p]=uiputfile({'*.png','PNG 图片'},'保存比较图片','comparison.png');if isequal(f,0),return;end;try,exportgraphics(app.Controls.CompareAxes,fullfile(p,f),'Resolution',300);catch e,app.showError(e,'保存图片失败');end,end
        function exportComparisonData(app),if isempty(fieldnames(app.CurrentComparison)),app.warn('尚无比较结果。');return;end;folder=uigetdir('','选择导出目录');if isequal(folder,0),return;end;try,lfp_export_comparison(app.CurrentComparison,string(folder));app.setStatus('就绪','比较数据已导出。',0);catch e,app.showError(e,'导出失败');end,end
        function saveCurrentFigure(app)
            if isempty(fieldnames(app.CurrentData)),app.warn('当前没有可保存图形。');return;end;[f,p]=uiputfile({'*.png','PNG 图片'},'保存当前图形',char(app.CurrentSessionId+".png"));if isequal(f,0),return;end;tab=app.Controls.AnalysisResultTabs.SelectedTab;ax=app.Controls.RawAxes;if tab==app.Controls.PsdResultTab,ax=app.Controls.PsdAxes;elseif tab==app.Controls.SpecResultTab,ax=app.Controls.SpecModelAxes;elseif tab==app.Controls.BandResultTab,ax=app.Controls.BandAxes;end
            if isempty(ax)||~isgraphics(ax(1)),app.warn('当前结果页没有可导出的图形。');return;end
            try,exportgraphics(ax(1),fullfile(p,f),'Resolution',300);catch e,app.showError(e,'保存图片失败');end
        end
        function saveCurrentData(app)
            if isempty(fieldnames(app.CurrentResults)),app.warn('当前 Session 尚无分析结果。');return;end;[f,p]=uiputfile({'*.mat','MAT 文件'},'保存当前结果',char(app.CurrentSessionId+"_results.mat"));if isequal(f,0),return;end;sessionId=app.CurrentSessionId;run=app.CurrentRun;results=app.CurrentResults;data=app.CurrentData;projectId=app.Project.project_id;save(fullfile(p,f),'projectId','sessionId','run','results','data','-v7.3');
        end

        function onWorkspaceTabChanged(app),if app.Busy || app.ClosingRequested,return;end;if app.Controls.WorkspaceTabs.SelectedTab==app.Controls.CompareTab,app.refreshComparisonCandidates();elseif app.Controls.WorkspaceTabs.SelectedTab==app.Controls.AnalysisTab,app.refreshAnalysisView();end,end
        function showWorkspace(app,name),if app.noProject(),app.showWelcome();return;end;app.Controls.Welcome.Visible='off';app.Controls.WorkspaceTabs.Visible='on';switch string(name),case 'analysis',app.Controls.WorkspaceTabs.SelectedTab=app.Controls.AnalysisTab;case 'compare',app.Controls.WorkspaceTabs.SelectedTab=app.Controls.CompareTab;otherwise,app.Controls.WorkspaceTabs.SelectedTab=app.Controls.DataTab;end,end
        function toggleNavigation(app)
            if app.CompactMode
                app.NavigationOnly=~app.NavigationOnly;
            else
                app.NavigationCollapsed=~app.NavigationCollapsed;
            end
            app.applyResponsiveLayout();
        end
        function applyResponsiveLayout(app)
            if app.ClosingRequested || ~app.UiInitialized
                return;
            end
            fig=app.Figure;
            if ~isscalar(fig)
                return;
            end
            if ~isgraphics(fig)
                return;
            end
            controls=app.Controls;
            if ~isstruct(controls) || ~isscalar(controls)
                return;
            end
            if ~isfield(controls,'BodyGrid')
                return;
            end
            bodyGrid=controls.BodyGrid;
            if ~isscalar(bodyGrid)
                return;
            end
            if ~isgraphics(bodyGrid)
                return;
            end
            if app.LayoutBusy
                return;
            end
            app.LayoutBusy=true;
            cleanup=onCleanup(@()app.releaseLayoutLock()); %#ok<NASGU>
            if isfield(controls,'HostPanel')
                hostPanel=controls.HostPanel;
                if isscalar(hostPanel) && isgraphics(hostPanel)
                    hostPanel.Position=[1 1 fig.Position(3) fig.Position(4)];
                end
            end
            app.CompactMode=fig.Position(3)<1300;
            if app.CompactMode
                if isfield(controls,'CompareGrid')
                    compareGrid=controls.CompareGrid;
                    if isscalar(compareGrid) && isgraphics(compareGrid),compareGrid.RowHeight={190,190,78,'1x'};end
                end
                if app.NavigationOnly
                    bodyGrid.ColumnWidth={'1x',0};
                    app.setLayoutVisibility(controls,'NavigationPanel','on');app.setLayoutVisibility(controls,'WorkspacePanel','off');app.setLayoutText(controls,'ToggleNavigation','返回工作区');
                else
                    bodyGrid.ColumnWidth={0,'1x'};
                    app.setLayoutVisibility(controls,'NavigationPanel','off');app.setLayoutVisibility(controls,'WorkspacePanel','on');app.setLayoutText(controls,'ToggleNavigation','打开导航');
                end
            else
                if isfield(controls,'CompareGrid')
                    compareGrid=controls.CompareGrid;
                    if isscalar(compareGrid) && isgraphics(compareGrid),compareGrid.RowHeight={220,220,78,'1x'};end
                end
                app.NavigationOnly=false;
                app.setLayoutVisibility(controls,'WorkspacePanel','on');
                if app.NavigationCollapsed
                    bodyGrid.ColumnWidth={0,'1x'};
                    app.setLayoutVisibility(controls,'NavigationPanel','off');app.setLayoutText(controls,'ToggleNavigation','打开导航');
                else
                    bodyGrid.ColumnWidth={285,'1x'};
                    app.setLayoutVisibility(controls,'NavigationPanel','on');app.setLayoutText(controls,'ToggleNavigation','收起导航');
                end
            end
        end
        function releaseLayoutLock(app),app.LayoutBusy=false;end
        function setLayoutVisibility(~,controls,name,value)
            if ~isfield(controls,name),return;end
            handle=controls.(name);
            if isscalar(handle) && isgraphics(handle),handle.Visible=value;end
        end
        function setLayoutText(~,controls,name,value)
            if ~isfield(controls,name),return;end
            handle=controls.(name);
            if isscalar(handle) && isgraphics(handle),handle.Text=value;end
        end
        function showWelcome(app),app.Controls.Welcome.Visible='on';app.Controls.WorkspaceTabs.Visible='off';app.Controls.SaveProject.Enable='off';end
        function resetSelection(app),app.CurrentSubjectId="";app.CurrentSessionId="";app.CurrentData=struct();app.CurrentRun=struct();app.CurrentResults=struct();app.CurrentComparison=struct();app.CompareSelectedSessionIds=strings(0,1);app.CompareSelectedChannelKeys=strings(0,1);app.SelectedChannelRows=[];app.SelectedChannelIds=strings(0,1);app.DisplayChannelIds=strings(0,1);app.CurrentViewedChannelId="";app.AnalysisSnapshot=struct();app.applyConfigToControls();end
        function clearSessionDisplay(app),app.CurrentData=struct();app.CurrentRun=struct();app.CurrentResults=struct();app.Controls.ChannelTable.Data=cell(0,13);app.Controls.Metadata.Value={'请选择项目节点。'};app.clearAnalysisAxes('请选择 Session。');app.refreshDataPreview();end
        function clearAnalysisAxes(app,message)
            axesList=[app.Controls.RawAxes app.Controls.CleanAxes app.Controls.PsdAxes app.Controls.SpecModelAxes app.Controls.SpecPeakAxes];
            for ax=axesList,if isgraphics(ax),cla(ax,'reset');text(ax,.5,.5,message,'Units','normalized','HorizontalAlignment','center');axis(ax,'off');end,end
            app.clearBandAxes(message);app.Controls.SpecQuality.Data=cell(0,2);app.Controls.BandResultTable.Data=cell(0,1);
        end
        function clearDataPreviewAxes(app)
            if ~isfield(app.Controls,'DataPreviewGrid')||~isgraphics(app.Controls.DataPreviewGrid),return;end
            axesList=app.Controls.DataPreviewAxesPool;
            for k=1:numel(axesList),if isgraphics(axesList(k)),axesList(k).Visible='off';end,end
        end
        function clearBandAxes(app,message)
            if nargin<2,message='暂无频带功率结果。';end
            axesList=app.Controls.BandAxes;
            if isfield(app.Controls,'BandPlotGrid')&&isgraphics(app.Controls.BandPlotGrid)
                for k=1:numel(axesList),if isgraphics(axesList(k)),axesList(k).Visible='off';cla(axesList(k),'reset');end,end
                app.Controls.BandPlotGrid.RowHeight={1};
            end
            if isfield(app.Controls,'BandPlotPanel')&&isgraphics(app.Controls.BandPlotPanel)
                ax=[]; for k=1:numel(axesList),if isgraphics(axesList(k)),ax=axesList(k);break;end,end
                if isempty(ax),ax=uiaxes(app.Controls.BandPlotGrid);axesList(end+1)=ax;end
                ax.Visible='on';ax.Layout.Row=1;ax.Layout.Column=1;text(ax,.5,.5,message,'Units','normalized','HorizontalAlignment','center');axis(ax,'off');app.Controls.BandAxes=axesList;
            end
        end
        function setBandEmptyState(app,message),app.clearBandAxes(message);end
        function message=cacheErrorSummary(~,exception)
            switch string(exception.identifier)
                case "LFP:ChannelCacheReferenceMissing",message="缓存引用缺失，请重建所选缓存";
                case "LFP:ChannelCacheMissing",message="缓存文件不存在，请重建所选缓存";
                case "LFP:ChannelCacheVariableMissing",message="缓存变量或字段缺失，请检查项目版本或重建";
                case "LFP:ChannelCacheDimension",message="缓存维度不正确，请重建所选缓存";
                case "LFP:ChannelCacheVersionUnsupported",message="缓存版本不兼容，请升级或重建";
                case "LFP:ChannelCacheReadFailed",message="缓存文件无法读取，请检查权限或重建";
                case "LFP:ChannelCacheChannelMismatch",message="缓存通道 ID 不匹配，请修复索引";
                case "LFP:ChannelCacheMetadata",message="缓存采样率等元数据无效，请重建所选缓存";
                otherwise,message=string(exception.message);
            end
        end
        function updateProjectHeader(app),if app.noProject(),return;end;app.Controls.ProjectTitle.Text=char(app.Project.name);app.Controls.ProjectTitle.Tooltip=char(app.Project.rootPath);app.Controls.SaveState.Text=local_choice(app.Dirty,'未保存','已保存');app.Controls.SaveProject.Enable='on';app.Controls.NavigationHint.Text='单击节点查看；比较对象在结果比较页单独勾选。';end
        function markDirty(app),app.Dirty=true;app.updateProjectHeader();end
        function setStatus(app,task,message,progress),task=clean_text(task);message=clean_text(message);app.Controls.TaskStatus.Text=char(task);app.Controls.StageStatus.Text=char(message);app.Controls.StageStatus.Tooltip=char(message);progress=max(0,min(1,double(progress)));app.Controls.Progress.Value=progress;app.Controls.Percent.Text=sprintf('%d%%',round(progress*100));app.LogMessages(end+1,1)="["+string(datestr(now,'HH:MM:SS'))+"] "+task+" | "+message;end
        function showError(app,e,titleText)
            if app.ClosingRequested
                app.LogMessages(end+1,1)="任务结束时窗口正在关闭 | "+string(e.identifier)+" | "+string(e.message);
                return;
            end
            app.Busy=false;app.updateBusyState();app.setStatus('失败',string(e.message),0);
            if isgraphics(app.Figure)&&strcmp(app.Figure.Visible,'on'),uialert(app.Figure,string(e.message),titleText);end
        end
        function warn(app,message),app.setStatus('提示',string(message),0);if isgraphics(app.Figure)&&strcmp(app.Figure.Visible,'on'),uialert(app.Figure,string(message),'提示','Icon','warning');end,end
        function showLog(app),fig=uifigure('Name','SceneRay LFP 日志','Position',[250 180 850 520]);g=uigridlayout(fig,[1 1]);uitextarea(g,'Editable','off','Value',cellstr(app.LogMessages),'WordWrap','on');end
        function tf=noProject(app),tf=isempty(fieldnames(app.Project));end
        function labels=channelLabels(~,session),labels=strings(numel(session.channels),1);for i=1:numel(session.channels),labels(i)=string(session.channels(i).display_label);if strlength(labels(i))==0,labels(i)=string(session.channels(i).original_label);end;end,end
        function mask=sessionEnabledMask(~,session)
            mask=true(1,numel(session.channels));if ~isempty(session.channels)&&isfield(session.channels,'enabled'),mask=logical([session.channels.enabled]);end
        end
        function idx=currentChannelIndex(app,session)
            ids=string({session.channels.channel_id})';idx=find(ids==app.CurrentViewedChannelId,1);if isempty(idx)||idx<1,idx=min(max(app.CurrentChannelIndex,1),max(1,numel(ids)));end
            if idx<=numel(ids),app.CurrentChannelIndex=idx;app.CurrentViewedChannelId=ids(idx);end
        end
        function refreshAnalysisChannelItems(app,session,labels,ids)
            mask=app.sessionEnabledMask(session);ids=ids(mask);labels=labels(mask);
            if isempty(ids),items="(无)";else,items=labels;end
            current=app.CurrentViewedChannelId; if strlength(current)==0&&~isempty(ids),current=ids(min(app.CurrentChannelIndex,numel(ids)));end
            app.Controls.AnalysisChannel.Items=cellstr(items);
            if isempty(items)||items(1)=="(无)",app.Controls.AnalysisChannel.Value=char(items(1));app.CurrentViewedChannelId="";return;end
            idx=find(ids==current,1);if isempty(idx),idx=1;end;app.Controls.AnalysisChannel.Value=char(items(idx));app.CurrentChannelIndex=idx;app.CurrentViewedChannelId=ids(idx);
        end
        function refreshDisplayChannelList(app,session,ids,labels)
            enabled=app.sessionEnabledMask(session);validIds=ids(enabled);validLabels=labels(enabled);if isempty(validIds),validIds="(无)";end
            if isempty(validIds)||validIds(1)=="(无)",app.Controls.DisplayChannelList.Items={'(无)'};app.Controls.DisplayChannelList.Value={'(无)'};app.DisplayChannelIds=strings(0,1);return;end
            app.Controls.DisplayChannelList.Items=cellstr(validLabels);keep=intersect(app.DisplayChannelIds,validIds,'stable');if isempty(keep),keep=validIds;end;app.DisplayChannelIds=keep;idx=find(ismember(validIds,keep));app.Controls.DisplayChannelList.Value=cellstr(validLabels(idx));
        end
        function ids=effectiveDisplayChannelIds(app,session)
            allIds=string({session.channels.channel_id})';enabled=app.sessionEnabledMask(session);allIds=allIds(enabled);if app.DisplaySelectionExplicit,ids=intersect(app.DisplayChannelIds,allIds,'stable');else,ids=allIds;end
        end
        function onDisplayChannelsChanged(app)
            if strlength(app.CurrentSessionId)==0,return;end;[session,~]=lfp_project_find_session(app.Project,app.CurrentSessionId);if isempty(session),return;end
            vals=string(app.Controls.DisplayChannelList.Value);ids=string({session.channels.channel_id})';labels=app.channelLabels(session);mask=app.sessionEnabledMask(session);enabledIds=ids(mask);enabledLabels=labels(mask);idx=find(ismember(enabledLabels,vals));app.DisplayChannelIds=enabledIds(idx);app.DisplaySelectionExplicit=true;app.refreshAnalysisView();
        end
        function selectAllDisplayChannels(app)
            if strlength(app.CurrentSessionId)==0,return;end;[session,~]=lfp_project_find_session(app.Project,app.CurrentSessionId);if isempty(session),return;end;ids=string({session.channels.channel_id})';mask=app.sessionEnabledMask(session);app.DisplayChannelIds=ids(mask);app.DisplaySelectionExplicit=false;labels=app.channelLabels(session);app.Controls.DisplayChannelList.Value=cellstr(labels(mask));app.refreshAnalysisView();
        end
        function clearDisplayChannels(app),app.DisplayChannelIds=strings(0,1);app.DisplaySelectionExplicit=true;if isfield(app.Controls,'DisplayChannelList'),app.Controls.DisplayChannelList.Value={};end;app.refreshAnalysisView();end
        function setDropdownItems(~,control,items),current=string(control.Value);control.Items=cellstr(items);if any(items==current),control.Value=char(current);else,control.Value=char(items(1));end,end
    end
end

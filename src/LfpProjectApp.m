classdef LfpProjectApp < handle
    %LFPPROJECTAPP MATLAB-native Project/Subject/Session workspace.

    properties
        Figure
        Project = struct()
        CurrentSubjectId = ""
        CurrentSessionId = ""
        CurrentChannelIndex = 1
        CurrentRun = struct()
        CurrentResults = struct()
        CurrentData = struct()
        CurrentComparison = struct()
        CompareSelectedSessionIds = strings(0,1)
        Controls = struct()
        Dirty = false
        Busy = false
        CancelRequested = false
        ClosingRequested = false
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
            if app.ClosingRequested, return; end
            if ~force && isgraphics(app.Figure) && strcmp(app.Figure.Visible,'on')
                if app.Busy
                    answer=uiconfirm(app.Figure,'当前计算块结束后才能安全退出。是否请求取消并关闭？','关闭', ...
                        'Options',{'请求关闭','取消'},'DefaultOption',2,'CancelOption',2);
                    if strcmp(answer,'取消'), return; end
                    app.CancelRequested=true;
                end
                if app.Dirty
                    answer=uiconfirm(app.Figure,'项目有未保存修改。','保存项目', ...
                        'Options',{'保存并关闭','不保存','取消'},'DefaultOption',1,'CancelOption',3);
                    if strcmp(answer,'取消'), return; end
                    if strcmp(answer,'保存并关闭')
                        try, app.saveProject(); catch e, app.showError(e,'保存失败'); return; end
                    end
                end
            end
            app.ClosingRequested=true;
            if isgraphics(app.Figure), delete(app.Figure); end
        end

        function createProjectAt(app,root,name,description)
            if nargin<4, description=""; end
            app.Project=lfp_create_project(string(root),string(name),Description=string(description));
            app.Dirty=false; app.resetSelection(); app.refreshProject(); app.showWorkspace("data");
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
            if ~isempty(session.data_refs),error('LFP:SessionHasData','Session %s already has data.',sessionId);end
            args=namedargs2cell(settings);[data,importInfo]=lfp_import_csv_configured(path,args{:});
            app.attachDataToSession(sessionId,data);
            app.setStatus('就绪',sprintf('已导入 %d 通道、%d 样本。',size(data.signal,2),size(data.signal,1)),0);
        end

        function selectSession(app,sessionId)
            [session,subject]=lfp_project_find_session(app.Project,string(sessionId));
            if isempty(session), return; end
            app.CurrentSessionId=string(sessionId); app.CurrentSubjectId=string(subject.subject_id); app.CurrentChannelIndex=1;
            app.loadCurrentSession(); app.updateSessionContext(session,subject); app.refreshAnalysisView();
        end

        function summary=runSelectedAnalysis(app)
            if strlength(app.CurrentSessionId)==0, error('LFP:NoSessionSelected','请先选择 Session。'); end
            [session,~,~,~]=lfp_project_find_session(app.Project,app.CurrentSessionId);
            if isempty(session)||isempty(session.data_refs), error('LFP:SessionHasNoData','当前 Session 尚未导入数据。'); end
            cfg=app.readAnalysisConfig(); app.Busy=true; app.CancelRequested=false; app.updateBusyState();
            cleanup=onCleanup(@()app.finishTask()); %#ok<NASGU>
            app.setStatus("运行中","正在分析 "+app.CurrentSessionId,.02); drawnow;
            [app.Project,summary]=lfp_analyze_project(app.Project,app.CurrentSessionId,Config=cfg, ...
                ComputeSpecparam=app.Controls.ModuleSpecparam.Value,ComputeBandPower=app.Controls.ModuleBand.Value, ...
                Save=true,ProgressCallback=@(p,m)app.progressUpdate(p,m));
            app.Project.defaultConfig=cfg; lfp_save_project(app.Project); app.Dirty=false;
            app.loadCurrentSession(); app.refreshProject(); app.refreshAnalysisView();
            status=string(summary(1).status);
            if status=="failed", app.setStatus("失败",summary(1).errorMessage,1);
            elseif status=="partial_failure"
                warnings=string(summary(1).warnings);warnings=warnings(~ismissing(warnings)&strlength(warnings)>0);
                message="部分模块未完成；详情见结果版本和日志。";if ~isempty(warnings),message=join(warnings,"；");end
                app.setStatus("部分失败",message,1);
            else, app.setStatus("完成","结果已自动保存（"+status+"）。",1); end
        end

        function comparison=compareSelected(app,unify)
            if nargin<2,unify=false;end
            if isempty(app.CompareSelectedSessionIds),error('LFP:NoSessionsSelected','请在候选表中勾选至少一个 Session。');end
            spec=app.readComparisonSpec(); app.Busy=true; app.updateBusyState(); cleanup=onCleanup(@()app.finishTask()); %#ok<NASGU>
            app.setStatus("运行中","正在读取比较结果。",.1); drawnow;
            [app.Project,comparison]=lfp_compare_project(app.Project,spec,Config=app.Project.defaultConfig, ...
                ComputeMissing=true,UnifyParameters=logical(unify),Save=true);
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
            app.Figure=uifigure('Name','SceneRay LFP 项目分析','Visible',char(visible), ...
                'Position',[80 60 1500 900],'CloseRequestFcn',@(~,~)app.close(false), ...
                'AutoResizeChildren','off','SizeChangedFcn',@(~,~)app.applyResponsiveLayout());
            host=uipanel(app.Figure,'BorderType','none','Units','pixels','Position',[1 1 1500 900]);app.Controls.HostPanel=host;
            root=uigridlayout(host,[3 1]);app.Controls.RootGrid=root;root.RowHeight={54,'1x',32};root.Padding=[8 8 8 8];root.RowSpacing=6;
            app.buildToolbar(root);body=uigridlayout(root,[1 2]);body.Layout.Row=2;body.ColumnWidth={285,'1x'};body.Padding=[0 0 0 0];body.ColumnSpacing=8;app.Controls.BodyGrid=body;
            app.buildNavigation(body);app.buildWorkspace(body);app.buildStatusbar(root);app.applyResponsiveLayout();
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
            uibutton(p,'Text','单次分析','ButtonPushedFcn',@(~,~)app.showWorkspace("analysis"));
            uibutton(p,'Text','结果比较','ButtonPushedFcn',@(~,~)app.showWorkspace("compare"));
            app.Controls.NavigationHint=uilabel(g,'Text','请先新建或打开项目。','WordWrap','on','FontColor',[.35 .35 .35]);
        end

        function buildWorkspace(app,parent)
            holder=uipanel(parent,'BorderType','none');holder.Layout.Column=2;app.Controls.WorkspacePanel=holder;
            hg=uigridlayout(holder,[1 1]);hg.Padding=[0 0 0 0];
            app.Controls.Welcome=uipanel(hg,'BorderType','none');
            app.Controls.Welcome.Layout.Row=1;app.Controls.Welcome.Layout.Column=1;
            wg=uigridlayout(app.Controls.Welcome,[5 3]);wg.RowHeight={'1x',60,44,44,'1x'};wg.ColumnWidth={'1x',360,'1x'};
            t=uilabel(wg,'Text','SceneRay LFP 项目分析','FontSize',24,'FontWeight','bold','HorizontalAlignment','center');t.Layout.Row=2;t.Layout.Column=2;
            n=uilabel(wg,'Text','从空白项目开始，或继续已有项目。无需预先准备工作区变量。','HorizontalAlignment','center','WordWrap','on');n.Layout.Row=3;n.Layout.Column=2;
            a=uigridlayout(wg,[1 2]);a.Layout.Row=4;a.Layout.Column=2;a.ColumnWidth={'1x','1x'};
            uibutton(a,'Text','新建项目','ButtonPushedFcn',@(~,~)app.newProjectDialog());uibutton(a,'Text','打开项目','ButtonPushedFcn',@(~,~)app.openProjectDialog());
            app.Controls.WorkspaceTabs=uitabgroup(hg,'Visible','off','SelectionChangedFcn',@(~,~)app.onWorkspaceTabChanged());
            app.Controls.WorkspaceTabs.Layout.Row=1;app.Controls.WorkspaceTabs.Layout.Column=1;
            app.Controls.DataTab=uitab(app.Controls.WorkspaceTabs,'Title','数据管理');app.Controls.AnalysisTab=uitab(app.Controls.WorkspaceTabs,'Title','单次分析');app.Controls.CompareTab=uitab(app.Controls.WorkspaceTabs,'Title','结果比较');
            app.buildDataPage(app.Controls.DataTab);app.buildAnalysisPage(app.Controls.AnalysisTab);app.buildComparePage(app.Controls.CompareTab);
        end

        function buildDataPage(app,parent)
            g=uigridlayout(parent,[3 1]);g.RowHeight={44,150,'1x'};g.Padding=[8 8 8 8];
            a=uigridlayout(g,[1 6]);a.ColumnWidth={110,110,110,110,110,'1x'};a.Padding=[0 0 0 0];
            app.Controls.AddSubject=uibutton(a,'Text','添加被试','ButtonPushedFcn',@(~,~)app.addSubjectDialog());
            app.Controls.AddSession=uibutton(a,'Text','添加 Session','ButtonPushedFcn',@(~,~)app.addSessionDialog());
            app.Controls.ImportData=uibutton(a,'Text','导入数据','ButtonPushedFcn',@(~,~)app.importCsvDialog());
            app.Controls.EditMetadata=uibutton(a,'Text','编辑信息','ButtonPushedFcn',@(~,~)app.editMetadataDialog());
            app.Controls.RemoveNode=uibutton(a,'Text','移除','ButtonPushedFcn',@(~,~)app.removeSelectedNode());
            app.Controls.DataContext=uilabel(a,'Text','选择项目节点开始。','HorizontalAlignment','right');
            app.Controls.Metadata=uitextarea(g,'Editable','off','Value',{'尚未选择对象。'},'WordWrap','on');
            content=uigridlayout(g,[1 2]);content.ColumnWidth={520,'1x'};content.Padding=[0 0 0 0];
            cp=uipanel(content,'Title','通道信息（原始名称和 ID 不可修改）');cg=uigridlayout(cp,[2 1]);cg.RowHeight={'1x',32};cg.Padding=[4 4 4 4];
            app.Controls.ChannelTable=uitable(cg,'Data',cell(0,8),'ColumnName',{'ID','原始名称','显示名称','侧别','脑区','触点','参考','单位'}, ...
                'ColumnEditable',[false false true true true true true false],'RowName',[],'CellEditCallback',@(~,~)app.saveChannelEdits());
            app.Controls.ChannelHint=uilabel(cg,'Text','编辑显示名称、侧别、脑区或参考后保存项目；不会改变原始数据。','FontColor',[.35 .35 .35]);
            pp=uipanel(content,'Title','完整记录预览');pg=uigridlayout(pp,[2 1]);pg.RowHeight={34,'1x'};pg.Padding=[4 4 4 4];
            top=uigridlayout(pg,[1 3]);top.ColumnWidth={70,180,'1x'};top.Padding=[0 0 0 0];uilabel(top,'Text','通道');
            app.Controls.DataPreviewChannel=uidropdown(top,'Items',{'(无)'},'ValueChangedFcn',@(~,~)app.refreshDataPreview());app.Controls.DataPreviewInfo=uilabel(top,'Text','','HorizontalAlignment','right');
            app.Controls.DataPreviewAxes=uiaxes(pg);
        end

        function buildAnalysisPage(app,parent)
            g=uigridlayout(parent,[5 1]);g.RowHeight={34,38,132,42,'1x'};g.Padding=[8 8 8 8];g.RowSpacing=5;
            app.Controls.AnalysisContext=uilabel(g,'Text','请选择包含数据的 Session。','FontWeight','bold');
            m=uigridlayout(g,[1 6]);m.ColumnWidth={95,95,110,110,'1x',170};m.Padding=[0 0 0 0];
            app.Controls.ModuleArtifact=uicheckbox(m,'Text','伪影处理','Value',true,'Enable','off','Tooltip','固定前置步骤');
            app.Controls.ModulePsd=uicheckbox(m,'Text','PSD','Value',true,'Enable','off','Tooltip','固定前置步骤');
            app.Controls.ModuleSpecparam=uicheckbox(m,'Text','specparam','Value',true);app.Controls.ModuleBand=uicheckbox(m,'Text','频带功率','Value',true);uilabel(m,'Text','');
            app.Controls.AnalysisChannel=uidropdown(m,'Items',{'(无)'},'ValueChangedFcn',@(~,~)app.onAnalysisChannelChanged());
            app.buildAnalysisSettings(g);
            r=uigridlayout(g,[1 7]);r.ColumnWidth={130,80,95,110,110,'1x',210};r.Padding=[0 0 0 0];
            app.Controls.RunSession=uibutton(r,'Text','运行所选分析','ButtonPushedFcn',@(~,~)app.onRun());
            app.Controls.Cancel=uibutton(r,'Text','取消','Enable','off','ButtonPushedFcn',@(~,~)app.requestCancel());
            uibutton(r,'Text','查看日志','ButtonPushedFcn',@(~,~)app.showLog());
            app.Controls.SaveFigure=uibutton(r,'Text','保存图片','ButtonPushedFcn',@(~,~)app.saveCurrentFigure());app.Controls.SaveResult=uibutton(r,'Text','保存数据','ButtonPushedFcn',@(~,~)app.saveCurrentData());
            app.Controls.AnalysisState=uilabel(r,'Text','未运行','HorizontalAlignment','right');app.Controls.ResultVersion=uilabel(r,'Text','结果：无','HorizontalAlignment','right');
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
            bt=uitab(tabs,'Title','频带功率');b=uigridlayout(bt,[2 4]);b.RowHeight={34,34};b.ColumnWidth={90,180,90,'1x'};
            uilabel(b,'Text','显示指标');app.Controls.BandMetric=uidropdown(b,'Items',{'totalPower','relativePower','logTotalPower','aperiodicPower','periodicPower'},'Value','totalPower','ValueChangedFcn',@(~,~)app.refreshAnalysisView());uilabel(b,'Text','频段范围');uilabel(b,'Text','来自项目配置；超出 PSD 范围会标记为不可计算。');
        end

        function buildAnalysisResults(app,parent)
            tabs=uitabgroup(parent,'SelectionChangedFcn',@(~,~)app.refreshAnalysisView());tabs.Layout.Row=5;app.Controls.AnalysisResultTabs=tabs;
            app.Controls.RawResultTab=uitab(tabs,'Title','原始信号与伪影');r=uigridlayout(app.Controls.RawResultTab,[2 1]);r.RowHeight={'1x','1x'};app.Controls.RawAxes=uiaxes(r);app.Controls.CleanAxes=uiaxes(r);
            app.Controls.PsdResultTab=uitab(tabs,'Title','PSD');pg=uigridlayout(app.Controls.PsdResultTab,[1 1]);pg.Padding=[8 8 8 8];app.Controls.PsdAxes=uiaxes(pg);
            app.Controls.SpecResultTab=uitab(tabs,'Title','specparam');s=uigridlayout(app.Controls.SpecResultTab,[2 2]);s.RowHeight={'1x','1x'};s.ColumnWidth={'1x',240};app.Controls.SpecModelAxes=uiaxes(s);app.Controls.SpecPeakAxes=uiaxes(s);app.Controls.SpecPeakAxes.Layout.Row=2;app.Controls.SpecQuality=uitable(s,'Data',cell(0,2),'ColumnName',{'参数','值'},'RowName',[]);app.Controls.SpecQuality.Layout.Row=[1 2];app.Controls.SpecQuality.Layout.Column=2;
            app.Controls.BandResultTab=uitab(tabs,'Title','频带功率');b=uigridlayout(app.Controls.BandResultTab,[1 2]);b.ColumnWidth={'1x',420};app.Controls.BandAxes=uiaxes(b);app.Controls.BandResultTable=uitable(b,'Data',cell(0,1),'RowName',[]);
        end

        function buildComparePage(app,parent)
            g=uigridlayout(parent,[4 1]);app.Controls.CompareGrid=g;g.RowHeight={130,112,72,'1x'};g.Padding=[8 8 8 8];g.RowSpacing=6;
            cp=uipanel(g,'Title','比较候选（筛选不会清除已选择对象）');c=uigridlayout(cp,[2 8]);c.RowHeight={32,'1x'};c.ColumnWidth={45,110,45,110,65,110,110,'1x'};
            uilabel(c,'Text','被试');app.Controls.FilterSubject=uidropdown(c,'Items',{'全部'},'ValueChangedFcn',@(~,~)app.refreshComparisonCandidates());uilabel(c,'Text','访视');app.Controls.FilterVisit=uidropdown(c,'Items',{'全部'},'ValueChangedFcn',@(~,~)app.refreshComparisonCandidates());uilabel(c,'Text','分析状态');app.Controls.FilterStatus=uidropdown(c,'Items',{'全部'},'ValueChangedFcn',@(~,~)app.refreshComparisonCandidates());app.Controls.SelectFiltered=uibutton(c,'Text','全选筛选结果','ButtonPushedFcn',@(~,~)app.selectFiltered());app.Controls.ClearComparison=uibutton(c,'Text','清空选择','ButtonPushedFcn',@(~,~)app.clearComparisonSelection());
            app.Controls.CandidateTable=uitable(c,'Data',cell(0,7),'ColumnName',{'选择','被试','Session','访视','条件','结果状态','稳定 ID'},'ColumnEditable',[true false false false false false false],'RowName',[],'CellEditCallback',@(~,e)app.onCandidateEdited(e));app.Controls.CandidateTable.Layout.Row=2;app.Controls.CandidateTable.Layout.Column=[1 8];
            sp=uipanel(g,'Title','已选择对象与通道映射');s=uigridlayout(sp,[1 2]);s.ColumnWidth={280,'1x'};left=uigridlayout(s,[2 1]);left.RowHeight={'1x',30};left.Padding=[0 0 0 0];app.Controls.SelectedSessions=uilistbox(left,'Items',{'(未选择)'},'Value',{'(未选择)'},'Multiselect','on');lb=uigridlayout(left,[1 2]);lb.ColumnWidth={100,'1x'};lb.Padding=[0 0 0 0];app.Controls.RemoveSelectedComparison=uibutton(lb,'Text','移除所选','ButtonPushedFcn',@(~,~)app.removeSelectedComparison());app.Controls.SelectedCount=uilabel(lb,'Text','已选择 0 条','HorizontalAlignment','right');app.Controls.MappingTable=uitable(s,'Data',cell(0,3),'ColumnName',{'Session ID','选用通道','比较标签'},'ColumnEditable',[false true true],'RowName',[]);
            x=uigridlayout(g,[2 6]);x.RowHeight={32,32};x.ColumnWidth={55,120,65,120,120,'1x'};x.Padding=[0 0 0 0];
            uilabel(x,'Text','指标');app.Controls.CompareMetric=uidropdown(x,'Items',{'totalPower','relativePower','logTotalPower','aperiodicPower','periodicPower'},'Value','totalPower');uilabel(x,'Text','频段');app.Controls.CompareBand=uidropdown(x,'Items',{'delta','theta','alpha','beta','lowGamma','highGamma'},'Value','beta');app.Controls.CompareButton=uibutton(x,'Text','比较','ButtonPushedFcn',@(~,~)app.onCompare(false));app.Controls.CompareStatus=uilabel(x,'Text','未比较');
            uilabel(x,'Text','图形');app.Controls.ComparePlot=uidropdown(x,'Items',{'点图','柱状图'},'Value','点图','ValueChangedFcn',@(~,~)app.renderComparison());uilabel(x,'Text','汇总');app.Controls.CompareAggregation=uidropdown(x,'Items',{'session'},'Value','session');app.Controls.UnifyCompare=uibutton(x,'Text','统一参数重算','ButtonPushedFcn',@(~,~)app.onCompare(true));
            res=uigridlayout(g,[1 2]);res.ColumnWidth={'1x',190};app.Controls.CompareAxes=uiaxes(res);tools=uigridlayout(res,[6 1]);tools.RowHeight={38,38,38,38,'1x',60};app.Controls.CompareSaveImage=uibutton(tools,'Text','保存图片','ButtonPushedFcn',@(~,~)app.saveComparisonImage());app.Controls.CompareExportData=uibutton(tools,'Text','导出比较数据','ButtonPushedFcn',@(~,~)app.exportComparisonData());app.Controls.CompareSavePlan=uibutton(tools,'Text','保存比较方案','ButtonPushedFcn',@(~,~)app.saveComparisonPlan());app.Controls.CompareDetails=uilabel(tools,'Text','缺失值不补零；跨被试不会连接为同一患者。','WordWrap','on','FontColor',[.35 .35 .35]);
        end

        function buildStatusbar(app,parent)
            p=uipanel(parent,'BorderType','none');p.Layout.Row=3;g=uigridlayout(p,[1 4]);g.ColumnWidth={90,'1x',230,90};g.Padding=[2 0 2 0];app.Controls.TaskStatus=uilabel(g,'Text','就绪','FontWeight','bold');app.Controls.StageStatus=uilabel(g,'Text','');app.Controls.Progress=uigauge(g,'linear','Limits',[0 1],'Value',0,'MajorTicks',[],'MinorTicks',[]);app.Controls.Percent=uilabel(g,'Text','0%','HorizontalAlignment','right');
        end

        function newProjectDialog(app)
            a=inputdlg({'项目名称','可选描述'},'新建项目',[1 45;3 45],{'Human LFP project',''});if isempty(a),return;end
            root=uigetdir('','选择项目保存位置');if isequal(root,0),return;end
            try,app.createProjectAt(root,string(a{1}),string(a{2}));catch e,app.showError(e,'新建项目失败');end
        end

        function openProjectDialog(app)
            root=uigetdir('','选择包含 project.mat 的项目目录');if isequal(root,0),return;end
            try,app.loadProjectFrom(root);catch e,app.showError(e,'打开项目失败');end
        end

        function saveProject(app)
            if app.noProject(),return;end
            lfp_save_project(app.Project);app.Dirty=false;app.updateProjectHeader();app.setStatus('就绪','项目已保存。',0);
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
            if ~isempty(session.data_refs),app.warn('当前 Session 已有数据；如需导入另一记录，请新建 Session。');return;end
            [file,folder]=uigetfile({'*.csv','CSV 文件'},'选择 LFP CSV');if isequal(file,0),return;end
            path=string(fullfile(folder,file));
            try
                app.setStatus('导入','正在检查 CSV…',.05);drawnow;
                inspection=lfp_inspect_csv(path);settings=app.csvSettingsDialog(inspection,subject,session);
                if isempty(settings),app.setStatus('就绪','已取消导入。',0);return;end
                [data,~]=app.importCsvToSession(app.CurrentSessionId,path,settings);
                app.setStatus('就绪',sprintf('已导入 %d 通道、%d 样本。',size(data.signal,2),size(data.signal,1)),0);
            catch e,app.showError(e,'导入失败');end
        end

        function settings=csvSettingsDialog(app,inspection,subject,session)
            settings=[];dg=uifigure('Name','确认 CSV 导入','WindowStyle','modal','Position',[220 140 900 650]);
            g=uigridlayout(dg,[4 1]);g.RowHeight={36,'1x',130,42};g.Padding=[8 8 8 8];
            uilabel(g,'Text',"归属："+app.Project.name+" / "+subject.subject_id+" / "+session.session_id,'FontWeight','bold');
            uitable(g,'Data',inspection.preview,'ColumnEditable',false,'RowName',[]);
            f=uigridlayout(g,[3 8]);f.RowHeight={34,34,34};f.ColumnWidth={80,95,80,95,80,95,95,'1x'};
            uilabel(f,'Text','格式');format=uidropdown(f,'Items',{'自动','SceneRay','通用 CSV'},'Value','自动');uilabel(f,'Text','采样率 Hz');fs=uieditfield(f,'numeric','Value',1000);uilabel(f,'Text','单位');units=uieditfield(f,'text','Value','uV');uilabel(f,'Text','时间单位');timeUnit=uidropdown(f,'Items',{'s','ms'},'Value','s');
            uilabel(f,'Text','表头行');header=uieditfield(f,'numeric','Value',inspection.headerRowSuggestion);uilabel(f,'Text','数据起始行');start=uieditfield(f,'numeric','Value',inspection.dataStartRowSuggestion);uilabel(f,'Text','时间列(0=无)');time=uieditfield(f,'numeric','Value',inspection.timeColumnSuggestion);uilabel(f,'Text','信号列');signal=uieditfield(f,'text','Value',strjoin(string(inspection.signalColumnsSuggestion),','));
            tip=uilabel(f,'Text',join(string(inspection.warnings),'；'),'WordWrap','on','FontColor',[.5 .3 0]);tip.Layout.Row=3;tip.Layout.Column=[1 8];
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
                dg.UserData=struct('Inspection',inspection,'SamplingRateHz',fs.Value,'Units',string(units.Value),'TimeUnit',string(timeUnit.Value), ...
                    'HeaderRow',header.Value,'DataStartRow',start.Value,'TimeColumn',time.Value,'SignalColumns',cols(:)','UseSceneRay',useScene);
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
            tbl=cell2table(raw,'VariableNames',{'channel_id','original_label','display_label','side','region','contacts','reference','unit'});
            [app.Project,~]=lfp_project_update_channels(app.Project,app.CurrentSessionId,tbl,Save=false);app.markDirty();app.loadCurrentSession();app.refreshProject();
        end

        function onTreeSelection(app)
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
            expand(root);app.updateProjectHeader();app.refreshComparisonFilters();app.refreshComparisonCandidates();
        end

        function showProjectDetails(app)
            app.CurrentData=struct();app.CurrentRun=struct();app.CurrentResults=struct();app.Controls.Metadata.Value={char("项目："+app.Project.name);char("说明："+string(app.Project.description));char("位置："+app.Project.rootPath);sprintf('被试数：%d',numel(app.Project.subjects))};app.Controls.ChannelTable.Data=cell(0,8);app.Controls.DataContext.Text='当前：项目';app.refreshDataPreview();
        end

        function showSubjectDetails(app)
            app.CurrentData=struct();app.CurrentRun=struct();app.CurrentResults=struct();i=find(string({app.Project.subjects.subject_id})==app.CurrentSubjectId,1);if isempty(i),return;end;s=app.Project.subjects(i);app.Controls.Metadata.Value={char("被试 ID："+s.subject_id);char("显示名称："+s.display_name);char("分组："+s.group);char("备注："+s.notes);sprintf('Session 数：%d',numel(s.sessions))};app.Controls.ChannelTable.Data=cell(0,8);app.Controls.DataContext.Text=char("当前被试："+s.subject_id);app.refreshDataPreview();
        end

        function updateSessionContext(app,session,subject)
            duration=NaN;fs=NaN;samples=0;if ~isempty(session.data_refs),r=session.data_refs(1);duration=r.time_end-r.time_start;fs=r.fs;samples=r.sample_count;end
            app.Controls.Metadata.Value={char("被试："+subject.subject_id);char("Session："+session.session_id);char("访视："+session.visit_label);char("状态："+session.status);sprintf('采样率：%.6g Hz | 样本：%d | 时长：%.3f s',fs,samples,duration);char("日期："+session.acquisition_date+" | 药物："+session.medication_state+" | 刺激："+session.stimulation_state)};
            rows=cell(numel(session.channels),8);for k=1:numel(session.channels),c=session.channels(k);rows(k,:)={char(c.channel_id),char(c.original_label),char(c.display_label),char(c.side),char(c.region),char(c.contacts),char(c.reference),char(c.unit)};end;app.Controls.ChannelTable.Data=rows;app.Controls.DataContext.Text=char(subject.subject_id+" / "+session.session_id);
            labels=app.channelLabels(session);if isempty(labels),labels="(无)";end;app.Controls.DataPreviewChannel.Items=cellstr(labels);app.Controls.DataPreviewChannel.Value=char(labels(1));app.Controls.AnalysisChannel.Items=cellstr(labels);app.Controls.AnalysisChannel.Value=char(labels(min(app.CurrentChannelIndex,numel(labels))));
            app.Controls.AnalysisContext.Text=char(subject.subject_id+" / "+session.visit_label+" / "+string(numel(session.channels))+" 通道 / "+sprintf('%.3f s',duration));app.refreshDataPreview();
        end

        function loadCurrentSession(app)
            app.CurrentData=struct();app.CurrentRun=struct();app.CurrentResults=struct();[session,subject]=lfp_project_find_session(app.Project,app.CurrentSessionId);if isempty(session),return;end
            if ~isempty(session.data_refs),app.CurrentData=lfp_project_get_session_data(app.Project,app.CurrentSessionId);end
            [run,results,isCurrent]=lfp_project_latest_run(app.Project,app.CurrentSessionId);if ~isempty(run),app.CurrentRun=run;app.CurrentResults=results;label="结果："+run.run_id;if ~isCurrent,label=label+"（参数已过期）";end;app.Controls.ResultVersion.Text=char(label);else,app.Controls.ResultVersion.Text='结果：无';end
            app.updateSessionContext(session,subject);
        end

        function refreshDataPreview(app)
            ax=app.Controls.DataPreviewAxes;cla(ax,'reset');if isempty(fieldnames(app.CurrentData)),text(ax,.5,.5,'当前对象没有可预览数据','Units','normalized','HorizontalAlignment','center');axis(ax,'off');return;end
            idx=find(string(app.Controls.DataPreviewChannel.Items)==string(app.Controls.DataPreviewChannel.Value),1);if isempty(idx),idx=1;end
            [t,y,info]=lfp_downsample_envelope(double(app.CurrentData.time(:)),double(app.CurrentData.signal(:,idx)),12000);plot(ax,t,y,'k');grid(ax,'on');xlabel(ax,'时间 (s)');ylabel(ax,string(app.CurrentData.units));title(ax,string(app.Controls.DataPreviewChannel.Value),'Interpreter','none');suffix="";if info.downsampled,suffix=" | 显示用 min-max 抽稀";end;app.Controls.DataPreviewInfo.Text=char(string(size(app.CurrentData.signal,1))+" 样本"+suffix);
        end

        function refreshAnalysisView(app)
            if isempty(fieldnames(app.CurrentData)),app.clearAnalysisAxes('请选择已导入数据的 Session。');return;end
            tab=app.Controls.AnalysisResultTabs.SelectedTab;
            if tab==app.Controls.BandResultTab,name="band";elseif tab==app.Controls.SpecResultTab,name="specparam";elseif tab==app.Controls.PsdResultTab,name="psd";else,name="raw";end
            [session,~]=lfp_project_find_session(app.Project,app.CurrentSessionId);
            state=lfp_render_project_session_view(name,app.viewHandles(name),app.CurrentData,app.CurrentResults,session,app.CurrentChannelIndex, ...
                MaxDisplayPoints=12000,BandMetric=string(app.Controls.BandMetric.Value));
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

        function cfg=readAnalysisConfig(app)
            cfg=app.Project.defaultConfig;cfg.artifact.amplitudeZ=app.Controls.ArtifactZ.Value;cfg.artifact.derivativeZ=app.Controls.JumpZ.Value;cfg.artifact.paddingSeconds=app.Controls.Padding.Value;
            cfg.psd.method=string(app.Controls.PsdMethod.Value);cfg.psd.windowLengthSec=app.Controls.PsdWindow.Value;cfg.psd.frequencyRange=[app.Controls.PsdLow.Value app.Controls.PsdHigh.Value];cfg.psd.overlapFraction=app.Controls.PsdOverlap.Value;cfg.psd.multitaper.timeBandwidthProduct=app.Controls.PsdNW.Value;
            cfg.psd.multitaper.taperCount=round(app.Controls.PsdK.Value);cfg.fooof.aperiodicMode=string(app.Controls.SpecMode.Value);cfg.fooof.frequencyRange=[app.Controls.SpecLow.Value app.Controls.SpecHigh.Value];cfg.fooof.maxNumberPeaks=round(app.Controls.SpecPeaks.Value);
            if ~isempty(fieldnames(app.CurrentData))&&cfg.psd.frequencyRange(2)>app.CurrentData.fs/2,error('LFP:FrequencyAboveNyquist','PSD 上限 %.3g Hz 超过 Nyquist %.3g Hz。',cfg.psd.frequencyRange(2),app.CurrentData.fs/2);end
        end

        function applyConfigToControls(app)
            if app.noProject(),return;end;c=app.Project.defaultConfig;app.Controls.ArtifactZ.Value=c.artifact.amplitudeZ;app.Controls.JumpZ.Value=c.artifact.derivativeZ;app.Controls.Padding.Value=c.artifact.paddingSeconds;
            app.Controls.PsdMethod.Value=char(c.psd.method);app.Controls.PsdWindow.Value=c.psd.windowLengthSec;app.Controls.PsdLow.Value=c.psd.frequencyRange(1);app.Controls.PsdHigh.Value=c.psd.frequencyRange(2);app.Controls.PsdOverlap.Value=c.psd.overlapFraction;app.Controls.PsdNW.Value=c.psd.multitaper.timeBandwidthProduct;app.Controls.PsdK.Value=c.psd.multitaper.taperCount;
            app.Controls.SpecMode.Value=char(c.fooof.aperiodicMode);app.Controls.SpecLow.Value=c.fooof.frequencyRange(1);app.Controls.SpecHigh.Value=c.fooof.frequencyRange(2);app.Controls.SpecPeaks.Value=c.fooof.maxNumberPeaks;
        end

        function onRun(app),try,app.runSelectedAnalysis();catch e,app.showError(e,'分析失败');end,end
        function requestCancel(app),app.CancelRequested=true;app.setStatus('正在取消','将在当前计算块结束后停止。',app.Controls.Progress.Value);end
        function progressUpdate(app,p,message),if app.CancelRequested,error('LFP:UserCancelled','用户已取消分析。');end;app.setStatus('运行中',string(message),p);drawnow limitrate;end
        function finishTask(app),app.Busy=false;app.updateBusyState();end
        function updateBusyState(app)
            enabled=local_choice(app.Busy,'off','on');app.Controls.RunSession.Enable=enabled;app.Controls.CompareButton.Enable=enabled;app.Controls.UnifyCompare.Enable=enabled;app.Controls.NewProject.Enable=enabled;app.Controls.OpenProject.Enable=enabled;app.Controls.Cancel.Enable=local_choice(app.Busy,'on','off');
        end
        function onAnalysisChannelChanged(app),app.CurrentChannelIndex=find(string(app.Controls.AnalysisChannel.Items)==string(app.Controls.AnalysisChannel.Value),1);if isempty(app.CurrentChannelIndex),app.CurrentChannelIndex=1;end;app.refreshAnalysisView();end

        function refreshComparisonFilters(app)
            if app.noProject(),return;end
            subjects=string({app.Project.subjects.subject_id});visits=strings(0,1);statuses=strings(0,1);for i=1:numel(app.Project.subjects),visits=[visits;string({app.Project.subjects(i).sessions.visit_label})'];statuses=[statuses;string({app.Project.subjects(i).sessions.status})'];end %#ok<LFPS>
            app.setDropdownItems(app.Controls.FilterSubject,["全部";unique(subjects(:),'stable')]);app.setDropdownItems(app.Controls.FilterVisit,["全部";unique(visits(strlength(visits)>0),'stable')]);app.setDropdownItems(app.Controls.FilterStatus,["全部";unique(statuses(strlength(statuses)>0),'stable')]);
        end

        function refreshComparisonCandidates(app)
            if app.noProject(),app.Controls.CandidateTable.Data=cell(0,7);return;end
            rows=cell(0,7);sf=string(app.Controls.FilterSubject.Value);vf=string(app.Controls.FilterVisit.Value);rf=string(app.Controls.FilterStatus.Value);
            for i=1:numel(app.Project.subjects),subject=app.Project.subjects(i);if sf~="全部"&&subject.subject_id~=sf,continue;end
                for j=1:numel(subject.sessions),session=subject.sessions(j);if vf~="全部"&&session.visit_label~=vf,continue;end;if rf~="全部"&&session.status~=rf,continue;end
                    selected=any(app.CompareSelectedSessionIds==session.session_id);condition=strtrim(session.medication_state+" "+session.stimulation_state);
                    rows(end+1,:)={selected,char(subject.subject_id),char(session.session_id),char(session.visit_label),char(condition),char(session.status),char(session.session_id)}; %#ok<AGROW>
                end
            end
            app.Controls.CandidateTable.Data=rows;app.refreshSelectedSessions();
        end

        function onCandidateEdited(app,event)
            row=event.Indices(1);data=app.Controls.CandidateTable.Data;id=string(data{row,7});if logical(data{row,1}),app.CompareSelectedSessionIds=unique([app.CompareSelectedSessionIds;id],'stable');else,app.CompareSelectedSessionIds(app.CompareSelectedSessionIds==id)=[];end;app.refreshSelectedSessions();
        end
        function selectFiltered(app),data=app.Controls.CandidateTable.Data;if isempty(data),return;end;app.CompareSelectedSessionIds=unique([app.CompareSelectedSessionIds;string(data(:,7))],'stable');app.refreshComparisonCandidates();end
        function clearComparisonSelection(app),app.CompareSelectedSessionIds=strings(0,1);app.refreshComparisonCandidates();end
        function removeSelectedComparison(app),selected=string(app.Controls.SelectedSessions.Value);selected=selected(selected~="(未选择)");app.CompareSelectedSessionIds(ismember(app.CompareSelectedSessionIds,selected))=[];app.refreshComparisonCandidates();end

        function refreshSelectedSessions(app)
            app.Controls.SelectedCount.Text=char("已选择 "+string(numel(app.CompareSelectedSessionIds))+" 条");if isempty(app.CompareSelectedSessionIds),app.Controls.SelectedSessions.Items={'(未选择)'};app.Controls.SelectedSessions.Value={'(未选择)'};app.Controls.MappingTable.Data=cell(0,3);return;end
            app.Controls.SelectedSessions.Items=cellstr(app.CompareSelectedSessionIds);app.Controls.SelectedSessions.Value=char(app.CompareSelectedSessionIds(1));old=app.Controls.MappingTable.Data;rows=cell(numel(app.CompareSelectedSessionIds),3);
            for i=1:numel(app.CompareSelectedSessionIds),id=app.CompareSelectedSessionIds(i);[session,~]=lfp_project_find_session(app.Project,id);channel="";if ~isempty(session)&&~isempty(session.channels),channel=string(session.channels(1).original_label);end
                if ~isempty(old),match=find(string(old(:,1))==id,1);if ~isempty(match),channel=string(old{match,2});target=string(old{match,3});else,target=channel;end;else,target=channel;end;rows(i,:)={char(id),char(channel),char(target)};
            end
            app.Controls.MappingTable.Data=rows;
        end

        function spec=readComparisonSpec(app)
            ids=app.CompareSelectedSessionIds(:);subjects=strings(numel(ids),1);mapping=repmat(struct('session_id',"",'channel_id',"",'channel_label',"",'target_label',""),numel(ids),1);rows=app.Controls.MappingTable.Data;
            for i=1:numel(ids),[session,subject]=lfp_project_find_session(app.Project,ids(i));subjects(i)=subject.subject_id;chosen=string(rows{i,2});target=string(rows{i,3});labels=string({session.channels.original_label});display=string({session.channels.display_label});idx=find(labels==chosen|display==chosen,1);if isempty(idx),error('LFP:ChannelMappingMissing','Session %s 中不存在通道 %s。',ids(i),chosen);end
                mapping(i)=struct('session_id',ids(i),'channel_id',string(session.channels(idx).channel_id),'channel_label',string(session.channels(idx).original_label),'target_label',target);
            end
            type="between_subjects";if numel(unique(subjects))==1,type="within_subject";end
            spec=struct('type',type,'session_ids',ids,'subject_ids',unique(subjects),'bands',string(app.Controls.CompareBand.Value),'metric',string(app.Controls.CompareMetric.Value),'aggregation',string(app.Controls.CompareAggregation.Value),'channel_mapping',mapping,'plot_settings',struct('type',string(app.Controls.ComparePlot.Value)));
        end

        function onCompare(app,unify),try,app.compareSelected(unify);catch e,app.showError(e,'比较失败');end,end
        function renderComparison(app)
            ax=app.Controls.CompareAxes;cla(ax,'reset');if isempty(fieldnames(app.CurrentComparison)),text(ax,.5,.5,'请选择比较对象并运行比较','Units','normalized','HorizontalAlignment','center');axis(ax,'off');return;end
            tbl=app.CurrentComparison.result_table;if isempty(tbl),text(ax,.5,.5,'没有可比较的有效结果','Units','normalized','HorizontalAlignment','center');axis(ax,'off');return;end
            labels=string(tbl.subject_id)+" / "+string(tbl.visit_label)+" / "+string(tbl.channel_label);values=double(tbl.value(:));x=(1:numel(values))';if string(app.Controls.ComparePlot.Value)=="柱状图",bar(ax,x,values,'FaceColor',[.15 .45 .75]);else,scatter(ax,x,values,60,[.1 .4 .8],'filled');end
            xticks(ax,x);xlim(ax,[.5 numel(values)+.5]);xticklabels(ax,cellstr(labels));xtickangle(ax,25);grid(ax,'on');ylabel(ax,string(tbl.metric(1))+" ("+string(tbl.unit(1))+")",'Interpreter','none');title(ax,string(app.CurrentComparison.type)+" | "+string(tbl.band(1)),'Interpreter','none');app.Controls.CompareStatus.Text=char(string(app.CurrentComparison.status)+" | "+string(height(tbl))+" 点");
        end

        function restoreLatestComparison(app)
            if ~isfield(app.Project,'comparisons')||isempty(app.Project.comparisons),return;end
            saved=app.Project.comparisons(end);app.CompareSelectedSessionIds=string(saved.session_ids(:));
            if isfield(saved,'metric')&&any(string(app.Controls.CompareMetric.Items)==string(saved.metric)),app.Controls.CompareMetric.Value=char(saved.metric);end
            if isfield(saved,'bands')&&~isempty(saved.bands)&&any(string(app.Controls.CompareBand.Items)==string(saved.bands(1))),app.Controls.CompareBand.Value=char(saved.bands(1));end
            app.refreshComparisonCandidates();
            if isfield(saved,'channel_mapping')&&~isempty(saved.channel_mapping)
                rows=cell(numel(saved.channel_mapping),3);
                for i=1:numel(saved.channel_mapping),m=saved.channel_mapping(i);label="";if isfield(m,'channel_label'),label=string(m.channel_label);end;target=label;if isfield(m,'target_label')&&strlength(string(m.target_label))>0,target=string(m.target_label);end;rows(i,:)={char(string(m.session_id)),char(label),char(target)};end
                app.Controls.MappingTable.Data=rows;
            end
            if isfield(saved,'result_table')&&istable(saved.result_table)&&~isempty(saved.result_table),app.CurrentComparison=saved;app.renderComparison();end
        end

        function saveComparisonPlan(app),try,spec=app.readComparisonSpec();[app.Project,plan]=lfp_save_comparison_plan(app.Project,spec);app.Dirty=false;app.setStatus('就绪','比较方案已保存：'+plan.comparison_id,0);catch e,app.showError(e,'保存比较方案失败');end,end
        function saveComparisonImage(app),if isempty(fieldnames(app.CurrentComparison)),app.warn('尚无比较图。');return;end;[f,p]=uiputfile({'*.png','PNG 图片'},'保存比较图片','comparison.png');if isequal(f,0),return;end;try,exportgraphics(app.Controls.CompareAxes,fullfile(p,f),'Resolution',300);catch e,app.showError(e,'保存图片失败');end,end
        function exportComparisonData(app),if isempty(fieldnames(app.CurrentComparison)),app.warn('尚无比较结果。');return;end;folder=uigetdir('','选择导出目录');if isequal(folder,0),return;end;try,lfp_export_comparison(app.CurrentComparison,string(folder));app.setStatus('就绪','比较数据已导出。',0);catch e,app.showError(e,'导出失败');end,end
        function saveCurrentFigure(app)
            if isempty(fieldnames(app.CurrentData)),app.warn('当前没有可保存图形。');return;end;[f,p]=uiputfile({'*.png','PNG 图片'},'保存当前图形',char(app.CurrentSessionId+".png"));if isequal(f,0),return;end;tab=app.Controls.AnalysisResultTabs.SelectedTab;ax=app.Controls.RawAxes;if tab==app.Controls.PsdResultTab,ax=app.Controls.PsdAxes;elseif tab==app.Controls.SpecResultTab,ax=app.Controls.SpecModelAxes;elseif tab==app.Controls.BandResultTab,ax=app.Controls.BandAxes;end;try,exportgraphics(ax,fullfile(p,f),'Resolution',300);catch e,app.showError(e,'保存图片失败');end
        end
        function saveCurrentData(app)
            if isempty(fieldnames(app.CurrentResults)),app.warn('当前 Session 尚无分析结果。');return;end;[f,p]=uiputfile({'*.mat','MAT 文件'},'保存当前结果',char(app.CurrentSessionId+"_results.mat"));if isequal(f,0),return;end;sessionId=app.CurrentSessionId;run=app.CurrentRun;results=app.CurrentResults;data=app.CurrentData;projectId=app.Project.project_id;save(fullfile(p,f),'projectId','sessionId','run','results','data','-v7.3');
        end

        function onWorkspaceTabChanged(app),if app.Controls.WorkspaceTabs.SelectedTab==app.Controls.CompareTab,app.refreshComparisonCandidates();elseif app.Controls.WorkspaceTabs.SelectedTab==app.Controls.AnalysisTab,app.refreshAnalysisView();end,end
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
            if ~isgraphics(app.Figure)||~isfield(app.Controls,'BodyGrid')||~isgraphics(app.Controls.BodyGrid),return;end
            if isfield(app.Controls,'HostPanel')&&isgraphics(app.Controls.HostPanel)
                app.Controls.HostPanel.Position=[1 1 app.Figure.Position(3) app.Figure.Position(4)];
            end
            app.CompactMode=app.Figure.Position(3)<1300;
            if app.CompactMode
                if isfield(app.Controls,'CompareGrid'),app.Controls.CompareGrid.RowHeight={130,112,68,'1x'};end
                if app.NavigationOnly
                    app.Controls.BodyGrid.ColumnWidth={'1x',0};app.Controls.NavigationPanel.Visible='on';app.Controls.WorkspacePanel.Visible='off';app.Controls.ToggleNavigation.Text='返回工作区';
                else
                    app.Controls.BodyGrid.ColumnWidth={0,'1x'};app.Controls.NavigationPanel.Visible='off';app.Controls.WorkspacePanel.Visible='on';app.Controls.ToggleNavigation.Text='打开导航';
                end
            else
                if isfield(app.Controls,'CompareGrid'),app.Controls.CompareGrid.RowHeight={130,112,72,'1x'};end
                app.NavigationOnly=false;app.Controls.WorkspacePanel.Visible='on';
                if app.NavigationCollapsed
                    app.Controls.BodyGrid.ColumnWidth={0,'1x'};app.Controls.NavigationPanel.Visible='off';app.Controls.ToggleNavigation.Text='打开导航';
                else
                    app.Controls.BodyGrid.ColumnWidth={285,'1x'};app.Controls.NavigationPanel.Visible='on';app.Controls.ToggleNavigation.Text='收起导航';
                end
            end
        end
        function showWelcome(app),app.Controls.Welcome.Visible='on';app.Controls.WorkspaceTabs.Visible='off';app.Controls.SaveProject.Enable='off';end
        function resetSelection(app),app.CurrentSubjectId="";app.CurrentSessionId="";app.CurrentData=struct();app.CurrentRun=struct();app.CurrentResults=struct();app.CurrentComparison=struct();app.CompareSelectedSessionIds=strings(0,1);app.applyConfigToControls();end
        function clearSessionDisplay(app),app.CurrentData=struct();app.CurrentRun=struct();app.CurrentResults=struct();app.Controls.ChannelTable.Data=cell(0,8);app.Controls.Metadata.Value={'请选择项目节点。'};app.clearAnalysisAxes('请选择 Session。');app.refreshDataPreview();end
        function clearAnalysisAxes(app,message),axesList=[app.Controls.RawAxes app.Controls.CleanAxes app.Controls.PsdAxes app.Controls.SpecModelAxes app.Controls.SpecPeakAxes app.Controls.BandAxes];for ax=axesList,cla(ax,'reset');text(ax,.5,.5,message,'Units','normalized','HorizontalAlignment','center');axis(ax,'off');end;app.Controls.SpecQuality.Data=cell(0,2);app.Controls.BandResultTable.Data=cell(0,1);end
        function updateProjectHeader(app),if app.noProject(),return;end;app.Controls.ProjectTitle.Text=char(app.Project.name);app.Controls.ProjectTitle.Tooltip=char(app.Project.rootPath);app.Controls.SaveState.Text=local_choice(app.Dirty,'未保存','已保存');app.Controls.SaveProject.Enable='on';app.Controls.NavigationHint.Text='单击节点查看；比较对象在结果比较页单独勾选。';end
        function markDirty(app),app.Dirty=true;app.updateProjectHeader();end
        function setStatus(app,task,message,progress),task=clean_text(task);message=clean_text(message);app.Controls.TaskStatus.Text=char(task);app.Controls.StageStatus.Text=char(message);app.Controls.StageStatus.Tooltip=char(message);progress=max(0,min(1,double(progress)));app.Controls.Progress.Value=progress;app.Controls.Percent.Text=sprintf('%d%%',round(progress*100));app.LogMessages(end+1,1)="["+string(datestr(now,'HH:MM:SS'))+"] "+task+" | "+message;end
        function showError(app,e,titleText),app.Busy=false;app.updateBusyState();app.setStatus('失败',string(e.message),0);if isgraphics(app.Figure)&&strcmp(app.Figure.Visible,'on'),uialert(app.Figure,string(e.message),titleText);end,end
        function warn(app,message),app.setStatus('提示',string(message),0);if isgraphics(app.Figure)&&strcmp(app.Figure.Visible,'on'),uialert(app.Figure,string(message),'提示','Icon','warning');end,end
        function showLog(app),fig=uifigure('Name','SceneRay LFP 日志','Position',[250 180 850 520]);g=uigridlayout(fig,[1 1]);uitextarea(g,'Editable','off','Value',cellstr(app.LogMessages),'WordWrap','on');end
        function tf=noProject(app),tf=isempty(fieldnames(app.Project));end
        function labels=channelLabels(~,session),labels=strings(numel(session.channels),1);for i=1:numel(session.channels),labels(i)=session.channels(i).display_label;if strlength(labels(i))==0,labels(i)=session.channels(i).original_label;end;end,end
        function setDropdownItems(~,control,items),current=string(control.Value);control.Items=cellstr(items);if any(items==current),control.Value=char(current);else,control.Value=char(items(1));end,end
    end
end

function value=local_choice(condition,a,b)
if condition,value=a;else,value=b;end
end

function value=clean_text(value)
value=string(value);value=value(~ismissing(value));if isempty(value),value="";else,value=join(value,"；");end
end

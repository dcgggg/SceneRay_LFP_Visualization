classdef LfpProjectApp < handle
    %LFPPROJECTAPP Native Project -> Subject -> Session workspace.

    properties
        Figure
        Project = struct()
        CurrentSessionId = ""
        Controls = struct()
        ClosingRequested = false
    end

    methods
        function app = LfpProjectApp(visible)
            app.Figure = uifigure('Name', 'SceneRay LFP 项目工作区', 'Visible', char(visible), ...
                'Position', [100 100 1250 760], 'CloseRequestFcn', @(~,~)app.close());
            tabs = uitabgroup(app.Figure);
            dataTab = uitab(tabs, 'Title', '数据管理');
            analysisTab = uitab(tabs, 'Title', '单次分析');
            compareTab = uitab(tabs, 'Title', '结果比较');
            app.buildDataTab(dataTab); app.buildAnalysisTab(analysisTab); app.buildCompareTab(compareTab);
            app.setStatus('尚未打开项目。', 'info');
        end

        function delete(app)
            app.close();
        end

        function close(app)
            if app.ClosingRequested, return; end
            app.ClosingRequested = true;
            if ~isempty(app.Figure) && isgraphics(app.Figure), delete(app.Figure); end
        end

        function buildDataTab(app, parent)
            grid = uigridlayout(parent, [1 2]); grid.ColumnWidth = {360, '1x'}; grid.Padding = [8 8 8 8];
            left = uipanel(grid, 'Title', 'Project / Subject / Session'); left.Layout.Column=1;
            right = uipanel(grid, 'Title', '元数据与通道'); right.Layout.Column=2;
            lg = uigridlayout(left, [5 1]); lg.RowHeight = {32 32 32 '1x' 32}; lg.Padding=[6 6 6 6];
            buttons = uigridlayout(lg, [1 2]); buttons.Layout.Row=1; buttons.ColumnWidth={'1x','1x'};
            app.Controls.CreateProject = uibutton(buttons, 'Text','新建项目', 'ButtonPushedFcn', @(~,~)app.createProject());
            app.Controls.OpenProject = uibutton(buttons, 'Text','打开项目', 'ButtonPushedFcn', @(~,~)app.openProject());
            buttons2 = uigridlayout(lg, [1 2]); buttons2.Layout.Row=2; buttons2.ColumnWidth={'1x','1x'};
            app.Controls.AddSubject = uibutton(buttons2, 'Text','添加被试', 'ButtonPushedFcn', @(~,~)app.addSubject());
            app.Controls.ImportSession = uibutton(buttons2, 'Text','导入 Session', 'ButtonPushedFcn', @(~,~)app.importSession());
            app.Controls.ProjectLabel = uilabel(lg, 'Text','未打开项目'); app.Controls.ProjectLabel.Layout.Row=3;
            app.Controls.ProjectTree = uitree(lg, 'SelectionChangedFcn', @(~,~)app.onTreeSelection()); app.Controls.ProjectTree.Layout.Row=4;
            app.Controls.DataStatus = uilabel(lg, 'Text','', 'WordWrap','on'); app.Controls.DataStatus.Layout.Row=5;
            rg = uigridlayout(right, [2 1]); rg.RowHeight = {110,'1x'}; rg.Padding=[8 8 8 8];
            app.Controls.Metadata = uitextarea(rg, 'Editable','off', 'Value', {'请选择 Session'}); rg.RowHeight{1}=110;
            app.Controls.ChannelTable = uitable(rg, 'Data', cell(0,5), 'ColumnName', {'channel_id','original_label','display_label','region','reference'}, 'RowName', []);
        end

        function buildAnalysisTab(app, parent)
            grid = uigridlayout(parent, [3 1]); grid.RowHeight={44,44,'1x'}; grid.Padding=[10 10 10 10];
            top=uigridlayout(grid,[1 4]); top.ColumnWidth={100,220,100,'1x'};
            uilabel(top,'Text','Session'); app.Controls.AnalysisSession=uidropdown(top,'Items',{'(none)'},'ValueChangedFcn',@(s,~)app.onSessionDropDown(s));
            app.Controls.RunSession=uibutton(top,'Text','运行分析','ButtonPushedFcn',@(~,~)app.runSession());
            app.Controls.AnalysisStatus=uilabel(top,'Text','未运行');
            app.Controls.AnalysisInfo=uitextarea(grid,'Editable','off','Value',{'选择 Session 后运行。'}); app.Controls.AnalysisInfo.Layout.Row=3;
        end

        function buildCompareTab(app, parent)
            grid=uigridlayout(parent,[3 1]); grid.RowHeight={70,40,'1x'}; grid.Padding=[10 10 10 10];
            controls=uigridlayout(grid,[2 6]); controls.RowHeight={30,30}; controls.ColumnWidth={75,220,75,120,90,'1x'};
            uilabel(controls,'Text','Session IDs'); app.Controls.CompareSessions= uieditfield(controls,'text','Value',''); app.Controls.CompareSessions.Layout.Column=2; app.Controls.CompareSessions.Layout.Row=1;
            uilabel(controls,'Text','频段'); controls.Children(end).Layout.Column=3; controls.Children(end).Layout.Row=1;
            app.Controls.CompareBand= uieditfield(controls,'text','Value','alpha'); app.Controls.CompareBand.Layout.Column=4; app.Controls.CompareBand.Layout.Row=1;
            app.Controls.CompareButton=uibutton(controls,'Text','比较','ButtonPushedFcn',@(~,~)app.compare()); app.Controls.CompareButton.Layout.Column=5; app.Controls.CompareButton.Layout.Row=1;
            app.Controls.CompareStatus=uilabel(controls,'Text',''); app.Controls.CompareStatus.Layout.Column=6; app.Controls.CompareStatus.Layout.Row=1;
            app.Controls.CompareAxes=uiaxes(grid); app.Controls.CompareAxes.Layout.Row=3;
        end

        function createProject(app)
            try
                root=uigetdir('', '选择项目目录'); if isequal(root,0), return; end
                answer=inputdlg({'项目名称'},'新建项目',[1 40],{'Human LFP study'}); if isempty(answer), return; end
                app.Project=lfp_create_project(string(root),string(answer{1})); app.refresh();
                app.setStatus('项目已创建。','info');
            catch exception, app.showError(exception); end
        end

        function openProject(app)
            try
                root=uigetdir('', '选择包含 project.mat 的项目目录'); if isequal(root,0), return; end
                app.Project=lfp_load_project(string(root)); app.refresh(); app.setStatus('项目已打开。','info');
            catch exception, app.showError(exception); end
        end

        function addSubject(app)
            if isempty(fieldnames(app.Project)), app.setStatus('请先创建或打开项目。','warning'); return; end
            answer=inputdlg({'subject_id','显示名称','分组'},'添加被试',[1 30;1 30;1 30],{'P01','P01',''}); if isempty(answer), return; end
            try
                [app.Project,~]=lfp_project_add_subject(app.Project, struct('subject_id',string(answer{1}),'display_name',string(answer{2}),'group',string(answer{3}))); app.refresh();
            catch exception, app.showError(exception); end
        end

        function importSession(app)
            if isempty(fieldnames(app.Project)), app.setStatus('请先创建或打开项目。','warning'); return; end
            subjects=string({app.Project.subjects.subject_id}); if isempty(subjects), app.setStatus('请先添加被试。','warning'); return; end
            [file,path]=uigetfile({'*.csv','CSV 文件'},'导入 Session'); if isequal(file,0), return; end
            answer=inputdlg({'subject_id','session_id','visit_label'},'Session 信息',[1 30;1 40;1 30],{char(subjects(1)),'S01','Baseline'}); if isempty(answer), return; end
            try
                [app.Project,~]=lfp_project_add_csv_session(app.Project,string(answer{1}),string(fullfile(path,file)),struct('session_id',string(answer{2}),'visit_label',string(answer{3}))); app.refresh(); app.setStatus('Session 已导入。','info');
            catch exception, app.showError(exception); end
        end

        function onTreeSelection(app)
            node=app.Controls.ProjectTree.SelectedNodes; if isempty(node), return; end
            data=node.NodeData; if isstruct(data) && isfield(data,'session_id'), app.CurrentSessionId=string(data.session_id); app.showSession(data); end
        end

        function onSessionDropDown(app, source)
            if string(source.Value) ~= "(none)", app.CurrentSessionId=string(source.Value); end
        end

        function runSession(app)
            if isempty(app.CurrentSessionId), app.setStatus('请先选择 Session。','warning'); return; end
            try
                [app.Project,summary]=lfp_analyze_project(app.Project,app.CurrentSessionId); app.Controls.AnalysisStatus.Text=char(summary.status); app.Controls.AnalysisInfo.Value={char("Session: "+app.CurrentSessionId);char("状态: "+summary.status);char("run_id: "+summary.runId)}; app.refresh();
            catch exception, app.showError(exception); end
        end

        function compare(app)
            if isempty(fieldnames(app.Project)), app.setStatus('请先打开项目。','warning'); return; end
            ids=split(strtrim(string(app.Controls.CompareSessions.Value)),','); ids=ids(strlength(ids)>0);
            if isempty(ids), app.setStatus('请输入逗号分隔的 Session ID。','warning'); return; end
            try
                spec=struct('type','custom','session_ids',ids,'bands',string(app.Controls.CompareBand.Value),'metric','totalPower');
                [app.Project,comparison]=lfp_compare_project(app.Project,spec); app.Controls.CompareStatus.Text=char(comparison.status); plotProjectComparison(comparison,Parent=app.Controls.CompareAxes,Band=string(app.Controls.CompareBand.Value),Metric='totalPower');
            catch exception, app.showError(exception); end
        end

        function refresh(app)
            if isempty(fieldnames(app.Project)), return; end
            app.Controls.ProjectLabel.Text=char(app.Project.name); delete(app.Controls.ProjectTree.Children);
            sessions={};
            for s=1:numel(app.Project.subjects)
                subject=uitreenode(app.Controls.ProjectTree,'Text',char(app.Project.subjects(s).display_name),'NodeData',app.Project.subjects(s));
                for k=1:numel(app.Project.subjects(s).sessions)
                    session=app.Project.subjects(s).sessions(k); uitreenode(subject,'Text',char(session.visit_label+" | "+session.session_id),'NodeData',session); sessions{end+1}=char(session.session_id); %#ok<AGROW>
                end
            end
            if isempty(sessions), sessions={'(none)'}; end
            app.Controls.AnalysisSession.Items=sessions; app.Controls.AnalysisSession.Value=sessions{1};
        end

        function showSession(app, session)
            lines={['Session: ' char(session.session_id)],['Subject: ' char(session.subject_id)],['Visit: ' char(session.visit_label)],['状态: ' char(session.status)]}; app.Controls.Metadata.Value=lines;
            if isempty(session.channels), app.Controls.ChannelTable.Data=cell(0,5); return; end
            rows=cell(numel(session.channels),5); for k=1:numel(session.channels), c=session.channels(k); rows(k,:)={char(c.channel_id),char(c.original_label),char(c.display_label),char(c.region),char(c.reference)}; end
            app.Controls.ChannelTable.Data=rows;
        end

        function setStatus(app,message,level)
            if isfield(app.Controls,'DataStatus') && isgraphics(app.Controls.DataStatus), app.Controls.DataStatus.Text=char(message); end
            if isfield(app.Controls,'CompareStatus') && isgraphics(app.Controls.CompareStatus) && strcmpi(string(level), "error"), app.Controls.CompareStatus.Text=char(message); end
        end

        function showError(app,exception)
            app.setStatus(string(exception.message),'error'); if ~isempty(app.Figure) && isgraphics(app.Figure) && strcmp(app.Figure.Visible,'on'), uialert(app.Figure,string(exception.message),'项目操作失败'); end
        end
    end
end

classdef LfpApp < handle
    %LFPAPP Native MATLAB GUI for the SceneRay LFP analysis workflow.
    %   The class owns only GUI state and delegates all calculations to the
    %   public importer, artifact, PSD, parameterization, band-power and
    %   export functions. Raw samples are kept in Data and are never
    %   overwritten by a derived NaN-marked display signal.

    properties
        Figure
        Config
        Data = struct()
        CleanData = struct()
        AnalysisData = struct()
        ArtifactResult = struct()
        BeforePsd = struct()
        PsdResult = struct()
        ModelResult = struct()
        BandResult = struct()
        LastRunSnapshot = struct()
        LastRunError = ""
        Controls = struct()
        Tabs = struct()
        Cache = struct('artifactValid', false, 'psdValid', false, ...
            'modelValid', false, 'bandValid', false, 'plotValid', false)
        IsRunning = false
        CancelRequested = false
    end

    methods
        function app = LfpApp(visible)
            if nargin < 1 || isempty(visible), visible = "on"; end
            app.Config = lfpDefaultConfig();
            app.buildUi(string(visible));
            app.refreshDependencyStatus();
            app.updateDataInfo();
            app.logMessage("GUI 已启动。请选择 CSV 文件开始分析。", "info");
        end

        function delete(app)
            if ~isempty(app.Figure) && isgraphics(app.Figure)
                delete(app.Figure);
            end
        end

        function closeApp(app, ~, ~)
            if app.IsRunning
                app.CancelRequested = true;
                app.setStatus("正在停止当前运行；请等待当前阶段结束。", "warning");
                return;
            end
            if ~isempty(app.Figure) && isgraphics(app.Figure)
                delete(app.Figure);
            end
        end

        function onImport(app, ~, ~)
            if app.IsRunning, return; end
            [file, folder] = uigetfile({'*.csv', 'CSV 文件 (*.csv)'}, '选择 LFP CSV 文件');
            if isequal(file, 0), return; end
            app.openImportDialog(string(fullfile(folder, file)));
        end

        function onLoadConfig(app, ~, ~)
            if app.IsRunning, return; end
            [file, folder] = uigetfile({'*.mat', 'MAT 配置文件 (*.mat)'}, '加载分析配置');
            if isequal(file, 0), return; end
            try
                loaded = load(fullfile(folder, file));
                if isfield(loaded, 'cfg'), candidate = loaded.cfg;
                elseif isfield(loaded, 'config'), candidate = loaded.config;
                else, error('LFP:ConfigNotFound', 'MAT 文件中没有 cfg 或 config 变量。');
                end
                app.Config = app.mergeConfig(lfpDefaultConfig(), candidate);
                app.populateControlsFromConfig();
                app.invalidateAll("配置已加载，已有结果需要重新运行。");
                app.logMessage("已加载配置：" + string(file), "info");
            catch exception
                app.showError("配置加载失败", exception);
            end
        end

        function onSaveConfig(app, ~, ~)
            if app.IsRunning, return; end
            try
                app.Config = app.readConfigFromUi();
                [file, folder] = uiputfile({'*.mat', 'MAT 配置文件 (*.mat)'}, '保存分析配置', 'lfp_config.mat');
                if isequal(file, 0), return; end
                cfg = app.Config; %#ok<NASGU>
                save(fullfile(folder, file), 'cfg', '-v7');
                app.logMessage("配置已保存：" + string(fullfile(folder, file)), "info");
            catch exception
                app.showError("配置保存失败", exception);
            end
        end

        function onSaveResults(app, ~, ~)
            if app.IsRunning, return; end
            if isempty(fieldnames(app.AnalysisData))
                app.showWarning("尚无可保存结果", "请先运行至少一个分析模块。");
                return;
            end
            folder = uigetdir('', '选择结果输出目录');
            if isequal(folder, 0), return; end
            folder = string(folder);
            expected = fullfile(folder, 'analysis_results.mat');
            if isfile(expected)
                choice = uiconfirm(app.Figure, ...
                    "输出目录中已有 analysis_results.mat，是否覆盖？", ...
                    "确认覆盖", 'Options', {'覆盖', '取消'}, 'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, '覆盖'), return; end
            end
            try
                app.Config = app.readConfigFromUi();
                files = lfp_export_results(app.AnalysisData, folder, ...
                    FigureResolution=app.Config.plot.exportResolution, ...
                    FigurePosition=app.Config.plot.figurePosition);
                app.logMessage("结果已保存到：" + folder, "info");
                app.logMessage("MAT=" + files.mat + " | band CSV=" + files.bandPowerCsv, "info");
            catch exception
                app.showError("结果保存失败", exception);
            end
        end

        function onBrowseOutput(app, ~, ~)
            folder = uigetdir('', '选择自动保存目录');
            if ~isequal(folder, 0)
                app.Controls.OutputFolder.Value = string(folder);
            end
        end

        function onRun(app, ~, ~)
            if app.IsRunning, return; end
            if isempty(fieldnames(app.Data))
                app.showWarning("尚未导入数据", "请先选择并确认一个 CSV 文件。");
                return;
            end
            try
                cfg = app.readConfigFromUi();
                snapshot = app.makeRunSnapshot(cfg);
                app.validateRun(snapshot);
            catch exception
                app.showError("运行参数有误", exception);
                return;
            end

            app.IsRunning = true;
            app.CancelRequested = false;
            app.setControlsEnabled(false);
            cleanup = onCleanup(@() app.finishRun()); %#ok<NASGU>
            try
                app.setProgress(0.05, "准备数据");
                selectedData = app.selectChannels(app.Data, snapshot.channels);
                fullArtifact = app.emptyArtifact(selectedData);
                fullClean = selectedData;
                fullClean.cleanedSignal = selectedData.signal;

                needPsd = snapshot.modules.psd || snapshot.modules.fooof || snapshot.modules.band;
                needModel = snapshot.modules.fooof || snapshot.modules.band;
                needArtifact = snapshot.modules.artifact || ...
                    (needPsd && snapshot.cfg.psd.excludeArtifacts && ~app.Cache.artifactValid);

                if needArtifact
                    app.setProgress(0.15, "检测伪迹");
                    [fullClean, fullArtifact] = detectAndHandleArtifacts(selectedData, snapshot.cfg.artifact);
                    fullArtifact.channelIndices = snapshot.channels;
                    app.checkCancellation();
                elseif app.Cache.artifactValid && app.compatibleArtifact(app.ArtifactResult, selectedData)
                    fullArtifact = app.ArtifactResult;
                    fullArtifact.channelIndices = snapshot.channels;
                    fullClean.artifacts = fullArtifact;
                    fullClean.cleanedSignal = selectedData.signal;
                    fullClean.cleanedSignal(fullArtifact.channelMask) = NaN;
                end
                if ~isfield(fullArtifact, 'channelIndices')
                    fullArtifact.channelIndices = snapshot.channels;
                end

                analysisIndex = app.timeIndexForRange(selectedData, snapshot.analysisRange);
                analysisData = app.sliceData(selectedData, analysisIndex);
                analysisArtifact = app.sliceArtifact(fullArtifact, analysisIndex, selectedData.fs);
                analysisClean = app.sliceData(fullClean, analysisIndex);
                analysisClean.artifacts = analysisArtifact;
                analysisClean.cleanedSignal = analysisData.signal;
                analysisClean.cleanedSignal(analysisArtifact.channelMask) = NaN;

                beforePsd = struct();
                psd = struct();
                model = struct([]);
                band = struct();
                if needPsd
                    app.setProgress(0.35, "计算 PSD");
                    if snapshot.modules.artifact || needArtifact
                        emptyForBefore = app.emptyArtifact(analysisData);
                        beforePsd = computeLfpPsd(analysisData, emptyForBefore, snapshot.cfg.psd);
                    else
                        beforePsd = computeLfpPsd(analysisData, app.emptyArtifact(analysisData), snapshot.cfg.psd);
                    end
                    app.checkCancellation();
                    psd = computeLfpPsd(analysisClean, analysisArtifact, snapshot.cfg.psd);
                end
                if needModel
                    app.setProgress(0.58, "拟合周期/非周期谱");
                    model = parameterizePowerSpectrum(psd.frequencyHz, psd.psd, snapshot.cfg.fooof);
                    model = app.addModelContext(model, analysisData);
                    app.checkCancellation();
                end
                if snapshot.modules.band
                    app.setProgress(0.74, "计算频段功率");
                    band = computeBandPower(psd, model, snapshot.cfg.bands);
                    app.checkCancellation();
                end

                analysisData.artifacts = analysisArtifact;
                analysisData.cleanedSignal = analysisClean.cleanedSignal;
                if needPsd, analysisData.spectrum = psd; end
                if needModel
                    analysisData.spectralParameters = struct( ...
                        'aperiodicPsd', app.collectModelField(model, 'aperiodicFit'), ...
                        'periodicPowerAboveAperiodic', app.collectModelField(model, 'periodicFit'));
                end
                if snapshot.modules.band, analysisData.bandPower = band; end
                analysisData.metadata.analysisRangeSeconds = snapshot.analysisRange;
                analysisData.metadata.selectedChannels = snapshot.channels;
                analysisData.metadata.runSnapshot = snapshot;
                if ~needPsd
                    analysisData.processingHistory = analysisClean.processingHistory;
                elseif isfield(psd, 'processingHistory')
                    analysisData.processingHistory = psd.processingHistory;
                end
                if needModel
                    analysisData.processingHistory(end + 1) = struct('operation', "spectral_parameterization", ...
                        'parameters', snapshot.cfg.fooof, 'notes', "Fixed/no-knee periodic and aperiodic model fitted in GUI run.");
                end
                if snapshot.modules.band
                    analysisData.processingHistory(end + 1) = struct('operation', "band_power", ...
                        'parameters', snapshot.cfg.bands, 'notes', "Band powers computed from the GUI run PSD/model snapshot.");
                end

                if app.CancelRequested
                    app.logMessage("用户请求取消；本次临时结果未替换上一份成功结果。", "warning");
                    return;
                end
                app.Config = snapshot.cfg;
                app.CleanData = fullClean;
                app.ArtifactResult = fullArtifact;
                app.AnalysisData = analysisData;
                app.BeforePsd = beforePsd;
                app.PsdResult = psd;
                app.ModelResult = model;
                app.BandResult = band;
                app.LastRunSnapshot = snapshot;
                app.LastRunError = "";
                app.Cache = struct('artifactValid', ~isempty(fieldnames(fullArtifact)), ...
                    'psdValid', ~isempty(fieldnames(psd)), ...
                    'modelValid', ~isempty(model), 'bandValid', ~isempty(fieldnames(band)), ...
                    'plotValid', true);
                app.setProgress(0.88, "更新图形");
                app.renderAll();
                if snapshot.autoSave
                    app.autoSaveResults(snapshot);
                end
                app.setProgress(1, "运行完成");
                app.logMessage("本次运行完成。结果使用当前参数快照。", "info");
            catch exception
                if strcmp(exception.identifier, 'LFP:UserCancelled')
                    app.LastRunError = "";
                    app.setStatus("本次运行已取消；上一份成功结果仍保留。", "warning");
                    app.logMessage("用户取消了本次运行。", "warning");
                else
                    app.LastRunError = string(exception.message);
                    app.setStatus("本次运行失败；上一份成功结果仍保留。", "error");
                    app.logMessage("运行失败：" + string(exception.message), "error");
                    app.showError("分析失败", exception);
                end
            end
        end

        function onCancel(app, ~, ~)
            if app.IsRunning
                app.CancelRequested = true;
                app.setStatus("已请求取消，将在当前分析阶段结束后停止。", "warning");
            end
        end

        function onRedraw(app, ~, ~)
            if app.IsRunning, return; end
            if isempty(fieldnames(app.Data)), return; end
            try
                app.Config = app.readConfigFromUi();
                app.renderAll();
                app.Cache.plotValid = true;
                app.setStatus("已根据当前显示参数重新绘图。", "info");
            catch exception
                app.showError("重新绘图失败", exception);
            end
        end

        function onChannelChanged(app, ~, ~)
            if app.IsRunning || isempty(fieldnames(app.Data)), return; end
            try
                app.renderRaw();
                app.setStatus("已更新通道显示；分析结果仍使用上一次运行快照。", "info");
            catch exception
                app.showError("通道显示失败", exception);
            end
        end

        function onBandCellEdit(app, ~, ~)
            if ~app.IsRunning
                app.invalidateStage("band", "频段边界已变更，需重新计算频段功率。");
            end
        end

        function addBand(app, ~, ~)
            raw = app.Controls.BandTable.Data;
            if isempty(raw), raw = cell(0, 3); end
            index = size(raw, 1) + 1;
            raw(index, :) = {['band' num2str(index)], 1, 2};
            app.Controls.BandTable.Data = raw;
            app.invalidateStage('band', '已新增频段，需重新计算频段功率。');
        end

        function removeBand(app, ~, ~)
            raw = app.Controls.BandTable.Data;
            if isempty(raw), return; end
            if size(raw, 1) <= 1
                app.showWarning('无法删除', '至少保留一个频段。');
                return;
            end
            raw(end, :) = [];
            app.Controls.BandTable.Data = raw;
            app.invalidateStage('band', '已删除频段，需重新计算频段功率。');
        end
    end

    methods (Access=private)
        function buildUi(app, visible)
            app.Figure = uifigure('Name', 'SceneRay LFP 分析工具', 'NumberTitle', 'off', ...
                'Color', [0.96 0.96 0.96], 'Position', [80 60 1560 940], ...
                'Visible', char(visible), 'CloseRequestFcn', @(src,event)app.closeApp(src,event));
            outer = uigridlayout(app.Figure, [3 3]);
            outer.RowHeight = {44, '1x', 38};
            outer.ColumnWidth = {300, 360, '1x'};
            outer.Padding = [6 6 6 6];

            toolbar = uipanel(outer, 'BorderType', 'none'); toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
            tg = uigridlayout(toolbar, [1 7]); tg.ColumnWidth = {100, 100, 100, 100, 150, '1x', 140}; tg.Padding = [0 0 0 0];
            app.Controls.ImportButton = uibutton(tg, 'Text', '导入 CSV', 'ButtonPushedFcn', @(s,e)app.onImport(s,e));
            app.Controls.LoadConfigButton = uibutton(tg, 'Text', '加载配置', 'ButtonPushedFcn', @(s,e)app.onLoadConfig(s,e));
            app.Controls.SaveConfigButton = uibutton(tg, 'Text', '保存配置', 'ButtonPushedFcn', @(s,e)app.onSaveConfig(s,e));
            app.Controls.SaveResultsButton = uibutton(tg, 'Text', '保存结果', 'ButtonPushedFcn', @(s,e)app.onSaveResults(s,e));
            app.Controls.StatusLabel = uilabel(tg, 'Text', '未加载数据', 'HorizontalAlignment', 'center');
            app.Controls.FileLabel = uilabel(tg, 'Text', '', 'HorizontalAlignment', 'left');
            app.Controls.DependencyLabel = uilabel(tg, 'Text', '', 'HorizontalAlignment', 'right');

            left = uipanel(outer, 'Title', '数据与运行'); left.Layout.Row = 2; left.Layout.Column = 1;
            lg = uigridlayout(left, [8 1]); lg.RowHeight = {105, 145, 50, 50, 120, 30, 30, '1x'}; lg.Padding = [5 5 5 5];
            app.Controls.InfoArea = uitextarea(lg, 'Editable', 'off', 'Value', {'未加载数据'});
            app.Controls.ChannelList = uilistbox(lg, 'Multiselect', 'on', 'Items', {'(未加载)'}, 'Value', {'(未加载)'}, ...
                'ValueChangedFcn', @(s,e)app.onChannelChanged(s,e));
            app.Controls.AnalysisRangePanel = uipanel(lg, 'Title', '分析时间范围 (s)');
            ar = uigridlayout(app.Controls.AnalysisRangePanel, [1 4]); ar.ColumnWidth = {36, 90, 36, 90};
            uilabel(ar, 'Text', '起始'); app.Controls.AnalysisStart = uieditfield(ar, 'numeric', 'Value', 0, 'ValueChangedFcn', @(s,e)app.markChanged('data'));
            uilabel(ar, 'Text', '结束'); app.Controls.AnalysisEnd = uieditfield(ar, 'numeric', 'Value', 0, 'ValueChangedFcn', @(s,e)app.markChanged('data'));
            app.Controls.DisplayRangePanel = uipanel(lg, 'Title', '波形显示范围 (s)');
            dr = uigridlayout(app.Controls.DisplayRangePanel, [1 4]); dr.ColumnWidth = {36, 90, 36, 90};
            uilabel(dr, 'Text', '起始'); app.Controls.DisplayStart = uieditfield(dr, 'numeric', 'Value', 0, 'ValueChangedFcn', @(s,e)app.markChanged('plot'));
            uilabel(dr, 'Text', '结束'); app.Controls.DisplayEnd = uieditfield(dr, 'numeric', 'Value', 0, 'ValueChangedFcn', @(s,e)app.markChanged('plot'));
            modulePanel = uipanel(lg, 'Title', '分析模块'); mg = uigridlayout(modulePanel, [4 1]);
            app.Controls.ArtifactCheck = uicheckbox(mg, 'Text', '伪迹检测/标记', 'Value', true, 'ValueChangedFcn', @(s,e)app.markChanged('artifact'));
            app.Controls.PsdCheck = uicheckbox(mg, 'Text', 'PSD', 'Value', true, 'ValueChangedFcn', @(s,e)app.markChanged('psd'));
            app.Controls.FooofCheck = uicheckbox(mg, 'Text', 'FOOOF 风格周期/非周期拟合', 'Value', true, 'ValueChangedFcn', @(s,e)app.markChanged('model'));
            app.Controls.BandCheck = uicheckbox(mg, 'Text', '频段功率', 'Value', true, 'ValueChangedFcn', @(s,e)app.markChanged('band'));
            autoPanel = uipanel(lg, 'BorderType', 'none'); ag = uigridlayout(autoPanel, [1 1]);
            app.Controls.AutoSaveCheck = uicheckbox(ag, 'Text', '运行成功后自动保存到输出目录', 'Value', false);
            outputPanel = uipanel(lg, 'BorderType', 'none'); og = uigridlayout(outputPanel, [1 2]); og.ColumnWidth = {'1x', 70};
            app.Controls.OutputFolder = uieditfield(og, 'text', 'Value', 'results');
            app.Controls.BrowseOutputButton = uibutton(og, 'Text', '浏览', 'ButtonPushedFcn', @(s,e)app.onBrowseOutput(s,e));
            app.Controls.LogArea = uitextarea(lg, 'Editable', 'off', 'Value', {'日志：'});

            middle = uipanel(outer, 'Title', '参数（修改后需重新运行）'); middle.Layout.Row = 2; middle.Layout.Column = 2;
            app.buildParameterTabs(middle);

            right = uipanel(outer, 'Title', '结果与图形'); right.Layout.Row = 2; right.Layout.Column = 3;
            app.buildResultTabs(right);

            bottom = uipanel(outer, 'BorderType', 'none'); bottom.Layout.Row = 3; bottom.Layout.Column = [1 3];
            bg = uigridlayout(bottom, [1 6]); bg.ColumnWidth = {125, 125, 125, 100, '1x', 260}; bg.Padding = [0 0 0 0];
            app.Controls.RunButton = uibutton(bg, 'Text', '运行所选分析', 'ButtonPushedFcn', @(s,e)app.onRun(s,e));
            app.Controls.CancelButton = uibutton(bg, 'Text', '取消', 'Enable', 'off', 'ButtonPushedFcn', @(s,e)app.onCancel(s,e));
            app.Controls.RedrawButton = uibutton(bg, 'Text', '重新绘图', 'ButtonPushedFcn', @(s,e)app.onRedraw(s,e));
            app.Controls.ProgressLabel = uilabel(bg, 'Text', '进度 0%', 'HorizontalAlignment', 'center');
            app.Controls.RunInfoLabel = uilabel(bg, 'Text', '原始数据保留；伪迹默认以 mask/NaN 显示', 'HorizontalAlignment', 'left');
            app.Controls.ResultStatusLabel = uilabel(bg, 'Text', '结果状态：未运行', 'HorizontalAlignment', 'right');
        end

        function buildParameterTabs(app, parent)
            tabs = uitabgroup(parent); app.Tabs.Parameter = tabs;
            artifactTab = uitab(tabs, 'Title', '伪迹');
            g = uigridlayout(artifactTab, [12 2]); g.ColumnWidth = {170, '1x'}; g.RowHeight = repmat({26}, 1, 12);
            app.Controls.ArtifactMethod = app.addDropDown(g, 1, '方法', {'native'}, 'native', 'artifact');
            app.Controls.ArtifactAmplitudeZ = app.addNumeric(g, 2, '振幅阈值 (z)', app.Config.artifact.amplitudeZ, 'artifact');
            app.Controls.ArtifactDerivativeZ = app.addNumeric(g, 3, '跳变阈值 (z)', app.Config.artifact.derivativeZ, 'artifact');
            app.Controls.ArtifactPadding = app.addNumeric(g, 4, '前后扩展 (s)', app.Config.artifact.paddingSeconds, 'artifact');
            app.Controls.ArtifactStrictMode = app.addCheck(g, 5, '严格短窗检测', app.Config.artifact.strictMode, 'artifact');
            app.Controls.ArtifactHighpass = app.addNumeric(g, 6, '严格高频边界 (Hz)', app.Config.artifact.strictHighpassHz, 'artifact');
            app.Controls.ArtifactStrictHFZ = app.addNumeric(g, 7, '严格高频阈值 (z)', app.Config.artifact.strictHighFrequencyZ, 'artifact');
            app.Controls.ArtifactStrictDerivativeZ = app.addNumeric(g, 8, '严格导数阈值 (z)', app.Config.artifact.strictDerivativeZ, 'artifact');
            app.Controls.ArtifactStrictRangeZ = app.addNumeric(g, 9, '严格局部范围阈值 (z)', app.Config.artifact.strictRangeZ, 'artifact');
            app.Controls.ArtifactLineNoise = app.addCheck(g, 10, '时间域标记工频（默认关闭）', app.Config.artifact.lineNoiseDetection, 'artifact');
            app.Controls.ArtifactReconstruct = app.addCheck(g, 11, '伪迹重建（当前未实现）', false, 'artifact');
            app.Controls.ArtifactReconstruct.Enable = 'off';
            app.Controls.ArtifactMethodStatus = uilabel(g, 'Text', ''); app.Controls.ArtifactMethodStatus.Layout.Row = 12; app.Controls.ArtifactMethodStatus.Layout.Column = [1 3];

            psdTab = uitab(tabs, 'Title', 'PSD');
            g = uigridlayout(psdTab, [10 2]); g.ColumnWidth = {170, '1x'}; g.RowHeight = repmat({26}, 1, 10);
            app.Controls.PsdWindow = app.addNumeric(g, 1, '窗长 (s)', app.Config.psd.windowLengthSec, 'psd');
            app.Controls.PsdOverlap = app.addNumeric(g, 2, '重叠比例', app.Config.psd.overlapFraction, 'psd');
            app.Controls.PsdNfft = app.addNumeric(g, 3, 'NFFT（0=自动）', app.Config.psd.nfft, 'psd');
            app.Controls.PsdFreqLow = app.addNumeric(g, 4, 'PSD 下限 (Hz)', app.Config.psd.frequencyRange(1), 'psd');
            app.Controls.PsdFreqHigh = app.addNumeric(g, 5, 'PSD 上限 (Hz)', app.Config.psd.frequencyRange(2), 'psd');
            app.Controls.PsdMaxArtifact = app.addNumeric(g, 6, '允许伪迹比例', app.Config.psd.maxArtifactFraction, 'psd');
            app.Controls.PsdExclude = app.addCheck(g, 7, '排除含伪迹窗口', app.Config.psd.excludeArtifacts, 'psd');
            app.Controls.PsdAggregation = app.addDropDown(g, 8, '窗口聚合', {'mean', 'median'}, char(app.Config.psd.aggregationMethod), 'psd');
            label = uilabel(g, 'Text', 'PSD 为线性功率；显示时可转 dB'); label.Layout.Row = 9; label.Layout.Column = [1 3];
            app.Controls.PsdInfo = uilabel(g, 'Text', ''); app.Controls.PsdInfo.Layout.Row = 10; app.Controls.PsdInfo.Layout.Column = [1 3];

            fooofTab = uitab(tabs, 'Title', 'FOOOF');
            g = uigridlayout(fooofTab, [10 2]); g.ColumnWidth = {170, '1x'}; g.RowHeight = repmat({26}, 1, 10);
            app.Controls.FooofFreqLow = app.addNumeric(g, 1, '拟合下限 (Hz)', app.Config.fooof.frequencyRange(1), 'model');
            app.Controls.FooofFreqHigh = app.addNumeric(g, 2, '拟合上限 (Hz)', app.Config.fooof.frequencyRange(2), 'model');
            app.Controls.FooofWidthLow = app.addNumeric(g, 3, '峰宽下限 (Hz)', app.Config.fooof.peakWidthLimits(1), 'model');
            app.Controls.FooofWidthHigh = app.addNumeric(g, 4, '峰宽上限 (Hz)', app.Config.fooof.peakWidthLimits(2), 'model');
            app.Controls.FooofMaxPeaks = app.addNumeric(g, 5, '最大峰数', app.Config.fooof.maxNumberPeaks, 'model');
            app.Controls.FooofMinHeight = app.addNumeric(g, 6, '最小峰高 (log10)', app.Config.fooof.minPeakHeight, 'model');
            app.Controls.FooofThreshold = app.addNumeric(g, 7, '峰检测阈值 (z)', app.Config.fooof.peakThreshold, 'model');
            app.Controls.FooofInterpolate = app.addCheck(g, 8, '拟合前插值 40 Hz 谐波', app.Config.fooof.interpolateLineNoise, 'model');
            label = uilabel(g, 'Text', '模式：fixed / no-knee（native MATLAB）'); label.Layout.Row = 9; label.Layout.Column = [1 3];
            app.Controls.FooofInfo = uilabel(g, 'Text', ''); app.Controls.FooofInfo.Layout.Row = 10; app.Controls.FooofInfo.Layout.Column = [1 3];

            bandTab = uitab(tabs, 'Title', '频段');
            bg = uigridlayout(bandTab, [3 3]); bg.RowHeight = {'1x', 32, 28}; bg.ColumnWidth = {'1x', 90, 90};
            app.Controls.BandTable = uitable(bg, 'ColumnName', {'名称', '下限 (Hz)', '上限 (Hz)'}, ...
                'ColumnEditable', [true true true], 'CellEditCallback', @(s,e)app.onBandCellEdit(s,e));
            app.Controls.BandTable.Layout.Row = 1; app.Controls.BandTable.Layout.Column = [1 3];
            bands = app.Config.bands; names = fieldnames(bands); bandData = cell(numel(names), 3);
            for k = 1:numel(names), bandData{k,1} = names{k}; bandData{k,2} = bands.(names{k})(1); bandData{k,3} = bands.(names{k})(2); end
            app.Controls.BandTable.Data = bandData;
            app.Controls.BandMetric = uidropdown(bg, 'Items', {'totalPower', 'relativePower', 'logTotalPower', 'aperiodicPower', 'periodicPower'}, ...
                'Value', 'totalPower', 'ValueChangedFcn', @(s,e)app.markChanged('plot')); app.Controls.BandMetric.Layout.Row = 2; app.Controls.BandMetric.Layout.Column = 1;
            app.Controls.BandAddButton = uibutton(bg, 'Text', '添加', 'ButtonPushedFcn', @(s,e)app.addBand(s,e)); app.Controls.BandAddButton.Layout.Row = 2; app.Controls.BandAddButton.Layout.Column = 2;
            app.Controls.BandRemoveButton = uibutton(bg, 'Text', '删除', 'ButtonPushedFcn', @(s,e)app.removeBand(s,e)); app.Controls.BandRemoveButton.Layout.Row = 2; app.Controls.BandRemoveButton.Layout.Column = 3;
            app.Controls.BandDefaultsButton = uibutton(bg, 'Text', '恢复默认', 'ButtonPushedFcn', @(s,e)app.restoreDefaultBands(s,e)); app.Controls.BandDefaultsButton.Layout.Row = 3; app.Controls.BandDefaultsButton.Layout.Column = 1;
            label = uilabel(bg, 'Text', '背景校正功率与原始总功率分开保存'); label.Layout.Row = 3; label.Layout.Column = [2 3];

            plotTab = uitab(tabs, 'Title', '绘图');
            g = uigridlayout(plotTab, [8 2]); g.ColumnWidth = {170, '1x'}; g.RowHeight = repmat({26}, 1, 8);
            app.Controls.PlotFreqLow = app.addNumeric(g, 1, '显示频率下限 (Hz)', app.Config.plot.frequencyRange(1), 'plot');
            app.Controls.PlotFreqHigh = app.addNumeric(g, 2, '显示频率上限 (Hz)', app.Config.plot.frequencyRange(2), 'plot');
            app.Controls.PlotMaxSeconds = app.addNumeric(g, 3, '最大显示时长 (s)', app.Config.plot.maxPlotSeconds, 'plot');
            app.Controls.PlotFreqScale = app.addDropDown(g, 4, '频率轴', {'linear', 'log'}, char(app.Config.plot.frequencyScale), 'plot');
            app.Controls.PlotPowerScale = app.addDropDown(g, 5, '功率轴', {'linear', 'log10', 'dB'}, char(app.Config.plot.powerScale), 'plot');
            app.Controls.PlotShowLabels = app.addCheck(g, 6, '显示伪迹标签', app.Config.plot.showArtifactLabels, 'plot');
            app.Controls.PlotFontSize = app.addNumeric(g, 7, '字体大小', app.Config.plot.fontSize, 'plot');
            label = uilabel(g, 'Text', '绘图范围独立于 PSD/FOOOF/频段计算范围'); label.Layout.Row = 8; label.Layout.Column = [1 3];
        end

        function buildResultTabs(app, parent)
            tabs = uitabgroup(parent); app.Tabs.Results = tabs;
            rawTab = uitab(tabs, 'Title', '原始与伪迹');
            g = uigridlayout(rawTab, [3 1]); g.RowHeight = {'1x', '1x', 150};
            app.Controls.RawAxes = uiaxes(g); title(app.Controls.RawAxes, 'Raw signal'); grid(app.Controls.RawAxes, 'on');
            app.Controls.CleanAxes = uiaxes(g); title(app.Controls.CleanAxes, 'Clean/display (NaN excluded)'); grid(app.Controls.CleanAxes, 'on');
            app.Controls.ArtifactTable = uitable(g, 'ColumnName', {'artifactType','startSample','endSample','startTime','endTime','channel','score','threshold','method'});

            psdTab = uitab(tabs, 'Title', 'PSD'); g = uigridlayout(psdTab, [2 1]); g.RowHeight = {'1x', 70};
            app.Controls.PsdAxes = uiaxes(g); grid(app.Controls.PsdAxes, 'on');
            app.Controls.PsdInfoResult = uitextarea(g, 'Editable', 'off', 'Value', {'尚未计算 PSD'});

            fooofTab = uitab(tabs, 'Title', 'FOOOF'); g = uigridlayout(fooofTab, [2 1]); g.RowHeight = {'1x', 170};
            app.Controls.FooofAxes = uiaxes(g); grid(app.Controls.FooofAxes, 'on');
            app.Controls.FooofTable = uitable(g, 'ColumnName', {'CF_Hz','PW_log10','BW_Hz','peakBand'});

            bandTab = uitab(tabs, 'Title', '频段功率'); g = uigridlayout(bandTab, [2 1]); g.RowHeight = {'1x', 170};
            app.Controls.BandAxes = uiaxes(g); grid(app.Controls.BandAxes, 'on');
            app.Controls.BandResultTable = uitable(g);

            summaryTab = uitab(tabs, 'Title', '摘要'); g = uigridlayout(summaryTab, [2 2]); g.RowHeight = {'1x', '1x'}; g.ColumnWidth = {'1x', '1x'};
            app.Controls.SummaryPsdAxes = uiaxes(g); grid(app.Controls.SummaryPsdAxes, 'on');
            app.Controls.SummaryFitAxes = uiaxes(g); grid(app.Controls.SummaryFitAxes, 'on');
            app.Controls.SummaryBandAxes = uiaxes(g); grid(app.Controls.SummaryBandAxes, 'on');
            app.Controls.SummaryArtifactAxes = uiaxes(g); grid(app.Controls.SummaryArtifactAxes, 'on');
        end

        function control = addNumeric(app, grid, row, labelText, value, stage)
            label = uilabel(grid, 'Text', labelText); label.Layout.Row = row; label.Layout.Column = 1;
            control = uieditfield(grid, 'numeric', 'Value', value, 'ValueChangedFcn', @(s,e)app.markChanged(stage));
            control.Layout.Row = row; control.Layout.Column = 2;
        end

        function control = addDropDown(app, grid, row, labelText, items, value, stage)
            label = uilabel(grid, 'Text', labelText); label.Layout.Row = row; label.Layout.Column = 1;
            control = uidropdown(grid, 'Items', items, 'Value', value, 'ValueChangedFcn', @(s,e)app.markChanged(stage));
            control.Layout.Row = row; control.Layout.Column = 2;
        end

        function control = addCheck(app, grid, row, labelText, value, stage)
            control = uicheckbox(grid, 'Text', labelText, 'Value', value, 'ValueChangedFcn', @(s,e)app.markChanged(stage));
            control.Layout.Row = row; control.Layout.Column = [1 3];
        end

        function refreshDependencyStatus(app)
            hasFieldTrip = exist('ft_artifact_zvalue', 'file') == 2;
            if hasFieldTrip
                app.Controls.ArtifactMethod.Items = {'native', 'fieldtrip'};
                app.Controls.DependencyLabel.Text = 'FieldTrip 可用';
                app.Controls.ArtifactMethodStatus.Text = 'FieldTrip 可选；native 默认按通道检测。';
            else
                app.Controls.ArtifactMethod.Items = {'native'};
                app.Controls.DependencyLabel.Text = 'native MATLAB 路径';
                app.Controls.ArtifactMethodStatus.Text = 'FieldTrip 未找到，已禁用；native fallback 可直接运行。';
            end
        end

        function openImportDialog(app, filename)
            try
                inspection = lfp_inspect_csv(filename);
            catch exception
                app.showError("CSV 检查失败", exception); return;
            end
            dialog = uifigure('Name', 'CSV 导入确认', 'WindowStyle', 'modal', 'Position', [120 100 1200 700]);
            dg = uigridlayout(dialog, [8 4]); dg.RowHeight = {230, 28, 28, 28, 28, 28, '1x', 36}; dg.ColumnWidth = {160, 180, 160, '1x'};
            preview = uitable(dg, 'Data', inspection.preview, 'ColumnEditable', false); preview.Layout.Row = 1; preview.Layout.Column = [1 4];
            note = uilabel(dg, 'Text', "检测结果：" + inspection.formatSuggestion + " | " + strjoin(inspection.warnings, " "), 'WordWrap', 'on'); note.Layout.Row = 2; note.Layout.Column = [1 4];
            uilabel(dg, 'Text', '分隔符'); delimiter = uidropdown(dg, 'Items', {',', ';', 'tab'}, 'Value', ','); delimiter.Layout.Row = 3; delimiter.Layout.Column = 2;
            uilabel(dg, 'Text', '表头行（0=无）'); header = uieditfield(dg, 'numeric', 'Value', inspection.headerRowSuggestion); header.Layout.Row = 3; header.Layout.Column = 4;
            uilabel(dg, 'Text', '数据起始行'); dataStart = uieditfield(dg, 'numeric', 'Value', inspection.dataStartRowSuggestion); dataStart.Layout.Row = 4; dataStart.Layout.Column = 2;
            uilabel(dg, 'Text', '时间列（0=无）'); timeColumn = uieditfield(dg, 'numeric', 'Value', inspection.timeColumnSuggestion); timeColumn.Layout.Row = 4; timeColumn.Layout.Column = 4;
            uilabel(dg, 'Text', '信号列（如 2,3）'); signals = uieditfield(dg, 'text', 'Value', strjoin(string(inspection.signalColumnsSuggestion), ',')); signals.Layout.Row = 5; signals.Layout.Column = 2;
            uilabel(dg, 'Text', '数据方向'); direction = uidropdown(dg, 'Items', {'samples_by_channels', 'channels_by_samples'}, 'Value', 'samples_by_channels'); direction.Layout.Row = 5; direction.Layout.Column = 4;
            uilabel(dg, 'Text', '采样率 (Hz)'); fs = uieditfield(dg, 'text', 'Value', app.defaultFsText(inspection)); fs.Layout.Row = 6; fs.Layout.Column = 2;
            uilabel(dg, 'Text', '单位'); units = uieditfield(dg, 'text', 'Value', 'uV'); units.Layout.Row = 6; units.Layout.Column = 4;
            uilabel(dg, 'Text', '幅值换算'); scale = uieditfield(dg, 'numeric', 'Value', 1); scale.Layout.Row = 7; scale.Layout.Column = 2;
            uilabel(dg, 'Text', '时间单位'); timeUnit = uidropdown(dg, 'Items', {'s', 'ms'}, 'Value', 's'); timeUnit.Layout.Row = 7; timeUnit.Layout.Column = 4;
            buttons = uigridlayout(dg, [1 3]); buttons.Layout.Row = 8; buttons.Layout.Column = [1 4]; buttons.ColumnWidth = {'1x', 120, 120};
            status = uilabel(buttons, 'Text', '请确认自动识别结果；歧义时修改参数。');
            importButton = uibutton(buttons, 'Text', '确认导入', 'ButtonPushedFcn', @(s,e)app.finishImport(dialog, filename, struct('delimiter', delimiter, 'header', header, 'dataStart', dataStart, 'timeColumn', timeColumn, 'signals', signals, 'direction', direction, 'fs', fs, 'units', units, 'scale', scale, 'timeUnit', timeUnit, 'status', status, 'inspection', inspection)));
            cancelButton = uibutton(buttons, 'Text', '取消', 'ButtonPushedFcn', @(s,e)uiresume(dialog)); %#ok<NASGU>
            dialog.CloseRequestFcn = @(s,e)uiresume(dialog);
            uiwait(dialog);
            if isgraphics(dialog), delete(dialog); end
        end

        function finishImport(app, dialog, filename, controls)
            try
                delimiter = string(controls.delimiter.Value); if delimiter == "tab", delimiter = string(char(9)); end
                signalColumns = app.parseIndexList(controls.signals.Value);
                fs = str2double(string(controls.fs.Value)); if ~isfinite(fs), fs = NaN; end
                header = controls.header.Value; if ~isfinite(header), header = NaN; end
                dataStart = controls.dataStart.Value; if ~isfinite(dataStart), dataStart = NaN; end
                timeColumn = controls.timeColumn.Value; if ~isfinite(timeColumn), timeColumn = 0; end
                [data, ~] = lfp_import_csv_configured(filename, Delimiter=delimiter, HeaderRow=header, ...
                    DataStartRow=dataStart, TimeColumn=timeColumn, SignalColumns=signalColumns, ...
                    DataDirection=string(controls.direction.Value), SamplingRateHz=fs, ...
                    Units=string(controls.units.Value), AmplitudeScale=controls.scale.Value, ...
                    TimeUnit=string(controls.timeUnit.Value), Inspection=controls.inspection);
                if isfield(data.metadata, 'timeValidation') && data.metadata.timeValidation.isIrregular
                    controls.status.Text = '时间不规则：已导入，但运行均匀采样算法前需修正。';
                    app.logMessage("检测到不规则时间间隔，分析按钮会阻止 PSD 运行。", "warning");
                end
                if isfinite(fs) && isfield(data.metadata, 'estimatedSamplingRateHz') && ...
                        isfinite(data.metadata.estimatedSamplingRateHz) && ...
                        abs(fs - data.metadata.estimatedSamplingRateHz) / max(data.metadata.estimatedSamplingRateHz, eps) > 0.01
                    controls.status.Text = '输入采样率与时间列估计值差异超过 1%，请复核。';
                    app.logMessage("输入采样率与时间列估计值不一致，请复核导入设置。", "warning");
                end
                app.setData(data);
                uiresume(dialog);
            catch exception
                uialert(dialog, string(exception.message), '导入失败');
            end
        end

        function setData(app, data)
            if ~isfield(data.metadata, 'sourceFilePath'), data.metadata.sourceFilePath = ""; end
            if ~isfield(data.metadata, 'displayName')
                data.metadata.displayName = string(data.metadata.sourceFileName);
            end
            app.Data = data;
            app.CleanData = struct(); app.AnalysisData = struct(); app.ArtifactResult = struct();
            app.BeforePsd = struct(); app.PsdResult = struct(); app.ModelResult = struct([]); app.BandResult = struct();
            app.Cache = struct('artifactValid', false, 'psdValid', false, 'modelValid', false, 'bandValid', false, 'plotValid', false);
            labels = string(data.channelLabels(:));
            app.Controls.ChannelList.Items = cellstr(labels);
            app.Controls.ChannelList.Value = cellstr(labels);
            duration = (size(data.signal, 1) - 1) / data.fs;
            app.Controls.AnalysisStart.Value = 0; app.Controls.AnalysisEnd.Value = duration;
            app.Controls.DisplayStart.Value = 0; app.Controls.DisplayEnd.Value = duration;
            app.Controls.FileLabel.Text = string(data.metadata.displayName);
            app.updateDataInfo();
            app.renderRaw();
            app.invalidateAll("已加载新数据，请运行所选分析。");
            app.logMessage("已导入 " + string(data.metadata.displayName) + "（" + string(size(data.signal,2)) + " 通道）", "info");
        end

        function updateDataInfo(app)
            if isempty(fieldnames(app.Data))
                app.Controls.InfoArea.Value = {'未加载数据'}; return;
            end
            d = app.Data; n = size(d.signal, 1); c = size(d.signal, 2); duration = (n - 1) / d.fs;
            missing = nnz(~isfinite(d.signal));
            ipg = ""; if isfield(d.metadata, 'ipgSN'), ipg = string(d.metadata.ipgSN); end
            infoLines = [ ...
                "文件：" + string(d.metadata.sourceFileName); ...
                "IPG SN：" + ipg; ...
                string(sprintf('通道数：%d | 样本数：%d', c, n)); ...
                string(sprintf('采样率：%.6g Hz | 时长：%.3f s', d.fs, duration)); ...
                "单位：" + string(d.units); ...
                string(sprintf('NaN/Inf：%d', missing))];
            % uitextarea.Value requires a string array or an N-by-1 cellstr;
            % do not pass a cell array containing string scalar elements.
            app.Controls.InfoArea.Value = infoLines;
        end

        function cfg = readConfigFromUi(app)
            cfg = app.Config;
            cfg.artifact.method = string(app.Controls.ArtifactMethod.Value);
            cfg.artifact.amplitudeZ = app.Controls.ArtifactAmplitudeZ.Value;
            cfg.artifact.derivativeZ = app.Controls.ArtifactDerivativeZ.Value;
            cfg.artifact.paddingSeconds = app.Controls.ArtifactPadding.Value;
            cfg.artifact.strictMode = logical(app.Controls.ArtifactStrictMode.Value);
            cfg.artifact.strictHighpassHz = app.Controls.ArtifactHighpass.Value;
            cfg.artifact.strictHighFrequencyZ = app.Controls.ArtifactStrictHFZ.Value;
            cfg.artifact.strictDerivativeZ = app.Controls.ArtifactStrictDerivativeZ.Value;
            cfg.artifact.strictRangeZ = app.Controls.ArtifactStrictRangeZ.Value;
            cfg.artifact.lineNoiseDetection = logical(app.Controls.ArtifactLineNoise.Value);
            cfg.artifact.reconstruct = false;
            cfg.psd.windowLengthSec = app.Controls.PsdWindow.Value;
            cfg.psd.overlapFraction = app.Controls.PsdOverlap.Value;
            cfg.psd.nfft = app.Controls.PsdNfft.Value;
            cfg.psd.frequencyRange = [app.Controls.PsdFreqLow.Value app.Controls.PsdFreqHigh.Value];
            cfg.psd.maxArtifactFraction = app.Controls.PsdMaxArtifact.Value;
            cfg.psd.excludeArtifacts = logical(app.Controls.PsdExclude.Value);
            cfg.psd.aggregationMethod = string(app.Controls.PsdAggregation.Value);
            cfg.fooof.frequencyRange = [app.Controls.FooofFreqLow.Value app.Controls.FooofFreqHigh.Value];
            cfg.fooof.peakWidthLimits = [app.Controls.FooofWidthLow.Value app.Controls.FooofWidthHigh.Value];
            cfg.fooof.maxNumberPeaks = app.Controls.FooofMaxPeaks.Value;
            cfg.fooof.minPeakHeight = app.Controls.FooofMinHeight.Value;
            cfg.fooof.peakThreshold = app.Controls.FooofThreshold.Value;
            cfg.fooof.aperiodicMode = "fixed";
            cfg.fooof.interpolateLineNoise = logical(app.Controls.FooofInterpolate.Value);
            cfg.bands = app.readBandsFromTable();
            cfg.plot.frequencyRange = [app.Controls.PlotFreqLow.Value app.Controls.PlotFreqHigh.Value];
            cfg.plot.maxPlotSeconds = app.Controls.PlotMaxSeconds.Value;
            cfg.plot.frequencyScale = string(app.Controls.PlotFreqScale.Value);
            cfg.plot.powerScale = string(app.Controls.PlotPowerScale.Value);
            cfg.plot.showArtifactLabels = logical(app.Controls.PlotShowLabels.Value);
            cfg.plot.fontSize = app.Controls.PlotFontSize.Value;
        end

        function populateControlsFromConfig(app)
            cfg = app.Config;
            availableMethods = string(app.Controls.ArtifactMethod.Items);
            if any(availableMethods == string(cfg.artifact.method))
                app.Controls.ArtifactMethod.Value = char(cfg.artifact.method);
            else
                app.Controls.ArtifactMethod.Value = 'native';
                app.Config.artifact.method = "native";
            end
            app.Controls.ArtifactAmplitudeZ.Value = cfg.artifact.amplitudeZ; app.Controls.ArtifactDerivativeZ.Value = cfg.artifact.derivativeZ;
            app.Controls.ArtifactPadding.Value = cfg.artifact.paddingSeconds; app.Controls.ArtifactStrictMode.Value = cfg.artifact.strictMode;
            app.Controls.ArtifactHighpass.Value = cfg.artifact.strictHighpassHz; app.Controls.ArtifactStrictHFZ.Value = cfg.artifact.strictHighFrequencyZ;
            app.Controls.ArtifactStrictDerivativeZ.Value = cfg.artifact.strictDerivativeZ; app.Controls.ArtifactStrictRangeZ.Value = cfg.artifact.strictRangeZ;
            app.Controls.ArtifactLineNoise.Value = cfg.artifact.lineNoiseDetection;
            app.Controls.PsdWindow.Value = cfg.psd.windowLengthSec; app.Controls.PsdOverlap.Value = cfg.psd.overlapFraction; app.Controls.PsdNfft.Value = cfg.psd.nfft;
            app.Controls.PsdFreqLow.Value = cfg.psd.frequencyRange(1); app.Controls.PsdFreqHigh.Value = cfg.psd.frequencyRange(2); app.Controls.PsdMaxArtifact.Value = cfg.psd.maxArtifactFraction;
            app.Controls.PsdExclude.Value = cfg.psd.excludeArtifacts; app.Controls.PsdAggregation.Value = char(cfg.psd.aggregationMethod);
            app.Controls.FooofFreqLow.Value = cfg.fooof.frequencyRange(1); app.Controls.FooofFreqHigh.Value = cfg.fooof.frequencyRange(2);
            app.Controls.FooofWidthLow.Value = cfg.fooof.peakWidthLimits(1); app.Controls.FooofWidthHigh.Value = cfg.fooof.peakWidthLimits(2); app.Controls.FooofMaxPeaks.Value = cfg.fooof.maxNumberPeaks;
            app.Controls.FooofMinHeight.Value = cfg.fooof.minPeakHeight; app.Controls.FooofThreshold.Value = cfg.fooof.peakThreshold; app.Controls.FooofInterpolate.Value = cfg.fooof.interpolateLineNoise;
            names = fieldnames(cfg.bands); bd = cell(numel(names), 3); for k = 1:numel(names), bd{k,1}=names{k}; bd{k,2}=cfg.bands.(names{k})(1); bd{k,3}=cfg.bands.(names{k})(2); end; app.Controls.BandTable.Data=bd;
            app.Controls.PlotFreqLow.Value = cfg.plot.frequencyRange(1); app.Controls.PlotFreqHigh.Value = cfg.plot.frequencyRange(2); app.Controls.PlotMaxSeconds.Value = cfg.plot.maxPlotSeconds;
            app.Controls.PlotFreqScale.Value = char(cfg.plot.frequencyScale); app.Controls.PlotPowerScale.Value = char(cfg.plot.powerScale); app.Controls.PlotShowLabels.Value = cfg.plot.showArtifactLabels; app.Controls.PlotFontSize.Value = cfg.plot.fontSize;
        end

        function bands = readBandsFromTable(app)
            raw = app.Controls.BandTable.Data; bands = struct('name', {}, 'rangeHz', {});
            if isempty(raw), error('LFP:InvalidBands', '至少保留一个频段。'); end
            validNames = strings(0, 1);
            for k = 1:size(raw, 1)
                name = string(raw{k,1}); low = app.cellNumber(raw{k,2}); high = app.cellNumber(raw{k,3});
                if strlength(strtrim(name)) == 0 || ~isfinite(low) || ~isfinite(high) || high <= low
                    error('LFP:InvalidBands', '频段第 %d 行名称或上下限无效。', k);
                end
                fieldName = string(matlab.lang.makeValidName(char(name)));
                if any(validNames == fieldName)
                    error('LFP:InvalidBands', '频段名称必须唯一（第 %d 行重复）。', k);
                end
                validNames(end + 1, 1) = fieldName; %#ok<AGROW>
                bands(end+1).name = name; bands(end).rangeHz = [low high]; %#ok<AGROW>
            end
            % Keep a named struct for computeBandPower compatibility.
            named = struct();
            for k = 1:numel(bands), named.(matlab.lang.makeValidName(char(bands(k).name))) = bands(k).rangeHz; end
            bands = named;
        end

        function restoreDefaultBands(app, ~, ~)
            cfg = lfpDefaultConfig(); app.Config.bands = cfg.bands;
            names = fieldnames(cfg.bands); bd = cell(numel(names), 3); for k=1:numel(names), bd{k,1}=names{k}; bd{k,2}=cfg.bands.(names{k})(1); bd{k,3}=cfg.bands.(names{k})(2); end; app.Controls.BandTable.Data=bd;
            app.invalidateStage('band', '已恢复默认频段，需重新计算频段功率。');
        end

        function markChanged(app, stage)
            if app.IsRunning, return; end
            if strcmp(stage, 'plot')
                app.Cache.plotValid = false;
                app.setStatus('绘图参数已变更，可点击“重新绘图”。', 'warning');
            else
                app.invalidateStage(stage, '分析参数已变更，结果需要重新计算。');
            end
        end

        function invalidateStage(app, stage, message)
            switch string(stage)
                case "data", app.Cache = struct('artifactValid', false, 'psdValid', false, 'modelValid', false, 'bandValid', false, 'plotValid', false);
                case "artifact", app.Cache.artifactValid=false; app.Cache.psdValid=false; app.Cache.modelValid=false; app.Cache.bandValid=false;
                case "psd", app.Cache.psdValid=false; app.Cache.modelValid=false; app.Cache.bandValid=false;
                case "model", app.Cache.modelValid=false; app.Cache.bandValid=false;
                case "band", app.Cache.bandValid=false;
            end
            app.Controls.ResultStatusLabel.Text = "结果状态：" + string(message);
            app.setStatus(message, 'warning');
        end

        function invalidateAll(app, message)
            app.Cache = struct('artifactValid', false, 'psdValid', false, 'modelValid', false, 'bandValid', false, 'plotValid', false);
            app.Controls.ResultStatusLabel.Text = "结果状态：" + string(message);
            app.setStatus(message, 'warning');
        end

        function channels = selectedChannels(app)
            if isempty(fieldnames(app.Data)), channels = []; return; end
            values = string(app.Controls.ChannelList.Value); labels = string(app.Data.channelLabels(:));
            channels = find(ismember(labels, values)); channels = channels(:)';
            if isempty(channels), channels = 1:size(app.Data.signal,2); end
        end

        function snapshot = makeRunSnapshot(app, cfg)
            channels = app.selectedChannels();
            snapshot = struct('cfg', cfg, 'channels', channels, 'analysisRange', ...
                [app.Controls.AnalysisStart.Value app.Controls.AnalysisEnd.Value], ...
                'displayRange', [app.Controls.DisplayStart.Value app.Controls.DisplayEnd.Value], ...
                'modules', struct('artifact', logical(app.Controls.ArtifactCheck.Value), 'psd', logical(app.Controls.PsdCheck.Value), ...
                    'fooof', logical(app.Controls.FooofCheck.Value), 'band', logical(app.Controls.BandCheck.Value)), ...
                'autoSave', logical(app.Controls.AutoSaveCheck.Value), 'outputFolder', string(app.Controls.OutputFolder.Value), ...
                'createdAt', string(datestr(now, 31)));
        end

        function validateRun(app, snapshot)
            if isempty(snapshot.channels), error('LFP:NoChannelsSelected', '至少选择一个通道。'); end
            duration = (size(app.Data.signal,1)-1) / app.Data.fs;
            r = snapshot.analysisRange;
            if numel(r) ~= 2 || any(~isfinite(r)) || r(1) < 0 || r(2) <= r(1) || r(2) > duration + 1/app.Data.fs
                error('LFP:InvalidAnalysisRange', '分析时间范围必须在数据时长内且结束时间大于起始时间。');
            end
            if snapshot.modules.psd || snapshot.modules.fooof || snapshot.modules.band
                if isfield(app.Data.metadata, 'timeValidation') && ...
                        (~app.Data.metadata.timeValidation.valid || app.Data.metadata.timeValidation.isIrregular)
                    error('LFP:IrregularSampling', '时间列不规则，已阻止均匀采样 PSD；请修正导入参数。');
                end
                if snapshot.cfg.psd.frequencyRange(2) > app.Data.fs/2
                    error('LFP:PsdAboveNyquist', 'PSD 上限不能超过 Nyquist 频率 %.6g Hz。', app.Data.fs/2);
                end
            end
            if snapshot.modules.fooof || snapshot.modules.band
                if snapshot.cfg.fooof.frequencyRange(2) > snapshot.cfg.psd.frequencyRange(2)
                    error('LFP:FooofOutsidePsd', 'FOOOF 拟合上限不能超过 PSD 上限。');
                end
            end
            if snapshot.modules.band && isempty(fieldnames(snapshot.cfg.bands)), error('LFP:InvalidBands', '至少选择一个频段。'); end
        end

        function selected = selectChannels(~, data, channels)
            selected = data; selected.signal = data.signal(:, channels); selected.channelLabels = string(data.channelLabels(channels)); selected.channelNames = selected.channelLabels; selected.channelCount = numel(channels);
            if isfield(data, 'artifacts') && isfield(data.artifacts, 'channelMask') && isequal(size(data.artifacts.channelMask,2), size(data.signal,2)), selected.artifacts.channelMask = data.artifacts.channelMask(:, channels); end
            if isfield(selected, 'metadata'), selected.metadata.selectedChannels = channels; end
        end

        function index = timeIndexForRange(~, data, range)
            first = max(1, floor(range(1) * data.fs) + 1); last = min(size(data.signal,1), ceil(range(2) * data.fs));
            index = first:last; if numel(index) < 2, error('LFP:ShortAnalysisRange', '分析范围少于两个样本。'); end
        end

        function sliced = sliceData(~, data, index)
            sliced = data; sliced.signal = data.signal(index, :); sliced.time = (0:numel(index)-1)' / data.fs;
            if isfield(data, 'cleanedSignal') && isequal(size(data.cleanedSignal), size(data.signal)), sliced.cleanedSignal = data.cleanedSignal(index, :); end
        end

        function artifact = sliceArtifact(~, artifact, index, fs)
            if isempty(fieldnames(artifact)), return; end
            if isfield(artifact, 'channelMask') && size(artifact.channelMask,1) >= max(index)
                artifact.channelMask = artifact.channelMask(index, :); artifact.sampleMask = any(artifact.channelMask,2); artifact.globalMask = artifact.sampleMask;
                artifact.retainedDuration = nnz(~artifact.globalMask) / fs;
                artifact.rejectedDuration = nnz(artifact.globalMask) / fs;
                artifact.rejectedPercentage = 100 * nnz(artifact.globalMask) / max(numel(index), 1);
                if isfield(artifact, 'events') && istable(artifact.events) && ~isempty(artifact.events)
                    firstSample = index(1); lastSample = index(end);
                    events = artifact.events;
                    keep = events.endSample >= firstSample & events.startSample <= lastSample;
                    events = events(keep, :);
                    if ~isempty(events)
                        events.startSample = max(events.startSample, firstSample) - firstSample + 1;
                        events.endSample = min(events.endSample, lastSample) - firstSample + 1;
                        events.startTime = (events.startSample - 1) ./ fs;
                        events.endTime = events.endSample ./ fs;
                    end
                    artifact.events = events;
                end
            end
        end

        function artifact = emptyArtifact(~, data)
            n = size(data.signal,1); c = size(data.signal,2);
            artifact = struct('sampleMask', false(n,1), 'channelMask', false(n,c), 'globalMask', false(n,1), ...
                'events', table(), 'badChannels', zeros(0,1), 'method', "none", 'parameters', struct(), 'summary', struct(), ...
                'retainedDuration', n/data.fs, 'rejectedDuration', 0, 'rejectedPercentage', 0, 'warnings', strings(0,1), ...
                'processingHistory', struct('operation', "artifact_not_requested", 'parameters', struct(), 'notes', "No artifact detection requested."));
        end

        function tf = compatibleArtifact(~, artifact, data)
            tf = isstruct(artifact) && isfield(artifact, 'channelMask') && isequal(size(artifact.channelMask), size(data.signal));
        end

        function model = addModelContext(~, model, data)
            labels = string(data.channelLabels(:));
            for k = 1:numel(model), model(k).channelIndex=k; model(k).channelLabel=labels(k); model(k).ipgSN=get_field_local(data.metadata,'ipgSN',"unknown"); model(k).sourceFileName=string(data.metadata.sourceFileName); end
        end

        function matrix = collectModelField(~, model, field)
            if isempty(model), matrix=[]; return; end
            nF = numel(model(1).freq); matrix = NaN(nF, numel(model));
            for k=1:numel(model), if isfield(model(k), field) && numel(model(k).(field))==nF, matrix(:,k)=model(k).(field)(:); end, end
        end

        function renderAll(app)
            app.renderRaw(); app.renderPsd(); app.renderFooof(); app.renderBand(); app.renderSummary();
        end

        function renderRaw(app)
            if isempty(fieldnames(app.Data)), return; end
            d=app.Data; channels=app.selectedChannels(); if isempty(channels), return; end
            r=[app.Controls.DisplayStart.Value app.Controls.DisplayEnd.Value];
            first=max(1,floor(r(1)*d.fs)+1); last=min(size(d.signal,1),ceil(r(2)*d.fs));
            if isfinite(app.Controls.PlotMaxSeconds.Value), last=min(last, first+max(1,round(app.Controls.PlotMaxSeconds.Value*d.fs))-1); end
            idx=first:last; t=(idx-1)'/d.fs;
            raw=d.signal(idx,channels); clean=raw;
            displayArtifactMatches = ~isempty(fieldnames(app.ArtifactResult)) && isfield(app.ArtifactResult, 'channelIndices') && isequal(app.ArtifactResult.channelIndices(:)', channels(:)');
            if displayArtifactMatches && ~isempty(fieldnames(app.CleanData)) && isfield(app.CleanData,'cleanedSignal') && size(app.CleanData.cleanedSignal,1)>=last && size(app.CleanData.cleanedSignal,2)==numel(channels)
                clean=app.CleanData.cleanedSignal(idx, :);
            elseif displayArtifactMatches && app.compatibleArtifact(app.ArtifactResult, app.selectChannels(d,channels))
                mask=app.ArtifactResult.channelMask(idx,:); clean(mask)=NaN;
            end
            rawLimits=app.finiteLimits(raw); if any(~isfinite(rawLimits)), rawLimits=[-1 1]; end
            cla(app.Controls.RawAxes); plot(app.Controls.RawAxes,t,raw,'LineWidth',0.7); hold(app.Controls.RawAxes,'on'); if displayArtifactMatches, app.addArtifactPatches(app.Controls.RawAxes, idx, rawLimits, d.fs); end; hold(app.Controls.RawAxes,'off');
            title(app.Controls.RawAxes, app.displayTitle("Raw signal"), 'Interpreter','none'); xlabel(app.Controls.RawAxes,'Time (s)'); ylabel(app.Controls.RawAxes,"Signal ("+string(d.units)+")"); app.Controls.RawAxes.YLim=rawLimits; grid(app.Controls.RawAxes,'on'); legend(app.Controls.RawAxes,cellstr(string(d.channelLabels(channels))),'Interpreter','none','Location','best');
            cla(app.Controls.CleanAxes); plot(app.Controls.CleanAxes,t,clean,'LineWidth',0.7); hold(app.Controls.CleanAxes,'on'); if displayArtifactMatches, app.addArtifactPatches(app.Controls.CleanAxes,idx,rawLimits,d.fs); end; hold(app.Controls.CleanAxes,'off');
            title(app.Controls.CleanAxes, app.displayTitle("Clean/display (artifact samples = NaN)"), 'Interpreter','none'); xlabel(app.Controls.CleanAxes,'Time (s)'); ylabel(app.Controls.CleanAxes,"Signal ("+string(d.units)+")"); app.Controls.CleanAxes.YLim=rawLimits; grid(app.Controls.CleanAxes,'on'); legend(app.Controls.CleanAxes,cellstr(string(d.channelLabels(channels))),'Interpreter','none','Location','best');
            app.updateArtifactTable();
        end

        function addArtifactPatches(app, ax, index, yLimits, fs)
            if isempty(fieldnames(app.ArtifactResult)) || ~isfield(app.ArtifactResult,'globalMask') || numel(app.ArtifactResult.globalMask) < max(index), return; end
            mask=app.ArtifactResult.globalMask(index); starts=find(diff([false;mask(:);false])==1); ends=find(diff([false;mask(:);false])==-1)-1;
            for k=1:numel(starts)
                x1=(index(starts(k))-1)/fs; x2=index(ends(k))/fs;
                patch(ax,[x1 x2 x2 x1], [yLimits(1) yLimits(1) yLimits(2) yLimits(2)], [1 0.2 0.2], 'FaceAlpha',0.14,'EdgeColor','none','HandleVisibility','off');
            end
        end

        function updateArtifactTable(app)
            if isempty(fieldnames(app.ArtifactResult)) || ~isfield(app.ArtifactResult,'events') || ~istable(app.ArtifactResult.events)
                app.Controls.ArtifactTable.Data=cell(0,9); return;
            end
            e=app.ArtifactResult.events; if isempty(e), app.Controls.ArtifactTable.Data=cell(0,9); else app.Controls.ArtifactTable.Data=table2cell(e); app.Controls.ArtifactTable.ColumnName=e.Properties.VariableNames; end
        end

        function renderPsd(app)
            cla(app.Controls.PsdAxes); if isempty(fieldnames(app.PsdResult)), app.Controls.PsdInfoResult.Value={'尚未计算 PSD'}; return; end
            p=app.PsdResult; ch=app.selectedChannels(); ch=ch(ch<=size(p.psd,2)); if isempty(ch), ch=1:size(p.psd,2); end;
            freq=p.frequencyHz; before=app.BeforePsd; hold(app.Controls.PsdAxes,'on');
            [afterValues, powerLabel] = app.displayPower(p.psd(:,ch));
            if ~isempty(fieldnames(before)) && isfield(before,'psd') && isequal(size(before.psd),size(p.psd)), [beforeValues, ~] = app.displayPower(before.psd(:,ch)); app.plotSpectrum(app.Controls.PsdAxes, freq, beforeValues, ':', [0.6 0.6 0.6], 'Before artifact exclusion'); end
            app.plotSpectrum(app.Controls.PsdAxes, freq, afterValues, '-', [0.1 0.25 0.8], 'After artifact exclusion'); hold(app.Controls.PsdAxes,'off');
            app.applyFrequencyLimits(app.Controls.PsdAxes, freq); xlabel(app.Controls.PsdAxes,'Frequency (Hz)'); ylabel(app.Controls.PsdAxes,powerLabel); title(app.Controls.PsdAxes, app.displayTitle('PSD')); grid(app.Controls.PsdAxes,'on'); legend(app.Controls.PsdAxes,'Location','best');
            app.Controls.PsdInfoResult.Value={sprintf('频率点：%d | Δf=%.6g Hz',numel(freq),p.frequencyResolutionHz),sprintf('有效窗口：%s',mat2str(p.windowCount)),sprintf('PSD 范围：[%.3g %.3g] Hz；功率单位：%s',freq(1),freq(end),p.psdUnits)};
        end

        function renderFooof(app)
            cla(app.Controls.FooofAxes); app.Controls.FooofTable.Data=cell(0,4); if isempty(app.ModelResult), return; end
            ch=app.selectedChannels(); ch=ch(ch<=numel(app.ModelResult)); if isempty(ch), ch=1; end; m=app.ModelResult(ch(1)); f=m.freq;
            valid=f>0 & isfinite(m.inputPower) & m.inputPower>0; hold(app.Controls.FooofAxes,'on'); [inputValues, powerLabel] = app.displayPower(m.inputPower); app.plotSpectrum(app.Controls.FooofAxes,f(valid),inputValues(valid),'-',[0 0 0],'Original PSD');
            if any(isfinite(m.fullModelFit)), [fullValues, ~] = app.displayPower(m.fullModelFit); app.plotSpectrum(app.Controls.FooofAxes,f,fullValues,'-',[0.8 0 0],'Full model'); end
            if any(isfinite(m.aperiodicFit)), [aperiodicValues, ~] = app.displayPower(m.aperiodicFit); app.plotSpectrum(app.Controls.FooofAxes,f,aperiodicValues,'--',[0 0.25 0.8],'Aperiodic'); end
            if any(isfinite(m.periodicFit)), [periodicValues, ~] = app.displayPower(m.aperiodicFit+m.periodicFit); app.plotSpectrum(app.Controls.FooofAxes,f,periodicValues,':',[0.1 0.6 0.1],'Periodic-inclusive'); end
            xline(app.Controls.FooofAxes,m.fitRange,':','Color',[.4 .4 .4]);
            if ~isempty(m.peakParams), centers=[m.peakParams.CF]; xline(app.Controls.FooofAxes,centers,'--','Color',[.1 .6 .1]); end
            hold(app.Controls.FooofAxes,'off'); app.applyFrequencyLimits(app.Controls.FooofAxes, f); xlabel(app.Controls.FooofAxes,'Frequency (Hz)'); ylabel(app.Controls.FooofAxes,powerLabel); title(app.Controls.FooofAxes,sprintf('%s | status=%s | offset %.3f | exponent %.3f | R² %.3f | error %.3f',app.displayTitle('FOOOF'),m.fitStatus,m.aperiodicParams.offset,m.aperiodicParams.exponent,m.rSquared,m.fitError),'Interpreter','none'); legend(app.Controls.FooofAxes,'Location','best'); grid(app.Controls.FooofAxes,'on');
            if ~isempty(m.peakParams), rows=cell(numel(m.peakParams),4); for k=1:numel(m.peakParams), rows{k,1}=m.peakParams(k).CF; rows{k,2}=m.peakParams(k).PW; rows{k,3}=m.peakParams(k).BW; rows{k,4}=char(m.peakParams(k).peakBand); end; app.Controls.FooofTable.Data=rows; end
            app.Controls.FooofTable.ColumnName={'CF_Hz','PW_log10','BW_Hz','peakBand'};
        end

        function renderBand(app)
            cla(app.Controls.BandAxes); app.Controls.BandResultTable.Data=cell(0,1); if isempty(fieldnames(app.BandResult)) || ~isfield(app.BandResult,'table'), return; end
            tbl=app.BandResult.table; app.Controls.BandResultTable.Data=table2cell(tbl); app.Controls.BandResultTable.ColumnName=tbl.Properties.VariableNames;
            metric=string(app.Controls.BandMetric.Value); names=unique(tbl.band,'stable'); chans=unique(tbl.channelIndex,'stable'); values=NaN(numel(chans),numel(names));
            for i=1:numel(chans), for j=1:numel(names), row=tbl.channelIndex==chans(i)&tbl.band==names(j); if any(row), values(i,j)=tbl.(metric)(find(row,1)); end, end, end
            imagesc(app.Controls.BandAxes,values); colorbar(app.Controls.BandAxes); set(app.Controls.BandAxes,'XTick',1:numel(names),'XTickLabel',names,'YTick',1:numel(chans),'YTickLabel',chans); xlabel(app.Controls.BandAxes,'Band'); ylabel(app.Controls.BandAxes,'Channel'); title(app.Controls.BandAxes,'频段功率：'+metric); grid(app.Controls.BandAxes,'on');
        end

        function renderSummary(app)
            cla(app.Controls.SummaryPsdAxes); if ~isempty(fieldnames(app.PsdResult)), [summaryPower, summaryLabel] = app.displayPower(app.PsdResult.psd); app.plotSpectrum(app.Controls.SummaryPsdAxes,app.PsdResult.frequencyHz,summaryPower,'-',[0.1 0.25 0.8],'PSD'); xlabel(app.Controls.SummaryPsdAxes,'Hz'); ylabel(app.Controls.SummaryPsdAxes,summaryLabel); title(app.Controls.SummaryPsdAxes,'PSD'); grid(app.Controls.SummaryPsdAxes,'on'); else, title(app.Controls.SummaryPsdAxes,'尚未计算 PSD'); end
            cla(app.Controls.SummaryFitAxes); if ~isempty(app.ModelResult), ex=NaN(1,numel(app.ModelResult)); r2=ex; for k=1:numel(app.ModelResult), ex(k)=app.ModelResult(k).aperiodicParams.exponent; r2(k)=app.ModelResult(k).rSquared; end; yyaxis(app.Controls.SummaryFitAxes,'left'); bar(app.Controls.SummaryFitAxes,ex); ylabel(app.Controls.SummaryFitAxes,'Exponent'); yyaxis(app.Controls.SummaryFitAxes,'right'); plot(app.Controls.SummaryFitAxes,r2,'o-'); ylabel(app.Controls.SummaryFitAxes,'R²'); title(app.Controls.SummaryFitAxes,'拟合质量'); xlabel(app.Controls.SummaryFitAxes,'Channel'); grid(app.Controls.SummaryFitAxes,'on'); else, title(app.Controls.SummaryFitAxes,'尚未拟合'); end
            cla(app.Controls.SummaryBandAxes); if ~isempty(fieldnames(app.BandResult)) && isfield(app.BandResult,'table'), tbl=app.BandResult.table; names=unique(tbl.band,'stable'); chans=unique(tbl.channelIndex,'stable'); values=NaN(numel(chans),numel(names)); for i=1:numel(chans), for j=1:numel(names), row=tbl.channelIndex==chans(i)&tbl.band==names(j); if any(row), values(i,j)=tbl.totalPower(find(row,1)); end, end, end; imagesc(app.Controls.SummaryBandAxes,values); colorbar(app.Controls.SummaryBandAxes); title(app.Controls.SummaryBandAxes,'总频段功率'); else, title(app.Controls.SummaryBandAxes,'尚未计算频段功率'); end
            cla(app.Controls.SummaryArtifactAxes); if ~isempty(fieldnames(app.ArtifactResult)) && isfield(app.ArtifactResult,'summary') && isfield(app.ArtifactResult.summary,'channelArtifactPercentage'), bar(app.Controls.SummaryArtifactAxes,app.ArtifactResult.summary.channelArtifactPercentage); ylabel(app.Controls.SummaryArtifactAxes,'%'); xlabel(app.Controls.SummaryArtifactAxes,'Channel'); title(app.Controls.SummaryArtifactAxes,'各通道伪迹比例'); grid(app.Controls.SummaryArtifactAxes,'on'); else, title(app.Controls.SummaryArtifactAxes,'尚未检测伪迹'); end
        end

        function [values, label] = displayPower(app, power)
            scale = string(app.Controls.PlotPowerScale.Value);
            switch scale
                case "linear"
                    values = power; label = 'Power (units^2/Hz)';
                case "dB"
                    values = 10 * log10(max(power, realmin)); label = 'Power (dB)';
                otherwise
                    values = log10(max(power, realmin)); label = 'log10(power)';
            end
        end

        function plotSpectrum(app, ax, frequency, values, lineStyle, color, displayName)
            if string(app.Controls.PlotFreqScale.Value) == "log"
                semilogx(ax, frequency, values, lineStyle, 'Color', color, 'LineWidth', 1, 'DisplayName', displayName);
            else
                plot(ax, frequency, values, lineStyle, 'Color', color, 'LineWidth', 1, 'DisplayName', displayName);
            end
        end

        function applyFrequencyLimits(app, ax, frequency)
            if isempty(frequency), return; end
            rangeHz = [app.Controls.PlotFreqLow.Value app.Controls.PlotFreqHigh.Value];
            low = max(min(frequency), rangeHz(1)); high = min(max(frequency), rangeHz(2));
            if string(app.Controls.PlotFreqScale.Value) == "log", low = max(low, eps); end
            if isfinite(low) && isfinite(high) && high > low, xlim(ax, [low high]); end
        end

        function defaultText = defaultFsText(~, inspection)
            if isfinite(inspection.estimatedSamplingRateHz), defaultText = sprintf('%.10g',inspection.estimatedSamplingRateHz); elseif inspection.isSceneRay, defaultText='1000'; else, defaultText=''; end
        end

        function values = parseIndexList(~, textValue)
            token=string(textValue); if strlength(strtrim(token))==0, values=[]; return; end
            token=replace(token,'，',','); parts=split(token,','); values=[];
            for k=1:numel(parts)
                part=strtrim(parts(k)); if contains(part,'-'), ends=split(part,'-'); values=[values,str2double(ends(1)):str2double(ends(2))]; else, values(end+1)=str2double(part); end %#ok<AGROW>
            end
            values=unique(values(isfinite(values)&values>=1));
        end

        function finishRun(app)
            app.IsRunning=false; app.setControlsEnabled(true); app.Controls.CancelButton.Enable='off'; app.Controls.ArtifactReconstruct.Enable='off'; app.refreshDependencyStatus();
            if ~isempty(app.LastRunError), app.Controls.ResultStatusLabel.Text='结果状态：失败（上一份结果保留）'; end
        end

        function setControlsEnabled(app, enabled)
            names=fieldnames(app.Controls);
            for k=1:numel(names)
                h=app.Controls.(names{k});
                try
                    if isprop(h,'Enable') && ~ismember(names{k},{'CancelButton'}), h.Enable=ternary_local(enabled,'on','off'); end
                catch
                end
            end
            app.Controls.CancelButton.Enable=ternary_local(~enabled,'on','off');
            app.Controls.RunButton.Enable=ternary_local(enabled,'on','off');
        end

        function setProgress(app, fraction, message)
            fraction=max(0,min(1,fraction)); app.Controls.ProgressLabel.Text=sprintf('进度 %.0f%%：%s',100*fraction,message); app.setStatus(message,'info'); drawnow limitrate;
        end

        function checkCancellation(app)
            drawnow limitrate; if app.CancelRequested, error('LFP:UserCancelled','用户取消了本次运行。'); end
        end

        function setStatus(app, message, level)
            app.Controls.StatusLabel.Text=string(message); if strcmp(level,'error'), app.Controls.StatusLabel.FontColor=[.75 0 0]; elseif strcmp(level,'warning'), app.Controls.StatusLabel.FontColor=[.75 .35 0]; else, app.Controls.StatusLabel.FontColor=[0 .25 .5]; end
        end

        function logMessage(app, message, level)
            if isempty(fieldnames(app.Controls)) || ~isfield(app.Controls,'LogArea') || ~isgraphics(app.Controls.LogArea), return; end
            stamp=datestr(now,'HH:MM:SS'); app.Controls.LogArea.Value=[app.Controls.LogArea.Value; {['[' stamp '][' char(level) '] ' char(string(message))]}];
        end

        function showError(app, titleText, exception)
            app.setStatus(string(exception.message),'error'); app.logMessage(string(exception.message),'error');
            if ~isempty(app.Figure) && isgraphics(app.Figure) && strcmp(app.Figure.Visible, 'on')
                uialert(app.Figure,string(exception.message),titleText,'Icon','error');
            end
        end

        function showWarning(app, titleText, message)
            app.setStatus(message,'warning'); app.logMessage(message,'warning');
            if isgraphics(app.Figure) && strcmp(app.Figure.Visible, 'on'), uialert(app.Figure,message,titleText,'Icon','warning'); end
        end

        function titleText = displayTitle(app, suffix)
            if isempty(fieldnames(app.Data)), titleText=string(suffix); return; end
            titleText=string(app.Data.metadata.displayName)+" | "+string(suffix);
        end

        function limits = finiteLimits(~, values)
            values=values(isfinite(values)); if isempty(values), limits=[NaN NaN]; else limits=[min(values) max(values)]; if limits(1)==limits(2), d=max(abs(limits(1))*0.05,1); limits=limits+[-d d]; end, end
        end

        function number = cellNumber(~, value)
            if isnumeric(value), number=double(value); else, number=str2double(string(value)); end
        end

        function merged = mergeConfig(~, base, override)
            merged=base; if ~isstruct(override), error('LFP:InvalidConfig','配置必须是 struct。'); end
            fields=fieldnames(override); for k=1:numel(fields), name=fields{k}; if isstruct(override.(name)) && isfield(base,name) && isstruct(base.(name)), merged.(name)=mergeConfig_local(base.(name),override.(name)); else, merged.(name)=override.(name); end, end
        end

        function autoSaveResults(app, snapshot)
            folder=string(snapshot.outputFolder); if strlength(strtrim(folder))==0, folder="results"; end
            stamp=string(datestr(now,'yyyymmdd_HHMMSS')); folder=fullfile(folder,"gui_run_"+stamp); files=lfp_export_results(app.AnalysisData,folder,FigureResolution=snapshot.cfg.plot.exportResolution,FigurePosition=snapshot.cfg.plot.figurePosition); app.logMessage("自动保存完成："+files.mat,'info');
        end
    end
end

function value = ternary_local(condition, first, second)
if condition, value=first; else, value=second; end
end

function value = get_field_local(s, name, defaultValue)
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), value=s.(name); else, value=defaultValue; end
end

function merged = mergeConfig_local(base, override)
merged=base; fields=fieldnames(override); for k=1:numel(fields), name=fields{k}; if isstruct(override.(name)) && isfield(base,name) && isstruct(base.(name)), merged.(name)=mergeConfig_local(base.(name),override.(name)); else, merged.(name)=override.(name); end, end
end

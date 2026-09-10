classdef LfpApp < handle
    %LFPAPP Native MATLAB GUI for the SceneRay LFP analysis workflow.
    %   The class owns only GUI state and delegates all calculations to the
    %   public importer, artifact, PSD, parameterization, band-power and
    %   export functions. Raw samples are kept in Data and are never
    %   overwritten by a derived NaN-marked display signal.

    properties
        Figure
        Config
        UiStyle = struct('labelFontSize', 11, 'buttonHeight', 30, ...
            'panelPadding', [8 8 8 8], 'defaultControlWidth', 180)
        Data = struct()
        Datasets = struct('id', {}, 'fileName', {}, 'filePath', {}, ...
            'time', {}, 'signal', {}, 'fs', {}, 'channelLabels', {}, ...
            'units', {}, 'metadata', {}, 'analysisResults', {}, 'status', {})
        CurrentDatasetIndex = 0
        AppState = struct('selectedDatasets', [], 'selectedChannels', [], ...
            'selectedAnalysis', "current", 'currentResults', struct(), ...
            'plotSettings', struct())
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
            [file, folder] = uigetfile({'*.csv', 'CSV 文件 (*.csv)'}, '选择一个或多个 LFP CSV 文件', 'MultiSelect', 'on');
            if isequal(file, 0), return; end
            if iscell(file)
                files = strings(numel(file), 1);
                for k = 1:numel(file), files(k) = string(fullfile(folder, file{k})); end
            else
                files = string(fullfile(folder, file));
            end
            for k = 1:numel(files)
                if ~isfile(files(k)), continue; end
                app.openImportDialog(files(k));
            end
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
                legacyInterpolation = isfield(candidate, 'fooof') && isfield(candidate.fooof, 'interpolateLineNoise');
                app.Config = app.mergeConfig(lfpDefaultConfig(), candidate);
                if legacyInterpolation
                    app.logMessage("旧配置中的拟合前插值选项已忽略；specparam直接使用PSD频率网格。", "warning");
                end
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
            datasetIndices = app.selectedDatasetIndices();
            if isempty(datasetIndices)
                app.showWarning("尚未导入数据", "请先导入并选择至少一个 CSV 文件。");
                return;
            end
            try
                cfg = app.readConfigFromUi();
            catch exception
                app.showError("运行参数有误", exception);
                return;
            end

            app.IsRunning = true;
            app.CancelRequested = false;
            app.setControlsEnabled(false);
            cleanup = onCleanup(@() app.finishRun()); %#ok<NASGU>
            try
                total = numel(datasetIndices);
                for datasetOrder = 1:total
                    app.checkCancellation();
                    app.activateDataset(datasetIndices(datasetOrder), false);
                    snapshot = app.makeRunSnapshot(cfg);
                    app.validateRun(snapshot);
                    app.setProgress((datasetOrder - 1) / total, sprintf('准备数据 %d/%d', datasetOrder, total));
                    app.runCurrentDataset(snapshot, datasetOrder, total);
                    if app.CancelRequested, break; end
                end
                if ~app.CancelRequested
                    app.setProgress(1, sprintf('已完成 %d 个数据集', total));
                    app.logMessage("所选数据集已分别完成分析；未进行跨数据集合并。", "info");
                end
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
                app.AppState.selectedChannels = app.selectedChannels();
                app.renderRaw();
                app.setStatus("已更新通道显示；分析结果仍使用上一次运行快照。", "info");
            catch exception
                app.showError("通道显示失败", exception);
            end
        end

        function onPsdMethodChanged(app, ~, ~)
            if isfield(app.Controls, 'PsdNW')
                isMultitaper = string(app.Controls.PsdMethod.Value) == "multitaper";
                app.Controls.PsdNW.Enable = ternary_local(isMultitaper, 'on', 'off');
                app.Controls.PsdK.Enable = ternary_local(isMultitaper, 'on', 'off');
                app.Controls.PsdTaper.Enable = ternary_local(~isMultitaper, 'on', 'off');
            end
            app.markChanged('psd');
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

        function onDatasetTableEdit(app, ~, ~)
            if app.IsRunning, return; end
            indices = app.selectedDatasetIndices();
            if isempty(indices) && ~isempty(app.Datasets)
                raw = app.Controls.DatasetTable.Data;
                if ~isempty(raw), raw(:,1) = {false}; app.Controls.DatasetTable.Data = raw; end
                app.setStatus('请至少选择一个数据集。', 'warning');
                return;
            end
            app.AppState.selectedDatasets = indices;
            if ~isempty(indices)
                app.activateDataset(indices(1));
                app.setStatus(sprintf('已选择 %d 个数据集；当前显示第一个数据集。', numel(indices)), 'info');
            end
        end

        function onDatasetDropDownChanged(app, source, ~)
            if app.IsRunning, return; end
            index = find(string(source.Items) == string(source.Value), 1);
            if isempty(index) && isnumeric(source.Value), index = round(source.Value); end
            if isempty(index) || index < 1 || index > numel(app.Datasets), return; end
            if isfield(app.Controls, 'DatasetTable') && index >= 1 && index <= numel(app.Datasets)
                raw = app.Controls.DatasetTable.Data;
                raw(:,1) = {false}; raw{index,1} = true;
                app.Controls.DatasetTable.Data = raw;
            end
            app.activateDataset(index);
            app.renderAll();
        end

        function onResultChannelChanged(app, source, ~)
            if app.IsRunning, return; end
            label = string(source.Value);
            labels = string(app.Data.channelLabels(:));
            if any(labels == label)
                app.Controls.ChannelList.Value = cellstr(label);
                app.AppState.selectedChannels = find(labels == label, 1);
            end
            app.renderAll();
        end

        function selectAllDatasets(app, ~, ~)
            if app.IsRunning || isempty(app.Datasets), return; end
            raw = app.Controls.DatasetTable.Data; raw(:,1) = {true}; app.Controls.DatasetTable.Data = raw;
            app.AppState.selectedDatasets = 1:numel(app.Datasets);
            app.setStatus('已全选数据集。', 'info');
        end

        function clearDatasetSelection(app, ~, ~)
            if app.IsRunning, return; end
            raw = app.Controls.DatasetTable.Data;
            if ~isempty(raw), raw(:,1) = {false}; app.Controls.DatasetTable.Data = raw; end
            app.AppState.selectedDatasets = [];
            app.setStatus('已清除数据集选择。', 'warning');
        end

        function deleteSelectedDatasets(app, ~, ~)
            if app.IsRunning, return; end
            indices = app.selectedDatasetIndices();
            if isempty(indices), app.showWarning('没有选择', '请先勾选需要删除的数据集。'); return; end
            if isgraphics(app.Figure) && strcmp(app.Figure.Visible, 'on')
                choice = uiconfirm(app.Figure, sprintf('确认从当前会话删除 %d 个数据集？原始 CSV 文件不会被删除。', numel(indices)), ...
                    '删除数据集', 'Options', {'删除', '取消'}, 'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, '删除'), return; end
            end
            app.Datasets(indices) = [];
            if isempty(app.Datasets)
                app.CurrentDatasetIndex = 0; app.Data = struct(); app.resetCurrentResults();
            else
                app.CurrentDatasetIndex = min(max(1, app.CurrentDatasetIndex), numel(app.Datasets));
                app.activateDataset(app.CurrentDatasetIndex);
            end
            app.refreshDatasetTable(); app.setStatus('已删除选中的会话数据集；CSV 文件未被删除。', 'info');
        end

        function showSelectedDatasetInfo(app, ~, ~)
            indices = app.selectedDatasetIndices();
            if isempty(indices), app.showWarning('没有选择', '请先选择数据集。'); return; end
            lines = strings(numel(indices), 1);
            for k = 1:numel(indices)
                d = app.Datasets(indices(k));
                lines(k) = sprintf('%s | %d 通道 | %.6g Hz | %s', char(d.fileName), size(d.signal,2), d.fs, char(d.status));
            end
            if isgraphics(app.Figure) && strcmp(app.Figure.Visible, 'on')
                uialert(app.Figure, strjoin(lines, newline), '数据集信息', 'Icon', 'info');
            else
                app.logMessage(strjoin(lines, ' ; '), 'info');
            end
        end

        function onSaveView(app, kind, ~)
            if app.IsRunning, return; end
            kind = string(kind);
            [file, folder, filterIndex] = uiputfile({'*.png','PNG 图片'; '*.svg','SVG 矢量图'; '*.fig','MATLAB FIG 文件'}, ...
                '保存当前图形', char(kind + ".png"));
            if isequal(file,0), return; end
            switch kind
                case "raw", ax = app.Controls.RawAxes;
                case "psd", ax = app.Controls.PsdAxes;
                case "timeFrequency", ax = app.Controls.PsdTimeFrequencyAxes;
                case "specparam", ax = app.Controls.FooofAxes;
                case "band", ax = app.Controls.BandAxes;
                otherwise, error('LFP:UnknownPlot', '未知绘图视图：%s', kind);
            end
            target = fullfile(folder, file); fig = ancestor(ax, 'figure');
            try
                if filterIndex == 3 || endsWith(lower(string(file)), '.fig')
                    savefig(fig, target);
                else
                    exportgraphics(ax, target, 'Resolution', app.Config.plot.exportResolution, 'ContentType', ternary_local(filterIndex == 2, 'vector', 'image'));
                end
                app.logMessage("图形已保存：" + string(target), "info");
            catch exception
                app.showError("图形保存失败", exception);
            end
        end

        function onSaveViewData(app, kind, ~)
            if app.IsRunning, return; end
            [file, folder] = uiputfile('*.mat', '保存当前视图数据', char(string(kind) + "_view.mat"));
            if isequal(file,0), return; end
            payload = struct('dataset', app.currentDatasetName(), 'channel', string(app.Data.channelLabels(:)), ...
                'analysisParameters', get_field_local(app.LastRunSnapshot, 'cfg', app.Config), ...
                'savedAt', string(datestr(now, 31)), 'kind', string(kind));
            switch string(kind)
                case "raw", payload.time = app.Data.time; payload.signal = app.Data.signal;
                case "psd", payload.beforePsd = app.BeforePsd; payload.psd = app.PsdResult;
                case "timeFrequency", payload.timeFrequency = get_field_local(app.PsdResult, 'timeFrequency', struct());
                case "specparam", payload.modelResult = app.ModelResult;
                case "band", payload.bandResult = app.BandResult;
            end
            target = fullfile(folder, file); save(target, 'payload', '-v7'); app.logMessage("视图数据已保存：" + string(target), "info");
        end
    end

    methods (Access=public)
        function setData(app, data)
            %SETDATA Public programmatic import hook for tests and scripts.
            % GUI file selection still routes through the configured importer.
            if ~isfield(data.metadata, 'sourceFilePath'), data.metadata.sourceFilePath = ""; end
            if ~isfield(data.metadata, 'displayName')
                data.metadata.displayName = string(get_field_local(data.metadata, 'sourceFileName', "dataset"));
            end
            app.addDataset(data);
        end
    end

    methods (Access=private)
        function addDataset(app, data)
            if ~isfield(data, 'signal') || ~isnumeric(data.signal) || isempty(data.signal)
                error('LFP:InvalidData', '数据集必须包含非空 numeric signal。');
            end
            if ~isfield(data, 'time') || numel(data.time) ~= size(data.signal, 1)
                data.time = (0:size(data.signal,1)-1)' / double(data.fs);
            end
            if ~isfield(data, 'channelLabels') || numel(data.channelLabels) ~= size(data.signal,2)
                data.channelLabels = "channel_" + string((1:size(data.signal,2))');
            end
            if ~isfield(data, 'metadata') || ~isstruct(data.metadata), data.metadata = struct(); end
            if ~isfield(data.metadata, 'sourceFileName'), data.metadata.sourceFileName = "dataset_" + string(numel(app.Datasets)+1); end
            if ~isfield(data.metadata, 'sourceFilePath'), data.metadata.sourceFilePath = ""; end
            if ~isfield(data.metadata, 'displayName'), data.metadata.displayName = string(data.metadata.sourceFileName); end
            if ~isfield(data, 'units'), data.units = "unknown"; end
            datasetId = "dataset_" + string(numel(app.Datasets) + 1);
            entry = struct('id', datasetId, 'fileName', string(data.metadata.sourceFileName), ...
                'filePath', string(data.metadata.sourceFilePath), 'time', double(data.time(:)), ...
                'signal', double(data.signal), 'fs', double(data.fs), ...
                'channelLabels', string(data.channelLabels(:)), 'units', string(data.units), ...
                'metadata', data.metadata, 'analysisResults', struct(), 'status', "已导入");
            app.Datasets(end + 1) = entry;
            newIndex = numel(app.Datasets);
            app.CurrentDatasetIndex = 0;
            app.activateDataset(newIndex, false);
            app.AppState.selectedDatasets = newIndex;
            app.refreshDatasetTable();
            app.invalidateAll("已导入数据集，请运行所选分析。");
            app.logMessage("已加入数据集 " + entry.fileName + "（" + string(size(entry.signal,2)) + " 通道）", "info");
        end

        function resetCurrentResults(app)
            app.CleanData = struct(); app.AnalysisData = struct(); app.ArtifactResult = struct();
            app.BeforePsd = struct(); app.PsdResult = struct(); app.ModelResult = struct([]); app.BandResult = struct();
            app.LastRunSnapshot = struct(); app.LastRunError = "";
            app.Cache = struct('artifactValid', false, 'psdValid', false, 'modelValid', false, 'bandValid', false, 'plotValid', false);
            app.AppState.currentResults = struct();
        end

        function saveCurrentDataset(app)
            index = app.CurrentDatasetIndex;
            if index < 1 || index > numel(app.Datasets), return; end
            if isempty(fieldnames(app.Data)), return; end
            app.Datasets(index).time = double(app.Data.time(:));
            app.Datasets(index).signal = double(app.Data.signal);
            app.Datasets(index).fs = double(app.Data.fs);
            app.Datasets(index).channelLabels = string(app.Data.channelLabels(:));
            app.Datasets(index).units = string(app.Data.units);
            app.Datasets(index).metadata = app.Data.metadata;
            app.Datasets(index).analysisResults = struct('cleanData', app.CleanData, ...
                'artifactResult', app.ArtifactResult, 'beforePsd', app.BeforePsd, ...
                'psdResult', app.PsdResult, 'modelResult', app.ModelResult, ...
                'bandResult', app.BandResult, 'analysisData', app.AnalysisData, ...
                'snapshot', app.LastRunSnapshot, 'cache', app.Cache);
            if ~isempty(fieldnames(app.AnalysisData)), app.Datasets(index).status = "已完成"; else, app.Datasets(index).status = "已导入"; end
        end

        function activateDataset(app, index, redraw)
            if nargin < 3, redraw = true; end
            if isempty(app.Datasets)
                app.AppState.selectedDatasets = [];
                return;
            end
            app.saveCurrentDataset();
            index = max(1, min(numel(app.Datasets), round(index)));
            app.CurrentDatasetIndex = index;
            entry = app.Datasets(index);
            app.Data = struct('signal', entry.signal, 'fs', entry.fs, 'time', entry.time, ...
                'channelLabels', entry.channelLabels, 'channelNames', entry.channelLabels, ...
                'channelCount', size(entry.signal,2), 'units', entry.units, 'metadata', entry.metadata, ...
                'processingHistory', get_field_local(entry.metadata, 'processingHistory', struct()));
            if isempty(fieldnames(app.Data.processingHistory))
                app.Data.processingHistory = struct('operation', "import", 'parameters', get_field_local(entry.metadata, 'importSettings', struct()), 'notes', "Dataset activated in GUI.");
            end
            results = entry.analysisResults;
            if isfield(results, 'analysisData') && ~isempty(fieldnames(results.analysisData))
                app.CleanData = results.cleanData; app.ArtifactResult = results.artifactResult;
                app.BeforePsd = results.beforePsd; app.PsdResult = results.psdResult;
                app.ModelResult = results.modelResult; app.BandResult = results.bandResult;
                app.AnalysisData = results.analysisData; app.LastRunSnapshot = results.snapshot;
                if isfield(results, 'cache'), app.Cache = results.cache; end
            else
                app.resetCurrentResults();
            end
            labels = string(entry.channelLabels(:));
            if isfield(app.Controls, 'ChannelList') && isgraphics(app.Controls.ChannelList)
                app.Controls.ChannelList.Items = cellstr(labels);
                app.Controls.ChannelList.Value = cellstr(labels);
            end
            [timeStart, timeEnd] = app.timeBounds(app.Data);
            if isfield(app.Controls, 'AnalysisStart')
                app.Controls.AnalysisStart.Value = timeStart; app.Controls.AnalysisEnd.Value = timeEnd;
                app.Controls.DisplayStart.Value = timeStart; app.Controls.DisplayEnd.Value = timeEnd;
            end
            app.AppState.selectedDatasets = app.selectedDatasetIndices();
            app.AppState.selectedChannels = 1:size(entry.signal,2);
            app.updateDataInfo(); app.updateDatasetSelectors();
            if redraw && isgraphics(app.Figure), app.renderAll(); end
        end

        function indices = selectedDatasetIndices(app)
            if isempty(app.Datasets)
                if isempty(fieldnames(app.Data)), indices = []; else, indices = 1; end
                return;
            end
            raw = app.Controls.DatasetTable.Data;
            if isempty(raw), indices = app.CurrentDatasetIndex; return; end
            flags = false(size(raw,1),1);
            for k = 1:size(raw,1), flags(k) = islogical(raw{k,1}) && raw{k,1}; end
            indices = find(flags)';
            if isempty(indices) && app.CurrentDatasetIndex >= 1, indices = app.CurrentDatasetIndex; end
        end

        function refreshDatasetTable(app)
            if ~isfield(app.Controls, 'DatasetTable') || ~isgraphics(app.Controls.DatasetTable), return; end
            n = numel(app.Datasets); rows = cell(n, 5); selected = app.AppState.selectedDatasets;
            if isempty(selected) && app.CurrentDatasetIndex > 0, selected = app.CurrentDatasetIndex; end
            for k = 1:n
                rows{k,1} = any(selected == k); rows{k,2} = char(app.Datasets(k).fileName);
                rows{k,3} = size(app.Datasets(k).signal, 2); rows{k,4} = app.Datasets(k).fs;
                rows{k,5} = char(app.Datasets(k).status);
            end
            app.Controls.DatasetTable.Data = rows;
            app.AppState.selectedDatasets = find(cell2mat(rows(:,1)))';
        end

        function updateDatasetSelectors(app)
            if isempty(app.Datasets), return; end
            names = strings(numel(app.Datasets),1);
            for k=1:numel(app.Datasets), names(k) = app.Datasets(k).fileName; end
            names = string(matlab.lang.makeUniqueStrings(cellstr(names)));
            controls = {'RawDatasetDropDown','PsdDatasetDropDown','TfDatasetDropDown','FooofDatasetDropDown'};
            for k=1:numel(controls)
                name = controls{k};
                if isfield(app.Controls, name) && isgraphics(app.Controls.(name))
                    app.Controls.(name).Items = cellstr(names);
                    app.Controls.(name).Value = char(names(app.CurrentDatasetIndex));
                end
            end
            labels = string(app.Data.channelLabels(:));
            channelControls = {'RawChannelDropDown','PsdChannelDropDown','TfChannelDropDown','FooofChannelDropDown'};
            for k=1:numel(channelControls)
                name=channelControls{k};
                if isfield(app.Controls,name) && isgraphics(app.Controls.(name))
                    app.Controls.(name).Items=cellstr(labels); app.Controls.(name).Value=char(labels(1));
                end
            end
        end

        function index = channelIndexFromControl(~, control, labels)
            index = find(labels == string(control.Value), 1);
            if isempty(index), index = 1; end
        end

        function name = currentDatasetName(app)
            if app.CurrentDatasetIndex >= 1 && app.CurrentDatasetIndex <= numel(app.Datasets)
                name = string(app.Datasets(app.CurrentDatasetIndex).fileName);
            elseif ~isempty(fieldnames(app.Data)) && isfield(app.Data, 'metadata')
                name = string(get_field_local(app.Data.metadata, 'displayName', 'current dataset'));
            else
                name = "current dataset";
            end
        end

        function runCurrentDataset(app, snapshot, datasetOrder, totalDatasets)
            selectedData = app.selectChannels(app.Data, snapshot.channels);
            fullArtifact = app.emptyArtifact(selectedData); fullClean = selectedData; fullClean.cleanedSignal = selectedData.signal;
            needPsd = snapshot.modules.psd || snapshot.modules.fooof || snapshot.modules.band;
            needModel = snapshot.modules.fooof || snapshot.modules.band;
            needArtifact = snapshot.modules.artifact || (needPsd && snapshot.cfg.psd.excludeArtifacts && ~app.Cache.artifactValid);
            if needArtifact
                app.setProgress((datasetOrder - 0.85) / totalDatasets, sprintf('检测伪迹 %d/%d', datasetOrder, totalDatasets));
                [fullClean, fullArtifact] = detectAndHandleArtifacts(selectedData, snapshot.cfg.artifact);
                fullArtifact.channelIndices = snapshot.channels; app.checkCancellation();
            elseif app.Cache.artifactValid && app.compatibleArtifact(app.ArtifactResult, selectedData)
                fullArtifact = app.ArtifactResult; fullArtifact.channelIndices = snapshot.channels;
                fullClean.artifacts = fullArtifact; fullClean.cleanedSignal = selectedData.signal; fullClean.cleanedSignal(fullArtifact.channelMask) = NaN;
            end
            if ~isfield(fullArtifact, 'channelIndices'), fullArtifact.channelIndices = snapshot.channels; end
            analysisIndex = app.timeIndexForRange(selectedData, snapshot.analysisRange);
            analysisData = app.sliceData(selectedData, analysisIndex);
            analysisArtifact = app.sliceArtifact(fullArtifact, analysisIndex, selectedData.fs);
            analysisClean = app.sliceData(fullClean, analysisIndex); analysisClean.artifacts = analysisArtifact;
            analysisClean.cleanedSignal = analysisData.signal; analysisClean.cleanedSignal(analysisArtifact.channelMask) = NaN;
            beforePsd = struct(); psd = struct(); model = struct([]); band = struct();
            if needPsd
                app.setProgress((datasetOrder - 0.70) / totalDatasets, sprintf('计算 PSD %d/%d', datasetOrder, totalDatasets));
                psdCfgBefore = snapshot.cfg.psd; if isfield(psdCfgBefore, 'timeFrequency'), psdCfgBefore.timeFrequency.enabled = false; end
                beforePsd = computeLfpPsd(analysisData, app.emptyArtifact(analysisData), psdCfgBefore); app.checkCancellation();
                psd = computeLfpPsd(analysisClean, analysisArtifact, snapshot.cfg.psd);
            end
            if needModel
                app.setProgress((datasetOrder - 0.45) / totalDatasets, sprintf('拟合 specparam %d/%d', datasetOrder, totalDatasets));
                model = parameterizePowerSpectrum(psd.frequencyHz, psd.psd, snapshot.cfg.fooof); model = app.addModelContext(model, analysisData); app.checkCancellation();
            end
            if snapshot.modules.band
                app.setProgress((datasetOrder - 0.20) / totalDatasets, sprintf('计算频段功率 %d/%d', datasetOrder, totalDatasets));
                band = computeBandPower(psd, model, snapshot.cfg.bands); app.checkCancellation();
            end
            analysisData.artifacts = analysisArtifact; analysisData.cleanedSignal = analysisClean.cleanedSignal;
            if needPsd, analysisData.spectrum = psd; end
            if needModel, analysisData.spectralParameters = struct('aperiodicPsd', app.collectModelField(model, 'aperiodicFit'), 'periodicPowerAboveAperiodic', app.collectModelField(model, 'periodicFit')); end
            if snapshot.modules.band, analysisData.bandPower = band; end
            analysisData.metadata.analysisRangeSeconds = snapshot.analysisRange; analysisData.metadata.selectedChannels = snapshot.channels; analysisData.metadata.runSnapshot = snapshot;
            if ~needPsd, analysisData.processingHistory = analysisClean.processingHistory; elseif isfield(psd, 'processingHistory'), analysisData.processingHistory = psd.processingHistory; end
            if needModel, analysisData.processingHistory(end+1) = struct('operation', "spectral_parameterization", 'parameters', snapshot.cfg.fooof, 'notes', "Native specparam periodic and aperiodic model fitted in GUI run."); end
            if snapshot.modules.band, analysisData.processingHistory(end+1) = struct('operation', "band_power", 'parameters', snapshot.cfg.bands, 'notes', "Band powers computed from the GUI run PSD/model snapshot."); end
            if app.CancelRequested, return; end
            app.Config = snapshot.cfg; app.CleanData = fullClean; app.ArtifactResult = fullArtifact; app.AnalysisData = analysisData;
            app.BeforePsd = beforePsd; app.PsdResult = psd; app.ModelResult = model; app.BandResult = band; app.LastRunSnapshot = snapshot; app.LastRunError = "";
            app.Cache = struct('artifactValid', ~isempty(fieldnames(fullArtifact)), 'psdValid', ~isempty(fieldnames(psd)), 'modelValid', ~isempty(model), 'bandValid', ~isempty(fieldnames(band)), 'plotValid', true);
            app.AppState.currentResults = struct('artifact', app.ArtifactResult, 'psd', app.PsdResult, 'model', {app.ModelResult}, 'band', app.BandResult);
            app.saveCurrentDataset(); app.refreshDatasetTable(); app.renderAll();
            if snapshot.autoSave, app.autoSaveResults(snapshot); end
        end

        function buildUi(app, visible)
            app.Figure = uifigure('Name', 'SceneRay LFP 分析工具', 'NumberTitle', 'off', ...
                'Color', [0.96 0.96 0.96], 'Position', [60 40 1760 1000], ...
                'Visible', char(visible), 'CloseRequestFcn', @(src,event)app.closeApp(src,event));
            outer = uigridlayout(app.Figure, [3 3]);
            outer.RowHeight = {44, '1x', 38};
            outer.ColumnWidth = {360, 410, '1x'};
            outer.Padding = app.UiStyle.panelPadding;

            toolbar = uipanel(outer, 'BorderType', 'none'); toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
            tg = uigridlayout(toolbar, [1 7]); tg.ColumnWidth = {120, 120, 120, 120, 180, '1x', 190}; tg.Padding = [0 0 0 0];
            app.Controls.ImportButton = uibutton(tg, 'Text', '导入 CSV（可多选）', 'ButtonPushedFcn', @(s,e)app.onImport(s,e));
            app.Controls.LoadConfigButton = uibutton(tg, 'Text', '加载配置', 'ButtonPushedFcn', @(s,e)app.onLoadConfig(s,e));
            app.Controls.SaveConfigButton = uibutton(tg, 'Text', '保存配置', 'ButtonPushedFcn', @(s,e)app.onSaveConfig(s,e));
            app.Controls.SaveResultsButton = uibutton(tg, 'Text', '保存当前结果', 'ButtonPushedFcn', @(s,e)app.onSaveResults(s,e));
            app.Controls.StatusLabel = uilabel(tg, 'Text', '未加载数据', 'HorizontalAlignment', 'center');
            app.Controls.FileLabel = uilabel(tg, 'Text', '', 'HorizontalAlignment', 'left', 'WordWrap', 'on');
            app.Controls.DependencyLabel = uilabel(tg, 'Text', '', 'HorizontalAlignment', 'right');

            left = uipanel(outer, 'Title', '数据与运行'); left.Layout.Row = 2; left.Layout.Column = 1;
            lg = uigridlayout(left, [11 1]); lg.RowHeight = {150, 34, 92, 110, 50, 50, 120, 30, 30, 30, '1x'}; lg.Padding = app.UiStyle.panelPadding;
            app.Controls.DatasetTable = uitable(lg, 'Data', cell(0,5), 'ColumnName', {'选择','文件名','通道数','采样率 (Hz)','状态'}, ...
                'ColumnEditable', [true false false false false], 'ColumnFormat', {'logical','char','numeric','numeric','char'}, ...
                'CellEditCallback', @(s,e)app.onDatasetTableEdit(s,e)); app.Controls.DatasetTable.Layout.Row = 1;
            datasetButtons = uigridlayout(lg, [1 4]); datasetButtons.ColumnWidth = {'1x','1x','1x','1x'}; datasetButtons.Layout.Row = 2;
            app.Controls.DatasetSelectAllButton = uibutton(datasetButtons, 'Text', '全选', 'ButtonPushedFcn', @(s,e)app.selectAllDatasets(s,e));
            app.Controls.DatasetClearButton = uibutton(datasetButtons, 'Text', '清除选择', 'ButtonPushedFcn', @(s,e)app.clearDatasetSelection(s,e));
            app.Controls.DatasetDeleteButton = uibutton(datasetButtons, 'Text', '删除', 'ButtonPushedFcn', @(s,e)app.deleteSelectedDatasets(s,e));
            app.Controls.DatasetInfoButton = uibutton(datasetButtons, 'Text', '查看信息', 'ButtonPushedFcn', @(s,e)app.showSelectedDatasetInfo(s,e));
            app.Controls.InfoArea = uitextarea(lg, 'Editable', 'off', 'Value', {'未加载数据'}, 'WordWrap', 'on'); app.Controls.InfoArea.Layout.Row = 3;
            app.Controls.ChannelList = uilistbox(lg, 'Multiselect', 'on', 'Items', {'(未加载)'}, 'Value', {'(未加载)'}, ...
                'ValueChangedFcn', @(s,e)app.onChannelChanged(s,e)); app.Controls.ChannelList.Layout.Row = 4;
            app.Controls.AnalysisRangePanel = uipanel(lg, 'Title', '分析时间范围 (s)'); app.Controls.AnalysisRangePanel.Layout.Row = 5;
            ar = uigridlayout(app.Controls.AnalysisRangePanel, [1 4]); ar.ColumnWidth = {42, '1x', 42, '1x'};
            uilabel(ar, 'Text', '起始'); app.Controls.AnalysisStart = uieditfield(ar, 'numeric', 'Value', 0, 'ValueChangedFcn', @(s,e)app.markChanged('data'));
            uilabel(ar, 'Text', '结束'); app.Controls.AnalysisEnd = uieditfield(ar, 'numeric', 'Value', 0, 'ValueChangedFcn', @(s,e)app.markChanged('data'));
            app.Controls.DisplayRangePanel = uipanel(lg, 'Title', '波形显示范围 (s)'); app.Controls.DisplayRangePanel.Layout.Row = 6;
            dr = uigridlayout(app.Controls.DisplayRangePanel, [1 4]); dr.ColumnWidth = {42, '1x', 42, '1x'};
            uilabel(dr, 'Text', '起始'); app.Controls.DisplayStart = uieditfield(dr, 'numeric', 'Value', 0, 'ValueChangedFcn', @(s,e)app.markChanged('plot'));
            uilabel(dr, 'Text', '结束'); app.Controls.DisplayEnd = uieditfield(dr, 'numeric', 'Value', 0, 'ValueChangedFcn', @(s,e)app.markChanged('plot'));
            modulePanel = uipanel(lg, 'Title', '分析模块'); modulePanel.Layout.Row = 7; mg = uigridlayout(modulePanel, [4 1]); mg.RowHeight = {28,28,40,28};
            app.Controls.ArtifactCheck = uicheckbox(mg, 'Text', '伪迹检测/标记', 'Value', true, 'ValueChangedFcn', @(s,e)app.markChanged('artifact'));
            app.Controls.PsdCheck = uicheckbox(mg, 'Text', 'PSD', 'Value', true, 'ValueChangedFcn', @(s,e)app.markChanged('psd'));
            app.Controls.FooofCheck = uicheckbox(mg, 'Text', 'specparam 周期/非周期拟合', 'Value', true, 'ValueChangedFcn', @(s,e)app.markChanged('model'));
            app.Controls.BandCheck = uicheckbox(mg, 'Text', '频段功率', 'Value', true, 'ValueChangedFcn', @(s,e)app.markChanged('band'));
            autoPanel = uipanel(lg, 'BorderType', 'none'); autoPanel.Layout.Row = 8; ag = uigridlayout(autoPanel, [1 1]);
            app.Controls.AutoSaveCheck = uicheckbox(ag, 'Text', '成功后自动保存结果', 'Value', false);
            outputPanel = uipanel(lg, 'BorderType', 'none'); outputPanel.Layout.Row = 9; og = uigridlayout(outputPanel, [1 2]); og.ColumnWidth = {'1x', 70};
            app.Controls.OutputFolder = uieditfield(og, 'text', 'Value', 'results');
            app.Controls.BrowseOutputButton = uibutton(og, 'Text', '浏览', 'ButtonPushedFcn', @(s,e)app.onBrowseOutput(s,e));
            app.Controls.LogArea = uitextarea(lg, 'Editable', 'off', 'Value', {'日志：'}, 'WordWrap', 'on'); app.Controls.LogArea.Layout.Row = [10 11];

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
            app.onPsdMethodChanged([], []);
        end

        function buildParameterTabs(app, parent)
            tabs = uitabgroup(parent); app.Tabs.Parameter = tabs;
            artifactTab = uitab(tabs, 'Title', '伪迹');
            g = uigridlayout(artifactTab, [12 2]); g.ColumnWidth = {190, '1x'}; g.RowHeight = repmat({32}, 1, 12);
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

            psdTab = uitab(tabs, 'Title', 'PSD + 时频');
            g = uigridlayout(psdTab, [23 2]); g.ColumnWidth = {200, '1x'}; g.RowHeight = repmat({32}, 1, 23);
            app.Controls.PsdMethod = app.addDropDown(g, 1, 'PSD 方法', {'welch', 'multitaper'}, char(app.Config.psd.method), 'psd');
            app.Controls.PsdMethod.ValueChangedFcn = @(s,e)app.onPsdMethodChanged(s,e);
            app.Controls.PsdWindow = app.addNumeric(g, 2, '窗长 T (s)', app.Config.psd.windowLengthSec, 'psd');
            app.Controls.PsdOverlap = app.addNumeric(g, 3, '重叠比例', app.Config.psd.overlapFraction, 'psd');
            app.Controls.PsdNfft = app.addNumeric(g, 4, 'NFFT（0=自动）', app.Config.psd.nfft, 'psd');
            app.Controls.PsdFreqLow = app.addNumeric(g, 5, 'PSD 下限 (Hz)', app.Config.psd.frequencyRange(1), 'psd');
            app.Controls.PsdFreqHigh = app.addNumeric(g, 6, 'PSD 上限 (Hz)', app.Config.psd.frequencyRange(2), 'psd');
            app.Controls.PsdMaxArtifact = app.addNumeric(g, 7, '允许伪迹比例', app.Config.psd.maxArtifactFraction, 'psd');
            app.Controls.PsdExclude = app.addCheck(g, 8, '排除含伪迹窗口', app.Config.psd.excludeArtifacts, 'psd');
            app.Controls.PsdAggregation = app.addDropDown(g, 9, '窗口聚合', {'mean', 'median'}, char(app.Config.psd.aggregationMethod), 'psd');
            app.Controls.PsdNW = app.addNumeric(g, 10, 'Multitaper NW', app.Config.psd.multitaper.timeBandwidthProduct, 'psd');
            app.Controls.PsdK = app.addNumeric(g, 11, 'DPSS taper K', app.Config.psd.multitaper.taperCount, 'psd');
            app.Controls.PsdTaper = app.addDropDown(g, 12, 'Welch 窗函数', {'hann'}, char(app.Config.psd.taper), 'psd');
            label = uilabel(g, 'Text', 'W=NW/T；总平滑带宽≈2W；默认 K=floor(2NW)-1'); label.Layout.Row = 13; label.Layout.Column = [1 3];
            label = uilabel(g, 'Text', 'PSD 为线性功率；显示时可转 dB'); label.Layout.Row = 14; label.Layout.Column = [1 3];
            tf = get_field_local(app.Config.psd, 'timeFrequency', struct());
            tfRange = get_field_local(tf, 'frequencyRange', [1 40]);
            app.Controls.TfEnable = app.addCheck(g, 15, '启用时频图', get_field_local(tf, 'enabled', true), 'psd');
            app.Controls.TfReuse = app.addCheck(g, 16, '时频复用 PSD 参数', get_field_local(tf, 'reusePsdParameters', true), 'psd');
            app.Controls.TfWindow = app.addNumeric(g, 17, '时频窗长 (s)', get_field_local(tf, 'windowLengthSec', 1), 'psd');
            app.Controls.TfStep = app.addNumeric(g, 18, '时频步长 (s)', get_field_local(tf, 'stepSeconds', .25), 'psd');
            app.Controls.TfFreqLow = app.addNumeric(g, 19, '时频下限 (Hz)', tfRange(1), 'psd');
            app.Controls.TfFreqHigh = app.addNumeric(g, 20, '时频上限 (Hz)', tfRange(2), 'psd');
            label = uilabel(g, 'Text', '步长为主要输入；重叠比例由窗长与步长派生'); label.Layout.Row = 21; label.Layout.Column = [1 3];
            app.Controls.TfPowerScale = app.addDropDown(g, 22, '时频功率', {'linear', 'log10', 'dB'}, char(get_field_local(tf, 'powerScale', "log10")), 'plot');
            app.Controls.PsdInfo = uilabel(g, 'Text', ''); app.Controls.PsdInfo.Layout.Row = 23; app.Controls.PsdInfo.Layout.Column = [1 3];

            fooofTab = uitab(tabs, 'Title', 'specparam（原FOOOF）');
            g = uigridlayout(fooofTab, [10 2]); g.ColumnWidth = {190, '1x'}; g.RowHeight = repmat({32}, 1, 10);
            app.Controls.FooofFreqLow = app.addNumeric(g, 1, '拟合下限 (Hz)', app.Config.fooof.frequencyRange(1), 'model');
            app.Controls.FooofFreqHigh = app.addNumeric(g, 2, '拟合上限 (Hz)', app.Config.fooof.frequencyRange(2), 'model');
            app.Controls.FooofWidthLow = app.addNumeric(g, 3, '峰宽下限 (Hz)', app.Config.fooof.peakWidthLimits(1), 'model');
            app.Controls.FooofWidthHigh = app.addNumeric(g, 4, '峰宽上限 (Hz)', app.Config.fooof.peakWidthLimits(2), 'model');
            app.Controls.FooofMaxPeaks = app.addNumeric(g, 5, '最大峰数', app.Config.fooof.maxNumberPeaks, 'model');
            app.Controls.FooofMinHeight = app.addNumeric(g, 6, '最小峰高 (log10)', app.Config.fooof.minPeakHeight, 'model');
            app.Controls.FooofThreshold = app.addNumeric(g, 7, '峰检测阈值 (z)', app.Config.fooof.peakThreshold, 'model');
            app.Controls.FooofMode = app.addDropDown(g, 8, '非周期模型', {'fixed', 'knee'}, char(app.Config.fooof.aperiodicMode), 'model');
            label = uilabel(g, 'Text', 'fixed: offset/exponent；knee: 额外估计 knee（非 Hz 拐点）'); label.Layout.Row = 9; label.Layout.Column = [1 3];
            app.Controls.FooofInfo = uilabel(g, 'Text', ''); app.Controls.FooofInfo.Layout.Row = 10; app.Controls.FooofInfo.Layout.Column = [1 3];

            bandTab = uitab(tabs, 'Title', '频段');
            bg = uigridlayout(bandTab, [4 3]); bg.RowHeight = {'1x', 32, 28, 28}; bg.ColumnWidth = {'1x', 120, 120};
            app.Controls.BandTable = uitable(bg, 'ColumnName', {'名称', '下限 (Hz)', '上限 (Hz)'}, ...
                'ColumnEditable', [true true true], 'CellEditCallback', @(s,e)app.onBandCellEdit(s,e));
            app.Controls.BandTable.Layout.Row = 1; app.Controls.BandTable.Layout.Column = [1 3];
            bands = app.Config.bands; names = fieldnames(bands); bandData = cell(numel(names), 3);
            for k = 1:numel(names), bandData{k,1} = names{k}; bandData{k,2} = bands.(names{k})(1); bandData{k,3} = bands.(names{k})(2); end
            app.Controls.BandTable.Data = bandData;
            app.Controls.BandMetric = uidropdown(bg, 'Items', {'totalPower', 'relativePower', 'logTotalPower', 'aperiodicPower', 'periodicPower'}, ...
                'Value', 'totalPower', 'ValueChangedFcn', @(s,e)app.markChanged('plot')); app.Controls.BandMetric.Layout.Row = 2; app.Controls.BandMetric.Layout.Column = 1;
            app.Controls.BandFacet = uidropdown(bg, 'Items', {'按频段分面', '按通道分面'}, ...
                'Value', '按频段分面', 'ValueChangedFcn', @(s,e)app.markChanged('plot')); app.Controls.BandFacet.Layout.Row = 2; app.Controls.BandFacet.Layout.Column = 2;
            app.Controls.BandAddButton = uibutton(bg, 'Text', '添加', 'ButtonPushedFcn', @(s,e)app.addBand(s,e)); app.Controls.BandAddButton.Layout.Row = 2; app.Controls.BandAddButton.Layout.Column = 2;
            app.Controls.BandRemoveButton = uibutton(bg, 'Text', '删除', 'ButtonPushedFcn', @(s,e)app.removeBand(s,e)); app.Controls.BandRemoveButton.Layout.Row = 2; app.Controls.BandRemoveButton.Layout.Column = 3;
            app.Controls.BandDefaultsButton = uibutton(bg, 'Text', '恢复默认', 'ButtonPushedFcn', @(s,e)app.restoreDefaultBands(s,e)); app.Controls.BandDefaultsButton.Layout.Row = 3; app.Controls.BandDefaultsButton.Layout.Column = 1;
            label = uilabel(bg, 'Text', '点=一个通道/频段汇总值；不伪造误差条'); label.Layout.Row = 3; label.Layout.Column = [2 3];
            label = uilabel(bg, 'Text', '背景校正功率与原始总功率分开保存'); label.Layout.Row = 4; label.Layout.Column = [1 3];

            plotTab = uitab(tabs, 'Title', '绘图');
            g = uigridlayout(plotTab, [8 2]); g.ColumnWidth = {190, '1x'}; g.RowHeight = repmat({32}, 1, 8);
            app.Controls.PlotFreqLow = app.addNumeric(g, 1, '显示频率下限 (Hz)', app.Config.plot.frequencyRange(1), 'plot');
            app.Controls.PlotFreqHigh = app.addNumeric(g, 2, '显示频率上限 (Hz)', app.Config.plot.frequencyRange(2), 'plot');
            app.Controls.PlotMaxSeconds = app.addNumeric(g, 3, '最大显示时长 (s)', app.Config.plot.maxPlotSeconds, 'plot');
            app.Controls.PlotFreqScale = app.addDropDown(g, 4, '频率轴', {'linear', 'log'}, char(app.Config.plot.frequencyScale), 'plot');
            app.Controls.PlotPowerScale = app.addDropDown(g, 5, '功率轴', {'linear', 'log10', 'dB'}, char(app.Config.plot.powerScale), 'plot');
            app.Controls.PlotShowLabels = app.addCheck(g, 6, '显示伪迹标签', app.Config.plot.showArtifactLabels, 'plot');
            app.Controls.PlotFontSize = app.addNumeric(g, 7, '字体大小', app.Config.plot.fontSize, 'plot');
            label = uilabel(g, 'Text', '绘图范围独立于 PSD/specparam/频段计算范围'); label.Layout.Row = 8; label.Layout.Column = [1 3];
        end

        function buildResultTabs(app, parent)
            tabs = uitabgroup(parent); app.Tabs.Results = tabs;
            rawTab = uitab(tabs, 'Title', '原始与伪迹');
            g = uigridlayout(rawTab, [4 1]); g.RowHeight = {34, '1x', '1x', 150};
            rawControls = uigridlayout(g, [1 6]); rawControls.Layout.Row = 1; rawControls.ColumnWidth = {170, 170, 120, '1x', 92, 92};
            app.Controls.RawDatasetDropDown = uidropdown(rawControls, 'Items', {'(未加载)'}, 'Value', '(未加载)', ...
                'ValueChangedFcn', @(s,e)app.onDatasetDropDownChanged(s,e));
            app.Controls.RawChannelDropDown = uidropdown(rawControls, 'Items', {'(未加载)'}, 'Value', '(未加载)', ...
                'ValueChangedFcn', @(s,e)app.onResultChannelChanged(s,e));
            app.Controls.RawOverlayMode = uidropdown(rawControls, 'Items', {'叠加', '单独显示'}, 'Value', '叠加', ...
                'ValueChangedFcn', @(s,e)app.onRedraw(s,e));
            uilabel(rawControls, 'Text', '选择数据集和通道；红色区域为伪迹标记', 'WordWrap', 'on');
            app.Controls.RawSaveFigure = uibutton(rawControls, 'Text', '保存图像', 'ButtonPushedFcn', @(s,e)app.onSaveView("raw",e));
            app.Controls.RawSaveData = uibutton(rawControls, 'Text', '保存数据', 'ButtonPushedFcn', @(s,e)app.onSaveViewData("raw",e));
            app.Controls.RawPlotPanel = uipanel(g, 'BorderType', 'none'); app.Controls.RawPlotPanel.Layout.Row=2;
            app.Controls.RawAxes = uiaxes(app.Controls.RawPlotPanel); app.Controls.RawAxes.Position=[10 10 700 420]; title(app.Controls.RawAxes, 'Raw signal'); grid(app.Controls.RawAxes, 'on');
            app.Controls.CleanPlotPanel = uipanel(g, 'BorderType', 'none'); app.Controls.CleanPlotPanel.Layout.Row=3;
            app.Controls.CleanAxes = uiaxes(app.Controls.CleanPlotPanel); app.Controls.CleanAxes.Position=[10 10 700 420]; title(app.Controls.CleanAxes, 'Clean/display (NaN excluded)'); grid(app.Controls.CleanAxes, 'on');
            app.Controls.ArtifactTable = uitable(g, 'ColumnName', {'artifactType','startSample','endSample','startTime','endTime','channel','score','threshold','method'}); app.Controls.ArtifactTable.Layout.Row=4;

            psdTab = uitab(tabs, 'Title', 'PSD'); g = uigridlayout(psdTab, [3 1]); g.RowHeight = {36, '1x', 70};
            psdControls = uigridlayout(g, [1 7]); psdControls.Layout.Row = 1; psdControls.ColumnWidth = {150, 150, 110, 135, '1x', 92, 92};
            app.Controls.PsdDatasetDropDown = uidropdown(psdControls, 'Items', {'(未加载)'}, 'Value', '(未加载)', ...
                'ValueChangedFcn', @(s,e)app.onDatasetDropDownChanged(s,e));
            app.Controls.PsdChannelDropDown = uidropdown(psdControls, 'Items', {'(未加载)'}, 'Value', '(未加载)', ...
                'ValueChangedFcn', @(s,e)app.onResultChannelChanged(s,e));
            app.Controls.PsdViewMode = uidropdown(psdControls, 'Items', {'单通道', '多通道', 'subplot'}, 'Value', '多通道', ...
                'ValueChangedFcn', @(s,e)app.onRedraw(s,e));
            app.Controls.PsdShowBefore = uicheckbox(psdControls, 'Text', '显示伪迹前 PSD', 'Value', false, ...
                'ValueChangedFcn', @(s,e)app.onRedraw(s,e));
            uilabel(psdControls, 'Text', '处理后 PSD 默认显示；线型保持可比较', 'WordWrap', 'on');
            app.Controls.PsdSaveFigure = uibutton(psdControls, 'Text', '保存图像', 'ButtonPushedFcn', @(s,e)app.onSaveView("psd",e));
            app.Controls.PsdSaveData = uibutton(psdControls, 'Text', '保存数据', 'ButtonPushedFcn', @(s,e)app.onSaveViewData("psd",e));
            app.Controls.PsdPlotPanel = uipanel(g, 'BorderType', 'none'); app.Controls.PsdPlotPanel.Layout.Row=2;
            app.Controls.PsdAxes = uiaxes(app.Controls.PsdPlotPanel); app.Controls.PsdAxes.Position=[10 10 700 420]; grid(app.Controls.PsdAxes, 'on');
            app.Controls.PsdInfoResult = uitextarea(g, 'Editable', 'off', 'Value', {'尚未计算 PSD'}); app.Controls.PsdInfoResult.Layout.Row=3;

            tfTab = uitab(tabs, 'Title', '时频分析'); g = uigridlayout(tfTab, [3 1]); g.RowHeight = {36, '1x', 28};
            tfControls = uigridlayout(g, [1 8]); tfControls.Layout.Row = 1; tfControls.ColumnWidth = {145, 145, 120, 100, 100, '1x', 92, 92};
            app.Controls.TfDatasetDropDown = uidropdown(tfControls, 'Items', {'(未加载)'}, 'Value', '(未加载)', ...
                'ValueChangedFcn', @(s,e)app.onDatasetDropDownChanged(s,e));
            app.Controls.TfChannelDropDown = uidropdown(tfControls, 'Items', {'(未加载)'}, 'Value', '(未加载)', ...
                'ValueChangedFcn', @(s,e)app.onResultChannelChanged(s,e));
            app.Controls.TfColorMode = uidropdown(tfControls, 'Items', {'自动（5%-95%）', '自动（最小-最大）', '手动'}, 'Value', '自动（5%-95%）', ...
                'ValueChangedFcn', @(s,e)app.onRedraw(s,e));
            app.Controls.TfColorLow = uieditfield(tfControls, 'numeric', 'Value', -5, 'ValueChangedFcn', @(s,e)app.onRedraw(s,e));
            app.Controls.TfColorHigh = uieditfield(tfControls, 'numeric', 'Value', 1, 'ValueChangedFcn', @(s,e)app.onRedraw(s,e));
            uilabel(tfControls, 'Text', '色限：自动采用稳健百分位；功率单位见 colorbar', 'WordWrap', 'on');
            app.Controls.TfSaveFigure = uibutton(tfControls, 'Text', '保存图像', 'ButtonPushedFcn', @(s,e)app.onSaveView("timeFrequency",e));
            app.Controls.TfSaveData = uibutton(tfControls, 'Text', '保存数据', 'ButtonPushedFcn', @(s,e)app.onSaveViewData("timeFrequency",e));
            app.Controls.PsdTimeFrequencyAxes = uiaxes(g); app.Controls.PsdTimeFrequencyAxes.Layout.Row=2; grid(app.Controls.PsdTimeFrequencyAxes, 'on');
            app.Controls.TfInfoResult = uilabel(g, 'Text', '尚未计算时频结果', 'WordWrap', 'on'); app.Controls.TfInfoResult.Layout.Row=3;

            fooofTab = uitab(tabs, 'Title', 'specparam（原FOOOF）'); g = uigridlayout(fooofTab, [3 1]); g.RowHeight = {34, '1x', 170};
            fooofControls = uigridlayout(g, [1 5]); fooofControls.Layout.Row = 1; fooofControls.ColumnWidth = {180, 180, '1x', 92, 92};
            app.Controls.FooofDatasetDropDown = uidropdown(fooofControls, 'Items', {'(未加载)'}, 'Value', '(未加载)', ...
                'ValueChangedFcn', @(s,e)app.onDatasetDropDownChanged(s,e));
            app.Controls.FooofChannelDropDown = uidropdown(fooofControls, 'Items', {'(未加载)'}, 'Value', '(未加载)', ...
                'ValueChangedFcn', @(s,e)app.onResultChannelChanged(s,e));
            uilabel(fooofControls, 'Text', '显示单通道模型与 Gaussian 峰分解', 'WordWrap', 'on');
            app.Controls.FooofSaveFigure = uibutton(fooofControls, 'Text', '保存图像', 'ButtonPushedFcn', @(s,e)app.onSaveView("specparam",e));
            app.Controls.FooofSaveData = uibutton(fooofControls, 'Text', '保存数据', 'ButtonPushedFcn', @(s,e)app.onSaveViewData("specparam",e));
            app.Controls.FooofAxes = uiaxes(g); app.Controls.FooofAxes.Layout.Row=2; grid(app.Controls.FooofAxes, 'on');
            app.Controls.FooofTable = uitable(g, 'ColumnName', {'CF_Hz','PW_log10','BW_Hz','peakBand'}); app.Controls.FooofTable.Layout.Row=3;

            bandTab = uitab(tabs, 'Title', '频段功率'); g = uigridlayout(bandTab, [3 1]); g.RowHeight = {34, '1x', 170};
            bandControls = uigridlayout(g, [1 3]); bandControls.Layout.Row = 1; bandControls.ColumnWidth = {'1x', 92, 92};
            uilabel(bandControls, 'Text', '按频段或通道查看功率；多数据集比较使用 grouped bar', 'WordWrap', 'on');
            app.Controls.BandSaveFigure = uibutton(bandControls, 'Text', '保存图像', 'ButtonPushedFcn', @(s,e)app.onSaveView("band",e));
            app.Controls.BandSaveData = uibutton(bandControls, 'Text', '保存数据', 'ButtonPushedFcn', @(s,e)app.onSaveViewData("band",e));
            app.Controls.BandPlotPanel = uipanel(g, 'BorderType', 'none'); app.Controls.BandPlotPanel.Layout.Row = 2;
            app.Controls.BandAxes = uiaxes(app.Controls.BandPlotPanel); app.Controls.BandAxes.Position = [10 10 500 300]; grid(app.Controls.BandAxes, 'on');
            app.Controls.BandResultTable = uitable(g); app.Controls.BandResultTable.Layout.Row = 3;
        end

        function control = addNumeric(app, grid, row, labelText, value, stage)
            label = uilabel(grid, 'Text', labelText, 'FontSize', app.UiStyle.labelFontSize, 'WordWrap', 'on'); label.Layout.Row = row; label.Layout.Column = 1;
            control = uieditfield(grid, 'numeric', 'Value', value, 'ValueChangedFcn', @(s,e)app.markChanged(stage));
            control.Layout.Row = row; control.Layout.Column = 2;
        end

        function control = addDropDown(app, grid, row, labelText, items, value, stage)
            label = uilabel(grid, 'Text', labelText, 'FontSize', app.UiStyle.labelFontSize, 'WordWrap', 'on'); label.Layout.Row = row; label.Layout.Column = 1;
            control = uidropdown(grid, 'Items', items, 'Value', value, 'ValueChangedFcn', @(s,e)app.markChanged(stage));
            control.Layout.Row = row; control.Layout.Column = 2;
        end

        function control = addCheck(app, grid, row, labelText, value, stage)
            control = uicheckbox(grid, 'Text', labelText, 'Value', value, 'FontSize', app.UiStyle.labelFontSize, 'ValueChangedFcn', @(s,e)app.markChanged(stage));
            if isprop(control, 'WordWrap'), control.WordWrap = 'on'; end
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
                    estimated = data.metadata.estimatedSamplingRateHz;
                    choice = uiconfirm(dialog, sprintf('输入采样率 %.6g Hz 与时间列估计值 %.6g Hz 相差超过 1%%。请选择如何保存。', fs, estimated), ...
                        '采样率不一致', 'Options', {'保留输入值', '使用估计值', '取消导入'}, 'DefaultOption', 1, 'CancelOption', 3);
                    if strcmp(choice, '取消导入'), return; end
                    if strcmp(choice, '使用估计值')
                        data.fs = estimated;
                        data.metadata.samplingRateHz = estimated;
                        data.metadata.importSettings.samplingRateHz = estimated;
                        data.metadata.samplingRateDecision = "time_column_estimate";
                    else
                        data.metadata.samplingRateDecision = "user_confirmed_input";
                    end
                    controls.status.Text = '采样率差异已由用户确认并记录。';
                    app.logMessage("时间列估计采样率与输入值不同，已记录用户选择。", "warning");
                end
                app.setData(data);
                uiresume(dialog);
            catch exception
                uialert(dialog, string(exception.message), '导入失败');
            end
        end

        function updateDataInfo(app)
            if isempty(fieldnames(app.Data))
                app.Controls.InfoArea.Value = {'未加载数据'}; return;
            end
            d = app.Data; n = size(d.signal, 1); c = size(d.signal, 2); [timeStart, timeEnd] = app.timeBounds(d);
            missing = nnz(~isfinite(d.signal));
            ipg = ""; if isfield(d.metadata, 'ipgSN'), ipg = string(d.metadata.ipgSN); end
            infoLines = [ ...
                "文件：" + string(d.metadata.sourceFileName); ...
                "IPG SN：" + ipg; ...
                string(sprintf('通道数：%d | 样本数：%d', c, n)); ...
                string(sprintf('采样率：%.6g Hz | 时间范围：%.3f–%.3f s', d.fs, timeStart, timeEnd)); ...
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
            cfg.psd.method = string(app.Controls.PsdMethod.Value);
            cfg.psd.detrend = "constant";
            cfg.psd.taper = string(app.Controls.PsdTaper.Value);
            cfg.psd.multitaper.timeBandwidthProduct = app.Controls.PsdNW.Value;
            cfg.psd.multitaper.taperCount = app.Controls.PsdK.Value;
            cfg.psd.multitaper.weighting = "equal";
            cfg.psd.frequencyRange = [app.Controls.PsdFreqLow.Value app.Controls.PsdFreqHigh.Value];
            cfg.psd.maxArtifactFraction = app.Controls.PsdMaxArtifact.Value;
            cfg.psd.excludeArtifacts = logical(app.Controls.PsdExclude.Value);
            cfg.psd.aggregationMethod = string(app.Controls.PsdAggregation.Value);
            cfg.psd.timeFrequency.enabled = logical(app.Controls.TfEnable.Value);
            cfg.psd.timeFrequency.reusePsdParameters = logical(app.Controls.TfReuse.Value);
            cfg.psd.timeFrequency.windowLengthSec = app.Controls.TfWindow.Value;
            cfg.psd.timeFrequency.stepSeconds = app.Controls.TfStep.Value;
            cfg.psd.timeFrequency.frequencyRange = [app.Controls.TfFreqLow.Value app.Controls.TfFreqHigh.Value];
            cfg.psd.timeFrequency.powerScale = string(app.Controls.TfPowerScale.Value);
            cfg.fooof.frequencyRange = [app.Controls.FooofFreqLow.Value app.Controls.FooofFreqHigh.Value];
            cfg.fooof.peakWidthLimits = [app.Controls.FooofWidthLow.Value app.Controls.FooofWidthHigh.Value];
            cfg.fooof.maxNumberPeaks = app.Controls.FooofMaxPeaks.Value;
            cfg.fooof.minPeakHeight = app.Controls.FooofMinHeight.Value;
            cfg.fooof.peakThreshold = app.Controls.FooofThreshold.Value;
            cfg.fooof.aperiodicMode = string(app.Controls.FooofMode.Value);
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
            app.Controls.PsdMethod.Value = char(get_field_local(cfg.psd, 'method', "welch"));
            app.Controls.PsdWindow.Value = cfg.psd.windowLengthSec; app.Controls.PsdOverlap.Value = cfg.psd.overlapFraction; app.Controls.PsdNfft.Value = cfg.psd.nfft;
            app.Controls.PsdTaper.Value = char(get_field_local(cfg.psd, 'taper', "hann"));
            mt = get_field_local(cfg.psd, 'multitaper', struct());
            app.Controls.PsdNW.Value = get_field_local(mt, 'timeBandwidthProduct', 3.5);
            app.Controls.PsdK.Value = get_field_local(mt, 'taperCount', floor(2 * app.Controls.PsdNW.Value) - 1);
            app.Controls.PsdFreqLow.Value = cfg.psd.frequencyRange(1); app.Controls.PsdFreqHigh.Value = cfg.psd.frequencyRange(2); app.Controls.PsdMaxArtifact.Value = cfg.psd.maxArtifactFraction;
            app.Controls.PsdExclude.Value = cfg.psd.excludeArtifacts; app.Controls.PsdAggregation.Value = char(cfg.psd.aggregationMethod);
            tf = get_field_local(cfg.psd, 'timeFrequency', struct());
            app.Controls.TfEnable.Value = get_field_local(tf, 'enabled', true);
            app.Controls.TfReuse.Value = get_field_local(tf, 'reusePsdParameters', true);
            app.Controls.TfWindow.Value = get_field_local(tf, 'windowLengthSec', 1);
            app.Controls.TfStep.Value = get_field_local(tf, 'stepSeconds', .25);
            tfRange = get_field_local(tf, 'frequencyRange', cfg.psd.frequencyRange);
            app.Controls.TfFreqLow.Value = tfRange(1); app.Controls.TfFreqHigh.Value = tfRange(2);
            app.Controls.TfPowerScale.Value = char(get_field_local(tf, 'powerScale', "log10"));
            app.Controls.FooofFreqLow.Value = cfg.fooof.frequencyRange(1); app.Controls.FooofFreqHigh.Value = cfg.fooof.frequencyRange(2);
            app.Controls.FooofWidthLow.Value = cfg.fooof.peakWidthLimits(1); app.Controls.FooofWidthHigh.Value = cfg.fooof.peakWidthLimits(2); app.Controls.FooofMaxPeaks.Value = cfg.fooof.maxNumberPeaks;
            app.Controls.FooofMinHeight.Value = cfg.fooof.minPeakHeight; app.Controls.FooofThreshold.Value = cfg.fooof.peakThreshold;
            app.Controls.FooofMode.Value = char(get_field_local(cfg.fooof, 'aperiodicMode', "fixed"));
            names = fieldnames(cfg.bands); bd = cell(numel(names), 3); for k = 1:numel(names), bd{k,1}=names{k}; bd{k,2}=cfg.bands.(names{k})(1); bd{k,3}=cfg.bands.(names{k})(2); end; app.Controls.BandTable.Data=bd;
            app.Controls.PlotFreqLow.Value = cfg.plot.frequencyRange(1); app.Controls.PlotFreqHigh.Value = cfg.plot.frequencyRange(2); app.Controls.PlotMaxSeconds.Value = cfg.plot.maxPlotSeconds;
            app.Controls.PlotFreqScale.Value = char(cfg.plot.frequencyScale); app.Controls.PlotPowerScale.Value = char(cfg.plot.powerScale); app.Controls.PlotShowLabels.Value = cfg.plot.showArtifactLabels; app.Controls.PlotFontSize.Value = cfg.plot.fontSize;
            app.onPsdMethodChanged([], []);
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
            app.AppState.selectedAnalysis = string(stage);
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
            [timeStart, timeEnd] = app.timeBounds(app.Data);
            r = snapshot.analysisRange;
            if numel(r) ~= 2 || any(~isfinite(r)) || r(1) < timeStart || r(2) <= r(1) || r(2) > timeEnd + 1/app.Data.fs
                error('LFP:InvalidAnalysisRange', '分析时间范围必须在数据实际时间范围内且结束时间大于起始时间。');
            end
            if snapshot.modules.psd || snapshot.modules.fooof || snapshot.modules.band
                if isfield(app.Data.metadata, 'timeValidation') && ...
                        (~app.Data.metadata.timeValidation.valid || app.Data.metadata.timeValidation.isIrregular)
                    error('LFP:IrregularSampling', '时间列不规则，已阻止均匀采样 PSD；请修正导入参数。');
                end
                if snapshot.cfg.psd.frequencyRange(2) > app.Data.fs/2
                    error('LFP:PsdAboveNyquist', 'PSD 上限不能超过 Nyquist 频率 %.6g Hz。', app.Data.fs/2);
                end
                if string(snapshot.cfg.psd.method) == "multitaper"
                    nw = snapshot.cfg.psd.multitaper.timeBandwidthProduct;
                    k = snapshot.cfg.psd.multitaper.taperCount;
                    if nw <= 0.5 || nw >= snapshot.cfg.psd.windowLengthSec * app.Data.fs / 2
                        error('LFP:InvalidDPSS', 'Multitaper NW 必须大于0.5且小于窗口样本数的一半。');
                    end
                    if k < 1 || k > floor(snapshot.cfg.psd.windowLengthSec * app.Data.fs)
                        error('LFP:InvalidDPSS', 'DPSS taper K 超出有效范围。');
                    end
                end
            end
            if snapshot.modules.fooof || snapshot.modules.band
                if snapshot.cfg.fooof.frequencyRange(2) > snapshot.cfg.psd.frequencyRange(2)
                    error('LFP:FooofOutsidePsd', 'specparam 拟合上限不能超过 PSD 上限。');
                end
            end
            if snapshot.modules.band && isempty(fieldnames(snapshot.cfg.bands)), error('LFP:InvalidBands', '至少选择一个频段。'); end
            tf = get_field_local(snapshot.cfg.psd, 'timeFrequency', struct());
            if (snapshot.modules.psd || snapshot.modules.fooof || snapshot.modules.band) && get_field_local(tf, 'enabled', false)
                if ~get_field_local(tf, 'reusePsdParameters', true) && get_field_local(tf, 'stepSeconds', 0) <= 0
                    error('LFP:InvalidTimeFrequency', '时频步长必须为正。');
                end
            end
        end

        function selected = selectChannels(~, data, channels)
            selected = data; selected.signal = data.signal(:, channels); selected.channelLabels = string(data.channelLabels(channels)); selected.channelNames = selected.channelLabels; selected.channelCount = numel(channels);
            if isfield(data, 'artifacts') && isfield(data.artifacts, 'channelMask') && isequal(size(data.artifacts.channelMask,2), size(data.signal,2)), selected.artifacts.channelMask = data.artifacts.channelMask(:, channels); end
            if isfield(selected, 'metadata'), selected.metadata.selectedChannels = channels; end
        end

        function index = timeIndexForRange(~, data, range)
            if isfield(data, 'time') && numel(data.time) == size(data.signal, 1) && all(isfinite(data.time)) && all(diff(data.time) > 0)
                index = find(data.time >= range(1) & data.time <= range(2));
            else
                first = max(1, floor(range(1) * data.fs) + 1); last = min(size(data.signal,1), ceil(range(2) * data.fs));
                index = first:last;
            end
            if numel(index) < 2, error('LFP:ShortAnalysisRange', '分析范围少于两个样本。'); end
        end

        function sliced = sliceData(~, data, index)
            sliced = data; sliced.signal = data.signal(index, :);
            if isfield(data, 'time') && numel(data.time) >= max(index)
                sliced.time = double(data.time(index));
            else
                sliced.time = (index(:) - 1) / data.fs;
            end
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
            app.renderRaw(); app.renderPsd(); app.renderTimeFrequency(); app.renderFooof(); app.renderBand();
        end

        function renderRaw(app)
            if isempty(fieldnames(app.Data)), return; end
            datasetIndices = app.selectedDatasetIndices();
            if numel(datasetIndices) > 1 && isfield(app.Controls, 'RawOverlayMode')
                if string(app.Controls.RawOverlayMode.Value) == "叠加"
                    app.renderRawOverlay(datasetIndices);
                    return;
                elseif string(app.Controls.RawOverlayMode.Value) == "单独显示"
                    app.renderRawSubplots(datasetIndices);
                    return;
                end
            end
            app.ensureSingleRawAxes();
            d=app.Data; channels=app.selectedChannels(); if isempty(channels), return; end
            r=[app.Controls.DisplayStart.Value app.Controls.DisplayEnd.Value];
            if isfield(d, 'time') && numel(d.time) == size(d.signal, 1) && all(isfinite(d.time)) && all(diff(d.time) > 0)
                idx = find(d.time >= r(1) & d.time <= r(2));
            else
                first=max(1,floor(r(1)*d.fs)+1); last=min(size(d.signal,1),ceil(r(2)*d.fs)); idx=first:last;
            end
            if isempty(idx), return; end
            if isfinite(app.Controls.PlotMaxSeconds.Value), idx=idx(1:min(numel(idx),max(1,round(app.Controls.PlotMaxSeconds.Value*d.fs)))); end
            if isfield(d, 'time') && numel(d.time) == size(d.signal, 1), t=double(d.time(idx)); else, t=(idx(:)-1)/d.fs; end
            raw=d.signal(idx,channels); clean=raw;
            displayArtifactMatches = ~isempty(fieldnames(app.ArtifactResult)) && isfield(app.ArtifactResult, 'channelIndices') && isequal(app.ArtifactResult.channelIndices(:)', channels(:)');
            if displayArtifactMatches && ~isempty(fieldnames(app.CleanData)) && isfield(app.CleanData,'cleanedSignal') && size(app.CleanData.cleanedSignal,1)>=max(idx) && size(app.CleanData.cleanedSignal,2)==numel(channels)
                clean=app.CleanData.cleanedSignal(idx, :);
            elseif displayArtifactMatches && app.compatibleArtifact(app.ArtifactResult, app.selectChannels(d,channels))
                mask=app.ArtifactResult.channelMask(idx,:); clean(mask)=NaN;
            end
            rawLimits=app.finiteLimits(raw); if any(~isfinite(rawLimits)), rawLimits=[-1 1]; end
            cla(app.Controls.RawAxes); plot(app.Controls.RawAxes,t,raw,'LineWidth',0.7); hold(app.Controls.RawAxes,'on'); if displayArtifactMatches, app.addArtifactPatches(app.Controls.RawAxes, idx, rawLimits, t); end; hold(app.Controls.RawAxes,'off');
            title(app.Controls.RawAxes, app.displayTitle("Raw signal"), 'Interpreter','none'); xlabel(app.Controls.RawAxes,'Time (s)'); ylabel(app.Controls.RawAxes,"Signal ("+string(d.units)+")"); app.Controls.RawAxes.YLim=rawLimits; grid(app.Controls.RawAxes,'on'); legend(app.Controls.RawAxes,cellstr(string(d.channelLabels(channels))),'Interpreter','none','Location','best');
            cla(app.Controls.CleanAxes); plot(app.Controls.CleanAxes,t,clean,'LineWidth',0.7); hold(app.Controls.CleanAxes,'on'); if displayArtifactMatches, app.addArtifactPatches(app.Controls.CleanAxes,idx,rawLimits,t); end; hold(app.Controls.CleanAxes,'off');
            title(app.Controls.CleanAxes, app.displayTitle("Clean/display (artifact samples = NaN)"), 'Interpreter','none'); xlabel(app.Controls.CleanAxes,'Time (s)'); ylabel(app.Controls.CleanAxes,"Signal ("+string(d.units)+")"); app.Controls.CleanAxes.YLim=rawLimits; grid(app.Controls.CleanAxes,'on'); legend(app.Controls.CleanAxes,cellstr(string(d.channelLabels(channels))),'Interpreter','none','Location','best');
            app.updateArtifactTable();
        end

        function renderRawOverlay(app, datasetIndices)
            if isempty(datasetIndices), return; end
            app.ensureSingleRawAxes();
            currentLabels=string(app.Data.channelLabels(:)); channel=app.channelIndexFromControl(app.Controls.RawChannelDropDown,currentLabels);
            r=[app.Controls.DisplayStart.Value app.Controls.DisplayEnd.Value]; rawSeries=cell(numel(datasetIndices),1); cleanSeries=cell(numel(datasetIndices),1); timeSeries=cell(numel(datasetIndices),1); names=strings(numel(datasetIndices),1); allValues=[];
            for k=1:numel(datasetIndices)
                entry=app.Datasets(datasetIndices(k)); names(k)=entry.fileName; idx=app.indicesForDisplay(entry,r); if isempty(idx), continue; end
                channelIndex=min(channel,size(entry.signal,2)); timeSeries{k}=entry.time(idx); rawSeries{k}=entry.signal(idx,channelIndex); cleanSeries{k}=rawSeries{k};
                results=entry.analysisResults;
                if isfield(results,'artifactResult') && isstruct(results.artifactResult) && isfield(results.artifactResult,'channelMask') && size(results.artifactResult.channelMask,1)>=max(idx) && size(results.artifactResult.channelMask,2)>=channelIndex
                    mask=results.artifactResult.channelMask(idx,channelIndex); cleanSeries{k}(mask)=NaN;
                end
                allValues=[allValues; rawSeries{k}(isfinite(rawSeries{k}))]; %#ok<AGROW>
            end
            if isempty(allValues), return; end
            limits=app.finiteLimits(allValues); colors=lines(numel(datasetIndices));
            cla(app.Controls.RawAxes); hold(app.Controls.RawAxes,'on'); cla(app.Controls.CleanAxes); hold(app.Controls.CleanAxes,'on');
            for k=1:numel(datasetIndices)
                if isempty(timeSeries{k}), continue; end
                plot(app.Controls.RawAxes,timeSeries{k},rawSeries{k},'Color',colors(k,:),'DisplayName',names(k),'LineWidth',0.7);
                plot(app.Controls.CleanAxes,timeSeries{k},cleanSeries{k},'Color',colors(k,:),'DisplayName',names(k),'LineWidth',0.7);
            end
            hold(app.Controls.RawAxes,'off'); hold(app.Controls.CleanAxes,'off');
            for ax=[app.Controls.RawAxes app.Controls.CleanAxes]
                ax.YLim=limits; xlabel(ax,'Time (s)'); ylabel(ax,"Signal ("+string(app.Data.units)+")"); grid(ax,'on'); legend(ax,'Location','best','Interpreter','none');
            end
            title(app.Controls.RawAxes,'Raw overlay | selected datasets','Interpreter','none'); title(app.Controls.CleanAxes,'Clean overlay | artifact samples = NaN','Interpreter','none'); app.updateArtifactTable();
        end

        function renderRawSubplots(app, datasetIndices)
            if isempty(datasetIndices), return; end
            currentLabels=string(app.Data.channelLabels(:)); channel=app.channelIndexFromControl(app.Controls.RawChannelDropDown,currentLabels);
            r=[app.Controls.DisplayStart.Value app.Controls.DisplayEnd.Value]; rawSeries=cell(numel(datasetIndices),1); cleanSeries=cell(numel(datasetIndices),1); timeSeries=cell(numel(datasetIndices),1); names=strings(numel(datasetIndices),1); allValues=[];
            for k=1:numel(datasetIndices)
                entry=app.Datasets(datasetIndices(k)); names(k)=entry.fileName; idx=app.indicesForDisplay(entry,r); if isempty(idx), continue; end
                channelIndex=min(channel,size(entry.signal,2)); timeSeries{k}=entry.time(idx); rawSeries{k}=entry.signal(idx,channelIndex); cleanSeries{k}=rawSeries{k};
                results=entry.analysisResults;
                if isfield(results,'artifactResult') && isstruct(results.artifactResult) && isfield(results.artifactResult,'channelMask') && size(results.artifactResult.channelMask,1)>=max(idx) && size(results.artifactResult.channelMask,2)>=channelIndex
                    mask=results.artifactResult.channelMask(idx,channelIndex); cleanSeries{k}(mask)=NaN;
                end
                allValues=[allValues; rawSeries{k}(isfinite(rawSeries{k}))]; %#ok<AGROW>
            end
            if isempty(allValues), return; end
            limits=app.finiteLimits(allValues); app.ensureRawSubplotLayouts(numel(datasetIndices));
            rawAxes=findall(app.Controls.RawPlotPanel,'Type','uiaxes'); rawAxes=flipud(rawAxes(:)); cleanAxes=findall(app.Controls.CleanPlotPanel,'Type','uiaxes'); cleanAxes=flipud(cleanAxes(:));
            for k=1:numel(datasetIndices)
                if isempty(timeSeries{k}), continue; end
                cla(rawAxes(k)); plot(rawAxes(k),timeSeries{k},rawSeries{k},'Color',[0.1 0.25 0.85],'LineWidth',0.7); rawAxes(k).YLim=limits; xlabel(rawAxes(k),'Time (s)'); ylabel(rawAxes(k),"Signal ("+string(app.Data.units)+")"); title(rawAxes(k),"Raw | "+names(k),'Interpreter','none'); grid(rawAxes(k),'on');
                cla(cleanAxes(k)); plot(cleanAxes(k),timeSeries{k},cleanSeries{k},'Color',[0.1 0.55 0.2],'LineWidth',0.7); cleanAxes(k).YLim=limits; xlabel(cleanAxes(k),'Time (s)'); ylabel(cleanAxes(k),"Signal ("+string(app.Data.units)+")"); title(cleanAxes(k),"Clean | "+names(k)+" (artifact samples = NaN)",'Interpreter','none'); grid(cleanAxes(k),'on');
            end
            app.Controls.RawAxes=rawAxes(1); app.Controls.CleanAxes=cleanAxes(1); app.updateArtifactTable();
        end

        function ensureSingleRawAxes(app)
            if ~isfield(app.Controls,'RawPlotPanel') || ~isgraphics(app.Controls.RawPlotPanel) || ~isfield(app.Controls,'CleanPlotPanel') || ~isgraphics(app.Controls.CleanPlotPanel), return; end
            rawAxes=findall(app.Controls.RawPlotPanel,'Type','uiaxes'); cleanAxes=findall(app.Controls.CleanPlotPanel,'Type','uiaxes');
            if numel(rawAxes)==1 && numel(cleanAxes)==1
                app.Controls.RawAxes=rawAxes(1); app.Controls.CleanAxes=cleanAxes(1); return;
            end
            delete(app.Controls.RawPlotPanel.Children); delete(app.Controls.CleanPlotPanel.Children);
            app.Controls.RawAxes=uiaxes(app.Controls.RawPlotPanel); app.Controls.RawAxes.Position=[10 10 700 420]; grid(app.Controls.RawAxes,'on');
            app.Controls.CleanAxes=uiaxes(app.Controls.CleanPlotPanel); app.Controls.CleanAxes.Position=[10 10 700 420]; grid(app.Controls.CleanAxes,'on');
        end

        function ensureRawSubplotLayouts(app, nDatasets)
            nRows=max(1,ceil(nDatasets/2));
            delete(app.Controls.RawPlotPanel.Children); delete(app.Controls.CleanPlotPanel.Children);
            rawLayout=uigridlayout(app.Controls.RawPlotPanel,[nRows 2]); rawLayout.RowHeight=repmat({'1x'},1,nRows); rawLayout.ColumnWidth={'1x','1x'}; rawLayout.Padding=[4 4 4 4];
            cleanLayout=uigridlayout(app.Controls.CleanPlotPanel,[nRows 2]); cleanLayout.RowHeight=repmat({'1x'},1,nRows); cleanLayout.ColumnWidth={'1x','1x'}; cleanLayout.Padding=[4 4 4 4];
            for k=1:nDatasets
                uiaxes(rawLayout); uiaxes(cleanLayout);
            end
        end

        function idx = indicesForDisplay(app, entry, range)
            if numel(entry.time) == size(entry.signal,1) && all(isfinite(entry.time)) && all(diff(entry.time)>0)
                idx=find(entry.time>=range(1) & entry.time<=range(2));
            else
                first=max(1,floor(range(1)*entry.fs)+1); last=min(size(entry.signal,1),ceil(range(2)*entry.fs)); idx=first:last;
            end
            if isfinite(app.Controls.PlotMaxSeconds.Value) && ~isempty(idx), idx=idx(1:min(numel(idx),max(1,round(app.Controls.PlotMaxSeconds.Value*entry.fs)))); end
        end

        function ensureSinglePsdAxes(app)
            if ~isfield(app.Controls, 'PsdPlotPanel') || ~isgraphics(app.Controls.PsdPlotPanel), return; end
            axesHandles = findall(app.Controls.PsdPlotPanel, 'Type', 'uiaxes');
            if numel(axesHandles) == 1
                app.Controls.PsdAxes = axesHandles(1); return;
            end
            delete(app.Controls.PsdPlotPanel.Children);
            app.Controls.PsdAxes = uiaxes(app.Controls.PsdPlotPanel); app.Controls.PsdAxes.Position=[10 10 700 420]; grid(app.Controls.PsdAxes, 'on');
        end

        function renderPsdSubplots(app, p, before, channels, labels)
            delete(app.Controls.PsdPlotPanel.Children);
            nRows=max(1,ceil(numel(channels)/2)); layout=uigridlayout(app.Controls.PsdPlotPanel,[nRows 2]); layout.RowHeight=repmat({'1x'},1,nRows); layout.ColumnWidth={'1x','1x'}; layout.Padding=[4 4 4 4];
            freq=p.frequencyHz; colors=lines(max(numel(channels),1)); axesHandles=gobjects(numel(channels),1);
            for k=1:numel(channels)
                ax=uiaxes(layout); axesHandles(k)=ax; hold(ax,'on'); [values,label]=app.displayPower(p.psd(:,channels(k))); plot(ax,freq,values,'-','Color',colors(k,:),'DisplayName','After');
                if isfield(app.Controls,'PsdShowBefore') && app.Controls.PsdShowBefore.Value && ~isempty(fieldnames(before)) && isfield(before,'psd') && isequal(size(before.psd),size(p.psd))
                    [old,~]=app.displayPower(before.psd(:,channels(k))); plot(ax,freq,old,':','Color',[.55 .55 .55],'DisplayName','Before');
                end
                xlabel(ax,'Frequency (Hz)'); ylabel(ax,label); title(ax,labels(channels(k)),'Interpreter','none'); grid(ax,'on'); legend(ax,'Location','best'); app.applyFrequencyLimits(ax,freq); hold(ax,'off');
            end
            if ~isempty(axesHandles), app.Controls.PsdAxes=axesHandles(1); end
        end

        function addArtifactPatches(app, ax, index, yLimits, timeVector)
            if isempty(fieldnames(app.ArtifactResult)) || ~isfield(app.ArtifactResult,'globalMask') || numel(app.ArtifactResult.globalMask) < max(index), return; end
            mask=app.ArtifactResult.globalMask(index); starts=find(diff([false;mask(:);false])==1); ends=find(diff([false;mask(:);false])==-1)-1;
            for k=1:numel(starts)
                x1=timeVector(starts(k)); x2=timeVector(ends(k));
                patch(ax,[x1 x2 x2 x1], [yLimits(1) yLimits(1) yLimits(2) yLimits(2)], [1 0.2 0.2], 'FaceAlpha',0.14,'EdgeColor','none','HandleVisibility','off');
            end
        end

        function updateArtifactTable(app)
            if isempty(fieldnames(app.ArtifactResult)) || ~isfield(app.ArtifactResult,'events') || ~istable(app.ArtifactResult.events)
                app.Controls.ArtifactTable.Data=cell(0,9); return;
            end
            e=app.ArtifactResult.events; if isempty(e), app.Controls.ArtifactTable.Data=cell(0,9); else app.Controls.ArtifactTable.Data=lfp_table_to_uitable_data(e); app.Controls.ArtifactTable.ColumnName=e.Properties.VariableNames; end
        end

        function renderPsd(app)
            if isempty(fieldnames(app.PsdResult)), app.ensureSinglePsdAxes(); cla(app.Controls.PsdAxes); app.Controls.PsdInfoResult.Value={'尚未计算 PSD'}; return; end
            p=app.PsdResult; labels=string(get_field_local(p,'channelLabels',app.Data.channelLabels(:))); labels=labels(:);
            mode = "多通道"; if isfield(app.Controls,'PsdViewMode'), mode=string(app.Controls.PsdViewMode.Value); end
            if mode == "单通道" && isfield(app.Controls,'PsdChannelDropDown')
                ch = app.channelIndexFromControl(app.Controls.PsdChannelDropDown, labels);
            else
                ch=app.selectedChannels(); ch=ch(ch<=size(p.psd,2)); if isempty(ch), ch=1:size(p.psd,2); end
            end
            if mode == "subplot" && numel(ch) > 1
                app.renderPsdSubplots(p, app.BeforePsd, ch, labels);
                app.Controls.PsdInfoResult.Value={sprintf('方法：%s | 显示模式：subplot | 通道数：%d | 频率点：%d',p.method,numel(ch),numel(p.frequencyHz)),sprintf('有效窗口：%s；功率单位：%s',mat2str(p.windowCount),p.psdUnits)};
                return;
            end
            app.ensureSinglePsdAxes(); cla(app.Controls.PsdAxes);
            freq=p.frequencyHz; before=app.BeforePsd; hold(app.Controls.PsdAxes,'on');
            [afterValues, powerLabel] = app.displayPower(p.psd(:,ch));
            if isfield(app.Controls,'PsdShowBefore') && app.Controls.PsdShowBefore.Value && ~isempty(fieldnames(before)) && isfield(before,'psd') && isequal(size(before.psd),size(p.psd))
                [beforeValues, ~] = app.displayPower(before.psd(:,ch));
                for k=1:numel(ch), app.plotSpectrum(app.Controls.PsdAxes, freq, beforeValues(:,k), ':', [0.55 0.55 0.55], 'Before | '+labels(ch(k))); end
            end
            colors=lines(max(numel(ch),1));
            for k=1:numel(ch), app.plotSpectrum(app.Controls.PsdAxes, freq, afterValues(:,k), '-', colors(k,:), 'After | '+labels(ch(k))); end
            hold(app.Controls.PsdAxes,'off'); app.applyFrequencyLimits(app.Controls.PsdAxes, freq); xlabel(app.Controls.PsdAxes,'Frequency (Hz)'); ylabel(app.Controls.PsdAxes,powerLabel); title(app.Controls.PsdAxes, app.displayTitle('PSD')); grid(app.Controls.PsdAxes,'on'); legend(app.Controls.PsdAxes,'Location','best','Interpreter','none');
            app.Controls.PsdInfoResult.Value={sprintf('方法：%s | 显示模式：%s | 频率点：%d | Δf=%.6g Hz',p.method,mode,numel(freq),p.frequencyResolutionHz),sprintf('有效窗口：%s',mat2str(p.windowCount)),sprintf('PSD 范围：[%.3g %.3g] Hz；功率单位：%s',freq(1),freq(end),p.psdUnits)};
        end

        function renderTimeFrequency(app)
            if ~isfield(app.Controls, 'PsdTimeFrequencyAxes') || ~isgraphics(app.Controls.PsdTimeFrequencyAxes), return; end
            cla(app.Controls.PsdTimeFrequencyAxes);
            % MATLAB's headless uiaxes renderer can block on imagesc.  A
            % hidden GUI is used by automated tests and batch smoke checks;
            % keep the result state available without attempting a display.
            if isgraphics(app.Figure) && strcmp(app.Figure.Visible, 'off')
                if isfield(app.Controls,'TfInfoResult'), app.Controls.TfInfoResult.Text='时频结果已计算（隐藏窗口不渲染图像）。'; end
                return;
            end
            if isempty(fieldnames(app.PsdResult)) || ~isfield(app.PsdResult, 'timeFrequency') || ~isstruct(app.PsdResult.timeFrequency) || ~isfield(app.PsdResult.timeFrequency, 'power')
                title(app.Controls.PsdTimeFrequencyAxes, '尚未计算时频结果');
                if isfield(app.Controls,'TfInfoResult'), app.Controls.TfInfoResult.Text='尚未计算时频结果'; end
                return;
            end
            tf=app.PsdResult.timeFrequency; labels=string(get_field_local(app.PsdResult,'channelLabels',app.Data.channelLabels(:))); labels=labels(:);
            channel=1; if isfield(app.Controls,'TfChannelDropDown'), channel=app.channelIndexFromControl(app.Controls.TfChannelDropDown,labels); end
            values=tf.power(:,:,min(channel,size(tf.power,3))); scale=string(get_field_local(tf,'powerScale','linear'));
            if scale=="log10", displayValues=log10(max(values,realmin)); displayUnit='log10(power)'; elseif scale=="dB", displayValues=10*log10(max(values,realmin)); displayUnit='Power (dB)'; else, displayValues=values; displayUnit=string(get_field_local(tf,'powerUnits','units^2/Hz')); end
            imagesc(app.Controls.PsdTimeFrequencyAxes, tf.timeSeconds, tf.frequencyHz, displayValues); axis(app.Controls.PsdTimeFrequencyAxes,'xy'); colorbar(app.Controls.PsdTimeFrequencyAxes); xlabel(app.Controls.PsdTimeFrequencyAxes,'Time (s)'); ylabel(app.Controls.PsdTimeFrequencyAxes,'Frequency (Hz)');
            title(app.Controls.PsdTimeFrequencyAxes, sprintf('时频功率 | %s | %s',labels(channel),get_field_local(tf,'method','unknown')),'Interpreter','none'); app.applyFrequencyLimits(app.Controls.PsdTimeFrequencyAxes,tf.frequencyHz);
            finite=displayValues(isfinite(displayValues)); mode='auto';
            if isfield(app.Controls,'TfColorMode'), mode=char(app.Controls.TfColorMode.Value); end
            if strcmp(mode,'手动') && isfield(app.Controls,'TfColorLow') && isfield(app.Controls,'TfColorHigh')
                low=app.Controls.TfColorLow.Value; high=app.Controls.TfColorHigh.Value;
            elseif isempty(finite)
                low=0; high=1;
            elseif startsWith(string(mode),'自动（5%')
                low=percentile_local(finite,5); high=percentile_local(finite,95);
            else
                low=min(finite); high=max(finite);
            end
            if isfinite(low) && isfinite(high) && high>low, caxis(app.Controls.PsdTimeFrequencyAxes,[low high]); end
            if isfield(app.Controls,'TfInfoResult'), app.Controls.TfInfoResult.Text=sprintf('通道：%s | 方法：%s | 显示：%s | 窗长 %.3g s，步长 %.3g s | 色限 [%.3g %.3g]',labels(channel),get_field_local(tf,'method','unknown'),displayUnit,get_field_local(tf,'windowSeconds',NaN),get_field_local(tf,'stepSeconds',NaN),low,high); end
        end

        function renderFooof(app)
            cla(app.Controls.FooofAxes); app.Controls.FooofTable.Data=cell(0,4); if isempty(app.ModelResult), return; end
            labels=string(get_field_local(app.PsdResult,'channelLabels',app.Data.channelLabels(:))); labels=labels(:);
            if isfield(app.Controls,'FooofChannelDropDown'), ch=app.channelIndexFromControl(app.Controls.FooofChannelDropDown,labels); else, ch=app.selectedChannels(); ch=ch(1); end
            ch=min(max(1,ch),numel(app.ModelResult)); m=app.ModelResult(ch); f=m.freq;
            valid=f>0 & isfinite(m.inputPower) & m.inputPower>0; hold(app.Controls.FooofAxes,'on'); [inputValues, powerLabel] = app.displayPower(m.inputPower); app.plotSpectrum(app.Controls.FooofAxes,f(valid),inputValues(valid),'-',[0 0 0],'Original PSD');
            if any(isfinite(m.fullModelFit)), [fullValues, ~] = app.displayPower(m.fullModelFit); app.plotSpectrum(app.Controls.FooofAxes,f,fullValues,'-',[0.8 0 0],'Full model'); end
            if any(isfinite(m.aperiodicFit)), [aperiodicValues, ~] = app.displayPower(m.aperiodicFit); app.plotSpectrum(app.Controls.FooofAxes,f,aperiodicValues,'--',[0 0.25 0.8],'Aperiodic'); end
            if any(isfinite(m.periodicFit)), [periodicValues, ~] = app.displayPower(m.aperiodicFit+m.periodicFit); app.plotSpectrum(app.Controls.FooofAxes,f,periodicValues,':',[0.1 0.6 0.1],'Periodic-inclusive'); end
            if isfield(m,'gaussianParams') && ~isempty(m.gaussianParams) && any(isfinite(m.aperiodicFit))
                gaussianSum = zeros(size(f));
                peakColors = lines(numel(m.gaussianParams));
                for peakIndex=1:numel(m.gaussianParams)
                    g=m.gaussianParams(peakIndex); componentLog=g.amplitudeLog10*exp(-0.5*((f-g.centerFrequencyHz)/g.sigmaHz).^2); gaussianSum=gaussianSum+componentLog;
                    componentPower=10.^(log10(max(m.aperiodicFit,realmin))+componentLog); app.plotSpectrum(app.Controls.FooofAxes,f,componentPower,'-.',peakColors(peakIndex,:),sprintf('Gaussian %d (CF %.2f Hz)',peakIndex,g.centerFrequencyHz));
                end
                sumPower=10.^(log10(max(m.aperiodicFit,realmin))+gaussianSum); app.plotSpectrum(app.Controls.FooofAxes,f,sumPower,'-',[0.1 0.6 0.1],'Sum of Gaussian peaks');
            end
            xline(app.Controls.FooofAxes,m.fitRange,':','Color',[.4 .4 .4]);
            if ~isempty(m.peakParams), centers=[m.peakParams.CF]; xline(app.Controls.FooofAxes,centers,'--','Color',[.1 .6 .1]); end
            kneeText = '';
            if isfield(m.aperiodicParams, 'knee') && isfinite(m.aperiodicParams.knee), kneeText = sprintf(' | knee %.4g', m.aperiodicParams.knee); end
            modeText = get_field_local(m.aperiodicParams, 'mode', "fixed");
            hold(app.Controls.FooofAxes,'off'); app.applyFrequencyLimits(app.Controls.FooofAxes, f); xlabel(app.Controls.FooofAxes,'Frequency (Hz)'); ylabel(app.Controls.FooofAxes,powerLabel); title(app.Controls.FooofAxes,sprintf('%s | dataset=%s | channel=%s | status=%s | mode=%s | offset %.3f | exponent %.3f%s | R² %.3f | error %.3f',app.displayTitle('specparam（原FOOOF）'),app.currentDatasetName(),labels(ch),m.fitStatus,modeText,m.aperiodicParams.offset,m.aperiodicParams.exponent,kneeText,m.rSquared,m.fitError),'Interpreter','none'); legend(app.Controls.FooofAxes,'Location','best','Interpreter','none'); grid(app.Controls.FooofAxes,'on');
            if ~isempty(m.peakParams), rows=cell(numel(m.peakParams),4); for k=1:numel(m.peakParams), rows{k,1}=m.peakParams(k).CF; rows{k,2}=m.peakParams(k).PW; rows{k,3}=m.peakParams(k).BW; rows{k,4}=char(m.peakParams(k).peakBand); end; app.Controls.FooofTable.Data=rows; end
            app.Controls.FooofTable.ColumnName={'CF_Hz','PW_log10','BW_Hz','peakBand'};
        end

        function renderBand(app)
            if isgraphics(app.Controls.BandPlotPanel)
                delete(app.Controls.BandPlotPanel.Children);
            end
            app.Controls.BandResultTable.Data=cell(0,1); if isempty(fieldnames(app.BandResult)) || ~isfield(app.BandResult,'table'), return; end
            tbl=app.BandResult.table; app.Controls.BandResultTable.Data=lfp_table_to_uitable_data(tbl); app.Controls.BandResultTable.ColumnName=tbl.Properties.VariableNames;
            metric=string(app.Controls.BandMetric.Value); names=unique(string(tbl.band),'stable'); chans=unique(tbl.channelIndex,'stable');
            selectedDatasets = app.selectedDatasetIndices();
            if numel(selectedDatasets) > 1 && app.hasBandResults(selectedDatasets)
                app.renderBandGrouped(selectedDatasets, metric);
                return;
            end
            facetByBand = string(app.Controls.BandFacet.Value) == "按频段分面";
            if facetByBand, nPlots = numel(names); else, nPlots = numel(chans); end
            nCols = max(1, min(3, nPlots)); nRows = max(1, ceil(nPlots / nCols));
            panelGrid = uigridlayout(app.Controls.BandPlotPanel, [nRows nCols]); panelGrid.RowHeight = repmat({'1x'},1,nRows); panelGrid.ColumnWidth = repmat({'1x'},1,nCols); panelGrid.Padding = [4 4 4 4];
            plotAxes = gobjects(nPlots,1);
            if nPlots == 0, return; end
            for plotIndex = 1:nPlots
                ax = uiaxes(panelGrid); plotAxes(plotIndex) = ax;
                if facetByBand
                    bandName = names(plotIndex); values = NaN(numel(chans),1);
                    for i=1:numel(chans), row=tbl.channelIndex==chans(i) & string(tbl.band)==bandName; if any(row), values(i)=tbl.(metric)(find(row,1)); end, end
                    channelLabels = strings(numel(chans),1); for c=1:numel(chans), channelLabels(c)=string(tbl.channelLabel(find(tbl.channelIndex==chans(c),1))); end
                    scatter(ax, 1:numel(chans), values, 28, 'filled'); set(ax,'XTick',1:numel(chans),'XTickLabel',cellstr(channelLabels)); xlabel(ax,'Channel'); title(ax, bandName + " [" + string(tbl.lowHz(find(string(tbl.band)==bandName,1))) + "-" + string(tbl.highHz(find(string(tbl.band)==bandName,1))) + " Hz]", 'Interpreter','none');
                else
                    channel = chans(plotIndex); values = NaN(numel(names),1);
                    for j=1:numel(names), row=tbl.channelIndex==channel & string(tbl.band)==names(j); if any(row), values(j)=tbl.(metric)(find(row,1)); end, end
                    scatter(ax, 1:numel(names), values, 28, 'filled'); set(ax,'XTick',1:numel(names),'XTickLabel',cellstr(names)); xlabel(ax,'Band'); title(ax, string(tbl.channelLabel(find(tbl.channelIndex==channel,1))), 'Interpreter','none');
                end
                ylabel(ax, metric); grid(ax,'on');
            end
            app.Controls.BandAxes = plotAxes(1);
        end

        function tf = hasBandResults(app, indices)
            tf = true;
            for k=1:numel(indices)
                r=app.Datasets(indices(k)).analysisResults;
                if ~isfield(r,'bandResult') || ~isstruct(r.bandResult) || ~isfield(r.bandResult,'table') || isempty(r.bandResult.table)
                    tf=false; return;
                end
            end
        end

        function renderBandGrouped(app, indices, metric)
            firstTable=app.Datasets(indices(1)).analysisResults.bandResult.table;
            bandNames=unique(string(firstTable.band),'stable'); channelIndices=unique(firstTable.channelIndex,'stable');
            nRows=max(1,ceil(numel(bandNames)/2)); panelGrid=uigridlayout(app.Controls.BandPlotPanel,[nRows 2]); panelGrid.RowHeight=repmat({'1x'},1,nRows); panelGrid.ColumnWidth={'1x','1x'}; panelGrid.Padding=[4 4 4 4];
            axesList=gobjects(numel(bandNames),1); datasetNames=strings(numel(indices),1);
            for d=1:numel(indices), datasetNames(d)=app.Datasets(indices(d)).fileName; end
            for b=1:numel(bandNames)
                ax=uiaxes(panelGrid); axesList(b)=ax; values=NaN(numel(channelIndices),numel(indices));
                for d=1:numel(indices)
                    t=app.Datasets(indices(d)).analysisResults.bandResult.table;
                    for c=1:numel(channelIndices)
                        row=t.channelIndex==channelIndices(c) & string(t.band)==bandNames(b);
                        if any(row) && ismember(metric,string(t.Properties.VariableNames)), values(c,d)=t.(metric)(find(row,1)); end
                    end
                end
                bar(ax,values,'grouped'); labels=strings(numel(channelIndices),1);
                for c=1:numel(channelIndices), row=firstTable.channelIndex==channelIndices(c); labels(c)=string(firstTable.channelLabel(find(row,1))); end
                ax.XTick=1:numel(channelIndices); ax.XTickLabel=cellstr(labels); xlabel(ax,'Channel'); ylabel(ax,metric); title(ax,bandNames(b),'Interpreter','none'); legend(ax,cellstr(datasetNames),'Interpreter','none','Location','best'); grid(ax,'on');
            end
            if ~isempty(axesList), app.Controls.BandAxes=axesList(1); end
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
            % Keep the editable import default deterministic.  A measured
            % rate from a time column is shown in the dialog note and is
            % never silently used to overwrite the user's confirmation.
            defaultText = '1000';
        end

        function [timeStart, timeEnd] = timeBounds(~, data)
            if isfield(data, 'time') && numel(data.time) == size(data.signal, 1) && ~isempty(data.time) && all(isfinite(data.time))
                timeStart = double(data.time(1));
                timeEnd = double(data.time(end));
            else
                timeStart = 0;
                timeEnd = max(0, (size(data.signal, 1) - 1) / data.fs);
            end
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
            if isfield(merged, 'fooof') && isfield(merged.fooof, 'interpolateLineNoise')
                legacyFields = intersect(fieldnames(merged.fooof), {'interpolateLineNoise', 'lineFrequencyHz', ...
                    'lineInterpolationHalfWidthHz', 'lineInterpolationBufferSamples', 'lineIncludeHarmonics'});
                if ~isempty(legacyFields), merged.fooof = rmfield(merged.fooof, legacyFields); end
            end
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

function value = percentile_local(values, percentile)
values = sort(double(values(:)));
if isempty(values), value = NaN; return; end
position = 1 + (numel(values) - 1) * percentile / 100;
lower = floor(position); upper = ceil(position);
if lower == upper, value = values(lower); else, value = values(lower) + (position - lower) * (values(upper) - values(lower)); end
end

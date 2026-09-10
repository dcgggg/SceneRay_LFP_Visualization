classdef LfpAnalysisTaskManager < handle
    %LFPANALYSISTASKMANAGER Track GUI analysis stages, timing and cancellation.
    %   The manager does not run algorithms or require Parallel Computing
    %   Toolbox. It provides cooperative cancellation and progress hooks so
    %   long base-MATLAB loops can periodically yield to the UI with drawnow.

    properties (SetAccess=private)
        IsRunning = false
        CancelRequested = false
        CurrentStage = ""
        StageTimings = struct('name', {}, 'seconds', {}, 'status', {})
        TotalSeconds = NaN
    end

    properties
        ProgressCallback = []
        LogCallback = []
    end

    properties (Access=private)
        TotalTimer
        StageTimer
        StageIndex = 0
        StageCount = 0
    end

    methods
        function manager = LfpAnalysisTaskManager(progressCallback, logCallback)
            if nargin >= 1, manager.ProgressCallback = progressCallback; end
            if nargin >= 2, manager.LogCallback = logCallback; end
        end

        function start(manager, stageCount)
            if manager.IsRunning, error('LFP:TaskAlreadyRunning', 'An analysis task is already running.'); end
            manager.IsRunning = true; manager.CancelRequested = false;
            manager.CurrentStage = ""; manager.StageTimings = struct('name', {}, 'seconds', {}, 'status', {});
            manager.TotalSeconds = NaN; manager.StageIndex = 0; manager.StageCount = max(1, round(stageCount));
            manager.TotalTimer = tic; manager.emit(0, "Running...");
        end

        function beginStage(manager, name, stageIndex, stageCount)
            manager.checkCancelled();
            if strlength(manager.CurrentStage) > 0, manager.finishStage("completed"); end
            manager.CurrentStage = string(name); manager.StageIndex = stageIndex;
            if nargin >= 4, manager.StageCount = max(1, stageCount); end
            manager.StageTimer = tic;
            manager.emit((stageIndex - 1) / manager.StageCount, sprintf('Stage %d/%d: %s', stageIndex, manager.StageCount, name));
            manager.log("开始：" + string(name));
        end

        function update(manager, localFraction, message)
            manager.checkCancelled();
            fraction = (manager.StageIndex - 1 + max(0, min(1, localFraction))) / manager.StageCount;
            manager.emit(fraction, string(message));
        end

        function finishStage(manager, status)
            if strlength(manager.CurrentStage) == 0, return; end
            seconds = toc(manager.StageTimer);
            manager.StageTimings(end + 1) = struct('name', manager.CurrentStage, ...
                'seconds', seconds, 'status', string(status)); %#ok<AGROW>
            manager.log(sprintf('%s：%.3f s', manager.CurrentStage, seconds));
            manager.CurrentStage = "";
        end

        function requestCancel(manager)
            manager.CancelRequested = true;
            manager.log("已请求取消；将在当前算法下一个检查点停止。");
        end

        function complete(manager)
            if strlength(manager.CurrentStage) > 0, manager.finishStage("completed"); end
            manager.TotalSeconds = toc(manager.TotalTimer); manager.IsRunning = false;
            manager.emit(1, sprintf('Analysis completed in %.3f s', manager.TotalSeconds));
            manager.log(sprintf('总耗时：%.3f s', manager.TotalSeconds));
        end

        function fail(manager, exception)
            if strlength(manager.CurrentStage) > 0
                status = "failed";
                if strcmp(exception.identifier, 'LFP:UserCancelled'), status = "cancelled"; end
                manager.finishStage(status);
            end
            if ~isempty(manager.TotalTimer), manager.TotalSeconds = toc(manager.TotalTimer); end
            manager.IsRunning = false;
        end

        function result = summary(manager)
            result = struct('totalSeconds', manager.TotalSeconds, ...
                'stageTimings', manager.StageTimings, 'cancelRequested', manager.CancelRequested);
        end

        function checkCancelled(manager)
            drawnow limitrate;
            if manager.CancelRequested
                error('LFP:UserCancelled', '用户取消了本次运行。');
            end
        end

        function reset(manager)
            manager.IsRunning = false; manager.CancelRequested = false; manager.CurrentStage = "";
        end

        function summary = getSummary(manager)
            summary = struct('stageTimings', manager.StageTimings, ...
                'totalSeconds', manager.TotalSeconds, 'cancelRequested', manager.CancelRequested);
        end
    end

    methods (Access=private)
        function emit(manager, fraction, message)
            if isempty(manager.ProgressCallback), return; end
            manager.ProgressCallback(max(0, min(1, fraction)), string(message));
        end

        function log(manager, message)
            if isempty(manager.LogCallback), return; end
            manager.LogCallback(string(message));
        end
    end

end

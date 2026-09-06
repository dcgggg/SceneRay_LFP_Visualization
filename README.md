# SceneRay MATLAB LFP Analysis

模块化、可测试的 MATLAB 局部场电位（LFP）分析与可视化项目。当前版本提供脚本/API 工作流；GUI 暂不实现。

## 目标

- 读取 SceneRay 及通用 CSV LFP 数据；
- 保留原始数据并标记疑似伪影；
- 计算 PSD、总功率、相对功率和周期功率；
- 分离周期峰与非周期背景；
- 输出可追溯的参数、结果、图片和处理日志；
- 后续阶段可提供 MATLAB 原生 GUI，但算法核心始终可由脚本直接调用。

## 环境

- 最低设计版本：MATLAB R2022b；
- 当前开发机检测到：MATLAB R2024a、Signal Processing Toolbox、Statistics and Machine Learning Toolbox、FieldTrip；
- 当前未检测到 EEGLAB 或 MATLAB 版 FOOOF/specparam；后续频谱参数化优先使用 FieldTrip 或 MATLAB 原生实现；
- 不在运行时下载依赖。可选工具箱只用于加速或扩展，基础 MATLAB 路径负责核心兼容性。

## 当前状态

当前已完成 SceneRay CSV 导入、非破坏性伪影标记、FieldTrip/native artifact backend、artifact-aware Welch PSD、40 Hz 谐波拟合前插值、fixed/no-knee 1/f 参数化、Gaussian 周期峰、频带功率、伪影/PSD/频带/模型对照图和结果导出。导入器通过寻找每个 `Channel` 元数据行自动识别通道数，并在每个块内部寻找对应的 `Time Index, Voltage, Tag Code` 表头；当前约定为 1 kHz、μV。伪影只写入掩码和处理副本，不覆盖原始信号。

`fooof_mat` 是 MATLAB 对 Python FOOOF 的封装，需要 Python 运行环境，因此不纳入本项目的核心依赖。FieldTrip/原生 MATLAB 路径将保持纯 MATLAB 运行。

## 快速分析

```matlab
addpath('src');
data = lfp_import_scenray_csv("my_recording.csv");
cfg = lfpDefaultConfig();
[cleanData, artifactResult] = detectAndHandleArtifacts(data, cfg.artifact);
psdResult = computeLfpPsd(cleanData, artifactResult, cfg.psd);
modelResult = parameterizePowerSpectrum(psdResult.frequencyHz, psdResult.psd, cfg.fooof);
bandResult = computeBandPower(psdResult, modelResult, cfg.bands);
cleanData.spectrum = psdResult;
cleanData.spectralParameters = struct('aperiodicPsd', horzcat(modelResult.aperiodicFit), ...
    'periodicPowerAboveAperiodic', horzcat(modelResult.periodicFit));
cleanData.bandPower = bandResult;
plotArtifactComparison(data, cleanData, artifactResult, cfg.plot);
plotSpectralModel(modelResult(1), cfg.plot);
plotAnalysisSummary(artifactResult, psdResult, modelResult, bandResult, cfg.plot);
files = lfp_export_results(cleanData, "results");
```

## 批量处理文件夹

如果需要一次处理文件夹中的所有 CSV，可以只调用一次批处理入口。每个文件内部的多个 `Channel` 区块会自动变成独立通道列，后续 PSD、参数化和频段功率均按通道分别计算：

```matlab
inputFolder = "C:\Users\PC\Desktop\test";
cfg = lfpDefaultConfig();
batch = analyzeLfpFolder(inputFolder, cfg, ...
    OutputFolder="results", MakeFigures=true, ExportResults=true);

for k = 1:batch.fileCount
    fprintf('%s | IPG SN %s | %d channels | %s\n', ...
        batch.files(k).fileName, batch.files(k).ipgSN, ...
        batch.files(k).channelCount, batch.files(k).status);
end
```

结果中的 `channelLabels`、`channelNames`、`channelCount` 和 `ipgSN` 会保留到每个文件的结果结构与图标题中。批处理只对每个文件执行一次导入、伪影、PSD、参数化和频段功率计算；绘图和导出是可选步骤。

40 Hz 及其 Nyquist 以下谐波保留在原始时域和 PSD 中；`parameterizePowerSpectrum` 默认调用拟合副本上的 log-log 插值（可由 `cfg.fooof.interpolateLineNoise` 关闭），并在 `modelResult.lineNoise` / `modelResult.fittingPower` 中记录结果，`modelResult.inputPower` 始终是原始 PSD。`cfg.psd.frequencyRange` 和 `cfg.fooof.frequencyRange` 默认均为 `[1 40]`，超出 PSD 范围的频带返回 NaN，而不是虚假功率。当前不执行时频分析、PAC 或功能连接。

绘图函数支持 `cfg.plot.parent` 指定 Figure、uipanel 或 uitab；所有分析函数仍可在无 GUI 的 MATLAB 脚本中独立调用。`computeLfpPsd` 和 `computeBandPower` 也会返回带有 `processingHistory` 的结果结构，便于未来 GUI 或批处理保存审计轨迹。

## 初始化测试

在 MATLAB 中从仓库根目录执行：

```matlab
results = runtests('tests');
assert(all([results.Passed]));
```

也可以检查入口：

```matlab
addpath('src');
info = lfp_project_startup();
disp(info);
```

## 目录约定

```text
src/       分析核心与公共入口
tests/     matlab.unittest 测试
examples/  可运行示例
docs/      架构、数据格式和算法说明
```

## 数据安全

原始数据和生成结果不应提交到 Git。`.gitignore` 默认排除 `data/raw/`、`data/private/`、`results/`、`*_results/` 和 MAT/FIG 文件。

## 版本历史

见 [CHANGELOG.md](CHANGELOG.md)。长期开发规则见 [AGENTS.md](AGENTS.md)。

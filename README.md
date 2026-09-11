# SceneRay MATLAB LFP Analysis

模块化、可测试的 MATLAB 局部场电位（LFP）分析与可视化项目。当前版本同时提供脚本/API 工作流和 MATLAB 原生 GUI；GUI 只负责交互与状态管理，算法仍可脱离界面调用。

当前本地开发版本：**v0.9.0**。本版本移除时频分析链路，修复 specparam 与频带功率协作、结果状态和频段越界标记，并保留多 CSV 数据集管理、PSD 显示模式、Gaussian 峰分解、分组频段比较及大文件导入优化。新增可选的 Project→Subject→Session→Channel 数据管理、AnalysisRun 版本缓存、比较长表和 GUI-free 批处理入口。

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
- 频谱参数化使用项目内置的 MATLAB 原生 specparam 实现；不需要 Python 或外部服务；
- 不在运行时下载依赖。可选工具箱只用于加速或扩展，基础 MATLAB 路径负责核心兼容性。

## 调用的代码、工具包与官方网站

下表列出本项目实际调用、检测或作为算法依据的代码/工具包及其官方地址。核心分析路径只需要 MATLAB 本体，不调用 Python、R、Java、Node.js 或外部服务器。

| 名称 | 代码中的用途 | 是否必需 | 官方网站 |
| --- | --- | --- | --- |
| MATLAB R2022b 或更高版本 | 运行全部分析、绘图和批处理函数；核心 PSD 使用 `fft`、`interp1` 等基础函数 | 必需 | [MATLAB](https://www.mathworks.com/products/matlab.html) |
| MATLAB Unit Testing Framework | 运行 `tests/` 中的 `matlab.unittest` 自动化测试 | 仅开发/测试必需 | [MATLAB Unit Testing Framework](https://www.mathworks.com/help/matlab/matlab-unit-testing-framework.html) |
| Signal Processing Toolbox | 由 `lfp_project_startup` 检测；Welch 与 DPSS multitaper 均提供基础 MATLAB 实现，可用工具箱加速但不是运行必需 | 可选 | [Signal Processing Toolbox](https://www.mathworks.com/products/signal.html) |
| Statistics and Machine Learning Toolbox | 由 `lfp_project_startup` 检测；当前 fixed/no-knee 拟合提供 MATLAB 基础实现，不依赖它 | 可选 | [Statistics and Machine Learning Toolbox](https://www.mathworks.com/products/statistics.html) |
| FieldTrip | `cfg.artifact.method = "fieldtrip"` 时调用 `ft_artifact_zvalue`；默认仍使用 native backend | 可选 | [FieldTrip](https://www.fieldtriptoolbox.org/) |
| specparam | 提供功率谱参数化定义和报告风格参考；本项目使用 MATLAB 原生 fixed/knee 实现 | 参考资料，不是运行依赖 | [specparam documentation](https://fooof-tools.github.io/fooof/) |

EEGLAB 和 Python `specparam` 当前没有被项目代码调用，因此不会影响仅使用 MATLAB 的运行方式；如未来增加对应 backend，会在本表和变更日志中单独注明。

## 当前状态

当前已完成 SceneRay/通用 CSV 导入、导入预览与确认、非破坏性伪影标记、FieldTrip/native artifact backend、artifact-aware Welch 与 DPSS Multitaper PSD、fixed/knee specparam 参数化、Gaussian 周期峰、频带功率点图、伪影/PSD/模型图、结果导出以及 MATLAB 原生 GUI。GUI 现在可以一次选择多个 CSV；每个文件作为独立 dataset 保存时间、信号、通道、采样率、元数据和 `analysisResults`，运行时逐个完成分析，禁止跨文件拼接计算 PSD。SceneRay 导入器通过寻找每个 `Channel` 元数据行自动识别通道数，并在每个块内部寻找对应的 `Time Index, Voltage, Tag Code` 表头；通用 CSV 可在 GUI 中确认表头、时间列、信号列、方向、采样率和单位。伪影只写入掩码和处理副本，不覆盖原始信号。

项目不调用 Python 封装；FieldTrip/原生 MATLAB 路径保持纯 MATLAB 运行。

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

## 多被试、多 Session 项目模式

项目模式不会替代现有单文件入口，而是在其上增加稳定的身份和结果层：

```matlab
addpath('src');
project = lfp_create_project("my_lfp_project", "Human LFP study");
[project, ~] = lfp_project_add_subject(project, ...
    struct('subject_id', "P01", 'display_name', "Patient 01"));
data = lfp_import_scenray_csv("recording.csv");
[project, ~] = lfp_project_add_session(project, "P01", data, ...
    struct('session_id', "P01_Baseline", 'visit_label', "Baseline", ...
           'medication_state', "off", 'stimulation_state', "on"));
[project, runSummary] = lfp_analyze_project(project, "P01_Baseline");
spec = struct('type', "within_subject", 'session_ids', "P01_Baseline", ...
    'bands', "delta", 'metric', "totalPower");
[project, comparison] = lfp_compare_project(project, spec);
```

`lfp_analyze_project` 按 Session 独立执行现有伪影→PSD→specparam→频带功率流程；数据版本和计算配置指纹一致时复用有效 `AnalysisRun`，否则生成新的结果版本。`lfp_compare_project` 只读取已保存结果并生成可查询长表，不跨患者拼接原始数据。批处理可通过 `lfp_run_batch(taskStructOrMatFile)` 调用，任务结构包含 `projectRoot`、可选 `sessionIds`、`analysisConfig`、`comparisonSpec` 和 `outputFolder`。

当前项目管理 API 已可由脚本调用；现有 GUI 的单次分析工作区保持兼容。Subject/Session 树形管理和比较工作区将在后续增量版本接入，暂不改变现有 GUI 分析入口。

## MATLAB 原生 GUI

在 MATLAB 命令窗口中从仓库根目录运行：

```matlab
addpath('src');
app = launchLfpApp;
```

GUI 工作流为“导入 CSV → 预览并确认格式 → 选择通道和分析时间 → 调整参数 → 勾选模块 → 运行所选分析 → 查看图形/表格 → 保存配置或结果”。结果页包含：

- **原始与伪迹**：全记录 Raw/Clean（伪迹样本以 NaN 断线）、伪迹色块和事件表；
- **PSD**：有效窗口数量、频率分辨率、去伪迹前后 PSD 对照；
- **specparam**：原始谱、完整模型、非周期背景、周期峰、offset/exponent/knee/R²/误差和峰参数表；
- **频段功率**：可编辑频段表、按频段或按通道分面的通道点图，不伪造误差条；
- **PSD**：支持单通道、多通道和 subplot 显示，可切换显示伪迹前 PSD；
- **specparam**：支持数据集/通道选择，并显示各 Gaussian 峰分量及其总和；
- **频段功率**：单数据集按频段/通道分面，多数据集使用 grouped bar 比较；已移除旧的“摘要”页。

“分析时间范围”和“波形显示范围”彼此独立。修改颜色、坐标或显示范围后使用“重新绘图”；修改 PSD、specparam、频段或伪迹参数会标记结果过期，必须重新运行。GUI 中的“伪迹重建”暂时禁用，默认只保存原始数据、mask、事件和 NaN 显示副本。没有有效时间列或时间间隔不规则时，GUI 会阻止需要均匀采样的 PSD 分析，并提示修正导入设置。

导入预览只读取有限行；通用数值 CSV 使用 `readmatrix`，SceneRay 多块文件使用一次流式解析。运行分析时会显示当前阶段、进度和耗时，取消按钮会在原生算法的下一个通道/窗口检查点安全停止。结果页采用延迟绘图，只有打开的标签页会绘制。仅改变显示参数不会重算 PSD；改变上游计算参数时，缓存会沿 Data → Artifact → PSD → specparam → Band power 依赖链失效。

GUI 也支持保存/加载 `cfg` 配置、保存完整 MAT 结果、导出标准 `signal_data.csv`、`psd.csv`、band-power/processing-history CSV 和 PNG 总览图。结果页提供保存图像（PNG/SVG/FIG）和保存当前视图数据（MAT）按钮，保存内容包含数据集、通道、参数快照和时间戳。自动保存选项使用带时间戳的子目录，不覆盖已有结果；完整 MAT 会同时保留导入映射、单位、PSD/specparam 参数与 processingHistory。

v0.6.1 还包含以下 GUI 稳定性修复：CSV 预览、信息栏、伪迹事件表和频段结果表会将字符串/分类值转换为 `uitable` 可显示的字符值，但不会修改原始导入数据或分析结果表；确认导入时会复用已经完成预览的 CSV 内容，SceneRay 数据行解析也采用预分配方式以减少大文件导入耗时。

默认伪迹处理使用逐通道的 native 检测，并启用严格短窗模式（`cfg.artifact.strictMode = true`）。严格模式按窗口内高于 `strictHighpassHz` 的 FFT 能量、导数能量和局部振幅范围检测持续突发，并将候选窗口之间不超过 `strictMergeGapSeconds` 的短间隙一并标记。原始 `data.signal` 始终保留；伪迹只写入 `artifactResult.channelMask`，显示副本 `cleanData.cleanedSignal` 将对应样本标为 `NaN`，不会自动把前后数据拼接或重建。40 Hz 及其 Nyquist 以下谐波默认保留在时域和 PSD 中；specparam不再执行拟合前插值。若明确需要 FieldTrip，可设置 `cfg.artifact.method = "fieldtrip"`，但其时间区间会应用到所有通道。

PSD 默认严格排除包含任意无效/伪迹样本的窗口（`cfg.psd.maxArtifactFraction = 0`），因此被标记的红色区间不会进入默认 PSD、参数化或频段功率分析。若明确需要允许少量污染，可将阈值改为正数（例如 `0.05`）；此时低于阈值的样本只在该 PSD 窗口内线性填补，并记录到 `filledSampleCount`。

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

40 Hz 及其 Nyquist 以下谐波保留在原始时域和 PSD 中；`parameterizePowerSpectrum` 直接使用 PSD 实际频率网格，旧配置中的 `interpolateLineNoise` 只会被忽略并记录迁移提示。新的 PSD 默认方法为 `multitaper`，分析范围默认 `[1 35]` Hz；兼容配置字段 `cfg.fooof.frequencyRange` 默认 `[1 35]`。超出 PSD 范围的频带返回 NaN，而不是虚假功率。Multitaper 使用真正的 DPSS 多窗估计，`NW` 为主输入，`W=NW/T`、总平滑带宽约为 `2W`，默认 `K=floor(2NW)-1`。

绘图函数支持 `cfg.plot.parent` 指定 Figure、uipanel 或 uitab；所有分析函数仍可在无 GUI 的 MATLAB 脚本中独立调用。`computeLfpPsd` 和 `computeBandPower` 也会返回带有 `processingHistory` 的结果结构，便于未来 GUI 或批处理保存审计轨迹。

## 初始化测试

在 MATLAB 中从仓库根目录执行：

```matlab
results = runtests('tests');
assert(all([results.Passed]));
```

当前开发版在 MATLAB R2024a 环境中运行完整自动化测试；最终通过数量见本次交付报告。测试运行时可能出现用户本机 FieldTrip 路径优先级提示；这些提示不属于项目测试失败。

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

见 [CHANGELOG.md](CHANGELOG.md)。长期开发规则见 [AGENTS.md](AGENTS.md)。单文件示例见 `examples/example_lfp_analysis.m`，文件夹批处理示例见 `examples/example_lfp_batch.m`。

## 交互式绘图

绘图函数默认创建可交互的 MATLAB 图窗（`cfg.plot.visible = "on"`），可以直接缩放、平移和读取数据光标。GUI 波形默认显示完整记录（`cfg.plot.maxPlotSeconds = Inf`），仍可改为具体秒数。超过 `cfg.plot.maxDisplayPoints` 的 Raw/Clean 波形只在显示层转换为峰谷包络，短尖峰仍可见；分析和导出始终使用完整数组。`plotArtifactComparison` 会将每个通道按 `Raw`、`Clean/display` 两个面板纵向排列；Clean 面板中的伪影样本显示为 `NaN`，不会伪造连续曲线。批处理示例使用 `KeepFiguresOpen=true` 保留图窗；如只需要保存图片，可改为 `false`。

性能测量、限制和可复现基准见 [docs/performance.md](docs/performance.md)。

保存图片默认使用较大的画布（1600×1100 像素）和 300 DPI，可在 `cfg.plot.figurePosition`、`cfg.plot.exportResolution` 中调整。

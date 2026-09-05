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

当前已完成 SceneRay CSV 导入、非破坏性伪影标记、artifact-aware Welch PSD、40 Hz 谐波拟合前插值、fixed 1/f 参数化、频带功率、结果绘图和导出。导入器通过寻找每个 `Channel` 元数据行自动识别通道数，并在每个块内部寻找对应的 `Time Index, Voltage, Tag Code` 表头；当前约定为 1 kHz、μV。伪影只写入掩码和处理副本，不覆盖原始信号。

`fooof_mat` 是 MATLAB 对 Python FOOOF 的封装，需要 Python 运行环境，因此不纳入本项目的核心依赖。FieldTrip/原生 MATLAB 路径将保持纯 MATLAB 运行。

## 快速分析

```matlab
addpath('src');
data = lfp_import_scenray_csv("my_recording.csv");
data = lfp_preprocess(data, ReplaceArtifacts=false);
data = lfp_compute_psd(data, WindowSeconds=4, OverlapFraction=0.5);
data = lfp_prepare_spectrum_for_fitting(data, LineFrequencyHz=40, ...
    InterpolationHalfWidthHz=2, BufferSamples=3);
data = lfp_fit_spectral_parameters(data, FitRangeHz=[3 150]);
data = lfp_compute_band_power(data);
data = lfp_compute_time_frequency(data, WindowSeconds=1, StepSeconds=0.25);
lfp_plot_results(data);
files = lfp_export_results(data, "results");
```

40 Hz 及其 Nyquist 以下谐波保留在原始时域和 `spectrum.psd` 中；`lfp_prepare_spectrum_for_fitting` 仅生成 `spectrum.psdForFitting`，按照 FOOOF 的 line-noise 插值思路在 log-log 空间插值，供参数化使用。`lfp_compute_time_frequency` 提供基础 MATLAB STFT，并对伪影过多的时间窗返回 NaN。

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

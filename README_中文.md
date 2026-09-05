# 颅内 LFP CSV 的 MATLAB 分析代码

## 文件

- `analyze_lfp_csv.m`：主函数，读取 CSV、预处理、计算 Welch PSD、计算频带功率并导出结果。
- `example_run.m`：通过文件选择窗口运行分析的示例。

需要 MATLAB Signal Processing Toolbox。

## 最快用法

把本文件夹加入 MATLAB Path，然后运行：

```matlab
results = analyze_lfp_csv('your_lfp_file.csv', ...
    'SamplingRate', 1000);
```

如果不传入 `SamplingRate`，代码会尝试根据样本数和 `Collect Time` 推断采样率。不过，正式科研分析应优先使用设备说明或采集设置中记录的真实采样率，并显式传入。

## 默认处理

- 原始波形图：直接绘制 CSV 中的 Voltage，不滤波。
- PSD/频带功率信号：去均值、0.5 Hz 四阶 Butterworth 高通、50 Hz 陷波（带宽 2 Hz），全部使用零相位 `filtfilt`。
- PSD：4 秒 Hann 窗、50% 重叠的 Welch 法。
- 默认频带：Delta 1–4、Theta 4–8、Alpha 8–13、Beta 13–30、LowGamma 30–55、HighGamma 65–100 Hz。
- 相对功率分母：1–100 Hz 的总积分功率。

55–65 Hz 默认留空，用于避开 50 Hz 工频及其邻近区域。频带边界和工频设置应根据实验方案调整，代码中的默认值不是临床判读标准。

## 输出内容

默认在输入 CSV 同目录新建 `<文件名>_results` 文件夹，输出：

- 原始波形 PNG
- PSD PNG
- 绝对/相对频带功率 PNG
- `band_power.csv`：绝对功率、相对功率、dB 功率、频带峰值频率和峰值 PSD
- `psd.csv`：完整 PSD 数值
- `signal_metrics.csv`：样本数、时长、均值、标准差、RMS、极值和峰峰值
- `quality_flags.csv`：潜在削顶/量程边界、缺失值插补等自动质控提示
- `metadata.csv`：设备、序列号、通道、采样率来源等
- `analysis.mat`：全部分析结果，便于后续 GUI 直接调用

功率单位取决于输入 Voltage 的单位。当前版本按 `uV` 解释 Voltage，因此 PSD 为 `uV^2/Hz`，绝对频带功率为 `uV^2`；使用其他单位的数据前需要相应修改单位标注或完成换算。

## 常用参数

```matlab
results = analyze_lfp_csv(filePath, ...
    'SamplingRate', 1000, ...     % 留空则从样本数/Collect Time 推断
    'HighpassHz', 0.5, ...        % 设为 0 可关闭高通
    'LineNoiseHz', 50, ...        % 设为 [] 可关闭陷波；60 Hz 地区改成 60
    'NotchBandwidthHz', 2, ...
    'WindowSeconds', 4, ...
    'OverlapFraction', 0.5, ...
    'PSDMaxHz', 100, ...
    'TotalPowerRangeHz', [1 100], ...
    'PreviewSeconds', 10, ...
    'OutputDirectory', 'D:\my_results', ...
    'SaveOutputs', true, ...
    'CreateFigures', true, ...
    'FigureVisible', 'on');
```

## 通道解释

代码会把 CSV 中的 `Channel,5~6` 解析为触点 5 和 6 的双极采集，并显示为 `5-6`。它不会根据序号自动推断电极的解剖位置；`0–3` 和 `4–7` 分属两根电极的规则可以在后续 GUI 中用于分组与输入校验。

## 后续 GUI 封装建议

GUI 只需负责选择文件、填写参数和显示结果；计算核心继续调用：

```matlab
results = analyze_lfp_csv(selectedFile, ...);
```

可直接读取 `results.Metadata`、`results.Time_s`、`results.RawVoltage_uV`、`results.Frequency_Hz`、`results.PSD_uV2_per_Hz` 和 `results.BandPower`，不用在界面代码中重复分析逻辑。

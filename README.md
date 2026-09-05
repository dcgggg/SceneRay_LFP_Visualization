# SceneRay LFP Visualization

用于读取 SceneRay 颅内 LFP CSV、绘制原始波形、计算 Welch 功率谱密度（PSD），并导出频带功率与质量控制结果的 MATLAB 工具。

## 功能

- 解析设备类型、IPG 序列号、通道、采集时长和增益
- 输出完整原始波形和局部预览
- 对独立分析信号执行去均值、可选高通和工频陷波
- 使用 Welch 方法估计 PSD
- 计算绝对功率、相对功率、dB 功率及频带峰值频率
- 导出 PNG、CSV 和 MAT 结果
- 自动提示潜在削顶/量程边界及缺失值插补
- 以单一分析函数返回结构体，便于后续封装 MATLAB App Designer GUI

## 环境要求

- MATLAB
- Signal Processing Toolbox

## 快速开始

将仓库加入 MATLAB Path，然后运行：

```matlab
results = analyze_lfp_csv('your_lfp_file.csv', ...
    'SamplingRate', 1000);
```

也可以直接运行 `example_run.m`，通过文件选择窗口选择 CSV。

更完整的参数、输出和通道说明参见 [README_中文.md](README_中文.md)。

## 数据安全

原始颅内电生理数据、患者相关文件和生成的 MAT/结果目录不应直接提交到仓库。本仓库的 `.gitignore` 已默认排除：

- `data/raw/`
- `data/private/`
- `*_results/`
- `*.mat`

提交前仍应运行 `git status`，人工确认不存在患者身份信息或其他敏感内容。

## 说明

代码默认参数用于通用研究分析起点，不构成临床判读标准。采样率、工频、滤波参数和频带定义应根据设备配置与实验方案确认。

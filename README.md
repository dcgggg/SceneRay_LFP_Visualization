# SceneRay LFP Visualization

SceneRay 颅内 LFP CSV 的无界面批处理工具：自动标记疑似头动伪影，去除 40 Hz 及其倍频干扰，生成原始波形、PSD、FOOOF 周期/非周期分解和频带功率结果。

> 本版本没有 GUI。原始 CSV 永远不会被修改或删除；程序对伪影片段采用“标记并从 PSD 窗口中排除”，不会用插值伪造神经信号。

## 处理流程

1. 读取 SceneRay 元数据及 Voltage；`Channel,5~6` 显示为双极通道 `5-6`。
2. 用 SciPy 零相位陷波依次处理 40、80、120 Hz……直到 Nyquist 频率以下。
3. 联合 YASA 分窗标准差检测与稳健特征（峰峰值、差分 RMS、瞬时跳变、量程边界）标记疑似头动/电极运动伪影。
4. 只用通过质控的 4 秒窗口计算 PSD，并取各窗口 periodogram 的中位数。
5. 将陷波处的谱点仅在 FOOOF 输入谱中按对数功率插值，避免陷波凹口被误拟合；FOOOF 接收线性 PSD。
6. 导出周期峰、非周期参数以及各频带的模型总功率、非周期功率和周期功率。

40/80 Hz 在本项目中按设备相关工频谐波处理，不按刺激伪影处理。项目没有使用 PyPARRM。

## 最简单的用法：Windows 免安装包

在 GitHub 仓库的 **Releases** 下载 `SceneRay-LFP-Windows-x64.zip`，解压后在 PowerShell 中运行：

```powershell
.\SceneRay-LFP.exe "D:\data\your_lfp.csv"
```

程序会在 CSV 同目录创建 `<文件名>_results`。该 ZIP 已包含 Python 和依赖，目标 Windows x64 电脑不需要另装 Python、MATLAB 或工具包。PyInstaller 的构建产物与操作系统有关，因此 Windows 包不能直接用于 macOS/Linux。

如果采样率无法从 `Collect Time` 可靠推断，请显式传入：

```powershell
.\SceneRay-LFP.exe "D:\data\your_lfp.csv" --fs 1000
```

## 从源码运行

需要 Python 3.10–3.12：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e .
.\.venv\Scripts\sceneray-lfp.exe "D:\data\your_lfp.csv" --fs 1000
```

常用选项：

```text
--output DIR                 指定结果目录
--line-frequency 40         干扰基频，默认 40 Hz
--notch-width 2             每个谐波陷波带宽，默认 2 Hz
--artifact-window 2         伪影检测分窗秒数
--artifact-threshold 3      YASA 标准差 z 阈值
--robust-threshold 6        稳健特征阈值
--artifact-padding 1        伪影两侧扩展秒数
--psd-window 4              PSD 窗长
--fooof-min-hz 1            FOOOF 拟合下限
--fooof-max-hz 100          FOOOF 拟合上限
--export-cleaned-signal     额外导出信号；伪影样本留空/NaN
--no-artifact-rejection     诊断选项：PSD 包含全部窗口
```

## 输出

- `*_waveforms.png`：原始波形、伪影区域和 40 Hz 谐波陷波后波形
- `*_psd_fooof.png`：干净窗口 PSD、FOOOF 完整模型和非周期成分
- `*_band_components.png`：各频带周期/非周期模型功率
- `*_artifact_epochs.csv`：每个检测窗的各项分数与判定
- `*_psd_windows.csv`：PSD 窗口接受/拒绝记录
- `*_harmonic_attenuation.csv`：40 Hz 各次谐波处理前后 PSD 与衰减 dB
- `*_periodic_peaks.csv`：中心频率、超出非周期背景的峰功率和带宽
- `*_band_components.csv`：频带总功率、非周期功率和周期功率
- `*_psd.csv`：PSD 与 FOOOF 输入谱
- `*_summary.json`：元数据、参数、伪影比例和 FOOOF 拟合质量

## 使用的工具包与引用

| 工具包 | 固定版本 | 用途 |
| --- | ---: | --- |
| [FOOOF](https://fooof-tools.github.io/fooof/) | 1.1.1 | 周期峰与非周期成分参数化 |
| [YASA](https://yasa-sleep.org/generated/yasa.art_detect.html) | 0.7.0 | 自动检测主要运动伪影窗口 |
| [SciPy](https://scipy.org/) | 1.13.1 | 陷波、高通、PSD 和稳健统计 |
| [NumPy](https://numpy.org/) | 1.26.4 | 数值计算 |
| [Matplotlib](https://matplotlib.org/) | 3.9.4 | 结果图 |
| [MNE-Python](https://mne.tools/) | 1.9.0 | YASA 运行依赖 |
| [pandas](https://pandas.pydata.org/) | 2.2.3 | YASA 运行依赖 |
| [PyInstaller](https://pyinstaller.org/) | 6.22.2 | Windows 免安装打包 |

论文引用、许可证及“直接调用/间接依赖”的区分见 [THIRD_PARTY.md](THIRD_PARTY.md)。FOOOF 建议引用 Donoghue et al., *Nature Neuroscience* (2020), DOI `10.1038/s41593-020-00744-x`；YASA 建议引用 Vallat & Walker, *eLife* (2021), DOI `10.7554/eLife.70092`。

## 科研与临床限制

单通道双极 LFP 在没有加速度计、视频或人工事件标注时，无法证明每个异常片段一定由头动造成，也无法可靠重建被污染的真实神经信号。YASA 的该检测器原本面向 EEG 的主要身体运动伪影，本项目将它用于 LFP 属于工程适配，正式研究前必须用人工复核数据验证阈值、灵敏度和特异度。

本工具仅用于研究质控和探索性分析，不构成临床判读或医疗器械软件。

## 数据安全

`.gitignore` 默认排除 `data/raw/`、`data/private/`、`*_results/` 和 `*.mat`。提交前仍应运行 `git status`，确认患者数据或身份信息没有进入 Git。

## 旧 MATLAB 版本

仓库仍保留 `analyze_lfp_csv.m` 和 `example_run.m` 作为历史参考；当前维护的主流程是上述 Python/FOOOF 版本。

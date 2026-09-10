# Architecture

## Layers

1. **Data import** — parses SceneRay metadata and signal columns without changing source files.
2. **Data model** — stores `signal`, `fs`, `time`, `channelLabels`, `units`, `metadata`, `artifacts`, and `processingHistory`.
3. **Preprocessing and artifacts** — robust amplitude, derivative/step, and saturation markers with optional NaN-derived signal.
4. **Spectral analysis** — artifact-aware manual Welch or DPSS Multitaper PSD and sliding STFT/DPSS time-frequency estimates; no line-frequency notch.
5. **Spectral parameterization** — native MATLAB specparam (original FOOOF naming retained for compatibility) with fixed or estimated-knee aperiodic models; no fitting-time interpolation; periodic peaks remain separate from the background.
6. **Band analysis** — total, relative, aperiodic, and periodic-above-aperiodic power.
7. **Visualization** — figures consume result structures and do not run hidden analysis.
8. **Export** — tables, MAT files, figures, and a processing log with parameters and software information.
9. **GUI** — the MATLAB-native `LfpApp`/`launchLfpApp` layer. It owns import confirmation, parameter controls, run snapshots, cache/expiry status, result tabs and save actions, while calling the same public analysis functions as scripts.
10. **Dataset manager** — the GUI keeps each CSV as an independent `Datasets(k)` record with canonical arrays and an `analysisResults` struct. Checkbox selection drives sequential per-dataset runs; files are never concatenated for PSD or parameterization.

## Dependency policy

The base path must not require Python, R, Java, Node.js, network access, or automatic downloads. Optional MATLAB toolboxes are detected with capability checks and never silently change scientific definitions.

## Data flow

```text
CSV -> inspection/import confirmation -> validated data model -> derived preprocessing
    -> artifact annotations -> PSD/time-frequency -> parameterization
    -> bands/figures/tables/log -> export
```

`analyzeLfpFolder` 在文件层面复用同一条流水线：扫描 `*.csv`，逐文件导入并识别 `Channel` 区块，随后一次性完成伪影、PSD、参数化和频段功率。结果按文件保存，通道始终以 samples × channels 矩阵和 `channelLabels` 传播，避免重复计算或跨文件混合通道。

The GUI takes a run snapshot containing the selected channels, analysis range, module switches and a copied configuration. A successful run replaces the previous result atomically; a failed or cancelled run leaves the last successful result and raw data intact. Plot-only edits do not trigger analysis, while data/artifact/PSD/model/band edits invalidate their downstream caches.

The raw signal remains in the data model and is never overwritten by a derived signal.

The GUI `AppState` records selected dataset indices, selected channels, the active analysis stage, current result handles and plot settings. Dataset/channel selectors in the Raw, PSD, time-frequency and specparam tabs update the active record and redraw only the corresponding result views where possible.

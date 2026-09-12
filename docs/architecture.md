# Architecture

## Layers

1. **Data import** — parses SceneRay metadata and signal columns without changing source files.
2. **Data model** — stores `signal`, `fs`, `time`, `channelLabels`, `units`, `metadata`, `artifacts`, and `processingHistory`; Project Sessions additionally store stable per-channel metadata and independent raw-cache references.
3. **Preprocessing and artifacts** — robust amplitude, derivative/step, and saturation markers with optional NaN-derived signal.
4. **Spectral analysis** — artifact-aware manual Welch or DPSS Multitaper PSD; no line-frequency notch.
5. **Spectral parameterization** — native MATLAB specparam with fixed or estimated-knee aperiodic models; no fitting-time interpolation; periodic peaks remain separate from the background.
6. **Band analysis** — total, relative, aperiodic, and periodic-above-aperiodic power.
7. **Visualization** — figures consume result structures and do not run hidden analysis.
8. **Export** — tables, MAT files, figures, and a processing log with parameters and software information.
9. **GUI** — `launch_gui` creates one `LfpProjectApp` controller with an empty welcome state, a stable-ID navigation tree and three task-specific pages. It calls public import/project/analysis/comparison functions; rendering reads cached results and never launches hidden analysis. `launchLfpApp` remains a legacy single-file compatibility entry.
10. **Legacy dataset manager** — `launchLfpApp` retains the previous independent `Datasets(k)` workflow for compatibility. It is not the primary project GUI and never shares live state with `LfpProjectApp`.
11. **Legacy task manager** — `LfpAnalysisTaskManager` remains available to the compatibility GUI. The project GUI calls the project analysis dispatcher and exposes cooperative cancellation at its progress checkpoints.
12. **Project platform** — `lfp_create_project_in_parent` creates a self-contained project folder after validating the parent and name. New GUI-created projects use `storage_mode="subject_session"`: `subjects/<display-name>__<stable-id>/<visit>__<stable-id>/` contains `subject.mat`, `session.mat`, `data/`, `configs/`, `results/` and `exports/`; project-wide `comparisons/`, `exports/` and `logs/` remain at the project root. Direct callers of `lfp_create_project` retain the legacy root-level `data/` and `results/` layout, so old projects remain readable.
13. **AnalysisRun/cache** — `lfp_analyze_project` runs Sessions independently, creates versioned run metadata and derived result files under `results/`, and reuses a run only when both the content-sensitive data version and computation-only configuration fingerprint match. Sessions with appended or heterogeneous files use `lfp_analyze_independent_channels`; each enabled Channel is analyzed and cached separately under `results/channels/`.
14. **Comparison/query** — `lfp_compare_project` reads saved band-power results into an explicit long table and records comparison type, Session–Channel IDs, visit labels, run IDs and configuration compatibility. It never concatenates raw signals or treats epochs/channels as independent subjects. A comparison mapping may contain multiple channels per Session; `plotProjectComparison` renders each selected entry without inferential statistics. `lfp_build_psd_comparison` and `plotGroupedPsdComparison` add subject-weighted group curves (multiple entries are averaged within Subject first); `plotGroupedBandPower` uses the same subject-level weighting for bars, points and SD. Group labels belong to the comparison mapping and do not modify Subject metadata.
15. **Batch/migration** — `lfp_run_batch` provides a GUI-free task entry point with a project lock; `lfp_preview_legacy_dataset` and `lfp_migrate_legacy_dataset` require explicit Subject/Session identity and preserve the source file.

## Dependency policy

The base path must not require Python, R, Java, Node.js, network access, or automatic downloads. Optional MATLAB toolboxes are detected with capability checks and never silently change scientific definitions.

## Data flow

```text
CSV -> inspection/import confirmation -> validated data model
    -> Project/Subject/Session/Channel reference and per-channel cache (optional)
    -> derived preprocessing -> artifact annotations -> PSD -> parameterization
    -> bands/figures/tables/log -> AnalysisRun/export -> Comparison query
```

`analyzeLfpFolder` 在文件层面复用同一条流水线：扫描 `*.csv`，逐文件导入并识别 `Channel` 区块，随后一次性完成伪影、PSD、参数化和频段功率。结果按文件保存，通道始终以 samples × channels 矩阵和 `channelLabels` 传播，避免重复计算或跨文件混合通道。

The GUI takes a run snapshot containing the selected channels, analysis range, module switches and a copied configuration. A successful run replaces the previous result atomically; a failed or cancelled run leaves the last successful result and raw data intact. Plot-only edits do not trigger analysis, while data/artifact/PSD/model/band edits invalidate their downstream caches. Every run also stores a requested-product set, channel revisions and a scoped computation fingerprint; reuse/latest/comparison all call the same identity validator. Project writes use the common `.lfp_write.lock` and monotonic `project_revision`; import/append/rename operations leave a staging manifest for diagnosing interrupted multi-file updates.

The raw signal remains in the data model and is never overwritten by a derived signal. A
Session may contain channels with different sample counts or time axes; the display-only
compatibility matrix may contain NaN padding, but analysis always reads the individual
channel cache and never treats padding as samples.

Project persistence is intentionally separate from transient GUI handles. `project.mat` contains metadata, stable IDs, configuration, saved comparison plans and result references. In nested projects, each Session stores canonical raw arrays in its own `data/session_data.mat` and derived results in its own `results/<run_id>.mat`; legacy projects keep `data/<session_id>.mat` and root `results/<run_id>.mat`. `comparisons/<comparison_id>.mat` contains reproducible comparison tables and group definitions. Relative references allow the complete project folder to be moved and reopened without importing or recomputing successful runs; source CSVs are copied into Session/data with a collision-safe name while the original source path is retained as provenance.

`LfpProjectApp` keeps the current project, subject ID, Session ID, channel index, comparison selection, cached run and dirty/busy state in one controller. Tree and table rows carry stable IDs, so filtering and ordering do not change object identity. Result tabs consume the currently loaded Session run; switching to a Session without results clears the previous plots. Busy analysis blocks Session navigation and result-tab refresh callbacks; close requests become cooperative cancellation and are finalized only after the active task cleanup checkpoint.

The compatibility GUI keeps its own `AppState`. Both GUIs may use `lfp_downsample_envelope` for display only; this cannot alter `data.signal`, PSD input, artifact masks, or exported canonical arrays.

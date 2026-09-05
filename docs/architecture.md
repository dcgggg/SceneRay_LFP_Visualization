# Architecture

## Layers

1. **Data import** — parses SceneRay metadata and signal columns without changing source files.
2. **Data model** — stores `signal`, `fs`, `time`, `channelLabels`, `units`, `metadata`, `artifacts`, and `processingHistory`.
3. **Preprocessing and artifacts** — explicit filter configuration, line-interference harmonics, suspected-motion markers, and optional derived signals.
4. **Spectral analysis** — PSD and time-frequency estimates with toolbox capability detection and base-MATLAB fallbacks.
5. **Spectral parameterization** — fixed aperiodic fit first; knee model as a separately reported option; periodic peaks remain separate from the background.
6. **Band analysis** — total, relative, aperiodic, and periodic-above-aperiodic power.
7. **Visualization** — figures consume result structures and do not run hidden analysis.
8. **Export** — tables, MAT files, figures, and a processing log with parameters and software information.
9. **GUI** — a later MATLAB-native layer that calls the same public analysis functions.

## Dependency policy

The base path must not require Python, R, Java, Node.js, network access, or automatic downloads. Optional MATLAB toolboxes are detected with capability checks and never silently change scientific definitions.

## Data flow

```text
CSV -> importer -> validated data model -> derived preprocessing
    -> artifact annotations -> PSD/time-frequency -> parameterization
    -> bands/figures/tables/log -> export
```

The raw signal remains in the data model and is never overwritten by a derived signal.

# Architecture

## Layers

1. **Data import** — parses SceneRay metadata and signal columns without changing source files.
2. **Data model** — stores `signal`, `fs`, `time`, `channelLabels`, `units`, `metadata`, `artifacts`, and `processingHistory`.
3. **Preprocessing and artifacts** — robust amplitude, derivative/step, and saturation markers with optional NaN-derived signal.
4. **Spectral analysis** — artifact-aware manual Welch PSD and STFT time-frequency estimates; no line-frequency notch.
5. **Spectral parameterization** — fitting-only log-log interpolation of 40-Hz harmonics followed by fixed aperiodic fit; knee model remains a separately reported future option; periodic peaks remain separate from the background.
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

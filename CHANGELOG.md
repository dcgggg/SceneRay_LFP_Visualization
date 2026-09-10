# Changelog

## Unreleased

- Incremental local development after v0.6.1; no remote release or push performed in this task.
- Added configurable DPSS Multitaper PSD and sliding STFT/DPSS time-frequency outputs.
- Added native fixed/knee specparam parameterization and removed fitting-time interpolation.
- Updated GUI labels to specparam（原FOOOF）, added method/multitaper/time-frequency controls, replaced band heatmap with dot facets, and removed the legacy 摘要 tab.
- Added import metadata for time source/unit conversion and a confirmation dialog for sampling-rate disagreement.

## [0.6.1] - 2026-09-07

- Fixed native GUI import failure caused by assigning string scalars inside a `uitextarea.Value` cell array.
- Added `lfp_table_to_uitable_data` so artifact, FOOOF and band-power result tables can display typed string/categorical values without changing analysis results.
- Reused the CSV inspection result during GUI confirmation and preallocated SceneRay sample parsing to reduce large-file import overhead.
- Added regression coverage for typed table display conversion and preloaded SceneRay import.

- Added a MATLAB-native `launchLfpApp`/`LfpApp` GUI for CSV import confirmation, channel/time selection, configurable artifact/PSD/FOOOF/band/plot parameters, run snapshots, cache-expiry status, result tabs, redraw and save workflows.
- Added `lfp_inspect_csv` and `lfp_import_csv_configured` for previewed generic CSV import while preserving the existing SceneRay block-aware importer.
- Added GUI/import smoke tests and documented generic CSV orientation and uniform-sampling validation.

## [0.6.0] - 2026-09-06

- Added strict native burst marking based on short-window FFT high-frequency energy, derivative energy and local range, with configurable gap joining for sustained interference trains. The default PSD policy now rejects any window containing a marked sample.
- Revised artifact defaults for LFP: native channel-specific detection is now the default, 40-Hz line noise is retained unless explicitly enabled for time-domain rejection, and PSD windows use a configurable artifact-fraction tolerance. Full-record waveform display is now the default.
- Enlarged interactive/export figures, added shared plot sizing/resolution settings, and changed artifact comparison to a one-column Raw/Clean panel pair for every channel. Batch analysis can keep MATLAB figure windows open with `KeepFiguresOpen=true`.
- Added unified configuration, FieldTrip/native artifact API, strict artifact-aware PSD metadata, fixed/no-knee Gaussian spectral parameterization, cfg-compatible entry points, and before/after/model summary plots.
- Parameterization now performs configurable 40-Hz harmonic interpolation on a fitting-only PSD copy and preserves raw/fitting spectra separately. Artifact comparison plots now include before/after amplitude distributions, channel fractions, event counts, and durations; plotting and cfg-compatible entry points expose parent/history handles for future GUI integration.

- Added non-destructive robust artifact marking, manual Welch PSD, FOOOF-compatible fitting-only line-noise interpolation, fixed aperiodic/periodic parameterization, configurable band-power integration, artifact-aware manual STFT, overview plotting, and MAT/CSV/log/PNG export.

- Initialized the MATLAB-only project structure and development rules.
- Added a MATLAB entry-point smoke test.
- Added the SceneRay CSV import layer with fixed 1000 Hz / uV defaults, metadata, contact parsing, Tag Code retention, and processing-history initialization.
- GUI, PAC, functional connectivity, and automatic signal reconstruction remain out of scope for this iteration.

# Changelog

## Unreleased

- Added appendable Session channel imports with stable source-file/column identity, independent atomic raw caches, explicit cache corruption errors, channel enable/disable/remove operations, and per-channel analysis/result isolation for heterogeneous lengths or time axes.
- Added `lfp_project_get_channel_data`, `lfp_project_append_data`, `lfp_project_remove_channels` and channel-level regression tests while preserving legacy synchronized Session MAT files and result formats.
- Added relocatable nested project storage with automatic parent/name folder creation, collision-safe source CSV copies, and stable-ID Subject/Session folder references.
- Added expanded comparison selection metadata, custom group labels, subject-weighted grouped PSD curves and grouped band-power bars with explicit SD definitions.
- Added an editable per-project band-definition table with validation and compatibility with legacy field-style configurations.
- Fixed GUI project analysis band-power failure when the new struct-array band representation is passed through the compatibility entry point.

- Rebuilt the MATLAB-native GUI as a zero-input project workspace launched by `launch_gui`.
- Added a welcome state, persistent project toolbar, stable-ID Subject/Session tree, focused data/analysis/comparison pages and a compact status bar.
- Added metadata-first Session creation, CSV preview confirmation, editable channel display metadata and non-destructive index removal.
- Added cached raw/PSD/specparam/band result views, explicit result-version status and independent Session/channel comparison selection.
- Added saved comparison plans, explicit per-Session channel mapping, project reopen restoration and seven MATLAB-rendered GUI acceptance screenshots.
- Added comparison filtering by subject, visit and analysis status, per-item removal, and a compact-width navigation switch so export actions remain reachable.
- Corrected comparison row selection and computation-config fingerprints so labels, values and cached result versions stay aligned.
- Added a persistent `Project -> Subject -> Session -> Channel` data model with stable IDs and per-Session raw-data references.
- Added versioned `AnalysisRun` persistence, content-sensitive data/config fingerprints, independent Session analysis and cache reuse.
- Added explicit comparison long tables, legacy migration preview/entry points and a GUI-free batch runner with a project write lock.
- Added MATLAB tests covering multi-Session storage, multi-channel identity, analysis reuse and visit-based comparison.
- Added synchronized Session-segment validation, CSV-to-Session import bridge, comparison plotting and long-table export.

## [0.9.0] - 2026-09-10

- Removed the time-frequency analysis module from the GUI, PSD execution chain, export path and dedicated tests; legacy time-frequency fields are ignored when loading older sessions.
- Decoupled ordinary band-power analysis from specparam so PSD-derived total and relative power can run when specparam is unavailable or fails.
- Added explicit band computability/status fields and stopped silently clipping bands outside the available PSD range.
- Preserved independent per-dataset execution and report partial failures without presenting a failed specparam stage as successful.
- Standardized user-facing documentation and GUI labels on specparam, while retaining legacy configuration field names for compatibility.
- Replaced full-file `readcell` inspection with a bounded streaming preview, added a numeric `readmatrix` path for rectangular CSV files, and added a streaming SceneRay block parser with import progress/cancellation hooks and memory metadata.
- Upgraded the native GUI to a multi-dataset session manager: multiple CSV files remain independent, each dataset keeps raw arrays and analysis results, and selected datasets can be run sequentially.
- Added unified dataset table controls, per-result dataset/channel selectors, PSD single/multi/subplot views, grouped multi-dataset band bars, Gaussian component display, and per-tab PNG/SVG/FIG/MAT export actions.
- Enlarged/reflowed GUI controls, added shared UI sizing parameters, shortened long labels, and preserved real CSV time origins in range controls.
- Added configurable DPSS Multitaper PSD.
- Added native fixed/knee specparam parameterization and removed fitting-time interpolation.
- Updated GUI labels to specparam, replaced band heatmap with dot facets, and removed the legacy 摘要 tab.
- Added import metadata for time source/unit conversion and a confirmation dialog for sampling-rate disagreement.
- Added staged progress, cooperative cancellation, per-stage timing, dependency-aware cache reuse, lazy result-tab rendering, and actionable stage-aware errors.
- Added a display-only min/max envelope for long raw/clean traces and changed the default waveform view to the full record; full arrays remain unchanged for analysis and export.
- Reflowed fixed-width control grids, fixed overlapping band controls, and centralized GUI sizing/font choices.
- Added reproducible small/medium/opt-in-large performance benchmarks and runtime engineering regression tests.

## [0.6.1] - 2026-09-07

- Fixed native GUI import failure caused by assigning string scalars inside a `uitextarea.Value` cell array.
- Added `lfp_table_to_uitable_data` so artifact, specparam and band-power result tables can display typed string/categorical values without changing analysis results.
- Reused the CSV inspection result during GUI confirmation and preallocated SceneRay sample parsing to reduce large-file import overhead.
- Added regression coverage for typed table display conversion and preloaded SceneRay import.

- Added a MATLAB-native `launchLfpApp`/`LfpApp` GUI for CSV import confirmation, channel/time selection, configurable artifact/PSD/specparam/band/plot parameters, run snapshots, cache-expiry status, result tabs, redraw and save workflows.
- Added `lfp_inspect_csv` and `lfp_import_csv_configured` for previewed generic CSV import while preserving the existing SceneRay block-aware importer.
- Added GUI/import smoke tests and documented generic CSV orientation and uniform-sampling validation.

## [0.6.0] - 2026-09-06

- Added strict native burst marking based on short-window FFT high-frequency energy, derivative energy and local range, with configurable gap joining for sustained interference trains. The default PSD policy now rejects any window containing a marked sample.
- Revised artifact defaults for LFP: native channel-specific detection is now the default, 40-Hz line noise is retained unless explicitly enabled for time-domain rejection, and PSD windows use a configurable artifact-fraction tolerance. Full-record waveform display is now the default.
- Enlarged interactive/export figures, added shared plot sizing/resolution settings, and changed artifact comparison to a one-column Raw/Clean panel pair for every channel. Batch analysis can keep MATLAB figure windows open with `KeepFiguresOpen=true`.
- Added unified configuration, FieldTrip/native artifact API, strict artifact-aware PSD metadata, fixed/no-knee Gaussian spectral parameterization, cfg-compatible entry points, and before/after/model summary plots.
- Parameterization now performs configurable 40-Hz harmonic interpolation on a fitting-only PSD copy and preserves raw/fitting spectra separately. Artifact comparison plots now include before/after amplitude distributions, channel fractions, event counts, and durations; plotting and cfg-compatible entry points expose parent/history handles for future GUI integration.

- Added non-destructive robust artifact marking, manual Welch PSD, specparam-compatible fitting-only line-noise interpolation, fixed aperiodic/periodic parameterization, configurable band-power integration, overview plotting, and MAT/CSV/log/PNG export.

- Initialized the MATLAB-only project structure and development rules.
- Added a MATLAB entry-point smoke test.
- Added the SceneRay CSV import layer with fixed 1000 Hz / uV defaults, metadata, contact parsing, Tag Code retention, and processing-history initialization.
- GUI, PAC, functional connectivity, and automatic signal reconstruction remain out of scope for this iteration.

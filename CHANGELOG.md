# Changelog

## Unreleased

- Added strict native burst marking based on short-window FFT high-frequency energy, derivative energy and local range, with configurable gap joining for sustained interference trains.
- Revised artifact defaults for LFP: native channel-specific detection is now the default, 40-Hz line noise is retained unless explicitly enabled for time-domain rejection, and PSD windows use a configurable artifact-fraction tolerance. Full-record waveform display is now the default.
- Enlarged interactive/export figures, added shared plot sizing/resolution settings, and changed artifact comparison to a one-column Raw/Clean panel pair for every channel. Batch analysis can keep MATLAB figure windows open with `KeepFiguresOpen=true`.
- Added unified configuration, FieldTrip/native artifact API, strict artifact-aware PSD metadata, fixed/no-knee Gaussian spectral parameterization, cfg-compatible entry points, and before/after/model summary plots.
- Parameterization now performs configurable 40-Hz harmonic interpolation on a fitting-only PSD copy and preserves raw/fitting spectra separately. Artifact comparison plots now include before/after amplitude distributions, channel fractions, event counts, and durations; plotting and cfg-compatible entry points expose parent/history handles for future GUI integration.

- Added non-destructive robust artifact marking, manual Welch PSD, FOOOF-compatible fitting-only line-noise interpolation, fixed aperiodic/periodic parameterization, configurable band-power integration, artifact-aware manual STFT, overview plotting, and MAT/CSV/log/PNG export.

- Initialized the MATLAB-only project structure and development rules.
- Added a MATLAB entry-point smoke test.
- Added the SceneRay CSV import layer with fixed 1000 Hz / uV defaults, metadata, contact parsing, Tag Code retention, and processing-history initialization.
- GUI, PAC, functional connectivity, and automatic signal reconstruction remain out of scope for this iteration.

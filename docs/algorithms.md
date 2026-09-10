# Algorithms

This document records the implemented MATLAB definitions and their limits.

## Interference

The current project assumption is 40 Hz device/line interference and integer harmonics below Nyquist. Line noise is retained in the time-domain signal and PSD and is not treated as stimulation artifact. The current specparam path performs no fitting-time interpolation or frequency-grid densification; legacy interpolation fields are ignored with a migration warning.

## Artifact policy

Artifacts are represented as sample masks, channel masks and an events table. The default native backend detects high amplitude, jump/spike, flatline, saturation, high-frequency burst, bad channels and manual intervals independently per channel. With `cfg.artifact.strictMode=true`, short-window FFT high-frequency energy, derivative energy and local range are also evaluated; candidate windows are joined across gaps up to `strictMergeGapSeconds` and marked as complete intervals. Strong 40-Hz projection can be enabled explicitly with `cfg.artifact.lineNoiseDetection=true`, but is disabled by default so line noise remains available for fitting-only interpolation. FieldTrip is an explicit optional backend using `ft_artifact_zvalue`; its returned time intervals are applied to all channels. Detection is not proof of head motion or any physiological source. Default handling is mask-based exclusion; reconstruction is not silently performed.

## PSD and bands

PSD units are signal-unit-squared per Hz. Welch uses one-sided FFT windows. Multitaper uses K true DPSS tapers per continuous valid window, equal taper weighting, and records `NW`, `K`, `W=NW/T`, total smoothing bandwidth, window count and per-frequency valid-window counts. `cfg.psd.maxArtifactFraction` controls tolerated invalid/artifact samples; default 0 rejects contaminated windows. Input power remains linear; log10 conversion occurs only inside model fitting or display. Band power is the integral of a selected PSD interval. Total (`totalPower`), log total (`logTotalPower`), relative, aperiodic and periodic-above-aperiodic quantities remain separate. Bands outside the PSD range return NaN.

## Aperiodic and periodic components

The native model supports fixed/no-knee `L(F)=offset-exponent*log10(F)` and knee `L(F)=offset-log10(knee+F^exponent)`. Knee is estimated in positive log10(knee) coordinates with a base-MATLAB optimizer; it is not a user-supplied Hz breakpoint. Both modes perform robust initial fitting, flattening, residual candidate detection, bounded Gaussian peak fitting, peak subtraction in log space, and final aperiodic refitting. Each peak reports CF (Hz), PW (log10 power above background), and BW=`2*sigma` (Hz). Python FOOOF/specparam is never called. `modelResult.inputPower` and `modelResult.fittingPower` are the same un-interpolated PSD grid.

`lfp_interpolate_line_noise` remains as a standalone legacy/reference utility for compatibility with older sessions, but it is not called by the current parameterization path. New analyses therefore retain 40-Hz harmonics in both `inputPower` and `fittingPower` and report their influence rather than silently modifying the fit grid.

Implemented functions:

- `lfp_preprocess`: robust amplitude, derivative/step and saturation marking; optional NaN processing copy.
- `lfp_compute_psd`: manual Welch or DPSS Multitaper PSD with artifact-heavy window rejection.
- `lfp_dpss`, `lfp_compute_multitaper_psd`: base-MATLAB DPSS generation and multitaper implementation.
- `lfp_fit_spectral_parameters`: legacy fixed offset/exponent path; fitting-only interpolation fields are ignored.
- `lfp_compute_band_power`: total, relative, aperiodic and periodic-above-aperiodic integrations.
- `lfp_compute_time_frequency`: artifact-aware sliding STFT/Welch or sliding DPSS time-frequency power.
- `lfp_plot_results` and `lfp_export_results`: overview figures, MAT/CSV/log/PNG outputs.
- `detectAndHandleArtifacts`, `computeLfpPsd`, `parameterizePowerSpectrum`, `computeBandPower`: stable cfg-based entry points for future GUI use.
- `plotArtifactComparison`, `plotPsdComparison`, `plotBandPowerComparison`, `plotSpectralModel`: independent before/after, dot/facet and model-result plots. The GUI no longer creates the legacy summary tab.

Plot functions return figure/layout/axes handles and accept an optional `plotCfg.parent` Figure, panel, or tab. Artifact comparison places Raw and Clean/display (NaN-marked) panels vertically for each channel, using the same y-limits for each before/after pair. It also includes raw versus finite masked amplitude distributions, per-channel artifact fractions, and event-count/total-duration summaries by artifact type. Figures default to a 1600×1100-pixel canvas and 300-DPI export; adjust `cfg.plot.figurePosition`, `cfg.plot.tileSpacing`, and `cfg.plot.exportResolution` as needed. Batch plotting can retain interactive windows with `KeepFiguresOpen=true`.

## Testing

Synthetic signals will use fixed random seeds and known sinusoids, 1/f backgrounds, artifacts, NaN/Inf values, short recordings, empty channels, and multiple sampling rates. Tolerances will be recorded with each test rather than hidden in implementation defaults.

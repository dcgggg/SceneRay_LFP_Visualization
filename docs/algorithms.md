# Algorithms

This document records the implemented MATLAB definitions and their limits.

## Interference

The current project assumption is 40 Hz device/line interference and integer harmonics below Nyquist. The fundamental frequency and notch width will be explicit parameters, not hidden defaults. This is not treated as stimulation artifact.

## Artifact policy

Artifacts are represented as sample masks, channel masks and an events table. The default FieldTrip backend uses `ft_artifact_zvalue` when available; native checks complement it for high amplitude, jump/spike, flatline, saturation, high-frequency burst, strong 40-Hz projection, bad channels and manual intervals. The native backend is available without FieldTrip. Detection is not proof of head motion or any physiological source. Default handling is mask-based exclusion; reconstruction is not silently performed.

## PSD and bands

PSD units are signal-unit-squared per Hz. PSD is computed from clean windows only, with per-window PSD and per-frequency valid-window counts saved. Input power is linear; log10 conversion occurs only inside model fitting or display. Band power is the integral of a selected PSD interval. Total (`totalPower`), log total (`logTotalPower`), relative, aperiodic and periodic-above-aperiodic quantities remain separate. Bands outside the PSD range return NaN.

## Aperiodic and periodic components

The native model is fixed/no-knee: `L(F)=offset-exponent*log10(F)`, so exponent is the negative log-log slope and no knee is fitted. The implementation performs robust initial fitting, flattening, residual candidate detection, bounded Gaussian peak fitting, peak subtraction in log space, and final aperiodic refitting. Each peak reports CF (Hz), PW (log10 power above background), and BW=`2*sigma` (Hz). Python FOOOF/specparam is never called. 40-Hz harmonics remain in the original PSD and are interpolated only in a fitting copy before the robust fit; `modelResult.inputPower` is raw and `modelResult.fittingPower` is the interpolated copy. Set `cfg.fooof.interpolateLineNoise=false` to disable this step.

`lfp_interpolate_line_noise` reproduces the documented `fooof.utils.interpolate_spectrum` behavior: each closed range uses averaged buffer samples on both sides and linear interpolation in log-log spacing. With the defaults, ranges are 38–42, 78–82, and so on up to Nyquist. The original `spectrum.psd` is never replaced.

Implemented functions:

- `lfp_preprocess`: robust amplitude, derivative/step and saturation marking; optional NaN processing copy.
- `lfp_compute_psd`: manual Welch PSD with artifact-heavy window rejection.
- `lfp_prepare_spectrum_for_fitting`: fitting-only line-noise interpolation with processing history.
- `lfp_fit_spectral_parameters`: fixed offset/exponent and residual peak detection.
- `lfp_compute_band_power`: total, relative, aperiodic and periodic-above-aperiodic integrations.
- `lfp_compute_time_frequency`: artifact-aware manual STFT.
- `lfp_plot_results` and `lfp_export_results`: overview figures, MAT/CSV/log/PNG outputs.
- `detectAndHandleArtifacts`, `computeLfpPsd`, `parameterizePowerSpectrum`, `computeBandPower`: stable cfg-based entry points for future GUI use.
- `plotArtifactComparison`, `plotPsdComparison`, `plotBandPowerComparison`, `plotSpectralModel`, `plotAnalysisSummary`: independent before/after and model-result plots.

Plot functions return figure/layout/axes handles and accept an optional `plotCfg.parent` Figure, panel, or tab. Artifact comparison places Raw and Clean/display (NaN-marked) panels vertically for each channel, using the same y-limits for each before/after pair. It also includes raw versus finite masked amplitude distributions, per-channel artifact fractions, and event-count/total-duration summaries by artifact type. Figures default to a 1600×1100-pixel canvas and 300-DPI export; adjust `cfg.plot.figurePosition`, `cfg.plot.tileSpacing`, and `cfg.plot.exportResolution` as needed. Batch plotting can retain interactive windows with `KeepFiguresOpen=true`.

## Testing

Synthetic signals will use fixed random seeds and known sinusoids, 1/f backgrounds, artifacts, NaN/Inf values, short recordings, empty channels, and multiple sampling rates. Tolerances will be recorded with each test rather than hidden in implementation defaults.

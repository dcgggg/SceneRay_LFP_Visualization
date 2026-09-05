# Algorithms

This document records planned definitions before implementation.

## Interference

The current project assumption is 40 Hz device/line interference and integer harmonics below Nyquist. The fundamental frequency and notch width will be explicit parameters, not hidden defaults. This is not treated as stimulation artifact.

## Artifact policy

Artifacts are first represented as intervals and channel masks. Detection candidates will include high amplitude, abrupt steps, saturation/rail hits, and abnormal local variance. A detected interval is not proof of head motion without an external motion reference or manual review.

## PSD and bands

PSD units are signal-unit-squared per Hz. Band power is the integral of the selected PSD over a documented frequency interval. Total, relative, aperiodic, and periodic-above-aperiodic quantities are stored separately.

## Aperiodic and periodic components

The current MATLAB-native implementation supports a fixed log-log aperiodic model and reports offset, exponent, residual/error, and fit quality separately from periodic peaks. Knee fitting is intentionally a separate future mode. FieldTrip or native MATLAB implementations may be used, but the project will not call Python FOOOF at runtime. The 40 Hz harmonic bins remain in the PSD and are interpolated only in the spectrum supplied to the parameterization step.

`lfp_interpolate_line_noise` reproduces the documented `fooof.utils.interpolate_spectrum` behavior: each closed range uses averaged buffer samples on both sides and linear interpolation in log-log spacing. With the defaults, ranges are 38–42, 78–82, and so on up to Nyquist. The original `spectrum.psd` is never replaced.

Implemented functions:

- `lfp_preprocess`: robust amplitude, derivative/step and saturation marking; optional NaN processing copy.
- `lfp_compute_psd`: manual Welch PSD with artifact-heavy window rejection.
- `lfp_prepare_spectrum_for_fitting`: fitting-only line-noise interpolation with processing history.
- `lfp_fit_spectral_parameters`: fixed offset/exponent and residual peak detection.
- `lfp_compute_band_power`: total, relative, aperiodic and periodic-above-aperiodic integrations.
- `lfp_plot_results` and `lfp_export_results`: overview figures, MAT/CSV/log/PNG outputs.

## Testing

Synthetic signals will use fixed random seeds and known sinusoids, 1/f backgrounds, artifacts, NaN/Inf values, short recordings, empty channels, and multiple sampling rates. Tolerances will be recorded with each test rather than hidden in implementation defaults.

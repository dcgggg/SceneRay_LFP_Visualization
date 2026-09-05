# Algorithms (draft)

This document records planned definitions before implementation.

## Interference

The current project assumption is 40 Hz device/line interference and integer harmonics below Nyquist. The fundamental frequency and notch width will be explicit parameters, not hidden defaults. This is not treated as stimulation artifact.

## Artifact policy

Artifacts are first represented as intervals and channel masks. Detection candidates will include high amplitude, abrupt steps, saturation/rail hits, and abnormal local variance. A detected interval is not proof of head motion without an external motion reference or manual review.

## PSD and bands

PSD units are signal-unit-squared per Hz. Band power is the integral of the selected PSD over a documented frequency interval. Total, relative, aperiodic, and periodic-above-aperiodic quantities are stored separately.

## Aperiodic and periodic components

The first MATLAB-native implementation will support a fixed log-log aperiodic model and report offset, exponent, residual/error, and fit quality separately from periodic peaks. Knee fitting will be designed as a separate mode. The project will not call Python FOOOF at runtime.

## Testing

Synthetic signals will use fixed random seeds and known sinusoids, 1/f backgrounds, artifacts, NaN/Inf values, short recordings, empty channels, and multiple sampling rates. Tolerances will be recorded with each test rather than hidden in implementation defaults.

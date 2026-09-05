# Data format (draft)

The importer will support the SceneRay CSV layout used by this project and a documented generic matrix layout.

## SceneRay draft

The file may contain metadata rows such as `Device Type`, `IPG SN`, `Channel`, `Gain`, and `Collect Time`, followed by a data header containing `TimeIndex` and one or more signal columns. A channel such as `5~6` means bipolar contacts 5 and 6 and is normalized for display as `5-6`.

The exact multi-channel representation is still a design question: one file with multiple signal columns versus one file per channel. The importer must reject ambiguous sampling-rate or unit metadata rather than silently guessing.

## Canonical MATLAB structure

```matlab
data.signal             % samples x channels, numeric, original units
data.fs                 % scalar Hz
data.time               % samples x 1 seconds
data.channelLabels      % 1 x channels string/cell labels
data.units              % signal unit, e.g. "uV"
data.metadata           % source/device/channel metadata
data.artifacts          % interval and channel-level annotations
data.processingHistory  % ordered struct array of operations and parameters
```

## Validation policy

- Preserve the source file and original numeric samples.
- Reject empty signals, empty channels, non-finite sampling rates, and inconsistent channel lengths.
- Handle NaN/Inf explicitly and record the policy in `processingHistory`.
- Do not infer anatomical electrode location from contact numbers alone.

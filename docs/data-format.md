# Data format

The importer currently supports the confirmed SceneRay CSV layout used by this project. A generic multi-channel matrix adapter remains a later extension.

## SceneRay draft

The file contains one or more repeated blocks. Each block is identified by a `Channel` metadata row, followed by metadata such as `Device Type`, `IPG SN`, `Gain`, and `Collect Time`, and then exactly one `Time Index, Voltage, Tag Code` header. The importer uses the `Channel` rows to determine the channel count and uses the nearest block-local `Time Index` header to delimit samples. A channel such as `5~6` means bipolar contacts 5 and 6 and is normalized for display as `5-6`.

For the current acquisition, sampling rate is fixed at 1000 Hz and Voltage is fixed at μV. The importer records the original Time Index and Tag Code for every block, while `data.time` is generated in seconds from the fixed sampling rate. Blocks must have equal sample counts so they can be represented as one samples × channels matrix; inconsistent counts are rejected instead of silently aligning or truncating data.

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
data.cleanedSignal      % optional NaN-marked analysis/display copy
```

`detectAndHandleArtifacts` returns `artifactResult.sampleMask`, `channelMask`, `globalMask`, `events`, `badChannels`, `method`, `parameters`, `summary`, `retainedDuration`, `rejectedDuration`, `rejectedPercentage`, `warnings`, and `processingHistory`. `events` contains artifact type, sample/time bounds, channel, score, threshold and method. Original `data.signal` remains unchanged; mask-based exclusion is distinct from reconstruction.

For multi-block files, `data.metadata.channelRows`, `blockStarts`, `blockEnds`, and `headerRows` preserve the row-level parsing decisions for auditability. `data.metadata.blocks` stores metadata for each channel independently.

## Validation policy

- Preserve the source file and original numeric samples.
- Reject empty signals, empty channels, non-finite sampling rates, and inconsistent channel lengths.
- Handle NaN/Inf explicitly and record the policy in `processingHistory`.
- Do not infer anatomical electrode location from contact numbers alone.

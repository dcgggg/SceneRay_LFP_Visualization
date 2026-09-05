# Data format

The importer currently supports the confirmed SceneRay CSV layout used by this project. A generic multi-channel matrix adapter remains a later extension.

## SceneRay draft

The file contains metadata rows such as `Device Type`, `IPG SN`, `Channel`, `Gain`, and `Collect Time`, followed by `Time Index, Voltage, Tag Code`. A channel such as `5~6` means bipolar contacts 5 and 6 and is normalized for display as `5-6`.

For the current acquisition, sampling rate is fixed at 1000 Hz and Voltage is fixed at μV. The importer records the original Time Index and Tag Code, while `data.time` is generated in seconds from the fixed sampling rate. Multi-channel file organization will be specified before that adapter is implemented.

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

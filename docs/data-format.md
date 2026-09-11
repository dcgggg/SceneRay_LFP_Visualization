# Data format

The project supports the confirmed SceneRay CSV layout and a GUI-confirmed generic CSV adapter. Generic imports never silently guess a disputed layout: the GUI shows a preview and lets the user confirm delimiter, header/data rows, time column, signal columns, orientation, sampling rate, units and amplitude scale.

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

### Session 内的通道缓存

项目模式下 `Session.channels` 为每个通道保存 `channel_id`、`source_file_id`、
`source_column`、`sampling_rate_hz`、`sample_count`、`cache_relative_path`、
`enabled`、`data_revision` 和质量/来源元数据。原始样本位于 Session `data/channels/`
下的独立 MAT 文件中；`lfp_project_get_channel_data(project,sessionId,channelId)`
按通道读取并校验缓存。`lfp_project_append_data` 只追加新通道，拒绝重复的源文件+列，
不会因为名称相同而覆盖已有通道。移除通道只更新活动索引，不删除共享缓存或历史结果。
不同通道可以有不同长度、采样率和时间轴，分析函数逐通道执行；为兼容旧接口，
`lfp_project_get_session_data` 在需要时返回带 NaN 标记的显示矩阵，并在 metadata 中标记
`heterogeneousChannels`，该矩阵不能替代独立通道分析输入。

For generic CSV files, `lfp_inspect_csv` reads only a bounded prefix for preview and automatic suggestions; it does not materialize the entire file as a heterogeneous cell array. `lfp_import_csv_configured` accepts the confirmed settings and uses a numeric `readmatrix` path for rectangular files, with an explicitly recorded `readcell_fallback` only when the numeric reader cannot handle the source. With `DataDirection="samples_by_channels"`, rows are samples and selected columns are channels. With `DataDirection="channels_by_samples"`, selected columns are samples and each source row is a channel; the output is normalized back to samples × channels. A time column is not supported for the latter orientation because its meaning is ambiguous; provide an explicit sampling rate. Missing signal cells remain NaN and are counted in `metadata.missingValueCount`.

`metadata.timeValidation` records monotonicity, duplicates, regularity, median time step and coefficient of variation. The GUI blocks PSD/model workflows when this validation is invalid or irregular rather than silently resampling. If no time column is supplied, a user-confirmed `SamplingRateHz` is required and `data.time` is generated from sample indices.

`detectAndHandleArtifacts` returns `artifactResult.sampleMask`, `channelMask`, `globalMask`, `events`, `badChannels`, `method`, `parameters`, `summary`, `retainedDuration`, `rejectedDuration`, `rejectedPercentage`, `warnings`, and `processingHistory`. `events` contains artifact type, sample/time bounds, channel, score, threshold and method. Original `data.signal` remains unchanged; mask-based exclusion is distinct from reconstruction.

For multi-block files, `data.metadata.channelRows`, `blockStarts`, `blockEnds`, and `headerRows` preserve the row-level parsing decisions for auditability. `data.metadata.blocks` stores metadata for each channel independently.

Both adapters record `metadata.fileSizeBytes`, `metadata.importStrategy`, and `metadata.estimatedMemoryBytes`. SceneRay files are parsed sequentially so large files do not require a second full heterogeneous cell-array copy solely for preview/import.

## Validation policy

- Preserve the source file and original numeric samples.
- Reject empty signals, empty channels, non-finite sampling rates, and inconsistent channel lengths.
- Handle NaN/Inf explicitly and record the policy in `processingHistory`.
- Do not infer anatomical electrode location from contact numbers alone.

## Project data model

Project mode uses four stable identity levels:

```text
Project
  └─ Subject (subject_id)
      └─ Session (session_id, visit_label, conditions)
          └─ Channel (channel_id, original_label, mapping metadata)
```

Create a project with `lfp_create_project(root, name)`, add explicit Subject
and Session identities with `lfp_project_add_subject` and
`lfp_project_add_session`, and load raw arrays with
`lfp_project_get_session_data`. IDs are persisted and are not regenerated when
display labels change. Channel strings such as `channel01` retain leading
zeros; bipolar labels remain their original labels until a user-provided
mapping specifies side, region, contacts or reference.

The GUI uses a metadata-first workflow: `lfp_project_add_empty_session`
creates a stable Session with status `no_data`, and
`lfp_project_attach_data` attaches the first canonical synchronized record.
Subsequent files can be appended with `lfp_project_append_data`; each imported
channel is independently cached and can be enabled/disabled without deleting
raw samples.
Removing a Subject or Session from the project index does not delete the
original CSV or the project's stored data/result files. Editable display labels,
side, region, contacts and reference can be edited without changing
`channel_id` or `original_label`.

GUI-created projects use a nested, relocatable layout. `project.mat` stores
`storage_mode="subject_session"`; each Subject has a stable-ID folder recorded
in `folder_relative_path`, and each Session has its own stable-ID folder with
`data/`, `configs/`, `results/` and `exports/`. `data_refs.relative_path` and
`data_refs.project_copy_relative_path` are relative to the project root. The
imported source CSV is copied into the Session `data/` directory without
altering the source file; identical source names receive a suffix. Renaming a
Subject or Session changes only display metadata and these relative references,
while stable IDs remain unchanged. Legacy projects with empty folder fields
continue to use their existing root-level references.

For a direct import bridge, `lfp_project_add_csv_session` accepts either the
SceneRay block format or explicit generic-CSV import settings. It never
derives patient or visit identity from a filename.

The project index is kept lightweight. Raw data are stored in a per-Session
MAT file, while every analysis is stored as an `AnalysisRun` with a data
version, computation configuration fingerprint, complete configuration,
module statuses and a result reference. `lfp_analyze_project` never joins
different Sessions into one PSD. A second run with the same data version and
configuration reuses the saved result; changing PSD, artifact, specparam or
analysis-range inputs creates a new run instead of silently overwriting a
successful run.

If separate files belong to the same synchronized Session, call
`lfp_project_add_session_segment`. It requires identical sampling rates,
sample counts and time vectors and rejects duplicate channel labels. Only
after these checks pass are columns combined; a time gap, independent segment
or mismatched length must be represented as a separate Session.

`lfp_compare_project` accepts explicit Session IDs and returns a long table
with `subject_id`, `session_id`, `visit_label`, `channel_id`, `run_id`,
`band`, `metric`, `value`, `unit`, `aggregation`, `config_id` and `qc_status`.
Comparisons match visits by `visit_label`/conditions and report missing or
incompatible runs. They do not perform group-level significance tests or
silently average repeated tests. `lfp_preview_legacy_dataset` provides a
read-only migration preview; `lfp_migrate_legacy_dataset` requires explicit
Subject and Session IDs and never deletes the source file.

Comparison selections are stored by stable Session and Channel IDs. A mapping
may contain multiple rows for one Session, so each row represents one explicit
Session–Channel comparison object and can define its own target label; the GUI
also provides an exact original/display-label matching shortcut across Sessions.
Missing or ambiguous labels are reported instead of falling back to the first
channel. A comparison mapping may define a custom `group_label` per entry, with
`grouping_basis` recorded as `custom`, `subject_group` or `visit`; this does not
change the Subject's stored research group. Grouped PSD summaries first average
repeated Session–Channel entries within a Subject and then average Subjects with
equal weight. Grouped band-power plots use the same hierarchy and report SD only
when at least two Subject values are available. Missing or out-of-range band
values remain missing and are not replaced by zeros.

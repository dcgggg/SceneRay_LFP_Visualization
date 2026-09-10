# Performance and responsiveness

## Identified bottlenecks

- The old inspection path loaded the complete CSV with `readcell` even though the GUI only displayed a preview. This created a large heterogeneous cell array before the numeric import.
- A completed analysis rendered every result tab immediately, including dense raw traces.
- Cache flags existed, but PSD, specparam, and band power were still recomputed on every run.
- Long loops did not yield to the event queue, so the window appeared frozen and cancellation could only occur between modules.
- Several toolbar and parameter-grid columns used fixed pixel widths; long Chinese labels could overlap or be clipped.

## Implemented controls

- CSV inspection streams at most 200 rows by default. Generic rectangular data use `readmatrix`; SceneRay multi-block files use a one-pass block-aware stream parser.
- Import metadata records the strategy, source size, estimated canonical-array memory, and elapsed time.
- The task manager reports preparation, artifact, PSD, specparam, band-power, and visualization stages. Native artifact, Welch, multitaper, and per-channel specparam loops perform cooperative progress/cancellation checks.
- Runtime callbacks are removed before parameters enter result structures or `processingHistory`.
- Result tabs render lazily. Display-only changes dirty plots without invalidating numeric results.
- Dependency-aware cache checks follow Data → Artifact → PSD → specparam → Band power.
- Raw/clean plotting defaults to the full selected record. Longer ranges are reduced only for display with a min/max envelope; the full arrays remain the analysis input.

## Measured CSV improvement

Measurements below were made with MATLAB R2024a on the development Windows computer using generic numeric CSV fixtures. Times vary with storage and MATLAB startup state.

| Fixture | Old inspection | Old numeric import | New inspection | New numeric import | Inspection memory old → new |
| --- | ---: | ---: | ---: | ---: | ---: |
| 10,000 × 5 (0.37 MB) | 1.362 s | 0.032 s | 0.124 s | 0.959 s | 5.36 MB → 0.12 MB |
| 100,000 × 9 (6.87 MB) | 4.293 s | 0.056 s | 0.024 s | 0.162 s | 96.16 MB → 0.22 MB |

For the medium fixture, total inspect-plus-import time fell from about 4.35 seconds to about 0.19 seconds. The first small `readmatrix` call has startup overhead, so very small files can show a slower numeric-import substep despite a much faster preview and far lower temporary memory.

A separate end-to-end benchmark run after the engineering changes used the formal 10-second/4-channel and 10-minute/8-channel fixtures:

| Fixture | CSV size | Inspection | Import | Welch PSD + fixed specparam |
| --- | ---: | ---: | ---: | ---: |
| 10 seconds, 4 channels | 0.39 MB | 0.301 s | 1.040 s | 0.132 s |
| 10 minutes, 8 channels | 43.93 MB | 0.332 s | 0.718 s | 0.093 s |

This benchmark disables artifact exclusion to isolate CSV loading and the PSD/specparam path. It validates imported dimensions before timing analysis. Times should be treated as machine-specific, and the first small-file import includes MATLAB I/O initialization overhead.

## Reproducible benchmark

From the repository root:

```matlab
results = benchmark_lfp_engineering();
```

This runs the required 10-second/4-channel and 10-minute/8-channel fixtures. The 2-hour/16-channel fixture requires roughly 0.92 GB for the canonical doubles before temporary copies and produces a much larger CSV, so it is explicit opt-in:

```matlab
results = benchmark_lfp_engineering(RunLarge=true);
```

The benchmark reports import, inspection, uncached PSD/specparam time, file size, and estimated array memory. GUI cache reuse is validated by `tests/test_lfp_runtime_engineering.m`. Responsiveness is validated structurally through progress callbacks, event-queue yields, cancellation tests and lazy rendering; automated headless testing cannot measure subjective interactive latency.

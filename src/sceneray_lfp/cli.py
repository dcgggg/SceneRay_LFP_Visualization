from __future__ import annotations

import argparse
from pathlib import Path

from .pipeline import AnalysisConfig, analyze_file


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "SceneRay continuous LFP analysis: motion-artifact rejection, "
            "40-Hz harmonic removal, PSD, and FOOOF decomposition."
        )
    )
    parser.add_argument("input_csv", type=Path, help="SceneRay LFP CSV file")
    parser.add_argument("--output", type=Path, default=None, help="Output directory")
    parser.add_argument("--fs", type=float, default=None, help="Sampling rate in Hz; inferred when omitted")
    parser.add_argument("--line-frequency", type=float, default=40.0, help="Fundamental interference frequency (default: 40 Hz)")
    parser.add_argument("--notch-width", type=float, default=2.0, help="Width of every harmonic notch in Hz")
    parser.add_argument("--highpass", type=float, default=0.5, help="High-pass cutoff in Hz; use 0 to disable")
    parser.add_argument("--artifact-window", type=float, default=2.0, help="YASA artifact epoch length in seconds")
    parser.add_argument("--artifact-threshold", type=float, default=3.0, help="YASA standard-deviation z threshold")
    parser.add_argument("--robust-threshold", type=float, default=6.0, help="Robust epoch/sample threshold in MAD-scaled SD")
    parser.add_argument("--artifact-padding", type=float, default=1.0, help="Seconds added around detected artifacts")
    parser.add_argument("--psd-window", type=float, default=4.0, help="PSD window length in seconds")
    parser.add_argument("--psd-max-hz", type=float, default=100.0, help="Maximum plotted/exported PSD frequency")
    parser.add_argument("--fooof-min-hz", type=float, default=1.0, help="FOOOF fit lower frequency")
    parser.add_argument("--fooof-max-hz", type=float, default=100.0, help="FOOOF fit upper frequency")
    parser.add_argument("--export-cleaned-signal", action="store_true", help="Export line-cleaned signal with motion-artifact samples stored as blank/NaN")
    parser.add_argument("--no-artifact-rejection", action="store_true", help="Diagnostic only: include every PSD window")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    config = AnalysisConfig(
        sampling_rate_hz=args.fs,
        line_frequency_hz=args.line_frequency,
        notch_width_hz=args.notch_width,
        highpass_hz=args.highpass,
        artifact_window_s=args.artifact_window,
        yasa_threshold=args.artifact_threshold,
        robust_threshold=args.robust_threshold,
        artifact_padding_s=args.artifact_padding,
        psd_window_s=args.psd_window,
        psd_max_hz=args.psd_max_hz,
        fooof_range_hz=(args.fooof_min_hz, args.fooof_max_hz),
        artifact_rejection=not args.no_artifact_rejection,
        export_cleaned_signal=args.export_cleaned_signal,
    )
    result = analyze_file(args.input_csv, args.output, config)
    print(f"Analysis complete: {result.output_directory}")
    print(
        f"PSD windows accepted: {result.accepted_windows}/{result.total_windows}; "
        f"FOOOF R^2: {result.fooof_r_squared:.4f}"
    )
    return 0

from __future__ import annotations

import csv
import json
import math
import warnings
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy import signal, stats
from yasa import art_detect

with warnings.catch_warnings(record=True):
    from fooof import FOOOF


BANDS = (
    ("Delta", 1.0, 4.0),
    ("Theta", 4.0, 8.0),
    ("Alpha", 8.0, 13.0),
    ("Beta", 13.0, 30.0),
    ("LowGamma", 30.0, 55.0),
    ("HighGamma", 65.0, 100.0),
)


@dataclass(slots=True)
class AnalysisConfig:
    sampling_rate_hz: float | None = None
    line_frequency_hz: float = 40.0
    notch_width_hz: float = 2.0
    highpass_hz: float = 0.5
    artifact_window_s: float = 2.0
    yasa_threshold: float = 3.0
    robust_threshold: float = 6.0
    artifact_padding_s: float = 1.0
    psd_window_s: float = 4.0
    psd_overlap_fraction: float = 0.5
    max_artifact_fraction_per_psd_window: float = 0.01
    minimum_clean_windows: int = 3
    psd_max_hz: float = 100.0
    fooof_range_hz: tuple[float, float] = (1.0, 100.0)
    fooof_peak_width_limits_hz: tuple[float, float] = (1.0, 12.0)
    fooof_max_peaks: int = 10
    fooof_min_peak_height: float = 0.1
    fooof_peak_threshold: float = 2.0
    artifact_rejection: bool = True
    export_cleaned_signal: bool = False


@dataclass(slots=True)
class AnalysisResult:
    output_directory: Path
    sampling_rate_hz: float
    accepted_windows: int
    total_windows: int
    fooof_r_squared: float
    metadata: dict[str, Any]


def read_scenray_csv(path: Path) -> tuple[dict[str, Any], np.ndarray, np.ndarray, list[str]]:
    metadata: dict[str, Any] = {}
    indices: list[float] = []
    voltages: list[float] = []
    tags: list[str] = []
    in_data = False
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.reader(handle):
            if not row:
                continue
            key = row[0].strip()
            normalized = "".join(key.lower().split())
            if normalized == "timeindex":
                in_data = True
                continue
            if not in_data:
                values = [item.strip() for item in row[1:] if item.strip()]
                if normalized == "devicetype" and values:
                    metadata["device_type"] = values[0]
                elif normalized == "ipgsn" and values:
                    metadata["ipg_sn"] = values[0]
                elif normalized == "channel" and values:
                    metadata["channel_raw"] = values[0]
                    metadata["channel"] = values[0].replace("~", "-")
                elif normalized == "gain" and values:
                    metadata["gain"] = float(values[0])
                elif normalized == "collecttime":
                    metadata["collect_time_s"] = _parse_collect_time(row[1:])
                continue
            if len(row) < 2:
                continue
            try:
                indices.append(float(row[0].strip()))
                voltages.append(float(row[1].strip()))
                tags.append(row[2].strip() if len(row) > 2 else "")
            except ValueError:
                continue
    if not voltages:
        raise ValueError(f"No numeric LFP samples found in {path}")
    return metadata, np.asarray(indices), np.asarray(voltages), tags


def _parse_collect_time(parts: list[str]) -> float | None:
    total = 0.0
    found = False
    for raw in parts:
        value = raw.strip().lower()
        try:
            if value.endswith("h"):
                total += float(value[:-1]) * 3600
                found = True
            elif value.endswith("m"):
                total += float(value[:-1]) * 60
                found = True
            elif value.endswith("s"):
                total += float(value[:-1])
                found = True
        except ValueError:
            pass
    return total if found else None


def resolve_sampling_rate(config_fs: float | None, metadata: dict[str, Any], n_samples: int) -> tuple[float, str]:
    if config_fs is not None:
        return float(config_fs), "user supplied"
    duration = metadata.get("collect_time_s")
    if duration and duration > 0:
        estimate = n_samples / duration
        rounded = round(estimate)
        if abs(estimate - rounded) / estimate <= 0.01:
            return float(rounded), "sample count / Collect Time, rounded"
        return float(estimate), "sample count / Collect Time"
    raise ValueError("Sampling rate unavailable; pass --fs with the acquisition sampling rate.")


def harmonic_notch(data: np.ndarray, fs: float, fundamental: float, width: float) -> tuple[np.ndarray, list[float]]:
    if fundamental <= 0 or width <= 0:
        return data.copy(), []
    output = np.asarray(data, dtype=float).copy()
    harmonics = []
    frequency = fundamental
    while frequency < fs / 2 - width:
        quality = frequency / width
        b, a = signal.iirnotch(frequency, quality, fs=fs)
        output = signal.filtfilt(b, a, output)
        harmonics.append(float(frequency))
        frequency += fundamental
    return output, harmonics


def highpass(data: np.ndarray, fs: float, cutoff: float) -> np.ndarray:
    centered = signal.detrend(data, type="constant")
    if cutoff <= 0:
        return centered
    if cutoff >= fs / 2:
        raise ValueError("High-pass cutoff must be below Nyquist frequency.")
    sos = signal.butter(4, cutoff, btype="highpass", fs=fs, output="sos")
    return signal.sosfiltfilt(sos, centered)


def _robust_z(values: np.ndarray) -> np.ndarray:
    center = np.nanmedian(values)
    scale = stats.median_abs_deviation(values, nan_policy="omit", scale="normal")
    if not np.isfinite(scale) or scale <= np.finfo(float).eps:
        scale = np.nanstd(values)
    if not np.isfinite(scale) or scale <= 0:
        return np.zeros_like(values, dtype=float)
    return (values - center) / scale


def _expand_mask(mask: np.ndarray, padding: int) -> np.ndarray:
    if padding <= 0 or not np.any(mask):
        return mask.copy()
    points = np.flatnonzero(mask)
    starts = np.maximum(points - padding, 0)
    ends = np.minimum(points + padding + 1, mask.size)
    delta = np.zeros(mask.size + 1, dtype=np.int64)
    np.add.at(delta, starts, 1)
    np.add.at(delta, ends, -1)
    return np.cumsum(delta[:-1]) > 0


def detect_motion_artifacts(
    raw: np.ndarray, line_cleaned: np.ndarray, fs: float, config: AnalysisConfig
) -> tuple[np.ndarray, list[dict[str, Any]], dict[str, Any]]:
    n = raw.size
    epoch_samples = max(16, round(config.artifact_window_s * fs))
    n_epochs = n // epoch_samples
    if n_epochs < 3:
        raise ValueError("Recording is too short for automatic artifact detection.")
    trimmed = line_cleaned[: n_epochs * epoch_samples]
    try:
        yasa_bad, yasa_scores = art_detect(
            trimmed[np.newaxis, :],
            sf=fs,
            window=config.artifact_window_s,
            method="std",
            threshold=config.yasa_threshold,
            verbose=False,
        )
        yasa_bad = np.asarray(yasa_bad, dtype=bool)
        yasa_scores = np.asarray(yasa_scores).reshape(-1)
    except Exception as exc:
        warnings.warn(f"YASA artifact detection failed; robust safeguards remain active: {exc}")
        yasa_bad = np.zeros(n_epochs, dtype=bool)
        yasa_scores = np.full(n_epochs, np.nan)

    epochs = trimmed.reshape(n_epochs, epoch_samples)
    epoch_std = np.std(epochs, axis=1)
    epoch_ptp = np.ptp(epochs, axis=1)
    epoch_diff_rms = np.sqrt(np.mean(np.diff(epochs, axis=1) ** 2, axis=1))
    std_z = _robust_z(np.log(np.maximum(epoch_std, np.finfo(float).tiny)))
    ptp_z = _robust_z(np.log(np.maximum(epoch_ptp, np.finfo(float).tiny)))
    diff_z = _robust_z(np.log(np.maximum(epoch_diff_rms, np.finfo(float).tiny)))
    robust_bad = np.maximum.reduce([std_z, ptp_z, diff_z]) > config.robust_threshold
    epoch_bad = yasa_bad | robust_bad

    base_mask = np.zeros(n, dtype=bool)
    for index, bad in enumerate(epoch_bad):
        if bad:
            base_mask[index * epoch_samples : (index + 1) * epoch_samples] = True

    derivative = np.diff(raw, prepend=raw[0])
    derivative_z = np.abs(_robust_z(derivative))
    transient_mask = derivative_z > config.robust_threshold
    base_mask |= transient_mask
    raw_min, raw_max = np.nanmin(raw), np.nanmax(raw)
    min_fraction = np.mean(raw == raw_min)
    max_fraction = np.mean(raw == raw_max)
    rail_mask = np.zeros(n, dtype=bool)
    if min_fraction > 0.001:
        rail_mask |= raw == raw_min
    if max_fraction > 0.001:
        rail_mask |= raw == raw_max
    base_mask |= rail_mask

    if config.artifact_rejection:
        artifact_mask = _expand_mask(base_mask, round(config.artifact_padding_s * fs))
    else:
        artifact_mask = np.zeros(n, dtype=bool)

    rows: list[dict[str, Any]] = []
    for index in range(n_epochs):
        start = index * epoch_samples
        stop = (index + 1) * epoch_samples
        transient_fraction = float(np.mean(transient_mask[start:stop]))
        rail_fraction = float(np.mean(rail_mask[start:stop]))
        sample_level_artifact = transient_fraction > 0 or rail_fraction > 0
        rows.append(
            {
                "epoch": index + 1,
                "start_time_s": index * epoch_samples / fs,
                "end_time_s": (index + 1) * epoch_samples / fs,
                "yasa_zscore": float(yasa_scores[index]) if index < yasa_scores.size else math.nan,
                "log_std_robust_z": float(std_z[index]),
                "log_ptp_robust_z": float(ptp_z[index]),
                "log_diff_rms_robust_z": float(diff_z[index]),
                "yasa_artifact": bool(yasa_bad[index]),
                "robust_artifact": bool(robust_bad[index]),
                "transient_sample_fraction": transient_fraction,
                "rail_sample_fraction": rail_fraction,
                "artifact": bool(epoch_bad[index] or sample_level_artifact),
            }
        )
    epoch_artifact_count = sum(bool(row["artifact"]) for row in rows)
    summary = {
        "artifact_sample_percent": float(100 * np.mean(artifact_mask)),
        "yasa_artifact_epochs": int(np.count_nonzero(yasa_bad)),
        "robust_artifact_epochs": int(np.count_nonzero(robust_bad)),
        "combined_artifact_epochs": int(epoch_artifact_count),
        "total_artifact_epochs": int(n_epochs),
        "observed_minimum_fraction": float(min_fraction),
        "observed_maximum_fraction": float(max_fraction),
    }
    return artifact_mask, rows, summary


def harmonic_attenuation_rows(
    raw: np.ndarray, line_cleaned: np.ndarray, fs: float, harmonics: list[float]
) -> list[dict[str, Any]]:
    """Quantify the attenuation at each configured interference harmonic."""
    nperseg = min(raw.size, max(256, round(4 * fs)))
    frequencies, raw_power = signal.welch(raw, fs=fs, nperseg=nperseg, detrend="constant")
    _, cleaned_power = signal.welch(line_cleaned, fs=fs, nperseg=nperseg, detrend="constant")
    rows: list[dict[str, Any]] = []
    for harmonic in harmonics:
        index = int(np.argmin(np.abs(frequencies - harmonic)))
        before = float(raw_power[index])
        after = float(cleaned_power[index])
        rows.append(
            {
                "configured_harmonic_hz": harmonic,
                "welch_bin_hz": float(frequencies[index]),
                "raw_psd_uV2_per_hz": before,
                "notched_psd_uV2_per_hz": after,
                "attenuation_db": float(10 * np.log10(max(after, np.finfo(float).tiny) / max(before, np.finfo(float).tiny))),
            }
        )
    return rows


def clean_window_psd(
    data: np.ndarray, artifact_mask: np.ndarray, fs: float, config: AnalysisConfig
) -> tuple[np.ndarray, np.ndarray, list[dict[str, Any]]]:
    window_samples = max(16, round(config.psd_window_s * fs))
    step = max(1, round(window_samples * (1 - config.psd_overlap_fraction)))
    starts = range(0, data.size - window_samples + 1, step)
    spectra: list[np.ndarray] = []
    rows: list[dict[str, Any]] = []
    frequencies: np.ndarray | None = None
    for number, start in enumerate(starts, 1):
        stop = start + window_samples
        fraction = float(np.mean(artifact_mask[start:stop]))
        accepted = (not config.artifact_rejection) or fraction <= config.max_artifact_fraction_per_psd_window
        rows.append(
            {
                "window": number,
                "start_time_s": start / fs,
                "end_time_s": stop / fs,
                "artifact_fraction": fraction,
                "accepted": accepted,
            }
        )
        if accepted:
            frequencies, power = signal.periodogram(
                data[start:stop], fs=fs, window="hann", detrend="constant", scaling="density"
            )
            spectra.append(power)
    if len(spectra) < config.minimum_clean_windows:
        raise ValueError(
            f"Only {len(spectra)} clean PSD windows remain; at least "
            f"{config.minimum_clean_windows} are required. Review artifact thresholds."
        )
    return frequencies, np.median(np.vstack(spectra), axis=0), rows


def interpolate_harmonic_notches(
    frequencies: np.ndarray, power: np.ndarray, harmonics: list[float], width: float
) -> np.ndarray:
    output = power.copy()
    log_power = np.log10(np.maximum(power, np.finfo(float).tiny))
    excluded = np.zeros(power.size, dtype=bool)
    for frequency in harmonics:
        excluded |= np.abs(frequencies - frequency) <= width
    good = ~excluded & np.isfinite(log_power)
    if np.count_nonzero(good) >= 2:
        output[excluded] = 10 ** np.interp(frequencies[excluded], frequencies[good], log_power[good])
    return output


def fit_fooof(
    frequencies: np.ndarray, power: np.ndarray, harmonics: list[float], config: AnalysisConfig
) -> tuple[FOOOF, np.ndarray]:
    upper = min(config.fooof_range_hz[1], frequencies[-1], config.sampling_rate_hz / 2 if config.sampling_rate_hz else frequencies[-1])
    fit_range = [config.fooof_range_hz[0], upper]
    if fit_range[1] <= fit_range[0]:
        raise ValueError("FOOOF frequency range is invalid for this sampling rate.")
    prepared = interpolate_harmonic_notches(frequencies, power, harmonics, config.notch_width_hz)
    model = FOOOF(
        peak_width_limits=config.fooof_peak_width_limits_hz,
        max_n_peaks=config.fooof_max_peaks,
        min_peak_height=config.fooof_min_peak_height,
        peak_threshold=config.fooof_peak_threshold,
        aperiodic_mode="fixed",
        verbose=False,
    )
    model.fit(frequencies, prepared, fit_range)
    return model, prepared


def _integral(frequencies: np.ndarray, values: np.ndarray, low: float, high: float) -> float:
    mask = (frequencies >= low) & (frequencies <= high)
    if np.count_nonzero(mask) < 2:
        return math.nan
    return float(np.trapz(values[mask], frequencies[mask]))


def component_band_rows(model: FOOOF) -> list[dict[str, Any]]:
    frequencies = model.freqs
    full = model.get_model("full", "linear")
    aperiodic = model.get_model("aperiodic", "linear")
    periodic = model.get_model("peak", "linear")
    rows = []
    for name, low, high in BANDS:
        rows.append(
            {
                "band": name,
                "low_hz": low,
                "high_hz": high,
                "model_total_power_uV2": _integral(frequencies, full, low, high),
                "aperiodic_power_uV2": _integral(frequencies, aperiodic, low, high),
                "periodic_power_uV2": _integral(frequencies, periodic, low, high),
            }
        )
    return rows


def peak_rows(model: FOOOF) -> list[dict[str, Any]]:
    return [
        {
            "center_frequency_hz": float(center),
            "peak_power_above_aperiodic_log10": float(power),
            "bandwidth_hz": float(bandwidth),
        }
        for center, power, bandwidth in np.asarray(model.peak_params_).reshape(-1, 3)
    ]


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def _plot_results(
    output: Path,
    stem: str,
    time_s: np.ndarray,
    raw: np.ndarray,
    line_cleaned: np.ndarray,
    artifact_mask: np.ndarray,
    frequencies: np.ndarray,
    power: np.ndarray,
    model: FOOOF,
    band_rows: list[dict[str, Any]],
    metadata: dict[str, Any],
    accepted: int,
    total: int,
    psd_max_hz: float,
    harmonics: list[float],
) -> None:
    blue, orange, gold, gray = "#1f5f9f", "#d75a18", "#c98f22", "#555b66"
    stride = max(1, raw.size // 60000)
    fig, axes = plt.subplots(2, 1, figsize=(12, 8), constrained_layout=True)
    axes[0].plot(time_s[::stride], raw[::stride], color=blue, linewidth=0.6, label="Raw")
    marked = raw.copy()
    marked[~artifact_mask] = np.nan
    axes[0].plot(time_s[::stride], marked[::stride], color=orange, linewidth=0.8, label="Rejected")
    axes[0].set(title="Raw LFP and detected motion-artifact regions", ylabel="Voltage (µV)")
    axes[0].legend(frameon=False)
    axes[1].plot(time_s[::stride], line_cleaned[::stride], color=blue, linewidth=0.6)
    axes[1].set(title="40 Hz harmonic-notched signal (artifacts retained for audit)", xlabel="Time (s)", ylabel="Voltage (µV)")
    for axis in axes:
        axis.grid(alpha=0.22)
        axis.spines[["top", "right"]].set_visible(False)
    fig.suptitle(f"IPG {metadata.get('ipg_sn', 'unknown')} | Channel {metadata.get('channel', 'unknown')}")
    fig.savefig(output / f"{stem}_waveforms.png", dpi=180)
    plt.close(fig)

    fig, axis = plt.subplots(figsize=(11, 7), constrained_layout=True)
    shown = (frequencies >= 0.5) & (frequencies <= psd_max_hz)
    axis.plot(frequencies[shown], 10 * np.log10(np.maximum(power[shown], np.finfo(float).tiny)), color=blue, label="Clean-window PSD")
    axis.plot(model.freqs, 10 * np.log10(model.get_model("full", "linear")), color=orange, linewidth=1.4, label="FOOOF full model")
    axis.plot(model.freqs, 10 * np.log10(model.get_model("aperiodic", "linear")), color=gray, linestyle="--", label="Aperiodic component")
    for index, harmonic in enumerate(harmonics):
        if harmonic <= psd_max_hz:
            axis.axvline(harmonic, color="#999999", linewidth=0.8, linestyle=":", label="40 Hz harmonics" if index == 0 else None)
    axis.set(title=f"PSD and FOOOF parameterization | clean windows {accepted}/{total}", xlabel="Frequency (Hz)", ylabel="PSD (dB re 1 µV²/Hz)")
    axis.grid(alpha=0.22)
    axis.spines[["top", "right"]].set_visible(False)
    axis.legend(frameon=False)
    fig.savefig(output / f"{stem}_psd_fooof.png", dpi=180)
    plt.close(fig)

    names = [row["band"] for row in band_rows]
    periodic = [row["periodic_power_uV2"] for row in band_rows]
    aperiodic = [row["aperiodic_power_uV2"] for row in band_rows]
    x = np.arange(len(names))
    fig, axis = plt.subplots(figsize=(11, 6), constrained_layout=True)
    axis.bar(x, aperiodic, color=gray, label="Aperiodic")
    axis.bar(x, periodic, bottom=aperiodic, color=gold, label="Periodic above aperiodic")
    axis.set_xticks(x, names)
    axis.set(title="FOOOF model-derived spectral power by band", ylabel="Integrated model power (µV²)")
    axis.grid(axis="y", alpha=0.22)
    axis.spines[["top", "right"]].set_visible(False)
    axis.legend(frameon=False)
    fig.savefig(output / f"{stem}_band_components.png", dpi=180)
    plt.close(fig)


def analyze_file(
    input_csv: str | Path,
    output_directory: str | Path | None = None,
    config: AnalysisConfig | None = None,
) -> AnalysisResult:
    path = Path(input_csv).expanduser().resolve()
    if not path.is_file():
        raise FileNotFoundError(path)
    config = config or AnalysisConfig()
    metadata, indices, raw, tags = read_scenray_csv(path)
    fs, fs_source = resolve_sampling_rate(config.sampling_rate_hz, metadata, raw.size)
    config.sampling_rate_hz = fs
    if np.any(~np.isfinite(raw)):
        raise ValueError("Voltage contains non-finite values; repair or exclude them before analysis.")

    line_cleaned, harmonics = harmonic_notch(raw, fs, config.line_frequency_hz, config.notch_width_hz)
    artifact_mask, artifact_epochs, artifact_summary = detect_motion_artifacts(raw, line_cleaned, fs, config)
    analysis_signal = highpass(line_cleaned, fs, config.highpass_hz)
    frequencies, power, psd_windows = clean_window_psd(analysis_signal, artifact_mask, fs, config)
    model, fooof_input = fit_fooof(frequencies, power, harmonics, config)
    bands = component_band_rows(model)
    peaks = peak_rows(model)
    harmonic_attenuation = harmonic_attenuation_rows(raw, line_cleaned, fs, harmonics)

    output = Path(output_directory) if output_directory else path.with_name(f"{path.stem}_results")
    output.mkdir(parents=True, exist_ok=True)
    metadata.update(
        {
            "input_file_name": path.name,
            "sampling_rate_hz": fs,
            "sampling_rate_source": fs_source,
            "sample_count": int(raw.size),
            "duration_s": float(raw.size / fs),
            "line_frequency_hz": config.line_frequency_hz,
            "notched_harmonics_hz": harmonics,
        }
    )
    accepted = sum(bool(row["accepted"]) for row in psd_windows)
    summary = {
        "metadata": metadata,
        "config": asdict(config),
        "artifact_summary": artifact_summary,
        "psd_windows_accepted": accepted,
        "psd_windows_total": len(psd_windows),
        "fooof": {
            "aperiodic_parameters": np.asarray(model.aperiodic_params_).tolist(),
            "r_squared": float(model.r_squared_),
            "error": float(model.error_),
            "peak_count": int(model.n_peaks_),
        },
    }
    (output / f"{path.stem}_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    _write_csv(output / f"{path.stem}_artifact_epochs.csv", artifact_epochs)
    _write_csv(output / f"{path.stem}_psd_windows.csv", psd_windows)
    _write_csv(output / f"{path.stem}_periodic_peaks.csv", peaks)
    _write_csv(output / f"{path.stem}_band_components.csv", bands)
    _write_csv(output / f"{path.stem}_harmonic_attenuation.csv", harmonic_attenuation)
    _write_csv(
        output / f"{path.stem}_psd.csv",
        [
            {
                "frequency_hz": float(f),
                "clean_window_psd_uV2_per_hz": float(p),
                "fooof_input_psd_uV2_per_hz": float(fp),
            }
            for f, p, fp in zip(frequencies, power, fooof_input)
            if f <= config.psd_max_hz
        ],
    )
    if config.export_cleaned_signal:
        cleaned = line_cleaned.copy()
        cleaned[artifact_mask] = np.nan
        _write_csv(
            output / f"{path.stem}_cleaned_signal.csv",
            [
                {"time_s": i / fs, "cleaned_voltage_uV": value, "artifact": bool(bad)}
                for i, (value, bad) in enumerate(zip(cleaned, artifact_mask))
            ],
        )
    _plot_results(
        output,
        path.stem,
        np.arange(raw.size) / fs,
        raw,
        line_cleaned,
        artifact_mask,
        frequencies,
        power,
        model,
        bands,
        metadata,
        accepted,
        len(psd_windows),
        min(config.psd_max_hz, fs / 2),
        harmonics,
    )
    return AnalysisResult(output, fs, accepted, len(psd_windows), float(model.r_squared_), metadata)

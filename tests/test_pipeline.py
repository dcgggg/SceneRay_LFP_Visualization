import numpy as np

from sceneray_lfp.pipeline import (
    AnalysisConfig,
    detect_motion_artifacts,
    harmonic_notch,
)


def test_harmonic_notch_suppresses_40_and_80_hz():
    fs = 1000.0
    time = np.arange(0, 20, 1 / fs)
    data = np.sin(2 * np.pi * 10 * time) + 5 * np.sin(2 * np.pi * 40 * time) + 3 * np.sin(2 * np.pi * 80 * time)
    cleaned, harmonics = harmonic_notch(data, fs, 40, 2)
    before = np.abs(np.fft.rfft(data))
    after = np.abs(np.fft.rfft(cleaned))
    frequencies = np.fft.rfftfreq(data.size, 1 / fs)
    for target in (40, 80):
        index = np.argmin(np.abs(frequencies - target))
        assert after[index] < before[index] * 0.05
    assert harmonics[:2] == [40.0, 80.0]


def test_motion_artifact_mask_flags_large_transient():
    fs = 500.0
    rng = np.random.default_rng(42)
    data = rng.normal(0, 2, int(60 * fs))
    data[int(20 * fs) : int(24 * fs)] += 500 * np.sin(2 * np.pi * 2 * np.arange(int(4 * fs)) / fs)
    config = AnalysisConfig(sampling_rate_hz=fs, artifact_padding_s=0.25, robust_threshold=4)
    mask, _, summary = detect_motion_artifacts(data, data, fs, config)
    assert mask[int(21 * fs) : int(23 * fs)].mean() > 0.9
    assert summary["artifact_sample_percent"] > 0

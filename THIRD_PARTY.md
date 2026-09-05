# Third-party tools and citations

This project orchestrates established open-source scientific packages; it does not copy their source code into this repository. The portable Windows build bundles the installed runtime packages. This file records their license metadata and citation guidance; consult each upstream distribution for the complete license text.

## Directly used scientific packages

### FOOOF 1.1.1

- Purpose: parameterize power spectra into periodic peaks and an aperiodic component.
- Project: https://fooof-tools.github.io/fooof/
- Source: https://github.com/fooof-tools/fooof
- License: Apache License 2.0.
- Citation: Donoghue T, Haller M, Peterson EJ, et al. Parameterizing neural power spectra into periodic and aperiodic components. *Nature Neuroscience*. 2020;23:1655–1665. https://doi.org/10.1038/s41593-020-00744-x

### YASA 0.7.0

- Purpose: `yasa.art_detect(..., method="std")` for automatic major movement-artifact window detection in single-channel data.
- Documentation: https://yasa-sleep.org/generated/yasa.art_detect.html
- Source: https://github.com/raphaelvallat/yasa
- License: BSD 3-Clause.
- Citation requested by the project: Vallat R, Walker MP. An open-source, high-performance tool for automated sleep staging. *eLife*. 2021;10:e70092. https://doi.org/10.7554/eLife.70092
- Scope note: YASA documents this detector for EEG and major body artifacts. Its use for intracranial LFP is an engineering adaptation and must be validated against manually reviewed data.

### SciPy 1.13.1

- Purpose: 40 Hz harmonic notch filters, high-pass filter, periodograms, detrending, and robust statistics.
- Project: https://scipy.org/
- License: BSD 3-Clause.
- Citation: Virtanen P, Gommers R, Oliphant TE, et al. SciPy 1.0: fundamental algorithms for scientific computing in Python. *Nature Methods*. 2020;17:261–272. https://doi.org/10.1038/s41592-019-0686-2

### NumPy 1.26.4

- Purpose: numerical arrays and numerical aggregation.
- Project: https://numpy.org/
- License: BSD 3-Clause.
- Citation: Harris CR, Millman KJ, van der Walt SJ, et al. Array programming with NumPy. *Nature*. 2020;585:357–362. https://doi.org/10.1038/s41586-020-2649-2

### Matplotlib 3.9.4

- Purpose: exported waveform, artifact, PSD, FOOOF, and band-component figures.
- Project: https://matplotlib.org/
- License: PSF-based Matplotlib license.
- Citation: Hunter JD. Matplotlib: A 2D Graphics Environment. *Computing in Science & Engineering*. 2007;9(3):90–95. https://doi.org/10.1109/MCSE.2007.55

## Runtime dependencies brought in by YASA

- MNE-Python 1.9.0 — BSD 3-Clause, https://mne.tools/
- pandas 2.2.3 — BSD 3-Clause, https://pandas.pydata.org/

The program does not directly call MNE or pandas APIs, but these packages are pinned because YASA depends on them.

## Build tool

### PyInstaller 6.22.2

- Purpose: create a Windows x64 folder that includes Python and all runtime packages.
- Project: https://pyinstaller.org/
- License: GPL 2.0 with an exception permitting distribution of bundled applications.

Versions are pinned in `requirements.txt` and `requirements-build.txt` for reproducibility. Always consult each upstream project for full license terms and current citation guidance.

# AGENTS.md — MATLAB LFP project rules

## Scope

This repository is a MATLAB-only LFP analysis and visualization project. Do not add Python, R, Java, Node.js, runtime downloads, external servers, or hard-coded user paths.

## Supported environment

- Minimum design target: MATLAB R2022b.
- Primary platform: Windows; keep paths and file I/O portable to macOS and Linux.
- Optional acceleration: Signal Processing Toolbox, Statistics and Machine Learning Toolbox, FieldTrip, EEGLAB, or a MATLAB-compatible spectral-parameterization package. Core behavior must have a base-MATLAB path when practical.

## Architecture rules

- Keep data import, data model, preprocessing/artifact handling, spectral analysis, parameterization, band analysis, visualization, GUI, export, and tests in separate modules.
- Analysis functions must not depend on GUI state.
- Preserve raw samples. Prefer artifact intervals and channel masks over destructive deletion; any derived signal with NaN values must be explicitly named and documented.
- Every public analysis function documents units, missing-value behavior, validation, and exceptional cases.
- Append every processing operation and its parameters to `data.processingHistory`.

## Git workflow

- Before editing, run `git status --short --branch` and preserve unrelated user changes.
- Use small independently reversible commits.
- Run the relevant MATLAB tests, inspect `git diff --check` and `git diff`, then commit only after tests pass.
- Use English Conventional Commit messages, for example `feat: add LFP data importer`.
- Never use `git reset --hard`, force push, branch deletion, tag deletion, or broad cleaning commands without explicit user authorization.
- Stable milestones may receive annotated tags such as `v0.1.0`.

## Scientific safeguards

- Keep total power, relative power, periodic power, aperiodic offset, exponent, knee, and fit quality as separate fields.
- Never interpret a change in band power without checking the aperiodic background.
- Fixed and knee aperiodic models must be explicit configuration choices.
- 40 Hz interference and harmonics are configuration, not stimulation artifacts, unless the user later specifies otherwise.
- Do not label an artifact as head motion with certainty when no motion reference or manual annotation exists; use language such as `suspected_motion_artifact`.

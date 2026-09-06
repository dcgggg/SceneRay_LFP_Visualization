function cfg = lfpDefaultConfig()
%LFPDEFAULTCONFIG Return explicit defaults for the script/API workflow.
%   The structure is GUI-independent and can be copied and edited before
%   calling the analysis functions. No function reads user input dialogs.

cfg = struct();
cfg.version = "0.5.0";
cfg.artifact = struct();
cfg.artifact.method = "fieldtrip";
cfg.artifact.nativeFallback = true;
cfg.artifact.fieldtripCutoff = 6;
cfg.artifact.paddingSeconds = 0.010;
cfg.artifact.manualIntervalsSamples = zeros(0, 2);
cfg.artifact.manualIntervalsSeconds = zeros(0, 2);
cfg.artifact.amplitudeZ = 8;
cfg.artifact.derivativeZ = 8;
cfg.artifact.flatlineRunSeconds = 0.250;
cfg.artifact.flatlineToleranceUV = 1e-6;
cfg.artifact.saturationAbsoluteThresholdUV = 5000;
cfg.artifact.saturationRunLength = 5;
cfg.artifact.highFrequencyWindowSeconds = 0.250;
cfg.artifact.highFrequencyZ = 8;
cfg.artifact.lineFrequencyHz = 40;
cfg.artifact.lineHarmonics = true;
cfg.artifact.lineWindowSeconds = 1;
cfg.artifact.lineNoiseRatioThreshold = 0.50;
cfg.artifact.badChannelFraction = 0.50;
cfg.artifact.reconstruct = false;

cfg.psd = struct();
cfg.psd.method = "welch";
cfg.psd.windowLengthSec = 4;
cfg.psd.overlapFraction = 0.5;
cfg.psd.nfft = 0;
cfg.psd.taper = "hann";
cfg.psd.frequencyRange = [1 40];
cfg.psd.excludeArtifacts = true;
cfg.psd.maxArtifactFraction = 0;
cfg.psd.aggregationMethod = "mean";

cfg.fooof = struct();
cfg.fooof.frequencyRange = [1 40];
cfg.fooof.aperiodicMode = "fixed";
cfg.fooof.peakWidthLimits = [2 12];
cfg.fooof.maxNumberPeaks = 6;
cfg.fooof.minPeakHeight = 0.10;
cfg.fooof.peakThreshold = 2.5;
cfg.fooof.fitErrorMetric = "rmse";
cfg.fooof.interpolateLineNoise = true;
cfg.fooof.lineFrequencyHz = 40;
cfg.fooof.lineInterpolationHalfWidthHz = 2;
cfg.fooof.lineInterpolationBufferSamples = 3;
cfg.fooof.lineIncludeHarmonics = true;

cfg.bands = struct();
cfg.bands.delta = [1 4];
cfg.bands.theta = [4 8];
cfg.bands.alpha = [8 13];
cfg.bands.beta = [13 30];
cfg.bands.lowGamma = [30 55];
cfg.bands.highGamma = [65 100];

cfg.plot = struct();
cfg.plot.visible = "on";
cfg.plot.frequencyScale = "linear";
cfg.plot.powerScale = "log10";
cfg.plot.frequencyRange = [1 40];
cfg.plot.maxPlotSeconds = 30;
cfg.plot.channelIndex = [];
cfg.plot.parent = [];
cfg.plot.showArtifactLabels = true;
cfg.plot.figurePosition = [80 80 1600 1100];
cfg.plot.tileSpacing = "loose";
cfg.plot.tilePadding = "loose";
cfg.plot.fontSize = 10;
cfg.plot.exportResolution = 300;

cfg.export = struct();
cfg.export.exportFigure = true;
cfg.export.figureResolution = 150;

cfg.parameterMetadata = build_parameter_metadata(cfg);
end

function metadata = build_parameter_metadata(cfg)
metadata = struct('name', {}, 'defaultValue', {}, 'dataType', {}, ...
    'unit', {}, 'validRange', {}, 'choices', {}, 'description', {}, 'guiGroup', {});
metadata(end+1) = item("artifact.method", cfg.artifact.method, "string", "", [], ...
    ["fieldtrip" "native" "asr"], "Artifact backend; unavailable backends fall back when enabled.", "Artifact");
metadata(end+1) = item("artifact.fieldtripCutoff", cfg.artifact.fieldtripCutoff, "double", "z", [0 Inf], [], ...
    "FieldTrip z-value cutoff; must be tuned to the LFP distribution.", "Artifact");
metadata(end+1) = item("artifact.paddingSeconds", cfg.artifact.paddingSeconds, "double", "s", [0 Inf], [], ...
    "Padding applied around detected artifact samples.", "Artifact");
metadata(end+1) = item("artifact.amplitudeZ", cfg.artifact.amplitudeZ, "double", "z", [0 Inf], [], ...
    "Robust amplitude threshold for the native backend.", "Artifact");
metadata(end+1) = item("artifact.derivativeZ", cfg.artifact.derivativeZ, "double", "z", [0 Inf], [], ...
    "Robust first-difference threshold for jumps and spikes.", "Artifact");
metadata(end+1) = item("psd.windowLengthSec", cfg.psd.windowLengthSec, "double", "s", [eps Inf], [], ...
    "Welch/STFT window length.", "PSD");
metadata(end+1) = item("psd.overlapFraction", cfg.psd.overlapFraction, "double", "fraction", [0 1], [], ...
    "Fractional overlap between adjacent windows.", "PSD");
metadata(end+1) = item("psd.frequencyRange", cfg.psd.frequencyRange, "double", "Hz", [0 Inf], [], ...
    "Frequency range retained in the PSD result.", "PSD");
metadata(end+1) = item("fooof.frequencyRange", cfg.fooof.frequencyRange, "double", "Hz", [0 Inf], [], ...
    "Frequency range used for fixed/no-knee parameterization.", "Spectral model");
metadata(end+1) = item("fooof.aperiodicMode", cfg.fooof.aperiodicMode, "string", "", [], ...
    ["fixed" "knee"], "Aperiodic model selection; current native implementation supports fixed.", "Spectral model");
metadata(end+1) = item("fooof.interpolateLineNoise", cfg.fooof.interpolateLineNoise, "logical", "", [0 1], [], ...
    "Interpolate line-noise harmonics in a fitting copy only; original PSD is retained.", "Spectral model");
metadata(end+1) = item("fooof.lineFrequencyHz", cfg.fooof.lineFrequencyHz, "double", "Hz", [eps Inf], [], ...
    "Line-noise fundamental used for fitting-only interpolation.", "Spectral model");
metadata(end+1) = item("fooof.lineInterpolationHalfWidthHz", cfg.fooof.lineInterpolationHalfWidthHz, "double", "Hz", [0 Inf], [], ...
    "Half-width of each interpolation range around line-noise harmonics.", "Spectral model");
metadata(end+1) = item("fooof.peakWidthLimits", cfg.fooof.peakWidthLimits, "double", "Hz", [0 Inf], [], ...
    "Lower/upper Gaussian bandwidth limits; lower bound is checked against frequency resolution.", "Spectral model");
metadata(end+1) = item("fooof.maxNumberPeaks", cfg.fooof.maxNumberPeaks, "double", "count", [1 Inf], [], ...
    "Maximum number of periodic peaks per channel.", "Spectral model");
metadata(end+1) = item("bands", cfg.bands, "struct", "Hz", [], [], ...
    "Named frequency intervals used for total, relative, aperiodic and periodic power.", "Band power");
metadata(end+1) = item("plot.frequencyScale", cfg.plot.frequencyScale, "string", "", [], ...
    ["linear" "log"], "Frequency-axis scale for model plots.", "Plot");
end

function value = item(name, defaultValue, dataType, unit, validRange, choices, description, guiGroup)
value = struct('name', name, 'defaultValue', defaultValue, 'dataType', dataType, ...
    'unit', unit, 'validRange', validRange, 'choices', choices, ...
    'description', description, 'guiGroup', guiGroup);
end

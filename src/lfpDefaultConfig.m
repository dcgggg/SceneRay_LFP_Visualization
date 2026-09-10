function cfg = lfpDefaultConfig()
%LFPDEFAULTCONFIG Return explicit defaults for the script/API workflow.
%   The structure is GUI-independent and can be copied and edited before
%   calling the analysis functions. No function reads user input dialogs.

cfg = struct();
cfg.version = "0.7.0";
cfg.artifact = struct();
cfg.artifact.method = "native";
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
cfg.artifact.highFrequencyZ = 6;
cfg.artifact.strictMode = true;
cfg.artifact.strictWindowSeconds = 0.100;
cfg.artifact.strictStepSeconds = 0.050;
cfg.artifact.strictHighpassHz = 100;
cfg.artifact.strictHighFrequencyZ = 4;
cfg.artifact.strictDerivativeZ = 4;
cfg.artifact.strictRangeZ = 4;
cfg.artifact.strictMergeGapSeconds = 0.200;
cfg.artifact.lineFrequencyHz = 40;
cfg.artifact.lineHarmonics = true;
cfg.artifact.lineNoiseDetection = false;
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
cfg.psd.detrend = "constant";
cfg.psd.multitaper = struct('timeBandwidthProduct', 3.5, ...
    'taperCount', floor(2 * 3.5) - 1, 'weighting', "equal");
cfg.psd.frequencyRange = [1 40];
cfg.psd.excludeArtifacts = true;
cfg.psd.maxArtifactFraction = 0;
cfg.psd.aggregationMethod = "mean";
cfg.psd.timeFrequency = struct();
cfg.psd.timeFrequency.enabled = true;
cfg.psd.timeFrequency.reusePsdParameters = true;
cfg.psd.timeFrequency.windowLengthSec = 1;
cfg.psd.timeFrequency.stepSeconds = 0.25;
cfg.psd.timeFrequency.nfft = 0;
cfg.psd.timeFrequency.frequencyRange = [1 40];
cfg.psd.timeFrequency.maxArtifactFraction = 0;
cfg.psd.timeFrequency.powerScale = "log10";
cfg.psd.timeFrequency.colorLimits = "auto";
cfg.psd.timeFrequency.colorLimitsManual = [-5 1];
cfg.psd.timeFrequency.colormap = "parula";
cfg.psd.timeFrequency.baselineEnabled = false;
cfg.psd.timeFrequency.baselineRangeSec = [0 0];
cfg.psd.timeFrequency.multitaper = struct('timeBandwidthProduct', 3.5, ...
    'taperCount', floor(2 * 3.5) - 1, 'weighting', "equal");

cfg.fooof = struct();
cfg.fooof.frequencyRange = [1 35];
cfg.fooof.aperiodicMode = "fixed";
cfg.fooof.peakWidthLimits = [2 12];
cfg.fooof.maxNumberPeaks = 6;
cfg.fooof.minPeakHeight = 0.10;
cfg.fooof.peakThreshold = 2.5;
cfg.fooof.fitErrorMetric = "rmse";

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
cfg.plot.maxPlotSeconds = Inf;
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
cfg.export.figureResolution = 300;

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
metadata(end+1) = item("artifact.lineNoiseDetection", cfg.artifact.lineNoiseDetection, "logical", "", [0 1], [], ...
    "Time-domain 40-Hz rejection; disabled by default so line noise can be interpolated only during fitting.", "Artifact");
metadata(end+1) = item("artifact.strictMode", cfg.artifact.strictMode, "logical", "", [0 1], [], ...
    "Short-window high-frequency/burst detector; marks complete abnormal windows and joins short gaps.", "Artifact");
metadata(end+1) = item("artifact.strictHighpassHz", cfg.artifact.strictHighpassHz, "double", "Hz", [0 Inf], [], ...
    "Approximate high-pass boundary for the strict detector; keep above retained LFP/line-noise frequencies.", "Artifact");
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
metadata(end+1) = item("psd.method", cfg.psd.method, "string", "", [], ...
    ["welch" "multitaper"], "PSD estimator. Multitaper uses DPSS tapers and never silently falls back to Welch.", "PSD");
metadata(end+1) = item("psd.detrend", cfg.psd.detrend, "string", "", [], ...
    ["none" "constant" "linear"], "Detrending applied independently to each valid window.", "PSD");
metadata(end+1) = item("psd.multitaper.timeBandwidthProduct", cfg.psd.multitaper.timeBandwidthProduct, "double", "NW", [0.5 Inf], [], ...
    "DPSS time-bandwidth product. Derived half-bandwidth is NW/T and total smoothing is approximately 2NW/T.", "PSD");
metadata(end+1) = item("psd.multitaper.taperCount", cfg.psd.multitaper.taperCount, "double", "count", [1 Inf], [], ...
    "Number of DPSS tapers; default floor(2*NW)-1.", "PSD");
metadata(end+1) = item("psd.timeFrequency", cfg.psd.timeFrequency, "struct", "", [], [], ...
    "Sliding-window time-frequency parameters. Invalid windows remain NaN and time gaps are not compressed.", "PSD");
metadata(end+1) = item("psd.timeFrequency.windowLengthSec", cfg.psd.timeFrequency.windowLengthSec, "double", "s", [eps Inf], [], ...
    "Independent sliding-window length when PSD parameters are not reused.", "PSD");
metadata(end+1) = item("psd.timeFrequency.stepSeconds", cfg.psd.timeFrequency.stepSeconds, "double", "s", [eps Inf], [], ...
    "Sliding-window step; overlap is derived from window length and step.", "PSD");
metadata(end+1) = item("psd.timeFrequency.frequencyRange", cfg.psd.timeFrequency.frequencyRange, "double", "Hz", [0 Inf], [], ...
    "Time-frequency frequency range; invalid windows remain NaN.", "PSD");
metadata(end+1) = item("psd.maxArtifactFraction", cfg.psd.maxArtifactFraction, "double", "fraction", [0 1], [], ...
    "Maximum invalid/artifact fraction accepted in a PSD window when exclusion is enabled.", "PSD");
metadata(end+1) = item("fooof.frequencyRange", cfg.fooof.frequencyRange, "double", "Hz", [0 Inf], [], ...
    "Frequency range used for fixed/no-knee parameterization.", "Spectral model");
metadata(end+1) = item("fooof.aperiodicMode", cfg.fooof.aperiodicMode, "string", "", [], ...
    ["fixed" "knee"], "Aperiodic model selection for native MATLAB specparam (original FOOOF naming retained for compatibility).", "Spectral model");
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

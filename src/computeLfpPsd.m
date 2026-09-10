function psdResult = computeLfpPsd(cleanData, artifactResult, psdCfg)
%COMPUTELFPPSD GUI-independent PSD entry point using cfg.psd fields.
%   PSDRESULT = COMPUTELFPPSD(CLEANDATA, ARTIFACTRESULT, CFGPSD) reuses
%   lfp_compute_psd and returns its DATA.spectrum structure. Raw samples are
%   read from cleanData.signal; artifactResult.channelMask controls window
%   exclusion. Power values remain linear units^2/Hz.

arguments
    cleanData (1,1) struct
    artifactResult (1,1) struct
    psdCfg (1,1) struct
end

if ~isfield(artifactResult, 'channelMask')
    error('LFP:InvalidArtifactResult', 'artifactResult.channelMask is required.');
end
cleanData.artifacts = artifactResult;
required = {'windowLengthSec', 'overlapFraction', 'nfft', 'maxArtifactFraction', ...
    'excludeArtifacts', 'aggregationMethod', 'frequencyRange'};
for index = 1:numel(required)
    if ~isfield(psdCfg, required{index})
        error('LFP:InvalidPsdConfig', 'psdCfg.%s is required.', required{index});
    end
end
method = get_field(psdCfg, 'method', "multitaper");
detrendMode = get_field(psdCfg, 'detrend', "constant");
multitaper = get_field(psdCfg, 'multitaper', struct());
progress = get_field(psdCfg, 'progressCallback', @(fraction, message)[]);
cancel = get_field(psdCfg, 'cancellationCheck', @()[]);
if ~isa(progress, 'function_handle'), progress = @(fraction, message)[]; end
if ~isa(cancel, 'function_handle'), cancel = @()[]; end
tfCfg = get_field(psdCfg, 'timeFrequency', struct());
computeTimeFrequency = isstruct(tfCfg) && get_field(tfCfg, 'enabled', false);
if computeTimeFrequency
    psdProgress = @(fraction, message)progress(0.65 * fraction, message);
else
    psdProgress = progress;
end
resultData = lfp_compute_psd(cleanData, ...
    WindowSeconds=psdCfg.windowLengthSec, ...
    OverlapFraction=psdCfg.overlapFraction, ...
    Nfft=psdCfg.nfft, ...
    MaxArtifactFraction=psdCfg.maxArtifactFraction, ...
    ExcludeArtifacts=psdCfg.excludeArtifacts, ...
    AggregationMethod=string(psdCfg.aggregationMethod), ...
    Method=string(method), DetrendMode=string(detrendMode), ...
    TimeBandwidthProduct=get_field(multitaper, 'timeBandwidthProduct', 3.5), ...
    TaperCount=get_field(multitaper, 'taperCount', 0), ...
    TaperWeighting=string(get_field(multitaper, 'weighting', "equal")), ...
    FrequencyRangeHz=psdCfg.frequencyRange, ...
    ProgressCallback=psdProgress, CancellationCheck=cancel);
psdResult = resultData.spectrum;
% Expose the updated history so a GUI/script can persist the complete audit
% trail without needing to use the legacy DATA-returning entry point.
psdResult.processingHistory = resultData.processingHistory;
if computeTimeFrequency
    tfMethod = string(method);
    if get_field(tfCfg, 'reusePsdParameters', true)
        tfWindow = psdCfg.windowLengthSec;
        tfStep = psdCfg.windowLengthSec * (1 - psdCfg.overlapFraction);
        tfNfft = psdCfg.nfft;
        tfRange = psdCfg.frequencyRange;
        tfNW = get_field(multitaper, 'timeBandwidthProduct', 3.5);
        tfK = get_field(multitaper, 'taperCount', 0);
    else
        tfWindow = get_field(tfCfg, 'windowLengthSec', 1);
        tfStep = get_field(tfCfg, 'stepSeconds', 0.25);
        tfNfft = get_field(tfCfg, 'nfft', 0);
        tfRange = get_field(tfCfg, 'frequencyRange', psdCfg.frequencyRange);
        tfMt = get_field(tfCfg, 'multitaper', struct());
        tfNW = get_field(tfMt, 'timeBandwidthProduct', get_field(multitaper, 'timeBandwidthProduct', 3.5));
        tfK = get_field(tfMt, 'taperCount', get_field(multitaper, 'taperCount', 0));
    end
    tfData = lfp_compute_time_frequency(cleanData, ...
        WindowSeconds=tfWindow, StepSeconds=tfStep, Nfft=tfNfft, ...
        FrequencyRangeHz=tfRange, MaxArtifactFraction=get_field(tfCfg, 'maxArtifactFraction', psdCfg.maxArtifactFraction), ...
        ExcludeArtifacts=psdCfg.excludeArtifacts, Method=tfMethod, ...
        TimeBandwidthProduct=tfNW, TaperCount=tfK, ...
        PowerScale=string(get_field(tfCfg, 'powerScale', "linear")), ...
        ProgressCallback=@(fraction, message)progress(0.65 + 0.35 * fraction, message), ...
        CancellationCheck=cancel);
    psdResult.timeFrequency = tfData.timeFrequency;
end
progress(1, "PSD and time-frequency calculation complete");
end

function value = get_field(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = defaultValue; end
end

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
resultData = lfp_compute_psd(cleanData, ...
    WindowSeconds=psdCfg.windowLengthSec, ...
    OverlapFraction=psdCfg.overlapFraction, ...
    Nfft=psdCfg.nfft, ...
    MaxArtifactFraction=psdCfg.maxArtifactFraction, ...
    ExcludeArtifacts=psdCfg.excludeArtifacts, ...
    AggregationMethod=string(psdCfg.aggregationMethod), ...
    FrequencyRangeHz=psdCfg.frequencyRange);
psdResult = resultData.spectrum;
% Expose the updated history so a GUI/script can persist the complete audit
% trail without needing to use the legacy DATA-returning entry point.
psdResult.processingHistory = resultData.processingHistory;
end

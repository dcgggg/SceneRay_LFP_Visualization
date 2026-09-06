function bandResult = computeBandPower(psdResult, modelResult, bandsCfg)
%COMPUTEBANDPOWER GUI-independent band-power compatibility entry point.
%   BANDRESULT = COMPUTEBANDPOWER(PSDRESULT, MODELRESULT, CFGBANDS) returns
%   total, relative, aperiodic and periodic-above-aperiodic powers. PSD and
%   model powers are linear values; integration uses trapz.

arguments
    psdResult (1,1) struct
    modelResult struct
    bandsCfg (1,1) struct
end
if ~isfield(psdResult, 'frequencyHz') || ~isfield(psdResult, 'psd')
    error('LFP:InvalidSpectrum', 'psdResult.frequencyHz and psdResult.psd are required.');
end
bands = struct('name', {}, 'rangeHz', {});
names = fieldnames(bandsCfg);
for index = 1:numel(names)
    bands(index).name = string(names{index});
    bands(index).rangeHz = bandsCfg.(names{index});
end
nChannels = size(psdResult.psd, 2);
data = struct('signal', zeros(1, nChannels), 'fs', get_field(psdResult, 'fs', 1000), ...
    'units', get_field(psdResult, 'units', "uV"), 'channelLabels', "channel_" + string((1:nChannels)'), ...
    'spectrum', psdResult, 'processingHistory', struct( ...
    'operation', "psd", 'parameters', struct(), 'notes', "compatibility entry point"));
if ~isempty(modelResult)
    if numel(modelResult) ~= nChannels
        error('LFP:InvalidModelResult', 'modelResult count must match PSD channels.');
    end
    data.spectralParameters = struct('aperiodicPsd', horzcat(modelResult.aperiodicFit), ...
        'periodicPowerAboveAperiodic', horzcat(modelResult.periodicFit));
end
resultData = lfp_compute_band_power(data, Bands=bands);
bandResult = resultData.bandPower;
end

function value = get_field(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = defaultValue; end
end

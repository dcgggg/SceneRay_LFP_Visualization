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
labels = get_field(psdResult, 'channelLabels', "channel_" + string(1:nChannels));
labels = string(labels(:))';
data = struct('signal', zeros(1, nChannels), 'fs', get_field(psdResult, 'fs', 1000), ...
    'units', get_field(psdResult, 'units', "uV"), 'channelLabels', labels, ...
    'spectrum', psdResult, 'processingHistory', struct( ...
    'operation', "psd", 'parameters', struct(), 'notes', "compatibility entry point"));
if ~isempty(modelResult)
    aperiodicPsd = collect_model_spectrum(modelResult, 'aperiodicFit', size(psdResult.psd, 1), nChannels);
    periodicPsd = collect_model_spectrum(modelResult, 'periodicFit', size(psdResult.psd, 1), nChannels);
    data.spectralParameters = struct('aperiodicPsd', aperiodicPsd, ...
        'periodicPowerAboveAperiodic', periodicPsd);
end
resultData = lfp_compute_band_power(data, Bands=bands);
bandResult = resultData.bandPower;
bandResult.processingHistory = resultData.processingHistory;
bandResult.parameterizationWarnings = collect_fit_warnings(modelResult, nChannels);
end

function value = get_field(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = defaultValue; end
end

function matrix = collect_model_spectrum(modelResult, fieldName, nFrequencies, nChannels)
% Normalize row/column vectors and matrix orientation to frequency-by-channel.
if isstruct(modelResult) && numel(modelResult) == 1
    values = modelResult.(fieldName);
    if isempty(values)
        matrix = NaN(nFrequencies, nChannels);
        return;
    end
    if isvector(values) && numel(values) == nFrequencies && nChannels == 1
        matrix = values(:);
    elseif isequal(size(values), [nFrequencies nChannels])
        matrix = values;
    elseif isequal(size(values), [nChannels nFrequencies])
        matrix = values.';
    else
        error('LFP:InvalidModelResult', ...
            '%s has size [%d %d]; expected [%d %d] or its transpose.', fieldName, ...
            size(values, 1), size(values, 2), nFrequencies, nChannels);
    end
    return;
end
if numel(modelResult) ~= nChannels
    error('LFP:InvalidModelResult', ...
        'modelResult count (%d) must match PSD channel count (%d).', numel(modelResult), nChannels);
end
matrix = NaN(nFrequencies, nChannels);
for channel = 1:nChannels
    values = modelResult(channel).(fieldName);
    if isempty(values)
        % Preserve a failed fit as missing parameterized power. Total and
        % relative PSD-derived band powers remain available.
        continue;
    end
    if numel(values) ~= nFrequencies
        error('LFP:InvalidModelResult', ...
            '%s for channel %d has %d elements; expected %d.', fieldName, channel, numel(values), nFrequencies);
    end
matrix(:, channel) = values(:);
end
end

function warnings = collect_fit_warnings(modelResult, nChannels)
warnings = strings(0, 1);
if isempty(modelResult) || ~isstruct(modelResult) || ...
        (numel(modelResult) == 1 && nChannels > 1)
    return;
end
for channel = 1:min(numel(modelResult), nChannels)
    status = get_field(modelResult(channel), 'fitStatus', "unknown");
    if string(status) ~= "ok"
        warnings(end + 1, 1) = sprintf('Channel %d parameterization status: %s.', ...
            channel, string(status)); %#ok<AGROW>
    end
    fitWarnings = get_field(modelResult(channel), 'warnings', strings(0, 1));
    if ~isempty(fitWarnings)
        warnings = [warnings; string(fitWarnings(:))]; %#ok<AGROW>
    end
end
warnings = unique(warnings, 'stable');
end

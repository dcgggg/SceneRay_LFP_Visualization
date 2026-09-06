function data = lfp_compute_band_power(data, options)
%LFP_COMPUTE_BAND_POWER Integrate total, relative, aperiodic and periodic power.
%   DATA = LFP_COMPUTE_BAND_POWER(DATA) integrates DATA.spectrum.psd with
%   trapz for configurable bands. If DATA.spectralParameters is present,
%   its aperiodic and periodic spectra are integrated separately.

arguments
    data (1,1) struct
    options.Bands = []
    options.ReferenceRangeHz (1,2) double {mustBeNonnegative} = [0 Inf]
end

if ~isfield(data, 'spectrum') || ~isfield(data.spectrum, 'frequencyHz') || ...
        ~isfield(data.spectrum, 'psd')
    error('LFP:InvalidSpectrum', 'Run lfp_compute_psd before band-power analysis.');
end
if isempty(options.Bands)
    bands = default_bands();
else
    bands = validate_bands(options.Bands);
end

frequencyHz = double(data.spectrum.frequencyHz(:));
totalPsd = double(data.spectrum.psd);
nChannels = size(totalPsd, 2);
if size(totalPsd, 1) ~= numel(frequencyHz)
    error('LFP:InvalidSpectrum', 'PSD rows must match frequencyHz.');
end
referenceMask = frequencyHz >= options.ReferenceRangeHz(1) & ...
    frequencyHz <= min(options.ReferenceRangeHz(2), frequencyHz(end)) & frequencyHz > 0;
referencePower = integrate_columns(frequencyHz(referenceMask), totalPsd(referenceMask, :));

hasParameterization = isfield(data, 'spectralParameters') && ...
    isfield(data.spectralParameters, 'aperiodicPsd') && ...
    isfield(data.spectralParameters, 'periodicPowerAboveAperiodic');
if hasParameterization
    aperiodicPsd = double(data.spectralParameters.aperiodicPsd);
    periodicPsd = double(data.spectralParameters.periodicPowerAboveAperiodic);
    if ~isequal(size(aperiodicPsd), size(totalPsd)) || ~isequal(size(periodicPsd), size(totalPsd))
        error('LFP:InvalidParameters', 'Parameterized spectra must match the PSD dimensions.');
    end
else
    aperiodicPsd = NaN(size(totalPsd));
    periodicPsd = NaN(size(totalPsd));
end

nBands = numel(bands);
rows = nBands * nChannels;
bandName = strings(rows, 1);
channelIndex = zeros(rows, 1);
channelLabel = strings(rows, 1);
lowHz = zeros(rows, 1);
highHz = zeros(rows, 1);
totalPower = NaN(rows, 1);
relativePower = NaN(rows, 1);
aperiodicPower = NaN(rows, 1);
periodicPower = NaN(rows, 1);
logTotalPower = NaN(rows, 1);
row = 0;
for bandIndex = 1:nBands
    bandMask = frequencyHz >= bands(bandIndex).rangeHz(1) & ...
        frequencyHz <= min(bands(bandIndex).rangeHz(2), frequencyHz(end)) & frequencyHz > 0;
    for channel = 1:nChannels
        row = row + 1;
        bandName(row) = bands(bandIndex).name;
        channelIndex(row) = channel;
        channelLabel(row) = get_channel_label(data, channel);
        lowHz(row) = bands(bandIndex).rangeHz(1);
        highHz(row) = bands(bandIndex).rangeHz(2);
        if nnz(bandMask) >= 2
            totalPower(row) = integrate_columns(frequencyHz(bandMask), totalPsd(bandMask, channel));
            if isfinite(totalPower(row)) && totalPower(row) > 0
                logTotalPower(row) = log10(totalPower(row));
            end
            relativePower(row) = totalPower(row) / max(referencePower(channel), eps);
            if hasParameterization
                aperiodicPower(row) = integrate_columns(frequencyHz(bandMask), aperiodicPsd(bandMask, channel));
                periodicPower(row) = integrate_columns(frequencyHz(bandMask), periodicPsd(bandMask, channel));
            end
        end
    end
end

resultTable = table(channelIndex, channelLabel, bandName, lowHz, highHz, ...
    totalPower, logTotalPower, relativePower, aperiodicPower, periodicPower, ...
    'VariableNames', {'channelIndex', 'channelLabel', 'band', 'lowHz', 'highHz', ...
    'totalPower', 'logTotalPower', 'relativePower', 'aperiodicPower', 'periodicPower'});
data.bandPower = struct('table', resultTable, 'bands', bands, ...
    'referenceRangeHz', options.ReferenceRangeHz, ...
    'referencePower', referencePower, 'hasParameterization', hasParameterization, ...
    'powerUnits', string(data.units) + "^2");
entry = struct('operation', "band_power", ...
    'parameters', struct('bands', bands, 'referenceRangeHz', options.ReferenceRangeHz), ...
    'notes', "Total, relative, aperiodic and periodic powers integrated independently with trapz.");
data.processingHistory(end + 1) = entry;
end

function bands = default_bands()
bands = struct('name', {"delta", "theta", "alpha", "beta", "low-gamma", "high-gamma"}, ...
    'rangeHz', {[1 4], [4 8], [8 13], [13 30], [30 55], [65 100]});
end

function bands = validate_bands(bands)
if ~isstruct(bands) || ~all(isfield(bands, {'name', 'rangeHz'}))
    error('LFP:InvalidBands', 'Bands must be a struct array with name and rangeHz fields.');
end
for index = 1:numel(bands)
    bands(index).name = string(bands(index).name);
    if numel(bands(index).rangeHz) ~= 2 || any(~isfinite(bands(index).rangeHz)) || ...
            bands(index).rangeHz(2) <= bands(index).rangeHz(1)
        error('LFP:InvalidBands', 'Each band rangeHz must be an increasing finite two-element vector.');
    end
end
end

function value = integrate_columns(frequencyHz, values)
if isempty(frequencyHz) || size(values, 1) < 2
    value = NaN(size(values, 2), 1);
    return;
end
value = trapz(frequencyHz, values, 1)';
end

function label = get_channel_label(data, channel)
if isfield(data, 'channelLabels') && numel(data.channelLabels) >= channel
    label = string(data.channelLabels(channel));
else
    label = "channel_" + channel;
end
end

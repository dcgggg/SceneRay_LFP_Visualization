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
referenceInterval=double(options.ReferenceRangeHz);
referenceInterval(1)=max(referenceInterval(1),frequencyHz(1));
if ~isfinite(referenceInterval(2)),referenceInterval(2)=frequencyHz(end);else,referenceInterval(2)=min(referenceInterval(2),frequencyHz(end));end
[referencePower,~] = integrate_interval(frequencyHz, totalPsd, referenceInterval);

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
computable = false(rows, 1);
status = strings(rows, 1);
row = 0;
for bandIndex = 1:nBands
    bandInRange = bands(bandIndex).rangeHz(1) >= frequencyHz(1) && ...
        bands(bandIndex).rangeHz(2) <= frequencyHz(end);
    for channel = 1:nChannels
        row = row + 1;
        bandName(row) = bands(bandIndex).name;
        channelIndex(row) = channel;
        channelLabel(row) = get_channel_label(data, channel);
        lowHz(row) = bands(bandIndex).rangeHz(1);
        highHz(row) = bands(bandIndex).rangeHz(2);
        if ~bandInRange
            status(row) = "outside_psd_range";
        else
            [totalPower(row),integralOk] = integrate_interval(frequencyHz, totalPsd(:,channel), bands(bandIndex).rangeHz);
            if ~integralOk || ~isfinite(totalPower(row)) || totalPower(row) < 0
                status(row) = "invalid_psd";
                continue;
            end
            if isfinite(totalPower(row)) && totalPower(row) > 0
                logTotalPower(row) = log10(totalPower(row));
                computable(row) = true;
                status(row) = "ok";
            end
            if isfinite(referencePower(channel)) && referencePower(channel) > 0
                relativePower(row) = totalPower(row) / referencePower(channel);
            else
                % Total power remains valid even when the selected
                % reference interval cannot provide a denominator.
                status(row) = "reference_unavailable";
            end
            if hasParameterization
                [aperiodicPower(row),aperiodicOk] = integrate_interval(frequencyHz, aperiodicPsd(:,channel), bands(bandIndex).rangeHz);
                [periodicPower(row),periodicOk] = integrate_interval(frequencyHz, periodicPsd(:,channel), bands(bandIndex).rangeHz);
                if ~aperiodicOk, aperiodicPower(row)=NaN; end
                if ~periodicOk, periodicPower(row)=NaN; end
            end
        end
    end
end

resultTable = table(channelIndex, channelLabel, bandName, lowHz, highHz, ...
    totalPower, logTotalPower, relativePower, aperiodicPower, periodicPower, ...
    computable, status, ...
    'VariableNames', {'channelIndex', 'channelLabel', 'band', 'lowHz', 'highHz', ...
    'totalPower', 'logTotalPower', 'relativePower', 'aperiodicPower', 'periodicPower', ...
    'computable', 'status'});
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

function [value,ok] = integrate_interval(frequencyHz, values, interval)
% Integrate linear PSD values and interpolate only valid interval edges.
% Interior NaN/Inf values are rejected; no extrapolation or gap filling is
% performed. This keeps adjacent, non-grid-aligned band edges consistent.
frequencyHz=double(frequencyHz(:));values=double(values);if isvector(values),values=values(:);end
nChannels=size(values,2);value=NaN(nChannels,1);ok=false(nChannels,1);
if numel(interval)~=2 || numel(frequencyHz)<2 || size(values,1)~=numel(frequencyHz),return;end
if any(~isfinite(frequencyHz)) || any(diff(frequencyHz)<=0),return;end
low=double(interval(1));high=double(interval(2));
if ~isfinite(low),low=frequencyHz(1);end;if ~isfinite(high),high=frequencyHz(end);end
if low<frequencyHz(1) || high>frequencyHz(end) || high<=low,return;end
mask=frequencyHz>=low & frequencyHz<=high;
if nnz(mask)<1,return;end
x=unique([low;frequencyHz(mask);high]);
for c=1:nChannels
    interior=values(mask,c);
    if any(~isfinite(interior)) || any(interior<0),continue;end
    yq=interp1(frequencyHz,values(:,c),x,'linear');
    if any(~isfinite(yq)) || any(yq<0),continue;end
    value(c)=trapz(x,yq);ok(c)=isfinite(value(c));
end
end

function label = get_channel_label(data, channel)
if isfield(data, 'channelLabels') && numel(data.channelLabels) >= channel
    label = string(data.channelLabels(channel));
else
    label = "channel_" + channel;
end
end

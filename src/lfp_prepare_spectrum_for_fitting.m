function data = lfp_prepare_spectrum_for_fitting(data, options)
%LFP_PREPARE_SPECTRUM_FOR_FITTING Interpolate line noise and log the step.
%   DATA = LFP_PREPARE_SPECTRUM_FOR_FITTING(DATA) preserves DATA.spectrum.psd
%   and adds DATA.spectrum.psdForFitting using 40-Hz harmonic interpolation.

arguments
    data (1,1) struct
    options.LineFrequencyHz (1,1) double {mustBeFinite, mustBePositive} = 40
    options.InterpolationHalfWidthHz (1,1) double {mustBeFinite, mustBeNonnegative} = 2
    options.BufferSamples (1,1) double {mustBeInteger, mustBePositive} = 3
    options.IncludeHarmonics (1,1) logical = true
end

if ~isfield(data, 'spectrum') || ~isfield(data, 'processingHistory')
    error('LFP:InvalidData', 'DATA.spectrum and DATA.processingHistory are required.');
end
data.spectrum = lfp_interpolate_line_noise(data.spectrum, ...
    LineFrequencyHz=options.LineFrequencyHz, ...
    InterpolationHalfWidthHz=options.InterpolationHalfWidthHz, ...
    BufferSamples=options.BufferSamples, IncludeHarmonics=options.IncludeHarmonics);
parameters = struct('lineFrequencyHz', options.LineFrequencyHz, ...
    'interpolationHalfWidthHz', options.InterpolationHalfWidthHz, ...
    'bufferSamples', options.BufferSamples, 'includeHarmonics', options.IncludeHarmonics, ...
    'rangesHz', data.spectrum.lineNoise.rangesHz);
data.processingHistory(end + 1) = struct('operation', "line_noise_interpolation", ...
    'parameters', parameters, ...
    'notes', "Only psdForFitting was interpolated; original PSD and harmonic peaks were retained.");
end

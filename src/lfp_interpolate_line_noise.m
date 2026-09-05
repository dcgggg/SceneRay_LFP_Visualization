function spectrum = lfp_interpolate_line_noise(spectrum, options)
%LFP_INTERPOLATE_LINE_NOISE Prepare a PSD for spectral parameterization.
%   SPECTRUM = LFP_INTERPOLATE_LINE_NOISE(SPECTRUM) copies SPECTRUM.psd
%   into SPECTRUM.psdForFitting and interpolates 40-Hz harmonics in the
%   frequency domain. The original PSD is not changed. Interpolation
%   follows fooof.utils.interpolate_spectrum: linearly interpolate in
%   log-log space using averaged buffer samples on both sides of each
%   closed frequency range.

arguments
    spectrum (1,1) struct
    options.LineFrequencyHz (1,1) double {mustBeFinite, mustBePositive} = 40
    options.InterpolationHalfWidthHz (1,1) double {mustBeFinite, mustBeNonnegative} = 2
    options.BufferSamples (1,1) double {mustBeInteger, mustBePositive} = 3
    options.IncludeHarmonics (1,1) logical = true
end

if ~isfield(spectrum, 'frequencyHz') || ~isfield(spectrum, 'psd')
    error('LFP:InvalidSpectrum', 'SPECTRUM.frequencyHz and SPECTRUM.psd are required.');
end
frequencyHz = double(spectrum.frequencyHz(:));
psd = double(spectrum.psd);
if size(psd, 1) ~= numel(frequencyHz)
    error('LFP:InvalidSpectrum', 'SPECTRUM.psd rows must match frequencyHz.');
end
if any(diff(frequencyHz) <= 0) || any(frequencyHz < 0)
    error('LFP:InvalidSpectrum', 'frequencyHz must be nonnegative and strictly increasing.');
end

maxFrequency = frequencyHz(end);
if options.IncludeHarmonics
    harmonicCenters = options.LineFrequencyHz:options.LineFrequencyHz:maxFrequency;
else
    harmonicCenters = options.LineFrequencyHz;
end
harmonicCenters = harmonicCenters(harmonicCenters <= maxFrequency);
ranges = [harmonicCenters(:) - options.InterpolationHalfWidthHz, ...
    harmonicCenters(:) + options.InterpolationHalfWidthHz];
ranges(:, 1) = max(ranges(:, 1), frequencyHz(1));
ranges(:, 2) = min(ranges(:, 2), maxFrequency);

fittingPsd = psd;
interpolatedMask = false(size(psd, 1), 1);
for channelIndex = 1:size(psd, 2)
    for rangeIndex = 1:size(ranges, 1)
        inside = frequencyHz >= ranges(rangeIndex, 1) & frequencyHz <= ranges(rangeIndex, 2);
        insideIndices = find(inside);
        if isempty(insideIndices)
            continue;
        end
        leftCandidates = find(frequencyHz < ranges(rangeIndex, 1));
        rightCandidates = find(frequencyHz > ranges(rangeIndex, 2));
        if isempty(leftCandidates) || isempty(rightCandidates)
            continue;
        end
        leftIndices = leftCandidates(max(1, end - options.BufferSamples + 1):end);
        rightIndices = rightCandidates(1:min(options.BufferSamples, numel(rightCandidates)));
        anchorIndices = [leftIndices(:); rightIndices(:)];
        anchorPowers = psd(anchorIndices, channelIndex);
        valid = isfinite(anchorPowers) & anchorPowers > 0 & frequencyHz(anchorIndices) > 0;
        if nnz(valid) < 2
            continue;
        end
        leftValid = valid(1:numel(leftIndices));
        rightValid = valid(numel(leftIndices)+1:end);
        if ~any(leftValid) || ~any(rightValid)
            continue;
        end
        leftAnchor = leftIndices(find(leftValid, 1, 'last'));
        rightAnchor = rightIndices(find(rightValid, 1, 'first'));
        leftPool = leftIndices(leftValid);
        rightPool = rightIndices(rightValid);
        leftLogFrequency = mean(log10(frequencyHz(leftPool)));
        rightLogFrequency = mean(log10(frequencyHz(rightPool)));
        leftLogPower = mean(log10(psd(leftPool, channelIndex)));
        rightLogPower = mean(log10(psd(rightPool, channelIndex)));
        if ~(isfinite(leftLogFrequency) && isfinite(rightLogFrequency) && ...
                rightLogFrequency > leftLogFrequency)
            leftLogFrequency = log10(frequencyHz(leftAnchor));
            rightLogFrequency = log10(frequencyHz(rightAnchor));
            leftLogPower = log10(psd(leftAnchor, channelIndex));
            rightLogPower = log10(psd(rightAnchor, channelIndex));
        end
        interpolatedLogPower = interp1([leftLogFrequency, rightLogFrequency], ...
            [leftLogPower, rightLogPower], log10(frequencyHz(insideIndices)), 'linear');
        fittingPsd(insideIndices, channelIndex) = 10 .^ interpolatedLogPower(:);
        interpolatedMask(insideIndices) = true;
    end
end

spectrum.psdForFitting = fittingPsd;
spectrum.lineNoise = struct('lineFrequencyHz', options.LineFrequencyHz, ...
    'harmonicCentersHz', harmonicCenters(:), 'rangesHz', ranges, ...
    'interpolatedMask', interpolatedMask, 'bufferSamples', options.BufferSamples, ...
    'interpolationHalfWidthHz', options.InterpolationHalfWidthHz, ...
    'method', "log-log interpolation (fooof.utils.interpolate_spectrum compatible)");
spectrum.includesLineNoise = true;
end

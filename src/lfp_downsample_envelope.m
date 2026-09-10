function [displayTime, displaySignal, info] = lfp_downsample_envelope(time, signal, maxPoints)
%LFP_DOWNSAMPLE_ENVELOPE Create a display-only min/max envelope.
%   [T,Y,INFO] = LFP_DOWNSAMPLE_ENVELOPE(TIME,SIGNAL,MAXPOINTS) reduces a
%   samples-by-channels waveform to at most approximately MAXPOINTS rows.
%   Each bin contributes its minimum and maximum in chronological order, so
%   short spikes remain visible. A bin containing NaN/Inf is represented by
%   NaN for that channel; excluded artifact gaps are therefore never drawn
%   as continuous data. The input arrays are not modified and this helper
%   must not be used for scientific calculations.

arguments
    time (:,1) double
    signal double
    maxPoints (1,1) double {mustBeFinite, mustBeInteger, mustBeGreaterThanOrEqual(maxPoints, 2)} = 12000
end
if size(signal, 1) ~= numel(time)
    error('LFP:DisplayDimensionMismatch', 'TIME and SIGNAL must have the same number of rows.');
end
nSamples = numel(time);
if nSamples <= maxPoints
    displayTime = time;
    displaySignal = signal;
    info = struct('downsampled', false, 'inputRows', nSamples, ...
        'outputRows', nSamples, 'binSize', 1, 'method', "none");
    return;
end

binCount = max(1, floor(maxPoints / 2));
edges = unique(round(linspace(1, nSamples + 1, binCount + 1)));
binCount = numel(edges) - 1;
displayTime = NaN(2 * binCount, 1);
displaySignal = NaN(2 * binCount, size(signal, 2));
for binIndex = 1:binCount
    rows = edges(binIndex):(edges(binIndex + 1) - 1);
    t = time(rows);
    for channel = 1:size(signal, 2)
        values = signal(rows, channel);
        target = 2 * binIndex - 1;
        if any(~isfinite(values)) || any(~isfinite(t))
            displayTime(target:target + 1) = [t(1); t(end)];
            displaySignal(target:target + 1, channel) = NaN;
            continue;
        end
        [low, lowIndex] = min(values);
        [high, highIndex] = max(values);
        if lowIndex <= highIndex
            displayTime(target:target + 1) = [t(lowIndex); t(highIndex)];
            displaySignal(target:target + 1, channel) = [low; high];
        else
            displayTime(target:target + 1) = [t(highIndex); t(lowIndex)];
            displaySignal(target:target + 1, channel) = [high; low];
        end
    end
end
% All channels share one time vector. Rebuild it from bin centers if their
% extrema occurred at different samples; the min/max amplitudes are still
% preserved and ordered within every bin.
for binIndex = 1:binCount
    target = 2 * binIndex - 1;
    rows = edges(binIndex):(edges(binIndex + 1) - 1);
    displayTime(target:target + 1) = [time(rows(1)); time(rows(end))];
end
info = struct('downsampled', true, 'inputRows', nSamples, ...
    'outputRows', numel(displayTime), 'binSize', ceil(nSamples / binCount), ...
    'method', "min_max_envelope");
end

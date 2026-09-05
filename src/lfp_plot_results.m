function figureHandle = lfp_plot_results(data, options)
%LFP_PLOT_RESULTS Plot raw signals, PSD/parameterization, and band powers.
%   FIGUREHANDLE = LFP_PLOT_RESULTS(DATA) creates a MATLAB figure without
%   changing DATA. Use Visible="off" for batch export or tests.

arguments
    data (1,1) struct
    options.Visible (1,1) string {mustBeMember(options.Visible, ["on", "off"])} = "on"
    options.ChannelIndex double {mustBeInteger, mustBePositive} = []
    options.MaxPlotSeconds (1,1) double {mustBeFinite, mustBePositive} = 30
end

if ~isfield(data, 'signal') || ~isfield(data, 'fs')
    error('LFP:InvalidData', 'DATA.signal and DATA.fs are required.');
end
[nSamples, nChannels] = size(data.signal);
if isempty(options.ChannelIndex)
    channels = 1:nChannels;
else
    channels = unique(options.ChannelIndex(:)');
    if any(channels > nChannels)
        error('LFP:InvalidChannelIndex', 'ChannelIndex exceeds the number of channels.');
    end
end
time = (0:nSamples-1)' / data.fs;
sampleLimit = min(nSamples, max(1, round(options.MaxPlotSeconds * data.fs)));

figureHandle = figure('Visible', char(options.Visible), 'Color', 'w', ...
    'Name', 'SceneRay LFP analysis', 'NumberTitle', 'off');
tiledlayout(4, 1, 'TileSpacing', 'compact');
nexttile;
plot(time(1:sampleLimit), data.signal(1:sampleLimit, channels), 'LineWidth', 0.8);
xlabel('Time (s)'); ylabel("Signal (" + string(data.units) + ")");
title('Raw LFP and detected artifacts'); grid on;
if isfield(data, 'artifacts') && isfield(data.artifacts, 'channelMask')
    hold on;
    artifact = any(data.artifacts.channelMask(1:sampleLimit, channels), 2);
    plot(time(1:sampleLimit), nanmax(data.signal(1:sampleLimit, channels), [], 2) .* artifact, ...
        'r.', 'MarkerSize', 5);
    hold off;
end
legend(channel_labels(data, channels), 'Interpreter', 'none', 'Location', 'best');

nexttile;
if isfield(data, 'spectrum')
    frequencyHz = data.spectrum.frequencyHz;
    semilogy(frequencyHz, data.spectrum.psd(:, channels), 'LineWidth', 0.9); hold on;
    if isfield(data, 'spectralParameters')
        semilogy(frequencyHz, data.spectralParameters.aperiodicPsd(:, channels), '--', 'LineWidth', 1.0);
    end
    if isfield(data.spectrum, 'lineNoise')
        xline(data.spectrum.lineNoise.harmonicCentersHz, ':', 'Color', [0.5 0.5 0.5]);
    end
    hold off; xlim([max(0, frequencyHz(1)), frequencyHz(end)]);
    xlabel('Frequency (Hz)'); ylabel('Power (units^2/Hz)');
    title('Power spectral density (40-Hz harmonics retained)'); grid on;
else
    text(0.1, 0.5, 'Run lfp_compute_psd to display the spectrum.'); axis off;
end

nexttile;
if isfield(data, 'bandPower') && isfield(data.bandPower, 'table')
    resultTable = data.bandPower.table;
    selected = ismember(resultTable.channelIndex, channels);
    plotTable = resultTable(selected, :);
    names = unique(plotTable.band, 'stable');
    values = NaN(numel(names), numel(channels));
    for bandIndex = 1:numel(names)
        for channelIndex = 1:numel(channels)
            row = plotTable.band == names(bandIndex) & plotTable.channelIndex == channels(channelIndex);
            if any(row), values(bandIndex, channelIndex) = plotTable.totalPower(find(row, 1)); end
        end
    end
    bar(categorical(names), values); ylabel('Total power (units^2)');
    title('Band power'); grid on; legend(channel_labels(data, channels), 'Interpreter', 'none', 'Location', 'best');
else
    text(0.1, 0.5, 'Run lfp_compute_band_power to display band powers.'); axis off;
end

nexttile;
if isfield(data, 'timeFrequency')
    channel = channels(1);
    imagesc(data.timeFrequency.timeSeconds, data.timeFrequency.frequencyHz, ...
        10*log10(max(data.timeFrequency.power(:, :, channel), realmin)));
    axis xy; xlabel('Time (s)'); ylabel('Frequency (Hz)'); colorbar;
    title('Time-frequency power (channel ' + string(channel) + ')');
else
    text(0.1, 0.5, 'Run lfp_compute_time_frequency to display the STFT.'); axis off;
end
end

function labels = channel_labels(data, channels)
labels = strings(1, numel(channels));
for index = 1:numel(channels)
    if isfield(data, 'channelLabels') && numel(data.channelLabels) >= channels(index)
        labels(index) = string(data.channelLabels(channels(index)));
    else
        labels(index) = "channel_" + channels(index);
    end
end
end

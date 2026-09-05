function results = analyze_lfp_csv(filePath, varargin)
%ANALYZE_LFP_CSV Read an intracranial LFP CSV and export analysis results.
%
% results = analyze_lfp_csv(filePath)
% results = analyze_lfp_csv(filePath, 'SamplingRate', 1000, ...)
%
% The raw waveform is never filtered. PSD and band powers are calculated
% from a separate analysis signal after mean removal and optional high-pass
% and line-noise filtering.
%
% Required toolbox: Signal Processing Toolbox (butter, filtfilt, hann,
% iirnotch). Welch PSD is implemented explicitly so contaminated windows
% can be excluded instead of silently contributing broadband power.

    narginchk(1, inf);

    parser = inputParser;
    parser.FunctionName = mfilename;
    addRequired(parser, 'filePath', @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(parser, 'SamplingRate', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(parser, 'HighpassHz', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(parser, 'LineNoiseHz', 50, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(parser, 'NotchBandwidthHz', 2, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(parser, 'WindowSeconds', 4, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(parser, 'OverlapFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
    addParameter(parser, 'ArtifactRejection', true, @(x) islogical(x) && isscalar(x));
    addParameter(parser, 'ArtifactAmplitudeMAD', 8, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(parser, 'ArtifactDerivativeMAD', 8, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(parser, 'ArtifactAbsoluteThreshold_uV', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(parser, 'ArtifactPaddingSeconds', 1, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(parser, 'MaxArtifactFractionPerWindow', 0.01, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
    addParameter(parser, 'MinCleanWindows', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1 && mod(x, 1) == 0);
    addParameter(parser, 'PSDMaxHz', 100, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(parser, 'TotalPowerRangeHz', [1 100], @(x) isnumeric(x) && numel(x) == 2 && x(1) >= 0 && x(2) > x(1));
    addParameter(parser, 'Bands', defaultBands(), @isValidBands);
    addParameter(parser, 'PreviewSeconds', 10, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(parser, 'OutputDirectory', "", @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(parser, 'SaveOutputs', true, @(x) islogical(x) && isscalar(x));
    addParameter(parser, 'CreateFigures', true, @(x) islogical(x) && isscalar(x));
    addParameter(parser, 'FigureVisible', 'on', @(x) any(strcmpi(string(x), ["on", "off"])));
    parse(parser, filePath, varargin{:});
    opt = parser.Results;
    filePath = char(string(filePath));

    if ~isfile(filePath)
        error('LFP:FileNotFound', 'CSV file not found: %s', filePath);
    end
    assertSignalToolboxFunctions();

    [metadata, sampleIndex, voltage_uV, tagCode] = readLfpCsv(filePath);
    nSamples = numel(voltage_uV);
    if nSamples < 16
        error('LFP:TooFewSamples', 'At least 16 numeric samples are required.');
    end

    missingMask = ~isfinite(voltage_uV);
    if all(missingMask)
        error('LFP:NoNumericVoltage', 'No valid numeric voltage samples were found.');
    elseif any(missingMask)
        voltage_uV = fillmissing(voltage_uV, 'linear', 'EndValues', 'nearest');
        warning('LFP:MissingVoltage', '%d missing voltage samples were interpolated.', nnz(missingMask));
    end

    [fs, fsSource, fsEstimate] = resolveSamplingRate(opt.SamplingRate, metadata, nSamples);
    if any(diff(sampleIndex) ~= 1)
        warning('LFP:NonSequentialIndex', 'Time Index is not fully sequential; time is based on sample order and Fs.');
    end
    time_s = (0:nSamples-1)' ./ fs;

    if opt.HighpassHz >= fs / 2
        error('LFP:InvalidHighpass', 'HighpassHz must be below Nyquist frequency (%.3f Hz).', fs / 2);
    end
    if ~isempty(opt.LineNoiseHz) && opt.LineNoiseHz >= fs / 2
        warning('LFP:NotchSkipped', 'LineNoiseHz is at or above Nyquist; notch filtering was skipped.');
        opt.LineNoiseHz = [];
    end

    analysis_uV = detrend(voltage_uV, 'constant');
    preprocessing = "mean removed";
    if opt.HighpassHz > 0
        [bHigh, aHigh] = butter(4, opt.HighpassHz / (fs / 2), 'high');
        analysis_uV = filtfilt(bHigh, aHigh, analysis_uV);
        preprocessing = preprocessing + sprintf(', %.3g Hz high-pass', opt.HighpassHz);
    end
    if ~isempty(opt.LineNoiseHz)
        wo = opt.LineNoiseHz / (fs / 2);
        bw = opt.NotchBandwidthHz / (fs / 2);
        [bNotch, aNotch] = iirnotch(wo, bw);
        analysis_uV = filtfilt(bNotch, aNotch, analysis_uV);
        preprocessing = preprocessing + sprintf(', %.3g Hz notch (BW %.3g Hz)', ...
            opt.LineNoiseHz, opt.NotchBandwidthHz);
    end

    rawMin = min(voltage_uV);
    rawMax = max(voltage_uV);
    minHitPercent = 100 * nnz(voltage_uV == rawMin) / nSamples;
    maxHitPercent = 100 * nnz(voltage_uV == rawMax) / nSamples;

    windowSamples = min(nSamples, max(16, round(opt.WindowSeconds * fs)));
    overlapSamples = min(windowSamples - 1, round(opt.OverlapFraction * windowSamples));
    nfft = max(windowSamples, 2 ^ nextpow2(windowSamples));
    window = hann(windowSamples, 'periodic');
    [artifactMask, artifactInfo] = detectArtifacts(voltage_uV, fs, opt, ...
        minHitPercent, maxHitPercent);
    [psd_uV2_per_Hz, frequency_Hz, psdWindowTable] = ...
        calculateRejectedWindowWelch(analysis_uV, artifactMask, fs, window, ...
        overlapSamples, nfft, opt);
    acceptedWindows = nnz(psdWindowTable.Accepted);
    totalWindows = height(psdWindowTable);
    rejectedWindows = totalWindows - acceptedWindows;
    artifactSamplePercent = 100 * nnz(artifactMask) / nSamples;

    bands = normalizeBands(opt.Bands);
    bandPowerTable = calculateBandPowers(frequency_Hz, psd_uV2_per_Hz, ...
        bands, opt.TotalPowerRangeHz, fs);

    signalMetrics = table( ...
        ["Sample count"; "Duration"; "Raw mean"; "Raw standard deviation"; ...
         "Raw RMS"; "Raw minimum"; "Raw maximum"; "Raw peak-to-peak"; ...
         "Analysis RMS"; "Input non-finite samples"; ...
         "Samples at observed minimum"; "Samples at observed maximum"; ...
         "Artifact-marked samples"; "PSD windows total"; ...
         "PSD windows accepted"; "PSD windows rejected"], ...
        [nSamples; nSamples/fs; mean(voltage_uV); std(voltage_uV); ...
         rms(voltage_uV); rawMin; rawMax; range(voltage_uV); ...
         rms(analysis_uV); nnz(missingMask); minHitPercent; maxHitPercent; ...
         artifactSamplePercent; totalWindows; acceptedWindows; rejectedWindows], ...
        ["samples"; "s"; "uV"; "uV"; "uV"; "uV"; "uV"; "uV"; "uV"; ...
         "samples"; "%"; "%"; "%"; "windows"; "windows"; "windows"], ...
        'VariableNames', {'Metric', 'Value', 'Unit'});

    qualityFlags = strings(0, 1);
    if minHitPercent > 0.1 || maxHitPercent > 0.1
        qualityFlags(end+1, 1) = sprintf([ ...
            'Potential clipping/rail contact: %.4g%% of samples equal the observed minimum ' ...
            'and %.4g%% equal the observed maximum. Review the raw waveform before interpretation.'], ...
            minHitPercent, maxHitPercent);
    end
    if any(missingMask)
        qualityFlags(end+1, 1) = sprintf('%d non-finite voltage samples were interpolated.', nnz(missingMask));
    end
    if opt.ArtifactRejection && rejectedWindows > 0
        qualityFlags(end+1, 1) = sprintf([ ...
            'Artifact rejection excluded %d/%d PSD windows (%.3g%%). ' ...
            'Band powers use only the %d accepted windows.'], ...
            rejectedWindows, totalWindows, 100*rejectedWindows/totalWindows, acceptedWindows);
    end

    metadata.SamplingRate_Hz = fs;
    metadata.SamplingRateSource = fsSource;
    metadata.SamplingRateEstimate_Hz = fsEstimate;
    metadata.SampleCount = nSamples;
    metadata.FirstTimeIndex = sampleIndex(1);
    metadata.LastTimeIndex = sampleIndex(end);
    metadata.ActualDuration_s = nSamples / fs;
    metadata.PreprocessingForPSD = char(preprocessing);
    metadata.ArtifactRejectionEnabled = opt.ArtifactRejection;
    metadata.PSDWindowsAccepted = acceptedWindows;
    metadata.PSDWindowsRejected = rejectedWindows;
    metadata.InputFile = filePath;

    results = struct();
    results.Metadata = metadata;
    results.SampleIndex = sampleIndex;
    results.Time_s = time_s;
    results.RawVoltage_uV = voltage_uV;
    results.AnalysisVoltage_uV = analysis_uV;
    results.ArtifactMask = artifactMask;
    results.ArtifactInfo = artifactInfo;
    results.PSDWindows = psdWindowTable;
    results.TagCode = tagCode;
    results.Frequency_Hz = frequency_Hz;
    results.PSD_uV2_per_Hz = psd_uV2_per_Hz;
    results.BandPower = bandPowerTable;
    results.SignalMetrics = signalMetrics;
    results.QualityFlags = table(qualityFlags, 'VariableNames', {'Flag'});
    results.Options = opt;
    results.Figures = gobjects(0);
    results.OutputFiles = struct();

    if opt.CreateFigures
        results.Figures = createFigures(results, opt);
    end

    if opt.SaveOutputs
        [inputDir, inputStem] = fileparts(filePath);
        outputDir = char(string(opt.OutputDirectory));
        if isempty(outputDir)
            outputDir = fullfile(inputDir, [inputStem, '_results']);
        end
        if ~isfolder(outputDir)
            mkdir(outputDir);
        end
        results.OutputFiles = saveResults(results, outputDir, inputStem);
    end
end

function bands = defaultBands()
    bands = table( ...
        ["Delta"; "Theta"; "Alpha"; "Beta"; "LowGamma"; "HighGamma"], ...
        [1; 4; 8; 13; 30; 65], ...
        [4; 8; 13; 30; 55; 100], ...
        'VariableNames', {'Band', 'Low_Hz', 'High_Hz'});
end

function tf = isValidBands(x)
    tf = istable(x) || (iscell(x) && size(x, 2) == 3) || ...
        (isnumeric(x) && size(x, 2) == 2);
end

function bands = normalizeBands(inputBands)
    if istable(inputBands)
        required = {'Band', 'Low_Hz', 'High_Hz'};
        if ~all(ismember(required, inputBands.Properties.VariableNames))
            error('LFP:InvalidBands', 'Band table must contain Band, Low_Hz, and High_Hz.');
        end
        bands = inputBands(:, required);
        bands.Band = string(bands.Band);
    elseif iscell(inputBands)
        bands = table(string(inputBands(:, 1)), cell2mat(inputBands(:, 2)), ...
            cell2mat(inputBands(:, 3)), ...
            'VariableNames', {'Band', 'Low_Hz', 'High_Hz'});
    else
        names = "Band" + (1:size(inputBands, 1))';
        bands = table(names, inputBands(:, 1), inputBands(:, 2), ...
            'VariableNames', {'Band', 'Low_Hz', 'High_Hz'});
    end
    if any(~isfinite(bands.Low_Hz)) || any(~isfinite(bands.High_Hz)) || ...
            any(bands.Low_Hz < 0) || any(bands.High_Hz <= bands.Low_Hz)
        error('LFP:InvalidBands', 'Each band must have finite limits with 0 <= Low_Hz < High_Hz.');
    end
end

function assertSignalToolboxFunctions()
    required = {'butter', 'filtfilt', 'hann', 'iirnotch'};
    missing = required(cellfun(@(f) exist(f, 'file') == 0, required));
    if ~isempty(missing)
        error('LFP:MissingToolbox', ...
            'Signal Processing Toolbox functions are missing: %s', strjoin(missing, ', '));
    end
end

function [artifactMask, info] = detectArtifacts(raw_uV, fs, opt, minHitPercent, maxHitPercent)
    n = numel(raw_uV);
    amplitudeCenter = median(raw_uV, 'omitnan');
    amplitudeScale = robustStd(raw_uV);
    derivative = [0; diff(raw_uV)];
    derivativeCenter = median(derivative, 'omitnan');
    derivativeScale = robustStd(derivative);

    amplitudeThreshold_uV = opt.ArtifactAmplitudeMAD * amplitudeScale;
    derivativeThreshold_uV_perSample = opt.ArtifactDerivativeMAD * derivativeScale;
    amplitudeMask = abs(raw_uV - amplitudeCenter) > amplitudeThreshold_uV;
    derivativeMask = abs(derivative - derivativeCenter) > derivativeThreshold_uV_perSample;

    absoluteMask = false(n, 1);
    if ~isempty(opt.ArtifactAbsoluteThreshold_uV)
        absoluteMask = abs(raw_uV) > opt.ArtifactAbsoluteThreshold_uV;
    end

    railMask = false(n, 1);
    if minHitPercent > 0.1
        railMask = railMask | raw_uV == min(raw_uV);
    end
    if maxHitPercent > 0.1
        railMask = railMask | raw_uV == max(raw_uV);
    end

    baseMask = amplitudeMask | derivativeMask | absoluteMask | railMask | ~isfinite(raw_uV);
    if opt.ArtifactRejection
        paddingSamples = round(opt.ArtifactPaddingSeconds * fs);
        if paddingSamples > 0 && any(baseMask)
            artifactMask = movmax(baseMask, [paddingSamples paddingSamples]) > 0;
        else
            artifactMask = baseMask;
        end
    else
        artifactMask = false(n, 1);
        paddingSamples = 0;
    end

    info = struct();
    info.Enabled = opt.ArtifactRejection;
    info.AmplitudeCenter_uV = amplitudeCenter;
    info.AmplitudeRobustSD_uV = amplitudeScale;
    info.AmplitudeThresholdFromCenter_uV = amplitudeThreshold_uV;
    info.DerivativeCenter_uV_perSample = derivativeCenter;
    info.DerivativeRobustSD_uV_perSample = derivativeScale;
    info.DerivativeThresholdFromCenter_uV_perSample = derivativeThreshold_uV_perSample;
    info.AbsoluteThreshold_uV = opt.ArtifactAbsoluteThreshold_uV;
    info.PaddingSamples = paddingSamples;
    info.PaddingSeconds = paddingSamples / fs;
    info.BaseArtifactSamples = nnz(baseMask);
    info.PaddedArtifactSamples = nnz(artifactMask);
end

function value = robustStd(x)
    center = median(x, 'omitnan');
    value = 1.4826 * median(abs(x - center), 'omitnan');
    if ~isfinite(value) || value <= eps(max(abs(center), 1))
        value = std(x, 'omitnan');
    end
    if ~isfinite(value) || value <= 0
        value = eps;
    end
end

function [pxx, f, windowTable] = calculateRejectedWindowWelch( ...
        signal, artifactMask, fs, window, overlapSamples, nfft, opt)
    windowSamples = numel(window);
    stepSamples = windowSamples - overlapSamples;
    starts = (1:stepSamples:(numel(signal) - windowSamples + 1))';
    if isempty(starts)
        error('LFP:NoPsdWindows', 'The signal is shorter than one PSD window.');
    end
    ends = starts + windowSamples - 1;
    artifactFraction = zeros(numel(starts), 1);
    for k = 1:numel(starts)
        artifactFraction(k) = mean(artifactMask(starts(k):ends(k)));
    end
    accepted = artifactFraction <= opt.MaxArtifactFractionPerWindow;
    if ~opt.ArtifactRejection
        accepted(:) = true;
    end
    if nnz(accepted) < opt.MinCleanWindows
        error('LFP:TooFewCleanWindows', [ ...
            'Only %d clean PSD windows remain (minimum %d). Review the raw signal or adjust ' ...
            'ArtifactAmplitudeMAD, ArtifactDerivativeMAD, ArtifactPaddingSeconds, ' ...
            'MaxArtifactFractionPerWindow, or disable ArtifactRejection explicitly.'], ...
            nnz(accepted), opt.MinCleanWindows);
    end

    nFrequencyBins = floor(nfft / 2) + 1;
    pxx = zeros(nFrequencyBins, 1);
    normalization = fs * sum(window .^ 2);
    acceptedIndexes = find(accepted);
    for k = 1:numel(acceptedIndexes)
        w = acceptedIndexes(k);
        segment = signal(starts(w):ends(w));
        segment = detrend(segment, 'constant') .* window;
        spectrum = fft(segment, nfft);
        oneSided = abs(spectrum(1:nFrequencyBins)) .^ 2 / normalization;
        if rem(nfft, 2) == 0
            oneSided(2:end-1) = 2 * oneSided(2:end-1);
        else
            oneSided(2:end) = 2 * oneSided(2:end);
        end
        pxx = pxx + oneSided;
    end
    pxx = pxx / numel(acceptedIndexes);
    f = (0:nFrequencyBins-1)' * (fs / nfft);

    windowTable = table((1:numel(starts))', starts, ends, ...
        (starts - 1) / fs, ends / fs, artifactFraction, accepted, ...
        'VariableNames', {'Window', 'StartSample', 'EndSample', ...
        'StartTime_s', 'EndTime_s', 'ArtifactFraction', 'Accepted'});
end

function [metadata, sampleIndex, voltage_uV, tagCode] = readLfpCsv(filePath)
    fid = fopen(filePath, 'r');
    if fid < 0
        error('LFP:OpenFailed', 'Cannot open CSV file: %s', filePath);
    end
    cleaner = onCleanup(@() fclose(fid));

    metadata = struct('DeviceType', '', 'IPGSN', '', 'ChannelRaw', '', ...
        'ChannelLabel', '', 'Contact1', NaN, 'Contact2', NaN, ...
        'AcquisitionMode', '', 'CollectTime_s', NaN, 'Gain', NaN);
    headerFound = false;
    maxHeaderLines = 100;
    for lineNumber = 1:maxHeaderLines
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end
        fields = strsplit(line, ',', 'CollapseDelimiters', false);
        key = strtrim(fields{1});
        normalizedKey = lower(regexprep(key, '\s+', ''));
        if strcmp(normalizedKey, 'timeindex')
            headerFound = true;
            break;
        end
        values = string(fields(2:end));
        values = strtrim(values);
        values(values == "") = [];
        switch normalizedKey
            case 'devicetype'
                if ~isempty(values), metadata.DeviceType = char(values(1)); end
            case 'ipgsn'
                if ~isempty(values), metadata.IPGSN = char(values(1)); end
            case 'channel'
                if ~isempty(values), metadata.ChannelRaw = char(values(1)); end
            case 'collecttime'
                metadata.CollectTime_s = parseCollectTime(line);
            case 'gain'
                if ~isempty(values), metadata.Gain = str2double(values(1)); end
        end
    end
    if ~headerFound
        error('LFP:HeaderNotFound', 'Could not find the Time Index data header.');
    end

    parsed = textscan(fid, '%f%f%q%*[^\n]', 'Delimiter', ',', ...
        'MultipleDelimsAsOne', false, 'ReturnOnError', false);
    sampleIndex = parsed{1};
    voltage_uV = parsed{2};
    tagCode = string(parsed{3});
    if numel(tagCode) < numel(voltage_uV)
        tagCode(end+1:numel(voltage_uV), 1) = "";
    elseif numel(tagCode) > numel(voltage_uV)
        tagCode = tagCode(1:numel(voltage_uV));
    end

    metadata.ChannelLabel = strrep(metadata.ChannelRaw, '~', '-');
    tokens = regexp(metadata.ChannelRaw, '(\d+)\s*[~-]\s*(\d+)', 'tokens', 'once');
    if ~isempty(tokens)
        metadata.Contact1 = str2double(tokens{1});
        metadata.Contact2 = str2double(tokens{2});
        metadata.AcquisitionMode = 'bipolar';
    end
    clear cleaner;
end

function seconds = parseCollectTime(line)
    seconds = NaN;
    h = regexp(line, '(\d+)\s*h', 'tokens', 'once');
    m = regexp(line, '(\d+)\s*m', 'tokens', 'once');
    s = regexp(line, '(\d+(?:\.\d+)?)\s*s', 'tokens', 'once');
    if ~isempty(h) || ~isempty(m) || ~isempty(s)
        hv = 0; mv = 0; sv = 0;
        if ~isempty(h), hv = str2double(h{1}); end
        if ~isempty(m), mv = str2double(m{1}); end
        if ~isempty(s), sv = str2double(s{1}); end
        seconds = hv * 3600 + mv * 60 + sv;
    end
end

function [fs, source, estimate] = resolveSamplingRate(userFs, metadata, nSamples)
    estimate = NaN;
    if ~isempty(userFs)
        fs = double(userFs);
        source = 'user supplied';
        if isfinite(metadata.CollectTime_s) && metadata.CollectTime_s > 0
            estimate = nSamples / metadata.CollectTime_s;
        end
        return;
    end
    if isfinite(metadata.CollectTime_s) && metadata.CollectTime_s > 0
        estimate = nSamples / metadata.CollectTime_s;
        nearestInteger = round(estimate);
        if abs(estimate - nearestInteger) / estimate <= 0.01
            fs = nearestInteger;
            source = 'inferred from sample count and Collect Time, rounded to integer';
        else
            fs = estimate;
            source = 'inferred from sample count and Collect Time';
        end
    else
        error('LFP:SamplingRateUnknown', ...
            'Sampling rate is absent from the CSV. Supply it with ''SamplingRate'', Fs.');
    end
end

function output = calculateBandPowers(f, pxx, bands, totalRange, fs)
    nyquist = fs / 2;
    totalUpper = min(totalRange(2), nyquist);
    totalMask = f >= totalRange(1) & f <= totalUpper;
    if nnz(totalMask) < 2
        error('LFP:InvalidTotalRange', 'TotalPowerRangeHz does not contain enough PSD bins.');
    end
    totalPower = trapz(f(totalMask), pxx(totalMask));

    n = height(bands);
    absolutePower = nan(n, 1);
    relativePower = nan(n, 1);
    powerDb = nan(n, 1);
    peakFrequency = nan(n, 1);
    peakPsd = nan(n, 1);
    available = false(n, 1);
    for k = 1:n
        upper = min(bands.High_Hz(k), nyquist);
        mask = f >= bands.Low_Hz(k) & f <= upper;
        if upper > bands.Low_Hz(k) && nnz(mask) >= 2
            absolutePower(k) = trapz(f(mask), pxx(mask));
            relativePower(k) = 100 * absolutePower(k) / totalPower;
            powerDb(k) = 10 * log10(max(absolutePower(k), realmin));
            [peakPsd(k), localIndex] = max(pxx(mask));
            localF = f(mask);
            peakFrequency(k) = localF(localIndex);
            available(k) = true;
        end
    end
    output = table(bands.Band, bands.Low_Hz, bands.High_Hz, available, ...
        absolutePower, relativePower, powerDb, peakFrequency, peakPsd, ...
        'VariableNames', {'Band', 'Low_Hz', 'High_Hz', 'Available', ...
        'AbsolutePower_uV2', 'RelativePower_percent', 'Power_dB_re_1uV2', ...
        'PeakFrequency_Hz', 'PeakPSD_uV2_per_Hz'});
end

function figures = createFigures(results, opt)
    meta = results.Metadata;
    channelText = meta.ChannelLabel;
    if isempty(channelText), channelText = 'unknown'; end
    identity = sprintf('IPG %s | Ch %s | Fs %.6g Hz', meta.IPGSN, channelText, meta.SamplingRate_Hz);
    visible = char(string(opt.FigureVisible));
    blue = [0.12 0.35 0.62];
    artifactOrange = [0.85 0.33 0.10];
    charcoal = [0.15 0.17 0.20];

    rawFig = figure('Name', 'Raw LFP waveform', 'Color', 'w', 'Visible', visible);
    tiledlayout(rawFig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    nexttile;
    rawLine = plot(results.Time_s, results.RawVoltage_uV, 'Color', blue, 'LineWidth', 0.65);
    hold on;
    artifactVoltage = results.RawVoltage_uV;
    artifactVoltage(~results.ArtifactMask) = NaN;
    artifactLine = plot(results.Time_s, artifactVoltage, 'Color', artifactOrange, 'LineWidth', 0.8);
    hold off;
    grid on; box off;
    xlabel('Time (s)'); ylabel('Voltage (\muV)');
    title('Raw LFP waveform'); subtitle(identity, 'Interpreter', 'none');
    if any(results.ArtifactMask)
        legend([rawLine artifactLine], {'Raw signal', 'Artifact-rejected region'}, ...
            'Location', 'best', 'Box', 'off');
    end
    nexttile;
    previewMask = results.Time_s <= min(opt.PreviewSeconds, results.Time_s(end));
    plot(results.Time_s(previewMask), results.RawVoltage_uV(previewMask), ...
        'Color', blue, 'LineWidth', 0.8);
    hold on;
    plot(results.Time_s(previewMask), artifactVoltage(previewMask), ...
        'Color', artifactOrange, 'LineWidth', 0.9);
    hold off;
    grid on; box off;
    xlabel('Time (s)'); ylabel('Voltage (\muV)');
    title(sprintf('Raw waveform preview (first %.3g s)', min(opt.PreviewSeconds, results.Time_s(end))));

    psdFig = figure('Name', 'LFP PSD', 'Color', 'w', 'Visible', visible);
    maxHz = min([opt.PSDMaxHz, meta.SamplingRate_Hz/2, max(results.Frequency_Hz)]);
    showMask = results.Frequency_Hz >= 0.5 & results.Frequency_Hz <= maxHz;
    plot(results.Frequency_Hz(showMask), ...
        10*log10(max(results.PSD_uV2_per_Hz(showMask), realmin)), ...
        'Color', blue, 'LineWidth', 1.15);
    grid on; box off; xlim([0.5 maxHz]);
    xlabel('Frequency (Hz)'); ylabel('PSD (dB re 1 \muV^2/Hz)');
    title('Power spectral density (Welch method)');
    subtitle(sprintf('%s | Clean windows %d/%d', ...
        identity, meta.PSDWindowsAccepted, ...
        meta.PSDWindowsAccepted + meta.PSDWindowsRejected), 'Interpreter', 'none');
    if ~isempty(opt.LineNoiseHz) && opt.LineNoiseHz <= maxHz
        xline(opt.LineNoiseHz, '--', 'Line noise', 'Color', [0.45 0.45 0.45]);
    end

    bandFig = figure('Name', 'LFP band powers', 'Color', 'w', 'Visible', visible);
    tiledlayout(bandFig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    valid = results.BandPower.Available;
    names = results.BandPower.Band(valid);
    nexttile;
    bar(1:nnz(valid), results.BandPower.AbsolutePower_uV2(valid), ...
        0.72, 'FaceColor', blue, 'EdgeColor', charcoal, 'LineWidth', 0.6);
    grid on; box off; xlim([0.25 nnz(valid)+0.75]);
    ax = gca; ax.YAxis.Exponent = 0; ytickformat('%.0f');
    set(gca, 'XTick', 1:nnz(valid), 'XTickLabel', names);
    ylabel('Power (\muV^2)'); title('Absolute band power');
    nexttile;
    bar(1:nnz(valid), results.BandPower.RelativePower_percent(valid), ...
        0.72, 'FaceColor', [0.78 0.56 0.16], 'EdgeColor', charcoal, 'LineWidth', 0.6);
    grid on; box off; xlim([0.25 nnz(valid)+0.75]);
    set(gca, 'XTick', 1:nnz(valid), 'XTickLabel', names);
    ylabel('Relative power (%)'); title(sprintf('Relative band power (denominator %.3g-%.3g Hz)', ...
        opt.TotalPowerRangeHz(1), min(opt.TotalPowerRangeHz(2), meta.SamplingRate_Hz/2)));
    xlabel('Frequency band');

    figures = [rawFig, psdFig, bandFig];
end

function files = saveResults(results, outputDir, inputStem)
    files = struct();
    files.OutputDirectory = outputDir;
    files.BandPowerCsv = fullfile(outputDir, [inputStem, '_band_power.csv']);
    files.SignalMetricsCsv = fullfile(outputDir, [inputStem, '_signal_metrics.csv']);
    files.MetadataCsv = fullfile(outputDir, [inputStem, '_metadata.csv']);
    files.QualityFlagsCsv = fullfile(outputDir, [inputStem, '_quality_flags.csv']);
    files.PsdWindowsCsv = fullfile(outputDir, [inputStem, '_psd_windows.csv']);
    files.PsdCsv = fullfile(outputDir, [inputStem, '_psd.csv']);
    files.MatFile = fullfile(outputDir, [inputStem, '_analysis.mat']);
    writetable(results.BandPower, files.BandPowerCsv);
    writetable(results.SignalMetrics, files.SignalMetricsCsv);
    writetable(results.QualityFlags, files.QualityFlagsCsv);
    writetable(results.PSDWindows, files.PsdWindowsCsv);
    writetable(table(results.Frequency_Hz, results.PSD_uV2_per_Hz, ...
        'VariableNames', {'Frequency_Hz', 'PSD_uV2_per_Hz'}), files.PsdCsv);

    metaNames = string(fieldnames(results.Metadata));
    metaValues = strings(numel(metaNames), 1);
    for k = 1:numel(metaNames)
        value = results.Metadata.(metaNames(k));
        metaValues(k) = string(value);
    end
    writetable(table(metaNames, metaValues, 'VariableNames', {'Field', 'Value'}), files.MetadataCsv);

    if ~isempty(results.Figures) && all(isgraphics(results.Figures))
        suffixes = {'_raw_waveform.png', '_psd.png', '_band_power.png'};
        figureFields = {'RawWaveformPng', 'PsdPng', 'BandPowerPng'};
        for k = 1:numel(results.Figures)
            files.(figureFields{k}) = fullfile(outputDir, [inputStem, suffixes{k}]);
            exportgraphics(results.Figures(k), files.(figureFields{k}), 'Resolution', 200);
        end
    end

    savedResults = results;
    savedResults.Figures = [];
    savedResults.OutputFiles = files;
    save(files.MatFile, 'savedResults', '-v7.3');
end

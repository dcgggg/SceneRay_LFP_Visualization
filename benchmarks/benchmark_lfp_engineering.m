function results = benchmark_lfp_engineering(options)
%BENCHMARK_LFP_ENGINEERING Reproducible import and analysis benchmark.
%   RESULTS = BENCHMARK_LFP_ENGINEERING() measures the documented small and
%   medium datasets. Set RunLarge=true to also materialize the 2-hour,
%   16-channel case (about 0.92 GB as MATLAB doubles before temporary
%   copies, and substantially larger as CSV). The benchmark never runs the
%   large case by default.

arguments
    options.RunMedium (1,1) logical = true
    options.RunLarge (1,1) logical = false
    options.RunAnalysis (1,1) logical = true
    options.OutputFolder (1,1) string = string(tempdir)
end

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
cleanupPath = onCleanup(@()rmpath(fullfile(projectRoot, 'src'))); %#ok<NASGU>
specifications = struct( ...
    'name', {"small", "medium", "large"}, ...
    'seconds', {10, 600, 7200}, ...
    'channels', {4, 8, 16}, ...
    'run', {true, options.RunMedium, options.RunLarge});
results = struct('name', {}, 'samples', {}, 'channels', {}, 'fileSizeBytes', {}, ...
    'estimatedArrayBytes', {}, 'inspectionSeconds', {}, 'importSeconds', {}, ...
    'dataVersionSeconds', {}, 'analysisSeconds', {}, 'status', {});

for caseIndex = 1:numel(specifications)
    spec = specifications(caseIndex);
    nSamples = spec.seconds * 1000;
    if ~spec.run
        results(end+1) = empty_result(spec.name, nSamples, spec.channels, "not run; opt in explicitly"); %#ok<AGROW>
        continue;
    end
    filename = fullfile(options.OutputFolder, "lfp_benchmark_" + spec.name + ".csv");
    cleanupFile = onCleanup(@()delete_if_present(filename));
    write_fixture(filename, nSamples, spec.channels);
    fileInfo = dir(filename);
    timer = tic; inspection = lfp_inspect_csv(filename); inspectionSeconds = toc(timer);
    timer = tic;
    data = lfp_import_csv_configured(filename, Inspection=inspection, HeaderRow=1, ...
        DataStartRow=2, TimeColumn=1, SignalColumns=2:(spec.channels+1), SamplingRateHz=1000);
    importSeconds = toc(timer);
    if size(data.signal, 1) ~= nSamples || size(data.signal, 2) ~= spec.channels
        error('LFP:BenchmarkImportMismatch', ...
            'Imported [%d %d], expected [%d %d].', size(data.signal,1), size(data.signal,2), nSamples, spec.channels);
    end
    timer = tic; lfp_data_version(data); dataVersionSeconds = toc(timer);
    analysisSeconds = NaN;
    if options.RunAnalysis
        cfg = lfpDefaultConfig(); cfg.psd.excludeArtifacts = false;
        artifact = struct('channelMask', false(size(data.signal)));
        timer = tic;
        psd = computeLfpPsd(data, artifact, cfg.psd);
        parameterizePowerSpectrum(psd.frequencyHz, psd.psd, cfg.fooof);
        analysisSeconds = toc(timer);
    end
    results(end+1) = struct('name', spec.name, 'samples', nSamples, 'channels', spec.channels, ...
        'fileSizeBytes', double(fileInfo.bytes), 'estimatedArrayBytes', 8*nSamples*(spec.channels+1), ...
        'inspectionSeconds', inspectionSeconds, 'importSeconds', importSeconds, ...
        'dataVersionSeconds', dataVersionSeconds, 'analysisSeconds', analysisSeconds, 'status', "completed"); %#ok<AGROW>
    clear cleanupFile;
end
disp(struct2table(results));
end

function result = empty_result(name, samples, channels, status)
result = struct('name', name, 'samples', samples, 'channels', channels, ...
    'fileSizeBytes', NaN, 'estimatedArrayBytes', 8*samples*(channels+1), ...
    'inspectionSeconds', NaN, 'importSeconds', NaN, 'dataVersionSeconds', NaN, ...
    'analysisSeconds', NaN, 'status', status);
end

function write_fixture(filename, nSamples, nChannels)
fs = 1000; time = (0:nSamples-1)'/fs;
signal = zeros(nSamples, nChannels);
for channel = 1:nChannels
    signal(:,channel) = sin(2*pi*(6+2*channel)*time) + 0.05*cos(2*pi*40*time);
end
header = [{'time_s'}, cellstr("channel_" + string(1:nChannels))];
writecell(header, filename);
writematrix([time signal], filename, 'WriteMode', 'append');
end

function delete_if_present(filename)
if isfile(filename), delete(filename); end
end

function tests = test_lfp_import_csv_configured
%TEST_LFP_IMPORT_CSV_CONFIGURED Test generic GUI-compatible CSV import.
tests = functiontests(localfunctions);
end

function testHeaderTimeAndMultipleSignals(testCase)
ensure_src_on_path(testCase);
filename = [tempname '.csv'];
cleanup = onCleanup(@() delete_if_exists(filename)); %#ok<NASGU>
fid = fopen(filename, 'w');
fprintf(fid, 'Time,ChA,ChB,Note\n');
for index = 0:99
    fprintf(fid, '%.6f,%.6f,%.6f,ok\n', index / 1000, sin(index), cos(index));
end
fclose(fid);

inspection = lfp_inspect_csv(filename);
verifyFalse(testCase, inspection.isSceneRay);
verifyEqual(testCase, inspection.headerRowSuggestion, 1);
verifyEqual(testCase, inspection.timeColumnSuggestion, 1);
verifyEqual(testCase, inspection.signalColumnsSuggestion, [2 3]);

[data, info] = lfp_import_csv_configured(filename);
verifyEqual(testCase, info.usedFormat, "generic");
verifySize(testCase, data.signal, [100 2]);
verifyEqual(testCase, data.fs, 1000, 'AbsTol', 1e-9);
verifyEqual(testCase, data.channelLabels, ["ChA" "ChB"]);
verifyTrue(testCase, data.metadata.timeValidation.valid);
verifyEqual(testCase, data.metadata.missingValueCount, 0);
end

function testNoHeaderRequiresConfirmedSamplingRate(testCase)
ensure_src_on_path(testCase);
filename = [tempname '.csv'];
cleanup = onCleanup(@() delete_if_exists(filename)); %#ok<NASGU>
writematrix([(1:20)' (21:40)'], filename);
verifyError(testCase, @() lfp_import_csv_configured(filename, TimeColumn=0, SignalColumns=[1 2]), 'LFP:SamplingRateRequired');
data = lfp_import_csv_configured(filename, TimeColumn=0, SignalColumns=[1 2], SamplingRateHz=500);
verifySize(testCase, data.signal, [20 2]);
verifyEqual(testCase, data.fs, 500);
end

function testChannelsBySamplesOrientation(testCase)
ensure_src_on_path(testCase);
filename = [tempname '.csv'];
cleanup = onCleanup(@() delete_if_exists(filename)); %#ok<NASGU>
writematrix([1:12; 21:32], filename);
data = lfp_import_csv_configured(filename, HeaderRow=0, DataStartRow=1, ...
    TimeColumn=0, SignalColumns=1:12, DataDirection="channels_by_samples", SamplingRateHz=1000);
verifySize(testCase, data.signal, [12 2]);
verifyEqual(testCase, data.signal(:, 1), (1:12)');
verifyEqual(testCase, data.signal(:, 2), (21:32)');
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

function delete_if_exists(filename)
if isfile(filename), delete(filename); end
end

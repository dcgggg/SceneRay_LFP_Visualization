function tests = test_lfp_import_scenray_csv
%TEST_LFP_IMPORT_SCENRAY_CSV Tests for the SceneRay CSV import layer.
tests = functiontests(localfunctions);
end

function testImportsMetadataAndSamples(testCase)
ensure_src_on_path(testCase);
filename = create_fixture(testCase, ["Device Type,WCH,"; ...
    "IPG SN,1010P26468,"; ...
    "Channel,5~6,"; ...
    "Collect Time,0h,0m,0.01s,"; ...
    "Gain,6,"; ...
    "Time Index, Voltage, Tag Code,"; ...
    "0, -1.5, A"; ...
    "1, 2.5, B"; ...
    "2, 0, " ]);

data = lfp_import_scenray_csv(filename);
verifyEqual(testCase, data.fs, 1000);
verifyEqual(testCase, data.units, "uV");
verifyEqual(testCase, data.channelLabels, "5-6");
verifyEqual(testCase, data.metadata.ipgSN, "1010P26468");
verifyEqual(testCase, data.metadata.contactIndices, {[5 6]});
verifyEqual(testCase, data.metadata.electrodeGroup, "contacts_4_7");
verifyEqual(testCase, data.metadata.collectTimeSeconds, 0.01, 'AbsTol', eps);
verifyEqual(testCase, data.signal, [-1.5; 2.5; 0]);
verifyEqual(testCase, data.time, [0; 0.001; 0.002], 'AbsTol', eps);
verifyEqual(testCase, data.metadata.tagCode, ["A"; "B"; ""]);
verifyEqual(testCase, data.processingHistory.operation, "import");
verifyEqual(testCase, data.metadata.importStrategy, "streamed_scenray");

% Small previews that reached EOF can still be reused without a second read.
inspection = lfp_inspect_csv(filename);
configured = lfp_import_csv_configured(filename, Inspection=inspection);
verifyEqual(testCase, configured.signal, data.signal);
verifyEqual(testCase, configured.channelLabels, data.channelLabels);
end

function testInvalidHeaderFails(testCase)
ensure_src_on_path(testCase);
filename = create_fixture(testCase, ["Channel,5~6,"; "Time Index,Current,"; "0,1,"]);
verifyError(testCase, @() lfp_import_scenray_csv(filename), 'LFP:MissingVoltageColumn');
end

function testCustomSamplingRateAndUnits(testCase)
ensure_src_on_path(testCase);
filename = create_fixture(testCase, ["Channel,0~1,"; "Time Index, Voltage,"; "0,1,"; "1,2,"]);
data = lfp_import_scenray_csv(filename, SamplingRateHz=2000, Units="mV");
verifyEqual(testCase, data.fs, 2000);
verifyEqual(testCase, data.units, "mV");
verifyEqual(testCase, data.time, [0; 0.0005], 'AbsTol', eps);
end

function testRepeatedBlocksBecomeChannels(testCase)
ensure_src_on_path(testCase);
filename = create_fixture(testCase, ["Device Type,WCH,"; ...
    "IPG SN,SN,"; "Channel,1~2,"; "Collect Time,0h,0m,0.002s,"; ...
    "Time Index, Voltage, Tag Code,"; "0,1,A"; "1,2,B"; ...
    "Device Type,WCH,"; "IPG SN,SN,"; "Channel,5~6,"; ...
    "Collect Time,0h,0m,0.002s,"; "Time Index, Voltage, Tag Code,"; ...
    "0,3,C"; "1,4,D"]);

data = lfp_import_scenray_csv(filename);
verifySize(testCase, data.signal, [2 2]);
verifyEqual(testCase, data.channelLabels, ["1-2", "5-6"]);
verifyEqual(testCase, data.signal, [1 3; 2 4]);
verifyEqual(testCase, data.metadata.blockCount, 2);
verifyEqual(testCase, data.metadata.channelCount, 2);
verifyEqual(testCase, data.channelCount, 2);
verifyEqual(testCase, data.channelNames, ["1-2", "5-6"]);
verifyEqual(testCase, data.metadata.contactIndices, {[1 2], [5 6]});
verifyEqual(testCase, data.metadata.tagCode, ["A", "C"; "B", "D"]);
end

function filename = create_fixture(testCase, lines)
filename = string(tempname) + ".csv";
fid = fopen(filename, 'w', 'n', 'UTF-8');
testCase.addTeardown(@() delete_if_exists(filename));
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
for index = 1:numel(lines)
    fprintf(fid, '%s\n', lines(index));
end
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

function delete_if_exists(filename)
if isfile(filename)
    delete(filename);
end
end

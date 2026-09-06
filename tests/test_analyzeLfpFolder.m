function tests = test_analyzeLfpFolder
%TEST_ANALYZELFPFOLDER Test one- and multi-channel folder processing.
tests = functiontests(localfunctions);
end

function testProcessesAllCsvFilesAndPreservesIdentity(testCase)
ensure_src_on_path(testCase);
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
filename = fullfile(folder, 'recording_A.csv');
fid = fopen(filename, 'w', 'n', 'UTF-8');
cleanupFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
lines = ["Device Type,WCH,"; "IPG SN,1010P26468,"; "Channel,1~2,"; ...
    "Time Index, Voltage, Tag Code,"];
for sample = 0:255
    lines(end + 1) = sprintf('%d,%g,A', sample, sin(2*pi*10*sample/1000)); %#ok<AGROW>
end
lines(end + 1:end + 4) = ["Device Type,WCH,"; "IPG SN,1010P26468,"; ...
    "Channel,5~6,"; "Time Index, Voltage, Tag Code,"];
for sample = 0:255
    lines(end + 1) = sprintf('%d,%g,B', sample, cos(2*pi*10*sample/1000)); %#ok<AGROW>
end
for index = 1:numel(lines), fprintf(fid, '%s\n', lines(index)); end
clear cleanupFile;

cfg = lfpDefaultConfig();
cfg.artifact.method = "native";
cfg.artifact.paddingSeconds = 0;
cfg.psd.windowLengthSec = 0.256;
cfg.psd.frequencyRange = [1 40];
cfg.fooof.frequencyRange = [1 40];
batch = analyzeLfpFolder(string(folder), cfg, OutputFolder=string(folder), MakeFigures=true);
verifyEqual(testCase, batch.fileCount, 1);
verifyEqual(testCase, batch.successfulCount, 1);
verifyEqual(testCase, batch.files(1).status, "ok");
verifyEqual(testCase, batch.files(1).channelCount, 2);
verifyEqual(testCase, batch.files(1).channelLabels, ["1-2", "5-6"]);
verifyEqual(testCase, batch.files(1).ipgSN, "1010P26468");
verifyEqual(testCase, batch.files(1).psdResult.channelLabels, ["1-2", "5-6"]);
verifyTrue(testCase, contains(batch.files(1).data.metadata.displayName, "1010P26468"));
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

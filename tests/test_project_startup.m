function tests = test_project_startup
%TEST_PROJECT_STARTUP Smoke tests for the non-analytical project entry point.
tests = functiontests(localfunctions);
end

function testStartupReturnsProjectMetadata(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
cleanup = onCleanup(@() rmpath(srcRoot)); %#ok<NASGU>

info = lfp_project_startup(projectRoot);
verifyEqual(testCase, string(info.projectRoot), string(projectRoot));
verifyEqual(testCase, string(info.minimumDesignedVersion), "R2022b");
verifyTrue(testCase, info.sourceOnPath);
verifyEqual(testCase, string(info.status), "initialized_only");
end

function testInvalidRootFails(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
cleanup = onCleanup(@() rmpath(srcRoot)); %#ok<NASGU>
verifyError(testCase, @() lfp_project_startup(fullfile(tempdir, 'not-a-real-lfp-project')), ...
    'LFP:InvalidProjectRoot');
end

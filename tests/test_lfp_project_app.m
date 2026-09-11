function tests = test_lfp_project_app
%TEST_LFP_PROJECT_APP Basic startup/close validation for project workspace.
tests = functiontests(localfunctions);
end

function testProjectWorkspaceStartsAndCloses(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(projectRoot, 'src'));
testCase.addTeardown(@() rmpath(fullfile(projectRoot, 'src')));
app = launchLfpProjectApp(Visible="off");
testCase.addTeardown(@() delete_if_valid(app));
verifyTrue(testCase, isgraphics(app.Figure));
verifyTrue(testCase, isgraphics(app.Controls.ProjectTree));
verifyTrue(testCase, isgraphics(app.Controls.CompareAxes));
app.close();
verifyFalse(testCase, isgraphics(app.Figure));
end

function delete_if_valid(app)
if ~isempty(app) && isvalid(app), app.delete(); end
end

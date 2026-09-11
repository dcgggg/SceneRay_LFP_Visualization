function tests = test_lfp_project_app
%TEST_LFP_PROJECT_APP Basic startup/close validation for project workspace.
tests = functiontests(localfunctions);
end

function testProjectWorkspaceStartsAndCloses(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(projectRoot, 'src'));
addpath(projectRoot);
testCase.addTeardown(@() rmpath(fullfile(projectRoot, 'src')));
testCase.addTeardown(@() rmpath(projectRoot));
app = launch_gui(Visible="off");
testCase.addTeardown(@() delete_if_valid(app));
verifyTrue(testCase, isgraphics(app.Figure));
verifyTrue(testCase, isgraphics(app.Controls.ProjectTree));
verifyTrue(testCase, isgraphics(app.Controls.CompareAxes));
verifyTrue(testCase, isgraphics(app.Controls.Welcome));
verifyEqual(testCase, string(app.Controls.PsdMethod.Value), "multitaper");
verifyEqual(testCase, app.Controls.PsdHigh.Value, 35);
verifyFalse(testCase, any(contains(string({app.Controls.WorkspaceTabs.Children.Title}), "时频")));
app.close();
verifyFalse(testCase, isgraphics(app.Figure));
end

function testProjectGuiEndToEndWithoutWorkspaceInputs(testCase)
projectRoot=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(projectRoot,'src'));
testCase.addTeardown(@()rmpath(fullfile(projectRoot,'src')));
root=string(tempname);mkdir(root);testCase.addTeardown(@()cleanup(root));
app=launchLfpProjectApp(Visible="off");testCase.addTeardown(@()delete_if_valid(app));
app.createProjectAt(root,"GUI E2E","no workspace variables");
app.Project.defaultConfig.artifact.strictMode=false;
app.addSubjectRecord(struct('subject_id',"P01",'display_name',"P01"));
app.addSessionRecord("P01",struct('session_id',"S01",'visit_label',"Baseline"));
app.attachDataToSession("S01",fixture_data(10,1));
first=app.runSelectedAnalysis();
verifyTrue(testCase,ismember(string(first.status),["ok" "partial_failure"]));
app.addSessionRecord("P01",struct('session_id',"S02",'visit_label',"Day07"));
app.attachDataToSession("S02",fixture_data(10,1.2));
second=app.runSelectedAnalysis();
verifyTrue(testCase,ismember(string(second.status),["ok" "partial_failure"]));
app.CompareSelectedSessionIds=["S01";"S02"];
app.Controls.MappingTable.Data={'S01','channel01','STN';'S02','channel01','STN'};
comparison=app.compareSelected(false);
verifyEqual(testCase,string(comparison.status),"ok");
verifyEqual(testCase,height(comparison.result_table),2);
snapshot=fullfile(root,'gui_snapshot.png');app.exportSnapshot(snapshot);verifyTrue(testCase,isfile(snapshot));
app.close(true);app=launchLfpProjectApp(Visible="off",ProjectRoot=root);
verifyEqual(testCase,numel(app.Project.subjects),1);
verifyEqual(testCase,numel(app.Project.subjects(1).sessions),2);
verifyEqual(testCase,numel(app.Project.analysisRuns),2);
verifyGreaterThanOrEqual(testCase,numel(app.Project.comparisons),1);
verifyEqual(testCase,app.CompareSelectedSessionIds,["S01";"S02"]);
verifyFalse(testCase,isempty(fieldnames(app.CurrentComparison)));
end

function data=fixture_data(seconds,scale)
fs=200;t=(0:1/fs:seconds-1/fs)';signal=scale.*[sin(2*pi*10*t),sin(2*pi*20*t)];
data=struct('signal',signal,'time',t,'fs',fs,'channelLabels',["channel01" "channel12"], ...
    'units',"uV",'metadata',struct('sourceFileName',"synthetic.csv"), ...
    'processingHistory',struct('operation',"test",'parameters',struct(),'notes',"GUI test"));
end

function cleanup(path)
if isfolder(path),rmdir(path,'s');end
end

function delete_if_valid(app)
if ~isempty(app) && isvalid(app), app.delete(); end
end

function tests = test_lfp_project_channel_workflow
tests = functiontests(localfunctions);
end

function testEnabledChannelPreviewUsesStableIds(testCase)
[app, projectRoot] = make_gui_with_channels();
cleanup = onCleanup(@()cleanup_gui(app, projectRoot)); %#ok<NASGU>
[session,~] = lfp_project_find_session(app.Project,"SE1");
ids = string({session.channels.channel_id})';
rows = table(ids([4 5]),false(2,1),'VariableNames',{'channel_id','enabled'});
[app.Project,~] = lfp_project_update_channels(app.Project,"SE1",rows,Save=false);
app.selectSession("SE1"); drawnow;
verifyEqual(testCase,numel(app.Controls.DataPreviewAxes),3);
verifyTrue(testCase,contains(string(app.Controls.DataPreviewInfo.Text),'3 个启用通道'));
verifyEqual(testCase,string(app.Controls.AnalysisEnabledCount.Text),string('启用 3 通道'));
end

function testBatchAnalysisUsesAllEnabledChannels(testCase)
[app, projectRoot] = make_gui_with_channels();
cleanup = onCleanup(@()cleanup_gui(app, projectRoot)); %#ok<NASGU>
[session,~] = lfp_project_find_session(app.Project,"SE1"); ids=string({session.channels.channel_id})';
[app.Project,~] = lfp_project_update_channels(app.Project,"SE1",table(ids([4 5]),false(2,1),'VariableNames',{'channel_id','enabled'}),Save=false);
app.Project.defaultConfig.artifact.strictMode=false; app.Controls.PsdWindow.Value=1; app.Controls.PsdHigh.Value=35;
app.Controls.ModuleSpecparam.Value=false; app.Controls.ModuleBand.Value=true; app.selectSession("SE1");
summary=app.runSelectedAnalysis(); drawnow;
verifyEqual(testCase,string(summary.status),string('ok'));
verifyEqual(testCase,numel(app.CurrentResults.channelResults),5);
active=app.CurrentResults.channelResults(ismember(string({app.CurrentResults.channelResults.status}),["ok" "partial_failure"]));
verifyEqual(testCase,numel(active),3);
validPsd=arrayfun(@(x)isstruct(x)&&isfield(x,'psdResult')&&isfield(x.psdResult,'psd'),active);
verifyEqual(testCase,nnz(validPsd),3);
app.Controls.AnalysisResultTabs.SelectedTab=app.Controls.PsdResultTab; cb=app.Controls.AnalysisResultTabs.SelectionChangedFcn; feval(cb,[],[]); drawnow;
verifyEqual(testCase,numel(app.Controls.PsdAxes.Children),3);
app.Controls.AnalysisResultTabs.SelectedTab=app.Controls.BandResultTab; feval(cb,[],[]); drawnow;
verifyEqual(testCase,numel(app.Controls.BandAxes),numel(unique(string(app.CurrentResults.channelResults(1).bandResult.table.band))));
end

function testChannelViewSelectionUsesEnabledStableId(testCase)
[app, projectRoot] = make_gui_with_channels();
cleanup = onCleanup(@()cleanup_gui(app, projectRoot)); %#ok<NASGU>
[session,~] = lfp_project_find_session(app.Project,"SE1"); ids=string({session.channels.channel_id})';
[app.Project,~] = lfp_project_update_channels(app.Project,"SE1",table(ids([1 2]),false(2,1),'VariableNames',{'channel_id','enabled'}),Save=false);
app.selectSession("SE1");
app.Controls.AnalysisChannel.Value='C';
cb=app.Controls.AnalysisChannel.ValueChangedFcn; feval(cb,[],[]);
verifyEqual(testCase,app.CurrentViewedChannelId,ids(3));
verifyEqual(testCase,app.CurrentChannelIndex,3);
end

function [app,root] = make_gui_with_channels()
root=string(tempname); mkdir(root);
projectRoot=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(projectRoot,'src'));
app=launchLfpProjectApp(Visible="off"); app.createProjectAt(root,"Workflow");
app.addSubjectRecord(struct('subject_id',"S1",'display_name',"S1")); app.addSessionRecord("S1",struct('session_id',"SE1",'visit_label',"Baseline"));
fs=200; t=(0:fs*4-1)'/fs; y=zeros(numel(t),5);
for k=1:5, y(:,k)=sin(2*pi*(4+k)*t); end
data=struct('time',t,'signal',y,'fs',fs,'channelLabels',string({'A','B','C','D','E'}),'units',"uV",'metadata',struct());
app.attachDataToSession("SE1",data);
end

function cleanup_gui(app,root)
try,if ~isempty(app)&&isvalid(app),app.close(true);end,catch,end
if isfolder(root),rmdir(root,'s');end
end

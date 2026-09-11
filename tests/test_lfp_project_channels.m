function tests = test_lfp_project_channels
%TEST_LFP_PROJECT_CHANNELS Channel-level import/cache regression tests.
tests = functiontests(localfunctions);
end

function testAppendIndependentChannelsAndCacheReload(testCase)
[project, sessionId, root] = make_project(); %#ok<ASGLU>
cleanup = onCleanup(@() cleanup_root(root));
fs = 1000; t = (0:1999)'/fs;
first = struct('time',t,'signal',[sin(2*pi*10*t),sin(2*pi*20*t)],'fs',fs, ...
    'channelLabels',["4-5" "6-7"],'units',"uV",'metadata',struct());
[project,~] = lfp_project_attach_data(project,sessionId,first,Save=false);
t2 = (0:1199)'/fs; second = struct('time',t2,'signal',sin(2*pi*8*t2),'fs',fs, ...
    'channelLabels',"8-9",'units',"uV",'metadata',struct());
[project,report] = lfp_project_append_data(project,sessionId,second,Save=false);
verifyEqual(testCase,numel(report.addedChannelIds),1);
[session,~] = lfp_project_find_session(project,sessionId);
verifyEqual(testCase,numel(session.channels),3);
verifyEqual(testCase,double([session.channels.sample_count]),[2000 2000 1200]);
[channel,~,~] = lfp_project_get_channel_data(project,sessionId,report.addedChannelIds(1));
verifyEqual(testCase,numel(channel.signal),1200);
verifyTrue(testCase,isfile(fullfile(root,session.channels(3).cache_relative_path)));
end

function testDuplicateSourceAndCorruptCacheAreExplicit(testCase)
[project, sessionId, root] = make_project(); cleanup = onCleanup(@() cleanup_root(root));
t=(0:999)'/1000; path=fullfile(root,'input.csv'); fid=fopen(path,'w');fprintf(fid,'x\n1\n');fclose(fid);
data=struct('time',t,'signal',randn(1000,1),'fs',1000,'channelLabels',"A",'units',"uV", ...
    'metadata',struct('sourceFilePath',string(path),'sourceFileName',"input.csv",'sourceColumns',1));
[project,~]=lfp_project_attach_data(project,sessionId,data,Save=false);
verifyError(testCase,@() lfp_project_append_data(project,sessionId,data,Save=false),'LFP:DuplicateChannelSource');
[session,~]=lfp_project_find_session(project,sessionId);cache=fullfile(root,session.channels(1).cache_relative_path);fid=fopen(cache,'w');fprintf(fid,'corrupt');fclose(fid);
verifyError(testCase,@() lfp_project_get_channel_data(project,sessionId,string(session.channels(1).channel_id)),'LFP:ChannelCacheCorrupt');
end

function testDisableAndRemoveKeepCache(testCase)
[project, sessionId, root] = make_project(); cleanup = onCleanup(@() cleanup_root(root));
t=(0:999)'/1000;data=struct('time',t,'signal',randn(1000,2),'fs',1000,'channelLabels',["A" "B"],'units',"uV",'metadata',struct());
[project,~]=lfp_project_attach_data(project,sessionId,data,Save=false);[session,~]=lfp_project_find_session(project,sessionId);cache=fullfile(root,session.channels(2).cache_relative_path);
ids=string(session.channels(2).channel_id);tbl=table(ids,'VariableNames',{'channel_id'});tbl.enabled=false;[project,~]=lfp_project_update_channels(project,sessionId,tbl,Save=false);
[session,~]=lfp_project_find_session(project,sessionId);verifyFalse(testCase,session.channels(2).enabled);
[project,~]=lfp_project_remove_channels(project,sessionId,ids,Save=false);[session,~]=lfp_project_find_session(project,sessionId);verifyEqual(testCase,numel(session.channels),1);verifyTrue(testCase,isfile(cache));
end

function testGuiImportBridgeAppendsWithoutReparsingOldChannels(testCase)
projectRoot=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(projectRoot,'src'));
root=string(tempname);mkdir(root);cleanup=onCleanup(@() cleanup_root(root));
app=launchLfpProjectApp(Visible="off");cleanupApp=onCleanup(@() delete_if_valid(app));
app.createProjectAt(root,"GuiChannels");app.addSubjectRecord(struct('subject_id',"S1",'display_name',"S1"));app.addSessionRecord("S1",struct('session_id',"SE1"));
for k=1:2
    path=fullfile(root,"source"+string(k)+".csv");fid=fopen(path,'w');fprintf(fid,'Time,Ch%d\n',k);for n=0:99,fprintf(fid,'%.6f,%.6f\n',n/1000,sin(2*pi*(5+k)*n/1000));end;fclose(fid);
    inspection=lfp_inspect_csv(path);settings=struct('Inspection',inspection,'SamplingRateHz',1000,'Units',"uV",'TimeColumn',1,'SignalColumns',2,'HeaderRow',1,'DataStartRow',2,'TimeUnit',"s",'UseSceneRay',false);
    app.importCsvToSession("SE1",string(path),settings);
end
[session,~]=lfp_project_find_session(app.Project,"SE1");verifyEqual(testCase,numel(session.channels),2);verifyEqual(testCase,numel(session.data_refs),2);
end

function [project,sessionId,root]=make_project()
projectRoot=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(projectRoot,'src'));
root=string(tempname);mkdir(root);project=lfp_create_project(char(root),char("ChannelTest"));[project,~]=lfp_project_add_subject(project,struct('subject_id',"S1",'display_name',"S1"),Save=false);[project,session]=lfp_project_add_empty_session(project,"S1",struct('session_id',"SE1"),Save=false);sessionId=string(session.session_id);
end
function cleanup_root(root)
if isfolder(root),rmdir(root,'s');end
end
function delete_if_valid(app)
if ~isempty(app)&&isvalid(app),app.delete();end
end

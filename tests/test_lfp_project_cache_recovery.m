function tests = test_lfp_project_cache_recovery
%TEST_LFP_PROJECT_CACHE_RECOVERY Regression tests for stable cache lookup.
tests = functiontests(localfunctions);
end

function testCachePathFollowsSubjectAndSessionRename(testCase)
[project,sessionId,root] = make_project(); cleanup = onCleanup(@()cleanup_root(root));
t=(0:999)'/1000;data=struct('time',t,'signal',[sin(2*pi*8*t),sin(2*pi*12*t)],'fs',1000, ...
    'channelLabels',["A" "B"],'units',"uV",'metadata',struct());
[project,~]=lfp_project_attach_data(project,sessionId,data,Save=false);
[project,~]=lfp_project_update_session(project,sessionId,struct('visit_label',"Post Visit"),Save=false);
[d,channel]=lfp_project_get_channel_data(project,sessionId,"channel_A");
verifyEqual(testCase,d.signal,data.signal(:,1));verifyTrue(testCase,isfile(fullfile(root,channel.cache_relative_path)));
[project,~]=lfp_project_update_subject(project,"S1",struct('display_name',"Renamed Subject"),Save=false);
[d,channel]=lfp_project_get_channel_data(project,sessionId,"channel_A");
verifyEqual(testCase,d.signal,data.signal(:,1));verifyTrue(testCase,isfile(fullfile(root,channel.cache_relative_path)));
end

function testLegacyReferenceIsResolvedWithoutCurrentFolder(testCase)
[project,sessionId,root] = make_project(); cleanup = onCleanup(@()cleanup_root(root));
t=(0:99)'/100;data=struct('time',t,'signal',sin(2*pi*10*t),'fs',100,'channelLabels',"A",'units',"uV",'metadata',struct());
[project,~]=lfp_project_attach_data(project,sessionId,data,Save=false);
[project.subjects(1).sessions(1).channels.cache_relative_path] = deal("");
old=pwd;cd(tempdir);restore=onCleanup(@()cd(old)); %#ok<NASGU>
[d,~,~]=lfp_project_get_channel_data(project,sessionId,"channel_A");verifyEqual(testCase,d.signal,data.signal);
end

function testRepairRebuildsPerChannelFromCanonicalCache(testCase)
[project,sessionId,root] = make_project(); cleanup = onCleanup(@()cleanup_root(root));
t=(0:99)'/100;data=struct('time',t,'signal',[sin(2*pi*8*t),sin(2*pi*12*t)],'fs',100,'channelLabels',["A" "B"],'units',"uV",'metadata',struct());
[project,~]=lfp_project_attach_data(project,sessionId,data,Save=false);
[session,~]=lfp_project_find_session(project,sessionId);cache=fullfile(root,session.channels(1).cache_relative_path);delete(cache);
[project.subjects(1).sessions(1).channels(1).cache_relative_path] = deal("");
[project,report]=lfp_project_repair_channel_caches(project,sessionId,"channel_A",Save=true);
verifyEqual(testCase,string(report.status),"rebuilt");[d,channel]=lfp_project_get_channel_data(project,sessionId,"channel_A");
verifyEqual(testCase,d.signal,data.signal(:,1));verifyTrue(testCase,isfile(fullfile(root,channel.cache_relative_path)));
reloaded=lfp_load_project(root);[d2]=lfp_project_get_channel_data(reloaded,sessionId,"channel_A");verifyEqual(testCase,d2.signal,d.signal);
end

function testDistinctMissingAndReadErrors(testCase)
[project,sessionId,root] = make_project(); cleanup = onCleanup(@()cleanup_root(root));
t=(0:99)'/100;data=struct('time',t,'signal',sin(2*pi*10*t),'fs',100,'channelLabels',"A",'units',"uV",'metadata',struct());
[project,~]=lfp_project_attach_data(project,sessionId,data,Save=false);[session,~]=lfp_project_find_session(project,sessionId);
delete(fullfile(root,session.channels(1).cache_relative_path));verifyError(testCase,@()lfp_project_get_channel_data(project,sessionId,"channel_A"),'LFP:ChannelCacheMissing');
end

function [project,sessionId,root]=make_project()
projectRoot=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(projectRoot,'src'));
root=string(tempname);mkdir(root);project=lfp_create_project(root,"CacheTest");[project,~]=lfp_project_add_subject(project,struct('subject_id',"S1",'display_name',"S1"),Save=false);[project,session]=lfp_project_add_empty_session(project,"S1",struct('session_id',"SE1"),Save=false);sessionId=string(session.session_id);
end
function cleanup_root(root),if isfolder(root),rmdir(root,'s');end,end

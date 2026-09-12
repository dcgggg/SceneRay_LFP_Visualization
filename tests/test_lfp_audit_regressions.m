function tests = test_lfp_audit_regressions
% Regression tests for the high-priority code-audit findings.
tests = functiontests(localfunctions);
end

function testBandEdgeUsesAdjacentFftSupport(testCase)
add_src(testCase);
for fs=[200 250 1000]
t=(0:fs*8-1)'/fs;
d=struct('signal',sin(2*pi*10*t),'time',t,'fs',fs,'units',"uV", ...
    'processingHistory',struct('operation',{},'parameters',{},'notes',{}));
a=struct('channelMask',false(size(d.signal))); cfg=lfpDefaultConfig();cfg.psd.windowLengthSec=1;cfg.psd.frequencyRange=[1 35];
p=computeLfpPsd(d,a,cfg.psd); b=computeBandPower(p,struct([]),cfg.bands);
row=b.table(string(b.table.band)=="beta",:); verifyTrue(testCase,row.computable); verifyLessThanOrEqual(testCase,p.frequencyHz(end),fs/2);
verifyEqual(testCase,p.requestedFrequencyRangeHz,[1 35]); verifyGreaterThanOrEqual(testCase,p.effectiveFrequencyRangeHz(2),35);
end
end

function testAppendInvalidatesLatestRun(testCase)
add_src(testCase); [project,sid,root]=make_project();testCase.addTeardown(@()cleanup_root(root));
fs=200;t=(0:fs*8-1)'/fs;d=make_data(t,["A"]);[project,~]=lfp_project_attach_data(project,sid,d,Save=false);
cfg=lfpDefaultConfig();cfg.artifact.strictMode=false;cfg.psd.windowLengthSec=1;cfg.psd.frequencyRange=[1 35];
[project,~]=lfp_analyze_project(project,sid,Config=cfg,ComputeSpecparam=false,ComputeBandPower=true,Save=true);
t2=(0:fs*4-1)'/fs;[project,~]=lfp_project_append_data(project,sid,make_data(t2,["B"]),Save=false);
[run,~,current]=lfp_project_latest_run(project,sid,Config=cfg);verifyFalse(testCase,current);verifyEqual(testCase,string(run.status),"stale_data");
end

function testMissingRequestedModulesAreNotReused(testCase)
add_src(testCase); [project,sid,root]=make_project();testCase.addTeardown(@()cleanup_root(root));fs=200;t=(0:fs*8-1)'/fs;[project,~]=lfp_project_attach_data(project,sid,make_data(t,["A"]),Save=false);
cfg=lfpDefaultConfig();cfg.artifact.strictMode=false;cfg.psd.windowLengthSec=1;cfg.psd.frequencyRange=[1 35];
[project,s1]=lfp_analyze_project(project,sid,Config=cfg,ComputeSpecparam=false,ComputeBandPower=false,Save=true); %#ok<ASGLU>
[project,s2]=lfp_analyze_project(project,sid,Config=cfg,ComputeSpecparam=false,ComputeBandPower=true,Save=true);
verifyNotEqual(testCase,string(s1.runId),string(s2.runId));verifyEqual(testCase,string(project.analysisRuns(end).module_status.band_power),"ok");
end

function testZeroValidWindowsIsFailure(testCase)
add_src(testCase);fs=200;t=(0:fs*4-1)'/fs;d=make_data(t,"A");d.artifacts=struct('channelMask',true(size(d.signal)));cfg=lfpDefaultConfig();cfg.psd.windowLengthSec=1;
a=struct('channelMask',true(size(d.signal)));p=computeLfpPsd(d,a,cfg.psd);verifyEqual(testCase,string(p.status),"no_valid_windows");verifyFalse(testCase,p.validChannelMask(1));
end

function testConfigFingerprintIgnoresPresentationAndDisabledDefinitions(testCase)
add_src(testCase); cfg=lfpDefaultConfig(); altered=cfg; altered.plot.frequencyRange=[1 20]; altered.export.figureResolution=72; altered.version="other";
altered.bandDefinitions(5).rangeHz=[14 19]; verifyEqual(testCase,lfp_config_fingerprint(cfg),lfp_config_fingerprint(altered));
end

function testProjectLockIsSharedBySaveAndBatch(testCase)
add_src(testCase); root=string(tempname);mkdir(root);testCase.addTeardown(@()cleanup_root(root));
project=lfp_create_project(root,"lock"); lock=lfp_project_acquire_lock(root); testCase.addTeardown(@()release_if_valid(lock));
verifyError(testCase,@()lfp_save_project(project),'LFP:ProjectLocked');
lfp_project_release_lock(lock); verifyWarningFree(testCase,@()lfp_save_project(project)); verifyTrue(testCase,isfile(fullfile(root,'project.mat')));
end

function testStrictRevisionRejectsConcurrentIndex(testCase)
add_src(testCase); root=string(tempname);mkdir(root);testCase.addTeardown(@()cleanup_root(root));
project=lfp_create_project(root,"revision"); p1=lfp_load_project(root); p2=lfp_load_project(root);
p1.description="writer one"; [~,p1]=lfp_save_project(p1,RequireRevision=true); %#ok<ASGLU>
p2.description="writer two"; verifyError(testCase,@()lfp_save_project(p2,RequireRevision=true),'LFP:ProjectRevisionConflict');
end

function testAnalysisPayloadWriteRespectsProjectLock(testCase)
add_src(testCase); [project,sid,root]=make_project(); testCase.addTeardown(@()cleanup_root(root));
fs=200; t=(0:fs*4-1)'/fs;
[project,~]=lfp_project_attach_data(project,sid,make_data(t,"A"),Save=false);
lock=lfp_project_acquire_lock(root); testCase.addTeardown(@()release_if_valid(lock));
cfg=lfpDefaultConfig(); cfg.artifact.strictMode=false; cfg.psd.windowLengthSec=1;
verifyError(testCase,@()lfp_analyze_project(project,sid,Config=cfg,Save=false), 'LFP:ProjectLocked');
end

function [project,sid,root]=make_project()
root=string(tempname);mkdir(root);project=lfp_create_project(root,"audit");[project,~]=lfp_project_add_subject(project,struct('subject_id',"S1"),Save=false);[project,s]=lfp_project_add_empty_session(project,"S1",struct('session_id',"SE1"),Save=false);sid=string(s.session_id);
end

function d=make_data(t,labels)
d=struct('signal',sin(2*pi*10*t),'time',t,'fs',1/median(diff(t)),'channelLabels',labels,'units',"uV",'metadata',struct(), ...
    'processingHistory',struct('operation',{},'parameters',{},'notes',{}));
if numel(labels)>1,d.signal=repmat(d.signal,1,numel(labels));end
end

function add_src(testCase),root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'src'));testCase.addTeardown(@()rmpath(fullfile(root,'src')));end
function cleanup_root(root),if isfolder(root),rmdir(root,'s');end,end
function release_if_valid(lock),try,lfp_project_release_lock(lock);catch,end,end

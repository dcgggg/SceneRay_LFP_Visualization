function tests = test_lfp_band_definitions
%TEST_LFP_BAND_DEFINITIONS Tests editable enabled/disabled band snapshots.
tests = functiontests(localfunctions);
end

function testDefaultsPreserveSixRowsAndFourEnabled(testCase)
ensure_src(testCase);cfg=lfpDefaultConfig();[defs,active]=lfp_get_band_definitions(cfg);
verifyEqual(testCase,numel(defs),6);verifyEqual(testCase,logical([defs.enabled]),[true true true true false false]);
verifyEqual(testCase,string({active.name}),["Delta" "Theta" "Alpha" "Beta"]);
rows=band_table_data(defs);verifySize(testCase,rows,[6 4]);verifyEqual(testCase,logical(cell2mat(rows(:,1)))',[true true true true false false]);
end

function testSessionRunStoresBandSnapshot(testCase)
ensure_src(testCase);root=string(tempname);mkdir(root);cleanup=onCleanup(@()cleanup_root(root));
app=launchLfpProjectApp(Visible="off");cleanupApp=onCleanup(@()delete_if_valid(app));app.createProjectAt(root,"Band GUI");app.addSubjectRecord(struct('subject_id',"S1",'display_name',"S1"));app.addSessionRecord("S1",struct('session_id',"SE1"));
fs=200;t=(0:fs*3-1)'/fs;data=struct('time',t,'signal',sin(2*pi*10*t),'fs',fs,'channelLabels',"A",'units',"uV",'metadata',struct());app.attachDataToSession("SE1",data);app.Controls.ArtifactZ.Value=1e6;app.Controls.JumpZ.Value=1e6;app.Project.defaultConfig.artifact.strictMode=false;app.Project.defaultConfig.psd.maxArtifactFraction=1;
rows=app.Controls.BandTable.Data;for k=1:size(rows,1),rows{k,1}=false;end;rows{3,1}=true;app.Controls.BandTable.Data=rows;app.Controls.ModuleSpecparam.Value=false;app.Controls.ModuleBand.Value=true;summary=app.runSelectedAnalysis();
verifyTrue(testCase,ismember(string(summary.status),["ok" "partial_failure"]));[session,~]=lfp_project_find_session(app.Project,"SE1");verifyTrue(testCase,isfield(session,'analysis_config'));verifyEqual(testCase,numel(session.analysis_config.bandDefinitions),6);verifyEqual(testCase,numel(session.analysis_config.bands),1);verifyEqual(testCase,string(session.analysis_config.bands(1).name),"Alpha");
verifyEqual(testCase,string(app.CurrentResults.bandResult.table.band),"Alpha");
end

function ensure_src(testCase),root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'src'));testCase.addTeardown(@()rmpath(fullfile(root,'src')));end
function cleanup_root(root),if isfolder(root),rmdir(root,'s');end,end
function delete_if_valid(app),try,if ~isempty(app)&&isvalid(app),app.close(true);end,catch,end,end

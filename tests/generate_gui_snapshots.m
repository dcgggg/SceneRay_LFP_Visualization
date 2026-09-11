function files = generate_gui_snapshots(outputFolder)
%GENERATE_GUI_SNAPSHOTS Build deterministic GUI acceptance screenshots.

if nargin<1
    root=fileparts(fileparts(mfilename('fullpath')));
    outputFolder=fullfile(root,'docs','images','gui');
else
    root=fileparts(fileparts(mfilename('fullpath')));
end
addpath(fullfile(root,'src'));if ~isfolder(outputFolder),mkdir(outputFolder);end
projectParent=string(tempname);mkdir(projectParent);cleanup=onCleanup(@()cleanup_all(projectParent)); %#ok<NASGU>
projectRoot=fullfile(projectParent,"Human LFP study");
files=strings(7,1);app=launchLfpProjectApp(Visible="off");appCleanup=onCleanup(@()app.close(true)); %#ok<NASGU>
files(1)=fullfile(outputFolder,'01-welcome.png');app.exportSnapshot(files(1));
app.createProjectInParent(projectParent,"Human LFP study","GUI acceptance project");app.Project.defaultConfig.artifact.strictMode=false;
app.Project.defaultConfig.psd.maxArtifactFraction=1;
for subject=["P01" "P02"]
    app.addSubjectRecord(struct('subject_id',subject,'display_name',subject));
    for visit=["Baseline" "Day07"]
        id=subject+"_"+visit;app.addSessionRecord(subject,struct('session_id',id,'visit_label',visit));
        scale=1+0.15*(subject=="P02")+0.25*(visit=="Day07");source=fixture(scale);csvFile=fullfile(projectRoot,id+".csv");
        writetable(table(source.time,source.signal(:,1),source.signal(:,2),'VariableNames',{'time','channel01','channel12'}),csvFile);
        settings=struct('HeaderRow',1,'DataStartRow',2,'TimeColumn',1,'SignalColumns',[2 3], ...
            'SamplingRateHz',source.fs,'Units',"uV",'TimeUnit',"s",'UseSceneRay',false);
        app.importCsvToSession(id,csvFile,settings);
    end
end
app.selectSession("P01_Baseline");app.Controls.WorkspaceTabs.SelectedTab=app.Controls.DataTab;drawnow;
files(2)=fullfile(outputFolder,'02-project-management.png');app.exportSnapshot(files(2));
app.selectSession("P01_Day07");drawnow;files(3)=fullfile(outputFolder,'03-session-imported.png');app.exportSnapshot(files(3));
app.Controls.PsdWindow.Value=1;
for id=["P01_Baseline" "P01_Day07" "P02_Baseline" "P02_Day07"]
    app.selectSession(id);app.runSelectedAnalysis();
end
app.selectSession("P01_Day07");app.Controls.WorkspaceTabs.SelectedTab=app.Controls.AnalysisTab;app.Controls.AnalysisResultTabs.SelectedTab=app.Controls.SpecResultTab;drawnow;
files(4)=fullfile(outputFolder,'04-session-analysis.png');app.exportSnapshot(files(4));
app.CompareSelectedSessionIds=["P01_Baseline";"P01_Day07"];
app.Controls.MappingTable.Data={'P01_Baseline','channel01','STN';'P01_Day07','channel01','STN'};
runCount=numel(app.Project.analysisRuns);
app.Controls.WorkspaceTabs.SelectedTab=app.Controls.CompareTab;app.compareSelected(false);drawnow;
assert(numel(app.Project.analysisRuns)==runCount,'Comparison must reuse cached session analyses.');
assert(all(isfinite(app.CurrentComparison.result_table.value)),'Within-subject screenshot values must be finite.');
files(5)=fullfile(outputFolder,'05-within-subject-comparison.png');app.exportSnapshot(files(5));
app.CompareSelectedSessionIds=["P01_Day07";"P02_Day07"];
app.Controls.MappingTable.Data={'P01_Day07','channel01','STN';'P02_Day07','channel01','STN'};
app.compareSelected(false);drawnow;
assert(numel(app.Project.analysisRuns)==runCount,'Between-subject comparison must not repeat analysis.');
assert(all(isfinite(app.CurrentComparison.result_table.value)),'Between-subject screenshot values must be finite.');
exported=lfp_export_comparison(app.CurrentComparison,fullfile(projectRoot,'comparison-export'));
assert(isfile(exported.csv)&&isfile(exported.mat),'Comparison CSV and MAT exports are required.');
files(6)=fullfile(outputFolder,'06-between-subject-comparison.png');app.exportSnapshot(files(6));
app.Figure.Position=[100 100 1100 800];app.Figure.SizeChangedFcn(app.Figure,[]);drawnow;
files(7)=fullfile(outputFolder,'07-small-window-comparison.png');app.exportSnapshot(files(7));
reopened=launchLfpProjectApp(Visible="off",ProjectRoot=projectRoot);
reopenedCleanup=onCleanup(@()reopened.close(true)); %#ok<NASGU>
assert(numel(reopened.Project.subjects)==2,'Reopened project must contain two subjects.');
assert(sum(arrayfun(@(s)numel(s.sessions),reopened.Project.subjects))==4, ...
    'Reopened project must contain four sessions.');
assert(numel(reopened.Project.analysisRuns)==4,'Reopened project must restore four analysis runs.');
assert(numel(reopened.Project.comparisons)>=2,'Reopened project must restore saved comparisons.');
assert(~isempty(fieldnames(reopened.CurrentComparison)),'Latest comparison must be restored on reopen.');
end

function data=fixture(scale)
fs=200;t=(0:1/fs:8-1/fs)';rng(42);signal=scale.*[sin(2*pi*10*t)+.08*randn(size(t)),sin(2*pi*20*t)+.08*randn(size(t))];
data=struct('signal',signal,'time',t,'fs',fs,'channelLabels',["channel01" "channel12"], ...
    'units',"uV",'metadata',struct('sourceFileName',"synthetic.csv"), ...
    'processingHistory',struct('operation',"test_fixture",'parameters',struct(),'notes',"Screenshot fixture"));
end

function cleanup_all(path)
if isfolder(path),rmdir(path,'s');end
end

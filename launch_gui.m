function app = launch_gui(options)
%LAUNCH_GUI Start the SceneRay LFP project GUI without input data.
%   APP = LAUNCH_GUI opens the complete Project/Subject/Session workspace.

arguments
    options.Visible (1,1) string = "on"
    options.ProjectRoot (1,1) string = ""
end
root=fileparts(mfilename('fullpath'));src=fullfile(root,'src');
if ~contains(path,src),addpath(src);end
lfp_project_startup();
app=launchLfpProjectApp(Visible=options.Visible,ProjectRoot=options.ProjectRoot);
end

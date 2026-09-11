function app = launchLfpProjectApp(options)
%LAUNCHLFPPROJECTAPP Launch the Project/Subject/Session workspace.
%   APP = LAUNCHLFPPROJECTAPP starts a small MATLAB-native workspace that
%   delegates import, analysis, comparison and persistence to the script API.
%   The existing single-record LfpApp remains available through launchLfpApp.

arguments
    options.Visible (1,1) string = "on"
    options.ProjectRoot (1,1) string = ""
end
app = LfpProjectApp(options.Visible);
if strlength(options.ProjectRoot)>0
    app.loadProjectFrom(options.ProjectRoot);
end
end

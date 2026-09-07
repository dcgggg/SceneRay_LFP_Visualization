function app = launchLfpApp(options)
%LAUNCHLFPAPP Launch the native MATLAB LFP analysis GUI.
%   APP = LAUNCHLFPAPP opens the GUI and returns an LfpApp handle.  Use
%   APP = LAUNCHLFPAPP(Visible="off") for a smoke test or scripted setup.
%   The GUI uses no Python, web service, runtime download, global state, or
%   hard-coded user data path.  Close the returned figure to release it.

arguments
    options.Visible (1,1) string {mustBeMember(options.Visible, ["on" "off"])} = "on"
    options.ProjectRoot (1,1) string = ""
end

if strlength(options.ProjectRoot) == 0
    thisFile = mfilename('fullpath');
    projectRoot = fileparts(fileparts(thisFile));
else
    projectRoot = char(options.ProjectRoot);
end
lfp_project_startup(projectRoot);
app = LfpApp(options.Visible);
end

%EXAMPLE_LFP_GUI Launch the MATLAB-native SceneRay LFP analysis GUI.
%   Run this script from any folder after opening the project in MATLAB.
%   The GUI does not upload data or download dependencies at runtime.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(projectRoot);
app = launch_gui; %#ok<NASGU>

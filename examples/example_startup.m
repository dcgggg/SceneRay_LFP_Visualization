% Minimal project-entry example. No LFP analysis is performed yet.
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
info = lfp_project_startup(projectRoot);
disp(info);

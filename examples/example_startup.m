% Minimal project-entry example.
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
info = lfp_project_startup(projectRoot);
disp(info);

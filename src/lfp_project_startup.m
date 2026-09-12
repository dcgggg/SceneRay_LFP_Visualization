function info = lfp_project_startup(projectRoot)
%LFP_PROJECT_STARTUP Validate and register the MATLAB project entry point.
%   INFO = LFP_PROJECT_STARTUP(PROJECTROOT) adds the project's source path
%   and returns environment metadata. It performs no signal analysis.

if nargin < 1 || isempty(projectRoot)
    thisFile = mfilename('fullpath');
    projectRoot = fileparts(fileparts(thisFile));
end

projectRoot = char(string(projectRoot));
if ~isfolder(projectRoot)
    error('LFP:InvalidProjectRoot', 'Project root does not exist: %s', projectRoot);
end

srcRoot = fullfile(projectRoot, 'src');
if ~isfolder(srcRoot)
    error('LFP:MissingSourceDirectory', 'Missing source directory: %s', srcRoot);
end

addpath(srcRoot);

info = struct();
info.projectRoot = projectRoot;
info.sourceDirectory = srcRoot;
info.matlabVersion = version;
info.minimumDesignedVersion = 'R2022b';
info.sourceOnPath = contains(string(path), string(srcRoot), 'IgnoreCase', ispc);
info.signalProcessingToolbox = license('test', 'Signal_Toolbox') == 1;
info.statisticsToolbox = license('test', 'Statistics_Toolbox') == 1;
info.fieldTripEntryPoint = ~isempty(which('ft_defaults'));
provider = lfp_dpss_provider();
info.dpssProvider = provider.name;
info.dpssResolution = provider.resolution;
info.dpssAllResolutions = string(which('dpss','-all'));
info.dpssSelectionReason = provider.reason;
info.fieldTripPathWarning = "";
if info.fieldTripEntryPoint && ~isempty(info.dpssAllResolutions) && ...
        contains(lower(info.dpssAllResolutions(1)), 'fieldtrip')
    info.fieldTripPathWarning = "FieldTrip is on the MATLAB path; native DPSS remains selected, but global path shadowing may affect optional FieldTrip calls.";
end
info.status = 'initialized_only';
end

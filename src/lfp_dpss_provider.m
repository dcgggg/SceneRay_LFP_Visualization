function provider = lfp_dpss_provider()
%LFP_DPSS_PROVIDER Report the controlled DPSS implementation selection.
%   FieldTrip compatibility folders can shadow MATLAB's dpss function. Such
%   paths are never used for the numerical core; the project falls back to
%   its native eigensolver instead.
resolved = string(which('dpss'));
lowered = lower(resolved);
shadowedByFieldTrip = contains(lowered, "fieldtrip") || contains(lowered, "dpss_hack");
provider = struct('name', "SceneRay native lfp_dpss", ...
    'resolution', resolved, 'useToolbox', false, 'reason', "controlled native fallback");
if ~shadowedByFieldTrip && strlength(resolved) > 0 && exist('dpss','file') == 2
    provider.name = "MATLAB dpss";
    provider.useToolbox = true;
    provider.reason = "Signal Processing Toolbox dpss resolved without FieldTrip shadowing";
elseif shadowedByFieldTrip
    provider.reason = "FieldTrip dpss shadowing detected; native fallback selected";
end
end

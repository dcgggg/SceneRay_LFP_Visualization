function fingerprint = lfp_analysis_config_fingerprint(cfg, requestedModules)
%LFP_ANALYSIS_CONFIG_FINGERPRINT Fingerprint only products requested by a run.
%   Artifact/PSD settings always participate. specparam and band settings are
%   included only when their products are requested, preventing a change to
%   an unused module from invalidating unrelated cached results.
arguments
    cfg (1,1) struct
    requestedModules (1,1) struct = struct('specparam',true,'band_power',true)
end
scoped = struct();
for name = ["artifact" "psd"]
    if isfield(cfg,char(name)), scoped.(char(name)) = cfg.(char(name)); end
end
if isfield(requestedModules,'specparam') && requestedModules.specparam && isfield(cfg,'fooof')
    scoped.fooof = cfg.fooof;
end
if isfield(requestedModules,'band_power') && requestedModules.band_power
    if isfield(cfg,'bands'), scoped.bands = cfg.bands; end
    if isfield(cfg,'bandDefinitions')
        defs = cfg.bandDefinitions;
        if isstruct(defs) && ~isempty(defs) && isfield(defs,'enabled'), defs = defs([defs.enabled]); end
        scoped.bandDefinitions = defs;
    end
    if isfield(cfg,'bandConfigVersion'), scoped.bandConfigVersion = cfg.bandConfigVersion; end
end
fingerprint = lfp_config_fingerprint(scoped);
end

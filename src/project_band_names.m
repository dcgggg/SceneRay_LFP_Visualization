function names = project_band_names(project)
names = strings(0,1);
if ~isstruct(project)||~isfield(project,'defaultConfig')||~isstruct(project.defaultConfig), return; end
[~, bands] = lfp_get_band_definitions(project.defaultConfig);
if ~isempty(bands), names=string({bands.name})'; end
names=unique(names(strlength(names)>0),'stable');
end

function names = project_band_names(project)
names = strings(0,1);
if ~isstruct(project)||~isfield(project,'defaultConfig')||~isstruct(project.defaultConfig)||~isfield(project.defaultConfig,'bands'), return; end
bands = project.defaultConfig.bands;
if isstruct(bands)&&numel(bands)>0&&isfield(bands,'name'), names=string({bands.name})';
elseif isstruct(bands), names=string(fieldnames(bands)); end
names=unique(names(strlength(names)>0),'stable');
end

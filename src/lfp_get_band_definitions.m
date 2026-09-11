function [definitions, activeBands] = lfp_get_band_definitions(config)
%LFP_GET_BAND_DEFINITIONS Normalize saved band settings for GUI and analysis.
%   DEFINITIONS preserves enabled rows and exact bounds. ACTIVEBANDS is the
%   legacy name/rangeHz struct array consumed by computeBandPower. Older
%   configs that only contain cfg.bands are treated as all-enabled rows.

definitions = struct('name', {}, 'rangeHz', {}, 'enabled', {});
if isstruct(config) && isfield(config, 'bandDefinitions') && ...
        isstruct(config.bandDefinitions) && ~isempty(config.bandDefinitions)
    source = config.bandDefinitions;
    definitions = repmat(struct('name', "", 'rangeHz', [NaN NaN], 'enabled', true), numel(source), 1);
    for k = 1:numel(source)
        definitions(k).name = string(get_field(source(k), 'name', "band_" + k));
        definitions(k).rangeHz = double(get_field(source(k), 'rangeHz', [NaN NaN]));
        definitions(k).enabled = logical(get_field(source(k), 'enabled', true));
    end
elseif isstruct(config) && isfield(config, 'bands')
    source = config.bands;
    if isstruct(source) && ~isempty(source) && isfield(source, 'name') && isfield(source, 'rangeHz')
        definitions = repmat(struct('name', "", 'rangeHz', [NaN NaN], 'enabled', true), numel(source), 1);
        for k = 1:numel(source)
            definitions(k).name = string(source(k).name);
            definitions(k).rangeHz = double(source(k).rangeHz);
            definitions(k).enabled = true;
        end
    elseif isstruct(source)
        names = string(fieldnames(source));
        definitions = repmat(struct('name', "", 'rangeHz', [NaN NaN], 'enabled', true), numel(names), 1);
        for k = 1:numel(names)
            definitions(k).name = names(k);
            definitions(k).rangeHz = double(source.(char(names(k))));
            definitions(k).enabled = true;
        end
    end
end
activeMask = false(numel(definitions), 1);
if ~isempty(definitions), activeMask = logical([definitions.enabled])'; end
activeBands = struct('name', {}, 'rangeHz', {});
for k = find(activeMask(:))'
    activeBands(end+1) = struct('name', definitions(k).name, 'rangeHz', definitions(k).rangeHz); %#ok<AGROW>
end
end

function value = get_field(source, name, fallback)
if isstruct(source) && isfield(source, name) && ~isempty(source.(name)), value = source.(name); else, value = fallback; end
end

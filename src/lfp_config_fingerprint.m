function fingerprint = lfp_config_fingerprint(cfg, options)
%LFP_CONFIG_FINGERPRINT Return a deterministic fingerprint for computation.
%   FINGERPRINT = LFP_CONFIG_FINGERPRINT(CFG) canonicalizes field ordering,
%   removes GUI-only/runtime fields, and returns a hexadecimal FNV-1a hash.
%   The fingerprint is intentionally independent of plotting settings and
%   callback handles so it can be used for analysis-result cache validation.

arguments
    cfg (1,1) struct
    options.IncludePlot (1,1) logical = false
end

canonical = canonicalize(cfg, options.IncludePlot);
encoded = jsonencode(canonical);
bytes = uint8(char(encoded));
hashValue = uint32(2166136261);
for index = 1:numel(bytes)
    hashValue = bitxor(hashValue, uint32(bytes(index)));
    hashValue = hashValue * uint32(16777619);
end
fingerprint = string(lower(dec2hex(hashValue, 8)));
end

function value = canonicalize(value, includePlot)
if isstruct(value)
    if numel(value) ~= 1
        cells = cell(size(value));
        for index = 1:numel(value), cells{index} = canonicalize(value(index), includePlot); end
        value = cells;
        return;
    end
    names = fieldnames(value);
    if ~includePlot
        names = setdiff(names, {'plot', 'parameterMetadata'}, 'stable');
    end
    names = sort(names);
    result = struct();
    for index = 1:numel(names)
        name = names{index};
        nested = value.(name);
        if isa(nested, 'function_handle') || isobject(nested)
            continue;
        end
        result.(name) = canonicalize(nested, includePlot);
    end
    value = result;
elseif iscell(value)
    for index = 1:numel(value), value{index} = canonicalize(value{index}, includePlot); end
elseif isa(value, 'string')
    value = cellstr(value);
elseif isa(value, 'datetime') || isa(value, 'duration')
    value = char(string(value));
elseif isa(value, 'function_handle') || isobject(value)
    value = char(string(value));
end
end

function version = lfp_data_version(data)
%LFP_DATA_VERSION Compute a content-sensitive version for an imported record.
%   The version includes dimensions, sampling metadata, labels, time values,
%   and signal samples.  It is used only as a cache key; raw data are never
%   modified by this function.

arguments
    data (1,1) struct
end
required = {'signal', 'fs'};
for index = 1:numel(required)
    if ~isfield(data, required{index}), error('LFP:InvalidData', 'data.%s is required.', required{index}); end
end
payload = struct('size', size(data.signal), 'fs', double(data.fs), ...
    'time', get_field(data, 'time', []), 'labels', string(get_field(data, 'channelLabels', strings(0,1))), ...
    'signal', double(data.signal));
text = jsonencode(payload);
bytes = uint8(char(text));
h = uint32(2166136261);
for index = 1:numel(bytes), h = bitxor(h, uint32(bytes(index))); h = h * uint32(16777619); end
version = string(lower(dec2hex(h, 8)));
end

function value = get_field(s, name, fallback)
if isfield(s, name), value = s.(name); else, value = fallback; end
end

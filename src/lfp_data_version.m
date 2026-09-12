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
% Hash a stable binary representation directly.  This avoids copying large
% recordings into JSON text while retaining sensitivity to metadata, time and
% every signal sample.
h = uint32(2166136261);
h = update_bytes(h, uint8('lfp-data-v2'));
h = update_bytes(h, typecast(uint64(size(data.signal)), 'uint8'));
h = update_bytes(h, typecast(double(data.fs), 'uint8'));
h = update_bytes(h, typecast(double(get_field(data, 'time', [])), 'uint8'));
labels = string(get_field(data, 'channelLabels', strings(0,1)));
h = update_bytes(h, uint8(char(join(labels, char(0)))));
h = update_bytes(h, uint8(char(string(get_field(data, 'units', "unknown")))));
h = update_bytes(h, typecast(double(data.signal(:)), 'uint8'));
version = string(lower(dec2hex(h, 8)));
end

function h = update_bytes(h, bytes)
bytes = uint8(bytes(:));
for index = 1:numel(bytes)
    h = bitxor(h, uint32(bytes(index)));
    h = uint32(mod(uint64(h) * uint64(16777619), uint64(2)^32));
end
end

function value = get_field(s, name, fallback)
if isfield(s, name), value = s.(name); else, value = fallback; end
end

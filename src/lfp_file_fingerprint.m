function fingerprint = lfp_file_fingerprint(filePath, options)
%LFP_FILE_FINGERPRINT Return a deterministic content fingerprint for a file.
%   This base-MATLAB fingerprint is computed once at import time and stored
%   in the project manifest. It deliberately does not use Java, Python or a
%   network service. The byte stream is folded into two independent uint32
%   FNV-style accumulators so a later cache lookup never needs to re-read the
%   source file unless the caller explicitly requests a new import.

arguments
    filePath (1,1) string
    options.ChunkBytes (1,1) double {mustBePositive} = 1024 * 1024
end
if ~isfile(filePath), error('LFP:InputFileNotFound', 'File not found: %s', filePath); end
fid = fopen(filePath, 'r');
if fid < 0, error('LFP:FileOpenFailed', 'Cannot open file: %s', filePath); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
h1 = uint32(2166136261); h2 = uint32(2246822519);
total = uint64(0); chunk = fread(fid, floor(options.ChunkBytes), '*uint8');
while ~isempty(chunk)
    total = total + uint64(numel(chunk));
    for k = 1:numel(chunk)
        h1 = uint32(mod(uint64(bitxor(h1, uint32(chunk(k)))) * uint64(16777619), uint64(2)^32));
        h2 = uint32(mod(uint64(bitxor(h2, uint32(chunk(k)))) * uint64(3266489917), uint64(2)^32));
    end
    chunk = fread(fid, floor(options.ChunkBytes), '*uint8');
end
% Include byte count, but not path or modification time: moving/copying an
% unchanged CSV must preserve its identity.
fingerprint = lower(string([dec2hex(h1, 8) dec2hex(h2, 8) ...
    dec2hex(uint32(mod(total, uint64(2)^32)), 8)]));
end

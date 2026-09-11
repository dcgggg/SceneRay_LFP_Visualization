function id = lfp_make_id(prefix)
%LFP_MAKE_ID Create a portable, stable-looking identifier for project records.
%   ID = LFP_MAKE_ID(PREFIX) returns a string identifier.  The function does
%   not use Java, external services, or a global counter.  IDs are generated
%   from the current clock and random state and are intended to be persisted
%   once created; callers must not regenerate an existing ID on load.

arguments
    prefix (1,1) string = "id"
end

stamp = string(datestr(now, 'yyyymmddTHHMMSSFFF'));
randomPart = randi([0, intmax('uint32')], 1, 2, 'uint32');
id = prefix + "_" + stamp + "_" + string(dec2hex(randomPart(1), 8)) + ...
    string(dec2hex(randomPart(2), 8));
end

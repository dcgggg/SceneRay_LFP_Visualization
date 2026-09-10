function values = lfp_parse_delimited_line(line, delimiter)
%LFP_PARSE_DELIMITED_LINE Parse one delimited text line without Java/Python.
%   VALUES = LFP_PARSE_DELIMITED_LINE(LINE, DELIMITER) supports quoted
%   fields and doubled quote escapes. Numeric-looking values are returned
%   as doubles; all other values are chars. It is intended for lightweight
%   CSV previews and streaming import paths.

arguments
    line {mustBeTextScalar}
    delimiter {mustBeTextScalar} = ','
end

line = char(line);
delimiter = char(delimiter);
if numel(delimiter) ~= 1
    error('LFP:InvalidDelimiter', 'Delimiter must contain exactly one character.');
end

tokens = cell(1, max(1, count(line, delimiter) + 1));
tokenCount = 1;
buffer = '';
insideQuotes = false;
index = 1;
while index <= numel(line)
    character = line(index);
    if character == '"'
        if insideQuotes && index < numel(line) && line(index + 1) == '"'
            buffer(end + 1) = '"'; %#ok<AGROW>
            index = index + 1;
        else
            insideQuotes = ~insideQuotes;
        end
    elseif character == delimiter && ~insideQuotes
        tokens{tokenCount} = convert_token(buffer);
        tokenCount = tokenCount + 1;
        buffer = '';
    else
        buffer(end + 1) = character; %#ok<AGROW>
    end
    index = index + 1;
end
tokens{tokenCount} = convert_token(buffer);
values = tokens(1:tokenCount);
if ~isempty(values) && ischar(values{1}) && ~isempty(values{1}) && double(values{1}(1)) == 65279
    values{1} = values{1}(2:end);
end
end

function value = convert_token(token)
token = strtrim(token);
if isempty(token)
    value = '';
    return;
end
number = str2double(token);
if isfinite(number) || any(strcmpi(token, {'nan', '+nan', '-nan', 'inf', '+inf', '-inf'}))
    value = number;
else
    value = token;
end
end

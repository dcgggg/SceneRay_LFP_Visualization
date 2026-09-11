function value = get_field_local(source, name, fallback)
if isstruct(source) && isfield(source,name) && ~isempty(source.(name)), value=source.(name); else, value=fallback; end
end

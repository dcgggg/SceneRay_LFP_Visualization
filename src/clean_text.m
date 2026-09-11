function value = clean_text(value)
value = string(value);
value = value(~ismissing(value));
if isempty(value), value = ""; else, value = join(value, "；"); end
end

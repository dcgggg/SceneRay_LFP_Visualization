function rows = band_table_data(bands)
if isstruct(bands) && numel(bands)>0 && isfield(bands,'name') && isfield(bands,'rangeHz')
    names = string({bands.name})'; ranges = {bands.rangeHz};
    if isfield(bands,'enabled'), enabledValues = logical([bands.enabled])'; else, enabledValues = true(numel(names),1); end
else
    names = string(fieldnames(bands)); ranges = cell(numel(names),1);
    enabledValues = true(numel(names),1);
    for i=1:numel(names), ranges{i}=bands.(char(names(i))); end
end
rows = cell(numel(names),4);
for i=1:numel(names), range=double(ranges{i}); rows(i,:)={enabledValues(i),char(names(i)),double(range(1)),double(range(2))}; end
end

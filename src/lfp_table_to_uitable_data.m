function displayData = lfp_table_to_uitable_data(inputTable)
%LFP_TABLE_TO_UITABLE_DATA Convert a table to MATLAB uitable-safe display data.
%   DISPLAYDATA = LFP_TABLE_TO_UITABLE_DATA(INPUTTABLE) returns a cell array
%   containing only scalar numeric/logical values or character vectors. This
%   is a display conversion only; the source table and its typed variables
%   are not modified.

arguments
    inputTable table
end

rawData = table2cell(inputTable);
displayData = cell(size(rawData));
for row = 1:size(rawData, 1)
    for column = 1:size(rawData, 2)
        value = rawData{row, column};
        if isnumeric(value) && isscalar(value)
            displayData{row, column} = value;
        elseif islogical(value) && isscalar(value)
            displayData{row, column} = value;
        elseif ischar(value)
            displayData{row, column} = value;
        elseif isstring(value) && isscalar(value)
            if ismissing(value)
                displayData{row, column} = '';
            else
                displayData{row, column} = char(value);
            end
        elseif isempty(value)
            displayData{row, column} = '';
        else
            try
                token = string(value);
                if ismissing(token)
                    displayData{row, column} = '';
                else
                    displayData{row, column} = char(token);
                end
            catch
                displayData{row, column} = '';
            end
        end
    end
end
end

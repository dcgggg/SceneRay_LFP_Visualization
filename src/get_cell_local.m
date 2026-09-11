function value = get_cell_local(rows,row,column,fallback)
value=fallback;
if column<=size(rows,2)&&~isempty(rows{row,column}), value=rows{row,column}; end
end

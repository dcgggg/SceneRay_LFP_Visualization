function tests = test_lfp_table_to_uitable_data
%TEST_LFP_TABLE_TO_UITABLE_DATA Test conversion of typed tables for uitable.
tests = functiontests(localfunctions);
end

function testStringAndNumericColumnsBecomeSupportedCells(testCase)
ensure_src_on_path(testCase);
inputTable = table([1; 2], string(["1-2"; "5-6"]), ...
    string(["delta"; "theta"]), [NaN; 3.5], ...
    'VariableNames', {'channelIndex', 'channelLabel', 'band', 'power'});
displayData = lfp_table_to_uitable_data(inputTable);
verifyClass(testCase, displayData, 'cell');
verifyEqual(testCase, displayData{1, 1}, 1);
verifyEqual(testCase, displayData{1, 2}, '1-2');
verifyEqual(testCase, displayData{2, 3}, 'theta');
verifyTrue(testCase, isnan(displayData{1, 4}));
for row = 1:size(displayData, 1)
    for column = 1:size(displayData, 2)
        value = displayData{row, column};
        verifyTrue(testCase, isnumeric(value) || islogical(value) || ischar(value));
    end
end
end

function ensure_src_on_path(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
srcRoot = fullfile(projectRoot, 'src');
addpath(srcRoot);
testCase.addTeardown(@() rmpath(srcRoot));
end

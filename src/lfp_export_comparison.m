function files = lfp_export_comparison(comparison, outputFolder)
%LFP_EXPORT_COMPARISON Export a reproducible comparison table and metadata.

arguments
    comparison (1,1) struct
    outputFolder (1,1) string
end
if ~isfield(comparison, 'result_table') || ~istable(comparison.result_table)
    error('LFP:InvalidComparison', 'comparison.result_table is required.');
end
if ~isfolder(outputFolder), mkdir(outputFolder); end
files = struct('csv', fullfile(outputFolder, "comparison_long_table.csv"), ...
    'mat', fullfile(outputFolder, "comparison.mat"));
writetable(comparison.result_table, files.csv);
savedComparison = comparison; %#ok<NASGU>
save(files.mat, 'savedComparison', '-v7');
end

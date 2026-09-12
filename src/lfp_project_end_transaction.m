function lfp_project_end_transaction(transaction, status, message)
%LFP_PROJECT_END_TRANSACTION Commit or annotate a project staging marker.
arguments
    transaction (1,1) struct
    status (1,1) string
    message (1,1) string = ""
end
if ~isfield(transaction,'path') || ~isfolder(string(transaction.path)), return; end
if status == "committed"
    rmdir(string(transaction.path),'s');
    parent = fileparts(string(transaction.path));
    if isfolder(parent) && isempty(dir(fullfile(parent,'*'))), rmdir(parent); end
else
    transaction.status=status;transaction.message=message;transaction.finishedAt=string(datestr(now,31));
    manifest=transaction; %#ok<NASGU>
    save(fullfile(string(transaction.path),'manifest.mat'),'manifest','-v7');
end
end

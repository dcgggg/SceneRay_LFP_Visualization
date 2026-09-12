function transaction = lfp_project_begin_transaction(projectRoot, operation)
%LFP_PROJECT_BEGIN_TRANSACTION Create a diagnostic staging marker.
%   Multi-file project operations still write their individual files through
%   atomic replacements, but this marker makes an interrupted operation
%   discoverable instead of presenting a silent mixed index/cache state.
arguments
    projectRoot (1,1) string
    operation (1,1) string
end
stagingRoot = fullfile(projectRoot, '.lfp_staging');
if ~isfolder(stagingRoot), mkdir(stagingRoot); end
id = lfp_make_id('txn'); path = fullfile(stagingRoot, id); mkdir(path);
transaction = struct('id',id,'path',string(path),'operation',operation, ...
    'startedAt',string(datestr(now,31)),'status',"running");
manifest = transaction; %#ok<NASGU>
save(fullfile(path,'manifest.mat'),'manifest','-v7');
end

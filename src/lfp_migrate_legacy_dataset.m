function [project, session] = lfp_migrate_legacy_dataset(project, filePath, subjectId, sessionInfo, options)
%LFP_MIGRATE_LEGACY_DATASET Import a legacy MAT data file by explicit IDs.
%   Source files remain untouched.  Missing or legacy analysis metadata is
%   recorded as a warning and is not automatically considered cache-valid.

arguments
    project (1,1) struct
    filePath (1,1) string
    subjectId (1,1) string
    sessionInfo (1,1) struct
    options.Save (1,1) logical = true
end
loaded = load(filePath);
if isfield(loaded, 'data'), data=loaded.data;
elseif isfield(loaded, 'payload') && isfield(loaded.payload, 'data'), data=loaded.payload.data;
else, error('LFP:LegacyDataNotFound', 'No data variable found in legacy file.'); end
sessionInfo.notes = string(get_field(sessionInfo,'notes',"")) + " | migrated from legacy MAT; prior result validity not assumed.";
[project, session] = lfp_project_add_session(project, subjectId, data, sessionInfo, Save=options.Save);
entry = struct('operation', "legacy_migration", 'sourceFile', filePath, ...
    'subject_id', subjectId, 'session_id', session.session_id, ...
    'notes', "Explicit identity supplied; legacy cached analysis requires revalidation.");
if ~isfield(project,'migrationLog') || isempty(project.migrationLog), project.migrationLog=entry; else, project.migrationLog(end+1)=entry; end
if options.Save, lfp_save_project(project); end
end

function value = get_field(s,name,fallback)
if isfield(s,name) && ~isempty(s.(name)), value=s.(name); else, value=fallback; end
end

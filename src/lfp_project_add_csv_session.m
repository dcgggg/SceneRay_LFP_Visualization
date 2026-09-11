function [project, session, importInfo] = lfp_project_add_csv_session(project, subjectId, filePath, sessionInfo, options)
%LFP_PROJECT_ADD_CSV_SESSION Import one CSV and add it as an explicit Session.
%   ImportMode="scenray" uses the block-aware SceneRay importer.  For a
%   generic CSV, pass ImportMode="configured" and an ImportSettings struct
%   accepted by lfp_import_csv_configured.  No Subject/Session identity is
%   inferred from a filename.

arguments
    project (1,1) struct
    subjectId (1,1) string
    filePath (1,1) string
    sessionInfo (1,1) struct = struct()
    options.ImportMode (1,1) string {mustBeMember(options.ImportMode, ["scenray" "configured"])} = "scenray"
    options.ImportSettings (1,1) struct = struct()
    options.Save (1,1) logical = true
end
if ~isfile(filePath), error('LFP:InputFileNotFound', 'CSV file not found: %s', filePath); end
if options.ImportMode == "scenray"
    data = lfp_import_scenray_csv(filePath);
    importInfo = struct('format', "SceneRay", 'filePath', filePath);
else
    if isempty(fieldnames(options.ImportSettings))
        data = lfp_import_csv_configured(filePath);
    else
        args = namedargs2cell(options.ImportSettings);
        data = lfp_import_csv_configured(filePath, args{:});
    end
    importInfo = struct('format', "configured", 'filePath', filePath, 'settings', options.ImportSettings);
end
data.metadata.sourceFilePath = filePath;
[project, session] = lfp_project_add_session(project, subjectId, data, sessionInfo, Save=options.Save);
end

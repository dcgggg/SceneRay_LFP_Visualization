function project = lfp_load_project(projectRoot)
%LFP_LOAD_PROJECT Load and migrate a Project index without touching raw data.

arguments
    projectRoot (1,1) string
end
projectFile = fullfile(projectRoot, "project.mat");
if ~isfile(projectFile)
    error('LFP:ProjectNotFound', 'Project index not found: %s', projectFile);
end
loaded = load(projectFile, 'project');
if ~isfield(loaded, 'project') || ~isstruct(loaded.project)
    error('LFP:InvalidProject', 'project.mat does not contain a Project struct.');
end
project = migrate(loaded.project, projectRoot);
end

function project = migrate(project, projectRoot)
[template, subjectTemplate, sessionTemplate, channelTemplate, runTemplate, comparisonTemplate] = lfp_project_schema();
names = fieldnames(template);
for index = 1:numel(names)
    if ~isfield(project, names{index}), project.(names{index}) = template.(names{index}); end
end
project.rootPath = string(projectRoot);
if isempty(project.schema_version), project.schema_version = 1; end
project.subjects = normalize_array(project.subjects, subjectTemplate);
for s = 1:numel(project.subjects)
    project.subjects(s).sessions = normalize_array(project.subjects(s).sessions, sessionTemplate);
    for k = 1:numel(project.subjects(s).sessions)
        project.subjects(s).sessions(k).channels = normalize_array(project.subjects(s).sessions(k).channels, channelTemplate);
        if isempty(project.subjects(s).sessions(k).analysis_run_ids)
            project.subjects(s).sessions(k).analysis_run_ids = strings(0, 1);
        else
            project.subjects(s).sessions(k).analysis_run_ids = string(project.subjects(s).sessions(k).analysis_run_ids(:));
        end
    end
end
project.analysisRuns = normalize_array(project.analysisRuns, runTemplate);
project.comparisons = normalize_array(project.comparisons, comparisonTemplate);
if ~isfield(project, 'defaultConfig') || isempty(fieldnames(project.defaultConfig))
    project.defaultConfig = lfpDefaultConfig();
end
end

function array = normalize_array(array, template)
if isempty(array), array = template([]); return; end
for index = 1:numel(array)
    fields = fieldnames(template);
    for fieldIndex = 1:numel(fields)
        name = fields{fieldIndex};
        if ~isfield(array, name), array(index).(name) = template.(name); end
    end
end
end

function project = lfp_create_project(projectRoot, name, options)
%LFP_CREATE_PROJECT Create and persist a lightweight LFP project index.
%   PROJECT = LFP_CREATE_PROJECT(ROOT, NAME) creates the Project index and
%   data/results/comparisons directories.  Raw and derived arrays are stored
%   separately; the index contains only metadata and references.

arguments
    projectRoot (1,1) string
    name (1,1) string = "LFP Project"
    options.Description (1,1) string = ""
    options.Config (1,1) struct = struct()
    options.Save (1,1) logical = true
end

if strlength(strtrim(projectRoot)) == 0
    error('LFP:InvalidProjectRoot', 'Project root must not be empty.');
end
if ~isfolder(projectRoot), mkdir(projectRoot); end
[project, ~, ~, ~, ~, ~] = lfp_project_schema();
project.schema_version = 2;
project.project_id = lfp_make_id("project");
project.name = name;
project.description = options.Description;
project.rootPath = string(projectRoot);
project.createdAt = string(datestr(now, 31));
project.updatedAt = project.createdAt;
if isempty(fieldnames(options.Config)), project.defaultConfig = lfpDefaultConfig();
else, project.defaultConfig = options.Config; end
for field = {'data', 'results', 'comparisons'}
    folder = fullfile(projectRoot, project.paths.(field{1}));
    if ~isfolder(folder), mkdir(folder); end
end
if options.Save, lfp_save_project(project); end
end

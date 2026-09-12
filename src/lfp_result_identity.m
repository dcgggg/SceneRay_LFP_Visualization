function info = lfp_result_identity(project, session, run, options)
%LFP_RESULT_IDENTITY Validate whether an AnalysisRun belongs to a request.
%   INFO = LFP_RESULT_IDENTITY(PROJECT,SESSION,RUN) performs the same
%   identity checks used by latest-result lookup, analysis reuse and
%   comparison.  It never changes PROJECT or RUN.  A run is current only
%   when its input data version, enabled-channel snapshot, revisions,
%   computation config and requested products all match.

arguments
    project (1,1) struct %#ok<INUSA>
    session (1,1) struct
    run (1,1) struct
    options.Config (1,1) struct = struct()
    options.RequiredModules (1,1) struct = struct()
end

reasons = strings(0,1);
current = true;
if isfield(run, 'status') && startsWith(string(run.status), "stale")
    current = false; reasons(end+1) = "run_status=" + string(run.status); %#ok<AGROW>
end
if ~isfield(run, 'input_data_version') || string(run.input_data_version) ~= string(get_field(session,'data_version',""))
    current = false; reasons(end+1) = "input_data_version_mismatch"; %#ok<AGROW>
end

targetConfig = options.Config;
if isempty(fieldnames(targetConfig)) && isfield(run, 'config') && isstruct(run.config)
    targetConfig = run.config;
end
if ~isempty(fieldnames(targetConfig))
    if any(struct2array(options.RequiredModules))
        expectedConfigId = lfp_analysis_config_fingerprint(targetConfig, options.RequiredModules);
        % A run may have been created with a superset of requested products,
        % so its stored config_id can include extra fooof/band fields. Compare
        % the candidate's own config projected onto the requested products,
        % rather than requiring the raw (possibly broader) fingerprint to be
        % textually identical.
        candidateConfigId = "";
        if isfield(run,'config') && isstruct(run.config)
            candidateConfigId = lfp_analysis_config_fingerprint(run.config, options.RequiredModules);
        end
    else
        expectedConfigId = lfp_config_fingerprint(targetConfig);
        candidateConfigId = string(get_field(run,'config_id',""));
    end
    if (strlength(candidateConfigId) == 0 || candidateConfigId ~= expectedConfigId) && ...
            (~isfield(run, 'config_id') || string(run.config_id) ~= expectedConfigId)
        current = false; reasons(end+1) = "config_mismatch"; %#ok<AGROW>
    end
end

enabled = true(1, numel(get_field(session,'channels',struct([]))));
channels = get_field(session, 'channels', struct([]));
if ~isempty(channels) && isfield(channels, 'enabled'), enabled = logical([channels.enabled]); end
currentIds = strings(0,1); currentRevisions = strings(0,1);
if ~isempty(channels)
    currentIds = string({channels(enabled).channel_id})';
    currentRevisions = string(get_channel_revisions(channels(enabled)));
end
runIds = string(get_field(run, 'channel_ids', strings(0,1))); runIds = runIds(:);
% A result without a stable channel snapshot cannot be safely relabeled from
% the current Session order (especially after channel removal/reordering).
if ~isequal(runIds, currentIds)
    current = false; reasons(end+1) = "channel_set_mismatch"; %#ok<AGROW>
end
if isfield(run, 'channel_revisions') && ~isempty(run.channel_revisions) && ~isempty(runIds)
    if ~isequal(string(run.channel_revisions(:)), currentRevisions)
        current = false; reasons(end+1) = "channel_revision_mismatch"; %#ok<AGROW>
    end
end

required = normalize_modules(options.RequiredModules);
if any(struct2array(required))
    status = get_field(run, 'module_status', struct());
    for name = ["specparam" "band_power"]
        if required.(char(name)) && ~is_module_success(status, name)
            current = false; reasons(end+1) = "missing_module=" + name; %#ok<AGROW>
        end
    end
end

resultPath = string(get_field(run, 'result_ref', ""));
if strlength(resultPath) == 0 || ~isfile(fullfile(string(project.rootPath), resultPath))
    current = false; reasons(end+1) = "result_file_missing"; %#ok<AGROW>
end
info = struct('isCurrent', logical(current), 'reasons', unique(reasons,'stable'), ...
    'currentChannelIds', currentIds, 'currentChannelRevisions', currentRevisions, ...
    'runChannelIds', runIds, 'requiredModules', required);
end

function modules = normalize_modules(value)
modules = struct('specparam', false, 'band_power', false);
if ~isstruct(value), return; end
if isfield(value,'specparam'), modules.specparam = logical(value.specparam); end
if isfield(value,'band_power'), modules.band_power = logical(value.band_power); end
end

function tf = is_module_success(status, name)
tf = false;
if ~isstruct(status) || ~isfield(status, char(name)), return; end
tf = ismember(string(status.(char(name))), ["ok" "ok_no_channels"]);
end

function revisions = get_channel_revisions(channels)
revisions = strings(numel(channels),1);
for k = 1:numel(channels)
    if isfield(channels(k),'data_revision'), revisions(k) = string(channels(k).data_revision); end
end
end

function value = get_field(s, name, fallback)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = fallback; end
end

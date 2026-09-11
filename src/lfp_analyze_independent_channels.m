function [project, run, results, statusSummary] = lfp_analyze_independent_channels(project, sessionId, cfg, options)
%LFP_ANALYZE_INDEPENDENT_CHANNELS Analyze enabled Session channels separately.
%   Each channel has an isolated result payload. No padding, resampling or
%   cross-channel concatenation enters the analysis.

arguments
    project (1,1) struct
    sessionId (1,1) string
    cfg (1,1) struct
    options.ComputeSpecparam (1,1) logical = true
    options.ComputeBandPower (1,1) logical = true
    options.Save (1,1) logical = true
    options.Force (1,1) logical = false
    options.ProgressCallback = []
end
[session, ~, si, ki] = lfp_project_find_session(project, sessionId);
if isempty(session), error('LFP:SessionNotFound', 'Session ID not found: %s', sessionId); end
configId = lfp_config_fingerprint(cfg);
run = struct('run_id',lfp_make_id('run'),'session_id',sessionId,'input_data_version',string(session.data_version), ...
    'channel_ids',string({session.channels.channel_id})','channel_labels',string({session.channels.original_label})', ...
    'analysis_time_range',[NaN NaN],'config',cfg,'config_id',configId,'software_version',"SceneRay-LFP v"+string(cfg.version), ...
    'created_at',string(datestr(now,31)),'module_status',struct('artifact',"ok",'psd',"ok",'specparam',"ok",'band_power',"ok"), ...
    'result_ref',"",'summary',struct(),'status',"running",'warnings',strings(0,1),'channel_results',struct([]));
channelResults = repmat(struct('channel_id',"",'channel_label',"",'status',"",'data_revision',"", ...
    'artifactResult',struct(),'psdResult',struct(),'modelResult',struct([]),'bandResult',struct(), ...
    'warnings',strings(0,1),'result_ref',""),0,1);
enabledMask = true(1,numel(session.channels));
for k=1:numel(session.channels)
    if isfield(session.channels(k),'enabled'), enabledMask(k)=logical(session.channels(k).enabled); end
end
for k=find(enabledMask)
    channel = session.channels(k);
    if ~isempty(options.ProgressCallback), options.ProgressCallback((k-1)/max(numel(session.channels),1), "Channel " + string(channel.original_label)); end
    one = struct('channel_id',string(channel.channel_id),'channel_label',string(channel.original_label),'status',"failed", ...
        'data_revision',string(get_field(channel,'data_revision',session.data_version)),'artifactResult',struct(), ...
        'psdResult',struct(),'modelResult',struct([]),'bandResult',struct(),'warnings',strings(0,1),'result_ref',"");
    if ~options.Force
        cached = find_reusable_channel(project, sessionId, channel, configId);
        if ~isempty(cached)
            one = cached; channelResults(end+1,1)=one; %#ok<AGROW>
            continue;
        end
    end
    try
        data = lfp_project_get_channel_data(project, sessionId, string(channel.channel_id));
        result = lfp_analyze_one_channel(data, cfg, ComputeSpecparam=options.ComputeSpecparam, ComputeBandPower=options.ComputeBandPower);
        one.artifactResult=result.artifactResult; one.psdResult=result.psdResult; one.modelResult=result.modelResult; one.bandResult=result.bandResult; one.status=result.status; one.warnings=result.warnings;
        folder = channel_result_folder(project, session); if ~isfolder(folder), mkdir(folder); end
        channelFile = fullfile(folder, run.run_id + "_" + string(channel.channel_id) + ".mat");
        channelPayload = struct('channel_id',channel.channel_id,'data_revision',one.data_revision,'result',one,'saved_at',string(datestr(now,31))); %#ok<NASGU>
        temp=channelFile+".tmp_"+lfp_make_id('channel_result');cleanup=onCleanup(@()delete_if_present(temp));save(temp,'channelPayload','-v7');movefile(temp,channelFile,'f');clear cleanup
        one.result_ref = relative_to_root(project, channelFile);
    catch exception
        one.status="failed"; one.warnings(end+1,1)=string(exception.message);
    end
    channelResults(end+1,1)=one; %#ok<AGROW>
end
for k=find(~enabledMask)
    channel=session.channels(k);
    channelResults(end+1,1)=struct('channel_id',string(channel.channel_id),'channel_label',string(channel.original_label), ...
        'status',"disabled",'data_revision',string(get_field(channel,'data_revision',session.data_version)),'artifactResult',struct(), ...
        'psdResult',struct(),'modelResult',struct([]),'bandResult',struct(),'warnings',"Channel disabled by user.",'result_ref',""); %#ok<AGROW>
end
run.channel_results = rmfield(channelResults, {'artifactResult','psdResult','modelResult','bandResult'});
run.summary = struct('channel_count',numel(session.channels),'enabled_channel_count',nnz(enabledMask), ...
    'successful_channel_count',nnz(string({channelResults.status})=="ok"),'failed_channel_count',nnz(string({channelResults.status})=="failed"));
run.module_status = aggregate_status(channelResults, options.ComputeSpecparam, options.ComputeBandPower);
run.status = aggregate_run_status(channelResults);
run.result_ref = session_result_ref(project, session, run.run_id);
results = struct('channelResults',channelResults,'psdResult',struct(),'modelResult',struct([]),'bandResult',struct(), ...
    'artifactResult',struct(),'metadata',struct('independentChannels',true),'processingHistory',struct());
valid = find(string({channelResults.status})=="ok",1);
if ~isempty(valid), results.psdResult=channelResults(valid).psdResult; results.modelResult=channelResults(valid).modelResult; results.bandResult=channelResults(valid).bandResult; results.artifactResult=channelResults(valid).artifactResult; end
resultPath = fullfile(string(project.rootPath), run.result_ref); if ~isfolder(fileparts(resultPath)), mkdir(fileparts(resultPath)); end
payload = struct('run',run,'channelResults',channelResults,'psdResult',results.psdResult,'modelResult',results.modelResult, ...
    'bandResult',results.bandResult,'artifactResult',results.artifactResult,'metadata',results.metadata); %#ok<NASGU>
temp=resultPath+".tmp_"+lfp_make_id('result');cleanup=onCleanup(@()delete_if_present(temp));save(temp,'payload','-v7');movefile(temp,resultPath,'f');clear cleanup
project.analysisRuns(end+1)=normalize_run(run);
project.subjects(si).sessions(ki).analysis_run_ids(end+1,1)=run.run_id;
project.subjects(si).sessions(ki).status="analyzed";
statusSummary=struct('sessionId',sessionId,'status',run.status,'runId',run.run_id,'configId',configId,'errorMessage',"",'errorIdentifier',"",'warnings',run.warnings);
if options.Save, lfp_save_project(project); end
end

function run=normalize_run(run)
[~,~,~,~,template,~]=lfp_project_schema(); names=fieldnames(template); for k=1:numel(names), if ~isfield(run,names{k}), run.(names{k})=template.(names{k}); end, end
end
function folder=channel_result_folder(project,session)
if isfield(session,'folder_relative_path')&&strlength(string(session.folder_relative_path))>0, folder=fullfile(string(project.rootPath),session.folder_relative_path,'results','channels'); else, folder=fullfile(string(project.rootPath),'results','channels'); end
end
function path=relative_to_root(project,absolutePath)
root=char(string(project.rootPath)); p=char(string(absolutePath)); if startsWith(p,[root filesep]), path=string(p(numel(root)+2:end)); else, path=string(absolutePath); end
end
function path=session_result_ref(project,session,runId)
if isfield(session,'folder_relative_path')&&strlength(string(session.folder_relative_path))>0, path=fullfile(string(session.folder_relative_path),'results',runId+'.mat'); else, path=fullfile('results',runId+'.mat'); end
end
function status=aggregate_run_status(results)
states=string({results.status}); if isempty(states)||all(states=="disabled"), status="failed"; elseif any(states=="failed"), status="partial_failure"; else, status="ok"; end
end
function status=aggregate_status(results,doSpec,doBand)
states=string({results.status}); if any(states=="failed"), state="partial"; else, state="ok"; end
status=struct('artifact',state,'psd',state,'specparam',ternary(doSpec,state,"not_requested"),'band_power',ternary(doBand,state,"not_requested"));
end
function value=get_field(s,n,f)
if isstruct(s)&&isfield(s,n)&&~isempty(s.(n)), value=s.(n); else, value=f; end
end
function value=ternary(c,a,b)
if c, value=a; else, value=b; end
end
function one=find_reusable_channel(project,sessionId,channel,configId)
one=[];
for k=numel(project.analysisRuns):-1:1
    run=project.analysisRuns(k);
    if string(run.session_id)~=sessionId||string(run.config_id)~=configId||~isfield(run,'channel_results')||isempty(run.channel_results),continue;end
    idx=find(string({run.channel_results.channel_id})==string(channel.channel_id)&string({run.channel_results.data_revision})==string(get_field(channel,'data_revision',"")),1);
    if isempty(idx),continue;end
    ref=string(run.channel_results(idx).result_ref);if strlength(ref)==0||~isfile(fullfile(string(project.rootPath),ref)),continue;end
    loaded=load(fullfile(string(project.rootPath),ref),'channelPayload');if ~isfield(loaded,'channelPayload')||~isfield(loaded.channelPayload,'result'),continue;end
    one=loaded.channelPayload.result;return;
end
end
function delete_if_present(path)
if isfile(path), delete(path); end
end

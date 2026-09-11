function relativePath = lfp_project_write_channel_manifest(project, session)
%LFP_PROJECT_WRITE_CHANNEL_MANIFEST Persist the channel/cache manifest.
%   The project index remains authoritative, while this lightweight manifest
%   lets tools inspect a Session's cache inventory without loading samples.

arguments
    project (1,1) struct
    session (1,1) struct
end
if isfield(session,'folder_relative_path') && strlength(string(session.folder_relative_path)) > 0
    relativePath = fullfile(string(session.folder_relative_path),'data','channel_manifest.mat');
else
    relativePath = fullfile('data','channel_manifest_'+string(session.session_id)+'.mat');
end
target = fullfile(string(project.rootPath),relativePath); if ~isfolder(fileparts(target)),mkdir(fileparts(target));end
manifest = struct('session_id',session.session_id,'data_version',get_field(session,'data_version',''), ...
    'channels',session.channels,'data_refs',session.data_refs,'saved_at',string(datestr(now,31)), ...
    'schema_version',get_field(project,'schema_version',4)); %#ok<NASGU>
temp=target+'.tmp_'+lfp_make_id('manifest');cleanup=onCleanup(@()delete_if_present(temp));save(temp,'manifest','-v7');movefile(temp,target,'f');
end
function value=get_field(s,n,f),if isstruct(s)&&isfield(s,n)&&~isempty(s.(n)),value=s.(n);else,value=f;end,end
function delete_if_present(path),if isfile(path),delete(path);end,end

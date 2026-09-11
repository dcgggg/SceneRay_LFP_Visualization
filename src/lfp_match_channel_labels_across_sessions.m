function report = lfp_match_channel_labels_across_sessions(project, sessionIds, channelLabel)
%LFP_MATCH_CHANNEL_LABELS_ACROSS_SESSIONS Resolve exact display/original labels.
%   No fallback-to-first-channel is used. REPORT.entries records found,
%   missing and ambiguous matches so a GUI can require explicit correction.

arguments
    project (1,1) struct
    sessionIds string
    channelLabel (1,1) string
end
sessionIds = string(sessionIds(:));
entries = repmat(struct('session_id',"",'subject_id',"",'channel_label',channelLabel, ...
    'channel_id',"",'status',"missing",'candidates',strings(0,1)),0,1);
for k=1:numel(sessionIds)
    [session,subject]=lfp_project_find_session(project,sessionIds(k));
    entry=struct('session_id',sessionIds(k),'subject_id',"",'channel_label',channelLabel,'channel_id',"",'status',"missing",'candidates',strings(0,1));
    if isempty(session),entries(end+1)=entry;continue;end
    entry.subject_id=string(subject.subject_id);original=string({session.channels.original_label});display=string({session.channels.display_label});
    matches=find(original==channelLabel|display==channelLabel);
    entry.candidates=string({session.channels(matches).channel_id})';
    if numel(matches)==1,entry.channel_id=string(session.channels(matches).channel_id);entry.status="found";elseif numel(matches)>1,entry.status="ambiguous";end
    entries(end+1)=entry;
end
report=struct('channelLabel',channelLabel,'entries',entries,'foundCount',nnz(string({entries.status})=="found"), ...
    'missingCount',nnz(string({entries.status})=="missing"),'ambiguousCount',nnz(string({entries.status})=="ambiguous"), ...
    'ready',all(string({entries.status})=="found"));
end

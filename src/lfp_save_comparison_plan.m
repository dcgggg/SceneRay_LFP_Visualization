function [project, plan] = lfp_save_comparison_plan(project, comparisonSpec, options)
%LFP_SAVE_COMPARISON_PLAN Persist a comparison selection without computing.

arguments
    project (1,1) struct
    comparisonSpec (1,1) struct
    options.Save (1,1) logical = true
end
[~, ~, ~, ~, ~, plan] = lfp_project_schema();
plan.comparison_id = lfp_make_id("comparison_plan");
plan.type = string(get_field(comparisonSpec, 'type', "custom"));
plan.session_ids = string(get_field(comparisonSpec, 'session_ids', strings(0,1))); plan.session_ids = plan.session_ids(:);
plan.subject_ids = string(get_field(comparisonSpec, 'subject_ids', strings(0,1))); plan.subject_ids = plan.subject_ids(:);
plan.visit_label = string(get_field(comparisonSpec, 'visit_label', ""));
plan.channel_mapping = get_field(comparisonSpec, 'channel_mapping', struct([]));
plan.metric = string(get_field(comparisonSpec, 'metric', "totalPower"));
plan.bands = string(get_field(comparisonSpec, 'bands', strings(0,1))); plan.bands = plan.bands(:);
plan.aggregation = string(get_field(comparisonSpec, 'aggregation', "session"));
plan.plot_settings = get_field(comparisonSpec, 'plot_settings', struct());
plan.target_config_id = string(get_field(comparisonSpec, 'target_config_id', ""));
plan.created_at = string(datestr(now, 31));
plan.status = "plan";
project.comparisons(end + 1) = plan;
if options.Save, lfp_save_project(project); end
end

function value = get_field(source, name, fallback)
if isfield(source, name) && ~isempty(source.(name)), value = source.(name); else, value = fallback; end
end

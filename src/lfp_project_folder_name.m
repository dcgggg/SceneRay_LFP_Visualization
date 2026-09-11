function folderName = lfp_project_folder_name(displayName, stableId, label)
%LFP_PROJECT_FOLDER_NAME Build a readable, collision-resistant relative name.
%   The display name remains visible while the stable ID keeps folders
%   unique when display names repeat.  Neither input is silently sanitized.

arguments
    displayName (1,1) string
    stableId (1,1) string
    label (1,1) string = "对象"
end

displayName = lfp_validate_folder_name(displayName, label + "显示名称");
stableId = lfp_validate_folder_name(stableId, label + "稳定 ID");
folderName = displayName + "__" + stableId;
end

function value = lfp_validate_folder_name(value, label)
%LFP_VALIDATE_FOLDER_NAME Validate a user-visible project folder component.
%   VALUE is returned trimmed but otherwise unchanged.  Path separators,
%   Windows reserved device names, trailing dots/spaces and control
%   characters are rejected rather than silently rewritten.

arguments
    value (1,1) string
    label (1,1) string = "文件夹名称"
end

value = strtrim(value);
if strlength(value) == 0
    error('LFP:InvalidFolderName', '%s不能为空。', label);
end
if any(ismissing(value)) || any(double(char(value)) < 32)
    error('LFP:InvalidFolderName', '%s包含控制字符。', label);
end
if ~isempty(regexp(char(value), '[<>:"/\\|?*]', 'once'))
    error('LFP:InvalidFolderName', '%s包含Windows不允许的路径字符：%s。', label, value);
end
if endsWith(value, ["." " "]) || value == "." || value == ".."
    error('LFP:InvalidFolderName', '%s不能以点或空格结尾，也不能为点路径。', label);
end
stem = upper(extractBefore(value + ".", "."));
reserved = ["CON" "PRN" "AUX" "NUL" "COM1" "COM2" "COM3" "COM4" "COM5" "COM6" "COM7" "COM8" "COM9" "LPT1" "LPT2" "LPT3" "LPT4" "LPT5" "LPT6" "LPT7" "LPT8" "LPT9"];
if any(stem == reserved)
    error('LFP:InvalidFolderName', '%s使用了Windows保留设备名：%s。', label, value);
end
end

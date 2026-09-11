function name = get_filename_local(path)
[~,name,ext] = fileparts(char(path)); name = string([name ext]);
end

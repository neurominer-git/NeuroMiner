function spmver = nk_CheckSPMver

spmver = 0;

% If running as a compiled application, skip the SPM version check
if isdeployed
    spmver = 1;
    return;
end

% Check SPM installation and version (non-deployed MATLAB)
if ~isempty(which('spm'))
    try
        ver = spm('ver');
        if any(strcmp(ver, {'SPM5','SPM8','SPM12'}))
            spmver = 1;
        end
    catch
        spmver = 0;
    end
end

end


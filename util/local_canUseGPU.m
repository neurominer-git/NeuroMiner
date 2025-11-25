function tf = local_canUseGPU()
% Return true if a usable GPU is available; false otherwise.
tf = false;
try
    % Quick checks without throwing hard errors on systems without PCT
    if exist('gpuDeviceCount','file') == 2 && gpuDeviceCount > 0
        d = gpuDevice(); 
        tf = true;
    end
catch
    tf = false;
end
end

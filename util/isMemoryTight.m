function overThreshold = isMemoryTight(thresh)
% isMemoryTight  returns true when MATLAB has used more than thresh fraction of its max heap.
%   thresh should be between 0 and 1 (e.g. 0.8 for 80%).
%
%   On Windows this uses the built-in memory() call, on Linux/Mac we fall back to Java.

    if ispc
        [u,s] = memory; 
        used  = u.MemUsedMATLAB; 
        avail = s.PhysicalMemory.Available;
    else
        rt    = java.lang.Runtime.getRuntime();
        used  = rt.totalMemory() - rt.freeMemory();
        avail = rt.maxMemory();
    end

    overThreshold = (double(used) / double(avail)) > thresh;
end
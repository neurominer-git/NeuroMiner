function decompfl = nk_DetIfDimRefInPREPROC(PREPROC, varind)

if iscell(PREPROC) 
    if ~exist("varind",'var') || isempty(varind), varind = 1; end
    PREPROC = PREPROC{varind}; 
end
DIMRED = {'reducedim', 'remvarcomp'};
decompfl = false; 

if isfield(PREPROC,'ACTPARAM')
    for zu = numel(PREPROC.ACTPARAM) : -1 : 1
        if any(contains(DIMRED, PREPROC.ACTPARAM{zu}.cmd)), decompfl = true; end
    end
end
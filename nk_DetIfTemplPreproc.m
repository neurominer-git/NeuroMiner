function [tmplfl, templateflag] = nk_DetIfTemplPreproc(inp)
global FUSION

nM = numel(inp.tF); 
templateflag = false(1,nM);

for i=1:nM
    switch FUSION.flag
        case 2
            iPREPROC = inp.PREPROC{i}; 
        otherwise
            iPREPROC = inp.PREPROC;
    end
    
    if isfield(iPREPROC,'TEMPLPROC') && iPREPROC.TEMPLPROC
        templateflag(i) = true;
    else
        templateflag(i) = false;
    end 

end

if any(templateflag), tmplfl = true; else, tmplfl = false; end
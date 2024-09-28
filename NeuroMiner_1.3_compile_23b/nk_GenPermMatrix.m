function indpermA = nk_GenPermMatrix(CV, inp)
% =========================================================================
% function indpermA = nk_GenPermMatrix(CV, inp)
% =========================================================================
% Generate permutation matrix for use in nk_VisModels and nk_OOCV
% -------------------------------------------------------------------------
% (c) Nikolaos Koutsouleris, 04/2024

fprintf('\nCreating parent permutation matrix with %g perms', inp.PERM.nperms(1))
if inp.nclass > 1
    for h=1:inp.nclass
        if h==1, indpermA = cell(1, inp.nclass); end
        if isscalar(CV.class{1,1}{1}.groups)
            % One-vs-all
            lb = [find(inp.labels == CV.class{1,1}{h}.groups(1)); find(inp.labels ~= CV.class{1,1}{h}.groups(1))];  
        else
            % One-vs-one
            lb = [find(inp.labels == CV.class{1,1}{h}.groups(1)); find(inp.labels == CV.class{1,1}{h}.groups(2))]; 
        end
        indpermA{h} = zeros(size(inp.labels,1), inp.PERM.nperms(1));
        indpermAh = nk_VisXPermHelper('genpermlabel', size(lb,1), inp.PERM.nperms(1), lb);
        for ii=1:inp.PERM.nperms(1)
            indpermA{h}(lb,ii) = lb(indpermAh(:,ii));
        end
    end
else
    indpermA = nk_VisXPermHelper('genpermlabel', size(inp.labels,1), inp.PERM.nperms(1), inp.labels);
end


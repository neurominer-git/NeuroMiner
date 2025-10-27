function [indperm,s] = nk_VisXPermHelper(act, N, nperms, L)

s = RandStream.create('mt19937ar','seed',sum(100*clock));
RandStream.setGlobalStream(s);

switch act
    case 'genpermlabel'
        indperm = zeros(N, nperms);
        if exist('L','var') && ~isempty(L)
            uL = unique(L); nuL = numel(uL);
            if nuL<=20
                for perms = 1:nperms
                    vec = (1:N)';
                    for n = 1:nuL
                        Nn = length(vec);
                        idxl = L==uL(n);
                        idxn = randperm(Nn,sum(idxl));
                        indperm(idxl,perms) = vec(idxn);
                        vec(idxn) = [];
                    end
                end
            else
                for perms = 1:nperms
                    indperm(:,perms) = randperm(N); 
                end
            end
        else
            for perms = 1:nperms
                indperm(:,perms) = randperm(N); 
            end
        end
    case 'genpermfeats'
        uL = unique(L); nuL = numel(uL);
        indperm = zeros(nuL, N, nperms);
        for i = 1:nuL
            for perms = 1:nperms
                indperm(i,:,perms) = randperm(N);
            end
        end  
end



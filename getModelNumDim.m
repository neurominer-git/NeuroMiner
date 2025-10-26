function [D, F] = getModelNumDim(h, iy, jy, nP, Pspos, GDFEAT)
    
D=0; F=0;
for m = 1 : nP % Parameter combinations
    for k=1:iy % permutations
        for l=1:jy % folds
            D = D + size(GDFEAT{Pspos(m)}{k,l,h},2);
            if size(GDFEAT{Pspos(m)}{k,l,h},1) > F
                F=size(GDFEAT{Pspos(m)}{k,l,h},1) ;
            end
        end
    end     
end
function GD = nk_GenVI(mapYi, GD, CV, f, d, nclass, idx, curlabel)

    if isfield(mapYi,'VI')
    
        [iy,jy] = size(CV(1).cvin{f,d}.TrainInd);
        
        GD.VI{idx, curlabel} = cell(iy,jy,nclass);
        for k=1:iy
            for l=1:jy
                if iscell(mapYi.VI{k,l})
                     for curclass = 1:nclass
                        VI = repmat(mapYi.VI{k,l}{curclass},1,size(GD.FEAT{idx, curlabel}{k,l,curclass},2));
                        GD.VI{idx, curlabel}{k,l,curclass} = VI;
                     end
                else
                    for curclass = 1:nclass
                        VI = repmat(mapYi.VI{k,l},1,size(GD.FEAT{idx, curlabel}{k,l,curclass},2));
                        GD.VI{idx, curlabel}{k,l,curclass} = VI;
                    end
                end                            
            end
        end
    end

end
function out = nk_DealWithNaNCases(out, iy, jy, nclass, DealWithCompleteNanRows)
global VERBOSE 

% In the future the user should be able to define the imputation setting in
% nk_Fusion_config
if DealWithCompleteNanRows == 2
    IN.method = 'SeqkNN';
    IN.k = 5;
end
if ~iscell(out.Tr{1,1}{1}) 
    multiproc = true;
    nZo = height(out.Tr{1,1}); 
    t_nclass = 1;
else
    multiproc = false;
    nZo = height(out.Tr{1,1}{1});
    t_nclass = nclass;
end

% This should be replace for multiple kernel learning scenarios with an
% appropriate logic
nM=1; modalstr = '';

for k=1:iy
    for l=1:jy
        for j = 1:t_nclass
            fprintf('\nVisiting CV1 [ permutation: %g, fold: %g, class: %g ]', k, l, j); 
            for i=1:nZo 
                for m=1:nM
                    %% Extract data from container
                    if nM>1
                        modalstr = sprintf('Modality #%g:', m); 
                        if multiproc
                            outTr = out.Tr{k,l}{i}{m};
                            outCV = out.CV{k,l}{i}{m};
                            outTs = out.Ts{k,l}{i}{m};                    
                        else
                            outTr = out.Tr{k,l}{j}{i}{m};
                            outCV = out.CV{k,l}{j}{i}{m};
                            outTs = out.Ts{k,l}{j}{i}{m}; 
                        end
                    else
                        if multiproc
                            outTr = out.Tr{k,l}{i};
                            outCV = out.CV{k,l}{i};
                            outTs = out.Ts{k,l}{i};                    
                        else
                            outTr = out.Tr{k,l}{j}{i};
                            outCV = out.CV{k,l}{j}{i};
                            outTs = out.Ts{k,l}{j}{i}; 
                        end
                    end

                    %% Find missings
                    idx_Tr = sum(isnan(outTr),2)>0;
                    idx_CV = sum(isnan(outCV),2)>0;
                    idx_Ts = sum(isnan(outTs),2)>0;

                    if ~any(idx_Tr) && ~any(idx_CV) && ~any(idx_Ts)
                        if VERBOSE
                            fprintf('\n%sNo missing data found in CV1 [ permutation: %g, fold: %g, class: %g, shelf: %g] to NaN', modalstr, k, l, j); 
                        end
                        continue
                    end
                    
                    %% Address missings
                    switch DealWithCompleteNanRows                    
                        case 1 % Set rows to complete NaN if NaNs are found
                            if VERBOSE, fprintf('\n%sSetting cases in CV1 [ permutation: %g, fold: %g, class: %g, shelf: %g] to NaN', modalstr, k, l, j, i); end
                            outTr(idx_Tr,:) = nan;
                            outCV(idx_CV,:) = nan;
                            outTs(idx_Ts,:) = nan; 
                        
                        case 2 % Impute missing data
                            if VERBOSE, fprintf('\n%sImputing missing data in CV1 [ permutation: %g, fold: %g, class: %g, shelf: %g] to NaN', modalstr, k, l, j, i); end
                            IN.blockind = 1:width(out.Tr{k,l}{j}{i});
                            IN.X = outTr;
                            [outTr, IN] = nk_PerfImputeObj(outTr, IN);
                            IN.X = outTr;
                            outCV = nk_PerfImputeObj(outCV, IN);
                            outTs = nk_PerfImputeObj(outTs, IN);
                    end
                    
                    %% Write managed data back to container
                    if nM>1
                        if multiproc
                            out.Tr{k,l}{i}{m} = outTr;
                            out.CV{k,l}{i}{m} = outCV;
                            out.Ts{k,l}{i}{m} = outTs;                    
                        else
                            out.Tr{k,l}{i}{j}{m} = outTr;
                            out.CV{k,l}{i}{j}{m} = outCV;
                            out.Ts{k,l}{i}{j}{m} = outTs; 
                        end
                    else
                        if multiproc
                            out.Tr{k,l}{i} = outTr;
                            out.CV{k,l}{i} = outCV;
                            out.Ts{k,l}{i} = outTs;                    
                        else
                            out.Tr{k,l}{i}{j} = outTr;
                            out.CV{k,l}{i}{j} = outCV;
                            out.Ts{k,l}{i}{j} = outTs; 
                        end
                    end
                end
            end
        end
    end
end
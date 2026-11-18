function out = nk_DealWithNaNCases_OOCV(out, iy, jy, nclass, DealWithCompleteNanRows)
% nk_DealWithNaNCases_OOCV  Handle missing data in OOCV-only prediction sets (no Tr or CV)
%
%   out = nk_DealWithNaNCases_OOCV(out, iy, jy, nclass, DealWithCompleteNanRows)
%
% Inputs:
%   out  - Structure containing only field .Ts with OOCV test data
%   iy, jy - number of permutations (CV1 repeats) and folds
%   nclass - number of classes (1 for regression/binary)
%   DealWithCompleteNanRows - 1 = set NaN rows to all NaN, 2 = impute
%
% Output:
%   out - modified out struct with missing data handled
%
% Notes:
%   Requires global VERBOSE.
%   Assumes out.Ts{k,l}{j}{i} or out.Ts{k,l}{i} structure.

global VERBOSE

% Determine data layout (multiproc = flat list vs nested for classes)
if ~iscell(out.Ts{1,1}{1})
    multiproc = true;
    nZo = height(out.Ts{1,1});
    t_nclass = 1;
else
    multiproc = false;
    nZo = height(out.Ts{1,1}{1});
    t_nclass = nclass;
end

% Imputation setup if needed
if DealWithCompleteNanRows == 2
    IN.method = 'SeqkNN';
    IN.k = 5;
end

% Loop through structure
for k = 1:iy
    for l = 1:jy
        for j = 1:t_nclass
            for i = 1:nZo
                % Extract test data
                if multiproc
                    outTs = out.Ts{k,l}{i};
                else
                    outTs = out.Ts{k,l}{j}{i};
                end

                % Find rows with any NaNs
                idx_Ts = any(isnan(outTs),2);

                if ~any(idx_Ts)
                    if VERBOSE
                        fprintf('\nNo missing data in OOCV [perm=%g, fold=%g, class=%g, shelf=%g]', k, l, j, i);
                    end
                    continue
                end

                % Handle missings
                switch DealWithCompleteNanRows
                    case 1
                        if VERBOSE
                            fprintf('\nSetting NaNs in OOCV [perm=%g, fold=%g, class=%g, shelf=%g] to full NaN rows', k, l, j, i);
                        end
                        outTs(idx_Ts,:) = NaN;

                    case 2
                        if VERBOSE
                            fprintf('\nImputing NaNs in OOCV [perm=%g, fold=%g, class=%g, shelf=%g]', k, l, j, i);
                        end
                        IN.X = outTs;
                        IN.blockind = 1:width(outTs);
                        outTs = nk_PerfImputeObj(outTs, IN);
                end

                % Write back
                if multiproc
                    out.Ts{k,l}{i} = outTs;
                else
                    out.Ts{k,l}{j}{i} = outTs;
                end
            end
        end
    end
end

function [A,Q] = nk_Diversity_masked(Ccorr, RelMask)
[~,n] = size(Ccorr);
if n < 2, A = NaN; Q = NaN; return; end
DFsum = 0; Qsum = 0; nDF = 0; nQ = 0;
for i = 1:n-1
    ci = Ccorr(:,i); mi = RelMask(:,i);
    for j = i+1:n
        cj = Ccorr(:,j); mj = RelMask(:,j);
        idx = mi & mj & ~isnan(ci) & ~isnan(cj);
        m = nnz(idx); if m==0, continue; end
        xi = logical(ci(idx)); xj = logical(cj(idx));
        N11 = sum( xi &  xj);
        N00 = sum(~xi & ~xj);
        N10 = sum( xi & ~xj);
        N01 = sum(~xi &  xj);
        DFsum = DFsum + (N00 / m); nDF = nDF + 1;
        denom = (N11*N00 + N10*N01);
        if denom > 0
            Qsum = Qsum + (N11*N00 - N10*N01)/denom; nQ = nQ + 1;
        end
    end
end
A = (nDF>0) * (DFsum / max(nDF,1)) + (nDF==0)*NaN;
Q = (nQ>0)  * (Qsum / max(nQ,1))   + (nQ==0)*0;
end

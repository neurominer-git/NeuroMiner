function kappa = nk_DiversityKappa_masked(Ccorr, RelMask)
% Fleiss' kappa over correctness with varying #raters (mask).
% Ccorr,RelMask: N x n, Ccorr∈{0,1,NaN}, RelMask true where valid
N = size(Ccorr,1);
Pi_sum = 0; n_items = 0;
sum_correct = 0; sum_total = 0;
for i = 1:N
    m = RelMask(i,:) & ~isnan(Ccorr(i,:));
    ni = nnz(m);
    if ni < 2, continue; end
    ci = Ccorr(i,m);
    s  = sum(ci);                 % #correct
    Pi = ( s*(s-1) + (ni-s)*(ni-s-1) ) / (ni*(ni-1));
    Pi_sum = Pi_sum + Pi;
    n_items = n_items + 1;
    sum_correct = sum_correct + s;
    sum_total   = sum_total + ni;
end
if n_items == 0
    kappa = NaN; return;
end
Pbar = Pi_sum / n_items;
pc   = sum_correct / max(1,sum_total);
Pe   = pc^2 + (1-pc)^2;
if abs(1 - Pe) < eps
    kappa = NaN;
else
    kappa = (Pbar - Pe) / (1 - Pe);
end
end

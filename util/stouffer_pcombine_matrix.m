function p_comb = stouffer_pcombine_matrix(pvals)
% Combines one-tailed p-values row-wise using Stouffer's method.
% Input:  pvals (n_components x n_folds) - matrix of p-values [0,1]
% Output: p_comb (n_components x 1) - combined one-tailed p-value

    % Force valid range
    pvals(pvals <= 0) = realmin;  % avoid -Inf from norminv(0)
    pvals(pvals >= 1) = 1 - eps;  % avoid Inf from norminv(1)

    % Convert p-values to Z-scores (one-sided)
    z = norminv(1 - pvals);

    % Zero out NaN contributions
    z(~isfinite(z)) = 0;

    % Count valid entries per row
    k = sum(isfinite(pvals), 2);

    % Combine
    z_comb = sum(z, 2) ./ sqrt(k);

    % Convert back to one-tailed p-values
    p_comb = 1 - normcdf(z_comb);

    % If no valid entries, return NaN
    p_comb(k == 0) = NaN;
end

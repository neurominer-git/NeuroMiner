function p_combined = fisher_pcombine_matrix(pvals)
% Combine p-values across columns (e.g., folds) using Fisher's method.
% Input:  pvals [n_components x n_folds] matrix of p-values (can include NaNs)
% Output: p_combined [n_components x 1] vector of combined p-values

    [nrows, ~] = size(pvals);
    p_combined = nan(nrows, 1);

    for i = 1:nrows
        p = pvals(i, :);
        p = p(~isnan(p));  % remove NaNs

        if isempty(p)
            continue;
        end

        % Ensure all p-values are in (0,1) to avoid log(0)
        p = max(min(p, 1 - 1e-15), 1e-15);

        % Fisher's statistic: -2 * sum(log(p))
        X2 = -2 * sum(log(p));
        df = 2 * numel(p);

        % Combined p-value from chi-squared distribution
        p_combined(i) = 1 - chi2cdf(X2, df);
    end
end

function W = nk_WeigthDataInstanceHisto(L)
% =========================================================================
% FORMAT W = nk_WeigthDataInstanceHisto(L)
% =========================================================================
% Inverse-density instance weights (tail-sensitive), no toolboxes required.
% - Computes a simple Gaussian KDE of the NON-NaN labels L.
% - Sets weight_i = 1 / p(L_i), then normalizes weights to have mean 1.
% - NaN labels receive weight 0 (ignored in training).
% -------------------------------------------------------------------------
% Complexity: O(n^2) in the number of valid (non-NaN) labels. For very
% large n, consider a binned/interpolated approximation.
% =========================================================================
% (c) Nikolaos Koutsouleris, 09/2025

    % Empty input handling
    if isempty(L)
        W = [];
        return;
    end

    % Column vector
    L = L(:);

    % Valid mask (ignore NaNs)
    validMask = ~isnan(L);
    Y = L(validMask);

    % If no valid labels, return zeros (ignored)
    if isempty(Y)
        W = zeros(size(L));
        return;
    end

    % ---------------------------------------------------------------------
    % Manual Gaussian KDE at each observed point (no toolboxes)
    % ---------------------------------------------------------------------
    n = numel(Y);
    s = std(Y);
    if s == 0
        % Constant labels: assign uniform weights
        W = zeros(size(L));
        W(validMask) = 1;                % mean will be 1 after normalization below
        % Normalize to mean 1
        W(validMask) = W(validMask) * (n / sum(W(validMask)));
        return;
    end

    % Silverman's rule-of-thumb bandwidth
    h = 1.06 * s * n^(-1/5);
    if h <= eps
        h = max(s, 1) * n^(-1/5);
    end

    % Pairwise differences and Gaussian kernel
    % NOTE: O(n^2); fine for up to a few thousands.
    D = Y - Y.';                                    % n x n
    K = exp(-0.5*(D./h).^2) / (sqrt(2*pi)*h);       % Gaussian kernel
    p = mean(K, 2);                                  % density at each Y_i

    % Avoid division by zero
    p(p <= eps) = eps;

    % Inverse-density weights
    w = 1 ./ p;

    % Normalize weights to have mean 1 (stable for training)
    w = w * (n / sum(w));

    % Map back to original shape; NaNs get weight 0
    W = zeros(size(L));
    W(validMask) = w;
end

function q = nm_nanquantile(X, p, dim)
% NAN-tolerant quantile wrapper
    if nargin < 3, dim = 1; end
    X = X; X(~isfinite(X)) = NaN;
    q = quantile(X, p, dim);   % MATLAB’s quantile ignores NaNs pairwise if present; else use nan functions if you have them
end
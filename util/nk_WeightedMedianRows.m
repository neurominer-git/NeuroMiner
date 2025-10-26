function m = nk_WeightedMedianRows(X, w)
% Row-wise weighted median with NaN handling.
% X : n × M matrix (NaNs allowed)
% w : 1×M or M×1 nonnegative weights (need not be normalized)

if nargin < 2 || isempty(w)
    m = nm_nanmedian(X, 2);
    return
end

w = double(w(:)).';
w = max(w, 0);
if ~any(w)
    m = nm_nanmedian(X, 2);
    return
end
w = w / sum(w);

[n, ~] = size(X);
m = nan(n,1);

for i = 1:n
    xi = X(i,:);
    mask = ~isnan(xi) & (w > 0);
    if ~any(mask)
        m(i) = NaN;
        continue
    end
    xs = xi(mask);
    ws = w(mask);
    ws = ws / sum(ws);
    [xs, ord] = sort(xs);
    ws = ws(ord);
    cdf = cumsum(ws);
    k = find(cdf >= 0.5, 1, 'first');
    m(i) = xs(k);
end
end

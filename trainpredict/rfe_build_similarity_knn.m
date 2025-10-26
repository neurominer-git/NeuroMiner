%==========================================================================
% Helper: Build sparse k-NN similarity matrix (|corr|, pairwise)
%--------------------------------------------------------------------------
function S = rfe_build_similarity_knn(X, k)
% Build a sparse k-NN similarity graph on features (columns of X).
% Similarity measure: |corr| with pairwise exclusion of NaNs.
% Keeps only the top-k neighbors per column (excluding self).
%
% Inputs
%   X : [n x p] design matrix
%   k : number of neighbors to keep per feature (default 20)
%
% Output
%   S : [p x p] sparse similarity matrix (column-j lists neighbors of j)

if nargin < 2, k = 20; end
p = size(X,2);

% z-score columns robustly (omit NaNs)
Xz = X;
Xz = Xz - mean(Xz, 'omitnan');
Xz = Xz ./ std(Xz, 0, 'omitnan');

% |corr| with pairwise rows (safe with NaNs)
C = abs(corr(Xz, 'rows', 'pairwise'));   % p x p

% Keep top-k neighbors for each column; zero out self-similarity
S = spalloc(p, p, p*(k+1));
for j = 1:p
    cj = C(:,j);
    cj(j) = 0;                               % exclude self
    if k < p-1
        [~, idx] = maxk(cj, k);
    else
        idx = find(cj > 0);
    end
    S(idx, j) = cj(idx);
end
end

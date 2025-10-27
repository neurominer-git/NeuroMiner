function H_vote_norm = nk_Entropy(P, class_list, ~, ~)
% NK_ENTROPY Normalized vote-entropy of ensemble predictions (label-free).
% See header in your version; this one additionally honors 'class_list'
% to keep normalization consistent across subsets.

% P: N x n hard labels
[N,n] = size(P);

% Determine class universe for consistent normalization
if nargin >= 2 && ~isempty(class_list)
    classes = class_list(:);
else
    classes = unique(P(:));        % fallback: infer from P
end
K = numel(classes);
if K <= 1 || n == 0 || N == 0
    H_vote_norm = 0;               % no dispersion possible
    return
end

% Map P to indices 1..K (respecting the provided classes)
[lia, idx] = ismember(P, classes.');
if ~all(lia(:))
    % Any labels outside 'classes' -> fold them into the nearest policy;
    % here we drop them into the first class to keep code robust.
    idx(~lia) = 1;
end

% Fast vote counts per row: N x K
rowIdx = repelem((1:N).', n, 1);
Count = accumarray([rowIdx, idx(:)], 1, [N, K]);

% Per-row entropy and normalization
p = Count / n;                         % N x K
% Avoid log2(0) without branching
Hrow = -sum(p .* log2(max(p, eps)), 2);
H_vote_norm = mean(Hrow) / log2(K);

end

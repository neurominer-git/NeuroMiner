function [A, Q] = nk_Diversity(P, L, ~, ~)
% =========================================================================
% function [A, Q] = nk_Diversity(P, L, ~, ~)
% =========================================================================
% NK_DIVERSITY Pairwise double-fault (A) and Q-statistic (Q) for ensemble diversity.
%   [A,Q] = NK_DIVERSITY(P,L,~,~) measures how similarly classifiers err.
%   Given hard predictions P (N-by-n) and ground-truth labels L (N-by-1 or
%   N-by-n replicated), the function:
%     1) Builds a correctness matrix C = (P == L).
%     2) For every classifier pair (i,j), counts:
%           N11 — both correct
%           N00 — both wrong   (double-faults)
%           N10 — i correct, j wrong
%           N01 — i wrong,  j correct
%     3) Aggregates across all pairs to return:
%           A = mean double-fault rate = average(N00 / N)      ∈ [0,1]
%               (lower is better; fewer simultaneous errors)
%           Q = mean Yule’s Q-statistic =
%               average( (N11*N00 - N10*N01) / (N11*N00 + N10*N01) ) ∈ [-1,1]
%               (more negative indicates greater error diversity)
%
%   INPUTS
%     P : N-by-n matrix of hard class labels (any datatype supporting ==).
%     L : N-by-1 vector of ground-truth labels (or N-by-n replicated).
%     ~ : Unused placeholders for API compatibility.
%
%   OUTPUTS
%     A : Scalar, average double-fault rate across all classifier pairs.
%     Q : Scalar, average Yule’s Q-statistic across all classifier pairs.
%
%   DETAILS & ASSUMPTIONS
%     • Requires n ≥ 2 classifiers; N is the number of instances.
%     • C = (P == L) relies on implicit expansion (MATLAB R2016b or later).
%     • When (N11*N00 + N10*N01) == 0 for a pair, its Q contribution is set to 0.
%     • Complexity: O(N·n^2) over classifier pairs.
%
%   EXAMPLE
%     % 4 instances, 3 classifiers
%     P = [1 2 1; 1 2 2; 2 2 2; 1 3 1];
%     L = [1;2;2;3];
%     [A,Q] = nk_Diversity(P,L,[],[]);
%
% =========================================================================
% (c) Nikolaos Koutsouleris, 10/2025

[N,n] = size(P);
if n < 2 || N < 1
    A = NaN; Q = NaN; return;
end

% Ensure L matches P's width if needed (for older MATLABs replace with repmat)
if size(L,2) == 1
    L = L(:,ones(1,n));
end

C = (P == L);  % N x n logical correctness

Qvals = [];    % collect valid Qs
DFsum = 0;     % sum of double-fault fractions across pairs

for i = 1:n-1
    ci = C(:,i);
    for j = i+1:n
        cj = C(:,j);
        N11 = sum( ci  &  cj);
        N00 = sum(~ci  & ~cj);
        N10 = sum( ci  & ~cj);
        N01 = sum(~ci  &  cj);
        N11 = N11 + 0.5;  N00 = N00 + 0.5;  N10 = N10 + 0.5;  N01 = N01 + 0.5;
        denom = N11*N00 + N10*N01;         % now > 0
        Qvals(end+1,1) = (N11*N00 - N10*N01) / denom;
        DFsum = DFsum + N00 / N;  % per-pair double-fault rate
    end
end

pairs = n*(n-1)/2;
A = DFsum / pairs;             % lower = better (fewer simultaneous errors)
if isempty(Qvals)
    Q = 0;                     % “neutral” Q when undefined
else
    Q = mean(Qvals);           % no need for 'omitnan' now
end

end
function D = nk_DiversityKappa(E, L, m, n)
% Fleiss' kappa over correctness (binary: correct/incorrect).
% E: m x n predicted labels; L: m x 1 (or m x n replicated)
if ~exist('m','var') || isempty(m), m = size(E,1); end
if ~exist('n','var') || isempty(n), n = size(E,2); end

C = (E == L);                % correctness matrix (m x n)
s = sum(C,2);                % # correct per item
p_correct = sum(s) / (m*n);  % marginal proportion correct
p_incorrect = 1 - p_correct;

% Per-item agreement
Pi = ( s.*(s-1) + (n-s).*(n-s-1) ) ./ ( n*(n-1) );  % in [0,1]
Pbar = mean(Pi);

Pe = p_correct^2 + p_incorrect^2;                   % expected agreement
if abs(1 - Pe) < eps
    kappa = NaN;                                    % undefined when Pe≈1
else
    kappa = (Pbar - Pe) / (1 - Pe);                 % in [-1,1]
end

D = 1 - kappa;                                      % “diversity”: higher = more error diversity
end
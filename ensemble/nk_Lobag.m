function [mED, ED] = nk_Lobag(E, L)
% NK_LOBAG Bias/variance decomposition (Valentini & Dietterich, 2004) for binary ensembles.
% E: N x n matrix of base predictions (scores or labels). L: N x 1 true labels.
% Assumes binary labels; ties are counted as errors.

% --- input checks ---
[N,n] = size(E);
if numel(L) ~= N, error('Size mismatch: size(E,1) must equal numel(L).'); end
L = L(:);

% ensure labels in {-1,+1}
uL = unique(L);
if ~all(ismember(uL, [-1 1]))
    if numel(uL)==2
        % map min->-1, max->+1
        L = 2*(L==max(uL)) - 1;
    else
        error('L must be binary and convertible to {-1,+1}.');
    end
end

% binarize predictions to {-1,+1}; map zeros to -1
E = sign(E);
E(E==0) = -1;

% majority vote prediction; count ties as errors
s   = sum(E,2);
g   = sign(s);
bias = (g ~= L) | (g == 0);    % logical N x 1

% per-item variance across classifiers (population variance)
v = var(E, 1, 2);              % N x 1, for values in {-1,+1} it's 1 - mean(E,2).^2

% split variance into unbiased (correct) and biased (incorrect) parts
vu = v .* ~bias;               % only on correctly classified items
vb = v .*  bias;               % only on misclassified items

% per-item decomposition and its mean
ED  = double(bias) + vu - vb;  % N x 1
mED = mean(ED);

end

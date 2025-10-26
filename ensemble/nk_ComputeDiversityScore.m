function D = nk_ComputeDiversityScore(Psub, Lsub, src)
% Psub: N x n (hard labels for classification; scores for 'regvar')
% Lsub: N x 1 labels when needed

switch lower(src)
    case 'entropy'   % vote entropy on hard labels, label-free
        D = nk_Entropy(Psub, [-1 1], size(Psub,2), []);
    case 'kappaa'    % 1 - double-fault A  ∈ [0,1]
        [A,~] = nk_Diversity(Psub, Lsub, [], []);
        D = max(0, min(1, 1 - A));
    case 'kappaq'    % map Q ∈ [-1,1] to [0,1] via (1 - Q)/2; fallback to 1-A
        [A,Q] = nk_Diversity(Psub, Lsub, [], []);
        if ~isfinite(Q), D = max(0, min(1, 1 - A));
        else,            D = 0.5*(1 - max(-1, min(1, Q)));
        end
    case 'kappaf'    % Fleiss κ over correctness -> (1-κ)/2 ∈ [0,1]
        kdiv = nk_DiversityKappa(Psub, Lsub, [], []); % returns 1 - κ
        D = max(0, min(1, 0.5 * kdiv));
    case 'lobag'     % lower ED is better → maximize -ED
        ED = -nk_Lobag(Psub, Lsub);
        ED = max(-1, min(2, ED));      % clamp to theoretical bounds
        D = (2 - ED) / 3;              % map ED [-1,2] -> D [1,0]
    case 'regvar'    % regression ambiguity on scores
        D = nk_RegAmbig(Psub, [], 'var', 'mean');
    otherwise
        D = nk_Entropy(Psub, [-1 1], size(Psub,2), []);
end
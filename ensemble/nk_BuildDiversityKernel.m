function R = nk_BuildDiversityKernel(P, L, src, opts)
% P : N×M predictions per learner (continuous for regression; hard votes for cls metrics)
% L : N×1 labels/targets (continuous for regression)
% src: 'entropy'|'kappaa'|'kappaq'|'kappaf'|'lobag'|'regvar'
% opts (optional): struct with fields for regression kernels:
%   .regMode  = 'residual-cov' | 'residual-corr' | 'residual-lapl'  (default 'residual-cov')
%   .diagMode = 'one'|'zero'|'keep'                                    (default 'one')
%   .scaleTo  = 'HHT'|'unit'                                           (default 'HHT')

if nargin < 4 || isempty(opts), opts = struct; end
if ~isfield(opts,'regMode'),  opts.regMode  = 'residual-cov'; end
if ~isfield(opts,'diagMode'), opts.diagMode = 'one';          end
if ~isfield(opts,'scaleTo'),  opts.scaleTo  = 'HHT';          end

[~,M] = size(P);

if strcmpi(src,'regvar')
    % -------- Regression: build kernel in one shot via nk_RegAmbig --------
    % P are continuous predictions; L is continuous target
    R = nk_RegAmbig(P, L, opts.regMode, [], 'kernel', opts.diagMode);  % M×M PSD
else
    % -------- Classification-like sources: pairwise diversity → redundancy --------
    R = zeros(M,M);
    for a = 1:M
        for b = a:M
            if a==b
                R(a,a) = 1;                               % self-redundancy baseline
            else
                Dpair = nm_diversity_score(P(:,[a b]), L, src);  % higher = more diverse
                redund = 1 - max(0, min(1, Dpair));       % map to redundancy in [0,1]
                R(a,b) = redund; R(b,a) = redund;
            end
        end
    end

    % If your cls metrics expect hard labels, ensure P were hard-votes upstream.
end

% -------- Symmetrize, PSD-project (safety) --------
R = (R + R.')/2;
[V,D] = eig(R); d = max(diag(D),0); R = V*diag(d)*V.';

% -------- Scale so alpha is interpretable --------
switch lower(opts.scaleTo)
    case 'unit'
        sR = norm(R,2); if sR>0, R = R/sR; end
    otherwise % 'HHT': match curvature to H'H
        sH = norm(P.'*P, 2); sR = norm(R, 2);
        if sR > 0, R = R * (sH / sR); end
end
end

function D = nm_diversity_score(Psub, Lsub, src)
    % Psub: for classification should be hard labels (either {-1,+1} or class ids)
    K = numel(unique(Lsub(~isnan(Lsub))));
    switch lower(src)
        case 'entropy'
            % nk_Entropy remaps labels internally → works for binary & multi-class
            D = nk_Entropy(Psub, [], [], []);                       % higher = more diversity
        case 'kappaa'     % use double-fault A; invert to “higher=better”
            [A,~] = nk_Diversity(Psub, Lsub, [], []);
            if ~isfinite(A), D = 0; else, D = max(0, min(1, 1 - A)); end
        case 'kappaq'     % more negative Q is better → map [-1,1] → [0,1]
            [A,Q] = nk_Diversity(Psub, Lsub, [], []);
            if isfinite(Q)
                D = 0.5*(1 - max(-1, min(1, Q)));
            elseif isfinite(A)
                D = max(0, min(1, 1 - A));          % fallback to 1−A
            else
                D = 0;                               % neutral fallback
            end
        case 'kappaf'     % Fleiss' kappa; your impl returns 1-κ
            kdiv = nk_DiversityKappa(Psub, Lsub, [], []);
            if ~isfinite(kdiv), D = 0; else, D = max(0, min(1, 0.5*kdiv)); end
        case 'lobag'      % lower ED is better → we report as higher=better
            if K > 2
                D = -nk_LobagMulti_from_labels(Psub, Lsub);  % lower ED ⇒ higher diversity
            else
                D = -nk_Lobag(Psub, Lsub);
            end
        otherwise
            D = nk_Entropy(Psub, [], [], []);
    end
end
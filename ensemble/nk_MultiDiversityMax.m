function [opt_hE, opt_E, opt_F, opt_Fcat, opt_D, opt_Pred] = nk_MultiDiversityMax(E, L, EnsStrat, C, G)
% =========================================================================
% [opt_hE, opt_E, opt_F, opt_Fcat, opt_D, opt_Pred] = ...
%                       nk_MultiDiversityMax(E, L, EnsStrat, C, G)
% =========================================================================
% Multi-class, performance-free ensemble constructor that optimizes a pure
% diversity objective per dichotomizer group and averages it across groups.
% Supports the same diversity objectives as nk_DiversityMax.
%
% INPUTS
% ------
% E, L, C, G : as in nk_MultiCVMax.
% EnsStrat   : fields as in nk_DiversityMax (plus .type):
%   .type              1 (BE) or 5/7 (FS)
%   .DiversityObjective 'A' | 'Q' | 'K'   (default 'Q')
%   .Metric            2 => use sign(E)
%   .MinNum, .MaxNum, .DiversityEps, .SizeReward
%
% OUTPUTS
% -------
% opt_hE   : multi-class performance (reported for reference only)
% opt_E    : selected predictions
% opt_F    : per-group logical masks
% opt_Fcat : flat index list
% opt_D    : averaged diversity across groups (lower is better when
%            reporting the minimized raw objective; if you map to [0,1],
%            clarify in the implementation)
% opt_Pred : predictions from nk_MultiEnsPerf for the selected set
%
% NOTES
% -----
% • Groups with <2 learners are passed through unchanged.
% • Forward selection seeds with the best pair *within each group*, then
%   grows using the group-wise objective; the final score is averaged.
%
% SEE ALSO
% --------
% nk_DiversityMax, nk_MultiCVMax, nk_Diversity, nk_DiversityKappa, nk_Entropy
% =========================================================================
% (c) Nikolaos Koutsouleris, 10/2025

if nargin < 5, G = []; end
ind0 = (L~=0); E = E(ind0,:); L = L(ind0);
[N,d] = size(E); if N==0 || d==0, opt_hE=0; opt_E=E; opt_F=[]; opt_Fcat=[]; opt_D=NaN; opt_Pred=[]; return; end

K = max(C);
if ~isfield(EnsStrat,'MinNum') || isempty(EnsStrat.MinNum), EnsStrat.MinNum = 1; end
if ~isfield(EnsStrat,'ConstructMode') || isempty(EnsStrat.ConstructMode), EnsStrat.ConstructMode = 1; end
if ~isfield(EnsStrat,'DiversitySource') || isempty(EnsStrat.DiversitySource), EnsStrat.DiversitySource = 'kappaq'; end
divsrc = lower(EnsStrat.DiversitySource);

% hard labels if needed
if isfield(EnsStrat,'Metric') && EnsStrat.Metric == 2
    T = sign(E); T(T==0) = -1;
else
    T = E;
end

% baseline perf (for reporting only)
[orig_hE, ~] = nk_MultiEnsPerf(E, T, L, C, G);

% baseline diversity
orig_D = agg_diversity(T, L, C, divsrc, K);
opt_D  = orig_D; orig_F = 1:d; opt_I = orig_F;

% per-dichotomizer counts
kq = zeros(K,1);
for q=1:K, kq(q) = sum(C==q); end
ksum = d;

switch EnsStrat.ConstructMode
    case 1  % ------------------------ Backward Elimination (RCE) -------------------
        strhdr = 'Multi-group RCE => max(diversity)';
        MinTot = EnsStrat.MinNum * K;
        BestD  = opt_D; I = orig_F; iters = 0;

        while ksum > MinTot
            for q=1:K
                cols_q = find(C(I)==q);
                l = numel(cols_q);
                if l==0, continue; end
                lhD = -inf(l,1);

                for t=1:l
                    kI = I; kI(cols_q(t)) = [];
                    lhD(t) = agg_diversity(T(:,kI), L, C(kI), divsrc, K);
                end

                [candD, which] = max(lhD);
                I(cols_q(which)) = []; ksum = ksum - 1; kq(q) = kq(q) - 1;

                if candD >= BestD
                    BestD = candD; opt_I = I; iters = iters + 1;
                end
            end
            if all(kq <= EnsStrat.MinNum), break; end
        end
        MaxParamD = BestD;

    case 2
        % ------------------------ Forward Construction (FCC) -------------------
        strhdr = 'Multi-group FCC => max(diversity)';
        I = zeros(1,K); pool = []; iters = 0;

        % seed with 1 per dichotomizer (if available)
        for q=1:K
            idx = find(C==q);
            if ~isempty(idx), I(q) = idx(1); pool = [pool idx(2:end)]; end %#ok<AGROW>
        end
        I = I(I>0); pool = pool(:)'; ksum = numel(I);
        BestD = agg_diversity(T(:,I), L, C(I), divsrc, K);

        while ~isempty(pool)
            lhD = -inf(numel(pool),1);
            for t=1:numel(pool)
                kI = [I pool(t)];
                lhD(t) = agg_diversity(T(:,kI), L, C(kI), divsrc, K);
            end
            [candD, which] = max(lhD);
            if candD >= BestD
                I = [I pool(which)];
                BestD = candD; opt_I = I; iters = iters + 1;
            end
            pool(which) = [];
        end
        MaxParamD = BestD;

    otherwise
        error('EnsStrat.ConstructMode must be 1 (BE) or 2 (FS).');
end

% finalize selection
if opt_D > MaxParamD
    opt_I = orig_F; opt_D = orig_D;
else
    opt_D = MaxParamD;
end

opt_E = E(:,opt_I);
[opt_hE, opt_Pred] = nk_MultiEnsPerf(opt_E, T(:,opt_I), L, C(:,opt_I), G);

% pack masks
opt_F = cell(K,1); logI = false(1,d); logI(opt_I)=true;
for q=1:K
    opt_F{q} = logI(C==q);
end
opt_Fcat = opt_I;

% (optional) print (guard if needed)
if ~isempty(getenv('OCTAVE_VERSION'))
    fprintf('\n%s: Div(orig->final): %.3f->%.3f, Perf: %.3f->%.3f, #Learners: %d->%d\n',...
        strhdr, orig_D, opt_D, orig_hE, opt_hE, numel(orig_F), numel(opt_I));
end

end

% ---------------- helpers ----------------

function D = agg_diversity(T, L, C, divsrc, K)
% Aggregate per-dichotomizer diversity -> mean across q=1..K
Dq = zeros(K,1);
for q=1:K
    cols = (C==q);
    if ~any(cols)
        Dq(q) = 0; continue;
    end
    Tq = T(:,cols);
    switch divsrc
        case 'entropy'
            Dq(q) = nk_Entropy(Tq, [-1 1], [], []);

        case 'kappaa'
            if size(Tq,2) < 2, Dq(q)=0; else
                Lbin = -ones(size(L)); Lbin(L==q) = 1;
                [A,~] = nk_Diversity(Tq, Lbin, [], []);
                Dq(q) = max(0, min(1, 1 - A));
            end

        case 'kappaq'
            if size(Tq,2) < 2, Dq(q)=0; else
                Lbin = -ones(size(L)); Lbin(L==q) = 1;
                [A,Q] = nk_Diversity(Tq, Lbin, [], []);
                if isfinite(Q)
                    Dq(q) = 0.5*(1 - max(-1,min(1,Q))); % map [-1,1] -> [0,1]
                else
                    Dq(q) = max(0, min(1, 1 - A));       % fallback
                end
            end

        case 'kappaf'
            if size(Tq,2) < 2, Dq(q)=0; else
                Lbin = -ones(size(L)); Lbin(L==q) = 1;
                D1mK = nk_DiversityKappa(Tq, Lbin, [], []);
                if isfinite(D1mK), Dq(q) = max(0, min(1, 0.5*D1mK));
                else, Dq(q)=0; end
            end

        case 'lobag'
            % LoBag ED: lower is better → use -ED as diversity signal here
            Lbin = -ones(size(L)); Lbin(L==q) = 1;
            ED = nk_Lobag(Tq, Lbin);      % raw ED
            Dq(q) = -ED;                  % higher is more diverse

        otherwise
            % default: entropy
            Dq(q) = nk_Entropy(Tq, [-1 1], [], []);
    end
end
D = mean(Dq, 'omitnan');

end
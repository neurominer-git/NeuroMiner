function [opt_hE, opt_E, opt_F, opt_D] = nk_DiversityMax(E, L, EnsStrat)
% =========================================================================
% [opt_hE, opt_E, opt_F, opt_D] = nk_DiversityMax(E, L, EnsStrat)
% =========================================================================
% Greedy ensemble constructor that optimizes a *pure diversity* objective
% (no performance in the criterion). Useful for decorrelating errors.
%
% Search modes via EnsStrat.type:
%   • type==1 : Backward Elimination (remove worst wrt diversity)
%   • type==5 or 7 : Forward Selection (seed by best pair, then grow)
%
% INPUTS / OUTPUTS
% ----------------
% Same E, L as nk_CVMax. EnsStrat adds:
%   .DiversityObjective 'A' (double-fault), 'Q' (Yule’s Q), or 'K' (Fleiss κ)
%                       (default 'Q')
%   .MaxNum             max #learners to keep (default k)
%   .DiversityEps       ε tie-tolerance on diversity (default 0.02)
%   .SizeReward         γ ≥ 0 size penalty used as: J(S)=D(S)+γ·log|S|
%   .MinNum             recommended ≥3 for pairwise statistics
%
% Returns:
%   opt_hE : performance of the selected set (reported only)
%   opt_E  : selected columns of E
%   opt_F  : selected indices
%   opt_D  : minimized value of the diversity objective:
%            'A' → A   (lower better), 'Q' → Q (lower better),
%            'K' → κ   (lower better)
%
% NOTES
% -----
% • For 'Q'/'A' the function uses nk_Diversity; for 'K' uses nk_DiversityKappa.
% • Forward mode seeds with the best pair by the chosen objective.
% • If the optimized set is not better than the original (by diversity),
%   the full set is returned.
%
% SEE ALSO
% --------
% nk_MultiDiversityMax, nk_Diversity, nk_DiversityKappa, nk_Entropy, nk_Lobag
% =========================================================================
% (c) Nikolaos Koutsouleris, 10/2025

global VERBOSE

% ---------- sanitize ----------
ind0 = (L ~= 0); E = E(ind0,:); L = L(ind0);
[~,k] = size(E);
if k == 0
    opt_hE = 0; opt_E = E; opt_F = []; opt_D = NaN; return;
end

% ---------- defaults ----------
if ~isfield(EnsStrat,'MinNum')       || isempty(EnsStrat.MinNum),       EnsStrat.MinNum       = 2;    end
if ~isfield(EnsStrat,'MaxNum')       || isempty(EnsStrat.MaxNum),       EnsStrat.MaxNum       = k;    end
if ~isfield(EnsStrat,'DiversityEps') || isempty(EnsStrat.DiversityEps), EnsStrat.DiversityEps = 0.02; end
if ~isfield(EnsStrat,'SizePenalty')   || isempty(EnsStrat.SizePenalty), EnsStrat.SizePenalty   = 0;    end

% Resolve objective
if isfield(EnsStrat,'DiversitySource') && ~isempty(EnsStrat.DiversitySource)
    switch lower(EnsStrat.DiversitySource)
        case 'entropy', obj = 'H';
        case 'kappaa',  obj = 'A';
        case 'kappaq',  obj = 'Q';
        case 'kappaf',  obj = 'K';
        case 'lobag',   obj = 'ED';
        otherwise,      obj = 'Q';
    end
else
    obj = 'Q';
end
if ismember(obj, {'A','Q','K'}), EnsStrat.MinNum = max(EnsStrat.MinNum, 2); end

% ---------- use HARD labels by default ----------
useHard = true;
if isfield(EnsStrat,'Metric') && EnsStrat.Metric==2
    useHard = true;                 % explicit
elseif isfield(EnsStrat,'Metric') && EnsStrat.Metric==1
    useHard = false;                % caller insists on soft (not recommended)
end
if useHard
    T = sign(E); T(T==0) = -1;
else
    T = E;
end

% ---------- scoring helper (MINIMIZE) ----------
    function s = score_idx(idx)
        if isempty(idx), s = Inf; return; end
        P = T(:, idx);

        switch obj
            case 'H'   % maximize vote-entropy ⇒ minimize negative entropy
                Ph = sign(P); Ph(Ph==0) = -1;
                s = -nk_Entropy(Ph, [-1 1], size(Ph,2), []);

            case 'A'   % double-fault, lower better
                if size(P,2) < 2, s = Inf; return; end
                [A,~] = nk_Diversity(P, L, [], []);
                if ~isfinite(A), s = Inf; else, s = A; end

            case 'Q'   % Yule’s Q, MORE NEGATIVE is better ⇒ minimize Q
                if size(P,2) < 2, s = Inf; return; end
                [~,Q] = nk_Diversity(P, L, [], []);
                if ~isfinite(Q), s = Inf; else, s = Q; end  % <-- no 0 fallback

            case 'K'   % Fleiss κ; nk_DiversityKappa returns 1-κ
                if size(P,2) < 2, s = Inf; return; end
                D1mK = nk_DiversityKappa(P, L, [], []);     % 1-κ, lower is better
                s = D1mK;                                   % <-- minimize 1-κ directly

            case 'ED'  % LoBag ED, lower better
                Ph = sign(P); Ph(Ph==0) = -1;
                s = nk_Lobag(Ph, L);
                if ~isfinite(s), s = Inf; end

            otherwise
                if size(P,2) < 2, s = Inf; return; end
                [~,Q] = nk_Diversity(P, L, [], []);
                if ~isfinite(Q), s = Inf; else, s = Q; end
        end
    end

% ---------- baselines ----------
opt_hE = nk_EnsPerf(E, L);     orig_hE = opt_hE;
opt_D  = score_idx(1:k);       orig_D  = opt_D;
orig_F = 1:k;

% ---------- select mode (support .type and .ConstructMode) ----------
modeVal = [];
if isfield(EnsStrat,'ConstructMode') && ~isempty(EnsStrat.ConstructMode)
    modeVal = EnsStrat.ConstructMode;
elseif isfield(EnsStrat,'type') && ~isempty(EnsStrat.type)
    if any(EnsStrat.type == 1), modeVal = 1; end
    if any(EnsStrat.type == 5 | EnsStrat.type == 7), modeVal = 2; end
end
if isempty(modeVal), modeVal = 2; end  % default to forward
iter=0;

% --- size penalty used in J = D + gamma*log|S| (0 means "off") ---
if isfield(EnsStrat,'SizePenalty') && ~isempty(EnsStrat.SizePenalty)
    gamma = EnsStrat.SizePenalty;
else
    gamma = 0;
end

switch modeVal
    case 1
        % --- Backward Elimination (unchanged except NaN->Inf behavior already handled) ---
        I = orig_F; opt_I = I; iter=0; kcur = k; Best = opt_D;
        while kcur > EnsStrat.MinNum
            lD = inf(kcur,1);
            for l = 1:kcur
                kI = I; kI(l) = [];
                lD(l) = score_idx(kI);
            end
            [cand, l] = min(lD);
            I(l) = []; kcur = kcur - 1;
            if cand < Best - 1e-12
                Best = cand; opt_I = I; iter = iter + 1;
            end
        end
        MinParam = Best;

    case 2
        % --- Forward Selection (tighter acceptance) ---
        if ismember(upper(obj), {'A','Q','K'})
            EnsStrat.MinNum = max(EnsStrat.MinNum, 2);
        end
        if k < 2
            opt_I = 1; MinParam = score_idx(1); iter = 0;
        else

            % ---------- seed phase starts here --------------- 
            origI = 1:k;

            % --- triad-aware candidate pool (reuse your topM; or set topM=k) ---
            topM = min(25, k);   % keep as you have it
            % Pre-rank learners by their best pair-mate (works for A/Q/K/H/LoBag)
            bestPairForA = inf(1,k);
            for a = 1:k
                bp = inf;
                for b = [1:a-1, a+1:k]
                    d2 = score_idx([a b]);
                    if d2 < bp, bp = d2; end
                end
                bestPairForA(a) = bp;
            end
            [~, order] = sort(bestPairForA, 'ascend');
            candIdx = order(1:topM);
            
            % ---------- pick the best TRIAD among the topM ----------
            best3 = Inf; best_triad = [];
            for ia = 1:numel(candIdx)-2
                a = candIdx(ia);
                for ib = ia+1:numel(candIdx)-1
                    b = candIdx(ib);
                    for ic = ib+1:numel(candIdx)
                        c = candIdx(ic);
                        d3 = score_idx([a b c]);     % average pairwise A over the triad
                        if d3 < best3
                            best3 = d3; best_triad = [a b c];
                        end
                    end
                end
            end
            
            % Fallback if something went wrong
            if isempty(best_triad)
                % keep your previous best-pair seed path here if you like
                best_triad = 1:min(3,k);
            end
            
            I        = best_triad;
            MinParam = score_idx(I);
            opt_I    = I;
            origI(ismember(origI, I)) = [];

            % ----- optimization starts here -------
            Jbest  = MinParam + gamma*log(numel(I));
            
            while ~isempty(origI) && numel(I) < EnsStrat.MaxNum
                accepted_this_round=false;
                lD = inf(numel(origI),1);
                for l = 1:numel(origI)
                    kI   = [I, origI(l)];
                    lD(l) = score_idx(kI);
                end
                [candD, l] = min(lD);
                if ~isfinite(candD), origI(l) = []; continue; end

                % Add size penalty to diversity criterion (candD)
                m_cur  = numel(I);
                Jcand  = candD + gamma*log(m_cur + 1);

                % Define tolerance based on epsilon
                tolD = EnsStrat.DiversityEps;
                tolJ = max(1e-12, 0.5*EnsStrat.DiversityEps);
                
                if m_cur < EnsStrat.MinNum
                    accept = (candD < MinParam + 0.25*tolD);
                else
                    acceptRaw = (candD < MinParam - tolD);
                    acceptPen = (Jcand < Jbest - tolJ);
                    accept    = acceptRaw && acceptPen;   % BOTH required
                end

                if accept
                    I        = [I, origI(l)];
                    MinParam = min(MinParam, candD);
                    Jbest    = min(Jbest, Jcand);
                    opt_I    = I; 
                    iter = iter + 1;
                    if VERBOSE, fprintf('\n\tOpt iter #%g: MinParam: %g, candD: %g | Jbest: %g, Jcand: %g, Size opt_I: %g', ...
                                        iter, MinParam, candD, Jbest, Jcand, numel(opt_I)); end
                    origI(l) = [];
                    accepted_this_round = true;
                else
                    % do nothing
                end
                if ~exist('accepted_this_round','var') || ~accepted_this_round
                    did_swap = false;
                    curD = score_idx(I);
                    for r = 1:numel(I)  % try removing one current member
                        bestSwap = Inf; best_c = [];
                        for c = origI   % only outsiders
                            d = score_idx([I([1:r-1 r+1:end]) c]);
                            if d < bestSwap, bestSwap = d; best_c = c; end
                        end
                        if isfinite(bestSwap) && bestSwap < curD - EnsStrat.DiversityEps
                            % perform the swap
                            origI(origI==best_c) = [];     % remove chosen from pool
                            origI(end+1) = I(r);           % put the removed one back
                            I(r) = best_c;
                            MinParam = min(MinParam, bestSwap);
                            opt_I = I; iter = iter + 1;
                            did_swap = true;
                            if VERBOSE
                                fprintf('\n\tFloating swap: replaced #%d, new D=%.6f, |I|=%d', r, bestSwap, numel(I));
                            end
                            break
                        end
                    end
                    if did_swap
                        % continue outer FS while-loop (do NOT stop yet)
                        continue
                    end
                end

                % ---------- decide how to proceed ----------
                if accepted_this_round
                    continue                          % set changed via add → recompute
                elseif did_swap
                    continue                          % set changed via swap → recompute
                else
                    break                             % no progress possible → stop FS
                end
            end

            % ensure MinNum (force-fill to reach the hard minimum)
            while numel(I) < EnsStrat.MinNum && ~isempty(origI)
                nLeft = numel(origI);
                lD    = inf(nLeft,1);
                lJ    = inf(nLeft,1);
                for l = 1:nLeft
                    kI      = [I, origI(l)];
                    d       = score_idx(kI);                  % raw D(kI)
                    if isfinite(d)
                        j   = d + gamma * log(numel(kI));     % J(kI) = D - γ log|S|
                        lD(l) = d;
                        lJ(l) = j;
                    end
                end
            
                % choose by penalized objective (ties broken by raw D)
                [minJ, l] = min(lJ);
                if ~isfinite(minJ)
                    % no finite candidates left → stop trying to fill
                    break
                end
            
                chosen = origI(l);
                I      = [I, chosen];
                opt_I  = I;
                iter   = iter + 1;
            
                % keep these in sync for reporting and finalization
                candD  = lD(l);
                Jcand  = lJ(l);
                MinParam = min(MinParam, candD);
                Jbest    = min(Jbest,   Jcand);
            
                % remove from pool and continue
                origI(l) = [];
            end

        end

    otherwise
        error('EnsStrat.type must be 1 (BE) or 5/7 (FS), or ConstructMode==1/2.');
end

% ---------- finalize with a MEANINGFUL tolerance ----------
D_full = orig_D;
J_full = D_full + gamma*log(k);

D_opt  = MinParam;
J_opt  = D_opt + gamma*log(numel(opt_I));

tolD   = EnsStrat.DiversityEps;
tolJ   = max(1e-12, 0.5*EnsStrat.DiversityEps);

if gamma > 0
    take_opt = (J_opt < J_full - tolJ);
else
    take_opt = (D_opt < D_full - tolD);
end

if take_opt
    opt_F = opt_I; opt_E = E(:,opt_I); opt_hE = nk_EnsPerf(opt_E,L); opt_D = D_opt;
else
    opt_F = 1:k;   opt_E = E;           opt_hE = nk_EnsPerf(opt_E,L); opt_D = D_full;
end

if VERBOSE
   fprintf(['\n%s: %g iters\tDiv(%s, orig->final): %1.6f->%1.6f, ' ...
            'Perf (orig->final): %1.3f->%1.3f, ' ...
            '# Learners (orig->final): %g->%g'], ...
            ternary(modeVal==1,'BE','FS'), iter, obj, orig_D, opt_D, ...
            nk_EnsPerf(E,L), opt_hE, numel(orig_F), numel(opt_F));
end

end

function out = ternary(cond, valTrue, valFalse)
%TERNARY  Tiny ternary helper: returns valTrue if cond, else valFalse.
    if cond
        out = valTrue;
    else
        out = valFalse;
    end
end

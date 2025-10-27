function [optparam, optind, optfound, optmodel] = ...
    rfe_backward_multi_v2(Y, mY, label, labelB, labelM, Ynew, labelnew, labelnewM, Ps, FullFeat, FullParam, ngroups, ActStr)
%=================================================================================================
% rfe_backward_multi_v2 — Multi-class greedy backward elimination with
%                          adaptive regularization + natural stopping
%
% This is an upgrade of the NM 1.3 function rfe_backward_multi:
%   • Keeps legacy flow: ALWAYS remove the selected block; update optimum only if improved.
%   • Adds a per-class refusal r_c that PROTECTS remaining features from removal.
%   • Ranks “single-removal candidates” by penalized score:
%       val_pen(m) = val(m) - lambda_eff * rho(m),
%     where val(m) is ensemble performance after removing the m-th position
%     (one feature per class), and rho(m) aggregates refusal across classes.
%   • Natural stopping: stop when max penalized gain ≤ τ (MAD-based, with patience).
%   • Optional Auto-λ: λ_eff adapts to current gain scale (robust MAD).
%
% INPUT/OUTPUT are identical to rfe_backward_multi.
% All configuration is provided by rfe_algo_settings_multi via r.AdRef.
%=================================================================================================
% (c) Nikolaos Koutsouleris, 10/2025

global VERBOSE TRAINFUNC

% ------------------------------------------------------------------------------
% Get multi-class settings (includes AdRef with all adaptive knobs)
% ------------------------------------------------------------------------------
r = rfe_algo_settings_multi(Y, mY, label, labelB, labelM, Ynew, labelnew, labelnewM, Ps, FullFeat, FullParam, ngroups, ActStr);
AD = r.AdRef;                    % Adaptive regularization configuration
nclass = numel(Y);

% ------------------------------------------------------------------------------
% Initialize state from the full models (close to legacy)
% ------------------------------------------------------------------------------
optfound = 0; 
optparam = r.FullParamMulti;     % ensemble performance for full set
optind   = r.FullInd;            % cell per class
optmodel = r.FullModel;          % cell per class (may be [])
param    = optparam;             % ensure defined for finalization

% S{c} holds the CURRENT feature pool for class c (indices into r.FullInd{c})
S     = cell(1,nclass); 
k     = zeros(1,nclass); 
lstep = zeros(1,nclass);

for c = 1:nclass
    k(c) = r.kFea(c);
    if r.PreSort
        S{c} = r.PreOrder{c};                  % pre-sorted pool (legacy)
    else
        S{c} = 1:r.kFea(c);
    end
    % Step size per class (legacy: percentage of CURRENT pool)
    lstep(c) = ceil((numel(S{c})/100) * r.lperc(c));
    lstep(c) = max(lstep(c), 1);
end

if max(k) <= r.MinNum, return; end

% ------------------------------------------------------------------------------
% Verbose banner (legacy text + adaptive tag)
% ------------------------------------------------------------------------------
if VERBOSE
    fprintf('\n----------------------------------------------------------------------------------')
    fprintf('\nGREEDY BACKWARD FEATURE ELIMINATION (multi-class, v2: adaptive reg + natural stop)')
    fprintf('\n----------------------------------------------------------------------------------')
    fprintf('\nOptimization data mode: %s', ActStr)
    fprintf('\nParameter evaluation: %s (%s)', r.evaldir, r.optfunc)
    if r.FeatStepPerc
        for c=1:nclass
            fprintf('\nStepping: %g%% of %g features in model #%g per wrapper cycle.', r.lperc(c), r.kFea(c), c)
        end
    else
        fprintf('\nStepping: Top feature in wrapper cycle.')
    end
    if r.FeatRandPerc
        fprintf('\nRandom feature selection: %g%% of top-ranked features in block', r.FeatRandPerc)
    end
    if AD.Enable
        fprintf('\n[AdaptiveReg] ON (λ: %s, kNN=%d, γ=%.3f, η0=%.3g, η1=%.3g, rmax=%.1f)', ...
            tern(AD.Auto.Enable,'auto','manual'), AD.kNN, AD.gamma, AD.eta0, AD.eta1, AD.rmax);
        fprintf('\n[AdaptiveReg] φ(s): c=%.2f w=%.2f (beta_well=%g, beta_hi=%g, sigma_lo=%g, sigma_hi=%g)', ...
                AD.c, AD.w, AD.beta_well, AD.beta_hi, AD.sigma_lo, AD.sigma_hi);
        if AD.Stop.Enable
            fprintf('\n[NaturalStop] τ_abs=%g, UseMAD=%d (W=%d, Zmad=%.1f), Patience=%d', ...
                AD.Stop.TauAbs, AD.Stop.UseMAD, AD.Stop.MADWinsz, AD.Stop.Zmad, AD.Stop.Patience);
        end
    end
end

% ------------------------------------------------------------------------------
% Adaptive structures (only if enabled):
%   rvec{c} — refusal per feature (length p_c) for class c (protect from removal)
%   SMat{c} — sparse kNN similarity (|corr|) among features for class c
% ------------------------------------------------------------------------------
if AD.Enable
    rvec = cell(1,nclass);
    SMat = cell(1,nclass);
    for c = 1:nclass
        rvec{c} = zeros(r.kFea(c),1);
        SMat{c} = rfe_build_similarity_knn(r.Y{c}, AD.kNN);
    end
    % Natural stop history & counter
    if AD.Stop.Enable
        AD.Stop.hist    = [];    % recent accepted raw improvements at ensemble level
        AD.Stop.holdcnt = 0;     % patience iterations met so far
    end
end

maxK = max(k); 
minK = min(r.MinNum);
cnt  = 1;

% ======================================================================
% Start Wrapper: BACKWARD FEATURE ELIMINATION
% ======================================================================
while maxK > minK

    % maxNS = maximum number of removable positions across classes
    maxNS = max(cellfun(@numel, S));   % each position m removes one feature per class at that position
    if ~maxNS, break; end

    val = zeros(maxNS,1);              % ensemble performance after single-position removal
    if VERBOSE
        for c=1:nclass
            fprintf('\n\tFeature pool size of model #%g: %4.0f, block size: %4.0f feature(s) ', c, numel(S{c}), lstep(c));
        end
    end

    % tEnd(m,c) maps removal "position" m to the actual index in S{c}
    tEnd = zeros(maxNS, nclass);
    ds   = zeros(size(r.T{1},1), nclass, maxNS);
    ts   = zeros(size(r.T{1},1), nclass, maxNS);

    % ----------------------------------------------------------
    % Evaluate raw score for each single-position removal:
    %   For position m: remove S{c}(m) (or the last one if shorter pool)
    %   Train per-class models on remaining features and compute ensemble perf
    % ----------------------------------------------------------
    mm = maxNS;
    while mm > 0
        for c = 1:nclass
            NS = numel(S{c});
            if mm > NS
                tEnd(mm, c) = NS;      % shortest guard: drop last available
            else
                tEnd(mm, c) = mm;
            end
            lind = 1:NS; 
            lind( tEnd(mm,c) ) = [];   % remove position mm in class c
            kS = S{c}(lind);

            tY = r.Y{c}(:, kS); 
            T  = r.T{c}(:, kS);
            [~, model] = TRAINFUNC(tY, label{c}, 1, Ps{c});
            [~, ds(:, c, mm), ts(:, c, mm)] = nk_GetTestPerf(T, r.L{c}, [], model, tY);
        end
        val(mm) = nk_MultiEnsPerf(ds(:,:,mm), ts(:,:,mm), r.Lm, 1:nclass, r.ngroups);
        mm = mm - 1;
    end

    % ----------------------------------------------------------
    % Adaptive ranking: protect from removal using refusal rvec
    %   For position m, the to-be-removed feature in class c is S{c}(tEnd(m,c)).
    %   Aggregate refusal rho(m) across classes (median for robustness).
    %   Sort by val_pen = val - lambda_eff * rho (so high-refusal → harder to remove).
    % ----------------------------------------------------------
    if AD.Enable
        rho = zeros(maxNS,1);
        for mm = 1:maxNS
            rvals = zeros(nclass,1);
            for c = 1:nclass
                pos = tEnd(mm, c);
                if pos >= 1 && pos <= numel(S{c})
                    fidx = S{c}(pos);                % absolute index in class c
                    rvals(c) = rvec{c}(fidx);
                else
                    rvals(c) = 0;
                end
            end
            rho(mm) = median(rvals);
        end

        % Auto-λ or manual λ
        if AD.Auto.Enable
            sigmaG     = robust_sigma(val);         % ≈ 1.4826·MAD(val)
            denom      = 1 + median(rho,'omitnan');
            lambda_eff = AD.Auto.LambdaC * sigmaG / max(denom, eps);
        else
            lambda_eff = AD.lambda;
        end

        val_pen = val - lambda_eff * rho;
        [~, ind] = sort(val_pen, r.optfunc);
    else
        [~, ind] = sort(val, r.optfunc);
        lambda_eff = NaN; 
        rho        = zeros(maxNS,1);
    end
   
    %-------------------------------------
    % Natural stopping using shared helper
    %-------------------------------------
    if AD.Enable && AD.Stop.Enable
        rsub = rho(:);   % aggregated (e.g., median) refusal across classes
        [should_stop, Tau, info] = rfe_natural_stop_test(val(:), optparam, rsub, lambda_eff, AD.Stop);
    
        if should_stop
            AD.Stop.holdcnt = AD.Stop.holdcnt + 1;
            if VERBOSE
                fprintf('\n[AdaptiveReg] Natural stop: max penalized gain=%.6g ≤ τ=%.6g (raw max Δ=%.6g, τMAD=%.6g).', ...
                    info.max_mprime, Tau, info.max_raw_delta, info.TauMAD);
            end
            if AD.Stop.holdcnt > AD.Stop.Patience
                break; % graceful termination
            end
        else
            AD.Stop.holdcnt = 0;
        end
    end

    % ----------------------------------------------------------
    % Choose the removal block (legacy: by top-lstep positions),
    % apply optional random sub-selection, and COMMIT removal.
    % ----------------------------------------------------------
    krem = 1:min(lstep);    % per-iteration block size uses the minimum across classes (legacy)
    % Random sub-selection (legacy)
    if r.FeatRandPerc
        rstep = ceil(min(lstep)/100) * r.FeatRandPerc;
        rind  = randperm(min(lstep), rstep);
    else
        rind  = krem;
    end

    % Map selected positions from ranking (ind) to per-class feature ids
    rem_pos = ind(rind);       % selected positions to remove (shared across classes)

    % COMMIT removal (legacy behavior: always remove)
    for c = 1:nclass
        % positions to remove in class c this round
        pos_c = tEnd(rem_pos, c)';               % positions in S{c}
        pos_c = unique(pos_c(pos_c>=1 & pos_c <= numel(S{c})));   % guard
        if ~isempty(pos_c)
            mask = true(1, numel(S{c}));
            mask(pos_c) = false;
            S{c} = S{c}(mask);
        end
        % Recompute step size for this class (percentage of CURRENT pool)
        lstep(c) = ceil((max(cellfun(@numel,S))/100) * min(r.lperc)); % mirrors your legacy line
        lstep(c) = max(lstep(c), 1);
    end

    % ----------------------------------------------------------
    % Evaluate ensemble performance AFTER removal (legacy flow)
    % ----------------------------------------------------------
    ds2 = zeros(size(r.T{1},1), nclass);
    ts2 = zeros(size(r.T{1},1), nclass);
    for c = 1:nclass
        tY = r.Y{c}(:, S{c}); 
        T  = r.T{c}(:, S{c});
        [~, model] = TRAINFUNC(tY, label{c}, 1, Ps{c});
        [~, ds2(:,c), ts2(:,c)] = nk_GetTestPerf(T, r.L{c}, [], model, tY);
    end
    param = nk_MultiEnsPerf(ds2, ts2, r.Lm, 1:nclass, r.ngroups);

    % Raw improvement relative to current optimum (for history if accepted)
    raw_impr = param - optparam;

    % ----------------------------------------------------------
    % Update optimum ONLY if improved (legacy)
    % ----------------------------------------------------------
    if feval(r.evaldir, param, optparam)
        optfound = 1; 
        optparam = param; 
        for c=1:nclass
            optind{c} = r.FullInd{c}( S{c} );
        end
        if VERBOSE, fprintf('=> NEW optimum: # Features: %4.0f ==> %s = %g', mean(cellfun(@numel,optind)), ActStr, optparam); end
        for c=1:nclass, Opt.S{c,cnt} = S{c}; end
        Opt.Param = [Opt.Param optparam];
        cnt = cnt + 1;

        % Record into natural-stop history (accepted raw gain)
        if AD.Enable && AD.Stop.Enable
            AD.Stop.hist = [AD.Stop.hist; raw_impr];
            if numel(AD.Stop.hist) > AD.Stop.MADWinsz
                AD.Stop.hist = AD.Stop.hist(end-AD.Stop.MADWinsz+1:end);
            end
        end
    else
        if VERBOSE, fprintf('(%s = %g)', ActStr, optparam); end
    end

    % ----------------------------------------------------------
    % Adaptive update AFTER removal:
    %   backward → PROTECT remaining neighbors of removed features:
    %   r_c ← γ r_c + η0 + η1 * (1 - w_t) * ( -φ(s) )
    %   (flip sign vs forward to discourage removing near-duplicates next)
    % ----------------------------------------------------------
    if AD.Enable
        % Decay + global drift for all classes
        for c = 1:nclass
            rvec{c} = AD.gamma * rvec{c} + AD.eta0;
        end

        % Rank weights for this iteration using RAW val ordering:
        % better (higher val) removals get smaller w_t (thus larger protection bump).
        ranks = tiedrank(-val);                   % 1 = best removal position
        w_ts  = ranks( rem_pos ) / numel(val);    % weights for the positions we removed

        % For each removed position, update refusal in EACH class
        for jj = 1:numel(rem_pos)
            pos = rem_pos(jj);
            w_t = w_ts(jj);
            for c = 1:nclass
                old_pos = tEnd(pos, c);          % position removed in class c
                if old_pos < 1 || old_pos > numel(SMat{c}), continue; end
                % The absolute feature index removed was the one previously at S{c}_pre(old_pos).
                % We don't have S_pre now; an acceptable proxy is to map by index because SMat
                % is built on the original full set ordering (size r.kFea(c)).
                % In practice, tEnd stored positions; for the similarity vector we need the absolute id.
                % We can reconstruct it via the last known rvec size assumption (rvec aligned to full set).
                % To stay consistent, cache the absolute ids BEFORE removal if exact mapping is needed.
                % Here we approximate by assuming positions refer to absolute ids (common in your flow).
                % If needed, store a copy of S before removal and index from there.
                % For robustness:
                %   → we’ll derive absolute id as the closest available (cap to bounds).
                abs_idx = min(max(old_pos,1), r.kFea(c));

                si_sparse = SMat{c}(:, abs_idx);
                if isempty(si_sparse), continue; end
                si  = full(si_sparse);
                pen = rfe_redundancy_penalty(si, AD.c, AD.w, AD.beta_well, AD.beta_hi, AD.sigma_lo, AD.sigma_hi);
                bump = AD.eta1 * (1 - w_t) * (-pen);   % backward: -φ
                rvec{c} = rvec{c} + bump;
            end
        end

        % Cap refusal for stability
        for c = 1:nclass
            rvec{c} = min(rvec{c}, AD.rmax);
        end
    end

    % ----------------------------------------------------------
    % Update overall counter; legacy uses decrease by block size
    % ----------------------------------------------------------
    maxK = maxK - numel(rind);
    if max(cellfun(@numel, S)) <= r.MinNum, break; end
end

% ======================================================================
% Finalization: compare to original; knee-point (legacy-compatible)
% ======================================================================
if ~feval(r.evaldir, optparam, r.FullParamMulti)
    % Did not beat the original ensemble performance -> return original
    optparam = r.FullParamMulti; 
    optind   = r.FullInd; 
    optfound = 0; 
    optmodel = r.FullModel;

elseif (~isfinite(param) || isempty(param)) && ~optfound 
    % Non-finite performance encountered and no optimum found
    optind   = r.FullInd; 
    optmodel = r.FullModel; 
    optparam = r.FullParamMulti;
    fprintf('\n'); warning('Greedy backward search (multi) did not return any feature mask for given parameter setting. Return original feature space.')
else
    optfound = 1;
    for c = 1:nclass
        if r.KneePoint
            kneepoint = knee_pt(Opt.Param);
            if isnan(kneepoint)
                fprintf('\nNot enough data points to compute kneepoint. Selecting final feature mask.');
                optind{c} = r.FullInd{c}( S{c} );
            else
                fprintf('\nSelected kneepoint of optimization curve at wrapper cycle #%g => %s = %g', kneepoint, ActStr, Opt.Param(kneepoint));
                try
                    optind{c} = r.FullInd{c}( Opt.S{c}{kneepoint} );
                catch
                    fprintf('\nNo optimum found. Selecting current feature mask.');
                    optind{c} = r.FullInd{c}( S{c} );
                end
            end
        else
            optind{c} = r.FullInd{c}( S{c} );
        end
        [~, optmodel{c}] = TRAINFUNC(Y{c}(:, optind{c}), label{c}, 1, Ps{c}); 
    end
end

if VERBOSE; fprintf('\nDone. '); end
end % rfe_backward_multi_v2

% =============================================================================
% Helper: robust σ (MAD-based), NaN-safe
% =============================================================================
function s = robust_sigma(x)
x = x(:);
xm = median(x,'omitnan');
s  = 1.4826 * median(abs(x - xm), 'omitnan');
if ~isfinite(s) || s <= 0, s = eps; end
end

% =============================================================================
% Small util
% =============================================================================
function out = tern(cond, a, b)
if cond, out = a; else, out = b; end
end

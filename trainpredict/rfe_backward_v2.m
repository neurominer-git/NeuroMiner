function [optparam, optind, optfound, optmodel] = ...
    rfe_backward_v2(Y, label, Ynew, labelnew, Ps, FullFeat, FullParam, ActStr)
%=================================================================================================
% rfe_backward_v2 — Greedy backward (RFE) with adaptive regularization + natural stopping
%
% This version is an upgrade of the legacy NM 1.3 function rfe_backward:
%   • Maintains a per-feature "refusal" vector rvec that penalizes REMOVING certain features,
%     updated by similarity to recently removed features (protects near-duplicates you may
%     still want to keep for stability).
%   • Ranks candidates by a penalized score: val_pen = val - λ_eff * rvec (so higher refusal
%     makes a feature LESS likely to be removed in this iteration).
%   • Natural stopping: stop when NO single removal can beat its penalty within a noise-aware
%     tolerance τ (MAD-based).
%   • Optional Auto-λ: adapt λ_eff to the current gain scale each iteration (from r.AdRef.Auto).
%
% All configuration is prepared in rfe_algo_settings and accessible via r.AdRef.
% There are NO parameter defaults hardcoded here.
%
% INPUT/OUTPUT are identical to rfe_backward.
%=================================================================================================
% (c) Nikolaos Koutsouleris, 10/2025

global VERBOSE TRAINFUNC 

% ------------------------------------------------------------------------------
% Retrieve all wrapper settings (incl. AdRef) prepared upstream
% ------------------------------------------------------------------------------
r = rfe_algo_settings(Y, label, Ynew, labelnew, Ps, FullFeat, FullParam, ActStr);
AD = r.AdRef;   % Adaptive-regularization (prepared in rfe_algo_settings)

% ------------------------------------------------------------------------------
% Initialize state from full model (close to legacy)
% ------------------------------------------------------------------------------
optfound = 0; 
optparam = r.FullParam; 
optind   = r.FullInd;

S        = 1:r.kFea;                 % current *kept* feature indices (relative to r.FullInd)
k        = r.kFea; 
optmodel = r.FullModel;              % may be [], depending on rfe_algo_settings path
if k <= r.MinNum, return; end

Opt = struct('S',[],'Param',[],'ParamTs',[]); % for optional kneepoint

% Ensure 'param' always exists even if we break before a post-removal eval
param = r.FullParam;   % baseline; will be updated after each committed removal

if VERBOSE
    fprintf('\n----------------------------------------------------------------------')
    fprintf('\nGREEDY BACKWARD FEATURE ELIMINATION (v2: adaptive reg + natural stop)')
    fprintf('\n----------------------------------------------------------------------')
    fprintf('\nOptimization data mode: %s', ActStr)
    fprintf('\nParameter evaluation: %s (%s)', r.evaldir, r.optfunc)
    if r.FeatStepPerc
        fprintf('\nStepping: %g%% of %g features per wrapper cycle.', r.lperc, r.kFea)
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
% Compute block stepping (as in legacy)
% ------------------------------------------------------------------------------
lstep = 1;
if r.lperc
    if r.PercMode == 1
        lstep = ceil((numel(S)/100)*r.lperc);
    else
        lstep = r.lperc;
    end
end

% ------------------------------------------------------------------------------
% Adaptive structures (only allocated if enabled)
%   rvec — refusal to REMOVE a given feature (aligned to absolute feature index)
%   SMat — sparse kNN similarity graph between features (|corr|), built once
% ------------------------------------------------------------------------------
if AD.Enable
    rvec = zeros(r.kFea,1);

    % Build sparse |corr| kNN graph among features of r.Y (p x p)
    SMat = rfe_build_similarity_knn(r.Y, AD.kNN);
else
    rvec = []; SMat = [];
end
cnt=0;
% ======================================================================
% Start Wrapper: BACKWARD FEATURE ELIMINATION
% ======================================================================
switch r.WeightSort 
    
    % ------------------------------------------------------------------
    % CASE 1: remove according to performance after single removal
    %         (evaluate each candidate j: score with S\{j})
    % ------------------------------------------------------------------
    case 1 

        while k > r.MinNum 

            l = k;
            lvec = 1:l; lc = numel(lvec);
            if ~lc, break; end
            val = zeros(lc,1);      % raw performance after removing candidate j

            if VERBOSE
                fprintf('\n\tFeature pool size: %4.0f, block size: %4.0f feature(s) ', numel(S), lstep);
            end
            % ----------------------------------------------------------
            % 1) Evaluate raw score for each single-feature removal
            %    val(j) = performance of model trained on S \ {j}
            % ----------------------------------------------------------
            for ii = lc:-1:1
                lind = lvec; 
                lind(ii) = [];                   % S without candidate ii
                kS = S(lind);
                tY = r.Y(:,kS); 
                T  = r.T(:,kS);
                [~, model] = TRAINFUNC(tY, label, 1, Ps);          
                val(ii) = nk_GetTestPerf(T, r.L, [], model, tY);
            end
            % ----------------------------------------------------------
            % 2) Rank "removal desirability" with adaptive penalty
            %    Idea: high refusal rvec makes a feature HARDER to remove.
            %    We therefore subtract λ_eff * rvec from the raw score
            %    BEFORE ranking (so protected features fall in rank).
            % ----------------------------------------------------------
            if AD.Enable
                rsub = rvec(S);  % refusal aligned to current pool
                % Auto-λ: λ_eff adapts to gain scale this iteration
                if AD.Auto.Enable
                    sigmaG = robust_sigma(val);           % ≈ 1.4826 * MAD(val)
                    denom  = 1 + median(rsub,'omitnan');  % scale against present refusal level
                    AD.lambda_eff = AD.Auto.LambdaC * sigmaG / max(denom, eps);
                else
                    AD.lambda_eff = AD.lambda;
                end
                val_pen = val - AD.lambda_eff * rsub;        % protected features get lower penalized score
                [~, ind] = sort(val_pen, r.optfunc);
            else
                [~, ind] = sort(val, r.optfunc);
            end
            if VERBOSE
                % ---- Default diag values for this iteration ----
                raw_delta  = val - optparam;   % improvement vs current best (pre-accept)
                TauUsed    = NaN;
                infoNS     = struct('max_mprime', NaN, 'max_raw_delta', max(raw_delta), 'TauMAD', NaN);
                lam_eff    = NaN;
                if AD.Enable
                    lam_eff = AD.Auto.Enable * AD.lambda_eff + (~AD.Auto.Enable) * AD.lambda; % just for logging
                end
            end
            % ----------------------------------------------------------
            % 3) Natural stopping: if NO single removal can beat its
            %    penalty beyond τ, stop (optionally with patience).
            %    We use m'_j = (val(j) - optparam) - λ_eff * r_j.
            % ----------------------------------------------------------
            if AD.Enable && AD.Stop.Enable
                [stop_now, TauUsed, infoNS] = rfe_natural_stop_test(val, optparam, rvec(S), AD.lambda_eff, AD.Stop);
                if stop_now
                    if VERBOSE
                        fprintf('\n[AdaptiveReg] Natural stop: max penalized gain=%.6g ≤ τ=%.6g (raw max Δ=%.6g, τMAD=%.6g).', ...
                                infoNS.max_mprime, TauUsed, infoNS.max_raw_delta, infoNS.TauMAD);
                    end
                    AD.Stop.holdcnt = getfielddef(AD.Stop,'holdcnt',0) + 1;
                    if AD.Stop.holdcnt > AD.Stop.Patience
                        break;  % exit while-loop; natural halt
                    else
                        % If patience not yet met, continue one more cycle
                        % (penalties will keep drifting up, making stop more likely)
                    end
                else
                    AD.Stop.holdcnt = 0;
                end
            end
            % ----------------------------------------------------------
            % 4) Remove the top-lstep candidates by current ranking
            %    (mirrors legacy: ALWAYS remove; improvement just updates optima)
            % ----------------------------------------------------------
            krem = 1:lstep;
            % Optional random sub-selection within the block
            if r.FeatRandPerc
                rstep = ceil(lstep/100) * r.FeatRandPerc;
                rind  = randperm(lstep, rstep);
            else
                rind  = krem;
            end
            
            % Identify absolute indices to remove this step and COMMIT removal
            rem_local  = ind(rind);               % positions within current pool ordering
            rem_global = S(lvec(rem_local));
            S          = setdiff(S, rem_global, 'stable');   % <-- commit removal
            k          = numel(S);
            if k <= r.MinNum, break; end
            
            % Recompute step size after removal
            if r.PercMode == 1
                lstep = ceil((numel(S)/100)*r.lperc);
                lstep = max(lstep, 1);
            end
            
            % Evaluate performance AFTER removal (for bookkeeping / opt update)
            tY = r.Y(:,S);  T = r.T(:,S);
            [~, model] = TRAINFUNC(tY, label, 1, Ps);
            param = nk_GetTestPerf(T, r.L, [], model, tY);
            
            % Raw improvement relative to current optimum
            raw_impr = param - optparam;
            % ----------------------------------------------------------
            % 5) Update optimum ONLY if improved (legacy behavior)
            % ----------------------------------------------------------
            if feval(r.evaldir, param, optparam)
                optparam = param; 
                optind   = r.FullInd(S); 
                optfound = 1; 
                if VERBOSE 
                    fprintf('=> NEW optimum: # Features: %4.0f ==> %s = %g', numel(optind), ActStr, optparam); 
                    if AD.Enable
                        cnt=cnt+1;
                        % ---- Trace on acceptance ----
                        r.Hist.optparam    = [r.Hist.optparam, optparam];
                        r.Hist.it          = [r.Hist.it, cnt];
                        r.Hist.block_size  = [r.Hist.block_size, lstep];
                        r.Hist.n_selected  = [r.Hist.n_selected, numel(S)];
                        r.Hist.lambda_eff  = [r.Hist.lambda_eff, lam_eff];
                        r.Hist.rho_med     = [r.Hist.rho_med, median(rsub,'omitnan')];
                        r.Hist.rho_max     = [r.Hist.rho_max, max(rsub)];
                        r.Hist.raw_maxGain = [r.Hist.raw_maxGain, max(raw_delta)];
                        r.Hist.max_mprime  = [r.Hist.max_mprime, infoNS.max_mprime];
                        r.Hist.tau_used    = [r.Hist.tau_used, TauUsed];
                        r.Hist.sel_idx{end+1} = r.FullInd(rem_global);   % map to original feature indices
                        if ~isfield(r.Hist,'sel_local') || isempty(r.Hist.sel_local), r.Hist.sel_local = {}; end
                        r.Hist.sel_local{end+1} = rem_global;         % local indices 1..kFea

                        % Optional: update natural stop history for the MAD band
                        if AD.Enable && AD.Stop.Enable
                            AD.Stop.hist = [AD.Stop.hist; raw_impr];
                            if numel(AD.Stop.hist) > AD.Stop.MADWinsz
                                AD.Stop.hist = AD.Stop.hist(end-AD.Stop.MADWinsz+1:end);
                            end
                        end
                        % Optional: rvec snapshot every N accepts
                        if AD.Enable && r.Hist.snap_every>0 && mod(cnt, r.Hist.snap_every)==0
                            r.Hist.rvec_snap{end+1} = rvec(:);
                            r.Hist.rvec_snap_it      = [r.Hist.rvec_snap_it, cnt];
                        end
                        % each acceptance step
                    end
                end
                Opt.S{end+1}  = S; 
                Opt.Param     = [Opt.Param optparam];
            
                % Record into natural-stop history (only when accepted)
                if AD.Enable && AD.Stop.Enable
                    if ~isfield(AD.Stop,'hist') || isempty(AD.Stop.hist), AD.Stop.hist = []; end
                    AD.Stop.hist = [AD.Stop.hist; raw_impr];
                    if numel(AD.Stop.hist) > AD.Stop.MADWinsz
                        AD.Stop.hist = AD.Stop.hist(end-AD.Stop.MADWinsz+1:end);
                    end
                end
            else
                if VERBOSE, fprintf('(%s = %g)', ActStr, optparam); end
            end
            % ------------------------------------------------------
            % 6) Update refusal rvec to PROTECT remaining neighbors
            %    of the removed features (backward → use -φ)
            % ------------------------------------------------------
            if AD.Enable
                % decay + global drift
                if isempty(rvec), rvec = zeros(r.kFea,1); end
                rvec = AD.gamma * rvec + AD.eta0;
            
                % Rank weights from current iteration (use previous single-removal scores)
                ranks = tiedrank(-val);                     % 1 = most desirable removal
                w_ts  = ranks(rem_local) / numel(val);
            
                for jj = 1:numel(rem_global)
                    i_t = rem_global(jj);
                    si_sparse = SMat(:, i_t);
                    if ~isempty(si_sparse)
                        si  = full(si_sparse);
                        pen = rfe_redundancy_penalty(si, AD.c, AD.w, AD.beta_well, AD.beta_hi, AD.sigma_lo, AD.sigma_hi); % φ(s)
                        bump = AD.eta1 * (1 - w_ts(jj)) * (-pen);   % protect neighbors
                        rvec = rvec + bump;
                    end
                end
            
                % Cap for stability
                rvec = min(rvec, AD.rmax);
            end
            % ----------------------------------------------------------
            % 7) Update step size & counters (as in legacy)
            % ----------------------------------------------------------
            if r.PercMode == 1
                lstep = ceil((numel(S)/100)*r.lperc);
            end
            k = numel(S);   % #features left
            if k <= r.MinNum, break; end
        end
    % ------------------------------------------------------------------
    % CASE 2: remove according to smallest absolute weights (linear only)
    %         We preserve your flow, adding refusal and natural stop.
    % ------------------------------------------------------------------
    case 2
        
         % Initial weights from the full model provided upstream
         W = abs(nk_GetPrimalW(r.FullModel));
         if norm(W,2) > 0, W = W / (norm(W,2)); end
         [~, ind] = sort(W, 'ascend');   % smallest weights removed first (legacy)

         if AD.Enable
             rvec = zeros(r.kFea,1);
             SMat = rfe_build_similarity_knn(r.Y, AD.kNN);
         end
         
         while k > r.MinNum
             
            if VERBOSE
                fprintf('\n\tFeature pool size: %g out of %g, block size: %g feature(s) ', numel(S), r.kFea, lstep);
            end
            % ----------------------------------------------------------
            % 1) Optional re-ranking with refusal (protect via +rvec)
            % ----------------------------------------------------------
            if AD.Enable
                rsub  = rvec(S);
                Wpool = W(S);
                if AD.Auto.Enable
                    % Use robust spread of Wpool as proxy; or do mini evals as in CASE 1 (costly)
                    sigmaG = robust_sigma(Wpool);
                    denom  = 1 + median(rsub,'omitnan');
                    AD.lambda_eff = AD.Auto.LambdaC * sigmaG / max(denom, eps);
                else
                    AD.lambda_eff = AD.lambda;
                end
                [~, ind] = sort(Wpool - AD.lambda_eff * rsub, 'ascend'); % protect high-refusal features
            end

            % Select removal block by index and COMMIT removal (legacy behavior)
            krem = 1:lstep; 
            rem_local  = ind(krem);
            rem_global = S(rem_local);
            S          = setdiff(S, rem_global, 'stable');   % <-- commit removal
            k          = numel(S);
            if r.PercMode == 1
                lstep = ceil((numel(S)/100)*r.lperc);
                lstep = max(lstep, 1);
            end
            if k <= r.MinNum, break; end
            
            % Evaluate performance AFTER removal
            tY = r.Y(:,S);  T = r.T(:,S);
            [~, model] = TRAINFUNC(tY, label, 1, Ps);    
            param = nk_GetTestPerf(T, r.L, [], model, tY);
            
            % Raw improvement (for history if accepted)
            raw_impr = param - optparam;
            
            % Accept optimum only if improved
            if feval(r.evaldir, param, optparam) 
                optparam = param; 
                optind   = r.FullInd(S); 
                optfound = 1;
                if VERBOSE, fprintf('=> NEW optimum: # Features: %4.0f ==> %s = %g', numel(S), ActStr, optparam); end
                Opt.S{end+1} = S; 
                Opt.Param    = [Opt.Param optparam];
            
                if AD.Enable && AD.Stop.Enable
                    if ~isfield(AD.Stop,'hist') || isempty(AD.Stop.hist), AD.Stop.hist = []; end
                    AD.Stop.hist = [AD.Stop.hist; raw_impr];
                    if numel(AD.Stop.hist) > AD.Stop.MADWinsz
                        AD.Stop.hist = AD.Stop.hist(end-AD.Stop.MADWinsz+1:end);
                    end
                end
            else
                if VERBOSE, fprintf('(%s = %g)', ActStr, optparam); end
            end
            
            % Refusal update (protect neighbors of removed features)
            if AD.Enable
                rvec = AD.gamma * rvec + AD.eta0;
            
                % Use W ranks of removed items as a proxy for w_t
                ranks_pool = tiedrank(W(S));            % smallest weight = rank 1
                if ~isempty(ranks_pool)
                    w_t = mean(ranks_pool(1:min(numel(ranks_pool), numel(rem_local))) / numel(S));
                else
                    w_t = 0.5;
                end
            
                for jj = 1:numel(rem_global)
                    i_t = rem_global(jj);
                    si_sparse = SMat(:, i_t);
                    if ~isempty(si_sparse)
                        si  = full(si_sparse);
                        pen = rfe_redundancy_penalty(si, AD.c, AD.w, AD.beta_well, AD.beta_hi, AD.sigma_lo, AD.sigma_hi);
                        bump = AD.eta1 * (1 - w_t) * (-pen);
                        rvec = rvec + bump;
                    end
                end
                rvec = min(rvec, AD.rmax);
            end
            
            % Recompute weights on remaining pool for next ranking
            [~, kmodel] = TRAINFUNC(r.Y(:,S), label, 1, Ps);    
            W = abs(nk_GetPrimalW(kmodel));
            [~, ind] = sort(W,'ascend');   % smallest first, like legacy

            % ----------------------------------------------------------
            % 4) Natural stopping — safer route: mini single-removal evals
            %    (same as CASE 1) to compute m'_j. Optional but robust.
            % ----------------------------------------------------------
            if AD.Enable && AD.Stop.Enable
                lc = numel(S);
                if lc > 0
                    val_tmp = zeros(lc,1);
                    for ii = lc:-1:1
                        kS_tmp = S; kS_tmp(ii) = [];     % remove one
                        tY_tmp = r.Y(:,kS_tmp); 
                        T_tmp  = r.T(:,kS_tmp);
                        [~, mtmp] = TRAINFUNC(tY_tmp, label, 1, Ps);
                        val_tmp(ii) = nk_GetTestPerf(T_tmp, r.L, [], mtmp, tY_tmp);
                    end
                    [stop_now, TauUsed, infoNS] = rfe_natural_stop_test(val_tmp, optparam, rvec(S), AD.lambda_eff, AD.Stop);
                    if stop_now
                        if VERBOSE
                            fprintf('\n[AdaptiveReg] Natural stop (W-branch): max penalized gain=%.6g ≤ τ=%.6g (raw max Δ=%.6g, τMAD=%.6g).', ...
                                    infoNS.max_mprime, TauUsed, infoNS.max_raw_delta, infoNS.TauMAD);
                        end
                        AD.Stop.holdcnt = getfielddef(AD.Stop,'holdcnt',0) + 1;
                        if AD.Stop.holdcnt > AD.Stop.Patience
                            break;
                        end
                    else
                        AD.Stop.holdcnt = 0;
                    end
                end
            end
         
            % ----------------------------------------------------------
            % 5) Retrain weights for remaining pool; recompute step size
            % ----------------------------------------------------------
            [~, kmodel] = TRAINFUNC(r.Y(:,S), label, 1, Ps);    
            W = abs(nk_GetPrimalW(kmodel));
            if r.lperc && r.PercMode == 1
                lstep = ceil((numel(S)/100)*r.lperc); 
            end
            k = numel(S);
            if k <= r.MinNum, break; end
         end
    
end

% ======================================================================
% Finalize: compare to original, kneepoint selection as in legacy
% ======================================================================
% If 'param' was never (re)computed due to an early/natural stop, compute it now
if ~isfinite(param)
    tY = r.Y(:,S);  T = r.T(:,S);
    [~, model] = TRAINFUNC(tY, label, 1, Ps);
    param = nk_GetTestPerf(T, r.L, [], model, tY);
end
if ~feval(r.evaldir, optparam, r.FullParam)
    % Wrapper did not beat original: return original model
    optparam = r.FullParam; 
    optind   = r.FullInd; 
    optfound = 0; 
    optmodel = r.FullModel;
elseif (~isfinite(param) || isempty(param)) && ~optfound
    % Non-finite performance encountered and no optimum found
    optind   = r.FullInd; 
    optmodel = r.FullModel; 
    optparam = r.FullParam;
    fprintf('\n'); warning('Greedy backward search did not return any feature mask for given parameter setting. Return original feature space.')
else
    optfound = 1;
    if r.KneePoint
        kneepoint = knee_pt(Opt.Param,[],true);
        if isnan(kneepoint)
            fprintf('\nNot enough data points to compute kneepoint. Selecting final feature mask.');
            optind = r.FullInd(S);
        else
            fprintf('\nSelected kneepoint of optimization curve at wrapper cycle #%g => %s = %g', kneepoint, ActStr, Opt.Param(kneepoint));
            try
                optind = r.FullInd(Opt.S{kneepoint});
            catch
                fprintf('\nNo optimum found. Selecting current feature mask.');
                optind = r.FullInd(S);
            end
        end
    else
        optind = r.FullInd(S);
    end
    [~, optmodel] = TRAINFUNC(Y(:,optind), label, 1, Ps); 
end

if VERBOSE
    fprintf('\nDone. '); 
    if AD.Enable
        rfe_plot_wrapper_trace(r.Hist, AD); 
        drawnow();
    end
end

end 

% =============================================================================
% Small utilities
% =============================================================================
function s = robust_sigma(x)
% Robust σ ≈ 1.4826 * median(|x - median(x)|), NaN-safe.
x = x(:);
xm = median(x,'omitnan');
s  = 1.4826 * median(abs(x - xm), 'omitnan');
if ~isfinite(s) || s <= 0, s = eps; end
end

function out = tern(cond, a, b)
if cond, out = a; else, out = b; end
end

function v = getfielddef(S, f, d)
if isstruct(S) && isfield(S,f) && ~isempty(S.(f)), v = S.(f); else, v = d; end
end

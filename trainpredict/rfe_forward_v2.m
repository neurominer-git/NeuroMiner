function [optparam, optind, optfound, optmodel] = ...
    rfe_forward_v2(Y, label, Ynew, labelnew, Ps, FullFeat, FullParam, ActStr)
%=============================================================================
% function [optparam, optind, optfound, optmodel] = ...
%    rfe_forward_v2(Y, label, Ynew, labelnew, Ps, FullFeat, FullParam, ActStr)
% ============================================================================
% Greedy forward search with adaptive regularization and natural stopping
%
% This version is an upgrade of the legacy NM 1.3 function rfe_forward wrapper:
%  (A) Adaptive, similarity-aware per-feature penalties ("refusal") r_j
%  (B) A natural stopping rule: stop when no feature can surmount its
%      current penalty (within a small, noise-aware tolerance)
%
% Key ideas:
%  • Maintain a penalty vector rvec (size = #features) that:
%      - decays slightly each step (memory), plus small global drift
%      - gets a "similarity bump" around newly accepted features
%      - uses a smooth redundancy penalty φ(s) that is negative on [0.4,0.7]
%        (encourage moderate redundancy) and positive outside (discourage
%        too-high redundancy and overly dissimilar additions)
%      - is performance-weighted: bigger marginal gain ⇒ smaller bump
%  • Rank candidates by penalized score: val_pen = val - λ * rvec(candidates)
%  • Natural stopping: if max_j{ (val(j)-optparam) - λ*r_j } ≤ τ, stop.
%      τ = max(TauAbs,  Zmad * 1.4826 * MAD(recent accepted improvements))
%
% Toggling:
%  • r.AdRef.Enable = true to activate (defaults set below if missing)
%==========================================================================
%(c) Nikolaos Koutsouleris, 10/2025

global VERBOSE TRAINFUNC
%----------------------------------------------------------------------
% use settings builder (unchanged)
%----------------------------------------------------------------------
r = rfe_algo_settings(Y, label, Ynew, labelnew, Ps, FullFeat, FullParam, ActStr);

%----------------------------------------------------------------------
% Adaptive Regularization Defaults (injected locally for easy testing)
% These can be moved these into rfe_algo_settings later.
%----------------------------------------------------------------------
AD = r.AdRef;

%----------------------------------------------------------------------
% Initialization (unchanged from the original, plus banner tweaks)
%----------------------------------------------------------------------
S = [];                 % indices (within r.FullInd) of selected features
Sind = 1:r.kFea;        % current pool indices (within r.FullInd)
k = r.kFea;             % counter for remaining pool size
optfound = 0;           
optparam = r.optparam;  % best performance so far
param = nan;            % last evaluated block performance

if VERBOSE
    fprintf('\n---------------------------------------------------------------')
    fprintf('\nGREEDY FORWARD FEATURE SEARCH (v2: adaptive reg + natural stop)')
    fprintf('\n---------------------------------------------------------------')
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
        fprintf('\n[AdaptiveReg] ON: gamma=%.3f eta0=%.3g eta1=%.3g lambda=%.3f kNN=%d rmax=%.1f', ...
                AD.gamma, AD.eta0, AD.eta1, AD.lambda, AD.kNN, AD.rmax);
        fprintf('\n[AdaptiveReg] φ(s): c=%.2f w=%.2f (beta_well=%g, beta_hi=%g, sigma_lo=%g, sigma_hi=%g)', ...
                AD.c, AD.w, AD.beta_well, AD.beta_hi, AD.sigma_lo, AD.sigma_hi);
        if AD.Stop.Enable
            fprintf('\n[NaturalStop] τ_abs=%.1e, UseMAD=%d (W=%d, Zmad=%.1f), Patience=%d', ...
                    AD.Stop.TauAbs, AD.Stop.UseMAD, AD.Stop.MADWinsz, AD.Stop.Zmad, AD.Stop.Patience);
        end
    end
end

% Compute step size lstep from percentage mode (unchanged)
lstep = 1;
if r.lperc
    if r.PercMode == 1
        lstep = ceil((numel(Sind)/100)*r.lperc);
    else
        lstep = r.lperc;
    end
end

% For optional knee-point selection
Opt = struct('S',[],'Param',[],'ParamTs',[]);

%----------------------------------------------------------------------
% Adaptive regularization structures
%----------------------------------------------------------------------
if AD.Enable
    % rvec: per-feature refusal/penalty (aligned with absolute feature indices)
    rvec = zeros(r.kFea,1);

    % SMat: sparse k-NN similarity graph on current training design r.Y
    %       (computed fold-safely; |corr| with pairwise rows; top-k neighbors)
    SMat = rfe_build_similarity_knn(r.Y, AD.kNN);
else
    rvec = []; SMat = [];
end
cnt = 0;

%%======================================================================
%% Start Wrapper: FORWARD FEATURE SELECTION
%%======================================================================
switch r.WeightSort 
    
    %------------------------------------------------------------------
    % CASE 1: Sorting by CV1 performance (train/test/average/combined)
    %------------------------------------------------------------------
    case 1 

        while k > r.MinNum 

            lc = numel(Sind);
            if ~lc, break; end

            % val   : raw candidate performance when adding that single feature
            % valts : optional test performance for critical gap logic
            val  = zeros(lc,1);
            valts = val;

            if VERBOSE
                fprintf('\n\tFeature pool size: %4.0f out of %4.0f, block size: %4.0f feature(s) ', ...
                        numel(S), numel(Sind), lstep);
            end

            %----------------------------------------------------------
            % 1) Evaluate raw marginal gains for each candidate feature
            %    We compute raw val(j) so penalty affects only ranking,
            %    not the measurement of gain itself.
            %----------------------------------------------------------
            for ii = lc:-1:1
                kS = [S Sind(ii)];      % current selection plus candidate j
                tY = r.Y(:,kS); 
                T  = r.T(:,kS);
                [~, model] = TRAINFUNC(tY, label, 1, Ps);
                val(ii) = nk_GetTestPerf(T, r.L, [], model, tY);
                if r.CritFlag
                    valts(ii) = nk_GetTestPerf(r.TT(:,kS), r.LL, [], model, tY);
                end
            end
            %----------------------------------------------------------
            % 2) Rank candidates by penalized score (if adaptive on)
            %    val_pen = val - lambda * rvec(current pool)
            %----------------------------------------------------------
            if AD.Enable
                rsub = rvec(Sind);
                % ---------- Auto-λ: compute lambda_eff from gain scale ----------
                if AD.Auto.Enable
                    sigmaG = robust_sigma(val);  % 1.4826*mad (median-based), omitnan
                    denom  = 1 + median(rsub,'omitnan');
                    AD.lambda_eff = AD.Auto.LambdaC * sigmaG / max(denom, eps);
                else
                    AD.lambda_eff = AD.lambda;
                end
                val_pen = val - AD.lambda_eff * rsub;
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
            %----------------------------------------------------------
            % 3) Natural stopping test:
            %    If no feature can surmount its penalty (within tolerance),
            %    stop now (optionally with patience across iterations).
            %----------------------------------------------------------
            if AD.Enable && AD.Stop.Enable
                [should_stop, TauUsed, infoNS] = rfe_natural_stop_test(val, optparam, rvec(Sind), AD.lambda_eff, AD.Stop);
                if should_stop
                    if VERBOSE
                        fprintf('\n[AdaptiveReg] Natural stop: max penalized gain=%.6g ≤ τ=%.6g (raw max Δ=%.6g, τMAD=%.6g).', ...
                                infoNS.max_mprime, TauUsed, infoNS.max_raw_delta, infoNS.TauMAD);
                        if should_stop && AD.Stop.holdcnt > AD.Stop.Patience
                            r.Hist.stopped = true;
                            r.Hist.tau_used = [r.Hist.tau_used, Tau]; % last seen τ
                        end
                    end
                    AD.Stop.holdcnt = AD.Stop.holdcnt + 1;
                    if AD.Stop.holdcnt > AD.Stop.Patience
                        break; % exit the while-loop; natural halt
                    else
                        % If patience not yet met, continue one more cycle
                        % (penalties will keep drifting up, making stop more likely)
                    end
                else
                    AD.Stop.holdcnt = 0; % reset hold count when condition breaks
                end
            end
            %----------------------------------------------------------
            % 4) Build the proposed block (top lstep candidates by rank)
            %    Then evaluate the block's overall performance "param".
            %----------------------------------------------------------
            krem = 1:lstep; 
            rind = krem;                       % may randomize later
            pick = Sind(ind(krem));            % proposed block (pool-relative ids)
            kS = [S pick];                     % trial selection including block
            tY = r.Y(:,kS);  
            T  = r.T(:,kS);
            [~, model] = TRAINFUNC(tY, label, 1, Ps);
            param = nk_GetTestPerf(T, r.L, [], model, tY);
            if r.CritFlag
                paramts = nk_GetTestPerf(r.TT(:,kS), r.LL, [], model, tY);
            else
                paramts = [];
            end
            %----------------------------------------------------------
            % 5) Accept the block only if it improves the current optimum
            %    (unchanged logic; random sub-selection optional)
            %----------------------------------------------------------
            if feval(r.evaldir2, param, optparam) 
                % Optional random sub-selection of the block (your feature)
                if r.FeatRandPerc
                    rstep = ceil(lstep/100)*r.FeatRandPerc;
                    rind = randperm(lstep, rstep);
                else
                    rind = krem;
                end

                % --- Determine the features actually added this step
                add_inds = ind(rind);       % indices within "Sind" ordering
                add_feat = Sind(add_inds);  % absolute feature indices (within r.FullInd)

                % --- Bookkeeping: compute raw improvement BEFORE updating optparam
                raw_impr = param - optparam;

                % --- Commit the additions
                S = [S add_feat]; 
                optparam = param;           % update best-so-far
                optfound = 1; 
                if VERBOSE
                    fprintf('=> NEW optimum: # Features: %4.0f ==> %s = %g', numel(S), ActStr, optparam);
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
                        r.Hist.sel_idx{end+1} = r.FullInd(add_feat);   % map to original feature indices
                        if ~isfield(r.Hist,'sel_local') || isempty(r.Hist.sel_local), r.Hist.sel_local = {}; end
                        r.Hist.sel_local{end+1} = add_feat;         % local indices 1..kFea

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
                Opt.S{end+1}   = S; 
                Opt.Param      = [Opt.Param optparam];

                % --- Update natural stop history with the raw improvement
                if AD.Enable && AD.Stop.Enable
                    AD.Stop.hist = [AD.Stop.hist; raw_impr];
                    if numel(AD.Stop.hist) > AD.Stop.MADWinsz
                        AD.Stop.hist = AD.Stop.hist(end-AD.Stop.MADWinsz+1:end);
                    end
                end

                %------------------------------------------------------
                % 6) Adaptive regularization update (if enabled)
                %    • decay + drift
                %    • similarity bumps around each accepted feature
                %    • performance weighting via rank-based w_t
                %------------------------------------------------------
                if AD.Enable
                    % 6.1 decay + global drift (always increase)
                    rvec = AD.gamma * rvec + AD.eta0;

                    % 6.2 compute rank-based w_t per accepted candidate
                    %     ranks based on RAW marginal "val" (not penalized)
                    ranks = tiedrank(-val);                 % 1=best, lc=worst
                    w_ts  = ranks(add_inds) / numel(val);  % vector aligned to add_feat

                    % 6.3 apply similarity bumps using φ(s)
                    for jj = 1:numel(add_feat)
                        i_t = add_feat(jj);
                        w_t = w_ts(jj);
                        si_sparse = SMat(:, i_t);           % sparse col: similarities to i_t
                        if ~isempty(si_sparse)
                            si  = full(si_sparse);          % dense vector ok; only k entries nonzero
                            pen = rfe_redundancy_penalty(si, AD.c, AD.w, AD.beta_well, AD.beta_hi, AD.sigma_lo, AD.sigma_hi);
                            bump = AD.eta1 * (1 - w_t) * pen;
                            rvec = rvec + bump;             % add bump; affects O(k) entries effectively
                        end
                    end

                    % 6.4 cap refusal values for numerical stability
                    rvec = min(rvec, AD.rmax);
                end

            else
                % No improvement: keep current optimum; optional print
                if VERBOSE, fprintf('(%s = %g)', ActStr, optparam); end
            end

            %----------------------------------------------------------
            % 7) Early stopping via critical gap 
            %    (executes after acceptance check)
            %----------------------------------------------------------
            if r.CritFlag
                crit = 100 - (paramts*100/optparam); 
                if crit >= r.CritGap 
                    if VERBOSE
                        fprintf('\n=> Critical gap between optimal [%g] and test performance [%g] detected (=%g). ABORT further optimization.', ...
                                optparam, paramts, crit );
                    end
                    break
                end
            end

            %----------------------------------------------------------
            % 8) Remove only the features we actually added from the pool
            %    (rind captures the subset of the proposed block we took)
            %----------------------------------------------------------
            Sind(ind(rind)) = [];

            %----------------------------------------------------------
            % 9) Recompute lstep if percentage mode and update counters
            %----------------------------------------------------------
            if r.PercMode == 1 && r.lperc
                lstep = ceil((numel(Sind)/100)*r.lperc);
            end
            k = k - numel(rind);
        end
        
    %------------------------------------------------------------------
    % CASE 2: Sorting by primal weights (abs(W)) from a model on pool
    %------------------------------------------------------------------
    case 2
        
         % Initial W estimate on the full model you provided
         W = abs(nk_GetPrimalW(r.FullModel));
         W = W/(norm(W,2));
         [~, ind] = sort(W,'descend');

         if AD.Enable
             % Maintain refusal and similarity in this branch as well
             rvec = zeros(r.kFea,1);
             SMat = rfe_build_similarity_knn(r.Y, AD.kNN);
         end
         
         while k > r.MinNum
             
            if VERBOSE
                fprintf('\n\tFeature pool size: %4.0f out of %4.0f, block size: %4.0f feature(s) ', ...
                        numel(S), numel(Sind), lstep);
            end
            
            %----------------------------------------------------------
            % 1) If adaptive on, re-rank the pool by W - λ * rvec(Sind),
            %    otherwise use plain W on the pool.
            %----------------------------------------------------------
            if AD.Enable
                rsub = rvec(Sind);
                Wpool = W(Sind);
                [~, ind] = sort(Wpool - AD.lambda_eff * rsub, 'descend');
            end

            % Select the proposed block from the top of the (penalized) order
            krem  = 1:lstep; 
            kSind = Sind(ind(krem));
             
            %----------------------------------------------------------
            % 2) Evaluate the block's performance "param"
            %----------------------------------------------------------
            kS = [S kSind]; 
            tY = r.Y(:,kS);  
            T  = r.T(:,kS);
            [~, model] = TRAINFUNC(tY, label, 1, Ps);    
            param = nk_GetTestPerf(T, r.L, [], model, tY);
            
            %----------------------------------------------------------
            % 3) Accept block if it improves current optimum (unchanged)
            %----------------------------------------------------------
            if feval(r.evaldir2, param, optparam) 
                % Raw improvement BEFORE updating optparam (for stop hist)
                raw_impr = param - optparam;

                % Commit
                S = [S kSind]; 
                optparam = param;
                Opt.S{end+1} = S; 
                Opt.Param    = [Opt.Param optparam];
                if VERBOSE
                    fprintf('=> NEW optimum: # Features: %4.0f ==> %s = %g', numel(S), ActStr, optparam);
                end

                % Update natural stop history
                if AD.Enable && AD.Stop.Enable
                    AD.Stop.hist = [AD.Stop.hist; raw_impr];
                    if numel(AD.Stop.hist) > AD.Stop.MADWinsz
                        AD.Stop.hist = AD.Stop.hist(end-AD.Stop.MADWinsz+1:end);
                    end
                end

                %------------------------------------------------------
                % 4) Adaptive refusal update (decay+drift + sim bumps)
                %    (We approximate "w_t" via W-based ranks here.)
                %------------------------------------------------------
                if AD.Enable
                    rvec = AD.gamma * rvec + AD.eta0;

                    % Use W ranks on remaining pool as a proxy for gains
                    ranks_pool = tiedrank(-W(Sind));        % 1=best
                    w_t = mean(ranks_pool( ind(krem) ) / numel(Sind)); % average for block

                    for jj = 1:numel(kSind)
                        i_t = kSind(jj);
                        si_sparse = SMat(:, i_t);
                        if ~isempty(si_sparse)
                            si  = full(si_sparse);
                            pen = rfe_redundancy_penalty(si, AD.c, AD.w, AD.beta_well, AD.beta_hi, AD.sigma_lo, AD.sigma_hi);
                            bump = AD.eta1 * (1 - w_t) * pen;
                            rvec = rvec + bump;
                        end
                    end
                    rvec = min(rvec, AD.rmax);
                end

            else
                if VERBOSE, fprintf('(%s = %g)', ActStr, optparam); end
            end
            
            %----------------------------------------------------------
            % 5) Natural stopping also applies here.
            %    We need raw single-feature surmountability; approximate
            %    by checking top-1 candidate with the current pool ordering.
            %----------------------------------------------------------
            if AD.Enable && AD.Stop.Enable
                % Approximate single-feature surmountability:
                %   raw_delta ≈ max(Wpool) proxy is less direct; safer is
                %   to do a mini-eval of each remaining candidate as in CASE 1.
                % Here we choose the safer route for correctness.
                lc = numel(Sind);
                if lc > 0
                    val_tmp = zeros(lc,1);
                    for ii = lc:-1:1
                        kS_tmp = [S Sind(ii)];
                        tY_tmp = r.Y(:,kS_tmp); 
                        T_tmp  = r.T(:,kS_tmp);
                        [~, mtmp] = TRAINFUNC(tY_tmp, label, 1, Ps);
                        val_tmp(ii) = nk_GetTestPerf(T_tmp, r.L, [], mtmp, tY_tmp);
                    end
                    [should_stop, TauUsed, infoNS] = rfe_natural_stop_test(val_tmp, optparam, rvec(Sind), AD.lambda_eff, AD.Stop);
                    if should_stop
                        if VERBOSE
                            fprintf('\n[AdaptiveReg] Natural stop (W-branch): max penalized gain=%.6g ≤ τ=%.6g (raw max Δ=%.6g, τMAD=%.6g).', ...
                                    infoNS.max_mprime, TauUsed, infoNS.max_raw_delta, infoNS.TauMAD);
                        end
                        AD.Stop.holdcnt = AD.Stop.holdcnt + 1;
                        if AD.Stop.holdcnt > AD.Stop.Patience
                            break;
                        end
                    else
                        AD.Stop.holdcnt = 0;
                    end
                end
            end

            %----------------------------------------------------------
            % 6) Remove selected features from pool and refresh W
            %----------------------------------------------------------
            Sind(ind(krem)) = [];
            [~, kmodel] = TRAINFUNC(r.Y(:,Sind), label, 1, Ps);    
            W = abs(nk_GetPrimalW(kmodel));
            
            % Recompute lstep if percentage mode and update counters
            if r.lperc, lstep = ceil((numel(Sind)/100)*r.lperc); end
            k = k - numel(krem);
         end
end

%----------------------------------------------------------------------
% Knee point selection (unchanged)
%----------------------------------------------------------------------
if r.KneePoint
    kneepoint = knee_pt(Opt.Param, [], true);
    if VERBOSE
        if isnan(kneepoint)
            fprintf('\nNot enough data points to compute kneepoint. Selecting final feature mask.');
        else
            fprintf('\nSelected kneepoint of optimization curve at wrapper cycle #%g => %s = %g', ...
                    kneepoint, ActStr, Opt.Param(kneepoint));
        end
    end
    if isnan(kneepoint), kneepoint = numel(Opt.S); end
    optind = r.FullInd(Opt.S{kneepoint});

elseif isnan(param) && ~optfound 
    % Fallback: optimization returned non-finite performance; return original
    optind = r.FullInd;
    fprintf('\n'); warning('Greedy forward search did not return any feature mask for given parameter setting. Return original feature space.')
else
    optind = r.FullInd(S);
end

if VERBOSE
    fprintf('\nDone. '); 
    if AD.Enable
        rfe_plot_wrapper_trace(r.Hist, AD); 
        drawnow();
    end
end
optfound = 1; 
[~, optmodel] = TRAINFUNC(Y(:,optind), label, 1, Ps);

end % rfe_forward_v2

function val = getfield_default(S, fld, dflt)
%GETFIELD_DEFAULT  Safely get S.(fld) or return dflt if missing/empty.
    if isstruct(S) && isfield(S, fld) && ~isempty(S.(fld))
        val = S.(fld);
    else
        val = dflt;
    end
end

function s = robust_sigma(x)
%ROBUST_SIGMA  Robust σ ≈ 1.4826 * median(|x - median(x)|), NaN-safe.
    x  = x(:);
    xm = median(x,'omitnan');
    s  = 1.4826 * median(abs(x - xm),'omitnan');
    if ~isfinite(s) || s<=0, s = eps; end
end

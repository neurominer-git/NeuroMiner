function [optparam, optind, optfound, optmodel] = ...
    rfe_forward_multi_v2(Y, mY, label, labelB, labelM, Ynew, labelnew, labelnewM, Ps, FullFeat, FullParam, ngroups, ActStr)
%=================================================================================================
% rfe_forward_multi_v2 — Multi-class greedy forward search with adaptive regularization + natural stop
%
% This is an upgrade of the NM 1.3 function rfe_forward_multi:
%   • Maintains a per-class, per-feature "refusal" vector rvec{c} that
%     penalizes adding features already well-covered by the current set.
%   • Ranks candidate “positions” (one feature per class) by a penalized score:
%       val_pen(m) = val(m) - lambda_eff * rho(m),
%     where rho(m) aggregates the per-class refusals of the m-th candidate.
%   • Natural stopping: stop when no candidate’s penalized gain exceeds a
%     noise-aware tolerance τ (MAD-based with optional patience).
%   • Optional Auto-λ: adapts λ_eff to the iteration’s gain scale.
%
% INPUTS/OUTPUTS are identical to rfe_forward_multi.
% All configuration is obtained from rfe_algo_settings_multi via r.AdRef.
%=================================================================================================
% (c) Nikolaos Koutsouleris, 10/2025

global VERBOSE TRAINFUNC

% ------------------------------------------------------------------------------
% Retrieve settings prepared upstream (incl. AdRef for adaptive behaviour)
% ------------------------------------------------------------------------------
r = rfe_algo_settings_multi(Y, mY, label, labelB, labelM, Ynew, labelnew, labelnewM, Ps, FullFeat, FullParam, ngroups, ActStr);
AD = r.AdRef;                 % Adaptive-regularization config (prepared in settings)
nclass = numel(Y);            % number of binary submodels in the ensemble
optfound = 0; 
optparam = r.optparam;        % ensemble performance of the current best
r.InitializeOrder = true;

% ------------------------------------------------------------------------------
% Banner (legacy text + small adaptive tag)
% ------------------------------------------------------------------------------
if VERBOSE
    fprintf('\n----------------------------------------------------------------------------')
    fprintf('\nGREEDY FORWARD FEATURE SEARCH (multi-class, v2: adaptive reg + natural stop)')
    fprintf('\n----------------------------------------------------------------------------')
    fprintf('\nOptimization data mode: %s', ActStr)
    fprintf('\nParameter evaluation: %s (%s)', r.evaldir, r.optfunc)
    if r.FeatStepPerc
        for curclass=1:nclass
            fprintf('\nStepping: %g%% of %g features in model #%g per wrapper cycle.', r.lperc(curclass), r.kFea(curclass), curclass)
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
% Initialize per-class structures (legacy pool + step sizes)
% ------------------------------------------------------------------------------
S     = cell(1,nclass);          % selected features per class (indices into r.FullInd{c})
Sind  = cell(1,nclass);          % remaining pool per class (same indexing)
k     = zeros(1,nclass);         % #features per class
lstep = zeros(1,nclass);         % step size per class

for curclass=1:nclass
    k(curclass) = r.kFea(curclass);
    if r.PreSort
        Sind{curclass} = r.PreOrder{curclass};
    else
        Sind{curclass} = 1:r.kFea(curclass);
    end
    lstep(curclass) = 1;
    if r.lperc(curclass)
        lstep(curclass) = ceil((numel(Sind{curclass})/100) * r.lperc(curclass));
    end
end

maxK = max(k); 
minK = min(r.MinNum); 
Opt  = struct('S',[],'Param',[],'ParamTs',[]);
cnt  = 1;

% ------------------------------------------------------------------------------
% Adaptive structures (only if enabled):
%   rvec{c} — refusal per feature (length p_c) for class c
%   SMat{c} — sparse kNN similarity (|corr|) among features for class c
% ------------------------------------------------------------------------------
if AD.Enable
    rvec = cell(1,nclass);
    SMat = cell(1,nclass);
    for c = 1:nclass
        rvec{c} = zeros(r.kFea(c),1);
        SMat{c} = rfe_build_similarity_knn(r.Y{c}, AD.kNN);
    end
    % History for natural stopping
    if AD.Stop.Enable
        AD.Stop.hist    = [];    % recent accepted raw gains (ensemble-level)
        AD.Stop.holdcnt = 0;     % patience counter
    end
end

% Ensure 'param' always exists for the finalization block
param = optparam;

% ======================================================================
% Start Wrapper: FORWARD FEATURE SELECTION
% ======================================================================
while maxK > minK

    % maxNS = maximum number of candidates across classes for this iteration
    maxNS = max(cellfun(@numel, Sind));
    if ~maxNS, break; end

    % val(m) is the ensemble performance if we add the m-th candidate across all classes
    val = zeros(maxNS,1); 

    if VERBOSE
        for curclass=1:nclass
            fprintf('\n\tFeature pool size of model #%g: %4.0f out of %4.0f, block size: %4.0f feature(s) ', ...
                curclass, numel(S{curclass}), numel(Sind{curclass}), lstep(curclass));
        end
    end

    % tEnd(m,c) will hold the index (into Sind{c}) of the m-th candidate for class c
    tEnd = zeros(maxNS, nclass);
    % ds/ts hold per-sample decision/score outputs for the ensemble metric
    ds = zeros(size(r.T{1},1), nclass, maxNS);
    ts = zeros(size(r.T{1},1), nclass, maxNS);

    % ----------------------------------------------------------
    % Evaluate raw candidate scores val(m) for adding m-th feature per class
    % (legacy logic preserved)
    % ----------------------------------------------------------
    mm = maxNS; 
    while mm > 0
        for curclass=1:nclass
            NSind = numel(Sind{curclass});
            if mm > NSind
                tEnd(mm, curclass) = Sind{curclass}(NSind);
            else
                tEnd(mm, curclass) = Sind{curclass}(mm);
            end
            kS = [S{curclass} tEnd(mm,curclass)];
            tY = r.Y{curclass}(:,kS); T = r.T{curclass}(:,kS);
            [~, model] = TRAINFUNC(tY, label{curclass}, 1, Ps{curclass});
            [~, ts(:, curclass, mm), ds(:, curclass, mm)] = nk_GetTestPerf(T, r.L{curclass}, [], model, tY);
        end
        val(mm) = nk_MultiEnsPerf(ds(:,:, mm), ts(:,:, mm), r.Lm, 1:nclass, r.ngroups);
        mm = mm - 1;
    end

    % ----------------------------------------------------------
    % Adaptive ranking: penalize candidates by refusal
    %   Each candidate "position" m proposes one feature per class:
    %      f_c = tEnd(m, c) for class c.
    %   Aggregate refusal rho(m) across classes (median for robustness),
    %   then sort val_pen = val - lambda_eff * rho.
    % ----------------------------------------------------------
    if AD.Enable
        % Gather refusal per candidate across classes
        rho = zeros(maxNS,1);
        for mm = 1:maxNS
            rvals = zeros(nclass,1);
            for c = 1:nclass
                f = tEnd(mm,c);
                % Guard against empty pools per class
                if f > 0 && f <= numel(rvec{c})
                    rvals(c) = rvec{c}(f);
                else
                    rvals(c) = 0;
                end
            end
            rho(mm) = median(rvals);   % robust aggregation
        end

        % Auto-λ or manual λ
        if AD.Auto.Enable
            sigmaG     = robust_sigma(val);             % ≈ 1.4826·MAD(val)
            denom      = 1 + median(rho,'omitnan');     % scale down if refusal already high
            lambda_eff = AD.Auto.LambdaC * sigmaG / max(denom, eps);
        else
            lambda_eff = AD.lambda;
        end

        val_pen = val - lambda_eff * rho;
        [~, ind] = sort(val_pen, r.optfunc);
    else
        [~, ind] = sort(val, r.optfunc);
        lambda_eff = NaN; % only for logging/consistency; not used
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
    % Candidate block selection and evaluation (legacy behaviour)
    % ----------------------------------------------------------
    ds2 = zeros(size(r.T{1},1), nclass);
    ts2 = zeros(size(r.T{1},1), nclass);
    krem = 1:min(lstep); 
    rind = krem;

    for curclass=1:nclass
        % The legacy code supports permutation-based selection; keep it
        if r.perm
            % NOTE: In your original code, permind is only defined in perm branch above.
            % If you use permutations, replicate that logic here too; otherwise this path
            % is unchanged from legacy behaviour.
            error('Permutation-based block selection not wired into v2 ranking here. Disable r.perm or extend perm mapping for val_pen.');
        else
            IndAdd_c = tEnd(ind(krem), curclass)'; % candidates for this class from the top-k positions
        end

        kS = [S{curclass} IndAdd_c];
        tY = r.Y{curclass}(:,kS); T = r.T{curclass}(:,kS);
        [~, model] = TRAINFUNC(tY, label{curclass}, 1, Ps{curclass});
        [~, ds2(:,curclass), ts2(:,curclass)] = nk_GetTestPerf(T, r.L{curclass}, [], model, tY); 
    end

    % Ensemble performance with this proposed block
    param = nk_MultiEnsPerf(ds2, ts2, r.Lm, 1:nclass, r.ngroups);      

    % ----------------------------------------------------------
    % Accept the block only if performance improves (legacy rule)
    % ----------------------------------------------------------
    if feval(r.evaldir, param, optparam) 
        % Random sub-selection within the block, if requested (legacy)
        if r.FeatRandPerc
            rstep = ceil(min(lstep)/100) * r.FeatRandPerc;
            rind  = randperm(min(lstep), rstep);
        else
            rind  = krem;
        end

        % Commit selection to S per class; record optimization trace
        for curclass=1:nclass
            IndAdd_c = tEnd(ind(rind), curclass)';   % accepted positions mapped to class features
            S{curclass} = [S{curclass} IndAdd_c]; 
            Opt.S{curclass, cnt} = S{curclass};
        end
        raw_impr  = param - optparam;               % ensemble-level raw improvement
        optparam  = param; 
        optfound  = 1; 
        if VERBOSE, fprintf('=> NEW optimum: # Features: %4.0f ==> %s = %g', mean(cellfun(@numel,S)), ActStr, optparam); end
        Opt.Param = [Opt.Param optparam];
        cnt       = cnt + 1;

        % Record into natural-stop history (for MAD band)
        if AD.Enable && AD.Stop.Enable
            AD.Stop.hist = [AD.Stop.hist; raw_impr];
            if numel(AD.Stop.hist) > AD.Stop.MADWinsz
                AD.Stop.hist = AD.Stop.hist(end-AD.Stop.MADWinsz+1:end);
            end
        end

        % ------------------------------------------------------
        % Adaptive update: bump refusals around the ACCEPTED features
        %   r_c ← γ r_c + η0 + η1 * (1 - w_t) * φ(s)
        %   where s is similarity to the just-added feature in class c.
        %   (Forward: use +φ to down-rank similar candidates next round.)
        % ------------------------------------------------------
        if AD.Enable
            % Decay + global drift for all classes
            for c = 1:nclass
                rvec{c} = AD.gamma * rvec{c} + AD.eta0;
            end

            % Rank weights from this iteration based on RAW candidate scores
            ranks = tiedrank(-val);                        % 1 = best position
            w_ts  = ranks(ind(rind)) / numel(val);         % weights for accepted positions

            % For each accepted "position", update each class separately
            for jj = 1:numel(rind)
                pos = ind(rind(jj));   % global candidate position
                w_t = w_ts(jj);
                for c = 1:nclass
                    i_t = tEnd(pos, c);                 % feature index chosen for class c
                    if i_t < 1 || i_t > size(SMat{c},2), continue; end
                    si_sparse = SMat{c}(:, i_t);
                    if isempty(si_sparse), continue; end
                    si  = full(si_sparse);
                    pen = rfe_redundancy_penalty(si, AD.c, AD.w, AD.beta_well, AD.beta_hi, AD.sigma_lo, AD.sigma_hi);
                    bump = AD.eta1 * (1 - w_t) * pen;   % forward: +φ
                    rvec{c} = rvec{c} + bump;
                end
            end

            % Cap
            for c = 1:nclass
                rvec{c} = min(rvec{c}, AD.rmax);
            end
        end
    else
        if VERBOSE, fprintf('(%s = %g)', ActStr, optparam); end
        % No acceptance ⇒ no adaptive bump (consistent with forward_v2 design).
    end

    % ----------------------------------------------------------
    % Remove considered features from the per-class pools (legacy behaviour)
    %   Note: legacy uses 'rind' for removing from Sind, so random sub-selection
    %         affects removal too (keep unchanged).
    % ----------------------------------------------------------
    for curclass=1:nclass
        IndRemove_c = tEnd(ind(rind), curclass)';  % features to remove from pool for this class
        remInd = ismember(Sind{curclass}, IndRemove_c);
        Sind{curclass}(remInd) = [];
        % Recompute step size for this class
        if r.lperc(curclass)
            lstep(curclass) = ceil((numel(Sind{curclass})/100) * r.lperc(curclass));
            lstep(curclass) = max(lstep(curclass), 1);
        end
    end

    % Update counters; if *any* class still has many, we keep going
    maxK = maxK - numel(rind);
end

% ======================================================================
% Finalization: knee-point logic and final model fit (legacy-compatible)
% ======================================================================
optind = cell(1, nclass);

for curclass=1:nclass
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
        try
            optind{curclass} = r.FullInd{curclass}( Opt.S{curclass}{kneepoint} );
        catch
            fprintf('\nNo optimum found. Selecting original feature mask.');
            optind{curclass} = r.FullInd{curclass};
        end

    elseif (~isfinite(param) || isempty(param)) && ~optfound
        % Optimization returned non-finite performance at given parameter combination.
        optind{curclass} = r.FullInd{curclass};
        fprintf('\n');warning('Greedy forward search (multi) did not return any feature mask for given parameter setting. Return original feature space.')
    else
        optind{curclass} = r.FullInd{curclass}( S{curclass} );
    end

    % Fit final model for this class on its selected features
    [~, optmodel{curclass}] = TRAINFUNC(Y{curclass}(:, optind{curclass}), label{curclass}, 1, Ps{curclass});
end

optfound = 1;
if VERBOSE, fprintf('\nDone. '); end
end % rfe_forward_multi_v2

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

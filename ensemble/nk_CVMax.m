function [opt_hE, opt_E, opt_F, opt_D] = nk_CVMax(E, L, EnsStrat)
% =========================================================================
% [opt_hE, opt_E, opt_F, opt_D] = nk_CVMax(E, L, EnsStrat)
% =========================================================================
% Greedy ensemble constructor that optimizes cross-validated performance
% subject to diversity and simple regularization.
%
% Two search modes are supported via EnsStrat.type:
%   • type==2 : Backward Elimination (RCE) – remove one learner per step
%   • type==6 : Forward Selection   (FCC) – add one learner per step
%
% INPUTS
% ------
% E        : [N × k] base-learner predictions (scores or hard labels).
% L        : [N × 1] labels. Classification: {-1,+1} (0 = ignore row).
%            Regression: real-valued targets.
% EnsStrat : struct with options (all optional unless noted):
%   .type            (2|6)  search mode (see above)
%   .CompFunc        'max' | 'min' (default 'max'; for regression metrics)
%   .Metric          2 => use sign(E) for diversity (NM convention)
%   .DiversitySource 'entropy' | 'kappaa' | 'kappaq' | 'kappaf' | 'lobag'
%                    | 'regvar'  (default 'entropy' for classification,
%                                 'regvar' for regression)
%   .EntropyWeight   weight in the perf/diversity rank sum (default 2.0)
%   .MinNum          minimal #selected learners (default 1)
%   .PerfSlackPct    ε-constraint on performance (as % of metric span)
%   .PerfIsLog       true if the perf metric is log-scaled
%   .SizePenalty     λ ≥ 0, penalizes larger sets
%   .LearnerCost     [1 × k] non-negative per-learner costs (default 1)
%   .Patience        non-improving steps before early stop (default 0)
%   .OptInlineFunc1  @(newPerf,curPerf,newDiv,curDiv) boolean gate
%   .OptInlineFunc2  @(origPerf,optPerf,origDiv,optDiv) reject-check
%   .isMulti         (internal; false here) set by caller when multi-class
%   .ECOC            (internal; struct with oECOC, Mode) if isMulti=true
%
% OUTPUTS
% -------
% opt_hE   : scalar performance (on the data passed to this function)
% opt_E    : [N × m] predictions of the selected ensemble (m ≤ k)
% opt_F    : [1 × m] column indices of selected base learners
% opt_D    : scalar diversity/ambiguity score of the selected set
%            • 'entropy':     vote-entropy in [0,1] (higher better)
%            • 'kappaa':      1−A (double-fault) in [0,1] (higher better)
%            • 'kappaq':      (1−Q)/2 in [0,1] (higher better)
%            • 'kappaf':      (1−κ)/2 in [0,1] (higher better)
%            • 'lobag':       mapped from ED ∈ [−1,2] to [0,1]
%            • 'regvar':      regression ambiguity (higher better)
%
% NOTES
% -----
% • Diversity is computed on hard labels if EnsStrat.Metric==2 (T=sign(E)).
% • Candidate choice uses a weighted rank of performance and diversity
%   inside an ε-performance pool; accept decisions also use a size penalty.
% • If the optimized set is not better than the original (per OptInlineFunc2),
%   the function returns the full set.
%
% SEE ALSO
% --------
% nk_MultiCVMax, nk_Entropy, nk_Diversity, nk_DiversityKappa, nk_Lobag,
% nk_RegAmbig, nk_EnsPerf
% =========================================================================
% (c) Nikolaos Koutsouleris, 10/2025

global MODEFL VERBOSE SVM

% --- filter rows with labels ------------------------------------------------
% --- filter rows with labels (only for internal metrics/diversity) --------
E_full = E; 
L_full = L;

varflag = ~strcmpi(MODEFL,'classification');  % 0 => classification

if varflag
    % REGRESSION: keep zeros; only drop NaNs
    ind0 = ~isnan(L_full);
else
    % CLASSIFICATION: 0 means "ignore row" (NM convention) + drop NaNs
    ind0 = (L_full ~= 0) & ~isnan(L_full);
end

E = E_full(ind0,:);
L = L_full(ind0,:);
[N,k] = size(E);
if N==0 || k==0
    opt_hE = 0; 
    opt_E  = E_full;                 
    opt_F  = 1:size(E_full,2); 
    opt_D  = 0; 
    return;
end

% --- defaults ---------------------------------------------------------------
if ~isfield(EnsStrat,'MinNum')         || isempty(EnsStrat.MinNum),         EnsStrat.MinNum = 1; end
if ~isfield(EnsStrat,'CompFunc')       || isempty(EnsStrat.CompFunc),       EnsStrat.CompFunc = 'max'; end
if ~isfield(EnsStrat,'EntropyWeight')  || isempty(EnsStrat.EntropyWeight),  EnsStrat.EntropyWeight = 2.0; end
if ~isfield(EnsStrat,'DiversitySource')|| isempty(EnsStrat.DiversitySource),EnsStrat.DiversitySource = 'entropy'; end
% Regularizers / add-ons
if ~isfield(EnsStrat,'PerfSlackPct')   || isempty(EnsStrat.PerfSlackPct),   EnsStrat.PerfSlackPct = 0.0; end
if ~isfield(EnsStrat,'PerfIsLog')      || isempty(EnsStrat.PerfIsLog),      EnsStrat.PerfIsLog = false; end % reserved
if ~isfield(EnsStrat,'SizePenalty')    || isempty(EnsStrat.SizePenalty),    EnsStrat.SizePenalty = 0.0; end
if ~isfield(EnsStrat,'LearnerCost')    || isempty(EnsStrat.LearnerCost),    EnsStrat.LearnerCost = ones(1,k); end
if numel(EnsStrat.LearnerCost) < k, EnsStrat.LearnerCost = ones(1,k); end
if ~isfield(EnsStrat,'Patience')       || isempty(EnsStrat.Patience),       EnsStrat.Patience = 0; end

[yl, ~, ~] = nk_GetScaleYAxisLabel(SVM);   % yl = [min max] of active metric
span = yl(2) - yl(1);
slackAbs = max(0, EnsStrat.PerfSlackPct) * span;   % absolute slack in metric units

cmp = lower(EnsStrat.CompFunc);   % 'max' or 'min'

% Inline acceptance defaults (back-compat)
if ~isfield(EnsStrat,'OptInlineFunc1') || isempty(EnsStrat.OptInlineFunc1) || ...
   ~isfield(EnsStrat,'OptInlineFunc2') || isempty(EnsStrat.OptInlineFunc2)
    if strcmpi(EnsStrat.CompFunc,'max')
        EnsStrat.OptInlineFunc1 = @(Perf,PerfCrit,Entropy,EntropyCrit) ...
            (Perf >  PerfCrit) || (Perf == PerfCrit && Entropy > EntropyCrit);
        EnsStrat.OptInlineFunc2 = @(OrigPerf,OptPerf,OrigEntropy,OptEntropy) ...
            ~(OptPerf > OrigPerf || (OptPerf == OrigPerf && OptEntropy > OrigEntropy));
    else
        EnsStrat.OptInlineFunc1 = @(Perf,PerfCrit,Entropy,EntropyCrit) ...
            (Perf <  PerfCrit) || (Perf == PerfCrit && Entropy < EntropyCrit);
        EnsStrat.OptInlineFunc2 = @(OrigPerf,OptPerf,OrigEntropy,OptEntropy) ...
            ~(OptPerf < OrigPerf || (OptPerf == OrigPerf && OptEntropy < OrigEntropy));
    end
end

% --- classification vs regression mode -------------------------------------
varflag = ~strcmpi(MODEFL,'classification');  % 0 => classification

% predictions used for diversity (classification)
if isfield(EnsStrat,'Metric') && EnsStrat.Metric==2
    T = sign(E); T(T==0) = -1;         % NM convention
else
    T = E;
end

% --- helper: compute diversity metric --------------------------------------
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
            case 'regvar'     % regression ambiguity (var around ensemble)
                D = nk_RegAmbig(Psub, Lsub);
            otherwise
                D = nk_Entropy(Psub, [], [], []);
        end
    end

% --- helpers: perf slack mask & size penalty --------------------------------
    function mask = perf_slack_mask(vals)
        if isempty(vals), mask = false(size(vals)); return; end
        if strcmp(cmp,'max')
            bestv = max(vals);
            mask  = (vals >= bestv - slackAbs);
        else
            bestv = min(vals);
            mask  = (vals <= bestv + slackAbs);
        end
    end

    function pen = size_penalty(idx_subset)
        if isempty(idx_subset), pen = 0;
        else, pen = EnsStrat.SizePenalty * sum(EnsStrat.LearnerCost(idx_subset));
        end
    end

% --- baselines --------------------------------------------------------------
opt_hE = nk_EnsPerf(E, L);   orig_hE = opt_hE;

if ~varflag
   opt_D  = nm_diversity_score(T, L, EnsStrat.DiversitySource);
else
   opt_D  = nk_RegAmbig(E, L);
end

orig_D = opt_D;  orig_F = 1:k;

switch EnsStrat.ConstructMode
    % ----------------------- Backward elimination --------------------------
    case 1
        if ~varflag
            strhdr = 'Binary/Multiclass RCE => max(perf | diversity)';
        else
            strhdr = ['Regression RCE => ' EnsStrat.CompFunc ' (perf | variance)'];
        end

        I = orig_F; opt_I = I; iter=0; kcur = k;
        MaxParamRaw = orig_hE;            % unpenalized perf for reporting
        MaxAbParam  = orig_D;             % diversity/ambiguity
        if strcmp(cmp,'max'), MaxParamPen = MaxParamRaw - size_penalty(I);
        else,                 MaxParamPen = MaxParamRaw + size_penalty(I);
        end
        no_gain = 0;

        while kcur > EnsStrat.MinNum
            lD  = zeros(kcur,1);
            lhE = zeros(kcur,1);
            cand_sets = cell(kcur,1);

            for l = 1:kcur
                kI = I; kI(l) = []; cand_sets{l} = kI;
                lE = E(:,kI);

                % performance on the trial subset (raw)
                lhE(l) = nk_EnsPerf(lE, L);

                % diversity/ambiguity
                if ~varflag
                    lT = T(:,kI);
                    lD(l) = nm_diversity_score(lT, L, EnsStrat.DiversitySource);
                else
                    lD(l) = nk_RegAmbig(lE, L);
                end
            end

            % ε-constraint: restrict to perf within slack of step-best
            mask = perf_slack_mask(lhE);
            idxPool = find(mask);
            if isempty(idxPool), idxPool = 1:kcur; end % fallback to all

            % choose candidate: weighted rank (perf primary) inside the pool
            switch cmp
                case 'max', rP = tiedrank(-lhE(idxPool));
                case 'min', rP = tiedrank( lhE(idxPool));
            end
            rD = tiedrank(-lD(idxPool));
            rComb = rP + EnsStrat.EntropyWeight * rD;
            [~,iRel] = min(rComb);
            ind = idxPool(iRel);

            % candidate metrics
            kI         = cand_sets{ind};
            param_raw  = lhE(ind);
            abparam    = lD(ind);

            % penalized comparator for acceptance
            pen_cand   = size_penalty(kI);
            if strcmp(cmp,'max'), param_pen = param_raw - pen_cand;
            else,                 param_pen = param_raw + pen_cand;
            end

            % remove the chosen learner
            I(ind) = []; kcur = kcur - 1;

            % accept update? (penalized gate + user inline on raw)
            accepted = false;
            if ( (strcmp(cmp,'max') && param_pen > MaxParamPen) || ...
                 (strcmp(cmp,'min') && param_pen < MaxParamPen) )
                if EnsStrat.OptInlineFunc1(param_raw, MaxParamRaw, abparam, MaxAbParam)
                    iter        = iter + 1;
                    opt_I       = I;
                    MaxParamRaw = param_raw;
                    MaxAbParam  = abparam;
                    MaxParamPen = param_pen;
                    accepted    = true;
                end
            end

            % early stopping (patience)
            if EnsStrat.Patience > 0
                if accepted, no_gain = 0; else, no_gain = no_gain + 1; end
                if no_gain >= EnsStrat.Patience, break; end
            end
        end

    % ----------------------- Forward selection -----------------------------
    case 2
        if ~varflag
            strhdr = 'Binary/Multiclass FCC => max(perf | diversity)';
        else
            strhdr = ['Regression FCC => ' EnsStrat.CompFunc ' (perf | variance)'];
        end

        origI = 1:k; I = []; opt_I = I; iter=0; kleft = k;
        switch cmp
            case 'max', MaxParamRaw = -inf; MaxAbParam = -inf;
            case 'min', MaxParamRaw =  inf; MaxAbParam =  inf;
        end
        MaxParamPen = MaxParamRaw; % empty set penalty = 0
        no_gain = 0;

        while kleft > 0
            lD  = zeros(kleft,1);
            lhE = zeros(kleft,1);

            for l = 1:kleft
                kI = [I, origI(l)];
                lE = E(:,kI);

                % perf of trial subset (raw)
                lhE(l) = nk_EnsPerf(lE, L);

                % diversity of trial subset
                if ~varflag
                    lT = T(:,kI);
                    lD(l) = nm_diversity_score(lT, L, EnsStrat.DiversitySource);
                else
                    lD(l) = nk_RegAmbig(lE, L);
                end
            end

            % ε-constraint: restrict to perf within slack of step-best
            mask = perf_slack_mask(lhE);
            idxPool = find(mask);
            if isempty(idxPool), idxPool = 1:kleft; end

            % weighted rank within the pool
            switch cmp
                case 'max', rP = tiedrank(-lhE(idxPool));
                case 'min', rP = tiedrank( lhE(idxPool));
            end
            rD = tiedrank(-lD(idxPool));
            rComb = rP + EnsStrat.EntropyWeight * rD;
            [~,iRel] = min(rComb);
            indRel = idxPool(iRel);

            % proposed subset after adding chosen base learner
            ind      = indRel;
            kI       = [I, origI(ind)];
            param_raw= lhE(ind);
            abparam  = lD(ind);

            % penalized comparator for acceptance
            pen_cand = size_penalty(kI);
            if strcmp(cmp,'max')
                param_pen = param_raw - pen_cand;
                perf_within_slack = (param_raw >= MaxParamRaw - slackAbs);
                pen_improves      = (param_pen >  MaxParamPen);
            else
                param_pen = param_raw + pen_cand;
                perf_within_slack = (param_raw <= MaxParamRaw + slackAbs);
                pen_improves      = (param_pen <  MaxParamPen);
            end
            div_better = (abparam > MaxAbParam);        % strict diversity improvement
            
            % acceptance
            acceptA = pen_improves && EnsStrat.OptInlineFunc1(param_raw, MaxParamRaw, abparam, MaxAbParam);
            acceptB = perf_within_slack && div_better;
            acceptC = pen_improves && (abparam >= MaxAbParam);
            accepted = acceptA || acceptB || acceptC;
            
            if accepted
                I           = kI;                  % add learner
                MaxParamRaw = param_raw;           % update raw (for reporting)
                MaxAbParam  = max(MaxAbParam,abparam);
                MaxParamPen = param_pen;           % update penalized (for gating)
                opt_I       = I;
                iter        = iter + 1;
            end

            % remove explored candidate from pool
            origI(ind) = []; kleft = kleft - 1;

            % early stopping (patience)
            if EnsStrat.Patience > 0
                if accepted, no_gain = 0; else, no_gain = no_gain + 1; end
                if no_gain >= EnsStrat.Patience, break; end
            end
        end

    otherwise
        error('EnsStrat.type must be 2 (BE) or 6 (FS) for nk_CVMax.');
end

% --- finalize vs. original full set ---------------------------------------
if EnsStrat.OptInlineFunc2(opt_hE, MaxParamRaw, opt_D, MaxAbParam)
    rej_str = ' [ solution rejected ]';
    opt_E   = E; 
    opt_F   = 1:k; 
else
    rej_str = '';
    opt_hE  = MaxParamRaw;
    opt_D   = MaxAbParam;
    opt_E   = E(:, opt_I);
    opt_F   = opt_I;
end

if VERBOSE
   fprintf(['\n%s: %g iters\t' ...
            'Div(orig->final): %1.3f->%1.3f, ' ...
            'Perf (orig->final): %1.3f->%1.3f, ' ...
            '# Learners (orig->final): %d->%d%s'], ...
            strhdr, iter, orig_D, opt_D, nk_EnsPerf(E,L), opt_hE, k, numel(opt_F), rej_str);
end

end

function v = local_getf(S, fname, default)
%LOCAL_GETF  Safe struct field getter with default.
    if isstruct(S) && isfield(S, fname) && ~isempty(S.(fname))
        v = S.(fname);
    else
        v = default;
    end
end
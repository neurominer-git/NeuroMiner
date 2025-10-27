function [opt_hE, opt_E, opt_F, opt_Fcat, opt_D, opt_Pred] = nk_MultiCVMax(E, L, EnsStrat, C, G)
% =========================================================================
% [opt_hE, opt_E, opt_F, opt_Fcat, opt_D, opt_Pred] = ...
%                            nk_MultiCVMax(E, L, EnsStrat, C, G)
% =========================================================================
% Multi-class version of nk_CVMax. Optimizes cross-validated performance
% (via nk_MultiEnsPerf) while incorporating diversity and regularization.
%
% INPUTS
% ------
% E        : [N × n] concatenated dichotomizer predictions (per class group).
% L        : [N × 1] multi-class labels in {1..K} (0 rows ignored).
% EnsStrat : same core fields as nk_CVMax:
%   .type (2|6), .CompFunc, .Metric, .DiversitySource, .EntropyWeight,
%   .MinNum, .PerfSlackPct, .PerfIsLog, .SizePenalty, .LearnerCost, .Patience,
%   .OptInlineFunc1, .OptInlineFunc2
% C        : [1 × n] dichotomization vector (column→group index 1..K).
% G        : (optional) group info passed to nk_MultiEnsPerf.
%
% OUTPUTS
% -------
% opt_hE   : multi-class performance from nk_MultiEnsPerf
% opt_E    : [N × m] selected columns of E (across all groups)
% opt_F    : 1×K cell with logical masks per dichotomizer group
% opt_Fcat : [1 × m] flat list of selected column indices (cat of opt_F)
% opt_D    : mean diversity across groups (each in [0,1], higher better)
% opt_Pred : optional structure with predictions/probabilities from
%            nk_MultiEnsPerf for the selected ensemble
%
% NOTES
% -----
% • “Singleton dichotomizers” (groups with only one learner) are kept
%   fixed and excluded from optimization.
% • Diversity per group is computed on its own columns and then averaged.
% • Uses EnsStrat.Metric==2 → sign(E) before diversity, consistent with NM.
%
% SEE ALSO
% --------
% nk_CVMax, nk_MultiEnsPerf, nk_Entropy, nk_Diversity, nk_DiversityKappa, nk_Lobag
% =========================================================================
% (c) Nikolaos Koutsouleris, 10/2025

global VERBOSE SVM

% --- Filter ---------------------------------------------------------------
ind0 = (L ~= 0);
E    = E(ind0,:); 
L    = L(ind0);
if isempty(E)
    opt_hE=0; opt_E=E; opt_F=[]; opt_Fcat=[]; opt_D=0; opt_Pred=[];
    return
end
[~,d]   = size(E);
nclass  = max(C(:));

% --- Defaults -------------------------------------------------------------
if ~isfield(EnsStrat,'Metric')        || isempty(EnsStrat.Metric),        EnsStrat.Metric = 2; end
if ~isfield(EnsStrat,'MinNum')        || isempty(EnsStrat.MinNum),        EnsStrat.MinNum = 1; end
if ~isfield(EnsStrat,'CompFunc')      || isempty(EnsStrat.CompFunc),      EnsStrat.CompFunc = 'max'; end
if ~isfield(EnsStrat,'EntropyWeight') || isempty(EnsStrat.EntropyWeight), EnsStrat.EntropyWeight = 2.0; end
if ~isfield(EnsStrat,'DiversitySource')||isempty(EnsStrat.DiversitySource),EnsStrat.DiversitySource = 'entropy'; end
if ~isfield(EnsStrat,'PerfSlackPct')  || isempty(EnsStrat.PerfSlackPct),  EnsStrat.PerfSlackPct = 0.0; end
if ~isfield(EnsStrat,'PerfIsLog')     || isempty(EnsStrat.PerfIsLog),     EnsStrat.PerfIsLog = false; end
if ~isfield(EnsStrat,'SizePenalty')   || isempty(EnsStrat.SizePenalty),   EnsStrat.SizePenalty = 0.0; end
if ~isfield(EnsStrat,'LearnerCost')   || isempty(EnsStrat.LearnerCost),   EnsStrat.LearnerCost = ones(1,d); end
if numel(EnsStrat.LearnerCost) < d,   EnsStrat.LearnerCost = ones(1,d); end
if ~isfield(EnsStrat,'Patience')      || isempty(EnsStrat.Patience),      EnsStrat.Patience = 0; end

% --- Prepare sign(T) for classification -----------------------------------
if EnsStrat.Metric == 2
    T = sign(E); T(T==0) = -1;
else
    T = E; % assume labels
end

% --- Performance scale for PerfSlackPct -----------------------------------
[yl, ~, ~] = nk_GetScaleYAxisLabel(SVM);
span    = yl(2) - yl(1);
slackAbs= max(0, EnsStrat.PerfSlackPct) * span;

% --- Per-class counts and singleton protection ----------------------------
n_per_class = accumarray(C(:),1,[nclass 1]);
class_mins  = max(1, min(EnsStrat.MinNum, n_per_class));   % at least 1 per class
total_min   = sum(class_mins);

% --- Baselines -------------------------------------------------------------
[orig_hE, orig_Pred] = nk_MultiEnsPerf(E, T, L, C, G);
orig_D  = overall_diversity(T, L, C, EnsStrat.DiversitySource);
orig_I  = 1:d;

cmpMax  = strcmpi(EnsStrat.CompFunc,'max');

% --- Inline acceptance defaults (compat) ----------------------------------
if ~isfield(EnsStrat,'OptInlineFunc1') || isempty(EnsStrat.OptInlineFunc1) || ...
   ~isfield(EnsStrat,'OptInlineFunc2') || isempty(EnsStrat.OptInlineFunc2)
    if cmpMax
        EnsStrat.OptInlineFunc1 = @(Perf,PerfCrit,Div,DivCrit) ...
            (Perf >  PerfCrit) || (Perf == PerfCrit && Div > DivCrit);
        EnsStrat.OptInlineFunc2 = @(OrigPerf,OptPerf,OrigDiv,OptDiv) ...
            ~(OptPerf > OrigPerf || (OptPerf == OrigPerf && OptDiv > OrigDiv));
    else
        EnsStrat.OptInlineFunc1 = @(Perf,PerfCrit,Div,DivCrit) ...
            (Perf <  PerfCrit) || (Perf == PerfCrit && Div < DivCrit);
        EnsStrat.OptInlineFunc2 = @(OrigPerf,OptPerf,OrigDiv,OptDiv) ...
            ~(OptPerf < OrigPerf || (OptPerf == OrigPerf && OptDiv < OrigDiv));
    end
end

% --- Helpers --------------------------------------------------------------

    function mask = perf_slack_mask(vals)
        if isempty(vals), mask = false(size(vals)); return; end
        if EnsStrat.PerfIsLog && all(vals>0)
            v = log(vals);
            if cmpMax
                bestv = max(v);
                mask  = (v >= bestv - (slackAbs/max(vals))); % mild normalization
            else
                bestv = min(v);
                mask  = (v <= bestv + (slackAbs/max(vals)));
            end
        else
            if cmpMax
                bestv = max(vals);
                mask  = (vals >= bestv - slackAbs);
            else
                bestv = min(vals);
                mask  = (vals <= bestv + slackAbs);
            end
        end
    end

    function pen = size_penalty(idx_subset)
        if isempty(idx_subset), pen = 0;
        else, pen = EnsStrat.SizePenalty * sum(EnsStrat.LearnerCost(idx_subset));
        end
    end

% --- Optimize --------------------------------------------------------------
switch EnsStrat.ConstructMode
    case 1
        % ------------------------ Backward Elimination (RCE) -------------------
        strhdr = 'Multi-group RCE => max(perf | diversity)';
    
        I           = 1:d;              % active set (global column indices)
        k_class     = arrayfun(@(c) sum(C==c), 1:nclass)'; % per-class counts
        MaxParamRaw = orig_hE;          % best perf (raw) so far
        MaxDiv      = orig_D;           % best diversity so far
        MaxParamPen = MaxParamRaw - (cmpMax*1 - ~cmpMax*1)*size_penalty(I);
        opt_I       = I;
        iter        = 0;
        no_gain     = 0;
    
        while sum(k_class) > total_min
            % build all legal single-removal candidates across classes
            cand_idx  = [];  % index to remove (global)
            cand_perf = [];
            cand_div  = [];
            cand_sets = {};  % resulting I after removal
    
            for ccur = 1:nclass
                if k_class(ccur) <= class_mins(ccur), continue; end
                idxCur = find(C(I)==ccur); l = numel(idxCur);
                if l==0, continue; end
                for t = 1:l
                    kI   = I; kI(idxCur(t)) = [];
                    Etr  = E(:,kI); Ttr = T(:,kI); Ctr = C(:,kI);
                    [p,~] = nk_MultiEnsPerf(Etr, Ttr, L, Ctr, G);
                    dval  = overall_diversity(Ttr, L, Ctr, EnsStrat.DiversitySource);
    
                    cand_idx  = [cand_idx, I(idxCur(t))]; %#ok<AGROW>
                    cand_perf = [cand_perf, p];           %#ok<AGROW>
                    cand_div  = [cand_div, dval];         %#ok<AGROW>
                    cand_sets{end+1} = kI;                %#ok<AGROW>
                end
            end
            if isempty(cand_idx), break; end
    
            % ε-constraint on perf; pick by weighted rank inside the admissible pool
            pool = find(perf_slack_mask(cand_perf));
            if isempty(pool), pool = 1:numel(cand_idx); end
            rP   = tiedrank( cmpMax * -cand_perf(pool) + (~cmpMax) * cand_perf(pool) );
            rD   = tiedrank(-cand_div(pool)); % higher diversity → smaller rank
            rComb= rP + EnsStrat.EntropyWeight * rD;
            [~,iRel] = min(rComb);
            indRel   = pool(iRel);
    
            kI         = cand_sets{indRel};
            param_raw  = cand_perf(indRel);
            div_cand   = cand_div(indRel);
    
            % penalized acceptance
            pen_cand   = size_penalty(kI);
            if cmpMax
                param_pen = param_raw - pen_cand;
                pen_improves = (param_pen > MaxParamPen);
                within_slack = (param_raw >= MaxParamRaw - slackAbs);
            else
                param_pen = param_raw + pen_cand;
                pen_improves = (param_pen < MaxParamPen);
                within_slack = (param_raw <= MaxParamRaw + slackAbs);
            end
    
            % three gates (same spirit as nk_CVMax FS)
            acceptA = pen_improves && EnsStrat.OptInlineFunc1(param_raw, MaxParamRaw, div_cand, MaxDiv);
            acceptB = within_slack && (div_cand > MaxDiv);
            acceptC = pen_improves && (div_cand >= MaxDiv);
    
            accepted = acceptA || acceptB || acceptC;
            if ~accepted
                no_gain = no_gain + 1;
                if EnsStrat.Patience > 0 && no_gain >= EnsStrat.Patience, break; end
                % remove the chosen anyway (RCE) to continue exploring
                I = kI;
            else
                I           = kI;
                MaxParamRaw = param_raw;
                MaxDiv      = div_cand;
                MaxParamPen = param_pen;
                opt_I       = I;
                iter        = iter + 1;
                no_gain     = 0;
            end
    
            % update per-class counts
            k_class = arrayfun(@(c) sum(C(I)==c), 1:nclass)'; 
            if sum(k_class) <= total_min, break; end
        end

    case 2
        % ------------------------ Forward Construction (FCC) -------------------
        strhdr = 'Multi-group FCC => max(perf | diversity)';
    
        % seed: one per class (first in each class)
        Iseed = zeros(1,nclass);
        pool  = [];
        for ccur = 1:nclass
            idx = find(C==ccur);
            Iseed(ccur) = idx(1);
            pool = [pool, idx(2:end)]; %#ok<AGROW>
        end
        I = Iseed;
        [MaxParamRaw, ~] = nk_MultiEnsPerf(E(:,I), T(:,I), L, C(:,I), G);
        MaxDiv      = overall_diversity(T(:,I), L, C(:,I), EnsStrat.DiversitySource);
        MaxParamPen = MaxParamRaw - (cmpMax*1 - ~cmpMax*1)*size_penalty(I);
        opt_I       = I;
        iter        = numel(Iseed);
        no_gain     = 0;
    
        while ~isempty(pool)
            % evaluate all single additions
            cand_idx  = pool;
            cand_perf = zeros(1,numel(pool));
            cand_div  = zeros(1,numel(pool));
            for t = 1:numel(pool)
                kI   = [I, pool(t)];
                [p,~]= nk_MultiEnsPerf(E(:,kI), T(:,kI), L, C(:,kI), G);
                dval = overall_diversity(T(:,kI), L, C(:,kI), EnsStrat.DiversitySource);
                cand_perf(t) = p;
                cand_div(t)  = dval;
            end
    
            % ε-constraint on perf and weighted rank
            poolmask = perf_slack_mask(cand_perf);
            idxPool  = find(poolmask);
            if isempty(idxPool), idxPool = 1:numel(pool); end
            rP   = tiedrank( cmpMax * -cand_perf(idxPool) + (~cmpMax) * cand_perf(idxPool) );
            rD   = tiedrank(-cand_div(idxPool));
            rComb= rP + EnsStrat.EntropyWeight * rD;
            [~,iRel] = min(rComb);
            jRel     = idxPool(iRel);
    
            % propose
            ind_add    = cand_idx(jRel);
            kI         = [I, ind_add];
            param_raw  = cand_perf(jRel);
            div_cand   = cand_div(jRel);
    
            % penalized gate
            pen_cand   = size_penalty(kI);
            if cmpMax
                param_pen = param_raw - pen_cand;
                pen_improves = (param_pen > MaxParamPen);
                within_slack = (param_raw >= MaxParamRaw - slackAbs);
            else
                param_pen = param_raw + pen_cand;
                pen_improves = (param_pen < MaxParamPen);
                within_slack = (param_raw <= MaxParamRaw + slackAbs);
            end
            acceptA = pen_improves && EnsStrat.OptInlineFunc1(param_raw, MaxParamRaw, div_cand, MaxDiv);
            acceptB = within_slack && (div_cand > MaxDiv);
            acceptC = pen_improves && (div_cand >= MaxDiv);
            accepted = acceptA || acceptB || acceptC;
    
            % update state
            pool(pool==ind_add) = [];
            if accepted
                I           = kI;
                MaxParamRaw = param_raw;
                MaxDiv      = div_cand;
                MaxParamPen = param_pen;
                opt_I       = I;
                iter        = iter + 1;
                no_gain     = 0;
            else
                no_gain     = no_gain + 1;
                if EnsStrat.Patience > 0 && no_gain >= EnsStrat.Patience, break; end
            end
        end
end

% --- Finalize: full vs. selected (inline #2) ------------------------------
if EnsStrat.OptInlineFunc2(orig_hE, MaxParamRaw, orig_D, MaxDiv)
    % reject → keep full
    opt_E    = E(:,orig_I);
    opt_Fcat = orig_I;
    opt_D    = orig_D;
    opt_hE   = orig_hE;
    opt_Pred = orig_Pred;
else
    opt_E    = E(:,opt_I);
    opt_Fcat = opt_I;
    opt_D    = MaxDiv;
    [opt_hE, opt_Pred] = nk_MultiEnsPerf(opt_E, T(:,opt_I), L, C(:,opt_I), G);
end

% Build per-class logical masks (NM convention)
log_I = false(1,d); log_I(opt_Fcat) = true;
opt_F = cell(nclass,1);
for ccur = 1:nclass
    indCur = (C==ccur);
    opt_F{ccur} = log_I(indCur);
end

if VERBOSE
    fprintf(['\n%s: %g iters\t' ...
        'Div(orig->final): %1.3f->%1.3f, ' ...
        'Perf (orig->final): %1.3f->%1.3f, ' ...
        '# Learners (orig->final): %d->%d'], ...
        strhdr, iter, orig_D, opt_D, orig_hE, opt_hE, numel(orig_I), numel(opt_Fcat));
end

end

% ========================= Helper functions ===============================

function D = overall_diversity(T, L, C, src)
% Returns a scalar diversity in [0,1] (higher = better) for all sources.
switch lower(src)
    case 'lobag'
        % global LoBag over predicted class labels (see builder below)
        P = build_predicted_labels(T, C, L);
        D = -nk_LobagMulti_from_labels(P, L); % higher=better
        % normalize softly to [0,1] if you prefer; here we leave as-is.
    otherwise
        % mean over classes of per-class diversity in [0,1]
        D = max(0, min(1, class_diversity(T, L, C, src)));
end
end

function D = diversity_one_class(T, L, C, src, curclass)
% Class-conditional diversity, returns in [0,1] (higher=better).
idxC = (C==curclass);
Psub = T(:,idxC);   % N x n_c, entries in {-1,+1}
if isempty(Psub), D = 0; return; end
Lbin = ones(size(L)); Lbin(L~=curclass) = -1; % +1 for class, -1 otherwise

switch lower(src)
    case 'entropy'
        D = nk_Entropy(Psub, [-1 1], [], []); % already normalized
    case 'kappaa'
        [A,~] = nk_Diversity(Psub, Lbin, [], []); % A ∈ [0,1]
        D = 1 - A;
    case 'kappaq'
        [A,Q] = nk_Diversity(Psub, Lbin, [], []);
        if isfinite(Q)
            D = 0.5*(1 - max(-1, min(1, Q)));  % map [-1,1] → [0,1]
        elseif isfinite(A)
            D = max(0, min(1, 1 - A));
        else
            D = nk_Entropy(Psub, [-1 1], [], []);
        end
    case 'kappaf'
        D1mK = nk_DiversityKappa(Psub, Lbin, [], []);  % returns (1-κ)
        % map (1-κ) to [0,1] defensively (κ in [-1,1] → (1-κ) in [0,2])
        D = max(0, min(1, 0.5 * D1mK));
    otherwise
        D = nk_Entropy(Psub, [-1 1], [], []);
end
end

function P = build_predicted_labels(T, C, L)
% Build N x n hard label matrix for multi-class LoBag:
% column j belongs to class c = C(j); predict c if T(:,j)==+1, else "L".
N = size(T,1); n = size(T,2);
P = repmat(L,1,n);
for j=1:n
    cj = C(j);
    pos = (T(:,j) > 0);
    if any(pos), P(pos,j) = cj; end
end
end

function D = class_diversity(Psub, Lsub, Csub, src)
    % mean over present classes; each term in [0,1], higher=better
    classes_here = unique(Csub(:))';
    vals = zeros(numel(classes_here),1);
    for cc = 1:numel(classes_here)
        cur = classes_here(cc);
        vals(cc) = diversity_one_class(Psub, Lsub, Csub, src, cur);
    end
    D = mean(vals,'omitnan');
end
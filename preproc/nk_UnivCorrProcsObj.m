function [sY, IN] = nk_UnivCorrProcsObj( Y, IN )
% =========================================================================
% [sY, IN] = nk_UnivCorrProcsObj( Y, IN )
% Remove nuisance effects / harmonize features (PC / ComBat / DIR)
% =========================================================================
% DESCRIPTION
%   Wrapper that removes covariate effects from data Y using one of three
%   methods selected via IN.METHOD:
%     1 = Partial correlations / linear residualization
%     2 = ComBat (empirical Bayes harmonization, extended)
%     3 = Disparate Impact Remover (fairness-oriented feature repair)
%
%   Works on a matrix Y (n_samples x n_features) or a 1xK cell array of
%   matrices (e.g., per fold or split). When Y is a cell array, the function
%   iterates over cells and pulls the corresponding covariates/design from
%   IN.TrCovars / IN.TsCovars (and IN.TrMod / IN.TsMod for ComBat). If
%   IN.estimators (ComBat/DIR) or IN.beta (PC) are provided, they are used
%   to APPLY the previously learned correction; otherwise, they are FITTED.
%
% SYNTAX
%   % Single matrix:
%   [sY, IN] = nk_UnivCorrProcsObj(Y, IN);
%
%   % Cell array with train/test mapping:
%   %   - If IN.copy_ts is true, processing starts at cell 2 (cell 1 copied)
%   %   - Otherwise, all cells are processed
%   [sY, IN] = nk_UnivCorrProcsObj({Y1, Y2, ...}, IN);
%
% INPUTS
%   Y                 : (n x p) matrix OR 1xK cell array of (n_k x p_k) matrices.
%
%   IN                : Struct controlling the correction. Key fields:
%     METHOD          : 1=PC, 2=ComBat, 3=DIR. Default=1.
%
%     % --- Common fields ---
%     TrCovars        : Training covariate matrix or cell array (n x q) / {n_k x q}.
%     TsCovars        : Test covariate matrix or cell array (n x q) / {n_k x q}.
%                       (For ComBat, these are turned into TrMod/TsMod in
%                       nk_GenPreprocSequence, including labels + dummies.)
%     subgroup        : Logical index (n x 1) of samples to fit estimators on.
%                       Others are corrected using these estimates. Optional.
%     featind         : Logical or index vector selecting features to correct;
%                       defaults to all features.
%
%     % --- Partial correlations (METHOD=1) ---
%     G               : Covariate matrix actually used in the current call
%                       (set internally from Tr/TsCovars unless IN.beta exists).
%     nointercept     : If true, do NOT add intercept to G (default adds one).
%     beta            : Precomputed regression coefficients (size q[+1] x p);
%                       if provided, used to apply correction without refitting.
%     revertflag      : If true, RE-ADD (rather than remove) G*beta to Y.
%
%     % --- ComBat (METHOD=2) ---
%     G               : Batch indicator(s) used in the current call.
%                       If one-hot / multi-column, it is converted to a
%                       single batch label per sample.
%
%     TrMod, TsMod    : Additional design matrices for ComBat (n x q) / {n_k x q}.
%                       These are prepared in nk_GenPreprocSequence and may
%                       include:
%                         - prepended label column(s),
%                         - dummy-coded categorical covariates,
%                         - continuous / ordinal / binary covariates.
%
%     M               : Design matrix actually used in the current call
%                       (one of TrMod/TsMod depending on context).
%
%     keep_idx        : Indices (1..q) in M of covariate columns whose
%                       variance should be RETAINED (e.g. labels, biological
%                       covariates). Defined in pre-spline space.
%
%     remove_idx      : Indices (1..q) in M of covariate columns whose
%                       variance should be REMOVED (nuisance covariates).
%                       Also defined in pre-spline space. Disjoint from keep_idx.
%
%     covars_idx      : Indices (subset of 1..q) of covariate columns whose
%                       estimators (gamma/delta) may be dropped/retained at
%                       apply-time. Typically all non-label columns.
%
%     spline          : Optional struct specifying spline expansion of
%                       selected covariate columns in M, e.g.:
%                          spline.df_map(col) = df
%                       where 'col' is a pre-spline column index in M and
%                       df >= 2 is the spline degrees of freedom.
%
%     REFERENCE_LEVEL : Optional numeric batch label used as reference
%                       (reference-batch ComBat). If empty/absent, pooled
%                       target ComBat is used.
%
%     COVBAT_MODE     : 1 = Simple ComBat, 2 = ComBat + CovBat covariance
%                       alignment in PCA space.
%     COVBAT_K        : Optional integer; number of PCs to use in CovBat.
%     COVBAT_VAR      : Optional cumulative variance fraction (0..1) used
%                       to choose K when COVBAT_K is empty.
%
%     UNSEENBATCH_MODE  : Handling strategy for batches unseen at training:
%                           1 = 'EB'          (empirical Bayes, default)
%                           2 = 'no_shrink'   (MoM, more aggressive)
%                           3 = 'strong_shrink' (EB + extra shrinkage).
%     UNSEENBATCH_ALPHA : Extra shrinkage parameter (0..1) used in
%                         'strong_shrink' mode.
%
%     estimators      : Trained ComBat parameters; if absent, they are
%                       learned on the training data (optionally on a
%                       subgroup). If present, they may be updated in
%                       "apply" mode using combat_update_newbatch_auto to
%                       calibrate truly new batches.
%
%     % --- Disparate Impact Remover (METHOD=3) ---
%     G               : Sensitive attribute(s) used for repair.
%     LAMBDA          : Strength of correction in [0,1].
%     DISTYPE         : Distribution type / strategy for DIR implementation.
%     estimators      : Trained DIR distributions; learned if absent, reused
%                       if present.
%
%     % --- Cell-array control ---
%     copy_ts         : If true, start processing at cell 2 and copy cell 1.
%
% OUTPUTS
%   sY                : Corrected data with the same structure/shape as Y.
%   IN                : Updated struct. Contains fitted parameters:
%                       - METHOD=1: IN.beta (if fitted)
%                       - METHOD=2: IN.estimators (ComBat parameters)
%                       - METHOD=3: IN.estimators (DIR distributions)
%
% BEHAVIOR / DETAILS
%   • METHOD=1 (PC):
%       - Regresses Y on [intercept, G] unless IN.nointercept==true.
%       - If IN.subgroup is provided, betas are estimated on that subset only.
%       - Then Y(:,featind) := Y(:,featind) -/+ G*beta(:,featind)
%         depending on IN.revertflag.
%
%   • METHOD=2 (ComBat):
%       - Internally transposes data to p x n (features x samples).
%       - Coerces G to a single batch label per subject.
%       - If IN.estimators is missing:
%           • Fits ComBat on the training data (optionally restricted to
%             IN.subgroup), respecting:
%               · keep_idx / remove_idx,
%               · spline.df_map (continuous/ordinal covariates),
%               · REFERENCE_LEVEL,
%               · CovBat settings.
%       - If IN.estimators is present:
%           • Optionally updates them with combat_update_newbatch_auto to
%             calibrate unseen batches (using UNSEENBATCH_MODE/ALPHA).
%           • Applies harmonization via combat_new using the frozen (and
%             possibly updated) estimators and IN.covars_idx.
%
%   • METHOD=3 (DIR):
%       - If IN.estimators missing → learns repair maps from data (optionally
%         restricted to IN.subgroup).
%       - Otherwise applies pre-learned maps.
%       - Only features in IN.featind are modified.
%
% ERRORS
%   • Missing IN.G for any method.
%   • Invalid DIR strength (IN.LAMBDA ∉ [0,1]).
%   • For ComBat: size mismatch between IN.M / IN.TrMod / IN.TsMod and Y.
%
% NOTES
%   • For cell-array input, the function selects Tr/Ts covariates (and Tr/Ts
%     design for ComBat) per cell automatically based on whether estimators
%     (or betas) already exist.
%   • Covariate measurement scale (continuous / binary / ordinal / categorical),
%     dummy-coding and spline settings are configured upstream in
%     nk_UnivCorrProcs_config and nk_GenPreprocSequence; nk_UnivCorrProcsObj
%     assumes that IN.TrMod / IN.TsMod and the indices (keep_idx, remove_idx,
%     covars_idx) are already consistent.
%   • Feature masking via IN.featind is honored in all methods.
%
% SEE ALSO
%   combat_new, combat_update_newbatch_auto, RemoveDisparateImpact
%
% =========================================================================
% (c) Nikolaos Koutsouleris, 11/2025

method = @PartialCorrelationsObj; methodsel = 1;
if exist('IN','var') && ~isempty(IN) && isfield(IN,'METHOD') && IN.METHOD == 2
    method = @CombatObj; methodsel = 2;
elseif exist('IN','var') && ~isempty(IN) && isfield(IN,'METHOD') && IN.METHOD == 3
    method = @DIRObj; methodsel = 3;
end
if isfield(IN,'copy_ts') && IN.copy_ts
    str = 2; off = 1;
else
    str = 1; off = 0;
end
% =========================== WRAPPER FUNCTION ============================ 
if iscell(Y) && exist('IN','var') && ~isempty(IN)
    sY = cell(1,numel(Y));
    for i = str:numel(Y) + off
        switch methodsel 
            case 1
                if isfield(IN,'beta') && ~isempty(IN.beta)
                    IN.G = IN.TsCovars{i};
                else
                    IN.G = IN.TrCovars{i};
                end
            case 2
                if isfield(IN,'estimators') && ~isempty(IN.estimators)
                    IN.G = IN.TsCovars{i};
                    %Bug correction: IN.TsMod empty if no var. retain.
                    if ~isempty(IN.TsMod), IN.M = IN.TsMod{i}; end
                else
                    IN.G = IN.TrCovars{i};
                    if ~isempty(IN.TrMod),IN.M = IN.TrMod{i}; end
                end
            case 3
                if isfield(IN,'estimators') && ~isempty(IN.estimators)
                    IN.G = IN.TsCovars{i};

                else
                    IN.G = IN.TrCovars{i};
                end
        end
        [sY{i-off}, IN] = method (Y{i-off}, IN); 
    end
else
    switch methodsel 
        case 1
            if isfield(IN,'beta') && ~isempty(IN.beta)
                if iscell(IN.TsCovars)
                    IN.G = IN.TrCovars;
                else
                    IN.G = IN.TsCovars;
                end
            else
                IN.G = IN.TrCovars;
            end

        case 2
            if isfield(IN,'estimators') && ~isempty(IN.estimators)
                if iscell(IN.TsMod)
                    IN.G = IN.TrCovars;
                    IN.M = IN.TrMod;
                else
                    IN.G = IN.TsCovars;
                    IN.M = IN.TsMod;
                end
            else
                IN.G = IN.TrCovars;
                IN.M = IN.TrMod;
            end
        case 3
            if isfield(IN, 'estimators') && ~isempty(IN.estimators)
                IN.G = IN.TsCovars;
            else
                IN.G = IN.TrCovars;
            end
    end

    [ sY, IN ] = method( Y, IN );
end
% =========================================================================
function [Y, IN] = PartialCorrelationsObj( Y, IN )

if isempty(IN),eIN=true; else, eIN=false; end

if eIN|| ~isfield(IN,'G') || isempty(IN.G) 
    error('No covariates defined in parameter structure'), 
end

if eIN || (~isfield(IN,'nointercept') || isempty(IN.nointercept) || ~IN.nointercept ) 
     %Create intercept vecotr
    interceptflag = true;
    intercept = ones(size(IN.G,1),1);
    %Check if intercept is already included in matrix to avoid double
    %intercept removal
    if isfield(IN,'beta') && ~isempty(IN.beta)
        if size(IN.beta,1) == size(IN.G,2), interceptflag = false; end
    end
else
    interceptflag = false;
end

if interceptflag
    %fprintf(' ... adding intercept to covariate matrix')
    IN.G = [intercept IN.G];
end

if eIN || ~isfield(IN,'beta') || isempty(IN.beta) 
    if ~isfield(IN,'subgroup') || isempty(IN.subgroup)
        % Compute IN.beta from entire population
        IN.beta = pinv(IN.G) * Y; 
    else
        % Compute IN.beta from a subgroup of observations
        idxSubgroup = logical(IN.subgroup);
        IN.beta = pinv(IN.G(idxSubgroup,:)) * Y(idxSubgroup,:);
    end
end

if isfield(IN,'featind')
    featind = IN.featind;
else
    featind = true(1,size(Y,2));
end

if eIN || ~isfield(IN,'revertflag') || isempty(IN.revertflag) || ~IN.revertflag
    Y(:,featind) = Y(:,featind) - IN.G * IN.beta(:,featind);
else
    Y(:,featind) = Y(:,featind) + IN.G * IN.beta(:,featind);
    
end

% =========================================================================
function [ Y, IN ] = CombatObj( Y, IN )

if isempty(IN), eIN = true; else, eIN = false; end
if eIN || ~isfield(IN,'G') || isempty(IN.G)
    error('No covariates defined in parameter structure');
end

% ComBat expects: dat = p x n, batch = length n (prefer column), mod = n x q
Y = Y.';                              % now p x n
G = IN.G.';                           % make it n x ? for inspection

% Convert batch to a single numeric label per sample if it is one-hot (logical OR numeric)
if islogical(G) || (ismatrix(G) && size(G,1) > 1)
    [~, G] = max(G, [], 1);          % 1 x n numeric labels
    G = G(:);                        % n x 1
else
    G = G(:);                        % ensure column vector n x 1
end

% Covariates (already prepared in nk_GenPreprocSequence: label + dummies + others)
M = [];
if isfield(IN,'M'), M = IN.M; end
if ~isempty(M) && size(M,1) ~= size(Y,2)
    error('IN.M must have n rows matching the number of samples.');
end

% Feature mask
if isfield(IN,'featind') && ~isempty(IN.featind)
    featind = IN.featind;
else
    featind = true(1, size(Y, 1));
end

% ------------------------- TRAIN OPTIONS -------------------------
opts_train = struct();

% Reference batch
if isfield(IN,'REFERENCE_LEVEL')
    opts_train.reference_level = IN.REFERENCE_LEVEL; 
end

% CovBat settings
opts_train.useCovBat = isfield(IN,'COVBAT_MODE') && IN.COVBAT_MODE==2;
if opts_train.useCovBat
    if isfield(IN,'COVBAT_K'),   opts_train.K        = IN.COVBAT_K;   end
    if isfield(IN,'COVBAT_VAR'), opts_train.var_expl = IN.COVBAT_VAR; end
end

% Spline settings (df_map prepared in nk_GenPreprocSequence)
if isfield(IN,'spline') && ~isempty(IN.spline)
    opts_train.spline = IN.spline;
end

% keep/remove indices in MOD space (pre-spline); also prepared in nk_GenPreprocSequence
if isfield(IN,'keep_idx') && ~isempty(IN.keep_idx)
    opts_train.keep_idx = IN.keep_idx;
end
if isfield(IN,'remove_idx') && ~isempty(IN.remove_idx)
    opts_train.remove_idx = IN.remove_idx;
end

istrainmode = false;

% -------------------- TRAIN ESTIMATORS IF NEEDED -------------------------
if eIN || ~isfield(IN,'estimators') || isempty(IN.estimators)
    if ~isfield(IN,'subgroup') || isempty(IN.subgroup)
        % full sample
        [~, IN.estimators] = combat_new(Y(featind,:), G, M, [], opts_train);
    else
        % user-defined training subgroup
        idxSubgroup = logical(IN.subgroup);
        if ~isempty(M)
            [~, IN.estimators] = combat_new(Y(featind, idxSubgroup), ...
                                            G(idxSubgroup), ...
                                            M(idxSubgroup,:), [], opts_train);
        else
            [~, IN.estimators] = combat_new(Y(featind, idxSubgroup), ...
                                            G(idxSubgroup), [], [], opts_train);
        end
    end
    istrainmode = true;
end

% ----------------- UNSEEN-BATCH CALIBRATION (APPLY) ---------------
if ~istrainmode
    % Build options for combat_update_newbatch_auto
    opts_batch = struct();
    opts_batch.selector = struct('per_batch_frac', 1, 'min_per_batch', 5);
    
    % unseen-batch mode: EB / no-shrink / strong-shrink
    if isfield(IN,'UNSEENBATCH_MODE')
        switch IN.UNSEENBATCH_MODE
            case 1
                opts_batch.mode = 'eb';             % empirical Bayes (default)
            case 2
                opts_batch.mode = 'no_shrink';      % MoM, aggressive
            case 3
                opts_batch.mode = 'strong_shrink';  % EB + extra shrink
            otherwise
                opts_batch.mode = 'eb';
        end
    else
        opts_batch.mode = 'eb';
    end

    if isfield(IN,'UNSEENBATCH_ALPHA') && ~isempty(IN.UNSEENBATCH_ALPHA)
        opts_batch.strong_alpha = IN.UNSEENBATCH_ALPHA;
    end

    % Optional: pass strict_min if you want to override default (5)
    % opts_batch.strict_min = 5;

    IN.estimators = combat_update_newbatch_auto( ...
        Y(featind,:), ...  % p x n
        G.', ...           % 1 x n, helper reshapes internally
        M, ...
        IN.estimators, ...
        opts_batch);
end

% ---------------------- APPLY COMBAT (TEST) -----------------------
opts_apply = struct();
if isfield(IN,'covars_idx'),      opts_apply.covars_idx     = IN.covars_idx;      end
if isfield(IN,'REFERENCE_LEVEL'), opts_apply.reference_level = IN.REFERENCE_LEVEL; end
opts_apply.useCovBat = isfield(IN,'COVBAT_MODE') && IN.COVBAT_MODE==2;

try
    Y(featind,:) = combat_new(Y(featind,:), G, M, IN.estimators, opts_apply);
catch ME
    fprintf('\n[ComBat] Issue applying combat_new: %s\n', ME.message);
end

% restore original orientation (n x p)
Y = Y.';

% =========================================================================
%Function of disparate impact remover (DIR). 
function [Y, IN] = DIRObj(Y, IN)

%Check if covariates are defined. 
if isempty(IN),eIN=true; else, eIN=false; end

%Error handling. 
if eIN|| ~isfield(IN,'G') || isempty(IN.G) 
    error('No covariates defined in parameter structure')
elseif isempty(IN.G) || IN.LAMBDA > 1 || IN.LAMBDA < 0
    error('Strength of correction should be a numerical value between 0 and 1')
end

% Check if subsection of features. 
if isfield(IN,'featind')
    featind = IN.featind;
else
    featind = true(1, size(Y, 2));
end

% Check if subgroup.
if ~isfield(IN,'subgroup') || isempty(IN.subgroup)
    idxSubgroup = true(size(Y, 1), 1);
else
    idxSubgroup = logical(IN.subgroup);
end

% Correct data from scratch if training set and with precomputed distributions if test set.
if eIN || (~isfield(IN,'estimators') || isempty(IN.estimators))
    [Y(:, featind), IN.estimators] = RemoveDisparateImpact(Y(:, featind), IN.G, idxSubgroup, IN.LAMBDA, IN.DISTYPE);
else
    [Y(:, featind), ~] = RemoveDisparateImpact(Y(:, featind), IN.G, idxSubgroup, IN.LAMBDA, IN.DISTYPE, IN.estimators);
end

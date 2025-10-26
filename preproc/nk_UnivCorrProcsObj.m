function [sY, IN] = nk_UnivCorrProcsObj( Y, IN )
% =========================================================================
% [sY, IN] = nk_UnivCorrProcsObj( Y, IN )
% Remove nuisance effects / harmonize features (PC/ComBat/DIR)
% =========================================================================
% DESCRIPTION
%   Wrapper that removes covariate effects from data Y using one of three
%   methods selected via IN.METHOD:
%     1 = Partial correlations / linear residualization
%     2 = ComBat (empirical Bayes harmonization)
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
%     % --- Common fields ---
%     TrCovars        : Training covariate matrix or cell array (n x q) / {n_k x q}
%     TsCovars        : Test covariate matrix or cell array (n x q) / {n_k x q}
%     subgroup        : Logical index (n x 1) of samples to fit estimators on
%                       (others are corrected using these estimates). Optional.
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
%     G               : Batch indicator(s) used in the current call. If one-hot,
%                       it is converted to a single batch label per sample.
%     TrMod, TsMod    : Additional design matrix (M) for ComBat; train/test.
%     M               : Design matrix actually used in the current call.
%     estimators      : Trained ComBat parameters; if absent, they are learned.
%                       If present, function may update them to handle new batches.
%
%     % --- Disparate Impact Remover (METHOD=3) ---
%     G               : Sensitive attribute(s) used for repair.
%     LAMBDA          : Strength of correction in [0,1].
%     DISTYPE         : Distribution type / strategy for DIR implementation.
%     estimators      : Trained DIR distributions; learned if absent, reused if present.
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
%   • METHOD=1 (PC): Regress Y on [intercept, G] unless IN.nointercept==true.
%     If IN.subgroup is provided, betas are estimated on that subset only.
%     Then Y(:,featind) := Y(:,featind) -/+ G*beta(:,featind) per revertflag.
%
%   • METHOD=2 (ComBat): Expects data as p x n, so data are transposed
%     internally. Batch (G) is coerced to a single label per sample.
%     If IN.estimators missing → fit (optionally on IN.subgroup). Otherwise,
%     attempt new-batch auto-update and then apply harmonization.
%
%   • METHOD=3 (DIR): If IN.estimators missing → learn repair maps (optionally
%     on IN.subgroup). Otherwise, apply pre-learned maps. Only features in
%     IN.featind are modified.
%
% ERRORS
%   • Missing IN.G for any method.
%   • Invalid DIR strength (IN.LAMBDA ∉ [0,1]).
%   • For ComBat: size mismatch between IN.M and number of samples.
%
% NOTES
%   • For cell-array input, the function selects Tr/Ts covariates (and Tr/Ts
%     design for ComBat) per cell automatically based on whether estimators
%     (or betas) exist.
%   • Feature masking via IN.featind is honored in all methods.
%
% SEE ALSO
%   combat, combat_update_newbatch_auto, RemoveDisparateImpact
%
% =========================================================================
% (c) Nikolaos Koutsouleris, 09/2025

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

% Covariates
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

% Select reference level is user wants us to do so.
opts = struct();
if isfield(IN,'REFERENCE_LEVEL')
    opts.reference_level = IN.REFERENCE_LEVEL; 
end

opts.useCovBat = isfield(IN,'COVBAT_MODE') && IN.COVBAT_MODE==2;
if opts.useCovBat
    if isfield(IN,'COVBAT_K'), opts.K = IN.COVBAT_K; else, opts.K = []; end
    if isfield(IN,'COVBAT_VAR'), opts.var_expl = IN.COVBAT_VAR; else, opts.var_expl = 0.95; end
end
istrainmode = false;

% Train estimators if missing (on all data or subgroup)
if eIN || ~isfield(IN,'estimators') || isempty(IN.estimators)
    if ~isfield(IN,'subgroup') || isempty(IN.subgroup)
        [~, IN.estimators] = combat(Y(featind,:), G, M, [], opts);
    else
        idxSubgroup = logical(IN.subgroup);
        if ~isempty(M)
            [~, IN.estimators] = combat(Y(featind, idxSubgroup), G(idxSubgroup), M(idxSubgroup,:), [], opts);
        else
            [~, IN.estimators] = combat(Y(featind, idxSubgroup), G(idxSubgroup), [], [], opts);
        end
    end
    istrainmode = true;
end

% Only attempt new-batch calibration in "apply" mode
if ~istrainmode
    opts_batch = struct('selector', struct('per_batch_frac', 1, 'min_per_batch', 5));
    IN.estimators = combat_update_newbatch_auto( ...
        Y(featind,:), ...  % p x n
        G.', ...           % pass as 1 x n to match helper’s interface (it reshapes internally)
        M, ...
        IN.estimators, ...
        opts_batch);
end

% Apply ComBat using the (possibly updated) estimators
opts = struct();
if isfield(IN,'covars_idx'), opts.covars_idx = IN.covars_idx; end
if isfield(IN,'REFERENCE_LEVEL'), opts.reference_level = IN.REFERENCE_LEVEL; end
opts.useCovBat = isfield(IN,'COVBAT_MODE') && IN.COVBAT_MODE==2;
Y(featind,:) = combat(Y(featind,:), G, M, IN.estimators, opts);

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

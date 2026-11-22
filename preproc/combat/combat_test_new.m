function bayesdata = combat_test_new(dat, batch, mod, estimators, opts)
global VERBOSE
% This function takes the estimators from a training analysis and applies
% them to the test data. In the script above, the data is first
% standardized using a weighted grand mean of the data divided by a measure
% of variance. Coefficients are then generated to ultimately get the
% gamma_star and delta_star matrices that are used to correct the
% standardized data. The logic of this script was to use the grand mean,
% weights for the grand mean, variance, and the gamma/delta star from the
% training analysis and then apply them to the test data.

if nargin < 5, opts = struct(); end
if ~isfield(opts,'covars_idx') || isempty(opts.covars_idx)
    covars_idx = [];   % means "use all columns of mod"
else
    covars_idx = opts.covars_idx(:).';
end

if isfield(estimators,'spline') && ~isempty(estimators.spline)
    tmpopts = struct('spline',estimators.spline);
    if estimators.spline.hasLabel
        mod_label   = mod(:, 1);
        mod_other   = mod(:, setdiff(1:size(mod,2), 1));
        mod_other_exp = expand_splines(mod_other, tmpopts, estimators.spline);   
        mod = [mod_label, mod_other_exp];
    else
        mod = expand_splines(mod, tmpopts, estimators.spline);
    end
end

if isfield(estimators,'idx_map') && ~isempty(covars_idx)
    covars_idx = lift_idx(covars_idx, estimators.idx_map);
end

hasBatch = ~isfield(estimators,'no_batch') || ~estimators.no_batch;

if hasBatch

    % --- unpack training estimators
    levels     = estimators.levels;          % all batches (train + any new)
    n_array    = size(dat, 2);
    var_pooled = estimators.var_pooled;
    B_hat      = estimators.B_hat;           % rows: [batch_dummies_train ; covariates]
    grand_mean = estimators.grand_mean;
    gamma_star = estimators.gamma_star;      % one row per batch
    delta_star = estimators.delta_star;
    
    % total number of covariate columns used at training (expanded)
    if isfield(estimators,'q_mod') && ~isempty(estimators.q_mod)
        q_total = estimators.q_mod;
    else
        q_total = 0; % very old estimators (should not happen with the new pipeline)
    end
    
    % infer how many rows of B_hat correspond to *training* batch dummies
    n_batch_train = size(B_hat,1) - q_total;
    if n_batch_train < 0
        error('[combat] B_hat rows (%d) smaller than q_mod (%d).', size(B_hat,1), q_total);
    end
    
    % --- guard: unseen batch labels (must have been calibrated already)
    unknown_mask = ~ismember(batch, levels);
    if any(unknown_mask)
        unknowns = unique(batch(unknown_mask));
        error(['[combat] Unseen batch label(s) in test data: ', mat2str(unknowns), ...
               '. Calibrate them first and update "estimators".']);
    end
    
    % --- choose effective levels for design (pooled vs reference mode)
    if isfield(opts, 'reference_level') && ~isempty(opts.reference_level)
        % reference-batch mode: training dropped the reference column
        levels_eff = estimators.levels_no_ref(:)';   % non-reference levels only
        if VERBOSE
            fprintf('[combat] (reference mode) Found %d non-reference batches\n', numel(levels_eff));
        end
    else
        % pooled-target mode: indicators for all levels
        levels_eff = levels(:)';                     % all batch levels
        if VERBOSE
            fprintf('[combat] Found %d batches\n', numel(levels_eff));
        end
    end
    
    % --- build batch design for *all* batches we have gamma_star for ---
    n_batch  = numel(levels_eff);                    % total #batches (train + new)
    batchmod = zeros(n_array, n_batch);
    batches  = cell(1, n_batch);
    
    for i = 1:n_batch
        L = levels_eff(i);
        idx = (batch == L);
        batchmod(:, i) = idx;
        batches{i}     = find(idx);
    end
    
    % sanity: gamma_star rows should match number of modeled batches
    if size(gamma_star,1) ~= n_batch
        error('[combat] gamma_star rows (%d) do not match number of batches (%d).', ...
              size(gamma_star,1), n_batch);
    end
    
    % --- sizes per batch 
    n_batches = cellfun(@length, batches);
    
    % --- standardize using frozen training stats (use n_batch_train later) ---
    if VERBOSE
        fprintf('[combat] Standardizing the Data Based on Training Sample\n');
    end

    stand_mean = grand_mean' * ones(1, n_array);
    
    % Use only the selected covariate columns from 'mod' for add-back
    q_total = estimators.q_mod;

    if ~isempty(mod)
        use_none = (isscalar(covars_idx) && covars_idx == 0); % allow 0 => no covariates
        if use_none
            % do nothing: add-back only grand_mean, no covariates
            cov_block = [];
        elseif isempty(covars_idx)
           % default: use training keep set unless user overrides
            covars_idx_eff = estimators.cov_keep_idx;
            if size(mod,2) ~= q_total
                error('[combat] mod has %d columns at apply but training expected %d.', size(mod,2), q_total);
            end
            rows_in_B = n_batch_train + covars_idx_eff;
            cov_block = mod(:, covars_idx);
        else
            % Use only specified covariate columns
            if any(covars_idx < 1) || any(covars_idx > size(mod,2))
                error('[combat] opts.covars_idx out of range for mod (has %d columns).', size(mod,2));
            end
            covars_idx_eff = intersect(estimators.cov_keep_idx, covars_idx);
            rows_in_B = n_batch_train + covars_idx_eff; % rows of B_hat for chosen covariates
            cov_block = mod(:, covars_idx_eff);   % n_array x q_use
        end
        if ~isempty(cov_block)
            B_cov = B_hat(rows_in_B, :);      % q_use x p
            stand_mean = stand_mean + (cov_block * B_cov)';  % p x n_array
        end
    end
    
    s_data = dat - stand_mean;
    if ~isempty(estimators.cov_remove_idx)
        s_data = s_data - (mod(:,estimators.cov_remove_idx)*B_hat(n_batch_train+estimators.cov_remove_idx,:))';
    end
    s_data = s_data ./ (sqrt(var_pooled) * ones(1, n_array));
    
    % --- adjust per batch
    if VERBOSE, fprintf('[combat] Adjusting the data\n'); end
    bayesdata = s_data;
    j = 1;
    for i = 1:n_batch
        idx = batches{i};
        if isempty(idx), j = j + 1; continue; end
        bayesdata(:, idx) = (bayesdata(:, idx) - (batchmod(idx, :) * gamma_star)') ...
                            ./ (sqrt(delta_star(j, :))' * ones(1, n_batches(i)));
        j = j + 1;
    end
    
    % --- back-transform
    bayesdata = (bayesdata .* (sqrt(var_pooled) * ones(1, n_array))) + stand_mean;
    
    if isfield(opts,'useCovBat') && opts.useCovBat
         bayesdata = covbat_apply_addon(bayesdata, batch, estimators.covbat);
    end
else
    if VERBOSE, fprintf('[combat] Apply in no-batch mode.\n'); end
    
    q_total = estimators.q_mod;
    if size(mod,2) ~= q_total
        error('[combat] mod has %d columns at apply but training expected %d.', ...
              size(mod,2), q_total);
    end
    
    % --- interpret covars_idx (original coordinate system) ---
    use_none = (isscalar(covars_idx) && covars_idx == 0);
    
    if use_none
        % do not add back anything (pure nuisance removal)
        cov_keep_eff = [];
    elseif isempty(covars_idx)
        % default: use training keep set
        cov_keep_eff = estimators.cov_keep_idx;
    else
        % restrict training keep set to requested covariates
        cov_keep_eff = intersect(estimators.cov_keep_idx, covars_idx);
    end

    % --- determine which indices are allowed to be removed ---
    if isfield(opts,'hasLabel') && opts.hasLabel
        n_label = 1;
        removable = (n_label+1):q_total;
    else
        removable = 1:q_total;
    end

    % everything else is removed
    cov_remove_eff = setdiff(removable, cov_keep_eff);
    
    % --- build design blocks ---
    X_keep   = mod(:, cov_keep_eff);     % may be empty
    X_remove = mod(:, cov_remove_eff);
    
    % --- reconstruct signal ---
    Y_remove = (X_remove * estimators.B_remove)';  % p x n
    
    if isempty(X_keep)
        bayesdata = dat - Y_remove;
    else
        Y_keep = (X_keep * estimators.B_keep(cov_keep_eff, :))';
        bayesdata = dat - Y_remove + Y_keep;
    end
    
    % --- optional standardization ---
    if isfield(estimators,'mu_nb')
        mu = estimators.mu_nb;
        sd = estimators.sd_nb; sd(sd==0) = 1;
        bayesdata = (bayesdata - mu) ./ sd;
    end

end
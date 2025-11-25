function [estimators, used_idx] = combat_update_newbatch_auto(X_all, batch_all, mod_all, estimators, opts)
% Calibrate one or more UNSEEN batches by sampling a calibration subset.
% X_all    : p x n  (features x samples)
% batch_all: 1 x n or n x 1 numeric batch labels
% mod_all  : n x q  covariates aligned to columns of X_all (or [])
% estimators: struct from training (needs var_pooled, B_hat, grand_mean,
%             and EB priors: gamma_bar, t2, a_prior, b_prior)
%
% opts (optional struct):
%   .target_levels   : numeric vector of batch labels to calibrate. If omitted,
%                      auto-detect unseen labels in batch_all vs estimators.levels
%   .selector        : indices | logical mask | rules struct:
%                      rules = struct('per_batch_n',10 OR 'per_batch_frac',0.2,
%                                     'min_per_batch',5,'max_per_batch',Inf,'seed',[])
%   .strict_min      : minimum samples per new batch (default 5)
%
%   .mode            : 'eb' (default) | 'no_shrink' | 'strong_shrink'
%                      - 'eb'          : standard EB posterior for new batches
%                      - 'no_shrink'   : use MoM gamma_hat_new / delta_hat_new
%                      - 'strong_shrink': EB posterior, then extra shrink of
%                                         gamma_star_new toward training prior mean
%   .strong_shrink_alpha : in [0,1], strength of additional shrinkage (default 0.5)
%
% Returns:
%   estimators : updated with gamma_star/delta_star for new batches
%   used_idx   : logical 1 x n mask of calibration samples used

global VERBOSE

% --------- defaults / basic checks ----------
if nargin < 5 || isempty(opts), opts = struct(); end
if ~isfield(opts,'strict_min') || isempty(opts.strict_min), opts.strict_min = 5; end

% Mode handling
if ~isfield(opts,'mode') || isempty(opts.mode)
    mode = 'eb';
else
    mode = lower(opts.mode);
end
if ~ismember(mode, {'eb','no_shrink','strong_shrink'})
    error('combat_update_newbatch_auto: unknown mode "%s".', mode);
end
if ~isfield(opts,'strong_shrink_alpha') || isempty(opts.strong_shrink_alpha)
    opts.strong_shrink_alpha = 0.5;  % default extra shrink
end
alpha = opts.strong_shrink_alpha;

% --- detect CovBat state (optional) ---
useCovBat = isfield(estimators,'covbat') && ~isempty(estimators.covbat) ...
            && isfield(estimators.covbat,'U') && ~isempty(estimators.covbat.U);
if useCovBat
    Ccov = estimators.covbat;               % convenience handle
end

[~,n] = size(X_all);
batch_all = batch_all(:)';           % force 1 x n
if numel(batch_all) ~= n, error('batch_all length must equal size(X_all,2).'); end
if ~isempty(mod_all) && size(mod_all,1) ~= n
    error('mod_all must have n rows aligned to X_all columns.');
end
if ~isnumeric(batch_all)
    error('batch_all must be numeric labels (double).');
end

used_idx = false(1,n);

% --------- which batches to calibrate ----------
all_levels = unique(batch_all);
if isfield(opts,'target_levels') && ~isempty(opts.target_levels)
    new_levels = opts.target_levels(:)';
else
    new_levels = all_levels(~ismember(all_levels, estimators.levels));
end
if isempty(new_levels)
    if VERBOSE
        fprintf('[combat_update_newbatch_auto] No unseen batches to calibrate.\n');
    end
    return;
end

% --------- build selection mask ----------
sel_global = false(1,n);
if isfield(opts,'selector') && ~isempty(opts.selector)
    sel = opts.selector;
    if isnumeric(sel)
        sel = sel(:)';  assert(all(sel>=1 & sel<=n), 'selector indices out of range');
        sel_global(sel) = true;
    elseif islogical(sel) && numel(sel)==n
        sel_global = sel(:)';
    elseif isstruct(sel)
        rules = struct('per_batch_n',[], 'per_batch_frac',[], ...
                       'min_per_batch',5, 'max_per_batch',Inf, 'seed',[]);
        f = fieldnames(sel); 
        for k=1:numel(f), rules.(f{k}) = sel.(f{k}); end
        if ~isempty(rules.seed), rng(rules.seed); end
        for L = new_levels
            idx = find(batch_all==L);
            k = numel(idx);
            if isempty(rules.per_batch_n) && ~isempty(rules.per_batch_frac)
                take = max(rules.min_per_batch, ceil(rules.per_batch_frac * k));
            elseif ~isempty(rules.per_batch_n)
                take = rules.per_batch_n;
            else
                take = k;   % default: use all available
            end
            % hard clamps
            take = min(take, k);
            take = min(take, rules.max_per_batch);
            if take > 0
                perm = randperm(k, take);
                sel_global(idx(perm)) = true;
            end
        end
    else
        error('opts.selector must be indices, logical mask, or rules struct.');
    end
else
    % default: sample up to 10 per unseen batch, min strict_min
    for L = new_levels
        idx = find(batch_all==L); k = numel(idx);
        take = min(k, max(opts.strict_min, 10));
        if take>0, perm = randperm(k, take); sel_global(idx(perm)) = true; end
    end
end

% --------- expand mod_all like training, if needed ----------
if isfield(estimators,'spline') && ~isempty(estimators.spline) && ~isempty(mod_all)
    tmpopts = struct('spline', estimators.spline);
    [mod_all_exp, ~] = expand_splines(mod_all, tmpopts);
else
    mod_all_exp = mod_all;
end

% --------- calibrate each unseen batch ----------
for L = new_levels
    calib_idx = find((batch_all==L) & sel_global);
    if numel(calib_idx) < opts.strict_min
        error('Batch %g: only %d calibration sample(s). Need >= %d. Adjust selector/min.', ...
              L, numel(calib_idx), opts.strict_min);
    end
    used_idx(calib_idx) = true;

    % frozen training stats
    var_pooled = estimators.var_pooled;   % p x 1
    B_hat      = estimators.B_hat;        % (n_batch_train+q_total) x p
    grand_mean = estimators.grand_mean;   % 1 x p

    % --- determine which covariate columns to add back (expanded coords) ---
    if ~isempty(mod_all_exp)
        q_total = estimators.q_mod;
        if size(mod_all_exp,2) ~= q_total
            error('[combat_update_newbatch_auto] mod_all has %d columns but training expected %d (expanded).', ...
                  size(mod_all_exp,2), q_total);
        end

        if isfield(opts,'covars_idx') && ~isempty(opts.covars_idx)
            covars_idx = opts.covars_idx(:)';          % override
        else
            covars_idx = estimators.cov_keep_idx;      % default: training keep set
        end

        if any(covars_idx < 1) || any(covars_idx > q_total)
            error('[combat_update_newbatch_auto] covars_idx out of range for expanded mod_all.');
        end
    else
        covars_idx = [];
        q_total    = 0;
    end

    % infer training #batch dummy rows in B_hat
    n_batch_train = size(B_hat,1) - q_total;
    if n_batch_train < 0
        error('[combat_update_newbatch_auto] B_hat rows (%d) smaller than q_mod (%d).', ...
              size(B_hat,1), q_total);
    end

    % design for calibration: covariate add-back like in combat_test
    m = numel(calib_idx);

    stand_mean = grand_mean' * ones(1, m);      % p x m
    if ~isempty(covars_idx)
        cov_cal   = mod_all_exp(calib_idx, covars_idx);    % m x q_use
        rows_in_B = n_batch_train + covars_idx;            % rows in B_hat
        B_cov     = B_hat(rows_in_B, :);                   % q_use x p
        stand_mean = stand_mean + (cov_cal * B_cov)';      % p x m
    end

    s_data = (X_all(:,calib_idx) - stand_mean) ./ (sqrt(var_pooled) * ones(1,m)); % p x m

    % EB priors (pooled across training batches)
    gamma_bar_global = mean(estimators.gamma_bar);
    t2_global        = mean(estimators.t2);
    a_prior_global   = mean(estimators.a_prior);
    b_prior_global   = mean(estimators.b_prior);

    % MoM starts (row 1 x p)
    gamma_hat_new = mean(s_data, 2)'; 
    delta_hat_new = var(s_data, 0, 2)';

    % --------- posterior for this new batch, depending on mode ----------
    switch mode
        case 'no_shrink'
            % Use raw MoM estimates as the "posterior"
            gamma_star_new = gamma_hat_new;
            delta_star_new = delta_hat_new;

        otherwise  % 'eb' or 'strong_shrink'
            temp = itSol(s_data, gamma_hat_new, delta_hat_new, ...
                         gamma_bar_global, t2_global, a_prior_global, b_prior_global, 0.001);
            gamma_star_eb = temp(1,:);
            delta_star_eb = temp(2,:);

            if strcmp(mode, 'eb')
                gamma_star_new = gamma_star_eb;
                delta_star_new = delta_star_eb;
            else
                % 'strong_shrink': extra shrink of gamma toward prior mean
                gamma_prior_vec = gamma_bar_global * ones(1, numel(gamma_hat_new));
                gamma_star_new  = (1-alpha)*gamma_star_eb + alpha*gamma_prior_vec;
                delta_star_new  = delta_star_eb;   % keep EB variance
            end
    end

    % --------- append new batch parameters to estimators ----------
    estimators.levels(end+1,1) = L;
    if isfield(estimators,'levels_no_ref') && ~isempty(estimators.levels_no_ref) ...
            && ~ismember(L, estimators.levels_no_ref)
        estimators.levels_no_ref(end+1,1) = L;
    end

    % n_batch field is "logical" count of batches we have parameters for
    if isfield(estimators,'n_batch')
        estimators.n_batch = estimators.n_batch + 1;
    end

    estimators.gamma_star = [estimators.gamma_star; gamma_star_new];
    estimators.delta_star = [estimators.delta_star; delta_star_new];
    estimators.gamma_bar  = [estimators.gamma_bar, gamma_bar_global];
    estimators.t2         = [estimators.t2,        t2_global];
    estimators.a_prior    = [estimators.a_prior,   a_prior_global];
    estimators.b_prior    = [estimators.b_prior,   b_prior_global];

    % --- update CovBat per-batch moments for this new batch ---
    if useCovBat
        if VERBOSE, fprintf('[covbat] Updating PC moments for new batch %g.\n', L); end

        % Recreate ComBat-adjusted data for the calibration subset
        % using *updated* gamma_star/delta_star for this batch.
        % For this new batch, batch_design is a column of ones in s_data space:
        adj   = repmat(gamma_star_new, m, 1)';                     % p x m
        s_adj = (s_data - adj) ./ (sqrt(delta_star_new.').' * ones(1,m));  % p x m
        Yc_cal = (s_adj .* (sqrt(var_pooled) * ones(1,m))) + stand_mean;   % p x m

        % Project onto training PCs and compute this batch's PC-score moments
        Uk     = Ccov.U;                     % p x K
        mu_pca = Ccov.mu_pca;                % p x 1
        Tcal   = Uk' * (Yc_cal - mu_pca);    % K x m

        mu_b = mean(Tcal, 2)';               % 1 x K
        sd_b = std(Tcal, 0, 2)';             % 1 x K
        sd_b(sd_b==0) = eps;

        % Store into CovBat maps under numeric label L
        Ccov.pc_mu(L) = mu_b;
        Ccov.pc_sd(L) = sd_b;

        estimators.covbat = Ccov;
    end

end

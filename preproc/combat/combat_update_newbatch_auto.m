function [estimators, used_idx] = combat_update_newbatch_auto(X_all, batch_all, mod_all, estimators, opts)
% Calibrate one or more UNSEEN batches by sampling a calibration subset.
% X_all    : p x n  (features x samples)
% batch_all: 1 x n or n x 1 numeric batch labels
% mod_all  : n x q  covariates aligned to columns of X_all (or [])
% estimators: struct from training (needs var_pooled, B_hat, grand_mean,
%             and EB priors: gamma_bar, t2, a_prior, b_prior)
% opts (optional struct):
%   .target_levels   : numeric vector of batch labels to calibrate. If omitted,
%                      auto-detect unseen labels in batch_all vs estimators.levels
%   .selector        : indices | logical mask | rules struct:
%                      rules = struct('per_batch_n',10 OR 'per_batch_frac',0.2,
%                                     'min_per_batch',5,'max_per_batch',Inf,'seed',[])
%   .strict_min      : minimum samples per new batch (default 5)
%
% Returns:
%   estimators : updated with gamma_star/delta_star for new batches
%   used_idx   : logical 1 x n mask of calibration samples used

% --------- defaults / basic checks ----------
if nargin < 5 || isempty(opts), opts = struct(); end
if ~isfield(opts,'strict_min') || isempty(opts.strict_min), opts.strict_min = 5; end

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
        rules = struct('per_batch_n',[], 'per_batch_frac',[], 'min_per_batch',5, 'max_per_batch',Inf, 'seed',[]);
        f = fieldnames(sel); for k=1:numel(f), rules.(f{k}) = sel.(f{k}); end
        if ~isempty(rules.seed), rng(rules.seed); end
        for L = new_levels
            idx = find(batch_all==L);
            k = numel(idx);
            if isempty(rules.per_batch_n) && ~isempty(rules.per_batch_frac)
                take = max(rules.min_per_batch, ceil(rules.per_batch_frac * k));
            elseif ~isempty(rules.per_batch_n)
                take = rules.per_batch_n;
            else
                % default in deploy: use all; if you prefer the old heuristic, keep it
                take = k;
            end
            % hard clamps
            take = min(take, k);                     % <-- ensure take ≤ k
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
    % default: sample up to 10 per unseen batch, min 5
    for L = new_levels
        idx = find(batch_all==L); k = numel(idx);
        take = min(k, max(opts.strict_min, 10));
        if take>0, perm = randperm(k, take); sel_global(idx(perm)) = true; end
    end
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
    B_hat      = estimators.B_hat;        % (n_batch_train+q) x p
    grand_mean = estimators.grand_mean;   % 1 x p

    % design for calibration: [batch_dummy, covariates]
    m = numel(calib_idx);
    if isempty(mod_all)
        q = 0;
    else
        q = size(mod_all,2);
    end

    % standardize like combat_test (add back covariates only)
    stand_mean = grand_mean' * ones(1, m);      % p x m
    if q > 0
        cov_cal   = mod_all(calib_idx, :);   % m x q
        B_cov     = B_hat(end-q+1:end, :);   % q x p
        stand_mean = stand_mean + (cov_cal * B_cov)';   % p x m
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

    % posterior for this new batch
    temp = itSol(s_data, gamma_hat_new, delta_hat_new, ...
                 gamma_bar_global, t2_global, a_prior_global, b_prior_global, 0.001);

    gamma_star_new = temp(1,:);     % 1 x p
    delta_star_new = temp(2,:);     % 1 x p

    % append
    estimators.levels(end+1,1) = L;
    estimators.n_batch = estimators.n_batch + 1;
    estimators.gamma_star = [estimators.gamma_star; gamma_star_new];
    estimators.delta_star = [estimators.delta_star; delta_star_new];
    estimators.gamma_bar(end+1) = gamma_bar_global;
    estimators.t2(end+1)        = t2_global;
    estimators.a_prior(end+1)   = a_prior_global;
    estimators.b_prior(end+1)   = b_prior_global;

    if isfield(estimators,'reference_level') && ~isempty(estimators.reference_level)
        if isfield(estimators,'levels_no_ref')
            estimators.levels_no_ref(end+1,1) = L;
        end
    end

    % --- OPTIONAL: update CovBat per-batch moments for this new batch ---
    if useCovBat
        % 1) Recreate ComBat-adjusted data for the calibration subset
        %    using the *updated* (now includes this new batch) estimators.
        %    We already have stand_mean (p x m) and s_data (p x m) for calib_idx.
        %    For a single batch, batch_design is ones(m,1), so:
        adj = (ones(m,1) * gamma_star_new).';                     % p x m
        s_adj = (s_data - adj) ./ (sqrt(delta_star_new.').' * ones(1,m));  % p x m
        Yc_cal = (s_adj .* (sqrt(var_pooled) * ones(1,m))) + stand_mean;   % p x m

        % 2) Project onto training PCs and compute this batch's PC-score moments
        Uk     = Ccov.U;                     % p x K
        mu_pca = Ccov.mu_pca;                % p x 1
        Tcal   = Uk' * (Yc_cal - mu_pca);    % K x m

        mu_b = mean(Tcal, 2)';               % 1 x K
        sd_b = std(Tcal, 0, 2)';             % 1 x K
        sd_b(sd_b==0) = eps;

        % 3) Store into CovBat maps under the *numeric* batch label L
        %    (containers.Map with 'double' keys)
        Ccov.pc_mu(L) = mu_b;
        Ccov.pc_sd(L) = sd_b;

        % 4) Write back
        estimators.covbat = Ccov;
    end

end


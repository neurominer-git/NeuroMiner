function [bayesdata,estimators] = combat_new(dat, batch, mod, estimators, opts)
% This function was originally sent to Dom Dwyer from Russel Shinohara and
% is based on the following papers and the git repo below:
% Jean-Philippe Fortin, Drew Parker, Birkan Tunc, Takanori Watanabe, Mark A Elliott, Kosha Ruparel, David R Roalf, Theodore D Satterthwaite, Ruben C Gur, Raquel E Gur, Robert T Schultz, Ragini Verma, Russell T Shinohara. Harmonization Of Multi-Site Diffusion Tensor Imaging Data. NeuroImage, 161, 149-170, 2017
% Jean-Philippe Fortin, Nicholas Cullen, Yvette I. Sheline, Warren D. Taylor, Irem Aselcioglu, Philip A. Cook, Phil Adams, Crystal Cooper, Maurizio Fava, Patrick J. McGrath, Melvin McInnis, Mary L. Phillips, Madhukar H. Trivedi, Myrna M. Weissman, Russell T. Shinohara. Harmonization of cortical thickness measurements across scanners and sites. NeuroImage, 167, 104-120, 2018
% https://github.com/Jfortin1/ComBatHarmonization
%
% INPUTS
% dat        - (required) a data matrix (p x n) for which the p rows are features, and the n columns are participants. 
% batch      - (required) a numeric or character vector of length n indicating the site/scanner/study id.
% mod        - a (n x p) matrix containing the outcome of interest (e.g., illness) and other covariates that will not be removed (i.e., they will be statistically preserved). 
% estimators - stored parameters from a previous combat run used to apply to test data
%
% OUTPUTS
% bayesdata  - the corrected data matrix
% estimators - parameters used to correct data that can be applied to new data
%
% For directions on function use in the training case, see the README.md
% file that was produced by the developers. 
%
% The modification was to allow external validation on test data. I did
% this by creating an "estimators" structure that is output when the
% algorithm is run on the training data. This can then be entered as a
% field when the test data is run. 
%
% When running on training data, do not include the "estimators"
% variable and run with: 
% [bayesdata,estimators] = combat(dat, batch, mod)
%
% When running on test data, include the "estimators" field that comes from
% the training data: 
% [bayesdata] = combat(dat, batch, mod, estimators)
%
% This is the same logic as regression, so it means that if a test site is
% not included in the training sites then it won't work. 
%
% Original function: JP Fortin?, don't know when it was produced. Need to follow-up.  
% Edits: Dom edits to add external validation 1July2020.  
%        Nikos edits to add non-batch mode, variance removal, oocv
%        extension to work with unseen batches
%%
global VERBOSE

if nargin < 5, opts = struct(); end
if nargin < 4, estimators = []; end
if ~isfield(opts,'covars_idx'), opts.covars_idx = []; end
if ~isfield(opts,'reference_level'), opts.reference_level = []; end
if nargin < 2, if VERBOSE, fprintf('\nDefine batch variable or leave it empty for no-batch correction.'); end; return; end
if nargin < 3, if VERBOSE, fprintf('\nLeave mod empty if no mod exists.'); end; return; end    

% --- NO-BATCH MODE: if batch is empty or has a single unique value, bypass EB ---
hasBatch = ~isempty(batch) && ~isscalar(unique(batch(:)));
useCovBat = isfield(opts,'useCovBat') && opts.useCovBat;

if hasBatch
    if isempty(estimators)
        % Check data 
        [sds] = std(dat,0,2)';
        wh = sum(sds==0);
        if wh>0
            error('Error. There are rows with constant values across samples. Remove these rows and rerun ComBat.')
        end
    
        % --- build batch dummies (optionally drop a reference batch) ---
        % %% NEW: optional reference batch
        if exist('opts','var') && isstruct(opts) && isfield(opts,'reference_level')
            if VERBOSE, fprintf('\n[combat] Reference batch mode activated (reference level = %g).\n', opts.reference_level); end
            reference_level = opts.reference_level;   % e.g., a value from 'batch'
        else
            if VERBOSE, fprintf('\n'); end
            reference_level = []; % pooled target (default)
        end
    
        % Sorted unique numeric levels
        % batch : 1 x n_array (double labels, possibly non-contiguous)
        levels = unique(batch(:));              % K x 1 doubles (true labels)
        [~,~,batch_idx] = unique(batch(:));     % 1..K coding aligned to 'levels'
        n_batch_all = numel(levels);
        
        % --- handle pooled vs. reference mode ---
        if isempty(reference_level)             % POOLed target (no reference dropped)
            batch_keep_idx = 1:n_batch_all;     % which encoded levels to keep
            levels_no_ref = levels;             % (optional bookkeeping)
        else                                    % REFERENCE mode
            ref_pos = find(levels == reference_level, 1);
            if isempty(ref_pos)
                error('reference_level %g not found among training levels.', reference_level);
            end
            batch_keep_idx = setdiff(1:n_batch_all, ref_pos, 'stable');  % drop reference column
            levels_no_ref = levels(batch_keep_idx);
        end
        n_batch = numel(batch_keep_idx);
        
        % --- design dummies aligned with kept levels ---
        batchmod_full = dummyvar(batch_idx);    % n_array x n_batch_all
        batchmod      = batchmod_full(:, batch_keep_idx);
        
        % --- per-batch indices (this is what your loop needs) ---
        batches  = cell(1, n_batch);
        for i = 1:n_batch
            batches{i} = find(batch_idx == batch_keep_idx(i));   % << works for both modes
        end
    
        n_batches = cellfun(@length,batches);
        n_array = size(dat,2);

        % === Spline expansion (TRAIN) ===
        % Save original (conceptual) covariates for confounding check
        mod_orig = mod;   % n_array x q_orig  (before any spline expansion)

        % Expand 'mod' using opts.spline spec, and get original->expanded mapping
        if isfield(opts,'spline') && ~isempty(opts.spline)
            [mod, idx_map] = expand_splines(mod, opts);   % replaces 'mod'
        else
            % no expansion: build a trivial mapping 1:1
            idx_map = arrayfun(@(i){i}, 1:size(mod,2));
        end
        
        % Figure out which original covariates to keep/remove (user space = original mod)
        n_orig = numel(idx_map);
        if ~isfield(opts,'keep_idx') || isempty(opts.keep_idx)
            keep_orig = 1:n_orig;               % default: keep all covariates
        else
            keep_orig = opts.keep_idx(:).';
        end
        if ~isfield(opts,'remove_idx') || isempty(opts.remove_idx)
            remove_orig = setdiff(1:n_orig, keep_orig);
        else
            remove_orig = opts.remove_idx(:).';
        end
        if ~isempty(intersect(keep_orig, remove_orig))
            error('[combat] keep_idx and remove_idx overlap (original coordinates).');
        end
        
        % Lift original indices to expanded indices
        cov_keep_idx   = lift_idx(keep_orig,   idx_map);
        cov_remove_idx = lift_idx(remove_orig, idx_map);
        
        % (re)compute sizes after expansion
        q_mod = size(mod,2);

        % Creating design matrix and removing intercept:
        design = [batchmod mod];
        intercept = ones(1,n_array)';
        wh = cellfun(@(x) isequal(x,intercept),num2cell(design,1));
        design(:,wh==1)=[];
        n_covariates = size(design,2)-size(batchmod,2);

        % --- Build a conceptual design for confounding checks only ---
        design_check = [batchmod mod_orig];      % uses unexpanded covariates
        whc = cellfun(@(x) isequal(x,intercept), num2cell(design_check,1));
        design_check(:,whc==1) = [];

        if VERBOSE
            if ~n_covariates
                fprintf('[combat] No covariate variance adjustment.\n')
            else
                fprintf('[combat] Adjusting for %d covariate(s) of covariate level(s)\n',n_covariates)
            end
        end
        % Check if the design is confounded
        if rank(design_check)<size(design_check,2)
            nn = size(design_check,2);
            if nn==(n_batch+1)
                error('Error. The covariate is confounded with batch. Remove the covariate and rerun ComBat.')
            end
            if nn>(n_batch+1)
                temp = design(:,(n_batch+1):nn);
                if rank(temp) < size(temp,2)
                    error('Error. The covariates are confounded. Please remove one or more of the covariates so the design is not confounded.')
                else
                    error('Error. At least one covariate is confounded with batch. Please remove confounded covariates and rerun ComBat.')
                end
            end
        end
        if VERBOSE, fprintf('[combat] Standardizing data across features\n'); end
        %B_hat = inv(design'*design)*design'*dat';
        % inspect rank for info only
        r_design = rank(design);
        if r_design < size(design,2) && VERBOSE
            fprintf('[combat] Warning: design matrix rank-deficient (%d < %d). ', ...
                    r_design, size(design,2));
            fprintf('Proceeding with minimum-norm least-squares solution.\n');
        end
        
        % Use lsqminnorm if available (R2017b+), otherwise fall back to pinv
        if exist('lsqminnorm','file') == 2
            % lsqminnorm(A,B) solves min ||A*X - B|| with minimum-norm X even if A is rank-deficient
            B_hat = lsqminnorm(design, dat');    % size: n_design x p
        else
            % Generic fallback; minimum-norm LS via pseudoinverse
            B_hat = pinv(design) * dat';        % size: n_design x p
        end
    
        % --- standardization ---
        if isempty(reference_level)  % pooled target (original behavior)
            grand_mean = (n_batches/n_array)*B_hat(1:n_batch,:);
        else % reference target: baseline has no column ⇒ grand_mean from covariates only
            grand_mean = zeros(1, size(B_hat,2));    % batch baseline is implicit zero
        end
        var_pooled = ((dat-(design*B_hat)').^2)*repmat(1/n_array,n_array,1);
        
        % selective add-back: only kept covariates
        stand_mean = grand_mean' * ones(1, n_array);
        if q_mod > 0 && ~isempty(cov_keep_idx)
            tmp = zeros(size(design));
            tmp(:, n_batch + cov_keep_idx) = design(:, n_batch + cov_keep_idx);
            stand_mean = stand_mean + (tmp * B_hat)';  % add back kept covariates only
        end
        s_data = (dat-stand_mean)./(sqrt(var_pooled)*ones(1,n_array));

        % --- EB estimation (unchanged core) ---
        if VERBOSE, fprintf('[combat] Fitting L/S model and finding priors\n'); end
        batch_design = design(:,1:n_batch);
        %gamma_hat = inv(batch_design'*batch_design)*batch_design'*s_data';     % size: n_batch x p
        gamma_hat = batch_design \ s_data';
        delta_hat = [];
        for i=1:n_batch
            indices = batches{i};
            if isscalar(indices)
                error('Only one case found for subgroup %g. ComBat is not defined for 1-sample batches.', i)
            end
            delta_hat = [delta_hat; var(s_data(:,indices),0,2)'];  % size: n_batch x p
        end
        
        %Find parametric priors:
        gamma_bar = mean(gamma_hat,2)';
        t2 = var(gamma_hat,0,2)';
        delta_hat_cell = num2cell(delta_hat,2);
        a_prior=[]; b_prior=[];
        for i=1:n_batch
            a_prior=[a_prior aprior(delta_hat_cell{i})];
            b_prior=[b_prior bprior(delta_hat_cell{i})];
        end
        
        if VERBOSE, fprintf('[combat] Finding parametric adjustments\n'); end
        gamma_star=[]; delta_star=[];
        for i=1:n_batch
            indices = batches{i};
            temp = itSol(s_data(:,indices), gamma_hat(i,:), delta_hat(i,:), ...
                         gamma_bar(i), t2(i), a_prior(i), b_prior(i), 0.001);
            gamma_star = [gamma_star; temp(1,:)];
            delta_star = [delta_star; temp(2,:)];
        end
        
        if VERBOSE, fprintf('[combat] Adjusting the data\n'); end
        bayesdata = s_data;
        j = 1;
        for i=1:n_batch
            indices = batches{i};
            bayesdata(:,indices) = (bayesdata(:,indices)-(batch_design(indices,:)*gamma_star)')./(sqrt(delta_star(j,:))'*ones(1,n_batches(i)));
            j = j+1;
        end
        bayesdata = (bayesdata.*(sqrt(var_pooled)*ones(1,n_array))) + stand_mean;
        
        % --- SAVE ESTIMATORS (add priors & reference info) ---
        estimators.levels          = levels;           % original level list
        estimators.levels_no_ref   = levels_no_ref;    % levels actually modelled in batch_design
        estimators.reference_level = reference_level;  % [] when pooled
        estimators.n_batch         = n_batch;
        estimators.var_pooled      = var_pooled;
        estimators.B_hat           = B_hat;
        estimators.grand_mean      = grand_mean;
        estimators.gamma_star      = gamma_star;
        estimators.delta_star      = delta_star;
        % NEW: store EB priors so we can calibrate unseen batches later
        estimators.gamma_bar       = gamma_bar;
        estimators.t2              = t2;
        estimators.a_prior         = a_prior;
        estimators.b_prior         = b_prior; 
        % NEW: save covariate mappings for specific removal or keeping to use at apply time
        estimators.q_mod           = q_mod;
        estimators.cov_keep_idx    = cov_keep_idx;
        estimators.cov_remove_idx  = cov_remove_idx;
        % Save spline flags
        if isfield(opts,'spline') && ~isempty(opts.spline)
            estimators.spline = opts.spline;
        else
            estimators.spline = [];
        end
        estimators.idx_map = idx_map;  % optional
    
        if useCovBat
            estimators = covbat_train_addon( ...
                bayesdata, ...   % p x n ComBat-corrected data
                batch, ...       % 1 x n batch labels
                estimators, ...
                opts.K, ...      % optional: number of PCs to align
                opts.var_expl ); % optional: cumulative variance threshold
            bayesdata = covbat_apply_addon(bayesdata, batch, estimators.covbat);
        end
    
    else
        if isstruct(estimators) && ~isempty(estimators)
            bayesdata = combat_test(dat, batch, mod, estimators, opts);
            if useCovBat, bayesdata = covbat_apply_addon(bayesdata, batch, estimators.covbat); end
        else
            if VERBOSE, fprintf('Estimators is empty. Enter estimators structure or do not enter argument'); end
        end
    end
else
    if isempty(estimators)
        if VERBOSE, fprintf('[combat] No-batch mode: removing nuisance covariates, preserving kept covariates.\n'); end
        q_mod   = size(mod,2);
        if q_mod == 0
            bayesdata = dat;           % nothing to do
            estimators = struct('no_batch', true, 'q_mod', 0, 'keep_idx', [], 'remove_idx', []);
            return
        end
    
        % === Spline expansion (TRAIN) ===
        % Expand 'mod' using opts.spline spec, and get original->expanded mapping
        if isfield(opts,'spline') && ~isempty(opts.spline)
            [mod, idx_map] = expand_splines(mod, opts);   % replaces 'mod'
        else
            % no expansion: build a trivial mapping 1:1
            idx_map = arrayfun(@(i){i}, 1:size(mod,2));
        end
        
        % Figure out which original covariates to keep/remove (user space = original mod)
        n_orig = numel(idx_map);
        if ~isfield(opts,'keep_idx') || isempty(opts.keep_idx)
            keep_orig = 1:n_orig;               % default: keep all covariates
        else
            keep_orig = opts.keep_idx(:).';
        end
        if ~isfield(opts,'remove_idx') || isempty(opts.remove_idx)
            remove_orig = setdiff(1:n_orig, keep_orig);
        else
            remove_orig = opts.remove_idx(:).';
        end
        if ~isempty(intersect(keep_orig, remove_orig))
            error('[combat] keep_idx and remove_idx overlap (original coordinates).');
        end
        
        % Lift original indices to expanded indices
        cov_keep_idx   = lift_idx(keep_orig,   idx_map);
        cov_remove_idx = lift_idx(remove_orig, idx_map);
        
        % (re)compute sizes after expansion
        q_mod = size(mod,2);
    
        X_keep   = mod(:, cov_keep_idx);        % n x q_keep
        X_remove = mod(:, cov_remove_idx);      % n x q_remove
    
        % Fit per-feature linear model: [X_keep X_remove] → dat'
        X_all = [X_keep X_remove];
        
        % Optional: inspect rank for info only
        r_design = rank(X_all);
        if r_design < size(X_all,2) && VERBOSE
            fprintf('[combat] Warning: design matrix rank-deficient (%d < %d). ', ...
                    r_design, size(X_all,2));
            fprintf('Proceeding with minimum-norm least-squares solution.\n');
        end
        
        % Use lsqminnorm if available (R2017b+), otherwise fall back to pinv
        if exist('lsqminnorm','file') == 2
            % lsqminnorm(A,B) solves min ||A*X - B|| with minimum-norm X even if A is rank-deficient
            B_all = lsqminnorm(X_all, dat');    % size: n_design x p
        else
            % Generic fallback; minimum-norm LS via pseudoinverse
            B_all = pinv(X_all) * dat';        % size: n_design x p
        end

        % Predicted contributions
        B_keep   = B_all(1:size(X_keep,2),      :);
        B_remove = B_all(size(X_keep,2)+1:end,  :);
    
        Y_keep   = (X_keep   * B_keep)';    % p x n
        Y_remove = (X_remove * B_remove)';  % p x n
    
        % Remove nuisance, keep biology/labels
        bayesdata = dat - Y_remove + Y_keep;
    
        % Optional: variance standardization (off by default—toggle if you want)
        if isfield(opts,'zscore_no_batch') && opts.zscore_no_batch
            mu  = mean(bayesdata, 2);
            sd  = std(bayesdata, 0, 2); sd(sd==0) = 1;
            bayesdata = (bayesdata - mu) ./ sd;
            estimators.mu_nb = mu; estimators.sd_nb = sd;
        end
    
        % Save what we need to apply to test data
        estimators.no_batch         = true;
        estimators.q_mod            = q_mod;
        estimators.cov_keep_idx     = cov_keep_idx;
        estimators.cov_remove_idx   = cov_remove_idx;
        estimators.B_keep           = B_keep;
        estimators.B_remove         = B_remove;
        % after saving B_keep/B_remove etc.
        if isfield(opts,'spline') && ~isempty(opts.spline)
            estimators.spline = opts.spline;
        else
            estimators.spline = [];
        end
    
        % CovBat is undefined without batches; skip it silently
    else
        if isstruct(estimators) && ~isempty(estimators)
             bayesdata = combat_test(dat, batch, mod, estimators, opts);
        end
    end
end

function bayesdata = combat_test(dat, batch, mod, estimators, opts)
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
    tmpopts = struct('spline', estimators.spline);
    [mod, ~] = expand_splines(mod, tmpopts);
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
            covars_idx = estimators.cov_keep_idx;
            if size(mod,2) ~= q_total
                error('[combat] mod has %d columns at apply but training expected %d.', size(mod,2), q_total);
            end
            rows_in_B = n_batch_train + covars_idx;
            cov_block = mod(:, covars_idx);
        else
            % Use only specified covariate columns
            if any(covars_idx < 1) || any(covars_idx > size(mod,2))
                error('[combat] opts.covars_idx out of range for mod (has %d columns).', size(mod,2));
            end
            rows_in_B = n_batch_train + covars_idx; % rows of B_hat for chosen covariates
            cov_block = mod(:, covars_idx);   % n_array x q_use
        end
        if ~isempty(cov_block)
            B_cov = B_hat(rows_in_B, :);      % q_use x p
            stand_mean = stand_mean + (cov_block * B_cov)';  % p x n_array
        end
    end
    
    s_data = (dat - stand_mean) ./ (sqrt(var_pooled) * ones(1, n_array));
    
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
    % Rebuild X_keep/X_remove in the SAME order/encoding as training
    q_total = estimators.q_mod;
    if size(mod,2) ~= q_total
        error('[combat] mod has %d columns at apply but training expected %d.', size(mod,2), q_total);
    end
    cov_keep_idx   = estimators.cov_keep_idx;
    cov_remove_idx = estimators.cov_remove_idx;

    X_keep   = mod(:, cov_keep_idx);
    X_remove = mod(:, cov_remove_idx);

    Y_keep   = (X_keep   * estimators.B_keep)';    % p x n
    Y_remove = (X_remove * estimators.B_remove)';  % p x n
    bayesdata = dat - Y_remove + Y_keep;

    if isfield(estimators,'mu_nb')
        mu = estimators.mu_nb; sd = estimators.sd_nb; sd(sd==0) = 1;
        bayesdata = (bayesdata - mu) ./ sd;
    end
end
% _____________________________________________________________________________

function estimators = covbat_train_addon(Yc, batch, estimators, K, var_expl)
% Yc    : p x n  (ComBat-adjusted data)
% batch : 1 x n or n x 1 numeric batch labels
global VERBOSE
if nargin < 4, K = []; end
if nargin < 5 || isempty(var_expl), var_expl = 0.95; end

if VERBOSE, fprintf('[covbat] Estimating PCA model for covariance alignment...\n'); end

% Center features for PCA
mu_pca = mean(Yc, 2);
Y0     = Yc - mu_pca;

% Economy SVD
[U,S,~] = svd(Y0, 'econ');
eigvals = diag(S).^2;
Kmax    = size(U,2);

% Choose K
if isempty(K)
    if isfinite(var_expl) && var_expl > 0 && var_expl < 1
        c = cumsum(eigvals) / sum(eigvals);
        K = find(c >= var_expl, 1, 'first');
        if isempty(K), K = Kmax; end
    else
        K = min(50, Kmax);   % sensible default
    end
end
K = max(1, min(K, Kmax));    % clamp to [1..Kmax]

% Leading K loadings and scores
Uk = U(:,1:K);
T  = Uk' * Y0;                % K x n

% Pooled (target) moments across all subjects
mu_tgt = mean(T, 2)';         % 1 x K
sd_tgt = std(T, 0, 2)';       % 1 x K
sd_tgt(sd_tgt==0) = eps;

% Per-batch moments
bvec = batch(:)';                             % 1 x n
if numel(bvec) ~= size(Yc,2)
    error('[covbat] batch length (%d) does not match #samples (%d).', ...
          numel(bvec), size(Yc,2));
end
lvls       = unique(bvec);
pc_mu      = containers.Map('KeyType','double','ValueType','any');
pc_sd      = containers.Map('KeyType','double','ValueType','any');
n_in_batch = containers.Map('KeyType','double','ValueType','double');

for bb = lvls(:)'
    idx = (bvec == bb);
    n_b = sum(idx);
    n_in_batch(bb) = n_b;
    if n_b < 1
        pc_mu(bb) = mu_tgt;
        pc_sd(bb) = sd_tgt;
    else
        Tb  = T(:, idx);              % K x n_b
        mu_b = mean(Tb, 2)';          % 1 x K  (mean over subjects)
        sd_b = std(Tb, 0, 2)';        % 1 x K
        sd_b(sd_b==0) = eps;
        pc_mu(bb) = mu_b;
        pc_sd(bb) = sd_b;
    end
end

% Pack into estimators
estimators.covbat = struct( ...
    'U',          Uk, ...
    'mu_pca',     mu_pca, ...
    'K',          K, ...
    'mu_tgt',     mu_tgt, ...
    'sd_tgt',     sd_tgt, ...
    'pc_mu',      pc_mu, ...
    'pc_sd',      pc_sd, ...
    'n_in_batch', n_in_batch ...
);

% _____________________________________________________________________________

function Y_adj = covbat_apply_addon(Yc, batch, est)
global VERBOSE
if VERBOSE, fprintf('[covbat] Applying PCA model for covariance alignment...\n'); end

U      = est.U;           % p x K
mu_pca = est.mu_pca;      % p x 1
mu_tgt = est.mu_tgt;      % 1 x K
sd_tgt = est.sd_tgt;      % 1 x K

Y0  = Yc - mu_pca;        % p x n
T0  = U' * Y0;            % K x n  (keep ORIGINAL scores for residual)
T   = T0;                 % working copy to adjust

n = size(Yc,2);
for j = 1:n
    b = batch(j);
    if isKey(est.pc_mu,b)
        mu_b = est.pc_mu(b);
        sd_b = est.pc_sd(b);
    else
        % fallback: pooled targets if batch unseen
        mu_b = mu_tgt;
        sd_b = sd_tgt;
    end
    t = T(:,j)';    
    T(:,j) = ((t - mu_b) .* (sd_tgt ./ sd_b) + mu_tgt).';  % adjusted scores
end

% Reconstruct with adjusted scores, but preserve residual from ORIGINAL scores
Y_adj = mu_pca + U*T + (Y0 - U*T0);

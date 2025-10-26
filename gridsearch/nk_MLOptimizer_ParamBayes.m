% ====================================================================================
% [GD, MD, DISP] = nk_MLOptimizer_ParamBayes(GD, MD, DISP, Ps, Params_desc, ...
%                     mapY, algostr, f, d, npreml, nclass, batchflag, PsSel, combcell)
% ====================================================================================
% DESCRIPTION:
%   This function implements a Bayesian optimization procedure to search the 
%   hyperparameter space defined in Ps. For each label (in multi‐label mode),
%   an initial set of seed candidates is evaluated; then a Gaussian Process (GP)
%   surrogate is built on these evaluated candidates. The Expected Improvement (EI)
%   acquisition function is computed over the valid candidate space and the candidate
%   with the highest EI is chosen for evaluation. If a candidate’s preprocessing 
%   hyperparameter setting (the last npreml entries) changes, new preprocessed data 
%   are retrieved via nk_MLOptimizer_ExtractDimMat and new feature subsets are computed 
%   via nk_CreateSubSets.
%
%   The candidate’s performance is evaluated on the CV partitions using nk_CVPermFold,
%   and the results are passed to nk_GridSearchHelper (which updates GD and MD). The 
%   optimization direction is determined from nk_ReturnEvalOperator.
%
% INPUTS:
%   GD           : Results container.
%   MD           : Model container.
%   DISP         : Display structure for reporting progress.
%   Ps           : Cell array of parameter combinations (per binary predictor).
%   Params_desc  : Cell array of parameter descriptions (per binary predictor).
%   mapY         : Structure containing CV1 training/test data.
%   algostr      : String describing the ML algorithm.
%   f, d         : Current outer (CV2) permutation and fold.
%   npreml       : Number of preprocessing hyperparameters (at end of candidate).
%   nclass       : Number of binary classifiers/predictors.
%   ngroups      : Number of study groups.
%   batchflag    : Batch mode flag.
%   PsSel        : (Optional) Previously selected parameter nodes (restricts search).
%   combcell     : Flag indicating that Ps entries are stored as a cell array.
%
% OUTPUTS:
%   GD           : Updated results container.
%   MD           : Updated model container.
%   DISP         : Updated display structure.
%
% GLOBAL VARIABLES:
%   CV, MULTILABEL, CVPOS
% ====================================================================================
% (c) Nikolaos Koutsouleris, 05/2024

function [GD, MD, DISP] = nk_MLOptimizer_ParamBayes(GD, MD, DISP, Ps, Params_desc, mapY, algostr, f, d, npreml, nclass, ngroups, batchflag, PsSel, combcell)

global VERBOSE GRD SVM MULTILABEL CV CVPOS

% Set current CV partition.
CVPOS.CV2p = f;
CVPOS.CV2f = d;

% Number of candidate combinations.
nPs = size(Ps{1},1);
if npreml > -1
    if combcell
        pp = unique(cell2mat(Ps{1}(:, end-npreml:end)), 'rows', 'stable');
    else
        pp = unique(Ps{1}(:, end-npreml:end), 'rows', 'stable');
    end
end

% Determine evaluation operator and optimization direction.
[~, ~, ~, ~, ~, minmaxfl, evalop_str] = nk_ReturnEvalOperator(SVM.GridParam);
evalop = str2func(evalop_str);
if minmaxfl == 1
    dir = 1;  % Maximization (e.g., Balanced Accuracy)
else
    dir = -1; % Minimization (e.g., MAE)
end

nl = nk_GetLabelDim(MULTILABEL);

% Set Bayesian parameters.
num_seed = min(GRD.OptMode.Bayes.num_seed, nPs); % Number of initial seed evaluations.
max_iter_bayes = min(GRD.OptMode.Bayes.max_iter, nPs); % Maximum Bayesian iterations.
tElapsedSum = 0;
tic;
if nPs > 1
    fprintf('\n === Performing Bayesian hyperparameter optimization [%s] === \n', algostr);
else
    fprintf('\n');
end
if ~isfield(DISP,'vizHandles'), DISP.vizHandles = []; end
if ~isfield(DISP, 'visited'), DISP.visited = []; end

% Build numeric grid from Ps{1} for surrogate modeling.
if combcell
    idxCharCols = all(cellfun(@ischar, Ps{1}), 1);
    Xgrid = cell2mat(Ps{1}(:,~idxCharCols));
else
    Xgrid = Ps{1};
end

min_EI_threshold = 1e-4;  % minimum expected improvement required to continue
max_no_improve = min(GRD.OptMode.Bayes.max_iter_no_change, round(nPs/4)); % maximum iterations without significant improvement
no_improve_count = 0;     % counter for iterations with negligible improvement
    
% For each label:
for curlabel = 1:nl
    
    MULTILABEL.curdim = curlabel;
    if MULTILABEL.flag
        if nl > 1
            labelstr = sprintf('Label #%g: %s | ', MULTILABEL.sel(curlabel), MULTILABEL.desc{MULTILABEL.sel(curlabel)});
        else
            labelstr = sprintf('Label %s | ', MULTILABEL.desc{MULTILABEL.sel(curlabel)});
        end
    else
        labelstr = '';
    end
    
    % Caching
    idxPs = false(nPs,1);
    evaluated_idx = [];
    y = [];  % vector of observed costs

    % Restrict candidate selection based on PsSel.
    if ~exist('PsSel','var') || isempty(PsSel)
        PiSel = true(nPs, nclass);
    else
        PiSel = false(nPs, nclass);
        for curclass = 1:nclass
            PiSel(:,curclass) = PsSel{curclass}{curlabel}.SelNodes;
        end
    end
    
    valid_indices = find(all(PiSel,2));
    if isempty(valid_indices)
        error('No valid hyperparameter combinations found per PsSel restrictions.');
    end
    
    % ---- Initial Seeding (unique seeds, no stale cost) ----
    % pool of valid & not-yet-visited candidates
    seed_pool = valid_indices(~idxPs(valid_indices));
    num_seed_eff = min(num_seed, numel(seed_pool));
    if num_seed_eff == 0
        error('No available candidates for seeding.');
    end
    % draw without replacement
    seed_list = seed_pool(randperm(numel(seed_pool), num_seed_eff));
    
    for s = 1:num_seed_eff
        seed_idx = seed_list(s);
    
        % Prepare candidate parameters
        cPs = cell(nclass,1);
        for curclass = 1:nclass
            DISP.P{curclass} = Ps{curclass}(seed_idx,:);
            cPs{curclass} = nk_PrepMLParams(Ps{curclass}, Params_desc{curclass}, seed_idx);
        end
    
        % Preproc index
        if npreml > -1
            if combcell
                preproc = cell2mat(Ps{1}(seed_idx, end-npreml:end));
            else
                preproc = Ps{1}(seed_idx, end-npreml:end);
            end
            [~, preproc_index] = ismember(preproc, pp, 'rows');
        else
            preproc_index = 1;
        end
    
        % Evaluate
        mapYi = nk_MLOptimizer_ExtractDimMat(mapY, preproc_index, cPs);
        FilterSubsets = nk_CreateSubSets(mapYi);
        [CV1perf, CV2perf, models] = nk_CVPermFold(mapYi, nclass, ngroups, cPs, FilterSubsets, batchflag);
        
        % Progress / bookkeeping
        pltperc = s*100/num_seed_eff;
        DISP.pltperc = pltperc;
        tElapsed = toc; tElapsedSum = tElapsedSum + tElapsed;
        elaps = sprintf('\t%1.2f sec.', tElapsed);
        DISP.s = sprintf('%s | %s%s\nCV2 [ %g, %g ] => %4g/%4g seed iterations => %1.1f%% [Bayesian seeds]', ...
                elaps, labelstr, algostr, f, d , s, num_seed_eff, pltperc);
    
        [GD, MD, DISP] = nk_GridSearchHelper(GD, MD, DISP, seed_idx, nclass, ngroups, CV1perf, CV2perf, models);
        
        % Record result
        cost = GD.TR(seed_idx);           % scalar used by minimization/maximization logic
        evaluated_idx(end+1,1) = seed_idx;
        y(end+1,1) = cost;
        entry.index = seed_idx;
        entry.cost  = cost;
        entry.CV1   = GD.TR(seed_idx);
        entry.CV2   = GD.TS(seed_idx);
        DISP.visited = [DISP.visited; entry];
        idxPs(seed_idx) = true;

        % Create variate mask according to selected features
        GD = nk_GenVI(mapYi, GD, CV, f, d, nclass, seed_idx, curlabel);
        
    end

    % Set initial best candidate from seeds.
    if dir == 1
        [best_cost, best_pos] = max(y);
    else
        [best_cost, best_pos] = min(y);
    end
    best_index = evaluated_idx(best_pos);
    for curclass = 1:nclass
        DISP.P{curclass} = Ps{curclass}(best_index,:);
        best_cPs{curclass} = nk_PrepMLParams(Ps{curclass}, Params_desc{curclass}, best_index);
    end
    if npreml > -1
        if combcell
            preproc = cell2mat(Ps{1}(best_index, end-npreml:end));
        else
            preproc = Ps{1}(best_index, end-npreml:end);
        end
        [~, preproc_index] = ismember(preproc, pp, 'rows');
    else
        preproc_index = 1;
    end
    best_mapYi = nk_MLOptimizer_ExtractDimMat(mapY, preproc_index, best_cPs);
    best_FilterSubsets = nk_CreateSubSets(mapYi);

    % Bayesian Optimization Iterations.
    for iter = 1:max_iter_bayes

        notVisited = setdiff(valid_indices, evaluated_idx);
        if isempty(notVisited)
            fprintf('\nBayesian optimization: no remaining candidates to evaluate.\n');
            break;
        end

        % Fit GP surrogate on evaluated candidates.
        X = Xgrid(evaluated_idx,:);
        y_vec = y;
        gpModel = fitrgp(X, y_vec, 'BasisFunction','constant',...
                          'KernelFunction',GRD.OptMode.Bayes.kernel_function,...
                          'Standardize',true);
        % Compute Expected Improvement (EI) for each candidate in valid_indices.
        notVisited = setdiff(valid_indices, evaluated_idx);
        [mu, sigma] = predict(gpModel, Xgrid(notVisited,:));  % Vectorized prediction
        if any(sigma < 1e-6)
            sigma(sigma < 1e-6) = 1e-6;
        end

        improvement = (dir==1) * (mu - best_cost) + (dir==-1) * (best_cost - mu);
        Z = improvement ./ sigma;
        EI_vec = max(0, improvement) .* normcdf(Z) + sigma .* normpdf(Z);
        EI = zeros(nPs,1);
        EI(notVisited) = EI_vec;

         % Check if maximum EI is below threshold => abort.
        if max(EI) < min_EI_threshold
            fprintf('\nAborting Bayesian optimization: maximum EI (%.6f) below threshold.\n', max(EI));
            break;
        end
        
        [max_EI, next_idx] = max(EI);
        if max_EI == 0 || isempty(next_idx)
            next_idx = valid_indices(randi(numel(valid_indices)));
        end
        
        next_cPs = cell(nclass,1);
        for curclass = 1:nclass
            DISP.P{curclass} = Ps{curclass}(next_idx,:);
            next_cPs{curclass} = nk_PrepMLParams(Ps{curclass}, Params_desc{curclass}, next_idx);
        end

        if npreml > -1
            if combcell
                next_preproc = cell2mat(Ps{1}(next_idx, end-npreml:end));
            else
                next_preproc = Ps{1}(next_idx, end-npreml:end);
            end
            [~, next_preproc_index] = ismember(next_preproc, pp, 'rows');
        else
            next_preproc_index = 1;
        end
        mapY_next = nk_MLOptimizer_ExtractDimMat(mapY, next_preproc_index, next_cPs);
        FilterSubsets_next = nk_CreateSubSets(mapY_next);

        if ~idxPs(next_idx)
            [CV1perf_next, CV2perf_next, models_next] = nk_CVPermFold(mapY_next, nclass, ngroups, next_cPs, FilterSubsets_next, batchflag);
            pltperc = iter*100/max_iter_bayes;
            DISP.pltperc = pltperc;
            DISP.s = sprintf('%s | %s%s\nCV2 [ %g, %g ] => %4g/%4g optimization iterations => %1.1f%% [Bayesian optimization]', ...
                    elaps, labelstr, algostr, f, d , iter, max_iter_bayes, pltperc);
            [GD, MD, DISP] = nk_GridSearchHelper(GD, MD, DISP, next_idx, nclass, ngroups, CV1perf_next, CV2perf_next, models_next);
            if isfield(CV1perf,'detrend'), GD.Detrend{next_idx} = CV1perf.detrend; end
            GD = nk_GenVI(mapY_next, GD, CV, f, d, nclass, next_idx, curlabel);
            idxPs(next_idx) = true;
        end
        cost_next = GD.TR(next_idx);
        evaluated_idx(end+1,1) = next_idx;
        y(end+1,1) = cost_next;
        
        % (After evaluation) Compare with current best:
        if (dir == 1 && cost_next > best_cost) || (dir == -1 && cost_next < best_cost)
            best_cost = cost_next;
            best_index = next_idx;
            best_cPs = next_cPs;
            no_improve_count = 0;  % reset counter on improvement
        else
            no_improve_count = no_improve_count + 1;
        end
        
        % Abort if no significant improvement for many iterations.
        if no_improve_count >= max_no_improve
            fprintf('\nAborting Bayesian optimization: no significant improvement in %d iterations.\n', max_no_improve);
            break;
        end
        entry.index = next_idx;
        entry.cost = cost_next;
        entry.CV1 = GD.TR(next_idx);
        entry.CV2 = GD.TS(next_idx);
        DISP.visited = [DISP.visited; entry];

        if VERBOSE
            % Display visited indices analysis plots
            DISP.vizHandles = nk_VisVisitedIdx(DISP.vizHandles, DISP.visited , Ps{1}, Params_desc{1});
            % Update display message.
            currentHP = mat2str(Ps{1}(next_idx,:));
            bestHP = mat2str(Ps{1}(best_index,:));
            fprintf('\n%sBayes Iteration %g/%g, Current Perf = %1.4f, Best Perf = %1.4f\nCurrent HP: %s\nBest HP: %s',...
                labelstr, iter, max_iter_bayes, cost_next, best_cost, currentHP, bestHP);
        end
    end  
end

DISP.visited = [];
fprintf('\n'); fprintf('CV2 [%g, %g]: OPTIMIZATION COMPLETED IN %1.2f SEC\n', f, d, tElapsedSum);

end

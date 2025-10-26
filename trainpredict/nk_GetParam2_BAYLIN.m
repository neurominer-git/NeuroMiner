% ==========================================================================
% FORMAT [param, model] = nk_GetParam2_BAYESLIN(Y, label, ModelOnly, Param)
% ==========================================================================
% Bayesian linear models via scikit-learn (Python)
%   - Regression: BayesianRidge or ARDRegression
%   - Classification (binary): fit Bayesian regression to {0,1} labels and
%     use a sigmoid link to obtain probabilities.
%
% INPUTS
%   Y         : [N x p] features
%   label     : [N x 1] targets (regression) or class labels (classification)
%   ModelOnly : if 1, return only fitted model (no param struct)
%   Param     : hyperparam vector (see below)
%
% GLOBALS
%   MODEFL    : 'classification' or 'regression'
%   EVALFUNC  : function handle for evaluation (label, pred)
%
% Param mapping (both modes):
%   Param(1) = model type: 1 -> BayesianRidge, 2 -> ARDRegression
%   Param(2) = n_iter                (int, e.g., 300)
%   Param(3) = tol                   (double, e.g., 1e-3)
%   Param(4) = alpha_1               (double, Gamma prior on alpha)
%   Param(5) = alpha_2               (double)
%   Param(6) = lambda_1              (double, Gamma prior on lambda)
%   Param(7) = lambda_2              (double)
%   Param(8) = fit_intercept         (0/1)
%   Param(9) = compute_score         (0/1)
%   Param(10)= threshold_lambda (ARD only; e.g., 1e4). Ignored for BR.
%
% Notes:
% - Multiclass classification not implemented here (binary only).
% - For classification, labels in {-1,+1} are mapped to {0,1}.
% ==========================================================================
% (c) Nikolaos Koutsouleris, 10/2025

function [param, model] = nk_GetParam2_BAYLIN(Y, label, ModelOnly, Param)
global EVALFUNC MODEFL

param = [];

% ---- sanitize inputs
feat = double(Y);
lab  = double(label(:));

% ---- hyperparameters

mdltype   = Param{1};                  % 1=BayesianRidge, 2=ARDRegression
n_iter    = int64(Param{2});
tol       = double(Param{3});
alpha_1   = double(Param{4});
alpha_2   = double(Param{5});
lambda_1  = double(Param{6});
lambda_2  = double(Param{7});
fit_int   = logical(Param{8});
comp_sc   = logical(Param{9});
thresh_l  = double(Param{10});                % ARD only

% ---- build python model
switch MODEFL
    case 'classification'
        % Map labels to {0,1} if they are {-1,+1}
        u = unique(lab(~isnan(lab)));
        if numel(u) ~= 2
            error('BAYESLIN classification expects binary labels.');
        end
        % Ensure [0,1]
        if all(ismember(u, [-1, 1]))
            lab = lab == max(u);  % -1->0, +1->1
        elseif all(ismember(u, [0, 1]))
            % ok
        else
            % map to {0,1} using the order of unique values
            lab = lab == max(u);
        end

        switch mdltype 
            case 'BayesianRidge'
                % BayesianRidge
                model = py.sklearn.linear_model.BayesianRidge( ...
                    max_iter=n_iter, tol=tol, alpha_1=alpha_1, alpha_2=alpha_2, ...
                    lambda_1=lambda_1, lambda_2=lambda_2, ...
                    fit_intercept=fit_int, compute_score=comp_sc, copy_X=true);
            case 'ARDRegression'
                % ARDRegression
                model = py.sklearn.linear_model.ARDRegression( ...
                    max_iter=n_iter, tol=tol, alpha_1=alpha_1, alpha_2=alpha_2, ...
                    lambda_1=lambda_1, lambda_2=lambda_2, threshold_lambda=thresh_l, ...
                    fit_intercept=fit_int, compute_score=comp_sc, copy_X=true);
        end

    case 'regression'
        switch mdltype
            case 'BayesianRidge'
                model = py.sklearn.linear_model.BayesianRidge( ...
                    max_iter=n_iter, tol=tol, alpha_1=alpha_1, alpha_2=alpha_2, ...
                    lambda_1=lambda_1, lambda_2=lambda_2, ...
                    fit_intercept=fit_int, compute_score=comp_sc, copy_X=true);
            case 'ARDRegression'
                model = py.sklearn.linear_model.ARDRegression( ...
                    max_iter=n_iter, tol=tol, alpha_1=alpha_1, alpha_2=alpha_2, ...
                    lambda_1=lambda_1, lambda_2=lambda_2, threshold_lambda=thresh_l, ...
                    fit_intercept=fit_int, compute_score=comp_sc, copy_X=true);
        end

    otherwise
        error('MODEFL must be ''classification'' or ''regression''.');
end

% ---- fit (reshape like your template)
if size(feat,1) == 1 && size(feat,2) == 1
    model = model.fit(py.numpy.array(feat).reshape(int64(1), int64(1)), double(lab'));
elseif size(feat, 2) == 1
    model = model.fit(py.numpy.array(feat).reshape(int64(-1), int64(1)), double(lab'));
elseif size(feat, 1) == 1
    model = model.fit(py.numpy.array(feat).reshape(int64(1), int64(-1)), double(lab'));
else
    model = model.fit(double(feat), double(lab'));
end

% ---- return param if requested
if ~ModelOnly
    switch MODEFL
        case 'classification'
            % Linear predictor
            ylin = double(model.predict(double(Y)));
            % Map to probabilities with sigmoid
            p = 1 ./ (1 + exp(-ylin));
            % targets = probabilities; dec_values = linear scores
            param.target     = p(:);
            param.dec_values = ylin(:);
            % Use your eval function on probabilities (or scores if preferred)
            try
                param.val = EVALFUNC(label, param.target);
            catch
                param.val = EVALFUNC(label, param.dec_values);
            end

        case 'regression'
            yhat = double(model.predict(double(Y)));
            param.target     = yhat(:);
            param.dec_values = yhat(:);
            param.val        = EVALFUNC(label, param.dec_values);
    end
end

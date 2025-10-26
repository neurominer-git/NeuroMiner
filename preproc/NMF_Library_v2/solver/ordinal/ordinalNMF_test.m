function [Y, infos] = ordinalNMF_test(X, model, in_options)
% ORDINALNMF_TEST Apply a trained ordinalNMF model to new data.
%
%   [Y, infos] = ordinalNMF_test(X, model, in_options) computes the coefficient
%   matrix Y for test data X using a trained ordinalNMF model. The model is assumed
%   to have been obtained by factorizing an ordinal data matrix V as V ≈ W*H with
%   threshold parameters tau.
%
%   At test time, W (and tau, if applicable) are kept fixed and Y is updated to
%   maximize the log-likelihood under the cumulative logistic model:
%
%       P(X_ij = c) = sigma(tau_c - (W*Y)_ij) - sigma(tau_(c-1) - (W*Y)_ij),
%
%   where sigma(z)=1/(1+exp(-z)) and tau_0 = -Inf, tau_L = Inf.
%
%   Inputs:
%       X         : m x n_test ordinal test data matrix.
%       model     : struct from ordinalNMF with fields:
%                      model.W   : m x r basis matrix.
%                      model.tau : (L-1) x 1 threshold parameters (if L > 1).
%       in_options: (optional) struct with test-phase options. Supported fields:
%                     .iter    : maximum number of iterations (default: 100)
%                     .lrH     : learning rate for updating Y (default: 1e-3)
%                     .verbose : display progress flag (default: 1)
%
%   Outputs:
%       Y     : r x n_test coefficient matrix representing the new data.
%       infos : struct containing test-phase information:
%                   infos.numIter         - number of iterations performed.
%                   infos.finalLogLikelihood - final log-likelihood value.
%                   infos.tElapsed        - elapsed time in seconds.
%                   infos.logLikelihood   - log-likelihood history.
%

    tStart = tic;
    
    % Set default test-phase options.
    defaultOptions.iter = 100;
    defaultOptions.lrH = 1e-3;
    defaultOptions.verbose = 1;
    
    if nargin < 3 || isempty(in_options)
        in_options = struct();
    end
    options = mergeOptions(defaultOptions, in_options);
    
    % Extract trained parameters.
    if ~isfield(model, 'W')
        error('Model must contain field ''W''.');
    end
    W = model.W;
    if isfield(model, 'tau')
        tau = model.tau;
    else
        tau = [];
    end
    [m, r] = size(W);
    
    % Ensure X has correct dimensions.
    if size(X,1) ~= m
        if size(X,2) == m
            X = X';
        else
            error('Test data X must have %d rows.', m);
        end
    end
    [~, n_test] = size(X);
    
    % Initialize Y (the test coefficient matrix) with random positive values.
    Y = rand(r, n_test);
    
    % Define logistic function and its derivative.
    sigma = @(z) 1./(1 + exp(-z));
    sigma_deriv = @(z) sigma(z) .* (1 - sigma(z));
    
    % Determine number of ordinal levels.
    L = max(X(:));
    
    % Main iteration loop to update Y.
    logLikelihood = zeros(options.iter, 1);
    Z = W * Y;
    for iter = 1:options.iter
        dL_dZ = zeros(m, n_test);  % gradient with respect to Z = W*Y
        ll = 0;
        for c = 1:L
            idx = find(X == c);
            if isempty(idx)
                continue;
            end
            z_vals = Z(idx);
            if c == 1
                lower = -Inf;
                sigma_lower = zeros(size(z_vals));
                sigma_lower_deriv = zeros(size(z_vals));
            else
                if ~isempty(tau)
                    lower = tau(c-1);
                else
                    lower = c - 0.5;
                end
                sigma_lower = sigma(lower - z_vals);
                sigma_lower_deriv = sigma_deriv(lower - z_vals);
            end
            if c == L
                upper = Inf;
                sigma_upper = ones(size(z_vals));
                sigma_upper_deriv = zeros(size(z_vals));
            else
                if ~isempty(tau)
                    upper = tau(c);
                else
                    upper = c - 0.5 + 1;
                end
                sigma_upper = sigma(upper - z_vals);
                sigma_upper_deriv = sigma_deriv(upper - z_vals);
            end
            
            p = sigma_upper - sigma_lower;
            p(p < 1e-10) = 1e-10;
            ll = ll + sum(log(p));
            
            dL_dZ(idx) = dL_dZ(idx) - (sigma_upper_deriv - sigma_lower_deriv) ./ p;
        end
        
        logLikelihood(iter) = ll;
        
        % Compute gradient with respect to Y.
        dL_dY = W' * dL_dZ;
        
        % Update Y using gradient descent.
        Y = Y - options.lrH * dL_dY;
        Y = max(Y, 1e-16);
        
        % Update latent representation.
        Z = W * Y;
        
        if options.verbose && mod(iter,10)==0
            fprintf('Test Iteration %d, Log Likelihood: %f\n', iter, ll);
        end
    end
    
    tElapsed = toc(tStart);
    
    infos.numIter = options.iter;
    infos.finalLogLikelihood = logLikelihood(end);
    infos.tElapsed = tElapsed;
    infos.logLikelihood = logLikelihood;
end

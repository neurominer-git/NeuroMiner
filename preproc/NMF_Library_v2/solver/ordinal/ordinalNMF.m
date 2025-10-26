function [x, infos] = ordinalNMF(V, rank, in_options)
% ORDINALNMF Ordinal Nonnegative Matrix Factorization using a cumulative logistic model.
%
%   [x, infos] = ordinalNMF(V, rank, in_options) factorizes an ordinal data
%   matrix V (with values in {1,2,...,L}) into nonnegative factors W and H,
%   along with threshold parameters tau for a cumulative logistic model.
%
%   The model assumes that the probability of an observed ordinal value c is
%   given by:
%
%       P(V_ij = c) = sigma(tau_c - (W*H)_ij) - sigma(tau_(c-1) - (W*H)_ij),
%
%   where sigma(z) = 1/(1+exp(-z)) and we define tau_0 = -Inf and tau_L = Inf.
%
%   Inputs:
%       V         : m x n ordinal data matrix.
%       rank      : desired factorization rank.
%       in_options: (optional) struct with options. Supported fields:
%                     .iter    : number of iterations (default: 200)
%                     .lrW     : learning rate for W (default: 1e-3)
%                     .lrH     : learning rate for H (default: 1e-3)
%                     .lrTau   : learning rate for tau (default: 1e-3)
%                     .verbose : display progress flag (default: 1)
%
%   Outputs:
%       x       : struct containing the factorization results with fields:
%                    x.W   : m x rank nonnegative factor matrix.
%                    x.H   : rank x n nonnegative coefficient matrix.
%                    x.tau : (L-1) x 1 vector of threshold parameters (if L > 1).
%       infos   : struct containing log information:
%                    infos.logLikelihood : vector of log-likelihood values over iterations.
%                    infos.numIter       : number of iterations performed.
%                    infos.tElapsed      : elapsed time in seconds.
%

    % Set default options.
    defaultOptions.iter = 200;
    defaultOptions.lrW = 1e-3;
    defaultOptions.lrH = 1e-3;
    defaultOptions.lrTau = 1e-3;
    defaultOptions.verbose = 1;
    
    if nargin < 3
        in_options = struct();
    end
    options = mergeOptions(defaultOptions, in_options);
    
    % Data dimensions and number of ordinal levels.
    [m, n] = size(V);
    L = max(V(:));
    
    % Initialize factor matrices and thresholds.
    W = rand(m, rank);
    H = rand(rank, n);
    if L > 1
        tau = ((1:(L-1))' + 0.5);
    else
        tau = [];
    end
    
    % Preallocate log-likelihood history.
    logLikelihood = zeros(options.iter, 1);
    
    tStart = tic;
    % Main iteration loop.
    for iter = 1:options.iter
        % Compute the latent matrix.
        Y_latent = W * H;  % m x n
        
        % Initialize gradients and log-likelihood.
        dL_dY = zeros(m, n);
        dL_dtau = zeros(length(tau), 1);
        ll = 0;
        
        % Define logistic function and its derivative.
        sigma = @(z) 1./(1 + exp(-z));
        sigma_deriv = @(z) sigma(z) .* (1 - sigma(z));
        
        % Loop over each ordinal category.
        for c = 1:L
            % Find indices for category c.
            idx = find(V == c);
            if isempty(idx)
                continue;
            end
            y_vals = Y_latent(idx);
            
            % Lower threshold.
            if c == 1
                lower = -Inf;
                sigma_lower = zeros(size(y_vals));        % sigma(-Inf)=0
                sigma_lower_deriv = zeros(size(y_vals));    % derivative 0
            else
                lower = tau(c-1);
                sigma_lower = sigma(lower - y_vals);
                sigma_lower_deriv = sigma_deriv(lower - y_vals);
            end
            
            % Upper threshold.
            if c == L
                upper = Inf;
                sigma_upper = ones(size(y_vals));         % sigma(Inf)=1
                sigma_upper_deriv = zeros(size(y_vals));    % derivative 0
            else
                upper = tau(c);
                sigma_upper = sigma(upper - y_vals);
                sigma_upper_deriv = sigma_deriv(upper - y_vals);
            end
            
            % Compute probability and avoid numerical issues.
            p = sigma_upper - sigma_lower;
            p(p < 1e-10) = 1e-10;
            
            % Accumulate log-likelihood.
            ll = ll + sum(log(p));
            
            % Compute derivative with respect to the latent variable.
            dL_dY(idx) = dL_dY(idx) - (sigma_upper_deriv - sigma_lower_deriv) ./ p;
            
            % Compute derivatives with respect to thresholds.
            if c > 1
                dL_dtau(c-1) = dL_dtau(c-1) + sum(sigma_lower_deriv ./ p);
            end
            if c < L
                dL_dtau(c) = dL_dtau(c) - sum(sigma_upper_deriv ./ p);
            end
        end
        
        logLikelihood(iter) = ll;
        
        % Compute gradients for W and H.
        dL_dW = dL_dY * H';
        dL_dH = W' * dL_dY;
        
        % Update parameters via gradient descent.
        W = W - options.lrW * dL_dW;
        H = H - options.lrH * dL_dH;
        if ~isempty(tau)
            tau = tau - options.lrTau * dL_dtau;
            tau = sort(tau, 'ascend');
        end
        
        % Enforce nonnegativity.
        W(W < 0) = 0;
        H(H < 0) = 0;
        
        if options.verbose && mod(iter,10) == 0
            fprintf('Iteration %d, Log Likelihood: %f\n', iter, ll);
        end
    end
    tElapsed = toc(tStart);
    
    % Prepare output.
    x.W = W;
    x.H = H;
    if ~isempty(tau)
        x.tau = tau;
    end
    
    infos.logLikelihood = logLikelihood(1:iter);
    infos.numIter = iter;
    infos.tElapsed = tElapsed;
end

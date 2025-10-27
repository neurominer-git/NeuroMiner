function [Y, infos] = sparse_mu_nmf_test(X, model, in_options)
% SPARSE_MU_NMF_TEST Apply a trained sparse_mu_nmf model to new data.
%
%   [Y, infos] = sparse_mu_nmf_test(X, model, in_options) computes the new
%   coefficient matrix Y for test data X using the effective basis matrix from
%   a sparse_mu_nmf factorization. In training, the model solved
%
%       min ||V - W*H||_F^2 + lambda*sum(sum(H))
%
%   and produced x.W (an m x r effective basis) and x.H. At test time, with W fixed,
%   we solve for Y (of size r x n_test) in
%
%       min_{Y >= 0} ||X - W*Y||_F^2 + lambda*sum(sum(Y)).
%
%   The update rule is:
%
%       if metric_type is 'euc':
%           Y = Y .* ( (W' * X) ./ max((W' * W)*Y + lambda, myeps) );
%
%       if metric_type is 'kl-div':
%           Y = Y .* ( (W'*(X./(W*Y))) ./ max(W'*ones(m,n_test) + lambda, myeps) );
%
%   Inputs:
%       X         : (m x n_test) nonnegative test data matrix (each column is a sample).
%       model     : struct from sparse_mu_nmf training containing at least:
%                      model.W - (m x r) effective basis matrix.
%       in_options: (optional) struct with test-phase options. Supported fields:
%                     .iter        : maximum number of iterations (default: 200)
%                     .lambda      : sparsity parameter (default: taken from training, e.g., 0.1)
%                     .metric_type : 'euc' (default) or 'kl-div'
%                     .verbose     : display progress flag (default: 1)
%                     .myeps       : small constant to avoid division by zero (default: 1e-16)
%
%   Outputs:
%       Y     : (r x n_test) nonnegative coefficient matrix for the test data.
%       infos : struct containing test-phase information:
%                   .numIter       - number of iterations performed.
%                   .finalResidual - final reconstruction error, ||X - W*Y||_F.
%                   .tElapsed      - total elapsed time in seconds.
%

    tStart = tic;
    
    % Set default options.
    defaultOptions.iter = 200;
    defaultOptions.verbose = 1;
    defaultOptions.myeps = 1e-16;
    
    if nargin < 3 || isempty(in_options)
        in_options = struct();
    end
    options = mergeOptions(defaultOptions, in_options);
    
    % Use provided lambda, or set default if not provided.
    if ~isfield(options, 'lambda')
        options.lambda = 0.1;
    end
    
    % Use provided metric type or default to 'euc'
    if ~isfield(options, 'metric_type')
        options.metric_type = 'euc';
    end

    % Extract effective basis from the model.
    if ~isfield(model, 'W')
        error('Model must contain the field ''W'' (the effective basis matrix).');
    end
    W = model.W;
    [m, r] = size(W);
    
    % Ensure that X has m rows (features).
    if size(X,1) ~= m
        if size(X,2) == m
            X = X';
        else
            error('Test data X must have %d rows, but has %d.', m, size(X,1));
        end
    end
    [~, n_test] = size(X);
    
    % Initialize Y (coefficient matrix) with ones.
    Y = ones(r, n_test);
    
    % For KL-divergence, preallocate a ones matrix.
    if strcmp(options.metric_type, 'kl-div')
        Omn = ones(m, n_test);
    end
    
    % Iterative multiplicative update for Y.
    XfitPrevious = Inf;
    for iter = 1:options.iter
        switch lower(options.metric_type)
            case 'euc'
                numerator = W' * X;
                denominator = max((W' * W)*Y + options.lambda, options.myeps);
                Y = Y .* (numerator ./ denominator);
            case 'kl-div'
                numerator = W' * (X ./ (W * Y));
                denominator = max(W' * Omn + options.lambda, options.myeps);
                Y = Y .* (numerator ./ denominator);
            otherwise
                error('Unknown metric_type: %s', options.metric_type);
        end
        Y = max(Y, options.myeps);
        
        % Compute current reconstruction and check convergence.
        XfitThis = W * Y;
        fitRes = norm(XfitPrevious - XfitThis, 'fro');
        XfitPrevious = XfitThis;
        curRes = norm(X - XfitThis, 'fro');
        
        if options.verbose
            fprintf('Test Iteration %d, residual = %.4e\n', iter, curRes);
        end
        
        if fitRes < 1e-4 || iter == options.iter
            break;
        end
    end
    
    tElapsed = toc(tStart);
    
    infos.numIter = iter;
    infos.finalResidual = curRes;
    infos.tElapsed = tElapsed;
    
end

function [Y, infos] = dtpp_nmf_test(X, model, in_options)
%DTPP_NMF_TEST Apply a trained DTPP-NMF model to new data.
%
%   [Y, infos] = dtpp_nmf_test(X, model, in_options) computes the coefficient
%   matrix Y for test data X given a trained DTPP-NMF model. In training, the
%   data matrix V was factorized as
%
%       V ≈ W * S * H,
%
%   and the training function outputs the effective basis as x.W = W * S.
%   At test time we take the effective basis as
%
%       B = model.W,
%
%   and solve for Y (with Y ≥ 0) in
%
%       min_Y || X - B * Y ||_F^2.
%
%   This version uses the standard multiplicative update:
%
%       Y = Y .* ( (B' * X) ./ max( B' * B * Y, myeps ) );
%
%   which is more consistent with the projection step in test-phase NMF.
%
%   INPUTS:
%       X         : (m x n_test) nonnegative test data matrix, with each column
%                   representing a sample.
%       model     : struct from dtpp_nmf training containing at least:
%                       model.W  - (m x rank) effective basis matrix (W*S).
%       in_options: (optional) struct with test-phase options. Supported fields:
%                     .iter     : maximum number of iterations (default: 200)
%                     .dis      : display progress (default: 1)
%                     .residual : convergence tolerance (default: 1e-4)
%                     .myeps    : small constant to avoid division by zero (default: 1e-16)
%
%   OUTPUTS:
%       Y     : (rank x n_test) coefficient matrix representing the new data in
%               the learned feature space.
%       infos : struct containing test-phase information:
%                   .numIter       - number of iterations performed.
%                   .finalResidual - final reconstruction error, ||X - B*Y||_F.
%                   .tElapsed      - total elapsed time in seconds.
%
%   Example:
%       % Assume a model was trained using dtpp_nmf:
%       model = dtpp_nmf(V, rank, options);
%
%       % To compute the representation for new data X_new:
%       [Y_new, test_infos] = dtpp_nmf_test(X_new, model, test_options);
%
%   See also: dtpp_nmf, mergeOptions.
%

    tStart = tic;
    
    % Set default test-phase options.
    optionDefault.iter     = 200;
    optionDefault.dis      = 1;
    optionDefault.residual = 1e-4;
    optionDefault.myeps    = 1e-16;
    
    if ~exist('in_options','var') || isempty(in_options)
        in_options = struct();
    end
    options = mergeOptions(in_options, optionDefault);
    
    % Extract the effective basis.
    % The training function outputs x.W = W*S, so model.W is already the basis.
    if ~isfield(model, 'W')
        error('The model must contain the field "W" (the effective basis matrix).');
    end
    B = model.W;
    [m, r] = size(B);
    
    % Ensure X has the proper dimensions (m rows corresponding to features).
    if size(X,1) ~= m
        if size(X,2) == m
            X = X';
        else
            error('Test data X must have %d rows, but has %d.', m, size(X,1));
        end
    end
    [~, n_test] = size(X);
    
    % Initialize Y (coefficient matrix) as ones.
    Y = max(rand(r, n_test), options.myeps);
    
    % Iterative update for Y using standard MU update.
    XfitPrevious = Inf;
    for iter = 1:options.iter
        numerator = B' * X;          % size: (r x n_test)
        denominator = max(B' * B * Y, options.myeps);  % size: (r x n_test)
        % Update Y elementwise.
        Y = Y .* (numerator ./ denominator);
        Y = max(Y, options.myeps);
        
        % Compute reconstruction error.
        XfitThis = B * Y;
        fitRes = norm(XfitPrevious - XfitThis, 'fro');
        curRes = norm(X - XfitThis, 'fro');
        XfitPrevious = XfitThis;
        
        if options.dis
            fprintf('Iteration %d, residual = %.4e\n', iter, curRes);
        end
        
        if fitRes < options.residual || iter == options.iter
            break;
        end
    end
    
    tElapsed = toc(tStart);
    
    % Package output information.
    infos.numIter = iter;
    infos.finalResidual = curRes;
    infos.tElapsed = tElapsed;
end

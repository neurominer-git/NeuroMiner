function [Y, infos] = alternating_onmf_test(X, model, in_options)
%ALTERNATING_ONMF_TEST Apply a trained alternating ONMF model to new data.
%
%   [Y, infos] = alternating_onmf_test(X, model, in_options) computes the new
%   coefficient matrix Y for test data X using the trained basis matrix W from
%   an alternatingONMF factorization. In training, the data matrix V was
%   approximated by:
%
%       V ≈ W * H,
%
%   where H was computed via a nonnegative least squares (NNLS) procedure with a
%   row-orthogonality constraint (i.e., H*H' ≈ I). Given new data X (m x n_test),
%   the test-phase problem is:
%
%       min_{Y >= 0} || X - W * Y ||_F^2,
%
%   and we solve it using the same NNLS subroutine used in training.
%
%   INPUTS:
%       X         : (m x n_test) nonnegative test data matrix, where each column
%                   is a sample.
%       model     : struct containing the trained model from alternating_onmf, with
%                   at least the field:
%                       model.W - (m x rank) basis matrix.
%       in_options: (optional) struct with test-phase options. Supported fields:
%                     .iter  : maximum number of iterations (default: 1)
%                              (Typically, a single call to nnls_orth suffices.)
%                     .dis   : display progress (default: 0)
%
%   OUTPUTS:
%       Y     : (rank x n_test) coefficient matrix representing the test data in
%               the learned feature space.
%       infos : struct containing test-phase information:
%                   .tElapsed - total elapsed time (in seconds).
%
%   Example:
%       % Suppose you trained a model using alternating_onmf:
%       model = alternating_onmf(V, rank, options);
%
%       % To compute the representation for new data X_new:
%       [Y_new, test_infos] = alternating_onmf_test(X_new, model, test_options);
%
%   See also: alternating_onmf, nnls_orth, mergeOptions.
%

    tStart = tic;
    
    % Set default test-phase options.
    optionDefault.iter = 1;  % Typically a single call is sufficient.
    optionDefault.dis  = 0;
    
    if ~exist('in_options','var') || isempty(in_options)
        in_options = struct();
    end
    options = mergeOptions(in_options, optionDefault);
    
    % Extract the trained basis matrix W.
    if isfield(model, 'W')
        W = model.W;
    else
        error('Model must contain the field ''W''.');
    end
    
    [m, rank] = size(W);
    [~, n_test] = size(X);
    
    % Normalize test data X: scale each column to have unit l2 norm.
    norm2x = sqrt(sum(X.^2, 1));
    Xn = X .* repmat(1./(norm2x+1e-16), m, 1);
    
    % Compute the coefficient matrix Y using the NNLS subroutine.
    % In training, H was computed as: H = nnls_orth(V, W, Vn).
    % Here we compute Y = nnls_orth(X, W, Xn).
    Y = nnls_orth(X, W, Xn);
    
    % Normalize rows of Y to enforce the orthogonality constraint (up to scaling).
    norm2y = sqrt(sum(Y'.^2, 1)) + 1e-16;
    Y = repmat(1./norm2y', 1, n_test) .* Y;
    
    tElapsed = toc(tStart);
    
    infos.tElapsed = tElapsed;
end

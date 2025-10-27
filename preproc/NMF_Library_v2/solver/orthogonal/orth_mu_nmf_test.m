function [Y, infos] = orth_mu_nmf_test(X, model, in_options)
%ORTH_MU_NMF_TEST Apply a trained orth_mu_nmf model to new data.
%
%   [Y, infos] = orth_mu_nmf_test(X, model, in_options) computes the coefficient
%   matrix Y for test data X using the trained basis matrix from orth_mu_nmf.
%
%   The training factorization was:
%
%       V ≈ W * H,
%
%   with options:
%       options.orth_w and options.orth_h to enforce orthogonality on W and H,
%       and options.norm_h to normalize H.
%
%   At test time, we use the effective basis stored in model.W.
%
%   Mapping strategy:
%      - If both orth_w and orth_h were active (or if in_options.useLSQ is true),
%        we map each test sample using NNLS:
%
%             y = lsqnonneg(W, x)
%
%        and then normalize y with normalize_H if norm_h is active.
%
%      - Otherwise, we use the standard multiplicative update:
%
%             Y = Y .* ( (W' * X) ./ max((W' * W)*Y, myeps) ).
%
%   INPUTS:
%       X         : (m x n_test) nonnegative test data matrix (each column is a sample).
%       model     : struct from orth_mu_nmf training containing at least:
%                       model.W : (m x r) basis matrix.
%       in_options: (optional) struct with test-phase options. Supported fields:
%                     .orth_w    : flag for enforcing W orthogonality (default: 0)
%                     .orth_h    : flag for enforcing H orthogonality (default: 1)
%                     .norm_h    : flag for normalizing the coefficient matrix (default: 1)
%                     .iter      : max iterations for MU update (default: 200)
%                     .residual  : convergence tolerance (default: 1e-4)
%                     .myeps     : small constant (default: 1e-16)
%                     .useLSQ    : if true, force NNLS mapping (default: automatic selection)
%
%   OUTPUTS:
%       Y     : (r x n_test) coefficient matrix for the new data.
%       infos : struct with fields:
%                   .method       - mapping method used ('NNLS' or 'MU')
%                   .numIter      - number of iterations (if MU mode, NaN for NNLS)
%                   .finalResidual- final reconstruction error, ||X - W*Y||_F.
%                   .tElapsed     - total elapsed time.
%
%   Example:
%       % Suppose you trained a model using orth_mu_nmf:
%       model = orth_mu_nmf(V, rank, options);
%
%       % To compute representation for new data X_new:
%       [Y_new, test_infos] = orth_mu_nmf_test(X_new, model, test_options);
%
%   See also: orth_mu_nmf, mergeOptions, lsqnonneg, normalize_H.
%

    tStart = tic;
    
    % Default options.
    optionDefault.orth_w   = 0;
    optionDefault.orth_h   = 1;
    optionDefault.norm_h   = 1;
    optionDefault.iter     = 200;
    optionDefault.residual = 1e-4;
    optionDefault.myeps    = 1e-16;
    optionDefault.useLSQ   = []; % if empty, decide automatically
    
    if nargin < 3 || isempty(in_options)
        in_options = struct();
    end
    options = mergeOptions(optionDefault, in_options);
    
    % Extract the trained effective basis.
    if ~isfield(model, 'W')
        error('Model must contain field "W" (the effective basis matrix).');
    end
    W = model.W;  % size: (m x r)
    [m, r] = size(W);
    
    % Check dimensions of X.
    if size(X,1) ~= m
        if size(X,2) == m
            X = X';
        else
            error('Test data X must have %d rows, but has %d.', m, size(X,1));
        end
    end
    [~, n_test] = size(X);
    
    % Decide mapping method: if both orth_w and orth_h were active, use NNLS.
    if isempty(options.useLSQ)
        if options.orth_w && options.orth_h
            mappingMethod = 'NNLS';
        else
            mappingMethod = 'MU';
        end
    else
        if options.useLSQ
            mappingMethod = 'NNLS';
        else
            mappingMethod = 'MU';
        end
    end
    
    switch mappingMethod
        case 'NNLS'
            % For each test sample, solve NNLS: min_{y>=0} || x - W*y ||_2^2.
            Y = zeros(r, n_test);
            for i = 1:n_test
                Y(:, i) = lsqnonneg(W, X(:, i));
            end
            % Normalize Y columns if norm_h is active (to mimic training).
            if options.norm_h
                Y = normalize_H(Y, options.norm_h);
            end
            numIter = NaN;
        case 'MU'
            % Standard multiplicative update projection.
            Y = max(rand(r, n_test), options.myeps);
            XfitPrevious = Inf;
            for iter = 1:options.iter
                numerator = W' * X;
                denominator = max((W' * W) * Y, options.myeps);
                Y = Y .* (numerator ./ denominator);
                Y = max(Y, options.myeps);
                if options.norm_h
                    Y = normalize_H(Y, options.norm_h);
                end
                XfitThis = W * Y;
                fitRes = norm(XfitPrevious - XfitThis, 'fro');
                curRes = norm(X - XfitThis, 'fro');
                XfitPrevious = XfitThis;
                if options.disp_freq
                    fprintf('Test MU Iteration %d, residual = %.4e\n', iter, curRes);
                end
                if fitRes < options.residual || iter == options.iter
                    break;
                end
            end
            numIter = iter;
    end
    
    tElapsed = toc(tStart);
    
    infos.method = mappingMethod;
    infos.numIter = numIter;
    infos.finalResidual = norm(X - W * Y, 'fro');
    infos.tElapsed = tElapsed;
end

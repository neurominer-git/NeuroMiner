function [Y, infos] = hals_so_nmf_test(X, model, in_options)
% HALS_SO_NMF_TEST Apply a trained NMF-HALS-SO model to new data.
%
%   [Y, infos] = hals_so_nmf_test(X, model, in_options) computes the
%   coefficient matrix Y for test data X using the trained basis matrix W
%   from an NMF-HALS-SO factorization. In training, the data matrix V was
%   approximated by
%
%       V ≈ W * H,
%
%   where W was learned with a soft orthogonal constraint. Given new data
%   X (m x n_test), this function solves for Y ≥ 0 in
%
%       min_Y || X - W * Y ||_F^2.
%
%   The update for Y is performed in a HALS fashion, similar to the update
%   used for H during training:
%
%       For j = 1,...,rank,
%           Y(j,:) = (X' * W(:,j))' - (W' * W(:,j))' * Y + (W(:,j)' * W(:,j)) * Y(j,:);
%           Y(j,:) = max( (Y(j,:) + abs(Y(j,:)))/2, myeps );
%
%   INPUTS:
%       X         : (m x n_test) nonnegative test data matrix (each column is a sample).
%       model     : struct containing the trained model from hals_so_nmf, with at
%                   least the field:
%                       model.W  - (m x rank) basis matrix.
%       in_options: (optional) struct with test-phase options. Supported fields:
%                     .iter      : maximum number of iterations (default: 200)
%                     .dis       : flag to display progress (default: 1)
%                     .residual  : convergence tolerance for reconstruction change (default: 1e-4)
%                     .myeps     : small constant to avoid division by zero (default: 1e-16)
%
%   OUTPUTS:
%       Y     : (rank x n_test) coefficient matrix representing the new data.
%       infos : struct containing test-phase information:
%                   .numIter       - number of iterations performed.
%                   .finalResidual - final reconstruction error, i.e. ||X - W*Y||_F.
%                   .tElapsed      - elapsed time in seconds.
%
%   Example:
%       % Assume a model was trained using hals_so_nmf:
%       model = hals_so_nmf(V, rank, options);
%
%       % To compute the representation for new data X_new:
%       [Y_new, test_infos] = hals_so_nmf_test(X_new, model, test_options);
%
%   See also: hals_so_nmf, mergeOptions.
%

    tStart = tic;
    
    % Set default test-phase options.
    optionDefault.iter = 200;
    optionDefault.dis = 1;
    optionDefault.residual = 1e-4;
    optionDefault.myeps = 1e-16;
    
    if ~exist('in_options','var') || isempty(in_options)
        in_options = struct();
    end
    options = mergeOptions(in_options, optionDefault);
    
    % Extract the trained basis matrix W.
    if ~isfield(model, 'W')
        error('The model must contain the field ''W'' (the basis matrix).');
    end
    W = model.W;
    [m, rank] = size(W);
    
    % Ensure that X has the proper dimensions (m rows: one per feature).
    if size(X,1) ~= m
        if size(X,2) == m
            X = X';
        else
            error('Test data X must have %d rows, but has %d.', m, size(X,1));
        end
    end
    [~, n_test] = size(X);
    
    % Initialize Y (the new coefficient matrix) as ones.
    Y = ones(rank, n_test);
    
    % Precompute constant matrices.
    % Compute W'*W once since W is fixed.
    WWT = W' * W;  % rank x rank matrix.
    % Compute XTW which plays the role of V'*W in training.
    XTW = X' * W;  % n_test x rank, each column corresponds to one column of W.
    
    % Iteratively update Y using a HALS-like rule.
    XfitPrevious = Inf;
    for iter = 1:options.iter
        for j = 1:rank
            % Update Y(j,:) based on the HALS rule.
            % Note: XTW(:,j)' is 1 x n_test.
            %       WWT(:,j)'*Y is 1 x n_test.
            Y(j,:) = XTW(:,j)' - (WWT(:,j)' * Y) + WWT(j,j)*Y(j,:);
            % Ensure nonnegativity:
            Y(j,:) = max( (Y(j,:) + abs(Y(j,:)))/2, options.myeps );
        end
        
        % Compute the current reconstruction and check convergence.
        XfitThis = W * Y;
        fitRes = norm(XfitPrevious - XfitThis, 'fro');
        XfitPrevious = XfitThis;
        curRes = norm(X - XfitThis, 'fro');
        
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

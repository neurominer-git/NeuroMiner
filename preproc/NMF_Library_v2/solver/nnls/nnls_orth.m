function [V, norm2v] = nnls_orth(M, U, Mn)
% NNLS_ORTH solves 
%
%   min_{V >= 0} || M - U*V ||_F^2
%
% where the columns of Mn are the normalized columns of M.
%
% References:
%   F. Pompili, N. Gillis, P.-A. Absil and F. Glineur,
%   "Two Algorithms for Orthogonal Nonnegative Matrix Factorization
%   with Application to Clustering," 
%   Neurocomputing 141, pp. 15-25, 2014.
%
%   This file has been ported from orthNNLS.m available at:
%   https://gitlab.com/ngillis/nmfbook/-/tree/master/algorithms
%   by Nicolas Gillis (nicolas.gillis@umons.ac.be)
%
% Modified to handle the case where the factorization rank is 1.

    if nargin <= 2 || isempty(Mn)
        norm2m = sqrt(sum(M.^2, 1));
        Mn = M .* repmat(1./(norm2m+1e-16), size(M,1), 1);
    end

    [m, n] = size(Mn);
    [m, r] = size(U);
    
    % Normalize columns of U
    norm2u = sqrt(sum(U.^2, 1));
    Un = U .* repmat(1./(norm2u+1e-16), m, 1);
    
    % Compute the cosine similarities between the normalized columns of M and U.
    A = Mn' * Un;  % A is an (n x r) matrix

    % If r == 1, we cannot use max on A' as in the multi-column case.
    if r == 1
        a = A';            % a is 1 x n, but its values are not used further.
        b = ones(1, n);    % For each sample, the only candidate index is 1.
    else
        [a, b] = max(A');  % b is a 1 x n vector with indices in 1:r.
    end
    
    % Initialize output
    V = zeros(r, n);
    
    % Assign the optimal weights: for each sample i, use the index b(i).
    for i = 1 : n
        V(b(i), i) = (M(:, i)' * U(:, b(i))) / (norm(U(:, b(i)))^2);
    end

    norm2v = sqrt(sum(V.^2, 1));
end

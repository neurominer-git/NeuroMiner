function [rdc, stats] = rdc(X, Y, varargin)
%RDC  Randomized Dependence Coefficient between X and Y.
%
%   rdc = RDC(X, Y) computes the RDC between (row-aligned) samples X and Y.
%   X is n-by-dx, Y is n-by-dy. Returns a scalar rdc in [0,1].
%
%   [rdc, stats] = RDC(...) also returns a struct with useful details:
%       stats.r                 - vector of canonical correlations (desc)
%       stats.A, stats.B        - CCA weight matrices (X and Y sides)
%       stats.U, stats.V        - first pair of canonical variates
%       stats.PhiX, stats.PhiY  - randomized feature maps
%       stats.Wx, stats.Wy      - random projection matrices
%       stats.bx, stats.by      - random phase/bias vectors
%       stats.idx_kept          - rows kept after NaN/Inf removal
%
%   Name-value pairs:
%       'K'        (default 20)    - number of random projections per side
%       'Scale'    (default 1/6)   - Gaussian scale for W ~ N(0, Scale^2)
%       'Seed'     (default [])    - rng seed (fixed randomness if provided)
%       'UseCos'   (default true)  - include cos() features in addition to sin()
%       'AddBias'  (default true)  - append a column of ones to PhiX/PhiY
%
%   Notes:
%   - Follows Lopez-Paz, Hennig, Schölkopf (NeurIPS 2013).
%   - Steps: empirical copula -> random Fourier features (sin/cos) -> CCA.
%   - Invariance to monotone transforms comes from the copula step.
%
%   Example:
%       n = 500;
%       x = randn(n,1);
%       y = sin(2*x) + 0.1*randn(n,1);
%       r = rdc(x,y)
%
%   Reference:
%   Lopez-Paz, D., Hennig, P., & Schölkopf, B. (2013).
%   The Randomized Dependence Coefficient. NeurIPS 2013.
% =========================================================================
% (c) Nikolaos Koutsouleris, 10/2025

    % ---- Parse inputs
    p = inputParser;
    p.addRequired('X', @(z) isnumeric(z) && ~isempty(z));
    p.addRequired('Y', @(z) isnumeric(z) && ~isempty(z));
    p.addParameter('K', 20, @(z) isscalar(z) && z>=1 && z==floor(z));
    p.addParameter('Scale', 1/6, @(z) isscalar(z) && z>0);
    p.addParameter('Seed', [], @(z) isempty(z) || (isscalar(z) && isnumeric(z)));
    p.addParameter('UseCos', true, @(z) islogical(z) && isscalar(z));
    p.addParameter('AddBias', true, @(z) islogical(z) && isscalar(z));
    p.parse(X, Y, varargin{:});
    K      = p.Results.K;
    s      = p.Results.Scale;
    seed   = p.Results.Seed;
    useCos = p.Results.UseCos;
    addBias= p.Results.AddBias;

    % ---- Basic checks
    if size(X,1) ~= size(Y,1)
        error('X and Y must have the same number of rows (samples).');
    end
    n = size(X,1);
    if n < 3
        warning('Not enough samples for a meaningful RDC. Returning NaN.');
        rdc = NaN; stats = struct(); return;
    end

    % ---- Remove rows with any NaN/Inf
    badX = any(~isfinite(X),2);
    badY = any(~isfinite(Y),2);
    keep = ~(badX | badY);
    X = X(keep,:); Y = Y(keep,:);
    if nnz(keep) < 3
        warning('Too many invalid rows removed. Returning NaN.');
        rdc = NaN; stats = struct(); return;
    end

    % ---- Optional fixed RNG
    if ~isempty(seed)
        rng_state = rng; 
        rng(seed, 'twister');
        cleanupRNG = onCleanup(@() rng(rng_state));
    else
        cleanupRNG = []; %#ok<NASGU>
    end

    % ---- Empirical copula transform (rank -> uniform(0,1))
    Ux = copula_transform(X);
    Uy = copula_transform(Y);

    % ---- Random Fourier features (sin/cos with random linear projections)
    dx = size(Ux,2); dy = size(Uy,2);

    Wx = s * randn(dx, K);
    Wy = s * randn(dy, K);
    bx = -pi + (2*pi)*rand(1, K);
    by = -pi + (2*pi)*rand(1, K);

    % Affine projections
    Zx = Ux * Wx + repmat(bx, size(Ux,1), 1);
    Zy = Uy * Wy + repmat(by, size(Uy,1), 1);

    % Nonlinear map
    PhiX = sin(Zx);
    PhiY = sin(Zy);
    if useCos
        PhiX = [PhiX, cos(Zx)];
        PhiY = [PhiY, cos(Zy)];
    end
    if addBias
        PhiX = [PhiX, ones(size(PhiX,1),1)];
        PhiY = [PhiY, ones(size(PhiY,1),1)];
    end

    % ---- Center features (recommended for CCA numerical stability)
    PhiX = center_cols(PhiX);
    PhiY = center_cols(PhiY);

    % ---- Canonical Correlation (use canoncorr if available; else robust SVD)
    try
        % MATLAB Statistics Toolbox
        [A,B, r, U, V] = canoncorr(PhiX, PhiY); 
    catch
        % Fallback: compute leading canonical correlations via SVD.
        [r, A, B, U, V] = cca_fallback(PhiX, PhiY);
    end

    if isempty(r)
        rdc = 0;
    else
        rdc = r(1);
    end

    % ---- Outputs
    stats = struct();
    stats.r       = r(:);
    stats.A       = A;
    stats.B       = B;
    stats.U       = (exist('U','var') && ~isempty(U)) * U + [];
    stats.V       = (exist('V','var') && ~isempty(V)) * V + [];
    stats.PhiX    = PhiX;
    stats.PhiY    = PhiY;
    stats.Wx      = Wx;
    stats.Wy      = Wy;
    stats.bx      = bx;
    stats.by      = by;
    stats.idx_kept= find(keep);

end

% ---------- Helpers ----------

function U = copula_transform(X)
    % Rank each column and scale to (0,1) using (rank)/(n+1) to avoid 0/1 endpoints.
    n = size(X,1);
    U = zeros(size(X));
    for j = 1:size(X,2)
        % tiedrank handles ties by averaging ranks
        r = tiedrank(X(:,j));
        U(:,j) = r / (n + 1);
    end
end

function Z = center_cols(Z)
    mu = mean(Z,1);
    Z = bsxfun(@minus, Z, mu);
end

function [r, A, B, U, V] = cca_fallback(X, Y)
    % Compute canonical correlations via covariance whitening + SVD.
    % Returns all canonical correlations (descending), and weights A,B.
    %
    % Based on: r = svd( Cxx^{-1/2} * Cxy * Cyy^{-1/2} )
    % Then weights follow from singular vectors mapped back.

    n = size(X,1);
    if size(Y,1) ~= n
        error('cca_fallback: X and Y must have same #rows.');
    end

    % Covariances (unbiased)
    Cxx = (X.' * X) / (n - 1);
    Cyy = (Y.' * Y) / (n - 1);
    Cxy = (X.' * Y) / (n - 1);

    % Regularization for numerical stability
    epsx = 1e-8 * trace(Cxx) / size(Cxx,1);
    epsy = 1e-8 * trace(Cyy) / size(Cyy,1);
    Cxx = Cxx + epsx * eye(size(Cxx));
    Cyy = Cyy + epsy * eye(size(Cyy));

    % Inverse square roots via eigen-decomposition
    [Ux, Sx] = eig_sym(Cxx);
    [Uy, Sy] = eig_sym(Cyy);

    Sx_inv_sqrt = diag((diag(Sx)).^(-0.5));
    Sy_inv_sqrt = diag((diag(Sy)).^(-0.5));

    Cxx_inv_sqrt = Ux * Sx_inv_sqrt * Ux.';
    Cyy_inv_sqrt = Uy * Sy_inv_sqrt * Uy.';

    T = Cxx_inv_sqrt * Cxy * Cyy_inv_sqrt;

    % SVD
    [L, S, R] = svd(T, 'econ');

    r = diag(S);
    % CCA weight matrices in original feature spaces
    A = Cxx_inv_sqrt * L;
    B = Cyy_inv_sqrt * R;

    % First pair of canonical variates
    U = X * A;
    V = Y * B;
end

function [U, S] = eig_sym(C)
    % Symmetric eigendecomposition with cleanup for numerical noise
    [U, S] = eig((C + C.')/2, 'vector');
    S = diag(max(S, 0)); % clamp tiny negatives to zero
    % sort descending
    [d, idx] = sort(diag(S), 'descend');
    S = diag(d);
    U = U(:, idx);
end

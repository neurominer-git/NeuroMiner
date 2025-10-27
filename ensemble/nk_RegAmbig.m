function out = nk_RegAmbig(sE, tE, mode, agg, outType, diagMode)
% =========================================================================
% nk_RegAmbig — Regression ensemble diversity / ambiguity
% -------------------------------------------------------------------------
% out = nk_RegAmbig(sE, tE, mode, agg, outType, diagMode)
%
% sE      : N×M matrix of base-learner predictions (double)
% tE      : (optional) N×1 target vector (needed for 'residual-*' modes)
% mode    : 'var'        -> mean per-sample variance across learners (default)
%           'pairwise'   -> mean per-sample average pairwise squared diff
%           'corr'       -> 1 - |corr(mean(sE,2), tE)|     (perf-like complement)
%           'residual-cov'  (kernel only) -> cov of residuals across learners
%           'residual-corr' (kernel only) -> corr of residuals across learners
%           'residual-lapl' (kernel only) -> Laplacian built from residual similarity
% agg     : 'mean' (default) | 'median'  (only for 'var')
% outType : 'scalar' (default) | 'kernel'
% diagMode: for outType='kernel' only:
%           'one' (default) set diag(R)=1
%           'zero'           set diag(R)=0
%           'keep'           keep computed diagonal
%
% Returns:
%   out  : scalar (higher = more dispersion)    if outType='scalar'
%          M×M PSD kernel matrix (double)       if outType='kernel'
%
% Notes (scalar modes):
%   • 'var' matches Krogh–Vedelsby ambiguity (with 'mean' aggregate).
%   • 'pairwise' equals (2n/(n-1)) × population variance across learners.
%   • 'corr' is not intra-ensemble diversity; it’s a perf-complement.
%
% Notes (kernel modes):
%   • 'residual-*' modes build a pairwise structure that Boosting can use
%     via alpha * w' R w. Use 'residual-lapl' to encourage smooth/shared
%     weights across similar learners (less spiky solutions).
% =========================================================================

% ---- defaults & hygiene --------------------------------------------------
if nargin < 3 || isempty(mode),     mode     = 'var';     end
if nargin < 4 || isempty(agg),      agg      = 'mean';    end
if nargin < 5 || isempty(outType),  outType  = 'scalar';  end
if nargin < 6 || isempty(diagMode), diagMode = 'one';     end

sE = double(sE);
[N,M] = size(sE);

if strcmpi(outType,'scalar')
    % ====================== SCALAR DIVERSITY ==============================
    if M <= 1 || N == 0
        out = 0;
        return;
    end

    switch lower(mode)
        case 'var'
            switch lower(agg)
                case 'median', mu = nm_nanquantile(sE, 0.5, 2);
                otherwise,     mu = nm_nanmean(sE,   2);
            end
            R  = sE - mu;               % N×M residuals around aggregate
            v  = nm_nanmean(R.^2, 2);         % per-sample population variance across learners
            out = nm_nanmean(v);              % higher = more dispersion

        case 'pairwise'
            % (2/(M*(M-1))) * sum_{i<j} (f_i - f_j)^2  ==  (2M/(M-1)) * popVar
            mu = nm_nanmean(sE, 2);
            R  = sE - mu;
            popVar = nm_nanmean(R.^2, 2);
            out = nm_nanmean( (2*M/(M-1)) * popVar );  % higher = more dispersion

        case 'corr'
            if nargin < 2 || isempty(tE) || numel(tE) ~= N
                error('nk_RegAmbig: mode=''corr'' requires tE as N×1 target.');
            end
            ens = nm_nanmean(sE,2);
            c   = corr(ens, double(tE(:)), 'type','Pearson', 'rows','pairwise');
            if ~isfinite(c), c = 0; end
            out = 1 - abs(c);           % higher = worse corr (more “diverse” wrt target)

        % Provide a scalar from residual structure if someone requests it
        case {'residual','residual-cov','residual-corr','residual-lapl'}
            if nargin < 2 || isempty(tE) || numel(tE) ~= N
                error('nk_RegAmbig: residual-* modes require tE as N×1 target.');
            end
            E = bsxfun(@minus, double(tE(:)), sE);     % residuals N×M
            C = corr(E, 'rows','pairwise');            % [-1,1], NaN-safe
            C(~isfinite(C)) = 0;
            % turn into a diversity-like scalar: mean(1 - |corr|) off-diagonal
            mask = ~eye(M);
            out  = nm_nanmean( 1 - abs(C(mask)) );           % higher = less redundancy
        otherwise
            error('nk_RegAmbig: unknown mode ''%s''.', mode);
    end

else
    % ====================== KERNEL CONSTRUCTION ===========================
    if ~startsWith(lower(mode),'residual')
        error('nk_RegAmbig: outType=''kernel'' requires a residual-* mode.');
    end
    if nargin < 2 || isempty(tE) || numel(tE) ~= N
        error('nk_RegAmbig: residual-* kernel requires tE as N×1 target.');
    end

    % residuals (center columns to be safe)
    E = bsxfun(@minus, double(tE(:)), sE);   % N×M
    E = bsxfun(@minus, E, nm_nanmean(E,1));        % center

    switch lower(mode)
        case 'residual-cov'
            R = cov(E, 1);                   % population covariance (PSD)
            % scale each column to unit variance so off-diagonals are visible
            d = sqrt(diag(R) + eps);
            R = R ./ (d*d.');                % correlation-like; diag ~ 1

        case 'residual-corr'
            R = corr(E, 'rows','pairwise');  % in [-1,1]
            R(~isfinite(R)) = 0;
            R = max(R,0);                    % keep redundancy only (positive corr)

        case 'residual-lapl'
            % Pairwise squared-diff → similarity → Laplacian
            D = pdist2(E.', E.', @(a,b) nm_nanmean((a-b).^2));  % M×M; mean over rows
            % Gaussian affinity; robust scale
            s2 = nm_nanquantile(D(:).^2, 0.5) + eps;
            S  = exp( -D / s2 );
            S  = (S+S.')/2;  S(1:M+1:end)=0;
            d  = sum(S,2);
            L  = diag(d) - S;                % graph Laplacian
            % Normalize to unit spectral norm
            L  = (L+L.')/2;
            ev = eig(L); L = L / max(max(ev), eps);
            % Use Laplacian as the kernel (alpha * w' L w)
            R  = L;

        otherwise
            error('nk_RegAmbig: unknown residual kernel mode ''%s''.', mode);
    end

    % Diagonal handling
    switch lower(diagMode)
        case 'one',  R(1:M+1:end) = 1;
        case 'zero', R(1:M+1:end) = 0;
        case 'keep'  % do nothing
        otherwise,   error('nk_RegAmbig: unknown diagMode ''%s''.', diagMode);
    end

    % Symmetrize, PSD-project (safety), and return
    R = (R+R.')/2;
    [V,D] = eig(R); D = diag(D); D = max(D,0); R = V*diag(D)*V.';
    out = R;                                 % M×M kernel
end
end

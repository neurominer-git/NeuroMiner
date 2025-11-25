function [ref, cnt_vec] = nk_UpdateRefEMA_Simple(ref_cell, Tx_realigned, corrPerComp, alpha, cnt_vec, unitnorm, robust)
% Exponential Moving Average (EMA) update of reference templates per modality.
%
% Inputs
%   ref_cell    : 1×nM cell, each [nFeat × nRef] current reference (per CV1 fold, per modality)
%   Tx_realigned      : 1×nM cell, each [nFeat × nRef] aligned + sign-corrected maps (this model)
%   corrPerComp : 1×nRef similarity per reference column (optional; [] if not used)
%   alpha       : scalar in [0,1] (e.g., 0.15)
%   cnt_vec     : 1×nRef update counts ([] on first call → will be created/extended)
%   unitnorm    : logical, default true (shape-only templates)
%   robust      : logical, default true (down-weight by corrPerComp if provided)
%
% Outputs
%   ref         : updated references
%   cnt_vec     : updated counts (same length as nRef)
% =======================================================================================================================
% (c) Nikolaos Koutsouleris 11/2025

    if nargin < 6 || isempty(unitnorm), unitnorm = true; end
    if nargin < 7 || isempty(robust),   robust   = true; end
    if ~iscell(ref_cell), ref_cell = {ref_cell}; return2mat = true; else, return2mat= false; end
    if ~iscell(Tx_realigned), Tx_realigned = {Tx_realigned}; end
    nM  = numel(ref_cell);
    nRf = size(ref_cell{1},2);

    % Sanity: Tx_realigned must match reference width (ref order)
    for m = 1:nM
        if size(Tx_realigned{m},2) ~= nRf
            error('Tx_realigned{%d} has %d columns, expected %d (reference width).', m, size(Tx_realigned{m},2), nRf);
        end
    end

    % decide once which refs to update this fold
    if ~isempty(corrPerComp)
        % prefer the aligner’s signal: finite corr means a winner/collapsed source
        obs = isfinite(corrPerComp(:)).';
    else
        % fallback: any modality provided finite data for that ref
        obs = false(1, nRf);
        for m = 1:nM
            obs = obs | any(isfinite(Tx_realigned{m}), 1);
        end
    end
        
    % per-ref alpha (optionally scaled by similarity)
    if isscalar(alpha), a = alpha * ones(1, nRf); else, a = alpha; end
    if robust && ~isempty(corrPerComp)
        tau  = 0.2;
        rho  = corrPerComp(:).';
        gain = max((rho - tau) ./ max(1 - tau, eps), 0);
        a    = a .* gain;
    end
    
    % apply EMA per modality, but DO NOT bump counts here
    for m = 1:nM
        R = ref_cell{m};
        A = Tx_realigned{m};
        if size(A,2) ~= nRf, error('Tx_realigned{%d} width mismatch.', m); end
    
        idx = obs;                          % update the same refs across all modalities
        if any(idx)
            if unitnorm
                R(:,idx) = l2norm_cols(R(:,idx));
                A(:,idx) = l2norm_cols(A(:,idx));
            end
            R(:,idx) = bsxfun(@times, 1 - a(idx), R(:,idx)) + bsxfun(@times, a(idx), A(:,idx));
            if unitnorm
                R(:,idx) = l2norm_cols(R(:,idx));
            end
            ref_cell{m} = R;
        end
    end
    
    % increment counts ONCE per ref
    cnt_vec = pad_or_trim(cnt_vec, nRf);
    cnt_vec(obs) = cnt_vec(obs) + 1;

    if return2mat
        ref = ref_cell{1};
    else
        ref = ref_cell;
    end
    
end

% ---------- utils ----------
function X = l2norm_cols(X)
    n = sqrt(sum(X.^2, 1));
    nz = n > 0 & isfinite(n);
    X(:,nz) = bsxfun(@rdivide, X(:,nz), n(nz));
end
function v = pad_or_trim(v, n)
    if numel(v) < n, v(end+1:n) = 0; else, v = v(1:n); end
end

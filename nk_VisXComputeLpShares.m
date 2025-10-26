function [share, method] = nk_VisXComputeLpShares(W, SVM, normalizeflag)

    if ~exist("normalizeflag","var") || isempty(normalizeflag)
        normalizeflag = true;
    end
    
    % --- choose method (very simple mapping) ---
    switch SVM.prog
        % Linear / margin / coefficient-based → L2n
        case {'LIBSVM','LIBLIN','GLMFIT','GLMNET','MATLRN','ELASVM','WBLCOX','MEXELM','MVTRVR','MVTRVM'}
            method = 'L2n';
    
        % Importance / saliency based → L1n (mean |w| is more natural)
        case {'RNDFOR','GRDBST','DECTRE','MLPERC','TFDEEP','IMRELF'}
            method = 'L1n';
    
        otherwise
            % fallback: L2n (safe default)
            method = 'L2n';
    end
    
    switch method
        case 'L2n'
            v = l2n_block(W); 
        case 'L1n'
            v = l1n_block(W); 
    end
    
    share = NaN;
    if normalizeflag && numel(v)>1
        tot = sum(v,'omitnan');
        if tot > 0, share = v ./ tot; end
    else
        share = v;
    end

end

% ===== helpers =====
function L2n = l2n_block(x)
% normalized L2: ||x||2 / sqrt(#finite)
  
    if isempty(x), L2n = 0; return; end
    xf = x(isfinite(x));
    if isempty(xf), L2n = 0; return; end

    % Vector case -> single scalar
    if isvector(x)
        w = x(:);
        m = isfinite(w);
        if ~any(m)
            L2n = NaN;
            return
        end
        L2n = norm(w(m), 2) / sqrt(sum(m));
        return
    end

    % Matrix case -> column vector result
    m   = isfinite(x);              % logical mask of finite entries
    cnt = sum(m, 1);                % finite count per col
    L2n = nan(size(x,2), 1);        % default NaN for empty columns

    nz = cnt > 0;                   % columns with at least one finite entry
    if any(nz)
        % Zero-out non-finite entries (avoid NaNs in sums), then sum squares
        tmp = x(:, nz);
        % For speed with sparse/dense, avoid elementwise multiply with mask; assign zeros instead
        tmp(~isfinite(tmp)) = 0;
        ssq = sum(tmp.^2, 1); % 1 x nnz cols
        L2n(nz) = sqrt(ssq(:)) ./ sqrt(cnt(nz)).';
    end

end

% ===== helpers =====
function L1n = l1n_block(x)
% normalized L1: ||x||1 / (#finite)
  
    xf = x(isfinite(x));
    if isempty(xf), L1n = 0; return; end

    % Vector case -> single scalar
    if isvector(x)
        w = x(:);
        m = isfinite(w);
        if ~any(m)
            L1n = NaN;
            return
        end
        L1n = sum(abs(w(m))) / sum(m);
        return
    end

    % Matrix case -> column vector result
    m   = isfinite(x);              % logical mask of finite entries
    cnt = sum(m, 1);                % finite count per col
    L1n = nan(size(x,2), 1);        % default NaN for empty columns

    nz = cnt > 0;                   % columns with at least one finite entry
    if any(nz)
        % Zero-out non-finite entries (avoid NaNs in sums), then sum absolutes
        tmp = x(:, nz);
        tmp(~isfinite(tmp)) = 0;
        sabs = sum(abs(tmp), 1); % 1 x nnz cols

        L1n(nz) = sabs(:) ./ cnt(nz).';
    end

end

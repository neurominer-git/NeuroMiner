function [Ref_new, cnt_new, mg] = nk_MergeRefColumns(Ref, cnt_vec, opts)
% Greedy merge of reference columns across ALL modalities jointly
% (same mapping applied to every modality).
%
% Inputs
%   Ref      : 1×nM cell, each [nFeat_m × nRef] (all have same nRef)
%   cnt_vec  : 1×nRef (presence counts or weights); [] -> ones
%   opts     : struct with fields (all optional)
%              .thr       (default 0.85) similarity threshold
%              .metric    (default 'pearson') {'cosine','pearson','spearman','euclidean','bicor'}
%              .unitnorm  (default true) unit-normalize columns before similarity/averaging
%              .w         (1×nM modality weights, default ones)
%              .merge_neg (default true) allow merging of strongly anti-correlated pairs (flip j)
%
% Outputs
%   Ref_new  : 1×nM cell, merged columns removed (same nM)
%   cnt_new  : 1×nRef_new updated counts (sum of merged)
%   mg       : struct with fields: oldN,newN,pairsMerged,map_old2new,kept_idx,smax

    if ~iscell(Ref), Ref = {Ref}; end
    nM = numel(Ref);
    assert(nM>=1, 'Ref must be a non-empty cell array.');
    nRef = size(Ref{1},2);
    for m=2:nM, assert(isempty(Ref{m}) || size(Ref{m},2)==nRef, 'All modalities must share nRef.'); end
    if nargin<2 || isempty(cnt_vec), cnt_vec = ones(1,nRef); end
    if nargin<3, opts = struct; end
    thr       = get_opt(opts,'thr',0.85);
    metric    = get_opt(opts,'metric','pearson');
    unitnorm  = get_opt(opts,'unitnorm',true);
    w         = get_opt(opts,'w', ones(1,nM));
    merge_neg = get_opt(opts,'merge_neg',true);    % <<< NEW
    w = w(:)'; if numel(w)~=nM, w = ones(1,nM); end
    validateattributes(thr, {'numeric'},{'scalar','>=',0,'<=',1});

    if nRef<=1
        Ref_new = Ref; cnt_new = cnt_vec;
        mg = struct('oldN',nRef,'newN',nRef,'pairsMerged',[], ...
                    'map_old2new',1:nRef,'kept_idx',1:nRef,'smax',NaN);
        return
    end

    active = true(1,nRef);
    pairs  = zeros(0,2);
    counts = cnt_vec(:)';

    % Greedy merging
    while true
        S = agg_ref_ref_similarity(Ref, metric, w, unitnorm);  % [nRef x nRef]
        % optionally include negative correlations
        if merge_neg && is_signed_metric(metric)
            Suse = abs(S);
        else
            Suse = S;
        end
        Suse(~isfinite(S)) = -Inf;                               % sanitize
        % ignore inactive and diagonal
        Suse(:,~active) = -Inf;
        Suse(~active,:) = -Inf;
        
        % only take upper triangle (no diagonal)
        Suse = triu(Suse, 1);
        
        % find strongest pair
        [smax, idx] = max(Suse(:));
        if ~isfinite(smax) || smax < thr
            break;
        end

        [i,j] = ind2sub([nRef nRef], idx);
        ci = counts(i); cj = counts(j);
        csum = ci + cj; if csum==0, csum = 1; end

        % if signed & negative similarity, flip j to align signs
        sgn_ij = 1;
        if merge_neg && is_signed_metric(metric)
            sij = S(i,j);
            if isfinite(sij) && sij < 0
                sgn_ij = -1;
            end
        end

        % Weighted average per modality, then (optionally) unit-norm
        for m = 1:nM
            if isempty(Ref{m}), continue; end
            Ri = Ref{m}(:,i);
            Rj = Ref{m}(:,j) * sgn_ij;   % <<< NEW: apply flip if needed
            Ri(~isfinite(Ri)) = 0; Rj(~isfinite(Rj)) = 0;
            Rm = (ci*Ri + cj*Rj)/csum;
            if unitnorm
                nr = norm(Rm); if nr>0 && isfinite(nr), Rm = Rm/nr; end
            end
            Ref{m}(:,i) = Rm;
        end

        counts(i) = csum;
        active(j) = false;
        pairs(end+1,:) = [i j]; 
    end

    kept = find(active);
    Ref_new = cellfun(@(R) R(:,kept), Ref, 'uni', 0);
    cnt_new = counts(kept);
    map_old2new       = zeros(1,nRef);
    map_old2new(kept) = 1:numel(kept);
    for k = 1:size(pairs,1)
        map_old2new(pairs(k,2)) = map_old2new(pairs(k,1));
    end
    mg = struct('oldN',nRef,'newN',numel(kept),'pairsMerged',pairs, ...
                'map_old2new',map_old2new,'kept_idx',kept, 'smax', smax);
end

% ---------- helpers ----------
function S = agg_ref_ref_similarity(Ref, metric, w, unitnorm)
% Aggregate per-modality ref-vs-ref similarity into one matrix.
    nM   = numel(Ref);
    nRef = size(Ref{1},2);
    Ssum = zeros(nRef, nRef, 'like', Ref{1});
    wsum = 0;
    for m=1:nM
        A = Ref{m};
        if isempty(A), continue; end
        Sm = similarity_kernel(A, A, metric, unitnorm); % [nRef x nRef]
        wm = w(m);
        Ssum = Ssum + wm * Sm;
        wsum = wsum + wm;
    end
    if wsum>0, S = Ssum / wsum; else, S = Ssum; end
    S(~isfinite(S)) = 0;
end

function tf = is_signed_metric(metric)
    % negative similarity is meaningful for these metrics
    tf = any(strcmpi(metric, {'pearson','spearman','cosine','bicor'}));
end

function v = get_opt(s,f,d)
    if ~isstruct(s) || ~isfield(s,f) || isempty(s.(f)), v = d; else, v = s.(f); end
end

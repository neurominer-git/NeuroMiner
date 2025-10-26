function [sortedMaps, unmatchedComponents, assignmentVec, corrPerComp, signCorrections, similarityMatrix, refMapsUpdated, groupsPerRef] = ...
         nk_AlignCompAndSignCorrect(refMaps, currentMaps, cutoff, metric, collapseManyToOne)
% nk_AlignCompAndSignCorrect
% Align & sign-correct currentMaps columns to refMaps (single or multi-modality).
%
% Usage:
%   [S,U,A,C,SGN,Sim]                        = nk_AlignCompAndSignCorrect(R, C)
%   [S,U,A,C,SGN,Sim]                        = nk_AlignCompAndSignCorrect(R, C, cutoff)
%   [S,U,A,C,SGN,Sim]                        = nk_AlignCompAndSignCorrect(R, C, cutoff, metric)
%   [S,U,A,C,SGN,Sim,Rupd,groupsPerRef]      = nk_AlignCompAndSignCorrect(R, C, cutoff, metric, collapseManyToOne)
%
% Inputs:
%   refMaps, currentMaps  : [F×k] or cell{nM} per-modality matrices.
%   cutoff                : absolute-similarity threshold (default 0.3).
%   metric                : 'pearson' | 'spearman' | 'cosine' | 'bicor' | 'euclidean' (default 'pearson').
%   collapseManyToOne     : logical flag; if true, collapse all sources with |sim|>=cutoff into the ref by mean.
%                           DEFAULT = false (old policy: "winner takes all").
%
% Outputs:
%   sortedMaps       : maps in ref order (winner-only or collapsed mean depending on flag), sign-corrected.
%   unmatchedComponents : still-unmatched source columns (per modality) after growth & final align.
%   assignmentVec    : shared source index chosen by Hungarian for each ref (0 if unmatched below cutoff).
%   corrPerComp      : non-negative similarity per ref vs signed (winner or collapsed) source vector.
%   signCorrections  : sign of aggregated signed similarity for the Hungarian winner (legacy / diagnostic).
%   similarityMatrix : final-pass signed aggregated similarity (ref × shared source index).
%   refMapsUpdated   : possibly grown reference (per-modality cells or single matrix).
%   groupsPerRef     : 1×nRef cell of shared indices used for each ref.
%                      If collapseManyToOne=false → winner only ([j] or []).
%
% Policy notes:
% - Inputs are assumed already "significant"; ANY shared source column left unmatched after cutoff
%   is appended to the reference, then we re-align once.
% - When collapseManyToOne=false (default): behavior matches the classic "winner takes all" policy.

if nargin < 3 || isempty(cutoff), cutoff = 0.3; end
if nargin < 4 || isempty(metric), metric  = 'pearson'; end
if nargin < 5 || isempty(collapseManyToOne), collapseManyToOne = false; end
metric = validatestring(lower(metric), {'euclidean','pearson','cosine','spearman','bicor'});

% -------- normalize to cell arrays --------
isMulti = iscell(refMaps) || iscell(currentMaps);
if ~isMulti
    refCells = {refMaps};
    curCells = {currentMaps};
else
    if ~iscell(refMaps),     refMaps     = {refMaps};     end
    if ~iscell(currentMaps), currentMaps = {currentMaps}; end
    nM = max(numel(refMaps), numel(currentMaps));
    refCells = cell(1,nM); curCells = cell(1,nM);
    for m = 1:nM
        refCells{m} = []; curCells{m} = [];
        if m <= numel(refMaps)     && ~isempty(refMaps{m}),     refCells{m} = refMaps{m};     end
        if m <= numel(currentMaps) && ~isempty(currentMaps{m}), curCells{m} = currentMaps{m}; end
    end
end
nM = numel(refCells);

% -------- sizes & unify reference width across modalities --------
k_ref_mod = zeros(1,nM);
k_src_mod = zeros(1,nM);
for m = 1:nM
    if isempty(refCells{m}), refCells{m} = zeros(size(curCells{m},1), 0); end
    if isempty(curCells{m}), curCells{m} = zeros(size(refCells{m},1), 0); end
    k_ref_mod(m) = size(refCells{m},2);
    k_src_mod(m) = size(curCells{m},2);
end
if any(k_ref_mod ~= k_ref_mod(1))
    Ktgt = max(k_ref_mod);
    for m = 1:nM
        if k_ref_mod(m) < Ktgt
            refCells{m} = [refCells{m}, sparse(size(refCells{m},1), Ktgt - k_ref_mod(m))];
            k_ref_mod(m) = Ktgt;
        end
    end
end
K_ref     = k_ref_mod(1);
K_src_max = max(k_src_mod);

% equal weights over modalities
w = ones(1, nM); w = w / sum(w);

% ========= PASS 1: similarities & Hungarian (with cutoff) =========
[S_signed, S_abs] = aggregate_similarity(refCells, curCells, metric, w, K_ref, K_src_max);
[assignmentVec, signCorrections] = hungarian_with_cutoff(S_signed, S_abs, cutoff);

% unmatched shared source indices (by shared j)
used = false(1, K_src_max);
used(assignmentVec(assignmentVec>0)) = true;
unmatched_shared = find(~used);

% ========= Growth policy: append ALL unmatched shared source columns =========
refMapsUpdated = refCells;
if ~isempty(unmatched_shared)
    for idx = 1:numel(unmatched_shared)
        j = unmatched_shared(idx);
        for m = 1:nM
            Cm = curCells{m};
            if j <= size(Cm,2)
                refMapsUpdated{m} = [refMapsUpdated{m}, Cm(:, j)];
            else
                refMapsUpdated{m} = [refMapsUpdated{m}, sparse(size(refMapsUpdated{m},1),1)];
            end
        end
    end
    % sizes change
    K_ref = size(refMapsUpdated{1},2);
    fprintf('\n\t\t\t[Aligner] Added %d unmatched component%s from source (%g components) to reference (now %d total in reference). Method=%s, cutoff=%.3g', ...
        numel(unmatched_shared), char('s'*(numel(unmatched_shared)~=1)), K_src_max, K_ref, upper(metric), cutoff);

    % ========= PASS 2: similarities & Hungarian after growth =========
    [S_signed, S_abs] = aggregate_similarity(refMapsUpdated, curCells, metric, w, K_ref, K_src_max);
    [assignmentVec, signCorrections] = hungarian_with_cutoff(S_signed, S_abs, cutoff);
end
similarityMatrix = S_signed;  % final pass (signed, aggregated)

% ========= groups per ref =========
groupsPerRef = cell(1, K_ref);
if collapseManyToOne
    % collapse all sources with |sim| >= cutoff
    for i = 1:K_ref
        js = find(isfinite(S_abs(i,:)) & (S_abs(i,:) >= cutoff));
        groupsPerRef{i} = js(:)';
    end
else
    % old policy: winner only
    for i = 1:K_ref
        j = assignmentVec(i);
        if j > 0, groupsPerRef{i} = j; else, groupsPerRef{i} = []; end
    end
end

% ========= Per-pair robust sign on COMBINED vectors =========
sign_pair = zeros(K_ref, K_src_max); % -1, 0, +1
for i = 1:K_ref
    ref_vec = combine_vec(refMapsUpdated, i);
    for j = 1:K_src_max
        src_vec = combine_vec(curCells, j);
        if isempty(src_vec), sign_pair(i,j) = 0; continue; end
        sim_ij = combined_similarity(ref_vec, src_vec, metric);
        if isfinite(sim_ij) && sim_ij ~= 0
            sign_pair(i,j) = sign(sim_ij);
        else
            sign_pair(i,j) = 0;
        end
    end
end

% ========= Build sorted maps (winner-only or collapsed mean), using per-pair sign =========
sortedMaps = refMapsUpdated;  % retain per-modality shape
for m = 1:nM
    Fm = size(refMapsUpdated{m},1);
    Cm = curCells{m};
    out = nan(Fm, K_ref);
    for i = 1:K_ref
        js = groupsPerRef{i};
        if isempty(js), continue; end
        if ~collapseManyToOne
            % winner-only, single signed column
            j = js(1);
            if j <= size(Cm,2) && sign_pair(i,j) ~= 0
                out(:, i) = sign_pair(i,j) .* Cm(:, j);
            else
                out(:, i) = NaN;
            end
        else
            % collapse mean over multiple signed columns
            cols = nan(Fm, numel(js));
            for t = 1:numel(js)
                j = js(t);
                if j <= size(Cm,2) && sign_pair(i,j) ~= 0
                    cols(:,t) = sign_pair(i,j) .* Cm(:, j);
                end
            end
            out(:, i) = mean(cols, 2, 'omitnan');
        end
    end
    sortedMaps{m} = out;
end

% ========= Correlation per ref vs signed (winner/collapsed) source (non-negative) =========
corrPerComp = nan(1, K_ref);
for i = 1:K_ref
    ref_vec = combine_vec(refMapsUpdated, i);
    src_vec = combine_vec(sortedMaps, i);
    sim = combined_similarity(ref_vec, src_vec, metric);
    if isfinite(sim), corrPerComp(i) = abs(sim); end
end

% ========= unmatchedComponents output (w.r.t. final assignment) =========
used_final = false(1, K_src_max);
used_final(assignmentVec(assignmentVec>0)) = true;
unmatched_shared_final = find(~used_final);
unmatchedComponents = cell(1, nM);
for m = 1:nM
    Cm = curCells{m};
    keep = unmatched_shared_final(unmatched_shared_final <= size(Cm,2));
    if isempty(keep)
        unmatchedComponents{m} = Cm(:, []);
    else
        unmatchedComponents{m} = Cm(:, keep);
    end
end

% ========= unwrap single-modality outputs =========
if ~isMulti
    sortedMaps          = sortedMaps{1};
    unmatchedComponents = unmatchedComponents{1};
    refMapsUpdated      = refMapsUpdated{1};
end

end % ===== end main =====


% ============================ helpers ============================
function [S_signed, S_abs] = aggregate_similarity(refCells, curCells, metric, w, K_ref, K_src_max)
% Aggregated per-ref×shared-j similarity (signed and abs), synchronized across modalities.
nM = numel(refCells);
S_signed = nan(K_ref, K_src_max);
S_abs    = nan(K_ref, K_src_max);
for j = 1:K_src_max
    avail = false(1,nM);
    for m = 1:nM
        avail(m) = (j <= size(curCells{m},2));
    end
    idx = find(avail);
    if isempty(idx), continue; end
    s_signed = zeros(K_ref,1);
    s_abs    = zeros(K_ref,1);
    wsum     = 0;
    for t = 1:numel(idx)
        m = idx(t);
        Sm = local_similarity(refCells{m}, curCells{m}, metric); % [K_ref x K_src_m]
        wm = w(m);
        col = Sm(:, j);
        s_signed = s_signed + wm * col;
        s_abs    = s_abs    + wm * abs(col);
        wsum     = wsum + wm;
    end
    if wsum > 0
        S_signed(:, j) = s_signed / wsum;
        S_abs(:, j)    = s_abs    / wsum;
    end
end
end

function [assignmentVec, signCorrections] = hungarian_with_cutoff(S_signed, S_abs, cutoff)
% Hungarian on negative abs-sim; apply cutoff to accept match.
K_ref = size(S_abs,1);
C = -S_abs;
C(~isfinite(C)) = +1e6;
[assignLog, ~] = munkres(C);
assignmentVec   = zeros(1, K_ref);
signCorrections = zeros(1, K_ref);
for i = 1:K_ref
    j = find(assignLog(i,:), 1, 'first');
    if ~isempty(j) && isfinite(S_abs(i,j)) && S_abs(i,j) >= cutoff
        assignmentVec(i)   = j;
        sgn = S_signed(i,j);
        if isfinite(sgn) && sgn ~= 0
            signCorrections(i) = sign(sgn);
        else
            signCorrections(i) = 0;
        end
    end
end
end

function S = local_similarity(A, B, metric)
% Per-modality similarity between columns of A (ref) and B (current): [R x S]
if isempty(A) || isempty(B)
    S = zeros(size(A,2), size(B,2));
    return
end
switch metric
    case 'euclidean'
        Au = A ./ max(vecnorm(A,2,1), eps);
        Bu = B ./ max(vecnorm(B,2,1), eps);
        D  = pdist2(Au', Bu', 'euclidean');  % [R x S]
        S  = 1 - D/2;
    case 'pearson'
        mx = mean(A,'omitnan'); my = mean(B,'omitnan');
        Ac = A - mx; Bc = B - my;
        Ma = isfinite(Ac); Ac(~Ma) = 0;
        Mb = isfinite(Bc); Bc(~Mb) = 0;
        num = Ac' * Bc;
        sx2 = sum(Ac.^2,1); sy2 = sum(Bc.^2,1);
        den = sqrt(sx2') * sqrt(sy2);
        cnt = double(Ma)' * double(Mb);
        S   = zeros(size(num));
        vld = (cnt > 1) & (den > eps);
        S(vld) = num(vld) ./ den(vld);
    case 'spearman'
        S = corr(A, B, 'Type','Spearman', 'Rows','complete');
    case 'cosine'
        A0 = A; B0 = B; A0(~isfinite(A0)) = 0; B0(~isfinite(B0)) = 0;
        S = (A0' * B0) ./ (sqrt(sum(A0.^2))' * sqrt(sum(B0.^2)));
    case 'bicor'
        S = bicor_matrix(A, B, 12);
end
S(~isfinite(S)) = 0;
end

function v = combine_vec(cells, col)
% Concatenate column 'col' across modalities (NaN padded where absent).
nM = numel(cells);
v = [];
for m = 1:nM
    M = cells{m};
    if isempty(M) || col > size(M,2)
        v = [v; nan(size(M,1),1)];
    else
        v = [v; M(:, col)];
    end
end
end

function sim = combined_similarity(ref_vec, src_vec, metric)
% Similarity on concatenated vectors; NaN-safe.
switch metric
    case 'euclidean'
        a = ref_vec ./ max(norm(ref_vec,2), eps);
        b = src_vec ./ max(norm(src_vec,2), eps);
        sim = 1 - norm(a-b)/2;
    case 'pearson'
        sim = corr(ref_vec, src_vec, 'Type','Pearson', 'Rows','complete');
    case 'spearman'
        sim = corr(ref_vec, src_vec, 'Type','Spearman', 'Rows','complete');
    case 'cosine'
        a = ref_vec; b = src_vec; a(~isfinite(a))=0; b(~isfinite(b))=0;
        sim = dot(a,b) / (sqrt(dot(a,a))*sqrt(dot(b,b)) + eps);
    case 'bicor'
        sim = bicor_matrix(ref_vec, src_vec, 12);
end
end

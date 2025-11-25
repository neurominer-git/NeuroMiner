function [sortedMaps, unmatchedComponents, assignmentVec, corrPerComp, signCorrections, similarityMatrix, refMapsUpdated, groupsPerRef, sign_pair] = ...
         nk_AlignCompAndSignCorrect(refMaps, currentMaps, cutoff, metric, collapseManyToOne, unitnorm)
% nk_AlignCompAndSignCorrect — drop-in replacement (output-identical, faster)
% Align & sign-correct currentMaps columns to refMaps (single or multi-modality).
global CVPOS
if nargin < 3 || isempty(cutoff), cutoff = 0.3; end
if nargin < 4 || isempty(metric), metric  = 'pearson'; end
if nargin < 5 || isempty(collapseManyToOne), collapseManyToOne = false; end
if nargin < 6 || isempty(unitnorm), unitnorm = true; end
metric = validatestring(lower(metric), {'euclidean','pearson','pearson_dice','cosine','spearman','bicor'});
%refpath = sprintf('RefData_%s_CV2-%g-%g_CV1-%g-%g.mat',CVPOS.mode, CVPOS.CV2p, CVPOS.CV2f, CVPOS.CV1p, CVPOS.CV1f);
%if isfield(CVPOS,'mode') && strcmp(CVPOS.mode,'loaded'); debug = true; else, debug = false; end
%debug = false; freshdata = [];
%freshdata = compare_fresh_vs_load(freshdata, 'line 14');

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
%compare_fresh_vs_load(freshdata, 'line 33');

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
            refCells{m} = [refCells{m}, nan(size(refCells{m},1), Ktgt - k_ref_mod(m))];
            k_ref_mod(m) = Ktgt;
        end
    end
end
K_ref     = k_ref_mod(1);
K_src_max = max(k_src_mod);

%compare_fresh_vs_load(freshdata,'line 56');

% equal weights over modalities
w = ones(1, nM); w = w / sum(w);

% ========= PASS 1: similarities & Hungarian (with cutoff) =========
[S_signed, S_abs] = aggregate_similarity(refCells, curCells, metric, w, K_ref, K_src_max, unitnorm);
[assignmentVec, signCorrections] = hungarian_with_cutoff(S_signed, S_abs, cutoff);

%compare_fresh_vs_load(freshdata, 'line 65');

% unmatched shared source indices (by shared j)
used = false(1, K_src_max);
used(assignmentVec(assignmentVec>0)) = true;
has_viable = any(isfinite(S_abs) & (S_abs >= cutoff), 1);  % 1×K_src_max
unmatched_shared = find(~used & ~has_viable);

% ========= Growth policy: append ALL unmatched shared source columns =========
refMapsUpdated = refCells;
if ~isempty(unmatched_shared)
    for idx = 1:numel(unmatched_shared)
        j = unmatched_shared(idx);
        % assert all modalities have column j
        for m = 1:nM
            assert(j <= size(curCells{m},2), 'Invariant violated: modality #%g missing column %d.', m, j);
            refMapsUpdated{m} = [refMapsUpdated{m}, curCells{m}(:, j)];
        end
    end
    K_ref = size(refMapsUpdated{1},2);
    %compare_fresh_vs_load(freshdata, 'line 85');
    fprintf('\n\t\t\t[Aligner] Added %d unmatched component%s from source (%g components) to reference (now %d total in reference). Method=%s, cutoff=%.3g', ...
        numel(unmatched_shared), char('s'*(numel(unmatched_shared)~=1)), K_src_max, K_ref, upper(metric), cutoff);

    % ========= PASS 2: similarities & Hungarian after growth =========
    [S_signed, S_abs] = aggregate_similarity(refMapsUpdated, curCells, metric, w, K_ref, K_src_max, unitnorm);
    [assignmentVec, signCorrections] = hungarian_with_cutoff(S_signed, S_abs, cutoff);
    %compare_fresh_vs_load(freshdata, 'line 92');
end
similarityMatrix = S_signed;  % final pass (signed, aggregated)

% ========= groups per ref (winner-only or collapsed list) =========
groupsPerRef = cell(1, K_ref);
j_winner = zeros(1, K_src_max);
for i = 1:K_ref
    j = assignmentVec(i);
    if j > 0, j_winner(j) = i; end
end
if collapseManyToOne
    for j = 1:K_src_max
        col = S_abs(:, j);
        if ~any(isfinite(col)) || max(col) < cutoff, continue; end
        i_star = j_winner(j);
        if i_star == 0
            [~, i_star] = max(col);
        end
        groupsPerRef{i_star} = [groupsPerRef{i_star}, j];
    end
else
    for i = 1:K_ref
        j = assignmentVec(i);
        groupsPerRef{i} = (j > 0) * j;
        if j == 0, groupsPerRef{i} = []; end
    end
end
%compare_fresh_vs_load(freshdata, 'line 120');

% ========= Per-pair sign on concatenated vectors (exactly matches old combine_vec loop) =========
% Build concatenated matrices (sum of feature rows) with NaN padding to mimic combine_vec.
sumF = 0; Fmods = zeros(1,nM);
for m = 1:nM, Fmods(m) = size(refMapsUpdated{m},1); sumF = sumF + Fmods(m); end
RefAll = nan(sumF, K_ref);
CurAll = nan(sumF, K_src_max);
r0 = 0;
for m = 1:nM
    Fm = Fmods(m);
    if ~isempty(refMapsUpdated{m})
        RefAll(r0+(1:Fm), 1:size(refMapsUpdated{m},2)) = refMapsUpdated{m};
    end
    if ~isempty(curCells{m})
        CurAll(r0+(1:Fm), 1:size(curCells{m},2)) = curCells{m};
    end
    r0 = r0 + Fm;
end
S_sign_concat = similarity_kernel(RefAll, CurAll, metric, unitnorm);  % K_ref x K_src_max
sign_pair = zeros(size(S_sign_concat));
mask_fin = isfinite(S_sign_concat) & (S_sign_concat ~= 0);
sign_pair(mask_fin) = sign(S_sign_concat(mask_fin));  % -1/0/+1 exactly as before

% ========= Build sorted maps (winner-only or collapsed mean), output-identical =========
sortedMaps = refMapsUpdated;

if ~collapseManyToOne
    % ---- Winner-only: keep exact NaN structure of the chosen source column
    for m = 1:nM
        Fm = size(refMapsUpdated{m},1);
        Cm = curCells{m};
        out = nan(Fm, K_ref, 'like', refMapsUpdated{m});
        for i = 1:K_ref
            js = groupsPerRef{i};
            if isempty(js), continue; end
            j = js(1);
            if j <= size(Cm,2) && sign_pair(i,j) ~= 0
                out(:, i) = sign_pair(i,j) .* Cm(:, j);
            end
        end
        sortedMaps{m} = out;
    end
else
    % ---- Collapsed mean: exactly reproduce near-1 clamp, valid-mask, gamma, L1 norm, fallbacks, NaN handling.
    gamma = 1.5;      % keep original
    oneTol = 1e-4;    % near-1 clamp tolerance (identical to your code)

    for m = 1:nM
        Cm = curCells{m};                  % (F_m x K_src_max)
        Fm = size(refMapsUpdated{m},1);
        
        % Pre-count nonzeros to avoid sparse growth; then build I/J/V once
        nnz_total = 0;
        for i = 1:K_ref
            nnz_total = nnz_total + numel(groupsPerRef{i});
        end
        I = zeros(nnz_total,1);
        J = zeros(nnz_total,1);
        V = zeros(nnz_total,1);
        p = 1;

        refs_no_valid = false(1, K_ref);

        for i = 1:K_ref
            js = groupsPerRef{i};
            if isempty(js), continue; end

            s = sign_pair(i, js);
            viable = (s ~= 0);
            js = js(viable); s = s(viable);
            if isempty(js), continue; end

            % near-1 clamp on S_abs row (exactly as before)
            c_row = S_abs(i, :);
            idx_nearOne = (c_row >= 1-oneTol) & (c_row <= 1+oneTol);
            c_row(idx_nearOne) = 0;
            wj = c_row(js);

            % per-modality valid: at least one finite entry in this modality
            if ~isempty(Cm)
                valid = any(isfinite(Cm(:, js)), 1);
            else
                valid = false(size(js));
            end

            % identical masking & weighting semantics
            wj(~isfinite(wj) | wj < 0) = 0;
            wj = wj .* valid;

            wj = wj .^ gamma;
            sw = sum(wj);

            if sw > 0
                wj = wj / sw;
                k = numel(js);
                idx = p:(p+k-1);
                I(idx) = js(:);
                J(idx) = i;
                V(idx) = s(:) .* wj(:);
                p = p + k;
            else
                % fallback: equal weights over valid columns
                if any(valid)
                    js_valid = js(valid);
                    s_valid  = s(valid);
                    k = numel(js_valid);
                    eq = (1/k) * ones(k,1, 'like', V);
                    idx = p:(p+k-1);
                    I(idx) = js_valid(:);
                    J(idx) = i;
                    V(idx) = s_valid(:) .* eq;
                    p = p + k;
                else
                    % no valid columns in this modality for this ref: keep out(:,i)=NaN
                    refs_no_valid(i) = true;
                end
            end
        end

         % build sparse once
        I = I(1:p-1); J = J(1:p-1); V = V(1:p-1);
        if ~isempty(I)
            A_m = sparse(I, J, V, K_src_max, K_ref);
        
            if ~isempty(Cm)
                % NaN-safe sum under globally normalized weights: NaNs -> 0 for the product
                Cm_0 = Cm;
                Cm_0(~isfinite(Cm_0)) = 0;
        
                % ---- dense × dense multiply as before ----
                A_full = full(A_m);
                A_full = cast(A_full, 'like', Cm_0);
                prod = Cm_0 * A_full;              % candidate result (F_m x K_ref)
            else
                prod = nan(Fm, K_ref, 'like', refMapsUpdated{m});
            end
        else
            prod = nan(Fm, K_ref, 'like', refMapsUpdated{m});
        end
        
        % ---- reconstruct original NaN semantics ----
        % Start with all-NaN output
        out = nan(Fm, K_ref, 'like', refMapsUpdated{m});
        
        % refs with at least one assigned source
        has_group = ~cellfun(@isempty, groupsPerRef);   % 1 x K_ref logical
        
        % valid in this modality (not flagged as "no valid columns")
        valid_cols = has_group & ~refs_no_valid;        % 1 x K_ref
        
        % Only these columns should get numbers; others remain NaN
        out(:, valid_cols) = prod(:, valid_cols);
        
        sortedMaps{m} = out;
    end
end

% ========= Correlation per ref vs signed (winner/collapsed) source (non-negative) =========
corrPerComp = nan(1, K_ref);
for i = 1:K_ref
    ref_vec = combine_vec(refMapsUpdated, i);
    src_vec = combine_vec(sortedMaps, i);
    if ~nnz(isfinite(src_vec)), continue; end
    sim = similarity_kernel(ref_vec, src_vec, metric, unitnorm);
    if isfinite(sim), corrPerComp(i) = abs(sim); end
end

% ========= unmatchedComponents output (unchanged semantics: based on Hungarian winners) =========
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

% Save critical inputs and outputs of alignment procedure
% if isfield(CVPOS,'mode') && strcmp(CVPOS.mode,'fresh')
%     save(refpath,"refMaps", "refMapsUpdated", "currentMaps", "sortedMaps", "S_abs", "S_signed", "assignmentVec", "unmatchedComponents", "groupsPerRef", "sign_pair");
% end

    % function [fresh, mismatch] = compare_fresh_vs_load(fresh, position)
    %     mismatch = [];
    %     if strcmp(CVPOS.mode,'loaded') && debug 
    %         refpath_fresh = sprintf('RefData_fresh_CV2-%g-%g_CV1-%g-%g.mat', CVPOS.CV2p, CVPOS.CV2f, CVPOS.CV1p, CVPOS.CV1f);
    %         if isempty(fresh), fresh = load(refpath_fresh); end
    %         if ~isequaln(single(fresh.refMaps{1}), refMaps{1}), mismatch.RefMaps_have_mismatch = true; end
    %         if ~isequaln(single(fresh.currentMaps{1}), currentMaps{1}), mismatch.currentMap_have_mismatch = true; end
    %         if exist("refMapsUpdated","var") && ~isequaln(single(fresh.refMapsUpdated{1}), refMapsUpdated{1}), mismatch.RefMapsUpdated_have_mismatch = true; end
    %         if exist("sortedMaps","var") && ~isequaln(fresh.sortedMaps{1}, sortedMaps{1}), mismatch.sortedMaps_have_mismatch = true; end
    %         if exist("S_abs","var") && ~isequaln(fresh.S_abs, S_abs), mismatch.S_abs_have_mismatch = true; end
    %         if exist("S_signed","var") && ~isequaln(fresh.S_signed, S_signed), mismatch.S_signed_have_mismatch = true; end
    %         if exist("assignmentVec","var") && ~isequaln(fresh.assignmentVec, assignmentVec), mismatch.assignmentVec_have_mismatch = true; end
    %         if exist("unmatchedComponents","var") && ~isequaln(fresh.unmatchedComponents, unmatchedComponents{1}), mismatch.unmatchedComponents_have_mismatch = true; end
    %         if exist("groupsPerRef","var") && ~isequaln(fresh.groupsPerRef, groupsPerRef{1}), mismatch.groupsPerRef_have_mismatch = true; end
    %         if ~isempty(mismatch)
    %             mismatchstr = sprintf('\nWe have a problem with at %s ...:', position);
    %             f = fieldnames(fresh); nf = numel(f);
    %             for ff = 1:nf
    %                 if mismatch.(f{ff})
    %                     mismatchstr = sprintf('\n\t%s',ff{f});
    %                 end
    %             end
    %             disp(mismatchstr);
    %             error('Mismatch detected!!!')
    %         end
    %     end
    % end

end % ===== end main =====

% ============================ helpers (unchanged behavior) ============================
function [S_signed, S_abs] = aggregate_similarity(refCells, curCells, metric, w, K_ref, K_src, unitnorm)
    nM = numel(refCells);
    S_signed = zeros(K_ref, K_src);
    S_abs    = zeros(K_ref, K_src);
    for m = 1:nM
        Sm = similarity_kernel(refCells{m}, curCells{m}, metric, unitnorm); % [K_ref x K_src]
        S_signed = S_signed + w(m) * Sm;
        S_abs    = S_abs    + w(m) * abs(Sm);
    end
end

function [assignmentVec, signCorrections] = hungarian_with_cutoff(S_signed, S_abs, cutoff)

    K_ref = size(S_abs,1);

    % Build cost matrix: we want to maximize |similarity| -> minimize negative |similarity|
    C = -S_abs;
    C(~isfinite(C)) = +1e6;   % large positive cost for invalid entries (as before)

    % munkres now returns a vector, not a logical matrix
    [assignRow, ~] = munkres(C);   % 1 x K_ref, assignRow(i)=j or 0

    assignmentVec   = zeros(1, K_ref);
    signCorrections = zeros(1, K_ref);

    for i = 1:K_ref
        j = assignRow(i);         % column assigned to row i (or 0 if none)

        if j > 0 && isfinite(S_abs(i,j)) && S_abs(i,j) >= cutoff
            assignmentVec(i) = j;
            sgn = S_signed(i,j);
            if isfinite(sgn) && sgn ~= 0
                signCorrections(i) = sign(sgn);
            else
                signCorrections(i) = 0;
            end
        else
            % below cutoff or unassigned → keep as 0
            % assignmentVec(i) = 0; signCorrections(i) = 0;  % already zero-initialized
        end
    end
end


function v = combine_vec(cells, col)
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

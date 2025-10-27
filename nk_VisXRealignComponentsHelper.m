function [I1, Tx_out, Tx_unmatched, assignmentVec, signCorrections, VCV1REF] = ...
            nk_VisXRealignComponentsHelper(I1, inp, haveRef, Tx_in, VCV1REF, nM, il, ill, currmodal, h, Fadd, Vind)

global SVM

isInter = ~isempty(currmodal);
if ~isInter, currmodal = 1; Vind = ones(numel(Fadd),1); end

%% ---------- One call: realign (+ possibly grow ref) in blk-diag space ----------
if haveRef
    [Tx_out, Tx_unmatched, assignmentVec, corrPerComp, signCorrections, ~, refUpdated] = ...
        nk_AlignCompAndSignCorrect(VCV1REF, Tx_in, inp.simCorrThresh, inp.simCorrMethod);

    % Cache updated reference (per-modality cells)
    VCV1REF = refUpdated;
    % Unified component count across modalities (must match by construction)
    if ~iscell(VCV1REF)
        colsPerMod = size(VCV1REF,2);
    else
        colsPerMod = cellfun(@(R) size(R,2), VCV1REF(:)');
    end
    if ~isInter
        assert(all(colsPerMod == colsPerMod(1)), 'Ref columns must be equal across modalities after unified alignment.');
    end
    nRef_combined  = colsPerMod(1);
else
    % First time ever: seed with current kept maps; identity alignment
    VCV1REF       = Tx_in;
    Tx_out        = Tx_in;
    Tx_unmatched  = [];
    if ~iscell(VCV1REF)
        colsPerMod = size(VCV1REF,2);
    else
        colsPerMod = cellfun(@(R) size(R,2), VCV1REF(:)');
    end
    nRef_combined = colsPerMod(1);
    assignmentVec = (1:nRef_combined).';
    signCorrections = ones(nRef_combined,1);
    corrPerComp   = ones(nRef_combined,1);
    if isInter
        fprintf('\n\t\t\tDefine reference space for modality #%g consisting of %g component(s).', currmodal, colsPerMod(1));
    else
        fprintf('\n\t\t\tDefine reference space consisting of %g component(s).', colsPerMod(1));
    end
end

%% ---------- Ensure I1 destination containers exist *now* ----------
if isInter
    % Early fusion: operating accross modalities => mapping to one
    % container
    need_bootstrap = ( isempty(I1.VCV1WPERMREF{h})     || isempty(I1.VCV1WPERMREF{h}{currmodal}) )   || ...
                     ( isempty(I1.VCV1WCORRREF{h})     || isempty(I1.VCV1WCORRREF{h}{currmodal}) )   || ...
                     ( isempty(I1.ModComp_L2n{h})      || isempty(I1.ModComp_L2n{h}{currmodal}) );
else
    need_bootstrap = ( isempty(I1.VCV1WPERMREF{h}))    || ...
                     ( isempty(I1.VCV1WCORRREF{h}))    || ...
                     ( isempty(I1.ModComp_L2n{h}));
end

%% Create containers or copy from I1
if need_bootstrap
    VCV1WPERMREF    = nan(nRef_combined, ill);
    VCV1WCORRREF    = nan(nRef_combined, ill);
    ModComp_L2n     = nan(nRef_combined, ill);
    if nM>1
        if ~isInter
            ModComp_L2nCube = nan(nRef_combined, nM, ill); 
        end
    end
else
    if ~isInter
        VCV1WPERMREF    =  I1.VCV1WPERMREF{h};
        VCV1WCORRREF    =  I1.VCV1WCORRREF{h};
        ModComp_L2n     =  I1.ModComp_L2n{h};
        if nM>1
            ModComp_L2nCube =  I1.ModComp_L2nCube{h}; 
        end
    else
        VCV1WPERMREF    = I1.VCV1WPERMREF{h}{currmodal};
        VCV1WCORRREF    = I1.VCV1WCORRREF{h}{currmodal};
        ModComp_L2n     = I1.ModComp_L2n{h}{currmodal};
    end
end

%% ---------- Grow containers if ref got longer ----------
if size(VCV1WPERMREF,1) < nRef_combined, VCV1WPERMREF(end+1:nRef_combined,:) = NaN; end
if size(VCV1WCORRREF,1) < nRef_combined, VCV1WCORRREF(end+1:nRef_combined,:) = NaN; end
if size(ModComp_L2n,1) < nRef_combined, ModComp_L2n(end+1:nRef_combined,:) = NaN;  end
if ~isInter && nM>1
    [s1, s2, s3] = size(ModComp_L2nCube);
    if s1 < nRef_combined, ModComp_L2nCube = cat(1, ModComp_L2nCube, nan(nRef_combined - s1, s2, s3)); end
    if s3 < ill, ModComp_L2nCube = cat(3, ModComp_L2nCube, nan(size(ModComp_L2nCube,1), s2, ill - s3)); end
end

%% ---------- p-values and correlations (component-level, modality-agnostic) ----------
% p values
p_src_sig = I1.VCV1WPERM{h}(Fadd & (Vind == currmodal), il(h)); % compressed (sig-only)
mask_ref   = assignmentVec > 0 & assignmentVec <= numel(p_src_sig);
idx_pruned = assignmentVec(mask_ref);     % indices in p_src_sig
p_ref = nan(numel(assignmentVec),1);
p_ref(mask_ref) = p_src_sig(idx_pruned);
VCV1WPERMREF(1:nRef_combined, il(h)) = p_ref;
% correlations
c = corrPerComp(:);
oneTol = 1e-6; idx_nearOne = (c >= 1-oneTol) & (c <= 1+oneTol); c(idx_nearOne) = NaN;
VCV1WCORRREF(1:nRef_combined, il(h)) = c;

%% ---------- L2 magnitudes (two views, depending on fusion mode) ----------
% Tx_out is:
%   - EARLY fusion: cell(1,nM), each Tx_out{n} is [nFeat_n x nRef_combined] in reference order
%   - INTER fusion: a single matrix [nFeat_curr x nRef_combined] for the current modality

if ~isInter
    % ---------- EARLY FUSION ----------
    % 1) Per-modality L2 vectors in reference order
    %    (nan-aware columnwise L2; result is [nRef_combined x nM])
    L2_ref_mod = nan(nRef_combined, nM);
    for n = 1:nM
        Xn = Tx_out{n};                           % [nFeat_n x nRef_combined] in ref order
        if ~isempty(Xn)
            v = nk_VisXComputeLpShares(Xn, SVM, false); % [1 x nRef_combined] or [nRef_combined x 1]
            if isrow(v), v = v(:); end
            L2_ref_mod(1:numel(v), n) = v(1:min(numel(v), nRef_combined));
        end
    end

    % 2) Combined per-component L2 across modalities (sum over nM)
    L2_ref_combined = sum(L2_ref_mod, 2, 'omitnan');   % [nRef_combined x 1]

    % (a) Global per-component stats
    ModComp_L2n(1:nRef_combined, il(h)) = L2_ref_combined;

    if nM > 1
        % (b) Per-modality cube (component x modality x fold)
        for n = 1:nM
            ModComp_L2nCube(1:nRef_combined, n, il(h)) = L2_ref_mod(:, n);
        end
    end
else
    % ---------- INTERMEDIATE FUSION (per-DR modality handled in its own call) ----------
    % Tx_out is this modality’s ref-ordered map: [nFeat_curr x nRef_combined]
    if ~isempty(Tx_out)
        v = nk_VisXComputeLpShares(Tx_out, SVM, false);                % per-component L2, [nRef_combined x 1]
        if isrow(v), v = v(:); end
    else
        v = nan(nRef_combined,1);
    end

    % Store this modality’s per-component magnitudes
    ModComp_L2n(1:nRef_combined, il(h)) = v;
end

%% ---------- Copy back containers to I1 -----------
if isInter
    I1.VCV1WPERMREF{h}{currmodal} = VCV1WPERMREF;
    I1.VCV1WCORRREF{h}{currmodal} = VCV1WCORRREF;
    I1.ModComp_L2n{h}{currmodal} = ModComp_L2n;
else
    I1.VCV1WPERMREF{h} = VCV1WPERMREF;
    I1.VCV1WCORRREF{h} = VCV1WCORRREF;
    I1.ModComp_L2n{h} = ModComp_L2n;
    if nM>1, I1.ModComp_L2nCube{h} = ModComp_L2nCube; end
end
function [I, I1, Tx, Psel, Rx, SRx, PAx, assignmentVec, signCorrections] = ...
    nk_VisXRealignComponents(I, I1, h, Tx, Psel, Rx, SRx, PAx, Fadd, Vind, il, inp, nM, ill)
% nk_VisXRealignComponents
% Helper extracted from nk_VisModelsC.m — GLOBAL (CROSS-MODALITY) REALIGNMENT
%
% Returns updated I / I1 containers and working variables exactly as in the inline block.
%
% Dependencies (same as your original block):
%   - nk_AlignCompAndSignCorrect
%   - nan_l2n_block
%   - nm_nansum

    isInter = inp.isInter;

    % inp.decompfl is a logical/boolean vector (1 x nM or nM x 1) indicating DR-modalities
    if isInter
        assert(isfield(inp,'decompfl') && numel(inp.decompfl) >= nM, ...
            'Intermediate fusion requires inp.decompfl (length nM).');
        modMask = inp.decompfl(:);   % 1 x nM logical
    else
        modMask = true(1, nM);                  % early fusion: all modalities active
    end
    nonZeroMasks = cell(nM,1);
    %% ---------- 1) Prune empty/NaN columns modality-wise, collect shapes ----------
    for n = 1:nM
        if ~modMask(n)
            % Non-DR modality in intermediate fusion -> leave as-is (ignored downstream)
            nonZeroMasks{n} = false(1,0);
            continue;
        end
        nz               = any((Tx{n}~=0) & isfinite(Tx{n}), 1);
        nonZeroMasks{n}  = nz;
        Tx{n}            = Tx{n}(:, nz);
    
        % keep siblings pruned the same way if they exist
        if exist('Psel','var') && ~isempty(Psel) && ~isempty(Psel{n}), Psel{n} = Psel{n}(:, nz); end
        if exist('Rx','var')   && ~isempty(Rx)   && ~isempty(Rx{n}),   Rx{n}   = Rx{n}(:,   nz); end
        if exist('SRx','var')  && ~isempty(SRx)  && ~isempty(SRx{n}),  SRx{n}  = SRx{n}(:,  nz); end
        if exist('PAx','var')  && ~isempty(PAx)  && ~isempty(PAx{n}),  PAx{n}  = PAx{n}(:,  nz); end
    end

    if isInter
        assignmentVec = cell(nM,1);
        signCorrections = cell(nM,1);
        for n=1:nM
            if ~modMask(n), fprintf('\n\t\t\tNo dimensionality reduction involved in the processing of modality #%g', n); continue; end
            haveRef = isfield(I,'VCV1REF') && numel(I.VCV1REF) >= h && numel(I.VCV1REF{h}) >=n && ~isempty(I.VCV1REF{h}{n});
            % Ensure the cached ref cell exists and is length nM (placeholders for inactive)
            if ~haveRef, I.VCV1REF{h}{n} = {[]}; end
            [I1, Tx{n}, ~, assignmentVec{n}, signCorrections{n}, I.VCV1REF{h}{n}] = nk_VisXRealignComponentsHelper(I1, inp, haveRef, Tx{n}, I.VCV1REF{h}{n}, nM, il, ill, n, h, Fadd, Vind);
        end
    else
        haveRef = isfield(I,'VCV1REF') && numel(I.VCV1REF) >= h && ~isempty(I.VCV1REF{h});    
        if ~haveRef, I.VCV1REF{h} = []; end
        [I1, Tx, ~, assignmentVec, signCorrections, I.VCV1REF{h}] = nk_VisXRealignComponentsHelper(I1, inp, haveRef, Tx, I.VCV1REF{h}, nM, il, ill, [], h, Fadd, Vind);
    end

end

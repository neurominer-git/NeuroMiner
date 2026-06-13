function [ mW, mP, mR, mSR, mC, W, mPA, mD ] = nk_VisXWeightC(inp, MD, Y, L, varind, P, F, VI, decompfl, memprob, procfl, compwise, Fadd, for_share, Yts)
% =========================================================================
% [mW, mP, mR, mSR, mC, W, mPA ] = nk_VisXWeightC(inp, MD, Y, L, varind, ...
%                                          P, F, VI, decompfl, memprob, procfl, Fadd)
% =========================================================================
%   Prepare model weights for visualisation by:
%     - Splitting the global weight vector W into modality-specific
%       sub-vectors.
%     - Optionally reversing preprocessing / DR steps (back-projection)
%       to obtain aggregated or component-wise maps in input space.
%     - Computing *fractionated decision scores* mD in DR space:
%       per-subject × per-component decision contributions for CV2
%       subjects, aligned with the current discriminative PCA / DR space.
%
%   This function is used by the vis pipeline (nk_Vis* functions) for
%   early and intermediate fusion. For DR-based models, the modality-
%   specific eigenscores (modelTs) from the CV2 test set are used to
%   decompose the model decision into component-specific contributions.
%
% SYNTAX:
%   [mW, mP, mR, mSR, mC, W, mPA, mD] = nk_VisXWeightC( ...
%       inp, MD, Y, L, varind, P, F, VI, decompfl, memprob, procfl, ...
%       compwise, Fadd, for_share, modelTs )
%
% INPUT:
%   inp        : main input/option struct for the current analysis.
%   MD         : model descriptor for the current classifier (one
%                dichotomizer / repetition / CV2 partition), including
%                preprocessing and DR (e.g. PCA) information.
%   Y          : label vector (training + test) used in this model.
%   L          : logical index / partition labels corresponding to Y.
%   varind     : index of the current parameter combination / model.
%   P          : parameter struct for the current model (e.g. PCA params).
%   F          : logical vector marking active reduced-space dimensions
%                (features actually used by the model) in the global DR
%                space.
%   VI         : integer vector assigning each reduced-space dimension to a
%                modality (same length as F). Used to split W into
%                modality-specific weight vectors.
%   decompfl   : 1×nM logical array; decompfl(n) indicates that DR
%                (e.g. PCA) is active for modality n and that component-
%                wise back-projection / decomposition should be performed.
%   memprob    : memory / precision settings used by the vis pipeline.
%   procfl     : (optional) flag controlling whether full reversal of
%                preprocessing (back-projection to input space) is
%                attempted. When false, only reduced-space quantities are
%                prepared. (Semantics unchanged from previous versions.)
%   compwise   : flag for component-wise vis mode (one map per component),
%                as opposed to a single aggregate weight map.
%   Fadd       : additional feature mask to be combined with F for vis
%                purposes (e.g. to include previously dropped components).
%   for_share  : flag indicating whether the result is prepared for
%                sharing across CV folds (global reference space).
%   Yts        : CV2 test data features in model space (currently only DR) 
%                for the current classifier:
%                  - rows: CV2 test subjects used in this vis run
%                  - cols: active reduced-space dimensions (matching F)
%                For early fusion, this is typically a single matrix with
%                all DR components. For intermediate fusion, it may be a
%                single matrix (to be split by VI) or already a cell array
%                per modality. If empty, no fractionated decision scores
%                are computed and Dx = [].
%
% OUTPUT:
%   mW   : 1×nM cell array; mW{n} is a [F_n × K_n] matrix of modality-
%          specific component maps (weights) after reversing preprocessing
%          as far as requested (e.g. back-projected to input/voxel space
%          in DR-based models when procfl/compwise allow it).
%
%   mP   : 1×nM cell array; mP{n} encodes the component indices / mapping
%          used when constructing mW{n} from the original reduced-space
%          dimensions (selection / ordering information). 
%
%   mR   : 1×nM cell array; modality-specific correlation / redundancy
%          statistics for components (used for pruning / reporting in the
%          vis pipeline). 
%
%   mSR  : 1×nM cell array; summary statistics for mR (e.g. mean/median
%          redundancy). 
%
%   mC   : 1×nM cell array; additional component-level metrics (e.g.
%          component-wise performance / contribution) prepared for
%          downstream vis. 
%
%   W    : full weight vector in the *current* processed (reduced) space,
%          extended to all active reduced-space dimensions (matching F).
%          This is the same W used to derive mW and Dx.
%
%   mPA  : 1×nM cell array; modality-specific pattern-related information
%          (e.g. PCA loadings, projection matrices) as required by the vis
%          and back-projection routines. 
%
%   mD   : 1×nM cell array of fractionated decision scores for CV2
%          subjects in DR/model space:
%             Dx{n} is [nSubj_cv2 × K_n], where
%               - rows are CV2 subjects (same order as modelTs rows),
%               - columns are modality-specific DR components used by the
%                 model (matching the component indexing in mW{n} / mP{n}).
%
%          Each entry Dx{n}(s,k) represents the *per-component* contribution
%          of component k in modality n to the decision score of subject s:
%
%               Dx{n}(s,k) = modelTs(s,k_mod) * w_mod(k_mod)
%
%          where w_mod are the modality-specific model weights in DR space.
%          Summing Dx over all components and modalities (plus the model
%          bias) reconstructs the usual decision score:
%
%               DS(s) ≈ sum_n sum_k Dx{n}(s,k) + bias
%
%          For non-DR models (decompfl(n) == false) or when modelTs is
%          empty, Dx{n} is returned as [] for that modality.
%
% NOTES:
%   - mD is intended to be passed into nk_VisXRealignComponents in parallel
%     to mW (Tx), where the same alignment and sign-correction derived from
%     the component maps is applied to mD (Dx), yielding globally aligned,
%     per-subject fractionated decision scores ready for aggregation across
%     CV2 partitions.
%
% See also: nk_VisXRealignComponents, nk_AlignCompAndSignCorrect,
%           nk_VisModelsC, nk_GetTestPerf.
% =========================================================================
% (c) Nikolaos Koutsouleris, 11/2025

global SVM 
if ~exist('memprob','var') || isempty(memprob), memprob = false; end
if ~exist('procfl','var') || isempty(procfl), procfl = true; end
if ~exist('compwise','var') || isempty(compwise), compwise = false; end
if ~exist('Fadd','var') || isempty(Fadd), Fadd = true(size(F)); end
if ~exist('for_share','var') || isempty(for_share), for_share = false; end
computeFracDecScores = true; 
if ~exist('Yts', 'var') || isempty(Yts), Yts = []; computeFracDecScores = false; end
mPA = []; PA = []; warning off

% Get weight vector in the processed (possibly reduced) space.
[xV, AnalP] = nk_GetAlgoWeightVec(SVM, Y, L, MD, decompfl, true);
W = zeros(size(F,1),1);
W(F) = xV;
W(~Fadd)= 0;

% Process analytical P values.
if ~isempty(AnalP)
    PA = zeros(size(F,1),1);
    PA(F) = AnalP;
    PA(~Fadd) = 0;
end

Fu = F & Fadd;
nM = numel(inp.PREPROC);
mM = numel(inp.tF);

% Normalize weight vector for SVM (per Gaonkar et al. 2015). The default is
% no normalization because this interferes with permutation-based testing
% and results in unfair comparisons between observed and permuted weights
if inp.norm == 1 && any(strcmp({'LIBSVM','LIBLIN'},SVM.prog))
    W = W/(norm(W,2));
end

% Preallocate outputs for fusion.
mW = cell(1,mM); mD = []; 
if computeFracDecScores, if inp.isInter, mD = cell(1,mM); end; end

if ~isempty(PA)
    mPA = cell(1,mM);
end
mP = []; mR = []; mSR = []; mC = [];
if procfl
    mP = cell(1,mM); mR = cell(1,mM); mSR = cell(1,mM); mC = cell(1,nM);
end

% Loop through modalities.
for n = 1:nM    

    %-----------------------------------------------------------
    % Get preprocessing params for current modality
    %-----------------------------------------------------------
    if iscell(inp.PREPROC)
        nPREPROC = inp.PREPROC{n};
        nPX      = P{n};
    else
        nPREPROC = inp.PREPROC;
        nPX      = P;
    end
    
    %-----------------------------------------------------------
    % Get correct masks according to fusion mode
    %-----------------------------------------------------------
    if nM > 1
        % For intermediate fusion (concatenated feature spaces).
        lVI = VI == n;  
    else
        % For early fusion.
        lVI = true(size(Fu)); 
    end
    lFuVI = find(Fu(lVI)); 
    fVI = find(lVI); 
    nmP = Fu(fVI);

    %-----------------------------------------------------------
    % Aggregated weight vector for this modality
    %-----------------------------------------------------------
    nmW = zeros(numel(fVI),1); 
    nmW(nmP) = W(fVI(lFuVI));

    %-----------------------------------------------------------
    % FRACTIONATED DECISION SCORES (subjects x features)
    %-----------------------------------------------------------
    if decompfl(n) && ~isempty(Yts)
        % We only do this currently for DR-based models (decompfl(n)=true)
        % and when CV2 test subjects' factor scores (Yts) were provided.

        % All active reduced-space dims in the model
        cols_all = find(Fu);             % e.g. size = [K_totalDR x 1]

        % Reduced dims for THIS modality n that are active
        idx_mod = find(Fu & lVI);        % indices in full reduced-space index

        if isempty(idx_mod)
            mD{n} = [];  % no DR dims assigned to this modality
        else
            % Map idx_mod to column positions in modelTs.
            % Assumption: modelTs columns are ordered like cols_all = find(Fu).
            [~, colpos] = ismember(idx_mod, cols_all);
            colpos = colpos(colpos > 0);     % safety

            % DR scores for CV2 subjects, this modality only
            Zmod = Yts(:, colpos);       % [nSubj_cv2 x nModDRdims]

            % Corresponding weights (same dims)
            w_mod = W(idx_mod);              % [nModDRdims x 1]

            % Fractionated decision scores: D(s,k) = Zmod(s,k) * w_mod(k)
            mD{n} = bsxfun(@times, Zmod, w_mod(:).');   % [nSubj_cv2 x nModDRdims]
        end
    end
    
    %-----------------------------------------------------------
    % Get trained preprocessing parameters for current modality
    %-----------------------------------------------------------
    if ~isempty(PA)
         nmPA = nan(numel(fVI),1); 
         nmPA(nmP) = PA(lFuVI);
    end
    corr_mask = Fu(fVI);

    %-----------------------------------------------------------
    % MAP DATA BACK TO INPUT SPACE
    %-----------------------------------------------------------
    if procfl 
        if isfield(nPREPROC,'ACTPARAM')
            nA = numel(nPREPROC.ACTPARAM); 
        else
            nA = 0; 
        end

        for k = 1:nA
            preprocs{k,1} = nPREPROC.ACTPARAM{1,k}.cmd;
        end
        
        % Initialize flag for DR reversal.
        reducedimfl = false;  
        % When DR is applied, we will store component maps in matrices.
        % (Each matrix will be of size [numFeatures x numComponents].)
        % Initially, nmW, nmPA, and nmP are aggregated vectors.
        
        for a = nA:-1:1            
            if iscell(nPX{a})
                naPX = nPX{a}{1};
            else
                naPX = nPX{a};
            end
            
            switch nPREPROC.ACTPARAM{a}.cmd
                
                case 'scale'
                    % We only act once weights are in FEATURE space (after DR has been reversed).
                    if decompfl(n) && ~reducedimfl
                        % Scaling happened BEFORE DR in the forward pipeline, so we defer
                        % this until DR has been reversed.
                        continue
                    end
                    if for_share, continue; end
                    
                    % === Compute the forward slope a for each feature ===
                    % DO NOT use the "revert" path (that adds +min and multiplies by (max-min) for DATA).
                    % IN.ise in your scaler flags zero-variance features; emulate that:
                    if ~isfield(naPX,'ise')
                        naPX.ise = ~(naPX.minY == naPX.maxY);
                    end
                
                    switch naPX.ZeroOne
                        case 1   % scaled to [0,1] in forward pass:  z = (x - min)/(max - min)
                            ax = 1 ./ (naPX.maxY(:) - naPX.minY(:));
                        case 2   % scaled to [-1,1]:  z = 2*(x - min)/(max - min) - 1
                            ax = 2 ./ (naPX.maxY(:) - naPX.minY(:));
                        otherwise
                            error('Unsupported ZeroOne mode in SCALE (expected 1 or 2).');
                    end
                
                    % Avoid inf/NaN for zero-variance features
                    ax(~naPX.ise(:)) = 0;
                
                    % === Apply slope to WEIGHTS (no offset), broadcasting across components ===
                    if ismatrix(nmW) && size(nmW,2) > 1
                        nmW = bsxfun(@times, nmW, ax);      % [nFeat×nComp]
                        if exist('nmPA','var') && ~isempty(nmPA)
                            nmPA = bsxfun(@times, nmPA, ax);
                        end
                    else
                        nmW = nmW .* ax;                     % [nFeat×1]
                        if exist('nmPA','var') && ~isempty(nmPA)
                            nmPA = nmPA .* ax;
                        end
                    end

                case {'reducedim','remvarcomp'}
                    % DR branch: perform component-wise back-projection.
                    if isfield(naPX,'recon') && naPX.recon==1
                        fprintf('-');
                    else
                        % Retrieve reconstruction matrix.
                        if isfield(naPX.mpp,'vec')
                           redvec = naPX.mpp.vec;
                        elseif isfield(naPX.mpp,'factors')
                           redvec = naPX.mpp.factors{1};
                        elseif isfield(naPX.mpp,'u')
                           redvec = naPX.mpp.u;
                        elseif isfield(naPX.mpp,'M')
                           redvec = naPX.mpp.M;
                        elseif isfield(naPX.mpp,'W')
                           redvec = naPX.mpp.W;
                        elseif isfield(naPX.mpp,'network')
                           error('Autoencoder reconstructions not supported!')
                        end
                            
                        if isfield(naPX,'ind0')
                            ind0 = naPX.ind0;
                            DR = naPX.DR;
                        else
                            ind0 = 1:size(redvec,2);
                            DR = nPREPROC.ACTPARAM{a}.DR;
                        end
                        
                        mpp.vec = redvec(:,ind0);
                        
                         % -------------------- NEW: compwise vs aggregated DR --------------------
                        if compwise
                            % ===== component-wise path (unchanged logic) =====
                            switch DR.RedMode
                                case {'PCA','RobPCA','SparsePCA'}
                                    if strcmp(DR.RedMode,'RobPCA'), DRsoft = 1; else, DRsoft = DR.DRsoft; end
                                    numComponents = size(mpp.vec,2);
                                    if DRsoft == 0
                                        compMat = zeros(size(mpp.vec,1), numComponents);
                                        compPMat = []; if ~isempty(PA), compPMat = zeros(size(mpp.vec,1), numComponents); end
                                        for comp = 1:numComponents
                                            compMat(:, comp) = reconstruct_data(nmW(comp), struct('vec', mpp.vec(:,comp)));
                                            nmP(comp) = logical(reconstruct_data(nmP(comp), struct('vec', mpp.vec(:,comp))));
                                            if ~isempty(PA)
                                                compPMat(:, comp) = reconstruct_data(nmPA(comp), struct('vec', mpp.vec(:,comp)));
                                            end
                                        end
                                        nmW = compMat;
                                        if ~isempty(PA), nmPA = compPMat; end
                                    else
                                        nmW = mpp.vec * diag(nmW);
                                        nmP = logical(mpp.vec * diag(nmP));
                                        if ~isempty(PA), nmPA = mpp.vec * diag(nmPA); end
                                    end
                                case {'optNMF','NeNMF','NNMF','PLS','LPP','NPE','LLTSA','SPCA','PPCA','FA','FactorAnalysis','NCA','MCML','LMNN','fastICA'}
                                    numComponents = size(mpp.vec,2);
                                    nmW = mpp.vec * diag(nmW(1:numComponents));
                                    nmP = logical(mpp.vec * diag(nmP(1:numComponents)));
                                    if ~isempty(PA), nmPA = mpp.vec * diag(nmPA(1:numComponents)); end
                                otherwise
                                    error('Reconstruction of data is not supported for this technique.');
                            end
                        else
                            % ===== non-component DR (aggregated signature) =====
                            % Back-project the entire reduced-space vector to feature space in one go.
                            % Result: nmW is a single column vector in input space.
                            switch DR.RedMode
                                case {'PCA','RobPCA','SparsePCA', ...
                                      'optNMF','NeNMF','NNMF','PLS','LPP','NPE','LLTSA','SPCA','PPCA','FA','FactorAnalysis','NCA','MCML','LMNN','fastICA'}
                                    nmW = mpp.vec * nmW(:);              % [nFeat × 1]
                                    nmP = logical(mpp.vec * nmP(:));     % project mask & binarize (any contribution)
                                    if ~isempty(PA)
                                        nmPA = mpp.vec * nmPA(:);
                                    end
                                otherwise
                                    error('Reconstruction of data is not supported for this technique.');
                            end
                            corr_mask = logical(mpp.vec * corr_mask(:));
                        end
                        
                        % Feature re-introduction: if features were removed prior to DR,
                        % reintroduce them for each component.
                        if isfield(naPX,'indNonRem') && ~isempty(naPX.indNonRem) && sum(~naPX.indNonRem) > 0
                            % Create a new matrix with rows equal to length(naPX.indNonRem)
                            % and same number of columns as nmW.
                            tmW = zeros(length(naPX.indNonRem), size(nmW,2));
                            tmW(naPX.indNonRem, :) = nmW;
                            nmW = tmW;
                            tmP = false(length(naPX.indNonRem), size(nmW,2));
                            tmP(naPX.indNonRem, :) = nmP;
                            nmP = tmP;
                            if ~isempty(PA)
                                tmPA = zeros(length(naPX.indNonRem), size(nmW,2));
                                tmPA(naPX.indNonRem, :) = nmPA;
                                nmPA = tmPA;
                            end
                            if ~compwise
                                tcorr_mask = false(length(naPX.indNonRem), 1);
                                tcorr_mask(naPX.indNonRem) = corr_mask;
                                corr_mask = tcorr_mask;
                            end
                        end
                        reducedimfl = true;
                    end

                case {'elimzero','extfeat','extdim'}
                    % For these steps (feature elimination), apply to the aggregated vectors.
                    if ~any(strcmp(preprocs,'JuSpace'))
                        if isfield(naPX,'NonPruneVec')
                            IND = 'NonPruneVec';
                        elseif isfield(naPX,'indNonRem')    
                            IND = 'indNonRem';
                        else
                            IND = 'ind';
                        end
                        if size(naPX.(IND),2) > 1 && size(naPX.(IND),1) > 1
                            pIND = naPX.(IND)(:,inp.curlabel);
                        else
                            pIND = naPX.(IND);
                        end
                        % In DR case, nmW is a matrix.
                        tmW = zeros(length(pIND), size(nmW,2));
                        tmW(pIND, :) = nmW;
                        nmW = tmW;
                        tmP = false(length(pIND), size(nmW,2));
                        tmP(pIND, :) = nmP;
                        nmP = tmP;
                        if ~isempty(PA)
                            tmPA = zeros(length(pIND), size(nmW,2));
                            tmPA(pIND, :) = nmPA;
                            nmPA = tmPA;
                        end
                        if ~compwise
                            tcorr_mask = false(length(pIND), 1);
                            tcorr_mask(pIND) = corr_mask;
                            corr_mask = tcorr_mask;
                        end
                    % (Note: If needed, adjust the feature masks lFuVI, fVI here.)
                    end
            end
        end
        
        % After processing all steps, DR branch: nmW, nmP, nmPA are now matrices.
        % Store them for modality n.
        mW{n} = nmW;
        mP{n} = nmP;
        if ~isempty(PA)
            mPA{n} = nmPA;
        end
        
        %-----------------------------------------------------------
        % CORRELATION ANALYSIS
        %-----------------------------------------------------------
        if ~decompfl(n)
            nmPx = Fu(fVI);
            tY = zeros(size(Y,1), numel(nmPx));
            if nM > 1
                % VI references the respective modality n.
                tY(:, nmPx) = Y(:, VI(Fu) == n);
            else
                tY(:, nmPx) = Y;
            end
            % Treat non-finites as missing for correlation
            tY(~isfinite(tY)) = NaN;
            L(~isfinite(L))   = NaN;
            
            % --- Robust correlations (pairwise deletion of NaNs) ---
            % Cross-corr between model weights L and tY
            nmR  = corr(L, tY, 'Type','Pearson',  'Rows','pairwise');
            nmSR = corr(L, tY, 'Type','Spearman', 'Rows','pairwise');
            
            % Within tY correlation
            if ~memprob
                nmC = corr(tY, 'Type','Pearson', 'Rows','pairwise');
            end
            Rfull  = nan(size(nmW,1),1);
            SRfull = nan(size(nmW,1),1);            
            idx = find(corr_mask(:));          
            Rfull(idx)  = nmR(nmPx).';     
            SRfull(idx) = nmSR(nmPx).';
            nmR  = Rfull;
            nmSR = SRfull;
            if ~memprob && ~isempty(nmC)
                Cfull = nan(size(nmW,1));
                Cfull(idx, idx) = nmC(nmPx, nmPx);
                nmC = Cfull;
            end
        else
            % DR is active: Create correlation outputs as matrices with the same
            % number of columns (components) as nmW.
            nmR = nan(size(nmW));
            nmSR = nan(size(nmW));
            nmC = [];
        end
        
        %-----------------------------------------------------------
        % DATA FUSION SCENARIOS
        %-----------------------------------------------------------
        if nM == 1 && mM > 1
            for m = 1:numel(varind)
                indX = inp.X.dimvecx(m)+1 : inp.X.dimvecx(m+1);
                if size(nmW,2) > 1
                    % DR active: extract rows for each component.
                    mW{m} = nmW(indX, :);
                    mP{m} = nmP(indX, :);
                    if ~isempty(PA)
                        mPA{m} = nmPA(indX, :);
                    end
                    mR{m} = nmR(indX, :);
                    mSR{m} = nmSR(indX, :);
                    if ~isempty(nmC) && ~decompfl(n) && ~memprob
                        mC{m} = nmC(indX, indX, :);
                    else
                        mC{m} = [];
                    end
                else
                    % Aggregated case.
                    mW{m} = nmW(indX);
                    mP{m} = nmP(indX);
                    if ~isempty(PA)
                        mPA{m} = nmPA(indX);
                    end
                    mR{m} = nmR(indX);
                    mSR{m} = nmSR(indX);
                    if ~isempty(nmC) && ~decompfl(n) && ~memprob
                        mC{m} = nmC(indX, indX);
                    else
                        mC{m} = [];
                    end
                end
            end
        else
            mW{n} = nmW;
            mP{n} = nmP;
            if ~isempty(PA)
                mPA{n} = nmPA;
            end
            if ~decompfl(n)
                if isempty(mR{n})
                    mR{n} = zeros(size(nmW,1),1);
                    mSR{n} = zeros(size(nmW,1),1);
                    if ~memprob && ~isempty(nmC)
                        mC{n} = zeros(size(nmW,1), size(nmW,1));
                    end
                end
                mR{n}(lFuVI) = nmR(lFuVI);
                mSR{n}(lFuVI) = nmSR(lFuVI); 
                if ~memprob && ~isempty(nmC)
                    mC{n}(lFuVI,lFuVI) = nmC(lFuVI,lFuVI);
                end
            else
                mR{n} = nmR;
                mSR{n} = nmSR; 
                mC{n} = nmC;
            end
        end
    end
end

%-----------------------------------------------------------
% FINAL POSTPROCESSING: Replace zero entries with NaN.
%-----------------------------------------------------------
for n = 1:numel(mW)
    % mW{n} is now either a vector (aggregated) or a matrix (DR active).
    ind0 = mW{n} == 0;
    mW{n}(ind0) = NaN;
end

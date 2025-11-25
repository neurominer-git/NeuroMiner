function [I2, I1, filefound] = nk_VisXHelperC(act, nM, nclass, decompfl, permfl, sigfl, ix, jx, I2, inp, ll, nperms, I1, compwise, ill)
global FUSION SVM CV CVPOS

linsvmfl = determine_linsvm_flag(SVM);
filefound = false;

switch act
    
    case 'init'

        % Initialize arrays in data containers for CV2-level statistics
        if permfl ||sigfl
            I2.VCV2MPERM_CV2 = nan(nclass,ix*jx);
            I2.VCV2MPERM     = nan(nclass,ix*jx);
            if permfl
                I2.VCV2PERM      = cell(nclass,nM);                  % Container for feature space null distribution estimations: p value (each cell for one modality)
                I2.VCV2PERM_FDR  = cell(nclass,nM);                  % Container for feature space null distribution estimations: p value (each cell for one modality)
                I2.VCV2ZSCORE    = cell(nclass,nM);                  % Container for feature space null distribution estimations: Z score (each cell for one modality)
            end
        end
        if nM>1, I2.ModAgg_L2nShare = cell(nclass,1); end            % [nM × nCV2_models]            
        if any(~decompfl)
            I2.VCV2PEARSON              = cell(nclass,nM);           % Container for feature spaces' univariate pearson correlation coefficients
            I2.VCV2SPEARMAN             = cell(nclass,nM);           % Container for feature spaces' univariate spearman correlation coefficients
            I2.VCV2PEARSON_UNCORR_PVAL  = cell(nclass,nM);
            I2.VCV2SPEARMAN_UNCORR_PVAL = cell(nclass,nM);
            I2.VCV2PEARSON_FDR_PVAL     = cell(nclass,nM);
            I2.VCV2SPEARMAN_FDR_PVAL    = cell(nclass,nM);
            if linsvmfl
                I2.VCV2PVAL_ANALYTICAL = cell(nclass,nM);
                I2.VCV2PVAL_ANALYTICAL_FDR = cell(nclass,nM);
            end
            I2.VCV2CORRMAT              = cell(nclass,nM);
            I2.VCV2CORRMAT_UNCORR_PVAL  = cell(nclass,nM);
            I2.VCV2CORRMAT_FDR_PVAL     = cell(nclass,nM);
        end
        if compwise
            I2.VCV1REF                  = cell(nclass,1); 
            I2.VCV1REFCNT               = cell(nclass,1);
            I2.VCV2WPERMREF             = cell(nclass,1);   
            I2.VCV2WCORRREF             = cell(nclass,1);
            % ----- CV2-level L2 contribution containers (combined reference) -----
            if nM > 1
                % Per-modality aggregate shares across combined reference
                % {h}: [nM × nCV2_models]
                I2.ModAgg_L2nShare      = cell(nclass,1);
                if compwise
                    % Per-component × modality cube in combined space
                    % {h}: [nRef_combined × nM × nCV2_models]
                    I2.ModComp_L2nCube  = cell(nclass,1);
                end
            end
            % Global per-component L2 in combined space
            % {h}: [nRef_combined × nCV2_models]
            I2.ModComp_L2n              = cell(nclass,1);
            % --- CV2-level fractionated decision scores (per class × modality) ---
            % store sums + counts (handles different #components per classifier)
            if compwise
                I2.DxSUM                    = cell(nclass, 1);   % sums over CV2 models
                I2.DxSQSUM                    = cell(nclass, 1);   % sums of squares over CV2 models
                I2.DxN                      = cell(nclass, 1);   % counts per subject × component
                if inp.isInter
                    for h = 1:nclass 
                        I2.DxSUM{h}  = cell(1, nM); 
                        I2.DxSQSUM{h}  = cell(1, nM); 
                        I2.DxN{h} = cell(1, nM); 
                    end
                end
            end
        end
        I2.SignPosCount     = cell(nclass,nM);
        I2.SignNegCount     = cell(nclass,nM);
        I2.VCV2SUM          = cell(nclass,nM);                  % Container for feature spaces' sum values of CV-generated feature weights
        I2.VCV2SQ           = cell(nclass,nM);                  % Container for feature spaces' sqrt values of CV-generated feature weights
        I2.GCV2SUM          = cell(nclass,nM);
        I2.VCV2MEAN         = cell(nclass,nM);                  % Container for feature spaces' mean vectors of CV-generated feature weights
        I2.VCV2STD          = cell(nclass,nM);                  % Container for feature spaces' std vectors of CV-generated feature weights
        I2.VCV2PROB         = cell(nclass,nM);                  % Container for feature spaces' reliability masks of CV-generated feature weights (reliable means |mean| > sterr)
        I2.VCV2SEL          = cell(nclass,nM);                  % Vectors with #number of models per feature info
        I2.PCV2SUM          = cell(nclass,nM);                  % Vectors with 'times selected' feature info
        I2.VCV2NMODEL       = zeros(nclass,1);
        I2.VCV2MORIG_EVAL   = nan(ix,jx,nclass);
        
    case 'initI1'

        % --- CV1 model counter (per CV2 fold) ---
        I1.VCV1NMODEL = zeros(nclass,1);
        
        % --- Per-modality running stats (map-space; kept as before) ---
        I1.VCV1SUM  = cell(nclass, nM);
        I1.VCV1SQ   = cell(nclass, nM);
        I1.VCV1MEAN = cell(nclass, nM);
        I1.VCV1STD  = cell(nclass, nM);
        
        % --- Correlation/association (only for non-decomposed modalities) ---
        if any(~decompfl)
            I1.PCV1SUM                  = cell(nclass, nM);
            I1.VCV1PEARSON              = cell(nclass, nM);
            I1.VCV1SPEARMAN             = cell(nclass, nM);
            I1.VCV1PEARSON_UNCORR_PVAL  = cell(nclass, nM);
            I1.VCV1SPEARMAN_UNCORR_PVAL = cell(nclass, nM);
            I1.VCV1PEARSON_FDR_PVAL     = cell(nclass, nM);
            I1.VCV1SPEARMAN_FDR_PVAL    = cell(nclass, nM);
            if linsvmfl
                I1.VCV1PVAL_ANALYTICAL      = cell(nclass, nM);
                I1.VCV1PVAL_ANALYTICAL_FDR  = cell(nclass, nM);
            end
            I1.VCV1CORRMAT              = cell(nclass, nM);
        end
        
        % --- Permutation-related containers ---
        if permfl || sigfl
            if permfl
                % Per-modality, per-fold/per-component permutation-derived volumes
                I1.VCV1PERM     = cell(nclass, nM);
                I1.VCV1PERM_FDR = cell(nclass, nM);
                I1.VCV1ZSCORE   = cell(nclass, nM);
            end
            if sigfl
                % Modality-agnostic combined per-component p-values per fold (source order before alignment)
                % Later mapped into VCV1WPERMREF via assignment.
                I1.VCV1WPERM = cell(nclass, 1);
            end
            % Optional: place to store meta or max-perm stats per fold
            % (kept from original)
            I1.VCV1MPERM = cell(nclass, 1);
        end
        
        % --- Global (combined-space) alignment targets (per CV2 fold) ---
        % These are sized lazily during the first align/seed, but declaring
        % them here avoids repeated isfield checks downstream.
        I1.VCV1WPERMREF   = cell(nclass, 1);  % [nRef_combined × nFolds]
        I1.VCV1WCORRREF   = cell(nclass, 1);  % [nRef_combined × nFolds]
        
        % --- Fractionated decision scores (CV1-level; already aligned to ref) ---
        % Dx{h,n} will be [nSubj_fold × nRef_mod] for that CV2 file
        if compwise
            I1.Dx = cell(nclass, 1); 
            if inp.isInter
                for h = 1:nclass, I1.Dx{h} = cell(1, nM); end
            end
        end

        % --- Modality contribution containers (combined reference; per CV2 fold) ---
        % Defined in combined component space; only meaningful for multi-modality.
        if nM > 1
            % Per-modality aggregate share across the combined reference
            % {h}: [nM × nCV1_models] — sized lazily when seeding the combined ref
            I1.ModAgg_L2nShare = cell(nclass, 1);
        
            if compwise
                % Per-component × modality cube in combined space
                % {h}: [nRef_combined × nM × nCV1_models]
                I1.ModComp_L2nCube = cell(nclass, 1);
            end
        end
        % Per-component global L2 in combined space
        % {h}: [nRef_combined × nCV1_models]
        I1.ModComp_L2n = cell(nclass, 1);

        % --- Reset I2 (per-run scratch / global ref cache holder) ---
        I2 = [];

    case 'prune_final'

        if ~compwise
            % Nothing to prune: we’re collapsing components into one signature.
            % Ensure VCV1/VCV2 arrays are treated as 2-D everywhere else.
            return
        end

        % prune every per‑modality container that has component dimension
        for h=1:nclass
            keep = I2.KEEP{h};
            if ~iscell(keep)
                keep = repmat({keep},nM,1); 
            end
            for n = 1:nM
                if decompfl(n)
                    I2.VCV2SUM{h,n}       = I2.VCV2SUM{h,n}      (:, keep{n});
                    I2.VCV2SQ{h,n}        = I2.VCV2SQ{h,n}       (:, keep{n});
                    I2.VCV2SEL{h,n}       = I2.VCV2SEL{h,n}      (:, keep{n});
                    I2.VCV2PROB{h,n}      = I2.VCV2PROB{h,n}     (:, keep{n});
                    I2.SignPosCount{h,n}  = I2.SignPosCount{h,n} (:, keep{n});
                    I2.SignNegCount{h,n}  = I2.SignNegCount{h,n} (:, keep{n});
                    I2.GCV2SUM{h,n}       = I2.GCV2SUM{h,n}      (:, :, keep{n});
                    I2.VCV2STD{h,n}       = I2.VCV2STD{h,n}      (:, :, keep{n});
                    I2.VCV2MEAN{h,n}      = I2.VCV2MEAN{h,n}     (:, :, keep{n});
                    if permfl
                        I2.VCV2PERM{h,n}  = I2.VCV2PERM{h, n}    (:, keep{n});
                        I2.VCV2PERM_FDR{h,n} = I2.VCV2PERM_FDR{h,n}(:, keep{n});
                        I2.VCV2ZSCORE{h,n}  = I2.VCV2ZSCORE{h, n}(:, keep{n});
                    end
                end
            end
        end

        for h = 1:nclass
            keep = I2.KEEP{h};
            if ~iscell(keep)
                keep = repmat({keep},nM,1); 
            end
            if inp.isInter
                for n=1:nM
                    % 1) L2n magnitudes per component (nRef × ll)
                    if isfield(I2,'ModComp_L2n') && numel(I2.ModComp_L2n) >= h && numel(I2.ModComp_L2n{h}) >=n &&~isempty(I2.ModComp_L2n{h}{n})
                        I2.ModComp_L2n{h}{n} = I2.ModComp_L2n{h}{n}(keep{n}, :);
                    end
                    % 3) CV2-level mapped permutation p-values and correlations in REF order (nRef × ll)
                    if isfield(I2,'VCV2WPERMREF') && numel(I2.VCV2WPERMREF) >= h && numel(I2.VCV2WPERMREF{h}) >= n && ~isempty(I2.VCV2WPERMREF{h}{n})
                        I2.VCV2WPERMREF{h}{n} = I2.VCV2WPERMREF{h}{n}(keep{n}, :);
                    end
                    if isfield(I2,'VCV2WCORRREF') && numel(I2.VCV2WCORRREF) >= h && numel(I2.VCV2WCORRREF{h}) >= n && ~isempty(I2.VCV2WCORRREF{h}{n})
                        I2.VCV2WCORRREF{h}{n} = I2.VCV2WCORRREF{h}{n}(keep{n}, :);
                    end
                    if isfield(I2,'DxSUM') 
                        if ~decompfl(n), continue; end
                        if ~isempty(I2.DxSUM{h}{n})
                            keepCols = keep{n};
                            nComp = size(I2.DxSUM{h}{n},2);
                            if numel(keepCols) > nComp
                                keepCols = keepCols(1:nComp);
                            end
                            I2.DxSUM{h}{n}  = I2.DxSUM{h}{n}(:, keepCols);
                            I2.DxSQSUM{h}{n}  = I2.DxSQSUM{h}{n}(:, keepCols);
                            I2.DxN{h}{n} = I2.DxN{h}{n}(:, keepCols);
                        end
                    end
                end
            else
              
                % 1) L2n magnitudes per component (nRef × ll)
                if isfield(I2,'ModComp_L2n') && numel(I2.ModComp_L2n) >= h && ~isempty(I2.ModComp_L2n{h})
                    I2.ModComp_L2n{h} = I2.ModComp_L2n{h}(keep{1}, :);
                end
                % 2) L2n cube per component & modality (nRef × nM × ll)
                if isfield(I2,'ModComp_L2nCube') && numel(I2.ModComp_L2nCube) >= h && ~isempty(I2.ModComp_L2nCube{h})
                    I2.ModComp_L2nCube{h} = I2.ModComp_L2nCube{h}(keep{1}, :, :);
                end
                % 3) CV2-level mapped permutation p-values and correlations in REF order (nRef × ll)
                if isfield(I2,'VCV2WPERMREF') && numel(I2.VCV2WPERMREF) >= h && ~isempty(I2.VCV2WPERMREF{h})
                    I2.VCV2WPERMREF{h} = I2.VCV2WPERMREF{h}(keep{1}, :);
                end
                if isfield(I2,'VCV2WCORRREF') && numel(I2.VCV2WCORRREF) >= h && ~isempty(I2.VCV2WCORRREF{h})
                    I2.VCV2WCORRREF{h} = I2.VCV2WCORRREF{h}(keep{1}, :);
                end
                % ----- Prune Dx / DxN after merge+prune (intermediate) -----
                if isfield(I2,'DxSUM') 
                    if ~isempty(I2.DxSUM{h})
                        keepCols = keep{1};
                        nComp = size(I2.DxSUM{h},2);
                        if numel(keepCols) > nComp
                            keepCols = keepCols(1:nComp);
                        end
                        I2.DxSUM{h}  = I2.DxSUM{h}(:, keepCols);
                        I2.DxSQSUM{h}  = I2.DxSQSUM{h}(:, keepCols);
                        I2.DxN{h} = I2.DxN{h}(:, keepCols);
                    end
                end
            end
            % NOTE: Do NOT prune ModAgg_L2nShare{h} (nM × ll) – no component dimension.
        end

    case 'merge_and_prune'

        % ====================== MEMORY-AWARE MERGE/PRUNE (CV2) ======================
        if ~compwise
            % Nothing to prune: we’re collapsing components into one signature.
            % Ensure VCV1/VCV2 arrays are treated as 2-D everywhere else.
            return
        end
        fprintf('\nChecking memory used by CV2-level container and compacting reference space as required...')
        useMerge      = getfield_or(inp,'useRefMerge', true);
        mergeStepCap  = getfield_or(inp,'mergeStepCap', Inf);
        safetyFloor   = getfield_or(inp,'safetyFloor', 5); % never reduce ref below 5 columns per modality/class
        pruneMode     = getfield_or(inp,'PruneMode', 'fraction'); 
        pruneFrac     = getfield_or(inp,'PruneFraction', 0.10); 
        [~, availBytes] = isMemoryTight(inp.tightThresh);       % avail in BYTES (Windows: physical avail; Linux/Mac: JVM max)
        % be conservative: leave headroom (15%) to avoid spikes; clamp sane bounds
        memCapBytes = max( 5e8, min( inp.memFrac * double(availBytes), 0.85 * double(availBytes) ) ); % ≥0.5 GB, ≤85% of avail

        % ---- per-class compact ----
        for h = 1:nclass
        
            Ref = I2.VCV1REF{h};        % 1×1 cell, [nFeat × nRef]
            nRef = size(Ref{1}, 2);
            if nRef <= safetyFloor, continue; end

            % =======================================================================
            % 1) MERGE before pruning (mode-aware)
            % =======================================================================
            if useMerge && nRef > safetyFloor
                if ~inp.isInter
                    % ---------- EARLY FUSION: one joint merge across modalities ----------
                    % Build joint ref cell (1×nM) and a single presence vector cnt_vec
                    RefJoint = I2.VCV1REF{h};      % 1×nM cells, each [nFeat × nRef]
                    RefcntJoint = I2.VCV1REFCNT{h}; % 1×nRef
                    
                    mopts = struct('thr', inp.simCorrThresh+0.05, 'metric',inp.simCorrMethod, 'unitnorm', true, ...
                                   'maxMerges', mergeStepCap, 'modWeights', ones(1,numel(RefJoint)), ...
                                   'verbose', false);
                    
                    [Ref_new, Refcnt_new, mg] = nk_MergeRefColumns(RefJoint, RefcntJoint, mopts);
                    if mg.newN < mg.oldN
                        
                        P_old = I2.VCV2WPERMREF{h};
                        w_old = sum(isfinite(P_old), 2).';
                        fprintf('\n\t\t\t[Merger]: condensed %g to %g components (METHOD=%s, cutoff: %g, unitnorm=%g)', mg.oldN, mg.newN, mopts.metric, mopts.thr, mopts.unitnorm);
                        % Apply the same mapping to ALL modalities and ALL CV2 containers (rows/cols/3rd-dim)
                        I2.VCV1REF{h} = Ref_new;                % refs (all modalities simultaneously)
                        I2.VCV1REFCNT{h} = Refcnt_new;
                        map_old2new = mg.map_old2new;
            
                        % ------- remap CV2 containers (EARLY) -------
                        % columns == components
                        I2.VCV2SUM{h,1}      = apply_map_colwise(I2.VCV2SUM{h,1},      map_old2new, w_old, 'mean');
                        I2.VCV2SQ{h,1}       = apply_map_colwise(I2.VCV2SQ{h,1},       map_old2new, w_old, 'mean');
                        I2.VCV2SEL{h,1}      = apply_map_colwise(I2.VCV2SEL{h,1},      map_old2new, w_old, 'mean');
                        I2.VCV2PROB{h,1}     = apply_map_colwise(I2.VCV2PROB{h,1},     map_old2new, w_old, 'mean');
                        I2.SignPosCount{h,1} = apply_map_colwise(I2.SignPosCount{h,1}, map_old2new, w_old, 'mean');
                        I2.SignNegCount{h,1} = apply_map_colwise(I2.SignNegCount{h,1}, map_old2new, w_old, 'mean');
                        if permfl
                            % columns == components for per-fold uncorrected stuff
                            I2.VCV2PERM{h,1}   = apply_map_colwise(I2.VCV2PERM{h,1},   map_old2new, w_old, 'min');
                            % rows = components for *_REF stats gathered over folds
                            % p-values rowwise: conservative combine (min) or Fisher
                            I2.VCV2PERM_FDR{h} = apply_map_colwise(I2.VCV2PERM_FDR{h}, map_old2new, w_old, 'min');       
                            % z-scores rowwise: Stouffer z
                            I2.VCV2ZSCORE{h}   = apply_map_colwise(I2.VCV2ZSCORE{h},   map_old2new, w_old, 'zmean');
                        end
                        % 3D cube where components are along dim-3 in your CV2 aggregates
                        I2.GCV2SUM{h,1}  = apply_map_3dthird(I2.GCV2SUM{h,1},  map_old2new, w_old, 'mean');
                        I2.VCV2STD{h,1}  = apply_map_3dthird(I2.VCV2STD{h,1},  map_old2new, w_old, 'mean');
                        I2.VCV2MEAN{h,1} = apply_map_3dthird(I2.VCV2MEAN{h,1}, map_old2new, w_old, 'mean');
            
                        % REF-order matrices (rows = components), per early-fusion storage
                        I2.VCV2WPERMREF{h} = apply_map_rowwise(I2.VCV2WPERMREF{h}, map_old2new, w_old, 'min');
                        I2.VCV2WCORRREF{h} = apply_map_rowwise(I2.VCV2WCORRREF{h}, map_old2new, w_old, 'zmean');
                        I2.ModComp_L2n{h}  = apply_map_rowwise(I2.ModComp_L2n{h},  map_old2new, w_old, 'mean');
                        if nM>1 && isfield(I2,'ModComp_L2nCube') && numel(I2.ModComp_L2nCube)>=h && ~isempty(I2.ModComp_L2nCube{h})
                            % In your early-fusion cube, components are along dim-2 — adjust if different
                            I2.ModComp_L2nCube{h} = apply_map_3dfirst(I2.ModComp_L2nCube{h}, map_old2new, w_old, 'mean');
                        end
                        % ----- Remap Dx and DxN (subject × component) -----
                        if isfield(I2,'DxSUM') && ~isempty(I2.DxSUM{h}) 
                            % map columns (components) with same grouping as WPERMREF
                            I2.DxSUM{h} = apply_map_colwise(I2.DxSUM{h},  map_old2new, w_old, 'sum');
                            I2.DxSQSUM{h} = apply_map_colwise(I2.DxSQSUM{h},  map_old2new, w_old, 'sum');
                            % counts: sum over grouped old components
                            I2.DxN{h} = apply_map_colwise(I2.DxN{h}, map_old2new, w_old, 'sum');
                        end
                    end
            
                else
                    % ---------- INTERMEDIATE FUSION: merge per modality ----------
                    for n = 1:nM
                        if ~decompfl(n), continue; end
                        
                        Ref   = I2.VCV1REF{h}{n};      % [nFeat × nRef_n]
                        RefCnt = I2.VCV1REFCNT{h}{n};      
                        nRef  = size(Ref, 2);
                        if nRef <= safetyFloor, continue; end
            
                        mopts = struct('thr', inp.simCorrThresh+0.05, 'metric',inp.simCorrMethod, 'unitnorm', true, ...
                                       'maxMerges', mergeStepCap, 'modWeights', 1, 'verbose', false);

                        [Ref_m, Refcnt_m, mg_n] = nk_MergeRefColumns({Ref}, RefCnt, mopts);
                        
                        if mg_n.newN < mg_n.oldN

                            fprintf('\n\t\t\t[Merger -> Modality #%g]: condensed %g to %g components (METHOD=%s, cutoff: %g, unitnorm=%g)', n, mg_n.oldN, mg_n.newN, mopts.metric, mopts.thr, mopts.unitnorm);
                            map_old2newn = mg_n.map_old2new;
                            P_old = I2.VCV2WPERMREF{h}{n};
                            w_old = sum(isfinite(P_old), 2).';
                        
                            % refs
                            I2.VCV1REF{h}{n} = Ref_m{1};
                            I2.VCV1REFCNT{h}{n} = Refcnt_m{1};
                            
                            % ---- remap this modality’s CV2 containers only (INTER) ----
                            I2.VCV2SUM{h,n}      = apply_map_colwise(I2.VCV2SUM{h,n},      map_old2newn, w_old, 'mean');
                            I2.VCV2SQ{h,n}       = apply_map_colwise(I2.VCV2SQ{h,n},       map_old2newn, w_old, 'mean');
                            I2.VCV2SEL{h,n}      = apply_map_colwise(I2.VCV2SEL{h,n},      map_old2newn, w_old, 'mean');
                            I2.VCV2PROB{h,n}     = apply_map_colwise(I2.VCV2PROB{h,n},     map_old2newn, w_old, 'mean');
                            I2.SignPosCount{h,n} = apply_map_colwise(I2.SignPosCount{h,n}, map_old2newn, w_old, 'mean');
                            I2.SignNegCount{h,n} = apply_map_colwise(I2.SignNegCount{h,n}, map_old2newn, w_old, 'mean');
                            if permfl
                                I2.VCV2PERM{h,n}      = apply_map_colwise(I2.VCV2PERM{h,n},      map_old2newn, w_old, 'min');
                                I2.VCV2PERM_FDR{h,n}  = apply_map_colwise(I2.VCV2PERM_FDR{h,n},  map_old2newn, w_old, 'min'); 
                                I2.VCV2ZSCORE{h,n}    = apply_map_colwise(I2.VCV2ZSCORE{h,n},    map_old2newn, w_old, 'zmean');
                            end
                            % 3D: components on dim-3
                            I2.GCV2SUM{h,n}  = apply_map_3dthird(I2.GCV2SUM{h,n},  map_old2newn, w_old, 'mean');
                            I2.VCV2STD{h,n}  = apply_map_3dthird(I2.VCV2STD{h,n},  map_old2newn, w_old, 'mean');
                            I2.VCV2MEAN{h,n} = apply_map_3dthird(I2.VCV2MEAN{h,n}, map_old2newn, w_old, 'mean');
            
                            % REF-order rows per modality
                            I2.VCV2WPERMREF{h}{n} = apply_map_rowwise(I2.VCV2WPERMREF{h}{n}, map_old2newn, w_old, 'min');
                            I2.VCV2WCORRREF{h}{n} = apply_map_rowwise(I2.VCV2WCORRREF{h}{n}, map_old2newn, w_old, 'zmean');
                            I2.ModComp_L2n{h}{n}  = apply_map_rowwise(I2.ModComp_L2n{h}{n},  map_old2newn, w_old, 'mean');

                            % ----- Remap Dx and DxN (subject × component) -----
                            if isfield(I2,'DxSUM') && ~isempty(I2.DxSUM{h}{n}) && numel(I2.DxSUM{h}) >= n && ~isempty(I2.DxSUM{h}{n})
                                % map columns (components) with same grouping as WPERMREF
                                I2.DxSUM{h}{n}  = apply_map_colwise(I2.DxSUM{h}{n},  map_old2newn, w_old, 'sum');
                                I2.DxSQSUM{h}{n}  = apply_map_colwise(I2.DxSQSUM{h}{n},  map_old2newn, w_old, 'sum');
                                % counts: sum over grouped old components
                                I2.DxN{h}{n} = apply_map_colwise(I2.DxN{h}{n}, map_old2newn, w_old, 'sum');
                            end
                        end
                    end
                end
            end
        
            % =======================================================================
            % 2) PRUNE (depending on prune mode): keep most consistent columns
            % =======================================================================
            switch pruneMode
                case 'ram'
                     % ---------- estimate memory ----------
                    memNow = nk_EstimateRefMem(Ref, I2, h, inp.isInter, nM);
                    runPrune = memNow > memCapBytes;
                    if ~runPrune
                        if nclass>1
                            fprintf('\n[Model %d] OK: current mem %.1f MB ≤ cap %.1f MB', h, memNow/2^20, memCapBytes/2^20);
                        else
                            fprintf('\nOK: current mem %.1f MB ≤ cap %.1f MB', memNow/2^20, memCapBytes/2^20);
                        end
                        return
                    else
                        if nclass>1
                            fprintf('\n[Model %d] Over cap: mem %.1f MB > cap %.1f MB → compacting...', h, memNow/2^20, memCapBytes/2^20);
                        else
                            fprintf('\nOver cap: mem %.1f MB > cap %.1f MB → compacting...', memNow/2^20, memCapBytes/2^20);
                        end
                    end
                case 'fraction'
                    runPrune = true;
                    fprintf('\nFixed fractional prune is ON.')
            end

            if runPrune
                if inp.isInter
                    keep = cell(nM,1);
                    for n=1:nM
                        % count how many folds survived (not NaN) for each component
                        nBefore     = size(I2.VCV2WPERMREF{h}{n}, 1);
                        pres        = sum(~isnan(I2.VCV2WPERMREF{h}{n}), 2);  
                        % fractional prune settings
                        minKeepAbs  = safetyFloor;                   % always keep at least safetyFloor components
                        nDrop       = floor(pruneFrac * nBefore);
                        nDrop       = max(0, min(nDrop, nBefore - minKeepAbs));
                        if nDrop == 0
                            % nothing to prune for this class
                            keep{n} = true(nBefore,1);
                        else
                            % drop the nDrop lowest 'pres' (tie-broken deterministically)
                            [~, asc] = sort(pres, 'ascend');         % weakest first
                            dropIdx  = asc(1:nDrop);
                            keep{n}     = true(nBefore,1);
                            keep{n}(dropIdx) = false;
                            nAfter = sum(keep{n});
                            if nclass>1
                                fprintf('\nFractional prune (%1.1f%%): [ Model %d, Modality #%g ] %d → %d (dropped %d least-selected)', pruneFrac*100, h, n, nBefore, nAfter, nDrop);
                            else
                                fprintf('\nFractional prune (%1.1f%%): [ Modality #%g ] %d → %d (dropped %d least-selected)', pruneFrac*100, n, nBefore, nAfter, nDrop);
                            end
                        end
                    end
                else
                    % count how many folds survived (not NaN) for each component
                    nBefore = size(I2.VCV2WPERMREF{h}, 1);
                    pres    = sum(~isnan(I2.VCV2WPERMREF{h}), 2);  % [nRef x 1], selection count per component
                    % fractional prune settings
                    minKeepAbs  = 3;                             % always keep at least 3 components
                    nDrop       = floor(pruneFrac * nBefore);
                    nDrop       = max(0, min(nDrop, nBefore - minKeepAbs));
                    
                    if nDrop == 0
                        % nothing to prune for this class
                        keep = true(nBefore,1);
                    else
                        % drop the nDrop lowest 'pres' (tie-broken deterministically)
                        [~, asc] = sort(pres, 'ascend');         % weakest first
                        dropIdx  = asc(1:nDrop);
                        keep     = true(nBefore,1);
                        keep(dropIdx) = false;
                        nAfter = sum(keep);
                        if nclass>1
                            fprintf('\nFractional prune (%1.1f%%): [ Model %d ] %d → %d (dropped %d least-selected)', pruneFrac*100, h, nBefore, nAfter, nDrop);
                        else
                            fprintf('\nFractional prune (%1.1f%%): %d → %d (dropped %d least-selected)', pruneFrac*100, nBefore, nAfter, nDrop);
                        end
                    end
                    keep = repmat({keep},nM,1);
                end
        
                % ---- apply pruning to references and accumulators ----
                for n = 1:nM
                    if ~decompfl(n), continue; end
                    % reference space
                    I2.VCV1REF{h}{n} = I2.VCV1REF{h}{n}(:,keep{n});
                    if inp.isInter
                        I2.VCV1REFCNT{h}{n} = I2.VCV1REFCNT{h}{n}(keep{n});
                    else
                        if n==1, I2.VCV1REFCNT{h} = I2.VCV1REFCNT{h}(keep{n}); end
                    end
                    % 2D accumulators (columns=components)
                    I2.VCV2SUM{h,n}      = I2.VCV2SUM{h,n}(:, keep{n});
                    I2.VCV2SQ{h,n}       = I2.VCV2SQ{h,n}(:, keep{n});
                    I2.VCV2SEL{h,n}      = I2.VCV2SEL{h,n}(:, keep{n});
                    I2.VCV2PROB{h,n}     = I2.VCV2PROB{h,n}(:, keep{n});
                    I2.SignPosCount{h,n} = I2.SignPosCount{h,n}(:, keep{n});
                    I2.SignNegCount{h,n} = I2.SignNegCount{h,n}(:, keep{n});
                    if permfl
                        I2.VCV2PERM{h,n}      = I2.VCV2PERM{h,n}(:, keep{n});
                        % row-wise 2D:
                        I2.VCV2PERM_FDR{h,n}  = I2.VCV2PERM_FDR{h,n}(:, keep{n});
                        I2.VCV2ZSCORE{h,n}    = I2.VCV2ZSCORE{h,n}(:, keep{n});
                    end
                    % 3D cubes (third dimension = components)
                    I2.GCV2SUM{h,n}  = I2.GCV2SUM{h,n}(:, :, keep{n});
                    I2.VCV2STD{h,n}  = I2.VCV2STD{h,n}(:, :, keep{n});
                    I2.VCV2MEAN{h,n} = I2.VCV2MEAN{h,n}(:, :, keep{n});
                end
        
                if inp.isInter
                    for n=1:nM
                        if ~decompfl(n), continue; end
                        I2.VCV2WPERMREF{h}{n} = I2.VCV2WPERMREF{h}{n}(keep{n}, :);
                        I2.VCV2WCORRREF{h}{n} = I2.VCV2WCORRREF{h}{n}(keep{n}, :);
                        I2.ModComp_L2n{h}{n}  = I2.ModComp_L2n{h}{n}(keep{n}, :);
                        % ----- Prune Dx / DxN after merge+prune (intermediate) -----
                        if isfield(I2,'DxSUM') 
                            if ~decompfl(n), continue; end
                            if ~isempty(I2.DxSUM{h}{n})
                                keepCols = keep{n};
                                nComp = size(I2.DxSUM{h}{n},2);
                                if numel(keepCols) > nComp
                                    keepCols = keepCols(1:nComp);
                                end
                                I2.DxSUM{h}{n}  = I2.DxSUM{h}{n}(:, keepCols);
                                I2.DxSQSUM{h}{n}  = I2.DxSQSUM{h}{n}(:, keepCols);
                                I2.DxN{h}{n} = I2.DxN{h}{n}(:, keepCols);
                            end
                        end
                    end
                else
                    I2.VCV2WPERMREF{h} = I2.VCV2WPERMREF{h}(keep{1}, :);
                    I2.VCV2WCORRREF{h} = I2.VCV2WCORRREF{h}(keep{1}, :);
                    I2.ModComp_L2n{h}  = I2.ModComp_L2n{h}(keep{1}, :);
                    if nM>1, I2.ModComp_L2nCube{h} = I2.ModComp_L2nCube{h}(keep{1}, :, :); end
                    % ----- Prune Dx / DxN after merge+prune (intermediate) -----
                    if isfield(I2,'DxSUM') 
                        if ~isempty(I2.DxSUM{h})
                            keepCols = keep{1};
                            nComp = size(I2.DxSUM{h},2);
                            if numel(keepCols) > nComp
                                keepCols = keepCols(1:nComp);
                            end
                            I2.DxSUM{h}  = I2.DxSUM{h}(:, keepCols);
                            I2.DxSQSUM{h}  = I2.DxSQSUM{h}(:, keepCols);
                            I2.DxN{h} = I2.DxN{h}(:, keepCols);
                        end
                    end
                end
            end
        end

    case 'prune_memory'
        
        if ~compwise
            % Nothing to prune: we’re collapsing components into one signature.
            % Ensure VCV1/VCV2 arrays are treated as 2-D everywhere else.
            return
        end
        fprintf('\nChecking memory used by CV2-level container and dropping components as required (potentially adjust your settings!).')
        [~, availBytes] = isMemoryTight(inp.tightThresh); % avail in BYTES (Windows: physical avail; Linux/Mac: JVM max)
        memCapBytes = max( 5e8, min( inp.memFrac * double(availBytes), 0.85 * double(availBytes) ) ); % ≥0.5 GB, ≤85% of avail
        memNow = 0;
        for curclass = 1:nclass
            memNow = memNow + nk_EstimateRefMem(I2.VCV1REF, I2, curclass, inp.isInter, nM);
        end
        if memNow < memCapBytes
            if nclass>1
                for h=1:nclass
                    fprintf('\n[Model %d] OK: current mem %.1f MB ≤ cap %.1f MB', h, memNow/2^20, memCapBytes/2^20);
                end
            else
                fprintf('\nOK: current mem %.1f MB ≤ cap %.1f MB', memNow/2^20, memCapBytes/2^20);
            end
            return
        else

        end
        % prune every per‑modality container that has component dimension
        pruneFrac     = getfield_or(inp,'PruneFraction', 0.10);
        safetyFloor   = getfield_or(inp,'safetyFloor', 5); % never reduce ref below 5 columns per modality/class
        for h=1:nclass
            if inp.isInter
                keep = cell(nM,1);
                for n=1:nM
                    % count how many folds survived (not NaN) for each component
                    nBefore = size(I2.VCV2WPERMREF{h}{n}, 1);
                    pres    = sum(~isnan(I2.VCV2WPERMREF{h}{n}), 2);  
                    % fractional prune settings
                    nDrop       = floor(pruneFrac * nBefore);
                    nDrop       = max(0, min(nDrop, nBefore - safetyFloor));
                    
                    if nDrop == 0
                        % nothing to prune for this class
                        keep{n} = true(nBefore,1);
                    else
                        % drop the nDrop lowest 'pres' (tie-broken deterministically)
                        [~, asc] = sort(pres, 'ascend');         % weakest first
                        dropIdx  = asc(1:nDrop);
                        keep{n}     = true(nBefore,1);
                        keep{n}(dropIdx) = false;
                    
                        nAfter = sum(keep{n});
                        if nclass>1
                            fprintf('\nFractional prune (%1.1f%%): [ Model %d, Modality #%g ] %d → %d (dropped %d least-selected)', pruneFrac*100, h, n, nBefore, nAfter, nDrop);
                        else
                            fprintf('\nFractional prune (%1.1f%%): [ Modality #%g ] %d → %d (dropped %d least-selected)', pruneFrac*100, n, nBefore, nAfter, nDrop);
                        end
                    end
                end
            else
                % count how many folds survived (not NaN) for each component
                nBefore = size(I2.VCV2WPERMREF{h}, 1);
                pres    = sum(~isnan(I2.VCV2WPERMREF{h}), 2);  % [nRef x 1], selection count per component
                
                % fractional prune settings
                nDrop       = floor(pruneFrac * nBefore);
                nDrop       = max(0, min(nDrop, nBefore - safetyFloor));
                
                if nDrop == 0
                    % nothing to prune for this class
                    keep = true(nBefore,1);
                else
                    % drop the nDrop lowest 'pres' (tie-broken deterministically)
                    [~, asc] = sort(pres, 'ascend');         % weakest first
                    dropIdx  = asc(1:nDrop);
                    keep     = true(nBefore,1);
                    keep(dropIdx) = false;
                    nAfter = sum(keep);
                    if nclass>1
                        fprintf('\nFractional prune (10%%): [ Model %d ] %d → %d (dropped %d least-selected)', h, nBefore, nAfter, nDrop);
                    else
                        fprintf('\nFractional prune (10%%): %d → %d (dropped %d least-selected)', nBefore, nAfter, nDrop);
                    end
                end
                keep = repmat({keep},nM,1);
            end
            for n = 1:nM
                if decompfl(n)
                    % 1) prune the reference‐space weights
                    I2.VCV1REF{h}{n} = I2.VCV1REF{h}{n}(:, keep{n});
                    if inp.isInter
                        I2.VCV1REFCNT{h}{n} = I2.VCV1REFCNT{h}{n}(keep{n});
                    else
                        if n==1, I2.VCV1REFCNT{h} = I2.VCV1REFCNT{h}(keep{n}); end
                    end
                    % 2) prune the CV2‐aggregates
                    % The 2D accumulators:
                    I2.VCV2SUM{h,n}       = I2.VCV2SUM{h,n}      (:, keep{n});
                    I2.VCV2SQ{h,n}        = I2.VCV2SQ{h,n}       (:, keep{n});
                    I2.VCV2SEL{h,n}       = I2.VCV2SEL{h,n}      (:, keep{n});
                    I2.VCV2PROB{h,n}      = I2.VCV2PROB{h,n}     (:, keep{n});
                    I2.SignPosCount{h,n}  = I2.SignPosCount{h,n} (:, keep{n});
                    I2.SignNegCount{h,n}  = I2.SignNegCount{h,n} (:, keep{n});
                    if permfl
                        I2.VCV2PERM{h,n}  = I2.VCV2PERM{h, n}    (:, keep{n});
                        I2.VCV2PERM_FDR{h,n} = I2.VCV2PERM_FDR{h,n}(:, keep{n});
                        I2.VCV2ZSCORE{h,n}  = I2.VCV2ZSCORE{h, n}(:, keep{n});
                    end
                    % The 3D accumulators:
                    I2.GCV2SUM{h,n}       = I2.GCV2SUM{h,n}      (:, :, keep{n});
                    I2.VCV2STD{h,n}       = I2.VCV2STD{h,n}      (:, :, keep{n});
                    I2.VCV2MEAN{h,n}      = I2.VCV2MEAN{h,n}     (:, :, keep{n});
                end
            end
            if inp.isInter
                for n=1:nM
                    if ~decompfl(n), continue; end
                    % 2a) prune the CV2‐aggregates in intermediate fusion
                    % mode
                    I2.VCV2WPERMREF{h}{n} = I2.VCV2WPERMREF{h}{n}(keep{n},:);
                    I2.VCV2WCORRREF{h}{n} = I2.VCV2WCORRREF{h}{n}(keep{n},:);
                    I2.ModComp_L2n{h}{n} = I2.ModComp_L2n{h}{n}(keep{n},:);
                    % ----- Prune Dx / DxN after merge+prune (intermediate) -----
                    if isfield(I2,'DxSUM') 
                        if ~decompfl(n), continue; end
                        if ~isempty(I2.DxSUM{h}{n})
                            keepCols = keep{n};
                            nComp = size(I2.DxSUM{h}{n},2);
                            if numel(keepCols) > nComp
                                keepCols = keepCols(1:nComp);
                            end
                            I2.DxSUM{h}{n}  = I2.DxSUM{h}{n}(:, keepCols);
                            I2.DxSQSUM{h}{n}  = I2.DxSQSUM{h}{n}(:, keepCols);
                            I2.DxN{h}{n} = I2.DxN{h}{n}(:, keepCols);
                        end
                    end
                end
            else
                % 2b) prune the CV2‐aggregates in early fusion mode
                I2.VCV2WPERMREF{h} = I2.VCV2WPERMREF{h}(keep{1},:);
                I2.VCV2WCORRREF{h} = I2.VCV2WCORRREF{h}(keep{1},:);
                I2.ModComp_L2n{h} = I2.ModComp_L2n{h}(keep{1},:);
                if nM>1,I2.ModComp_L2nCube{h} = I2.ModComp_L2nCube{h}(keep{1},:,:); end
                % ----- Prune Dx / DxN after merge+prune (intermediate) -----
                if isfield(I2,'DxSUM') 
                    if ~isempty(I2.DxSUM{h})
                        keepCols = keep{1};
                        nComp = size(I2.DxSUM{h},2);
                        if numel(keepCols) > nComp
                            keepCols = keepCols(1:nComp);
                        end
                        I2.DxSUM{h}  = I2.DxSUM{h}(:, keepCols);
                        I2.DxSQSUM{h}  = I2.DxSQSUM{h}(:, keepCols);
                        I2.DxN{h} = I2.DxN{h}(:, keepCols);
                    end
                end
            end
        end

    case 'prune'

        if ~compwise 
            % Nothing to prune: we’re collapsing components into one signature.
            % Ensure VCV1/VCV2 arrays are treated as 2-D everywhere else.
            return
        end
        fprintf('\nPruning empty components to save disk space.')
        if exist('I1','var')
            if ischar(I1) && exist(I1,'file')
                try
                    load(I1); 
                    filefound = true;
                catch
                    fprintf('\nCould not load file %s ', I1);
                    filefound = false;
                    return;
                end
            elseif isstruct(I1) 
                filefound = true;
            end
        else
            error('Visualization structure I1 has to be provided!')
        end
        
        % Loop through classifiers
        for h = 1:nclass
                
            if any(decompfl)
                
                if inp.isInter
                    nonNaNrows = cell(nM,1);
                    for n=1:nM
                        if ~decompfl(n), continue; end
                        nonNaNrows{n} = ~all(isnan(I1.VCV1WPERMREF{h}{n}), 2);
                        I1.VCV1WPERMREF{h}{n} = I1.VCV1WPERMREF{h}{n}(nonNaNrows{n},:);
                        I1.VCV1WCORRREF{h}{n} = I1.VCV1WCORRREF{h}{n}(nonNaNrows{n},:);
                    end
                else
                    nonNaNrows = ~all(isnan(I1.VCV1WPERMREF{h}), 2);
                    I1.VCV1WPERMREF{h} = I1.VCV1WPERMREF{h}(nonNaNrows,:);
                    I1.VCV1WCORRREF{h} = I1.VCV1WCORRREF{h}(nonNaNrows,:);
                end
                
                % 1) Per-component L2n magnitudes (nRef × ll)
                if inp.isInter
                    for n=1:nM
                        if decompfl(n)
                            if isfield(I1,'ModComp_L2n') && numel(I1.ModComp_L2n) >= h && numel(I1.ModComp_L2n{h}) >=n && ~isempty(I1.ModComp_L2n{h}{n})
                                keepRows = nonNaNrows{n};
                                nRefLoc  = size(I1.ModComp_L2n{h}{n},1);
                                if numel(keepRows) > nRefLoc, keepRows = keepRows(1:nRefLoc); end
                                I1.ModComp_L2n{h}{n} = I1.ModComp_L2n{h}{n}(keepRows, :);
                            end
                        end
                    end
                else
                    if isfield(I1,'ModComp_L2n') && numel(I1.ModComp_L2n) >= h && ~isempty(I1.ModComp_L2n{h})
                        keepRows = nonNaNrows;
                        nRefLoc  = size(I1.ModComp_L2n{h},1);
                        if numel(keepRows) > nRefLoc, keepRows = keepRows(1:nRefLoc); end
                        I1.ModComp_L2n{h} = I1.ModComp_L2n{h}(keepRows, :);
                        % 2) Per-component, per-modality cube (nRef × nM × ll)
                        if isfield(I1,'ModComp_L2nCube') && numel(I1.ModComp_L2nCube) >= h && ~isempty(I1.ModComp_L2nCube{h})
                            keepRows = nonNaNrows;
                            nRefLoc  = size(I1.ModComp_L2nCube{h},1);
                            if numel(keepRows) > nRefLoc, keepRows = keepRows(1:nRefLoc); end
                            I1.ModComp_L2nCube{h} = I1.ModComp_L2nCube{h}(keepRows, :, :);
                        end
                    end
                end
 
                for n = 1:nM
   
                    % After nonNaNrows has been computed and applied to the class-level refs
                    if inp.isInter
                        keepIdxAll = find(nonNaNrows{n});   % numeric indices in class-ref component space
                    else
                        keepIdxAll = find(nonNaNrows);   
                    end

                    % --- VCV1 ---
                    if ~isempty(I1.VCV1{h,n})
                        nComp = size(I1.VCV1{h,n}, 3);
                        keepIdx = keepIdxAll(keepIdxAll <= nComp);   % clip to local size
                        if ~isempty(keepIdx)
                            I1.VCV1{h,n} = I1.VCV1{h,n}(:,:, keepIdx);
                        else
                            % nothing to keep for this modality — skip pruning to avoid empty 3rd dim
                            % (or, if you prefer, set to []; your choice)
                        end
                    end
                
                    if permfl
                        % --- VCV1PERM ---
                        if ~isempty(I1.VCV1PERM{h,n})
                            nComp = size(I1.VCV1PERM{h,n}, 3);
                            keepIdx = keepIdxAll(keepIdxAll <= nComp);
                            if ~isempty(keepIdx)
                                I1.VCV1PERM{h,n} = I1.VCV1PERM{h,n}(:,:, keepIdx);
                            end
                        end
                        % --- VCV1PERM_FDR ---
                        if ~isempty(I1.VCV1PERM_FDR{h,n})
                            nComp = size(I1.VCV1PERM_FDR{h,n}, 3);
                            keepIdx = keepIdxAll(keepIdxAll <= nComp);
                            if ~isempty(keepIdx)
                                I1.VCV1PERM_FDR{h,n} = I1.VCV1PERM_FDR{h,n}(:,:, keepIdx);
                            end
                        end
                        % --- VCV1ZSCORE ---
                        if ~isempty(I1.VCV1ZSCORE{h,n})
                            nComp = size(I1.VCV1ZSCORE{h,n}, 3);
                            keepIdx = keepIdxAll(keepIdxAll <= nComp);
                            if ~isempty(keepIdx)
                                I1.VCV1ZSCORE{h,n} = I1.VCV1ZSCORE{h,n}(:,:, keepIdx);
                            end
                        end
                    end
                    if inp.isInter
                        % --- Dx: prune component dimension identically to VCV1 ---
                        if isfield(I1,'Dx') && numel(I1.Dx,1) >= h && numel(I1.Dx{h}) >= n && ~isempty(I1.Dx{h}{n})
                            Dx_n  = I1.Dx{h}{n};         % [subj × CV1_model × comp]
                            nComp = size(Dx_n, 3);
                            keepIdx = keepIdxAll(keepIdxAll <= nComp);
                            if ~isempty(keepIdx)
                                I1.Dx{h}{n} = Dx_n(:,:, keepIdx);
                            end
                        end
                    elseif inp.isEarly && n==1
                        if isfield(I1,'Dx') && numel(I1.Dx,1) >= h
                            Dx_n  = I1.Dx{h};         % [subj × CV1_model × comp]
                            nComp = size(Dx_n, 3);
                            keepIdx = keepIdxAll(keepIdxAll <= nComp);
                            if ~isempty(keepIdx)
                                I1.Dx{h} = Dx_n(:,:, keepIdx);
                            end
                        end
                    end
                end
            end
         end

    case 'align'
         
         if exist('I1','var')
            if ischar(I1) && exist(I1,'file')
                try
                    load(I1); 
                    filefound = true;
                catch
                    fprintf('\nCould not load file %s ', I1);
                    filefound = false;
                    return;
                end
            else 
                filefound = true;
            end
         else
            error('Visualization structure I1 has to be provided!')
         end
         if ~compwise
            % Nothing to align if we are not in component-wise backprojection. 
            % Check also for late-fusion where each modality leads to a separate model 
            % we’re collapsing components into one signature.
            % Ensure VCV1/VCV2 arrays are treated as 2-D everywhere else.
            return
         end
        fprintf('\nRealigning compact component space to reference space.'); 
        
        for h = 1:nclass
            if ~exist('ill','var')
                if inp.isInter
                    ill = size(I1.VCV1WPERMREF{h}{1},2);
                else
                    ill = size(I1.VCV1WPERMREF{h},2);
                end
            end
        
            % --- fusion mode ---
            actMods  = find(decompfl~=0).';
            if numel(actMods)>1 && size(actMods,2)==1, actMods = actMods'; end
            if isempty(actMods), return; end
        
            % --- gather shapes ---
            nFolds_per_mod = zeros(1,nM);
            nFeat_per_mod  = zeros(1,nM);
            for n = actMods
                if ~isempty(I1.VCV1{h,n})
                    [nFeat_per_mod(n), nFolds_per_mod(n), ~] = size(I1.VCV1{h,n});
                end
            end
            nFolds = max(nFolds_per_mod);
        
            % --- ensure reference container shape ---
            if ~isfield(I2,'VCV1REF') || numel(I2.VCV1REF) < h || isempty(I2.VCV1REF{h})
                I2.VCV1REF{h} = cell(1,nM);
                I2.VCV1REFCNT{h} = cell(1,nM);
            elseif numel(I2.VCV1REF{h}) < nM
                I2.VCV1REF{h}(nM) = {[]};
                I2.VCV1REFCNT{h}(nM) = {[]};
            end
        
            % ==================== fold loop ====================
            for f = 1:nFolds
                
                CVPOS.CV1f = f;
                
                % 1) Build per-modality source cells (prune empty/NaN cols)
                src_cells   = cell(1,nM);
                validCols   = cell(1,nM);
                vc = cell(1,nM);
                for n = 1:nM
                    if size(I1.VCV1{h,n},3) >0
                        X = reshape(I1.VCV1{h,n}(:, f, :), size(I1.VCV1{h,n},1), []);
                    else
                        X = I1.VCV1{h,n}(:,f);
                    end
                    vc{n} = any(isfinite(X) & X ~= 0, 1);
                    validCols{n} = vc{n};
                    src_cells{n} = X(:, vc{n});
                end

                anyComp = any(cellfun(@(v) ~isempty(v) && any(v), validCols(actMods)));
                if ~anyComp
                    % nothing to align this fold
                    continue
                end
                nonZeroMasks = cell(1,nM);
                for n = actMods, nonZeroMasks{n} = validCols{n}; end
        
                if ~inp.isInter
                    % ================= EARLY FUSION (one joint call) =================
                    Ref_in = I2.VCV1REF{h};      % 1×nM cells (some may be empty)
                    Refcnt_in = I2.VCV1REFCNT{h};
                    Tx_in  = src_cells;          % 1×nM cells (pruned)
        
                    haveRef = any(~cellfun(@isempty, Ref_in));

                     % ----- Dx_in for early or late fusion: pass all modalities at once -----
                    if isfield(I1,'Dx') && numel(I1.Dx) >= h && ~isempty(I1.Dx{h})
                        Dx_slice = I1.Dx{h}(:, f, vc{1});  
                        nSubj = size(Dx_slice,1);
                        Dx_in    = {reshape(Dx_slice, size(Dx_slice,1), [])};  
                    else
                        Dx_in = [];
                        nSubj = 0;
                    end
        
                    [I1, Tx_out, ~, Dx_out, assignmentVec, ~, Ref_out, Refcnt_out] = nk_VisXRealignComponentsHelper( I1, inp, haveRef, Tx_in, Dx_in, Ref_in, Refcnt_in, nM, f, ill, [], h, I1.Fadd{h,f}, I1.Vind{h,f});
        
                    % --- detect growth & persist ---
                    nRef_old = 0;
                    if isfield(I2,'VCV1REF') && numel(I2.VCV1REF) >= h && ~isempty(I2.VCV1REF{h}) && ~isempty(I2.VCV1REF{h}{actMods(1)})
                        nRef_old = size(I2.VCV1REF{h}{actMods(1)}, 2);
                    end
                    colsPerMod_updated = cellfun(@(R) size(R,2), Ref_out(:)');
                    assert(all(colsPerMod_updated == colsPerMod_updated(1)), 'Post-align ref must have equal columns per modality.');
                    nRef_new = colsPerMod_updated(1);
                    grew     = (nRef_new > nRef_old);
                    
                    if grew
                        % persist updated ref & meta
                        I2.VCV1REF{h} = Ref_out;
                        I2.VCV1REFCNT{h} = Refcnt_out;
                    end

                    % --- scatter aligned maps back to cubes (ref-ordered columns) ---
                    nRef_combined = nRef_new;
                    for n = actMods
                        Aln_n = Tx_out{n};  % [nFeat_n x nRef_combined]
                        old3 = size(I1.VCV1{h,n},3);
                        if nRef_combined > old3
                            I1.VCV1{h,n}(:,:,old3+1:nRef_combined) = NaN;
                            if isfield(I1,'Dx') && ~isempty(I1.Dx{h})
                                I1.Dx{h}(:,:,old3+1:nRef_combined) = NaN;
                            end
                        end
                        I1.VCV1{h,n}(:, f, 1:nRef_combined) = reshape(Aln_n, [size(Aln_n,1), 1, nRef_combined]);
                        if isfield(I1,'Dx') && ~isempty(I1.Dx{h})
                            I1.Dx{h}(:, f, 1:nRef_combined) = reshape(Dx_out{1}, [nSubj, 1, nRef_combined]);
                        end
                    end
                    
                    % --- perm-stat cubes: realign with same assignment (unchanged logic) ---
                    if permfl
                        for fld = {'VCV1PERM','VCV1PERM_FDR','VCV1ZSCORE'}
                            srcP_cells = cell(1,nM);
                            for n = actMods
                                A = I1.(fld{1}){h,n};                 % [nFeat x nFolds x nComp]
                                if isempty(A), srcP_cells{n} = []; continue; end
                                slice = squeeze(A(:,f,:));             % [nFeat x nComp]
                                vc    = validCols{n};                  % same pruning as maps
                                srcP_cells{n} = slice(:, vc);
                            end
                            for n = actMods
                                if isempty(I1.(fld{1}){h,n}), continue; end
                                srcPn = full(srcP_cells{n});
                                AlnPn = nan(size(srcPn,1), nRef_combined);
                                keep  = assignmentVec > 0 & assignmentVec <= size(srcPn,2);
                                if any(keep), AlnPn(:, keep) = srcPn(:, assignmentVec(keep)); end
                                old3 = size(I1.(fld{1}){h,n},3);
                                if nRef_combined > old3
                                    I1.(fld{1}){h,n}(:,:,old3+1:nRef_combined) = NaN;
                                end
                                I1.(fld{1}){h,n}(:, f, 1:nRef_combined) = reshape(AlnPn, [size(AlnPn,1), 1, nRef_combined]);
                            end
                        end
                    end
                else
                    % ================ INTERMEDIATE FUSION (loop DR mods) ================
                    for n = actMods
                        Ref_in = I2.VCV1REF{h}{n};         % 1x1 cell
                        Refcnt_in = I2.VCV1REFCNT{h}{n};         % 1x1 cell
                        Tx_in  = src_cells{n};             % 1x1 cell
                        haveRef_n = ~isempty(Ref_in);

                         % ----- Dx_in for early or late fusion: pass all modalities at once -----
                         if isfield(I1,'Dx') && numel(I1.Dx) >= h && ~isempty(I1.Dx{h}) && numel(I1.Dx{h}) >= n && ~isempty(I1.Dx{h}{n})
                            Dx_slice = I1.Dx{h}{n}(:, f, vc{n});  
                            Dx_in = reshape(Dx_slice, size(Dx_slice,1), []);  
                            nSubj = size(Dx_slice,1);
                        else
                            Dx_in = [];
                            nSubj = 0;
                        end
        
                        [I1, Tx_out, ~, Dx_out, aVec_n, ~, Ref_out, Refcnt_out] = ...
                            nk_VisXRealignComponentsHelper(I1, inp, haveRef_n, Tx_in, Dx_in, Ref_in, Refcnt_in, nM, f, ill, n, h, I1.Fadd{h,f}, I1.Vind{h,f});
        
                        % --- detect growth & persist (per modality) ---
                        nRef_old = 0;
                        if ~isempty(I2.VCV1REF{h}{n}), nRef_old = size(I2.VCV1REF{h}{n}, 2); end
                        nRef = size(Ref_out, 2);
                        grew = (nRef > nRef_old);
                        
                        if grew
                            % persist updated ref
                            I2.VCV1REF{h}{n} = Ref_out;
                            I2.VCV1REFCNT{h}{n} = Refcnt_out;
                        end
                        
                        % --- scatter aligned map for modality n (ref order) ---
                        Aln_n = full(Tx_out);                  % [nFeat_n x nRef_n]
                        old3  = size(I1.VCV1{h,n},3);
                        if nRef > old3
                            I1.VCV1{h,n}(:,:,old3+1:nRef) = NaN;
                            if isfield(I1,'Dx') && ~isempty(I1.Dx{h})
                                I1.Dx{h}{n}(:,:,old3+1:nRef) = NaN;
                            end
                        end
                        I1.VCV1{h,n}(:, f, 1:nRef) = reshape(Aln_n, [size(Aln_n,1), 1, nRef]);
                        if isfield(I1,'Dx') && ~isempty(I1.Dx{h})
                            I1.Dx{h}{n}(:, f, 1:nRef) = reshape(Dx_out, [nSubj, 1, nRef]);
                        end

                        % --- perm-stat cubes for modality n (realign using same assignment) ---
                        if permfl && ~isempty(I1.VCV1PERM{h,n})
                            for fld = {'VCV1PERM','VCV1PERM_FDR','VCV1ZSCORE'}
                                A = I1.(fld{1}){h,n};                   % [nFeat x nFolds x nComp]
                                if isempty(A), continue; end
                                slice = squeeze(A(:,f,:));              % [nFeat x nComp]
                                vc    = validCols{n};                   % same pruning
                                srcPn = slice(:, vc);
                                AlnPn = nan(size(srcPn,1), nRef);
                                keepP = aVec_n > 0 & aVec_n <= size(srcPn,2);
                                if any(keepP), AlnPn(:, keepP) = srcPn(:, aVec_n(keepP)); end
                                old3 = size(I1.(fld{1}){h,n},3);
                                if nRef > old3
                                    I1.(fld{1}){h,n}(:,:,old3+1:nRef) = NaN;
                                end
                                I1.(fld{1}){h,n}(:, f, 1:nRef) = reshape(AlnPn, [size(AlnPn,1), 1, nRef]);
                            end
                        end
                    end
                end
            end
        end
        
    case 'accum'
        
        fprintf('\nComputing CV1 space stats and adding results to CV2-level container.')

        for h = 1:nclass
        
            if permfl || sigfl
                I2.VCV2MPERM(h,ll)     = mean(I1.VCV1MPERM{h});
                I2.VCV2MPERM_CV2(h,ll) = (sum(I1.VCV1MPERM_CV2{h}) + 1) / (nperms(1) + 1);
            end
            if nM>1 % modality shares
                % ----- aggregate modality shares (always available) -----
                if ~isempty(I1.ModAgg_L2nShare{h})
                    cv2Col = mean(I1.ModAgg_L2nShare{h}, 2, 'omitnan');   % [nM×1]
                    if isempty(I2.ModAgg_L2nShare{h})
                        I2.ModAgg_L2nShare{h} = cv2Col;
                    else
                        I2.ModAgg_L2nShare{h}(:, end+1) = cv2Col;
                    end
                end
            end
        
            % Loop through modalities
            for n = 1:nM
        
                [D, ~, ~, badcoords] = getD(FUSION.flag, inp, n);
                badcoords = ~badcoords;
        
                % ===== CV1-level summaries (work for 2-D or 3-D; keep unchanged) =====
                I1.VCV1NMODEL(h) = size(I1.VCV1{h,n},2);
                extra = 0;
                if ~isempty(I2.VCV2SUM{h,n}) && decompfl(n) && compwise
                        nCompNew = size(I1.VCV1{h,n},3);
                        nCompOld = size(I2.GCV2SUM{h,n},3);
                        extra = nCompNew - nCompOld;
                        if extra<0, I1.VCV1{h,n} = pad3D(I1.VCV1{h,n}, -1*extra); end
                end
        
                I1.VCV1SEL{h,n}  = squeeze(sum(~isnan(I1.VCV1{h,n}), 2, 'omitnan'));
                I1.VCV1SEL{h,n}(all(I1.VCV1SEL{h,n}==0, 2 ), :) = NaN;
                I1.VCV1MEAN{h,n} = squeeze(median(I1.VCV1{h,n}, 2, 'omitnan')); 
                I1.VCV1SUM{h,n}  = squeeze(sum(I1.VCV1{h,n}, 2, 'omitnan'));
                I1.VCV1SQ{h,n}   = squeeze(sum(I1.VCV1{h,n}.^2, 2, 'omitnan'));
                if inp.CVRnorm == 1
                    I1.VCV1STD{h,n} = squeeze(std(I1.VCV1{h,n}, [], 2, 'omitnan'));
                else
                    I1.VCV1STD{h,n} = (squeeze(std(I1.VCV1{h,n}, [], 2, 'omitnan')) ./ sqrt(I1.VCV1NMODEL(h)))*1.96;
                end

                if ~decompfl(n)
                    % --- NON-DR containers (unchanged) ---
                    if isempty(I2.PCV2SUM{h,n})
                        I2.PCV2SUM{h,n}(badcoords) = I1.VCV1SUM{h,n}(badcoords);
                    else
                        I2.PCV2SUM{h,n}(badcoords) = I2.PCV2SUM{h,n}(badcoords)' + I1.VCV1SUM{h,n}(badcoords);
                    end
                    I2.VCV2PEARSON{h,n}              = [I2.VCV2PEARSON{h,n}              mean(I1.VCV1PEARSON{h,n}, 2, 'omitnan')];
                    I2.VCV2SPEARMAN{h,n}             = [I2.VCV2SPEARMAN{h,n}             mean(I1.VCV1SPEARMAN{h,n}, 2, 'omitnan')];
                    I2.VCV2PEARSON_UNCORR_PVAL{h,n}  = [I2.VCV2PEARSON_UNCORR_PVAL{h,n}  mean(-log10(I1.VCV1PEARSON_UNCORR_PVAL{h,n}), 2, 'omitnan')];
                    I2.VCV2SPEARMAN_UNCORR_PVAL{h,n} = [I2.VCV2SPEARMAN_UNCORR_PVAL{h,n} mean(-log10(I1.VCV1SPEARMAN_UNCORR_PVAL{h,n}), 2, 'omitnan')];
                    I2.VCV2PEARSON_FDR_PVAL{h,n}     = [I2.VCV2PEARSON_FDR_PVAL{h,n}     mean(-log10(I1.VCV1PEARSON_FDR_PVAL{h,n}), 2, 'omitnan')];
                    I2.VCV2SPEARMAN_FDR_PVAL{h,n}    = [I2.VCV2SPEARMAN_FDR_PVAL{h,n}    mean(-log10(I1.VCV1SPEARMAN_FDR_PVAL{h,n}), 2, 'omitnan')];
                    if linsvmfl && isfield(I1,'VCV1PVAL_ANALYTICAL')
                        I2.VCV2PVAL_ANALYTICAL{h,n}     = [I2.VCV2PVAL_ANALYTICAL{h,n}     mean(-log10(I1.VCV1PVAL_ANALYTICAL{h,n}), 2, 'omitnan')];
                        I2.VCV2PVAL_ANALYTICAL_FDR{h,n} = [I2.VCV2PVAL_ANALYTICAL_FDR{h,n} mean(-log10(I1.VCV1PVAL_ANALYTICAL_FDR{h,n}), 2, 'omitnan')];
                    end
                    if isfield(I1,"VCV1CORRMAT") && ~isempty(I1.VCV1CORRMAT{h,n})
                        I2.VCV2CORRMAT{h,n}(:,:,ll)              = mean(I1.VCV1CORRMAT{h,n}, 3, 'omitnan');
                        I2.VCV2CORRMAT_UNCORR_PVAL{h,n}(:,:,ll)  = mean(-log10(I1.VCV1CORRMAT_UNCORR_PVAL{h,n}), 3, 'omitnan');
                        I2.VCV2CORRMAT_FDR_PVAL{h,n}(:,:,ll)     = mean(-log10(I1.VCV1CORRMAT_FDR_PVAL{h,n}), 3, 'omitnan');
                    end
        
                % --- DR + NO-COMPONENT: intentionally do NOT write the non-DR-only containers above ---
                elseif any(decompfl) && ~compwise
                    % (no action here — we’ll fall through to the common CV1 summaries below
                    %  and to the DR accumulators which also work with nComp==1)
        
                end
        
                % ===== PERM accumulation (make modality-local) =====
                if permfl
                    if ~decompfl(n)
                        % non-DR (unchanged)
                        if isempty(I2.VCV2PERM{h, n})
                            I2.VCV2PERM    {h, n}   = double(sum(I1.VCV1PERM{h, n}, 2, 'omitnan'));
                            I2.VCV2PERM_FDR{h, n}   = double(sum(I1.VCV1PERM_FDR{h, n}, 2, 'omitnan'));
                            I2.VCV2ZSCORE  {h, n}   = double(sum(I1.VCV1ZSCORE{h, n}, 2, 'omitnan'));
                        else
                            I2.VCV2PERM    {h, n}   = I2.VCV2PERM{h,n}       + double(sum(I1.VCV1PERM{h, n}, 2, 'omitnan'));
                            I2.VCV2PERM_FDR{h, n}   = I2.VCV2PERM_FDR{h,n}   + double(sum(I1.VCV1PERM_FDR{h, n}, 2, 'omitnan'));
                            I2.VCV2ZSCORE  {h, n}   = I2.VCV2ZSCORE{h,n}     + double(sum(I1.VCV1ZSCORE{h, n}, 2, 'omitnan'));
                        end
                    else
                        % DR (works for component-wise and no-component; nComp==1 in the latter)
                        % Get target component counts so reshape never collapses to 1-D
                        nC_perm    = size(I1.VCV1PERM{h,n},      3);
                        nC_permFDR = size(I1.VCV1PERM_FDR{h,n},  3);
                        nC_zs      = size(I1.VCV1ZSCORE{h,n},    3);
                        
                        % Sum across CV1 folds (dim=2) and force [feat × nComp]
                        newPerm    = double( reshape(sum(I1.VCV1PERM{h,n},     2, 'omitnan'), [], nC_perm) );
                        newPermFDR = double( reshape(sum(I1.VCV1PERM_FDR{h,n}, 2, 'omitnan'), [], nC_permFDR) );
                        newZS      = double( reshape(sum(I1.VCV1ZSCORE{h,n},   2, 'omitnan'), [], nC_zs) );
                                
                        if isempty(I2.VCV2PERM{h,n})
                            I2.VCV2PERM{h,n}     = newPerm;
                            I2.VCV2PERM_FDR{h,n} = newPermFDR;
                            I2.VCV2ZSCORE{h,n}   = newZS;
                        else
                            [I2.VCV2PERM{h,n},     newPerm]    = harmonizeSize(I2.VCV2PERM{h,n},     newPerm);
                            [I2.VCV2PERM_FDR{h,n}, newPermFDR] = harmonizeSize(I2.VCV2PERM_FDR{h,n}, newPermFDR);
                            [I2.VCV2ZSCORE{h,n},   newZS]      = harmonizeSize(I2.VCV2ZSCORE{h,n},   newZS);
                            I2.VCV2PERM{h,n}     = nk_NanMatrixAddition(I2.VCV2PERM{h,n},     newPerm);
                            I2.VCV2PERM_FDR{h,n} = nk_NanMatrixAddition(I2.VCV2PERM_FDR{h,n}, newPermFDR);
                            I2.VCV2ZSCORE{h,n}   = nk_NanMatrixAddition(I2.VCV2ZSCORE{h,n},   newZS);
                        end
                    end
                end
        
                % ===== CV2-level init/updates (keep DR path; nComp may be 1) =====
                indMEANgrSE = abs(I1.VCV1MEAN{h,n}) > I1.VCV1STD{h,n};
                if isempty(I2.VCV2SUM{h,n})
                    if ~decompfl(n)
                        I2.GCV2SUM  {h,n} = I1.VCV1SUM {h,n};
                        I2.VCV2MEAN {h,n} = I1.VCV1MEAN{h,n};
                        I2.VCV2STD  {h,n} = I1.VCV1STD {h,n};
                    else
                        nComp = size(I1.VCV1SUM{h,n},2);   % =1 in no-component DR
                        I2.GCV2SUM  {h,n}        = nan(D, ix*jx, nComp, 'double');
                        I2.VCV2MEAN {h,n}        = nan(D, ix*jx, nComp, 'double');
                        I2.VCV2STD  {h,n}        = nan(D, ix*jx, nComp, 'double');
                        I2.GCV2SUM  {h,n}(:,1,:) = I1.VCV1SUM {h,n};
                        I2.VCV2MEAN {h,n}(:,1,:) = I1.VCV1MEAN{h,n};
                        I2.VCV2STD  {h,n}(:,1,:) = I1.VCV1STD {h,n};
                    end
        
                    E = I1.VCV1{h,n};
                    notfiniteE = ~isfinite(E);
                    posE = single(E > 0); posE(notfiniteE) = NaN;
                    negE = single(E < 0); negE(notfiniteE) = NaN; 
                    clear E
                    I2.SignPosCount{h,n} = squeeze(sum(posE, 2, 'omitnan'));
                    I2.SignNegCount{h,n} = squeeze(sum(negE, 2, 'omitnan'));
                    I2.VCV2SUM   {h,n}   = I1.VCV1SUM  {h,n};
                    I2.VCV2SQ    {h,n}   = I1.VCV1SQ   {h,n};
                    I2.VCV2SEL   {h,n}   = I1.VCV1SEL  {h,n};
                    I2.VCV2PROB  {h,n}   = single(indMEANgrSE);
                else
                    if any(decompfl)
                        if extra>0
                            I2.GCV2SUM   {h,n} = pad3D(I2.GCV2SUM   {h,n}, extra);
                            I2.VCV2MEAN  {h,n} = pad3D(I2.VCV2MEAN  {h,n}, extra);
                            I2.VCV2STD   {h,n} = pad3D(I2.VCV2STD   {h,n}, extra);
                            I2.VCV2SUM   {h,n} = pad3D(I2.VCV2SUM   {h,n}, extra);
                            I2.VCV2SQ    {h,n} = pad3D(I2.VCV2SQ    {h,n}, extra);
                            I2.VCV2SEL   {h,n} = pad3D(I2.VCV2SEL   {h,n}, extra);
                            I2.VCV2PROB  {h,n} = pad3D(I2.VCV2PROB  {h,n}, extra);
                            I2.SignPosCount{h,n} = pad3D(I2.SignPosCount{h,n}, extra);
                            I2.SignNegCount{h,n} = pad3D(I2.SignNegCount{h,n}, extra);
                        end
                        I2.GCV2SUM   {h,n}(:,ll,:) = I1.VCV1SUM {h,n};
                        I2.VCV2MEAN  {h,n}(:,ll,:) = I1.VCV1MEAN{h,n};
                        I2.VCV2STD   {h,n}(:,ll,:) = I1.VCV1STD {h,n};
                    end
        
                    E = I1.VCV1{h,n};
                    notfiniteE = ~isfinite(E);
                    posE = single(E > 0); posE(notfiniteE) = NaN; posCount = squeeze(sum(posE, 2, 'omitnan'));
                    negE = single(E < 0); negE(notfiniteE) = NaN; negCount = squeeze(sum(negE, 2, 'omitnan'));
                    I2.SignPosCount{h,n} = nk_NanMatrixAddition(I2.SignPosCount{h,n}, posCount);
                    I2.SignNegCount{h,n} = nk_NanMatrixAddition(I2.SignNegCount{h,n}, negCount);
                    I2.VCV2SUM{h,n} = nk_NanMatrixAddition(I2.VCV2SUM{h,n}, I1.VCV1SUM{h,n});
                    I2.VCV2SQ{h,n} = nk_NanMatrixAddition(I2.VCV2SQ{h,n},  I1.VCV1SQ{h,n});
                    I2.VCV2SEL{h,n} = nk_NanMatrixAddition(I2.VCV2SEL{h,n}, I1.VCV1SEL{h,n});
                    I2.VCV2PROB{h,n} = nk_NanMatrixAddition(I2.VCV2PROB{h,n}, indMEANgrSE);
                end
            end
        
            I2.VCV2NMODEL(h) = I2.VCV2NMODEL(h) + I1.VCV1NMODEL(h);
            % per-fold model counts (columns contributed this cycle)
            if ~isfield(I2,'VCV2NMODEL_PERFOLD') || numel(I2.VCV2NMODEL_PERFOLD) < h || isempty(I2.VCV2NMODEL_PERFOLD{h})
                I2.VCV2NMODEL_PERFOLD{h} = I1.VCV1NMODEL(h);
            else
                I2.VCV2NMODEL_PERFOLD{h}(end+1,1) = I1.VCV1NMODEL(h);
            end

            % keep WPERMREF/WCORRREF only for component-wise DR
            if any(decompfl) && compwise
           
                actMods     = find(decompfl(:)~=0).';
                subjIdx     = CV.TestInd{CVPOS.CV2p, CVPOS.CV2f}; 
                maxSubj     = size(inp.labels,1);

                if ~inp.isInter
                    % ========================= EARLY FUSION (original behavior) =========================
                    % ---------- pull current combined-space columns once ----------
                    curW = []; curC = [];
                    if isfield(I1,'VCV1WPERMREF') && numel(I1.VCV1WPERMREF) >= h && ~isempty(I1.VCV1WPERMREF{h})
                        curW = I1.VCV1WPERMREF{h};   % [nComponents × nCV1_models]
                    end
                    if isfield(I1,'VCV1WCORRREF') && numel(I1.VCV1WCORRREF) >= h && ~isempty(I1.VCV1WCORRREF{h})
                        curC = I1.VCV1WCORRREF{h};   % [nComponents × nCV1_models]
                    end
            
                    % --- ensure reference space grows in lock-step with WPERMREF rows ---
                    % authoritative reference size AFTER prune_memory
                    refCols = size(I2.VCV1REF{h}{1}, 2);   % authoritative after prune/merge
                    nCur    = size(curW,1);                % == size(curC,1)
                    
                    % Harmonize CV1 contributions to refCols
                    if nCur > refCols
                        curW = curW(1:refCols, :);
                        curC = curC(1:refCols, :);
                    elseif nCur < refCols
                        if ~isempty(curW) && size(curW,1) < refCols, curW(end+1:refCols, :) = NaN; end
                        if ~isempty(curC) && size(curC,1) < refCols, curC(end+1:refCols, :) = NaN; end
                    end
                    
                    % Ensure presence tables have refCols rows (grow rows, NOT reference)
                    if isempty(I2.VCV2WPERMREF{h}), I2.VCV2WPERMREF{h} = nan(refCols, 0); end
                    if size(I2.VCV2WPERMREF{h},1) < refCols
                        I2.VCV2WPERMREF{h} = [I2.VCV2WPERMREF{h}; nan(refCols - size(I2.VCV2WPERMREF{h},1), size(I2.VCV2WPERMREF{h},2))];
                    end
                    if isempty(I2.VCV2WCORRREF{h}), I2.VCV2WCORRREF{h} = nan(refCols, 0); end
                    if size(I2.VCV2WCORRREF{h},1) < refCols
                        I2.VCV2WCORRREF{h} = [I2.VCV2WCORRREF{h}; nan(refCols - size(I2.VCV2WCORRREF{h},1), size(I2.VCV2WCORRREF{h},2))];
                    end
                    
                    % Append (ref count stays fixed)
                    I2.VCV2WPERMREF{h} = [I2.VCV2WPERMREF{h}, curW];
                    I2.VCV2WCORRREF{h} = [I2.VCV2WCORRREF{h}, curC];

                    % ===== Accumulate Dx (fractionated decision scores) at CV2 level =====
                    if isfield(I1,'Dx') && numel(I1.Dx) >= h 

                        Dx3 = squeeze(sum(I1.Dx{h},2,'omitnan')) ;   
                        DxSQ3 = squeeze(sum(I1.Dx{h}.^2,2,'omitnan')) ;   
                        DxN3 = squeeze(sum(~isnan(I1.Dx{h}),2,'omitnan'));  
                        
                        % --- transfer to I2.DxSUM / I2.DxN  ---
                        if isempty(I2.DxSUM{h})
                            nRef                       = size(Dx3,2);
                            I2.DxSUM{h}                = nan(maxSubj,nRef);
                            I2.DxSQSUM{h}              = nan(maxSubj,nRef);
                            I2.DxN{h}                  = nan(maxSubj,nRef);
                            I2.DxSUM{h}(subjIdx,:)     = Dx3;
                            I2.DxSQSUM{h}(subjIdx,:)   = DxSQ3;
                            I2.DxN{h}(subjIdx,:)       = DxN3;
                        else
                            I2.DxSUM{h} = harmonizeSize(I2.DxSUM{h}, Dx3); 
                            I2.DxSQSUM{h} = harmonizeSize(I2.DxSQSUM{h}, DxSQ3); 
                            I2.DxN{h} = harmonizeSize(I2.DxN{h}, DxN3);
                            I2.DxSUM{h}(subjIdx,:)     = nk_NanMatrixAddition(I2.DxSUM{h}(subjIdx,:), Dx3);
                            I2.DxSQSUM{h}(subjIdx,:)   = nk_NanMatrixAddition(I2.DxSQSUM{h}(subjIdx,:), DxSQ3);
                            I2.DxN{h}(subjIdx,:)       = nk_NanMatrixAddition(I2.DxN{h}(subjIdx,:),DxN3);
                        end
                    end
                else
                    % ========================= INTERMEDIATE FUSION (per-modality) =========================
                    % CV1 containers are per-modality cells: I1.VCV1WPERMREF{h}{n}, I1.VCV1WCORRREF{h}{n}
                    % Accumulate into per-mod CV2 cells: I2.VCV2WPERMREF{h}{n}, I2.VCV2WCORRREF{h}{n}
                    % pull per-modality CV1 WPERMREF / WCORRREF for this CV2 fold
                    curW = [];
                    curC = [];
                    
                    % ensure CV2 cell arrays exist for this class
                    if ~isfield(I2,'VCV2WPERMREF') || numel(I2.VCV2WPERMREF) < h || isempty(I2.VCV2WPERMREF{h})
                        I2.VCV2WPERMREF{h} = cell(1,nM);
                    end
                    if ~isfield(I2,'VCV2WCORRREF') || numel(I2.VCV2WCORRREF) < h || isempty(I2.VCV2WCORRREF{h})
                        I2.VCV2WCORRREF{h} = cell(1,nM);
                    end

                    if isfield(I1,'VCV1WPERMREF') && numel(I1.VCV1WPERMREF) >= h && ...
                            ~isempty(I1.VCV1WPERMREF{h}) && numel(I1.VCV1WPERMREF{h}) >= n && ...
                            ~isempty(I1.VCV1WPERMREF{h}{n})
                        curW = I1.VCV1WPERMREF{h}{n};    % [nRef_n × nCV1_models]
                    end
                    if isfield(I1,'VCV1WCORRREF') && numel(I1.VCV1WCORRREF) >= h && ...
                            ~isempty(I1.VCV1WCORRREF{h}) && numel(I1.VCV1WCORRREF{h}) >= n && ...
                            ~isempty(I1.VCV1WCORRREF{h}{n})
                        curC = I1.VCV1WCORRREF{h}{n};    % [nRef_n × nCV1_models]
                    end
            
                    for n = actMods
                        refCols = size(I2.VCV1REF{h}{n}, 2);
                        nCur    = size(curW,1);   % == size(curC,1)
                        
                        if nCur > refCols
                            curW = curW(1:refCols, :);
                            curC = curC(1:refCols, :);
                        elseif nCur < refCols
                            if ~isempty(curW) && size(curW,1) < refCols, curW(end+1:refCols, :) = NaN; end
                            if ~isempty(curC) && size(curC,1) < refCols, curC(end+1:refCols, :) = NaN; end
                        end
                        
                        if isempty(I2.VCV2WPERMREF{h}{n}), I2.VCV2WPERMREF{h}{n} = nan(refCols, 0); end
                        if size(I2.VCV2WPERMREF{h}{n},1) < refCols
                            I2.VCV2WPERMREF{h}{n} = [I2.VCV2WPERMREF{h}{n}; nan(refCols - size(I2.VCV2WPERMREF{h}{n},1), size(I2.VCV2WPERMREF{h}{n},2))];
                        end
                        if isempty(I2.VCV2WCORRREF{h}{n}), I2.VCV2WCORRREF{h}{n} = nan(refCols, 0); end
                        if size(I2.VCV2WCORRREF{h}{n},1) < refCols
                            I2.VCV2WCORRREF{h}{n} = [I2.VCV2WCORRREF{h}{n}; nan(refCols - size(I2.VCV2WCORRREF{h}{n},1), size(I2.VCV2WCORRREF{h}{n},2))];
                        end
                        
                        I2.VCV2WPERMREF{h}{n} = [I2.VCV2WPERMREF{h}{n}, curW];
                        I2.VCV2WCORRREF{h}{n} = [I2.VCV2WCORRREF{h}{n}, curC];
                        % ===== Accumulate Dx (fractionated decision scores) at CV2 level =====
                        if isfield(I1,'Dx') && numel(I1.Dx) >= h && numel(I1.Dx{h}) >= n && ~isempty(I1.Dx{h}{n})
                            
                            Dx3 = squeeze(sum(I1.Dx{h}{n},2,'omitnan'));
                            DxSQ3 = squeeze(sum(I1.Dx{h}{n}.^2,2,'omitnan'));
                            DxN3 = squeeze(sum(~isnan(I1.Dx{h}{n}),2,'omitnan'));  
                            
                            % --- transfer to I2.DxSUM for this modality ---
                            if ~isfield(I2,'DxSUM') || isempty(I2.DxSUM{h}{n})
                                nRef_n                      = size(Dx3,2);
                                I2.DxSUM{h}{n}              = nan(maxSubj, nRef_n);
                                I2.DxSQSUM{h}{n}            = nan(maxSubj, nRef_n);
                                I2.DxN{h}{n}                = nan(maxSubj, nRef_n);
                                I2.DxSUM{h}{n}(subjIdx,:)   = Dx3;
                                I2.DxSQSUM{h}{n}(subjIdx,:) = DxSQ3;
                                I2.DxN{h}{n}(subjIdx,:)     = DxN3;
                            else
                                I2.DxSUM{h}{n} = harmonizeSize(I2.DxSUM{h}{n}, Dx3); 
                                I2.DxSQSUM{h}{n} = harmonizeSize(I2.DxSQSUM{h}{n}, DxSQ3); 
                                I2.DxN{h}{n} = harmonizeSize(I2.DxN{h}{n}, DxN3);
                                I2.DxSUM{h}{n}(subjIdx,:)   = nk_NanMatrixAddition(I2.DxSUM{h}{n}(subjIdx,:),Dx3);
                                I2.DxSQSUM{h}{n}(subjIdx,:) = nk_NanMatrixAddition(I2.DxSQSUM{h}{n}(subjIdx,:),DxSQ3);
                                I2.DxN{h}{n}(subjIdx,:)     = nk_NanMatrixAddition(I2.DxN{h}{n}(subjIdx,:),DxN3);
                            end
            
                        end
                    end
                end
            
                % ========================= L2 aggregates (same handling for both modes) =========================
                if nM > 1
                    % fold-level modality shares, aggregated across CV1 models of this CV2 cycle
                    if ~isfield(I1,'ModAgg_L2nShare') || numel(I1.ModAgg_L2nShare) < h || isempty(I1.ModAgg_L2nShare{h})
                        I1.ModAgg_L2nShare{h} = nan(nM, ll);
                    end
                    cv2ColShare = mean(I1.ModAgg_L2nShare{h}, 2, 'omitnan');   % [nM × 1]
                    if ~isfield(I2,'ModAgg_L2nShare') || numel(I2.ModAgg_L2nShare) < h || isempty(I2.ModAgg_L2nShare{h})
                        I2.ModAgg_L2nShare{h} = cv2ColShare;
                    else
                        I2.ModAgg_L2nShare{h}(:, end+1) = cv2ColShare;
                    end
                end
            
                if compwise
                    if ~inp.isInter
                        % ---------- EARLY: combined per-component L2 ----------
                        % ensure I1 combined vector exists and tall enough
                        if ~isfield(I1,'ModComp_L2n') || numel(I1.ModComp_L2n) < h || isempty(I1.ModComp_L2n{h})
                            I1.ModComp_L2n{h} = nan(nCur, ll);
                        elseif size(I1.ModComp_L2n{h},1) < nCur
                            I1.ModComp_L2n{h}(end+1:nCur,:) = NaN;
                        end
                        L2_cv2_col = mean(I1.ModComp_L2n{h}, 2, 'omitnan');   % [nComponents × 1]
            
                        if ~isfield(I2,'ModComp_L2n') || numel(I2.ModComp_L2n) < h || isempty(I2.ModComp_L2n{h})
                            I2.ModComp_L2n{h} = L2_cv2_col;
                        else
                            rTarget = max(size(I2.ModComp_L2n{h},1), numel(L2_cv2_col));
                            if size(I2.ModComp_L2n{h},1) < rTarget
                                c = size(I2.ModComp_L2n{h},2);
                                I2.ModComp_L2n{h} = [I2.ModComp_L2n{h}; nan(rTarget - size(I2.ModComp_L2n{h},1), c)];
                            end
                            if numel(L2_cv2_col) < rTarget, L2_cv2_col(rTarget,1) = NaN; end
                            I2.ModComp_L2n{h}(:, end+1) = L2_cv2_col;
                        end
            
                        if nM>1
                            % combined per-component × modality L2 cube
                            if ~isfield(I1,'ModComp_L2nCube') || numel(I1.ModComp_L2nCube) < h || isempty(I1.ModComp_L2nCube{h})
                                I1.ModComp_L2nCube{h} = nan(nCur, nM, ll);
                            elseif size(I1.ModComp_L2nCube{h},1) < nCur
                                I1.ModComp_L2nCube{h} = cat(1, I1.ModComp_L2nCube{h}, nan(nCur - size(I1.ModComp_L2nCube{h},1), nM, size(I1.ModComp_L2nCube{h},3)));
                            end
                            L2_cv2_slice = mean(I1.ModComp_L2nCube{h}, 3, 'omitnan');   % [nRef_combined × nM]
            
                            if ~isfield(I2,'ModComp_L2nCube') || numel(I2.ModComp_L2nCube) < h || isempty(I2.ModComp_L2nCube{h})
                                I2.ModComp_L2nCube{h} = reshape(L2_cv2_slice, size(L2_cv2_slice,1), size(L2_cv2_slice,2), 1);
                            else
                                rTarget = max(size(I2.ModComp_L2nCube{h},1), size(L2_cv2_slice,1));
                                if size(I2.ModComp_L2nCube{h},1) < rTarget
                                    I2.ModComp_L2nCube{h} = cat(1, I2.ModComp_L2nCube{h}, ...
                                        nan(rTarget - size(I2.ModComp_L2nCube{h},1), size(I2.ModComp_L2nCube{h},2), size(I2.ModComp_L2nCube{h},3)));
                                end
                                if size(L2_cv2_slice,1) < rTarget
                                    pad = nan(rTarget - size(L2_cv2_slice,1), size(L2_cv2_slice,2));
                                    L2_cv2_slice = [L2_cv2_slice; pad];
                                end
                                I2.ModComp_L2nCube{h}(:,:, end+1) = L2_cv2_slice;
                            end
                        end
            
                    else
                        % ---------- INTER: per-modality per-component L2 (no combined cube) ----------
                        if ~isfield(I2,'ModComp_L2n') || numel(I2.ModComp_L2n) < h || isempty(I2.ModComp_L2n{h})
                            I2.ModComp_L2n{h} = cell(1,nM);
                        end
            
                        for n = actMods
                            if ~isfield(I1,'ModComp_L2n') || numel(I1.ModComp_L2n) < h || isempty(I1.ModComp_L2n{h}) ...
                                    || numel(I1.ModComp_L2n{h}) < n || isempty(I1.ModComp_L2n{h}{n})
                                continue;
                            end
                            % average over CV1 models (columns) for this modality
                            L2_cv2_col_n = mean(I1.ModComp_L2n{h}{n}, 2, 'omitnan'); % [nRef_n × 1]
                            nRef_n = numel(L2_cv2_col_n);
            
                            if isempty(I2.ModComp_L2n{h}{n})
                                I2.ModComp_L2n{h}{n} = L2_cv2_col_n;
                            else
                                rTarget = max(size(I2.ModComp_L2n{h}{n},1), nRef_n);
                                if size(I2.ModComp_L2n{h}{n},1) < rTarget
                                    c = size(I2.ModComp_L2n{h}{n},2);
                                    I2.ModComp_L2n{h}{n} = [I2.ModComp_L2n{h}{n}; nan(rTarget - size(I2.ModComp_L2n{h}{n},1), c)];
                                end
                                if nRef_n < rTarget
                                    L2_cv2_col_n(rTarget,1) = NaN;
                                end
                                I2.ModComp_L2n{h}{n}(:, end+1) = L2_cv2_col_n;
                            end
                        end
                        % NOTE: no ModComp_L2nCube in intermediate fusion (no shared component axis).
                    end
                end
            end
        end

    case 'report'

        for h = 1:nclass
            % tiny helpers (built-ins only)
            nanmed    = @(X,dim) median(X, dim, 'omitnan');
            nansum_f  = @(X,dim) sum(X, dim, 'omitnan');
            nanmean_f = @(X,dim) mean(X, dim, 'omitnan');
        
            % detect intermediate fusion
            actMods  = find(decompfl(:)~=0).';
        
            % ---- modality-wise: I2.ModAgg_L2nShare (unchanged; valid for both modes) ----
            if isfield(I2,'ModAgg_L2nShare') && numel(I2.ModAgg_L2nShare) >= h && ~isempty(I2.ModAgg_L2nShare{h})

                Mshare = I2.ModAgg_L2nShare{h};             % [nM x ll]
                [nM_loc, ill_loc] = size(Mshare);
        
                % names (optional)
                modNames = arrayfun(@(k) sprintf('Mod%d',k), (1:nM_loc).', 'uni',0);
        
                % stats per modality across CV1 folds
                medShare  = nanmed(Mshare, 2);
                meanShare = nanmean_f(Mshare, 2);
                covg      = sum(isfinite(Mshare), 2);       % folds with finite share
        
                % rank by median share
                [~, ord] = sort(medShare, 'descend', 'MissingPlacement','last');
        
                fprintf('\n[nk_VisModels] L_p share report — modality-wise (h=%d, CV1 folds=%d)\n', h, ill_loc);
                fprintf('   %-20s  %8s  %8s  %7s\n', 'Modality', 'Median', 'Mean', 'Covg');
                for r = 1:numel(ord)
                    m = ord(r);
                    fprintf('   %-20s  %8.4f  %8.4f  %4d/%-4d\n', modNames{m}, medShare(m), meanShare(m), covg(m), ill_loc);
                end
            else
                fprintf('\n[nk_VisModels] L_p share report — modality-wise: no data for h=%d.\n', h);
            end
        
            % ---- component-wise (optional) -----------------------------------------------
            if compwise && isfield(I2,'ModComp_L2n') && numel(I2.ModComp_L2n) >= h && ~isempty(I2.ModComp_L2n{h})
        
                if ~inp.isInter
                    % ======================= EARLY FUSION (unchanged) =======================
                    Cmag = I2.ModComp_L2n{h};                % [nRef x ll]
                    [nRef, ~] = size(Cmag);
        
                    % per-fold normalization to shares
                    denom = nansum_f(Cmag, 1);               % 1 x ll
                    denom(denom<=0 | ~isfinite(denom)) = NaN;
                    Cshare = Cmag ./ denom;                  % [nRef x ll]
        
                    % summary per component (CV1 level)
                    medShare_c  = nanmed(Cshare, 2);
                    meanShare_c = nanmean_f(Cshare, 2);
                    compNames = arrayfun(@(k) sprintf('Comp%03d',k), (1:nRef).', 'uni',0);
        
                    % ---------- CV2 p/r matrices ----------
                    Pcv2 = []; Ccv2 = [];
                    if isfield(I2,'VCV2WPERMREF') && numel(I2.VCV2WPERMREF) >= h && ~isempty(I2.VCV2WPERMREF{h}), Pcv2 = I2.VCV2WPERMREF{h}; end
                    if isfield(I2,'VCV2WCORRREF') && numel(I2.VCV2WCORRREF) >= h && ~isempty(I2.VCV2WCORRREF{h}), Ccv2 = I2.VCV2WCORRREF{h}; end

                    % build per-fold column counts up to current CV2 fold 'll'
                    if isfield(I2,'VCV2NMODEL_PERFOLD') && numel(I2.VCV2NMODEL_PERFOLD) >= h && ~isempty(I2.VCV2NMODEL_PERFOLD{h})
                        cpf_all = I2.VCV2NMODEL_PERFOLD{h}(:)';                  
                        cpf     = cpf_all(1:min(ll, numel(cpf_all)));            
                    else
                        totP = size(Pcv2,2); totC = size(Ccv2,2);
                        cpf  = max([totP, totC, 0]);                             
                        if cpf == 0, cpf = 0; end                                
                    end
                    col_offsets = [0, cumsum(cpf)];                              
                    total_cols  = col_offsets(end);                 
        
                    if isempty(Pcv2), Pcv2 = nan(nRef, 0); end
                    if isempty(Ccv2), Ccv2 = nan(nRef, 0); end
                    if ~isempty(Pcv2), Pcv2 = Pcv2(:, 1:min(end, total_cols)); end
                    if ~isempty(Ccv2), Ccv2 = Ccv2(:, 1:min(end, total_cols)); end
        
                    if size(Pcv2,1) < nRef, Pcv2(end+1:nRef, :) = NaN; elseif size(Pcv2,1) > nRef, Pcv2 = Pcv2(1:nRef,:); end
                    if size(Ccv2,1) < nRef, Ccv2(end+1:nRef, :) = NaN; elseif size(Ccv2,1) > nRef, Ccv2 = Ccv2(1:nRef,:); end
                    
                    % Determine "auto-correlation" rows by finding complete
                    % non-finite rows in Ccv2
                    isAuto = sum(isfinite(Ccv2),2)==0;
                    nRef_cv2 = nRef;
                    present_cv2 = zeros(nRef_cv2,1);
                    denom_cv2   = repmat(total_cols, nRef_cv2, 1);
                    meanP_cv2   = nan(nRef_cv2,1);
                    meanC_cv2   = nan(nRef_cv2,1);
        
                    if total_cols > 0
                        present_cv2 = sum(isfinite(Pcv2) | isfinite(Ccv2), 2);
                        meanP_cv2   = mean(Pcv2, 2, 'omitnan');
                        meanC_cv2   = mean(Ccv2, 2, 'omitnan');
                    end
        
                    [~, ordc] = sort(medShare_c, 'descend', 'MissingPlacement','last');
                    K = min(15, nRef);
        
                    fprintf('\n[nk_VisModels] Analysis report — component-wise (top %d of %d by median share)\n', K, nRef);
                    fprintf('   %-10s  %8s  %8s  %8s  %8s  %9s\n', ...
                            'Component', 'Median', 'Mean', 'mean p', 'mean r', 'pres [%]');
        
                    for r = 1:K
                        i  = ordc(r);
                        ip = min(i, size(Pcv2,1));
                        ic = min(i, size(Ccv2,1));
                    
                        % ---- presence string ----
                        if ~isempty(isAuto) && i <= numel(isAuto) && isAuto(i)
                            % exactly one finite p so far in this CV2 cycle
                            if exist('ilh','var') && ~isempty(ilh)
                                kHit = 1; kDen = max(1, ilh);
                            else
                                % fallback to denom_cv2 if ilh not available here
                                kHit = 1; kDen = max(1, denom_cv2(i));
                            end
                            pres_str = sprintf('%d/%-d (%1.1f%%) [CV1]', kHit, kDen, 100*kHit/kDen);
                        else
                            if ip <= numel(denom_cv2) && denom_cv2(ip) > 0
                                pres_str = sprintf('%d/%-d (%1.1f%%)', present_cv2(ip), denom_cv2(ip), present_cv2(ip)*100/denom_cv2(ip));
                            else
                                pres_str = '0/0 [0%%]';
                            end
                        end
                    
                        % ---- mean p / mean r strings ----
                        % mean p
                        if ip <= numel(meanP_cv2) && isfinite(meanP_cv2(ip))
                            mp_str = sprintf('%.4f', meanP_cv2(ip));
                        else
                            mp_str = 'NaN';
                        end
                        % mean r
                        if ~isempty(isAuto) && i <= numel(isAuto) && isAuto(i)
                            mr_str = 'auto';  % or 'N/A'
                        else
                            if ic <= numel(meanC_cv2) && isfinite(meanC_cv2(ic))
                                mr_str = sprintf('%.4f', meanC_cv2(ic));
                            else
                                mr_str = 'NaN';
                            end
                        end
                    
                        % ---- print (use %s for mp/mr so 'auto'/'NaN' work) ----
                        fprintf('   %-10s  %8.4f  %8.4f  %8s  %8s  %9s\n', ...
                            compNames{i}, medShare_c(i), meanShare_c(i), mp_str, mr_str, pres_str);
                    end
                    medVec   = medShare_c;
                    fin_mask = isfinite(medVec);
                    mass_raw = sum(medVec(ordc(1:K)), 'omitnan');
                    mass_den = sum(medVec(fin_mask), 'omitnan');
        
                    if mass_den > 0
                        mass_renorm = mass_raw / mass_den;
                        fprintf('   Top-%d components account for %.4f of median mass (raw=%.4f).\n', K, mass_renorm, mass_raw);
                    else
                        fprintf('   Top-%d components account for NaN of median mass (no finite medians).\n', K);
                    end
        
                else
                    % ======================= INTERMEDIATE FUSION (per modality) =======================
                    % Iterate DR modalities and print the same component-wise report per modality
                    if ~iscell(I2.ModComp_L2n{h})
                        fprintf('\n[nk_VisModels] Component-wise report: expected per-mod cells for h=%d (inter mode).\n', h);
                    end
        
                    % build per-fold column counts once (shared schedule) if present
                    cpf = [];
                    if isfield(I2,'VCV2NMODEL_PERFOLD') && numel(I2.VCV2NMODEL_PERFOLD) >= h && ~isempty(I2.VCV2NMODEL_PERFOLD{h})
                        cpf_all = I2.VCV2NMODEL_PERFOLD{h}(:)';                  
                        cpf     = cpf_all(1:min(ll, numel(cpf_all)));            
                    end
        
                    for n = actMods
                        Cmag = [];
                        if numel(I2.ModComp_L2n{h}) >= n, Cmag = I2.ModComp_L2n{h}{n}; end
                        if isempty(Cmag), continue; end
        
                        [nRef, ~] = size(Cmag);
        
                        % per-fold normalization to shares (within this modality)
                        denom = nansum_f(Cmag, 1);                
                        denom(denom<=0 | ~isfinite(denom)) = NaN;
                        Cshare = Cmag ./ denom;                  
        
                        % summary per component (CV1 level)
                        medShare_c  = nanmed(Cshare, 2);
                        meanShare_c = nanmean_f(Cshare, 2);
                        compNames   = arrayfun(@(k) sprintf('Mod%d:Comp%03d', n, k), (1:nRef).', 'uni',0);
        
                        % per-mod CV2 p/r matrices
                        Pcv2 = []; Ccv2 = [];
                        if isfield(I2,'VCV2WPERMREF') && numel(I2.VCV2WPERMREF) >= h && ~isempty(I2.VCV2WPERMREF{h}) ...
                                && numel(I2.VCV2WPERMREF{h}) >= n
                            Pcv2 = I2.VCV2WPERMREF{h}{n};     % [nRef_n x total_cols_mod]
                        end
                        if isfield(I2,'VCV2WCORRREF') && numel(I2.VCV2WCORRREF) >= h && ~isempty(I2.VCV2WCORRREF{h}) ...
                                && numel(I2.VCV2WCORRREF{h}) >= n
                            Ccv2 = I2.VCV2WCORRREF{h}{n};
                        end
        
                        % figure columns to include up to this CV2 fold
                        if ~isempty(cpf)
                            col_offsets = [0, cumsum(cpf)];
                            total_cols  = col_offsets(end);
                            if ~isempty(Pcv2), Pcv2 = Pcv2(:, 1:min(end, total_cols)); end
                            if ~isempty(Ccv2), Ccv2 = Ccv2(:, 1:min(end, total_cols)); end
                        end
        
                        % Row-align to nRef (pad/truncate)
                        if isempty(Pcv2), Pcv2 = nan(nRef, 0); end
                        if isempty(Ccv2), Ccv2 = nan(nRef, 0); end
                        if size(Pcv2,1) < nRef, Pcv2(end+1:nRef, :) = NaN; elseif size(Pcv2,1) > nRef, Pcv2 = Pcv2(1:nRef,:); end
                        if size(Ccv2,1) < nRef, Ccv2(end+1:nRef, :) = NaN; elseif size(Ccv2,1) > nRef, Ccv2 = Ccv2(1:nRef,:); end
                        
                        % Determine "auto-correlation" rows by finding complete
                        % non-finite rows in Ccv2
                        isAuto = sum(isfinite(Ccv2),2)==0;

                        total_cols = max(size(Pcv2,2), size(Ccv2,2));
                        present_cv2 = zeros(nRef,1);
                        denom_cv2   = repmat(total_cols, nRef, 1);
                        meanP_cv2   = nan(nRef,1);
                        meanC_cv2   = nan(nRef,1);
        
                        if total_cols > 0
                            present_cv2 = sum(isfinite(Pcv2) | isfinite(Ccv2), 2);
                            meanP_cv2   = mean(Pcv2, 2, 'omitnan');
                            meanC_cv2   = mean(Ccv2, 2, 'omitnan');
                        end
        
                        [~, ordc] = sort(medShare_c, 'descend', 'MissingPlacement','last');
                        K = min(15, nRef);
        
                        fprintf('\n[nk_VisModels] Analysis report — component-wise (Mod %d, top %d of %d by median share)\n', n, K, nRef);
                        fprintf('   %-14s  %8s  %8s  %8s  %8s  %9s\n', ...
                                'Component', 'Median', 'Mean', 'mean p', 'mean r', 'pres [%]');
        
                        for r = 1:K
                            i  = ordc(r);
                            ip = min(i, size(Pcv2,1));
                            ic = min(i, size(Ccv2,1));
                        
                            % ---- presence string ----
                            if ~isempty(isAuto) && i <= numel(isAuto) && isAuto(i)
                                % exactly one finite p so far in this CV2 cycle
                                if exist('ilh','var') && ~isempty(ilh)
                                    kHit = 1; kDen = max(1, ilh);
                                else
                                    % fallback to denom_cv2 if ilh not available here
                                    kHit = 1; kDen = max(1, denom_cv2(i));
                                end
                                pres_str = sprintf('%d/%-d (%1.1f%%) [CV1]', kHit, kDen, 100*kHit/kDen);
                            else
                                if ip <= numel(denom_cv2) && denom_cv2(ip) > 0
                                    pres_str = sprintf('%d/%-d (%1.1f%%)', present_cv2(ip), denom_cv2(ip), present_cv2(ip)*100/denom_cv2(ip));
                                else
                                    pres_str = '0/0 [0%%]';
                                end
                            end
                        
                            % ---- mean p / mean r strings ----
                            % mean p
                            if ip <= numel(meanP_cv2) && isfinite(meanP_cv2(ip))
                                mp_str = sprintf('%.4f', meanP_cv2(ip));
                            else
                                mp_str = 'NaN';
                            end
                            % mean r
                            if ~isempty(isAuto) && i <= numel(isAuto) && isAuto(i)
                                mr_str = 'auto';  % or 'N/A'
                            else
                                if ic <= numel(meanC_cv2) && isfinite(meanC_cv2(ic))
                                    mr_str = sprintf('%.4f', meanC_cv2(ic));
                                else
                                    mr_str = 'NaN';
                                end
                            end
                        
                            % ---- print (use %s for mp/mr so 'auto'/'NaN' work) ----
                            fprintf('   %-10s  %8.4f  %8.4f  %8s  %8s  %9s\n', ...
                                compNames{i}, medShare_c(i), meanShare_c(i), mp_str, mr_str, pres_str);
                        end
                        medVec   = medShare_c;
                        fin_mask = isfinite(medVec);
                        mass_raw = sum(medVec(ordc(1:K)), 'omitnan');
                        mass_den = sum(medVec(fin_mask), 'omitnan');
        
                        if mass_den > 0
                            mass_renorm = mass_raw / mass_den;
                            fprintf('   Top-%d components account for %.4f of median mass (raw=%.4f).\n', K, mass_renorm, mass_raw);
                        else
                            fprintf('   Top-%d components account for NaN of median mass (no finite medians).\n', K);
                        end
                    end
                end
        
            else
                if compwise
                    fprintf('\n[nk_VisModels] L2n share report — component-wise: no data for h=%d.\n', h);
                end
            end
        end
        
    case 'report_final'
        
        % Nothing to report if there is only one modality and no
        % back-projection activated
        if nM==1 && ~compwise, return; end

        for h = 1:nclass

            R = struct();
            R.meta = struct('h', h, ...
                            'ill', ll, ...
                            'nM', nM, ...
                            'has_compwise', logical(compwise));
        
            % helpers assumed available in file scope:
            nanmean_f = @(X,dim) mean(X, dim, 'omitnan');
            nansum_f  = @(X,dim) sum(X,  dim, 'omitnan');
        
            % fusion mode
            actMods = find(decompfl(:)~=0).';
        
            %% -------------------- 1) Modality-wise (ModAgg_L2nShare) --------------------
            R.modality = struct('names', {{}}, 'median', [], 'mean', [], 'coverage', [], 'order_by_median', [], 'lo95', [], 'hi95', []);
            if isfield(I2,'ModAgg_L2nShare') && numel(I2.ModAgg_L2nShare) >= h && ~isempty(I2.ModAgg_L2nShare{h})
                Mshare = I2.ModAgg_L2nShare{h};             % [nM x ll]
                [nM_loc, ill_loc] = size(Mshare);
        
                ModNames = getModNames(inp, nM);
        
                meanShareM = nanmean_f(Mshare, 2);
                covgM      = sum(isfinite(Mshare), 2);
                medShareM  = median(Mshare, 2, 'omitnan');
        
                lo95M = NaN(size(medShareM)); hi95M = lo95M;
                for m = 1:size(Mshare,1)
                    v = Mshare(m, :); v = v(isfinite(v));
                    if isempty(v)
                        lo95M(m) = NaN; hi95M(m) = NaN;
                    elseif isscalar(v)
                        lo95M(m) = v;   hi95M(m) = v;
                    else
                        lo95M(m) = nm_pctile_fast(v, 2.5);
                        hi95M(m) = nm_pctile_fast(v, 97.5);
                    end
                end
                [~, ordM] = sort(medShareM, 'descend', 'MissingPlacement','last');
        
                R.modality.names          = ModNames;
                R.modality.median         = medShareM(:);
                R.modality.mean           = meanShareM(:);
                R.modality.lo95           = lo95M(:);
                R.modality.hi95           = hi95M(:);
                R.modality.coverage       = [covgM, repmat(ill_loc, nM_loc, 1)];  % [hits, total]
                R.modality.order_by_median= ordM;
            end
        
            %% ---------------- 2) Component-wise (shares + CV2 presence + mean p/r) ----------------
            if compwise && isfield(I2,'ModComp_L2n') && numel(I2.ModComp_L2n) >= h && ~isempty(I2.ModComp_L2n{h})
               % --- KEPT COMPONENTS META ---
                if inp.isInter
                    % per-modality cells
                    R.meta.kept_components = cell(1, nM);
                
                    if isfield(I2,'KEEP') && numel(I2.KEEP) >= h && ~isempty(I2.KEEP{h}) && iscell(I2.KEEP{h})
                        for n = 1:nM
                            if ~decompfl(n)
                                R.meta.kept_components{n} = [];
                                continue;
                            end
                            if numel(I2.KEEP{h}) >= n && ~isempty(I2.KEEP{h}{n})
                                K = I2.KEEP{h}{n};
                                % normalize to logical mask
                                if islogical(K)
                                    mask = K;
                                elseif isnumeric(K)
                                    mask = K ~= 0;
                                else
                                    mask = false(size(K));
                                end
                                R.meta.kept_components{n} = find(mask(:));
                            else
                                R.meta.kept_components{n} = [];
                            end
                        end
                    else
                        % no KEEP recorded yet → empty cells
                        for n = 1:nM
                            R.meta.kept_components{n} = [];
                        end
                    end
                
                else
                    % single combined mask
                    if isfield(I2,'KEEP') && numel(I2.KEEP) >= h && ~isempty(I2.KEEP{h})
                        K = I2.KEEP{h};
                        % if someone accidentally stored a cell in early fusion, try to unwrap
                        if iscell(K) && ~isempty(K)
                            K = K{1};
                        end
                        if islogical(K)
                            mask = K;
                        elseif isnumeric(K)
                            mask = K ~= 0;
                        else
                            mask = false(size(K));
                        end
                        R.meta.kept_components = find(mask(:));
                    else
                        R.meta.kept_components = [];
                    end
                end
                R.meta.settings.backprojection_method          = inp.simCorrMethod;
                R.meta.settings.similarity_alignment_method    = inp.simCorrThresh;
                R.meta.settings.similarity_pruning_cutoff      = inp.CorrCompCutOff;
                R.meta.settings.presence_pruning_cutoff        = inp.SelCompCutOff;
        
                if ~inp.isInter
                    % ======================= EARLY FUSION (original) =======================
                    R.components = struct('names', {{}}, ...
                          'median_share', [], 'mean_share', [], 'coverage_cv1', [], ...
                          'mean_p_cv2', [], 'mean_p_lo95', [], 'mean_p_hi95', [], ...
                          'mean_r_cv2', [], 'mean_r_lo95', [], 'mean_r_hi95', [], ...
                          'present_cv2', [], 'denom_cv2', [], ...
                          'order_by_median', [], 'mass_den_median', []);
        
                    Cmag = I2.ModComp_L2n{h};                 % [nRef x ll]
                    nRef = size(Cmag,1);
        
                    % Names
                    if exist('CompNames','var') && numel(CompNames)==nRef
                        R.components.names = CompNames(:);
                    else
                        if isfield(R.meta,'kept_components') && ~isempty(R.meta.kept_components)
                            R.components.names = arrayfun(@(k) sprintf('Comp%03d',R.meta.kept_components(k)), (1:nRef).', 'uni',0);
                        else
                            R.components.names = arrayfun(@(k) sprintf('Comp%03d',k), (1:nRef).', 'uni',0);
                        end
                    end
        
                    % per-fold normalization to shares
                    denom = sum(Cmag, 1, 'omitnan');                 % 1 x ll
                    bad   = (denom<=0) | ~isfinite(denom);
                    denom(bad) = NaN;
                    Cshare = Cmag ./ denom;                           % [nRef x ll]
        
                    medShareC  = median(Cshare, 2, 'omitnan');
                    meanShareC = mean(Cshare,   2, 'omitnan');
                    covgC      = [sum(isfinite(Cshare), 2) repmat(size(Cshare,2),size(Cshare,1),1)];
        
                    % CV2 p/r (combined)
                    Pcv2 = []; Ccv2 = [];
                    if isfield(I2,'VCV2WPERMREF') && numel(I2.VCV2WPERMREF) >= h && ~isempty(I2.VCV2WPERMREF{h}), Pcv2 = I2.VCV2WPERMREF{h}; end
                    if isfield(I2,'VCV2WCORRREF') && numel(I2.VCV2WCORRREF) >= h && ~isempty(I2.VCV2WCORRREF{h}), Ccv2 = I2.VCV2WCORRREF{h}; end
        
                    % unify width, no filtering
                    if isempty(Pcv2) && isempty(Ccv2)
                        nRef_cv2   = nRef;
                        Pcv2_done  = nan(nRef_cv2,0);
                        Ccv2_done  = nan(nRef_cv2,0);
                        total_cols = 0;
                    else
                        nRef_cv2 = ~isempty(Pcv2) * size(Pcv2,1) + isempty(Pcv2) * size(Ccv2,1);
                        if isempty(Pcv2), Pcv2 = nan(nRef_cv2,0); end
                        if isempty(Ccv2), Ccv2 = nan(nRef_cv2,0); end
                        total_cols = max(size(Pcv2,2), size(Ccv2,2));
                        if size(Pcv2,2) < total_cols, Pcv2(:, end+1:total_cols) = NaN; end
                        if size(Ccv2,2) < total_cols, Ccv2(:, end+1:total_cols) = NaN; end
                        Pcv2_done  = Pcv2(:, 1:total_cols);
                        Ccv2_done  = Ccv2(:, 1:total_cols);
                    end
        
                    % row-align to nRef
                    if size(Pcv2_done,1) < nRef, Pcv2_done(end+1:nRef, :) = NaN; elseif size(Pcv2_done,1) > nRef, Pcv2_done = Pcv2_done(1:nRef,:); end
                    if size(Ccv2_done,1) < nRef, Ccv2_done(end+1:nRef, :) = NaN; elseif size(Ccv2_done,1) > nRef, Ccv2_done = Ccv2_done(1:nRef,:); end
        
                    % presence & means (same policy as 'report')
                    present_cv2 = zeros(nRef,1);
                    denom_cv2   = repmat(total_cols, nRef, 1);
                    meanP_cv2   = nan(nRef,1); meanR_cv2 = nan(nRef,1);
                    meanP_lo    = nan(nRef,1); meanP_hi  = nan(nRef,1);
                    meanR_lo    = nan(nRef,1); meanR_hi  = nan(nRef,1);
        
                    if total_cols > 0
                        present_cv2 = sum(isfinite(Pcv2_done) | isfinite(Ccv2_done), 2);
                        if ~isfield(I2,'VCV2WPERMREF_FDR_GLOBAL')
                            meanP_cv2   = nm_nanmean(Pcv2_done,2);
                        else
                            meanP_cv2   = I2.VCV2WPERMREF_FDR_GLOBAL{h}(I2.KEEP{h});
                        end
                        % convert to -log10(p) (as in your original report_final)
                        meanP_cv2   = -log10(meanP_cv2);
                        meanR_cv2   = mean(Ccv2_done, 2, 'omitnan');
        
                        for i = 1:nRef
                            pv = Pcv2_done(i, isfinite(Pcv2_done(i,:)));
                            rv = Ccv2_done(i, isfinite(Ccv2_done(i,:)));
                            if isempty(pv)
                                meanP_lo(i) = NaN; meanP_hi(i) = NaN;
                            elseif isscalar(pv)
                                meanP_lo(i) = pv;  meanP_hi(i) = pv;
                            else
                                meanP_lo(i) = nm_pctile_fast(pv, 2.5);
                                meanP_hi(i) = nm_pctile_fast(pv, 97.5);
                            end
                            if isempty(rv)
                                meanR_lo(i) = NaN; meanR_hi(i) = NaN;
                            elseif isscalar(rv)
                                meanR_lo(i) = rv;  meanR_hi(i) = rv;
                            else
                                meanR_lo(i) = nm_pctile_fast(rv, 2.5);
                                meanR_hi(i) = nm_pctile_fast(rv, 97.5);
                            end
                        end
                    end
        
                    % order by median share and mass denom
                    [~, ordc] = sort(medShareC, 'descend', 'MissingPlacement','last');
                    R.components.names            = R.components.names;
                    R.components.median_share     = medShareC;
                    R.components.mean_share       = meanShareC;
                    R.components.coverage_cv1     = covgC;
                    R.components.mean_p_cv2       = meanP_cv2;
                    R.components.mean_p_lo95      = meanP_lo;
                    R.components.mean_p_hi95      = meanP_hi;
                    R.components.mean_r_cv2       = meanR_cv2;
                    R.components.mean_r_lo95      = meanR_lo;
                    R.components.mean_r_hi95      = meanR_hi;
                    R.components.present_cv2      = present_cv2;
                    R.components.denom_cv2        = denom_cv2;
                    R.components.order_by_median  = ordc;
        
                    medVec   = medShareC; fin_mask = isfinite(medVec);
                    R.components.mass_den_median  = sum(medVec(fin_mask), 'omitnan');
        
                    % ---------- Component × Modality (only exists in early fusion) ----------
                    R.comp_by_mod = struct('median_share', [], 'mean_share', [], 'coverage', [], 'names_mod', {{}}, 'names_comp', {{}});
                    if isfield(I2,'ModComp_L2nCube') && numel(I2.ModComp_L2nCube) >= h && ~isempty(I2.ModComp_L2nCube{h})
                        Cube = I2.ModComp_L2nCube{h};              % [nRef x nM x ll]
                        [nRefC, nM_loc, ill_loc] = size(Cube);
        
                        % names
                        ModNames = getModNames(inp, nM_loc);
                        if exist('CompNames','var') && numel(CompNames)==nRefC
                            compList = CompNames(:);
                        else
                            compList = arrayfun(@(k) sprintf('Comp%03d',k), (1:nRefC).', 'uni',0);
                        end
                        R.comp_by_mod.names_mod  = ModNames(:);
                        R.comp_by_mod.names_comp = compList;
        
                        for t = 1:ill_loc
                            Sl = Cube(:,:,t);                        % [nRef x nM]
                            rowDen = nansum_f(Sl, 2);
                            rowDen(rowDen<=0 | ~isfinite(rowDen)) = NaN;
                            Sh = Sl ./ rowDen;
                            if t == 1
                                Sh_stack = nan(nRefC, nM_loc, ill_loc);
                            end
                            Sh_stack(:,:,t) = Sh;
                        end
        
                        medShare_CM  = median(Sh_stack, 3, 'omitnan');
                        meanShare_CM = mean(Sh_stack,   3, 'omitnan');
                        covg_CM      = sum(isfinite(Sh_stack), 3);
        
                        R.comp_by_mod.median_share = medShare_CM;
                        R.comp_by_mod.mean_share   = meanShare_CM;
                        R.comp_by_mod.coverage     = cat(3, covg_CM, repmat(ill_loc, nRefC, nM_loc));
                    end
        
                else
                    % ======================= INTERMEDIATE FUSION (per-modality) =======================
                    % Produce one component-wise report struct per DR modality.
                  
                    % optional shared column schedule (if present)
                    cpf = [];
                    if isfield(I2,'VCV2NMODEL_PERFOLD') && numel(I2.VCV2NMODEL_PERFOLD) >= h && ~isempty(I2.VCV2NMODEL_PERFOLD{h})
                        cpf_all = I2.VCV2NMODEL_PERFOLD{h}(:)';                  
                        cpf     = cpf_all(1:min(ll, numel(cpf_all)));            
                    end
                    R.components_idxs = actMods;
        
                    for n = actMods
                        Cmag = [];
                        if iscell(I2.ModComp_L2n{h}) && numel(I2.ModComp_L2n{h}) >= n
                            Cmag = I2.ModComp_L2n{h}{n};           % [nRef_n x ll]
                        end
                        if isempty(Cmag), continue; end
        
                        nRef = size(Cmag,1);
        
                        % names for this modality
                        if exist('CompNames','var') && numel(CompNames)==nRef
                            compList = CompNames(:);
                        else
                            compList = arrayfun(@(k) sprintf('Mod%d:Comp%03d', n, k), (1:nRef).', 'uni',0);
                        end
        
                        % per-fold normalization to shares (within modality)
                        denom = sum(Cmag, 1, 'omitnan');
                        bad   = (denom<=0) | ~isfinite(denom);
                        denom(bad) = NaN;
                        Cshare = Cmag ./ denom;
        
                        medShareC  = median(Cshare, 2, 'omitnan');
                        meanShareC = mean(Cshare,   2, 'omitnan');
                        covgC      = [sum(isfinite(Cshare), 2), repmat(size(Cshare,2), size(Cshare,1), 1)];
        
                        % per-mod CV2 p/r
                        Pcv2 = []; Ccv2 = [];
                        if isfield(I2,'VCV2WPERMREF') && numel(I2.VCV2WPERMREF) >= h && ~isempty(I2.VCV2WPERMREF{h}) ...
                                && numel(I2.VCV2WPERMREF{h}) >= n
                            Pcv2 = I2.VCV2WPERMREF{h}{n};     % [nRef_n x total_cols_mod]
                        end
                        if isfield(I2,'VCV2WCORRREF') && numel(I2.VCV2WCORRREF) >= h && ~isempty(I2.VCV2WCORRREF{h}) ...
                                && numel(I2.VCV2WCORRREF{h}) >= n
                            Ccv2 = I2.VCV2WCORRREF{h}{n};
                        end
        
                        % harmonize width up to current CV2 progress
                        if ~isempty(cpf)
                            col_offsets = [0, cumsum(cpf)];
                            total_cols  = col_offsets(end);
                            if ~isempty(Pcv2), Pcv2 = Pcv2(:, 1:min(end, total_cols)); end
                            if ~isempty(Ccv2), Ccv2 = Ccv2(:, 1:min(end, total_cols)); end
                        end
                        if isempty(Pcv2), Pcv2 = nan(nRef,0); end
                        if isempty(Ccv2), Ccv2 = nan(nRef,0); end
                        total_cols = max(size(Pcv2,2), size(Ccv2,2));
                        % row-align to nRef
                        if size(Pcv2,1) < nRef, Pcv2(end+1:nRef,:) = NaN; elseif size(Pcv2,1) > nRef, Pcv2 = Pcv2(1:nRef,:); end
                        if size(Ccv2,1) < nRef, Ccv2(end+1:nRef,:) = NaN; elseif size(Ccv2,1) > nRef, Ccv2 = Ccv2(1:nRef,:); end
        
                        % presence & means
                        present_cv2 = zeros(nRef,1);
                        denom_cv2   = repmat(total_cols, nRef, 1);
                        meanP_cv2   = nan(nRef,1); meanR_cv2 = nan(nRef,1);
                        meanP_lo    = nan(nRef,1); meanP_hi  = nan(nRef,1);
                        meanR_lo    = nan(nRef,1); meanR_hi  = nan(nRef,1);
        
                        if total_cols > 0
                            present_cv2 = sum(isfinite(Pcv2) | isfinite(Ccv2), 2);
                            if ~isfield(I2,'VCV2WPERMREF_FDR_GLOBAL')
                                meanP_cv2 = nm_nanmean(Pcv2,2);
                            else
                                meanP_cv2 = I2.VCV2WPERMREF_FDR_GLOBAL{h}{n}(I2.KEEP{h}{n});
                            end
                            % convert to -log10(p) (as in your original report_final)
                            meanP_cv2   = -log10(meanP_cv2);
                            meanR_cv2   = mean(Ccv2, 2, 'omitnan');
        
                            for i = 1:nRef
                                pv = Pcv2(i, isfinite(Pcv2(i,:)));
                                rv = Ccv2(i, isfinite(Ccv2(i,:)));
                                if isempty(pv)
                                    meanP_lo(i) = NaN; meanP_hi(i) = NaN;
                                elseif isscalar(pv)
                                    meanP_lo(i) = pv;  meanP_hi(i) = pv;
                                else
                                    meanP_lo(i) = nm_pctile_fast(pv, 2.5);
                                    meanP_hi(i) = nm_pctile_fast(pv, 97.5);
                                end
                                if isempty(rv)
                                    meanR_lo(i) = NaN; meanR_hi(i) = NaN;
                                elseif isscalar(rv)
                                    meanR_lo(i) = rv;  meanR_hi(i) = rv;
                                else
                                    meanR_lo(i) = nm_pctile_fast(rv, 2.5);
                                    meanR_hi(i) = nm_pctile_fast(rv, 97.5);
                                end
                            end
                        end
        
                        [~, ordc] = sort(medShareC, 'descend', 'MissingPlacement','last');
        
                        S = struct();
                        S.names            = compList;
                        S.median_share     = medShareC;
                        S.mean_share       = meanShareC;
                        S.coverage_cv1     = covgC;
                        S.mean_p_cv2       = meanP_cv2;
                        S.mean_p_lo95      = meanP_lo;
                        S.mean_p_hi95      = meanP_hi;
                        S.mean_r_cv2       = meanR_cv2;
                        S.mean_r_lo95      = meanR_lo;
                        S.mean_r_hi95      = meanR_hi;
                        S.present_cv2      = present_cv2;
                        S.denom_cv2        = denom_cv2;
                        S.order_by_median  = ordc;
        
                        medVec   = medShareC; fin_mask = isfinite(medVec);
                        S.mass_den_median  = sum(medVec(fin_mask), 'omitnan');
        
                        R.components{n} = S;  % store per-modality
                    end
        
                    % No component × modality matrix in intermediate fusion (no shared component axis)
                    R.comp_by_mod = [];
                end
            end
            I2.ReportFinal{h} = R;
        end
    end
end

function B = pad3D(A, padCount)

    if padCount <= 0, B = A; return; end
    sz = size(A);
    nd = ndims(A);
    if nd==2
        B = nan(sz(1), sz(2)+padCount, 'like', A);
        B(:,1:sz(2)) = A;
    elseif nd==3
        B = nan(sz(1), sz(2), sz(3)+padCount, 'like', A);
        B(:,:,1:sz(3)) = A;
    else
        error('pad3D only supports 2-D or 3-D arrays');
    end

end

% --- helpers (put them near the top of the file or as nested funcs) ---
function X = padRowsNaN(X, targetRows)
    [r,c] = size(X);
    if r < targetRows
        X(r+1:targetRows, 1:c) = NaN;
    end
end

function X = padColsNaN(X, targetCols)
    [r,c] = size(X);
    if c < targetCols
        X(1:r, c+1:targetCols) = NaN;
    end
end

function [Aeq,Beq] = harmonizeSize(A,B)
    R = max(size(A,1), size(B,1));
    C = max(size(A,2), size(B,2));
    Aeq = padColsNaN(padRowsNaN(A,R), C);
    Beq = padColsNaN(padRowsNaN(B,R), C);
end

function ModNames = getModNames(inp, nM)
    ModNames = cell(nM,1);
    try
        switch inp.FUSION.flag 
            case 1
                % Early fusion: inp.X.datadesc is expected to be a cellstr {nM}
                if isfield(inp,'X') && isfield(inp.X,'datadesc') && iscell(inp.X.datadesc)
                    for m = 1:min(nM, numel(inp.X.datadesc))
                        d = inp.X.datadesc{m};
                        if isstring(d) || ischar(d), ModNames{m} = char(d); end
                    end
                end
            otherwise
                % Intermediate fusion: inp.X is an array of structs with .datadesc
                if isfield(inp,'X') && numel(inp.X) >= 1
                    for m = 1:min(nM, numel(inp.X))
                        if isfield(inp.X(m), 'datadesc')
                            d = inp.X(m).datadesc;
                            if isstring(d) || ischar(d), ModNames{m} = char(d); end
                        end
                    end
                end
        end
    catch
         % Fallback names for any empties
        for m = 1:nM
            if isempty(ModNames{m})
                ModNames{m} = sprintf('Mod%d', m);
            end
        end
    end
end

function q = nm_pctile_fast(v, p)
%NM_PCTILE_FAST  Linear-interpolated percentile for finite vectors.
% v: finite numeric vector (NaNs already removed); p in [0,100]
    v = sort(v(:));
    n = numel(v);
    if n == 0
        q = NaN; return
    elseif n == 1
        q = v;  return
    end
    % Hyndman-Fan type 7 interpolation (MATLAB's default behavior)
    pos = (p/100) * (n - 1) + 1;   % 1-based
    k   = floor(pos);
    d   = pos - k;
    if k >= n
        q = v(n);
    else
        q = v(k) + d * (v(k+1) - v(k));
    end
end

function Y = apply_map_colwise(Y, map_old2new, w_old, op)
% Columns are components. Combine columns according to 'op'.
% op: 'sum' (default), 'mean'
    if nargin<4 || isempty(op), op = 'sum'; end
    if isempty(Y), return; end
    kmax = max(map_old2new); if kmax==0, Y = Y(:,[]); return; end
    Z = zeros(size(Y,1), kmax, 'like', Y);
    W = zeros(1, kmax, 'like', Y(1));
    if nargin < 3 || isempty(w_old), w_old = ones(1, numel(map_old2new)); end
    for j = 1:numel(map_old2new)
        k = map_old2new(j); if k==0, continue; end
        w = w_old(j); if w==0 || ~isfinite(w), w = 1; end
        Z(:,k) = Z(:,k) + Y(:,j) * w;
        W(k)   = W(k)   + w;
    end
    switch lower(op)
        case 'sum'
            Y = Z;               % keep sums
        case 'mean'
            mask = W>0;
            Y = nan(size(Z));
            if any(mask)
                Y(:,mask) = bsxfun(@rdivide, Z(:,mask), W(mask));
            end
        case 'min'
            Yout = nan(size(Y,1), kmax, 'like', Y);
            for k = 1:kmax
                js = find(map_old2new == k);
                if isempty(js), continue; end
                Yout(:,k) = nanmin_compat(Y(:,js), 2);
            end
            Y = Yout;
        case 'zmean'
            Yout = nan(size(Y,1), kmax, 'like', Y);
            for k = 1:kmax
                js = find(map_old2new == k);
                if isempty(js), continue; end
        
                r = Y(:,js);                  % cols to merge
                w = w_old(js);                  % 1×J weights for those cols
                w(~isfinite(w) | w<=0) = 0;     % zero-out invalid weights
        
                % clamp only finite r to avoid atanh(±1); keep NaNs as NaNs
                r_finite = isfinite(r);
                r(r_finite) = max(min(r(r_finite), 1-1e-6), -1+1e-6);
        
                z = atanh(r);                   % NaNs stay NaNs
        
                % build weight matrix per row, mask invalid cells
                W = repmat(w, size(z,1), 1);
                mask = isfinite(z) & (W>0);
        
                % weighted sum over valid cells only
                Zw   = zeros(size(z), 'like', z); Zw(~mask) = 0;  Zw(mask) = z(mask) .* W(mask);
                num  = sum(Zw, 2);
                den  = sum(W .* double(mask), 2);   % sum of weights that actually contributed
        
                zbar = nan(size(num), 'like', num);
                nz   = den > 0 & isfinite(den);
                zbar(nz) = num(nz) ./ den(nz);
        
                % back to r; columns with no contributors remain NaN
                Yout(:,k) = tanh(zbar);
            end
            Y = Yout;

        otherwise
            error('apply_map_colwise: unknown op "%s"', op);
    end
end

function Y = apply_map_rowwise(Y, map_old2new, w_old, op)
% Rows are components. Combine rows according to 'op'.
% op: 'sum' | 'mean' | 'min' | 'fisherp' | 'zmean' | 'stoufferz'

    if nargin<4 || isempty(op), op = 'sum'; end
    if isempty(Y), return; end

    Yin = Y;                  % <— keep the original
    kmax = max(map_old2new);
    if kmax==0, Y = Yin([],:); return; end

    if nargin < 3 || isempty(w_old)
        w_old = ones(1, numel(map_old2new));
    end

    switch lower(op)

        case {'sum','mean'}
            Z = zeros(kmax, size(Yin,2), 'like', Yin);
            W = zeros(kmax, 1,           'like', Yin(1));
            for j = 1:numel(map_old2new)
                k = map_old2new(j); if k==0, continue; end
                w = w_old(j); if ~isfinite(w) || w<=0, continue; end
                Z(k,:) = Z(k,:) + Yin(j,:) * w;
                W(k)   = W(k)   + w;
            end
            if strcmpi(op,'sum')
                Y = nan(size(Z), 'like', Yin);
                mask = W > 0;
                if any(mask)
                    Y(mask,:) = Z(mask,:);
                end
            else
                Y = nan(size(Z), 'like', Yin);
                mask = W > 0;
                if any(mask)
                    Y(mask,:) = Z(mask,:) ./ W(mask);
                end
            end
        case 'min'   % conservative p: per-column min over merged rows
            Yout = nan(kmax, size(Yin,2), 'like', Yin);
            for k = 1:kmax
                js = find(map_old2new == k);
                if isempty(js), continue; end
                Yout(k,:) = nanmin_compat(Yin(js,:), 1);
            end
            Y = Yout;

        case 'fisherp'  % combine p via Fisher per column
            Yout = nan(kmax, size(Yin,2), 'like', Yin);
            for k = 1:kmax
                js = find(map_old2new == k);
                if isempty(js), continue; end
                P = Yin(js,:);                         % rows: merged comps
                X = -2 * nm_nansum(log(max(P, realmin)), 1);
                m = sum(isfinite(P), 1);
                Yout(k,:) = 1 - chi2cdf(X, 2*max(m,1));
                Yout(k, m==0) = NaN;
            end
            Y = Yout;

        case 'zmean'    % Fisher r->z mean for correlations (rowwise), returns r
            Yin  = double(Yin);                 % ensure safe math
            Yout = nan(kmax, size(Yin,2), 'like', Yin);
            for k = 1:kmax
                js = find(map_old2new == k);
                if isempty(js), continue; end
        
                r = Yin(js,:);                  % rows to merge
                w = w_old(js);                  % 1×J weights for those rows
                w(~isfinite(w) | w<=0) = 0;     % zero-out invalid weights
        
                % clamp only finite r to avoid atanh(±1); keep NaNs as NaNs
                r_finite = isfinite(r);
                r(r_finite) = max(min(r(r_finite), 1-1e-6), -1+1e-6);
        
                z = atanh(r);                   % NaNs stay NaNs
        
                % build weight matrix per column, mask invalid cells
                W = repmat(w(:), 1, size(z,2));
                mask = isfinite(z) & (W>0);
        
                % weighted sum over valid cells only
                Zw   = zeros(size(z), 'like', z); Zw(~mask) = 0;  Zw(mask) = z(mask) .* W(mask);
                num  = sum(Zw, 1);
                den  = sum(W .* double(mask), 1);   % sum of weights that actually contributed
        
                zbar = nan(size(num), 'like', num);
                nz   = den > 0 & isfinite(den);
                zbar(nz) = num(nz) ./ den(nz);
        
                % back to r; columns with no contributors remain NaN
                Yout(k,:) = tanh(zbar);
            end
            Y = Yout;

        case 'stoufferz' % Stouffer combine z per column: z_new = sum(w*z)/sqrt(sum(w^2))
            Yin  = double(Yin);                                % safe math
            Yout = nan(kmax, size(Yin,2), 'like', Yin);
            for k = 1:kmax
                js = find(map_old2new == k);
                if isempty(js), continue; end
        
                z = Yin(js,:);                                 % rows to merge
                w = w_old(js);                                 % 1×J weights
                w(~isfinite(w) | w<=0) = 0;                    % zero-out invalid
        
                % Build weight matrix and validity mask per column
                W    = repmat(w(:), 1, size(z,2));             % J×C
                mask = isfinite(z) & (W>0);                    % valid (row,col) cells
        
                % Numerator: sum_i w_i * z_i over valid cells
                Zw   = zeros(size(z), 'like', z);
                Zw(mask) = z(mask) .* W(mask);
                num  = sum(Zw, 1);                             % 1×C
        
                % Denominator: sqrt(sum_i w_i^2) but only over rows that contribute to each column
                W2m  = (W.^2) .* double(mask);
                den  = sqrt(sum(W2m, 1));                      % 1×C
        
                out       = nan(1, size(z,2), 'like', z);
                ok        = den > 0 & isfinite(den);
                out(ok)   = num(ok) ./ den(ok);                % Stouffer z per column
                Yout(k,:) = out;
            end
            Y = Yout;

        otherwise
            error('apply_map_rowwise: unknown op "%s"', op);
    end
end

% --- local helper: nanmin across rows, MATLAB-version agnostic
function out = nanmin_compat(A, dim)
    try
        out = min(A, [], dim, 'omitnan');
    catch
        % Fallback if 'omitnan' unsupported
        mask = ~isnan(A);
        if dim==1
            out = nan(1, size(A,2), 'like', A);
            for c = 1:size(A,2)
                col = A(:,c);
                msk = mask(:,c);
                if any(msk), out(c) = min(col(msk)); end
            end
        else
            out = nan(size(A,1), 1, 'like', A);
            for r = 1:size(A,1)
                row = A(r,:);
                msk = mask(r,:);
                if any(msk), out(r) = min(row(msk)); end
            end
        end
    end
end

function Xout = apply_map_3dthird(X, map_old2new, w_old, op)
% Components are dim-3. Combine along 3rd dim.
% op: 'sum' | 'mean'
    if nargin<4 || isempty(op), op = 'sum'; end
    if isempty(X), return; end
    kmax = max(map_old2new); if kmax==0, X = X(:,:,[]); return; end
    Z = zeros(size(X,1), size(X,2), kmax, 'like', X);
    W = zeros(1, 1, kmax, 'like', X(1));
    if nargin < 3 || isempty(w_old), w_old = ones(1, numel(map_old2new)); end
    for j = 1:numel(map_old2new)
        k = map_old2new(j); if k==0, continue; end
        w = w_old(j); if w==0 || ~isfinite(w), continue; end
        Z(:,:,k) = Z(:,:,k) + X(:,:,j) * w;
        W(:,:,k) = W(:,:,k) + w;
    end
    switch lower(op)
        case 'sum'
            mask = W > 0;   
            Xout = nan(size(Z), 'like', X);
            Xout(mask) = Z(mask);
        case 'mean'
            mask = W > 0;                       % W is 1×1×k
            Xout = nan(size(Z), 'like', X);
            if any(mask, 'all')
                for k = 1:size(Z,3)
                    if mask(1,1,k)
                        Xout(:,:,k) = Z(:,:,k) ./ W(1,1,k);
                    end
                end
            end
        otherwise
            error('apply_map_3dthird: unknown op "%s"', op);
    end
end

function X = apply_map_3dfirst(X, map_old2new, w_old, mode)
    % 1st dim = components
    if isempty(X), return; end
    kmax = max(map_old2new); if kmax==0, X = X([],:,:); return; end
    Z = zeros(kmax, size(X,2), size(X,3), 'like', X);
    W = zeros(kmax, 1, 1, 'like', X(1));
    if nargin < 3 || isempty(w_old), w_old = ones(1, numel(map_old2new)); end
    if nargin < 4, mode = 'mean'; end

    for j = 1:numel(map_old2new)
        k = map_old2new(j); if k==0, continue; end
        w = w_old(j); if w==0 || ~isfinite(w), w = 1; end
        switch lower(mode)
            case 'mean'
                Z(k,:,:) = Z(k,:,:) + X(j,:,:) * w;
                W(k,:,:) = W(k,:,:) + w;
            otherwise
                error('Unsupported mode: %s', mode);
        end
    end
    W(W==0) = 1;
    X = bsxfun(@rdivide, Z, W);
end

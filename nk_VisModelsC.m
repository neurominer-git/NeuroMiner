function visdata = nk_VisModelsC(inp, id, GridAct, batchflag)
% =========================================================================
% visdata = nk_VisModelsC(inp, id, GridAct, batchflag)
% =========================================================================
% 
% NeuroMiner Model Visualization Function
%
% This function is a key component of the NeuroMiner toolbox, responsible for 
% visualizing the predictive patterns of machine learning models. It performs 
% an in-depth analysis of the feature relevance within these patterns and 
% assesses model significance through a permutation-based approach. This 
% allows for the evaluation of model stability, generalizability, and the 
% statistical significance of observed predictive patterns.
%
% Inputs:
%   - inp       : A structured array containing all necessary parameters and 
%                 configurations for the analysis, including:
%                 * analmode: Defines the analysis mode (e.g., visualization).
%                 * vismat: Precomputed visualization matrices (if available).
%                 * saveparam: Flag indicating whether to save parameters to disk.
%                 * CV1: Cross-validation level 1 parameters.
%                 * loadparam: Flag to use existing parameters from disk.
%                 * varstr: String suffix for output filenames.
%                 * nclass: Number of binary comparisons (e.g., classifiers).
%                 * tF: Current modality index.
%                 * labels: Labels of the data points.
%                 * PREPROC: Preprocessing settings for the input data.
%                 * VIS: Visualization settings.
%                 * featnames: Names of the features (if available).
%                 * extraL: Additional labels for testing model generalizability.
%                 * multiflag: Flag for multi-group (multi-label) processing.
%                 * targscale: Flag for target scaling.
%                 * CVRnorm: Normalization method for cross-validation ratios.
%
%   - id        : A string or numeric identifier for the current analysis, 
%                 used to distinguish and name output files generated during 
%                 the visualization process.
%
%   - GridAct   : A matrix that specifies which cross-validation (CV) 
%                 partitions should be processed. It acts as a control 
%                 grid, allowing selective execution of the function 
%                 for specific CV partitions.
%
%   - batchflag : A boolean flag that, when set to true, indicates the 
%                 function is being executed in batch mode. In this mode, 
%                 certain data processing steps may be skipped to optimize 
%                 performance and avoid redundant computations.
%
% Outputs:
%   - visdata   : A cell array where each cell contains visualization data 
%                 for a different modality analyzed. Each cell structure 
%                 typically includes:
%                 * MEAN: Mean relevance/weight vector across CV partitions.
%                 * SE: Standard error of the relevance/weight vector.
%                 * CVRatio: Cross-validation ratio.
%                 * PermProb_CV2: Permutation-based probability (uncorrected).
%                 * PermProb_CV2_FDR: Permutation-based probability (FDR-corrected).
%                 * PermZ_CV2: Permutation-based Z-scores.
%                 * CorrMat_CV2: Correlation matrices for the features.
%                 * SignBased_CV2: Sign-based consistency measures.
%                 * Pearson_CV2 and Spearman_CV2: Univariate association measures.
%                 * Analytical_p: P-values computed analytically (if applicable).
%                 * ExtraL: Results from additional labels testing model generalizability.
%
% Functionality:
%   1. **Initialization**: The function initializes various parameters and 
%      settings based on the input structure, preparing the environment for 
%      the visualization process.
%   2. **Cross-Validation Loop**: Iterates over cross-validation folds, 
%      computing feature relevance, model weights, and performance metrics 
%      at each fold level.
%   3. **Permutation Testing**: If enabled, the function performs permutation 
%      testing to assess the statistical significance of the predictive patterns.
%      This involves generating null distributions for model performance and 
%      relevance metrics.
%   4. **Visualization Data Assembly**: Gathers all computed metrics into the 
%      `visdata` structure, which is organized by modality and ready for 
%      further analysis or export.
%   5. **Output**: Depending on the analysis type (e.g., imaging or non-imaging), 
%      the function may output results as NIFTI files, surface-based files, or 
%      other formats suitable for the data type.
%
% Key Features:
%   - Supports both imaging (voxel/vertex-based) and non-imaging data types.
%   - Flexible configuration for various preprocessing and analysis workflows.
%   - Capable of handling multi-class and multi-label classification scenarios.
%   - Advanced statistical testing options including permutation-based significance 
%     testing with FDR correction.
%   - Efficient handling of large datasets through selective computation and 
%     memory optimization.
%
% This function is essential for researchers using the NeuroMiner framework 
% who require detailed insights into the predictive patterns of their models 
% and the statistical significance of these patterns.
% =========================================================================
% (c) Nikolaos Koutsouleris, last modified 10/2025

global SVM RAND SAV RFE MODEFL CV VERBOSE FUSION MULTILABEL EVALFUNC CVPOS OCTAVE 

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%% INITIALIZATION %%%%%%%%%%%%%%%%%%%%%%%%%%%%
visdata         = [];                               % Initialize with empty output
switch inp.analmode
    case 0
        ovrwrt  = inp.ovrwrt;                       % overwrite existing data files
    case 1
        vismat  = inp.vismat;                       % Visualization datamat
end
saveparam       = inp.saveparam;                    % Save parameters to disk
CV1op           = inp.CV1;                          % Operate preprocessing module at the CV1 level to save RAM
loadparam       = inp.loadparam;                    % Use existing parameters loaded from disk
strout          = inp.varstr;                       % Suffix for filename indicating modality assignment of file
nclass          = inp.nclass;                       % Number of binary comparisons
analysis        = inp.analysis;                     % GDanalysis structure to be used
varind          = inp.tF;                           % Current modality index
ol              = 0;                                % Counter for computing mean vectors
ll              = 1;                                % Counter for looping through CV2 arrays
lx              = size(inp.labels,1);               % number of cases
[ix, jx]        = size(CV.TrainInd);                % No. of Perms / Folds at CV2 level
ind0            = false(1,ix*jx);
algostr         = GetMLType(SVM);                   % Algorithm descriptions
FullPartFlag    = RFE.ClassRetrain;                 % Has the user activated full CV1 partition retraining ?
nM              = numel(inp.tF);                    % Number of modalities with independent preprocessing
decompfl        = inp.decompfl;                      % flag for factorization methods during preprocessing
permfl          = false;                            % flag for permutation mode 
nperms          = 1000;                             % number of permuations per modality
pmode           = 1;                                % Permutation mode
sigfl           = false;                            % flag for significance estimation mode
sigPthr         = 0.05;
sigPfdr         = 1;
memorytested    = false;
memoryprob      = false;
compwisefls     = {true,false}; 
compwise        = compwisefls{inp.DecompMode}; % global flag
inp.isEarly     = FUSION.flag == 1 || FUSION.flag == 0;
inp.isInter     = FUSION.flag == 2;
inp.isLate      = FUSION.flag == 3;

if compwise
   inp.useRefMerge = true;
   inp.mergeThr = 0.5;
   inp.mergeStepCap = Inf;
   inp.safetyFloor  = 5; % never reduce ref below 5 columns per modality/class
end

try
    inp.tightThresh = getfield_or(inp,'MemTightThresh', 0.85);  % e.g., 85%
    inp.memFrac     = getfield_or(inp,'CV2MemFrac',     0.80);  % we’ll allow up to 80% of what is available
    [~, availBytes] = isMemoryTight(inp.tightThresh);       % avail in BYTES (Windows: physical avail; Linux/Mac: JVM max)
        % be conservative: leave headroom (5%) to avoid spikes; clamp sane bounds
    inp.CV2MemCapBytes = max( 5e8, min( inp.memFrac * double(availBytes), 0.95 * double(availBytes) ) ); % ≥0.5 GB, ≤95% of avail
catch
    % Fallback if Java not available / function not in path
    inp.CV2MemCapBytes = [];
end

% Modify compwise according to whether current modality (see
% nk_VisModelPrep loop) contains a DR step
if inp.isEarly
    % Check whether early fusion is active and factorization methods are used.
    % if so, all decompfl entries have to be set to 'yes'
    if any(decompfl), decompfl(:)=true; end
elseif inp.isLate
    decompfl = inp.decompfl(inp.curmodal);
    % Overrun compwise depending on DR or non-DR pipeline
    if ~decompfl, compwise = false; end
else
    decompfl = inp.decompfl;
end

% Loop through modalities (in early fusion: nM = 1)
Dall = 0;

% Check whether you have to run label imputation
IMPUTE.flag = false;
if iscell(inp.PREPROC), iPREPROC = inp.PREPROC{1}; else, iPREPROC = inp.PREPROC; end    
if isfield(iPREPROC,'LABELMOD') && isfield(iPREPROC.LABELMOD,'LABELIMPUTE') 
    IMPUTE = iPREPROC.LABELMOD.LABELIMPUTE; 
    IMPUTE.flag = true; 
end
linsvmfl = determine_linsvm_flag(SVM);

BINMOD = iPREPROC.BINMOD; 
if isfield(RAND,'Decompose') && RAND.Decompose == 2
    BINMOD = 0;
end

clc
fprintf('***************************\n')
fprintf('**  MODEL VISUALIZATION  **\n')
fprintf('***************************\n')

inp.id = id;
CVPOS.fFull = FullPartFlag;
permflfound = false; sigflfound = false;
if compwise, fprintf('\nComponent-wise processing mode activated.'); end

% ----- preparations ------------------------------------------------------
for i = 1 : nM
    
    % Dimensionality of current modality
    D = getD(FUSION.flag, inp, i);

    % Dimensionality of the (concatenated feature space)
    Dall = Dall + D;
    
    % Activate preprocessing params of current modality
    switch FUSION.flag
        case 2
            iVis = inp.VIS{i};
        otherwise
            iVis = inp.VIS;
    end

    % Check whether the reconstruction of significant-only components is
    % activated if factorization methods are used in given modality
    if any(decompfl) && ~sigflfound
        sigfl = iVis.PERM.sigflag;
        if sigfl
            sigPthr = iVis.PERM.sigPthresh;
            sigPfdr = iVis.PERM.sigPfdr;
            nperms = iVis.PERM.nperms;
            inp.PERM.nperms = nperms;
            sigflfound = true;
            fprintf('\nPermutation flag found in reduced space of modality #%g.\n => Activating model permutation tests in all reduced-space modalities', i); 
        end
    end
    
    % Check whether permutation mode is activated in current modality and
    % activate it across all modalities
    if isfield(iVis,'PERM') && iVis.PERM.flag && ~permflfound
        if ~isfield(iVis.PERM,'mode')
            pmode = 1; 
        else
            pmode = iVis.PERM.mode;
        end
        nperms = iVis.PERM.nperms;
        permfl = true; 
        permflfound = true;
        pmodestrdefs = {'labels','features','labels AND features'};
        if any(decompfl)
            fprintf('\nPermutation flag found in modality #%g.\n => Activating additional feature permutation tests in all modalities (mode: %s)',i, pmodestrdefs{pmode}); 
        else
            fprintf('\nPermutation flag found in modality #%g.\n => Activating model permutation tests in all modalities (mode: %s)',i, pmodestrdefs{pmode}); 
        end
    end       
end

alpha_str = 'at uncorrected alpha';
if sigfl && sigPfdr == 1, alpha_str = 'at FDR-corrected q'; end

% Set comparator function depending on the type of optimization criterion
% chosen if permfl or sigfl are true
if permfl || sigfl, compfun = nk_ReturnEvalOperator(SVM.GridParam); end

%% For factorization methods: TEMPLATE MAPPING   
% Apply prerpocessing on the entire data and use these
% parameters to adjust for arbitrary PCA rotations through 
% the Procrustes transform 
templateflag = nk_DetIfTemplPreproc(inp);

% Initialize CV2 data containers
I = nk_VisXHelperC('init', nM, nclass, decompfl, permfl, sigfl, ix, jx, [], inp, [], [], [], compwise);
if permfl || sigfl
    I.VCV2MPERM_S = cell(lx,nclass,nperms); 
    I.VCV2MORIG_S = cell(lx,nclass); 
    if inp.multiflag
        I.VCV2MORIG_S_MULTI = nan(lx,ix);
        I.VCV2MPERM_S_MULTI = nan(lx,ix, nperms);
        I.VCV2MPERM_MULTI   = zeros(1,ix*jx);
    end
end

% Obtain feature labels for the selected modalities
featnames = get_featnames_VisModels(inp);

% Multi-Group processing?
multiflag = false; if isfield(inp,'multiflag') && ~isempty(inp.multiflag), multiflag = inp.multiflag; end
if ~exist('batchflag','var') || isempty(batchflag), batchflag = false; end
multlabelstr = '';  if MULTILABEL.flag, multlabelstr = sprintf('_t%g',inp.curlabel); end

 % Do we have to scale the labels?
 % Also if we are in multilabel mode this function return the current label
 % in inp.label.
[ inp ] = nk_ApplyLabelTransform( inp.PREPROC, MODEFL, inp );

if strcmp(MODEFL,'classification') && nclass > 1
    ngroups = numel(unique(inp.label(~isnan(inp.label)))); % Number of classes in the label
else
    ngroups = 1;
end

% Parameter flag structure for preprocessing
paramfl = struct('use_exist',   loadparam, ...
                 'found',       false, ... 
                 'write',       true, ... % has to be set to true otherwise no params will be returned from the preproc module
                 'CV1op',       CV1op, ...
                 'multiflag',   multiflag, ...
                 'templateflag', templateflag);

% Pre-smooth data, if needed, to save computational time
inp.ll=inp.GridAct';inp.ll=find(inp.ll(:));
if ~inp.analmode
    inp = nk_PerfInitSpatial(analysis, inp, paramfl);
end

% %%%%%%%%%%%%%%%%%%%%%%%%%% PROCESSING %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

for f=1:ix % Loop through CV2 permutations

    for d=1:jx % Loop through CV2 folds
        
        fprintf('\n---------------------------------------------------------------------------------------------')
        if ~GridAct(f,d) 
            ll=ll+1;
            fprintf('\nSkipping CV2 partition [%g,%g] (user-defined).',f,d)
            continue 
        end
        
        [iy, jy] = size(CV.cvin{f,d}.TrainInd); % No. of Perms / Folds at CV1 level
        CVPOS.CV2p = f;
        CVPOS.CV2f = d;
        CVPOS.CV1p = 1;
        CVPOS.CV1f = 1;
        operm = f; ofold = d;
        oVISpath = nk_GenerateNMFilePath(inp.rootdir, SAV.matname, inp.datatype, multlabelstr, strout, id, operm, ofold);
        OptModelPath = nk_GenerateNMFilePath( inp.saveoptdir, SAV.matname, 'OptModel', [], inp.varstr, inp.id, operm, ofold);
    
        switch inp.analmode 
            
            case 0
        
                %%%%%%%%%%%%%%%%%%%%%%%%% USE PRECOMPUTED ? %%%%%%%%%%%%%%%%%%%%%%%
                
                if exist(oVISpath,'file') && ~ovrwrt && ~batchflag
                    
                    [~, onam] = fileparts(oVISpath);
                    fprintf('\nVISdatamat found for CV2 partition [%g,%g]:',f,d)
                    fprintf('\nLoading visualization data: %s', onam);
                    CVPOS.mode = 'loaded';
                    ill= []; [I, I1, filefound] = CV2wrapUp(I, oVISpath);
                    if filefound
                        if isfield(I1,'PCV1SUM'), PCV1SUMflag=true; else, PCV1SUMflag = false; end
                        ll=ll+1;
                        ind0(ll) = true;
                        ol=ol+1; continue
                    end
                    
                elseif exist(oVISpath,'file') && batchflag
                    
                    % in batch mode we do not compute statistics across the
                    % CV2 partitions
                    [~, onam] = fileparts(oVISpath);
                    fprintf('\nVISdatamat found for CV2 partition [%g,%g]:\n%s',f,d,onam)
                    fprintf('\nBatch mode detected. Continue.')
                    ll=ll+1;
                    continue

                end
                CVPOS.mode = 'fresh';

                %%%%%%%%% GET PREPROCESSING PARAMETERS FOR CUR. CV2 PART. %%%%%%%%%
                % First generate parameter array for preprocessing based on
                % the trained base learners in the ensemble. This saves
                % computational resources because we are not going to preprocess the 
                % data with all possible parameter combinations specified by the user, 
                % but only with those chosen by the NM training process.
                
                inp.f = f; inp.d = d; inp.ll = ll;  

                % Compute params
                inp.loadGD = true;
                if isfield(inp,'CV1') && inp.CV1 == 1, inp.smoothonly = true; end
                
                paramfl = struct('use_exist',   loadparam, ...
                                 'found',       false, ... 
                                 'write',       true, ... % has to be set to true otherwise no params will be returned from the preproc module
                                 'CV1op',       CV1op, ...
                                 'multiflag',   multiflag, ...
                                 'templateflag',templateflag);
                                
                % find range of features in current CV2 partition 
                [ inp, contfl, analysis, mapY, GD, MD, Param, paramfl ] = nk_ApplyTrainedPreproc(analysis, inp, paramfl);
                
                % Determine max dimensionality of components
                if any(decompfl) || compwise
                    if iscell(mapY.Tr{1,1}) && iscell(mapY.Tr{1,1}{1})
                        maxTrWidth = max(cellfun(@(x) width(x), mapY.Tr{1,1}{1}));
                    else
                        maxTrWidth = max(cellfun(@(x) width(x), mapY.Tr{1,1}));
                    end
                else
                    maxTrWidth = 1;
                end

                inp.loadGD = false;
                
                if contfl, continue; end
                    
                % Prepare containers & initialize matrices for CV1-level
                % weight vector relevance metrics
                % =========================================================
                ol                             = ol+1;
                [~, I1] = nk_VisXHelperC('initI1', nM, nclass, decompfl, permfl, sigfl, [], [], [], inp, [], [], [], compwise);
                GDFEAT                         = GD.FEAT; 
                GDVI                           = GD.VI; 
                if inp.stacking
                    if strcmp(SVM.prog,'SEQOPT')
                        mChnl = ones(1,numel(GD.nM_cnt));
                    else
                        mChnl = GD.nM_cnt;
                    end
                end

                % Optional Boosting weights (same shelving as FEAT/VI)
                GDW = [];
                if isfield(GD,'Weights')
                    GDW = GD.Weights;
                end
                
                clear GD
                
                % Try to load models from disk if user
                % chose to do this
                fndMD = false; 
                if loadparam && isfield(inp,'optmodelmat') && exist(inp.optmodelmat{operm,ofold},'file')
                    fprintf('\nLoading OptModel: %s', inp.optmodelmat{operm,ofold});
                    load(inp.optmodelmat{operm,ofold},'MD'); fndMD = true; 
                end
                if ~fndMD, MD = cell(nclass,1); end
                
                % ---------------------------------------------------------
                if ~VERBOSE,fprintf('\n\nComputing visualizations for CV2 partition [ %g, %g ] ',f,d), end
                
                %% Initialize containers for analysis
                if permfl
                    I1.TS           = cell(nclass,1);
                    I1.DS           = cell(nclass,1);
                    I1.TS_perm      = cell(nclass,1);
                    I1.DS_perm      = cell(nclass,1);
                    if inp.multiflag
                        I1.mTS      = cell(nclass,1);
                        I1.mDS      = cell(nclass,1);
                        I1.mDS_perm = cell(nclass,1);
                        I1.mTS_perm = cell(nclass,1);
                    end
                end
                
                for h=1:nclass % Loop through binary comparisons
                    
                    switch MODEFL
                        case 'classification'
                            TsInd2 = CV.TestInd{f,d}(CV.classnew{f,d}{h}.ind);
                            if inp.multiflag, TsIndM = CV.TestInd{f,d}; end
                        case 'regression'
                            TsInd2 = CV.TestInd{f,d};
                    end
                    
                     %% Step 1: Get optimal model parameters
                    % Retrieve optimal parameters from precomputed analysis structure
                    % Differentiate according to binary or multi-group mode
                    [~, Pspos, nP] = nk_GetModelParams2(analysis, multiflag, ll, h, inp.curlabel);
                    
                    % Allocate memory to store CV1 ensemble patterns
                    [ill, maxFsize] = getModelNumDim(h,iy,jy,nP,Pspos,GDFEAT);
                    fprintf('\nPredictor #%g: Need to evaluate %g models in this CV2 partition', h, ill);
                  
                    if permfl || sigfl
                        I1.VCV1MPERM{h}     = nan(ill,1); 
                        nTs                 = size(TsInd2,1);
                        I1.TS{h}            = nan(nTs, ill);
                        I1.DS{h}            = nan(nTs, ill);
                        I1.DS_perm{h}       = nan(nTs, ill, nperms);
                        I1.TS_perm{h}       = nan(nTs, ill, nperms);
                        if inp.multiflag
                            nTsM = size(CV.TestInd{f,d},1);
                            I1.mTS{h}       = nan(nTsM, ill);
                            I1.mDS{h}       = nan(nTsM, ill);
                            I1.mDS_perm{h}  = nan(nTsM, ill, nperms);
                            I1.mTS_perm{h}  = nan(nTsM, ill, nperms);
                        end
                    end

                    if any(decompfl) || compwise
                        I1.VCV1WPERM{h}     = nan(maxFsize, ill); 
                    end
                    
                    % ------ Setup I1 containers ------
                    for n=1:nM
                        
                        % Retrieve dimensionality of target space
                        D = getD(FUSION.flag, inp, n);

                        % Setup container for weight storage
                        if inp.isEarly
                            if ~any(decompfl) || ~compwise % no DR or component-wise processing
                                I1.VCV1{h,n}        = nan(D, ill, 'single'); 
                            else % DR involved
                                I1.VCV1{h,n}        = nan(D, ill, maxTrWidth, 'single'); 
                            end
                        else
                            if ~decompfl(n) || ~compwise % no DR in actual modality (e.g. intermediate fusion) or component-wise processing
                                I1.VCV1{h,n}        = nan(D, ill, 'single'); 
                            else % DR involved
                                I1.VCV1{h,n}        = nan(D, ill, 0, 'single'); 
                            end
                        end
                        if ~memorytested
                            memoryprob = false;
                        end
                        % Prepare for analysis without factorization
                        if ~decompfl(n) && ~memoryprob
                            try
                                I1.PCV1SUM{h, n}                    = nan(D, 1, 'single'); 
                                I1.VCV1PEARSON{h, n}                = nan(D, iy*jy*nP,'single'); 
                                I1.VCV1SPEARMAN{h, n}               = nan(D, iy*jy*nP,'single'); 
                                I1.VCV1PEARSON_UNCORR_PVAL{h, n}    = nan(D, iy*jy*nP,'single'); 
                                I1.VCV1SPEARMAN_UNCORR_PVAL{h, n}   = nan(D, iy*jy*nP,'single');
                                I1.VCV1PEARSON_FDR_PVAL{h, n}       = nan(D, iy*jy*nP,'single'); 
                                I1.VCV1SPEARMAN_FDR_PVAL{h, n}      = nan(D, iy*jy*nP,'single'); 
                                I1.VCV1CORRMAT{h, n}                = nan(D, D, iy*jy*nP,'single');           
                                I1.VCV1CORRMAT_UNCORR_PVAL{h, n}    = nan(D, D, iy*jy*nP,'single');
                                I1.VCV1CORRMAT_FDR_PVAL{h, n}       = nan(D, D, iy*jy*nP,'single'); 
                            catch ERR
                                memoryprob=true; warning on;
                                warning(ERR.identifier, '\nEncountered problems creating variables:\n%s\nSkipping cross-correlation computations.',ERR.message);
                                if isfield(I1,'VCV1CORRMAT'), I1 = rmfield(I1,'VCV1CORRMAT'); end
                                if isfield(I1,'VCV1CORRMAT_UNCORR_PVAL'), I1 = rmfield(I1,'VCV1CORRMAT_UNCORR_PVAL'); end
                                if isfield(I1,'VCV1CORRMAT_FDR_PVAL'), I1 = rmfield(I1,'VCV1CORRMAT_FDR_PVAL'); end
                                warning off
                            end
                        end
                        memorytested = true;
                        if inp.lowmem == 1
                            if isfield(I1,'VCV1CORRMAT'), I1 = rmfield(I1,'VCV1CORRMAT'); end
                            if isfield(I1,'VCV1CORRMAT_UNCORR_PVAL'), I1 = rmfield(I1,'VCV1CORRMAT_UNCORR_PVAL'); end
                            if isfield(I1,'VCV1CORRMAT_FDR_PVAL'), I1 = rmfield(I1,'VCV1CORRMAT_FDR_PVAL'); end
                            memoryprob=true;
                        end
                        
                        % Prepare for permutation analysis
                        if permfl
                            if inp.isEarly
                                if ~any(decompfl) || ~compwise
                                    I1.VCV1PERM{h, n}   = nan(D, ill, 'single');
                                    I1.VCV1PERM_FDR{h, n} = nan(D, ill, 'single');
                                    I1.VCV1ZSCORE{h, n} = nan(D, ill, 'single');
                                else
                                    I1.VCV1PERM{h, n}   = nan(D, ill, maxTrWidth, 'single');
                                    I1.VCV1PERM_FDR{h, n} = nan(D, ill, maxTrWidth, 'single');
                                    I1.VCV1ZSCORE{h, n} = nan(D, ill, maxTrWidth, 'single');
                                end
                            else
                                if ~decompfl(n) || ~compwise
                                    I1.VCV1PERM{h, n}   = nan(D, ill, 'single');
                                    I1.VCV1PERM_FDR{h, n} = nan(D, ill, 'single');
                                    I1.VCV1ZSCORE{h, n} = nan(D, ill, 'single');
                                else
                                    I1.VCV1PERM{h, n}   = nan(D, ill, 0, 'single');
                                    I1.VCV1PERM_FDR{h, n} = nan(D, ill, 0, 'single');
                                    I1.VCV1ZSCORE{h, n} = nan(D, ill, 0, 'single');
                                end
                            end
                        end
                        
                        % Prepate for model-space statistics
                        if compwise && sigfl
                            if inp.isInter
                                if decompfl(n)
                                    I1.VCV1WPERMREF{h}{n} = nan(0, ill); 
                                    I1.VCV1WCORRREF{h}{n} = nan(0, ill); 
                                end
                            else
                                I1.VCV1WPERMREF{h}  = nan(0, ill); 
                                I1.VCV1WCORRREF{h}  = nan(0, ill); 
                            end
                        end
                    end
                    
                    % Initialize model container 
                    if ~fndMD , MD{h} = cell(nP,1); for m = 1 : nP, MD{h}{m} = cell(iy,jy); end; end
                end
                
                il = ones(nclass,1); kil=ones(nclass,1);
                
                %% Perform analyses   
                for k=1:iy % CV1 permutations

                    for l=1:jy % CV1 folds
                        
                        CVPOS.CV1p = k;
                        CVPOS.CV1f = l;
                        
                        if isfield(inp,'CV1') && inp.CV1 == 1
                            inp.CV1p = [k,k]; inp.CV1f = [l,l];
                            fprintf('\nPreprocessing data at selected parameter combination(s) ');
                            [ ~, ~, analysis, mapY, ~, ~, Param, paramfl ] = nk_ApplyTrainedPreproc(analysis, inp, paramfl);
                        end
                        
                        for h=1:nclass % Loop through binary comparisons
                    
                            if nclass > 1, fprintf('\n');fprintf('*** %s #%g *** ',algostr, h); end

                            switch MODEFL
                                case 'classification'
                                    TsInd2 = CV.TestInd{f,d}(CV.classnew{f,d}{h}.ind);
                                    if inp.multiflag, TsIndM = CV.TestInd{f,d}; end
                                case 'regression'
                                    TsInd2 = CV.TestInd{f,d};
                            end
                            
                            TsInd = mapY.TsInd{h}; 
                            
                            %% Step 1: Get optimal model parameters
                            % Retrieve optimal parameters from precomputed analysis structure
                            % Differentiate according to binary or multi-group mode
                            [Ps, Pspos, nP, Pdesc] = nk_GetModelParams2(analysis, multiflag, ll, h, inp.curlabel);
                            
                            for m = 1 : nP % parameter combinations

                                if nP>1, fprintf('\n');fprintf('Extracing model parameters at parameter node #%g/%g ', m, nP); end
                                % Prepare learning params
                                cPs = Ps(m,:); sPs = nk_PrepMLParams(Ps, Pdesc, m);

                                % -----------------------------------------------------
                                % Construct pattern for every base learnern in
                                % current CV1 [k,l] partition:
                                %% CV1 LOOP
                                P_str = nk_DefineMLParamStr(cPs, analysis.Model.ParamDesc, h);
                                
                                Fkl = GDFEAT{Pspos(m)}{k,l,h}; 
                                
                                % Determine number of features in mask and
                                % convert feature mask to logical index
                                ul=size(Fkl,2); if ~islogical(Fkl),F = Fkl ~= 0; else, F = Fkl; end

                                % Retrieve Boosting weights for this CV1 bundle (size ul×1), if present
                                Wkl = [];
                                if ~isempty(GDW)
                                    try
                                        % Prefer param-shelved layout
                                        if numel(GDW) >= Pspos(m) && iscell(GDW{Pspos(m)}) && ~isempty(GDW{Pspos(m)})
                                            % Try {Pspos}{k,l,h}, then {Pspos}{k,l}
                                            try
                                                Wkl = GDW{Pspos(m)}{k,l,h};
                                            catch
                                                Wkl = GDW{Pspos(m)}{k,l};
                                            end
                                        else
                                            % Legacy {k,l,h} or {k,l}
                                            try
                                                Wkl = GDW{k,l,h};
                                            catch
                                                try, Wkl = GDW{k,l}; catch, Wkl = []; end
                                            end
                                        end
                                    catch
                                        Wkl = [];
                                    end
                                end
                                % Validate and normalize to simplex (optional, just for interpretability)
                                if ~isempty(Wkl)
                                    Wkl = Wkl(:);
                                    if numel(Wkl) ~= ul, Wkl = []; end
                                end
                                if ~isempty(Wkl)
                                    s = sum(Wkl(isfinite(Wkl)));
                                    if s > 0, Wkl = Wkl ./ s; end
                                end

                                if VERBOSE
                                    fprintf('\n');fprintf(['Constructing predictive pattern(s) in CV2 partition [ %2g ,%2g ], ' ...
                                    'CV1 partition [ %2g ,%2g, Predictor #%g/%g ]: %g model(s), %s ML params [ %s ]. '], f, d, k, l, h, nclass, ul, algostr, P_str); 
                                else
                                    fprintf('\n');fprintf('Visualizing: CV2 [ %2g, %2g ], CV1 [ %2g, %2g, P: #%g/%g ]: %g model(s) ',f, d, k, l, h, nclass, ul);
                                end

                                CVInd   = mapY.CVInd{k,l}{h};
                                TrInd   = mapY.TrInd{k,l}{h};
                                                        
                                % Set the pointer to the correct mapY shelf
                                for n=1:numel(paramfl)
                                    pnt = 1;
                                    if ~BINMOD
                                         if isfield(paramfl{n},'PREPROC') && ...
                                           isfield(paramfl{n},'PXfull') && ... 
                                           isfield(paramfl{n},'P') && ...
                                           ~isempty(paramfl{n}.P{1})
                                            pnt = m;
                                            break   
                                        end
                                    else
                                        if isfield(paramfl{n},'PREPROC') && ...
                                           isfield(paramfl{n},'PXfull') && ...
                                           isfield(paramfl{n},'P') && ...
                                           ~isempty(paramfl{n}.P{h})
                                            %Actual parameter node
                                            pnt = m; 
                                            break   
                                        end
                                    end
                                end
                                
                                %%%%%% RECOMPUTE ORIGINAL MODEL %%%%%%
                                % get CV1 training and test data
                                if BINMOD, hix = h; else, hix =1; end
                                if inp.isInter
                                    % In intermediate fusion, mapY.Tr/CV/Ts already contain node-wise fused
                                    % data (across modalities) with data_ind applied in nk_mapY2Struct.
                                    % Therefore we MUST NOT call nk_ReturnAtOptPos for the data matrices,
                                    % otherwise data_ind would be applied twice and shelves would be wrong.
                                    % We only use nk_ReturnAtOptPos here to retrieve the correct TrainedParam
                                    % per modality via train_ind.
                                    modelTr = mapY.Tr{k,l}{hix}{pnt}; modelCV = mapY.CV{k,l}{hix}{pnt}; modelTs = mapY.Ts{k,l}{hix}{pnt};
                                    ParamX = cell(n,1);
                                    for n=1:nM
                                        [~,~,~,~, ParamX{n} ] = nk_ReturnAtOptPos(mapY.Tr{k,l}{hix},  mapY.CV{k,l}{hix}, mapY.Ts{k,l}{hix}, [], Param{n}(k,l,hix), pnt, [], true); 
                                    end
                                else
                                    [ modelTr , modelCV, modelTs] = nk_ReturnAtOptPos(mapY.Tr{k,l}{hix},  mapY.CV{k,l}{hix}, mapY.Ts{k,l}{hix}, [], Param{n}(k,l,hix), pnt); 
                                    [~,~,~,~, ParamX ] = nk_ReturnAtOptPos(mapY.Tr{k,l}{hix},  mapY.CV{k,l}{hix}, mapY.Ts{k,l}{hix}, [], Param{1}(k,l,hix), pnt); 

                                end

                                % Get label info
                                modelTrL = mapY.TrL{k,l}{h};
                                modelCVL = mapY.CVL{k,l}{h};
                                
                                % Impute labels if needed
                                [modelTrL, modelTr, TrInd] = nk_LabelImputer( modelTrL, modelTr, TrInd, sPs, IMPUTE);
                                
                                % Concatenate Training and CV data if needed
                                if FullPartFlag 
                                    modelTr = [modelTr; modelCV ]; 
                                    modelTrL = [modelTrL; modelCVL]; 
                                    TrInd = [TrInd; CVInd]; 
                                end
                                modelTr = modelTr(TrInd,:);
                                
                                % Prepare variables for
                                % input-space or model-space level
                                % permutation operations
                                if permfl || sigfl
                                    indpermfeat = [];
                                    switch MODEFL
                                        case 'classification'
                                            pTrInd = CV.TrainInd{f,d}(CV.class{f,d}{h}.TrainInd{k,l}); 
                                            pCVInd = CV.TrainInd{f,d}(CV.class{f,d}{h}.TestInd{k,l}); 
                                        otherwise
                                            pTrInd = CV.TrainInd{f,d}(CV.cvin{f,d}.TrainInd{k,l}); 
                                            pCVInd = CV.TrainInd{f,d}(CV.cvin{f,d}.TestInd{k,l});
                                    end
                                    if size(pTrInd,2)>1,pTrInd=pTrInd'; end
                                    if size(pCVInd,2)>1,pCVInd=pCVInd'; end
                                    if FullPartFlag, pTrInd = [pTrInd; pCVInd];end
                                    if pmode(1), G = nk_GenPermMatrix(CV, inp, nperms); end
                                    if inp.multiflag ==1
                                        modelTsm = modelTs;
                                        modelTsmL = inp.label(TsIndM);
                                    end
                                    modelTs = modelTs(TsInd,:); 
                                    modelTsL = mapY.TsL{h};
                                else
                                    modelTs = []; modelTsL = [];
                                end
                                
                                if ~fndMD, MD{h}{m}{k,l} = cell(ul,1); end
                                
                                % Loop through base learners' feature masks
                                for u=1:ul
                                     
                                    % Extract features according to mask
                                    try
                                        Ymodel = nk_ExtractFeatures(modelTr, F, [], u);
                                    catch
                                        fprintf('problem')
                                    end
                                    Find = F(:,u);

                                    % If permutation mode expects feature
                                    % permutation, prepare this here:
                                    if (permfl || sigfl) && pmode(1) > 1 
                                        indpermfeat = nk_VisXPermHelper('genpermfeats', sum(F(:,u)), nperms, modelTrL); 
                                    end

                                    % Get feature indices of current
                                    % modality
                                    if ~isempty(GDVI{Pspos(m)})
                                        Vind = GDVI{Pspos(m)}{k,l,h}(:,u);
                                    else
                                        Vind = ones(size(Find,1),1);
                                    end
                                    
                                    % Train model
                                    if isfield(mapY,'VI')
                                        if ~fndMD, [~, MD{h}{m}{k,l}{u}] = nk_GetParam2(Ymodel, modelTrL, sPs, 1, mapY.VI{k,l}{hix}{u}); end
                                    else
                                        if ~fndMD, [~, MD{h}{m}{k,l}{u}] = nk_GetParam2(Ymodel, modelTrL, sPs, 1); end
                                    end

                                    if inp.stacking
                                        vec_mj = [];
                                        for mj = 1:inp.nD
                                            vec_mj = [vec_mj; mj*ones(mChnl(mj),1)];
                                        end
                                    end
                                    
                                    % Prepare boosting weights, if relevant
                                    if isempty(Wkl), wu = 1; else, wu = Wkl(u); end
                                    if ~isfinite(wu) || wu < 0, wu = 1; end  % harden

                                    if permfl || sigfl
                                        fprintf('\n\t%3g | OptModel =>', u);
                                        try
                                        [perf_orig, I1.TS{h}(:,il(h)), I1.DS{h}(:,il(h))] = nk_GetTestPerf(modelTs, modelTsL, Find, MD{h}{m}{k,l}{u}, modelTr); 
                                        catch
                                            fprintf('\nproblem')
                                        end
                                        fprintf(' %1.2f',perf_orig)
    
                                        % Apply boosting weights if needed
                                        % (otherwise multiply with 1)
                                        I1.DS{h}(:,il(h)) = nm_apply_scalar_weight(I1.DS{h}(:,il(h)), wu);  
    
                                        if inp.multiflag
                                            % Here we collect the predicted labels and decision
                                            % scores of the observed binary classifier for the subsequent multiclass model assessment
                                            [~, I1.mTS{h}(:,il(h)), I1.mDS{h}(:,il(h))] = nk_GetTestPerf(modelTsm, modelTsmL, Find, MD{h}{m}{k,l}{u}, modelTr, true); 
    
                                            % Apply boosting weights if needed
                                            % (otherwise multiply with 1)
                                            I1.mDS{h}(:,il(h)) = nm_apply_scalar_weight(I1.mDS{h}(:,il(h)), wu);  
                                        end
                                    end

                                    if sigfl % Permutations in model space

                                        if compwise
                                            fprintf('\n\t\t\tCompute model significance in reduced space and identify sign. pattern components (%g perms):\t',nperms);
                                        else
                                            fprintf('\n\t\t\tCompute model significance in reduced space and aggregate sign. pattern components (%g perms):\t',nperms);
                                        end

                                        % Retrieve the original weight vector in model-space
                                        [~, ~, ~, ~, ~, Vx] = nk_VisXWeightC(inp, MD{h}{m}{k,l}{u}, Ymodel, modelTrL, varind, ParamX, Find, Vind, decompfl, memoryprob, false, compwise, [], true);

                                        % Apply boosting weights if needed
                                        % (otherwise multiply with 1)
                                        Vx = nm_apply_scalar_weight(Vx, wu);  % numeric

                                        nComp = height(Vx);

                                        Vx_perm = zeros( nComp, nperms );
                                        MD_perm = cell( 1, nperms );
                                        Px_perm = zeros( 1, nperms );

                                        % --- Run permutation test in model space ---
                                        for perms = 1:nperms

                                            % Create permuted data
                                            indperm = G.getperm(h,perms); indperm = indperm(pTrInd); 
                                            [ L_perm, Ymodel_perm ] = nk_VisXPermY(Ymodel, inp.label, pTrInd, pmode(1), indperm, indpermfeat, perms, analysis, inp, paramfl, BINMOD, h, k, l, pnt, FullPartFlag, F, u);
                                            
                                            % Train permuted model
                                            if isfield(mapY,'VI')
                                                [~, MD_perm{perms} ] = nk_GetParam2(Ymodel_perm, L_perm, sPs, 1, mapY.VI{k,l}{hix}{u});
                                            else
                                                [~, MD_perm{perms} ] = nk_GetParam2(Ymodel_perm, L_perm, sPs, 1);
                                            end
    
                                            % Retrieve permuted model performance
                                            [perf_perm, I1.TS_perm{h}(:,il(h),perms), I1.DS_perm{h}(:,il(h),perms)] = ...
                                                     nk_GetTestPerf(modelTs, modelTsL, Find, MD_perm{perms}, modelTr);
                                                    
                                            % Apply boosting weights if needed
                                            % (otherwise multiply with 1)
                                            I1.DS_perm{h}(:,il(h),perms) = nm_apply_scalar_weight(I1.DS_perm{h}(:,il(h),perms), wu);  

                                            % For multiflag mode, collect additional performance measures.
                                            if inp.multiflag
                                                [~, I1.mTS_perm{h}(:,il(h),perms), I1.mDS_perm{h}(:,il(h),perms)] = ...
                                                         nk_GetTestPerf(modelTsm, modelTsmL, Find, MD_perm{perms}, modelTr, true);

                                                I1.mDS_perm{h}(:,il(h),perms) = nm_apply_scalar_weight(I1.mDS_perm{h}(:,il(h),perms), wu);  
                                            end

                                            % Compare permuted against
                                            % original model performance
                                            if feval(compfun, perf_perm, perf_orig)
                                                fprintf('.');
                                                Px_perm(perms) = Px_perm(perms) + 1;
                                            else
                                                fprintf('*');
                                            end

                                            % Compute permuted weight vector in model space
                                            [~,~,~,~,~,Vx_perm(:, perms)] = nk_VisXWeightC(inp, MD_perm{perms}, Ymodel_perm, ...
                                                L_perm, varind, ParamX, Find, Vind, decompfl, memoryprob, false, compwise, [], true);

                                            % Apply boosting weights if needed
                                            % (otherwise multiply with 1)
                                            Vx_perm(:,perms) = nm_apply_scalar_weight(Vx_perm(:,perms), wu);  % numeric

                                        end

                                        % Compute model significance from permutation accumulators:
                                        I1.VCV1MPERM{h}(il(h)) = ( sum(Px_perm) + 1 ) ./ ( nperms + 1 );
                                        fprintf('\n\t\t\tModel P=%1.3f ', I1.VCV1MPERM{h}(il(h)));
    
                                        % Determine significance by comparing observed weight vector
                                        % against null distribution of permuted models' weight vectors
                                        % Compute uncorrected p-values in
                                        % model space and perform a
                                        % resolution-aware correction of
                                        % P=0;
                                        K = sum(bsxfun(@ge, abs(Vx_perm), abs(Vx(:))), 2);
                                        VxV_uncorr = (K + 1) ./ (nperms + 1);
                                        VxV_uncorr = VxV_uncorr(:);
                                        
                                        % Apply FDR correction to the uncorrected p-values.
                                        if sigPfdr == 1
                                            if inp.isInter
                                                uVals = unique(Vind(:)).';
                                                VxV_FDR = zeros(size(Vind,1),1);
                                                for nv = uVals
                                                    idx_Vx = find(Vind == nv);
                                                    [~, ~, ~, VxV_FDR(idx_Vx)] = fdr_bh(VxV_uncorr(idx_Vx), 0.05, 'pdep');
                                                end
                                            else
                                                [~, ~, ~, VxV_FDR] = fdr_bh(VxV_uncorr, 0.05, 'pdep');
                                            end
                                            % Store the FDR-adjusted p-values.
                                            I1.VCV1WPERM{h}(1:nComp,il(h)) = VxV_FDR;
                                        else % Stay with the uncorrected P values
                                            I1.VCV1WPERM{h}(1:nComp,il(h)) = VxV_uncorr;
                                        end
                                        clear VxV_uncorr VxV_FDR
                                        
                                        % Now evaluate feature significance using the FDR-corrected values.
                                        Fadd = (I1.VCV1WPERM{h}(1:nComp,il(h)) <= sigPthr);
                                        if inp.isInter
                                            % We have to check
                                            % modality-wise
                                             uVals = unique(Vind(:)).';
                                             for nv = uVals
                                                idx_Vx = find(Vind == nv);
                                                if ~nnz(Fadd(idx_Vx)) 
                                                    minP = min(I1.VCV1WPERM{h}(idx_Vx,il(h)));
                                                    fFadd = I1.VCV1WPERM{h}(idx_Vx,il(h)) == minP;
                                                    Fadd(idx_Vx(fFadd)) = true;
                                                    fprintf('\n\t\t\t=> Mod #%g: No feature survives %s = %g => relaxing to min P = %g [%g feature(s)].', nv, alpha_str, sigPthr, minP, nnz(fFadd) );
                                                else
                                                    fprintf('\n\t\t\t=> Mod #%g: %g / %g feature(s) significant %s = %g.', nv, nnz(Fadd(idx_Vx)), numel(idx_Vx), alpha_str, sigPthr);

                                                end
                                             end
                                        else
                                            if ~nnz(Fadd)
                                                minP = min(I1.VCV1WPERM{h}(1:nComp,il(h)));
                                                fFadd = I1.VCV1WPERM{h}(1:nComp,il(h)) == minP;
                                                Fadd = false(nComp,1); Fadd(fFadd) = true;
                                                fprintf('| No feature survives %s = %g => relaxing to min P = %g (%g features).', alpha_str, sigPthr, minP, nnz(Fadd) );
                                            else
                                                fprintf('| %g / %g features significant %s = %g.', sum(Fadd), numel(Fadd), alpha_str, sigPthr);
                                            end
                                        end
                                        I1.Fadd{h,il(h)} = Fadd;
                                        I1.Vind{h,il(h)} = Vind;
                                    else
                                        % All components will be
                                        % back-projected!
                                        I1.VCV1WPERM{h}(1:maxFsize,il(h)) = 1;
                                        Fadd = [];
                                        I1.Fadd{h,il(h)} = true(maxFsize,1);
                                        I1.Vind{h,il(h)} = Vind;
                                    end
                                    
                                    % Compute original weight map in input
                                    % space without re-scaling for L2 share computations
                                    [ Tx, Psel, Rx, SRx, Cx, ~, PAx, Dx ] = nk_VisXWeightC(inp, MD{h}{m}{k,l}{u}, Ymodel, modelTrL, varind, ParamX, Find, Vind, decompfl, memoryprob, [], compwise, Fadd, true, modelTs);

                                    % Apply boosting weights if needed
                                    % (otherwise multiply with 1)
                                    
                                    % Prepare boosting weights, if relevant
                                        if isempty(Wkl), wu = 1; else, wu = Wkl(u); end
                                        if ~isfinite(wu) || wu < 0, wu = 1; end  % harden

                                    Tx = nm_apply_scalar_weight(Tx, wu); 

                                    if compwise
                                        %% ================= GLOBAL (CROSS-MODALITY) REALIGNMENT — nk_VisModelsC =================
                                        [I, I1, Tx, Psel, Rx, SRx, PAx, assignmentVec, signCorrections, Dx ] = nk_VisXRealignComponents(I, I1, h, Tx, Dx, Psel, Rx, SRx, PAx, Fadd, Vind, il(h), inp, nM, ill);
                                    end

                                    % ===== per-modality aggregate share for aggregated pathways =====
                                    if nM>1 && ~inp.stacking
                                        if isempty(I1.ModAgg_L2nShare{h}), I1.ModAgg_L2nShare{h} = nan(nM, ill); end
                                        v=nan(nM,1);
                                        for n=1:nM
                                            vn = nk_VisXComputeLpShares(Tx{n}, SVM, false); 
                                            if numel(v)>1, v(n) = sum(vn,'omitnan'); else, v(n) = vn; end
                                        end
                                        tot = sum(v);
                                        if tot > 0, Lp_share = v ./ tot; else, Lp_share = 0; end
                                        I1.ModAgg_L2nShare{h}(:, il(h)) = Lp_share; 
                                    end

                                    % --- Perform permutation analysis of model and model weights ---
                                    if permfl
                                    
                                        fprintf('\n\t\t\tRun permutation analysis (%g perms):\t', nperms);
                                        Px_perm = zeros(1,nperms); 
                                        
                                        % --- PREPARATION: initialize running accumulators for each modality ---
                                        for n = 1:nM
                                            if any(decompfl) || compwise
                                                % DR active: Tx{n} is [nFeatures x numComponents]
                                                [nF, nComp] = size(Tx{n});
                                                runningSum{n}   = zeros(nF, nComp);
                                                runningSumSq{n} = zeros(nF, nComp);
                                                exceedCount{n}  = zeros(nF, nComp);
                                                validCount{n}   = zeros(nF, nComp);         % how many finite perms
                                            else
                                                % Aggregated case: Tx{n} is a vector [nFeatures x 1]
                                                nF = numel(Tx{n});
                                                runningSum{n}   = zeros(nF,1);
                                                runningSumSq{n} = zeros(nF,1);
                                                exceedCount{n}  = zeros(nF,1);
                                                validCount{n}   = zeros(nF,1);         % how many finite perms
                                            end
                                        end
                                         
                                        % --- (Second, if sigfl==true & permfl == true) PERMUTATION LOOP ---
                                        for perms = 1:nperms

                                            % Create permuted data
                                            indperm = G.getperm(h,perms); indperm = indperm(pTrInd); 
                                            [ L_perm, Ymodel_perm ] = nk_VisXPermY(Ymodel, inp.label, pTrInd, pmode(1), indperm, indpermfeat, perms, analysis, inp, paramfl, BINMOD, h, k, l, pnt, FullPartFlag, F, u);
                                                
                                            
                                            % We test model signifcance if the ML pipeline does not involve factorization methods
                                            if ~sigfl

                                                % Train permuted model
                                                if isfield(mapY,'VI')
                                                    [~, MD_perm{perms} ] = nk_GetParam2(Ymodel_perm, L_perm, sPs, 1, mapY.VI{k,l}{hix}{u});
                                                else
                                                    [~, MD_perm{perms} ] = nk_GetParam2(Ymodel_perm, L_perm, sPs, 1);
                                                end

                                                % For multiflag mode, collect additional performance measures.
                                                if inp.multiflag
                                                    [~, I1.mTS_perm{h}(:,il(h),perms), I1.mDS_perm{h}(:,il(h),perms)] = ...
                                                             nk_GetTestPerf(modelTsm, modelTsmL, Find, MD_perm{perms}, modelTr, true);
                                                end
        
                                                % Retrieve permuted model performance
                                                [perf_perm, I1.TS_perm{h}(:,il(h),perms), I1.DS_perm{h}(:,il(h),perms)] = ...
                                                         nk_GetTestPerf(modelTs, modelTsL, Find, MD_perm{perms}, modelTr);
                                                
                                                % Compare permuted against
                                                % original model performance
                                                if feval(compfun, perf_perm, perf_orig)
                                                    fprintf('.');
                                                    Px_perm(perms) = Px_perm(perms) + 1;
                                                else
                                                    fprintf('*');
                                                end
                                                Tx_perms = nk_VisXWeightC(inp, MD_perm{perms}, Ymodel_perm, L_perm, varind, ParamX, Find, Vind, decompfl, memoryprob, [], compwise, [], true);
                                                
                                                % Apply boosting weights if needed
                                                % (otherwise multiply with 1)
                                                Tx_perms = nm_apply_scalar_weight(Tx_perms, wu); 
                                            
                                            else
                                                fprintf('+');
                                                % we have to take the top-K
                                                % random components otherwise
                                                % the test will be too liberal.
                                                if inp.isInter
                                                    % sx: vector of scores for this permutation
                                                    sx = Vx_perm(:, perms);
                                                    sx = sx(:);                                % ensure column
                                                    Fadd_perms = false(numel(Fadd),1);
                                                
                                                    % iterate actual modality labels; skip non-DR modalities
                                                    uVals = unique(Vind(:)).';
                                                    for v = uVals
                                                        idx = find(Vind == v);                 % feature indices for this modality
                                                        K_m = nnz(Fadd(idx));                  % how many to keep within this modality
                                                        vals = sx(idx);
                                                        fin  = isfinite(vals);
                                                        % sort finite values descending; clamp K to available finite entries
                                                        [~, ordFin] = sort(vals(fin), 'descend');
                                                        K_keep = min(K_m, nnz(fin));
                                                        finIdx = find(fin);                    % positions within idx that are finite
                                                        keepLocal = finIdx(ordFin(1:K_keep));  % pick top-K finite
                                                        Fadd_perms(idx(keepLocal)) = true;
                                                    end
                                                else
                                                    sx = Vx_perm(:, perms);
                                                    sx = sx(:);
                                                    Fadd_perms = false(numel(Fadd),1);
                                                    sx(~isfinite(sx)) = -Inf;                  % degrade non-finite to bottom
                                                    [~, rx] = sort(sx, 'descend');
                                                    K = nnz(Fadd);
                                                    if K > 0
                                                        keep = rx(1:min(K, numel(rx)));
                                                        Fadd_perms(keep) = true;
                                                    end
                                                end
                                                Tx_perms = nk_VisXWeightC(inp, MD_perm{perms}, Ymodel_perm, L_perm, varind, ParamX, Find, Vind, decompfl, memoryprob, [], compwise, Fadd_perms, true);
                                                % Apply boosting weights if needed
                                                % (otherwise multiply with 1)
                                                Tx_perms = nm_apply_scalar_weight(Tx_perms, wu);  
                                            end

                                            for n = 1:nM

                                                if ~compwise || ~decompfl(n)
                                                    % ===================== Aggregated path =====================
                                                    % (covers non-DR and DR + no-component)
                                                    Tp = Tx_perms{n}(:);        % column vector
                                                    T  = Tx{n}(:);              % matching observed vector
                                                    ok = isfinite(Tp);
                                            
                                                    runningSum{n}(ok)   = runningSum{n}(ok)   + Tp(ok);
                                                    runningSumSq{n}(ok) = runningSumSq{n}(ok) + Tp(ok).^2;
                                                    exceedCount{n}(ok)  = exceedCount{n}(ok)  + double( abs(Tp(ok)) >= abs(T(ok)) );
                                                    validCount{n}(ok)   = validCount{n}(ok)   + 1;
                                                elseif compwise
                                                    % ===================== Component-specific path =====================
                                                    % Realign each modality's permuted weight map if DR is active.
                                                    % Should work for component-level and aggregated case
                                                    % Tx_perms{n} should be a matrix of size [nFeatures x non-zero components].
                                                    nz = any((Tx_perms{n}~=0) & isfinite(Tx_perms{n}), 1);
                                                    if ~any(nz), continue; end
                                                    nonZeroMasksPerm  = nz;
                                                    Tx_perms{n} = Tx_perms{n}(:, nonZeroMasksPerm );
                                                    if inp.isInter
                                                        aVec = assignmentVec{n};
                                                        sCorr = signCorrections{n};
                                                    else
                                                        aVec = assignmentVec;
                                                        sCorr = signCorrections;
                                                    end
                                                    nRef = numel(aVec); 
                                                    % Create an output matrix with the same size as Tx_perms{n}.
                                                    sortedTx = nan(size(Tx_perms{n},1), nRef,'like',Tx_perms{n});
                                                    % Identify the indices in assignmentVec that are valid (i.e. > 0)
                                                    valid = aVec > 0;
                                                    % For columns with valid assignments, reorder them accordingly.
                                                    sortedTx(:, valid) = Tx_perms{n}(:, aVec(valid));
                                                    % Now, sortedTx has the same number of columns as the reference.
                                                    % Apply sign correction
                                                    % Create a full sign-correction vector of the same length as assignmentVec.
                                                    fullSignCorrections = ones(nRef, 1);
                                                    for i = 1:nRef
                                                        if aVec(i) > 0
                                                            % If signCorrections has an entry at index i, use it; otherwise default to 1.
                                                            if i <= nRef
                                                                fullSignCorrections(i) = sCorr(i);
                                                            else
                                                                fullSignCorrections(i) = 1;
                                                            end
                                                        end
                                                    end
                                                    % Now, apply the full vector for sign correction.
                                                    % element‑wise sign correction, leaves NaNs untouched
                                                    Tx_perms{n} = sortedTx.* (ones(size(Tx_perms{n},1),1,'like', Tx_perms{n}) * fullSignCorrections.');
                                                    ok = isfinite(Tx_perms{n});  % mask of valid entries this round
                                                    runningSum{n}(ok)   = runningSum{n}(ok)   + Tx_perms{n}(ok);
                                                    runningSumSq{n}(ok) = runningSumSq{n}(ok) + Tx_perms{n}(ok).^2;
                                                    exceedCount{n}(ok)  = exceedCount{n}(ok)  + double( abs(Tx_perms{n}(ok)) >= abs(Tx{n}(ok)) );
                                                    validCount{n}(ok)   = validCount{n}(ok) + 1;
                                                end
                                            end
                                        end
    
                                        clear MD_perm Tx_perms
                                        
                                        % Compute model significance from permutation accumulators:
                                        if ~sigfl
                                            I1.VCV1MPERM{h}(il(h)) = (sum(Px_perm) + 1 ) / (nperms + 1);
                                            fprintf('\n\t\t\tModel P=%1.3f ', I1.VCV1MPERM{h}(il(h)));
                                        end

                                        % --- POST-PERMUTATION: Compute permutation metrics and update I1 containers ---
                                        for n = 1:nM
                                           
                                            % Should work for component-level and aggregated case
                                            c = validCount{n};
                                            c(c == 0) = NaN;

                                            % now compute mean & std using only the valid counts
                                            permMean = runningSum{n} ./ c;
                                            varHat   = (runningSumSq{n} - (runningSum{n}.^2)./c) ./ max(c-1,1);
                                            permStd  = sqrt(varHat);
                                            
                                            % empirical p‐values
                                            Pvals = (exceedCount{n}+1) ./ (c+1);
                                            
                                            % finally your continuous Z‐scores
                                            Zvals = (Tx{n} - permMean) ./ permStd;
                                        
                                            if decompfl(n) && compwise
    
                                                % ===== COMPONENT-WISE (per-component) path =====
                                                % DR active AND component-wise view: Tx{n}, Pvals, Zvals are [nFeat × nComp]
                                                compMask = any(isfinite(Tx{n}), 1);           
                                                keptIdx  = find(compMask);
                                                fprintf('\n\t\t\tCompute single component stats [Modality #%g]:\t', n);
                                                for kl = keptIdx
                                                    fprintf('~')
                                                    % feature mask for this component
                                                    Fmask = isfinite(Tx{n}(:, kl));
                                            
                                                    % per-component p/z
                                                    compP = Pvals(Fmask, kl);
                                                    compZ = Zvals(Fmask, kl);
                                            
                                                    if inp.stacking
                                                        % ---------- child-predictor aggregation ----------
                                                        for mj = 1:inp.nD
                                                            sel = vec_mj(Fmask) == mj;
                                                            mjP = mean(compP(sel),'omitnan');
                                                            mjZ = mean(compZ(sel),'omitnan');
                                                            I1.VCV1PERM{h,n}(mj, il(h), kl) = mjP;
                                                            [~,~,~, I1.VCV1PERM_FDR{h,n}(mj, il(h), kl)] = fdr_bh(mjP, 0.05, 'pdep');
                                                            I1.VCV1ZSCORE{h,n}(mj, il(h), kl) = mjZ;
                                                        end
                                                    else
                                                        % ---------- voxel / feature space ----------
                                                        [~,~,~, badcoords] = getD(FUSION.flag, inp, n);  
                                                        badcoords = ~badcoords;
                                                        upd = badcoords & Fmask';
                                                        I1.VCV1PERM     {h,n}(upd, il(h), kl) = compP;
                                                        [~,~,~, I1.VCV1PERM_FDR{h,n}(upd, il(h), kl)] = fdr_bh(compP, 0.05, 'pdep');
                                                        I1.VCV1ZSCORE   {h,n}(upd, il(h), kl) = compZ;
                                                    end
                                                end
                                            
                                            else
                                                
                                                % ===== AGGREGATED (no-component) path =====
                                                % Applies to BOTH: non-DR, and DR with compwise==false.
                                                % In this mode Tx{n} is guaranteed to be a VECTOR.
                                                if decompfl(n)
                                                    fprintf('\n\t\t\tCompute stats for aggregated backprojection [Modality #%g]:\t', n);
                                                else
                                                    fprintf('\n\t\t\tCompute stats [Modality #%g]:\t', n);
                                                end
                                                % Ensure column vectors
                                                TxAgg    = Tx{n}(:);
                                                PvalsVec = Pvals(:);   % full-length vectors for non-stacking indexing
                                                ZvalsVec = Zvals(:);
                                            
                                                % Valid feature indices from Tx
                                                Fpind = isfinite(TxAgg)';   % 1×nFeat logical
                                            
                                                if inp.stacking
                                                    % For stacking, we use values only at valid features (Fpind)
                                                    PvalsSel = Pvals(Fpind);   % length == sum(Fpind)
                                                    ZvalsSel = Zvals(Fpind);   % length == sum(Fpind)
                                            
                                                    for mj = 1:inp.nD
                                                        sel_valid_mj = (vec_mj(Fpind) == mj);   % logical over the reduced set
                                                        mjPvals = mean(PvalsSel(sel_valid_mj),'omitnan');
                                                        mjZvals = mean(ZvalsSel(sel_valid_mj),'omitnan');
                                                        I1.VCV1PERM    {h,n}(mj, il(h)) = mjPvals;
                                                        [~,~,~, I1.VCV1PERM_FDR{h,n}(mj, il(h))] = fdr_bh(mjPvals, 0.05, 'pdep');
                                                        I1.VCV1ZSCORE  {h,n}(mj, il(h)) = mjZvals;
                                                    end
                                                else
                                                    % Non-stacking: index full-length vectors by (badcoords & Fpind)
                                                    [~,~,~, badcoords] = getD(FUSION.flag, inp, n);
                                                    badcoords = ~badcoords;                 % valid feature positions
                                                    upd = badcoords & Fpind;                % 1×nFeat logical
                                                    % ensure the 3rd dim exists and grow by one slice (filled with NaN)
                                                    I1.VCV1PERM{h,n}(upd, il(h)) = PvalsVec(upd);
                                                    [~,~,~, I1.VCV1PERM_FDR{h,n}(upd, il(h))] = fdr_bh(PvalsVec(upd), 0.05, 'pdep');
                                                    I1.VCV1ZSCORE{h,n}(upd, il(h)) = ZvalsVec(upd);
                                                end
                                            end
                                            
                                            % ========================= REPORTING (permfl == true) =========================
                                            if decompfl(n) && compwise
                                                % ---------- component-specific case ----------
                                                nk_VisReportGlobalRefStats(I, I1, h, il(h), sigfl, inp.isInter, n);
                                                vcP   = squeeze(I1.VCV1PERM    {h,n}(:, il(h),:));
                                                vcPF  = squeeze(I1.VCV1PERM_FDR{h,n}(:, il(h),:));
                                                validIdx = find(any(isfinite(vcPF)));
                                            else
                                                % ---------- aggregated case (single vector) ----------
                                                vcP   = I1.VCV1PERM    {h,n}(:, il(h));
                                                vcPF  = I1.VCV1PERM_FDR{h,n}(:, il(h));
                                            end
                                            sig     = sum(vcP  <= 0.05,'omitnan');
                                            sigFDR  = sum(vcPF <= 0.05,'omitnan');
                                            minP    = min(vcP, [],'omitnan');
                                            minPFDR = min(vcPF, [],'omitnan');
                                            if decompfl(n) && compwise
                                                for nx = validIdx
                                                    fprintf('\n\t\t\tComp %2g: %g features ≤.05 (minP %1.2e)  |  FDR: %g (min %1.2e)', ...
                                                         nx, sig(nx), minP(nx), sigFDR(nx), minPFDR(nx));
                                                end
                                            else
                                                 fprintf('\n\t\t\tMod %2g: %g features ≤.05 (minP %1.2e)  |  FDR: %g (min %1.2e)', ...
                                                         n, sig, minP, sigFDR, minPFDR);
                                            end
                                        end
                                    else
                                        if any(decompfl) && compwise
                                            for n=1:nM
                                                if decompfl(n)
                                                    % ========================= REPORTING ( permfl == false ) =========================
                                                    nk_VisReportGlobalRefStats(I, I1, h, il(h), sigfl, inp.isInter,n);
                                                end
                                            end
                                        end
                                    end
                                    
                                    % Some additional computation if
                                    % factorization methods have not been used
                                    % in the preprocessing chain of a modality
                                    for n = 1:nM
                                        Fpind = any(Tx{n},2); 
                                        if inp.stacking
                                            for mj = 1:inp.nD
                                                Imj = vec_mj == mj & Fpind;
                                                I1.VCV1{h,n}(mj,il(h)) = mean(Tx{n}(Imj));
                                                if ~decompfl(n) && u==1  
                                                    I1.VCV1PEARSON{h, n}(mj,kil(h)) = nm_nanmean(Rx{n}(Imj));
                                                    I1.VCV1SPEARMAN{h, n}(mj,kil(h)) = nm_nanmean(SRx{n}(Imj));
                                                    I1.VCV1PEARSON_UNCORR_PVAL{h, n}(mj,kil(h)) = nm_nanmean(nk_PTfromR(Rx{n}(Imj), size(Ymodel,1), 2));
                                                    I1.VCV1SPEARMAN_UNCORR_PVAL{h, n}(mj,kil(h)) = nm_nanmean(nk_PTfromR(SRx{n}(Imj), size(Ymodel,1), 2));
                                                    [~,~,~,I1.VCV1PEARSON_FDR_PVAL{h, n}(mj,kil(h))] = fdr_bh(I1.VCV1PEARSON_UNCORR_PVAL{h, n}(mj,kil(h)), 0.05, 'pdep');
                                                    [~,~,~,I1.VCV1SPEARMAN_FDR_PVAL{h, n}(mj,kil(h))] = fdr_bh(I1.VCV1SPEARMAN_UNCORR_PVAL{h, n}(mj,kil(h)), 0.05, 'pdep');
                                                    if linsvmfl
                                                        I1.VCV1PVAL_ANALYTICAL{h, n}(mj,kil(h)) = nm_nanmean(PAx{n}(Imj));
                                                        try
                                                           [~,~,~,I1.VCV1PVAL_ANALYTICAL_FDR{h, n}(mj,kil(h))] = fdr_bh(I1.VCV1PVAL_ANALYTICAL{h, n}(mj,kil(h)),0.05,'pdep');
                                                        catch
                                                           fprintf('\n')
                                                        end
                                                    end
                                                    if ~memoryprob
                                                        mjCx = Cx{n}(Imj, Imj);
                                                        I1.VCV1CORRMAT{h,n}(mj,mj,kil(h)) = nm_nanmean(mjCx(:));
                                                    end
                                                end
                                            end
                                             %% Comnpute feature selection probabilities %%
                                             if inp.fixedOrder && ~decompfl(n)
                                                 if isempty(I1.PCV1SUM{h, n}), I1.PCV1SUM{h, n} = zeros(inp.nD,1); end
                                                 I1.PCV1SUM{h, n} = I1.PCV1SUM{h, n} + Psel{n}; 
                                             end
                                        else
                                            % Define index vector to
                                            % original space of modality
                                            [ ~, ~, ~, badcoords] = getD(FUSION.flag, inp, n); badcoords = ~badcoords;

                                            if ~decompfl(n)
                                                I1.VCV1{h,n}(badcoords, il(h)) = Tx{n};
                                            else
                                                % Tx{n} is a matrix [nFeatures x numComponents].
                                                % Store the values in the third dimension (components) of I1.VCV1{h,n}.
                                                % This requires that I1.VCV1{h,n} has been preallocated appropriately.
                                                if inp.isInter
                                                    if ~isempty(Dx) && ~isempty(Dx{n})
                                                        nSubj     = size(Dx{n},1);
                                                        nComp_new = size(Tx{n},2);        % components in this fold
                                                        if il(h) == 1 && (numel(I1.Dx) < h || numel(I1.Dx{h}) < n || isempty(I1.Dx{h}{n}))
                                                            % First time: full preallocation with NaNs
                                                            I1.Dx{h}{n} = nan(nSubj, jy, nComp_new, 'like', Dx{n});
                                                        else
                                                            % Ensure enough folds dimension (2nd dim) – extend with NaNs if needed
                                                            if size(I1.Dx{h}{n},2) < jy
                                                                I1.Dx{h}{n}(:, size(I1.Dx{h}{n},2)+1:jy, :) = NaN;
                                                            end
                                                            % Ensure enough components (3rd dim) – **NaN sheets** for new components
                                                            curK = size(I1.Dx{h}{n},3);
                                                            if curK < nComp_new
                                                                I1.Dx{h}{n}(:,:,curK+1:nComp_new) = NaN;
                                                            end
                                                        end
                                                    end
                                                elseif inp.isEarly
                                                    if ~isempty(Dx) && ~isempty(Dx{1})
                                                        nSubj     = size(Dx{1},1);
                                                        nComp_new = size(Tx{1},2);
                                                        
                                                        if il(h) == 1 && (numel(I1.Dx) < h || isempty(I1.Dx{h}))
                                                            I1.Dx{h} = nan(nSubj, jy, nComp_new, 'like', Dx{1});
                                                        else
                                                            if size(I1.Dx{h},2) < jy
                                                                I1.Dx{h}(:, size(I1.Dx{h},2)+1:jy, :) = NaN;
                                                            end
                                                            curK = size(I1.Dx{h},3);
                                                            if curK < nComp_new
                                                                I1.Dx{h}(:,:,curK+1:nComp_new) = NaN;
                                                            end
                                                        end
                                                    end
                                                end
                                                
                                                for comp = 1:size(Tx{n},2)
                                                    I1.VCV1{h,n}(badcoords, il(h), comp) = Tx{n}(badcoords, comp);
                                                    if inp.isInter
                                                        if ~isempty(Dx) && ~isempty(Dx{n}), I1.Dx{h}{n}(:, il(h), comp) = Dx{n}(:, comp); end
                                                    elseif inp.isEarly && n==1
                                                        if ~isempty(Dx) && ~isempty(Dx{1}), I1.Dx{h}(:, il(h), comp) = Dx{1}(:, comp); end
                                                    end
                                                    
                                                end
                                            end

                                            if ~decompfl(n) 
                                                if u==1  
                                                    %% Compute univariate correlation coefficient for each feature
                                                    I1.VCV1PEARSON{h, n}(badcoords,kil(h)) = Rx{n};
                                                    I1.VCV1SPEARMAN{h, n}(badcoords,kil(h)) = SRx{n};
                                                    if ~memoryprob
                                                        I1.VCV1CORRMAT{h,n}(badcoords,badcoords,kil(h)) = Cx{n};
                                                    end
                                                    I1.VCV1PEARSON_UNCORR_PVAL{h, n}(badcoords,kil(h)) = nk_PTfromR(Rx{n}, size(Ymodel,1), 2);
                                                    I1.VCV1SPEARMAN_UNCORR_PVAL{h, n}(badcoords,kil(h)) = nk_PTfromR(SRx{n}, size(Ymodel,1), 2);
                                                    if ~memoryprob
                                                        I1.VCV1CORRMAT_UNCORR_PVAL{h, n}(badcoords,badcoords,kil(h)) = nk_PTfromR(Cx{n}, size(Ymodel,1), 2);
                                                    end
                                                    [~,~,~,I1.VCV1PEARSON_FDR_PVAL{h, n}(badcoords,kil(h))] = fdr_bh(I1.VCV1PEARSON_UNCORR_PVAL{h, n}(badcoords,kil(h)), 0.05, 'pdep');
                                                    [~,~,~,I1.VCV1SPEARMAN_FDR_PVAL{h, n}(badcoords,kil(h))] = fdr_bh(I1.VCV1SPEARMAN_UNCORR_PVAL{h, n}(badcoords,kil(h)), 0.05, 'pdep');
                                                    % Use half of the matrix to correct P
                                                    % values
                                                    if ~memoryprob
                                                        p_uncorr = I1.VCV1CORRMAT_UNCORR_PVAL{h, n}(badcoords,badcoords, kil(h));
                                                        sz_p_uncorr = size(p_uncorr,1);
                                                        mI = itriu(sz_p_uncorr,1);
                                                        p_fdr = single(nan(sz_p_uncorr));                
                                                        [~,~,~, c_pfdr] = fdr_bh(p_uncorr(mI), 0.05, 'pdep');
                                                        p_fdr(mI) = c_pfdr;
                                                        I1.VCV1CORRMAT_FDR_PVAL{h, n}(:,:, kil(h)) = p_fdr;
                                                    end
                                                end
                                                %% Comnpute feature selection probabilities %%
                                                if isempty(I1.PCV1SUM{h, n}), I1.PCV1SUM{h, n} = zeros(size(badcoords,2),1); end
                                                I1.PCV1SUM{h, n}(badcoords) = I1.PCV1SUM{h, n}(badcoords) + Psel{n}; 
                                                if linsvmfl
                                                     I1.VCV1PVAL_ANALYTICAL{h, n}(badcoords,kil(h)) = PAx{n};
                                                     try
                                                        [~,~,~,I1.VCV1PVAL_ANALYTICAL_FDR{h, n}(badcoords,kil(h))] = fdr_bh(PAx{n},0.05,'pdep');
                                                     catch
                                                         fprintf('\n')
                                                     end
                                                end
                                            end
                                       end
                                    end
                                    il(h)=il(h)+1;
                                end
                                kil(h)=kil(h)+1;
                                clear Tx Vx Tx_perm Vx_perm tSRx tRx Rx SRx
                                %fprintf(' Done.')
                            end
                        end  
                    end
                    if permfl || sigfl
                        for h=1:nclass
                            % Compute CV2-level model significance
                            modelTsL = mapY.TsL{h};
                            I1.VCV1MORIG_EVALFUNC_CV2{h} = EVALFUNC(modelTsL, nm_nanmedian(I1.DS{h},2)); 
                            I1.VCV1MPERM_CV2{h} = zeros(nperms,1); 
                            I1.VCV1MPERM_EVALFUNC_CV2{h} = zeros(nperms,1);
                            for perms = 1:nperms
                                I1.VCV1MPERM_EVALFUNC_CV2{h}(perms) = EVALFUNC(modelTsL, nm_nanmedian(I1.DS_perm{h}(:,:,perms),2)); 
                                I1.VCV1MPERM_CV2{h}(perms)          = feval(compfun, I1.VCV1MPERM_EVALFUNC_CV2{h}(perms), I1.VCV1MORIG_EVALFUNC_CV2{h} );
                            end
                        end
                    end
                    clear Tx tmp V Ymodel modelTr modelTrL F Fkl dum 
                end
              
                [~, I1] = nk_VisXHelperC('prune', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, ll, nperms, I1, compwise);  
           
                fprintf('\nSaving %s', oVISpath); 
                if OCTAVE
                    save(oVISpath,'I1','sPs','operm','ofold');
                else
                    save(oVISpath,'-v7.3','I1','sPs','operm','ofold');
                end
                [I,I1] = CV2wrapUp(I,I1);
                if saveparam, fprintf('\nSaving %s', OptModelPath); save(OptModelPath, 'MD', 'ofold','operm', '-v7.3'); end
                if isfield(I1,'PCV1SUM'), PCV1SUMflag=true; else, PCV1SUMflag = false; end
                clear Param MD
                
            case 1

                vpth = deblank(vismat{f,d});

                if isempty(vpth) || ~exist(vpth,'file')
                    warning(['No valid VISdata-MAT detected for CV2 partition ' '[' num2str(f) ', ' num2str(d) ']!']);
                else
                    CVPOS.mode = 'loaded';
                    [~,vnam] = fileparts(vpth);
                    ind0(ll) = true; 
                    fprintf('\nLoading visualization data: %s.', vnam); ill=[];
                    [I,I1] = CV2wrapUp(I,vpth);
                    ol=ol+1;
                end
                if isfield(I1,'PCV1SUM'), PCV1SUMflag=true; else, PCV1SUMflag = false; end
        end
        ll=ll+1; clear GDFEAT
        clear I1 
    end
end
    % ----------------------------------------------------------------------------------------------------------------------------------------------
    function [I, I1, filefound] = CV2wrapUp(I, I1)
        [I, I1, filefound] = nk_VisXHelperC('align', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, ll, nperms, I1, compwise, ill);
        if filefound
            [I, I1] = nk_VisXHelperC('prune_memory', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, ll, nperms, I1, compwise);
            try
                [I, I1] = nk_VisXHelperC('accum', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, ll, nperms, I1, compwise);
            catch
                [I, I1] = nk_VisXHelperC('prune_memory', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, ll, nperms, I1, compwise);
                [I, I1] = nk_VisXHelperC('accum', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, ll, nperms, I1, compwise);
            end
            try
                [I, I1] = nk_VisXHelperC('merge_and_prune', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, ll, nperms, I1, compwise);
            catch
                [I, I1] = nk_VisXHelperC('prune_memory', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, ll, nperms, I1, compwise);
                [I, I1] = nk_VisXHelperC('merge_and_prune', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, ll, nperms, I1, compwise);
            end
            [I, I1] = nk_VisXHelperC('report', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, ll, nperms, I1, compwise);
            if VERBOSE
                for curclass = 1:nclass
                    nk_plot_VCV2CorrRef(I.VCV2WCORRREF, curclass, VERBOSE, sprintf('Model [%g]: Component correlations and contributions',curclass))
                end
            end
            WriteCV2Data(inp, nM, FUSION, SAV, operm, ofold, I1);
            % Assemble observed and permuted model predictions of current CV2
            % partition into overall prediction matrix
            if permfl || sigfl
                I = ComputeObsPermPerf(inp, I, I1, CV, f, d, ll, nclass, ngroups, nperms, operm, ofold, MODEFL, RFE, compfun);
            end
        end
    end
    % ------------------------------------------------------------------------------------------------------------------------------------------------ 

%% PERFORM POST-PROCESSING VISUALIZATION PROCEDURES ON THE ENTIRE DATA 
if ~batchflag
    
    % visdata is a cell array of with nM dimensions, where nM is defined by
    % the number of modalities used in the analysis
    visdata = cell(1,nM);

    % ——— Compute CV2 averages of the back‐projected metrics ———
    if any(decompfl) && compwise
        % user-definable thresholds with sensible defaults
        if ~isfield(inp, 'SelCompCutOff') || isempty(inp.SelCompCutOff), selMin = 0.20; else, selMin = inp.SelCompCutOff; end
        if ~isfield(inp, 'CorrCompCutOff')  || isempty(inp.CorrCompCutOff), corrMin  = 0.30; else, corrMin  = inp.CorrCompCutOff;  end

        for h = 1:nclass
            denom = I.VCV2NMODEL(h);
            if inp.isInter
                for n=1:nM
                    if ~decompfl(n), continue; end
                    % Selection matrix across CV2 folds:
                    % rows = reference components, cols = CV2 models/folds
                    W = I.VCV2WPERMREF{h}{n};         % size: [nComp x nModelsCV2]
                    
                    % Correct p values globally if user chose this option
                    if sigPfdr == 2
                        I.VCV2WPERMREF_GLOBAL_FDR{h}{n} = correct_p_values_across_cv(W);
                    end
                    nComp   = size(W, 1);
                    
                    % Selection likelihood across CV2 folds
                    present = sum(~isnan(W), 2);          % times selected
                    selProp = present ./ max(denom, 1); % guard against divide-by-zero
                
                    % Mean correlation per component (rowwise)
                    C = I.VCV2WCORRREF{h}{n};                % expected size: [nComp x nModelsCV2]
                    if isempty(C)
                        meanCorr = nan(nComp,1);
                    else
                        % length align if needed
                        nCompC = size(C,1);
                        if nCompC ~= nComp
                            % Trim/pad to match W’s row count
                            if nCompC > nComp, C = C(1:nComp,:); else, C(end+1:nComp, :) = NaN; end
                        end
                        meanCorr = mean(C, 2, 'omitnan');
                    end
                
                    % Dual-criterion keep mask
                    keep = (meanCorr >= corrMin) & (selProp >= selMin);
                
                    %safety fallback (keep best by meanCorr):
                    if ~any(keep) && nComp > 0
                         [~,best] = max(meanCorr); keep(best) = true;
                    end
                
                    % Store outputs (and keep selProp for diagnostics)
                    I.PRES{h}{n}      = selProp;   % selection likelihood across CV2
                    I.KEEP{h}{n}      = keep;      % final mask

                end
            else
                % Selection matrix across CV2 folds:
                % rows = reference components, cols = CV2 models/folds
                W = I.VCV2WPERMREF{h};         % size: [nComp x nModelsCV2]

                % Correct p values globally if user chose this option
                if sigPfdr==2
                    I.VCV2WPERMREF_GLOBAL_FDR{h} = correct_p_values_across_cv(W);
                end

                nComp   = size(W, 1);
                
                % Selection likelihood across CV2 folds
                present = sum(~isnan(W), 2);          % times selected
                selProp = present ./ max(denom, 1); % guard against divide-by-zero
            
                % Mean correlation per component (rowwise)
                C = I.VCV2WCORRREF{h};                % expected size: [nComp x nModelsCV2]
                if isempty(C)
                    meanCorr = nan(nComp,1);
                else
                    % length align if needed
                    nCompC = size(C,1);
                    if nCompC ~= nComp
                        % Trim/pad to match W’s row count
                        if nCompC > nComp, C = C(1:nComp,:); else, C(end+1:nComp, :) = NaN; end
                    end
                    meanCorr = mean(C, 2, 'omitnan');
                end
            
                % Dual-criterion keep mask
                keep = (meanCorr >= corrMin) & (selProp >= selMin);
            
                %safety fallback (keep best by meanCorr):
                if ~any(keep) && nComp > 0
                     [~,best] = max(meanCorr); keep(best) = true;
                end
            
                % Store outputs (and keep selProp for diagnostics)
                I.PRES{h}      = selProp;   % selection likelihood across CV2
                I.KEEP{h}      = keep;      % final mask
            end
        end
        I = nk_VisXHelperC('prune_final', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, [], [], [], compwise);
    end
    
    if permfl || sigfl
        
        % mean and SD model significance of binary models at the CV1 level
        I.VCV2MODELP = nm_nanmedian(I.VCV2MPERM,2); 
        I.VCV2MODELP_STD = nm_nanstd(I.VCV2MPERM); 
        
        % Loop through classifiers / regressors and compute hold-out
        % model significance 
        for h=1:nclass
            switch MODEFL
                case 'classification'
                    if numel(CV.class{1,1}{h}.groups) == 2
                        ind1 = inp.label == CV.class{1,1}{h}.groups(1); f1 = ones(sum(ind1),1);
                        ind2 = inp.label == CV.class{1,1}{h}.groups(2); f2 = -1*ones(sum(ind2),1);
                        labelh = zeros(numel(inp.label),1);
                        labelh(ind1) = f1; labelh(ind2) = f2; %labelh(~labelh)=[];
                    else
                        labelh = zeros(size(inp.label,1),1);
                        ind1 = inp.label == CV.class{1,1}{h}.groups(1); 
                        labelh(ind1) = 1; labelh(~ind1,h) = -1;
                    end
                case 'regression'
                    labelh = inp.label;
            end
            indempt     = ~(cellfun(@isempty,I.VCV2MORIG_S) | isnan(cellfun(@sum,I.VCV2MORIG_S)));
            Porig       = cellfun(@nm_nanmedian,I.VCV2MORIG_S(indempt(:,h),h)); 
            Lorig       = labelh(indempt(:,h));
            if inp.targscale, IN.revertflag = true; IN.minY = inp.minLbCV; IN.maxY = inp.maxLbCV; Porig = nk_PerfScaleObj(Porig, IN); end
            % Observed hold out performance
            I.VCV2MORIG_EVALFUNC_GLOBAL(h) = EVALFUNC(Lorig, Porig);
            fprintf('\nTesting observed %s model performance [ model #%g: %s = %1.2f ] in the hold-out data against %g permutations\n', ...
                                        MODEFL, h, char(EVALFUNC),  I.VCV2MORIG_EVALFUNC_GLOBAL(h), nperms);
            for perms = 1 : nperms
                Pperm                                = cellfun(@nm_nanmedian, I.VCV2MPERM_S(indempt(:,h),h,perms));
                if inp.targscale, Pperm              = nk_PerfScaleObj(Pperm, IN); end
                % Permuted hold-out performances
                I.VCV2MPERM_EVALFUNC_GLOBAL(h,perms) = EVALFUNC(Lorig, Pperm); 
                crt                                  = feval(compfun, I.VCV2MPERM_EVALFUNC_GLOBAL(h,perms), I.VCV2MORIG_EVALFUNC_GLOBAL(h));
                if ~crt, fprintf('*'); else, fprintf('.'); end
                % Store boolean measuring whether permuted hold-out
                % performance was better than the observed performance
                I.VCV2MPERM_GLOBAL(h,perms)          = crt;
            end
        end
        
        % Test models' generalizability to additional (external) labels
        if ~isempty(inp.extraL)
            I = nk_VisModels_ExtraLabels(I, inp, nperms, compfun);
        end
        
        % Perform multi-class significance test including entire model and
        % binary dichotomizers (one vs. REST models, irrespective of 
        % one-vs-one or one-vs-all decomposition schemes)
        if inp.multiflag
            
            % mean and SD model significance of multi-class models at the CV1 level
            I.VCV2MODELP = nm_nanmedian(I.VCV2MPERM_MULTI); 
            I.VCV2MODELP_STD = nm_nanstd(I.VCV2MPERM_MULTI); 
            
            I.VCV2MPERM_GLOBAL_MULTI = zeros(1,nperms);
            fprintf('\nTesting observed multi-class model performance against permuted models using entire data: %g permutations\n', nperms)
            % Convert predictions to class-membership probabilities of
            % observed model
            MultiCV2Prob_orig           = nk_ConvProbabilities(I.VCV2MORIG_S_MULTI, ngroups);
            ind                         = isnan(MultiCV2Prob_orig(:,1)) | isnan(inp.label); 
            [~, MultiCV2Pred_orig]      = max(MultiCV2Prob_orig,[],2);
            MultiCV2Pred_orig(ind)      = NaN;
            MultiCV2Errs_orig           = nan(size(ind,1),1);
            MultiCV2Errs_orig(ind)      = inp.label(ind)~= MultiCV2Pred_orig(ind);
            % Compute multi-class confusion matrix of observed model
            MultiCV2ConfMatrix_orig     = nk_ComputeConfMatrix(inp.label, MultiCV2Pred_orig, ngroups);
            % Observed multi-class performance and one vs. REST
            % dichotomizers are stored in a structure:
            I.VCV2MORIG_GLOBAL_MULTI    = nk_MultiClassAssessConfMatrix(MultiCV2ConfMatrix_orig, inp.label, MultiCV2Pred_orig, MultiCV2Errs_orig, 'BAC');
            fprintf('\nMulti-class performance: %1.2f | Permuting:\t', I.VCV2MORIG_GLOBAL_MULTI.BAC_Mean);
            I.VCV2PERM_GLOBAL_MULTI     = zeros(1,nperms);
            I.VCV2PERM_GLOBAL_MULTI_ONEvsREST = zeros(ngroups,nperms);
            for perms = 1 : nperms
                % Convert predictions to class-membership probabilities
                MultiCV2Prob_perm               = nk_ConvProbabilities(I.VCV2MPERM_S_MULTI(:,:,perms), ngroups);
                [~, MultiCV2Pred_perm]          = max(MultiCV2Prob_perm,[],2);
                MultiCV2Pred_perm(ind)          = NaN;
                MultiCV2Errs_perm               = nan(size(ind,1),1);
                MultiCV2Errs_perm(ind)          = inp.label(ind)~= MultiCV2Pred_perm(ind);
                % Compute multi-class confusion matrix of permuted model
                MultiCV2ConfMatrix_perm         = nk_ComputeConfMatrix(inp.label, MultiCV2Pred_perm, ngroups);
                % Permuted hold-out performance of the multi-class models
                % and its dichotomizers
                multicv2perf_perm               = nk_MultiClassAssessConfMatrix(MultiCV2ConfMatrix_perm, inp.label, MultiCV2Pred_perm, MultiCV2Errs_perm, 'BAC');
                I.VCV2PERM_GLOBAL_MULTI(perms)  = multicv2perf_perm.BAC_Mean;
                I.VCV2PERM_GLOBAL_MULTI_ONEvsREST(:, perms) = multicv2perf_perm.BAC;
                % Evaluate permutation test criterion in multi-class model
                % and its dichotomizers
                crt_multi = feval(compfun, I.VCV2PERM_GLOBAL_MULTI(perms), I.VCV2MORIG_GLOBAL_MULTI.BAC_Mean);
                crt_onevsrest = feval(compfun, I.VCV2PERM_GLOBAL_MULTI_ONEvsREST(:,perms), I.VCV2MORIG_GLOBAL_MULTI.BAC');
                if ~crt_multi, fprintf('*'); else, fprintf('.'); end
                % Store test results
                I.VCV2MPERM_GLOBAL_MULTI(perms) = crt_multi;
                I.VCV2MPERM_GLOBAL_MULTI_ONEvsREST(:,perms) = crt_onevsrest;
            end
        end
    end
     I = nk_VisXHelperC('report_final', nM, nclass, decompfl, permfl, sigfl, ix, jx, I, inp, [], [], [], compwise);
    
    for n=1:nM
        
        % Number of classifiers / predictors
        [ D, datatype, brainmaski, badcoordsi, labeli, labelopi ] = getD(FUSION.flag, inp, n);
        
        %if iscell(inp.VIS), nVIS = inp.VIS{n}; else, nVIS = inp.VIS; end
        
        % Probability of feature selection across all CV2 * CV1 partitions
        for h=1:nclass
            NumPredDiv = repmat(I.VCV2NMODEL(h),size(I.VCV2SEL{h,n},1),1);
            if ~decompfl(n) 
                if PCV1SUMflag && h==1, I.PCV2 = zeros(D,nclass); end
                I.PCV2(:,h) = I.PCV2SUM{h, n}' ./ NumPredDiv; 
                if size(I.VCV2PEARSON{h, n},2)>1
                    % Compute mean and SD univariate association measures
                    % (currently Pearson and Spearman), and their uncorrected
                    % and FDR-corrected statistical significance
                    I.VCV2PEARSON_STD{h,n} = std(I.VCV2PEARSON{h, n}, [], 2, 'omitnan');
                    I.VCV2PEARSON{h,n} = mean(I.VCV2PEARSON{h, n},2, 'omitnan');
                    I.VCV2SPEARMAN_STD{h,n} = std(I.VCV2SPEARMAN{h, n}, [], 2, 'omitnan');
                    I.VCV2SPEARMAN{h,n} = mean(I.VCV2SPEARMAN{h, n}, 2, 'omitnan');
                    I.VCV2PEARSON_UNCORR_PVAL_STD{h,n} = std(I.VCV2PEARSON_UNCORR_PVAL{h, n}, [], 2, 'omitnan');
                    I.VCV2PEARSON_UNCORR_PVAL{h,n} = mean(I.VCV2PEARSON_UNCORR_PVAL{h, n},2, 'omitnan');
                    I.VCV2SPEARMAN_UNCORR_PVAL_STD{h,n} = std(I.VCV2SPEARMAN_UNCORR_PVAL{h, n}, [], 2, 'omitnan');
                    I.VCV2SPEARMAN_UNCORR_PVAL{h,n} = mean(I.VCV2SPEARMAN_UNCORR_PVAL{h, n},2, 'omitnan');
                    I.VCV2PEARSON_FDR_PVAL{h,n} = mean(I.VCV2PEARSON_FDR_PVAL{h, n},2, 'omitnan');
                    I.VCV2SPEARMAN_FDR_PVAL{h,n} = mean(I.VCV2SPEARMAN_FDR_PVAL{h, n},2, 'omitnan');
                    % Compute analytical p values using the method of
                    % Gaonkar et al. if linear SVM was the base learner
                    if linsvmfl
                        I.VCV2PVAL_ANALYTICAL{h,n} = mean(I.VCV2PVAL_ANALYTICAL{h, n},2, 'omitnan');
                        I.VCV2PVAL_ANALYTICAL_FDR{h,n} = mean(I.VCV2PVAL_ANALYTICAL_FDR{h, n},2, 'omitnan');
                    end
                    if ~isempty(I.VCV2CORRMAT{h,n})
                        I.VCV2CORRMAT{h,n} = mean(I.VCV2CORRMAT{h, n}, 3, 'omitnan');
                        I.VCV2CORRMAT_STD{h,n} = std(I.VCV2CORRMAT{h, n}, [], 3, 'omitnan');
                        I.VCV2CORRMAT_UNCORR_PVAL{h,n} = mean(I.VCV2CORRMAT_UNCORR_PVAL{h, n},3, 'omitnan');
                        I.VCV2CORRMAT_UNCORR_PVAL_STD{h,n} = std(I.VCV2CORRMAT_UNCORR_PVAL{h, n}, [], 3, 'omitnan');
                        I.VCV2CORRMAT_FDR_PVAL{h,n} = mean(I.VCV2CORRMAT_FDR_PVAL{h, n},3, 'omitnan');
                        I.VCV2CORRMAT_FDR_PVAL_STD{h,n} = std(I.VCV2CORRMAT_FDR_PVAL{h, n}, [], 3, 'omitnan');
                    end
                end
            end
            % Compute empirical multivariate p values (corrected and
            % uncorrected as well as Z scores
            SEL = I.VCV2SEL{h,n};
            SEL(all(SEL==0,2), :) = NaN;
            if permfl
                % Z scores (component-wise)
                I.VCV2ZSCORE{h,n} = I.VCV2ZSCORE{h,n} ./ SEL;
                % Uncorrected p values (component-wise)
                Pvals = I.VCV2PERM{h,n} ./ SEL ;
                % FDR-Corrected p values (component-wise)
                Pvals_fdr = I.VCV2PERM_FDR{h,n} ./ SEL ;
                Pvals(Pvals==0) = realmin;
                Pvals_fdr(Pvals_fdr==0) = realmin;
                I.VCV2PERM{h,n} = -log10(Pvals);
                I.VCV2PERM_ZBASED{h,n} = -log10(1-normcdf(I.VCV2ZSCORE{h,n}));
                I.VCV2PERM_FDR_PVAL{h,n} = -log10(Pvals_fdr);
                [~,~,~,I.VCV2PERM_FDR_ZBASED{h,n}] = fdr_bh(1-normcdf(I.VCV2ZSCORE{h,n}));
                I.VCV2PERM_FDR_ZBASED{h,n} = -log10(I.VCV2PERM_FDR_ZBASED{h,n});
            end
            
            if decompfl(n)
                    %Grand mean scores: CV2 mean of CV1 means of weight vectors
                    I.VCV2MEAN_CV1{h,n} = squeeze(mean(I.VCV2MEAN{h,n},2, 'omitnan'));
                    % Compute grand mean of CV1 stds / sems of weight vectors 
                    I.VCV2SE_CV1{h,n}   = squeeze(mean(I.VCV2STD{h,n},2, 'omitnan'));
            else
                if size(I.VCV2SQ{h, n},2)>1
                    I.VCV2MEAN_CV1{h,n} = mean(I.VCV2MEAN{h,n},2, 'omitnan');
                    I.VCV2SE_CV1{h,n}   = mean(I.VCV2STD{h,n},2, 'omitnan');
                else
                    I.VCV2MEAN_CV1{h,n} = I.VCV2MEAN{h,n};
                    I.VCV2SE_CV1{h,n}   = I.VCV2STD{h,n};
                end
            end
            % Prepare for computation of global CVR
            SQ = sqrt(I.VCV2SQ{h,n} ./ SEL - (I.VCV2SUM{h,n} ./ SEL).^2);
            switch inp.CVRnorm 
                case 1
                    % we use the standard deviation, which is not
                    % sensitive to the number of partitions
                    I.VCV2SE{h,n} = SQ;
                case 2
                    % whereas here we use the SEM which is closer to the
                    % bootstrap ratio but produces overly lenient results
                    % in cross-validation settings with a high number of
                    % partitions
                    I.VCV2SE{h,n} = (SQ./sqrt(SEL))*1.96;
            end
            
            % Compute Global mean relevance/weight vector across all models partitions
            I.VCV2{h,n} = I.VCV2SUM{h,n} ./ SEL; 

            % Compute Global CVR
            I.VCV2rat{h,n} = I.VCV2{h,n}./I.VCV2SE{h,n};

            % Compute global sign-based consistency, Z scores and P values
            Rnan = SEL ./ I.VCV2NMODEL(h);
            Ip   = (I.SignPosCount{h,n} ./ SEL) .* Rnan;
            In   = (I.SignNegCount{h,n} ./ SEL) .* Rnan;
            I.SignBasedConsistency{h,n} = abs(Ip - In);
            [I.VCV2signconst_p{h,n}, I.VCV2signconst_pfdr{h,n}, I.VCV2signconst_z{h,n}, I.VCV2signconst{h,n}] = ...
                nk_SignBasedConsistencySignificance([],I.SignBasedConsistency{h,n});  
            
            % Compute GrandMean metrics: 
            % 2) Grand Mean Map where mean > std/sem
            I.VCV2MEANthreshSE_CV1{h,n} = zeros(size(I.VCV2MEAN_CV1{h,n}),'single');
            indMEANgrSE = abs(I.VCV2MEAN_CV1{h,n}) > I.VCV2SE_CV1{h,n};
            I.VCV2MEANthreshSE_CV1{h,n}(indMEANgrSE) = I.VCV2MEAN_CV1{h,n}(indMEANgrSE);

            % 3) Compute voxel selection probability using 95% confidence interval method (changed on 27/11/2023).
            I.VCV2PROB{h,n} = (I.VCV2PROB{h,n} ./ ol) .*sign(I.VCV2MEAN_CV1{h,n});
            if ~inp.stacking
                 if nM>1
                    S = I.ModAgg_L2nShare{h};    % [nMod x nCV1] raw shares
                    % Robust guard
                    if ~isempty(S) && isnumeric(S)
                        % Row-wise stats
                        med  = nm_nanquantile(S, 0.50, 2);
                        lo95 = nm_nanquantile(S, 0.025, 2);
                        hi95 = nm_nanquantile(S, 0.975, 2);
                        nn   = sum(isfinite(S), 2);
                
                        % Store summaries next to raw shares
                        I.ModAgg_L2nShare_SUMMARY{h}.median = med;   % [nMod x 1]
                        I.ModAgg_L2nShare_SUMMARY{h}.lo95   = lo95;  % [nMod x 1]
                        I.ModAgg_L2nShare_SUMMARY{h}.hi95   = hi95;  % [nMod x 1]
                        I.ModAgg_L2nShare_SUMMARY{h}.n      = nn;    % [nMod x 1]
                    else
                        I.ModAgg_L2nShare_SUMMARY{h} = struct('median',[],'lo95',[],'hi95',[],'n',[]);
                    end
                    
                end
                if compwise
                    S = I.ModComp_L2n{h};
                    % Robust guard
                    if ~isempty(S) && isnumeric(S)
                        % Row-wise stats
                        med  = nm_nanquantile(S, 0.50, 2);
                        lo95 = nm_nanquantile(S, 0.025, 2);
                        hi95 = nm_nanquantile(S, 0.975, 2);
                        nn   = sum(isfinite(S), 2);
                
                        % Store summaries next to raw shares
                        I.ModComp_L2n_SUMMARY{h}.median = med;   % [nMod x 1]
                        I.ModComp_L2n_SUMMARY{h}.lo95   = lo95;  % [nMod x 1]
                        I.ModComp_L2n_SUMMARY{h}.hi95   = hi95;  % [nMod x 1]
                        I.ModComp_L2n_SUMMARY{h}.n      = nn;    % [nMod x 1]
                    else
                        I.ModComp_L2n_SUMMARY{h} = struct('median',[],'lo95',[],'hi95',[],'n',[]);
                    end
                end
            end
        end

        if numel(inp.tF)>1 && datatype
            fprintf('\n\nWriting out images for Modality #%g',i)
        end
        
        % Now we have to differentiate between imaging and non-imaging
        % analyses. In the former case we write out data to the disk
        if datatype ==1 || datatype==2
            
            currdir = pwd;
            cd(inp.rootdir);
            
            for h = 1:nclass
                % build base names/suffix
                imgname = SAV.matname;
                suff    = ['_NumPred-' num2str(I.VCV2NMODEL(h))];
                varsuff = sprintf('_var%g', inp.tF(n));
                switch MODEFL
                    case 'regression'
                        basename = 'PredictVol';
                        suff = [multlabelstr suff varsuff '_ID' id];
                    case 'classification'
                        basename = 'DiscrimVol';
                        suff = [multlabelstr '_cl' num2str(h) suff varsuff '_ID' id];
                end
            
                % prepare empty holders
                vols   = [];    % will be [#voxels x #images]
                names  = {};    % cell array of filenames
            
                %  First, build a 2-column cell array: { data, tag }
                metrics = {
                            I.VCV2{h,n},                'Mean';
                            I.VCV2rat{h,n},             'CVratio';
                            I.VCV2SE{h,n},              'SE';
                            I.VCV2MEAN_CV1{h,n},        'Mean-GrM';
                            I.VCV2SE_CV1{h,n},          'SE-GrM';
                            I.VCV2MEANthreshSE_CV1{h,n},'Mean-thrSE-GrM';
                            I.VCV2PROB{h,n},            'Prob95CI-GrM';
                            I.VCV2signconst{h,n},       'SignBased';
                            I.VCV2signconst_z{h,n},     'SignBased_Z';
                            I.VCV2signconst_p{h,n},     'SignBased_p_uncorr';
                            I.VCV2signconst_pfdr{h,n},  'SignBased_p_FDR';
                        };
            
                % append univariate only if aggregated (not decompfl)
                if ~decompfl(n)
                    if ~isempty(I.VCV2SPEARMAN{h,n})
                        metrics(end+1,:) = { I.VCV2SPEARMAN{h,n}, 'Spearman-GrM' };
                    end
                    if ~isempty(I.VCV2PEARSON{h,n})
                        metrics(end+1,:) = { I.VCV2PEARSON{h,n},  'Pearson-GrM'  };
                    end
                end
            
                % permutation metrics
                if permfl
                    metrics(end+1,:) = { I.VCV2ZSCORE{h,n},          'PermZ'       };
                    metrics(end+1,:) = { I.VCV2PERM_ZBASED{h,n},     'PermProb'    };
                    metrics(end+1,:) = { I.VCV2PERM_FDR_ZBASED{h,n}, 'PermProbFDR' };
                end
            
               % Prepare kept component labels (only exists in compwise mode)
                if decompfl(n) && compwise
                    keptComps = find(I.KEEP{h}); 
                end
                
                % now loop over each metric
                for m = 1:size(metrics,1)
                
                    data = metrics{m,1};   % vector or [nF × nComp] matrix
                    tag  = metrics{m,2};
                
                    if decompfl(n) && compwise && ~isempty(data) && size(data,2) > 1
                        % component-wise: write one volume per column
                        K = size(data,2);
                        % Use I.KEEP labels if they line up; otherwise label 1..K
                        if ~isempty(keptComps) && numel(keptComps) == K
                            compLabels = keptComps(:).';
                        else
                            compLabels = 1:K;
                        end
                        for kc = 1:K
                            vols(:, end+1) = data(:, kc);
                            names{end+1}   = sprintf('%s_%s_comp%02d_%s%s', ...
                                                     basename, tag, compLabels(kc), imgname, suff);
                        end
                    else
                        % aggregated/vector case (covers non-DR and DR+no-component)
                        vols(:, end+1) = data(:);
                        names{end+1}   = sprintf('%s_%s_%s%s', basename, tag, imgname, suff);
                    end
                end
            
                % convert names into char array for nk_WriteVol
                volnam = char(names);
            
                % dispatch to the appropriate writer
                switch datatype
                    case 1  % SPM‐style NIfTI
                        nk_WriteVol(vols, volnam, 2, brainmaski, [], labeli, labelopi);
            
                    case 2  % surface‐based
                        [~,~,ext] = fileparts(brainmaski);
                        switch ext
                            case {'.mgh','.mgz'}
                                s = MRIread(brainmaski);
                                for yy = 1:size(vols,2)
                                    fname = fullfile(pwd, [deblank(volnam(yy,:)) '.mgh']);
                                    s.vol = vols(:,yy);
                                    MRIwrite(s, fname);
                                end
                            case '.gii'
                                s = GIIread(brainmaski);
                                for yy = 1:size(vols,2)
                                    fname = fullfile(pwd, [deblank(volnam(yy,:)) '.gii']);
                                    save( ...
                                      gifti(struct( ...
                                        'vertices',double(s.vertices), ...
                                        'faces',   double(s.faces),    ...
                                        'cdata',   vols(:,yy)          ...
                                      )), fname ...
                                    );
                                end
                        end
                end
            end
            
            cd(currdir);

        end
        
        %% Build output structure
        visdata{n}.params.dimvecx      = [1 D];
        visdata{n}.params.varind       = inp.tF(n);
        visdata{n}.params.visflag      = datatype;
        visdata{n}.params.brainmask    = brainmaski;
        visdata{n}.params.badcoords    = badcoordsi;
        visdata{n}.params.I.numCV2part = ll-1;
        visdata{n}.params.NumPred      = I.VCV2NMODEL(h);
        
        if ~isempty(featnames) && ~isempty(featnames{n})
            visdata{n}.params.features = featnames{n};
        else
            visdata{n}.params.features = cellstr(num2str((1:D)'));
        end
        visdata{n}.params.nfeats       = numel(visdata{n}.params.features);
        visdata{n}.MEAN                = I.VCV2(:,n);
        visdata{n}.SE                  = I.VCV2SE(:,n);
        visdata{n}.CVRatio             = I.VCV2rat(:,n);
        visdata{n}.MEAN_CV2            = I.VCV2MEAN_CV1(:,n);
        visdata{n}.SE_CV2              = I.VCV2SE_CV1(:,n);
        visdata{n}.Prob_CV2            = I.VCV2PROB(:,n);
        visdata{n}.SignBased_CV2       = I.VCV2signconst(:,n);
        visdata{n}.SignBased_CV2_p_uncorr = I.VCV2signconst_p(:,n);
        visdata{n}.SignBased_CV2_p_fdr = I.VCV2signconst_pfdr(:,n);
        visdata{n}.SignBased_CV2_z     = I.VCV2signconst_z(:,n);
        
        if ~decompfl(n)
            if isfield(I,'PCV2')
                visdata{n}.FeatProb        = {I.PCV2}; 
            end
            visdata{n}.Pearson_CV2              = I.VCV2PEARSON(:,n);
            visdata{n}.Spearman_CV2             = I.VCV2SPEARMAN(:,n);
            visdata{n}.Pearson_CV2_p_uncorr     = I.VCV2PEARSON_UNCORR_PVAL(:,n);
            visdata{n}.Spearman_CV2_p_uncorr    = I.VCV2SPEARMAN_UNCORR_PVAL(:,n);
            visdata{n}.Pearson_CV2_p_fdr        = I.VCV2PEARSON_FDR_PVAL(:,n);
            visdata{n}.Spearman_CV2_p_fdr       = I.VCV2SPEARMAN_FDR_PVAL(:,n);
            if isfield(I,'VCV2PEARSON_STD')
                visdata{n}.Pearson_CV2_STD          = I.VCV2PEARSON_STD(:,n);
                visdata{n}.Spearman_CV2_STD         = I.VCV2SPEARMAN_STD(:,n);
                visdata{n}.Pearson_CV2_p_uncorr_STD = I.VCV2PEARSON_UNCORR_PVAL_STD(:,n);
                visdata{n}.Spearman_CV2_p_uncorr_STD= I.VCV2SPEARMAN_UNCORR_PVAL_STD(:,n);
            end
            if linsvmfl
                visdata{n}.Analytical_p = I.VCV2PVAL_ANALYTICAL(:,n);
                visdata{n}.Analyitcal_p_fdr = I.VCV2PVAL_ANALYTICAL_FDR(:,n);
            end
            if ~isempty(I.VCV2CORRMAT{n})
                visdata{n}.CorrMat_CV2              = I.VCV2CORRMAT(:,n);
                visdata{n}.CorrMat_CV2_p_uncorr     = I.VCV2CORRMAT_UNCORR_PVAL(:,n);
                visdata{n}.CorrMat_CV2_p_fdr        = I.VCV2CORRMAT_FDR_PVAL(:,n);
                if isfield(I,'VCV2CORRMAT_STD')
                    visdata{n}.CorrMat_CV2_STD          = I.VCV2CORRMAT_STD(:,n);
                    visdata{n}.CorrMat_CV2_p_uncorr_STD = I.VCV2CORRMAT_UNCORR_PVAL_STD(:,n);
                    visdata{n}.CorrMat_CV2_p_fdr_STD    = I.VCV2CORRMAT_FDR_PVAL_STD(:,n);
                end
            end
        elseif compwise
            % expose the CV2‐averaged back‐projection matrices
            if inp.isInter
                visdata{n}.CompRefSpace{h}              = I.VCV1REF{h}{n};
                visdata{n}.PermPValRef_CV2{h}           = I.VCV2WPERMREF{h}{n};
                if isfield(I,'VCV2WPERMREF_GLOBAL_FDR')
                    visdata{n}.PermPValRef_Global_FDR   = I.VCV2WPERMREF_GLOBAL_FDR{h}{n};
                end
                visdata{n}.CorrRef_CV2{h}               = I.VCV2WCORRREF{h}{n};
                visdata{n}.CompSelRat{h}                = I.PRES{h}{n};
                visdata{n}.CompKept{h}                  = I.KEEP{h}{n};
                visdata{n}.ModComp_L2nShare{h}          = I.ModComp_L2n{h}{n};
                visdata{n}.ModComp_L2nShare_Summary{h}  = I.ModComp_L2n_SUMMARY{h};
            else
                visdata{n}.CompRefSpace                 = I.VCV1REF;
                visdata{n}.PermPValRef_CV2              = I.VCV2WPERMREF;
                if isfield(I,'VCV2WPERMREF_GLOBAL_FDR')
                    visdata{n}.PermPValRef_Global_FDR   = I.VCV2WPERMREF_GLOBAL_FDR;
                end
                visdata{n}.CorrRef_CV2                  = I.VCV2WCORRREF;
                visdata{n}.CompSelRat                   = I.PRES;
                visdata{n}.CompKept                     = I.KEEP;
                visdata{n}.ModComp_L2nShare             = I.ModComp_L2n;
                visdata{n}.ModComp_L2nShare_Summary{h}  = I.ModComp_L2n_SUMMARY{h};
            end
            if inp.isEarly
                num = I.DxSUM{h};
                sumx2  = I.DxSQSUM{h};
                den = I.DxN{h};
            else
                num = I.DxSUM{h}{n};
                sumx2  = I.DxSQSUM{h}{n};
                den = I.DxN{h}{n};
            end
            mask = den > 0 & isfinite(den);
            % Compute Means
            Frac = nan(size(num), 'like', num);   % prefill with NaN
            Frac(mask) = num(mask) ./ den(mask);
            % Compute SEs
            SE = nan(size(num), 'like', num);   % prefill with NaN
            SD = nan(size(num), 'like', num);   % prefill with NaN
            VAR = nan(size(num), 'like', num);   % prefill with NaN
            VAR(mask) = sumx2(mask) ./ den(mask) - Frac(mask).^2;
            VAR(mask & VAR<0) = 0;
            SD(mask) = sqrt(VAR(mask));
            SE(mask) = SD(mask) ./ sqrt(den(mask));
            % Assign
            visdata{n}.FracDec_CV2_mean{h} = Frac;
            visdata{n}.FracDec_CV2_se{h} = SE;
            visdata{n}.FracDec_CV2_sd{h} = SD;
        end
        if isfield(I,'ModAgg_L2nShare')
            visdata{n}.ModAgg_L2nShare   = I.ModAgg_L2nShare;
            visdata{n}.ModAgg_L2nShare_Summary = I.ModAgg_L2nShare_SUMMARY{h};
        end
        if permfl || sigfl
            visdata{n}.PermModel                = I.VCV2MODELP;
            visdata{n}.PermModel_std            = I.VCV2MODELP_STD;
            visdata{n}.PermModel_CV2            = I.VCV2MPERM_CV2;
            visdata{n}.ObsModel_Crit_CV2        = I.VCV2MORIG_EVAL;
            visdata{n}.PermModel_Eval_Global    = I.VCV2MPERM_GLOBAL;
            visdata{n}.PermModel_Crit_Global    = I.VCV2MPERM_EVALFUNC_GLOBAL;
            visdata{n}.ObsModel_Eval_Global     = I.VCV2MORIG_EVALFUNC_GLOBAL;
            if inp.multiflag
                visdata{n}.PermModel_Eval_Global_Multi_Bin  = I.VCV2MPERM_GLOBAL_MULTI_ONEvsREST;
                visdata{n}.PermModel_Crit_Global_Multi_Bin  = I.VCV2PERM_GLOBAL_MULTI_ONEvsREST;
                visdata{n}.ObsModel_Eval_Global_Multi_Bin   = I.VCV2MORIG_GLOBAL_MULTI.BAC;
                visdata{n}.PermModel_Eval_Global_Multi      = I.VCV2MPERM_GLOBAL_MULTI;
                visdata{n}.PermModel_Crit_Global_Multi      = I.VCV2PERM_GLOBAL_MULTI;
                visdata{n}.ObsModel_Eval_Global_Multi       = I.VCV2MORIG_GLOBAL_MULTI.BAC_Mean;
            end
            if permfl
                visdata{n}.PermProb_CV2             = I.VCV2PERM_ZBASED(:,n);
                visdata{n}.PermProb_CV2_FDR         = I.VCV2PERM_FDR_ZBASED(:,n); 
                visdata{n}.PermZ_CV2                = I.VCV2ZSCORE(:,n);
            end
        end
        if ~isempty(inp.extraL)
            visdata{n}.ExtraL = I.EXTRA_L;
        end
        visdata{n}.CVRnorm = inp.CVRnorm;
        if isfield(I,'ReportFinal')
            visdata{n}.Report = I.ReportFinal;
        end
    end
end

end
% _________________________________________________________________________
function WriteCV2Data(inp, nM, FUSION, SAV, operm, ofold, I1)

if inp.writeCV2 ~= 1, return; end
compwisefls      = {true,false}; compwise = compwisefls{inp.DecompMode}; 

for h = 1:inp.nclass
    for n = 1:nM
        [~, datatype, brainmaski, ~, labeli, labelopi] = getD(FUSION.flag, inp, n);
        [~, ~, ext] = fileparts(brainmaski);

        if datatype == 1 || datatype == 2
            % CVR & sign-consistency (works for 2-D or 3-D inputs)
            CVR = nk_ComputeCVR(I1.VCV1{h,n}, I1.VCV1SEL{h,n});                    % [nFeat×1] or [nFeat×K]
            [~, SIGNCONST_FDR, ~, ~] = nk_SignBasedConsistencySignificance(I1.VCV1{h,n}); % [nFeat×1] or [nFeat×K]

            isComp = compwise && ndims(I1.VCV1{h,n}) == 3 && size(I1.VCV1{h,n},3) > 1;
            if isComp
                K = size(CVR, 2);
                for k = 1:K
                    cvr_k = CVR(:, k);
                    fdr_k = SIGNCONST_FDR(:, k);
                    thr_k = cvr_k .* (fdr_k >= -log10(0.05));

                    [~, oCVRfile]      = nk_GenerateNMFilePath(inp.rootdir, SAV.matname, sprintf('CVR_comp%02d', k), [], inp.varstr, inp.id, operm, ofold, [], [], ext);
                    [~, oFDRfile]      = nk_GenerateNMFilePath(inp.rootdir, SAV.matname, sprintf('SignConstFDR_comp%02d', k), [], inp.varstr, inp.id, operm, ofold, [], [], ext);
                    [~, oCVRthrfile]   = nk_GenerateNMFilePath(inp.rootdir, SAV.matname, sprintf('CVR-SignConstFDR-masked-05_comp%02d', k), [], inp.varstr, inp.id, operm, ofold, [], [], ext);

                    local_write_vol(datatype, ext, cvr_k,  brainmaski, labeli, labelopi, oCVRfile);
                    local_write_vol(datatype, ext, fdr_k,  brainmaski, labeli, labelopi, oFDRfile);
                    local_write_vol(datatype, ext, thr_k,  brainmaski, labeli, labelopi, oCVRthrfile);
                end
            else
                % aggregated / single-vector case
                cvr   = CVR(:, 1);
                fdr   = SIGNCONST_FDR(:, 1);
                cvrth = cvr .* (fdr >= -log10(0.05));

                [~, oCVRfile]    = nk_GenerateNMFilePath(inp.rootdir, SAV.matname, 'CVR', [], inp.varstr, inp.id, operm, ofold, [], [], ext);
                [~, oFDRfile]    = nk_GenerateNMFilePath(inp.rootdir, SAV.matname, 'SignConstFDR', [], inp.varstr, inp.id, operm, ofold, [], [], ext);
                [~, oCVRthrfile] = nk_GenerateNMFilePath(inp.rootdir, SAV.matname, 'CVR-SignConstFDR-masked-05', [], inp.varstr, inp.id, operm, ofold, [], [], ext);

                local_write_vol(datatype, ext, cvr,   brainmaski, labeli, labelopi, oCVRfile);
                local_write_vol(datatype, ext, fdr,   brainmaski, labeli, labelopi, oFDRfile);
                local_write_vol(datatype, ext, cvrth, brainmaski, labeli, labelopi, oCVRthrfile);
            end
        end
    end
end

end

% ============================ subfunction =================================
function local_write_vol(datatype, ext, vec, brainmaski, labeli, labelopi, outbase)
switch datatype
    case 1
        % volumetric NIfTI
        nk_WriteVol(vec, [outbase '.nii'], 2, brainmaski, [], labeli, labelopi);
    case 2
        % surface formats
        switch ext
            case {'.mgh','.mgz'}
                s = MRIread(brainmaski);
                s.vol = vec;
                MRIwrite(s, outbase);
            case '.gii'
                s = GIIread(brainmaski);
                save(gifti(struct('vertices',double(s.vertices), 'faces',double(s.faces), 'cdata',vec)), outbase);
        end
end
end
% _________________________________________________________________________
function I = ComputeObsPermPerf(inp, I, I1, CV, f, d, ll, ...
                                                nclass, ngroups, nperms, ...
                                                operm, ofold, MODEFL, RFE, compfun)
for h=1:nclass

    fprintf('\nCV2 [%g, %g]: Observed performance [ model #%g ]: %1.2f; P[CV2] = %1.3f', ...
        operm, ofold, h, I1.VCV1MORIG_EVALFUNC_CV2{h}, I.VCV2MPERM_CV2(h,ll) ); 
    switch MODEFL
        case 'classification'
            TsInd2 = CV.TestInd{f,d}(CV.classnew{f,d}{h}.ind);
        case 'regression'
            TsInd2 = CV.TestInd{f,d};
    end
    if ~RFE.CV2Class.EnsembleStrategy.AggregationLevel && size(I1.DS{h},2)>1
         EnsDat = nm_nanmedian(I1.DS{h},2);
    else
         EnsDat = I1.DS{h};
    end
    I.VCV2MORIG_S(TsInd2,h) = cellmat_mergecols(I.VCV2MORIG_S(TsInd2,h), num2cell(EnsDat,2));
    for perms = 1:nperms
        if ~RFE.CV2Class.EnsembleStrategy.AggregationLevel && size(I1.DS_perm{h}(:,:,perms),2)>1
             EnsDat = nm_nanmedian(I1.DS_perm{h}(:,:,perms),2);
        else
             EnsDat = I1.DS_perm{h}(:,:,perms);
        end
        I.VCV2MPERM_S(TsInd2,h,perms) = cellmat_mergecols(I.VCV2MPERM_S(TsInd2,h,perms), num2cell(EnsDat,2)); 
    end

end

% Perform multi-class permutation testing
if inp.multiflag
     if ~isfield(I1,'mDS'), fprintf('\n');
         error('You requested multi-class significance but the current VISDATAMAT contains only binary classifier data. Rerun visualization with multi-group optimization.'); 
     end
     fprintf('\nComputing CV2 multi-class model significance\n\tMulti-class perfomance: '); 
     mDTs = []; mTTs = []; Classes = []; mcolend = 0;
     TsIndM = CV.TestInd{f,d};
     for h=1:nclass
         for il=1:size(I1.mDS{h},2)
            % Multi-group CV2 array construction for observed
            % multi-class model.
            [mDTs, mTTs, ~, Classes, ~, mcolend] = ...
                nk_MultiAssemblePredictions( I1.mDS{h}(:,il), I1.mTS{h}(:,il), [], mDTs, mTTs, Classes, 1, h, mcolend );
         end
     end

     % Compute multi-group performance of observed model
     [ mCV2perf_obs, mCV2pred_obs ] = nk_MultiEnsPerf(mDTs, [], inp.label(TsIndM), Classes, ngroups);
     I.VCV2MORIG_S_MULTI(TsIndM,f) = mCV2pred_obs;
     
     % now assess observed model's significance
     mPx_perm = zeros(1,nperms);
     fprintf(' %1.2f | Permuting:\t', mCV2perf_obs);
     for perms = 1:nperms
         mDTs_perm = []; mTTs_perm = []; Classes_perm = []; mcolend_perm = 0;
         for h=1:nclass
             % Multi-group CV2 array construction for permuted
             % multi-class model
             for il=1:size(I1.mDS{h},2)
                [mDTs_perm, mTTs_perm, ~, Classes_perm, ~, mcolend_perm] = ...
                    nk_MultiAssemblePredictions( I1.mDS_perm{h}(:,il,perms), I1.mTS_perm{h}(:,il,perms), [], mDTs_perm, mTTs_perm, Classes_perm, 1, h, mcolend_perm );
             end
         end
         % Compute multi-group performance of permuted
         % model
         [ mCV2perf_perm, mCV2pred_perm ] = nk_MultiEnsPerf(mDTs_perm, [], inp.labels(TsIndM), Classes_perm, ngroups);
         I.VCV2MPERM_S_MULTI(TsIndM,f,perms) = mCV2pred_perm;
         % Compare against original model performance
         if feval(compfun, mCV2perf_perm, mCV2perf_obs)
            fprintf('.'); 
            mPx_perm(perms) = mPx_perm(perms) + 1;
         end
     end
     I.VCV2MPERM_MULTI(ll) = (sum(mPx_perm) + 1) / (nperms + 1);
     fprintf('P[CV2] = %1.3f', I.VCV2MPERM_MULTI(ll));
else
    if isfield(I1,'mDS'), fprintf('\nNot computing CV2 multi-class model significance'); end
end

end
% ______________________________________________________________________________
function Z = nm_apply_scalar_weight(Z, w)
% Multiply Z by scalar w. Z can be numeric or a cell array (e.g., per modality).
% For cells, multiplies each non-empty cell. Returns Z unchanged if empty.

    if isempty(Z) || isequal(w,1), return; end

    if iscell(Z)
        for i = 1:numel(Z)
            if ~isempty(Z{i}), Z{i} = Z{i} .* w; end
        end
    else
        % Numeric (vector or matrix)
        Z = Z .* w;
    end
end

function y = nm_weighted_vote_binary(TS, w)      % TS: N×M in {-1,+1}
% NaN-safe: ignores NaNs and renormalizes available weight mass per row
    w = max(w(:),0); s=sum(w); if s>0, w=w/s; end
    mask = ~isnan(TS); wr = bsxfun(@times, ones(size(TS,1),1), w');
    wr = wr .* mask;
    v  = nm_nansum(TS .* wr, 2);
    y  = sign(v);
    z  = (y==0); if any(z), y(z) = 1; end   % tie-break default (+1) or your rule
end

function y = nm_weighted_vote_multiclass(TS, w, classes) 
% TS: N×M with integer class ids in classes (1..K). w: M×1
    w = max(w(:),0); s=sum(w); if s>0, w=w/s; end
    N = size(TS,1); K = numel(classes);
    y = nan(N,1);
    for i=1:N
        tally = zeros(K,1);
        for m=1:numel(w)
            t = TS(i,m);
            if ~isnan(t)
                k = find(classes==t,1);
                if ~isempty(k), tally(k) = tally(k) + w(m); end
            end
        end
        [~,kmax] = max(tally);
        y(i) = classes(kmax);
    end
end

function [pvals_corr, pvals_comb] = correct_p_values_across_cv(pvals)
    
    pvals_comb = nm_nanmean(pvals, 2);
    [~,~,~, pvals_corr] = fdr_bh(pvals_comb, 0.05, 'pdep'); % correct

end
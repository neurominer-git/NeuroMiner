%=====================================================================================
% [IN, OUT] = FoldPerm(IN, OUT, strout, fRFE, fFull, RetrainImmediate, fKX, LoopParam)
%=====================================================================================
%
% DESCRIPTION:
%   FoldPerm is the main NeuroMiner training module that orchestrates the 
%   model training and hyperparameter optimization within the inner 
%   cross-validation cycle (CV1). Depending on the configuration, it can:
%     - Train models using the CV1 training data and evaluate on CV1 test data
%       (with or without wrapper-based feature selection).
%     - Bypass the CV1 split to re-train models using the full CV1 partition 
%       when hyperparameter optimization is not required.
%
%   It supports both univariate and multivariate (multi-modal) input data, as 
%   well as multi-class optimization.
%
% INPUTS:
%   IN              - Structure containing all parameters and data needed for
%                     the model optimization process.
%   OUT             - Structure that stores results from the model optimization,
%                     including performance measures, trained models, and feature
%                     selection results.
%   strout          - Descriptive string for logging the operational mode.
%   fRFE            - Flag indicating whether to perform wrapper-based feature
%                     selection (recursive feature elimination).
%   fFull           - Flag indicating whether to use the entire CV1 partition 
%                     (bypassing the training/test split).
%   RetrainImmediate- Flag indicating if models should be re-trained immediately
%                     after optimization.
%   fKX             - Flag or integer controlling the step size for subspace-
%                     based filtering (determines feature subspace granularity).
%   LoopParam       - (Optional) Structure containing custom loop vectors:
%                     PermVec (permutation indices), FoldVec (fold indices), and
%                     ClassVec (class indices). If not provided, default ranges are used.
%
% OUTPUTS:
%   IN, OUT         - Updated input and output structures with the trained models,
%                     performance metrics, and feature subspace information.
%
% DEPENDENCIES:
%   Global variables: VERBOSE, CV, MODEFL, RAND, MULTILABEL, MULTI, RFE, CVPOS, Ytrain.
%   External functions:
%       nk_ExtractFeatures, nk_MLOptimizer_WrapperMulti, nk_MLOptimizer_Wrapper,
%       nk_GetParam2, nk_GetTestPerf, BAC.
%
% (c) Nikolaos Koutsouleris, 03/2020
%==========================================================================

function [IN, OUT] = FoldPerm(IN, OUT, strout, fRFE, fFull, RetrainImmediate, fKX, LoopParam)

% Global variables required by this function
global VERBOSE CV MODEFL RAND MULTILABEL MULTI RFE CVPOS Ytrain

% Initialize temporary variables
RF = []; 
fMULTI = false;  % Flag for multi-class wrapper optimization
VI = [];

% Check if multi-class optimization is enabled (based on the MULTI flag and RFE settings)
if MULTI.flag == 1 && MULTI.train == 1 && ...
        isfield(RFE.Wrapper.GreedySearch, 'MultiClassOptimization') && ...
        RFE.Wrapper.GreedySearch.MultiClassOptimization
    fMULTI = true; 
end

% Determine the number of classes for looping based on decomposition method
if RAND.Decompose == 9
    mnclass = IN.ngroups;
else
    mnclass = IN.nclass;
end

%% Preallocate and Setup Output Structure Containers
if ~exist('OUT', 'var') || isempty(OUT)
    OUT.tr      = cell(IN.nperms, IN.nfolds, mnclass);   % Training performance metrics
    OUT.mdl     = cell(IN.nperms, IN.nfolds, IN.nclass);   % Trained model structures
    OUT.Trtargs = cell(IN.nperms, IN.nfolds, mnclass);     % Predicted training target labels
    OUT.Trdecs  = cell(IN.nperms, IN.nfolds, mnclass);     % Decision values/probabilities for training
    OUT.kxVec   = cell(IN.nperms, IN.nfolds, IN.nclass);   % Vector for subspace stepping
    OUT.ts      = cell(IN.nperms, IN.nfolds, mnclass);     % Test performance metrics
    OUT.rf      = cell(IN.nperms, IN.nfolds, mnclass);     % Wrapper-based feature elimination results
    OUT.w2      = cell(IN.nperms, IN.nfolds, mnclass);     % |w| (weight magnitude) for linear SVMs
    OUT.Md      = cell(IN.nperms, IN.nfolds, mnclass);     % Distance to hyperplane (SVM)
    OUT.Mm      = cell(IN.nperms, IN.nfolds, mnclass);     % Normalized margin (SVM)
    OUT.CVtargs = cell(IN.nperms, IN.nfolds, mnclass);     % Predicted test target labels
    OUT.CVdecs  = cell(IN.nperms, IN.nfolds, mnclass);     % Decision values/probabilities for test data
    OUT.featnum = cell(IN.nperms, IN.nfolds, IN.nclass, IN.nvar); % Number of features selected per subspace
end

% Number of binary comparisons in IN.F (for multi-group classifiers)
nc = size(IN.F,3);

% Use provided loop parameters if available; otherwise, create default indices
if exist('LoopParam', 'var') && ~isempty(LoopParam)
    PermVec  = LoopParam.PermVec;
    FoldVec  = LoopParam.FoldVec;
    ClassVec = LoopParam.ClassVec;
else
    PermVec  = 1:IN.nperms;
    FoldVec  = 1:IN.nfolds; 
    ClassVec = 1:IN.nclass;
end

% Determine the number of iterations for each loop
PermNum  = numel(PermVec);
FoldNum  = numel(FoldVec);
ClassNum = numel(ClassVec);
kx = 1; % initial step for feature subspace search
CVPOS.fFull = fFull;  % update global CVPOS flag for full data usage

%% Main Loop: Iterate over Permutations and Folds (CV1 cross-validation)
for ii = 1:PermNum  % Loop over CV1 permutations
    for jj = 1:FoldNum  % Loop over CV1 folds
        
        % Initialize indices and global partition variables for current permutation & fold
        i           = PermVec(ii); 
        j           = FoldVec(jj);
        CVPOS.CV1p = i;
        CVPOS.CV1f = j;
        
        % Preallocate cell arrays for current fold and permutation
        modelTrL    = cell(1, ClassNum);  % Training labels for each dichotomizer
        Ymodel      = cell(1, ClassNum);  % Processed model training data
        Ytrain      = cell(1, ClassNum);  % Training data for learning
        Ytest       = cell(1, ClassNum);  % Test data for evaluation
        tTrL        = cell(1, ClassNum);  % Temporary training label container
        tCVL        = cell(1, ClassNum);  % Temporary CV label container
        kFea        = zeros(1, ClassNum); % Number of feature subspace steps per class
        lFea        = zeros(1, ClassNum); % Maximum number of features per class
        Fx          = cell(1, ClassNum);  % Cell array to store feature subspace masks
        cvts_fl     = false(1, ClassNum); % Flag to check if test (CV) structure needs update
        k           = zeros(1, ClassNum); % Stores current subspace size for each class
        Fk          = cell(ClassNum, IN.nvar); % Container for feature matrices
        
        % PART I: Prepare Training and Test Data for Each Dichotomizer/Class
        for ccurclass = 1:ClassNum 
            curclass = ClassVec(ccurclass);
            
            % Initialize temporary containers for feature sizes and models
            tFea = zeros(curclass, IN.nvar); 
            tCV = cell(1, IN.nvar); 
            tTr = cell(1, IN.nvar);
            modelTr = cell(1, IN.nvar);
            
            % Get CV indices for training and test splits for current class
            CVInd = IN.Y.CVInd{i,j}{curclass};
            TrInd = IN.Y.TrInd{i,j}{curclass};
            
            % Loop over each variate (modality) to extract feature data and labels
            for v = 1:IN.nvar 
                % Determine the size of the feature subspace (different for binary vs. multi-group)
                if nc > 1  % Multi-group: IN.F indexed by class and variate
                    try 
                        tFea(curclass, v) = size(IN.F{i,j,curclass,v}, 2); 
                    catch
                        tFea(curclass, v) = size(IN.F{i,j,curclass,v}, 1); 
                    end
                    Fk{curclass, v} = IN.F{i,j,curclass,v}; 
                else  % Binary classifier (or multi-group classifier not implemented)
                    try 
                        tFea(curclass, v) = size(IN.F{i,j,v}, 2); 
                    catch
                        tFea(curclass, v) = size(IN.F{i,j,v}, 1); 
                    end
                    Fk{curclass, v} = IN.F{i,j,v}; 
                end
                
                % Extract training and CV (validation/test) data
                if ~iscell(IN.Y.Tr{i,j,1})
                    % Univariate case: directly index the training matrix
                    modelTr{v} = IN.Y.Tr{i,j,v}(TrInd, :);
                    tTr{v} = IN.Y.Tr{i,j,v};
                    if fFull
                        modelTr{v} = [modelTr{v}; IN.Y.CV{i,j,v}(CVInd, :)];
                    end
                    tCV{v} = IN.Y.CV{i,j,v};
                elseif numel(IN.Y.Tr{i,j,v}) == nc
                    % Multi-group: training data stored per class in a cell array
                    modelTr{v} = IN.Y.Tr{i,j,v}{curclass}(TrInd, :);
                    tTr{v} = IN.Y.Tr{i,j,v}{curclass};
                    if fFull
                        modelTr{v} = [modelTr{v}; IN.Y.CV{i,j,v}{curclass}(CVInd, :)];
                    end
                    tCV{v} = IN.Y.CV{i,j,v}{curclass};
                else
                    % Fallback: use first cell element if data structure is non-standard
                    modelTr{v} = IN.Y.Tr{i,j,v}{1}(TrInd, :);
                    tTr{v} = IN.Y.Tr{i,j,v}{1};
                    if fFull
                        modelTr{v} = [modelTr{v}; IN.Y.CV{i,j,v}{1}(CVInd, :)];
                    end
                    tCV{v} = IN.Y.CV{i,j,v}{1};
                end
            end
            
            % Determine sample sizes for training and CV data (assume first variate represents size)
            kSubjTr = size(tTr{1}, 1); 
            kSubjCV = size(tCV{1}, 1);
            
            % Set the target labels for training and test
            modelTrL{curclass} = IN.Y.TrL{i,j}{curclass}(:, MULTILABEL.curdim);
            tTrL{curclass}     = zeros(kSubjTr, 1); 
            tTrL{curclass}(TrInd) = IN.Y.TrL{i,j}{curclass}(:, MULTILABEL.curdim);
            tCVL{curclass}     = zeros(kSubjCV, 1); 
            tCVL{curclass}(CVInd) = IN.Y.CVL{i,j}{curclass}(:, MULTILABEL.curdim);
            if fFull
                modelTrL{curclass} = [modelTrL{curclass}; IN.Y.CVL{i,j}{curclass}(:, MULTILABEL.curdim)]; 
            end
            
            % Determine the maximum number of features (across variates) for the current class
            lFea(curclass) = max(tFea(curclass, :)); 
            if fKX
                kx = ceil((lFea(curclass) / 100) * fKX);
            end
            
            % Create the vector for feature subspace stepping
            OUT.kxVec{i,j,curclass} = kx:kx:lFea(curclass);
            if isempty(OUT.kxVec{i,j,curclass})
                OUT.kxVec{i,j,curclass} = 1;
            else
                if OUT.kxVec{i,j,curclass}(end) < lFea(curclass)
                    OUT.kxVec{i,j,curclass} = [OUT.kxVec{i,j,curclass} lFea(curclass)]; 
                end 
            end
            kFea(curclass) = length(OUT.kxVec{i,j,curclass});
            cvts_fl(curclass) = kFea(curclass) ~= size(OUT.ts{i,j,curclass}, 1);
            
            % Initialize OUT structure arrays for current class and fold
            OUT.tr{i,j,curclass}      = zeros(kFea(curclass), 1);
            if isempty(OUT.mdl{i,j,curclass})
                OUT.mdl{i,j,curclass} = cell(kFea(curclass), 1);
            end
            OUT.Trtargs{i,j,curclass} = zeros(kSubjTr, kFea(curclass));
            OUT.Trdecs{i,j,curclass}  = zeros(kSubjTr, kFea(curclass));
            
            if ~fFull || RetrainImmediate || any(cvts_fl)
                OUT.ts{i,j,curclass}      = zeros(kFea(curclass), 1);
                OUT.CVtargs{i,j,curclass} = zeros(kSubjCV, kFea(curclass));
                OUT.CVdecs{i,j,curclass}  = zeros(kSubjCV, kFea(curclass));
                OUT.rf{i,j,curclass}      = cell(kFea(curclass), 1);
                OUT.w2{i,j,curclass}      = zeros(kFea(curclass), 1);
                OUT.Md{i,j,curclass}      = zeros(kFea(curclass), 1);
                OUT.Mm{i,j,curclass}      = zeros(kFea(curclass), 1);
            end
            
            % Loop over each feature subspace (defined by the stepping vector)
            for kT = 1:kFea(curclass)
                k(curclass) = OUT.kxVec{i,j,curclass}(kT);
                % Extract feature subsets for training, full training (for model fitting), 
                % and test data using an external function.
                [Ymodel{curclass}{k(curclass)}, Fx{curclass}{k(curclass)}] = nk_ExtractFeatures(modelTr, Fk(curclass,:), [], k(curclass));
                Ytrain{curclass}{k(curclass)} = nk_ExtractFeatures(tTr, Fk(curclass,:), [], k(curclass));
                Ytest{curclass}{k(curclass)}  = nk_ExtractFeatures(tCV, Fk(curclass,:), [], k(curclass));
            end
        end  % End of dichotomizer loop
        
        %% PART II: Train Models for Each Dichotomizer
        % Two branches: one for multi-class wrapper-based optimization and one
        % for separate (binary) optimization.
        if fMULTI && fRFE
            % Multi-class optimization branch
            tMTrL = IN.Y.mTrL{i,j};
            tMCVL = IN.Y.mCVL{i,j};
            indkX = 1;

            % Preallocate feature output structure based on data dimensionality
            if IN.nvar < 2  % Univariate case
                OUT.featout{i,j,curclass} = zeros(size(IN.F{i,j,curclass}, 1), kFea(curclass)); 
            else  % Multivariate case
                OUT.featout = cell(IN.nvar, 1);
                for v = 1:IN.nvar 
                    OUT.featout{v}{i,j,curclass} = zeros(size(IN.F{i,j,curclass,v}, 1), tFea(curclass,v)); 
                end
            end

            % Loop over feature subspaces (shared across classes in multi-class setting)
            for kT = 1:kFea(curclass)
                % Prepare cell arrays to store feature data for each class
                tYmodel = cell(1, ClassNum);
                tYtrain = cell(1, ClassNum);
                tYtest  = cell(1, ClassNum);
                
                % Populate feature data for each class
                for ccurclass = 1:ClassNum 
                    curclass = ClassVec(ccurclass);
                    tYmodel{curclass} = Ymodel{curclass}{k(curclass)};
                    tYtrain{curclass} = Ytrain{curclass}{k(curclass)};
                    tYtest{curclass}  = Ytest{curclass}{k(curclass)};
                end
                
                % Call the multi-class wrapper-based optimizer (external function)
                [RF, model] = nk_MLOptimizer_WrapperMulti(tYmodel, tYtrain, modelTrL, tTrL, tMTrL, tYtest, tCVL, tMCVL, IN.ngroups, IN.Ps, []);
                
                % For each dichotomizer, update feature masks and compute performance
                for ccurclass = 1:ClassNum 
                    curclass = ClassVec(ccurclass);
                    % Update feature data using the wrapper output
                    [OUT, IN, Ytrain, Ytest, Ymodel] = assignRF2data(OUT, RF, IN, Ytrain, Ytest, Ymodel, Fx, i, j, curclass, k, indkX, v);
                    % Compute performance metrics (training and test)
                    OUT = getperf2out(OUT, model, Ymodel, Ytrain, tTrL, Ytest, tCVL, fFull, RetrainImmediate, cvts_fl, i, j, curclass, indkX, k);
                    % Save feature count if no valid wrapper mask was detected
                    if isempty(RF) || ~RF.found
                        for v = 1:IN.nvar 
                            OUT.featnum{i,j,curclass,v}(indkX) = sum(Fk{curclass, v}(:, indkX) ~= 0);
                        end
                    end
                    % Final assignment of training and test results into OUT
                    OUT = assign2out(OUT, RetrainImmediate, fFull, cvts_fl, i, j, curclass);
                end
                indkX = indkX + 1;
            end
            
        else
            % Separate (binary) optimization branch
            for ccurclass = 1:ClassNum 
                curclass = ClassVec(ccurclass);
                indkX = 1;
                % Loop over each feature subspace for the current dichotomizer
                for kT = 1:kFea(curclass)
                    k(curclass) = OUT.kxVec{i,j,curclass}(kT);
                    % Compute the number of nonzero features for logging
                    % Robust feature count for current subspace across all variates
                    nfeats = 0;
                    for v = 1:IN.nvar
                        Fv = Fk{curclass, v};
                        if isempty(Fv), continue; end
                        if size(Fv,2) >= k(curclass)
                            nfeats = nfeats + nnz(Fv(:, k(curclass)));
                        else
                            % single-column (or fewer columns than k): count what's there
                            nfeats = nfeats + nnz(Fv);
                        end
                    end
                    if nfeats == 0
                        % fallback: the target subspace size (what you *asked* for)
                        nfeats = k(curclass);
                    end
                    
                    % Log progress if verbosity is enabled
                    if VERBOSE 
                        switch MODEFL
                            case 'classification'
                                if RAND.Decompose ~= 9
                                    fprintf('\n%s => CV1 [%g, %g, %s, Subspace %g/%g (%g feats)]:', ...
                                        strout, i, j, CV.class{1,1}{curclass}.groupdesc, k(curclass), lFea(curclass), nfeats);
                                else
                                    fprintf('\n%s => CV1 [%g, %g, Multi-Group, Subspace %g/%g (%g feats)]:', ...
                                        strout, i, j, k(curclass), lFea(curclass), nfeats);
                                end
                            case 'regression'
                                fprintf('\n%s => CV1 [%g, %g, Regression, Subspace %g/%g (%g feats)]:', ...
                                        strout, i, j, k(curclass), lFea(curclass), nfeats);
                        end
                    end
                    
                    % Retrieve feature importance information if available
                    if isfield(IN.Y, 'VI')
                        if iscell(IN.Y.VI{i,j})
                            VI = IN.Y.VI{i,j}{curclass}; 
                        else
                            VI = IN.Y.VI{i,j}; 
                        end
                    end
                    
                    %% Train Model(s) for current feature subspace
                    if ~fRFE
                        % Train without wrapper-based feature selection
                        [~, model] = nk_GetParam2(Ymodel{curclass}{k(curclass)}, modelTrL{curclass}, IN.Ps{curclass}, 1, VI);
                    else
                        % Use wrapper-based optimization (NOTE: currently supports only univariate data)
                        if IN.nvar < 2
                            OUT.featout{i,j,curclass} = zeros(size(IN.F{i,j,curclass}, 1), kFea(curclass)); 
                        else
                            OUT.featout = cell(IN.nvar, 1);
                            for v = 1:IN.nvar 
                                OUT.featout{v}{i,j,curclass} = zeros(size(IN.F{i,j,curclass,v}, 1), tFea(curclass,v)); 
                            end
                        end
                        [RF, model] = nk_MLOptimizer_Wrapper(Ymodel{curclass}{k(curclass)}, modelTrL{curclass}, ...
                                                              Ytest{curclass}{k(curclass)}, tCVL{curclass}, IN.Ps{curclass}, []);
                        % Update feature data according to the wrapper output
                        [OUT, IN, Ytrain, Ytest, Ymodel] = assignRF2data(OUT, RF, IN, Ytrain, Ytest, Ymodel, Fx, i, j, curclass, k, indkX, v);
                    end
                    
                    % Compute performance metrics for training and (if needed) test data
                    OUT = getperf2out(OUT, model, Ymodel, Ytrain, tTrL, Ytest, tCVL, fFull, RetrainImmediate, cvts_fl, i, j, curclass, indkX, k);
                    
                    % Record the number of features if no valid wrapper mask is present
                    if isempty(RF) || ~RF.found
                        for v = 1:IN.nvar 
                            OUT.featnum{i,j,curclass,v}(indkX) = sum(Fk{curclass, v}(:, indkX) ~= 0);
                        end
                    end
                    
                    % Final assignment of results into the OUT structure
                    OUT = assign2out(OUT, RetrainImmediate, fFull, cvts_fl, i, j, curclass);
                    
                    indkX = indkX + 1;
                end
            end
        end
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% SUBFUNCTION: assignRF2data
%  Updates feature subspace data according to the output of the wrapper-based
%  optimization. If a valid feature index (RF.FeatureIndex) is found, the 
%  function updates the feature matrices for training and test data.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [OUT, IN, Ytrain, Ytest, Ymodel] = assignRF2data(OUT, RF, IN, ...
                                                    Ytrain, Ytest, Ymodel, ...
                                                    Fx, i, j, curclass, ...
                                                    k, indkX, v)
    if RF.found
        % Identify indices of selected features from the current subspace mask
        indFx   = find(Fx{curclass}{k(curclass)}); 
        if iscell(RF.FeatureIndex)
            FI = RF.FeatureIndex{curclass};
            if isempty(FI)
                error('Wrapper of model #%g did not return any features! Relax your wrapper settings', curclass);
            end
        else
            FI = RF.FeatureIndex;
            if isempty(FI)
                error('Wrapper did not return any features! Relax your wrapper settings');
            end
        end
        indFx = indFx(FI);
        indFx0 = zeros(size(Fx{curclass}{k(curclass)}));  
        col = min(k(curclass), size(IN.F{i,j,curclass,v}, 2));
        indFx0(indFx) = IN.F{i,j,curclass,v}(indFx, col);
        
        % Update feature subspaces for training, test, and model data
        Ytrain{curclass}{k(curclass)} = Ytrain{curclass}{k(curclass)}(:, FI);
        Ytest{curclass}{k(curclass)}  = Ytest{curclass}{k(curclass)}(:, FI);
        Ymodel{curclass}{k(curclass)} = Ymodel{curclass}{k(curclass)}(:, FI);
        IN.F{i,j,curclass,v}(:, k(curclass)) = indFx0;
        col = min(k(curclass), size(Fk{curclass,v},2));
        OUT.featout{i,j,curclass,v}(:, indkX) = indFx0;
        OUT.featnum{i,j,curclass,v}(indkX) = nnz(Fk{curclass, v}(:, col));
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% SUBFUNCTION: getperf2out
%  Computes performance metrics on the training and test sets by applying the
%  trained model. The performance is calculated using an external function
%  (nk_GetTestPerf) and the results are stored in the OUT structure.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function OUT = getperf2out(OUT, model, Ymodel, Ytrain, tTrL, Ytest, tCVL, ...
                            fFull, RetrainImmediate, cvts_fl, ...
                            i, j, curclass, indkX, k)

    % Select the correct model if the model is stored in a cell array
    if iscell(model)
        iModel = model{curclass};
    else
        iModel = model;
    end

    %% Evaluate performance based on the decomposition method used
    switch RAND.Decompose
        case 9
            % Multi-group (one-versus-all) evaluation
            nclass = numel(unique(tTrL{curclass}));
            tr_label = tTrL{curclass}; 
            cv_label = tCVL{curclass};
            [~, tr_targs, tr_decs, iModel] = nk_GetTestPerf(Ytrain{curclass}{k(curclass)}, tr_label, [], iModel, Ymodel{curclass}{k(curclass)}, [], nclass);
            if ~fFull || RetrainImmediate || cvts_fl(curclass)
                [~, cv_targs, cv_decs, iModel] = nk_GetTestPerf(Ytest{curclass}{k(curclass)}, cv_label, [], iModel, Ymodel{curclass}{k(curclass)}, [], nclass);            
            end

            % For each binary classifier (one-vs-all) compute performance using BAC metric
            for m_curclass = 1:nclass
                Ltr_curclass = zeros(size(tr_label));
                Ltr_curclass(tr_label == m_curclass) = 1; 
                Ltr_curclass(Ltr_curclass == 0) = -1;
                tr = BAC(Ltr_curclass, tr_decs(:, indkX, m_curclass));  
                if isnan(tr)
                    warning('Binary comparison %g: Non-finite performance measures found in CV1 training data', m_curclass);
                end
                if VERBOSE
                    fprintf('\tTr(class %g) = %1.2f', m_curclass, tr);
                end
                OUT.tr{i,j,m_curclass}(indkX) = tr;
                OUT.Trtargs{i,j,m_curclass}(:, indkX) = tr_targs(:, indkX, m_curclass);
                OUT.Trdecs{i,j,m_curclass}(:, indkX) = tr_decs(:, indkX, m_curclass);
                if ~fFull || RetrainImmediate || cvts_fl(curclass)
                    Lcv_curclass = zeros(size(cv_label));
                    Lcv_curclass(cv_label == m_curclass) = 1; 
                    Lcv_curclass(Lcv_curclass == 0) = -1;
                    ts = BAC(Lcv_curclass, cv_decs(:, indkX, m_curclass));  
                    if isnan(ts)
                        warning('Binary comparison %g: Non-finite performance measures found in CV1 test data', m_curclass);
                    end
                    if VERBOSE
                        fprintf('\tCV(class %g) = %1.2f', m_curclass, ts);
                    end
                    OUT.ts{i,j,m_curclass}(indkX) = ts;
                    OUT.CVtargs{i,j,m_curclass}(:, indkX) = cv_targs(:, indkX, m_curclass);
                    OUT.CVdecs{i,j,m_curclass}(:, indkX) = cv_decs(:, indkX, m_curclass);
                end
            end

        otherwise
            % Standard binary or regression evaluation
            [OUT.tr{i,j,curclass}(indkX), OUT.Trtargs{i,j,curclass}(:, indkX), OUT.Trdecs{i,j,curclass}(:, indkX), iModel] = ...
                nk_GetTestPerf(Ytrain{curclass}{k(curclass)}, tTrL{curclass}, [], iModel, Ymodel{curclass}{k(curclass)});
            if isnan(OUT.tr{i,j,curclass}(indkX))
                warning('Non-finite performance measures found in CV1 training data')
            end
            if VERBOSE
                fprintf('\tTr = %1.2f', OUT.tr{i,j,curclass}(indkX));
            end
            if ~fFull || RetrainImmediate || cvts_fl(curclass)
                [OUT.ts{i,j,curclass}(indkX), OUT.CVtargs{i,j,curclass}(:, indkX), OUT.CVdecs{i,j,curclass}(:, indkX), iModel] = ...
                    nk_GetTestPerf(Ytest{curclass}{k(curclass)}, tCVL{curclass}, [], iModel, Ymodel{curclass}{k(curclass)});
                if isnan(OUT.ts{i,j,curclass}(indkX))
                    warning('Non-finite performance measures found in CV1 test data')
                end
                if VERBOSE
                    fprintf(', CV = %1.2f', OUT.ts{i,j,curclass}(indkX));
                end
            end
    end

    % Save the trained model into the output structure
    OUT.mdl{i,j,curclass}{indkX} = iModel;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% SUBFUNCTION: assign2out
%  Converts the output arrays to single precision to save disk space and
%  conditionally assigns decision scores for the CV1 data partition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function OUT = assign2out(OUT, RetrainImmediate, fFull, cvts_fl, i, j, curclass)
    % Convert training target and decision values to single precision
    OUT.Trtargs{i,j,curclass} = single(OUT.Trtargs{i,j,curclass}); 
    OUT.Trdecs{i,j,curclass}  = single(OUT.Trdecs{i,j,curclass});
    OUT.tr{i,j,curclass}      = single(OUT.tr{i,j,curclass}); 

    % Assign CV1 decision scores only if retraining is required or the full 
    % training/test split is bypassed
    if ~fFull || RetrainImmediate || cvts_fl(curclass)
        OUT.CVtargs{i,j,curclass} = single(OUT.CVtargs{i,j,curclass}); 
        OUT.CVdecs{i,j,curclass}  = single(OUT.CVdecs{i,j,curclass});
        OUT.ts{i,j,curclass}      = single(OUT.ts{i,j,curclass}); 
    end
end

end  

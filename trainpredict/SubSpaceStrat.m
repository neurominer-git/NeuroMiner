%==========================================================================
%FORMAT [ IN , OUT ] = SubSpaceStrat(IN, OUT, Param.EnsembleStrategy, strout)
%==========================================================================
%Performs subspace optimization using either probabilistic feature      
%extraction or ensemble-based optimization                             
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%(c) Nikolaos Koutsouleris, 04/2015

function [ IN , OUT ] = SubSpaceStrat(IN, OUT, Param, OptMode, strout)
                  
global CV MULTI MODEFL W2AVAIL MULTILABEL VERBOSE

%%%% INITIALIZE %%%%

% Prepare cell containers for ensemble learning
OUT.TrHDperf    = zeros( IN.nperms, IN.nfolds, IN.nclass );
OUT.TrHTperf    = zeros( IN.nperms, IN.nfolds, IN.nclass );
OUT.CVHDperf    = zeros( IN.nperms, IN.nfolds, IN.nclass );
OUT.CVHTperf    = zeros( IN.nperms, IN.nfolds, IN.nclass );
OUT.TrDiv       = zeros( IN.nperms, IN.nfolds, IN.nclass );
OUT.CVDiv       = zeros( IN.nperms, IN.nfolds, IN.nclass );
OUT.TrHD        = cell( IN.nperms, IN.nfolds, IN.nclass );
OUT.TrHT        = cell( IN.nperms, IN.nfolds, IN.nclass );
OUT.CVHD        = cell( IN.nperms, IN.nfolds, IN.nclass );
OUT.CVHT        = cell( IN.nperms, IN.nfolds, IN.nclass );

nc = size(OUT.F,3);
ns = size(IN.F,3);
EnsType = 0;
Metric = 2;
DivFunc = 'nk_Entropy';
ngroups = IN.ngroups;
if isfield(Param,'EnsembleStrategy') && Param.SubSpaceFlag 
    if ~isempty(Param.EnsembleStrategy) && isfield(Param.EnsembleStrategy,'type')
        EnsType = Param.EnsembleStrategy.type;
        Metric = Param.EnsembleStrategy.Metric;
        DivFunc = Param.EnsembleStrategy.DivFunc;
    end
end

if MULTI.flag
    % If multi-group training option has been chosen prepare multi-group
    % prediction and peformance copntainers
    OUT.mTrPred     = cell( IN.nperms, IN.nfolds );
    OUT.mCVPred     = cell( IN.nperms, IN.nfolds );
    OUT.mTrPerf     = zeros( IN.nperms, IN.nfolds );
    OUT.mCVPerf     = zeros( IN.nperms, IN.nfolds );
    OUT.mTrDiv      = zeros( IN.nperms, IN.nfolds );
    OUT.mCVDiv      = zeros( IN.nperms, IN.nfolds );
    tF        = cell( IN.nperms, IN.nfolds, IN.nclass );
    tWeights  = cell( IN.nperms, IN.nfolds, IN.nclass );
    tSubSpaces  = cell( IN.nperms, IN.nfolds, ns );
   
else
    tF          = cell( IN.nperms, IN.nfolds, IN.nclass );
    tWeights    = cell( IN.nperms, IN.nfolds, IN.nclass );
    tSubSpaces  = cell( IN.nperms, IN.nfolds, IN.nclass );
end

tModels         = cell( IN.nperms, IN.nfolds, IN.nclass );

if W2AVAIL
    tW2         = cell( IN.nperms, IN.nfolds, IN.nclass );
    tMd         = cell( IN.nperms, IN.nfolds, IN.nclass );
    tMm         = cell( IN.nperms, IN.nfolds, IN.nclass );
end

%%%% APPLY SUBSPACE STRATEGY %%%%

for i=1:IN.nperms % loop through CV1 permutations
    
    for j=1:IN.nfolds  % loop through CV1 folds
              
        mTr = []; mCV = []; mC = []; tkIndCat = [];
        kIndN = cell(IN.nclass,1); TrL = kIndN; CVL = kIndN;

        switch EnsType

            case 9 

                %% PROBABILISTIC FEATURE SPACE CONSTRUCTION

                for curclass=1:IN.nclass

                    %% Get feature subspace mask and feature weighting:
                    if nc > 1 
                        % Every dichotomizer has its own feature subspace mask
                        kInd = OUT.F{i,j,curclass}; W = OUT.Weights{i,j,curclass};
                    else
                        % All dichotomizers share one feature subspace mask
                        % This mode is used for multi-group optimization
                        kInd = OUT.F{i,j}; W = OUT.Weights{i,j};
                        ndim = size(OUT.Trdecs{i,j,curclass},2);
                         % number of base learners is not equal to the number of features in feature mask
                        if numel(kInd) > ndim, kInd = true(ndim,1); end 
                    end

                    % => only one classifier/predictor will be trained
                    if nc == 1 
                        OUT.F{i,j}       = 1;
                        OUT.Weights{i,j} = 1;
                        if ns > 1
                            IN.F{i,j,curclass} = ProbabilisticFea( IN.F{i,j,curclass}(:,OUT.kxVec{i,j,curclass}(kInd)), Param.EnsembleStrategy );
                        else
                            IN.F{i,j} = ProbabilisticFea( IN.F{i,j}(:,OUT.kxVec{i,j,curclass}(kInd)), Param.EnsembleStrategy );
                        end
                    else
                        OUT.F{i,j,curclass} = 1;
                        OUT.Weights{i,j,curclass} = 1;
                        IN.F{i,j,curclass} = ProbabilisticFea( IN.F{i,j,curclass}(:,OUT.kxVec{i,j,curclass}(kInd)), Param.EnsembleStrategy );
                    end    
                    % Retrain using new feature subspace mask
                    LoopParam.PermVec = i; LoopParam.FoldVec = j; LoopParam.ClassVec = curclass;
                    [IN, OUT] = FoldPerm(IN, OUT, 'Retrain for PFC', OptMode, 0, 0, Param.SubSpaceStepping, LoopParam); 

                    OUT.TrHDperf(i,j,curclass) = mean(OUT.tr{i,j,curclass});
                    OUT.TrHTperf(i,j,curclass) = mean(OUT.tr{i,j,curclass});       
                    OUT.CVHDperf(i,j,curclass) = mean(OUT.ts{i,j,curclass});
                    OUT.CVHTperf(i,j,curclass) = mean(OUT.ts{i,j,curclass}); 

                end

                %% Extract decision values / probabilities using feature subspace mask
                OUT.TrHD(i,j,:) = OUT.Trdecs(i,j,:); 
                OUT.TrHT(i,j,:) = OUT.Trtargs(i,j,:);
                OUT.CVHD(i,j,:) = OUT.CVdecs(i,j,:); 
                OUT.CVHT(i,j,:) = OUT.CVtargs(i,j,:);

                if MULTI.flag
                    OUT = MultiDichoFoldPerm(IN, OUT, [], LoopParam);
                    OUT.mTrPerf(i,j) = OUT.mtr{i,j};
                    OUT.mCVPerf(i,j) = OUT.mts{i,j};
                end
                
                %% BOOSTING (weight optimization; no retraining; per-dichotomizer)
                case 10  

                    % Controller options (override via Param.Boosting.*)
                    B = struct('mode','ridge', ...     % 'ridge' | 'logloss' | 'expgrad'
                               'lambda',1e-3, ...
                               'alpha',0.0, ...
                               'useLogits',false, ...
                               'wThreshold',0, ...
                               'clip',1e-7);
                    if isfield(Param.EnsembleStrategy,'Boosting')
                        fn = fieldnames(Param.EnsembleStrategy.Boosting);
                        for ff = 1:numel(fn), B.(fn{ff}) = Param.EnsembleStrategy.Boosting.(fn{ff}); end
                    end
                
                    fixmask = @(ndim,F) (isempty(F) || numel(F)~=ndim) .* true(ndim,1) + ...
                                        (numel(F)==ndim) .* logical(F(:));
                
                    for curclass = 1:IN.nclass
                        
                         %% Get pointers and labels
                        TrInd                   = IN.Y.TrInd{i,j}{curclass};
                        CVInd                   = IN.Y.CVInd{i,j}{curclass};
    
                        %% Construct dichotomization labels for CV1 training and test data:
                        CVL{curclass}           = zeros(size(OUT.CVtargs{i,j,curclass},1),1); 
                        CVL{curclass}(CVInd)    = IN.Y.CVL{i,j}{curclass}(:,MULTILABEL.curdim);
                        TrL{curclass}           = zeros(size(OUT.Trtargs{i,j,curclass},1),1); 
                        TrL{curclass}(TrInd)    = IN.Y.TrL{i,j}{curclass}(:,MULTILABEL.curdim);

                        % --- mask and dimensions
                        if nc > 1
                            kInd = OUT.F{i,j,curclass};
                        else
                            kInd = OUT.F{i,j};
                            ndim = size(OUT.Trdecs{i,j,curclass},2);
                            if numel(kInd) > ndim, kInd = kInd(1:ndim); end
                        end
                        ndim  = size(OUT.Trdecs{i,j,curclass},2);
                        kInd  = fixmask(ndim, kInd);
                        cols  = find(kInd);
                
                        % --- base predictions (decision vals / probs)
                        switch Metric
                            case 2
                                Htr = OUT.TrHD{i,j,curclass}; Hcv = OUT.CVHD{i,j,curclass};
                                if isempty(Htr) || isempty(Hcv)
                                    Htr = OUT.Trdecs{i,j,curclass};
                                    Hcv = OUT.CVdecs{i,j,curclass};
                                end
                            otherwise % Metric==1 (rare)
                                Htr = OUT.TrHT{i,j,curclass}; Hcv = OUT.CVHT{i,j,curclass};
                                if isempty(Htr) || isempty(Hcv)
                                    Htr = OUT.Trtargs{i,j,curclass};
                                    Hcv = OUT.CVtargs{i,j,curclass};
                                end
                        end
                        Htr = Htr(:, cols);  % N x m
                        Hcv = Hcv(:, cols);  % N x m
                
                        % --- labels (already constructed earlier in SubSpaceStrat)
                        Ltr_full = TrL{curclass};
                        Lcv_full = CVL{curclass};
                        
                        % --- decide when to mask rows:
                        % Only mask rows in one-vs-rest classification where 0 = "not relevant".
                        isClassification = strcmpi(MODEFL,'classification');
                        isDichotomizer   = (IN.nclass > 1);   % your multi-dicho setup
                        if isClassification && isDichotomizer
                            maskTr = (Ltr_full ~= 0);
                            maskCv = (Lcv_full ~= 0);
                        else
                            % regression or single-task classification: keep all rows
                            maskTr = true(size(Ltr_full));
                            maskCv = true(size(Lcv_full));
                        end
                        
                        % Apply masks to labels
                        Ltr = Ltr_full(maskTr);
                        Lcv = Lcv_full(maskCv);
                        
                        % --- base predictions (already sliced to 'cols' above): Htr, Hcv
                        % DataType routing
                        switch Param.EnsembleStrategy.DataType
                            case 1
                                Px = Htr(maskTr, :); Lx = Ltr;
                            case 2
                                Px = Hcv(maskCv, :); Lx = Lcv;
                            otherwise % 3
                                Px = [Htr(maskTr,:); Hcv(maskCv,:)]; 
                                Lx = [Ltr; Lcv];
                        end
                        
                        % --- label mapping for controller
                        % For classification/log-loss: map to {0,1}. For regression/expgrad/ridge:
                        %  - ridge: keep continuous labels
                        %  - expgrad: expects {-1,+1} (only meaningful for classification)
                        if strcmpi(B.mode,'logloss') && isClassification
                            labelsForController = (Lx == +1);   % {0,1}
                        elseif strcmpi(B.mode,'expgrad')
                            % ensure {-1,+1} for classification; avoid using expgrad in regression
                            if ~any(Lx==-1) || ~any(Lx==+1)
                                % map {0,1}->{-1,+1} if needed (only if classification)
                                labelsForController = 2*(Lx>0.5)-1;
                            else
                                labelsForController = Lx;
                            end
                        else
                            % ridge (works for regression or probs): use Lx as-is
                            labelsForController = Lx;
                        end

                        % Choose the appropriate representation for P:
                        %  - classification entropy/kappa/Q/LoBag: P_hard (N x m) of hard votes/correctness
                        %  - regression regvar: P_cont (N x m) of continuous predictions
                        if B.alpha>0 
                            if strcmpi(MODEFL, 'regression')
                                B.R = nk_BuildDiversityKernel(Px, labelsForController, Param.EnsembleStrategy.DiversitySource, B.Kernel); 
                            else
                                B.R = nk_BuildDiversityKernel(Px, labelsForController, Param.EnsembleStrategy.DiversitySource); 
                            end
                            %nk_ShowEnsembleDiversity(Px, B.R, VERBOSE, 'Name', sprintf('Fold %d | Class %d', j, curclass), 'CLimP', [0 1], 'CLimR', [0 1]);
                        end
                        w = nk_EnsembleBoostingWeights(Px, labelsForController, B);

                        % --- optional sparsification
                        if B.wThreshold > 0
                            w(w < B.wThreshold) = 0;
                            s = sum(w); if s>0, w = w/s; else, w = ones(size(w))/numel(w); end
                        end
                
                        % --- write back weights (full-length aligned to all learners)
                        wfull = zeros(ndim,1); wfull(cols) = w;
                        
                        % --- combine predictions (single column)
                        switch Metric
                            case 2
                                trComb = OUT.Trdecs{i,j,curclass}(:,cols) .* w';
                                cvComb = OUT.CVdecs{i,j,curclass}(:,cols) .* w';
                                
                                OUT.TrHD{i,j,curclass} = trComb;
                                OUT.CVHD{i,j,curclass} = cvComb;
                                OUT.TrHT{i,j,curclass} = OUT.Trtargs{i,j,curclass};
                                OUT.CVHT{i,j,curclass} = OUT.CVtargs{i,j,curclass};
                            otherwise
                                trComb = OUT.Trtargs{i,j,curclass}(:,cols) .* w';
                                cvComb = OUT.CVtargs{i,j,curclass}(:,cols) .* w';
                                OUT.TrHT{i,j,curclass} = trComb;
                                OUT.CVHT{i,j,curclass} = cvComb;
                                OUT.TrHD{i,j,curclass} = OUT.Trdecs{i,j,curclass};
                                OUT.CVHD{i,j,curclass} = OUT.CVdecs{i,j,curclass};
                        end
                        kIndN = wfull>0;
                        tSubSpaces{i,j,curclass}    = IN.F{i,j,curclass}(:,kIndN);
                        tF{i,j,curclass}            = kIndN; 
                        tWeights{i,j,curclass}      = wfull(kIndN);
                        tModels{i,j,curclass}       = OUT.mdl{i,j,curclass}(kIndN);
                        if W2AVAIL
                            tW2{i,j,curclass}       = OUT.w2{i,j,curclass}(kIndN);
                            tMd{i,j,curclass}       = OUT.Md{i,j,curclass}(kIndN);
                            tMm{i,j,curclass}       = OUT.Mm{i,j,curclass}(kIndN);
                        end                
                        % --- perf & diversity (assuming your helpers accept vector/matrix)
                        OUT.TrHDperf(i,j,curclass) = nk_EnsPerf( OUT.TrHD{i,j,curclass}, TrL{curclass} );
                        OUT.TrHTperf(i,j,curclass) = nk_EnsPerf( OUT.TrHT{i,j,curclass}, TrL{curclass} );
                        OUT.CVHDperf(i,j,curclass) = nk_EnsPerf( OUT.CVHD{i,j,curclass}, CVL{curclass} );
                        OUT.CVHTperf(i,j,curclass) = nk_EnsPerf( OUT.CVHT{i,j,curclass}, CVL{curclass} );
                
                        OUT.TrDiv(i,j,curclass)    = save_binary_div( Param, OUT.TrHT{i,j,curclass}, TrL{curclass} );
                        OUT.CVDiv(i,j,curclass)    = save_binary_div( Param, OUT.CVHT{i,j,curclass}, CVL{curclass} );
                    end
                
                    if MULTI.flag
                        OUT = MultiDichoFoldPerm(IN, OUT, [], LoopParam);
                        OUT.mTrPerf(i,j) = OUT.mtr{i,j};
                        OUT.mCVPerf(i,j) = OUT.mts{i,j};
                    end

            otherwise

                for curclass = 1: IN.nclass

                    %% Get pointers and labels
                    TrInd                   = IN.Y.TrInd{i,j}{curclass};
                    CVInd                   = IN.Y.CVInd{i,j}{curclass};

                    %% Construct dichotomization labels for CV1 training and test data:
                    CVL{curclass}           = zeros(size(OUT.CVtargs{i,j,curclass},1),1); 
                    CVL{curclass}(CVInd)    = IN.Y.CVL{i,j}{curclass}(:,MULTILABEL.curdim);
                    TrL{curclass}           = zeros(size(OUT.Trtargs{i,j,curclass},1),1); 
                    TrL{curclass}(TrInd)    = IN.Y.TrL{i,j}{curclass}(:,MULTILABEL.curdim);

                    %% Get feature subspace mask and feature weighting:
                    if nc > 1 
                        % Every dichotomizer has its own feature subspace mask
                        kInd = OUT.F{i,j,curclass}; W{curclass} = OUT.Weights{i,j,curclass};
                    else
                        % All dichotomizers share one feature subspace mask
                        % This mode is used for multi-group optimization
                        kInd = OUT.F{i,j}; W{curclass} = OUT.Weights{i,j};
                        ndim = size(OUT.Trdecs{i,j,curclass},2);
                         % number of base learners is not equal to the number of features in feature mask
                        if numel(kInd) > ndim, kInd = OUT.F{i,j}(1:ndim); end 
                    end

                    % Indices to preselected feature subspaces for each
                    % dichotomizer are retrieved using find function
                    kIndN{curclass} = find(kInd); 

                    %% Extract decision values / probabilities using feature subspace mask
                    OUT.TrHD{i,j,curclass} = OUT.Trdecs{i,j,curclass}(:,kIndN{curclass}); 
                    OUT.TrHT{i,j,curclass} = OUT.Trtargs{i,j,curclass}(:,kIndN{curclass});
                    OUT.CVHD{i,j,curclass} = OUT.CVdecs{i,j,curclass}(:,kIndN{curclass}); 
                    OUT.CVHT{i,j,curclass} = OUT.CVtargs{i,j,curclass}(:,kIndN{curclass});

                    %% Weighting: if no weighting is used targets and decision values are multiplied with ones
                    %kW{curclass} = W{curclass}(kIndN{curclass});
                    kW{curclass} = W{curclass}(kIndN{curclass});
                    m1 = size(OUT.TrHD{i,j,curclass},1); 
                    w1 = repmat(kW{curclass},1,m1)';
                    OUT.TrHD{i,j,curclass} = OUT.TrHD{i,j,curclass}.*w1; 
                    OUT.TrHT{i,j,curclass} = OUT.TrHT{i,j,curclass}.*w1;
                    m2 = size(OUT.CVHD{i,j,curclass},1);
                    w2 = repmat(kW{curclass},1,m2)';
                    OUT.CVHD{i,j,curclass} = OUT.CVHD{i,j,curclass}.*w2; 
                    OUT.CVHT{i,j,curclass} = OUT.CVHT{i,j,curclass}.*w2;

                    %% Multi-group preparation
                    % If multi-group classification is performed, perpare
                    % multi-group decision matrix by concatenating decision
                    % values / probabilities across dichotomizers:
                    % Memory allocation is preferable but not implemented
                    % yet.
                    if MULTI.flag
                        % Class array for dichotomization
                        mC = [mC ones(1,size(OUT.CVHT{i,j,curclass},2))*curclass];

                        % Choose either to use decision values / 
                        % probabilities (metric=2) or predicted class memberships 
                        % (metric=1)
                        switch Metric
                            case 1
                                % Training Data
                                mTr = [mTr OUT.TrHT{i,j,curclass}];
                                % Test Data
                                mCV = [mCV OUT.CVHT{i,j,curclass}];
                            case 2
                                mTr = [mTr OUT.TrHD{i,j,curclass}];
                                mCV = [mCV OUT.CVHD{i,j,curclass}];
                        end
                    end

                    switch EnsType

                        case 0 
                            %% AGGREGATED ENSEMBLE (no classifier selection)
                                if size(OUT.TrHD{i,j,curclass},2) > 1 
                                    if VERBOSE
                                        switch MODEFL
                                            case 'classification'

                                                fprintf('\n%s (Aggregated Ensemble) => CV1 [%g, %g, %s]:\t', ...
                                                    strout,i,j, CV.class{1,1}{curclass}.groupdesc); 
                                            case 'regression'
                                                fprintf('\n%s (Aggregated Ensemble) => CV1 [%g, %g, regression]:\t', ...
                                                    strout,i,j); 
                                        end
                                    end
                                    % Compute ensemble diversity criterion
                                    % only if more than 1 base learner is
                                    % present
                                    OUT.TrDiv(i,j,curclass) = save_binary_div( Param, OUT.TrHT{i,j,curclass}, TrL{curclass} );
                                    OUT.CVDiv(i,j,curclass) = save_binary_div( Param, OUT.CVHT{i,j,curclass}, CVL{curclass} );
                                     % Evaluate ensemble performance
                                    OUT.TrHDperf(i,j,curclass) = nk_EnsPerf( OUT.TrHD{i,j,curclass}, TrL{curclass} );
                                    OUT.TrHTperf(i,j,curclass) = nk_EnsPerf( OUT.TrHT{i,j,curclass}, TrL{curclass} );       
                                    OUT.CVHDperf(i,j,curclass) = nk_EnsPerf( OUT.CVHD{i,j,curclass}, CVL{curclass} );
                                    OUT.CVHTperf(i,j,curclass) = nk_EnsPerf( OUT.CVHT{i,j,curclass}, CVL{curclass} );
                                else
                                    OUT.TrHDperf(i,j,curclass) = OUT.tr{i,j,curclass}(kInd);
                                    OUT.TrHTperf(i,j,curclass) = OUT.tr{i,j,curclass}(kInd);
                                    OUT.CVHDperf(i,j,curclass) = OUT.ts{i,j,curclass}(kInd);
                                    OUT.CVHTperf(i,j,curclass) = OUT.ts{i,j,curclass}(kInd);
                                end                             

                                tkIndCat = [tkIndCat kInd'];
                                if ns > 1
                                    tSubSpaces{i,j,curclass}    = IN.F{i,j,curclass}(:,OUT.kxVec{i,j,curclass}(kIndN{curclass}));
                                    tF{i,j,curclass}            = kInd; 
                                    tWeights{i,j,curclass}      = W{curclass}(kIndN{curclass});
                                    tModels{i,j,curclass}       = OUT.mdl{i,j,curclass}(kIndN{curclass});

                                    if W2AVAIL
                                        tW2{i,j,curclass}       = OUT.w2{i,j,curclass}(kIndN{curclass});
                                        tMd{i,j,curclass}       = OUT.Md{i,j,curclass}(kIndN{curclass});
                                        tMm{i,j,curclass}       = OUT.Mm{i,j,curclass}(kIndN{curclass});
                                    end
                                else
                                    tSubSpaces{i,j,curclass}    = IN.F{i,j}(:,OUT.kxVec{i,j,curclass}(kIndN{curclass}));
                                    tF{i,j,curclass}            = kInd; 
                                    tWeights{i,j}               = W{curclass}(kIndN{curclass});
                                    tModels{i,j,curclass}       = OUT.mdl{i,j,curclass}(kIndN{curclass});

                                    if W2AVAIL
                                        tW2{i,j,curclass}       = OUT.w2{i,j,curclass}(kIndN{curclass});
                                        tMd{i,j,curclass}       = OUT.Md{i,j,curclass}(kIndN{curclass});
                                        tMm{i,j,curclass}       = OUT.Mm{i,j,curclass}(kIndN{curclass});
                                    end
                                end

                        otherwise
                                %% OPTIMIZED ENSEMBLE CONSTRUCTION 
                                 % (Recursive classifier elimination of forward classifier construction)                        
                                if ~MULTI.flag || ~MULTI.train % Perform binary optimization

                                    switch Param.EnsembleStrategy.DataType

                                        case 1 % Use CV1 training data for ensemble construction
                                            % Only for binary optimization: Use CV1-training data to optimize ensemble components
                                            Lx = TrL{curclass};
                                            
                                            switch Metric
                                                case 1 % Targets
                                                    
                                                    Px = OUT.TrHT{i,j,curclass};
                                                    [tkInd, Hx_perf, Hx ] = nk_BuildEnsemble(Px, Lx, Param.EnsembleStrategy,[], ngroups);
                                                    OUT.TrHTperf(i,j,curclass) = Hx_perf; OUT.TrHT{i,j,curclass} = Hx;
                                                    OUT.TrHD{i,j,curclass} = OUT.TrHD{i,j,curclass}(:,tkInd);
                                                    
                                                case 2 % Decision values
                                                    
                                                    Px = OUT.TrHD{i,j,curclass};  
                                                    [tkInd, Hx_perf, Hx ] = nk_BuildEnsemble(Px, Lx, Param.EnsembleStrategy,[], ngroups);
                                                    OUT.TrHDperf(i,j,curclass) = Hx_perf; OUT.TrHD{i,j,curclass} = Hx;
                                                    OUT.TrHT{i,j,curclass} = OUT.TrHT{i,j,curclass}(:,tkInd);
                                            end
                                            
                                            % Extract base classifiers from
                                            % CV1 test ensemble according to tkInd 
                                            OUT.CVHD{i,j,curclass}       = OUT.CVHD{i,j,curclass}(:,tkInd); 
                                            OUT.CVHT{i,j,curclass}       = OUT.CVHT{i,j,curclass}(:,tkInd);
                                            % Update performance of optimized CV1 test data ensemble
                                            OUT.CVHDperf(i,j,curclass)   = nk_EnsPerf( OUT.CVHD{i,j,curclass}, CVL{curclass} );
                                            OUT.CVHTperf(i,j,curclass)   = nk_EnsPerf( OUT.CVHT{i,j,curclass}, CVL{curclass} );
                                            % Compute entropy of optimized CV1 test data ensemble
                                            OUT.CVDiv(i,j,curclass) = save_binary_div( Param, OUT.CVHT{i,j,curclass}, CVL{curclass} );
                                            OUT.TrDiv(i,j,curclass) = save_binary_div( Param, OUT.TrHT{i,j,curclass}, TrL{curclass});

                                        case 2 % Use CV1 test data for ensemble construction
                                            % Only for binary optimization: Use CV1-test data to optimize ensemble components
                                            Lx = CVL{curclass};
                                            
                                            switch Metric
                                                case 1
                                                    Px = OUT.CVHT{i,j,curclass}; 
                                                    [tkInd, Hx_perf, Hx ] = nk_BuildEnsemble(Px, Lx, Param.EnsembleStrategy,[], ngroups);
                                                    OUT.CVHTperf(i,j,curclass) = Hx_perf; OUT.CVHT{i,j,curclass} = Hx;
                                                    OUT.CVHD{i,j,curclass} = OUT.CVHD{i,j,curclass}(:,tkInd);
                                                    
                                                case 2                       
                                                    Px = OUT.CVHD{i,j,curclass}; 
                                                    [ tkInd, Hx_perf, Hx ] = nk_BuildEnsemble(Px, Lx, Param.EnsembleStrategy,[],ngroups);
                                                    OUT.CVHDperf(i,j,curclass)  = Hx_perf; OUT.CVHD{i,j,curclass}      = Hx;  
                                                    OUT.CVHT{i,j,curclass} = OUT.CVHT{i,j,curclass}(:,tkInd);
                                            end
                                            
                                            % Extract base classifiers from
                                            % CV1 training ensemble according to tkInd 
                                            OUT.TrHD{i,j,curclass}       = OUT.TrHD{i,j,curclass}(:,tkInd); 
                                            OUT.TrHT{i,j,curclass}       = OUT.TrHT{i,j,curclass}(:,tkInd);
                                            % Update performance of optimized CV1 training data ensemble
                                            OUT.TrHDperf(i,j,curclass)   = nk_EnsPerf( OUT.TrHD{i,j,curclass}, TrL{curclass} );
                                            OUT.TrHTperf(i,j,curclass)   = nk_EnsPerf( OUT.TrHT{i,j,curclass}, TrL{curclass} );
                                            % Compute entropy of optimized CV1 training data ensemble
                                            OUT.TrDiv(i,j,curclass) = save_binary_div( Param, OUT.TrHT{i,j,curclass}, TrL{curclass});
                                            OUT.CVDiv(i,j,curclass) = save_binary_div( Param, OUT.CVHT{i,j,curclass}, CVL{curclass});
                                            
                                        case 3 % Use CV1 training & test data for ensemble construction
                                             
                                            Lx = [TrL{curclass}; CVL{curclass}];
                                            %Ix = [ones(size(TrL{curclass},1),1); 2*ones(size(CVL{curclass},1),1)];
                                            
                                            switch Metric
                                                case 1 
                                                    Px = [ OUT.TrHT{i,j,curclass}; OUT.CVHT{i,j,curclass} ]; 
                                                    tkInd = nk_BuildEnsemble(Px, Lx, Param.EnsembleStrategy, [], ngroups);
                                                    
                                                case 2
                                                    Px = [ OUT.TrHD{i,j,curclass}; OUT.CVHD{i,j,curclass} ]; 
                                                    tkInd = nk_BuildEnsemble(Px, Lx, Param.EnsembleStrategy,[],ngroups);
                                            end
                                           
                                            OUT.TrHT{i,j,curclass}      = OUT.TrHT{i,j,curclass}(:,tkInd);
                                            OUT.CVHT{i,j,curclass}      = OUT.CVHT{i,j,curclass}(:,tkInd);
                                            OUT.TrHD{i,j,curclass}      = OUT.TrHD{i,j,curclass}(:,tkInd);
                                            OUT.CVHD{i,j,curclass}      = OUT.CVHD{i,j,curclass}(:,tkInd);
                                            OUT.TrDiv(i,j,curclass)     = save_binary_div( Param, OUT.TrHT{i,j,curclass}, TrL{curclass});
                                            OUT.CVDiv(i,j,curclass)     = save_binary_div( Param, OUT.CVHT{i,j,curclass}, CVL{curclass});
                                            OUT.TrHDperf(i,j,curclass)  = nk_EnsPerf( OUT.TrHD{i,j,curclass}, TrL{curclass} );
                                            OUT.TrHTperf(i,j,curclass)  = nk_EnsPerf( OUT.TrHT{i,j,curclass}, TrL{curclass} );
                                            OUT.CVHDperf(i,j,curclass)  = nk_EnsPerf( OUT.CVHD{i,j,curclass}, CVL{curclass} );
                                            OUT.CVHTperf(i,j,curclass)  = nk_EnsPerf( OUT.CVHT{i,j,curclass}, CVL{curclass} );
                                            
                                    end
                                    % Is this correct?
                                    tInd = false(1,length(kIndN{curclass})); tInd(tkInd)=true;
                                    tkIndCat = [tkIndCat tInd];
                                    % Update feature subspace mask indices
                                    kIndN{curclass} = kIndN{curclass}(tkInd);
                                    % Update feature subspaces
                                    tSubSpaces{i,j,curclass} = IN.F{i,j,curclass}(:,OUT.kxVec{i,j,curclass}(kIndN{curclass}));
                                    % Update feature subspace masks
                                    tF{i,j,curclass} = false(size(OUT.F{i,j,curclass}));
                                    tF{i,j,curclass}(kIndN{curclass}) = true;
                                    % Update feature subspace weights
                                    tWeights{i,j,curclass} = W{curclass}(tkInd);
                                    tModels{i,j,curclass}  = OUT.mdl{i,j,curclass}(kIndN{curclass});

                                    if W2AVAIL
                                        tW2{i,j,curclass}       = OUT.w2{i,j,curclass}(kIndN{curclass});
                                        tMd{i,j,curclass}       = OUT.Md{i,j,curclass}(kIndN{curclass});
                                        tMm{i,j,curclass}       = OUT.Mm{i,j,curclass}(kIndN{curclass});
                                    end
                                end     
                    end
                end

                %% MULTI-GROUP OPTIMIZATION                              
                if MULTI.flag

                    % Hardcode if ECOC will be used:
                    if MULTI.method == 2, mTr = sign(mTr); mCV = sign(mCV); end

                    switch EnsType

                        case 0
                            %% MULTI-GROUP AGGREGATED ENSEMBLE (no classifier selection)
                            % Compute CV1-training and test data
                            % performance using simply the aggregated
                            % multi-group ensembles:
                            [OUT.mTrPerf(i,j), OUT.mTrPred{i,j}] = nk_MultiEnsPerf(mTr, sign(mTr), IN.Y.mTrL{i,j}(:,MULTILABEL.curdim), mC, ngroups);
                            [OUT.mCVPerf(i,j), OUT.mCVPred{i,j}] = nk_MultiEnsPerf(mCV, sign(mCV), IN.Y.mCVL{i,j}(:,MULTILABEL.curdim), mC, ngroups);
                            % Compute CV1-training and test data
                            % ensemble entropy as the mean of
                            % dichotomizers' entropies
                            if ~isempty(DivFunc)
                                for qcurclass = 1 : IN.nclass
                                    indC = mC==qcurclass; tkInd{qcurclass} = indC; 
                                end
                                OUT.mTrDiv(i,j) = compute_diversity(IN, Param, tkInd, mTr, TrL);
                                OUT.mCVDiv(i,j) = compute_diversity(IN, Param, tkInd, mCV, CVL);
                            end
                            % Subspace & models don't have to be
                            % updated, this has already been done in
                            % the binary classifier section

                        otherwise
                            %% OPTIMIZED MULTI-GROUP ENSEMBLE CONSTRUCTION 
                            if MULTI.train

                                % Perform multi-class optimization
                                switch Param.EnsembleStrategy.DataType
                                    
                                    case 1 % CV1-Training Data
                                        [tkInd, ...
                                            OUT.mTrPerf(i,j), ...
                                            ~, ...
                                            ~, ...
                                            tkIndCat, ...
                                            OUT.mTrPred{i,j}] = ...
                                                        nk_BuildEnsemble(mTr, IN.Y.mTrL{i,j}(:,MULTILABEL.curdim), Param.EnsembleStrategy, mC, ngroups);

                                        % Compute CV1-test data multi-group performance:
                                        [OUT.mCVPerf(i,j), OUT.mCVPred{i,j}] = nk_MultiEnsPerf(mCV(:,tkIndCat), sign(mCV(:,tkIndCat)), IN.Y.mCVL{i,j}(:,MULTILABEL.curdim), mC(tkIndCat), ngroups);
                                        
                                        % Compute CV1-train/test data ensemble entropy:
                                        OUT.mCVDiv(i,j) = compute_diversity(IN, Param, tkInd, mCV, CVL);
                                        OUT.mTrDiv(i,j) = compute_diversity(IN, Param, tkInd, mTr, TrL);

                                    case 2 % CV1-Test Data
                                        [tkInd, ...
                                            OUT.mCVPerf(i,j), ...
                                            ~, ...
                                            ~, ...
                                            tkIndCat,...
                                            OUT.mCVPred{i,j}] = ...
                                                        nk_BuildEnsemble(mCV, IN.Y.mCVL{i,j}(:,MULTILABEL.curdim), Param.EnsembleStrategy, mC, ngroups);

                                        % Compute CV1-training data multi-group performance:
                                        [OUT.mTrPerf(i,j), OUT.mTrPred{i,j}] = ...
                                            nk_MultiEnsPerf(mTr(:,tkIndCat), sign(mTr(:,tkIndCat)), IN.Y.mTrL{i,j}(:,MULTILABEL.curdim), mC(tkIndCat), ngroups);

                                        % Compute CV1-training data ensemble entropy:
                                        OUT.mTrDiv(i,j) = compute_diversity(IN, Param, tkInd, mTr, TrL);
                                        OUT.mCVDiv(i,j) = compute_diversity(IN, Param, tkInd, mCV, CVL);
                                end

                                % Apply tkInd to dichotomization info
                                for curclass = 1 : IN.nclass
                                    % Update feature mask indices with
                                    % optimization info:
                                    kIndN{curclass}               = kIndN{curclass}(tkInd{curclass});
                                    % Apply this to the training data:
                                    OUT.TrHD{i,j,curclass}          = OUT.TrHD{i,j,curclass}(:,tkInd{curclass}); 
                                    OUT.TrHT{i,j,curclass}          = OUT.TrHT{i,j,curclass}(:,tkInd{curclass});
                                    OUT.TrHDperf(i,j,curclass)      = nk_EnsPerf( OUT.TrHD{i,j,curclass}, TrL{curclass} );
                                    OUT.TrHTperf(i,j,curclass)      = nk_EnsPerf( OUT.TrHT{i,j,curclass}, TrL{curclass} );
                                    OUT.TrDiv(i,j,curclass)         = save_binary_div(Param, OUT.TrHT{i,j,curclass}, TrL{curclass});
                                    % ... to the CV1-test data:
                                    OUT.CVHD{i,j,curclass}          = OUT.CVHD{i,j,curclass}(:,tkInd{curclass} ); 
                                    OUT.CVHT{i,j,curclass}          = OUT.CVHT{i,j,curclass}(:,tkInd{curclass} );
                                    OUT.CVHDperf(i,j,curclass)      = nk_EnsPerf( OUT.CVHD{i,j,curclass}, CVL{curclass} );
                                    OUT.CVHTperf(i,j,curclass)      = nk_EnsPerf( OUT.CVHT{i,j,curclass}, CVL{curclass} );
                                    OUT.CVDiv(i,j,curclass)         = save_binary_div(Param, OUT.CVHT{i,j,curclass}, CVL{curclass});

                                    % ... and to the feature subspace info:
                                    if ns > 1
                                        tSubSpaces{i,j,curclass}    = IN.F{i,j,curclass}(:,OUT.kxVec{i,j,curclass}(kIndN{curclass}));
                                    else
                                        tSubSpaces{i,j,curclass}    = IN.F{i,j}(:,OUT.kxVec{i,j,curclass}(kIndN{curclass}));
                                    end
                                    if nc > 1
                                        tF{i,j,curclass}            = false(size(OUT.F{i,j,curclass}));
                                    else
                                        tF{i,j,curclass}            = false(size(OUT.F{i,j}));
                                    end
                                    tF{i,j,curclass}(kIndN{curclass}) = true;
                                    tWeights{i,j,curclass}          = W{curclass}(tkInd{curclass});
                                    tModels{i,j,curclass}           = OUT.mdl{i,j,curclass}(kIndN{curclass});
                                    if W2AVAIL
                                        tW2{i,j,curclass}       = OUT.w2{i,j,curclass}(kIndN{curclass});
                                        tMd{i,j,curclass}       = OUT.Md{i,j,curclass}(kIndN{curclass});
                                        tMm{i,j,curclass}       = OUT.Mm{i,j,curclass}(kIndN{curclass});
                                    end
                                end
                            else
                                % Simpy extract the multi-group
                                % ensemble by applying tkIndCat to the
                                % concated dichotomization data
                                tkIndCat = logical(tkIndCat);
                                if ~any(tkIndCat)
                                    % Fallback: keep all columns if nothing selected
                                    tkIndCat = true(1, size(mTr,2));
                                end
                                
                                % Build per-dichotomizer masks from the concatenated mask
                                tkInd = cell(1, IN.nclass);
                                for q = 1:IN.nclass
                                    tkInd{q} = (mC == q) & tkIndCat;  % logical mask across concatenated columns
                                end
                                
                                % CV1-training data ensemble performance and diversity
                                [OUT.mTrPerf(i,j), OUT.mTrPred{i,j}] = nk_MultiEnsPerf( ...
                                    mTr(:,tkIndCat), ...
                                    sign(mTr(:,tkIndCat)), ...
                                    IN.Y.mTrL{i,j}(:,MULTILABEL.curdim), ...
                                    mC(tkIndCat), ngroups);
                                
                                OUT.mTrDiv(i,j) = compute_diversity(IN, Param, tkInd, mTr, TrL);
                                
                                % CV1-test data ensemble performance and diversity
                                [OUT.mCVPerf(i,j), OUT.mCVPred{i,j}] = nk_MultiEnsPerf( ...
                                    mCV(:,tkIndCat), ...
                                    sign(mCV(:,tkIndCat)), ...
                                    IN.Y.mCVL{i,j}(:,MULTILABEL.curdim), ...
                                    mC(tkIndCat), ngroups);
                                
                                OUT.mCVDiv(i,j) = compute_diversity(IN, Param, tkInd, mCV, CVL);
                            end

                    end
                end
        end
    end
end

if EnsType ~=9 
    % Update IN and OUT
    IN.F        = tSubSpaces;
    OUT.F       = tF;
    OUT.Weights = tWeights;
    OUT.mdl     = tModels;
    if W2AVAIL
        OUT.w2  = tW2;
        OUT.Md  = tMd;
        OUT.Mm  = tMm;
    end
end

end

function tDiv = compute_diversity(IN, Param, tkInd, M, L)

% ---- M diversity (per-dichotomizer, then average) ------------
tDiv = nan(IN.nclass,1);

% Get the configured diversity source (default to 'entropy')
divsrc = 'entropy';
if isfield(Param,'EnsembleStrategy') && isfield(Param.EnsembleStrategy,'DiversitySource') ...
        && ~isempty(Param.EnsembleStrategy.DiversitySource)
    divsrc = lower(Param.EnsembleStrategy.DiversitySource);
end

for q = 1:IN.nclass
    cols = [];
    if iscell(tkInd)
        cols = tkInd{q};
    end
    if isempty(cols)
        % no selected learner for this dichotomizer → diversity undefined: set to 0
        tDiv(q) = 0;
        continue;
    end

    % keep only rows relevant for this dichotomizer (binary task has L in {-1,+1}, others 0)
    Lq = L{q};
    mask = (Lq ~= 0);
    if ~any(mask)
        tDiv(q) = 0;  % nothing to evaluate
        continue;
    end

    % slice CV1-training predictions for the selected learners and relevant rows
    Esub = M(mask, cols);

    % use hard predictions where needed
    Tsub = sign(Esub);
    Tsub(Tsub==0) = -1;

    Lsub = Lq(mask);        % binary {-1,+1}

    % compute diversity per the configured source
    switch divsrc
        case 'entropy'    % label-free vote dispersion in [0,1]
            tDiv(q) = nk_Entropy(Tsub, [-1 1], size(Tsub,2), []);
            
        case 'kappaa'     % 1 − Double-fault A  → map to [0,1], higher = more diversity
            [A,~] = nk_Diversity(Tsub, Lsub, [], []);
            tDiv(q) = max(0,min(1,1 - A));

        case 'kappaq'     % −Q  mapped to [0,1]: D = (1 − Q)/2
            [A,Q] = nk_Diversity(Tsub, Lsub, [], []);
            if isfinite(Q),   tDiv(q) = 0.5*(1 - max(-1,min(1,Q)));
            else,             tDiv(q) = max(0,min(1,1 - A)); % fallback
            end

        case 'kappaf'     % Fleiss' κ over correctness: use (1−κ)/2 ∈ [0,1]
            D1mK = nk_DiversityKappa(Tsub, Lsub, [], []);  % returns 1-κ
            if isfinite(D1mK), tDiv(q) = max(0,min(1,0.5*D1mK));
            else,               tDiv(q) = 0;
            end

        case 'lobag'      % LoBag (binary) — lower ED ⇒ more diversity; report −ED so “higher is better”
            % binary LoBag; returns ED in [-1,2]. “More diversity” ⇒ smaller ED
            ED = nk_Lobag(Tsub, Lsub);
            ED = max(-1,min(2,ED));       % clamp
            tDiv(q) = (2 - ED)/3;         % map ED→[0,1], higher=more diversity

        otherwise         % default to entropy
            tDiv(q) = nk_Entropy(Tsub, [-1 1], size(Tsub,2), []);
    end
end

% average across dichotomizers (ignore NaNs)
tDiv = mean(tDiv,'omitnan');

end

function Div = save_binary_div(Param, HT, Lbin)

    % Lbin: {-1,+1,0}, HT: per-dichotomizer predictions (scores or labels)
    % Returns a scalar diversity in [0,1] (higher = more diversity)

    if isempty(HT) || isempty(Lbin)
        Div = 0; return;
    end

    % relevant rows for this dichotomizer
    mask = (Lbin ~= 0);
    if ~any(mask)
        Div = 0; return;
    end

    % slice
    Tsub = HT(mask,:);           % N x n
    Lsub = Lbin(mask);           % N x 1 in {-1,+1}
  
    % hard votes for non-entropy metrics
    Vhard = sign(Tsub);
    Vhard(Vhard==0) = -1;

    src = 'entropy';
    if isfield(Param,'EnsembleStrategy') && isfield(Param.EnsembleStrategy,'DiversitySource') ...
       && ~isempty(Param.EnsembleStrategy.DiversitySource)
        src = lower(Param.EnsembleStrategy.DiversitySource);
    end

    switch src
        case 'lobag'
            % LoBag ED (lower is better) -> map to [0,1] diversity (higher better)
            if size(Vhard,2) < 1, Div = 0; return; end
            ED = nk_Lobag(Vhard, Lsub);         % ED ∈ [-1,2]
            ED = max(-1, min(2, ED));           % clamp
            Div = (2 - ED) / 3;                 % map to [0,1]

        case 'entropy'
            % vote-entropy in [0,1], label-free
            Div = nk_Entropy(Vhard, [-1 1], size(Vhard,2), []);

        case 'kappaa'   % 1 − Double-fault A
            if size(Vhard,2) < 2, Div = 0; return; end
            [A,~] = nk_Diversity(Vhard, Lsub, [], []);
            Div   = max(0,min(1,1 - A));

        case 'kappaq'   % (1 − Q)/2 with fallback to 1−A
            if size(Vhard,2) < 2, Div = 0; return; end
            [A,Q] = nk_Diversity(Vhard, Lsub, [], []);
            if isfinite(Q)
                Div = 0.5*(1 - max(-1,min(1,Q)));
            else
                Div = max(0,min(1,1 - A));
            end

        case 'kappaf'   % (1 − Fleiss’ κ)/2
            if size(Vhard,2) < 2, Div = 0; return; end
            D1mK = nk_DiversityKappa(Vhard, Lsub, [], []);  % returns 1 − κ
            if isfinite(D1mK)
                Div = max(0,min(1,0.5 * D1mK));
            else
                Div = 0;
            end

        otherwise
            % default to entropy
            Div = nk_Entropy(Vhard, [-1 1], size(Vhard,2), []);
    end
end

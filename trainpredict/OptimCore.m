% =========================================================================
% Res = OptimCore(IN, OUT, strout, Param, OptMode, Weighting)
% =========================================================================
%
% DESCRIPTION:
%   OptimCore is the central training engine of the NeuroMiner (NM)
%   framework. It implements various optimization strategies, including
%   filter and wrapper methods (via FoldPerm), as well as ensemble-based 
%   optimizations for binary/regression and multi-class settings. The 
%   function aggregates CV1 training and test results across partitions 
%   and organizes them into a structured output.
%
% INPUTS:
%   IN        - Structure containing the input data (training/test).
%   OUT       - Structure containing initial model outputs.
%   strout    - String used for labeling/logging intermediate results.
%   Param     - Structure with parameters for optimization and evaluation.
%   OptMode   - Flag indicating the optimization mode (e.g., 0 for filters,
%               1 for wrappers).
%   Weighting - Weighting scheme for subspace evaluation.
%
% OUTPUT:
%   Res       - Structured output that includes:
%               • Selected feature subspaces and their evaluation metrics
%               • Ensemble predictions (if applicable)
%               • Model complexity parameters, among other metrics.
%
% GLOBAL VARIABLES:
%   SVM, MULTI, MODEFL, RFE, VERBOSE
%
% DEPENDENT FUNCTIONS:
%   FoldPerm, MultiDichoFoldPerm, nk_ReturnEvalOperator, EvalSubSpaces,
%   DetrendFoldPerm, SubSpaceStrat, SelectFeaturesAcrossCV1, EvalSeqOpt,
%   EvalCoxPH, TransferResults, nk_ModelComplexityParams.
%
% (c) Nikolaos Koutsouleris, 03/2025
% =========================================================================

function Res = OptimCore(IN, OUT, strout, Param, OptMode, Weighting)

global SVM MULTI MODEFL RFE VERBOSE

%% Step 1: Train the Prediction Model on Pre-filtered Feature Subspaces
% Determine whether immediate retraining is needed based on RFE settings.
rtrfl = 0;
if isfield(RFE, 'RetrainImmediate') && RFE.RetrainImmediate && RFE.ClassRetrain && ...
        (~RFE.Wrapper.flag || OptMode == 1)
    rtrfl = 1;
end

if rtrfl
    % Immediate retraining (concatenates CV1-Tr and CV1-Ts without further optimization)
    [IN, OUT] = FoldPerm(IN, OUT, 'Immediate Retrain (CV1-Tr + CV1-Ts)', 0, 1, 1, 0);
else
    % Standard training with the specified optimization mode and subspace stepping
    [IN, OUT] = FoldPerm(IN, OUT, strout, OptMode, 0, 0, Param.SubSpaceStepping);
end

%% Step 1b: Handle Multi-Group Optimization (if applicable)
if MULTI.flag
    strprf = 'Multi-Group classifier';
    OUT = MultiDichoFoldPerm(IN, OUT);
else
    switch MODEFL
        case 'classification'
            strprf = 'Binary classifier';
        case 'regression'
            strprf = 'Regressor';
    end
end

%% Step 2: Evaluate and Select Feature Subspaces Based on Performance
if VERBOSE
    fprintf('\n\nEvaluate CV performance and select subsets');
    fprintf('\n------------------------------------------');
end
% Update output string to reflect current selection process
strout = [strprf ' selection'];

% Retrieve evaluation operator parameters (minmax flag etc.)
[~, ~, ~, ~, ~, minmaxfl] = nk_ReturnEvalOperator(SVM.GridParam);

% Determine if retraining after class-level optimization should be performed.
RetrainFlag = RFE.ClassRetrain && (~RFE.Wrapper.flag || OptMode == 1) && ~rtrfl;

% Compute the ranking criterion based on the cost function setting
switch Param.CostFun
    case 0
        tRankCrit = OUT.tr;
        fprintf('\nNo subspace evaluation required.');
    case {1, 2, 3}  % Optimize SVM performance on CV1 test data
        switch Param.CostFun
            case 1
                tRankCrit = OUT.tr;
                if MULTI.flag && MULTI.train
                    tRankCrit = OUT.mtr;
                end
            case 2
                tRankCrit = OUT.ts;
                if MULTI.flag && MULTI.train
                    tRankCrit = OUT.mts;
                end
            case 3
                if MULTI.flag && MULTI.train
                    X = cellfun(@plus, OUT.mts, OUT.mtr, 'UniformOutput', false);
                    tRankCrit = cellfun(@rdivide, X, repmat({2}, size(X)), 'UniformOutput', false);
                else
                    X = cellfun(@plus, OUT.ts, OUT.tr, 'UniformOutput', false);
                    tRankCrit = cellfun(@rdivide, X, repmat({2}, size(X)), 'UniformOutput', false);
                end
        end
end

% Evaluate subspaces using the defined cost criteria and weighting
[OUT.F, OUT.Weights] = EvalSubSpaces(tRankCrit, strout, ...
    Param.SubSpaceStrategy, Param.SubSpaceCrit, minmaxfl, [], Weighting);

%% Step 3: Post-Processing and Ensemble Construction
% Optionally remove trends from prediction errors in regression settings.
OUT = DetrendFoldPerm(IN, OUT);

% Construct ensemble predictor if defined in the strategy settings.
strout = 'Construct';
[IN, OUT] = SubSpaceStrat(IN, OUT, Param, OptMode, strout);

% Perform cross-CV1 probabilistic feature selection if enabled.
if isfield(Param, 'PFE') && Param.PFE.flag
    [IN, OUT] = SelectFeaturesAcrossCV1(IN, OUT, Param, minmaxfl, 0);
end

%% Step 4: Optional Retraining of the Classifier
% Compute sample sizes (S) for each class.
S = zeros(IN.nclass, 1);
if RetrainFlag
    % Retrain classifier by concatenating CV1 training and test data.
    [IN, OUT] = FoldPerm(IN, OUT, 'Retrain (CV1-Tr + CV1-Ts)', 0, 1, 0, 0);
    for curclass = 1:IN.nclass
        S(curclass) = size(IN.Y.TrL{1,1}{curclass}, 1) + size(IN.Y.CVL{1,1}{curclass}, 1);
    end
elseif rtrfl
    % Immediate retraining branch: compute combined sample sizes.
    for curclass = 1:IN.nclass
        S(curclass) = size(IN.Y.TrL{1,1}{curclass}, 1) + size(IN.Y.CVL{1,1}{curclass}, 1);
    end
else
    % Use only training data sample sizes.
    for curclass = 1:IN.nclass
        S(curclass) = size(IN.Y.TrL{1,1}{curclass}, 1);
    end
end

%% Step 5: Evaluate Additional Optimizers (if applicable)
switch SVM.prog
    case 'SEQOPT'
        [OUT.critgain, OUT.examfreq, OUT.percthreshU, OUT.percthreshL, ...
         OUT.absthreshU, OUT.absthreshL] = EvalSeqOpt(OUT.mdl);
    case 'WBLCOX'
        [OUT.threshperc, OUT.threshprob, OUT.times] = EvalCoxPH(OUT.mdl);
end

%% Final Step: Transfer and Augment Results
% Copy all relevant results into the output structure.
Res = TransferResults(IN, OUT, Param);

% Compute and store model complexity parameters.
[Res.ModelComplexity.sumNSV, ...
 Res.ModelComplexity.meanNSV, ...
 Res.ModelComplexity.stdNSV, ...
 Res.ModelComplexity.Complex] = nk_ModelComplexityParams(Res.Models, S);

end

% ===================================================================================================
%  Predict = nk_PredictData(F, W, TR, TRInd, CVD, CVDInd, TS, dTSInd, dTSLabel, mTSInd, mTSLabel, ...
%                           MD, ngroups, detrend)
% ===================================================================================================
% Apply the CV1-trained ensemble(s) to the CV2 (outer–CV) data and compute
% binary (per–dichotomizer) as well as multi-class predictions, performance,
% and diversity measures.
%
% The function supports:
%   • Binary classification and regression
%   • Multi-class via dichotomization (one-vs-one / one-vs-rest / ECOC)
%   • Optional per-learner weights
%   • Optional de-trending at prediction time
%
% INPUTS
% ------
% F         : Feature-mask(s) selected during CV1.
%             Cell array sized {nPerm, nFold [, nClass]}.
%             Each element is a logical/0-1 matrix (#features × #subspaces).
%             If only one page is provided (size(F,3)==1) it is shared.
%
% W         : Per-learner weights (optional). Same indexing as F.
%             Each element is a vector of length #subspaces (or empty).
%
% TR        : CV1 training data used to fit models (per fold/permutation).
%             Cell {nPerm, nFold} with either:
%               - numeric matrix  [Ntr × p] (regression or “shared” case), or
%               - 1×nClass cell of matrices (binary per dichotomizer).
%
% TRInd     : Row indices selecting the CV1-training rows from TR
%             (same nesting as TR). May be [] to use all rows.
%
% CVD       : CV1 test/validation (“held-out within CV1”) data.
%             Same structure as TR.
%
% CVDInd    : Row indices selecting the CV1-test rows from CVD
%             (same nesting). May be [].
%
% TS        : CV2 evaluation data (outer-CV). Same structure as TR.
%
% dTSInd    : Row indices selecting the CV2 rows per dichotomizer.
%             Cell {1,nClass} or [] to use all rows.
%
% dTSLabel  : Labels for CV2 data per dichotomizer. Cell {1,nClass};
%             binary labels in {-1,+1} (classification) or target y (regression).
%
% mTSInd    : Row indices for the multi-class view (outer-CV). May be a cell
%             {nPerm,nFold} or a vector; [] uses all rows.
%
% mTSLabel  : CV2 multi-class labels as a column vector (values 1..K), or
%             a matrix with the label in column MULTILABEL.curdim.
%
% MD        : CV1 model structures learned previously, indexed as
%             MD{nPerm,nFold,nClass}{u}, where u = 1..#subspaces (ul).
%             These are passed to nk_GetTestPerf / nk_ApplyDetrend.
%
% ngroups   : Number of classes (K) for the multi-class decoding when the
%             decomposition mode requires it (e.g., one-vs-rest).
%
% detrend   : (optional) Detrending settings. If provided, prediction uses
%             nk_ApplyDetrend; otherwise nk_GetTestPerf is used.
%
% GLOBALS USED
% ------------
% SVM, CV, MULTI, MODEFL, VERBOSE, RFE, EVALFUNC, RAND, MULTILABEL
% (configured by NeuroMiner; EVALFUNC is the performance metric, e.g., BAC)
%
% OUTPUT
% ------
% Predict : struct with the following fields (dimensions reflect the CV1
%          grid {nPerm × nFold} and the number of dichotomizers nClass):
%
%   % Per-dichotomizer predictions & performance on CV2 (by CV1 fold)
%   .binCV1Predictions{k,l,curclass}   : CV2 decision values per subspace
%                                        [Ntest × ul (× mnclass if OVR)]
%   .binCV1Performance(k,l,curclass)   : mean performance over ul models
%   .binCV1Performance_Mean(1,curclass): mean over all CV1 folds/perms
%   .binCV1Performance_SD(1,curclass)  : st.dev. over CV1 folds/perms
%
%   % Optional diagnostics depending on SVM.prog:
%   .binCV1CasePropagations{k,l,curclass}
%   .binCV1PerformanceIncreases{k,l,curclass}
%   .binCV1DecValTraj{k,l,curclass}
%   .binCV1times{k,l,curclass}
%   .binCV1probthresh(k,l,curclass)
%
%   % Aggregated multi-class (outer-CV / CV2) by CV1 fold
%   .MultiCV1Performance(k,l)          : scalar performance per (k,l)
%   .MultiCV1Predictions{k,l}          : predicted class per subject
%   .MultiCV1Probabilities{k,l}        : class probabilities/similarities
%
%   % Final per-dichotomizer performance & diversity on CV2
%   .binCV2Performance_Targets(1,nClass)   : using hard targets
%   .binCV2Performance_DecValues(1,nClass) : using decision values
%   .binCV2Predictions_Targets{curclass}   : CV2 hard-label ensemble output
%   .binCV2Predictions_DecValues{curclass} : CV2 score-based ensemble output
%   .binCV2Diversity_Targets(1,nClass)     : diversity on hard targets
%   .binCV2Diversity_DecValues(1,nClass)   : diversity on hard-labels
%                                            derived from decision values
%   .DiversitySource                        : 'entropy'|'kappaa'|'kappaq'|
%                                             'kappaf'|'lobag'|'regvar'
%
%   % Final multi-class performance & diversity on CV2
%   .MultiCV2Performance                 : scalar (outer-CV)
%   .MultiCV2Predictions                 : predicted class per subject
%   .MultiCV2Probabilities               : per-class probabilities
%   .MultiCV2Diversity_Targets           : mean of per-dichotomizer values
%   .MultiCV2Diversity_DecValues         : mean of per-dichotomizer values
%
% NOTES
% -----
% • Ensemble construction strategy (weights/diversity) is read from
%   RFE.Filter.EnsembleStrategy. Diversity is evaluated as configured and
%   reported on a [0,1] scale (LoBag is internally re-mapped to [0,1]).
% • In classification, majority vote / product vote / ECOC decoding are
%   used as implemented in the function body (see ENSMETHOD/RAND.Decompose).
% • Labels for binary tasks must be {-1,+1}; non-relevant rows are coded 0.
% • Multi-class performance uses nk_MultiEnsPerf; binary/regression uses
%   EVALFUNC on the aggregated predictions.
%
% SEE ALSO
% --------
% nk_GetTestPerf, nk_ApplyDetrend, nk_MultiEnsPerf, nk_Entropy, nk_Diversity,
% nk_DiversityKappa, nk_Lobag, nk_RegAmbig, nk_MultiAssemblePredictions
% =========================================================================
% (c) Nikolaos Koutsouleris, 10/2025

function Predict = nk_PredictData(F, W, TR, TRInd, ...
                                        CVD, CVDInd, ...
                                        TS, dTSInd, dTSLabel, ...
                                        mTSInd, mTSLabel, ...
                                        MD, ngroups, detrend)
                                    
global SVM CV MULTI MODEFL VERBOSE RFE EVALFUNC RAND MULTILABEL

% Initialize Variables
[iy,jy]     = size(TR);
mnclass = 1;
if strcmp(MODEFL,'classification')
    if RAND.Decompose ~= 9
        nclass = length(CV.class{1,1});
    else
        nclass = 1;
        mnclass = ngroups;
    end
elseif strcmp(MODEFL,'regression')
    nclass = 1;
end
nF          = size(F,3);
nW          = size(W,3);
ENSMETHOD   = 1;

% CV1 partitions
Predict.binCV1Predictions        = cell(iy,jy);
Predict.binCV1Performance        = zeros(iy,jy,mnclass);
Predict.binCV1Performance_Mean   = zeros(1,mnclass);
Predict.binCV1Performance_SD     = zeros(1,mnclass);
if MULTI.flag 
    Predict.MultiCV1Predictions  = cell(iy,jy);
    Predict.MultiCV1Probabilities  = cell(iy,jy);
    Predict.MultiCV1Performance  = zeros(iy,jy); 
end

switch SVM.prog
    case 'SEQOPT'
        Predict.binCV1CasePropagations = cell(iy,jy,nclass);
        Predict.binCV1PerformanceIncreases = cell(iy,jy,nclass);
        Predict.binCV1DecValTraj = cell(iy,jy,nclass);
    case 'WBLCOX'
        Predict.binCV1times = cell(iy,jy,nclass);
        Predict.binCV1probthresh = zeros(iy,jy,nclass);
end

% --- Get ensemble optimization strategy (from RFE) ---
EnsStrat = struct('DiversitySource','entropy');

if isfield(RFE,'Filter') && RFE.Filter.SubSpaceFlag && ...
   isfield(RFE.Filter,'EnsembleStrategy') && ~isempty(RFE.Filter.EnsembleStrategy)
    EnsStrat = RFE.Filter.EnsembleStrategy;
end

% Normalize DiversitySource
if ~isfield(EnsStrat,'DiversitySource') || isempty(EnsStrat.DiversitySource)
    if strcmpi(MODEFL,'classification'), EnsStrat.DiversitySource = 'entropy';
    else,                                EnsStrat.DiversitySource = 'regvar';
    end
end
divsrc = lower(EnsStrat.DiversitySource);

% Compute size of multi-group and binary arrays to avoid dynamic memory allocation
% This significantly improves code execution performance
Ydims = nk_GetCV2EnsembleDims(F); 
if nF ~= nclass
    sYdims = Ydims*nclass;
elseif RAND.Decompose == 9
    sYdims = Ydims*ngroups;
else
    sYdims = sum(Ydims); 
end
if iscell(TS{1,1})
    Xdims = size(TS{1,1}{1},1);
else
    Xdims = size(TS{1,1},1);
end
% Initialize buffers
mDTs = zeros(Xdims, sYdims); mTTs = mDTs; mWTs = ones(1, sYdims); Classes = zeros(1,sYdims);
mcolend = 0; mcolX = 1;

% Check if detrending should be applied after label prediction
if exist('detrend','var') && ~isempty(detrend)
    detrendfl = true;
else
    detrendfl = false;
end

for k=1:iy % Loop through CV1 permutations

    for l=1:jy % Loop through CV1 folds
        
        for curclass = 1:nclass % Loop through dichotomizers
            
            %%%%%%%%%%%%%%%% DATA EXTRACTION %%%%%%%%%%%%%%%%
            % Extract CV2 test data
            % Binary decomposition mode during preprocessing
            if iscell(TS{k,l}) && numel(TS{k,l}) == nclass 
                if ~isempty(mTSInd)
                    if iscell(mTSInd{k,l})
                        XTest = TS{k,l}{curclass}(mTSInd{k,l}{curclass},:); 
                    else
                        XTest = TS{k,l}{curclass}(mTSInd{k,l},:); 
                    end
                else
                    XTest = TS{k,l}{curclass}; 
                end
            % Multigroup mode during preprocessing
            elseif iscell(TS{k,l}) 
                if ~isempty(mTSInd)
                    if iscell(mTSInd{k,l})
                        XTest = TS{k,l}{1}(mTSInd{k,l}{curclass},:); 
                    else
                        XTest = TS{k,l}{1}(mTSInd{k,l},:); 
                    end
                else
                    XTest = TS{k,l}{1}; 
                end
            % Regression mode
            else
                if ~isempty(mTSInd)
                    if iscell(mTSInd{k,l})
                        XTest = TS{k,l}(mTSInd{k,l}{curclass},:);
                    else
                        XTest = TS{k,l}(mTSInd{k,l},:);
                    end
                else
                    XTest = TS{k,l};
                end
            end
            
            % Extract CV1 training data
            if iscell(TR{k,l}) && numel(TR{k,l}) == nclass
                if ~isempty(TRInd) 
                    if iscell(TRInd{k,l})
                        XTrain = TR{k,l}{curclass}(TRInd{k,l}{curclass},:); 
                    else
                        XTrain = TR{k,l}{curclass}(TRInd{k,l},:); 
                    end
                else
                    XTrain = TR{k,l}{curclass}; 
                end
            elseif iscell(TR{k,l}) 
                if ~isempty(TRInd) 
                    if iscell(TRInd{k,l})
                        XTrain = TR{k,l}{1}(TRInd{k,l}{curclass},:); 
                    else
                        XTrain = TR{k,l}{1}(TRInd{k,l},:); 
                    end
                else
                    XTrain = TR{k,l}{1}; 
                end
            else
                if ~isempty(TRInd)
                    if iscell(TRInd{k,l})
                        XTrain = TR{k,l}(TRInd{k,l}{curclass},:);
                    else
                        XTrain = TR{k,l}(TRInd{k,l},:);
                    end
                else
                    XTrain = TR{k,l};
                end
            end
            
            %Extract CV1 test data
            if iscell(CVD{k,l}) && numel(CVD{k,l}) == nclass
                if ~isempty(CVDInd) 
                    if iscell(CVDInd{k,l})
                        XCV = CVD{k,l}{curclass}(CVDInd{k,l}{curclass},:); 
                    else
                        XCV = CVD{k,l}{curclass}(CVDInd{k,l},:); 
                    end
                else
                    XCV = CVD{k,l}{curclass}; 
                end
            elseif iscell(CVD{k,l})
                if ~isempty(CVDInd) 
                    if iscell(CVDInd{k,l})
                        XCV = CVD{k,l}{1}(CVDInd{k,l}{curclass},:); 
                    else
                        XCV = CVD{k,l}{1}(CVDInd{k,l},:); 
                    end
                else
                    XCV = CVD{k,l}{1}; 
                end
            else
                if ~isempty(CVDInd)
                    if iscell(CVDInd{k,l})
                        XCV = CVD{k,l}(CVDInd{k,l}{curclass},:);
                    else
                        XCV = CVD{k,l}(CVDInd{k,l},:);
                    end
                else
                    XCV = CVD{k,l};
                end
            end
            % Extract CV1 test labels
            %YCV = dCVDLabel{k,l}{curclass}(:,MULTILABEL.curdim);
            Ydum = zeros(size(XTest,1),1);
            if RFE.ClassRetrain
               XTrain = [XTrain; XCV]; %YTrain = [YTrain; YCV]; 
            end
            
            if nF == 1
                ul = size(F{k,l},2); Fkl = F{k,l};
            else
                ul = size(F{k,l,curclass},2); Fkl = F{k,l,curclass}; 
            end
            
            %%%%%%%%%%%%%%%% GET FEATURE SUBSPACE MASK %%%%%%%%%%%%%%%%
            if ~islogical(Fkl), Fkl = Fkl ~= 0; end
            
            Mkl = MD{k,l,curclass};
            
            %%%%%%%%%%%%%%%%%%% PREDICT TEST DATA %%%%%%%%%%%%%%%%%%%%%
            if VERBOSE 
                switch MODEFL
                    case 'classification'
                        if RAND.Decompose ~= 9
                            fprintf('\nPredicting data in CV1 [%g,%g], classifier #%g (%s), %g models.', ...
                                k, l, curclass, CV.class{1,1}{curclass}.groupdesc, ul); 
                        else
                            fprintf('\nPredicting data in CV1 [%g,%g], multi-group classifier, %g models.', ...
                                k, l, ul); 
                        end
                    case 'regression'
                        fprintf('\nPredicting data in CV1 [%g,%g], regressor, %g models.', ...
                        k, l, ul); 
                end
            end
            
            if detrendfl
               [ tsT, tsD ] = nk_ApplyDetrend(XTest, Ydum, XTrain, Mkl, Fkl, detrend, curclass);
            else
               [~, tsT, tsD, Mkl] = nk_GetTestPerf(XTest, Ydum, Fkl, Mkl, XTrain, 1, mnclass);
            end
               
            Predict.binCV1Predictions{k,l,curclass} = tsD;
            switch SVM.prog
                case 'SEQOPT'
                    for u=1:size(tsD,2)
                        Predict.binCV1CasePropagations{k,l,curclass} = [Predict.binCV1CasePropagations{k,l,curclass} Mkl{u}.Nremain_test];
                        Predict.binCV1PerformanceIncreases{k,l,curclass} = [Predict.binCV1PerformanceIncreases{k,l,curclass}; Mkl{u}.SeqPerfGain_test];
                    end
                    Predict.binCV1DecValTraj{k,l,curclass} = Mkl{u}.optDh;
                case 'WBLCOX'
                    mdthresh = zeros(size(tsD,2),1);
                    for u=1:size(tsD,2)
                        Predict.binCV1times{k,l,curclass} = [ Predict.binCV1times{k,l,curclass} Mkl{u}.predicted_time]; 
                        mdthresh(u) = Mkl{u}.cutoff.prob;
                    end
                    Predict.binCV1probthresh(k,l,curclass) = nm_nanmedian(mdthresh);
            end
            % Extract learner weights for this (k,l,curclass); keep predictions RAW
            Wkl = [];
            if ~isempty(W)
                if nW == 1
                    if ~isempty(W{k,l}),          Wkl = W{k,l}(:);          end
                else
                    if ~isempty(W{k,l,curclass}), Wkl = W{k,l,curclass}(:); end
                end
            end
            % Normalize defensively (no effect if already simplex)
            if ~isempty(Wkl)
                Wkl = max(Wkl,0); s = sum(Wkl);
                if s > 0, Wkl = Wkl ./ s; end
            end
            
            % Compute binary performance on CV2 test data for current CV1 partition
            if ~isempty(tsD) 
                dtsD = tsD(dTSInd{curclass},:,:); 
            else
                tsD = 0; tsT = 0; dtsD = [];
            end
            
            switch RAND.Decompose
                case 9
                    perf = nan(ul,mnclass);
                otherwise
                    perf = nan(ul,1);
            end
            
            for u=1:ul
                for v=1:mnclass
                    if isempty(dtsD)
                        perf(u,v) = 0;
                    else
                        offs =0; if strcmp(SVM.prog,'WBLCOX'), offs =  Mkl{u}.cutoff.prob; end
                        if RAND.Decompose == 9
                            tsL = zeros(size(dTSLabel{curclass}));
                            tsL(dTSLabel{curclass} == mnclass) = 1; tsL(tsL==0) = -1;
                        else
                            tsL = dTSLabel{curclass}(:,MULTILABEL.curdim);
                        end
                        if ~nnz(isfinite(dtsD(:,u,v))),continue; end
                        perf(u,v) = EVALFUNC(tsL, dtsD(:,u,v)-offs);
                    end
                end
            end
            if RAND.Decompose == 9
                if ~mcolend
                    mcolX = 1;
                else
                    mcolX = mcolend+1;
                end
                for m_curclass = 1:mnclass
                    Predict.binCV1Performance(k,l,m_curclass) = nm_nanmean(perf(:,m_curclass));
                    [mDTs, mTTs, mWTs, Classes, ~, mcolend] = ...
                        nk_MultiAssemblePredictions( tsD(:,:,m_curclass), tsT(:,:,m_curclass), Wkl, mDTs, mTTs, mWTs, Classes, ul, m_curclass, mcolend );
                end
            else
                Predict.binCV1Performance(k,l,curclass) = nm_nanmean(perf);
                % Multi-group CV2 array construction
                [mDTs, mTTs, mWTs, Classes, mcolstart, mcolend] = ...
                    nk_MultiAssemblePredictions( tsD, tsT, Wkl, mDTs, mTTs, mWTs, Classes, ul, curclass, mcolend );
                if curclass == 1, mcolX = mcolstart; end
            end
        end
        
        % Compute multi-group performance on CV2 test data for current CV1 partition
        if MULTI.flag
            [Predict.MultiCV1Performance(k,l), Predict.MultiCV1Predictions{k,l}, Predict.MultiCV1Probabilities{k,l}] = ...
                nk_MultiEnsPerf(mDTs(:,mcolX:mcolend), ...
                mTTs(:,mcolX:mcolend), ...
                mTSLabel(:,MULTILABEL.curdim), ...
                Classes(:,mcolX:mcolend), ngroups);
        end
    end
end

% ScaleFlag = false;

% Compute CV2 ensemble binary performance for current CV2 partition
for curclass = 1 : nclass
    
    % Extract current dichotomization decision from (multi-group) array
    indCurClass = Classes == curclass;
    if isempty(dTSInd{curclass}) 
        Predict.binCV2Performance_Targets(curclass) = NaN;
        Predict.binCV2Performance_DecValues(curclass) = NaN;   
        Predict.binCV2Diversity_Targets(curclass) = NaN;
        Predict.binCV2Diversity_DecValues(curclass) = NaN;
        Predict.binCV2Predictions_Targets{curclass} = NaN;
        Predict.binCV2Predictions_DecValues{curclass} = NaN;
        continue; 
    end 
    dDTs = mDTs(dTSInd{curclass},indCurClass);
    dTTs = mTTs(dTSInd{curclass},indCurClass);
    perf = Predict.binCV1Performance(:,:,curclass);
    Predict.binCV1Performance_Mean(1,curclass) = nm_nanmean(perf(:));
    Predict.binCV1Performance_SD(1,curclass) = nm_nanstd(perf(:));
    
    % Compute diversity metrics using the raw values
    DTsign = sign(dDTs); 
    Predict.binCV2Diversity_Targets(curclass)   = nk_ComputeDiversityScore(dTTs, dTSLabel{curclass}(:,MULTILABEL.curdim), divsrc);
    if strcmpi(divsrc,'regvar')
        Predict.binCV2Diversity_DecValues(curclass) = nk_ComputeDiversityScore(dDTs, dTSLabel{curclass}(:,MULTILABEL.curdim), 'regvar');
    else
        Predict.binCV2Diversity_DecValues(curclass) = nk_ComputeDiversityScore(DTsign, dTSLabel{curclass}(:,MULTILABEL.curdim), divsrc);
    end

    dW = mWTs(1, indCurClass);          % 1×#models for this dichotomizer
    % normalize defensively; if all ones, it remains ones
    dW = max(dW, 0); s = sum(dW); if s > 0, dW = dW ./ s; end

    switch MODEFL

        case 'classification'
            
            switch RAND.Decompose
                
                case 9 % Multi-group classifier
                    
                    [hrx, ~, hdx] = nk_MultiDecideMulti(mTTs, dTSLabel, Classes, ngroups);
                    
                otherwise

                    if size(dTTs,2) < 2
                        hrx = dTTs; hdx = dDTs;
                    else
                        switch ENSMETHOD
                            case 1  % simple majority (now weighted-median + tie-break)
                                % Decision scores (soft): weighted median per row
                                hdx = nk_WeightedMedianRows(dDTs, dW);   % n_subj × 1
                    
                                % Hard labels: weighted median on {-1,+1} or {0,1}
                                vals = unique(dTTs(~isnan(dTTs)));
                                if all(ismember(vals, [-1 1]))
                                    hmed = nk_WeightedMedianRows(dTTs, dW);
                                    hrx  = sign(hmed);
                                    z = (hrx==0);
                                    if any(z), hrx(z) = sign(hdx(z)); end     % tie-break with soft
                                else
                                    % {0,1} encoding
                                    hmed = nk_WeightedMedianRows(dTTs, dW);
                                    hrx  = double(hmed >= 0.5);
                                    z = (hmed==0.5 | isnan(hmed));
                                    if any(z), hrx(z) = double(hdx(z) >= 0); end
                                end
                    
                            case 2  % product vote 
                                hrx = sign(prod(dTTs,2));
                                hdx = prod(dDTs,2);
                    
                            case 3  % ECOC 
                                coding=1; decoding=1;
                                classes = ones(1,size(dTTs,2));
                                hrx = nk_ErrorCorrOutCodes(dTTs, classes, coding, decoding);
                                hrx(hrx==2) = -1; hdx = hrx;
                        end
                    end
            end
            % Check for zeros
            if sum(hrx==0) > 0 % Throw coin
                hrx = nk_ThrowCoin(hrx);
            end 
            
            Predict.binCV2Performance_Targets(curclass) = EVALFUNC(dTSLabel{curclass}(:,MULTILABEL.curdim), hrx);
            mdcutoff=0; if strcmp(SVM.prog,'WBLCOX'), probthresh = Predict.binCV1probthresh(:,:,curclass); mdcutoff = nm_nanmedian(probthresh(:)); end
            Predict.binCV2Performance_DecValues(curclass) = EVALFUNC(dTSLabel{curclass}(:,MULTILABEL.curdim), hdx-mdcutoff);

            % Keep for plotting
            Predict.DiversitySource = divsrc;

        case 'regression'

            if size(dTTs,2) < 2
                hrx = dTTs; hdx = dDTs;
            else
                hdx = nk_WeightedMedianRows(dDTs, dW);   
                hrx = hdx;
            end
            Predict.binCV2Performance_Targets(curclass) = EVALFUNC(dTSLabel{curclass}(:,MULTILABEL.curdim), hrx);
            Predict.binCV2Performance_DecValues(curclass) = Predict.binCV2Performance_Targets(curclass);
    end
    
    Predict.binCV2Predictions_Targets{curclass} = hrx;
    Predict.binCV2Predictions_DecValues{curclass} = hdx;
    
end

% Compute CV2 ensemble multi-group performance and class membership
if MULTI.flag  
    [Predict.MultiCV2Performance, Predict.MultiCV2Predictions, Predict.MultiCV2Probabilities] = ...
                nk_MultiEnsPerf(mDTs, mTTs, mTSLabel(:,MULTILABEL.curdim), Classes, ngroups );
    Predict.MultiCV2Diversity_Targets = nm_nanmean(Predict.binCV2Diversity_Targets);
    Predict.MultiCV2Diversity_DecValues = nm_nanmean(Predict.binCV2Diversity_DecValues);
end

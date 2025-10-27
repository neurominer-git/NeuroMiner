function [GD, MD, DISP] = nk_GridSearchHelper(GD, MD, DISP, idx_selected, nclass, ngroups, CV1PerfData, CV2PerfData, models)

global VERBOSE MULTI CV BATCH SVM MODEFL W2AVAIL RAND MULTILABEL RFE SAV DEBUG

%%%%%% TRANSFER RESULTS TO GD :

if (SAV.savemodel && (exist('models','var') && ~isempty(models))) || (~isempty(DEBUG) && DEBUG.optmodel)
    MD{idx_selected} = models;
end

pos2 = []; pos3 = [];
hasComplexity = false;
if any(contains({'LIBSVM','MikRVM', 'MKLRVM', 'MVTRVR'}, SVM.prog))
    hasComplexity = true;
end

%% CV1 test data performance
% binary

CV2Param = RFE.CV2Class;
if RFE.Wrapper.flag 
    Param = RFE.Wrapper;
else
    Param = RFE.Filter;
end

if isfield(Param,'EnsembleStrategy')
    Metric = Param.EnsembleStrategy.Metric;
else
    Metric = CV2Param.EnsembleStrategy.Metric;
end

DISP.nclass = nclass; LCOstr = '';

curlabel = MULTILABEL.curdim;

if MULTILABEL.dim > 1
    if RFE.Wrapper.flag
        Perf = CV1PerfData{curlabel}.Wrapper;
    else
        Perf = CV1PerfData{curlabel}.Filter;
    end
    CV2Perf = CV2PerfData{curlabel};
else
    if RFE.Wrapper.flag
        Perf = CV1PerfData.Wrapper;
    else
        Perf = CV1PerfData.Filter;
    end
    CV2Perf = CV2PerfData;
end

switch Metric

    case 1 % Mean of ensembles (Targets)

        GD.TR(idx_selected,:,curlabel) = Perf.MeanCVHTperf;
        GD.sTR(idx_selected,:,curlabel) = Perf.SDCVHTperf;

    case 2 % Mean of ensembles (Decision Values)

        GD.TR(idx_selected,:,curlabel) = Perf.MeanCVHDperf;
        GD.sTR(idx_selected,:,curlabel) = Perf.SDCVHDperf;

end

if (Param.flag && Param.SubSpaceFlag ) && (isfield(Param,'EnsembleStrategy') && Param.EnsembleStrategy.type ~= 9 )

    GD.M_DivT(idx_selected,:,curlabel)    = Perf.Ens_MeanTrDiv;
    GD.SD_DivT(idx_selected,:,curlabel)   = Perf.Ens_SDTrDiv;
    GD.M_DivV(idx_selected,:,curlabel)    = Perf.Ens_MeanCVDiv;
    GD.SD_DivV(idx_selected,:,curlabel)   = Perf.Ens_SDCVDiv;
    hasDiversity = true;     
else
    hasDiversity = false;
end

% multi-group:
if MULTI.flag

   GD.MultiCV1TrPred{idx_selected,curlabel}       = Perf.MultiTrPredictions;
   GD.MultiCV1CVPred{idx_selected,curlabel}       = Perf.MultiCVPredictions;
   GD.MultiTR(idx_selected,curlabel)              = Perf.MeanMultiCVPerf; 
    switch CV2Param.type 
        case 1 % mean of CV1 ensemble
            GD.MultiTS(idx_selected,curlabel) = mean(CV2Perf.MultiCV1Performance(:));
        case 2 % Ensemble of ensembles
            GD.MultiTS(idx_selected,curlabel) = CV2Perf.MultiCV2Performance;
    end
    GD.MultiCV2Div(idx_selected,curlabel) = CV2Perf.MultiCV2Diversity_Targets;
    GD.MultiCV2DivDec(idx_selected,:,curlabel) = CV2Perf.MultiCV2Diversity_DecValues;
    GD.MultiCV2Pred{idx_selected,curlabel}   = CV2Perf.MultiCV2Predictions;
    GD.MultiCV2Prob{idx_selected,curlabel}   = CV2Perf.MultiCV2Probabilities;
    GD.MultiCV1Pred{idx_selected,curlabel}   = nk_cellcat(CV2Perf.MultiCV1Predictions,[],2);
    for g=1:ngroups
        F = repmat({g}, size(CV2Perf.MultiCV1Probabilities));
        GD.MultiCV1Prob{idx_selected,g,curlabel} = nk_cellcat(CV2Perf.MultiCV1Probabilities, [], 2, F);
    end
    GD.MultiERR(idx_selected,curlabel)    = GD.MultiTR(idx_selected) - GD.MultiTS(idx_selected);

   if hasDiversity
        GD.MultiM_DivT(idx_selected,curlabel)     = Perf.Ens_MeanMultiTrDiv;
        GD.MultiSD_DivT(idx_selected,curlabel)    = Perf.Ens_SDMultiTrDiv;
        GD.MultiM_DivV(idx_selected,curlabel)     = Perf.Ens_MeanMultiCVDiv;
        GD.MultiSD_DivV(idx_selected,curlabel)    = Perf.Ens_SDMultiCVDiv;
   end
end

%% CV2 test data performance
% binary:
switch CV2Param.type
    case 1
        % Mean of CV1 ensemble
        GD.TS(idx_selected,:,curlabel) = CV2Perf.BinCV1Performance_Mean;
    case 2
        % Ensemble of ensemble decision
        switch Metric                                     
            case 1
                GD.TS(idx_selected,:,curlabel) = CV2Perf.binCV2Performance_Targets;
            case 2
                GD.TS(idx_selected,:,curlabel) = CV2Perf.binCV2Performance_DecValues;
        end
end

% Decision values / Probabilities on CV2 test data
GD.DS{idx_selected,curlabel}          = CV2Perf.binCV1Predictions;
GD.BinPred{idx_selected,curlabel}     = CV2Perf.binCV2Predictions_DecValues;
GD.CV2Div(idx_selected,:,curlabel)    = CV2Perf.binCV2Diversity_Targets;
GD.CV2DivDec(idx_selected,:,curlabel) = CV2Perf.binCV2Diversity_DecValues;

% Model params
GD.FEAT{idx_selected,curlabel}        = Perf.SubSpaces;
if hasDiversity
    GD.Weights{idx_selected,curlabel} = Perf.Weights;
end
GD.DT{idx_selected,curlabel}          = Perf.TrDecisionValues;
GD.DV{idx_selected,curlabel}          = Perf.CVDecisionValues;
GD.C(idx_selected,:,curlabel)         = Perf.ModelComplexity.Complex;

if W2AVAIL
    GD.W2{idx_selected,curlabel}          = Perf.w2;
    GD.Md{idx_selected,curlabel}          = Perf.Md;
    GD.Mm{idx_selected,curlabel}          = Perf.Mm;
    GD.mMd(idx_selected,:,curlabel)       = mean(cellcat(GD.Md{idx_selected,curlabel}));
end

% Compute generalization error for current binary comparison
GD.ERR(idx_selected,:,curlabel) = GD.TR(idx_selected,:,curlabel) - GD.TS(idx_selected,:,curlabel);

switch SVM.prog
    case 'SEQOPT'
        for curclass = 1:nclass
           GD.mSEQI{idx_selected, curclass, curlabel}      = Perf.MeanCritGain(curclass,:);
           GD.sdSEQI{idx_selected, curclass, curlabel}     = Perf.SDCritGain(curclass,:);
           GD.mSEQE{idx_selected, curclass, curlabel}      = Perf.MeanExamFreq(curclass,:);  
           GD.sdSEQE{idx_selected, curclass, curlabel}     = Perf.SDExamFreq(curclass,:); 
           GD.mSEQAbsThrU{idx_selected, curclass, curlabel} = Perf.MeanAbsThreshU(curclass,:);
           GD.sdSEQAbsThrU{idx_selected, curclass, curlabel} = Perf.SDAbsThreshU(curclass,:);
           GD.mSEQAbsThrL{idx_selected, curclass, curlabel} = Perf.MeanAbsThreshL(curclass,:);
           GD.sdSEQAbsThrL{idx_selected, curclass, curlabel} = Perf.SDAbsThreshL(curclass,:);
           GD.mSEQPercThrU{idx_selected, curclass, curlabel} = Perf.MeanPercThreshU(curclass,:);
           GD.sdSEQPercThrU{idx_selected, curclass, curlabel} = Perf.SDPercThreshU(curclass,:);
           GD.mSEQPercThrL{idx_selected, curclass, curlabel} = Perf.MeanPercThreshL(curclass,:);
           GD.sdSEQPercThrL{idx_selected, curclass, curlabel} = Perf.SDPercThreshL(curclass,:);
           GD.CasePropagations{idx_selected, curclass, curlabel} = nk_cellcat(CV2Perf.binCV1CasePropagations(:,:,curclass),[],2);
           GD.SeqPerfIncreases{idx_selected, curclass, curlabel} = nk_cellcat(CV2Perf.binCV1PerformanceIncreases(:,:,curclass),[],1);
           GD.DecValTraj{idx_selected,curclass,curlabel} = cat(3,CV2Perf.binCV1DecValTraj{:,:,curclass});
        end
    case 'WBLCOX'
        for curclass=1:nclass
           GD.mCutOffPerc(idx_selected, curclass, curlabel) = Perf.MeanThreshPerc(curclass,:);
           GD.sdCutOffPerc(idx_selected, curclass, curlabel) = Perf.SDThreshPerc(curclass,:);
           GD.mCutOffProb(idx_selected, curclass, curlabel) = Perf.MeanThreshProb(curclass,:);
           GD.sdCutOffProb(idx_selected, curclass, curlabel) = Perf.SDThreshProb(curclass,:);
           GD.CV1predictedtimes{idx_selected,curlabel} = Perf.PredictedTimes(:,:,curclass);
           GD.CV2predictedtimes{idx_selected,curlabel} = CV2Perf.binCV1times(:,:,curclass);
           GD.CV2Cutoffs{idx_selected,curlabel} = CV2Perf.binCV1probthresh(:,:,curclass);
        end            
end

%%%%% OPTIONALLY, PRINT INFO TO FIGURE:
% Create multi-group bar chart of current results

if ~BATCH 

    if isfield(RAND,'CV2LCO') && ~isempty(RAND.CV2LCO), LCOstr = '_{LGO}'; end

    lefti = 0.10; wideelse = 0.15; sz = get( 0, 'Screensize' ); figuresz = sz;
    switch MODEFL
        case 'classification'
            for p = 1:DISP.nclass
                lg_long{p} = sprintf('M #%g: %s',p, CV.class{1,1}{p}.groupdesc);
                lg_short{p} = sprintf('M #%g',p);
            end
        case 'regression'
            lg_long{1} = sprintf('M #%g: %s',1,'Regression');
            lg_short{1} = sprintf('M #%g',1);
    end
    % Create position vectors depending on MULTI and hasDiversity
    if MULTI.flag
        figuresz(end) = 0.8*sz(end);
        height  = 0.35; bottom  = 0.47;
        bottomm = 0.05; 
    else
        figuresz(end) = 0.6*sz(end);
        height = 0.70; bottom = 0.1;
    end

    if hasDiversity
        figuresz(end-1) = 0.75*sz(end-1);
        if hasComplexity
            widthperf = 0.45;
            pos1 = [lefti   bottom  widthperf    height];   % Performance axes
            pos2 = [0.60    bottom  wideelse     height];   % Complexity axes
            pos3 = [0.80    bottom  wideelse     height];   % Diversity axes
        else
            widthperf = 0.65;
            pos1 = [lefti   bottom  widthperf    height];   % Performance axes
            pos3 = [0.80    bottom  wideelse     height];   % Diversity axes
        end
    else
        figuresz(end-1) = 0.5*sz(end-1);
        if hasComplexity
            widthperf = 0.65;
            pos1 = [lefti   bottom  widthperf    height];   % Performance axes
            pos2 = [0.80    bottom  wideelse     height];   % Complexity axes
        else
            widthperf = 0.85;
            pos1 = [lefti   bottom  widthperf    height];   % Performance axes
        end
    end

    if MULTI.flag
        if hasDiversity
            widthperf = 0.65;
            posm2 = [ 0.8 bottomm wideelse height ];
        else
            widthperf = 0.85;
            posm2 = [];
        end
        posm1 = [ lefti bottomm widthperf height ];  %
    end
    DISP.figuresz = figuresz;
    ex = '';
    if strcmp(MODEFL,'classification')
        ex = ' (D)'; 
        switch Metric
            case 1
                ex = ' (T)';
            case 2
                if SVM.RVMflag , ex = ' (P)'; end
        end
    end
    switch Metric
        case 1
            meanvec = [ Perf.MeanTrHTperf ; Perf.MeanCVHTperf;  CV2Perf.binCV1Performance_Mean; CV2Perf.binCV2Performance_Targets ];
            stdvec  = [ Perf.SDTrHTperf; Perf.SDCVHTperf; CV2Perf.binCV1Performance_SD; zeros(1,numel(Perf.SDTrHTperf)) ];
        case 2
            meanvec = [ Perf.MeanTrHDperf ; Perf.MeanCVHDperf;  CV2Perf.binCV1Performance_Mean; CV2Perf.binCV2Performance_DecValues ];
            stdvec  = [ Perf.SDTrHDperf; Perf.SDCVHDperf; CV2Perf.binCV1Performance_SD; zeros(1,numel(Perf.SDTrHDperf)) ];   
    end
    xaxlb = { sprintf('Mean Tr%s',ex), sprintf('Mean CV_{1}%s',ex), sprintf('Mean CV_{2}%s',ex), sprintf('Ensemble CV_{2}%s%s', LCOstr, ex)};
    
    % Complexity
    meanc       = GD.C(idx_selected,:);
    stdc        = zeros(size(meanc));
    if DISP.nclass > 1
         meanc=[meanc;zeros(1,DISP.nclass)];
         stdc = [stdc;zeros(1,DISP.nclass)];
    end
    xaxc        = ' ';
    DISP.ax{1}.val_y = meanvec;
    DISP.ax{1}.std_y = stdvec;
    DISP.ax{1}.label = xaxlb;
    [DISP.ax{1}.ylm, DISP.ax{1}.ylb] = nk_GetScaleYAxisLabel(SVM);
    DISP.ax{1}.fc = rgb("DeepSkyBlue"); 
    DISP.ax{1}.title = 'Ensemble Performance';
    DISP.ax{1}.position = pos1;
    DISP.ax{1}.lg = lg_long;

    if hasComplexity
        DISP.ax{2}.val_y = meanc;
        DISP.ax{2}.std_y = stdc;
        DISP.ax{2}.label = xaxc;
        DISP.ax{2}.ylm = [0 100]; DISP.ax{2}.ylb = ' ';
        DISP.ax{2}.fc = rgb('Coral');
        DISP.ax{2}.title = 'Complexity';
        DISP.ax{2}.position = pos2;
        DISP.ax{2}.lg = [];
        cnt=3;
    else
        cnt=2;
    end

    if hasDiversity % Ensemble method
        meandiv = zeros(2,nclass); stddiv=zeros(2,nclass);
        meandiv(1,:)         = Perf.Ens_MeanCVDiv;
        meandiv(2,:)         = CV2Perf.binCV2Diversity_Targets;
        stddiv(1,:)          = Perf.Ens_SDCVDiv;
        xaxdiv             = {'Div CV1',         'Div CV2'};

        DISP.ax{cnt}.val_y = meandiv;
        DISP.ax{cnt}.std_y = stddiv;
        DISP.ax{cnt}.label = xaxdiv;
        DISP.ax{cnt}.ylm = [0 1]; 
        DISP.ax{cnt}.fc = 'g';
        if isfield(Param.EnsembleStrategy,'DivStr')
            DISP.ax{cnt}.ylb = Param.EnsembleStrategy.DivStr;
        else
            DISP.ax{cnt}.ylb = ' ';
        end
        DISP.ax{cnt}.title = 'Ensemble Diversity';
        DISP.ax{cnt}.position = pos3;
        DISP.ax{cnt}.lg = [];
    end

    if MULTI.flag
         %%%%% OPTIONALLY, PRINT INFO TO FIGURE:
         % Create multi-group bar chart of current results
         if ~MULTILABEL.flag

            DISP.m_ax{1}.val_y = [ Perf.MeanMultiTrPerf   Perf.MeanMultiCVPerf    mean(CV2Perf.MultiCV1Performance(:)) CV2Perf.MultiCV2Performance];
            DISP.m_ax{1}.std_y = [ Perf.SDMultiTrPerf     Perf.SDMultiCVPerf      std(CV2Perf.MultiCV1Performance(:))  0]; 
            DISP.m_ax{1}.label = {'Mean Tr',              'Mean CV1',             'Mean CV2',                          'Ensemble CV2'};
            DISP.m_ax{1}.ylm   = [0 100];
            if SVM.GridParam == 14
                DISP.m_ax{1}.ylb = 'Average Binary BAC [%]'; 
            else
                DISP.m_ax{1}.ylb = 'Mulit-Class Accuracy [%]'; 
            end
            DISP.m_ax{1}.title = 'Multi-Class Performance';
            DISP.m_ax{1}.position = posm1;
            DISP.m_ax{1}.lg = [];
            if hasDiversity
                DISP.m_ax{2}.val_y  = [GD.MultiM_DivT(idx_selected)         GD.MultiM_DivV(idx_selected)         GD.MultiCV2Div(idx_selected)];
                DISP.m_ax{2}.std_y  = [GD.MultiSD_DivT(idx_selected)        GD.MultiSD_DivV(idx_selected)        0]; 
                DISP.m_ax{2}.label  = {'Tr Div','CV1 Div', 'CV2 Div'};
                DISP.m_ax{2}.ylm    = [0 1];
                DISP.m_ax{2}.ylb    = 'Entropy'; 
                DISP.m_ax{2}.title = 'Multi-Class Diversity';
                DISP.m_ax{2}.position = posm2;
                DISP.m_ax{2}.lg = [];
            end
         end
     end
     DISP = nk_PrintCV2BarChart(DISP, MULTI.flag);
end

if VERBOSE && ~MULTILABEL.flag
    for curclass=1:nclass% Print some info on the screen   
        fprintf('\nPerformance measures at parameter(s)')

        P_str = nk_DefineMLParamStr(DISP.P{curclass}, DISP.Pdesc, curclass);
        fprintf(' [%s]',P_str);

        switch MODEFL
            case 'classification'
                if RAND.Decompose ~=9
                     fprintf('\n%s: CV1 = %1.2f, CV2 = %1.2f, Complexity = %1.2f', CV.class{1,1}{curclass}.groupdesc, ...
                         GD.TR(idx_selected,curclass,curlabel), GD.TS(idx_selected,curclass,curlabel), GD.C(idx_selected,curclass,curlabel));
                else
                     fprintf('\nMulti-group: CV1 = %1.2f, CV2 = %1.2f, Complexity = %1.2f', ...
                     GD.TR(idx_selected,curclass,curlabel), GD.TS(idx_selected,curclass,curlabel), GD.C(idx_selected,curclass,curlabel));
                end
            case 'regression'
                 fprintf('\nRegression: CV1 = %1.2f, CV2 = %1.2f, Complexity = %1.2f', ...
                     GD.TR(idx_selected,curclass,curlabel), GD.TS(idx_selected,curclass,curlabel), GD.C(idx_selected,curclass,curlabel));
        end
    end

    if MULTI.flag
        fprintf('\nMulti-Group: CV1 = %1.2f, CV2 = %1.2f, Complexity = %1.2f', ...
            GD.MultiTR(idx_selected), GD.MultiTS(idx_selected), mean(GD.C(idx_selected,:)));
    end
end

% ___________________________________
function catarray = cellcat(arr, dim)

if nargin < 2, dim = 1; end
[ix,jx] = size(arr);
catarray = [];
for i=1:ix
    for j=1:jx
        switch dim 
            case 1
                catarray =[catarray; arr{i,j}];
            case 2
                catarray =[catarray arr{i,j}];
        end
    end
end
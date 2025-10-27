function r = rfe_algo_settings(Y, label, Ynew, labelnew, Ps, FullFeat, FullParam, ActStr)
%RFE_ALGO_SETTINGS Prepare wrapper-run settings (incl. adaptive wrapper config)
%
% This version centralizes the Adaptive Wrapper configuration so that the
% wrapper (rfe_forward_v2) can assume r.AdRef is fully populated.
%
% Inputs are unchanged.
%
% Output 'r' includes:
%   r.AdRef : struct with all adaptive-regularization knobs (manual+auto+stop),
%             ready to use in the wrapper.

global RFE VERBOSE SVM TRAINFUNC

% ------------------------- Base feature mask ------------------------------
r.FullInd = find(any(Y) & std(Y)~=0 & sum(isfinite(Y))~=0 & FullFeat==1);
r.Y      = Y(:,r.FullInd);
r.Ynew   = Ynew(:,r.FullInd);
r.YL     = label;
r.YnewL  = labelnew;
r.kFea   = numel(r.FullInd);

% Defaults used elsewhere
r.FeatRandPerc = 0;
r.FeatStepPerc = true;

% ------------------------- Wrapper type: Greedy --------------------------
switch RFE.Wrapper.type
    case 1
        %% Feature Sorting Mode
        if ~isfield(RFE.Wrapper.GreedySearch,'WeightSort') || isempty(RFE.Wrapper.GreedySearch.WeightSort)
            r.WeightSort = 1;
        else
            r.WeightSort = RFE.Wrapper.GreedySearch.WeightSort;
        end

        %% Feature block size settings
        kFea = length(r.FullInd);
        if ~isfield(RFE.Wrapper.GreedySearch,'FeatStepPerc')
            % No explicit setting -> make lperc such that effective step = 1
            switch RFE.Wrapper.GreedySearch.EarlyStop.Perc
                case 1
                    r.lperc = 1/(kFea/100); % translates to single-feature step
                case 2
                    r.lperc = ceil(kFea/100);
            end
            r.FeatStepPerc = false;
        elseif ~RFE.Wrapper.GreedySearch.FeatStepPerc
            r.lperc = 1; % single feature
        else
            r.lperc = RFE.Wrapper.GreedySearch.FeatStepPerc;
        end

        %% Early stopping → minimum #features
        r.MinNum = 1;
        if RFE.Wrapper.GreedySearch.EarlyStop.Thresh
           switch RFE.Wrapper.GreedySearch.EarlyStop.Perc
               case 1 % Percentage
                   r.MinNum = size(r.Y,2) / 100 * RFE.Wrapper.GreedySearch.EarlyStop.Thresh; 
               case 2 % Absolute
                   r.MinNum = RFE.Wrapper.GreedySearch.EarlyStop.Thresh;
           end
        end

        if isfield(RFE.Wrapper.GreedySearch,'FeatRandPerc')
            r.FeatRandPerc = RFE.Wrapper.GreedySearch.FeatRandPerc;
        end
        r.PercMode = RFE.Wrapper.GreedySearch.EarlyStop.Perc;
end

% ----------------------- Optimization criterion --------------------------
[r.evaldir, ~, r.optfunc, r.optparam, r.minmaxstr, ~, r.evaldir2] = nk_ReturnEvalOperator(SVM.GridParam);

% ----------------------- Full model performance ---------------------------
r.CritFlag = false;
if ~exist('FullParam','var') || isempty(FullParam)
    switch ActStr
        case 'Tr'
            r.T = r.Y;       r.L = label;
        case 'CV'
            r.T = r.Ynew;    r.L = labelnew;
        case 'TrCV'
            r.T = [r.Y; r.Ynew];
            r.L = [label; labelnew];
        case 'TrCVsep'
            r.T  = r.Y;     r.L  = label;
            r.TT = r.Ynew;  r.LL = labelnew;
            r.CritFlag = true;
            r.CritGap  = RFE.Wrapper.GreedySearch.CritGap.crit;
    end
    
    [~, r.FullModel] = TRAINFUNC(r.Y, label, 1, Ps);    
    if r.CritFlag
        r.FullParam      = nk_GetTestPerf(r.T,  r.L,  [], r.FullModel, r.Y);
        r.FullTestParam  = nk_GetTestPerf(r.TT, r.LL, [], r.FullModel, r.Y);
        r.FullParam      = (r.FullParam + r.FullTestParam) / 2;
    else
        r.FullParam      = nk_GetTestPerf(r.T,  r.L,  [], r.FullModel, r.Y);
    end

    if VERBOSE
        fprintf('\nFull model:\t# Features: %g, %s = %g', numel(r.FullInd), ActStr, r.FullParam)
    end
else
    r.FullParam = FullParam;
    r.FullModel = [];
end

% ----------------------- Knee point selection flag ------------------------
if isfield(RFE.Wrapper.GreedySearch,'KneePointDetection') && RFE.Wrapper.GreedySearch.KneePointDetection == 1
    r.KneePoint = true;
else
    r.KneePoint = false;
end

% ----------------------- Case-based forward (unchanged) -------------------
if isfield(RFE.Wrapper.GreedySearch,'CaseFrwd')
    r.CaseU    = RFE.Wrapper.GreedySearch.CaseFrwd.Upper;
    r.CaseL    = RFE.Wrapper.GreedySearch.CaseFrwd.Lower;
    r.CaseStep = RFE.Wrapper.GreedySearch.CaseFrwd.Step;
    r.CaseSpU  = r.CaseU(2):-1*round((r.CaseU(2)-r.CaseU(1))/r.CaseStep):r.CaseU(1);
    r.CaseSpL  = r.CaseL(1):round((r.CaseL(2)-r.CaseL(1))/r.CaseStep):r.CaseL(2);
end

[r.AdRef, r.Hist] = rfe_algo_settings_adaptive(RFE);

end

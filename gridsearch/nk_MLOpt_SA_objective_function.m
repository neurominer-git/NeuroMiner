function [score, GD, MD] = nk_MLOpt_SA_objective_function(GD, MD, Ps, Params_desc, combcell, curPsPos, nPsPos, mapY, algostr, f, d, npreml, nclass, ngroups)

% Calculate the performance of the model with a given configurationOOCV.
% This function should implement the evaluation of model based on selected config

%% Loop through binary learners and prepare learning params according to the algorithm chosen by the user
tic;
cPs = cell(nclass,1);
for curclass = 1:nclass
    DISP.P{curclass} = Ps{curclass};
    cPs{curclass} = nk_PrepMLParams(Ps{curclass}, Params_desc{curclass}, curPsPos);
end

%% Check whether new mapY container has to be retrieved
% Retrieve preprocessing parameter combinations and check whether
% there has been a parameter change from the previous to current
% parameter combination. The Ps array contains all hyperparameters
% for the optimization process. Some of the parameters may be
% related to the preprocessing stage, some to the proper ML
% optimization phase. "npreml" indicates how many preprocessing
% parameters belong to the preprocessing phase.
dimchng = false; i_dl = 1; m_dl = 1;

if npreml >-1
    if numel(nPsPos) > 1
        % Find the hyperparameters that belong to the preprocessing
        % phase
        if combcell
            % Current position in the hyperparameter space
            ipp     = cell2mat(Ps{1}(nPsPos(end),end-npreml:end));
            % Previous position in the hyperparameter space
            impp    = cell2mat(Ps{1}(nPsPos(end-1),end-npreml:end));
        else
            ipp     = Ps{1}(nPsPos(end),end-npreml:end);
            impp    = Ps{1}(nPsPos(end-1),end-npreml:end);
        end
        % Do we have a change between the previous and current
        % preprocessing hyperparameter position in the
        % preprocessing-related hyperparameter subspace? ...
        [~,i_dl] = ismember(ipp,pp,'rows');
        [~,m_dl] = ismember(impp,pp,'rows');
    else
        if combcell
            ipp     = cell2mat(Ps{1}(nPsPos,end-npreml:end));
        else
            ipp     = Ps{1}(nPsPos,end-npreml:end);
        end
        [~,i_dl] = ismember(ipp,pp,'rows');
        m_dl = i_dl;
    end
end

% ... if so, dimchng is set to true and thus we know that we have to
% retrieve new preprocessed data (mapYi) at the given hyperparameter 
% position from our preprocessed data container.
if i_dl ~= m_dl || (~exist('mapYi','var') || isempty(mapYi))
    dimchng = true;
end

%% Model training phase
if dimchng % now retrieve new mapYi from container
    mapYi = nk_MLOptimizer_ExtractDimMat(mapY, i_dl, cPs); 
    % ... and extract features according to filter mechanism (if
    % needed)
    FilterSubSets = nk_CreateSubSets(mapYi); 
end   

% Compute current model(s) for variable parameter combination P(curPsPos) = [ P1 P2 P3
% ... Pn] using the CV1 data partitions. Apply single or ensemble model
% to CV2 test sample in order to estimate the generalization 
% capacity of the classification / prediction rule    
[CV1perf, CV2perf, models] = nk_CVPermFold(mapYi, nclass, ngroups, cPs, FilterSubSets, batchflag);      

% Transfer results from CV1perf and CV2perf to GD
% structure using nk_GridSearchHelper2 function
[GD, MD, DISP] = nk_GridSearchHelper(GD, MD, DISP, curPsPos, nclass, ngroups, CV1perf, CV2perf, models);

if isfield(CV1perf,'detrend'), GD.Detrend{curPsPos} = CV1perf.detrend; end

%% Create variate mask according to selected features
if isfield(mapYi,'VI')

    [iy,jy] = size(CV(1).cvin{f,d}.TrainInd);
    
    GD.VI{curPsPos,curlabel} = cell(iy,jy,nclass);
    for k=1:iy
        for l=1:jy
            if iscell(mapYi.VI{k,l})
                 for curclass = 1:nclass
                    VI = repmat(mapYi.VI{k,l}{curclass},1,size(GD.FEAT{curPsPos,curlabel}{k,l,curclass},2));
                    GD.VI{curPsPos,curlabel}{k,l,curclass} = VI;
                 end
            else
                for curclass = 1:nclass
                    VI = repmat(mapYi.VI{k,l},1,size(GD.FEAT{curPsPos,curlabel}{k,l,curclass},2));
                    GD.VI{curPsPos,curlabel}{k,l,curclass} = VI;
                end
            end                            
        end
    end
    
end
fprintf(repmat('\b',1,numel(DISP.s))); 

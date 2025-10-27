% =========================================================================
% [ GD, MD ] = nk_MLOptimizer_ParamCycler(GD, MD, DISP, Ps, ...
%                           Params_desc, mapY, algostr, f, d, npreml, ...
%                           nclass, batchflag, PsSel, combcell)
% =========================================================================
% This child function of nk_MLOptimizer performs an extensive (brute-force)
% search of the parameter space as defined by the user.
% 
% Inputs:
% -------
% GD            : Results container
% MD            : Model container
% DISP          : Display structure with data for the NM Optimization Viewer
% Ps            : Parameter combinations to be visited
% Params_desc   : Descriptions of parameters
% mapY          : Structure containing CV1 training, CV1 test and CV2
%                 validation data
% algostr       : ML algorithm descriptor
% [ f, d ]      : Current outer (CV2) cross-validation partition
% npreml        : Number of preprocessing hyperparameters 
% nclass        : Number of binary classifiers | predictors
% batchflag     : batchmode (for HPC)
% PsSel         : Previously selected parameters nodes and data at that
%                 nodes
% combcell      : Flag indicating that Ps is a cell array rather than a
%                 numeric array of free parameters
%
% Outputs:
% --------
% GD (see above)
% MD (see above)
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris, 05/2024

function [ GD, MD, DISP ] = nk_MLOptimizer_ParamCycler(GD, MD, DISP, Ps, ...
                            Params_desc, mapY, algostr, f, d, npreml, ...
                            nclass, ngroups, batchflag, PsSel, combcell)

global CV MULTILABEL CVPOS VERBOSE

nPs = size(Ps{1},1);
% push current CV2 partition to global 
CVPOS.CV2p = f;
CVPOS.CV2f = d;

% Any free preprocessing parameters that we need to be aware of?
% => Retrieve the preprocessing-related hyperparameters and store them
% in pp
if npreml>-1
    if combcell
        pp = unique(cell2mat(Ps{1}(:,end-npreml:end)),'rows','stable');
    else
        pp = unique(Ps{1}(:,end-npreml:end),'rows','stable');
    end
end

% Do we have to deal with a multi-label situation?
nl = nk_GetLabelDim(MULTILABEL);

tElapsedSum = 0; 
tic; if nPs>1, fprintf('\n === Performing hyperparameter optimization === \n'); else, fprintf('\n'); end
     
% Loop through all available labels
for curlabel=1:nl
    visited_idx = []; labelstr = ''; 
    if MULTILABEL.flag
        if nl>1
            labelstr = sprintf('Label #%g: %s | ', MULTILABEL.sel(curlabel), MULTILABEL.desc{MULTILABEL.sel(curlabel)});
        else
            labelstr = sprintf('Label %s | ', MULTILABEL.desc{MULTILABEL.sel(curlabel)});
        end
    end
    MULTILABEL.curdim = curlabel;
    
    % Check whether selected parameter combinations should be tested
    if ~exist('PsSel','var') || isempty(PsSel)
        PiSel = true(nPs,nclass);
    else
        PiSel = false(nPs,nclass);
        for curclass=1:nclass
            PiSel(:,curclass) = PsSel{curclass}{curlabel}.SelNodes;
        end 
    end
    pltmax = sum(any(PiSel,2));
    
    % Do we have different CV structures assigned to different labels
    TCV = CV;
    if numel(TCV)>1, CV = TCV(curlabel); end
    pltcnt =0 ; 
    
    % Loop through all parameter combinations
    for current_idx = 1:nPs

        if ~sum(any(PiSel(current_idx,:)))
            if VERBOSE
                sskip = sprintf('\n%sSkipping hyperparameter combination %g!',labelstr,current_idx);
                fprintf('%s',sskip); 
            end
            continue; 
        end
        visited_idx = [visited_idx current_idx];
        pltcnt = pltcnt+1; pltperc = pltcnt*100/pltmax;
        tElapsed = toc; tElapsedSum = tElapsedSum+tElapsed; 
        elaps = sprintf('\t%1.2f sec.',tElapsed);
        
        %% Prepare NM Optimization viewer info
        if nPs > 1 
            DISP.s = sprintf('%s | %s%s\nCV2 [ %g, %g ] => %4g/%4g parameter combinations => %1.1f%% ', ...
                elaps, labelstr, algostr, f, d , pltcnt, pltmax, pltperc);
        else
            DISP.s = sprintf('%s | %s%s\nCV2 [ %g, %g ] => No-parameter optimization', ...
                elaps, labelstr, algostr, f, d  );
        end
        fprintf('%s',DISP.s); 
        DISP.pltperc = pltperc; 

        %% Loop through binary learners and prepare learning params according to the algorithm chosen by the user
        tic;
        cPs = cell(nclass,1);
        for curclass = 1:nclass
            DISP.P{curclass} = Ps{curclass}(current_idx,:);
            cPs{curclass} = nk_PrepMLParams(Ps{curclass}, Params_desc{curclass}, current_idx);
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
            if numel(visited_idx) > 1
                % Find the hyperparameters that belong to the preprocessing
                % phase
                if combcell
                    % Current position in the hyperparameter space
                    ipp     = cell2mat(Ps{1}(visited_idx(end),end-npreml:end));
                    % Previous position in the hyperparameter space
                    impp    = cell2mat(Ps{1}(visited_idx(end-1),end-npreml:end));
                else
                    ipp     = Ps{1}(visited_idx(end),end-npreml:end);
                    impp    = Ps{1}(visited_idx(end-1),end-npreml:end);
                end
                % Do we have a change between the previous and current
                % preprocessing hyperparameter position in the
                % preprocessing-related hyperparameter subspace? ...
                [~,i_dl] = ismember(ipp,pp,'rows');
                [~,m_dl] = ismember(impp,pp,'rows');
            else
                if combcell
                    ipp     = cell2mat(Ps{1}(visited_idx,end-npreml:end));
                else
                    ipp     = Ps{1}(visited_idx,end-npreml:end);
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
        % Compute current model(s) for variable parameter combination P(current_idx) = [ P1 P2 P3
        % ... Pn] using the CV1 data partitions. Apply single or ensemble model
        % to CV2 test sample in order to estimate the generalization 
        % capacity of the classification / prediction rule    
        [CV1perf, CV2perf, models] = nk_CVPermFold(mapYi, nclass, ngroups, cPs, FilterSubSets, batchflag);      

        % Transfer results from CV1perf and CV2perf to GD
        % structure using nk_GridSearchHelper 
        [GD, MD, DISP] = nk_GridSearchHelper(GD, MD, DISP, current_idx, nclass, ngroups, CV1perf, CV2perf, models);
       
        if isfield(CV1perf,'detrend'), GD.Detrend{current_idx} = CV1perf.detrend; end

        % Create variate mask according to selected features
        GD = nk_GenVI(mapYi, GD, CV, f, d, nclass, current_idx, curlabel);

        fprintf(repmat('\b',1,numel(DISP.s))); 
    end
end
MULTILABEL.curdim = 1;
CV = TCV(1);

fprintf('\n');fprintf('CV2 [%g, %g]: OPTIMIZATION COMPLETED IN %1.2f SEC ', ...
    f, d, tElapsedSum)

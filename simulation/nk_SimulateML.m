function [ performance_results, simulated_data, IN] = nk_SimulateML(IN, axes, batchflag)
% =========================================================================
% FORMAT function [ R, P ] = nk_SimulateML(IN)
% =========================================================================
% This function is part of the NeuroMiner machine learning library.
% It allows the user to determine the expected prognostic performance of a
% binary classification Algorithm under different learning scenarios, as
% determined by the "IN" parameter structure:
%
% 1) IN.NFeats : the dimensionality of the variable/feature space
%
% 2) IN.NMarkers : the percentage (0-1) of predictive markers within that
%    feature space
%
% 3) IN.NCases : the number of observations/cases/samples to learn from
%
% 4) IN.EventProb : the percentage (0-1) of cases with the (desired) event
%    in relation to the total number of cases
%
% 5) IN.AUCmax and IN.AUCmin : the maximum / minimum separability in the
%    feature matrix. The helper function is nk_ExpVec.m is used to create
%    features following an exponntial decline in separability. Feature
%    creation is based on randomly picking Gaussians within a certain
%    distance of each other and a certain span.
%
% 6) IN.NBatches : the absolute number of batched to corrupt the data
%
% 7) IN.BatchPerc : the maximum percentage (0-1) of the feature value range
%    allowed for site effects
%
% 8) IN.NCasesMiss : The percentage (0-1) of cases with missing data
%
% 9) IN.NFeatsMiss : The percentage (0-1) of missing values per case
%
% 10) IN.Data : The original data which structure should be simulated
%
% 11) IN.DataLabel : Output variable of original data
%
% 12) IN.NRanalysis : Which analysis to simulate, index (from NM structure)
%
% Parameters can come in ranges and thus are hyperparameters that the
% function will loop through in a brute-force approach. Based on these
% hyperparameters the function will generate a synthetic data matrix and
% forward it to a simple machine learning pipeline. The user currently can
% choose among four different classifiers:
% IN.Algorithm :
%       a) "LINKERNSVM" : LIBSVM with linear kernel (C=1)
%       b) "LINSVM": LINBLINEAR, L2-regularized, L1-Loss SVC
%       c) "L2LR" : L2-regularized logistic regression
%       d) "L1LR" : L1-regularized logistic regression
%       [not implemented yet:  "RF" : Random Forests]
%
% Furthermore, the setup of the cross-validation cycle can be tweaked, e.g.:
% IN.RAND.OuterPerm = 1; ==> Outer cross-validation permutations
% IN.RAND.InnerPerm = 1; ==> Inner cross-validation permutations
% IN.RAND.OuterFold = 5; ==> Outer cross-validation folds
% IN.RAND.InnerFold = 5; ==> Inner cross-validation folds
% IN.RAND.Decompose = 1;
%
% Please note that currently the function does not run any nested
% cross-validation as we will use standard machine learning parameters.
% This could be changed in the future but it will increase computational
% costs of the simulation enormously.
%
% This function will only work with NeuroMiner installed and initialized in
% an active MATLAB session Use preferably MATLAB 2018b or higher.
% _________________________________________________________________________
% (c) Nikolaos Koutsouleris, 10/02/2022
global fromData xNM 

if isfield(IN,'Data') && ~isempty(IN.Data)
    fromData = 1;
    if ~isdeployed
        xNM = evalin('base','NM');
    else
        xNM = IN.NM; 
    end
    analysis = xNM.analysis{1,IN.NRanalysis}; % CV: if NM was not closed after training the analysis, the analysis field does not exist yet
    resdir = analysis.rootdir;
else
    fromData = 0;
end

resdir = IN.outputdir;

% Create hyperparameter array
% Default Algorithm
if ~isfield(IN,'Algorithm') || isempty(IN.Algorithm)
    IN.Algorithm = 'LINKERNSVM';
end

if ~isfield(IN,'NBatches') || isempty(IN.NBatches)
    IN.NBatches = 0;
end

if ~isfield(IN,'BatchPerc') || isempty(IN.BatchPerc)
    IN.BatchPerc = 0.1;
end

if ~isfield(IN,'NCasesMiss') || isempty(IN.NCasesMiss)
    IN.NCasesMiss = 0;
end

if ~isfield(IN,'NMarkers') || isempty(IN.NMarkers)
    IN.NMarkers = 0;
end

if ~isfield(IN, 'NFeatsMiss') || isempty(IN.NFeatsMiss)
    IN.NFeatsMiss = 0;
end

if ~isfield(IN, 'AUCmax') || isempty(IN.AUCmax)
    IN.AUCmax = 0.7;
end

if ~isfield(IN, 'AUCmin') || isempty(IN.AUCmin)
    IN.AUCmin = 0.5;
end

if ~isfield(IN, 'EventProb') || isempty(IN.EventProb)
    IN.EventProb = 0;
end

if ~isfield(IN, 'verbose') || isempty(IN.verbose)
    IN.verbose = true;
end

if fromData
    IN.origRAND = analysis.params.TrainParam.RAND;
    P = IN.NCases;
    nP = size(P,2);
else
    if ~isfield(IN, 'RAND') || isempty(IN.RAND)
        % Setup permutation parameters
        IN.RAND.OuterPerm = 1;
        IN.RAND.InnerPerm = 1;
        IN.RAND.OuterFold = 5;
        IN.RAND.InnerFold = 5;
        IN.RAND.Decompose = 1;

    end
    P = allcomb2(IN.NFeats, IN.NMarkers, IN.NCases, IN.EventProb, IN.AUCmax, IN.AUCmin, IN.NBatches, IN.BatchPerc, IN.NCasesMiss, IN.NFeatsMiss);
    nP = size(P,1);
end

R = zeros(nP,1);
R95CI = zeros(2,nP);
detailed_R{nP} = [];
simulated_data{nP} = [];

if nargin > 1 && ~isempty(axes)
    ax = axes;
elseif nargin <=1
    if isfield(IN, 'plot_flag') && IN.plot_flag
        f = figure;
        ax = gca;
    end
end

[ CritRange, Crit, IN.OptFun ] = nk_GetScaleYAxisLabel(IN.GridParam);

Xl = cell(nP,1);

for i=1:nP
    if fromData
        sC = sprintf('C: %g/%g', i, size(P,1));
    else
        if numel(IN.NFeats)>1,       sF = sprintf('F: %g', P(i,1)); else, sF= ''; end
        if numel(IN.NMarkers)>1,     sM = sprintf(' M: %g', P(i,2)); else, sM= ''; end
        if numel(IN.NCases)>1,       sC = sprintf(' C: %g', P(i,3)); else, sC= ''; end
        if numel(IN.EventProb)>1,    sE = sprintf(' E: %g', P(i,4)); else, sE= ''; end
        if numel(IN.AUCmax)>1,       sAU = sprintf(' AU: %g', P(i,5)); else, sAU= ''; end
        if numel(IN.AUCmin)>1,       sAL = sprintf(' AL: %g', P(i,6)); else, sAL= ''; end
        if numel(IN.NBatches)>1,     sB = sprintf(' B: %g', P(i,7)); else, sB= ''; end
        if numel(IN.BatchPerc)>1,    sBP = sprintf(' BP: %g', P(i,8)); else, sBP= ''; end
        if numel(IN.NCasesMiss)>1,   sCm = sprintf(' Cm: %g', P(i,9)); else, sCm= ''; end
        if numel(IN.NFeatsMiss)>1,   sFm = sprintf(' Fm: %g', P(i,10)); else, sFm= ''; end
        Xl{i} = sprintf('%s%s%s%s%s%s%s%s%s%s',sF, sM, sC, sE, sAU, sAL, sB, sBP, sCm, sFm);
    end
end
for i=1:nP % Loop through hyperparameter combinations
    fprintf('\nWorking on parameter combination %g/%g: %s', i, nP, Xl{i});
    % Do the magic

    if fromData
        IN.this_NCases = IN.NCases(:,i);
    else
        IN.this_P = P(i,:);
    end
    [R(i), R95CI(:,i), detailed_R{i}, simulated_data{i}] = compute_perf(IN);
    % Update the simulation plot
    if exist("ax","var") && isfield(IN, 'plot_flag') && IN.plot_flag && i>2
        %plot(ax,1:i,R(1:i),'b-','LineWidth',2); hold on
        plotshaded(1:i, [(R95CI(1,1:i)+R(1:i)'); R(1:i)'; (R95CI(2,1:i)+R(1:i)')], rgb('Blue'), 0, 1.5);
        ax.XTick = 1:i;
        ax.XTickLabel = Xl(1:i);
        ax.XTickLabelRotation = 90;
        ax.XAxis.Label.String = 'Parameter combinations'; ax.XAxis.Label.FontWeight='bold';
        ax.YAxis.Label.String = Crit; ax.YAxis.Label.FontWeight='bold';
        ax.YAxis.Limits = CritRange;
        legend({'Mean','95%-CI'});
        drawnow
    end
end
performance_results.R = R;
performance_results.R95CI = R95CI';
performance_results.detailed_R = detailed_R;
performance_results.Params = P;

if isfield(IN, 'save_performance_flag') && IN.save_performance_flag
    uid = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
    resfilename = [resdir, '/', uid, '_samplesize_sim_results_NCases', sprintf('_min-%d', min(IN.NCases)), sprintf('_max-%d', max(IN.NCases)), '.mat']; 
    save(resfilename, 'performance_results', '-v7.3');
end

if isfield(IN, 'save_simdata_flag') && IN.save_simdata_flag
    uid = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
    simdatafilename = [resdir, '/', uid, '_samplesize_sim_data_NCases', sprintf('_min-%d', min(IN.NCases)), sprintf('_max-%d', max(IN.NCases)), '.mat']; 
    save(simdatafilename, 'simulated_data', '-v7.3');
end

if isfield(IN, 'plot_flag') && IN.plot_flag
    resplotfilename_png = [resdir, '/', uid, '_plot_sim_results_NCases', sprintf('_min-%d', min(IN.NCases)), sprintf('_max-%d', max(IN.NCases)), '.png'];
    resplotfilename_fig = [resdir, '/', uid, '_plot_sim_results_NCases', sprintf('_min-%d', min(IN.NCases)), sprintf('_max-%d', max(IN.NCases)), '.fig'];
    exportgraphics(ax, resplotfilename_png);
    savefig(f, resplotfilename_fig);
    performance_results.resplotfilename_fig = resplotfilename_fig;
end

if exist('ax')
    close(f);
end

% ___________________________________________________________________________________________________________________
function [Rmean, R95CI, R, simulated_data] = compute_perf(IN)
global SVM fromData xNM xCV

% Create marker matrix based on user's input
% fill the rest of the matrix with uninformative features
% in the range of -1 to 1

% check if original data was provided
if fromData

    nc = IN.this_NCases;
    if ~isdeployed
        xNM = evalin('base','NM');
    else
        xNM = IN.NM; 
    end
    verbose = IN.verbose; 
    %Ys = varargin{1,2};
    mods = IN.Modalities;
    labels = IN.DataLabel;
    curanal = IN.NRanalysis;
    add2orig = IN.add2orig;
    NReps = IN.NReps;
    sitesIdx = IN.SitesIdx;
    condIdx = IN.condIdx;
    if condIdx == 0
        condName = 'label';
    elseif condIdx > 0
        condName = xNM.covnames(condIdx);
    else
        condName = '';
    end

    origRAND = IN.origRAND;

    % what happens in the next lines, really necessary?
    %     if isa(labels_a, 'cell') % only binary problems
    %         num_labels = double(strcmp(labels_a,labels_a(1,1)));
    %         num_labels(num_labels==0) = -1;
    %     else % data and labels from NM structure; binary classification
    %         num_labels = labels_a;
    %         num_labels= num_labels-1; % simulate function could potentially better be adjusted to fit NM strucutre of labels
    %     end

    IN.analrootdir = xNM.analysis{1,curanal}.rootdir;
    %origDataFile = sprintf('%s/origData.csv',analrootdir);

    % check if several modalities included
    %   if length(Ys) >1
    % mods = 1:length(Ys);
    modNFeats = zeros(1,length(mods));
    Y = [];
    IN.YColNames = [];
    for i = 1:length(mods)
        modNFeats(i) = size(xNM.Y{1,mods(i)},2);
        Y = [Y, xNM.Y{1,i}];
    end
    modColIdx = repelem(mods, modNFeats);
    modNameVec = "Ymod" + modColIdx + "_Feat" + (1:sum(modNFeats));
    IN.YColNames = [IN.YColNames, modNameVec];

    % check whether covariates are included in analysis
    if isfield(xNM, 'covars')
        covColIdx = zeros(1,size(Y,2));
        IN.sitesIdxY = sitesIdx + size(Y,2);
        Y = [Y, xNM.covars];
        covColIdx = [covColIdx, ones(1,size(xNM.covars,2))];
        if height(xNM.covnames)>1; xNM.covnames = xNM.covnames'; end
        IN.YColNames = [IN.YColNames, xNM.covnames];
    end

    % check whether leave-one-group out cv framework is selected
    IN.cv1lcoIdx = 0;
    if isfield(origRAND,'CV1LCO')
        cv1lcoColIdx = zeros(1,size(Y,2));
        Y = [Y, origRAND.CV1LCO.ind];
        cv1lcoColIdx =[cv1lcoColIdx, 1];
        IN.cv1lcoIdx = length(cv1lcoColIdx);
        IN.YColNames = [IN.YColNames, 'CV1LCO'];
    end

    IN.cv2lcoIdx = 0;
    if isfield(origRAND,'CV2LCO')
        IN.cv2lcoColIdx = zeros(1,size(Y,2));
        Y = [Y, origRAND.CV2LCO.ind];
        cv2lcoColIdx =[cv2lcoColIdx, 1];
        IN.cv2lcoIdx = length(cv2lcoColIdx);
        IN.YColNames = [IN.YColNames, 'CV2LCO'];
    end


    % check if sample size dependent vectors are defined in preproc
    % - estimate betas in subgroup only
    % - ... ???
    preprocVecs.ModPStep = [];
    preprocVecs.Sequence = [];

    preprocIdx = zeros(1,length(Y));

    for m = 1:length(mods)
        if isfield(xNM.analysis{1,curanal}.params.TrainParam.PREPROC{1,m}, 'ACTPARAM')
        preprocs = xNM.analysis{1,curanal}.params.TrainParam.PREPROC{1,m}.ACTPARAM;
        for ps = 1:length(preprocs)
            switch preprocs{1,ps}.cmd
                case 'correctnuis' % type of preproc vec param 1
                    if isfield(preprocs{1,ps},'SUBGROUP') && any(~isnan(preprocs{1,ps}.SUBGROUP))
                        preprocVecs.ModPStep = [preprocVecs.ModPStep; m, ps];
                        Y = [Y, preprocs{1,ps}.SUBGROUP];
                        preprocIdx = [preprocIdx, 1];
                        preprocVecs.Sequence = [preprocVecs.Sequence, 1];
                        IN.YColNames = [IN.YColNames, "COVARSSUBGROUP"+m*ps];
                        break;
                    end
                case 'rankfeat' % type 2 (
                    if isfield(preprocs{1,ps}, 'label')
                        preprocVecs.ModPStep = [preprocVec.ModPStep; m, ps];
                        Y = [Y, preprocs{1,ps}.label];
                        preprocIdx = [preprocIdx, 1];
                        preprocVecs.Sequence = [preprocVecs.Sequence, 21];
                        IN.YColNames = [IN.YColNames, "RANKFEATLABEL"+m*ps];
                    end
                    if isfield(preprocs{1,ps}, 'glabel')
                        preprocVecs.ModPStep = [preprocVec.ModPStep; m, ps];
                        Y = [Y, preprocs{1,ps}.glabel];
                        preprocIdx = [preprocIdx, 1];
                        preprocVecs.Sequence = [preprocVecs.Sequence, 22];
                        IN.YColNames = [IN.YColNames, "RANKFEATGLABEL"+m*ps];
                    end
                    break;
                case 'remvarcomp'
                    if isfield(preprocs{1,ps}, 'REMOVECOMP')
                        preprocVecs.ModPStep = [preprocVec.ModPStep; m, ps];
                        Y = [Y, preprocs{1,ps}.G];
                        for i = 1:size(preprocs{1,ps}.G,2)
                            preprocIdx = [preprocIdx, 1];
                            preprocVecs.Sequence = [preprocVecs.Sequence, 3];
                            IN.YColNames = [IN.YColNames, "REMOVECOMPG"+dim];
                        end
                        break;
                    end
                end
            end
        end
    end

    % TODO: ADD DUMMY_CODED FEATURES AS CONSTRAINT

    %

    %writetable(Ytab, origDataFile);


    IN.numSyntheticObservations = nc;
    IN.condGroupVec = [];
    IN.condName = '';
    if condIdx > -1
        if condIdx == 0 % label
            IN.condName = 'label';
            IN.condIdxY = size(Y,2) + 1;
            IN.condGroupVec = repelem(unique(xNM.label),nc);
            IN.condVar = xNM.label;
        elseif condIdx > 0 % one of the covars  a   
            % check whether it's a categorical variable  TO DO
            IN.condName = xNM.covnames(condIdx);
            IN.condName = condName{1};
            IN.condGroupVec = repelem(unique(xNM.covars(:,condIdx)),nc);
            IN.condVar = xNM.covars(:,condIdx);
        end
    end

    % if certain condition
    R = zeros(1,NReps); % repeated for 10 times to increase stability of results
    for k=1:NReps
        tempRAND = origRAND;

        switch IN.method
            case 1
                if condIdx >= 0
                    IN_g = IN;
                    M = []; % synthetic data matrix
                    L = []; % synthetic label 
                    for nc_g=1:size(IN.numSyntheticObservations,1)
                        IN_g.numSyntheticObservations = IN.numSyntheticObservations(nc_g);
                        UN_g = nk_CountUniques(IN.condVar);
                        Y_g = Y(IN.condVar == UN_g.UX{1}(nc_g),:);
                        labels_g = labels(IN.condVar == UN_g.UX{1}(nc_g));
                        [M_g, L_g, ~] = nk_SynthDistkNN( Y_g, labels_g, [], IN_g); % covars are already added before, consider moving here (depending on how other additional vectors are treated by the other synthetic data tool)
                        M = [M; M_g]; 
                        L = [L; L_g];
                    end
                    clear IN_g labels_g Y_g UN_g;
                else
                    [M, L, ~] = nk_SynthDistkNN( Y, labels, [], IN); % covars are already added before, consider moving here (depending on how other additional vectors are treated by the other synthetic data tool)

                end
                %             case 2
                %                 [M, L,~, ~] = nk_PerfADASYN( Y, labels, [], IN, true);
            case 2
                if condIdx >= 0
                    IN_g = IN;
                    M = [];
                    L = [];
                    for nc_g=1:size(IN.numSyntheticObservations,1)
                        IN_g.numSyntheticObservations = IN.numSyntheticObservations(nc_g);
                        UN_g = nk_CountUniques(IN.condVar);
                        Y_g = Y(IN.condVar == UN_g.UX{1}(nc_g),:);
                        labels_g = labels(IN.condVar == UN_g.UX{1}(nc_g));
                        [M_g, L_g, ~] = nk_SynthPCAGauss( Y_g, labels_g, [], IN_g); % covars are already added before, consider moving here (depending on how other additional vectors are treated by the other synthetic data tool)
                        M = [M; M_g];
                        L = [L; L_g];
                    end
                    clear IN_g labels_g Y_g UN_g;
                else
                    [M, L, ~] = nk_SynthPCAGauss( Y, labels, [], IN);
                end
            case 3

               [M, L, ~] = cv_SynthGaussianCopula(Y, labels, [], IN); % % covars are already added before, consider moving here (depending on how other additional vectors are treated by the other synthetic data tool)
        end

        % if indicated, data will be added to original data
        if add2orig
            M = [Y;M];
            L = [labels;L];
        end

        if sum(preprocIdx)>0
            preprocIdx = logical(preprocIdx);
            for pt = 1:size(preprocVecs.Sequence,2)
                m = preprocVecs.ModPStep(pt,1);
                ps = preprocVecs.ModPStep(pt,2);
                if preprocVecs.Sequence(pt) == 1 % covars subgroup
                    xNM.analysis{1,curanal}.params.TrainParam.PREPROC{1,m}.ACTPARAM{1,ps}.SUBGROUP = M(:,size(M,2)-size(preprocVecs.Sequence,2)+pt);
                elseif preprocVecs.Sequence(pt) == 21 % rank target labels
                    xNM.analysis{1,curanal}.params.TrainParam.PREPROC{1,m}.ACTPARAM{1,ps}.label = M(:,size(M,2)-size(preprocVecs.Sequence,2)+pt);
                elseif  preprocVecs.Sequence(pt) == 22  % compute in subgroup
                    xNM.analysis{1,curanal}.params.TrainParam.PREPROC{1,m}.ACTPARAM{1,ps}.glabel = M(:,size(M,2)-size(preprocVecs.Sequence,2)+pt);
                elseif preprocVecs.Sequence(pt) == 3 % variance matrix
                    xNM.analysis{1,curanal}.params.TrainParam.PREPROC{1,m}.ACTPARAM{1,ps}.G = M(:,size(M,2)-size(preprocVecs.Sequence,2)+pt);
                end
            end
            M = M(:,~preprocIdx);
        end

        % TO DO: whether group size relation is correct otherwise
        % potentially use "conditions" of sdv package
        if isfield(tempRAND,'CV2LCO')
            % replace old CV2LCO with new one
            cv2lcoColIdx = logical(cv2lcoColIdx);
            tempRAND.CV2LCO.ind = M(:,cv2lcoColIdx == 1);
            M = M(:,~cv2lcoColIdx);
        end

        if isfield(tempRAND,'CV1LCO')
            % replace old CV1LCO with new one
            cv1lcoColIdx = logical(cv1lcoColIdx);
            tempRAND.CV1LCO.ind = M(:,cv1lcoColIdx == 1);
            M = M(:,~cv1lcoColIdx);
        end

        if isfield(xNM, 'covars')
            % add simulated covariates to xNM structure for preproc
            covColIdx = logical(covColIdx);
            xNM.covars = M(:,covColIdx);
            % remove covariate columns
            M = M(:,~covColIdx);
        end

        % separate different modalities into their own containers in xNM
        for i = 1:length(unique(modColIdx))
            xNM.Y{1,i} = M(:,modColIdx == mods(i));
        end

        xNM.analysis{1,curanal}.params.TrainParam.FUSION.M = mods;
        xNM.label = L;
        simCV = nk_MakeCrossFolds(L, tempRAND, xNM.modeflag,[], xNM.groupnames, [], 0);
        xNM.cv = simCV;
        xCV = simCV;
        xNM.analind = IN.NRanalysis;

        xinp = struct('analind', IN.NRanalysis, ...
            'lfl',1, ...
            'preprocmat',[], ...
            'gdmat',[], ...
            'gdanalmat', [], ...
            'varstr', [], ...
            'concatfl', [], ...
            'ovrwrt', 2, ...
            'update', true, ...
            'batchflag', true, ...
            'simFlag', true);
        [act, inp] = nk_MLOptimizerPrep(999, [],'Simulate analysis');
        R(k) = xNM.analysis{1,IN.NRanalysis}.GDdims{1,1}.BinClass{1,1}.contigency.BAC;
        
        fprintf(' ==> mean simulation outcome at %1.3f in repetition: %g,',R(k),k);
    end
    simulated_data.final_M = xNM.Y;
    simulated_data.cv = xNM.cv;
    simulated_data.NM = xNM;
else
    nf = IN.this_P(1,1);
    mr = IN.this_P(1,2);
    nc = IN.this_P(1,3);
    er = IN.this_P(1,4);
    auc_max = IN.this_P(1,5);
    auc_min = IN.this_P(1,6);
    nb = IN.this_P(1,7);
    bp = IN.this_P(1,8);
    ncm = IN.this_P(1,9);
    nfm = IN.this_P(1,10);
    Algorithm = IN.Algorithm;
    RAND = IN.RAND;
    NReps = IN.NReps;
    if mr<=1
        nmr = ceil(nf*mr);
    else
        if mr>nf, nmr = nf; else, nmr = round(mr);end
    end
    nc1     = ceil(nc*er);
    nc2     = nc-nc1;
    verbose = IN.verbose;
    % Create labels for synthetic data
    L = [ones(nc1,1); -1*ones(nc2,1)];
    IN.ZeroOne = 2;
    FM = [rand(nc1,nmr); -1*rand(nc2,nmr)];
    M = [ FM nk_PerfScaleObj(randn(nc,nf-nmr), IN)];
    simulated_data_FM = FM;
    simulated_data_M = M;

    % Define Algorithm to use for the simulation
    LIBSVMTRAIN = @svmtrain312;
    LIBSVMPREDICT = @svmpredict312;
    SCALEMODE = 'scale';
    switch Algorithm
        case 'LINKERNSVM'
            SVM.prog = 'LIBSVM';
            SVM.(SVM.prog).Weighting = 1;
            SVM.(SVM.prog).Optimization.b = 0;
        case 'LINSVM'
            SVM.prog = 'LIBLIN';
            SVM.(SVM.prog).b = 0;
            SVM.(SVM.prog).classifier = 3;
            SVM.(SVM.prog).tolerance = 0.01;
            CMDSTR.WeightFact = 1;
            SCALEMODE = 'std';
        case 'L2LR'
            SVM.prog = 'LIBLIN';
            SVM.(SVM.prog).b = 0;
            SVM.(SVM.prog).classifier = 0;
            SVM.(SVM.prog).tolerance = 0.01;
            CMDSTR.WeightFact = 1;
            SCALEMODE = 'std';
        case 'L1SVC'
            SVM.prog = 'LIBLIN';
            SVM.(SVM.prog).b = 0;
            SVM.(SVM.prog).classifier = 5;
            SVM.(SVM.prog).tolerance = 0.01;
            SCALEMODE = 'std';
        case 'L1LR'
            SVM.prog = 'LIBLIN';
            SVM.(SVM.prog).b = 0;
            SVM.(SVM.prog).classifier = 6;
            SVM.(SVM.prog).tolerance = 0.01;
            SCALEMODE = 'std';
        case 'RF' % not implemented yet
    end

    % We basically always want to weight the decision boundary
    SVM.(SVM.prog).Weighting = 1;
    CMDSTR.WeightFact = 1;

    % At the moment only binary classification is supported
    MODEFL = 'classification';

    % We want to repeat this ten times for producing more stable results
    pCV = RAND.OuterPerm;
    nCV = RAND.OuterFold;
    R = zeros(NReps,pCV*nCV);

    featmode = 'exponential';
    xSVM = SVM;
    % It is wonderful that we can use multi-core processors nowerdays,
    % (if the Parallel Computation toolbox is available!)
    %%
    xfromData = fromData;

    parfor k=1:NReps
        %for k = 1:NReps

        Ystar = M;
        auc_ystar=zeros(1,nmr);

        fprintf(['\n\nRepetition %g:\nWorking on new feature matrix:' ...
            '\n\t%g\tcases' ...
            '\n\t%g\tfeatures' ...
            '\n\t%1.2f\tevent rate', ...
            '\n\t%g\tpredictive markers' ...
            '\n\t%1.2f\tAUCmax' ...
            '\n\t%1.2f\tAUCmin' ...
            '\n\t%g\tbatches', ...
            '\n\t%1.2f\tbatch effect-to-feature scale ratio', ...
            '\n\t%1.2f\tratio of cases with missings', ...
            '\n\t%1.2f\tratio of features with missing per case\n'], ...
            k, nc, nf, er, nmr, auc_max, auc_min, nb, bp, ncm, nfm);

        % CREATE ARTIFICIAL DATA
        if ~xfromData
            switch featmode
                case 'simple'
                    for u=1:nmr
                        fprintf('.')
                        Ystar(:,u) = nk_CreatPredFeat(auc_max, auc_min, L, false);
                    end
                case 'exponential'
                    gran = 5;
                    sepvec = nk_ExpVec(auc_min,auc_max, gran);
                    featvec = floor(linspace(1,nmr,gran));
                    sepvec2 = zeros(nmr,2);
                    for u=1:gran-1
                        sepvec2(featvec(u):featvec(u+1),:) = repmat([sepvec(gran-u) sepvec(gran-u+1)], featvec(u+1)-featvec(u)+1,1);
                    end
                    sepvec2(end,:) = [sepvec(gran-u) sepvec(gran-u+1)];
                    if verbose, fprintf('\nRunning exponential decay function.\n'); end
                    for u=1:nmr
                        fprintf('.')
                        Ystar(:,u) = nk_CreatPredFeat(sepvec2(u,2), sepvec2(u,1), L, false);
                    end
            end

            % ADD BATCH EFFECTS
            if nb
                if verbose, fprintf('\nAdding batch effects to matrix.'); end
                % Create exponential batch vector and offsets
                batchvec = floor(nk_ExpVec(1, nc, nb));
                %rng
                batchoff = rescale(rand(nb,1), -bp, bp);
                % Create batch matrix
                Ybatch = zeros(nc, nf);
                for u=1:nb-1
                    Ybatch(batchvec(u):batchvec(u+1),:) = rand(batchvec(u+1)-batchvec(u)+1,nf)*batchoff(u);
                end
                Ystar = nk_PerfScaleObj(Ystar);
                % Make sure that the order of subjects is permuted before batch
                % effects are added to the matrix
                Iperm = randperm(nc);
                % add batch effects
                Ystar = Ystar + Ybatch(Iperm,:);
                Lk = L;
            else
                Lk = L;
            end

            % ADD MISSINGS

            if ncm
                if verbose, fprintf('\nInserting missings to matrix.'); end
                % creating boolean vector
                b_cm = false(nc,1);
                Ib_cm = randperm(nc,ceil(ncm*nc));
                b_cm(Ib_cm) = true;
                nbcm = numel(Ib_cm);
                Ymiss = zeros(nbcm,nf);
                for u=1:nbcm
                    b_fm = false(1,nf);
                    Ib_fm = randperm(nf,ceil(nfm*nf));
                    b_fm(Ib_fm) = true;
                    Ymiss(u,b_fm) = NaN;
                end
                Ystar(b_cm,:) = Ystar(b_cm,:) + Ymiss;
            end
        end
        Lk = L;
        if verbose, fprintf('\nFeature matrix creation completed.\n'); end
        simulated_data_final_FM{k} = Ystar;
        %figure;imagesc(Ystar);

        for u=1:size(Ystar,2), auc_ystar(u) = AUC(Lk,Ystar(:,u)); end

        %Create CV structure using NM
        %Produce label that NM understands
        Lx = Lk; Lx(Lk==-1)=2;
        cv = nk_MakeCrossFolds(Lx, RAND, 'classification', [], {'A','B'},[], 0,0);
        simulated_data_cv{k} = cv;
        Ri = zeros(pCV,nCV);

        for j=1:pCV

            % Use multi-core setting of my laptop to parallelize the CV cycle
            for i=1:nCV

                Tr = cv.TrainInd{j,i};
                Ts = cv.TestInd{j,i};
                Lr = Lk(Tr);
                Ls = Lk(Ts);
                W = ones(numel(Lr),1);

                % Scale / standardize matrix using NM and do it properly within the cross-validation cycle
                switch SCALEMODE
                    case 'scale'
                        if verbose, fprintf('\nScale data matrix.'); end
                        [Tr_Ystar, INi] = nk_PerfScaleObj(Ystar(Tr,:)); % Train scaling model
                        Ts_Ystar = nk_PerfScaleObj(Ystar(Ts,:), INi); % Apply it to the test data
                    case 'std'
                        if verbose, fprintf('\nStandardize data matrix.'); end
                        [Tr_Ystar, INi] = nk_PerfStandardizeObj(Ystar(Tr,:)); % Train standardization model
                        Ts_Ystar = nk_PerfStandardizeObj(Ystar(Ts,:), INi); % Apply it to the test data
                end

                if ncm
                    if verbose, fprintf('\nImpute data matrix.'); end
                    [Tr_Ystar, INi] = nk_PerfImputeObj(Tr_Ystar); % Train imputation model
                    Ts_Ystar = nk_PerfImputeObj(Ts_Ystar, INi); % Apply it to the test data
                end

                switch Algorithm
                    case 'LINKERNSVM'
                        % standard LIBSVM params:
                        cmd = '-s 0 -t 0 -c 1';
                        % set weighting!
                        cmd = nk_SetWeightStr(xSVM, MODEFL, CMDSTR, Lr, cmd);
                        % Train model
                        model = LIBSVMTRAIN(W, Lr, Tr_Ystar, cmd);
                        % Test model
                        [ ~, ~, ds ] = LIBSVMPREDICT( Ls, Ts_Ystar, model, sprintf(' -b %g',xSVM.LIBSVM.Optimization.b));

                    case {'LINSVM', 'L2LR', 'L1LR', 'L1SVC'}
                        %Define command string
                        cmd = nk_DefineCmdStr(xSVM, MODEFL);
                        cmd = [ ' -c 1' cmd.simplemodel cmd.quiet ];
                        % set weighting!
                        cmd = nk_SetWeightStr(xSVM, MODEFL, CMDSTR, Lr, cmd);
                        % Train model
                        model = train_liblin244(Lr, sparse(Tr_Ystar), cmd);
                        % Test model
                        [ ~, ~, ds ] = predict_liblin244(Ls, sparse(Ts_Ystar), model, sprintf(' -b %g -q',xSVM.LIBLIN.b));
                        ds = ds(:,1);
                    case 'RF'
                end

                % We use Balanced Accuracy for now.
                Ri(j,i) = IN.OptFun(Ls,ds);
            end
        end
        R(k,:) = Ri(:); fprintf(' ==> mean simulation outcome at %1.3f in repetition: %g,',mean(Ri(:)), k);

    end
    simulated_data.FM = simulated_data_FM;
    simulated_data.final_FM = simulated_data_final_FM;
    simulated_data.M = simulated_data_M;
    simulated_data.cv = simulated_data_cv;
end

R_flat=R(:);
Rmean = nm_nanmean(R_flat);

if NReps > 1
    R95CI = nm_95confint(R_flat);
else
    R95CI = [0,0];
end


function [Results, FileNames, RootPath] = nk_MLInterpreter(inp)
% nk_MLInterpreter - Executes the interpretable machine learning (ML) module
%
% Syntax:
%   [Results, FileNames, RootPath] = nk_MLInterpreter(inp)
%
% Description:
%   The `nk_MLInterpreter` function is designed to perform interpretable machine 
%   learning analysis on input data. It processes data across multiple modalities 
%   and classes, applying specified machine learning models and generating predictions 
%   for both original and modified data instances. The function supports various 
%   methods for generating interpretable results, including 'posneg', 'median', 
%   'medianflip', 'random', and 'shapley'. It returns the interpreted results, 
%   including Shapley values and mapped predictions, and saves these results to disk.
%
% Input:
%   inp        - A structure containing all necessary input parameters and data 
%                for the analysis. This includes configurations for cross-validation, 
%                machine learning models, preprocessing steps, and interpretation methods.
%
% Output:
%   Results    - A structure containing the results of the machine learning interpretation.
%                This includes mapped predictions, Shapley values, and other interpretive 
%                metrics for each class and modality.
%   FileNames  - A cell array of filenames where the results for each cross-validation (CV2)
%                partition are saved.
%   RootPath   - The root directory where the result files are stored.
%
% Main Steps:
%   1. **Initialization**:
%      - Initializes various parameters, checks input data, and sets up cross-validation 
%        counters and data containers.
%
%   2. **Preprocessing**:
%      - Depending on the analysis mode, the function preprocesses data, applies label 
%        transformations, and performs any necessary label imputations.
%
%   3. **Model Application**:
%      - Applies the machine learning models to the original data and generates predictions.
%        These predictions are used to assess the impact of data modifications.
%
%   4. **Artificial Data Creation**:
%      - Generates modified versions of the input data based on the specified interpretation 
%        method (e.g., 'posneg', 'median', 'shapley'). These modifications simulate various 
%        scenarios to evaluate the impact on model predictions.
%
%   5. **Prediction Evaluation**:
%      - Computes prediction changes for the modified data and compares them with the original 
%        predictions. The results are then stored in the `Results` structure.
%
%   6. **Result Storage**:
%      - Saves the results to disk, including mapped predictions, Shapley values, and other 
%        interpretation metrics. Additionally, the function handles the output of image files 
%        for spatial data (e.g., brain imaging data).
%
% Global Variables:
%   - SVM, RFE, MODEFL, CV, SCALE, SAV, CVPOS, FUSION
%     These global variables store configurations and data used throughout the function.
%
% Interpretation Methods:
%   - **posneg**: Generates positive and negative instances by modifying feature values 
%     based on specified thresholds.
%   - **median**: Sets selected features to their median values computed from the training data.
%   - **medianflip**: Flips the percentile values of the features around the median to explore 
%     the effect of feature inversion on the model's predictions.
%   - **random**: Randomly selects values for the features from the corresponding feature 
%     distribution in the training data.
%   - **shapley**: Generates Shapley values by quantifying the contribution of each feature to 
%     the model's predictions using coalition matrices.
%
% Detailed Subfunction Descriptions:
%   1. **return_imgind**:
%      - This subfunction determines which features (or image voxels) should be included 
%        based on a threshold and a specified operator.
%      - **Inputs**:
%        - `typthresh`: Operator type for thresholding (e.g., <, >, <=, >=, ==).
%        - `thresh`: The threshold value(s) to compare against.
%        - `img`: The image data or feature values to be thresholded.
%      - **Output**:
%        - `imgind`: Logical index vector indicating which features pass the thresholding criteria.
%
% Example:
%   [Results, FileNames, RootPath] = nk_MLInterpreter(inp);
%
% Notes:
%   - The function supports various machine learning methods (e.g., classification, 
%     regression) and multiple interpretation methods.
%   - It is designed to handle high-dimensional data (e.g., brain imaging) and complex 
%     preprocessing workflows.
%   - It can operate in different modes, either loading precomputed models or recomputing 
%     from scratch, based on user-defined settings.
%   - Results can be saved as files on disk, with support for batch processing and early 
%     fusion scenarios.
%
% See also:
%   nk_CreateData4MLInterpreter, nk_PerfInitSpatial, nk_ApplyTrainedPreproc
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris, last modified 08/2024
global SVM RFE MODEFL CV SCALE SAV CVPOS FUSION

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%% INITIALIZATION %%%%%%%%%%%%%%%%%%%%%%%%%%%%
FullPartFlag    = RFE.ClassRetrain;
switch inp.analmode
    case 0
        ovrwrt  = inp.ovrwrt;                       % overwrite existing data files
    case 1
        matfiles = inp.matfiles;                    % MLI files
end
multiflag       = false; if strcmp(MODEFL,'classification'), multiflag = inp.multiflag; end
saveparam       = inp.saveparam;
loadparam       = inp.loadparam;
nclass          = inp.nclass;
nM              = numel(inp.tF);  % No. of modalities to process
analysis        = inp.analysis;
GridAct         = inp.GridAct;
batchflag       = inp.batchflag;
algostr         = GetMLType(SVM);
cases           = inp.cases;
wts             = [];
if inp.oocvflag
    cases  = inp.OO.cases;
end

% Setup CV2 and CV1 counters and data containers:
[ix, jx]        = size(CV.TrainInd);
[iy, jy]        = size(CV.cvin{1,1}.TrainInd);
%interpAll       = size(inp)
ll              = 1; 
totLearn        = 0;
oocvflag        = inp.oocvflag;

if ~exist('GridAct','var') || isempty(GridAct), GridAct = nk_CVGridSelector(ix,jx); end
if ~exist('batchflag','var') || isempty(batchflag), batchflag = false; end

% Check and transform labels if needed
inp = nk_ApplyLabelTransform( SCALE, MODEFL, inp );

% Check whether you have to do prediction detrending for regression models
detrendfl = false;
if isfield(SVM,'Post') && isfield(SVM.Post,'Detrend') && SVM.Post.Detrend && strcmp(MODEFL,'regression')
    detrendfl = true;
end

% Check whether you have to perform label imputation and set flags
IMPUTE.flag = false;
if iscell(inp.PREPROC), iPREPROC = inp.PREPROC{1}; else, iPREPROC = inp.PREPROC; end    
if isfield(iPREPROC,'LABELMOD') && isfield(iPREPROC.LABELMOD,'LABELIMPUTE')
    IMPUTE = iPREPROC.LABELMOD.LABELIMPUTE; 
    IMPUTE.flag = true; 
end

BINMOD = iPREPROC.BINMOD;

CVPOS.fFull = FullPartFlag;

FileNames = cell(ix,jx);

RandFeats = struct('I',[]);

templateflag = nk_DetIfTemplPreproc(inp);

% Parameter flag structure for preprocessing
paramfl = struct('use_exist',inp.loadparam, ...
                 'found', false, ...
                 'write', inp.saveparam, ...
                 'writeCV1', inp.saveCV1, ...
                 'multiflag', multiflag, ...
                 'templateflag', templateflag);

inp.ll=inp.GridAct';inp.ll=find(inp.ll(:));

%Pre-smooth data, if needed, to save computational time
if ~inp.analmode
    inp = nk_PerfInitSpatial(analysis, inp, paramfl);
end

for h=1:nclass
    % We will later normalize the impact of feature modification using the
    % range of decision scores/probabilities/prediction in the training data.
    % (see nk_MapModelPredictions). In nk_MapModelPredictions, there is also 
    % the option to additionally normalize at the case level
    % (mean-centering, z-normalization, -1,1 scaling)
    switch MODEFL
        case 'classification'
            inp.MLI.RangePred(h) = range(analysis.BinClass{h}.mean_predictions);
        case 'regression'
            inp.MLI.RangePred = range(analysis.Regr.mean_predictions);
    end

    if inp.oocvflag
        mY2 = height(inp.X(1).Yocv);
    else
        mY2 = height(inp.X(1).Y);
    end
    nY = zeros(1,nM); nY2 = nY; datatype = zeros(1,nM);
    % Loop through modalities and prepare containers
    for nx=1:nM
        [nY(nx),datatype(nx),inp] = get_dimsizes_MLI(inp,nx,FUSION);
        nY2(nx) = nY(nx);
        % Prepare results containers
        switch MODEFL
            case 'classification'
                Results.BinResults(h).Modality(nx).Y_mapped = zeros(mY2,nY2(nx),ix);
                Results.BinResults(h).Modality(nx).Y_mapped_ciu = zeros(mY2,nY2(nx),ix);
                Results.BinResults(h).Modality(nx).Y_mapped_cil = zeros(mY2,nY2(nx),ix);
                Results.BinResults(h).Modality(nx).Y_mapped_std = zeros(mY2,nY2(nx),ix);
                Results.BinResults(h).Modality(nx).ShapleyValues = zeros(mY2,nY2(nx),ix);
                if inp.refdataflag
                    Results.BinResults(h).Modality(nx).refdata = inp.X.sY{nx}{1,1};
                     Results.BinResults(h).Modality(nx).refdataflag = inp.refdataflag;
                end
            case 'regression'
                Results.RegrResults.Modality(nx).Y_mapped = zeros(mY2,nY2(nx),ix);
                Results.RegrResults.Modality(nx).Y_mapped_ciu = zeros(mY2,nY2(nx),ix);
                Results.RegrResults.Modality(nx).Y_mapped_cil = zeros(mY2,nY2(nx),ix);
                Results.RegrResults.Modality(nx).Y_mapped_std = zeros(mY2,nY2(nx),ix);
                Results.RegrResults.Modality(nx).ShapleyValues = zeros(mY2,nY2(nx),ix);
                if inp.refdataflag
                    Results.RegrResults.Modality(nx).refdata = inp.X.sY{nx}{1,1};
                    Results.RegrResults.Modality(nx).refdataflag = inp.refdataflag;
                end
        end
        
        % If a statistical map should be used, determine the subspace for feature modification
        if isfield(inp.MLI.Modality{nx},'MAP') && inp.MLI.Modality{nx}.MAP.flag && isfield(inp,'visdata')
            if h==1 
                % get map type: currently, these metrics are supported: 
                % CVR, sign-based consistency, uncorrected and FDR-corrected
                maptype = inp.MLI.Modality{nx}.MAP.map; 
                % initialize map
                inp.MLI.Modality{nx}.MAP.map=[]; 
                % Get the cutoff to determine which features of the statistics
                % mask should be used.
                cutoff = inp.MLI.Modality{nx}.MAP.cutoff;
            end

            switch maptype
                case 'cvr'
                    inp.MLI.Modality{nx}.MAP.map{h} = inp.visdata{inp.curmodal,inp.curlabel}.CVRatio{h};
                case 'p_sgn'
                    inp.MLI.Modality{nx}.MAP.map{h} = inp.visdata{inp.curmodal,inp.curlabel}.SignBased_CV2_p_uncorr{h};
                case 'p_FDR_sgn'
                    inp.MLI.Modality{nx}.MAP.map{h} = inp.visdata{inp.curmodal,inp.curlabel}.SignBased_CV2_p_fdr{h};
            end
            % Is it a percentile cutoff? if so overwrite pre-existing
            % cutoff (see above)
            if isfield(inp.MLI.Modality{nx}.MAP,'percentile') && inp.MLI.Modality{nx}.MAP.percentmode
                cutoff = prctile(inp.MLI.Modality{nx}.MAP.map{h}, inp.MLI.Modality{nx}.MAP.cutoff);
            end
            inp.MLI.Modality{nx}.MAP.mapidx{h} = return_imgind(inp.MLI.Modality{nx}.MAP.operator, cutoff, inp.MLI.Modality{nx}.MAP.map{h});
        else
            inp.MLI.Modality{nx}.MAP.mapidx{h} = true(1,nY(nx));
        end
        if ~any(inp.MLI.Modality{nx}.MAP.mapidx{h})
            error(sprintf('User-specified feature selection map ''%s'' is empty! Adapt your settings.', maptype))
        end
    end
end
%% Generate, store/load permutation structure
permfile = fullfile(inp.rootdir,[SAV.matname '_MLIpermmat_ID' inp.id '.mat']);
if exist(permfile,'file') && inp.ovrwrtperm == 2
    fprintf('\nLoading %s', permfile);
    load(permfile,"RandFeats")
else
    clc
    sprintf('Generating random feature subspaces ... \n\n\n');
    for h=1:nclass
        if strcmp(MODEFL,'classification') && nclass >1, fprintf('\n\tBinary classifier #%g=> ', h); end
        nperms = zeros(1,nx);
        for nx=1:nM
            % Compute subspace size of current modality
            nYmap = sum(inp.MLI.Modality{nx}.MAP.mapidx{h});
            if nYmap<=2
                error('Only %g features out of %g were included in the feature mask. Reconsider the cutoffs used for mask definition!', ...
                    nYmap, numel(inp.MLI.Modality{nx}.MAP.mapidx{h}));
            end
            nperms(nx) = inp.MLI.nperms;
            if strcmp(inp.MLI.method,'shapley') && (nperms(nx) > 2^nYmap)
                nperms(nx) = 2^nYmap;
                warning('\nNumber of permutations exceeds maximum of possible permutations. Using the maximum number (#%g) of permutations.', nperms(nx))
            end
            if nM > 1, fprintf('\n\t\tModality #%g=> ', nx); end

            % Create random feature indices within (selected subspace of) the
            % original predictor space. Subspace selection can be based either 
            % on a relevance metric (CVR, sign-based consistency) and/or an
            % external map such as an atlas which summarizes raw input
            % space measurements (e.g. voxels) into groups (e.g. brain systems).
            switch inp.MLI.method
                case {'posneg','median','medianflip', 'medianmirror'}
                    % ordered permutations without replacement
                    % no repetitions
                    if isfield(inp.MLI.Modality{nx},'imgops') && ~isempty(inp.MLI.Modality{nx}.imgops) && inp.MLI.Modality{nx}.imgops.flag
                        % Fraction of unique atlas values to be selected => nfrac 
                        nfrac = ceil( numel(inp.MLI.Modality{nx}.imgops.csvnum) * inp.MLI.Modality{nx}.frac );
                        % Create permutations of atlas indices => tI
                        [ tI, nperms(nx) ] = uperms( inp.MLI.Modality{nx}.imgops.csvnum, inp.MLI.nperms, nfrac ); 
                        % Initialize logical index vector to map selected predictors within the space of MapIdx
                        RandFeats(h, nx).I = false(nperms(nx), nYmap);
                        for nq=1:nperms(nx)
                            % Find permuted atlas indices in masked atlas
                            % file (e.g. masked using CVR, sign-based )
                            RandFeats(h, nx).I(nq,:) = ismember(inp.MLI.Modality{nx}.imgops.atlasvec(inp.MLI.Modality{nx}.MAP.mapidx{h}), ...
                                                                inp.MLI.Modality{nx}.imgops.csvnum(tI(nq,:)));
                        end
                    else
                        % Fraction of (thresholded) image space 
                        nfrac = ceil( nYmap * inp.MLI.Modality{nx}.frac );
                        % return logical vector to permuted indices in
                        % (thresholded) image space.
                        [ RandFeats(h, nx).I, nperms(nx) ] = uperms( inp.MLI.Modality{nx}.MAP.mapidx{h}, inp.MLI.nperms, nfrac ); 
                    end
                     
                case {'random'}
                    % non-ordered permutations without replacement,
                    % repetitions are allowed.
                    if isfield(inp.MLI.Modality{nx},'imgops') && ~isempty(inp.MLI.Modality{nx}.imgops) && inp.MLI.Modality{nx}.imgops.flag
                        % only for imaging data when bound to an atlas
                        nfrac = ceil( numel(inp.MLI.Modality{nx}.imgops.csvnum) * inp.MLI.Modality{nx}.frac );
                        RandFeats(h, nx).I = false(nperms(nx), nYmap);
                        for nq = 1:nperms(nx)
                            tI = randperm( numel(inp.MLI.Modality{nx}.imgops.atlasvec_unique), nfrac); 
                            RandFeats(h, nx).I(nq,:) = ismember(inp.MLI.Modality{nx}.imgops.atlasvec(inp.MLI.Modality{nx}.MAP.mapidx{h}), ...
                                                                inp.MLI.Modality{nx}.imgops.csvnum(tI));   
                        end
                    else % for all other scenarios
                        nfrac = ceil( nYmap * inp.MLI.Modality{nx}.frac );
                        RandFeats(h, nx).I = false(nperms(nx),nYmap);
                        for nq = 1:nperms(nx)
                            RandFeats(h, nx).I(nq, randperm( nYmap, nfrac )) = true ;   
                        end
                    end
                case {'shapley'}
                    if isfield(inp.MLI.Modality{nx},'imgops') && ~isempty(inp.MLI.Modality{nx}.imgops) && inp.MLI.Modality{nx}.imgops.flag
                                                
                        [Z,wts] = coalitionMatrix(numel(inp.MLI.Modality{nx}.imgops.atlasvec_unique),nperms(nx)+2); %+2 added to nperms -> see comments below
                        if isempty(Z) % if no subsets besides the infinite weight subsets exist, return NaN
                            error('Please revise the number of iterations and features.')
                        end
                        %only nperms(nx)-2 iterations implemented,
                        %because two trivial cases, i.e. all or none
                        %features modified missing, see nm_shapley, line 1572 
%                         % Therefore, for now:
%                         Z(size(Z,1)+1,:) = false(1, size(Z,2)); %how useful? -> would be filtered out below
%                         Z(size(Z,1)+1,:) = true(1, size(Z,2));
                        RandFeats(h, nx).I = false(nperms(nx), nYmap);
                        for nq = 1:nperms(nx)
                            tI = find(Z(nq,:)); 
                            RandFeats(h, nx).I(nq,:) = ismember(inp.MLI.Modality{nx}.imgops.atlasvec(inp.MLI.Modality{nx}.MAP.mapidx{h}), ...
                                                                inp.MLI.Modality{nx}.imgops.csvnum(tI));   
                        end
                    else
                        %if subspace selection by relevance metric (e.g.
                        %CVR map) nYmap equals the number of relevant
                        %predictors
                        %create coalition matrix Z a 1000 times larger than
                        %nperms and choose randomly 1/1000 of it
                        %ToDo: replace 1000 by possible number of
                        %permutations
                        [Z,wts] = coalitionMatrix(nYmap,nperms(nx)+2); %+2 added to nperms -> see comments below
                        %[Z,wts] = coalitionMatrix(nYmap,nperms(nx)*1000);
                        %idx = randperm(nperms*1000,nperms);
                        %Z = Z(idx,:);
                        %wts = wts(idx,:);
                        if isempty(Z) % if no subsets besides the infinite weight subsets exist, return NaN
                            error('Please revise the number of iterations and features.')
                        end
                        %only nperms(nx)-2 iterations implemented,
                        %because two trivial cases, i.e. all or none
                        %features modified missing, see nm_shapley, line 1572 
%                         % Therefore, for now:
%                         Z(size(Z,1)+1,:) = false(1, size(Z,2)); %how useful? -> would be filtered out below
%                         Z(size(Z,1)+1,:) = true(1, size(Z,2));
                        RandFeats(h, nx).I = Z;
                    end
                    wts = wts./sum(wts); % normalize the weights
                case {'tree'}
                    error('Tree interpreter not yet implemented')
            end
            if ~strcmp(inp.MLI.method,'shapley')
                Dx = ~any(RandFeats(h,nx).I,2); RandFeats(h,nx).I(Dx,:) = [];
            end
        end
        if nM>1
            if numel(unique(nperms))>1
                inp.MLI.nperms = min(nperms);
                warning('\nNumber of permutations unequal across modalities. Using the minimum number (#%g) of permutations.', inp.MLI.nperms )
            end
        elseif min(nperms) < inp.MLI.nperms
             inp.MLI.nperms = min(nperms);
             warning('\nNumber of permutations adjusted to %g', inp.MLI.nperms )
        end
    end 
    fprintf('\nSaving to %s', permfile);

    switch inp.MLI.method
        case {'posneg','median','medianflip','random','tree'}
            save(permfile, 'RandFeats');
        case {'shapley'}
            save(permfile, 'RandFeats', 'wts');
    end

end
ol=1;

Sstr = ''; if isfield(inp,'issmoothed') && inp.issmoothed, Sstr = 's'; end
OCVstr = 'Y'; if isfield(inp,'oocvflag') && inp.oocvflag, OCVstr = 'Yocv'; end
OCVstr = [Sstr OCVstr];
TRstr = [Sstr 'Y'];

% =========================================================================
for f=1:ix % Loop through CV2 permutations

    for d=1:jx % Loop through CV2 folds
        
        fprintf('\n--------------------------------------------------------------------------')
        if ~GridAct(f,d) 
            ll=ll+1;
            fprintf('\nSkipping CV2 [%g,%g] (user-defined).',f,d)
            continue 
        end
       
        % Prepare variables for current CV2 partition
        CVPOS.CV2p = f;
        CVPOS.CV2f = d;
		
        if oocvflag
            tInd =  1:inp.nOOCVsubj;
        else
            tInd = CV.TestInd{f,d};
        end
        xTrInd = CV.TrainInd{f,d};

        inp.f = f; inp.d = d; 
        operm = f; ofold = d;
        inp.ll = ll;

        % Create MLI partition file path
        oMLIpath = nk_GenerateNMFilePath(inp.rootdir, SAV.matname, inp.datatype, inp.multlabelstr, inp.varstr, inp.id, operm, ofold);
        OptModelPath = nk_GenerateNMFilePath( inp.saveoptdir, SAV.matname, 'OptModel', [], inp.varstr, inp.id, operm, ofold);

        switch inp.analmode
            case 0
                 % Compute from scratch
                 % Now, check whether file exist and can be loaded
                 loadfl = false;
                 if exist(oMLIpath,'file') && ~ovrwrt && ~batchflag
                    
                    [~, onam] = fileparts(oMLIpath);
                    fprintf('\nMLIdatamat found for CV2 [%g,%g]:',f,d)
                    fprintf('\nLoading: %s',onam)
                    try
                        load(oMLIpath)
                        loadfl = true;
                    catch
                        fprintf('\nCould not open file. May be corrupt. Recompute CV2 partition [%g,%g].',f,d);
                        loadfl = false;
                    end
                    
                elseif exist(oMLIpath,'file') && batchflag
                     % in batch mode we do not compute statistics across the
                    % CV2 partitions
                    [~, onam] = fileparts(oMLIpath);
                    fprintf('\nMLIdatamat found for CV2 [%g,%g]:\n%s',f,d,onam)
                    fprintf('\nBatch mode detected. Continue.')
                    [RootPath, FileNames{f,d}] = fileparts(oMLIpath); 
                    load(oMLIpath)
                    loadfl=true;
                end
                   
                if ~loadfl 

                    % Parameter flag structure for preprocessing
                    paramfl = struct('use_exist',inp.loadparam, ...
                                     'found', false, ...
                                     'write', inp.saveparam, ...
                                     'writeCV1', inp.saveCV1, ...
                                     'multiflag', multiflag, ...
                                     'templateflag', templateflag);
                    
                    % Perform preprocessing of CV1/CV2 data
                    [ inp, contfl, analysis, mapY, GD, MD, Param, paramfl, mapYocv ] = nk_ApplyTrainedPreproc(analysis, inp, paramfl);

                    if contfl, continue; end

                    % Can we use a pretrained model saved on disk?
                    fndMD = false; 
                    if loadparam && isfield(inp,'optmodelmat') && exist(inp.optmodelmat{operm,ofold},'file')
                        fprintf('\nLoading OptModel: %s', inp.optmodelmat{operm,ofold});
                        load(inp.optmodelmat{operm,ofold},'MD'); fndMD = true; 
                    end
                    if ~fndMD, MD = cell(nclass,1); end
                    predOrig = cell(nclass,1);
                    % -----------------------------------------------------------------
                    for h=1:nclass  % Loop through binary comparisons
    
                        if nclass > 1, fprintf('\n\n*** %s #%g ***',algostr, h); end

                        %% Step 1: Get optimal model parameters
                        % Retrieve optimal parameters from precomputed analysis structure
                        % Differentiate according to binary or multi-group mode
                        [Ps, Pspos, nP, Pdesc] = nk_GetModelParams2(analysis, multiflag, ll, h, inp.curlabel);

                        if ~fndMD , MD{h} = cell(nP,1); end
                        
                        for m = 1 : nP % Loop through parameter combinations
                            
                            if nP > 1, fprintf('\nWorking on parameter combination #%g', m); end
                            % Create model parameter string
                            cPs = Ps(m,:); sPs = nk_PrepMLParams(Ps, Pdesc, m);                            
                            P_str = nk_DefineMLParamStr(cPs, analysis.Model.ParamDesc, h);
                            
                            %% Step 2: Apply trained model to original target data 
                            % Optionally, retrain every base learner in current CV1
                            % [k,l] partition (across different grid positions, if available)
                            if ~fndMD,MD{h}{m} = cell(iy,jy); end

                            for k=1:iy % Loop through CV1 permutations

                                for l=1:jy % Loop through CV1 folds
                                    
                                    CVPOS.CV1p = k;
                                    CVPOS.CV1f = l;

                                    % Get feature feature subspace mask for current 
                                    % parameter grid position
                                    Fkl = GD.FEAT{Pspos(m)}{k,l,h};

                                    % Determine number of features in mask and
                                    % convert feature mask to logical index, if needed
                                    ul=size(Fkl,2); totLearn = totLearn + ul;
                                    if ~islogical(Fkl), F = Fkl ~= 0; else, F = Fkl; end

                                    % Get data pointers for current dichotomization
                                    TrInd = mapY.TrInd{k,l}{h};
                                    CVInd = mapY.CVInd{k,l}{h};

                                    % Set the pointer to the correct mapY 
                                    % (preprocessed data) shelf
                                    for n=1:numel(paramfl)
                                        pnt = 1;
                                        if ~BINMOD
                                             if isfield(paramfl{n},'PREPROC') && ...
                                               isfield(paramfl{n},'PXfull') && ...
                                               ~isempty(paramfl{n}.P{1})
                                                pnt = m;
                                                break   
                                            end
                                        else
                                            if isfield(paramfl{n},'PREPROC') && ...
                                               isfield(paramfl{n},'PXfull') && ...
                                               ~isempty(paramfl{n}.P{h})
                                                %Actual parameter node
                                                pnt = m; 
                                                break   
                                            end
                                        end
                                    end

                                    % get training data using pointers
                                    % Either (a) only CV1 training data, (b) CV1
                                    % training and test data, (c) CV1 training & test
                                    % data as well as CV2 test data              
                                    if BINMOD, hix = h; else, hix = 1; end
                                    if inp.oocvflag
                                        [ TR , CV1, CV2, OCV ] = nk_ReturnAtOptPos(mapY.Tr{k,l}{hix},  mapY.CV{k,l}{hix}, mapY.Ts{k,l}{hix}, mapYocv.Ts{k,l}{hix}, Param{1}(k,l,hix), pnt);
                                        uD = zeros(size(OCV,1),ul);
                                    else 
                                        [ TR , CV1, CV2 ] = nk_ReturnAtOptPos(mapY.Tr{k,l}{hix},  mapY.CV{k,l}{hix}, mapY.Ts{k,l}{hix}, [], Param{1}(k,l,hix), pnt);
                                        uD = zeros(size(CV2,1),ul);
                                    end
                                    if FullPartFlag, TR = [ TR; CV1]; end
 
                                   % Get and build label info
                                    modelTrL = mapY.TrL{k,l}{h};                         
                                    if FullPartFlag 
                                        modelTrL = [modelTrL; mapY.CVL{k,l}{h}]; 
                                        TrInd = [TrInd; CVInd]; 
                                    end

                                    % Loop through feature subspaces
                                    if ~fndMD 
                                        MD{h}{m}{k,l} = cell(ul,1); 
                                        fprintf(['\nRetrain models in CV2 [%g,%g], ' ...
                                            'CV1 [%g,%g], %g %s, (total # learners: %g), ML params [%s] ==> '], ...
                                            f, d, k, l, ul, algostr, totLearn, P_str)
                                        % Impute labels if needed
                                        [modelTrL, TR, TrInd] = nk_LabelImputer( modelTrL, TR, TrInd, sPs, IMPUTE);
                                        TR = TR(TrInd,:);
                                    else
                                        fprintf(['\nUse precomputed models in CV2 [%g,%g], ' ...
                                            'CV1 [%g,%g], %g %s, (total # learners: %g), ML params [%s] ==> '], ...
                                            f, d, k, l, ul, algostr, totLearn, P_str)
                                    end

                                    % Loop through feature subspaces
                                    for u=1:ul
                                        % Extract features according to mask
                                        TR_star = nk_ExtractFeatures(TR, F, [], u);
                                        
                                        if ~fndMD
                                            fprintf('Compute optimal model...');
                                            [~, MD{h}{m}{k,l}{u}] = nk_GetParam2(TR_star, modelTrL, sPs, 1);
                                            fprintf(' done.');
                                        end

                                        fprintf(' Predict CV2 test data...')
                                        % Apply model to CV2 test data 
                                        if inp.oocvflag
                                            [~, ~, uD(:,u)] = nk_GetTestPerf(OCV, ones(size(OCV,1),1), F(:,u), MD{h}{m}{k,l}{u}, TR_star, 1);
                                        else
                                            [~, ~, uD(:,u)] = nk_GetTestPerf(CV2, ones(size(CV2,1),1), F(:,u), MD{h}{m}{k,l}{u}, TR_star, 1);

                                        end
                                        fprintf(' done.')
                                    end
                                    
                                    if detrendfl 
                                        fprintf(' Detrend CV2 predictions.')
                                        beta = GD.Detrend{Pspos(m)}.beta;
                                        p = GD.Detrend{Pspos(m)}.p;
                                        uD(:,u) = nk_DetrendPredictions2(beta, p, uD(:,u)); 
                                    end    
                                    predOrig{h} = [predOrig{h} uD];
                                end
                            end
                        end
                    end
                    
                    %% Step 3: Create artificial versions of target cases
                    % Prepare arrays
                    nTs = numel(tInd);
                    
                    switch inp.MLI.method
                        case {'posneg'}
                            predInterp = cell(nTs, nclass, 2);
                        case {'median','medianflip','random','medianmirror','shapley','tree'}
                            predInterp = cell(nTs, nclass);
                    end
                    mapInterp = cell(nclass, nM);
                    mapInterp_ciu = cell(nclass, nM);
                    mapInterp_cil = cell(nclass, nM);
                    mapInterp_std = cell(nclass, nM);
                    shapleyValues = cell(nclass, nM);
                    for h=1:nclass
                        for nx = 1:nM
                            mapInterp{h,nx} = nan(nTs, nY(nx));
                            mapInterp_ciu{h,nx} = nan(nTs, nY(nx));
                            mapInterp_cil{h,nx} = nan(nTs, nY(nx));
                            mapInterp_std{h,nx} = nan(nTs, nY(nx));
                            shapleyValues{h,nx} = nan(nTs, nY(nx));
                        end
                    end

                    for q=1:numel(tInd) % Loop through CV2/OOCV cases 
                        if isequal(inp.selectsamples,2)
                            if ~any(strcmp(inp.sampleID, cases{tInd(q)}))
                                continue
                            end
                        end
                        fprintf('\n\n--- Working on case ''%s'' (%g of %g cases) ---', cases{tInd(q)}, q, numel(tInd));
    
                        for h=1:nclass
                           
                            inp.NanModality = false(1, numel(inp.X));
    
                            for nx = 1:numel(inp.X)
                                % Create artificial data and add it as "OOCV
                                % data" (inp.X(nx).(s)Yocv) to the input structure. 
                                % if OOCV data has been selected for interpretation, then create
                                % inp.X(nx).(s)Yocv2 and deal with this scenario in nk_ApplyTrainedPreproc 
                                % (see there)
                                covs = [];
                                
                                if inp.oocvflag
                                    if ~isempty(inp.covars_oocv), covs = inp.covars_oocv(tInd(q),:); end
                                else
                                    if ~isempty(inp.covars), covs = inp.covars(tInd(q),:); end
                                end
                                if iscell(inp.X(nx).(OCVstr))
                                    nq = numel(inp.X(nx).(OCVstr){1});
                                    Ts = cell(nq,1); Tr = Ts;
                                    for qn = 1:nq
                                        Ts{qn} = inp.X(nx).(OCVstr){h}{qn}(tInd(q),:);
                                         % Check if the modality consists only of NaNs
                                        if sum(isnan(Ts{qn})) == size(inp.X(nx).Y,2)
                                            % processing this modality further makes
                                            % only sense for early fusion (where
                                            % imputation based on the other modalities
                                            % can remove the NaNs
                                            inp.NanModality(nx) = true;
                                            break
                                        end
                                        Tr{qn} = inp.X(nx).(TRstr){h}{qn}(xTrInd,:);
                                    end
                                    if inp.NanModality(nx), continue; end
                                else
                                    Ts = inp.X(nx).(OCVstr)(tInd(q),:);
                                    if sum(isnan(Ts)) == size(inp.X(nx).Y,2)
                                        inp.NanModality(nx) = true;
                                        continue;
                                    end
                                    Tr = inp.X(nx).(TRstr)(xTrInd,:);
                                end
                                if nclass>1
                                    ClassStr = sprintf('Binary classifier #%g, ',h) ;
                                else
                                    ClassStr = '';
                                end
                                fprintf('\n%sModality #%g: Creating %g modified instances of ''%s'' using the ''%s'' method', ...
                                    ClassStr, nx, inp.MLI.nperms, cases{tInd(q)}, inp.MLI.method);
                                % ToDo: loop through binary classifiers and
                                % call nk_CreateData4MLInterpreter with correct the binary idx (h) 
                                inp = nk_CreateData4MLInterpreter( inp.MLI, RandFeats(h, nx).I, Tr, Ts , covs, inp, nx, h );
                            end
                        end
             
                        % What shapley case saves in inp.X.Ycov has one dimension more than usual
                        % because it replaces the modified value not only with one random value but
                        % with each values available in the training sample once
                        % the preprocesssed data are stored in mapYcov
                        % Preprocess modified data
                        switch inp.MLI.method
                            case {'posneg','median','medianflip','medianmirror','random','tree'}
                                [ inp, ~, ~, ~, ~, ~, ~, ~, mapYocv] = nk_ApplyTrainedPreproc(analysis, inp, paramfl, Param);
                            case 'shapley'
                                if isfield(inp,'issmoothed') && inp.issmoothed
                                    % here we would need to potentially
                                    % account for multiple binary
                                    % classifier-related optimizations of 
                                    % smoothing kernels in multi-class learning:
                                    % M{classifier}{smoothing kernel}. At
                                    % the moment this will only work for
                                    % simple binary classification and
                                    % regression
                                    M = inp.X.sYocv;
                                else
                                    M = inp.X.Yocv;
                                end
                                % M can be a cell array if smoothing has
                                % been used during model optimization:
                                % M{classifier}{smoothing kernel}:
                                % "classifier" will always be 1 in binary
                                % classification or regression.
                                mapYocv_all = struct;
                                if iscell(M)
                                    % this may not work with
                                    % binary-optimized preprocessing
                                    % because the training data matrix will
                                    % vary across classifiers.
                                    nxM = numel(M{1}); nxY = size(inp.X.sYocv{1}{1},3); 
                                    Mij = cell(nclass,1);
                                    for i=1:nxY
                                        for curclass = 1:nclass
                                            Mij{curclass} = cell(nxM,1);
                                            for j=1:nxM, Mij{curclass}{j} = M{curclass}{j}(:,:,i); end
                                        end
                                        inp.X.sYocv = Mij;
                                        fprintf('\nOperating on data version #%g',i);
                                        [ inp, ~, ~, ~, ~, ~, ~, ~, mapYocv] = nk_ApplyTrainedPreproc(analysis, inp, paramfl, Param);
                                        mapYocv_all.(['mapYocv' num2str(i)]) = mapYocv;
                                    end
                                    inp.X.sYocv = M;
                                else
                                    for i=1:size(inp.X.Yocv,3)
                                        inp.X.Yocv = M(:,:,i);
                                        fprintf('\nOperating on data version #%g',i);
                                        [ inp, ~, ~, ~, ~, ~, ~, ~, mapYocv] = nk_ApplyTrainedPreproc(analysis, inp, paramfl, Param);
                                        mapYocv_all.(['mapYocv' num2str(i)]) = mapYocv;
                                    end
                                    inp.X.Yocv = M;
                                end
                                % store number of data instances for later
                                n_all = length(fieldnames(mapYocv_all));
                        end 
                        if any(inp.NanModality)
                            idxNan = find(any(inp.NanModality));
                            if numel(idxNan)>1
                                frstr = sprintf('Modalities %g', inp.F(idxNan(1)));
                                for qp = 2:numel(idxNan)
                                    frstr = sprintf('%s, %g', inp.F(idxNan(qp)));
                                end
                            else
                                frstr = sprintf('Modality %g', inp.F(idxNan));
                            end
                            switch inp.FUSION.flag
                                case {0,2,3} 
                                    warning('\nCase %s consists only of NaNs in %s! Skip interpretation',cases{tInd(q)}, frstr); continue;
                                case 1 
                                    warning('\nCase %s consists only of NaNs in %s! Proceed because of early fusion mode',cases{tInd(q)}, frstr);
                            end
                        end
                        
                        %% Step 4: generate predictions for artificial cases
                        switch inp.MLI.method
                            case 'posneg'
                                inp.desc_oocv{1} = sprintf('%g%%-percentile modification', inp.MLI.upper_thresh);
                                inp.desc_oocv{2} = sprintf('%g%%-percentile modification', inp.MLI.lower_thresh);
                            case 'median'
                                inp.desc_oocv = 'median modification';
                            case 'medianflip'
                                inp.desc_oocv = 'median flipped modification';
                            case 'medianmirror'
                                inp.desc_oocv = '100-centile modification';
                            case 'random'
                                inp.desc_oocv = 'random value modification';
                            case 'shapley'
                                inp.desc_oocv = 'shapley value modification';
                            case 'tree'
                                inp.desc_oocv = 'tree modification';
                        end
                        
                        for h=1:nclass  % Loop through binary comparisons

                            if nclass > 1, fprintf('\n*** %s #%g ***',algostr, h); end
    
                            [~, Pspos, nP] = nk_GetModelParams2(analysis, multiflag, ll, h, inp.curlabel);

                            for m = 1 : nP      % Loop through parameter combinations

                                if nP > 1,fprintf('\nWorking on parameter combination #%g', m); end
                                
                                for k=1:iy      % Loop through CV1 permutations
                                    for l=1:jy  % Loop through CV1 folds
                                    
                                        % Get feature subspace mask for current 
                                        % parameter grid position
                                        Fkl = GD.FEAT{Pspos(m)}{k,l,h};
    
                                        % Determine number of features in mask and
                                        % convert feature mask to logical index, if needed
                                        ul=size(Fkl,2); totLearn = totLearn + ul;
                                        if ~islogical(Fkl), F = Fkl ~= 0; else, F = Fkl; end

                                         % Set the pointer to the correct mapY shelf
                                        for n=1:numel(paramfl)
                                            pnt = 1;
                                            if ~BINMOD
                                                 if isfield(paramfl{n},'PREPROC') && ...
                                                   isfield(paramfl{n},'PXfull') && ...
                                                   ~isempty(paramfl{n}.P{1})
                                                    pnt = m;
                                                    break   
                                                end
                                            else
                                                if isfield(paramfl{n},'PREPROC') && ...
                                                   isfield(paramfl{n},'PXfull') && ...
                                                   ~isempty(paramfl{n}.P{h})
                                                    %Actual parameter node
                                                    pnt = m; 
                                                    break   
                                                end
                                            end
                                        end
  
                                        if BINMOD, hix = h; else, hix = 1; end
                                        if ~BINMOD && strcmp(inp.MLI.method,'posneg')
                                           mapYocv_h = mapYocv.Ts{k,l};
                                        else
                                           mapYocv_h = mapYocv.Ts{k,l}{hix};
                                        end

                                        switch inp.MLI.method
                                            case {'posneg','median','medianflip','medianmirror','random','tree'}

                                                [ TR , ~, ~, OCV ] = nk_ReturnAtOptPos(mapY.Tr{k,l}{hix},  mapY.CV{k,l}{hix}, mapY.Ts{k,l}{hix}, mapYocv_h, Param{1}(k,l,hix), pnt);

                                            case 'shapley'
                                                TR_all = cell(n_all,1); OCV_all = cell(n_all,1);
                                                for i=1:n_all
                                                    mapYocv = mapYocv_all.(['mapYocv' num2str(i)]);
                                                    [ TR , ~, ~, OCV ] = nk_ReturnAtOptPos(mapY.Tr{k,l}{hix},  mapY.CV{k,l}{hix}, mapY.Ts{k,l}{hix}, mapYocv_h, Param{1}(k,l,hix), pnt);
                                                    TR_all{i} = TR; OCV_all{i} = OCV; 
                                                end

                                        end

                                        switch inp.MLI.method

                                            case 'posneg'
                                                
                                                uD_pos = zeros(size(OCV{1},1),ul);
                                                uD_neg = zeros(size(OCV{1},1),ul);

                                                % Loop through feature subspaces
                                                for u=1:ul
            
                                                    % Extract features according to mask
                                                    TR_star   = nk_ExtractFeatures(TR, F, [], u);
                                                    
                                                    % Apply trained model to artificial data and generate
                                                    % predictions for later evaluation
                                                    fprintf('\nCV2 [%g,%g], CV1 [%g,%g]: Model #%g => Predicting %g modified instances of %s',  f, d, k, l, u, size(OCV{1},1), cases{tInd(q)});
                                                    [~, ~, uD_pos(:,u)] = nk_GetTestPerf(OCV{1}, ones(size(OCV{1},1),1), F(:,u), MD{h}{m}{k,l}{u}, TR_star, 1);
                                                    [~, ~, uD_neg(:,u)] = nk_GetTestPerf(OCV{2}, ones(size(OCV{2},1),1), F(:,u), MD{h}{m}{k,l}{u}, TR_star, 1);
        
                                                    % Detrend regressor predictions, if
                                                    % required by user input
                                                    if detrendfl 
                                                        beta = GD.Detrend{Pspos(m)}.beta;
                                                        p = GD.Detrend{Pspos(m)}.p;
                                                        uD_pos(:,u) = nk_DetrendPredictions2(beta, p, uD_pos(:,u));
                                                        uD_neg(:,u) = nk_DetrendPredictions2(beta, p, uD_neg(:,u));
                                                    end    
                                                end
                                                predInterp{q,h,1} = [predInterp{q,h,1} uD_pos];
                                                predInterp{q,h,2} = [predInterp{q,h,2} uD_neg];

                                            case {'median','medianflip','medianmirror','random'}

                                                uD = zeros(size(OCV,1),ul);

                                                % Loop through feature subspaces
                                                for u=1:ul
            
                                                    % Extract features according to mask
                                                    TR_star   = nk_ExtractFeatures(TR, F, [], u);
                                                 
                                                    % Apply trained model to artificial data and generate
                                                    % predictions for later evaluation
                                                    fprintf('\nCV2 [%g,%g], CV1 [%g,%g]: Model #%g | Parameter combination #%g => Predicting %g modified instances of %s', ...
                                                        f, d, k, l, u, m, size(OCV,1), cases{tInd(q)});
                                                    [~, ~, uD(:,u)] = nk_GetTestPerf(OCV, ones(size(OCV,1),1), F(:,u), MD{h}{m}{k,l}{u}, TR_star, 1);
        
                                                    % Detrend regressor predictions, if
                                                    % required by user input
                                                    if detrendfl 
                                                        beta = GD.Detrend{Pspos(m)}.beta;
                                                        p = GD.Detrend{Pspos(m)}.p;
                                                        uD(:,u) = nk_DetrendPredictions2(beta, p, uD(:,u)); 
                                                    end    
                                                end
                                                predInterp{q,h} = [predInterp{q,h} uD];
                                            
                                            case 'shapley'

                                                uD_all = zeros(size(OCV,1),ul,n_all);
                                                
                                                % Loop through data
                                                % instances required for
                                                % Shapley computations
                                                for i=1:n_all
                                                
                                                    TR = TR_all{i};
                                                    OCV = OCV_all{i};

                                                    uD = zeros(size(OCV,1),ul);

                                                    % Loop through feature subspaces
                                                    for u=1:ul

                                                        % Extract features according to mask
                                                        TR_star   = nk_ExtractFeatures(TR, F, [], u);

                                                        % Apply trained model to artificial data and generate
                                                        % predictions for later
                                                        % evaluation
                                                        fprintf('\nCV2 [%g,%g], CV1 [%g,%g]: Model #%g | Parameter combination #%g => Predicting %g modified instances of ''%s''', ...
                                                            f, d, k, l, u, m, size(OCV,1), cases{tInd(q)});
                                                        [~, ~, uD(:,u)] = nk_GetTestPerf(OCV, ones(size(OCV,1),1), F(:,u), MD{h}{m}{k,l}{u}, TR_star, 1);

                                                        % Detrend regressor predictions, if
                                                        % required by user input
                                                        if detrendfl
                                                            beta = GD.Detrend{Pspos(m)}.beta;
                                                            p = GD.Detrend{Pspos(m)}.p;
                                                            uD(:,u) = nk_DetrendPredictions2(beta, p, uD(:,u));
                                                        end
                                                    end
                                                    uD_all(:,:,i) = uD;
                                                end
                                                uD = mean(uD_all,3);    
                                                predInterp{q,h} = [predInterp{q,h} uD];
                                            
                                            case 'tree'
                                                error('Case tree is not yet implemented')
                                        end  
                                    end
                                end
                            end
                        end
                       
                        % Remove artificial data from inp structure
                        % otherwise nk_ApplyTrainedPreproc may not work
                        % properly.
                        if inp.oocvflag
                            if isfield(inp,'issmoothed') && inp.issmoothed
                                inp.X = rmfield(inp.X, 'sYocv2' );
                            else
                                inp.X = rmfield(inp.X, 'Yocv2' );
                            end
                        else
                            if isfield(inp,'issmoothed') && inp.issmoothed
                                inp.X = rmfield(inp.X, 'sYocv' );
                            else
                                inp.X = rmfield(inp.X, 'Yocv' );
                            end
                        end
                    end
                end

                %% Step 5: Evaluate impact of input data modifications using obtained predictions
                if ~loadfl || (loadfl && inp.recompute_estimates ==1)
                    fprintf('\nComputing MLI prediction change estimates in CV2 partition [ %g, %g ]:', f, d);
                  
                    for q=1:numel(tInd) % Loop through CV2/OOCV cases 
                        if isequal(inp.selectsamples,2)
                            if ~any(strcmp(inp.sampleID, cases{tInd(q)}))
                                continue
                            end
                        end
                        fprintf('\n\tCase %s (%g of %g cases)', cases{tInd(q)}, q, numel(tInd));

                        for h=1:nclass
                            Oh = nm_nanmedian(predOrig{h}(q,:),2);

                            for nx = 1:nM
                                fMapIdx = find( inp.MLI.Modality{nx}.MAP.mapidx{h} );
                                switch inp.MLI.method
                                    case 'posneg'
                                        Rh = [ nm_nanmedian(predInterp{q,h,1},2) nm_nanmedian(predInterp{q,h,2},2)]; 
                                    case {'median','medianflip','medianmirror','random','shapley'}
                                        Rh = nm_nanmedian(predInterp{q,h},2);
                                end
                                [mapInterp{h, nx}(q,:), ...
                                mapInterp_ciu{h, nx}(q,:), ...
                                mapInterp_cil{h, nx}(q,:), ...
                                mapInterp_std{h, nx}(q,:)] = nk_MapModelPredictions(nY(nx), Oh, Rh, RandFeats(h, nx).I, ...
                                                                    fMapIdx, inp.MLI.method, ...
                                                                    inp.MLI.RangePred(h), inp.MLI.znormdata);
                                
                                switch inp.MLI.method
                                    %calculate shapley values using´Kernel
                                    %SHAP
                                    case 'shapley'
                                        % 1. compute v0 and vM
                                        v0 = nm_nanmean(nm_nanmean(predOrig{h},2)); %this.Intercept: the mean of all predictions from the training sample (from all folds and permutations)
                                        vM = nm_nanmean(predOrig{h}(q,:),2); %scoreQueryPoint (mean over folds and permutations)

                                        % 2. Subtract the intercept from the ev
                                        ev = nm_nanmean(predInterp{q,h},2); %mean over predictions from all folds and permutations
                                        v = ev - v0;
                                        fx = vM - v0;

                                        % 3. solve the least squares problem
                                        % min (Z*phi - v)*W*(Z*phi - v) s.t sum(phi) = fx
                                        v = v.*sqrt(wts); % make weighted v
                                        Z = RandFeats(h,nx).I; %load correct Z
                                        Z = Z.*sqrt(wts); % make weighted Z
                                        % explicitly remove the constraint
                                        zM = Z(:,end);
                                        Z = Z(:,1:end-1);
                                        Z = Z - zM;
                                        
                                        %v is regressed onto Z under the
                                        %constraint that the sum of the coefficients equals fx (i.e. vM - v0)
                                        phiExceptLast = pinv(Z)*(v - zM.*fx);
                                        phi = [phiExceptLast;fx - sum(phiExceptLast,1)]; % do not forget to add 1 to the call in sum for the edge case where phiExceptLast is a row-vector (bivariate)
                                        shapleyValues{h, nx}(q,fMapIdx) = phi;
                                end
                            end
                        end
                    end
                    fprintf('\nSaving %s', oMLIpath);
                    refdataflag = inp.refdataflag;
                    if iscell(inp.X.sY)
                        refdata = inp.X.sY{nx}{1,1};
                    else
                        refdata = inp.X.sY;
                    end
                    save(oMLIpath,'predOrig', 'predInterp', 'mapInterp', 'mapInterp_ciu', 'mapInterp_cil', 'mapInterp_std', 'shapleyValues', 'operm','ofold','refdataflag','refdata');
                end
                if saveparam 
                    fprintf('\nSaving %s', OptModelPath); save(OptModelPath, 'MD', 'ofold','operm'); 
                end
                
            case 1
                
                vpth = deblank(matfiles{f,d});
                if isempty(vpth) || ~exist(vpth,'file') && GridAct(f,d)
                    error(['No valid MLIdatamat detected for CV2 partition ' '[' num2str(f) ', ' num2str(d) ']!']);
                else
                    [~,vnam] = fileparts(vpth);
                    fprintf('\n\nLoading MLI results for CV2 partition [ %g, %g ]:', f, d);
                    fprintf('\n%s',vnam);
                    load(vpth)
                    if inp.recompute_estimates == 1
                        fprintf('\nRecomputing MLI prediction change estimates in CV2 partition [ %g, %g ]:', f, d);
                        %% Step 5: Evaluate impact of input data modifications using obtained predictions
                        for q=1:numel(tInd) % Loop through CV2/OOCV cases 

                            fprintf('\n\tCase ''%s'' (%g of %g cases)', cases{tInd(q)}, q, numel(tInd));
                            
                            for h=1:nclass
                                Oh = nm_nanmedian(predOrig{h}(q,:),2);
                            
                                for nx = 1:nM
                                    fMapIdx = find( inp.MLI.Modality{nx}.MAP.mapidx{h} );
                                    switch inp.MLI.method
                                        case 'posneg'
                                            Rh = [ nm_nanmedian(predInterp{q,h,1},2) nm_nanmedian(predInterp{q,h,2},2)]; 
                                        case {'median','medianflip','medianmirror','random','shapley'}
                                            Rh = nm_nanmedian(predInterp{q,h},2);
                                    end
                                    [mapInterp{h, nx}(q,:), ...
                                     mapInterp_ciu{h, nx}(q,:), ...
                                     mapInterp_cil{h, nx}(q,:), ...
                                     mapInterp_std{h, nx}(q,:)] = nk_MapModelPredictions(nY(nx), Oh, Rh, RandFeats(h, nx).I, ...
                                                                     fMapIdx, inp.MLI.method, ...
                                                                     inp.MLI.RangePred(h), inp.MLI.znormdata);
                                end
                            end
                        end
                        fprintf('\nSaving %s', oMLIpath); 
                        save(oMLIpath,'predOrig', 'predInterp', 'mapInterp', 'mapInterp_ciu', 'mapInterp_cil', 'mapInterp_std', 'shapleyValues', 'operm','ofold');
                    end
                end 
        end
        
        %% Step 6: Concatenate results and assign them to results container
        [RootPath, FileNames{f,d}] = fileparts(oMLIpath);  
        ll=ll+1;
        for h = 1:nclass
            for nx = 1 : nM
                switch MODEFL
                    case 'classification'
                        Results.BinResults(h).Modality(nx).modality_num = inp.tF(nx); 
                        Results.BinResults(h).Modality(nx).modality_type = datatype(nx);
                        Results.BinResults(h).Modality(nx).modality_featnames = inp.featnames{nx};
                        Results.BinResults(h).Modality(nx).Y_mapped(tInd,:,f) = mapInterp{h,nx};
                        Results.BinResults(h).Modality(nx).Y_mapped_ciu(tInd,:,f) = mapInterp_ciu{h,nx};
                        Results.BinResults(h).Modality(nx).Y_mapped_cil(tInd,:,f) = mapInterp_cil{h,nx};
                        Results.BinResults(h).Modality(nx).Y_mapped_std(tInd,:,f) = mapInterp_std{h,nx};
                        Results.BinResults(h).Modality(nx).ShapleyValues(tInd,:,f) = shapleyValues{h,nx};
                        if inp.refdataflag
                            Results.BinResults(h).Modality(nx).refdata = inp.X.sY{nx}{1,1};
                            Results.BinResults(h).Modality(nx).refdataflag = inp.refdataflag;
                        end
                    case 'regression'
                        Results.RegrResults.Modality(nx).modality_num = inp.tF(nx);
                        Results.RegrResults.Modality(nx).modality_type = inp.X(nx).datatype;
                        Results.RegrResults.Modality(nx).modality_featnames = inp.featnames{nx};
                        Results.RegrResults.Modality(nx).Y_mapped(tInd,:,f) = mapInterp{h,nx};
                        Results.RegrResults.Modality(nx).Y_mapped_ciu(tInd,:,f) = mapInterp_ciu{h,nx};
                        Results.RegrResults.Modality(nx).Y_mapped_cil(tInd,:,f) = mapInterp_cil{h,nx};
                        Results.RegrResults.Modality(nx).Y_mapped_std(tInd,:,f) = mapInterp_std{h,nx};
                        Results.RegrResults.Modality(nx).ShapleyValues(tInd,:,f) = shapleyValues{h,nx};
                        if inp.refdataflag
                            Results.RegrResults.Modality(nx).refdata = inp.X.sY{nx}{1,1};
                            Results.RegrResults.Modality(nx).refdataflag = inp.refdataflag;
                        end
                end
            end
        end
    end
    ol=ol+1;
end
ol=ol-1;
for h = 1:nclass
    for nx = 1 : nM
        [ ~, datatype, brainmaski, badcoordsi, labeli, labelopi ] = getD(FUSION.flag, inp, nx);
        switch MODEFL
            case 'classification'
                Results.BinResults(h).Modality(nx).Y_mapped     = nm_nanmean(Results.BinResults(h).Modality(nx).Y_mapped(:,:,1:ol),3);
                Results.BinResults(h).Modality(nx).Y_mapped_ciu = nm_nanmean(Results.BinResults(h).Modality(nx).Y_mapped_ciu(:,:,1:ol),3);
                Results.BinResults(h).Modality(nx).Y_mapped_cil = nm_nanmean(Results.BinResults(h).Modality(nx).Y_mapped_cil(:,:,1:ol),3);
                Results.BinResults(h).Modality(nx).Y_mapped_std = nm_nanmean(Results.BinResults(h).Modality(nx).Y_mapped_std(:,:,1:ol),3);
                Results.BinResults(h).Modality(nx).ShapleyValues = nm_nanmean(Results.BinResults(h).Modality(nx).ShapleyValues(:,:,1:ol),3);
                Results.BinResults(h).RangePred = inp.MLI.RangePred(h);
                vols = Results.BinResults(h).Modality(nx).Y_mapped;
                if inp.refdataflag
                    Results.BinResults(h).Modality(nx).refdata = inp.X.sY{nx}{1,1};
                    Results.BinResults(h).Modality(nx).refdataflag = inp.refdataflag;
                end
            case 'regression'
                Results.RegrResults.Modality(nx).Y_mapped       = nm_nanmean(Results.RegrResults.Modality(nx).Y_mapped(:,:,1:ol),3);
                Results.RegrResults.Modality(nx).Y_mapped_ciu   = nm_nanmean(Results.RegrResults.Modality(nx).Y_mapped_ciu(:,:,1:ol),3);
                Results.RegrResults.Modality(nx).Y_mapped_cil   = nm_nanmean(Results.RegrResults.Modality(nx).Y_mapped_cil(:,:,1:ol),3);
                Results.RegrResults.Modality(nx).Y_mapped_std   = nm_nanmean(Results.RegrResults.Modality(nx).Y_mapped_std(:,:,1:ol),3);
                Results.RegrResults.Modality(nx).ShapleyValues  = nm_nanmean(Results.RegrResults.Modality(nx).ShapleyValues(:,:,1:ol),3);
                Results.RegrResults.RangePred = inp.MLI.RangePred(h);
                vols = Results.RegrResults.Modality(nx).Y_mapped; 
                if inp.refdataflag
                    Results.RegrResults.Modality(nx).refdata = inp.X.sY{nx}{1,1};
                    Results.RegrResults.Modality(nx).refdataflag = inp.refdataflag;
                end
        end
        
        % Write image files to disk
        if datatype == 1 || datatype == 2
            computedCases = find(any(vols,2));
            fprintf('\Writing out %g cases.',numel(computedCases));
            switch MODEFL
                case 'classification'
                    clstr = ['_cl' num2str(h)];
                case 'regression'
                    clstr = '';
            end
            for q=1:numel(computedCases) % Loop through CV2/OOCV cases
                volnamIDs = {'R','MC', 'Z', 'S'};
                volnam  = fullfile(inp.rootdir,sprintf('mli%s%s_var%g%s%s', volnamIDs{inp.MLI.znormdata}, ...
                    cases{computedCases(q)}, inp.tF(nx), clstr, inp.multlabelstr));
                switch datatype
                    case 1 % SPM-based NIFTI write-out
                        nk_WriteVol(vols(computedCases(q),:), volnam, 1, brainmaski, badcoordsi, labeli, labelopi);
                    case 2 % Surface-based write-out
                        s = MRIread(brainmaski);
                        volnam = fullfile(pwd,[deblank(volnam) '.mgh']);
                        s.vol = vols(computedCases(q),:);
                        MRIwrite(s,filename)
                end
            end
        end
    end
end

function imgind = return_imgind(typthresh, thresh, img)

if length(thresh) > 1
    switch typthresh
        case 1
            imgind = (img < thresh(1) | img > thresh(2)); 
        case 2
            imgind = (img <= thresh(1) | img >= thresh(2)); 
        case 3
            imgind = (img > thresh(1) | img < thresh(2)); 
        case 4
            imgind = (img >= thresh(1) | img <= thresh(2)); 
    end
else
    switch typthresh
        case 1
            imgind = img < thresh; 
        case 2
            imgind = img <= thresh;
        case 3
            imgind = img > thresh;
        case 4
            imgind = img >= thresh;
        case 5
            imgind = img == thresh;
    end
end

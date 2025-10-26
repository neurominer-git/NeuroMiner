function SubSets = nk_CreateSubSets(Y)
% NK_CREATESUBSETS: Create feature subsets for each label, variate, and binary
% predictor based on cross-validation partitions and feature ranking.
%
% USAGE:
%   SubSets = nk_CreateSubSets(Y)
%
% DESCRIPTION:
%   This function constructs structured feature subsets from the training
%   data stored in Y. The subsets are generated per label (for multi-label
%   problems), per variate (modality), and per binary predictor. Depending
%   on the ranking mode (multi-group vs. binary) and several global parameters,
%   the function selects a subset of features using a filtering method (e.g.,
%   FEAST, MRMR, RELIEF, IMRelief, etc.). When using IMRelief (RFE.Filter.type==6),
%   additional cross-validation is performed to compute optimal parameters.
%
% INPUTS:
%   Y - Structure containing training data and associated fields:
%         Y.Tr   : Cell array of training data for each CV partition.
%         Y.CV   : Cell array of CV data.
%         Y.TrL  : Cell array of training labels.
%         Y.CVL  : Cell array of CV labels.
%         Y.TrInd, Y.CVInd : Indices for training and CV splits.
%         (Optional fields for multi-label and multi-group cases: Y.mTrL, Y.mCVL)
%
% OUTPUTS:
%   SubSets - Cell array containing structured feature subsets for each label.
%
% GLOBAL VARIABLES:
%   CV, RAND, RFE, MULTI, MODEFL, MULTILABEL, VERBOSE, PREPROC, STACKING
%
% (c) Nikolaos Koutsouleris, 09/2017 - NeuroMiner Framework

global CV RAND RFE MULTI MODEFL MULTILABEL VERBOSE PREPROC STACKING

% Display status message if verbose and filter flag is set.
if VERBOSE && RFE.Filter.flag
    fprintf('\n\nCreate feature subsets');
end

% Determine dimensions from the training data cell array.
[nperms, nfolds, nvar] = size(Y.Tr);

% Determine number of labels (nl) for multi-label problems.
if MULTILABEL.flag
    if isfield(MULTILABEL, 'sel')
        nl = numel(MULTILABEL.sel);
    else
        nl = MULTILABEL.dim;
    end
else
    nl = 1;
end

% Preallocate output cells for subsets and weight vectors.
SubSets = cell(nl, 1);
W = cell(nl, 1);

% Determine number of binary predictors (nc) from the CV structure.
if isfield(CV(1), 'class')
    nc = numel(CV(1).class{1,1});
else
    nc = 1;
end

% For multi-group mode, ensure only one binary predictor is used when not in binary mode.
if MULTI.flag && MULTI.train
    if ~RFE.Filter.binmode && ~iscell(Y.Tr{1,1,1})
        nc = 1;
    end    
end

% Determine binary mode flag from PREPROC.
if iscell(PREPROC)
    BINMOD = PREPROC{1}.BINMOD;
else
    BINMOD = PREPROC.BINMOD;
end

% Override BINMOD if random decomposition is active.
if isfield(RAND, 'Decompose') && RAND.Decompose == 2
    BINMOD = 0;
end

% ------------------------------ Main Loop --------------------------------
% Loop over each label (multi-label) case.
for curlabel = 1:nl    
    % Preallocate cell arrays for current label.
    SubSets{curlabel} = cell(nperms, nfolds, nc, nvar);
    W{curlabel} = cell(nperms, nfolds, nc, nvar);
    
    % Loop over each variate (modality).
    for v = 1:nvar
        % Loop over each binary predictor/class.
        for curclass = 1:nc
            Mx = [];  % Initialize container for IMRelief performance grid.
            % Loop over permutation and fold partitions.
            for i = 1:nperms
                for j = 1:nfolds                
                    % Depending on ranking mode, get the training/CV data and labels.
                    switch RFE.Filter.binmode 
                        case 0  % Multi-group Feature Ranking
                            if VERBOSE && RFE.Filter.flag
                                switch MODEFL
                                    case 'classification'
                                        if nc > 1
                                            fprintf('\nFilter Label %g, Variate %g => CV1 [%g, %g, Multi-Group (%s)]:', ...
                                                curlabel, v, i, j, CV.class{1,1}{curclass}.groupdesc);
                                        else
                                            fprintf('\nFilter Label %g, Variate %g => CV1 [%g, %g, Multi-Group]:', curlabel, v, i, j);
                                        end
                                    case 'regression'
                                        fprintf('\nFilter Label %g, Variate %g => CV1 [%g, %g, Regression]:', curlabel, v, i, j);
                                end
                            end
                            % Retrieve training and CV data based on BINMOD.
                            if ~BINMOD
                                Tr = Y.Tr{i,j,v}; 
                                Cv = Y.CV{i,j,v};
                            else
                                Tr = Y.Tr{i,j,v}{curclass}; 
                                Cv = Y.CV{i,j,v}{curclass}; 
                            end
                            % Retrieve labels.
                            if MULTI.flag
                                TrL = Y.mTrL{i,j}; 
                                CvL = Y.mCVL{i,j}(:, curlabel);
                            else
                                TrL = Y.TrL{i,j}{1}; 
                                CvL = Y.CVL{i,j}{1}(:, curlabel);
                            end
                        case 1  % Binary Feature Ranking
                            if VERBOSE && RFE.Filter.flag
                                switch MODEFL
                                    case 'classification'
                                        fprintf('\nFilter Label %g, Modality %g => CV1 [%g, %g, %s]:', ...
                                            curlabel, v, i, j, CV.class{1,1}{curclass}.groupdesc);
                                    case 'regression'
                                        fprintf('\nFilter Label %g, Modality %g => CV1 [%g, %g, Regression]:', ...
                                            curlabel, v, i, j);
                                end
                            end
                            % Retrieve training and CV data based on BINMOD or STACKING flag.
                            if BINMOD || STACKING.flag == 1
                                Tr = Y.Tr{i,j,v}{curclass}(Y.TrInd{i,j}{curclass}, :); 
                                Cv = Y.CV{i,j,v}{curclass}(Y.CVInd{i,j}{curclass}, :); 
                            else
                                if iscell(Y.Tr{i,j,v})
                                    Tr = Y.Tr{i,j,v}{1}(Y.TrInd{i,j}{curclass}, :); 
                                    Cv = Y.CV{i,j,v}{1}(Y.CVInd{i,j}{curclass}, :);
                                else
                                    Tr = Y.Tr{i,j,v}(Y.TrInd{i,j}{curclass}, :); 
                                    Cv = Y.CV{i,j,v}(Y.CVInd{i,j}{curclass}, :);
                                end
                            end
                            % Retrieve labels.
                            TrL = Y.TrL{i,j}{curclass}; 
                            CvL = Y.CVL{i,j}{curclass}(:, curlabel);
                    end
                    
                    % Create a feature subspace using the current data.
                    [SubSets{curlabel}{i,j,curclass,v}, ...
                        W{curlabel}{i,j,curclass,v}, Mx] = CreateSubSet(Tr, TrL(:, curlabel), Cv, CvL, Mx, [], curclass);
                end
            end
            
            % For IMRelief (Filter.type==6), compute optimum parameters across all CV1 partitions.
            if RFE.Filter.flag && RFE.Filter.type == 6 && ~isempty(Mx)
                % Retrieve sigma and lambda parameters.
                if numel(RFE.Filter.imrelief) > 1
                    sigma = RFE.Filter.imrelief{curclass}.sigma;
                    lambda = RFE.Filter.imrelief{curclass}.lambda;
                    nsigma = numel(sigma);       
                else
                    sigma = RFE.Filter.imrelief{1}.sigma;
                    lambda = RFE.Filter.imrelief{1}.lambda;
                    nsigma = numel(sigma);
                end
                % Normalize performance grid.
                Mx = Mx ./ (nperms * nfolds);
                if VERBOSE
                    fprintf('\nComputed CV grid of sigma & lambda across CV1 partitions:');
                    for ii = 1:nsigma
                        fprintf('\n\t');
                        fprintf('%1.1f ', Mx(ii, :));
                    end
                end
                % Find optimum performance and corresponding indices.
                mxcv = max(Mx(:));
                [xpos, ypos] = find(Mx == mxcv);
                if VERBOSE
                    fprintf('\nSelected sigma = %1.1f, lambda = %1.3f, Perf = %1.2f', ...
                        sigma(xpos(1)), lambda(ypos(1)), mxcv);
                end
                % Average weight vector over CV1 partitions.
                weights = zeros(size(Tr, 2), 1);
                for ii = 1:nperms
                    for jj = 1:nfolds
                        weights = weights + W{curlabel}{ii,jj,curclass,v}(:, xpos(1), ypos(1)) ./ (nperms * nfolds);
                    end
                end
                [~, ind] = sort(weights, 'descend');
                
                % Recompute feature subspaces based on the average weight vector.
                for ii = 1:nperms
                    for jj = 1:nfolds
                        if BINMOD
                            Tr = Y.Tr{ii,jj,v}{curclass}(Y.TrInd{ii,jj}{curclass}, :); 
                            Cv = Y.CV{ii,jj,v}{curclass}(Y.CVInd{ii,jj}{curclass}, :); 
                        else
                            Tr = Y.Tr{ii,jj,v}(Y.TrInd{ii,jj}{curclass}, :); 
                            Cv = Y.CV{ii,jj,v}(Y.CVInd{ii,jj}{curclass}, :);
                        end
                        TrL = Y.TrL{ii,jj}{curclass}(:, curlabel); 
                        CvL = Y.CVL{ii,jj}{curclass}(:, curlabel);
                        SubSets{curlabel}{ii,jj,curclass,v} = CreateSubSet(Tr, TrL, Cv, CvL, [], ind, curclass);
                    end    
                end
            end
        end
    end
end
end

%% ------------------------------------------------------------------------
%% Subfunction: CreateSubSet
%% ------------------------------------------------------------------------
function [S, weights, aMx] = CreateSubSet(Y, label, Ynew, labelnew, aMx, ind, curclass)
% CREATESUBSET: Create a ranked feature subspace or return all features.
%
% USAGE:
%   [S, weights, aMx] = CreateSubSet(Y, label, Ynew, labelnew, aMx, ind, curclass)
%
% DESCRIPTION:
%   Depending on the global RFE.Filter settings, this function either:
%     - Returns all features (if no ranking/subspace learning is applied),
%     - Returns a thresholded ranked list of features, or
%     - Constructs multiple ranked subspaces (for classifier ensembles or
%       probabilistic feature extraction).
%
% INPUTS:
%   Y         - Training data matrix.
%   label     - Corresponding label vector (for current label).
%   Ynew      - New data matrix for evaluation (optional).
%   labelnew  - New labels for evaluation (optional).
%   aMx       - Accumulated performance grid (for IMRelief).
%   ind       - Pre-computed index order from feature ranking (optional).
%   curclass  - Current binary predictor index.
%
% OUTPUTS:
%   S         - Feature subset (converted to an appropriate unsigned integer type).
%   weights   - Weight vector from feature ranking.
%   aMx       - Updated accumulated performance grid.
%
% GLOBAL VARIABLES:
%   RFE, VERBOSE
%
% (c) Nikolaos Koutsouleris, 09/2017 - NeuroMiner Framework

global RFE VERBOSE

kFea = size(Y,2); 
weights = [];
if ~exist('aMx','var')
    aMx = [];
end

if ~RFE.Filter.flag
    % No ranking or subspace learning: use all features.
    S = (1:kFea)';
    
elseif ~RFE.Filter.SubSpaceFlag
    % Rank features and apply a threshold based on a user-defined threshold.
    S = (1:kFea)';
    if ~exist('ind','var') || isempty(ind)
        [weights, ind] = apply_filter(Y, label, kFea, Ynew, labelnew, aMx, curclass);
    end
    if RFE.Filter.RankThresh > 1
        RankThresh = RFE.Filter.RankThresh / 100;
    else
        RankThresh = RFE.Filter.RankThresh;
    end
    selnum = kFea - ceil(kFea * RankThresh);
    S = S(ind(selnum));
    if VERBOSE
        fprintf(' ranking.');
    end
    
else
    % Create ranked feature subspaces.
    k = kFea;
    km = k - (RFE.Filter.MinNum - 1);
    
    if ~exist('ind','var') || isempty(ind)
        [weights, ind, S] = apply_filter(Y, label, k, Ynew, labelnew, aMx, curclass);
    end
    
    if RFE.Filter.type ~= 11
        S = zeros(k, km);
        while km >= 1
            switch RFE.Filter.type
                case 0
                    kind = 1:kFea; % All features.
                    sx = kind;
                case {1, 2, 3, 4, 5, 6, 7, 10, 12, 13, 14}
                    kind = ind(1:k);
                    sx = 1:k;
                case 9
                    kind = 1:k;
                    sx = 1:k;
                case 11
                    kind = 1:kFea;
                    sx = ind(:, km);
            end
            S(kind, km) = sx;
            k = k - 1;
            km = km - 1;
        end
    end
end

% Convert S to an appropriate unsigned integer type to save memory.
if max(S(:)) > intmax('uint32')
    S = uint64(S);
elseif max(S(:)) > intmax('uint16')
    S = uint32(S);
elseif max(S(:)) > intmax('uint8')
    S = uint16(S);
else
    S = uint8(S);
end

end

%% ------------------------------------------------------------------------
%% Subfunction: apply_filter
%% ------------------------------------------------------------------------
function [weights, ind, S] = apply_filter(Y, label, k, Ynew, labelnew, aMx, curclass)
% APPLY_FILTER: Apply the specified feature ranking method to obtain an ordered
% index list for features.
%
% USAGE:
%   [weights, ind, S] = apply_filter(Y, label, k, Ynew, labelnew, aMx, curclass)
%
% DESCRIPTION:
%   This function applies the feature ranking filter as specified by
%   RFE.Filter.type. Various methods are supported, including FEAST, MRMR,
%   Pearson/Spearman correlation, Simba, G-flip, AMS, IMRelief, RELIEF, FScore,
%   Bhattacharya, and more. In the case of IMRelief, cross-validation is performed
%   to determine optimal parameters.
%
% INPUTS:
%   Y         - Training data matrix.
%   label     - Label vector.
%   k         - Total number of features.
%   Ynew      - New data for evaluation (for IMRelief CV).
%   labelnew  - New labels for evaluation (for IMRelief CV).
%   aMx       - Accumulated performance grid (optional).
%   curclass  - Current binary predictor index.
%
% OUTPUTS:
%   weights   - Computed weight vector (or tensor) from the ranking method.
%   ind       - Sorted index order of features based on ranking.
%   S         - For random subspace sampling (if applicable).
%
% GLOBAL VARIABLES:
%   VERBOSE, RFE
%
% (c) Nikolaos Koutsouleris, 09/2017 - NeuroMiner Framework

global VERBOSE RFE

weights = [];
ind = [];
S = [];
if size(Y, 1) < 5
    error('Your training matrix contains less than 4 subjects. Please ensure you have enough data for NM!');
end

switch RFE.Filter.type
    case 1 % FEAST
        ind = nk_FEAST(Y, label, k, RFE.Filter.FEAST);
        
    case 2 % MRMR
        ind = nk_MRMR(Y, label, k, RFE.Filter.MRMR);
        if VERBOSE, fprintf(' MRMR'); end

    case 3 % Pearson/Spearman correlation
        if RFE.Filter.Pearson == 1
            meas = 'pearson';
        else
            meas = 'spearman';
        end
        weights = abs(nk_CorrMat(Y, label, meas));
        [~, ind] = sort(weights, 'descend');
        if VERBOSE, fprintf(' %s', meas); end

    case 4 % Simba
        switch RFE.Filter.simba.utilfunc
            case 1 % linear
                if VERBOSE, fprintf(' Simba linear'); end
            case 2 % sigmoid
                if VERBOSE, fprintf(' Simba sigmoid (beta=%g)', RFE.Filter.simba.extra_param.beta); end
            case 3 % sigmoid with beta auto-adjust
                sugBeta = suggestBeta(Y, label);
                if VERBOSE, fprintf(' Simba sigmoid (beta=%g)', sugBeta); end
                RFE.Filter.simba.extra_param.beta = sugBeta;
        end
        weights = nk_SimbaMain(Y, label, RFE.Filter.simba.extra_param);
        [~, ind] = sort(weights, 'descend');

    case 5 % G-flip
        switch RFE.Filter.gflip.utilfunc
            case 1
                if VERBOSE, fprintf(' G-flip zero-one'); end
            case 2
                if VERBOSE, fprintf(' G-flip linear'); end
            case 3
                if VERBOSE, fprintf(' G-flip sigmoid (beta=%g)', RFE.Filter.gflip.extra_param.beta); end
        end
        [~, weights] = gflip(Y, label, RFE.Filter.gflip.extra_param);
        [~, ind] = sort(weights, 'descend');

    case 6 % AMS
        if VERBOSE, fprintf(' AMS'); end
        [weights, ~] = ams(Y, label, RFE.Filter.ams.method, RFE.Filter.ams.sphere, RFE.Filter.ams.extra_param);
        [~, ind] = sort(weights, 'descend');

    case 7 % IMRelief
        if iscell(RFE.Filter.imrelief)
            if numel(RFE.Filter.imrelief) < curclass
                imrelief = RFE.Filter.imrelief{end};
            else
                imrelief = RFE.Filter.imrelief{curclass};
            end
        else
            imrelief = RFE.Filter.imrelief;
        end
        nsigma = numel(imrelief.sigma);
        nlambda = numel(imrelief.lambda);
        if nsigma > 1 || nlambda > 1
            weights = zeros(size(Y,2), nsigma, nlambda);
        end
        for i = 1:nsigma
            for j = 1:nlambda
                if VERBOSE, fprintf(' IMRelief (sigma=%g, lambda=%g)', imrelief.sigma(i), imrelief.lambda(j)); end
                weights(:, i, j) = IMRelief_Sigmoid_FastImple(Y', label, imrelief.distance, imrelief.sigma(i), imrelief.lambda(j), imrelief.maxiter, imrelief.plotfigure);
            end
        end
        % Cross-validation for IMRelief parameter selection.
        if nsigma > 1 || nlambda > 1
            Mx = zeros(nsigma, nlambda);
            for i = 1:nsigma
                for j = 1:nlambda
                    pred = IMRelief_Sigmoid_FastImple_Predict2(Y', label, Ynew', weights(:, i, j), imrelief.distance, imrelief.sigma(i));
                    Mx(i, j) = feval('BAC2', labelnew, pred);
                end
            end
            mxcv = max(Mx(:));
            [xpos, ypos] = find(Mx == mxcv);
            if VERBOSE
                fprintf('\nComputed CV grid:');
                for i = 1:nsigma
                    fprintf('\n\t');
                    fprintf('%1.1f ', Mx(i, :));
                end
                fprintf('\nSelected sigma = %1.1f, lambda = %1.3f, Perf = %1.2f', imrelief.sigma(xpos(1)), imrelief.lambda(ypos(1)), mxcv);
            end
            [~, ind] = sort(weights(:, xpos(1), ypos(1)), 'descend');
            if exist('aMx', 'var')
                if isempty(aMx)
                    aMx = Mx;
                else
                    aMx = aMx + Mx;
                end
            end
        else
            [~, ind] = sort(weights, 'descend');
        end

    case 9 % Increasing subspace cardinality (no filtering)
        ind = 1:k;
        if VERBOSE, fprintf(' increasing subspace cardinality (no filter)'); end

    case 10 % RGS (regression)
        if VERBOSE, fprintf(' RGS'); end
        alpha = RGS(Y, label, RFE.Filter.RGS.extra_param);
        [~, ind] = sort(alpha, 'descend');

    case 11 % Random subspace sampling
        if VERBOSE, fprintf(' Random subspace sampling'); end
        S = nk_RSS(size(Y,2), RFE.Filter.RSS);

    case 12 % RELIEF-based feature ranking
        if VERBOSE, fprintf(' RELIEF-based feature ranking'); end
        ind = relieff(Y, label, RFE.Filter.Relief.k);
        
    case 13 % FScore feature ranking
        weights = nk_FScoreFeatRank(Y, label);
        [~, ind] = sort(weights, 'descend');
        if VERBOSE, fprintf(' FScore'); end
        
    case 14 % Bhattacharya feature ranking
        weights = nk_BhattacharyaFeatRank(Y, label);
        [~, ind] = sort(weights, 'descend');
        if VERBOSE, fprintf(' Bhattacharya'); end
        
end
end
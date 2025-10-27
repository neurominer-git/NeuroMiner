% ===================================================================================
% [param, model] = nk_GetParam2(Y, label, Params, ModelOnly, FeatGroups)
% ===================================================================================
%
% DESCRIPTION:
%   This function preprocesses the training data by:
%     1. Removing cases with all NaN values.
%     2. For survival models ('WBLCOX'): extracting the time vector from
%        the training indices and recoding labels.
%     3. Validating that the training data and labels are consistent.
%
%   It then calls a user-defined training function (TRAINFUNC) to produce
%   model parameters and a trained model. Optionally, if debugging is enabled,
%   the model and training data are saved for inspection.
%
% INPUTS:
%   Y         - Training data matrix (observations x features).
%   label     - Vector or matrix of labels corresponding to Y.
%   Params    - Parameters used for model training.
%   ModelOnly - Flag indicating whether only the model should be returned 
%               (without additional outputs such as prediction parameters).
%   FeatGroups- (Optional) Feature group indices or structure for group-wise 
%               training (used for some algorithms).
%
% OUTPUTS:
%   param     - Model parameters or training settings produced by the training
%               function.
%   model     - Trained model returned by the training function.
%
% GLOBAL VARIABLES:
%   TRAINFUNC - Function handle to the algorithm-specific training module.
%   SVM       - Structure containing settings for the current algorithm.
%   TIME      - Vector of time points for survival models (used in 'WBLCOX').
%   CV        - Cross-validation structure containing training indices.
%   CVPOS     - Structure with current CV positions and flags.
%   SAV       - Structure with saving options, including the matname.
%   DEBUG     - Debugging structure; if DEBUG.eachmodel is true, the model is saved.
%
% DEPENDENT FUNCTIONS:
%   nk_ManageNanCases - Preprocesses Y and label by pruning cases with all NaNs.
% ===================================================================================
% (c) Nikolaos Koutsouleris, 03/2025 

function [param, model] = nk_GetParam2(Y, label, Params, ModelOnly, FeatGroups)

global TRAINFUNC SVM TIME CV CVPOS SAV DEBUG

%% Step 1: Preprocess Data - Remove Cases with All NaN Values
[Y, label] = nk_ManageNanCases(Y, label, [], 'prune_single');

%% Step 2: Process Time Information for Survival Models (WBLCOX)
timevec = [];
if ~isempty(TIME) && strcmp(SVM.prog, 'WBLCOX')
    % Retrieve training indices from the cross-validation structure.
    TrInd = CV.TrainInd{CVPOS.CV2p, CVPOS.CV2f}(...
        CV.cvin{CVPOS.CV2p, CVPOS.CV2f}.TrainInd{CVPOS.CV1p, CVPOS.CV1f});
    if CVPOS.fFull
        % Include additional indices if full CV is requested.
        TrInd = [TrInd; CV.TrainInd{CVPOS.CV2p, CVPOS.CV2f}(...
            CV.cvin{CVPOS.CV2p, CVPOS.CV2f}.TestInd{CVPOS.CV1p, CVPOS.CV1f})];
    end
    % Extract the corresponding time vector.
    timevec = TIME(TrInd);
    % Recode labels: convert -1 to 0 (event indicator for survival analysis).
    label(label == -1) = 0;
end

%% Step 3: Validate Training Data
% Check for non-finite values in the training matrix.
numNonFinite = sum(~isfinite(Y(:)));
if numNonFinite > 0
    % If the number of features is small, export the data for further inspection.
    if size(Y, 2) < 500
        writetable(table(Y), sprintf('TrainingData_Error_CV2-%g-%g_CV1-%g-%g.xlsx', ...
            CVPOS.CV2p, CVPOS.CV2f, CVPOS.CV1p, CVPOS.CV1f));
    end
    error(['\nFound %g non-finite values in training matrix!\n' ...
           'This usually happens in intermediate fusion mode when some data modalities ' ...
           'have cases with completely missing data.\nCheck your preprocessing settings and your data!'], numNonFinite);
end

% Ensure that the number of observations in Y matches the number of labels.
if size(Y, 1) ~= size(label, 1)
    error('\nTraining data matrix and labels must have the same number of observations!');
end

%% Step 4: Train the Model Using the User-Defined Training Function
if nargin < 5 || isempty(FeatGroups)
    FeatGroups = []; % Ensure FeatGroups is empty if not provided.
end

switch SVM.prog
    case 'SEQOPT'
        [param, model] = TRAINFUNC(Y, label, FeatGroups, ModelOnly, Params);
    case 'WBLCOX'
        [param, model] = TRAINFUNC(Y, label, timevec, ModelOnly, Params);
    otherwise
        [param, model] = TRAINFUNC(Y, label, ModelOnly, Params);
end

%% Step 5: Debugging - Save the Model if Debug Flag is Set
if ~isempty(DEBUG) && isfield(DEBUG, 'eachmodel') && DEBUG.eachmodel
    filename = fullfile(pwd, sprintf('Model_%s_CV2%g-%g_CV1%g-%g.mat', ...
        SAV.matname, CVPOS.CV2p, CVPOS.CV2f, CVPOS.CV1p, CVPOS.CV1f));
    save(filename, "Y", "label", "model");
end

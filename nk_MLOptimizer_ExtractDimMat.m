% =========================================================================
% mapYi = nk_MLOptimizer_ExtractDimMat(mapY, dim_index, cPs)
% =========================================================================
%
% DESCRIPTION:
%   Extracts a specific dimension from the multi-dimensional cell arrays
%   contained in the input structure 'mapY'. The extraction is performed
%   according to the provided 'dim_index' and the current label dimension,
%   particularly for multi-label scenarios. If needed, the function applies 
%   label imputation for each class using the parameters in 'cPs', and 
%   returns a modified structure 'mapYi' that preserves the overall 
%   structure of 'mapY' with updated training (Tr), cross-validation (CV), 
%   and test (Ts) data.
%
% INPUTS:
%   mapY      - Structure with data matrices (fields: Tr, CV, Ts, TrL, TrInd,
%               and optionally VI) arranged in a cell array of size [m x n x o].
%   dim_index - Scalar specifying which dimension to extract from each cell.
%   cPs       - Cell array containing parameters for label imputation per class.
%
% OUTPUT:
%   mapYi     - Updated structure with extracted dimensions and imputed labels.
%
% GLOBAL VARIABLES:
%   PREPROC    - Preprocessing configuration (cell or structure) containing
%                settings for binary mode and label imputation.
%   STACKING   - Structure with stacking options (uses field 'flag').
%   MULTILABEL - Structure with multi-label configuration (e.g., 'curdim').
%   RAND       - Structure containing randomization settings (e.g., 'Decompose').
%
% DEPENDENT FUNCTIONS:
%   nk_LabelImputer - Performs label imputation on the training data.
%
% =========================================================================
% (c) Nikolaos Koutsouleris, 03/2025

function mapYi = nk_MLOptimizer_ExtractDimMat(mapY, dim_index, cPs)
global PREPROC STACKING MULTILABEL RAND

% Get dimensions of the training data cell array
[m, n, o] = size(mapY.Tr);

% Initialize output structure with the same overall fields as mapY
mapYi = mapY;
mapYi.Tr = cell(m, n, o);
mapYi.CV = cell(m, n, o);
mapYi.Ts = cell(m, n, o);

% Initialize the imputation flag (default: no imputation)
IMPUTE.flag = 0;

% Ensure PREPROC is in structure format
if iscell(PREPROC)
    iPREPROC = PREPROC{1};
else
    iPREPROC = PREPROC;
end

% Set binary mode processing flag from preprocessing settings
BINMOD = iPREPROC.BINMOD;

% If multi-group decomposition is active with mode 2, override binary mode
if isfield(RAND, 'Decompose') && RAND.Decompose == 2
    BINMOD = 0;
end

% Check if label imputation is defined in the preprocessing settings
if isfield(iPREPROC, 'LABELMOD') && isfield(iPREPROC.LABELMOD, 'LABELIMPUTE') && ...
        ~strcmp(iPREPROC.LABELMOD.LABELIMPUTE.method, 'none')
    IMPUTE = iPREPROC.LABELMOD.LABELIMPUTE;
    IMPUTE.flag = true;
end

% Determine the number of classes from the first element of the label data
nclass = numel(mapY.TrL{1,1,1});

% Check in multi-label mode, whether training data has separate containers 
% for each label. label_dim' is set to the current multi-label dimension,
% if applicable.
label_dim = 1;
if MULTILABEL.curdim > 1
    if size(mapY.Tr{1,1,1}{1}, 2) > 1
        label_dim = MULTILABEL.curdim;
    end
end

% Loop over all partitions of the data: m (e.g., repetitions), n (e.g.,
% folds), and o (e.g., iterations)
for i = 1:m
    for j = 1:n
        for k = 1:o
            % Check if binary mode is active or stacking is enabled.
            % In these cases, data are expected to be organized in separate
            % containers per class.
            if BINMOD || STACKING.flag == 1
                % Preallocate cell arrays for each class in the current partition
                mapYi.Tr{i,j,k} = cell(1, nclass);
                mapYi.CV{i,j,k} = cell(1, nclass);
                mapYi.Ts{i,j,k} = cell(1, nclass);
                
                % Process each class individually
                for l = 1:nclass
                    % Check if the training data is further encapsulated in a cell
                    if iscell(mapY.Tr{i,j,k}{l})
                        % Extract the specific dimension and label container
                        mapYi.Tr{i,j,k}{l} = mapY.Tr{i,j,k}{l}{dim_index, label_dim};
                        mapYi.CV{i,j,k}{l} = mapY.CV{i,j,k}{l}{dim_index, label_dim};
                        mapYi.Ts{i,j,k}{l} = mapY.Ts{i,j,k}{l}{dim_index, label_dim};
                        
                        % If available, extract the VI field similarly
                        if isfield(mapYi, 'VI')
                            mapYi.VI{i,j,k}{l} = mapY.VI{i,j,k}{l}{dim_index, label_dim};
                        end
                    else
                        % If data is not nested further, directly assign the cell content
                        mapYi.Tr{i,j,k}{l} = mapY.Tr{i,j,k}{l};
                        mapYi.CV{i,j,k}{l} = mapY.CV{i,j,k}{l};
                        mapYi.Ts{i,j,k}{l} = mapY.Ts{i,j,k}{l};
                        if isfield(mapYi, 'VI')
                            mapYi.VI{i,j,k}{l} = mapY.VI{i,j,k}{l};
                        end
                    end
                    
                    % Apply label imputation for the training labels.
                    % Different indexing is used if the label data has a third dimension.
                    if size(mapY.TrL, 3) > 1
                        [mapYi.TrL{i,j,k}{l}, mapYi.Tr{i,j,k}{l}, mapYi.TrInd{i,j,k}{l}] = ...
                            nk_LabelImputer(mapY.TrL{i,j,k}{l}, mapYi.Tr{i,j,k}{l}, mapYi.TrInd{i,j,k}{l}, cPs{l}, IMPUTE);
                    else
                        [mapYi.TrL{i,j}{l}, mapYi.Tr{i,j,k}{l}, mapYi.TrInd{i,j}{l}] = ...
                            nk_LabelImputer(mapY.TrL{i,j}{l}, mapYi.Tr{i,j,k}{l}, mapYi.TrInd{i,j}{l}, cPs{l}, IMPUTE);
                    end
                end
            else
                % For non-binary mode and when stacking is not enabled,
                % extract the dimension directly from each cell.
                if iscell(mapY.Tr{i,j,k})
                    mapYi.Tr{i,j,k} = mapY.Tr{i,j,k}{dim_index, label_dim};
                    mapYi.CV{i,j,k} = mapY.CV{i,j,k}{dim_index, label_dim};
                    mapYi.Ts{i,j,k} = mapY.Ts{i,j,k}{dim_index, label_dim};
                    if isfield(mapYi, 'VI')
                        mapYi.VI{i,j,k} = mapY.VI{i,j,k}{dim_index, label_dim};
                    end
                else
                    % If the cell is not nested, assign the data directly.
                    mapYi.Tr{i,j,k} = mapY.Tr{i,j,k};
                    mapYi.CV{i,j,k} = mapY.CV{i,j,k};
                    mapYi.Ts{i,j,k} = mapY.Ts{i,j,k};
                    if isfield(mapYi, 'VI')
                        mapYi.VI{i,j,k} = mapY.VI{i,j,k};
                    end
                end
                
                % For each class, apply label imputation to the training labels (nk_LabelImputer checks if this is needed).
                for l = 1:nclass
                    if size(mapY.TrL, 3) > 1
                        [mapYi.TrL{i,j,k}{l}, mapYi.Tr{i,j,k}, mapYi.TrInd{i,j,k}{l}] = ...
                            nk_LabelImputer(mapY.TrL{i,j,k}{l}, mapYi.Tr{i,j,k}, mapYi.TrInd{i,j,k}{l}, cPs{l}, IMPUTE);
                    else
                        [mapYi.TrL{i,j}{l}, mapYi.Tr{i,j}, mapYi.TrInd{i,j}{l}] = ...
                            nk_LabelImputer(mapY.TrL{i,j}{l}, mapYi.Tr{i,j}, mapYi.TrInd{i,j}{l}, cPs{l}, IMPUTE);
                    end
                end
            end
        end
    end
end
function [sY, IN] = nk_PerfWActObj(Y, IN)
% Applies precomputed weight vectors to input data using soft or hard feature selection.
%
% Usage:
%   [sY, IN] = nk_PerfWActObj(Y, IN)
%
% Inputs:
%   Y               - MxN data matrix (cases x features), or cell array of such matrices.
%   IN              - Structure with required fields:
%     W              - NxP weight vector/matrix.
%     W_ACT          - Structure with parameters:
%        .softflag   - Selection mode: 1=soft (weight exponentiation),
%                      2=hard percentile, 3=hard absolute, 4=hard top-k.
%        .opt        - Hyperparameter index for nk_ReturnParam.
%        .Params_desc- Descriptor for parameters used by nk_ReturnParam.
%        .clustflag  - 0=no clustering, 1=cluster suprathreshold features (3D data).
%        .threshvec  - Percentile vector for hard selection (optional).
%     Mask           - Predefined mask for clustering (optional).
%
% Outputs:
%   sY              - Output data: Mx(K*P) matrix with features weighted or selected
%                     for each of the P weight vectors, concatenated horizontally.
%   IN              - Updated input structure, with added fields:
%     .Weights      - NxP matrix of computed soft-selection weights.
%     .Thresh       - 1xP vector of threshold values for hard selection.
%     .ind          - NxP logical indices of selected features.
%     .WMask        - 1xP cell array of masks used for clustering outputs.
%
% The function supports both:
%   * Soft feature selection: exponentiate weight vectors and multiply features.
%   * Hard feature selection: threshold weights by percentile, absolute value,
%     or top-k ranking, with optional clustering for 3D data.
%
% Dependencies: nk_ReturnParam, nk_Cluster, nk_ExtractClusterData
%
% (c) Nikolaos Koutsouleris, 03/2021; Updated 04/2025

% =========================== WRAPPER FUNCTION ============================
if iscell(Y) && exist('IN','var') && ~isempty(IN)
    sY = cell(1, numel(Y));
    for i = 1:numel(Y)
        [sY{i}, IN] = PerfWActObj(Y{i}, IN);
    end
else
    [sY, IN] = PerfWActObj(Y, IN);
end

% =========================================================================
function [nY, IN] = PerfWActObj(Y, IN)
global VERBOSE

% Validate inputs
if isempty(IN)
    error('Input structure IN is missing. See help nk_PerfWActObj.');
end
if ~isfield(IN, 'W_ACT')
    error('W_ACT substructure is missing in IN.');
end
if ~isfield(IN, 'W')
    error('Weight vector/matrix W is missing in IN.');
end
if ~isfield(IN, 'Mask')
    IN.Mask = [];
end

nW = size(IN.W, 2);
nY = [];

% Loop over each weight vector
for i = 1:nW

    % Retrieve parameters
    if isfield(IN.W_ACT, 'opt') && isfield(IN.W_ACT, 'Params_desc')
        opt = IN.W_ACT.opt;
        Params_desc = IN.W_ACT.Params_desc;
    else
        error('Missing opt or Params_desc in W_ACT.');
    end
 
    switch IN.W_ACT.softflag
        case 1  % Soft feature selection
            if ~isfield(IN, 'Weights') || isempty(IN.Weights)
                if i == 1
                    IN.Weights = zeros(size(IN.W));
                    IN.ind = true(size(IN.W));
                end
                ExpMult = nk_ReturnParam('ExpMult', Params_desc, opt);
                IN.Weights(:, i) = IN.W(:, i) .^ ExpMult;
            end
            Yi = Y .* IN.Weights(:, i)';
            if VERBOSE, fprintf('\tApplied soft weights.\n'); end

        case {2, 3, 4, 5}  % Hard feature selection
            if i == 1
                IN.ind = false(size(IN.W));
                IN.Thresh = zeros(1, nW);
            end
            % Determine threshold value
            switch IN.W_ACT.softflag
                case 2
                    pct = nk_ReturnParam('Thresholds', Params_desc, opt);
                    IN.Thresh(i) = percentile(IN.W(:, i), pct);
                case 3
                    IN.Thresh(i) = nk_ReturnParam('Absolute thresholds', Params_desc, opt);
                case 4
                    IN.Thresh(i) = nk_ReturnParam('Top feats', Params_desc, opt);
                case 5
                    IN.Thresh(i) = nk_ReturnParam('Cutoffs', Params_desc, opt);
            end

            if IN.W_ACT.clustflag == 1
                % Cluster suprathreshold features (3D data)
                if isempty(IN.Mask)
                    Wthresh = zeros(size(IN.W(:, i)));
                    switch IN.W_ACT.softflag
                        case {2, 3}
                            IN.ind(:, i) = IN.W(:, i) > IN.Thresh(i);
                            Wthresh(IN.ind(:, i)) = IN.W(IN.ind(:, i), i);
                        case 4
                            [~, sInd] = sort(IN.W(:, i), 'descend');
                            IN.ind(sInd(1:IN.Thresh(i)), i) = true;
                            Wthresh(IN.ind(:, i)) = IN.W(IN.ind(:, i), i);
                        case 5
                            sInd = IN.W_ACT.operator(IN.W(:,i), IN.Thresh(i)) & isfinite(IN.W(:,i));
                            IN.ind(sInd, i) = true;
                            Wthresh(IN.ind(:, i)) = IN.W(IN.ind(:, i), i);
                    end
                    IN.WMask{i} = nk_Cluster(Wthresh, IN.W_ACT);
                else
                    IN.WMask{i} = IN.Mask;
                end
                Yi = nk_ExtractClusterData(Y, IN.WMask{i});
                if VERBOSE, fprintf('\tClusterized into %d regions.\n', nk_Range(IN.WMask{i})); end
            else
                % Select features without clustering
                switch IN.W_ACT.softflag
                    case {2, 3}
                        IN.ind(:, i) = IN.W(:, i) >= IN.Thresh(i);
                        Yi = Y(:, IN.ind(:, i));
                        if VERBOSE, fprintf('\tSelected %d of %d features at threshold %.2f.\n', size(Yi,2), size(Y,2), IN.Thresh(i)); end
                    case 4
                        [~, sInd] = sort(IN.W(:, i), 'descend');
                        IN.ind(sInd(1:IN.Thresh(i)), i) = true;
                        Yi = Y(:, IN.ind(:, i));
                        if VERBOSE, fprintf('\tSelected top %d features.\n', IN.Thresh(i)); end
                    case 5
                        sInd = IN.W_ACT.operator(IN.W(:,i), IN.Thresh(i)) & isfinite(IN.W(:,i));
                        IN.ind(sInd, i) = true;
                        Yi = Y(:, IN.ind(:, i));
                        if VERBOSE, fprintf('\tSelected %d features by applying %s on %g.\n', nnz(sInd), func2str(IN.W_ACT.operator), IN.Thresh(i)); end
                end
            end

        otherwise
            error('Invalid value for softflag: must be 1, 2, 3, 4, or 5.');
    end

    % Concatenate output for multiple weight vectors
    nY = [nY, Yi];

end


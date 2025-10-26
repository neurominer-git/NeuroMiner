% =========================================================================
% [L, X, IND] = nk_LabelImputer(L, X, IND, Params, IMPUTE)
% =========================================================================
%
% DESCRIPTION:
%   Imputes missing label values in the label matrix L based on the
%   imputation method specified in the IMPUTE structure. When IMPUTE.flag 
%   is true, the function propagates labels either using a machine learning
%   (ML) approach (via the user-defined prediction function referenced by
%   the global PREDICTFUNC) or by employing a nearest neighbor (NN) based
%   method. If imputation is not enabled (IMPUTE.flag is false), the function
%   removes instances (rows) where labels are missing.
%
% INPUTS:
%   L       - Matrix of labels, where each column corresponds to a different label.
%   X       - Feature matrix corresponding to the labels in L.
%   IND     - Logical vector indicating valid entries in L and X.
%   Params  - Parameter structure used for ML-based imputation.
%   IMPUTE  - Structure containing imputation settings:
%               .flag   : Boolean flag indicating whether imputation should be performed.
%               .method : Imputation method to use ('ml' for machine learning-based,
%                         any other non-'none' value for NN-based, 'none' to skip).
%
% OUTPUTS:
%   L       - Updated label matrix with imputed values (or pruned if imputation not applied).
%   X       - Feature matrix (unchanged when imputation is performed).
%   IND     - Updated logical vector after removal of rows with missing labels if imputation is off.
%
% GLOBAL VARIABLES:
%   PREDICTFUNC - Function handle for the ML-based prediction function used for label propagation.
%
% DEPENDENT FUNCTIONS:
%   nk_GetParam2         - Retrieves model parameters and fits the ML model.
%   nk_PerfImputeLabelObj - Performs NN-based label imputation.
%
% =========================================================================
% (c) Nikolaos Koutsouleris, 03/2025

function [L, X, IND] = nk_LabelImputer(L, X, IND, Params, IMPUTE)
global PREDICTFUNC

% Check if imputation is enabled.
if IMPUTE.flag 
    % Save the current feature matrix to the IMPUTE structure for further use.
    IMPUTE.X = X;
    
    % Loop through each label column.
    for i = 1:size(L,2)
        if strcmp(IMPUTE.method, 'ml')
            % ----- ML-Based Imputation -----
            % Identify indices with non-missing labels and valid entries.
            indf = ~isnan(L(:, i)) & IND;
            % Define training data: features and labels that are valid.
            X_tr = X(indf, :);
            L_tr = L(indf, i);
            % Define test data: features corresponding to missing labels.
            X_ts = X(~indf, :);
            L_ts = zeros(sum(~indf), 1);  % Placeholder labels for prediction
            
            % Fit the model using the provided parameters.
            [~, model] = nk_GetParam2(X_tr, L_tr, Params, 1);
            % Predict missing labels using the user-defined prediction function.
            L(~indf, i) = PREDICTFUNC(X_tr, X_ts, L_ts, model);
            
        elseif ~strcmp(IMPUTE.method, 'none')
            % ----- NN-Based Imputation -----
            % Use nearest neighbor based label propagation.
            L(:, i) = nk_PerfImputeLabelObj(L(:, i), IMPUTE);
        end
    end
else
    % If imputation is disabled, remove rows with any missing label values.
    indf = sum(isnan(L), 2) > 0;
    L(indf, :) = [];
    X(indf, :) = [];
    IND(indf) = [];
end

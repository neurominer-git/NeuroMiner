function [tY, Fx] = nk_ExtractFeatures(Y, F, Ytest, indF)
% =========================================================================
% [tY, Fx] = nk_ExtractFeatures(Y, F, Ytest, indF)
% =========================================================================
% This function processes one or more datasets (training and optionally tes-
% ting) to extract and/or select specific features based on a feature mask. 
% The feature extraction can be specified for each dataset individually, 
% and the datasets can be either concatenated or processed separately.
%
% Inputs:
%   Y      - Cell array or matrix containing the training data. Each cell 
%            or column corresponds to one variable.
%   F      - Cell array or matrix specifying the feature masks for each 
%            variable in Y. 
%            Each cell should contain a logical or numerical array 
%            indicating the features to be retained.
%   Ytest  - (Optional) Cell array or matrix containing the testing data. 
%            Must have the same structure as Y.
%   indF   - Index or indices specifying which dimensions of the feature 
%            masks in F to use.
%
% Outputs:
%   tY     - The transformed version of Y (and optionally Ytest), with 
%            feature selection applied as specified by F.
%            If Y is a cell array and consists of only one variable, tY 
%            will be returned as a matrix or vector.
%   Fx     - The final feature mask used to extract features from Y (and 
%            Ytest). This output helps in understanding
%            which features were actually selected or transformed during 
%            the processing.
%
% Details:
%   The function first checks if Y is a cell array, indicating multiple 
%   variables (or datasets). It then processes each variable separately:
%     - If Ytest is empty, it directly extracts or selects features based on F.
%     - If Ytest is provided, it concatenates Y and Ytest before applying 
%       the feature mask, allowing for combined processing.
%   If F is empty for a variable, no feature selection is applied, and all 
%   original features are retained. The function supports custom feature 
%   masks for each variable by using a helper function `prep_fmask`, which 
%   computes the actual feature indices based on the input mask F and index 
%   specification indF.
% =========================================================================
% (c) Nikolaos Koutsouleris, 07/2024

if iscell(Y)
    nvar    = size(Y,2);
    tY      = cell(1,nvar);
    for v=1:nvar
        if isempty(Ytest)
            if isempty(F)
                tY{v} = Y{v};
            else
                D = size(Y{v},2);
                Fx = prep_fmask(D, F{v}, indF);
                    tY{v} = Y{v}(:,Fx);
            end
        else % Concatenate Training and Test data
            if isempty(F)
                tY{v} = [Y{v}; Ytest{v}];
            else
                Fx = prep_fmask(D, F{v}, indF);
                tY{v} = [Y{v}(:,Fx); Ytest{v}(:,Fx)];
            end
        end
    end
    if nvar == 1, tY = tY{1}; end
else
    if isempty(Ytest)
        if isempty(F)
            tY = Y;
        else
            D = size(Y,2);
            Fx = prep_fmask(D, F, indF);
            tY = Y(:,Fx);
        end
    else
        if isempty(F)
            tY = [Y; Ytest];
        else
            D = size(Y,2);
            Fx = prep_fmask(D, F, indF);
            tY = [Y(:,Fx); Ytest(:,Fx)]; 
        end
    end
end

function Fx = prep_fmask(D, F, indF)

if size(F,2) == 1 && sum(any(F,2)) == numel(F)
    Fx = F;
else
    Fx = logical(F(1:D,indF));
end
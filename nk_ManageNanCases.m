% ========================================================================================
% [Y, label, I, NanStats] = nk_ManageNanCases(Y, label, I, act)
% ========================================================================================
%
% DESCRIPTION:
%   This function processes rows (cases) in the input data matrix Y and the
%   corresponding label matrix by handling NaN values. Depending on the
%   specified action ('act'), it either removes rows with NaNs or computes
%   statistics about the distribution of NaNs:
%
%   - 'prune': Remove rows where all elements are NaN.
%   - 'prune_single': Remove rows that contain any NaN.
%   - 'inform': Compute and return statistics on the NaN distribution in Y.
%
%   Optionally, if a logical indicator vector I is provided (or computed),
%   the function can "reinsert" the pruned rows as rows filled with NaNs.
%
% INPUTS:
%   Y     - Data matrix (observations x features), which can be numeric or a cell array.
%   label - (Optional) Label matrix corresponding to Y. Default is [].
%   I     - (Optional) Logical vector (length = number of original observations)
%           indicating rows to be treated as NaN cases.
%   act   - (Optional) Action to perform. Options are:
%             'prune'        : Remove rows where all entries are NaN.
%             'prune_single' : Remove rows with any NaN.
%             'inform'       : Return statistics on NaN distribution.
%           Default is 'prune'.
%
% OUTPUTS:
%   Y        - Updated data matrix after processing NaN cases.
%   label    - Updated label matrix after processing NaN cases.
%   I        - Logical vector indicating which rows were identified as NaN cases.
%   NanStats - Structure containing NaN statistics in Y (only computed for act = 'inform').
% =========================================================================================
% (c) Nikolaos Koutsouleris, 03/2025 

function [Y, label, I, NanStats] = nk_ManageNanCases(Y, label, I, act)

% Set default for label if not provided.
if ~exist('label', 'var'), label = []; end
% Set default action if not provided.
if ~exist('act', 'var') || isempty(act), act = 'prune'; end

NanStats = [];  % Initialize NaN statistics structure.

switch act    
    case {'prune', 'prune_single'}
        % If I is not provided, compute it based on the desired pruning criteria.
        if ~exist('I', 'var') || isempty(I)
            [~, n] = size(Y);
            if strcmp(act, 'prune')
                % Flag rows where all elements are NaN.
                I = sum(isnan(Y), 2) == n;
            elseif strcmp(act, 'prune_single')
                % Flag rows where at least one element is NaN.
                I = sum(isnan(Y), 2) > 0;
            end
            % Remove the flagged rows from Y (and label if provided).
            if any(I)
                Y(I, :) = [];
                if ~isempty(label)
                    label(I, :) = [];
                end
            end
        elseif ~isempty(I) && any(I)
            % If I is provided and non-empty, "reinsert" NaN rows into the matrices.
            if ~isempty(Y)
                if iscell(Y)
                    % Process each cell if Y is a cell array.
                    for i = 1:size(Y, 1)
                        for j = 1:size(Y, 2)
                            Y{i, j} = FillWithNan(Y{i, j}, I);
                        end
                    end
                else
                    Y = FillWithNan(Y, I);
                end
            end
            % Process label matrix similarly.
            if ~isempty(label)
                L = zeros(numel(I), size(label, 2));
                for i = 1:size(label, 2)
                    L(:, i) = FillWithNan(label(:, i), I);
                end
                label = L;
            end
        end
        
    case 'inform'
        % Compute statistics on the occurrence of NaN values.
        [m, n] = size(Y); 
        I = []; % No changes to Y; I is not used in 'inform' mode.
        NanStats.NanMat = isnan(Y);
        
        % Percentage of NaNs per feature (column)
        NanStats.Feats = sum(NanStats.NanMat) * 100 / m;
        % Percentage of NaNs per case (row)
        NanStats.Cases = sum(NanStats.NanMat, 2) * 100 / n;
        
        % Compute additional statistics for cases/features with specific NaN percentages.
        NanStats.Cases25 = NanStats.Cases > 25 & NanStats.Cases <= 50;
        NanStats.Feats25 = NanStats.Feats > 25 & NanStats.Feats <= 50;
        NanStats.Cases25Perc = sum(NanStats.Cases25) * 100 / m;
        NanStats.Feats25Perc = sum(NanStats.Feats25) * 100 / n;
        
        NanStats.Cases50 = NanStats.Cases > 50 & NanStats.Cases <= 99;
        NanStats.Feats50 = NanStats.Feats > 50 & NanStats.Feats <= 99;
        NanStats.Cases50Perc = sum(NanStats.Cases50) * 100 / m;
        NanStats.Feats50Perc = sum(NanStats.Feats50) * 100 / n;
        
        NanStats.Cases100 = NanStats.Cases == 100;
        NanStats.Feats100 = NanStats.Feats == 100;
        NanStats.Cases100Perc = sum(NanStats.Cases100) * 100 / m;
        NanStats.Feats100Perc = sum(NanStats.Feats100) * 100 / n;
end

end

%% Subfunction: FillWithNan
function Z = FillWithNan(Z, I)
% FILLWITHNAN: Reinserts NaN rows into a matrix based on a logical indicator.
%
% USAGE:
%   Z = FillWithNan(Z, I)
%
% DESCRIPTION:
%   Given a pruned matrix Z (with only non-NaN rows) and a logical vector I 
%   (with length equal to the original number of observations), this function
%   returns a new matrix with size [numel(I) x size(Z,2)]. The rows corresponding
%   to "false" in I are filled with the original data from Z, while the rows 
%   corresponding to "true" remain as NaN.
%
% INPUTS:
%   Z - Data matrix that has been pruned (only non-NaN rows remain).
%   I - Logical vector (length equals original number of rows) where true 
%       indicates that the row should be NaN.
%
% OUTPUT:
%   Z - Reconstructed data matrix of size [numel(I) x size(Z,2)] with NaN rows reinserted.
% ========================================================================================
% (c) Nikolaos Koutsouleris, 03/2025

[~, n] = size(Z);
% Preallocate a new matrix filled with NaN.
newZ = nan(numel(I), n);
% Ensure that the number of non-NaN rows in Z matches the expected count.
if size(Z, 1) ~= sum(~I)
    error('Size mismatch: The number of non-NaN rows in Z does not match the expected value based on I.');
end
% Insert the original data into the non-NaN positions.
newZ(~I, :) = Z;
Z = newZ;
end

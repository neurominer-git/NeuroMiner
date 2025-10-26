function S = gowerSimilarity(X, varTypes)
% gowerSimilarity computes the pairwise Gower similarity matrix.
%
%   S = gowerSimilarity(X)
%   S = gowerSimilarity(X, varTypes)
%
%   Inputs:
%     - X: An n-by-p matrix or table where each row is an observation and
%          each column is a variable.
%     - varTypes: (Optional) A 1-by-p cell array specifying the type of each
%          variable. Use 'numeric' for continuous variables and 'categorical'
%          for categorical variables. If omitted, it is inferred automatically.
%
%   Output:
%     - S: An n-by-n similarity matrix with values between 0 and 1.
%
%   Example:
%       % Example data: 3 observations, 2 numeric variables, 1 categorical variable.
%       X = [1.2, 3.4, 1;
%            2.3, 3.8, 2;
%            1.8, 3.6, 1];
%       S = gowerSimilarity(X);  % varTypes will be inferred automatically.
%

% If varTypes not provided, infer from X.
if nargin < 2 || isempty(varTypes)
    varTypes = inferVarTypes(X);
end

% Convert table to array if needed.
if istable(X)
    X = table2array(X);
end

[n, p] = size(X);
S = zeros(n);

% Pre-compute ranges for numeric variables.
ranges = zeros(1, p);
for k = 1:p
    if strcmpi(varTypes{k}, 'numeric')
        col = X(:, k);
        % Exclude NaN values when computing the range.
        colNoNaN = col(~isnan(col));
        if isempty(colNoNaN)
            ranges(k) = 1;  % default if all values are missing
        else
            ranges(k) = max(colNoNaN) - min(colNoNaN);
            if ranges(k) == 0
                ranges(k) = 1; % avoid division by zero if constant
            end
        end
    end
end

% Compute pairwise similarities.
for i = 1:n
    for j = i:n  % matrix is symmetric
        simSum = 0;
        validCount = 0;
        for k = 1:p
            % Skip variable if either value is missing.
            if isnan(X(i,k)) || isnan(X(j,k))
                continue;
            end
            validCount = validCount + 1;
            if strcmpi(varTypes{k}, 'numeric')
                % For numeric: similarity based on normalized difference.
                sim_k = 1 - abs(X(i,k) - X(j,k)) / ranges(k);
            elseif strcmpi(varTypes{k}, 'categorical')
                % For categorical: similarity is 1 if equal, 0 otherwise.
                sim_k = double(X(i,k) == X(j,k));
            else
                error('Unknown variable type: %s', varTypes{k});
            end
            simSum = simSum + sim_k;
        end
        
        % Assign average similarity, or NaN if no valid comparisons.
        if validCount > 0
            S(i,j) = simSum / validCount;
        else
            S(i,j) = NaN;
        end
        S(j,i) = S(i,j); % maintain symmetry.
    end
end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function varTypes = inferVarTypes(X, uniqueThreshold)
% inferVarTypes infers variable types for each column of X.
%
%   varTypes = inferVarTypes(X)
%   varTypes = inferVarTypes(X, uniqueThreshold)
%
%   The function checks each column of X. If the column is of a categorical
%   type (or is a cell array of strings/characters or a string array), it is
%   labeled as 'categorical'. For numeric (or logical) columns, if the number
%   of unique (non-missing) values is less than or equal to uniqueThreshold
%   (default is 10), the variable is classified as 'categorical'; otherwise,
%   it is classified as 'numeric'.
%
%   Example:
%       X = [1, 2, 2; 3, 2, 1; 5, 2, 3];
%       varTypes = inferVarTypes(X);
%

if nargin < 2
    uniqueThreshold = 10;  % default threshold for numeric columns.
end

% Determine the number of columns.
if istable(X)
    p = width(X);
else
    [~, p] = size(X);
end

varTypes = cell(1, p);

for k = 1:p
    % Extract column k.
    if istable(X)
        colData = X{:, k};
    else
        colData = X(:, k);
    end

    % Check if the column is already categorical.
    if iscategorical(colData)
        varTypes{k} = 'categorical';
    elseif iscell(colData)
        % If it's a cell array, check if all entries are characters or strings.
        if all(cellfun(@(x) ischar(x) || isstring(x), colData))
            varTypes{k} = 'categorical';
        else
            varTypes{k} = 'categorical'; % default to categorical.
        end
    elseif isnumeric(colData) || islogical(colData)
        % For numeric/logical arrays, decide based on unique values.
        uniqueVals = unique(colData(~isnan(colData)));
        if numel(uniqueVals) <= uniqueThreshold
            varTypes{k} = 'categorical';
        else
            varTypes{k} = 'numeric';
        end
    elseif isstring(colData)
        varTypes{k} = 'categorical';
    else
        % Fallback: classify as categorical.
        varTypes{k} = 'categorical';
    end
end

end

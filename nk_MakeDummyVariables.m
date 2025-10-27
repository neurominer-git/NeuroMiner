function [Dummy, Dummynum, Fu, Removed] = nk_MakeDummyVariables(V, vec, mode, unmatch)
% NK_MAKEDUMMYVARIABLES Create dummy (one-hot) variables from a vector.
%
% Syntax:
%   [Dummy, Dummynum, Fu, Removed] = nk_MakeDummyVariables(V)
%   [Dummy, Dummynum, Fu, Removed] = nk_MakeDummyVariables(V, vec)
%   [Dummy, Dummynum, Fu, Removed] = nk_MakeDummyVariables(V, vec, mode)
%   [Dummy, Dummynum, Fu, Removed] = nk_MakeDummyVariables(V, vec, mode, unmatch)
%
% Description:
%   This function converts a vector V of categorical values into a dummy
%   variable matrix (one-hot encoding). Each row of the dummy matrix
%   corresponds to an observation (if V is a column vector) or each column
%   corresponds to an observation (if V is a row vector). It also returns a 
%   numeric vector indicating the category index for each observation and a 
%   vector of unique categories (Fu). The function allows you to specify how 
%   to handle observations that do not match any category via the 'unmatch'
%   parameter.
%
% Inputs:
%   V       - A vector (numeric or string) containing the data to encode.
%             Must be a vector (row or column).
%   vec     - (Optional) A vector of categories to use. If provided, the
%             unique values in V will be ignored and vec will be used.
%   mode    - (Optional) A string to be passed to the UNIQUE function. Default
%             is 'stable' (which preserves the order of appearance).
%   unmatch - (Optional) How to handle observations in V that do not match any
%             category. Options are:
%                 'NaN'    - Label unmatched observations with NaN (default).
%                 '0'      - Label unmatched observations with 0.
%                 'remove' - Remove unmatched observations from the outputs.
%
% Outputs:
%   Dummy    - A binary matrix representing the dummy (indicator) variables.
%              For a column vector V, each row corresponds to an observation.
%              For a row vector V, each column corresponds to an observation.
%   Dummynum - A numeric vector indicating the category index for each observation.
%   Fu       - A vector of unique categories used (from V or provided via vec).
%   Removed  - (Only when unmatch is 'remove') A boolean vector of length equal
%              to the original number of observations indicating which observations
%              were removed. If unmatch is not 'remove', this is returned as [].
%
% Example:
%   V = {'apple','banana','apple','cherry','banana','date'};
%   [Dummy, Dummynum, Fu, Removed] = nk_MakeDummyVariables(V, [], 'stable', 'remove');
%
% Author: Nikolaos Koutsouleris
% Date: 01/02/2025
% Version: 1.1

% Set defaults for optional parameters
if ~exist('mode','var') || isempty(mode)
    mode = 'stable';
end
if ~exist('unmatch','var') || isempty(unmatch)
    unmatch = 'NaN';
end

% Ensure V is a vector
[m, n] = size(V);
if m > 1 && n > 1
    error('Only vector operations are supported!');
end

% Determine the number of observations (nObs)
if m > 1
    nObs = m;
else
    nObs = n;
end

% Determine the unique categories to use
if exist('vec','var') && ~isempty(vec)
    Fu = vec;
    nFu = numel(vec);
else
    Fu = unique(rmmissing(V), mode);
    nFu = numel(Fu);
end

% Preallocate the dummy matrix
if m > 1
    % V is a column vector: each row is an observation.
    Dummy = false(nObs, nFu);
else
    % V is a row vector: each column is an observation.
    Dummy = false(nFu, nObs);
end

% Fill in the dummy matrix based on category matches
for i = 1:nFu
    try
        ind = V == Fu(i);
    catch
        ind = strcmp(V, Fu{i});
    end
    if m > 1
        Dummy(ind, i) = true;
    else
        Dummy(i, ind) = true;
    end
end

% Determine the category index for each observation.
if m > 1
    [~, Dummynum] = max(Dummy, [], 2);
else
    [~, Dummynum] = max(Dummy, [], 1);
    Dummynum = Dummynum(:);  % Ensure it's a column vector.
end

% Identify observations that did not match any category.
if m > 1
    Ix = sum(Dummy, 2) == 0;
else
    Ix = (sum(Dummy, 1)' == 0);  % Ensure a column vector.
end

% Initialize the fourth output variable.
Removed = [];

% Handle observations that did not match any category.
switch lower(unmatch)
    case 'nan'
        Dummy = double(Dummy);
        if m > 1
            Dummy(Ix, :) = NaN;
            Dummynum(Ix) = NaN;
        else
            Dummy(:, Ix) = NaN;
            Dummynum(Ix) = NaN;
        end
    case '0'
        Dummy = double(Dummy);
        if m > 1
            Dummy(Ix, :) = 0;
            Dummynum(Ix) = 0;
        else
            Dummy(:, Ix) = 0;
            Dummynum(Ix) = 0;
        end
    case 'remove'
        % Save the indices of removed observations in the fourth output.
        Removed = Ix;
        if m > 1
            Dummy(Ix, :) = [];
            Dummynum(Ix) = [];
        else
            Dummy(:, Ix) = [];
            Dummynum(Ix) = [];
        end
    otherwise
        error('Unknown unmatch option. Please use ''NaN'', ''0'', or ''remove''.');
end
function idx = nk_SelectSpatialBranches(branchTable, uPREPROC, nBranches)
% nk_SelectSpatialBranches - Select trained subject-spatial branches by identity.
%
% Purpose
%   Select the resident spatial shelves required by one trained preprocessing
%   chain using the authoritative branch table produced during materialization.
%
% Syntax
%   idx = nk_SelectSpatialBranches(branchTable, uPREPROC, nBranches)
%
% Inputs
%   branchTable
%       Metadata produced by nk_PerfSpatialChain for one binary classifier.
%   uPREPROC
%       PREPROC with the current classifier's optimized parameter values restored.
%   nBranches
%       Number of resident shelves in the data container being selected.
%
% Outputs
%   idx
%       Logical column vector selecting the requested shelves in branch order.
%
% Authority and flow
%   branchTable is the sole branch-identity authority. Smoothing-kernel side
%   arrays and matrix dimensions are not alternative metadata sources.
%
% Scientific/state contract and invariants
%   Table branch identifiers must be contiguous 1:nBranches. Every selected
%   spatial step's PX.opt row must match the corresponding materialized step row.
%   Multi-step criteria are combined conjunctively.
%
% Materialization and performance
%   Metadata-only linear scan over branches; no data or file access.
%
% Failure semantics
%   Missing metadata, branch-count disagreement, noncontiguous identities, or an
%   unavailable requested value raise explicit errors. No mask is padded or
%   truncated.
%
% Side effects
%   None.
%
% Consumers and dependencies
%   Called by nk_PerfPreprocessSpatial during nk_ApplyTrainedPreproc and training
%   replay. Depends on nk_NormalizeSpatialSteps.

if nargin < 3 || isempty(nBranches) || ~isscalar(nBranches) || nBranches < 1
    error('nk_SelectSpatialBranches:InvalidBranchCount', ...
        'nBranches must be a positive scalar.');
end
if isempty(branchTable) || ~isstruct(branchTable) || ~all(isfield(branchTable, ...
        {'branch','step','opt'}))
    error('nk_SelectSpatialBranches:MissingBranchMetadata', ...
        'A canonical spatial branch table is required to select precomputed shelves.');
end

branches = unique([branchTable.branch], 'stable');
if numel(branches) ~= nBranches || ~isequal(branches(:)', 1:nBranches)
    error('nk_SelectSpatialBranches:BranchTableMismatch', ...
        ['The resident shelf contains %g branches, but its metadata defines a ' ...
         'different or noncontiguous branch sequence.'], nBranches);
end

idx = true(nBranches,1);
criteria = requested_step_criteria(uPREPROC);

if ~isempty(criteria)
    idx(:) = false;
    for i = 1:nBranches
        rows = branchTable([branchTable.branch] == i);
        keep = true;
        for q = 1:numel(criteria)
            keep = keep && rows_match(rows, criteria(q));
        end
        idx(i) = keep;
    end
end

if ~any(idx)
    error('nk_SelectSpatialBranches:RequestedBranchUnavailable', ...
        'No resident subject-spatial shelf matches the trained preprocessing parameters.');
end
end

function tf = rows_match(rows, criterion)
tf = false;
for r = 1:numel(rows)
    if rows(r).step == criterion.step
        tf = option_matches(rows(r).opt, criterion.options);
        if tf
            return
        end
    end
end
end

function criteria = requested_step_criteria(PREPROC)
criteria = struct('step',{},'options',{});
steps = nk_NormalizeSpatialSteps(PREPROC);
for i = 1:numel(steps)
    if ~isfield(steps(i),'PX') || ~isfield(steps(i).PX,'opt') || isempty(steps(i).PX.opt)
        continue
    end
    criterion.step = i;
    nParams = 1;
    if isfield(steps(i).PX,'Px') && ~isempty(steps(i).PX.Px)
        nParams = numel(steps(i).PX.Px);
    end
    criterion.options = normalize_options(steps(i).PX.opt, nParams);
    criteria(end+1) = criterion; %#ok<AGROW>
end
end

function options = normalize_options(options, nParams)
if isnumeric(options) || islogical(options)
    if nParams == 1 && isvector(options)
        options = options(:);
    elseif nParams > 1 && size(options,2) ~= nParams
        error('nk_SelectSpatialBranches:SpatialParameterWidthMismatch', ...
            'Spatial PX.opt has %g columns, but PX.Px defines %g parameters.', ...
            size(options,2), nParams);
    end
elseif isstring(options)
    options = options(:);
elseif ischar(options)
    options = cellstr(options);
elseif iscell(options)
    options = options(:);
else
    error('nk_SelectSpatialBranches:UnsupportedOptionType', ...
        'Spatial PX.opt values use an unsupported data type.');
end
end

function tf = option_matches(value, options)
if isnumeric(options) || islogical(options)
    tf = (isnumeric(value) || islogical(value)) && ...
        size(value,2) == size(options,2) && ismember(value, options, 'rows');
elseif isstring(options)
    tf = any(string(value) == options);
elseif iscell(options)
    tf = any(cellfun(@(candidate) isequaln(value,candidate), options));
else
    tf = false;
end
end

function PREPROC = nk_SetParamChain(paramfl, curclass, PREPROC)
% nk_SetParamChain - Restore optimized preprocessing values by source identity.
%
% Purpose
%   Write the optimized preprocessing values for one binary classifier into the
%   exact ACTPARAM or SPATIAL step from which each parameter was enumerated.
%
% Syntax
%   PREPROC = nk_SetParamChain(paramfl, curclass, PREPROC)
%
% Inputs
%   paramfl
%       Runtime parameter state produced by nk_PrepPreprocParams. PXfull carries
%       command, step, and Px indices; PXunique carries selected values per
%       binary classifier.
%   curclass
%       Binary/regression preprocessing-container index.
%   PREPROC
%       Fallback PREPROC returned unchanged when no optimized preprocessing
%       parameters are present.
%
% Outputs
%   PREPROC
%       PREPROC with selected values restored into the authoritative source
%       steps. Scalar legacy PREPROC.SPATIAL remains supported as spatial step 1.
%
% Authority and flow
%   nk_ReturnParamChain owns parameter source identity. This function is its
%   inverse and is the only writer of trained preprocessing values during shelf
%   materialization and shelf selection.
%
% Scientific/state contract and invariants
%   Each optimized column updates exactly one (command, step, Px index) tuple.
%   All nonoptimized parameters in the same step are preserved. Description
%   strings are display metadata and are never used to identify parameters.
%
% Materialization and performance
%   Metadata-only operation; no data or files are read.
%
% Failure semantics
%   Missing source identity, invalid class indices, column-count disagreement,
%   or malformed step PX structures raise explicit errors.
%
% Side effects
%   None; MATLAB copy-on-write semantics return the modified PREPROC value.
%
% Consumers and dependencies
%   Used by subject-spatial materialization/selection and CV-bound preprocessing.
%   Depends on allcomb2.

if ~isfield(paramfl,'PREPROC') || ~isfield(paramfl,'PXfull') || isempty(paramfl.PXfull)
    return
end
if ~isfield(paramfl.PXfull,'paramindex')
    error('nk_SetParamChain:MissingParameterIdentity', ...
        'PXfull does not contain the source Px indices required for deterministic restoration.');
end
if ~isfield(paramfl,'PXunique') || curclass < 1 || curclass > numel(paramfl.PXunique)
    error('nk_SetParamChain:InvalidBinaryIndex', ...
        'No optimized preprocessing values are available for binary classifier #%g.', curclass);
end

PREPROC = paramfl.PREPROC;
selected = paramfl.PXunique{curclass};
nParams = numel(paramfl.PXfull.Params);
if size(selected,2) ~= nParams
    error('nk_SetParamChain:ParameterColumnMismatch', ...
        'Expected %g preprocessing parameter columns for binary #%g, but received %g.', ...
        nParams, curclass, size(selected,2));
end

commands = paramfl.PXfull.cmd;
if ischar(commands)
    commands = cellstr(commands);
end
isSpatial = strcmp(commands,'spatialfilter');
stepVector = paramfl.PXfull.steps(:);

actSteps = unique(stepVector(~isSpatial), 'stable');
for q = 1:numel(actSteps)
    stepIndex = actSteps(q);
    columns = find(~isSpatial & stepVector == stepIndex);
    if ~isfield(PREPROC,'ACTPARAM') || stepIndex > numel(PREPROC.ACTPARAM)
        error('nk_SetParamChain:MissingActParamStep', ...
            'Optimized preprocessing refers to missing ACTPARAM step #%g.', stepIndex);
    end
    PREPROC.ACTPARAM{stepIndex}.PX = rebuild_px( ...
        PREPROC.ACTPARAM{stepIndex}.PX, columns, paramfl.PXfull.paramindex, selected);
end

spatialSteps = unique(stepVector(isSpatial), 'stable');
for q = 1:numel(spatialSteps)
    stepIndex = spatialSteps(q);
    columns = find(isSpatial & stepVector == stepIndex);
    step = get_spatial_step(PREPROC, stepIndex);
    step.PX = rebuild_px(step.PX, columns, paramfl.PXfull.paramindex, selected);
    PREPROC = set_spatial_step(PREPROC, stepIndex, step);
end
end

function PX = rebuild_px(originalPX, columns, paramIndices, selected)
if ~isstruct(originalPX) || ~isfield(originalPX,'Px') || isempty(originalPX.Px)
    error('nk_SetParamChain:MalformedPX', ...
        'The parameter source step has no PX.Px definition.');
end
PX = originalPX;
for z = 1:numel(originalPX.Px)
    hit = columns(paramIndices(columns) == z);
    if numel(hit) > 1
        error('nk_SetParamChain:DuplicateParameterIdentity', ...
            'More than one optimized column maps to Px index #%g.', z);
    elseif isempty(hit)
        values = originalPX.Px(z).Params;
    else
        values = unique(selected(:,hit), 'stable')';
    end
    PX.Px(z).Params = values;
end
parameterValues = arrayfun(@(p) p.Params, PX.Px, 'UniformOutput', false);
PX.opt = allcomb2(parameterValues, 'matlab');
end

function step = get_spatial_step(PREPROC, stepIndex)
if ~isfield(PREPROC,'SPATIAL') || stepIndex > numel(PREPROC.SPATIAL)
    error('nk_SetParamChain:MissingSpatialStep', ...
        'Optimized preprocessing refers to missing SPATIAL step #%g.', stepIndex);
end
if iscell(PREPROC.SPATIAL)
    step = PREPROC.SPATIAL{stepIndex};
else
    step = PREPROC.SPATIAL(stepIndex);
end
end

function PREPROC = set_spatial_step(PREPROC, stepIndex, step)
if iscell(PREPROC.SPATIAL)
    PREPROC.SPATIAL{stepIndex} = step;
else
    PREPROC.SPATIAL(stepIndex) = step;
end
end

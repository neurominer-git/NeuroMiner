function PX = nk_ReturnParamChain(PO, optimonly)
% nk_ReturnParamChain - Enumerate preprocessing parameters with source identity.
%
% Purpose
%   Return preprocessing parameters in the order used by model optimization.
%   Subject-spatial parameters are enumerated separately for every
%   PREPROC.SPATIAL step while preserving the legacy scalar ordering.
%
% Syntax
%   PX = nk_ReturnParamChain(PO, optimonly)
%
% Inputs
%   PO
%       One PREPROC structure, one standalone preprocessing-step structure, or
%       a cell array of modality-specific PREPROC structures.
%   optimonly
%       When true, return only parameters with more than one candidate value.
%
% Outputs
%   PX
%       Parameter description with Params, Params_desc, Typ, cmd, steps,
%       paramindex, stepparams, and Cartesian product opt. For cmd
%       'spatialfilter', steps is the PREPROC.SPATIAL index. For other commands,
%       steps is the PREPROC.ACTPARAM index. paramindex identifies the exact Px
%       element inside that step.
%
% Authority and flow
%   This function owns preprocessing-parameter enumeration. nk_GenPreML uses
%   its positional output to append preprocessing dimensions to the model grid;
%   nk_SetParamChain uses the explicit source identity to restore selected
%   values without matching display labels.
%
% Scientific/state contract
%   Every returned parameter maps to exactly one source tuple
%   (command, step index, Px index). Spatial-chain steps are never collapsed into
%   one legacy PREPROC.SPATIAL.PX entry.
%
% Invariants and failure semantics
%   Parameter metadata arrays have identical lengths. Malformed PX structures
%   fail explicitly. No parameter is inferred from its description.
%
% Materialization and performance
%   Metadata-only operation. It performs no file access and does not touch data
%   matrices.
%
% Side effects
%   None.
%
% Consumers and dependencies
%   Used by nk_GenPreML, nk_PrepPreprocParams, nk_SetParamChain callers, and
%   preprocessing bookkeeping. Depends on allcomb2.

if nargin < 2 || isempty(optimonly)
    optimonly = false;
end

if iscell(PO)
    nP = numel(PO);
    PX = repmat(empty_output(), 1, nP);
    for n = 1:nP
        PX(n) = enumerate_one(PO{n}, optimonly);
    end
else
    PX = enumerate_one(PO, optimonly);
    if isempty(PX.Params)
        PX = [];
    end
end
end

function out = enumerate_one(PREPROC, optimonly)
out = empty_output();
if ~isstruct(PREPROC) || numel(PREPROC) ~= 1
    error('nk_ReturnParamChain:InvalidPreproc', ...
        'Each preprocessing container must be one scalar structure.');
end

% Standalone preprocessing-step structures retain the legacy top-level PX path.
if isfield(PREPROC,'PX') && ~isempty(PREPROC.PX) && isfield(PREPROC.PX,'Px')
    cmd = '';
    if isfield(PREPROC,'cmd') && ~isempty(PREPROC.cmd)
        cmd = char(PREPROC.cmd);
    end
    out = append_px(out, PREPROC.PX.Px, optimonly, cmd, 1, PREPROC, false, 1);
else
    % CV-bound ACTPARAM parameters retain their established reverse order.
    if isfield(PREPROC,'ACTPARAM') && ~isempty(PREPROC.ACTPARAM)
        for i = numel(PREPROC.ACTPARAM):-1:1
            step = PREPROC.ACTPARAM{i};
            if ~isfield(step,'PX') || isempty(step.PX) || ~isfield(step.PX,'Px')
                continue
            end
            if ~isfield(step,'cmd') || isempty(step.cmd)
                error('nk_ReturnParamChain:MissingCommand', ...
                    'PREPROC.ACTPARAM{%g} has parameters but no cmd identity.', i);
            end
            out = append_px(out, step.PX.Px, optimonly, char(step.cmd), ...
                i, step, false, 1);
        end
    end

    % Subject-spatial parameters follow execution order and retain their exact
    % PREPROC.SPATIAL index.
    if isfield(PREPROC,'SPATIAL') && ~isempty(PREPROC.SPATIAL)
        spatialSteps = normalize_spatial_container(PREPROC.SPATIAL);
        nSpatial = numel(spatialSteps);
        for s = 1:nSpatial
            step = spatialSteps{s};
            if ~isfield(step,'PX') || isempty(step.PX) || ~isfield(step.PX,'Px')
                continue
            end
            out = append_px(out, step.PX.Px, optimonly, 'spatialfilter', ...
                s, step, nSpatial > 1, s);
        end
    end
end

if ~isempty(out.Params)
    out.opt = allcomb2(out.Params, 'matlab');
end
validate_output(out);
end

function out = append_px(out, Px, optimonly, cmd, stepIndex, step, decorate, spatialIndex)
[params, descriptions, types, paramIndices] = retrieve_from_struct(Px, optimonly);
for q = 1:numel(params)
    desc = descriptions{q};
    if decorate
        desc = sprintf('%s_{S%g}', desc, spatialIndex);
    end
    out.Params{end+1} = params{q};
    out.Params_desc{end+1} = desc;
    out.Typ{end+1} = types{q};
    out.cmd{end+1,1} = cmd;
    out.steps(end+1) = stepIndex;
    out.paramindex(end+1) = paramIndices(q);
    out.stepparams{end+1} = step;
end
end

function [Params, Params_desc, Typ, indices] = retrieve_from_struct(Px, optimonly)
required = {'Params','Params_desc','Typ'};
for r = 1:numel(required)
    if ~isfield(Px,required{r})
        error('nk_ReturnParamChain:MalformedPX', ...
            'PX.Px is missing required field %s.', required{r});
    end
end
indices = 1:numel(Px);
if optimonly
    keep = arrayfun(@(p) numel(p.Params) > 1, Px);
    indices = indices(keep);
end
Params = arrayfun(@(p) p.Params, Px(indices), 'UniformOutput', false);
Params_desc = arrayfun(@(p) p.Params_desc, Px(indices), 'UniformOutput', false);
Typ = arrayfun(@(p) p.Typ, Px(indices), 'UniformOutput', false);
end

function steps = normalize_spatial_container(S)
if iscell(S)
    steps = S(:)';
else
    steps = arrayfun(@(x) x, S, 'UniformOutput', false);
end
for s = 1:numel(steps)
    if ~isstruct(steps{s}) || numel(steps{s}) ~= 1
        error('nk_ReturnParamChain:InvalidSpatialStep', ...
            'PREPROC.SPATIAL step #%g must be one scalar structure.', s);
    end
end
end

function out = empty_output()
out = struct('Params',{{}}, 'Params_desc',{{}}, 'Typ',{{}}, 'cmd',{{}}, ...
    'steps',[], 'paramindex',[], 'stepparams',{{}}, 'opt',[]);
end

function validate_output(out)
n = numel(out.Params);
lengths = [numel(out.Params_desc), numel(out.Typ), numel(out.cmd), ...
    numel(out.steps), numel(out.paramindex), numel(out.stepparams)];
if any(lengths ~= n)
    error('nk_ReturnParamChain:MetadataLengthMismatch', ...
        'Preprocessing parameter metadata arrays do not have identical lengths.');
end
end

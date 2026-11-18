function Param = nm_preproc_spatial_param_from_context(Y, ctx)
% nm_preproc_spatial_param_from_context  Build the legacy spatial-parameter structure required by spatial preprocessing scaffold execution.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.
%
% ctx.Vm: field consumed from ctx to preserve the caller's configured UI/API/scaffold state.
% ctx.Vmvol: field consumed from ctx to preserve the caller's configured UI/API/scaffold state.
% ctx.datatype: field consumed from ctx to preserve the caller's configured UI/API/scaffold state.
% ctx.indNonRem: field consumed from ctx to preserve the caller's configured UI/API/scaffold state.

if nargin < 2 || isempty(ctx), ctx = struct(); end
nFeat = size(Y,2);
Param = struct();
Param.dimvecx = [0 nFeat];
Param.datatype = 1; % image modality
Param.brainmask = {local_get(ctx,'brainmask','')};
Param.badcoords = {local_get(ctx,'badcoords',[])};
Param.threshval = local_get(ctx,'threshval', local_get(ctx,'spatialThresh', []));
Param.threshop  = local_get(ctx,'threshop',  local_get(ctx,'spatialThreshOp', []));
if isempty(Param.threshval), Param.threshval = []; end
if isempty(Param.threshop), Param.threshop = []; end
if isfield(ctx,'datatype') && ~isempty(ctx.datatype), Param.datatype = ctx.datatype; end
if Param.datatype == 2
    Param.surfaceGeometryContract = ctx.surfaceGeometryContract;
    if ~ctx.surfaceSpatialAvailable
        error('nm_preproc_spatial_param_from_context:missingSurfaceMesh', ...
            'Surface spatial preprocessing requires DataIO-validated non-inflated geometry matching the vertex axis.');
    end
end
if isfield(ctx,'Vm') && ~isempty(ctx.Vm), Param.Vm = ctx.Vm; end
if isfield(ctx,'Vmvol') && ~isempty(ctx.Vmvol), Param.Vmvol = ctx.Vmvol; end
if isfield(ctx,'indNonRem') && ~isempty(ctx.indNonRem), Param.indNonRem = ctx.indNonRem; end
if Param.datatype == 1 && isempty(Param.brainmask{1})
    error('nm_preproc_spatial_param_from_context:missingBrainmask', ...
        ['Subject-spatial preprocessing in the matrix scaffold requires Context.brainmask ', ...
         'or a full NM-derived context with image geometry.']);
end
end
function v = local_get(s, f, d)
% local_get  Read a struct field with an explicit fallback while preserving caller-provided values.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

v = d;
if isstruct(s) && isfield(s,f), v = s.(f); end
end

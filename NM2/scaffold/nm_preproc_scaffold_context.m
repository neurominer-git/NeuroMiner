function ctx = nm_preproc_scaffold_context(baseCtx, labelTrain, covarsTrain, labelTest, covarsTest)
% nm_preproc_scaffold_context  Assemble the context structure shared by preprocessing scaffold fit and transform functions.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 1 || isempty(baseCtx)
    ctx = struct();
elseif isstruct(baseCtx)
    ctx = baseCtx;
else
    ctx = struct();
    ctx.brainmask = baseCtx;
end
if nargin >= 2, ctx.labelTrain = labelTrain; end
if nargin >= 3, ctx.covarsTrain = covarsTrain; end
if nargin >= 4, ctx.labelTest = labelTest; end
if nargin >= 5, ctx.covarsTest = covarsTest; end
if ~isfield(ctx,'modality') || isempty(ctx.modality)
    if isfield(ctx,'brainmask') && ~isempty(ctx.brainmask)
        ctx.modality = 'image';
        ctx.isImaging = true;
    else
        ctx.modality = 'matrix';
        ctx.isImaging = false;
    end
end
end

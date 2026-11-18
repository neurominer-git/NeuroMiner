function s = nm_preproc_scaffold_context_summary(ctx)
% nm_preproc_scaffold_context_summary  Summarize a preprocessing scaffold context for reports and generated-code comments.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.
%
% ctx.covarsTrain: training covariates supplied to preprocessing scaffold contexts.
% ctx.labelTrain: training labels supplied to preprocessing scaffold contexts.

s = struct();
if nargin < 1 || isempty(ctx), return; end
fn = {'modality','brainmask','datatype','threshval','threshop','varind','executionStage'};
for i=1:numel(fn)
    if isfield(ctx,fn{i}), s.(fn{i}) = ctx.(fn{i}); end
end
if isfield(ctx,'labelTrain'), s.hasLabelTrain = ~isempty(ctx.labelTrain); end
if isfield(ctx,'covarsTrain'), s.hasCovarsTrain = ~isempty(ctx.covarsTrain); end
end

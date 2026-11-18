function [branches, info] = nm_preproc_scaffold_apply_subject_spatial(Y, orch, ctx)
% nm_preproc_scaffold_apply_subject_spatial  Apply subject-level spatial preprocessing branches through the scaffold context.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

branches = {Y};
info = struct('used',false,'branchTable',struct([]),'message','No subject-spatial steps.');
if isempty(orch) || isempty(orch.SubjectSequence) || orch.SubjectSequence.numSteps() == 0
    return;
end
PREPROC = orch.SubjectSequence.toLegacy(orch.SubjectSequence.Context);
if ~isfield(PREPROC,'SPATIAL') || isempty(PREPROC.SPATIAL)
    return;
end
if exist('nk_PerfSpatialChain','file') ~= 2
    error('nm_preproc_scaffold_apply_subject_spatial:missingBackend', 'nk_PerfSpatialChain.m is required for subject-spatial scaffold execution.');
end
Param = nm_preproc_spatial_param_from_context(Y, ctx);
[branches, branchTable] = nk_PerfSpatialChain(Y, PREPROC, Param);
if ~iscell(branches), branches = {branches}; end
info.used = true;
info.branchTable = branchTable;
info.message = sprintf('Subject-spatial preprocessing generated %d branch(es).', numel(branches));
end

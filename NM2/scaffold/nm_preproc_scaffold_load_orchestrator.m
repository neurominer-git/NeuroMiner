function [orch, state] = nm_preproc_scaffold_load_orchestrator(pipeline, ctx)
% nm_preproc_scaffold_load_orchestrator  Load or reconstruct a preprocessing orchestrator from a scaffold pipeline definition.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 2 || isempty(ctx), ctx = struct(); end
if ischar(pipeline) || isstring(pipeline)
    fp = char(pipeline);
    if ~exist(fp,'file'), error('nm_preproc_scaffold_load_orchestrator:missingFile','Config file not found: %s', fp); end
    state = NMConfigTools.charifyStrings(NMConfigTools.readJson(fp));
elseif isa(pipeline,'NMPreprocOrchestrator')
    orch = pipeline;
    state = orch.toUIState();
    return;
elseif isstruct(pipeline)
    state = NMConfigTools.charifyStrings(pipeline);
else
    error('nm_preproc_scaffold_load_orchestrator:badInput','Pipeline must be a UI config file, state struct, or NMPreprocOrchestrator.');
end
orch = NMPreprocOrchestrator([], [], ctx);
orch.applyUIState(state, ctx);
end

function [orch, report] = nm_train_template_apply_snapshot(orch, snapshotFile, confirmApply, ctx, options)
% nm_train_template_apply_snapshot  Apply a saved training-template snapshot to an orchestrator after the required confirmation gate.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.
%
% options.allowHardErrors: field consumed from options to preserve the caller's configured UI/API/scaffold state.

if nargin < 3 || ~isequal(confirmApply, true)
    error('NMTrainTemplateSnapshot:confirmationRequired', ...
        'Snapshot apply requires explicit confirmation after preview.');
end
if nargin < 4 || isempty(ctx), ctx = struct(); end
if nargin < 5 || isempty(options), options = struct(); end

preview = nm_train_template_load_snapshot_preview(orch.NM, snapshotFile, ctx, orch.VarIndex);
allowHardErrors = false;
try, allowHardErrors = logical(options.allowHardErrors); catch, end
if preview.nErrors > 0 && ~allowHardErrors
    error('NMTrainTemplateSnapshot:hardErrors', ...
        'Snapshot has hard compatibility errors. Default action is not to apply.');
end

S = load(snapshotFile);
if isfield(S,'snapshot')
    snapshot = S.snapshot;
else
    fn = fieldnames(S);
    snapshot = S.(fn{1});
end
if isfield(snapshot,'TrainParam') && isstruct(snapshot.TrainParam)
    TP = snapshot.TrainParam;
elseif isfield(snapshot,'NM') && isstruct(snapshot.NM) && isfield(snapshot.NM,'TrainParam')
    TP = snapshot.NM.TrainParam;
else
    error('NMTrainTemplateSnapshot:noTrainParam','Snapshot does not contain TrainParam.');
end
NMnew = orch.NM;
if ~isfield(NMnew,'TrainParam') || ~isstruct(NMnew.TrainParam), NMnew.TrainParam = struct(); end
NMnew.TrainParam = TP;
loaded = NMTrainTemplateOrchestrator.fromNM(NMnew, orch.VarIndex, ctx);
local_copy_orchestrator_state(orch, loaded);
state = orch.menuState();
report = struct('ok',true, 'message','Snapshot applied after explicit confirmation.', ...
    'preview',preview, 'state',state, 'audit',state.audit, 'auditSummary',state.auditSummary);
end

function local_copy_orchestrator_state(dst, src)
% local_copy_orchestrator_state  Perform the local copy orchestrator state step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

props = {'NM','VarIndex','FusionFlag','FusionModalities','NumModalities','ModalityLabels','ModalityIsImaging', ...
    'Preproc','Stacking','StackingCandidates','StackingAvailable','StackingPreproc','MLGlobal','MLStrat', ...
    'AlternativeLabel','AlternativeLabelSourceVar','CVPartition','Synth','RFE','Multi','Vis','MLI','SAV'};
for i = 1:numel(props)
    try, dst.(props{i}) = src.(props{i}); catch, end
end
end

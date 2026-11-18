function [snapshot, outFile] = nm_train_template_save_snapshot(orch, outFile, ctx, metadata)
% nm_train_template_save_snapshot  Persist the current training-template orchestrator state as a reusable snapshot.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 2 || isempty(outFile), outFile = pwd; end
if nargin < 3 || isempty(ctx), ctx = struct(); end
if nargin < 4 || isempty(metadata), metadata = struct(); end

if exist(outFile,'dir') == 7
    outFile = fullfile(outFile, ['NMTrainTemplateSnapshot_' datestr(now,'yyyymmdd_HHMMSS') '.mat']);
end
[parentDir,~,ext] = fileparts(outFile);
if isempty(ext), outFile = [outFile '.mat']; end
if ~isempty(parentDir) && exist(parentDir,'dir') ~= 7
    mkdir(parentDir);
end

state = orch.menuState();
if isfield(state,'audit'), audit = state.audit; else, audit = orch.auditCurrentState(state); end
summary = orch.auditSummary(audit);
canvas = orch.canvasState(state, audit);

NMview = orch.NM;
try
    NMview = orch.toNM(NMview, ctx);
catch ME
    warning('NMTrainTemplateSnapshot:toNMFailed', ...
        'Could not materialize full TrainParam before snapshot save: %s', ME.message);
end

TP = struct();
if isfield(NMview,'TrainParam') && isstruct(NMview.TrainParam)
    TP = NMview.TrainParam;
elseif isfield(orch.NM,'TrainParam') && isstruct(orch.NM.TrainParam)
    TP = orch.NM.TrainParam;
end

snapshot = struct();
snapshot.type = 'NMTrainTemplateSnapshot';
snapshot.schemaVersion = 1;
snapshot.timestamp = datestr(now, 30);
snapshot.createdBy = 'nm_train_template_save_snapshot';
snapshot.version = local_version_info();
snapshot.modalityCount = local_get(state,'numModalities',orch.NumModalities);
snapshot.modalityLabels = local_get(state,'modalityLabels',orch.ModalityLabels);
snapshot.imagingFlags = local_get(state,'modalityIsImaging',orch.ModalityIsImaging);
snapshot.modeFlag = local_modeflag(NMview, orch.NM);
snapshot.effectiveLabel = local_effective_label_info(NMview, state);
snapshot.fusionState = struct('flag',local_get(state,'fusionFlag',orch.FusionFlag), ...
    'modalities',local_get(state,'fusionModalities',orch.FusionModalities), ...
    'activeModality',local_get(state,'activeModality',orch.VarIndex));
snapshot.TrainParam = TP;
snapshot.orchestratorState = state;
snapshot.audit = audit;
snapshot.auditSummary = summary;
snapshot.canvas = canvas;
snapshot.scaffoldExportMetadata = metadata;
snapshot.note = ['This file stores a lightweight NM.TrainParam browser-template snapshot. ' ...
    'It must be previewed for compatibility before applying to another NM object.'];

save(outFile, 'snapshot', '-v7');
end

function v = local_get(s, name, defaultVal)
% local_get  Read a struct field with an explicit fallback while preserving caller-provided values.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

v = defaultVal;
try
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), v = s.(name); end
catch
    v = defaultVal;
end
end

function mode = local_modeflag(NMview, NMbase)
% local_modeflag  Perform the local modeflag step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

mode = '';
try, mode = char(string(NMview.modeflag)); catch, end
if isempty(mode)
    try, mode = char(string(NMbase.modeflag)); catch, end
end
end

function info = local_effective_label_info(NMview, state)
% local_effective_label_info  Perform the local effective label info step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

info = struct();
info.modeFlag = local_modeflag(NMview, struct());
info.altLabelEnabled = local_get(state,'altLabelEnabled',false);
info.altLabelName = local_get(state,'altLabelName','');
info.altLabelSourceVar = local_get(state,'altLabelSourceVar','');
try
    if isfield(NMview,'label') && ~isempty(NMview.label)
        info.nObservations = size(NMview.label,1);
        info.labelSize = size(NMview.label);
    else
        info.nObservations = [];
        info.labelSize = [];
    end
catch
    info.nObservations = [];
    info.labelSize = [];
end
end

function v = local_version_info()
% local_version_info  Perform the local version info step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

v = struct('neuroMiner','', 'matlab','', 'source','best-effort');
try
    vv = ver('NeuroMiner');
    if ~isempty(vv), v.neuroMiner = vv.Version; end
catch
end
try
    v.matlab = version;
catch
end
end

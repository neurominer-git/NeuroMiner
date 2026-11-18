function preview = nm_train_template_load_snapshot_preview(currentNM, snapshotFile, ctx, varind)
% nm_train_template_load_snapshot_preview  Preview the effects of loading a training-template snapshot without mutating the active NM state.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 3 || isempty(ctx), ctx = struct(); end
if nargin < 4, varind = []; end
if nargin < 2 || isempty(snapshotFile)
    error('NMTrainTemplateSnapshot:missingFile','A snapshot filename is required.');
end
if exist(snapshotFile,'file') ~= 2
    error('NMTrainTemplateSnapshot:notFound','Snapshot file not found: %s', snapshotFile);
end

snapshot = local_load_snapshot(snapshotFile);
TP = local_trainparam_from_snapshot(snapshot);

NMtmp = currentNM;
if ~isfield(NMtmp,'TrainParam') || ~isstruct(NMtmp.TrainParam), NMtmp.TrainParam = struct(); end
NMtmp.TrainParam = TP;

tmpOrch = NMTrainTemplateOrchestrator.fromNM(NMtmp, varind, ctx);
state = tmpOrch.menuState();
audit = tmpOrch.auditCurrentState(state);
audit = local_with_category(audit, 'unknown/manual review');
compatItems = local_compatibility_items(currentNM, snapshot, state, audit);
if isempty(audit)
    compatibility = compatItems;
elseif isempty(compatItems)
    compatibility = audit;
else
    compatibility = [audit(:); compatItems(:)];
end
summary = tmpOrch.auditSummary(compatibility);
category = local_overall_category(compatibility);

preview = struct();
preview.type = 'NMTrainTemplateSnapshotPreview';
preview.schemaVersion = 1;
preview.sourceFile = snapshotFile;
preview.timestamp = local_get(snapshot,'timestamp','');
preview.snapshotType = local_get(snapshot,'type','');
preview.snapshotSchemaVersion = local_get(snapshot,'schemaVersion',[]);
preview.modalityCompatibility = local_modality_text(currentNM, snapshot);
preview.highestSeverity = summary.severity;
preview.nErrors = summary.nErrors;
preview.nWarnings = summary.nWarnings;
preview.nInfo = summary.nInfo;
preview.category = category;
preview.compatibilityItems = compatibility;
preview.audit = audit;
preview.auditSummary = summary;
preview.topMessages = local_top_messages(compatibility, 5);
preview.canApply = summary.nErrors == 0;
preview.defaultAction = ternary(preview.canApply, 'preview-confirm-then-apply', 'do-not-apply');
end

function snapshot = local_load_snapshot(file)
% local_load_snapshot  Perform the local load snapshot step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

S = load(file);
if isfield(S,'snapshot') && isstruct(S.snapshot)
    snapshot = S.snapshot;
    return;
end
fn = fieldnames(S);
for i = 1:numel(fn)
    if isstruct(S.(fn{i}))
        snapshot = S.(fn{i});
        return;
    end
end
error('NMTrainTemplateSnapshot:invalidFile','The MAT-file does not contain a snapshot struct.');
end

function TP = local_trainparam_from_snapshot(snapshot)
% local_trainparam_from_snapshot  Perform the local trainparam from snapshot step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if isfield(snapshot,'TrainParam') && isstruct(snapshot.TrainParam)
    TP = snapshot.TrainParam;
elseif isfield(snapshot,'NM') && isstruct(snapshot.NM) && isfield(snapshot.NM,'TrainParam') && isstruct(snapshot.NM.TrainParam)
    TP = snapshot.NM.TrainParam;
else
    error('NMTrainTemplateSnapshot:noTrainParam','Snapshot does not contain a TrainParam struct.');
end
end

function items = local_compatibility_items(currentNM, snapshot, loadedState, audit)
% local_compatibility_items  Perform the local compatibility items step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

items = local_empty_items();
items(end+1) = local_item('snapshot.type','snapshot','info','Snapshot type', ...
    sprintf('Snapshot type=%s, schemaVersion=%s.', char(string(local_get(snapshot,'type','?'))), mat2str(local_get(snapshot,'schemaVersion',[]))), ...
    'snapshot','Preview before applying.','snapshot','unknown/manual review');
if ~isfield(snapshot,'type') || ~strcmp(char(string(snapshot.type)), 'NMTrainTemplateSnapshot')
    items(end).severity = 'warning';
    items(end).title = 'Unknown snapshot type';
    items(end).message = 'The file does not identify itself as NMTrainTemplateSnapshot.';
    items(end).category = 'unknown/manual review';
end
curN = local_num_modalities_current(currentNM);
snapN = local_get(snapshot,'modalityCount',[]);
if isempty(snapN) || ~isnumeric(snapN)
    items(end+1) = local_item('snapshot.modalities.unknown','fusion','warning','Snapshot modality count unknown', ...
        'The snapshot does not contain modality-count metadata.', 'fusion','Review modality routing manually.','fusionModalities','unknown/manual review');
elseif double(snapN) == double(curN)
    items(end+1) = local_item('snapshot.modalities.compatible','fusion','ok','Modality count compatible', ...
        sprintf('Snapshot and current NM both expose %d modality/modalities.', curN), 'fusion','','fusionModalities','compatible');
else
    items(end+1) = local_item('snapshot.modalities.mismatch','fusion','error','Modality count mismatch', ...
        sprintf('Snapshot contains %d modality/modalities, current NM contains %d.', double(snapN), double(curN)), ...
        'fusion','Do not apply blindly; rebuild or explicitly clear invalid modality branches.','fusionModalities','incompatible and must be cleared');
end
try
    M = double(loadedState.fusionModalities(:))';
    if any(~isfinite(M)) || any(M < 1) || any(M > curN)
        items(end+1) = local_item('snapshot.fusion.indices.invalid','fusion','error','Fusion modality indices invalid for current NM', ...
            sprintf('Loaded FUSION.M=%s is outside current modality range 1..%d.', mat2str(M), curN), ...
            'fusion','Correct FUSION.M before applying.','fusionModalities','incompatible and must be cleared');
    end
catch
    items(end+1) = local_item('snapshot.fusion.indices.unknown','fusion','warning','Fusion modality indices could not be checked', ...
        'Loaded fusion modality routing could not be parsed.', 'fusion','Review fusion routing manually.','fusionModalities','unknown/manual review');
end
try
    snapImg = logical(local_get(snapshot,'imagingFlags',[]));
    curImg = local_imaging_current(currentNM, curN);
    if ~isempty(snapImg) && numel(snapImg) == numel(curImg) && any(snapImg(:)' ~= curImg(:)')
        items(end+1) = local_item('snapshot.imaging.flags.changed','preproc','warning','Imaging flags differ', ...
            'Snapshot imaging/non-imaging modality flags differ from the current NM object.', ...
            'preproc','Review imaging-specific preprocessing cards.','preproc','compatible but needs update');
    elseif isempty(snapImg)
        items(end+1) = local_item('snapshot.imaging.flags.unknown','preproc','info','Imaging flags unavailable', ...
            'Snapshot does not contain imaging-flag metadata.', 'preproc','Review if preprocessing uses imaging-specific modules.','preproc','unknown/manual review');
    end
catch
end
try
    if isfield(loadedState,'preprocMixedEarlyFusionIllegal') && logical(loadedState.preprocMixedEarlyFusionIllegal)
        items(end+1) = local_item('snapshot.preproc.mixedEarlyFusion','preproc','warning','Mixed early-fusion preprocessing needs update', ...
            local_get(loadedState,'preprocMixedEarlyFusionMessage','Mixed early fusion contains incompatible preprocessing cards.'), ...
            'preproc','Open preprocessing and resolve marked cards.','preproc','compatible but needs update');
    end
catch
end
% Surface key audit-derived incompatibility classes without duplicating the audit rules.
ids = local_audit_ids(audit);
if any(contains(ids,'multi.enabled'))
    items(end+1) = local_item('snapshot.audit.multi.task','multi','warning','MULTI/task compatibility surfaced by audit', ...
        'Patch H reported MULTI settings in a non-multi-class task.', 'multi','Disable MULTI or switch label.','multi','incompatible but recoverable');
end
if any(contains(ids,'vis.modelspace'))
    items(end+1) = local_item('snapshot.audit.vis.dimref','vis','warning','VIS dimensionality-reference dependency surfaced by audit', ...
        'Patch H reported model-space permutation without dimensionality-reference preprocessing.', 'vis','Add required preprocessing or disable this VIS option.','vis','incompatible but recoverable');
end
if any(contains(ids,'mli.atlas'))
    items(end+1) = local_item('snapshot.audit.mli.atlas','mli','warning','MLI atlas compatibility surfaced by audit', ...
        'Patch H reported atlas/import compatibility issues.', 'mli','Review atlas binding/import in MLI.','mli','incompatible but recoverable');
end
end

function n = local_num_modalities_current(NM)
% local_num_modalities_current  Perform the local num modalities current step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

n = 1;
try
    if isfield(NM,'datadescriptor') && iscell(NM.datadescriptor), n = max(1,numel(NM.datadescriptor)); return; end
    if isfield(NM,'Y') && iscell(NM.Y), n = max(1,numel(NM.Y)); return; end
    if isfield(NM,'TrainParam') && isfield(NM.TrainParam,'PREPROC') && iscell(NM.TrainParam.PREPROC), n = max(1,numel(NM.TrainParam.PREPROC)); return; end
catch
end
end

function flags = local_imaging_current(NM, n)
% local_imaging_current  Perform the local imaging current step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

flags = false(1,n);
try
    if isfield(NM,'datadescriptor') && iscell(NM.datadescriptor)
        for i = 1:min(n,numel(NM.datadescriptor))
            d = NM.datadescriptor{i};
            flags(i) = isstruct(d) && ((isfield(d,'isImage') && logical(d.isImage)) || (isfield(d,'type') && contains(lower(char(string(d.type))),'image')));
        end
    end
catch
end
end

function ids = local_audit_ids(audit)
% local_audit_ids  Perform the local audit ids step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

ids = strings(1,numel(audit));
for i = 1:numel(audit)
    try, ids(i) = string(audit(i).id); catch, ids(i) = ""; end
end
end

function items = local_with_category(items, category)
% local_with_category  Perform the local with category step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if isempty(items), return; end
for i = 1:numel(items)
    if ~isfield(items, 'category') || isempty(items(i).category)
        items(i).category = category;
    end
end
end

function items = local_empty_items()
% local_empty_items  Create an empty items structure with the fixed schema expected by later code.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

items = struct('id',{}, 'scope',{}, 'severity',{}, 'title',{}, 'message',{}, ...
    'configurator',{}, 'action',{}, 'target',{}, 'category',{});
end

function item = local_item(id, scope, severity, title, message, configurator, action, target, category)
% local_item  Perform the local item step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if nargin < 9, category = 'unknown/manual review'; end
item = struct('id',char(string(id)), 'scope',char(string(scope)), 'severity',char(string(severity)), ...
    'title',char(string(title)), 'message',char(string(message)), 'configurator',char(string(configurator)), ...
    'action',char(string(action)), 'target',char(string(target)), 'category',char(string(category)));
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

function txt = local_modality_text(currentNM, snapshot)
% local_modality_text  Perform the local modality text step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

curN = local_num_modalities_current(currentNM);
snapN = local_get(snapshot,'modalityCount',[]);
if isempty(snapN)
    txt = sprintf('current=%d; snapshot=unknown', curN);
elseif double(snapN) == double(curN)
    txt = sprintf('compatible: %d modality/modalities', curN);
else
    txt = sprintf('mismatch: current=%d; snapshot=%d', curN, double(snapN));
end
end

function msgs = local_top_messages(items, n)
% local_top_messages  Perform the local top messages step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if nargin < 2, n = 5; end
msgs = {};
if isempty(items), return; end
rank = zeros(1,numel(items));
for i = 1:numel(items)
    sev = 'info';
    try, sev = lower(char(string(items(i).severity))); catch, end
    switch sev
        case 'error', rank(i) = 4;
        case 'warning', rank(i) = 3;
        case 'info', rank(i) = 2;
        case 'ok', rank(i) = 1;
    end
end
[~,ord] = sort(rank,'descend');
for k = 1:min(n,numel(ord))
    i = ord(k);
    try
        msgs{end+1} = sprintf('%s: %s', items(i).title, items(i).message); %#ok<AGROW>
    catch
    end
end
end

function cat = local_overall_category(items)
% local_overall_category  Perform the local overall category step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

cat = 'compatible';
if isempty(items), return; end
cats = strings(1,numel(items));
for i = 1:numel(items)
    try, cats(i) = string(items(i).category); catch, cats(i) = "unknown/manual review"; end
end
if any(cats == "incompatible and must be cleared")
    cat = 'incompatible and must be cleared';
elseif any(cats == "incompatible but recoverable")
    cat = 'incompatible but recoverable';
elseif any(cats == "compatible but needs update")
    cat = 'compatible but needs update';
elseif any(cats == "unknown/manual review")
    cat = 'unknown/manual review';
end
end

function y = ternary(cond, a, b)
% ternary  Perform the ternary step in the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if cond, y = a; else, y = b; end
end

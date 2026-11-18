function [ok, report, NMout] = run_nm_train_template_scaffold(NM, varargin)
% run_nm_train_template_scaffold  Validate or dry-run a saved training-template scaffold against an NM structure without launching model training.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 1 || isempty(NM), NM = struct(); end
opts = local_parse_inputs(varargin{:});
mode = lower(strtrim(char(opts.Mode)));
if ~ismember(mode, {'validate','dryrun'})
    error('run_nm_train_template_scaffold:badMode', ...
        'Unsupported Mode "%s". Patch I.1 supports only ''validate'' and ''dryrun''.', opts.Mode);
end

NMout = NM;
report = local_empty_report(mode, opts);
stages = local_empty_stages();

try
    if exist('NMTrainTemplateOrchestrator','class') ~= 8
        error('run_nm_train_template_scaffold:missingOrchestrator', ...
            'NMTrainTemplateOrchestrator is not on the MATLAB path. Run nm_add_modular_paths first.');
    end

    orch = NMTrainTemplateOrchestrator.fromNM(NM, opts.VarIndex, opts.Context);
    state = orch.menuState();
    audit = orch.auditCurrentState(state);
    summary = orch.auditSummary(audit);
    report.audit = audit;
    report.auditSummary = summary;
    report.menuState = state;
    stages(end+1) = local_stage('audit', local_status_from_summary(summary), ...
        local_audit_message(summary), '', {'audit'}, summary.nErrors > 0); %#ok<AGROW>

    if strcmp(mode, 'validate')
        report.stages = stages;
        ok = summary.nErrors == 0;
        report.ok = ok;
        report.stage = 'audit';
        return;
    end

    if summary.nErrors > 0
        stages(end+1) = local_stage('dryrun', 'skipped', ...
            'Dry-run materialization was skipped because the Patch H audit reported hard errors.', '', {'audit'}, false); %#ok<AGROW>
        report.stages = stages;
        ok = false;
        report.ok = false;
        report.stage = 'audit';
        return;
    end

    cvState = local_suppress_cv_side_effects(orch.CVPartition);
    orch.CVPartition = cvState;

    NMwork = NM;
    [st, NMstage] = local_try_stage('cv', @() local_stage_cv(NMwork, cvState), false);
    stages(end+1) = st; %#ok<AGROW>
    if strcmp(st.status,'ok'), NMwork = NMstage; end

    [st, NMstage] = local_try_stage('fusion', @() local_stage_fusion(NMwork, orch), false);
    stages(end+1) = st; %#ok<AGROW>
    if strcmp(st.status,'ok'), NMwork = NMstage; end

    [st, preprocDetails] = local_try_stage('preproc', @() local_stage_preproc(orch), false);
    stages(end+1) = st; %#ok<AGROW>
    report.preprocDryRun = preprocDetails;

    [st, mlDetails] = local_try_stage('ml', @() local_stage_ml(orch, opts.Context), false);
    stages(end+1) = st; %#ok<AGROW>
    report.mlDryRun = mlDetails;

    [st, NMstage] = local_try_stage('synth', @() local_stage_synth(NMwork, orch), false);
    stages(end+1) = st; %#ok<AGROW>
    if strcmp(st.status,'ok'), NMwork = NMstage; end

    [st, NMstage] = local_try_stage('multi', @() local_stage_multi(NMwork, orch), false);
    stages(end+1) = st; %#ok<AGROW>
    if strcmp(st.status,'ok'), NMwork = NMstage; end

    [st, NMstage] = local_try_stage('rfe', @() local_stage_rfe(NMwork, orch), false);
    stages(end+1) = st; %#ok<AGROW>
    if strcmp(st.status,'ok'), NMwork = NMstage; end

    [st, NMstage] = local_try_stage('vis', @() local_stage_vis(NMwork, orch), false);
    stages(end+1) = st; %#ok<AGROW>
    if strcmp(st.status,'ok'), NMwork = NMstage; end

    [st, NMstage] = local_try_stage('mli', @() local_stage_mli(NMwork, orch), false);
    stages(end+1) = st; %#ok<AGROW>
    if strcmp(st.status,'ok'), NMwork = NMstage; end

    [st, NMstage] = local_try_stage('sav', @() local_stage_sav(NMwork, orch), false);
    stages(end+1) = st; %#ok<AGROW>
    if strcmp(st.status,'ok'), NMwork = NMstage; end

    [st, NMout] = local_try_stage('legacy_materialization', @() local_stage_materialize(NM, orch, opts.Context), true);
    stages(end+1) = st; %#ok<AGROW>

    if strcmp(st.status, 'ok') || strcmp(st.status, 'warning')
        [st2, post] = local_try_stage('post_materialization_audit', @() local_stage_post_audit(NMout, opts.VarIndex, opts.Context), true);
        stages(end+1) = st2; %#ok<AGROW>
        report.postMaterializationAudit = post;
    end

    report.stages = stages;
    ok = ~local_has_fatal_errors(stages);
    report.ok = ok;
    report.okCriterion = 'true when the Patch H audit has no hard errors and fatal materialization/post-audit stages succeed; diagnostic probe warnings do not make ok=false.';
    report.stage = local_final_stage(stages);
catch ME
    stages(end+1) = local_stage('scaffold', 'error', ME.message, local_exception_text(ME), {'scaffold'}, true); %#ok<AGROW>
    report.stages = stages;
    report.ok = false;
    report.stage = 'scaffold';
    report.exception = local_exception_text(ME);
    ok = false;
    NMout = NM;
end
end

function opts = local_parse_inputs(varargin)
% local_parse_inputs  Parse inputs options into a fixed scaffold/bridge structure.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

opts = struct('Mode','validate', 'Context',struct(), 'VarIndex',[], 'StopOnError',false);
if mod(numel(varargin),2) ~= 0
    error('run_nm_train_template_scaffold:badOptions', 'Options must be name/value pairs.');
end
for i = 1:2:numel(varargin)
    key = char(string(varargin{i}));
    val = varargin{i+1};
    switch lower(key)
        case 'mode'
            opts.Mode = char(string(val));
        case {'context','ctx'}
            if isempty(val), val = struct(); end
            if ~isstruct(val), error('run_nm_train_template_scaffold:badContext', 'Context must be a struct.'); end
            opts.Context = val;
        case {'varindex','varind','activevar','activemodality'}
            opts.VarIndex = val;
        case 'stoponerror'
            opts.StopOnError = logical(val);
        otherwise
            error('run_nm_train_template_scaffold:badOption', 'Unknown option: %s', key);
    end
end
end

function report = local_empty_report(mode, opts)
% local_empty_report  Create an empty report structure with the fixed schema expected by later code.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% opts.Context: optional NM context structure used to resolve legacy state and diagnostics.

report = struct();
report.ok = false;
report.mode = mode;
report.version = 'Patch I.1';
report.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
report.stage = '';
report.contextSummary = local_context_summary(opts.Context);
report.audit = struct([]);
report.auditSummary = struct();
report.stages = local_empty_stages();
end

function s = local_context_summary(ctx)
% local_context_summary  Perform the local context summary step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

s = struct();
if ~isstruct(ctx), return; end
f = fieldnames(ctx);
s.fields = f(:)';
for i = 1:numel(f)
    v = ctx.(f{i});
    if isnumeric(v) || islogical(v)
        s.(f{i}) = size(v);
    elseif ischar(v) || isstring(v)
        s.(f{i}) = char(string(v));
    elseif iscell(v)
        s.(f{i}) = sprintf('cell[%s]', strjoin(string(size(v)), 'x'));
    elseif isstruct(v)
        s.(f{i}) = sprintf('struct[%s]', strjoin(string(size(v)), 'x'));
    else
        s.(f{i}) = class(v);
    end
end
end

function stages = local_empty_stages()
% local_empty_stages  Create an empty stages structure with the fixed schema expected by later code.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

stages = struct('id',{},'status',{},'message',{},'exception',{},'auditRefs',{},'fatal',{});
end

function st = local_stage(id, status, message, exception, auditRefs, fatal)
% local_stage  Execute or describe the stage dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if nargin < 4, exception = ''; end
if nargin < 5, auditRefs = {}; end
if nargin < 6, fatal = false; end
st = struct('id', char(string(id)), 'status', char(string(status)), ...
    'message', char(string(message)), 'exception', char(string(exception)), ...
    'auditRefs', {auditRefs}, 'fatal', logical(fatal));
end

function [stage, out] = local_try_stage(id, fn, fatalOnError)
% local_try_stage  Run the stage stage and convert exceptions into structured scaffold diagnostics.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if nargin < 3, fatalOnError = true; end
try
    [out, msg] = fn();
    if isempty(msg), msg = sprintf('%s dry-run stage completed.', id); end
    stage = local_stage(id, 'ok', msg, '', {id}, false);
catch ME
    out = [];
    if fatalOnError
        stage = local_stage(id, 'error', ME.message, local_exception_text(ME), {id}, true);
    else
        stage = local_stage(id, 'warning', ...
            sprintf('Diagnostic %s probe failed but full TrainParam materialization will still be tested: %s', id, ME.message), ...
            local_exception_text(ME), {id}, false);
    end
end
end

function txt = local_exception_text(ME)
% local_exception_text  Perform the local exception text step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

txt = '';
try
    txt = getReport(ME, 'extended', 'hyperlinks', 'off');
catch
    txt = ME.message;
end
end

function status = local_status_from_summary(summary)
% local_status_from_summary  Perform the local status from summary step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if isfield(summary,'nErrors') && summary.nErrors > 0
    status = 'error';
elseif isfield(summary,'nWarnings') && summary.nWarnings > 0
    status = 'warning';
else
    status = 'ok';
end
end

function msg = local_audit_message(summary)
% local_audit_message  Perform the local audit message step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if isfield(summary,'displayText') && ~isempty(summary.displayText)
    msg = summary.displayText;
else
    msg = 'Patch H audit completed.';
end
end

function cvState = local_suppress_cv_side_effects(cvState)
% local_suppress_cv_side_effects  Perform the local suppress cv side effects step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if isempty(cvState) || ~isstruct(cvState), cvState = struct(); end
cvState.cvBuildRequested = false;
cvState.cvLoadRequested = false;
cvState.cvSaveRequested = false;
end

function [NMout, msg] = local_stage_cv(NM, cvState)
% local_stage_cv  Execute or describe the cv dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

NMout = NM;
if exist('NMCVPartitionTools','class') ~= 8
    error('run_nm_train_template_scaffold:missingCVTools', 'NMCVPartitionTools is not on the MATLAB path.');
end
NMout = NMCVPartitionTools.applyToNM(NMout, cvState);
msg = 'Cross-validation TrainParam.RAND was materialized with build/load/save side effects suppressed.';
end

function [NMout, msg] = local_stage_fusion(NM, orch)
% local_stage_fusion  Execute or describe the fusion dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

NMout = NM;
if ~isfield(NMout,'TrainParam') || ~isstruct(NMout.TrainParam), NMout.TrainParam = struct(); end
NMout.TrainParam.FUSION.flag = orch.FusionFlag;
NMout.TrainParam.FUSION.M = orch.FusionModalities;
NMout.TrainParam.ActiveModality = orch.VarIndex;
msg = sprintf('Fusion routing materialized: flag=%d, active modality=%d.', orch.FusionFlag, orch.VarIndex);
end


function tf = local_is_stacking_enabled(orch)
% local_is_stacking_enabled  Perform the local is stacking enabled step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

tf = false;
if ~isprop(orch, 'Stacking') || isempty(orch.Stacking) || ~isstruct(orch.Stacking)
    return;
end
if ~isfield(orch.Stacking, 'flag') || isempty(orch.Stacking.flag)
    return;
end
try
    flag = round(double(orch.Stacking.flag));
    tf = isfinite(flag) && isequal(flag, 1);
catch
    tf = false;
end
end

function [details, msg] = local_stage_preproc(orch)
% local_stage_preproc  Execute or describe the preproc dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

details = struct('branches', {{}}, 'nBranches', 0);
branches = local_preproc_branches(orch);
for k = 1:numel(branches)
    idx = branches(k);
    if idx < 1 || idx > numel(orch.Preproc) || isempty(orch.Preproc{idx})
        error('run_nm_train_template_scaffold:badPreprocBranch', 'Invalid preprocessing branch index: %d.', idx);
    end
    PREPROC = orch.Preproc{idx}.toLegacyPreproc(); %#ok<NASGU>
    details.branches{end+1} = sprintf('PREPROC{%d}', idx); %#ok<AGROW>
end
if local_is_stacking_enabled(orch) && ~isempty(orch.StackingPreproc)
    PREPROC = orch.StackingPreproc.toLegacyPreproc(); %#ok<NASGU>
    details.branches{end+1} = 'STACKING.PREPROC';
end
details.nBranches = numel(details.branches);
msg = sprintf('Converted %d preprocessing branch(es) to legacy PREPROC structures.', details.nBranches);
end

function branches = local_preproc_branches(orch)
% local_preproc_branches  Perform the local preproc branches step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if local_is_stacking_enabled(orch)
    branches = [];
    return;
end
mods = orch.FusionModalities;
if isempty(mods), mods = orch.VarIndex; end
if orch.FusionFlag == 1
    branches = mods(1);
elseif orch.FusionFlag == 3
    branches = mods(:)';
else
    branches = mods(:)';
end
branches = unique(branches(isfinite(branches) & branches >= 1));
end

function [details, msg] = local_stage_ml(orch, ctx)
% local_stage_ml  Execute or describe the ml dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

details = struct('scope','', 'branches', {{}}, 'nBranches', 0);
if orch.FusionFlag == 3 && ~local_is_stacking_enabled(orch)
    details.scope = 'late-fusion';
    mods = orch.FusionModalities;
    if isempty(mods), mods = 1:numel(orch.MLStrat); end
    for k = 1:numel(mods)
        idx = mods(k);
        if idx < 1 || idx > numel(orch.MLStrat) || isempty(orch.MLStrat{idx})
            error('run_nm_train_template_scaffold:badMLBranch', 'Invalid late-fusion ML branch index: %d.', idx);
        end
        [SVM, GRD] = orch.MLStrat{idx}.toLegacyML(ctx); %#ok<NASGU,ASGLU>
        details.branches{end+1} = sprintf('STRAT{%d}.SVM/GRD', idx); %#ok<AGROW>
    end
else
    details.scope = 'global';
    [SVM, GRD] = orch.MLGlobal.toLegacyML(ctx); %#ok<NASGU,ASGLU>
    details.branches = {'TrainParam.SVM/GRD'};
end
details.nBranches = numel(details.branches);
msg = sprintf('Converted %d machine-learning branch(es) to legacy SVM/GRD structures.', details.nBranches);
end

function [NMout, msg] = local_stage_synth(NM, orch)
% local_stage_synth  Execute or describe the synth dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

NMout = NMSynthTools.applyToNM(NM, orch.Synth);
msg = 'Synthetic-data configuration was applied to a dry-run NM copy.';
end

function [NMout, msg] = local_stage_multi(NM, orch)
% local_stage_multi  Execute or describe the multi dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

NMout = NMMULTITools.applyToNM(NM, orch.Multi, orch.VarIndex, orch.FusionFlag);
msg = 'MULTI configuration was applied to a dry-run NM copy.';
end

function [NMout, msg] = local_stage_rfe(NM, orch)
% local_stage_rfe  Execute or describe the rfe dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

NMout = NMRFETools.applyToNM(NM, orch.RFE, orch.VarIndex, orch.FusionFlag);
msg = 'RFE / ensemble-learning configuration was applied to a dry-run NM copy.';
end

function [NMout, msg] = local_stage_vis(NM, orch)
% local_stage_vis  Execute or describe the vis dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

NMout = NMVISTools.applyToNM(NM, orch.Vis, orch.VarIndex, orch.FusionFlag);
msg = 'VIS configuration was applied to a dry-run NM copy.';
end

function [NMout, msg] = local_stage_mli(NM, orch)
% local_stage_mli  Execute or describe the mli dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

NMout = NMMLITools.applyToNM(NM, orch.MLI, orch.VarIndex, orch.FusionFlag);
msg = 'MLI configuration was applied to a dry-run NM copy.';
end

function [NMout, msg] = local_stage_sav(NM, orch)
% local_stage_sav  Execute or describe the sav dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

NMout = NMSAVTools.applyToNM(NM, orch.SAV);
msg = 'Saving and verbosity configuration was applied to a dry-run NM copy.';
end

function [NMout, msg] = local_stage_materialize(NM, orch, ctx)
% local_stage_materialize  Execute or describe the materialize dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

orch.CVPartition = local_suppress_cv_side_effects(orch.CVPartition);
NMout = orch.toNM(NM, ctx);
msg = 'Full TrainParam materialization completed on a dry-run NM copy.';
end

function [post, msg] = local_stage_post_audit(NMout, varind, ctx)
% local_stage_post_audit  Execute or describe the post audit dry-run stage in the training-template scaffold.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

orch2 = NMTrainTemplateOrchestrator.fromNM(NMout, varind, ctx);
state2 = orch2.menuState();
audit2 = orch2.auditCurrentState(state2);
summary2 = orch2.auditSummary(audit2);
post = struct('audit', audit2, 'auditSummary', summary2);
if summary2.nErrors > 0
    error('run_nm_train_template_scaffold:postAuditErrors', ...
        'Post-materialization audit reported %d error(s).', summary2.nErrors);
end
msg = 'Post-materialization Patch H audit completed without hard errors.';
end


function tf = local_has_fatal_errors(stages)
% local_has_fatal_errors  Perform the local has fatal errors step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

tf = false;
if isempty(stages), return; end
if isfield(stages, 'fatal')
    tf = any([stages.fatal]);
else
    tf = any(strcmp({stages.status}, 'error'));
end
end

function stage = local_final_stage(stages)
% local_final_stage  Perform the local final stage step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

stage = '';
if isempty(stages), return; end
if isfield(stages, 'fatal') && any([stages.fatal])
    idx = find([stages.fatal], 1, 'first');
elseif any(strcmp({stages.status}, 'error'))
    idx = find(strcmp({stages.status}, 'error'), 1, 'first');
else
    idx = numel(stages);
end
stage = stages(idx).id;
end

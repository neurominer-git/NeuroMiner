function [out, PP, report] = nm_preproc_matrix_scaffold_fit_transform(Ytrain, pipeline, varargin)
% nm_preproc_matrix_scaffold_fit_transform  Fit and apply a matrix preprocessing scaffold to training data using NeuroMiner preprocessing semantics.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

opts = local_parse_opts(varargin{:});
ctx = nm_preproc_scaffold_context(opts.Context, opts.LabelTrain, opts.CovarsTrain, opts.LabelTest, opts.CovarsTest);
[orch, state] = nm_preproc_scaffold_load_orchestrator(pipeline, ctx);

needsLabels = nm_preproc_scaffold_needs_labels(orch);
if needsLabels && isempty(opts.LabelTrain)
    error('nm_preproc_matrix_scaffold_fit_transform:labelsRequired', ...
        ['The exported preprocessing pipeline contains label-dependent steps, ', ...
         'but LabelTrain is empty. Provide LabelTrain as a vector or nSubjects x nLabels matrix.']);
end

% 1) Subject-level spatial/image-preserving stage. This may produce multiple
% matrix branches, e.g. smoothing/wavelet levels.
[subBranches, subInfo] = nm_preproc_scaffold_apply_subject_spatial(Ytrain, orch, ctx);
if isempty(subBranches), subBranches = {Ytrain}; end

if ~isempty(opts.Ytest)
    [testBranches, testSubInfo] = nm_preproc_scaffold_apply_subject_spatial(opts.Ytest, orch, ctx);
    if isempty(testBranches), testBranches = {opts.Ytest}; end
else
    testBranches = cell(size(subBranches));
    testSubInfo = struct([]);
end

nSubB = numel(subBranches);
if ~isempty(opts.Ytest) && numel(testBranches) ~= nSubB
    error('nm_preproc_matrix_scaffold_fit_transform:branchMismatch', ...
        'Training and test subject-spatial preprocessing produced different branch counts (%d vs %d).', nSubB, numel(testBranches));
end

% 2) CV-bound matrix preprocessing: delegate to the NM object-level backend.
PREPROCcv = orch.CVSequence.toLegacy(ctx);
[P, act, hyperInfo] = local_prepare_inputparam_p(PREPROCcv);

out = struct();
out.branches = repmat(struct('Ytrain',[],'Ytest',[],'branchInfo',[],'hyperInfo',[],'InputParam',[]), 1, nSubB);

PP = struct();
PP.kind = 'NMMatrixLevelScaffoldPreproc';
PP.version = 3;
PP.executionBackend = 'nk_PerfPreprocessObj_core';
PP.created = datestr(now);
PP.uiState = state;
PP.subjectPreproc = [];
PP.cvPREPROC = PREPROCcv;
PP.act = act;
PP.P = P;
PP.hyperparameters = hyperInfo;
PP.contextSummary = nm_preproc_scaffold_context_summary(ctx);
PP.branches = cell(1,nSubB);
PP.mode = local_mode(ctx);

report = struct();
report.kind = PP.kind;
report.executionBackend = PP.executionBackend;
report.note = ['Matrix-level scaffold execution using nk_PerfPreprocessObj_core. ', ...
               'Hyperparameter and label shelves are preserved in the returned InputParam.Tr/Ts cells. ', ...
               'This is still not the full NM CV2/CV1 backend runner.'];
report.needsLabels = needsLabels;
report.subjectSpatial = subInfo;
report.subjectSpatialTest = testSubInfo;
report.hyperparameters = hyperInfo;
report.branches = repmat(struct('inputSize',[],'outputSizeTrain',[],'outputSizeTest',[], ...
    'subjectBranchIndex',[],'inputParamSummary',[]), 1, nSubB);

for b = 1:nSubB
    bctx = ctx;
    bctx.matrixScaffoldBranch = b;
    bctx.labelTrain = opts.LabelTrain;
    bctx.labelTest = opts.LabelTest;
    bctx.covarsTrain = opts.CovarsTrain;
    bctx.covarsTest = opts.CovarsTest;

    SrcParam = local_build_srcparam(size(subBranches{b},1), opts.LabelTrain, opts.CovarsTrain, opts.LabelTest, opts.CovarsTest, bctx);
    InputParam = local_build_inputparam(subBranches{b}, testBranches{b}, P, bctx);

    [SrcParamOut, InputParamOut, TrParam] = local_run_core(SrcParam, InputParam, [], act, bctx);

    out.branches(b).Ytrain = InputParamOut.Tr;
    if isfield(InputParamOut,'Ts')
        out.branches(b).Ytest = InputParamOut.Ts;
    else
        out.branches(b).Ytest = [];
    end
    if ~isempty(subInfo) && isfield(subInfo,'branchTable') && numel(subInfo.branchTable) >= b
        out.branches(b).branchInfo = subInfo.branchTable(b);
    else
        out.branches(b).branchInfo = [];
    end
    out.branches(b).hyperInfo = hyperInfo;
    out.branches(b).InputParam = local_compact_inputparam(InputParamOut);

    PP.branches{b} = struct('branchIndex',b, 'subjectBranchIndex',b, ...
        'TrParam',{TrParam}, 'SrcParam',SrcParamOut, 'InputParamTemplate',local_strip_data(InputParam), ...
        'branchInfo',out.branches(b).branchInfo, 'uiState',state);

    report.branches(b).inputSize = size(subBranches{b});
    report.branches(b).outputSizeTrain = local_size_or_cellsize(InputParamOut.Tr);
    if isfield(InputParamOut,'Ts'), report.branches(b).outputSizeTest = local_size_or_cellsize(InputParamOut.Ts); else, report.branches(b).outputSizeTest = []; end
    report.branches(b).subjectBranchIndex = b;
    report.branches(b).inputParamSummary = local_inputparam_summary(InputParamOut);
end
PP.report = report;
end

function [P, act, hyperInfo] = local_prepare_inputparam_p(PREPROCcv)
% local_prepare_inputparam_p  Perform the local prepare inputparam p step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

P = {}; act = {}; hyperInfo = struct('hasHyperparameters',false,'PX',[],'perStep',[]);
if isempty(PREPROCcv) || ~isfield(PREPROCcv,'ACTPARAM') || isempty(PREPROCcv.ACTPARAM)
    return;
end
P = PREPROCcv.ACTPARAM;
if ~iscell(P), P = num2cell(P); end
n = numel(P);
act = cell(1,n);
perStep = repmat(struct('stepIndex',[],'cmd','','hasOpt',false,'nOpt',1,'Params_desc',{{}},'opt',[]), 1, n);
for i = 1:n
    if ~isfield(P{i},'cmd') || isempty(P{i}.cmd)
        error('nm_preproc_matrix_scaffold_fit_transform:missingCmd', 'CV-bound ACTPARAM{%d} has no cmd field.', i);
    end
    act{i} = char(P{i}.cmd);
    if isfield(P{i},'PX') && ~isempty(P{i}.PX) && isfield(P{i}.PX,'opt') && ~isempty(P{i}.PX.opt)
        P{i}.opt = P{i}.PX.opt;
        P{i} = local_attach_px_descriptors(P{i});
        perStep(i).hasOpt = true;
        perStep(i).nOpt = size(P{i}.opt,1);
        perStep(i).opt = P{i}.opt;
    end
    perStep(i).stepIndex = i;
    perStep(i).cmd = act{i};
    if isfield(P{i},'Params_desc'), perStep(i).Params_desc = P{i}.Params_desc; end
end
try
    PX = nk_ReturnParamChain(struct('ACTPARAM',{P}), false);
catch
    PX = [];
end
hyperInfo.hasHyperparameters = ~isempty(PX) && isstruct(PX) && isfield(PX,'opt') && ~isempty(PX.opt);
if hyperInfo.hasHyperparameters
    hyperInfo.PX = PX;
else
    hyperInfo.PX = [];
end
hyperInfo.perStep = perStep;
end

function Pi = local_attach_px_descriptors(Pi)
% local_attach_px_descriptors  Perform the local attach px descriptors step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if ~isfield(Pi,'PX') || ~isfield(Pi.PX,'Px'), return; end
Px = Pi.PX.Px;
if isfield(Px,'Params'), Pi.Params = Px.Params; end
if isfield(Px,'Params_desc'), Pi.Params_desc = Px.Params_desc; end
if isfield(Px,'Typ'), Pi.Typ = Px.Typ; end
% Propagate descriptors to nested action structs if missing. Several act_*
% functions retrieve selected values from nested Params_desc.
fn = fieldnames(Pi);
for k = 1:numel(fn)
    f = fn{k};
    if any(strcmp(f, {'PX','cmd','opt','Params','Params_desc','Typ'})), continue; end
    if isstruct(Pi.(f))
        if isfield(Pi,'Params') && ~isfield(Pi.(f),'Params'), Pi.(f).Params = Pi.Params; end
        if isfield(Pi,'Params_desc') && ~isfield(Pi.(f),'Params_desc'), Pi.(f).Params_desc = Pi.Params_desc; end
        if isfield(Pi,'Typ') && ~isfield(Pi.(f),'Typ'), Pi.(f).Typ = Pi.Typ; end
    end
end
end

function SrcParam = local_build_srcparam(nTrain, labelTrain, covarsTrain, labelTest, covarsTest, ctx)
% local_build_srcparam  Build the srcparam structure required by the surrounding workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if nargin < 6, ctx = struct(); end
SrcParam = struct();
mode = local_mode(ctx);
if isempty(labelTrain)
    labelTrain = zeros(nTrain,1);
end
if isvector(labelTrain), labelTrain = labelTrain(:); end
SrcParam.TrainLabel = labelTrain;
SrcParam.MultiTrainLabel = labelTrain;
if isempty(labelTest)
    labelTest = zeros(0, size(labelTrain,2));
elseif isvector(labelTest)
    labelTest = labelTest(:);
end
SrcParam.CVLabel = labelTest;
SrcParam.MultiCVLabel = labelTest;
SrcParam.covars = covarsTrain;
SrcParam.covars_oocv = covarsTest;
SrcParam.synth_activated = false(1, max(1,size(labelTrain,2)));
SrcParam.mode = mode;
end

function InputParam = local_build_inputparam(Ytrain, Ytest, P, ctx)
% local_build_inputparam  Build the inputparam structure required by the surrounding workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% ctx.C: field consumed from ctx to preserve the caller's configured UI/API/scaffold state.
% ctx.Yw: field consumed from ctx to preserve the caller's configured UI/API/scaffold state.

InputParam = struct();
InputParam.Tr = Ytrain;
if ~isempty(Ytest)
    InputParam.Ts = {Ytest};
end
InputParam.P = P;
InputParam.CV1perm = true(size(Ytrain,1),1);
InputParam.CV1fold = 1;
InputParam.curclass = 1;
if isfield(ctx,'Yw') && ~isempty(ctx.Yw), InputParam.Yw = ctx.Yw; end
if isfield(ctx,'C') && ~isempty(ctx.C), InputParam.C = ctx.C; end
end

function [SrcParam, InputParam, TrParam] = local_run_core(SrcParam, InputParam, TrParam, act, ctx)
% local_run_core  Perform the local run core step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

old = local_capture_globals();
c = onCleanup(@() local_restore_globals(old)); %#ok<NASGU>
local_setup_globals(ctx);
[SrcParam, InputParam, TrParam] = nk_PerfPreprocessObj_core(SrcParam, InputParam, TrParam, act);
end

function mode = local_mode(ctx)
% local_mode  Perform the local mode step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

mode = 'classification';
if isstruct(ctx)
    candidates = {'mode','MODEFL','mlMode','analysisMode'};
    for i = 1:numel(candidates)
        k = candidates{i};
        if isfield(ctx,k) && ~isempty(ctx.(k))
            mode = char(ctx.(k)); return;
        end
    end
end
end

function old = local_capture_globals()
% local_capture_globals  Perform the local capture globals step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

global VERBOSE TEMPL SVM MODEFL SYNTH
old = struct('VERBOSE',VERBOSE,'TEMPL',TEMPL,'SVM',SVM,'MODEFL',MODEFL,'SYNTH',SYNTH);
end

function local_restore_globals(old)
% local_restore_globals  Perform the local restore globals step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

global VERBOSE TEMPL SVM MODEFL SYNTH
VERBOSE = old.VERBOSE; TEMPL = old.TEMPL; SVM = old.SVM; MODEFL = old.MODEFL; SYNTH = old.SYNTH;
end

function local_setup_globals(ctx)
% local_setup_globals  Perform the local setup globals step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% ctx.VERBOSE: field consumed from ctx to preserve the caller's configured UI/API/scaffold state.

global VERBOSE TEMPL SVM MODEFL SYNTH
if isempty(VERBOSE), VERBOSE = false; end
if isstruct(ctx) && isfield(ctx,'VERBOSE'), VERBOSE = ctx.VERBOSE; end
MODEFL = local_mode(ctx);
if isempty(TEMPL), TEMPL = []; end
if isempty(SYNTH), SYNTH = []; end
if isempty(SVM), SVM = struct(); end
if ~isstruct(SVM), SVM = struct(); end
if ~isfield(SVM,'ADASYN'), SVM.ADASYN = struct('flag',0); end
end

function C = local_compact_inputparam(InputParam)
% local_compact_inputparam  Perform the local compact inputparam step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

C = InputParam;
end

function T = local_strip_data(InputParam)
% local_strip_data  Perform the local strip data step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

T = InputParam;
if isfield(T,'Tr'), T = rmfield(T,'Tr'); end
if isfield(T,'Ts'), T = rmfield(T,'Ts'); end
if isfield(T,'C'), T = rmfield(T,'C'); end
end

function s = local_size_or_cellsize(x)
% local_size_or_cellsize  Perform the local size or cellsize step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if iscell(x)
    s = cellfun(@(z) size(z), x, 'UniformOutput', false);
else
    s = size(x);
end
end

function s = local_inputparam_summary(InputParam)
% local_inputparam_summary  Perform the local inputparam summary step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

s = struct();
s.Tr = local_size_or_cellsize(InputParam.Tr);
if isfield(InputParam,'Ts'), s.Ts = local_size_or_cellsize(InputParam.Ts); else, s.Ts = []; end
if isfield(InputParam,'P'), s.nSteps = numel(InputParam.P); else, s.nSteps = 0; end
end

function opts = local_parse_opts(varargin)
% local_parse_opts  Parse opts options into a fixed scaffold/bridge structure.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

opts = struct('Ytest',[], 'LabelTrain',[], 'LabelTest',[], 'CovarsTrain',[], 'CovarsTest',[], 'Context',struct());
if mod(numel(varargin),2) ~= 0
    error('nm_preproc_matrix_scaffold_fit_transform:badOptions','Options must be name/value pairs.');
end
for i = 1:2:numel(varargin)
    key = char(varargin{i}); val = varargin{i+1};
    switch lower(key)
        case 'ytest', opts.Ytest = val;
        case 'labeltrain', opts.LabelTrain = val;
        case 'labeltest', opts.LabelTest = val;
        case 'covarstrain', opts.CovarsTrain = val;
        case 'covarstest', opts.CovarsTest = val;
        case 'context', opts.Context = val;
        otherwise, error('nm_preproc_matrix_scaffold_fit_transform:badOption','Unknown option: %s', key);
    end
end
end

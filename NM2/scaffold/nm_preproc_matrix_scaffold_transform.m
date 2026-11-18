function [out, report] = nm_preproc_matrix_scaffold_transform(Y, PP, varargin)
% nm_preproc_matrix_scaffold_transform  Apply a fitted matrix preprocessing scaffold to new data without refitting preprocessing parameters.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

opts = local_parse_opts(varargin{:});
ctx = nm_preproc_scaffold_context(opts.Context, [], opts.Covars, opts.Label, []);
[orch, ~] = nm_preproc_scaffold_load_orchestrator(PP.uiState, ctx);
[subBranches, subInfo] = nm_preproc_scaffold_apply_subject_spatial(Y, orch, ctx);
if isempty(subBranches), subBranches = {Y}; end

nB = numel(PP.branches);
out = struct(); out.branches = repmat(struct('Y',[],'branchInfo',[],'InputParam',[]), 1, nB);
report = struct('subjectSpatial',subInfo,'branches',[]);
report.branches = repmat(struct('subjectBranchIndex',[],'outputSize',[],'inputParamSummary',[]), 1, nB);

for b = 1:nB
    if isfield(PP.branches{b},'subjectBranchIndex') && ~isempty(PP.branches{b}.subjectBranchIndex)
        sb = PP.branches{b}.subjectBranchIndex;
    else
        sb = b;
    end
    if sb < 1 || sb > numel(subBranches)
        error('nm_preproc_matrix_scaffold_transform:branchMismatch', ...
            'Stored subject branch index %d is not available in new data (%d branches).', sb, numel(subBranches));
    end
    bctx = ctx;
    bctx.matrixScaffoldBranch = sb;

    P = PP.P;
    act = PP.act;
    SrcParam = local_build_srcparam(size(subBranches{sb},1), opts.Label, opts.Covars, bctx);
    InputParam = local_build_inputparam(subBranches{sb}, P, bctx);
    TrParam = PP.branches{b}.TrParam;

    [~, InputParamOut, ~] = local_run_core(SrcParam, InputParam, TrParam, act, bctx);

    if isfield(InputParamOut,'Ts')
        Yout = InputParamOut.Ts;
    elseif isfield(InputParamOut,'Tr')
        % Defensive fallback. In out-of-sample mode Ts should normally exist.
        Yout = InputParamOut.Tr;
    else
        Yout = [];
    end

    out.branches(b).Y = Yout;
    out.branches(b).branchInfo = PP.branches{b}.branchInfo;
    out.branches(b).InputParam = InputParamOut;
    report.branches(b).subjectBranchIndex = sb;
    report.branches(b).outputSize = local_size_or_cellsize(Yout);
    report.branches(b).inputParamSummary = local_inputparam_summary(InputParamOut);
end
end

function SrcParam = local_build_srcparam(nTest, label, covars, ctx)
% local_build_srcparam  Build the srcparam structure required by the surrounding workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if nargin < 4, ctx = struct(); end
SrcParam = struct();
if isempty(label)
    label = zeros(nTest,1);
elseif isvector(label)
    label = label(:);
end
% nk_PerfPreprocessObj_core uses TrainLabel/MultiTrainLabel to determine nL
% even in out-of-sample mode. We therefore provide target labels as both
% Train and CV placeholders. They are not used for parameter fitting when
% TrParam is supplied.
SrcParam.TrainLabel = label;
SrcParam.MultiTrainLabel = label;
SrcParam.CVLabel = label;
SrcParam.MultiCVLabel = label;
SrcParam.covars = covars;
SrcParam.covars_oocv = covars;
SrcParam.synth_activated = false(1, max(1,size(label,2)));
SrcParam.mode = local_mode(ctx);
end

function InputParam = local_build_inputparam(Y, P, ctx)
% local_build_inputparam  Build the inputparam structure required by the surrounding workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% ctx.C: field consumed from ctx to preserve the caller's configured UI/API/scaffold state.
% ctx.Yw: field consumed from ctx to preserve the caller's configured UI/API/scaffold state.

InputParam = struct();
InputParam.Ts = {Y};
InputParam.P = P;
InputParam.CV1perm = true(size(Y,1),1);
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
if isfield(InputParam,'Tr'), s.Tr = local_size_or_cellsize(InputParam.Tr); else, s.Tr = []; end
if isfield(InputParam,'Ts'), s.Ts = local_size_or_cellsize(InputParam.Ts); else, s.Ts = []; end
if isfield(InputParam,'P'), s.nSteps = numel(InputParam.P); else, s.nSteps = 0; end
end

function opts = local_parse_opts(varargin)
% local_parse_opts  Parse opts options into a fixed scaffold/bridge structure.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

opts = struct('Label',[], 'Covars',[], 'Context',struct());
if mod(numel(varargin),2) ~= 0, error('Options must be name/value pairs.'); end
for i=1:2:numel(varargin)
    switch lower(char(varargin{i}))
        case 'label', opts.Label = varargin{i+1};
        case 'covars', opts.Covars = varargin{i+1};
        case 'context', opts.Context = varargin{i+1};
        otherwise, error('Unknown option: %s', char(varargin{i}));
    end
end
end

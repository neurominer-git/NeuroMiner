function [H, hyperTable] = nm_preproc_scaffold_expand_hyperparams(orch, ctx)
% nm_preproc_scaffold_expand_hyperparams  Expand preprocessing orchestrator hyperparameters into scaffold-ready configurations and a summary table.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 2 || isempty(ctx), ctx = struct(); end
baseState = orch.toUIState();
H = local_default_h(baseState);
hyperTable = struct([]);

if exist('nk_ReturnParamChain','file') ~= 2
    return;
end

try
    PREPROC = orch.CVSequence.toLegacy(ctx);
    PX = nk_ReturnParamChain(PREPROC, false);
catch ME
    warning('nm_preproc_scaffold_expand_hyperparams:legacyPX', ...
        'Could not retrieve preprocessing hyperparameter chain: %s', ME.message);
    return;
end

if isempty(PX) || ~isstruct(PX) || ~isfield(PX,'opt') || isempty(PX.opt) || ...
        ~isfield(PX,'Params_desc') || isempty(PX.Params_desc) || ...
        ~isfield(PX,'steps') || isempty(PX.steps)
    return;
end

opt = PX.opt;
if isvector(opt)
    opt = opt(:);
end
nH = size(opt,1);
steps = PX.steps(:)';
desc = PX.Params_desc;
if ischar(desc), desc = cellstr(desc); end
if isstring(desc), desc = cellstr(desc); end
if numel(desc) ~= numel(steps)
    desc = local_pad_desc(desc, numel(steps));
end

H = repmat(struct('index',[],'state',[],'description','','selectedOpt',[], ...
    'params',[],'source','PX.opt'), 1, nH);
for h = 1:nH
    st = baseState;
    params = repmat(struct('stepIndex',[],'moduleId','','description','','value',[]), 1, numel(steps));
    uSteps = unique(steps,'stable');
    for uu = 1:numel(uSteps)
        sidx = uSteps(uu);
        [step, ok] = local_get_cv_step(st, sidx);
        if ~ok, continue; end
        moduleId = local_canon(step.moduleId);
        cfg = step.config;
        cols = find(steps == sidx);
        for cc = 1:numel(cols)
            c = cols(cc);
            val = opt(h,c);
            d = char(desc{c});
            cfg = local_apply_param_to_config(moduleId, cfg, d, val);
            params(c).stepIndex = sidx;
            params(c).moduleId = moduleId;
            params(c).description = d;
            params(c).value = val;
        end
        step.config = cfg;
        st = local_set_cv_step(st, sidx, step);
    end
    H(h).index = h;
    H(h).state = st;
    H(h).selectedOpt = opt(h,:);
    H(h).params = params;
    H(h).description = local_description(h, params);
end

hyperTable = repmat(struct('index',[],'description','','selectedOpt',[], 'params',[]), 1, nH);
for h = 1:nH
    hyperTable(h).index = H(h).index;
    hyperTable(h).description = H(h).description;
    hyperTable(h).selectedOpt = H(h).selectedOpt;
    hyperTable(h).params = H(h).params;
end
end

function H = local_default_h(state)
% local_default_h  Perform the local default h step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

H = struct('index',1,'state',state,'description','default','selectedOpt',[], ...
    'params',struct([]),'source','none');
end

function desc = local_pad_desc(desc, n)
% local_pad_desc  Perform the local pad desc step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

desc = desc(:)';
while numel(desc) < n, desc{end+1} = sprintf('Param%d', numel(desc)+1); end %#ok<AGROW>
if numel(desc) > n, desc = desc(1:n); end
end

function [step, ok] = local_get_cv_step(state, idx)
% local_get_cv_step  Read a struct field with an explicit fallback while preserving caller-provided values.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% state.cv: field consumed from state to preserve the caller's configured UI/API/scaffold state.

ok = false; step = struct();
if ~isfield(state,'cv') || ~isfield(state.cv,'sequence') || ~isfield(state.cv.sequence,'steps')
    return;
end
steps = state.cv.sequence.steps;
if iscell(steps)
    if idx < 1 || idx > numel(steps), return; end
    step = steps{idx}; ok = true;
else
    if idx < 1 || idx > numel(steps), return; end
    step = steps(idx); ok = true;
end
end

function state = local_set_cv_step(state, idx, step)
% local_set_cv_step  Perform the local set cv step step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% state.cv: field consumed from state to preserve the caller's configured UI/API/scaffold state.
% state.sequence: field consumed from state to preserve the caller's configured UI/API/scaffold state.

steps = state.cv.sequence.steps;
if iscell(steps)
    steps{idx} = step;
else
    steps(idx) = step;
end
state.cv.sequence.steps = steps;
% Keep backward-compatible preview sequence in sync if present.
if isfield(state,'sequence') && isfield(state.sequence,'steps')
    s2 = state.sequence.steps;
    if iscell(s2)
        if idx <= numel(s2), s2{idx} = step; end
    else
        if idx <= numel(s2), s2(idx) = step; end
    end
    state.sequence.steps = s2;
end
end

function cfg = local_apply_param_to_config(moduleId, cfg, desc, val)
% local_apply_param_to_config  Perform the local apply param to config step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

if ~isstruct(cfg), cfg = struct(); end
key = local_key(desc);
moduleId = local_canon(moduleId);

switch moduleId
    case 'extfeat'
        cfg = local_apply_extfeat(cfg, key, val);
    case 'rankfeat'
        cfg = local_apply_rankfeat(cfg, key, val);
    case 'reducedim'
        cfg = local_apply_reducedim(cfg, key, val);
    case 'extdim'
        cfg = local_apply_extdim(cfg, key, val);
    case 'remvarcomp'
        cfg = local_apply_remvarcomp(cfg, key, val);
    case 'skewcorr'
        cfg = local_apply_skewcorr(cfg, key, val);
    case {'elimzero','prune'}
        cfg = local_apply_elimzero(cfg, key, val);
    case 'devmap'
        cfg = local_apply_devmap(cfg, key, val);
    case 'correctnuis'
        cfg = local_apply_correctnuis(cfg, key, val);
    otherwise
        cfg = local_record_unmapped(cfg, desc, val);
end
cfg = local_record_selected(cfg, desc, val);
end

function cfg = local_apply_extfeat(cfg, key, val)
% local_apply_extfeat  Perform the local apply extfeat step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% cfg.absoluteThresholds: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.cutoff: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.exponent: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.percentiles: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.topFeatures: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.

if contains(key,'expmult') || strcmp(key,'exp')
    cfg.exponent = val;
elseif contains(key,'absolutethreshold') || contains(key,'absthreshold')
    cfg.absoluteThresholds = val;
elseif contains(key,'threshold')
    cfg.percentiles = val;
elseif contains(key,'topfeat') || contains(key,'numfeat')
    cfg.topFeatures = val;
elseif contains(key,'cutoff')
    cfg.cutoff = val;
else
    cfg = local_record_unmapped(cfg, key, val);
end
end

function cfg = local_apply_rankfeat(cfg, key, val)
% local_apply_rankfeat  Perform the local apply rankfeat step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% cfg.methodParams: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.

if ~isfield(cfg,'methodParams') || ~isstruct(cfg.methodParams), cfg.methodParams = struct(); end
if contains(key,'beta')
    cfg.methodParams.beta = val;
elseif contains(key,'sigma')
    cfg.methodParams.sigma = val;
elseif contains(key,'lambda') || contains(key,'slackrank')
    cfg.methodParams.lambda = val;
    cfg.methodParams.slackParam = val;
elseif strcmp(key,'k') || contains(key,'reliefk') || contains(key,'rgsk')
    cfg.methodParams.k = val;
elseif contains(key,'numfeat')
    cfg.methodParams.numFeatures = val;
    cfg.methodParams.NumFeat = val;
elseif contains(key,'splscu')
    cfg.methodParams.cu = val;
elseif contains(key,'splscv')
    cfg.methodParams.cv = val;
elseif contains(key,'tolrank')
    cfg.methodParams.liblinTolerance = val;
elseif contains(key,'epsilonrank')
    cfg.methodParams.epsilonParam = val;
elseif contains(key,'nurank')
    cfg.methodParams.nuParam = val;
else
    cfg = local_record_unmapped(cfg, key, val);
end
end

function cfg = local_apply_reducedim(cfg, key, val)
% local_apply_reducedim  Perform the local apply reducedim step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% cfg.dims: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.methodParams: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.

if ~isfield(cfg,'methodParams') || ~isstruct(cfg.methodParams), cfg.methodParams = struct(); end
if contains(key,'dimension') || strcmp(key,'dims')
    cfg.dims = val;
elseif contains(key,'sparsepcalambda') || contains(key,'ncalambda')
    cfg.methodParams.lambda = val;
elseif contains(key,'sparsepcastop')
    cfg.methodParams.stop = val;
elseif contains(key,'sparsepcaiter') || contains(key,'probpcaiter') || contains(key,'fasticamaxiter')
    cfg.methodParams.maxiter = val;
    cfg.methodParams.max_iters = val;
    cfg.methodParams.iter = val;
elseif contains(key,'fasticatol')
    cfg.methodParams.tolerance = val;
elseif contains(key,'lppsigma') || contains(key,'laplaciansigma')
    cfg.methodParams.sigma = val;
    cfg.methodParams.s = val;
elseif contains(key,'lppk') || contains(key,'lltsak') || contains(key,'laplaciank') || contains(key,'llek')
    cfg.methodParams.k = val;
elseif contains(key,'splscu')
    cfg.methodParams.cu = val;
elseif contains(key,'splscv')
    cfg.methodParams.cv = val;
else
    cfg = local_record_unmapped(cfg, key, val);
end
end

function cfg = local_apply_extdim(cfg, key, val)
% local_apply_extdim  Perform the local apply extdim step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% cfg.dims: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.percent: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.

if contains(key,'dimension') || strcmp(key,'dims')
    cfg.dims = val;
elseif contains(key,'percent')
    cfg.percent = val;
else
    cfg = local_record_unmapped(cfg, key, val);
end
end

function cfg = local_apply_remvarcomp(cfg, key, val)
% local_apply_remvarcomp  Perform the local apply remvarcomp step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% cfg.correlationThreshold: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.fastICAParams: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.fitDim: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.waveletParams: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.

if contains(key,'corrthresh')
    cfg.correlationThreshold = val;
elseif strcmp(key,'dims') || contains(key,'dimension')
    cfg.fitDim = val;
elseif contains(key,'fasticatol')
    if ~isfield(cfg,'fastICAParams') || ~isstruct(cfg.fastICAParams), cfg.fastICAParams = struct(); end
    cfg.fastICAParams.tolerance = val;
    if ~isfield(cfg,'waveletParams') || ~isstruct(cfg.waveletParams), cfg.waveletParams = struct(); end
    cfg.waveletParams.fastICA.tolerance = val;
elseif contains(key,'fasticamaxiter')
    if ~isfield(cfg,'fastICAParams') || ~isstruct(cfg.fastICAParams), cfg.fastICAParams = struct(); end
    cfg.fastICAParams.max_iters = val;
    if ~isfield(cfg,'waveletParams') || ~isstruct(cfg.waveletParams), cfg.waveletParams = struct(); end
    cfg.waveletParams.fastICA.max_iters = val;
else
    cfg = local_record_unmapped(cfg, key, val);
end
end

function cfg = local_apply_skewcorr(cfg, key, val)
% local_apply_skewcorr  Perform the local apply skewcorr step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% cfg.BoxCoxLambdaVal: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.YJLambdaVal: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.boxcoxLambda: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.skewThreshold: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.yeoJohnsonLambda: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.

if contains(key,'skewthr')
    cfg.skewThreshold = val;
elseif contains(key,'boxcoxlambda')
    cfg.boxcoxLambda = val;
    cfg.BoxCoxLambdaVal = val;
elseif contains(key,'yjlambda')
    cfg.yeoJohnsonLambda = val;
    cfg.YJLambdaVal = val;
else
    cfg = local_record_unmapped(cfg, key, val);
end
end

function cfg = local_apply_elimzero(cfg, key, val)
% local_apply_elimzero  Perform the local apply elimzero step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% cfg.perc: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.percentage: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.

if contains(key,'pruneperc') || contains(key,'perc')
    cfg.percentage = val;
    cfg.perc = val;
else
    cfg = local_record_unmapped(cfg, key, val);
end
end

function cfg = local_apply_devmap(cfg, key, val)
% local_apply_devmap  Perform the local apply devmap step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% cfg.cu: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.
% cfg.cv: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.

if contains(key,'splscu')
    cfg.cu = val;
elseif contains(key,'splscv')
    cfg.cv = val;
else
    cfg = local_record_unmapped(cfg, key, val);
end
end

function cfg = local_apply_correctnuis(cfg, key, val)
% local_apply_correctnuis  Perform the local apply correctnuis step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% cfg.lambda: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.

if contains(key,'lambda')
    cfg.lambda = val;
else
    cfg = local_record_unmapped(cfg, key, val);
end
end

function cfg = local_record_selected(cfg, desc, val)
% local_record_selected  Perform the local record selected step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% cfg.scaffoldSelectedHyperparams: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.

if ~isfield(cfg,'scaffoldSelectedHyperparams') || ~isstruct(cfg.scaffoldSelectedHyperparams)
    cfg.scaffoldSelectedHyperparams = struct('description',{{}},'value',[]);
end
cfg.scaffoldSelectedHyperparams.description{end+1} = char(desc);
if isempty(cfg.scaffoldSelectedHyperparams.value)
    cfg.scaffoldSelectedHyperparams.value = val;
else
    cfg.scaffoldSelectedHyperparams.value(end+1) = val;
end
end

function cfg = local_record_unmapped(cfg, desc, val)
% local_record_unmapped  Perform the local record unmapped step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
%
% cfg.scaffoldUnmappedHyperparams: field consumed from cfg to preserve the caller's configured UI/API/scaffold state.

if ~isfield(cfg,'scaffoldUnmappedHyperparams') || ~isstruct(cfg.scaffoldUnmappedHyperparams)
    cfg.scaffoldUnmappedHyperparams = struct('description',{{}},'value',[]);
end
cfg.scaffoldUnmappedHyperparams.description{end+1} = char(desc);
if isempty(cfg.scaffoldUnmappedHyperparams.value)
    cfg.scaffoldUnmappedHyperparams.value = val;
else
    cfg.scaffoldUnmappedHyperparams.value(end+1) = val;
end
end

function s = local_key(x)
% local_key  Perform the local key step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

s = lower(regexprep(char(x),'[^a-zA-Z0-9]',''));
end

function s = local_canon(x)
% local_canon  Perform the local canon step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

s = lower(strtrim(char(x)));
end

function d = local_description(h, params)
% local_description  Perform the local description step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

parts = {};
for i = 1:numel(params)
    if isempty(params(i).description), continue; end
    v = params(i).value;
    if isnumeric(v), vs = mat2str(v); else, vs = char(v); end
    parts{end+1} = sprintf('s%d:%s=%s', params(i).stepIndex, params(i).description, vs); %#ok<AGROW>
end
if isempty(parts), d = sprintf('hyper_%d', h); else, d = sprintf('hyper_%d | %s', h, strjoin(parts, ', ')); end
end

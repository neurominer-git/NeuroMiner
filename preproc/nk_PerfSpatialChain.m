function [sY, branchTable] = nk_PerfSpatialChain(Y, PREPROC, Param)
% nk_PerfSpatialChain - Execute a subject-specific spatial preprocessing chain.
%
% The executor applies each PREPROC.SPATIAL step to every existing branch.
% If an upstream step has several PX.opt alternatives, all downstream steps
% are applied separately to every alternative. This enables chains such as
% smoothing(FWHM=[4 8]) -> ROImeans/JuSpace/KL graph construction.
% branchTable stores both a human-readable parameter/value pair and the exact
% PX.opt row for every executed step, allowing generic downstream selection.

steps = nk_NormalizeSpatialSteps(PREPROC);

if isempty(steps)
    sY = Y;
    branchTable = struct([]);
    return
end

branches = {Y};
branchRows = {struct([])};

for s = 1:numel(steps)
    step = steps(s);
    nextBranches = {};
    nextRows = {};
    for b = 1:numel(branches)
        CURACT = struct('SPATIAL', step);
        stepOut = nk_PerfSpatFilt(branches{b}, CURACT, Param);
        if ~iscell(stepOut)
            stepOut = {stepOut};
        end
        for q = 1:numel(stepOut)
            nextBranches{end+1,1} = stepOut{q}; %#ok<AGROW>
            nextRows{end+1,1} = append_branch_rows(branchRows{b}, numel(nextBranches), s, step, q); %#ok<AGROW>
        end
    end
    branches = nextBranches;
    branchRows = nextRows;
end

sY = branches;
branchTable = vertcat_branch_rows(branchRows);
end

function rows = append_branch_rows(prevRows, branchId, stepIndex, step, optIndex)
rows = prevRows;
if ~isempty(rows)
    for i = 1:numel(rows)
        rows(i).branch = branchId;
    end
end

row = struct();
row.branch = branchId;
row.step = stepIndex;
row.cmd = get_cmd(step);
row.cubetype = step.cubetype;
row.param = get_param_name(step);
row.value = get_opt_value(step, optIndex);
row.opt = get_opt_row(step, optIndex);

if isempty(rows)
    rows = row;
else
    rows(end+1) = row;
end
end

function rows = vertcat_branch_rows(branchRows)
rows = struct([]);
for i = 1:numel(branchRows)
    if isempty(branchRows{i}), continue; end
    if isempty(rows)
        rows = branchRows{i};
    else
        rows = [rows; branchRows{i}(:)]; %#ok<AGROW>
    end
end
end

function cmd = get_cmd(step)
if isfield(step,'cmd') && ~isempty(step.cmd)
    cmd = step.cmd;
else
    switch step.cubetype
        case 4
            cmd = 'smoothing';
        case 5
            cmd = 'JuSpace';
        case 7
            cmd = 'ROImeans';
        case 8
            cmd = 'graphComputation';
        case 9
            cmd = 'waveletSpatial';
        otherwise
            cmd = sprintf('cubetype_%g', step.cubetype);
    end
end
end

function pname = get_param_name(step)
switch step.cubetype
    case 4
        pname = 'FWHM';
    case 6
        pname = 'voxel_size';
    case 8
        pname = 'method';
    case 9
        pname = 'WaveletLevel';
    otherwise
        pname = 'none';
end
end

function val = get_opt_value(step, optIndex)
if step.cubetype == 8 && isfield(step,'GRAPHCONSTRUCTION') && isfield(step.GRAPHCONSTRUCTION,'method')
    val = step.GRAPHCONSTRUCTION.method;
    return
end

if step.cubetype == 9 && isfield(step,'PX') && isfield(step.PX,'opt') && ~isempty(step.PX.opt)
    opt = option_matrix(step);
    val = opt(min(optIndex,size(opt,1)),:);
    return
end
if isfield(step,'PX') && isfield(step.PX,'opt') && ~isempty(step.PX.opt)
    opt = option_matrix(step);
    if size(opt,1) >= optIndex
        val = opt(optIndex,:);
    else
        val = opt(1,:);
    end
else
    val = [];
end
end

function val = get_opt_row(step, optIndex)
val = [];
if ~isfield(step,'PX') || ~isfield(step.PX,'opt') || isempty(step.PX.opt)
    return
end
opt = option_matrix(step);
if size(opt,1) < optIndex
    error('nk_PerfSpatialChain:SpatialOptionIndexMismatch', ...
        'Spatial step option #%g is not represented in PX.opt.', optIndex);
end
val = opt(optIndex,:);
end

function opt = option_matrix(step)
opt = step.PX.opt;
nParams = 1;
if isfield(step.PX,'Px') && ~isempty(step.PX.Px)
    nParams = numel(step.PX.Px);
end
if nParams == 1 && (isnumeric(opt) || islogical(opt) || isstring(opt) || iscell(opt)) && isvector(opt)
    opt = opt(:);
elseif nParams > 1 && size(opt,2) ~= nParams
    error('nk_PerfSpatialChain:SpatialParameterWidthMismatch', ...
        'Spatial PX.opt has %g columns, but PX.Px defines %g parameters.', ...
        size(opt,2), nParams);
end
end

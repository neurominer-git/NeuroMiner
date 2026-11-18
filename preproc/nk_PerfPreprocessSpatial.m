function [sY, sYocv, sCocv, sAltY, sYw, inp, optfl] = ...
    nk_PerfPreprocessSpatial(Y, Yocv, Cocv, AltY, inp, paramfl, kbin)
% nk_PerfPreprocessSpatial - Materialize or select subject-spatial shelves.
%
% Purpose
%   Coordinate subject-spatial preprocessing at the boundary of CV-bound
%   preprocessing. Raw data are delegated to nk_MaterializeSpatialShelves;
%   resident canonical shelves are reduced to the branches required by the
%   current trained or candidate preprocessing parameters.
%
% Syntax
%   [sY,sYocv,sCocv,sAltY,sYw,inp,optfl] = ...
%       nk_PerfPreprocessSpatial(Y,Yocv,Cocv,AltY,inp,paramfl,kbin)
%
% Inputs
%   Y, Yocv, Cocv, AltY
%       Raw data or canonical shelves{binary,instance}{branch}, according to
%       inp.isSpatialPreprocessed for paramfl.currmodal.
%   inp
%       Runtime state carrying materialization flags, branch tables, and optional
%       weighting-map shelves.
%   paramfl
%       Current preprocessing parameter state. PREPROC/PXfull/PXunique identify
%       the current classifier-specific chain and PV supplies spatial geometry.
%   kbin
%       Number of binary/regression preprocessing containers.
%
% Outputs
%   sY, sYocv, sCocv, sAltY, sYw
%       Canonical materialized or selected shelves.
%   inp
%       Updated materialization state when raw data were processed.
%   optfl
%       True when subject-spatial preprocessing is configured.
%
% Authority and flow
%   nk_MaterializeSpatialShelves owns execution and shelf construction.
%   nk_SelectSpatialBranches owns metadata-driven selection. This function owns
%   only the materialized-versus-resident state transition used by
%   nk_PerfPreprocess and nk_ApplyTrainedPreproc.
%
% Scientific/state contract and invariants
%   Resident data must use shelves{binary,instance}{branch}; branch metadata must
%   use spatial_branch_table{modality}{binary}. A true materialization flag with
%   any other shape is invalid. Branch identity is never inferred from numeric
%   matrix size.
%
% Materialization and performance
%   Raw execution may scan all data and invoke SPM via the materializer. Resident
%   selection is metadata-only plus cell-shelf indexing and is safe inside CV
%   loops.
%
% Failure semantics
%   Invalid state/container shapes or missing binary-specific metadata raise
%   explicit errors before preprocessing continues.
%
% Side effects
%   Updates inp.isSpatialPreprocessed, inp.spatial_branch_table, and inp.iYw only
%   when raw data are materialized.
%
% Consumers and dependencies
%   Called by nk_PerfPreprocess. Indirect consumers include training,
%   nk_ApplyTrainedPreproc, OOCV, model visualization, MLI, and model export.

global PREPROC
sYocv = [];
sCocv = [];
sAltY = [];
sYw = [];

if isfield(paramfl,'PREPROC')
    activePreproc = paramfl.PREPROC;
else
    activePreproc = PREPROC;
end

if ~nk_HasSpatialSteps(activePreproc)
    optfl = false;
    sY = Y;
    if ~isempty(Yocv), sYocv = Yocv; end
    if ~isempty(Cocv), sCocv = Cocv; end
    if ~isempty(AltY), sAltY = AltY; end
    if isfield(inp,'iYw'), sYw = inp.iYw; end
    return
end

optfl = true;
modal = paramfl.currmodal;
runSpatialPreproc = ~nk_IsSpatialPreprocessed(inp, modal);
preprocByBinary = current_binary_preproc(activePreproc, paramfl, kbin, inp);

if runSpatialPreproc
    [sY, sYocv, sCocv, sAltY, sYw, branchTables] = ...
        nk_MaterializeSpatialShelves(Y, Yocv, Cocv, AltY, inp, ...
        preprocByBinary, paramfl, kbin);
    inp = store_materialization(inp, modal, branchTables, sYw);
    return
end

branchTables = get_branch_tables(inp, modal, kbin);
sY = select_dataset(Y, branchTables, preprocByBinary, kbin, 'training/CV');
if ~isempty(Yocv)
    sYocv = select_dataset(Yocv, branchTables, preprocByBinary, kbin, 'independent-test');
end
if ~isempty(Cocv)
    sCocv = select_dataset(Cocv, branchTables, preprocByBinary, kbin, 'calibration');
end
if ~isempty(AltY)
    sAltY = select_dataset(AltY, branchTables, preprocByBinary, kbin, 'alternative training/CV');
end
if isfield(inp,'iYw') && ~isempty(inp.iYw)
    sYw = select_weight_shelves(inp.iYw, branchTables, preprocByBinary, kbin);
end
end

function preprocByBinary = current_binary_preproc(PREPROC, paramfl, kbin, inp)
if isfield(inp,'multiflag') && inp.multiflag
    preprocByBinary = nk_SetParamChain(paramfl, 1, PREPROC);
    return
end
preprocByBinary = cell(kbin,1);
for u = 1:kbin
    preprocByBinary{u} = nk_SetParamChain(paramfl, u, PREPROC);
end
end

function inp = store_materialization(inp, modal, branchTables, sYw)
if ~isfield(inp,'isSpatialPreprocessed') || numel(inp.isSpatialPreprocessed) < modal
    flags = false(1,modal);
    if isfield(inp,'isSpatialPreprocessed')
        flags(1:numel(inp.isSpatialPreprocessed)) = inp.isSpatialPreprocessed;
    end
    inp.isSpatialPreprocessed = flags;
end
inp.isSpatialPreprocessed(modal) = true;

if ~isfield(inp,'spatial_branch_table') || numel(inp.spatial_branch_table) < modal
    tables = cell(1,modal);
    if isfield(inp,'spatial_branch_table')
        tables(1:numel(inp.spatial_branch_table)) = inp.spatial_branch_table;
    end
    inp.spatial_branch_table = tables;
end
inp.spatial_branch_table{modal} = branchTables;
if ~isempty(sYw)
    inp.iYw = sYw;
end
end

function branchTables = get_branch_tables(inp, modal, kbin)
if ~isfield(inp,'spatial_branch_table') || numel(inp.spatial_branch_table) < modal
    error('nk_PerfPreprocessSpatial:MissingBranchTables', ...
        'Spatial shelves are marked as materialized, but modality #%g has no branch metadata.', modal);
end
branchTables = inp.spatial_branch_table{modal};
if ~iscell(branchTables) || numel(branchTables) ~= kbin
    error('nk_PerfPreprocessSpatial:InvalidBranchTableContainer', ...
        ['Modality #%g requires one spatial branch table per binary classifier ' ...
         '(%g expected).'], modal, kbin);
end
branchTables = branchTables(:);
end

function selected = select_dataset(data, branchTables, preprocByBinary, kbin, dataName)
if ~iscell(data) || size(data,1) ~= kbin
    error('nk_PerfPreprocessSpatial:InvalidShelfContainer', ...
        ['The %s data are marked as spatially materialized but do not use ' ...
         'shelves{binary,instance}{branch}.'], dataName);
end
nInstances = size(data,2);
selected = cell(kbin,nInstances);
for u = 1:kbin
    for n = 1:nInstances
        shelf = data{u,n};
        if ~iscell(shelf) || isempty(shelf)
            error('nk_PerfPreprocessSpatial:InvalidBranchShelf', ...
                'The %s shelf for binary #%g, instance #%g is not a nonempty branch cell.', ...
                dataName, u, n);
        end
        idx = nk_SelectSpatialBranches(branchTables{u}, get_binary_preproc(preprocByBinary,u), numel(shelf));
        selected{u,n} = shelf(idx);
    end
end
if nInstances == 1
    selected = selected(:,1);
end
end

function selected = select_weight_shelves(weightShelves, branchTables, preprocByBinary, kbin)
if ~iscell(weightShelves) || numel(weightShelves) ~= kbin
    error('nk_PerfPreprocessSpatial:InvalidWeightShelfContainer', ...
        'Spatial weighting maps must use one branch shelf per binary classifier.');
end
selected = cell(kbin,1);
for u = 1:kbin
    shelf = weightShelves{u};
    if ~iscell(shelf) || isempty(shelf)
        error('nk_PerfPreprocessSpatial:InvalidWeightShelf', ...
            'The weighting-map shelf for binary classifier #%g is invalid.', u);
    end
    idx = nk_SelectSpatialBranches(branchTables{u}, get_binary_preproc(preprocByBinary,u), numel(shelf));
    selected{u} = shelf(idx);
end
end

function PREPROC = get_binary_preproc(preprocByBinary, u)
if iscell(preprocByBinary)
    PREPROC = preprocByBinary{u};
else
    PREPROC = preprocByBinary;
end
end

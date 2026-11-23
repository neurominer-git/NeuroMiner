function inp = nk_PerfInitSpatial(analysis, inp, paramfl)
% nk_PerfInitSpatial - Materialize the optimized spatial shelf set once.
%
% Purpose
%   Before trained-model application loops over CV2 partitions, collect the
%   preprocessing parameter values required by the selected trained models and
%   materialize only their subject-spatial shelves.
%
% Syntax
%   inp = nk_PerfInitSpatial(analysis, inp, paramfl)
%
% Inputs
%   analysis
%       Trained analysis containing optimized preprocessing parameter columns.
%   inp
%       Application runtime state with raw modality data, active GridAct indices,
%       PREPROC, class count, and optional external/calibration/alternative data.
%   paramfl
%       Runtime preprocessing flags, scalar or modality-specific cell array.
%
% Outputs
%   inp
%       State containing inp.X(modality).sY and optional sYocv/sCocv/sAltY/sYw in the
%       canonical shelves{binary,instance}{branch} representation, plus
%       spatial_branch_table{modality}{binary} and modality materialization flags.
%
% Authority and flow
%   nk_PrepPreprocParams identifies the union of trained values requested by the
%   caller's inp.ll selection. nk_SetParamChain restores those values per binary.
%   nk_MaterializeSpatialShelves is the sole execution/materialization authority.
%   nk_ApplyTrainedPreproc subsequently selects the shelves required by each CV2
%   partition without rematerializing them.
%
% Scientific/state contract and invariants
%   One optimized shelf set is resident per modality. Every binary shelf has its
%   own matching branch table. Stale materialized fields are removed before the
%   new set is stored.
%
% Materialization and performance
%   This is the expensive application boundary and may load a configured
%   calibration MAT file, scan all supplied data, and invoke SPM. It is intended
%   to run once before consumer CV loops, not once per nk_ApplyTrainedPreproc call.
%
% Failure semantics
%   Parameter extraction or shelf/table disagreement propagates as an explicit
%   error; no partial materialization is marked valid.
%
% Side effects
%   Replaces resident sY/sYocv/sCocv/sAltY/sYw and spatial branch metadata in inp.
%
% Consumers and dependencies
%   Called by OOCV, model visualization, MLI, model export, and the smooth-only
%   branch of nk_ApplyTrainedPreproc. Depends on nk_PrepPreprocParams,
%   nk_SetParamChain, and nk_MaterializeSpatialShelves.

global VERBOSE

kbin = inp.nclass;
nM = numel(inp.PREPROC);
inp.isSpatialPreprocessed = false(1,nM);
inp.spatial_branch_table = cell(1,nM);
inp.X = clear_materialized_fields(inp.X);

for n = 1:nM
    [PREPROC, Xn] = modality_state(inp, n, nM);
    if ~nk_HasSpatialSteps(PREPROC)
        continue
    end

    if iscell(paramfl)
        tparamfl = paramfl{n};
    else
        tparamfl = paramfl;
    end
    tparamfl.PV = Xn;
    tparamfl.currmodal = n;
    if VERBOSE
        if isfield(inp,'f')
            fprintf('\nGenerate optimized subject-spatial shelves for CV2 partition [%g,%g].', inp.f, inp.d);
        else
            fprintf('\nGenerate optimized subject-spatial shelves.');
        end
    end
    tparamfl = nk_PrepPreprocParams(PREPROC, tparamfl, analysis, n, inp.ll, inp.curlabel);
    preprocByBinary = binary_preproc(PREPROC, tparamfl, kbin, inp);

    [Yocv, yocvShelfField] = get_oocv_input(Xn);
    Cocv = calibration_input(inp, Xn, n, nM);
    AltY = get_field_or_empty(Xn, 'altY');
    materialInp = modality_weight_input(inp, Xn);
    [sY, sYocv, sCocv, sAltY, sYw, branchTables] = ...
        nk_MaterializeSpatialShelves(Xn.Y, Yocv, Cocv, AltY, materialInp, ...
        preprocByBinary, tparamfl, kbin);

    inp.X(n).sY = sY;
    if ~isempty(sYocv), inp.X(n).(yocvShelfField) = sYocv; end
    if ~isempty(sCocv), inp.X(n).sCocv = sCocv; end
    if ~isempty(sAltY), inp.X(n).sAltY = sAltY; end
    if ~isempty(sYw), inp.X(n).sYw = sYw; end
    inp.spatial_branch_table{n} = branchTables;
    inp.isSpatialPreprocessed(n) = true;
end
end

function [PREPROC, Xn] = modality_state(inp, n, nM)
if iscell(inp.PREPROC)
    PREPROC = inp.PREPROC{n};
else
    if nM ~= 1
        error('nk_PerfInitSpatial:PreprocModalityMismatch', ...
            'A noncell PREPROC can describe only one modality.');
    end
    PREPROC = inp.PREPROC;
end
Xn = inp.X(n);
if ~isfield(Xn,'Y') || isempty(Xn.Y)
    error('nk_PerfInitSpatial:MissingModalityData', ...
        'Modality #%g has no raw Y data for spatial materialization.', n);
end
end

function preprocByBinary = binary_preproc(PREPROC, paramfl, kbin, inp)
if isfield(inp,'multiflag') && inp.multiflag
    preprocByBinary = nk_SetParamChain(paramfl, 1, PREPROC);
else
    preprocByBinary = cell(kbin,1);
    for u = 1:kbin
        preprocByBinary{u} = nk_SetParamChain(paramfl, u, PREPROC);
    end
end
end

function value = get_field_or_empty(S, fieldName)
value = [];
if isfield(S,fieldName) && ~isempty(S.(fieldName))
    value = S.(fieldName);
end
end

function [Yocv, shelfField] = get_oocv_input(X)
Yocv = [];
shelfField = 'sYocv';
if isfield(X,'Yocv2') && ~isempty(X.Yocv2)
    Yocv = X.Yocv2;
    shelfField = 'sYocv2';
elseif isfield(X,'Yocv') && ~isempty(X.Yocv)
    Yocv = X.Yocv;
end
end

function Cocv = calibration_input(inp, X, modal, nModalities)
Cocv = get_field_or_empty(X, 'Cocv');
if ~isempty(Cocv)
    return
end
if ~isfield(inp,'C') || isempty(inp.C) || ~inp.C{1,1}.calibflag
    return
end
if nModalities > 1
    error('nk_PerfInitSpatial:MissingModalityCalibration', ...
        ['Calibration is configured for a multimodal application, but modality ' ...
         '#%g has no explicit X(%g).Cocv data.'], modal, modal);
end
source = inp.C{1,1}.Y;
if ischar(source) || (isstring(source) && isscalar(source))
    loaded = load(char(source), 'CY');
    if ~isfield(loaded,'CY')
        error('nk_PerfInitSpatial:MissingCalibrationVariable', ...
            'Calibration MAT file %s does not contain variable CY.', char(source));
    end
    Cocv = loaded.CY;
else
    Cocv = source;
end
end

function materialInp = modality_weight_input(inp, Xn)
materialInp = inp;
if isfield(materialInp,'Yw'), materialInp = rmfield(materialInp,'Yw'); end
if isfield(materialInp,'iYw'), materialInp = rmfield(materialInp,'iYw'); end
if isfield(Xn,'Yw') && ~isempty(Xn.Yw)
    materialInp.iYw = Xn.Yw;
end
end

function X = clear_materialized_fields(X)
fields = {'sY','sYocv','sYocv2','sAltY','sCocv','sYw','spatial_branch_table'};
present = fields(isfield(X,fields));
if ~isempty(present)
    X = rmfield(X,present);
end
end

function inp = nk_SmoothMask( uPREPROC, inp, paramfl, curclass )
% nk_SmoothMask - Detect and spatially process weighting masks.
%
% This function intentionally remains the single backend entry point for
% weighting-map detection, preserving the legacy NM flow:
%   1) weighting maps read during data input: inp.Yw / inp.iYw
%   2) step-bound external ranking maps: PREPROC.ACTPARAM{q}.RANK.EXTERN
%
% The function writes the spatially processed weighting map to inp.iYw.
% For wavelet spatial branches, SPATIAL.WAVELET.applyWaveletToExternalWeightMap
% controls whether the weighting map receives the same wavelet reconstruction
% as the data or is copied unchanged across wavelet branches.
%
% (c) Nikolaos Koutsouleris

if ~local_has_spatial_preproc(uPREPROC)
    return
end

% -------------------------------------------------------------------------
% 1) Legacy weighting-map source detection
% -------------------------------------------------------------------------
Yw = [];
haveWeight = false;
source = '';
rankStep = [];

% First priority: weighting mask uploaded/read during data input.
if isfield(inp,'Yw') || isfield(inp,'iYw')
    if isfield(inp,'Yw')
        Yw = inp.Yw;
    else
        Yw = inp.iYw;
    end
    haveWeight = true;
    source = 'data_input';
else
    % Second priority: ranking modules using an external weighting map.
    if isfield(uPREPROC,'ACTPARAM') && ~isempty(uPREPROC.ACTPARAM)
        I = false(1,numel(uPREPROC.ACTPARAM));
        for j = 1:numel(uPREPROC.ACTPARAM)
            I(j) = isfield(uPREPROC.ACTPARAM{j},'RANK');
        end
        Ix = find(I);
        for qx = 1:numel(Ix)
            RANK = uPREPROC.ACTPARAM{Ix(qx)}.RANK;
            if isfield(RANK,'algostr') && strcmpi(RANK.algostr,'extern') && ...
                    isfield(RANK,'EXTERN') && ~isempty(RANK.EXTERN)
                Yw = RANK.EXTERN;
                haveWeight = true;
                source = 'rank_extern';
                rankStep = Ix(qx);
                break
            end
        end
    end
end

if ~haveWeight || isempty(Yw)
    return
end

% Binary-specific input-side weighting maps are stored as cells.
if strcmp(source,'data_input') && exist('curclass','var') && ...
        iscell(Yw) && ~isempty(Yw) && ~isempty(Yw{1})
    fprintf('\nSmoothing the weighting map uploaded during data input for binary classifier #%g.', curclass)
    Yw = Yw{curclass};
elseif strcmp(source,'data_input')
    fprintf('\nSmoothing the weighting map uploaded during data input.')
elseif strcmp(source,'rank_extern')
    if ~isempty(rankStep)
        fprintf('\nSmoothing the external weighting map found in preprocessing chain (preprocessing step #%g).', rankStep)
    else
        fprintf('\nSmoothing the external weighting map found in preprocessing chain.')
    end
end

Param = local_get_param(inp, paramfl);
inp.iYw = local_apply_spatial_weight_chain(Yw, uPREPROC, Param);

end

% =========================================================================
% Local implementation details
% =========================================================================
function tf = local_has_spatial_preproc(PREPROC)
steps = nk_NormalizeSpatialSteps(PREPROC);
tf = ~isempty(steps) && any([steps.cubetype] > 1);
end

function Param = local_get_param(inp, paramfl)
Param = [];
if exist('paramfl','var') && isstruct(paramfl)
    if isfield(paramfl,'PV')
        Param = paramfl.PV;
        return
    elseif isfield(paramfl,'X')
        Param = paramfl.X;
        return
    end
end
if isfield(inp,'P') && isfield(inp.P,'X')
    Param = inp.P.X;
elseif isfield(inp,'X')
    Param = inp.X;
end
end

function Wout = local_apply_spatial_weight_chain(W, PREPROC, Param)
% Apply only image-preserving spatial operations to weighting maps. Terminal
% feature extractors such as JuSpace, ROI means and graph construction are
% deliberately not applied to weighting maps.
steps = nk_NormalizeSpatialSteps(PREPROC);
if isempty(steps)
    Wout = W;
    return
end

branches = {W};
for s = 1:numel(steps)
    step = steps(s);

    % Stop before terminal feature-space conversions.
    if ~ismember(step.cubetype, [2 3 4 6 9])
        break
    end

    nextBranches = {};
    if local_is_wavelet_step(step) && ~local_apply_wavelet_to_weight_map(step)
        nB = local_spatial_branch_count(step);
        for b = 1:numel(branches)
            for q = 1:nB
                nextBranches{end+1,1} = branches{b}; %#ok<AGROW>
            end
        end
        fprintf('\nExternal weighting image: wavelet reconstruction skipped; map copied to %g wavelet branch(es).', nB);
    else
        for b = 1:numel(branches)
            CURACT = struct('SPATIAL', step);
            if ~isempty(Param)
                stepOut = nk_PerfSpatFilt(branches{b}, CURACT, Param);
            else
                stepOut = nk_SpatFilt(branches{b}, step);
            end
            if ~iscell(stepOut)
                stepOut = {stepOut};
            end
            for q = 1:numel(stepOut)
                nextBranches{end+1,1} = stepOut{q}; %#ok<AGROW>
            end
        end
    end
    branches = nextBranches;
end

if numel(branches) == 1
    Wout = branches{1};
else
    Wout = branches;
end
end

function tf = local_is_wavelet_step(step)
tf = isfield(step,'cubetype') && double(step.cubetype) == 9;
if ~tf && isfield(step,'cmd') && ~isempty(step.cmd)
    tf = strcmpi(char(step.cmd),'waveletSpatial');
end
if ~tf && isfield(step,'WAVELET') && isstruct(step.WAVELET)
    tf = true;
end
end

function tf = local_apply_wavelet_to_weight_map(step)
% Explicit user setting has priority. Without the flag, use the intended
% auto-policy: approximation and denoised are image-reconstruction-like;
% selected detail modes are residual/detail feature spaces.
tf = [];
if isfield(step,'WAVELET') && isstruct(step.WAVELET)
    W = step.WAVELET;
    if isfield(W,'applyWaveletToExternalWeightMap') && ~isempty(W.applyWaveletToExternalWeightMap)
        tf = logical(W.applyWaveletToExternalWeightMap);
        return
    end
    if isfield(W,'ApplyWaveletToExternalWeightMap') && ~isempty(W.ApplyWaveletToExternalWeightMap)
        tf = logical(W.ApplyWaveletToExternalWeightMap);
        return
    end
end

if isempty(tf)
    mode = local_wavelet_mode(step);
    tf = any(strcmpi(mode, {'approximation','denoised','wavelet_denoised'}));
end
end

function mode = local_wavelet_mode(step)
mode = '';
if isfield(step,'WAVELET') && isstruct(step.WAVELET)
    W = step.WAVELET;
    if isfield(W,'reconstructionMode') && ~isempty(W.reconstructionMode)
        mode = lower(strtrim(char(W.reconstructionMode)));
        return
    elseif isfield(W,'mode') && ~isempty(W.mode)
        mode = lower(strtrim(char(W.mode)));
        return
    end
end
if isfield(step,'reconstructionMode') && ~isempty(step.reconstructionMode)
    mode = lower(strtrim(char(step.reconstructionMode)));
elseif isfield(step,'mode') && ~isempty(step.mode)
    mode = lower(strtrim(char(step.mode)));
end
end

function nB = local_spatial_branch_count(step)
nB = 1;
if isfield(step,'PX') && isstruct(step.PX) && isfield(step.PX,'opt') && ~isempty(step.PX.opt)
    opt = step.PX.opt;
    nParams = 1;
    if isfield(step.PX,'Px') && ~isempty(step.PX.Px)
        nParams = numel(step.PX.Px);
    end
    if nParams == 1 && (isnumeric(opt) || islogical(opt) || isstring(opt) || iscell(opt)) && isvector(opt)
        nB = numel(opt);
    elseif nParams == 1 && ischar(opt)
        nB = size(opt,1);
    else
        if size(opt,2) ~= nParams
            error('nk_SmoothMask:SpatialParameterWidthMismatch', ...
                'Spatial PX.opt has %g columns, but PX.Px defines %g parameters.', ...
                size(opt,2), nParams);
        end
        nB = size(opt,1);
    end
    nB = max(1,nB);
    return
end
if isfield(step,'WAVELET') && isstruct(step.WAVELET) && ...
        isfield(step.WAVELET,'levels') && ~isempty(step.WAVELET.levels)
    nB = max(1,numel(step.WAVELET.levels));
end
end

function steps = nk_NormalizeSpatialSteps(PREPROC)
% nk_NormalizeSpatialSteps - Return a canonical subject-spatial step array.
%
% Accepts legacy scalar PREPROC.SPATIAL and new chained PREPROC.SPATIAL(1:n)
% representations. graphComputation/KL-divergence steps are normalized to
% cubetype 8 and waveletSpatial steps to cubetype 9 for runtime dispatch.

steps = struct([]);

if nargin < 1 || isempty(PREPROC)
    return
end

if iscell(PREPROC)
    if isempty(PREPROC), return; end
    PREPROC = PREPROC{1};
end

if isfield(PREPROC,'SPATIAL')
    S = PREPROC.SPATIAL;
else
    S = PREPROC;
end

if isempty(S)
    return
end

if iscell(S)
    for i = 1:numel(S)
        if isempty(S{i}), continue; end
        st = normalize_one_step(S{i});
        if st.cubetype > 1
            steps = append_step(steps, st);
        end
    end
else
    for i = 1:numel(S)
        st = normalize_one_step(S(i));
        if st.cubetype > 1
            steps = append_step(steps, st);
        end
    end
end
end

function steps = append_step(steps, st)
if isempty(steps)
    steps = st;
    return
end
fOld = fieldnames(steps);
fNew = fieldnames(st);
for i=1:numel(fNew)
    if ~isfield(steps, fNew{i})
        [steps.(fNew{i})] = deal([]);
    end
end
for i=1:numel(fOld)
    if ~isfield(st, fOld{i})
        st.(fOld{i}) = [];
    end
end
steps(end+1) = st;
end

function st = normalize_one_step(st)

if ~isfield(st,'cmd') || isempty(st.cmd)
    st.cmd = cmd_from_cubetype(st);
end

if isfield(st,'cmd') && strcmpi(st.cmd,'waveletSpatial')
    st.cubetype = 9;
end

if isfield(st,'cmd') && strcmpi(st.cmd,'graphComputation')
    if ~isfield(st,'GRAPHCONSTRUCTION') || isempty(st.GRAPHCONSTRUCTION)
        error('Subject-specific graphComputation requires a GRAPHCONSTRUCTION field.');
    end
    if ~isfield(st.GRAPHCONSTRUCTION,'method') || ...
            ~strcmpi(st.GRAPHCONSTRUCTION.method,'KL divergence')
        error('Only graphComputation with method ''KL divergence'' is allowed as subject-specific spatial preprocessing.');
    end
    st.cubetype = 8;
end

if ~isfield(st,'cubetype') || isempty(st.cubetype)
    st.cubetype = cubetype_from_cmd(st.cmd);
end

if ~isfield(st,'PX') || ~isfield(st.PX,'opt') || isempty(st.PX.opt)
    st.PX.opt = default_opt(st);
end

% PX.opt rows are branch alternatives and columns are parameters. Legacy
% one-parameter steps often store alternatives as a row vector; transpose only
% that representation. A multi-parameter one-row combination must remain a row.
nStepParams = 1;
if isfield(st.PX,'Px') && ~isempty(st.PX.Px)
    nStepParams = numel(st.PX.Px);
end
if nStepParams == 1 && ((isnumeric(st.PX.opt) || islogical(st.PX.opt) || ...
        isstring(st.PX.opt) || iscell(st.PX.opt)) && isrow(st.PX.opt))
    st.PX.opt = st.PX.opt(:);
elseif nStepParams > 1 && size(st.PX.opt,2) ~= nStepParams
    error('nk_NormalizeSpatialSteps:SpatialParameterWidthMismatch', ...
        'Spatial step PX.opt has %g columns, but PX.Px defines %g parameters.', ...
        size(st.PX.opt,2), nStepParams);
end
end

function cmd = cmd_from_cubetype(st)
cmd = '';
if ~isfield(st,'cubetype') || isempty(st.cubetype)
    return
end
switch st.cubetype
    case 2
        cmd = 'absdiff6';
    case 3
        cmd = 'cubevar27';
    case 4
        cmd = 'smoothing';
    case 5
        cmd = 'JuSpace';
    case 6
        cmd = 'reslice';
    case 7
        cmd = 'ROImeans';
    case 8
        cmd = 'graphComputation';
    case 9
        cmd = 'waveletSpatial';
end
end

function cubetype = cubetype_from_cmd(cmd)
cubetype = 1;
if isempty(cmd), return; end
switch lower(cmd)
    case {'absdiff6','absdiff','absolute difference weighting (6 neighbors)'}
        cubetype = 2;
    case {'cubevar27','cubevariance','spatial variance weighting (27 neighbors)'}
        cubetype = 3;
    case {'smoothing','smooth','gaussian smoothing'}
        cubetype = 4;
    case {'juspace','neurotransmitter correlations'}
        cubetype = 5;
    case {'reslice','reslicing'}
        cubetype = 6;
    case {'roimeans','roi means computation'}
        cubetype = 7;
    case {'graphcomputation','graph construction'}
        cubetype = 8;
    case {'waveletspatial','wavelet','spatialwavelet','wavelet reconstruction'}
        cubetype = 9;
end
end

function opt = default_opt(st)
if isfield(st,'cubetype')
    switch st.cubetype
        case 4
            if isfield(st,'cubefwhm') && ~isempty(st.cubefwhm)
                opt = st.cubefwhm;
            elseif isfield(st,'fwhm') && ~isempty(st.fwhm)
                opt = st.fwhm;
            else
                opt = 0;
            end
        case 6
            if isfield(st,'cubevoxdim') && ~isempty(st.cubevoxdim)
                opt = st.cubevoxdim;
            elseif isfield(st,'cubevoxres') && ~isempty(st.cubevoxres)
                opt = st.cubevoxres;
            else
                opt = 0;
            end
        case 9
            if isfield(st,'WAVELET') && isfield(st.WAVELET,'levels') && ~isempty(st.WAVELET.levels)
                opt = st.WAVELET.levels(:);
            elseif isfield(st,'levels') && ~isempty(st.levels)
                opt = st.levels(:);
            else
                opt = 1;
            end
        otherwise
            opt = 1;
    end
else
    opt = 1;
end
end

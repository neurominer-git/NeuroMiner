function Yout = nk_WaveletSpatialReconstruct(Y, SPATIAL, level)
% nk_WaveletSpatialReconstruct - Image-preserving 3-D undecimated wavelet reconstruction.
%
% Syntax:
%   Yout = nk_WaveletSpatialReconstruct(Y, SPATIAL, level)
%
% Description:
%   Performs an undecimated a trous-style 3-D wavelet decomposition in the
%   mask-defined image grid and reconstructs an image-space matrix with the
%   same number and order of voxels as Y. The implementation is vectorized
%   across subject batches by storing data as a 4-D array [X Y Z subject] and
%   applying separable 3-D convolutions with singleton kernels in the subject
%   dimension. No Wavelet Toolbox dependency is required.
%
%   The output always remains in the original SPATIAL.dims / SPATIAL.indvol
%   grid. Multiple wavelet levels are handled as spatial preprocessing
%   branches by nk_SpatFilt through PREPROC.SPATIAL(i).PX.opt.
%
% Required SPATIAL fields:
%   dims      - 3-D volume dimensions
%   indvol    - mask voxel indices in the 3-D volume
%   WAVELET   - configuration struct
%
% WAVELET fields:
%   family              'b3spline' or 'haar'/'db1'
%                       Note: haar/db1 is implemented as a centered 3-tap
%                       binomial low-pass [1 2 1]/4. The classical two-tap
%                       Haar smoother is not used because it introduces a
%                       half-voxel phase shift under convn(...,'same').
%   boundary            'mirror' or 'zero' (default: mirror)
%   reconstructionMode  'approximation', 'selected_details', 'denoised',
%                       'detail_bands', 'detail_magnitude', or 'detail_energy'
%   detailLevels        vector of levels for selected_details
%   thresholdMode       'none', 'soft', or 'hard'
%   thresholdSigma      robust threshold multiplier
%   batchSize           subject batch size

if nargin < 3 || isempty(level), level = 1; end
if isempty(Y), Yout = Y; return; end

if ~isfield(SPATIAL,'dims') || isempty(SPATIAL.dims) || ~isfield(SPATIAL,'indvol') || isempty(SPATIAL.indvol)
    error('nk_WaveletSpatialReconstruct:missingGeometry', 'SPATIAL.dims and SPATIAL.indvol are required.');
end
if ~isfield(SPATIAL,'WAVELET') || isempty(SPATIAL.WAVELET)
    W = struct();
else
    W = SPATIAL.WAVELET;
end

level = max(1, round(double(level(1))));
family = getfield_default(W, 'family', 'b3spline');
boundary = lower(char(getfield_default(W, 'boundary', 'mirror')));
mode = getfield_default(W, 'reconstructionMode', getfield_default(W, 'mode', 'approximation'));
detailLevels = getfield_default(W, 'detailLevels', level);
thresholdMode = getfield_default(W, 'thresholdMode', 'soft');
thresholdSigma = getfield_default(W, 'thresholdSigma', 3);
batchSize = max(1, round(double(getfield_default(W, 'batchSize', 8))));
fprintf('\nWavelet Spatial Reconstruction (%s):',mode);
if ~ismember(boundary, {'mirror','zero'})
    error('nk_WaveletSpatialReconstruct:badBoundary', 'Unsupported wavelet boundary mode: %s', boundary);
end

nSub = size(Y,1);
Yout = zeros(size(Y), class(Y));
dims = double(SPATIAL.dims(:)');
if numel(dims) ~= 3
    error('nk_WaveletSpatialReconstruct:badDims', 'SPATIAL.dims must contain exactly three dimensions.');
end
prodDims = prod(dims);
indvol = SPATIAL.indvol(:);
if size(Y,2) ~= numel(indvol)
    error('nk_WaveletSpatialReconstruct:dimensionMismatch', ...
        'Y has %d columns, but SPATIAL.indvol contains %d voxels.', size(Y,2), numel(indvol));
end

warn_if_overscaled(family, level, dims);

for st = 1:batchSize:nSub
    en = min(nSub, st + batchSize - 1);
    Yb = double(Y(st:en,:));
    nb = size(Yb,1);
    A2 = zeros(prodDims, nb);
    A2(indvol,:) = Yb.';
    A = reshape(A2, [dims nb]);
    clear A2

    switch lower(char(mode))
        case 'approximation'
            R = wavelet_approximation(A, level, family, boundary);
        case {'selected_details','details','detail'}
            R = wavelet_selected_details(A, level, family, boundary, detailLevels);
        case {'detail_bands','detail_band','scale_specific_details','scale_specific_detail','band_details','band_detail'}
            R = wavelet_detail_band(A, level, family, boundary);
        case {'detail_magnitude','detail_abs','absolute_details','abs_detail','abs_details'}
            R = abs(wavelet_detail_band(A, level, family, boundary));
        case {'detail_energy','squared_details','detail_power'}
            D = wavelet_detail_band(A, level, family, boundary);
            R = D .* D;
        case 'denoised'
            R = wavelet_denoised(A, level, family, boundary, thresholdMode, double(thresholdSigma), indvol);
        otherwise
            error('nk_WaveletSpatialReconstruct:badMode','Unknown wavelet reconstruction mode: %s', char(mode));
    end

    gotDims = [size(R,1) size(R,2) size(R,3)];
    if ~isequal(gotDims, dims)
        error('nk_WaveletSpatialReconstruct:outputGeometryMismatch', ...
            'Wavelet reconstruction changed image geometry; expected [%s], got [%s].', ...
            num2str(dims), num2str(gotDims));
    end

    R2 = reshape(R, prodDims, nb);
    Yout(st:en,:) = cast(R2(indvol,:).', class(Yout));
    fprintf('.')
end
end

function A = wavelet_approximation(A, level, family, boundary)
for j = 1:level
    A = smooth_at_level(A, family, boundary, j);
end
end

function R = wavelet_selected_details(A, level, family, boundary, detailLevels)
if isempty(detailLevels), detailLevels = level; end
detailLevels = unique(round(double(detailLevels(:)')));
detailLevels = detailLevels(detailLevels >= 1 & detailLevels <= level);
if isempty(detailLevels), detailLevels = level; end
R = zeros(size(A));
Prev = A;
for j = 1:level
    Curr = smooth_at_level(Prev, family, boundary, j);
    if any(detailLevels == j)
        R = R + (Prev - Curr);
    end
    Prev = Curr;
end
end


function R = wavelet_detail_band(A, level, family, boundary)
% Return only the scale-specific signed detail band for the requested branch
% level: D_level = A_{level-1} - A_level. This differs from
% wavelet_selected_details, which sums all configured detail bands up to the
% current branch level.
Prev = A;
R = zeros(size(A));
for j = 1:level
    Curr = smooth_at_level(Prev, family, boundary, j);
    if j == level
        R = Prev - Curr;
        return
    end
    Prev = Curr;
end
end

function R = wavelet_denoised(A, level, family, boundary, thresholdMode, thresholdSigma, indvol)
Prev = A;
details = cell(1,level);
for j = 1:level
    Curr = smooth_at_level(Prev, family, boundary, j);
    D = Prev - Curr;
    details{j} = threshold_detail(D, indvol, thresholdMode, thresholdSigma);
    Prev = Curr;
end
R = Prev;
for j = 1:level
    R = R + details{j};
end
end

function D = threshold_detail(D, indvol, thresholdMode, thresholdSigma)
if strcmpi(char(thresholdMode),'none') || thresholdSigma <= 0
    return
end
sz = size(D);
nb = size(D,4);
D2 = reshape(D, [], nb);
X = D2(indvol,:);
med = robust_nanmedian(X);
sigma = robust_nanmedian(abs(bsxfun(@minus, X, med))) ./ 0.6745;
sigma(~isfinite(sigma) | sigma <= 0) = eps;
thr = thresholdSigma .* sigma;
for b = 1:nb
    db = D2(:,b);
    t = thr(b);
    switch lower(char(thresholdMode))
        case 'soft'
            db = sign(db) .* max(abs(db) - t, 0);
        case 'hard'
            db(abs(db) < t) = 0;
        otherwise
            % Unknown threshold labels are treated conservatively as no thresholding.
    end
    D2(:,b) = db;
end
D = reshape(D2, sz);
end

function A = smooth_at_level(A, family, boundary, level)
k = wavelet_kernel(family);
k = dilate_kernel(k, level);
A = conv_along_dim(A, k, 1, boundary);
A = conv_along_dim(A, k, 2, boundary);
A = conv_along_dim(A, k, 3, boundary);
end

function A = conv_along_dim(A, k, dim, boundary)
L = numel(k);
if mod(L,2) ~= 1
    error('nk_WaveletSpatialReconstruct:nonCenteredKernel', ...
        'A trous smoothing kernels must have odd length to preserve image alignment.');
end
kerSize = ones(1, ndims(A));
kerSize(dim) = L;
K = reshape(k, kerSize);

switch lower(char(boundary))
    case 'zero'
        A = convn(A, K, 'same');
    case 'mirror'
        pad = (L - 1) / 2;
        if pad == 0
            A = convn(A, K, 'same');
        else
            Ap = pad_symmetric_along_dim(A, pad, dim);
            A = convn(Ap, K, 'valid');
        end
    otherwise
        error('nk_WaveletSpatialReconstruct:badBoundary', 'Unsupported boundary mode: %s', char(boundary));
end
end

function Ap = pad_symmetric_along_dim(A, pad, dim)
if pad <= 0
    Ap = A;
    return
end
n = size(A, dim);
idx = symmetric_indices(n, pad);
subs = repmat({':'}, 1, ndims(A));
subs{dim} = idx;
Ap = A(subs{:});
end

function idx = symmetric_indices(n, pad)
% Symmetric mirror padding with edge duplication, matching padarray(...,'symmetric')
% behavior for one dimension, without requiring the Image Processing Toolbox.
if n <= 0
    idx = [];
    return
end
if n == 1
    idx = ones(1, 1 + 2*pad);
    return
end
q = (1-pad):(n+pad);
period = 2*n;
r = mod(q - 1, period) + 1;
idx = r;
hi = r > n;
idx(hi) = period - r(hi) + 1;
end

function k = wavelet_kernel(family)
switch lower(char(family))
    case {'haar','db1'}
        % Phase-safe Haar/db1 surrogate for the undecimated a trous path.
        % The classical two-tap Haar smoother [1 1]/2 is not centered under
        % convn(...,'same') and therefore shifts the image grid by 0.5 voxel
        % per smoothing pass. Use the centered three-tap binomial low-pass
        % instead so reconstructed branches remain aligned to SPATIAL.Vm.
        k = [1 2 1] ./ 4;
    case {'b3spline','b3','spline'}
        k = [1 4 6 4 1] ./ 16;
    otherwise
        error('nk_WaveletSpatialReconstruct:badFamily','Unsupported wavelet kernel: %s', char(family));
end
end

function kd = dilate_kernel(k, level)
level = max(1, round(double(level)));
step = 2^(level-1);
if step == 1
    kd = k;
    return
end
kd = zeros(1, (numel(k)-1)*step + 1);
kd(1:step:end) = k;
end

function warn_if_overscaled(family, level, dims)
k = wavelet_kernel(family);
span = (numel(k)-1) * 2^(level-1) + 1;
if span > min(double(dims(:)))
    warning('nk_WaveletSpatialReconstruct:largeKernelSpan', ...
        ['The dilated wavelet kernel span (%d voxels) exceeds the minimum image dimension (%d voxels). ', ...
         'The requested level may produce an over-smoothed or nearly constant approximation.'], ...
         span, min(double(dims(:))));
end
end

function med = robust_nanmedian(X)
med = nan(1, size(X,2));
for c = 1:size(X,2)
    xc = X(:,c);
    xc = xc(isfinite(xc));
    if isempty(xc)
        med(c) = 0;
    else
        med(c) = median(xc);
    end
end
end

function val = getfield_default(S, fname, defaultVal)
if isstruct(S) && isfield(S, fname) && ~isempty(S.(fname))
    val = S.(fname);
else
    val = defaultVal;
end
end

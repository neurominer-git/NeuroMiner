function Yout = nk_SurfaceHeatFilter(Y, op, fwhm, varargin)
% nk_SurfaceHeatFilter  Apply e^(-t Delta) on a native cortical mesh.
% Symmetric lumped-mass FEM Laplace-Beltrami operator. FWHM is in mm.
% Scaled modified Bessel coefficients implement a Chebyshev heat expansion.
% Row = subject, column = vertex. Constant signals are invariant.

if size(Y,2) ~= op.vertexCount
    error('nk_SurfaceHeatFilter:invalidAxis', ...
        'Surface data columns must match the DataIO mesh vertex count.');
end
if any(~isfinite(Y(:,op.vertexMask)),'all')
    error('nk_SurfaceHeatFilter:invalidInput', ...
        'Surface heat smoothing requires finite values on the selected surface domain.');
end
if ~isscalar(fwhm) || ~isfinite(fwhm) || fwhm < 0
    error('nk_SurfaceHeatFilter:invalidFWHM', 'FWHM must be a nonnegative finite scalar in mm.');
end
if fwhm == 0
    Yout = Y;
    if ~isempty(varargin), varargin{1}(size(Y,1),size(Y,1)); end
    return
end
% The 2-D surface heat kernel locally has variance 2t per tangential axis.
t = double(fwhm)^2/(16*log(2));
alpha = t*op.lambdaBound/2;
% The scaled Bessel coefficients sum to one; their omitted tail bounds
% the heat-filter error in the symmetric mass-weighted spectral norm.
N = ceil(alpha + 12*sqrt(alpha+1));
if N > 2000
    error('nk_SurfaceHeatFilter:unboundedExpansion', ...
        'Requested FWHM requires %d polynomial terms; check mesh units or resolution.',N);
end
coeff = 2*besseli(0:N,alpha,1);
coeff(1) = coeff(1)/2;
last = find(cumsum(coeff) >= 1-1e-12,1,'first');
if isempty(last)
    error('nk_SurfaceHeatFilter:uncertifiedExpansion', ...
        'Chebyshev coefficients do not meet the 1e-12 spectral-tail tolerance.');
end
N = max(1,last-1);
coeff = coeff(1:N+1);
B = op.B;
Yout = zeros(size(Y),'like',Y);
for st = 1:8:size(Y,1)
    rows = st:min(st+7,size(Y,1));
    Y0 = double(Y(rows,:)).';
    Y0(~op.vertexMask,:) = 0;
    Y0 = bsxfun(@times,Y0,op.sqrtMass);
    T0 = Y0;
    T1 = B*Y0;
    Z = coeff(1)*T0 + coeff(2)*T1;
    for k = 2:N
        T2 = 2*B*T1-T0;
        Z = Z + coeff(k+1)*T2;
        T0 = T1;
        T1 = T2;
    end
    Yout(rows,:) = cast(bsxfun(@times,Z,op.inverseSqrtMass).',class(Y));
    Yout(rows,~op.vertexMask) = NaN;
    if ~isempty(varargin), varargin{1}(rows(end),numel(rows)); end
end
end

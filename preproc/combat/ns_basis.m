function [B, model] = ns_basis(x, df, varargin)
% Natural cubic regression spline without intercept: df columns, linear tails.
% Fit knots and scaling on training ages; pass the returned model at apply.
x = x(:);
if any(~isfinite(x)) || df < 1 || df ~= floor(df)
    error('ns_basis:invalidInput', 'Spline ages must be finite and df a positive integer.');
end
if isempty(varargin)
    model = struct('df',df, 'center',mean(x), 'scale',std(x), 'knots',[]);
    if ~isfinite(model.scale) || model.scale <= 0
        error('ns_basis:constantAge', 'Spline training ages must vary.');
    end
    z = (x-model.center)/model.scale;
    model.knots = quantile(z, (0:df)/df);  % two boundary + df-1 interior knots
    if any(diff(model.knots) <= 0)
        error('ns_basis:duplicateKnots', 'Age distribution cannot support the selected spline df.');
    end
else
    model = varargin{1};
    if model.df ~= df
        error('ns_basis:dfMismatch', 'Training and application spline df differ.');
    end
    z = (x-model.center)/model.scale;
end
k = model.knots;
B = zeros(numel(x),df);
B(:,1) = z;
for j = 1:df-1
    a = (k(end)-k(j))/(k(end)-k(end-1));
    b = (k(end-1)-k(j))/(k(end)-k(end-1));
    B(:,j+1) = (max(z-k(j),0).^3 - a*max(z-k(end-1),0).^3 ...
        + b*max(z-k(end),0).^3)/(k(end)-k(1))^2;
end

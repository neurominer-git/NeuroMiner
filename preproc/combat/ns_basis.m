function B = ns_basis(x, df)
% Natural cubic spline basis with 'df' degrees of freedom (df >= 1)
% Returns n x df (first column can be intercept-like; you can drop it if needed)
x = x(:);
kn = linspace(min(x), max(x), max(df-1,2)); % internal knots
% Build truncated power basis then orthonormalize
T = [x, x.^2, x.^3];
for k = 2:numel(kn)-1
    T = [T, max(0, (x - kn(k))).^3]; %#ok<AGROW>
end
% Orthonormalize to improve conditioning
[Q,~] = qr(T,0);
B = Q(:,1:df);

function [dum, levels] = dummy_code_categorical_full(x)
% Dummy-code a categorical variable using k-1 dummies.
% x      : n x 1 numeric
% dum    : n x (k-1)
% levels : sorted unique levels in x

x = x(:);
mask = ~isnan(x);
u = unique(x(mask));
levels = u(:);
k = numel(levels);

if k < 2
    dum = zeros(numel(x),0);
    return;
end

others = levels(2:end);
dum    = zeros(numel(x), numel(others));

for j = 1:numel(others)
    dum(:,j) = double(x == others(j));
end
end
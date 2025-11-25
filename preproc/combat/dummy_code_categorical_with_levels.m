function dum = dummy_code_categorical_with_levels(x, levels)
% Dummy-code using FIXED levels learned from training.
% levels : column vector of levels used in training (first = reference)

x = x(:);
x(isnan(x)) = levels(1);  % treat NaNs as reference (or adapt to your needs)

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

% optional: warn if unseen levels appear
if any(~ismember(x, levels))
    warning('OOCV covariate contains levels not seen in training. They are treated as reference level.');
end
end
% =========================================================================
% FORMAT param = MSEINVDENS(expected, predicted)
% =========================================================================
% Inverse-density weighted mean squared error of regression
% -------------------------------------------------------------------------
% - NaN pairs are ignored.
% - Label density is estimated with a simple Gaussian kernel density
%   implemented from basic MATLAB operations (no toolboxes).
% - Returns NaN if no valid data pairs remain.
% -------------------------------------------------------------------------
% (c) Nikolaos Koutsouleris, 09/2025
% =========================================================================
function param = MSEINVDENS(expected, predicted)

    % No data at all
    if isempty(expected) || isempty(predicted)
        param = [];
        return;
    end

    % Ensure column vectors of same length
    if numel(expected) ~= numel(predicted)
        error('expected and predicted must have the same number of elements.');
    end
    expected  = expected(:);
    predicted = predicted(:);

    % Mask out any NaN pairs
    validMask = ~(isnan(expected) | isnan(predicted));
    validExpected  = expected(validMask);
    validPredicted = predicted(validMask);

    % If no valid data left, return NaN
    if isempty(validExpected)
        param = NaN;
        return;
    end

    % ---------------------------------------------------------------------
    % Gaussian kernel density estimation at each observed y
    % ---------------------------------------------------------------------
    n = numel(validExpected);

    % Silverman's rule-of-thumb bandwidth
    s = std(validExpected);
    if s==0, s = 1; end  % avoid division by zero for constant labels
    h = 1.06 * s * n^(-1/5);

    % Pairwise distance matrix
    % For large n this is O(n^2); acceptable for moderate size.
    Y = validExpected(:);
    diffMat = Y - Y';  % n-by-n matrix of differences

    % Gaussian kernel densities
    gaussKernel = exp(-0.5*(diffMat./h).^2) / (sqrt(2*pi)*h);
    p = mean(gaussKernel, 2);  % density estimate at each observation

    % Avoid division by zero
    p(p <= eps) = eps;

    % ---------------------------------------------------------------------
    % Inverse-density weights (normalised to sum to 1)
    % ---------------------------------------------------------------------
    w = 1 ./ p;
    w = w / sum(w);

    % ---------------------------------------------------------------------
    % Weighted mean squared error
    % ---------------------------------------------------------------------
    diff  = validPredicted - validExpected;
    param = sum(w .* (diff.^2));
end

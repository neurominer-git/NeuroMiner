% =========================================================================
% FORMAT param = MSE(expected, predicted)
% =========================================================================
% Compute Mean Standand Error of regression
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris, 09/2025

function param = MSE(expected, predicted)
%MSE  Mean squared error ignoring NaNs
%     Returns NaN if no valid data pairs remain.

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

    % Mean squared error over valid pairs
    diff   = validPredicted - validExpected;
    param  = mean(diff.^2);
end

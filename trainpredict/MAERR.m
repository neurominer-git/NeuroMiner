% =========================================================================
% FORMAT param = MAERR(expected, predicted)
% =========================================================================
% Compute Mean Absolute Error of regression
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris, 09/2025

function [param, stdparam] = MAERR(expected, predicted)
if isempty(expected), param = []; return; end

% Mask out any NaN pairs
validMask = ~(isnan(expected) | isnan(predicted));
validExpected  = expected(validMask);
validPredicted = predicted(validMask);

% If no valid data left, return NaN
if isempty(validExpected)
    param = NaN;
    return;
end
diff = validPredicted-validExpected;
param = mean(abs(diff));
stdparam = std(abs(diff));

end
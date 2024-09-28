function y = calibrateScores(score,scoreMapping)
%CALIBRATESCORES Calibrate scores
% y = calibrateScores(score,scoreMapping) maps the raw scores to calibrated
% scores, y, using the score mappinging information in scoreMapping.
% Specify score as a vector or matrix of raw scores. Specify score mapping
% as either struct or a two-element vector. If scoreMapping is specified as
% a struct, then it should have two fields: Raw and Calibrated, that
% together form a score mapping. If scoreMapping is specified as a vector,
% then the elements are used as the coefficients in the logistic function.
% y is returned as vector or matrix the same size as the raw scores.

% Copyright 2021 The MathWorks, Inc.

arguments
    score (:,:) {mustBeA(score,["single","double"])}
    scoreMapping
end

if isstruct(scoreMapping)
    % Calibration using isotonic regression

    rawScore = scoreMapping.Raw;
    interpretedScore = scoreMapping.Calibrated;

    n = numel(score);

    % Find the index of the raw score in the mapping closest to the score provided.
    idx = zeros(n,1);
    for ii = 1:n
        [~,idx(ii)] = min(abs(score(ii)-rawScore));
    end

    % Get the calibrated score.
    y = interpretedScore(idx);

else

    % Calibration using logistic regression
    y = logistic(score,scoreMapping);

end
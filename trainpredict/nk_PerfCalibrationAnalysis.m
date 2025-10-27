function nk_PerfCalibrationAnalysis(ax, y_true, y_scores, numBins, smoothline, metric, titlestr)

% plotCalibrationCurve Plots the calibration curve for a binary classification model
%
% Inputs:
%   y_true - A vector of true binary labels (0 or 1)
%   y_scores - A vector of scores or probabilities from the model
if ~exist("smoothline","var") || isempty(smoothline)
    smoothline = false;
end

idxnan = isnan(y_scores);
y_scores(idxnan)=[];
y_true(idxnan)=[];

% Check if the scores are probabilities (bounded between 0 and 1)
if all(y_scores >= 0 & y_scores <= 1)
    y_probs = y_scores;
else
    % Convert scores to probabilities using sigmoid function for non-probabilistic models
    y_probs = probtransform(y_true, y_scores, [], 'platt');
end

% Number of bins for grouping predictions
if ~exist("numBins","var") || isempty(numBins)
   numBins = 10;
end

% Initialize bins
bins = linspace(0, 1, numBins+1);

% Initialize calibration curve values
meanPredictedValue = zeros(numBins, 1);
fractionOfPositives = zeros(numBins, 1);

% Compute calibration curve
for i = 1:numBins
    binIndices = y_probs >= bins(i) & y_probs < bins(i+1);
    binScores = y_probs(binIndices);
    binTrue = y_true(binIndices);

    meanPredictedValue(i) = mean(binScores);
    fractionOfPositives(i) = mean(binTrue);
end

% Remove NaN values
validIndices = ~isnan(meanPredictedValue) & ~isnan(fractionOfPositives);
meanPredictedValue = meanPredictedValue(validIndices);
fractionOfPositives = fractionOfPositives(validIndices);

% Check if there's enough data to interpolate
if length(meanPredictedValue) < 2
    error('Not enough data points to interpolate a smooth curve.');
end

% Compute ECE
switch metric
    case 'ECE'
        metricval = ECE(y_true, y_probs, numBins);
    case 'Brier Score'
        metricval = brierScore(y_true, y_probs);
end

hold(ax, 'on');
hECE = plot(ax, NaN, NaN, 'LineStyle', 'none'); % Invisible plot
legendTextECE = sprintf('%s: %.4f', metric, metricval);

if smoothline 
    % Interpolation for smoother curve
    finerGrid = linspace(0, 1, 100); % Finer grid for interpolation
   
    smoothFractionOfPositives = interp1(meanPredictedValue, fractionOfPositives, finerGrid, 'pchip');
    % Plotting the calibration curve
    hCalibrationCurve = plot(ax, finerGrid, smoothFractionOfPositives, '-', 'LineWidth',1.5, 'Color', 'b');
else
    hCalibrationCurve = plot(ax, meanPredictedValue, fractionOfPositives, '-o', 'LineWidth',1.5, 'Color', 'b');
end
hold on;
hReferenceLine = plot(ax,[0, 1], [0, 1], 'k--', 'LineWidth',0.5); % Perfect calibration reference line
legendEntries = [hCalibrationCurve, hReferenceLine, hECE];
legendTexts = {'Calibration Curve', 'Reference Line', legendTextECE};

% Add legend to the plot
legend(ax, legendEntries, legendTexts, 'Location', 'best');
ylim(ax,[0 1]);
xlim(ax,[0 1]);
box on;
xlabel('Mean predicted value');
ylabel('Fraction of positives');
if ~exist("titlestr","var") || isempty(titlestr)
    title('Calibration Analysis');
else
    title(titlestr, "Interpreter","none");
end

hold off;




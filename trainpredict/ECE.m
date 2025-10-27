function ece = ECE(labels, predictions, numBins)
    % ECE Computes the Expected Calibration Error of a binary classifier
    %   labels: True binary labels (0 or 1)
    %   predictions: Predicted probabilities corresponding to the labels
    %   numBins: Number of bins to use for calculating ECE

    % Check and adjust labels to be 0 or 1
    labels(labels ~= 1) = 0;

    % Ensure the number of bins is a positive integer
    if nargin < 3 || isempty(numBins)
        numBins = 10;
    end
    numBins = max(1, round(numBins));

    % Sort predictions and associated labels
    [sortedPredictions, sortIdx] = sort(predictions);
    sortedLabels = labels(sortIdx);

    % Determine the number of data points per bin
    N = numel(labels);
    dataPerBin = floor(N / numBins);
    extraData = mod(N, numBins);

    % Initialize variables
    binWeights = zeros(numBins, 1);
    absErrors = zeros(numBins, 1);

    startIndex = 1;
    % Calculate the absolute error for each bin
    for i = 1:numBins
        binSize = dataPerBin + (i <= extraData);
        endIndex = startIndex + binSize - 1;

        % Ensure endIndex does not exceed N
        endIndex = min(endIndex, N);

        binPredictions = sortedPredictions(startIndex:endIndex);
        binLabels = sortedLabels(startIndex:endIndex);

        observedMean = mean(binLabels);
        predictedMean = mean(binPredictions);
        absErrors(i) = abs(predictedMean - observedMean);
        binWeights(i) = binSize / N;

        startIndex = endIndex + 1;
    end

    % Compute the weighted sum of the absolute errors
    ece = sum(absErrors .* binWeights);
end
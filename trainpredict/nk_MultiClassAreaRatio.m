function [areaModel, areaRandom, ratio, confMatrixRandom] = nk_MultiClassAreaRatio(confMatrixModel)
    % nk_MultiClassAreaRatio:
    %   Compute the ratio of the "spider-area" of the model's misclassification polygon
    %   to that of a random baseline classifier. The random baseline is automatically
    %   computed (uniformly) within this function so that each row's sum matches the
    %   corresponding row sum in 'confMatrixModel'.
    %
    % Usage:
    %   [areaModel, areaRandom, ratio, confMatrixRandom] = nk_MultiClassAreaRatio(confMatrixModel)
    %
    % Returns:
    %   areaModel        : The spider-area for the model's confusion matrix
    %   areaRandom       : The spider-area for the random baseline
    %   ratio            : areaModel / areaRandom
    %   confMatrixRandom : The generated random baseline confusion matrix
    
    % 1. Build random confusion matrix that preserves row sums
    K = size(confMatrixModel, 1);   % number of classes
    rowSums = sum(confMatrixModel, 2);
    
    % We'll build a uniform random conf matrix that has the same row sums
    confMatrixRandom = zeros(K);
    for i = 1:K
        for j = 1:K
            % Each class j is predicted with probability 1/K (uniform),
            % so the row i total is split equally among columns.
            confMatrixRandom(i, j) = rowSums(i) * (1.0 / K);
        end
    end
    
    % 2. Compute misclassification probabilities (row-normalized off-diagonal)
    misclassProbsModel  = compute_misclassification_probabilities(confMatrixModel);
    misclassProbsRandom = compute_misclassification_probabilities(confMatrixRandom);
    
    % 3. Compute spider (radar) area for each
    areaModel  = spider_area(misclassProbsModel);
    areaRandom = spider_area(misclassProbsRandom);
    
    % 4. Compute ratio
    if areaRandom == 0
        ratio = Inf;  % or NaN, depending on preference
    else
        ratio = areaRandom / areaModel;
    end
end

function misclassProbs = compute_misclassification_probabilities(confMatrix)
    % compute_misclassification_probabilities 
    %   Given a KxK confusion matrix, returns a 1D array of length K(K-1)
    %   containing the misclassification probabilities, row by row,
    %   skipping the diagonal.
    %
    %   The order is (0->1, 0->2, ..., 0->K-1, 1->0, 1->2, ..., K-1->K-2).

    K = size(confMatrix, 1);
    misclassProbs = zeros(K*(K-1), 1);

    rowSums = sum(confMatrix, 2);
    idx = 1;
    for i = 1:K
        for j = 1:K
            if i ~= j
                if rowSums(i) > 0
                    prob = confMatrix(i, j) / rowSums(i);
                else
                    prob = 0.0;
                end
                misclassProbs(idx) = prob;
                idx = idx + 1;
            end
        end
    end
end

function areaVal = spider_area(misclassProbs)
    % spider_area Compute the area of the radar/spider polygon
    %   given misclassProbs as the radii on equally spaced angles.
    %
    % Usage:
    %   areaVal = spider_area(misclassProbs)
    %
    % The formula used:
    %   Area = 0.5 * sin(2*pi/N) * sum( r_n * r_(n+1) ) with r_(N+1) = r_1

    N = length(misclassProbs);

    % If fewer than 3 points, area is essentially zero or undefined
    if N < 3
        areaVal = 0.0;
        return
    end

    % Use circshift to get r_(n+1) for each r_n
    rNext = circshift(misclassProbs, -1);
    sumRnRn1 = sum(misclassProbs .* rNext);

    % 0.5 * sin(2*pi/N) * sum(r_n * r_(n+1))
    areaVal = 0.5 * sin(2.0 * pi / N) * sumRnRn1;
end

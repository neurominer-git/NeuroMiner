function [ratio, confMatrixRandom] = nk_MultiClassRatio2Random(confMatrixModel)
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
    
    ratio = (1-(sum(misclassProbsModel) / sum(misclassProbsRandom))) * 100;
    
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
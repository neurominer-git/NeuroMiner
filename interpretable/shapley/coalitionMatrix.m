function [Z, subsetWeights] = coalitionMatrix(M, numsubsets)
% The purpose of this function is to return an appropriately sized
% coalition matrix of trues and falses (0s and 1s).
%
% The performance of this function is NOT CRITICAL at all (99% of
% the time is spent in the expected value computation). Hence, the
% UseParallel flag has no implications for this helper.
%
% Z is a NumSubsets-by-M coalition matrix, where M is the
% actual number of DIMENSIONS in the problem numsubsets is the number of
% subsets to consider for this problem.
%
% The NumSubsets property can also be interpreted as the level of
% approximation. The solution for an exact Shapley value
% computation will require Z to be of size 2^M-by-M.

if numsubsets ==2  % numsubsets is always greater than 1 (already validated in fit())
    % there are two subsets with infinite weights, they will be added to Z before solving the least squares
    % return early for this case of a budget of only two coalitions
    Z = [];
    subsetWeights = [];
    warning('Shapley: Max no. of subsets is too small');
    return;
end

if M==2 % only two features, spell out Z
    switch numsubsets
        case 3
            Z = [true false];
            subsetWeights = 1/2;
        case 4
            Z = [true false
                false true];
            subsetWeights = [1/2; 1/2];
    end
else
    numsubsetsLargeEnough = false; % numsubsets is large enough to enumerate all subsets (2^M - 2 subsets)
    hasOddNumDimensions = mod(M,2)==1; % for odd number of features every single coalition has a complement e.g. (3choose0) + (3choose1) | (3choose2) + (3chose3)
    halfNumDimensions = floor(M/2); % symmetric problem
    featureSubsetSizes = uint64(1:halfNumDimensions)'; % a column of size halfNumDimensions
    binomialCoefficientsHalf= arrayfun(@(k)nchoosek(M,k), featureSubsetSizes); % a column of size halfNumDimensions
    INFINITY = intmax("uint64");
    cumulativeEnumerationsHalf = cumsum(binomialCoefficientsHalf); % same size as halfNumDimensions,
    % can contain overflown integers but that is ok, as long as the budget is reasonable, but if the specified budget also exceeds intmax, throw an error
    % COMMENT AW: budget not known! First expression evaluates false although,
    % f.e., cumulativeEnumerationsHalf(15) == INFINITY is true
    if any(cumulativeEnumerationsHalf) == INFINITY && budget > INFINITY
        error('Shapley: Infinite no. of subsets');
    end
    % ideally we want to enumerate all the subsets,
    totalSubsetsWhole = 2^M; % this is the total number of subsets
    if numsubsets >= totalSubsetsWhole  % if the numsubsets exceeds the total number of enumerations to solve this problem, we can obtain an exact solution
        numsubsetsLargeEnough = true;
    else % numsubsets is less than required for enumeration of all possible subsets
        if numsubsets == 2*M + 2 % the case when subsets of size 1 can be enumerated
            featureSubsetSizeExact = 1;
        elseif numsubsets > 2*M + 2 % the case when more subsets than just size 1 can be enumerated
            for ind = 1:halfNumDimensions
                if numsubsets < 2*cumulativeEnumerationsHalf(ind) + 2
                    featureSubsetSizeExact = featureSubsetSizes(ind-1); % number of pairs of subsets we can fully enumerate within the numsubsets
                    break;
                end
            end
        else % for numsubsets less than 2*M + 2, here not all subsets of size 1 can be enumerated
            numSubsetsMinus2 = numsubsets-2;
            Z = false(numSubsetsMinus2,M);
            subsetWeights = zeros(numSubsetsMinus2,1);
            if numSubsetsMinus2 <= M % numsubsets are in the range (2, M+2]
                Z(1:numSubsetsMinus2+1:numSubsetsMinus2*numSubsetsMinus2) = true;
                subsetWeights(1:numSubsetsMinus2) = 1/M;
            else % numsubsets in the range (M+2, 2M+2)
                Z(1:numSubsetsMinus2+1:end) = true;
                remainingSubsets = numSubsetsMinus2 - M;
                Z(M+1:M+remainingSubsets,:) = ~Z(1:remainingSubsets,:); % fill the remaining with as many complements as you can
                subsetWeights = (1/M)*(ones(numSubsetsMinus2,1));
            end
            warning('Shapley: Max no. of subsets too small');
            return;
        end
    end
    kernelWeightsHalf = zeros(halfNumDimensions,1);
    binomialCoefficientsHalf = double(binomialCoefficientsHalf); % cast to double for weight calculation
    for ind = 1:halfNumDimensions % here ind is |z| and allPossibleSubsetSizesHalf is values of (M choose |z|) computed apriori, essentially make a hashtable of kernel weights
        kernelWeightsHalf(ind)= (M-1)/(binomialCoefficientsHalf(ind)*ind*(M-ind)); % (M-1)/((M choose |z|)*(|z|)*(M-|z|), where is z is the subset, and |z| is the subset size
    end

    if numsubsetsLargeEnough % we can fully enumerate all the subsets if the numsubsets is large enough to accomodate the size
        exactSize = 2^M-2; % there two subsets which have all features included and none of the features included, handle them separately
        % coalition matrix, Z (exactSize-by-M)
        %
        % +----------------------------------------+
        % |        subsets of size 1               |
        % |                                        |
        % +----------------------------------------+
        % |        subsets of size 2               |
        % |                                        |
        % +----------------------------------------+
        % |                 .                      |
        % |                 .                      |
        % |       goes on exactSize/2 times        |
        % |                 .                      |
        % |                 .                      |
        % +----------------------------------------+
        % |        subsets of size M-1             |
        % |       (complements of above)           |
        % +----------------------------------------+
        % |         subsets of size M-2            |
        % |         (complements of above)         |
        % +----------------------------------------+
        % |                 .                      |
        % |                 .                      |
        % |       goes on exactSize/2 times        |
        % |                 .                      |
        % |                 .                      |
        % +----------------------------------------+
        Z = false(exactSize, M);
        subsetWeights = zeros(exactSize,1);
        % work on subsets of size 1 through ceil(M/2) (illustrated in the top half of the picture above)
        % the rest will be complements of what you populate

        % as written, every iteration of the following for-loop is independent i.e. we can obtain these enumerations for a given subset size independently
        % however, parfor has very restrictive indexing, so the following for-loop cannot be changed to "parfor" right away
        % a parallel approach to this problem needs to be thought out

        for featureSubsetSize = 1:halfNumDimensions
            hotIndices = nchoosek(1:M, featureSubsetSize); % hot indices are of size n-by-M where n = M-choose-featureSubsetSize
            rowSize = binomialCoefficientsHalf(featureSubsetSize);
            if featureSubsetSize ==1
                rowOffset = 0; % avoid zero indexing into cumulativeEnumerations
            else
                rowOffset = cumulativeEnumerationsHalf(featureSubsetSize-1); % totalPossibleEnumerations are the cumulative sum so far
            end

            kw = kernelWeightsHalf(featureSubsetSize);
            for row = 1:rowSize
                Z(row+rowOffset, hotIndices(row,:)) = true; % flip the false bits in this subset
                subsetWeights(row+rowOffset) = kw; % kernel weights are symmetric so fill all of them out
            end
        end
        % for the subsets of size M-1 through M-ceil(M/2), do not do any work except taking the complement (bottom half of the above picture)
        if hasOddNumDimensions % for odd number of dimensions every subset has its complement
            Z(exactSize/2+1:end,:) = ~Z(1:exactSize/2,:); % add the complements to Z
            subsetWeights(exactSize/2+1:end) = subsetWeights(1:exactSize/2); % the weights are the same
        else
            % for even number of dimensions, subsets of size ceil(M/2) do not have a complement
            % the interval of these asymmetric indices is as follows:
            rowEndSymmetryIdx = cumulativeEnumerationsHalf(end-1);
            rowBeginSymmetryAgainIdx = cumulativeEnumerationsHalf(end)+1;
            Z(rowBeginSymmetryAgainIdx:end,:) = ~Z(1:rowEndSymmetryIdx,:); % add the complements to Z
            subsetWeights(rowBeginSymmetryAgainIdx:end) = subsetWeights(1:rowEndSymmetryIdx); % add the complements to Z
        end

    else % do budgeted shap, remember that we can enumerate featureSubsetSizeExact fully but the rest can only be partially enumerated

        % Use a deterministic approach to make the coalition matrix, we know
        % that the highest weighted subsets are the most important, so try to
        % put as many highest weighted subsets in the coalition matrix as we
        % can. There is no random sampling going on here for this reason. The
        % highest weighted subsets contribute most to the shapley sum. The SHAP
        % package uses a combination of this deterministic approach and random
        % sampling for the last remaining subsets. It is just faster to not
        % randomly sample even for the last few remaining subsets.

        % coalition matrix, Z (numsubsets-by-M),
        %
        % +----------------------------------------+
        % |        subsets of size 1               |
        % |                                        |
        % +----------------------------------------+
        % |        subsets of size 2               |
        % |                                        |
        % +----------------------------------------+
        % |                 .                      |
        % |                 .                      |
        % | goes on featureSubsetSizeExact/2 times |
        % |                 .                      |
        % |                 .                      |
        % +----------------------------------------+
        % |--   full subset enumerations above   --|
        % +----------------------------------------+
        % |                                        |
        % |leftover numsubsets: partial enumeration|
        % |                                        |
        % |                                        |
        % +----------------------------------------+
        % |--       complements below            --|
        % +----------------------------------------+
        % |        subsets of size M-1             |
        % |       (complements of above)           |
        % +----------------------------------------+
        % |         subsets of size M-2            |
        % |         (complements of above)         |
        % +----------------------------------------+
        % |                 .                      |
        % |                 .                      |
        % | goes on featureSubsetSizeExact/2 times |
        % |                 .                      |
        % |                 .                      |
        % +----------------------------------------+
        numSubsetsMinus2 = numsubsets-2; % exclude the two trivial subsets (taking all features or taking none), will be added later by fitKernelSHAP
        Z = false(numSubsetsMinus2, M);
        subsetWeights = zeros(numSubsetsMinus2,1);

        for featureSubsetSize = 1:featureSubsetSizeExact
            hotIndices = nchoosek(1:M, featureSubsetSize); % hot indices are of size n-by-M where n = M-choose-featureSubsetSize
            rowSize = binomialCoefficientsHalf(featureSubsetSize);
            if featureSubsetSize ==1
                rowOffset = 0; % avoid zero indexing into cumulativeEnu
            else
                rowOffset = cumulativeEnumerationsHalf(featureSubsetSize-1); % totalPossibleEnumerations are the cumulative sum so far
            end
            kw = kernelWeightsHalf(featureSubsetSize);
            for row = 1:rowSize
                Z(row+rowOffset, hotIndices(row,:)) = true; % flip the false bits in this subset
                subsetWeights(row+rowOffset) = kw; % kernel weights are symmetric so fill all of them out
            end
        end

        % now do partial enumeration for the next subset in line that would have been fully enumerated if we had more numsubsets
        halfBudget = ceil(numSubsetsMinus2/2);
        rowEndSymmetryIdx = floor(numSubsetsMinus2/2); % take complements of subsets upto here
        rowBeginSymmetryAgainIdx = halfBudget+1; % populate complements starting at this index
        partialEnumerationBlock = row+rowOffset+1:halfBudget;
        hotIndices = shapley.partiallyEnumeratedSubsets(1:M,featureSubsetSizeExact+1,numel(partialEnumerationBlock)); % this is the subset next in line to enumerate

        for row = 1:numel(partialEnumerationBlock)
            Z(partialEnumerationBlock(row), hotIndices(row,:)) = true;
            subsetWeights(partialEnumerationBlock(row)) = kernelWeightsHalf(featureSubsetSizeExact+1);
        end

        Z(rowBeginSymmetryAgainIdx:end,:) = ~Z(1:rowEndSymmetryIdx,:); % add the complements to Z
        subsetWeights(rowBeginSymmetryAgainIdx:end) = subsetWeights(1:rowEndSymmetryIdx); % add the complements to Z
    end
end
end

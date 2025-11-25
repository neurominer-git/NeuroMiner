function [repairedData, distributions] = RemoveDisparateImpact(data, covars, subgroup, lambda, corrType, distributions)
%==========================================================================
% RemoveDisparateImpact - Function to repair data for mitigating disparate impact.
%
% Syntax: repairedData = RemoveDisparateImpact(data, covar, lambda, featuresToRepair)
%
% Inputs:
%   data - Original data matrix (m x k), where m are the rows for each
%   data point and k are the columns for each feature. 
%   covars - Matrix (m x covar) with categorical covariates indicating the sensitive attribute for each data point.
%   subgroup - Subgroup column (m x 1) of data points to estimate the distribution.
%   lambda - Strength of correction.
%   corrType - Correction type, 1 for median, 2 for mean. 
%   distributions - cell (1 x covar) storing training distributions of each
%   covariate group for each feature (bins x k x covar group) 
% Output:
%   repairedData - Repaired data matrix after mitigating disparate impact.
%   distributions - cell (1 x covar) storing training distributions of each
%   covariate group for each feature (bins x k x covar group)
%==========================================================================
% Derived from previous implementations of AI Fairness 360
% (https://aif360.res.ibm.com/) and the original publication:
%   "Certifying and removing disparate impact", 
%   M. Feldman, S. A. Friedler, J. Moeller, C. Scheidegger, and S. Venkatasubramanian(2015)
% Sergio Mena Ortega, 2023

%Calculate number of covariates.
numCovars = size(covars, 2);

%Check if training distributions are not given and initialise them.
if nargin < 6
    train_flag = 1;
    distributions = cell(1, numCovars);
else
    train_flag = 0;
end

%Repeat DIR for each covariate. 
for covarIdx = 1:numCovars

    %Extract relevant covariate. 
    covar = covars(:, covarIdx);

    % Find unique groups in the sensitive attribute.
    uniqueGroups = unique(covar);

    % Check if the number of unique groups exceeds 10
    if numel(uniqueGroups) > 10
        warning('RemoveDisparateImpact:PossibleContinuousCovariate', ...
            'DIR works with discrete covariates only. Covariate number %d appears to have more than 10 unique groups. Remove continuous covariates.', covarIdx);
    end

    % Initialise repaired data matrix if first covar.
    if covarIdx == 1; repairedData = data; end
    
    % Calculating number of groups.
    numGroups = numel(uniqueGroups);

    % Calculating the number of features in the dataset.
    numFeatures = size(repairedData, 2);
    
    % Obtaining the original distribution for each group across all features.
    if train_flag == 1
        % Calculate number of samples for each group.
        groupCounts = arrayfun(@(x) sum(covar(subgroup == 1) == x), uniqueGroups); 
        % Check if any group count is zero
        if any(groupCounts == 0)
            error('One or more covariate groups have a count of zero. Disparate impact remover only supports categorical covariates.');
        end
        % Calculating the number of quantiles, maximum of 100.
        numQuantiles = min(min(groupCounts), 100);

        %Obtain distributions for each group in covar.
        for g = 1:numGroups
            logicalGroup = (covar == uniqueGroups(g)) & subgroup;
            oDist(:,:,g) = quantile(repairedData(logicalGroup, :), numQuantiles, 1);
        end
        
        % ===== NEW: compute global distribution using all training samples =====
        allSamples = repairedData(subgroup==1, :);  % combine all training samples
        globalMeanDist = quantile(allSamples, numQuantiles, 1);  % quantiles across all samples
        
        % Store training distributions AND their corresponding group labels
        distributions{covarIdx} = struct( ...
            'uniqueGroups', uniqueGroups, ...
            'oDist', oDist, ...
            'groupCounts', groupCounts, ...
            'globalMeanDist', globalMeanDist ...
        );

        % Assign the unique groups to the training groups. 
        trainGroups = uniqueGroups;

    else
        % ===== TESTING MODE =====
        %Load it for testing correction.
        distStruct = distributions{covarIdx};
        trainGroups = distStruct.uniqueGroups;
        oDist = distStruct.oDist;

        % Load global mean distribution from training
        globalMeanDist = distStruct.globalMeanDist;

    end
    
    % Calculate the correction distribution based on the specified type.
    if corrType == 1
        mDist = median(oDist, 3, 'omitnan');
    elseif corrType == 2
        mDist = mean(oDist, 3, 'omitnan');
    end


    % Perform the correction for each feature.
    for featureIdx = 1:numFeatures
        % Extract feature.
        x = repairedData(:, featureIdx);
        isNotNaN = ~isnan(x);

        % For each covariate group and feature selected, apply the correction. 
        for g = 1:numGroups
            groupLabel = uniqueGroups(g);
            % Find index of this group in training distributions
            trainGroupIdx = find(trainGroups == groupLabel, 1);

            % If this group wasn't seen in training, use training-only global fallback
            if isempty(trainGroupIdx)
                % Use global mean (prevalence-weighted) edges
                edges = globalMeanDist(:, featureIdx);
            else
                % Get edges of histogram distribution.
                edges = oDist(:, featureIdx, trainGroupIdx);
            end

            % Get indexes in x that belong to group.
            isGroupK = covar == groupLabel;

            % Extract x of the group.
            xGroupK = x(isGroupK);
            isNotNaNK = isNotNaN(isGroupK);

            % Get the indices (bin) for each value for the correction. 
            indices = discretize(xGroupK, [-inf; edges; inf]);

            % Matlab convention: select the values on the left.
            indices(indices ~= 1) = indices(indices ~= 1) - 1;

            % Clamp indices to valid range
            indices(indices < 1) = 1;
            indices(indices > size(mDist,1)) = size(mDist,1);

            %Perform the repair with a level of lambda.
            repairedData(isGroupK & isNotNaN, featureIdx) = ...
                (1 - lambda) * xGroupK(isNotNaNK) + ...
                lambda * mDist(indices(isNotNaNK), featureIdx);
        end
    end

end

end
%========================================================================
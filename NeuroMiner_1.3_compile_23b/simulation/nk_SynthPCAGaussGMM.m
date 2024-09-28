function [data, labels, covars] = nk_SynthPCAGaussGMM(realData, realLabels, realCovars, IN, method)
global VERBOSE

if ~exist("IN","var") || isempty(IN)
    numSyntheticObservations = 100;
else
    numSyntheticObservations = IN.numSyntheticObservations;
end

if ~exist("method","var") || isempty(method), method = 'pcagauss'; end

fprintf('\nNo. of requested synthetic observations: %g', numSyntheticObservations);

dRealData = size(realData,2);
if ~isempty(realCovars)
    dRealCovars = size(realCovars,2);
    realData= [realData realCovars realLabels];
    uXC = nk_CountUniques(realCovars);
else
    realData = [realData realLabels];
    dRealCovars = 0;
end

uXL = nk_CountUniques(realLabels);

% Check whether there are NaNs in the data and impute them
if sum(isnan(realData(:)))
    fprintf('\nImputing missing values in data');
    IN_impute.k = 5;
    IN_impute.method = 'SeqkNN'; 
    IN_impute.X = realData;
    realData = nk_PerfImputeObj(realData, IN_impute);
end

switch method
    
    case 'pcagauss'
        fprintf('| Generating synthetic data using Gaussian random interpolation');
        % Perform principal component analysis on the combined data
        IN.DR.DRsoft = 1; 
        IN.DR.RedMode = 'PCA';
        IN.DR.PercMode = 3; 
        [score, model] = nk_PerfRedObj(realData, IN);
        
        % Generate synthetic data and labels by sampling random values from a Gaussian distribution
        mu = mean(score, 1);
        sigma = std(score, 1);
        syntheticDataCovarsLabels = random('Normal', repmat(mu, numSyntheticObservations, 1), repmat(sigma, numSyntheticObservations, 1));
        
        % Project the synthetic data onto the principal components of the combined data
        tsyntheticDataCovarsLabels = syntheticDataCovarsLabels * model.mpp.vec' + model.mpp.sampleMean;
        syntheticDataCovarsLabels = zeros(numSyntheticObservations,numel(model.indNonRem));
        syntheticDataCovarsLabels(:,model.indNonRem) = tsyntheticDataCovarsLabels ;
        clear tsyntheticDataCovarsLabels
    
    case 'gmm'
        fprintf('| Generating synthetic data using Gaussian Mixture Modelling');
        % Import Python libraries
        py.importlib.import_module('numpy');
        py.importlib.import_module('sklearn.mixture');

        % Convert MATLAB data to Python-compatible format
        realData_py = py.numpy.array(realData);
        ncomp = numel(IN.n_components);
        min_values = zeros(1,ncomp);
        random_state_py = py.int(42);
        % Loop through the number of components for GMM
        for i=1:ncomp
            % Fit Gaussian Mixture Model using Python's scikit-learn
            n_components_py = py.int(IN.n_components(i));
            gmm = py.sklearn.mixture.GaussianMixture( n_components_py , pyargs('random_state', random_state_py));
            dimred = false;
            try % ... in the original space
                gmm.fit(realData_py);
                % Store BIC or AIC values
                switch IN.minMethod
                    case 1
                        min_values(i) = gmm.bic(realData_py);  % Get BIC value
                    case 2
                        min_values(i) = gmm.aic(realData_py);  % Get AIC value
                end
            catch % if that does not work perform dimensionality reduction using PCA
                dimred = true;
                if ~exist("score","var")
                    fprintf('| reducing dimensionality to ')
                    % Perform principal component analysis on the combined data
                    IN.DR = struct('DRsoft', 1, 'RedMode', 'PCA', 'PercMode', 3);
                    [score, model] = nk_PerfRedObj(realData, IN);
                    fprintf('%g eigenvariates because original data GMM does not fit into the memory', width(score));
                end
                reducedData_py = py.numpy.array(score);
                gmm.fit(reducedData_py);
                % Store BIC or AIC values
                switch IN.minMethod
                    case 1
                        min_values(i) = gmm.bic(reducedData_py);  % Get BIC value
                    case 2
                        min_values(i) = gmm.aic(reducedData_py);  % Get AIC value
                end
            end
        end

        % Find minimum BIC 
        [~,opt_ncomp_ind] = min(min_values);
        
        opt_ncomp = py.int(IN.n_components(opt_ncomp_ind));
        if VERBOSE, fprintf('| optimal GMM fitting with %g components', opt_ncomp); end

        % Fit Gaussian Mixture Model with the optimal number of components
        gmm = py.sklearn.mixture.GaussianMixture(opt_ncomp, pyargs('random_state', random_state_py));
        if dimred
            gmm.fit(reducedData_py);
        else
            gmm.fit(realData_py);
        end

        % Generate synthetic data from the GMM
        synthetic_data_py = gmm.sample(numSyntheticObservations); % Generate synthetic samples
        syntheticDataCovarsLabels = double(synthetic_data_py{1}); % Convert the output to a MATLAB array

        if dimred
            tsyntheticDataCovarsLabels = syntheticDataCovarsLabels * model.mpp.vec' + model.mpp.sampleMean;
            syntheticDataCovarsLabels = zeros(numSyntheticObservations,numel(model.indNonRem));
            syntheticDataCovarsLabels(:,model.indNonRem) = tsyntheticDataCovarsLabels ;
            clear tsyntheticDataCovarsLabels
        end
end

% Extract synthetic data
syntheticData = syntheticDataCovarsLabels(:,1:dRealData);

% Extract covariates
if ~isempty(realCovars)
    syntheticCovars = syntheticDataCovarsLabels(:,dRealData+1:dRealData+dRealCovars);
    rIdx = find(uXC.U<10); % is this a check whether it is ca
    if ~isempty(rIdx)
        for i=1:numel(rIdx)
            if size(uXC.UX{rIdx(i)},1) == 1
                syntheticCovars(:,rIdx(i)) = repelem(uXC.UX{rIdx(i)}, numSyntheticObservations);
            else
                syntheticCovars(:,rIdx(i)) = interp1(uXC.UX{rIdx(i)},uXC.UX{rIdx(i)},syntheticCovars(:,rIdx(i)),'nearest','extrap');
            end
        end
    end
end

% Extract the synthetic labels
syntheticLabels = syntheticDataCovarsLabels(:, dRealData+dRealCovars+1:end);
rIdx = find(uXL.U<10);
if ~isempty(rIdx)
    for i=1:numel(rIdx)
        syntheticLabels(:,rIdx(i)) = interp1(uXL.UX{rIdx(i)},uXL.UX{rIdx(i)},syntheticLabels(:,rIdx(i)),'nearest','extrap');
    end
end
fprintf(' Done!')
% Combine the real and synthetic data and labels
data = syntheticData;
labels = syntheticLabels;
if ~isempty(realCovars)
    covars = syntheticCovars;
else 
    covars = [];
end

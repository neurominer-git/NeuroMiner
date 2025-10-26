function [data, labels, covars] = nk_SynthPCAGauss(realData, realLabels, realCovars, IN)

if ~exist("IN","var") || isempty(IN)
    numSyntheticObservations = 100;
    method = 'pcagauss';
else
    numSyntheticObservations = IN.numSyntheticObservations;
    method = IN.method;
end

fprintf('\nGenerating synthetic data using Gaussian random interpolation:');
fprintf(' No. of synthetic observations: %g', numSyntheticObservations);

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

        % Import Python libraries
        py.importlib.import_module('numpy');
        py.importlib.import_module('sklearn.mixture');

        % Convert MATLAB data to Python-compatible format
        realData_py = py.numpy.array(realData);
        ncomp = numel(IN.n_components);
        bic_values = zeros(1,ncomp);
        aic_values = zeros(1,ncomp);
        
        % Loop through the number of components for GMM
        for i=1:ncomp
            % Fit Gaussian Mixture Model using Python's scikit-learn
            gmm = py.sklearn.mixture.GaussianMixture(IN.n_components(i), pyargs('random_state', 42));
            gmm.fit(realData_py);
            % Store BIC and AIC values
            bic_values(i) = gmm.bic(realData_py);  % Get BIC value
            aic_values(i) = gmm.aic(realData_py);  % Get AIC value
        end
        
        opt_ncomp = min(bic_values);
        
        % Fit Gaussian Mixture Model with the optimal number of components using Python's scikit-learn
        gmm = py.sklearn.mixture.GaussianMixture(opt_ncomp, pyargs('random_state', 42));

        % Generate synthetic data from the GMM
        synthetic_data_py = gmm.sample(numSyntheticObservations); % Generate 500 samples
        syntheticDataCovarsLabels = double(synthetic_data_py{1}); % Convert the output to a MATLAB array

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

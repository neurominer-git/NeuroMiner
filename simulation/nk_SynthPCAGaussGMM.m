function [data, labels, covars] = nk_SynthPCAGaussGMM(realData, realLabels, realCovars, IN, method)
global VERBOSE

% --- Python imports cached per MATLAB session ---
persistent np_mod sklearn_mixture_mod GaussianMixtureClass
if isempty(np_mod) || isempty(sklearn_mixture_mod) || isempty(GaussianMixtureClass)
    % Import Python libraries once
    np_mod              = py.importlib.import_module('numpy');
    sklearn_mixture_mod = py.importlib.import_module('sklearn.mixture');
    GaussianMixtureClass = sklearn_mixture_mod.GaussianMixture;
end

numSyntheticObservations = IN.numSyntheticObservations;

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

        % All candidates must be scored in one feature space.
        % Refit the entire sweep in PCA space only if the original-space fit fails.
        dimred = size(realData,2) >= size(realData,1);
        if dimred
            IN.DR = struct('DRsoft',1,'RedMode','PCA','PercMode',3);
            [score, model] = nk_PerfRedObj(realData, IN);
            fitData = py.numpy.array(score);
        else
            fitData = py.numpy.array(realData);
        end
        ncomp = numel(IN.n_components);
        min_values = zeros(1,ncomp);
        % Controlled by MATLAB's current stream; identical MATLAB seeds repeat.
        random_state_py = py.int(randi(intmax('int32')));
        for fitSpace = 1:2
            completeSweep = true;
            for i = 1:ncomp
                gmm = GaussianMixtureClass(py.int(IN.n_components(i)), ...
                    pyargs('random_state',random_state_py));
                try
                    gmm.fit(fitData);
                catch ME
                    if fitSpace == 2 || dimred, rethrow(ME); end
                    completeSweep = false;
                    break;
                end
                switch IN.minMethod
                    case 1
                        min_values(i) = double(gmm.bic(fitData));
                    case 2
                        min_values(i) = double(gmm.aic(fitData));
                end
            end
            if completeSweep, break; end
            IN.DR = struct('DRsoft',1,'RedMode','PCA','PercMode',3);
            [score, model] = nk_PerfRedObj(realData, IN);
            fitData = py.numpy.array(score);
            dimred = true;
        end

        [~,opt_ncomp_ind] = min(min_values);
        opt_ncomp = py.int(IN.n_components(opt_ncomp_ind));
        if VERBOSE, fprintf('| optimal GMM fitting with %g components', IN.n_components(opt_ncomp_ind)); end
        gmm = GaussianMixtureClass(opt_ncomp, pyargs('random_state',random_state_py));
        gmm.fit(fitData);

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

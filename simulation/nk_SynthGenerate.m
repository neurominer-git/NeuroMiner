function [data, labels, covars, activated, selected] = nk_SynthGenerate(realData, realLabels, realCovars, SYNTH, modeflag, selected)
% Generate SYNTH observations from a training-only population realization.
% At positive uncertainty, resample paired predictor/label/covariate rows.
% The caller can reuse selected row indices for aligned modality shelves.
% At zero uncertainty, preserve the accepted generator and RNG behavior.
if SYNTH.uncertaintyScale > 0
    if isempty(selected)
        switch modeflag
            case 'classification'
                % Keep each training class count fixed while varying its
                % empirical feature/covariate distribution.
                [~,~,group] = unique(realLabels,'rows');
            case 'regression'
                % Resample continuous outcomes together with their predictors.
                group = ones(size(realData,1),1);
            otherwise
                error('nk_SynthGenerate:modeflag', 'Unsupported learning mode: %s', modeflag);
        end

        selected = (1:size(realData,1))';
        for g = 1:max(group)
            rows = find(group == g);
            n = numel(rows);
            % At scale 1, exponential weights normalized to sum 1 form a
            % Bayesian-bootstrap Dirichlet(1,...,1) empirical population.
            % Scale 0 is the original empirical distribution; other positive
            % scales are controlled sensitivity departures from that posterior.
            logWeights = SYNTH.uncertaintyScale * log(-log(rand(n,1)));
            weights = exp(logWeights - max(logWeights));
            cumulative = cumsum(weights) / sum(weights);

            % Linear-time systematic sampling with replacement.
            % Keep the original class row positions for aligned shelves.
            positions = ((0:n-1)' + rand) / n;
            source = 1;
            for j = 1:n
                while cumulative(source) < positions(j)
                    source = source + 1;
                end
                selected(rows(j)) = rows(source);
            end
        end
    end
    % Reuse selected indices across aligned shelves; never redraw weights.
    realData = realData(selected,:);
    realLabels = realLabels(selected,:);
    if ~isempty(realCovars)
        realCovars = realCovars(selected,:);
    end
end

switch SYNTH.method
    case 1
        [data, labels, covars] = nk_SynthDistkNN(realData, realLabels, realCovars, SYNTH);
        activated = true;
    case 2
        [data, labels, covars, activated] = nk_PerfADASYN(realData, realLabels, realCovars, SYNTH, true);
    case 3
        [data, labels, covars] = nk_SynthPCAGaussGMM(realData, realLabels, realCovars, SYNTH, 'pcagauss');
        activated = true;
    case 4
        [data, labels, covars] = nk_SynthPCAGaussGMM(realData, realLabels, realCovars, SYNTH, 'gmm');
        activated = true;
    case 5
        [data, labels, covars] = nk_SynthGaussCopula(realData, realLabels, realCovars, SYNTH, modeflag);
        activated = true;
end
end

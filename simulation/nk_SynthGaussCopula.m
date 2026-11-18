function [data, labels, covars] = nk_SynthGaussCopula(realData, realLabels, realCovars, SYNTH, modeflag)
% nk_SynthGaussCopula  Gaussian-copula SYNTH generator for wide data.
%
% [data, labels, covars] = nk_SynthGaussCopula(realData, realLabels, ...
%     realCovars, SYNTH, modeflag)
% draws SYNTH.numSyntheticObservations synthetic subjects whose predictors,
% outcome and covariates are generated jointly from the calibration rows
% supplied by nk_SynthGenerate.
%
% Model
%   Marginals   Empirical quantile function of every column within each
%               class (classification) or over all rows (regression),
%               interpolated between order statistics. Columns with fewer
%               than 10 unique values return observed values only, the rule
%               nk_SynthPCAGaussGMM applies to covariates and outcomes.
%   Dependence  Pooled within-class correlation of mid-rank normal scores,
%               reproduced exactly by sampling z = Z'*w with w ~ N(0, I/n),
%               so no p-by-p matrix is formed. No shrinkage is applied:
%               shrinkage towards the identity attenuates outcome-predictor
%               dependence in regression.
%   Outcome     Classification: the requested number is allocated to the
%               classes by largest remainder at the calibration prevalence,
%               and each row takes its class's marginals. Regression: the
%               outcome is one more copula column.
%   Covariates  Further copula columns, drawn jointly with the predictors.
%
% Missing values are imputed with the SeqkNN settings of nk_SynthPCAGaussGMM.
% Rows are returned in random order, so callers that assign perturbations by
% row blocks do not align them with classes. All draws use the global random
% stream. Memory: about three copies of the calibration matrix plus output.

N = SYNTH.numSyntheticObservations;
p = size(realData,2);
nCov = size(realCovars,2);
assert(all(isfinite(realLabels)), 'nk_SynthGaussCopula:outcome', ...
    'Calibration outcomes must be finite.');
D = [realData realCovars];
switch modeflag
    case 'classification'
        [classes,~,group] = unique(realLabels);
    case 'regression'
        D = [D realLabels];
        group = ones(size(realLabels));
    otherwise
        error('nk_SynthGaussCopula:mode', 'Unsupported SYNTH mode ''%s''.', modeflag);
end
regression = strcmp(modeflag,'regression');
% NM calibration predictors and covariates may contain missing values.
if any(isnan(D(:)))
    D = nk_PerfImputeObj(D, struct('k',5, 'method','SeqkNN', 'X',D));
end
[n,q] = size(D);
discrete = 1 + sum(diff(sort(D,1),1,1) ~= 0, 1) < 10;

nGroup = max(group);
count = accumarray(group(:),1)';
assert(all(count >= 2), 'nk_SynthGaussCopula:groupSize', ...
    'Every class needs at least two calibration subjects.');
quota = N*count/n;
alloc = floor(quota);
[~,order] = sort(quota-alloc, 'descend');
extra = order(1:N-sum(alloc));
alloc(extra) = alloc(extra)+1;

% Mid-rank normal scores per group, standardized and pooled.
Z = zeros(n,q);
sortedGroup = cell(1,nGroup);
for g = 1:nGroup
    rows = find(group == g);
    nc = count(g);
    [S, idx] = sort(D(rows,:),1);
    pos = (1:nc)';
    step = diff(S,1,1) ~= 0;
    first = cummax([true(1,q); step] .* pos, 1);
    runEnd = [step; true(1,q)];
    last = flipud(cummin(flipud(runEnd .* pos + ~runEnd * nc), 1));
    zg = zeros(nc,q);
    zg(idx + (0:q-1)*nc) = norminv((first+last)/2/(nc+1));
    sd = std(zg,1,1);
    sd(sd == 0) = 1;   % constant columns (e.g. masked voxels) carry no dependence
    Z(rows,:) = (zg - mean(zg,1)) ./ sd;
    sortedGroup{g} = S;
end
clear D S idx pos step first runEnd last zg

data = zeros(N,p);
labels = zeros(N,1);
synCov = zeros(N,nCov);
chunk = 256;
row = 0;
for g = 1:nGroup
    S = sortedGroup{g};
    nc = count(g);
    offset = (0:q-1)*nc;
    for done = 0:chunk:alloc(g)-1
        m = min(chunk, alloc(g)-done);
        z = (randn(m,n)/sqrt(n))*Z;
        t = normcdf(z)*(nc-1);
        lo = floor(t);
        f = t-lo;
        hi = min(lo+1, nc-1);
        V = S(lo+1+offset).*(1-f) + S(hi+1+offset).*f;
        V(:,discrete) = S(round(t(:,discrete))+1+offset(discrete));
        out = row+(1:m);
        data(out,:) = V(:,1:p);
        synCov(out,:) = V(:,p+(1:nCov));
        if regression
            labels(out) = V(:,q);
        else
            labels(out) = classes(g);
        end
        row = row+m;
    end
end
order = randperm(N);
data = data(order,:);
labels = labels(order);
covars = synCov(order,:);
fprintf('\nGaussian copula SYNTH: %d observations, %d group(s)', N, nGroup);
end

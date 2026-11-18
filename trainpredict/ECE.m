function [ece, meanPredicted, fractionPositive, binCount] = ECE(labels, probabilities, numBins)
% ECE  Probability-based binary expected calibration error (equal-width bins).
% Labels are 0/1 or -1/+1; probability estimates refer to the positive class.
% Bin edges include p=0 in bin 1 and p=1 in the final bin.
% nm2-allow: nk_DefineEvalFunc installs ECE as two-argument EVALFUNC; use ten bins when the optional third input is omitted.
if nargin < 3 || isempty(numBins), numBins = 10; end
numBins = max(1,round(numBins));
y = double(labels(:)); p = double(probabilities(:));
assert(numel(y) == numel(p),'ECE: labels/probabilities must have the same number of cases.');
valid = isfinite(y) & isfinite(p);
y = y(valid); p = p(valid);
if any(p < 0 | p > 1)
    error('ECE:ProbabilitiesRequired', ...
        'ECE requires predicted positive-class probabilities in [0,1], not decision scores.');
end
meanPredicted = nan(numBins,1);
fractionPositive = nan(numBins,1);
binCount = zeros(numBins,1);
ece = NaN;
if isempty(y) || numel(unique(y)) < 2, return; end
y = double(y == 1);
bins = linspace(0,1,numBins+1);
ece = 0;
for b = 1:numBins
    if b == numBins
        inBin = p >= bins(b) & p <= bins(b+1);
    else
        inBin = p >= bins(b) & p < bins(b+1);
    end
    binCount(b) = sum(inBin);
    if binCount(b) > 0
        meanPredicted(b) = mean(p(inBin));
        fractionPositive(b) = mean(y(inBin));
        ece = ece + binCount(b)/numel(p)*abs(fractionPositive(b)-meanPredicted(b));
    end
end
end

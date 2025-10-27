function [presPct, adjPct, zScore, entryIdx, expHits, varHits] = display_presence_metrics(corrRefMat)
% corrRefMat: [nComp × T], finite when matched, NaN otherwise

presPct  = []; adjPct = []; zScore = []; entryIdx = []; expHits = []; varHits = [];
if isempty(corrRefMat), return; end

[nComp, T] = size(corrRefMat);
H = isfinite(corrRefMat);

% entry indices per component
entryIdx = nan(nComp,1);
for i=1:nComp
    j = find(H(i,:), 1, 'first');
    if ~isempty(j), entryIdx(i) = j; end
end

% fold propensity p_t among components eligible at each t
p = nan(1,T);
for t = 1:T
    elig = ~isnan(entryIdx) & entryIdx <= t;
    if any(elig)
        p(t) = mean(H(elig,t));
    end
end

presPct  = zeros(nComp,1);
adjPct   = nan(nComp,1);
zScore   = nan(nComp,1);
expHits  = nan(nComp,1);
varHits  = nan(nComp,1);

for i=1:nComp
    e = entryIdx(i);
    if isnan(e), continue; end
    rng = e:T;
    K   = sum(H(i, rng));
    denom = numel(rng);
    presPct(i) = 100 * K / max(1,denom);

    Ei = nm_nansum(p(rng));
    Vi = nm_nansum(p(rng) .* (1 - p(rng)));
    expHits(i) = Ei;
    varHits(i) = Vi;

    adjPct(i) = 100 * (K / max(Ei, eps));
    if Vi > 0
        zScore(i) = (K - Ei) / sqrt(Vi);
    end
end
end

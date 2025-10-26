function [timesExpected, excessPct, zScore] = display_presence_ratio(corrRefMat)
% corrRefMat: [nComp×T], finite when the ref was matched at fold t
[nComp,T] = size(corrRefMat);
H = isfinite(corrRefMat);

% entry time per ref
e = nan(nComp,1);
for i=1:nComp
    j = find(H(i,:),1,'first');
    if ~isempty(j), e(i)=j; end
end

% fold propensity among eligible refs
p = nan(1,T);
for t=1:T
    elig = ~isnan(e) & e<=t;
    if any(elig), p(t) = mean(H(elig,t)); end
end

timesExpected = nan(nComp,1);
excessPct     = nan(nComp,1);
zScore        = nan(nComp,1);

for i=1:nComp
    if isnan(e(i)), continue; end
    rng = e(i):T;
    K   = sum(H(i,rng));          % observed hits
    N   = numel(rng);             % exposures since entry
    E   = nm_nansum(p(rng));         % expected hits
    V   = nm_nansum(p(rng).*(1-p(rng)));

    timesExpected(i) = K / max(E, eps);           % can be >1 (i.e., >100%)
    excessPct(i)     = 100 * (K - E) / max(1,N);  % bounded in [-100,100]
    if V>0, zScore(i) = (K - E)/sqrt(V); end
end
end

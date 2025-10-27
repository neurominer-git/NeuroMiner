function selPct = display_presence_pct_since_entry(corrRefMat)
% corrRefMat: [nComp × nModels] finite where matched, NaN otherwise
if isempty(corrRefMat), selPct = []; return; end
[nComp, nCols] = size(corrRefMat);
isHit = isfinite(corrRefMat);
selPct = nan(nComp,1);
for i = 1:nComp
    e = find(isHit(i,:), 1, 'first');       % entry column
    if isempty(e)
        selPct(i) = 0;                       % or NaN if you prefer
    else
        denom = nCols - e + 1;
        numer = sum(isHit(i, e:end));
        selPct(i) = 100 * numer / max(1,denom);
    end
end
end
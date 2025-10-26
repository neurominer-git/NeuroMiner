function ED = nk_LobagMulti_from_labels(P, L)
[N,n] = size(P);
if N==0 || n==0, ED = NaN; return; end
g = mode(P,2);
bias = (g ~= L);
classes = unique(L(~isnan(L)));
K = numel(classes);
if K < 2, ED = 0; return; end
vb_acc = []; vu_acc = [];
for k = 1:K
    ck = classes(k);
    Ek = 2*(P == ck) - 1;
    if any(bias)
        vb_k = var(Ek(bias,:), 0, 2);
        if ~isempty(vb_k), vb_acc = [vb_acc; vb_k]; end
    end
    if any(~bias)
        vu_k = var(Ek(~bias,:), 0, 2);
        if ~isempty(vu_k), vu_acc = [vu_acc; vu_k]; end
    end
end
vb = mean(vb_acc, 'omitnan');  if isempty(vb) || isnan(vb), vb = 0; end
vu = mean(vu_acc, 'omitnan');  if isempty(vu) || isnan(vu), vu = 0; end
ED = mean(bias) + vu - vb;
end
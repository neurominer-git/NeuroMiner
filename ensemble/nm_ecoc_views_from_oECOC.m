function out = nm_ecoc_views_from_oECOC(Cbin, L, oECOC, mode)
% Build ECOC "views": per-column class labels, correctness, relevance.
[N,n] = size(Cbin);
K = size(oECOC,1);
out.K = K;
P_label = zeros(N,n,'like',L);
Ccorr   = nan(N,n);
RelMask = false(N,n);
if strcmpi(mode,'ovo')
    for j = 1:n
        col = oECOC(:,j);
        a = find(col== 1,1,'first');
        b = find(col==-1,1,'first');
        if isempty(a) || isempty(b), continue; end
        P_label(:,j) = a*(Cbin(:,j)== 1) + b*(Cbin(:,j)==-1);
        rel = (L==a) | (L==b);
        RelMask(rel,j) = true;
        Ccorr(rel,j) = (L(rel)==a & Cbin(rel,j)== 1) | ...
                       (L(rel)==b & Cbin(rel,j)==-1);
    end
else % 'ovr'
    for j = 1:n
        k = find(oECOC(:,j)==1,1,'first');
        if isempty(k), continue; end
        P_label(:,j) = k*(Cbin(:,j)== 1) + L.*(Cbin(:,j)==-1);
        RelMask(:,j) = true;
        Ccorr(:,j)   = ( (L==k) & Cbin(:,j)== 1 ) | ( (L~=k) & Cbin(:,j)==-1 );
    end
end
out.P_label = P_label;
out.Ccorr   = Ccorr;
out.RelMask = RelMask;
end

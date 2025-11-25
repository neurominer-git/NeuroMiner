function S = similarity_kernel(A, B, metric, unitnorm)

if nargin<4, unitnorm = false; end

% Per-modality similarity between columns of A (ref) and B (current): [R x S]
if isempty(A) || isempty(B)
    S = zeros(size(A,2), size(B,2));
    return
end

if unitnorm, [A, B] = unit_normalize(A, B); end

switch metric
    case 'euclidean'
        % NaN-aware Euclidean similarity on the unit sphere:
        % For each column pair (a,b), use only jointly-finite entries,
        % renormalize on that overlap, compute:
        %   cos = <a,b> / (||a||*||b||)   (overlap-only)
        %   D   = sqrt( max(0, 2 - 2*cos) )
        %   S   = 1 - D/2
        % Binary masks of finites
        Ma = isfinite(A);                 % [Fa x nA]
        Mb = isfinite(B);                 % [Fb x nB]; Fb==Fa

        % Zero-out non-finites for dot products
        A0 = A; A0(~Ma) = 0;
        B0 = B; B0(~Mb) = 0;

        % Overlap counts per column pair
        M = double(Ma)' * double(Mb);     % [nA x nB]

        % Dot products over overlap
        num = A0' * B0;                   % [nA x nB]

        % Squared norms over overlap (sum a_i^2 where both finite; same for b)
        NA2 = (A0.^2)' * double(Mb);      % [nA x nB]
        NB2 = double(Ma)' * (B0.^2);      % [nA x nB]

        % Valid pairs: enough overlap and non-zero norms
        valid = (M > 1) & (NA2 > eps) & (NB2 > eps);

        % Cosine on overlap, clamped to [-1, 1]
        cosTheta = nan(size(num), 'like', num);
        cosTheta(valid) = num(valid) ./ sqrt(NA2(valid) .* NB2(valid));
        cosTheta(valid) = max(-1, min(1, cosTheta(valid)));

        % Euclidean distance between unit-normalized overlap vectors
        D = nan(size(num), 'like', num);
        D(valid) = sqrt(max(0, 2 - 2 * cosTheta(valid)));

        % Your similarity scale
        S = nan(size(num), 'like', num);
        S(valid) = 1 - D(valid) / 2;

    case 'pearson'
        mx = mean(A,'omitnan'); my = mean(B,'omitnan');
        Ac = A - mx; Bc = B - my;
        Ma = isfinite(Ac); Ac(~Ma) = 0;
        Mb = isfinite(Bc); Bc(~Mb) = 0;
        num = Ac' * Bc;
        sx2 = sum(Ac.^2,1); sy2 = sum(Bc.^2,1);
        den = sqrt(sx2') * sqrt(sy2);
        cnt = double(Ma)' * double(Mb);
        S   = nan(size(num));
        vld = (cnt > 1) & (den > eps);
        S(vld) = num(vld) ./ den(vld);
    case 'pearson_dice'
        maskA = abs(A) > eps; maskB = abs(B) > eps;
        overlap = maskA' * maskB;
        dice = overlap ./ (sum(maskA)' + sum(maskB) - overlap + eps);
        S_pearson = corr(A,B,'type','Pearson','rows','pairwise');
        S = S_pearson .* sqrt(dice);
    case 'spearman'
        S = corr(A, B, 'Type','Spearman', 'Rows','complete');
    case 'cosine'
        A0 = A; B0 = B; A0(~isfinite(A0)) = 0; B0(~isfinite(B0)) = 0;
        S = (A0' * B0) ./ (sqrt(sum(A0.^2))' * sqrt(sum(B0.^2)));
    case 'bicor'
        S = bicor_matrix(A, B, 12);
end
end

function [A,B] = unit_normalize(A, B)

nA = sqrt(sum(A.^2, 1, 'omitnan')); nA(nA < eps) = 1;
nB = sqrt(sum(B.^2, 1, 'omitnan')); nB(nB < eps) = 1;
A  = bsxfun(@rdivide, A, nA);
B  = bsxfun(@rdivide, B, nB);

end
function [C, cAUC] = nk_CreatPredFeat(AUC_upper, AUC_lower, L, verbose, s)
% Generate one predictive feature whose *sample* AUC equals A_mid
% using fixed noise and bisection on the mean gap Delta.
% Signature unchanged except for optional RandStream s.

if nargin < 5 || isempty(s)
    s = RandStream.getGlobalStream; % backwards compatible
end

% class sizes
n1 = sum(L==1);
n2 = sum(L==-1);

% fixed scales (keep simple; or draw once outside & pass in if you wish)
s1 = 1; s2 = 1;

% --- draw noise ONCE (key to avoid selection on noise) ---
z1 = randn(s, n1, 1);
z2 = randn(s, n2, 1);

% target AUC = midpoint of band
A_lo  = AUC_lower;
A_hi  = AUC_upper;
A_mid = 0.5*(A_lo + A_hi);

% direction: if A_mid<0.5 we want class 1 to be *lower* than class -1
dir = sign(A_mid - 0.5); 
if dir == 0, dir = 1; end   % exactly 0.5 -> arbitrary

% helper to compute sample AUC at a given Delta
auc_at = @(D) AUC(L, [ +0.5*dir*D + s1*z1;  -0.5*dir*D + s2*z2 ]);

% --- bracket A_mid ---
Delta_lo = 0;                 a_lo = auc_at(Delta_lo);
Delta_hi = sqrt(s1^2+s2^2);   a_hi = auc_at(Delta_hi);

maxDelta = 64*sqrt(s1^2+s2^2);  % generous cap
while ( (a_lo - A_mid)*(a_hi - A_mid) > 0 ) && (Delta_hi < maxDelta)
    Delta_hi = Delta_hi * 2;
    a_hi = auc_at(Delta_hi);
end
% if still not bracketed (can happen with heavy ties), fall back to clamp
if (a_lo - A_mid)*(a_hi - A_mid) > 0
    % pick the closer endpoint
    if abs(a_lo - A_mid) <= abs(a_hi - A_mid)
        Delta_star = Delta_lo; 
    else
        Delta_star = Delta_hi;
    end
else
    % --- bisection to hit A_mid ---
    tol = 1e-4; maxit = 50;
    dlo = Delta_lo; dhi = Delta_hi;
    for it = 1:maxit
        dmid = 0.5*(dlo + dhi);
        amid = auc_at(dmid);
        if amid < A_mid
            dlo = dmid;
        else
            dhi = dmid;
        end
        if abs(dhi - dlo) < tol, break; end
    end
    Delta_star = 0.5*(dlo + dhi);
end

% final sample at Delta_star
c1 = +0.5*dir*Delta_star + s1*z1;
c2 = -0.5*dir*Delta_star + s2*z2;
C  = [c1; c2];
cAUC = AUC(L, C);   % should be ~ A_mid within tolerance

% (optional) if you *must* enforce staying inside [A_lo, A_hi], clamp:
if cAUC < A_lo || cAUC > A_hi
    % target is the closest boundary (A_lo if below, A_hi if above)
    target = min(max(cAUC, A_lo), A_hi);

    % --- re-do bracket/bisection toward 'target' using the same noise ---
    dlo = 0;                         alo = auc_at(dlo);
    dhi = sqrt(s1^2 + s2^2);         ahi = auc_at(dhi);

    maxDelta = 64*sqrt(s1^2 + s2^2);
    while ((alo - target) * (ahi - target) > 0) && (dhi < maxDelta)
        dhi = 2 * dhi;
        ahi = auc_at(dhi);
    end

    if (alo - target) * (ahi - target) > 0
        % couldn't bracket (rare, e.g., many ties) — pick closer endpoint
        if abs(alo - target) <= abs(ahi - target)
            Delta_star = dlo;
        else
            Delta_star = dhi;
        end
    else
        tol = 1e-4; maxit = 50;
        for it = 1:maxit
            dmid = 0.5 * (dlo + dhi);
            amid = auc_at(dmid);
            if amid < target
                dlo = dmid;
            else
                dhi = dmid;
            end
            if abs(dhi - dlo) < tol, break; end
        end
        Delta_star = 0.5 * (dlo + dhi);
    end

    % recompute final sample and AUC at the clamped target
    c1 = +0.5 * dir * Delta_star + s1 * z1;
    c2 = -0.5 * dir * Delta_star + s2 * z2;
    C  = [c1; c2];
    cAUC = AUC(L, C);
end

if verbose
    figure; histogram(c1,10,'Normalization','probability'); hold on;
    histogram(c2,10,'Normalization','probability')
    legend({'Class +1','Class -1'}); title(sprintf('AUC=%.3f', cAUC));
end
end

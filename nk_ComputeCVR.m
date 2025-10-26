function [CVR, SE, MN] = nk_ComputeCVR(I, SEL, useSEM)
% I   : [D×F] or [D×F×C] weights per fold
% SEL : [D×F] selection mask (nonzero/true = include that fold)
% useSEM (optional, default: true): true → SD/sqrt(N); false → SD
%
% Returns:
%   CVR : mean / SE  (NaN where SE==0 or no data)
%   SE  : denominator used (SD or SD/sqrt(N))
%   MN  : mean across folds

if nargin < 3, useSEM = true; end

sz = size(I); D = sz(1); F = sz(2);
C = 1; 
if ndims(I) == 3, C = sz(3); else, I = reshape(I, D, F, 1); end

% mask out unselected folds
mask  = isfinite(SEL) & (SEL > 0);     % [D×F]
mask3 = repmat(mask, [1 1 C]);         % [D×F×C]
I(~mask3) = NaN;

% counts per feature (replicated to components)
N  = sum(mask, 2);                      % [D×1]
N3 = repmat(N, [1 1 C]);                % [D×1×C]

% sufficient statistics across folds
S1 = nm_nansum(I, 2);                   % [D×1×C]
S2 = nm_nansum(I.^2, 2);                % [D×1×C]

MN  = S1 ./ N3;                         % [D×1×C]
VAR = S2 ./ N3 - (S1 ./ N3).^2;         % [D×1×C]
VAR(VAR < 0) = 0;                       % clip tiny negatives
SD  = sqrt(VAR);

if useSEM == 1
    SE = SD ./ sqrt(N3);                % no 1.96 factor
elseif useSEM == 2
    SE = SD;
end

CVR      = nan(size(MN));
ok       = isfinite(SE) & (SE > 0);
CVR(ok)  = MN(ok) ./ SE(ok);

CVR = squeeze(CVR); 
SE  = squeeze(SE); 
MN  = squeeze(MN);
end

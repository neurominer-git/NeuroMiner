function R = bicor_matrix(refMaps, currentMaps, c)
% BICOR_MATRIX  pairwise biweight mid‐correlations between columns of two matrices
%   R = bicor_matrix(refMaps, currentMaps)
%   R = bicor_matrix(..., c) allows you to choose the tuning constant (default 4.685)
%
%   refMaps     is nF×k
%   currentMaps is nF×k2
%   R           is   k×k2

if nargin<3, c = 4.685; end

[kF, k]  = size(refMaps);
[~,   k2] = size(currentMaps);

R = nan(k,k2);
for i = 1:k
  xi = refMaps(:,i);
  for j = 1:k2
    R(i,j) = bicor_pair(xi, currentMaps(:,j), c);
  end
end
end


% ------------------------------------------------------------------------------
function r = bicor_pair(x,y,c)
% BICOR_PAIR   one‐pair biweight mid‐correlation, dropping NaNs

  if nargin<3, c = 4.685; end

  % drop any pairs where either is NaN
  m = ~isnan(x) & ~isnan(y);
  x = x(m);  y = y(m);

  % need at least 3 points to define a scale
  if numel(x)<3
    r = NaN; return
  end

  % medians
  mx = median(x);
  my = median(y);

  % "σ-hat" = 1.4826·median(|x - median|)
  sx = 1.4826 * median(abs(x - mx));
  sy = 1.4826 * median(abs(y - my));
  if sx==0 || sy==0
    r = NaN; return
  end

  % scaled deviations
  u = (x - mx) / (c * sx);
  v = (y - my) / (c * sy);

  % biweight weights
  wx = (abs(u)<1) .* (1 - u.^2).^2;
  wy = (abs(v)<1) .* (1 - v.^2).^2;

  w = wx .* wy;            % combined weight

  % weighted, centered vectors
  xw = (x - mx) .* w;
  yw = (y - my) .* w;

  num = sum( xw .* yw );
  den = sqrt( sum(xw.^2) * sum(yw.^2) );
  if den==0
    r = NaN;
  else
    r = num/den;
  end
end

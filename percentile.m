function Pk = percentile(X, Nk)
% PERCENTILE: The kth percentile Pk is that value of X, say Xk, which
%  corresponds to a cumulative frequency of Nk/100.
%  (Cited from Eric W. Weisstein, "Percentile", MathWorld)
%
% Usage: Pk = percentile(X, Nk);
%
% In which, X can be a 1D vector or a 2D matrix, and Nk can be a scalar or vector.
% If Nk is a scalar and X is a 1D vector, Pk will be the percentile of this 1D vector.
% If Nk is a scalar and X is a 2D matrix, Pk will be a row vector representing the
% percentile of each column in X.
% If Nk is a vector, the results are stacked together.
%
% NaN values in X are ignored.

   % Remove singleton dimensions.
   X = squeeze(X);

   % Validate Nk as scalar or vector.
   if length(Nk) ~= numel(Nk)
      error('Nk must either be a scalar or a vector');
   end

   % If X is a vector, remove NaN and compute percentiles.
   if isvector(X)
      X = X(~isnan(X));  % remove NaN values
      if isempty(X)
         Pk = NaN(size(Nk));
         return;
      end
      % Ensure X is a column vector.
      if size(X,1) == 1
         X = X';
      end
      n = length(X);
      sortedX = sort(X);
      % Create cumulative percentages.
      x = [0, ([0.5:(n-0.5)] ./ n) * 100, 100];
      % Build the interpolation vector (min, sorted data, max).
      y = [min(sortedX); sortedX; max(sortedX)];
      Pk = interp1(x, y, Nk, 'linear');
      
   else
      % X is a matrix; compute percentiles column by column.
      [~, cols] = size(X);
      Pk = NaN(length(Nk), cols);
      for j = 1:cols
         % Remove NaNs for this column.
         colData = X(:,j);
         colData = colData(~isnan(colData));
         if isempty(colData)
            Pk(:,j) = NaN;
         else
            sortedCol = sort(colData);
            n = length(sortedCol);
            x = [0, ([0.5:(n-0.5)] ./ n) * 100, 100];
            y = [min(sortedCol); sortedCol; max(sortedCol)];
            Pk(:,j) = interp1(x, y, Nk, 'linear');
         end
      end
      % If Nk is scalar, return a row vector.
      if isscalar(Nk)
         Pk = Pk(:)';
      end
   end

end

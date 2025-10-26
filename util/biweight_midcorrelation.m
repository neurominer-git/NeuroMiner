function R = biweight_midcorrelation(X, Y, c)
    if nargin<3 || isempty(c), c = 9; end
    if nargin<2 || isempty(Y), Y = X; end
    [F,K] = size(X); [F2,L] = size(Y);
    assert(F==F2, 'X and Y must have same rows');

    % 1) column‐wise medians and MADs, omitting NaNs
    medX = median(X, 1, 'omitnan');
    medY = median(Y, 1, 'omitnan');
    madX = median(abs(X - medX), 1, 'omitnan');
    madY = median(abs(Y - medY), 1, 'omitnan');

    % 2) scaled deviations
    U = (X - medX) ./ (c*madX);
    V = (Y - medY) ./ (c*madY);

    % 3) biweight weights
    W_X = (1 - U.^2).^2;  W_X(abs(U)>=1) = 0;
    W_Y = (1 - V.^2).^2;  W_Y(abs(V)>=1) = 0;

    % 4) center the data (NaNs stay NaN)
    Xc = X - medX;
    Yc = Y - medY;

    R = nan(K, L);
    for i = 1:K
      xi = Xc(:,i);  wx = W_X(:,i);
      for j = 1:L
        yj = Yc(:,j);  wy = W_Y(:,j);
        % mask out any rows where xi or yj is NaN
        valid = ~isnan(xi) & ~isnan(yj);
        w     = wx(valid) .* wy(valid);
        xi2   = xi(valid);
        yj2   = yj(valid);
        num   = sum(w .* xi2 .* yj2);
        den   = sqrt( sum(w .* xi2.^2) * sum(w .* yj2.^2) );
        if den>0
          R(i,j) = num/den;
        end
      end
    end

    if isequal(X,Y)
      R = (R + R.')/2;
      R(1:K+1:end) = 1;
    end
end
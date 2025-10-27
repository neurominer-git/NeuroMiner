function scoreMapping = isotonicRegression(x,y)
%ISOTONICREGRESSION Isotonic regression
% scoreMapping = isotonicRegression(x,y) fits a line yhat to data y under
% the monotonicity constraint that x(i)>x(j) -> yhat(i)>=yhat(j). That is,
% the values in yhat are monotontically non-decreasing with respect to x.
% The output, scoreMapping, is a struct containing the changepoints of yhat
% and the corresponding raw score in x.

% Copyright 2021, The MathWorks, Inc.

N = numel(x);

% Sort points in ascending order of x.
[x,idx] = sort(x(:),"ascend"); 
y = y(idx);

% Initialize fitted values to the given values.
m = y;

% Initialize blocks, one per point. These will merge and the number of
% blocks will reduce as the algorithm proceeds.
blockMap = 1:N;
w = ones(size(m));

while true

    diffs = diff(m);
    
    if all(diffs >= 0)

        % If all blocks are monotonic, end the loop.
        break;

    else

        % Find all positive changepoints. These are the beginnings of each
        % block.
        blockStartIndex = diffs>0;

        % Create group indices for each unique block.
        blockIndices = cumsum([1;blockStartIndex]);

        % Calculate the mean of each block and update the weights for the
        % blocks. We're merging all the points in the blocks here.
        m = accumarray(blockIndices,w.*m);
        w = accumarray(blockIndices,w);
        m = m ./ w;

        % Map which block corresponds to which index.
        blockMap = blockIndices(blockMap);

    end
end

% Broadcast merged blocks out to original points.
m = m(blockMap);

% Find the changepoints
changepoints = find(diff(m)>0);
changepoints = [changepoints;changepoints+1];
changepoints = sort(changepoints);

% Remove all points that aren't changepoints.
a = m(changepoints);
b = x(changepoints);

scoreMapping = struct(Raw=b,Calibrated=a);
end
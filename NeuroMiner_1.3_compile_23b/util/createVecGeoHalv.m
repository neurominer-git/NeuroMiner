function vector = createVecGeoHalv(startValue, endValue, nElem, r)
% startValue    Starting value of the vector
% endValue      Ending value of the vector
% nElem         Number of elements in the vector
% r             Common ratio (step halving)

totalChange = endValue - startValue;  % Total change required

% Calculate the first term of the geometric series needed to sum to totalChange
a = totalChange * (1 - r) / (1 - r^nElem);

% Generate the steps based on the first term and the ratio
steps = a * r.^(0:nElem-2);  % Generate one fewer step

% Create the vector by cumulative sum of steps starting explicitly from startValue
vector = [startValue, startValue + cumsum(steps)];

% Add the endValue explicitly to ensure it's included
if numel(vector) < nElem
    vector = [vector, endValue];
elseif numel(vector) > nElem
    vector = [vector(1:end-1), endValue];
else
    vector(end) = endValue;  % Ensure the last element is exactly endValue
end
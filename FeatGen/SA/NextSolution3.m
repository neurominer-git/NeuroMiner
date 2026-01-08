function x_new = NextSolution3(x_curr, itt, n, featureID_order)
% The new voxel is introduced to the solution in the order determined by
% featureID_order.
MIN_FEATURES = 3; % Set appropriate minimum

moduloItt = mod(itt,n); 
if moduloItt == 0, moduloItt = n; end

x_new = x_curr;

% Check if toggle would violate minimum
feature_to_toggle = featureID_order(moduloItt);
would_turn_off = x_curr(feature_to_toggle) == 1;

% If turning off would go below minimum, don't toggle
if would_turn_off && sum(x_curr) <= MIN_FEATURES
    % Keep current solution or force turning ON a random feature
    x_new = x_curr;
else
    % Toggle the feature
    x_new(feature_to_toggle) = 1 - x_new(feature_to_toggle);
end

x_new = logical(x_new);
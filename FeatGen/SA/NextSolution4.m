function x_new = NextSolution4(x_curr, n, featureID_order, T, T_initial)
% NEXTSOLUTION4 - Hybrid adaptive next solution generator for SA
%
% DESCRIPTION:
%   Generates next solution using multiple strategies:
%   - Single random toggle (50% probability)
%   - Multi-feature toggle (30% probability, temperature-dependent)
%   - Feature swap (20% probability)
%
% INPUTS:
%   x_curr          - Current solution (logical vector of length n)
%   itt             - Current iteration number
%   n               - Total number of features
%   featureID_order - Order of features (can be used for guided selection)
%   T               - Current temperature
%   T_initial       - Initial temperature
%
% OUTPUT:
%   x_new           - New solution (logical vector of length n)
%
% STRATEGY DETAILS:
%   - At high temperatures: More aggressive exploration (multi-toggles, random)
%   - At low temperatures: More focused refinement (guided by feature order)
%   - Single Toggle: Uses feature order to bias toward important features at low T
%   - Multi Toggle: Can be guided by top-ranked features at low T
%   - Maintains minimum and maximum feature constraints
%
% =========================================================================
% Nikolaos Koutsouleris, 01/2026

%% ===== Configuration Parameters =====
MIN_FEATURES = 3;                    % Minimum number of features to maintain
MAX_FEATURES = round(0.8 * n);       % Maximum features (80% of total)
MAX_MULTI_TOGGLES = 5;               % Maximum features to toggle at once

% Strategy selection probabilities
PROB_SINGLE_TOGGLE = 0.5;            % 50% single toggle
PROB_MULTI_TOGGLE = 0.3;             % 30% multi-toggle
% Remaining 20% is swap strategy

%% ===== Input Validation =====
if nargin < 5
    error('NextSolution4 requires input arguments');
end

if ~islogical(x_curr)
    error('x_curr must be a logical vector');
end

if length(x_curr) ~= n
    error('Length of x_curr must equal n');
end

if T <= 0 || T_initial <= 0
    error('Temperature values must be positive');
end

%% ===== Initialize =====
x_new = x_curr;
num_selected = sum(x_curr);
temp_ratio = T / T_initial;  % 1.0 at start, approaches 0 at end

% Safety check: if current solution violates constraints, fix it
if num_selected < MIN_FEATURES
    % Add random features to reach minimum
    off_features = find(~x_curr);
    if ~isempty(off_features)
        num_to_add = MIN_FEATURES - num_selected;
        add_idx = randperm(length(off_features), min(num_to_add, length(off_features)));
        x_new(off_features(add_idx)) = true;
    end
    return;
elseif num_selected > MAX_FEATURES
    % Remove random features to reach maximum
    on_features = find(x_curr);
    num_to_remove = num_selected - MAX_FEATURES;
    remove_idx = randperm(length(on_features), num_to_remove);
    x_new(on_features(remove_idx)) = false;
    return;
end

%% ===== Strategy Selection =====
r = rand();

if r < PROB_SINGLE_TOGGLE
    %% STRATEGY 1: Single Toggle - Guided by Feature Order (50%)
    % Use featureID_order to bias selection toward important features
    % At high T: more random; at low T: more guided by order
    
    if rand() < temp_ratio
        % High temperature: random selection
        feature_to_toggle = randi(n);
    else
        % Low temperature: guided by feature importance order
        % Select from top features with decreasing probability
        position = min(n, max(1, round(exprnd(n/3))));  % Exponential distribution
        feature_to_toggle = featureID_order(position);
    end
    
    if x_curr(feature_to_toggle) == 1  % Currently ON - try to turn OFF
        if num_selected > MIN_FEATURES
            x_new(feature_to_toggle) = false;
        end
        % else: can't turn off, would violate minimum
        
    else  % Currently OFF - try to turn ON
        if num_selected < MAX_FEATURES
            x_new(feature_to_toggle) = true;
        end
        % else: can't turn on, would violate maximum
    end
    
elseif r < (PROB_SINGLE_TOGGLE + PROB_MULTI_TOGGLE)
    %% STRATEGY 2: Multi-Feature Toggle (30%)
    % Toggle multiple features - more aggressive at high temperatures
    % Optionally guided by feature order at low temperatures
    
    % Number of toggles scales with temperature
    % High T (temp_ratio ≈ 1): up to MAX_MULTI_TOGGLES features
    % Low T (temp_ratio ≈ 0): 1-2 features
    num_toggles = max(1, round(MAX_MULTI_TOGGLES * temp_ratio));
    
    % Select features: random at high T, guided at low T
    if rand() < temp_ratio
        % High temperature: completely random
        features_to_toggle = randperm(n, min(num_toggles, n));
    else
        % Low temperature: bias toward top features in order
        % Select from top 50% of features with higher probability
        top_portion = min(n, max(num_toggles, round(n/2)));
        available_features = featureID_order(1:top_portion);
        perm_idx = randperm(length(available_features), min(num_toggles, length(available_features)));
        features_to_toggle = available_features(perm_idx);
    end
    
    for i = 1:length(features_to_toggle)
        feat = features_to_toggle(i);
        current_count = sum(x_new);  % Recompute after each toggle
        
        if x_new(feat) == 1  % Currently ON
            if current_count > MIN_FEATURES
                x_new(feat) = false;
            end
        else  % Currently OFF
            if current_count < MAX_FEATURES
                x_new(feat) = true;
            end
        end
    end
    
else
    %% STRATEGY 3: Feature Swap (20%)
    % Swap one ON feature with one OFF feature
    % Maintains feature count while exploring different combinations
    
    on_features = find(x_new);
    off_features = find(~x_new);
    
    % Only swap if both sets are non-empty
    if ~isempty(on_features) && ~isempty(off_features)
        % Randomly select one feature from each set
        swap_on = on_features(randi(length(on_features)));
        swap_off = off_features(randi(length(off_features)));
        
        % Perform the swap
        x_new(swap_on) = false;
        x_new(swap_off) = true;
    else
        % Fallback: if swap not possible, do single toggle instead
        feature_to_toggle = randi(n);
        if x_new(feature_to_toggle) == 1 && num_selected > MIN_FEATURES
            x_new(feature_to_toggle) = false;
        elseif x_new(feature_to_toggle) == 0 && num_selected < MAX_FEATURES
            x_new(feature_to_toggle) = true;
        end
    end
end

%% ===== Final Validation =====
% Ensure output is logical
x_new = logical(x_new);

% Sanity check: verify constraints are satisfied
num_selected_new = sum(x_new);
if num_selected_new < MIN_FEATURES || num_selected_new > MAX_FEATURES
    % Should never happen, but if it does, return original solution
    warning('Generated solution violates constraints. Returning original solution.');
    x_new = x_curr;
end

end
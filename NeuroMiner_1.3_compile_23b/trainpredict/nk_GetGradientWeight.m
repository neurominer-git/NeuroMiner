% ==========================================================================
% FORMAT [featImp] = nk_GetGradWeight(model, tXtest, y)
% ==========================================================================
% Inputs 
% model: python sklearn MLP/RNDFOR model structure. 
% tXtest: test data. 
% y: labels.
% 
% Outputs
% featImp: feature importance based on gradient importance
% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Sergio Mena Ortega, 2024

function [featImp] = nk_GetGradientWeight(model, tXtest)
global MODEFL

    % Initialize the feature importance array.
    featImp = zeros(1, size(tXtest, 2));
switch MODEFL
    case 'classification'
            % Loop over each feature.
        for i = 1:size(tXtest, 2)
            % Create a copy of the test data to manipulate.
            tXtest_copy = tXtest;
            
            % Get the min and max values of the i-th feature in the test set.
            min_val = min(tXtest(:, i));
            max_val = max(tXtest(:, i));
    
            % Calculate the gradient for the min value.
            tXtest_copy(:, i) = min_val;
            pred_min = double(model.predict_proba(py.numpy.array(tXtest_copy)).data);
    
            % Calculate the gradient for the max value.
            tXtest_copy(:, i) = max_val;
            pred_max = double(model.predict_proba(py.numpy.array(tXtest_copy)).data);
    
            % Calculate the gradient importance for the i-th feature.
            featImp(i) = mean(pred_max(:, 2) - pred_min(:, 2))/(max_val - min_val);
        end

    case 'regression'
        % Loop over each feature.
        for i = 1:size(tXtest, 2)
            % Create a copy of the test data to manipulate.
            tXtest_copy = tXtest;
            
            % Get the min and max values of the i-th feature in the test set.
            min_val = min(tXtest(:, i));
            max_val = max(tXtest(:, i));
    
            % Calculate the gradient for the min value.
            tXtest_copy(:, i) = min_val;
            pred_min = double(model.predict(py.numpy.array(tXtest_copy)).data);
    
            % Calculate the gradient for the max value.
            tXtest_copy(:, i) = max_val;
            pred_max = double(model.predict(py.numpy.array(tXtest_copy)).data);
    
            % Calculate the gradient importance for the i-th feature.
            featImp(i) = mean(pred_max - pred_min)/(max_val - min_val);
        end
end
end
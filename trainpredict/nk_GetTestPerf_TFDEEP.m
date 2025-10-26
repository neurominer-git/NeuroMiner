% ==========================================================================
% FORMAT [rs, ds] = nk_GetTestPerf_TFDEEP(~, tXtest, ~, model, ~, ~)
% ==========================================================================
% Inputs 
% model: python TF NN model structure. 
% tXtest: test data. 
% 
% Outputs
% rs: model predictions [1, -1] for binary, 1 being the positive label.
% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Sergio Mena Ortega, 2025
function [rs, ds] = nk_GetTestPerf_TFDEEP(~, tXtest, ~, model, ~, ~)
global MODEFL
    switch MODEFL
        case 'classification'
            votes = double(model.predict(py.numpy.array(tXtest)));
            [~, rs] = max(votes, [], 2);
            rs(rs==2) = -1;
            ds = votes(:, 1); 

        case 'regression'
            rs = double(model.predict(py.numpy.array(tXtest))); 
            ds = rs; 
    end
end
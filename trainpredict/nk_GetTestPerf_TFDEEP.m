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

% ================= Convert to Python arrays (same logic as training) =======
if size(tXtest,1) == 1 && size(tXtest,2) == 1
    X_py = py.numpy.array(tXtest).reshape(int64(1), int64(1)).astype('float32');
elseif size(tXtest,2) == 1
    X_py = py.numpy.array(tXtest).reshape(int64(-1), int64(1)).astype('float32');
elseif size(tXtest,1) == 1
    X_py = py.numpy.array(tXtest).reshape(int64(1), int64(-1)).astype('float32');
else
    X_py = py.numpy.array(tXtest).astype('float32');
end

% ================= Prediction =============================================
switch MODEFL
    case 'classification'
        votes = double(model.predict(X_py));

        % Binary classification convention used in TFDEEP
        [~, rs] = max(votes, [], 2);
        rs(rs == 2) = -1;

        % Decision scores (positive class)
        ds = votes(:,1);

    case 'regression'
        rs = double(model.predict(X_py));
        ds = rs;
end
end
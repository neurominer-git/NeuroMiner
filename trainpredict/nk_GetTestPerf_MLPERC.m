% ==========================================================================
% FORMAT [rs, ds] = nk_GetTestPerf_MLP(~, tXtest, ~, model, ~, ~)
% ==========================================================================
% Inputs 
% model: python MLP model structure. 
% tXtest: test data. 
% 
% Outputs
% rs: model predictions
% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Sergio Mena Ortega, 2024
function [rs, ds] = nk_GetTestPerf_MLPERC(~, tXtest, ~, model, ~, ~)
global MODEFL
    switch MODEFL
        case 'classification'
            %Get predictions and probabilities.
            if size(tXtest,1) == 1 && size(tXtest,2) == 1
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(1), int64(1))).data);
                votes = double(model.predict_proba(py.numpy.array(tXtest).reshape(int64(1), int64(1))).data);
            elseif size(tXtest, 2) == 1 
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(-1), int64(1))).data);
                votes = double(model.predict_proba(py.numpy.array(tXtest).reshape(int64(-1), int64(1))).data);
            elseif size(tXtest, 1) == 1
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(1), int64(-1))).data);
                votes = double(model.predict_proba(py.numpy.array(tXtest).reshape(int64(1), int64(-1))).data);
            else
                rs = double(model.predict(tXtest).data);
                votes = double(model.predict_proba(tXtest).data);
            end
            ds = votes(:,2)./sum(votes,2);
        case 'regression'
            %Get predictions. 
            if size(tXtest,1) == 1 && size(tXtest,2) == 1
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(1), int64(1))).data);
            elseif size(tXtest, 2) == 1 
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(-1), int64(1))).data);
            elseif size(tXtest, 1) == 1
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(1), int64(-1))).data);
            else
                rs = double(model.predict(double(tXtest)).data);
            end
            ds = rs;
end
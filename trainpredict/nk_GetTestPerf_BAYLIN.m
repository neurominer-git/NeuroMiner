function [rs, ds] = nk_GetTestPerf_BAYLIN(~, tXtest, ~, md, ~, ~)
% nk_GetTestPerf_BAYESLIN
% Predictions for Bayesian linear models trained via scikit-learn:
%   - classification (binary): BayesianRidge/ARD fit on {0,1}, sigmoid link
%   - regression: BayesianRidge/ARD regression
%
% INPUTS
%   tXtest : [N* x p] test features
%   md     : fitted Python model (BayesianRidge or ARDRegression)
%
% OUTPUTS
%   rs : classification -> predicted class labels in {0,1}
%        regression     -> predicted targets (yhat)
%   ds : classification -> probability of class 1 (sigmoid of linear score)
%        regression     -> equals rs (continuous predictions)
% =========================================================================
% (c) Nikolaos Koutsouleris, 10/2025

global MODEFL

model = md;

% -------- helpers --------
    function v = py2mat(ypy)
        % Converts common Python containers / numpy arrays to MATLAB double
        if isa(ypy, 'py.numpy.ndarray')
            v = cell2mat(cell(ypy.tolist()));     % preserves shape
        elseif isa(ypy, 'py.list')
            v = cell2mat(cell(ypy));
        else
            try
                v = double(ypy);                  % scalars / simple types
            catch
                % last-resort: go via list()
                v = cell2mat(cell(py.list(ypy)));
            end
        end
    end

    function v = predict_to_double(X)
        ypy = model.predict(X);                   % NumPy ndarray
        v   = py2mat(ypy);
    end

% -------- predict --------
switch MODEFL
    case 'classification'
        % linear scores from sklearn model
        if size(tXtest,1) == 1 && size(tXtest,2) == 1
            ylin = predict_to_double(py.numpy.array(tXtest).reshape(int64(1), int64(1)));
        elseif size(tXtest, 2) == 1 
            ylin = predict_to_double(py.numpy.array(tXtest).reshape(int64(-1), int64(1)));
        elseif size(tXtest, 1) == 1
            ylin = predict_to_double(py.numpy.array(tXtest).reshape(int64(1), int64(-1)));
        else
            ylin = predict_to_double(double(tXtest));
        end
        ylin = ylin(:);

        % sigmoid -> probability of class 1
        ds = 1 ./ (1 + exp(-ylin));
        ds=ylin;
        rs = double(ds >= 0.5);                  % hard labels {0,1}

    case 'regression'
        if size(tXtest,1) == 1 && size(tXtest,2) == 1
            rs = predict_to_double(py.numpy.array(tXtest).reshape(int64(1), int64(1)));
        elseif size(tXtest, 2) == 1 
            rs = predict_to_double(py.numpy.array(tXtest).reshape(int64(-1), int64(1)));
        elseif size(tXtest, 1) == 1
            rs = predict_to_double(py.numpy.array(tXtest).reshape(int64(1), int64(-1)));
        else
            rs = predict_to_double(double(tXtest));
        end
        rs = rs(:); 
        ds = rs;                                  % regression: ds == rs

    otherwise
        error('MODEFL must be ''classification'' or ''regression''.');
end
end

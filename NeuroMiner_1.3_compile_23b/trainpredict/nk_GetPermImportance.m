% ==========================================================================
% FORMAT [featImp] = nk_GetPermImportance(model, tXtest, y)
% ==========================================================================
% Inputs 
% model: python sklearn MLP/RNDFOR model structure. 
% tXtest: test data. 
% y: labels.
% 
% Outputs
% featImp: feature importance based on permutation importance
% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Sergio Mena Ortega, 2024
function [featImp] = nk_GetPermImportance(model, tXtest, y)
global MODEFL EVALFUNC 

%Initialise variables; performance array and feature importance.
perf2 = zeros(1, size(tXtest, 2));
featImp = zeros(1, size(tXtest, 2));


if size(tXtest, 2) > 1
   pred1 = double(model.predict(tXtest).data);
   perf1 = EVALFUNC(y, pred1');
   for i=1:length(featImp)
      % Shuffle the i-th feature
      X_shuf = tXtest;
      X_shuf(:,i) = tXtest(randperm(size(X_shuf, 1)), i);

      % Predict the new performance.
      pred2 = double(model.predict(X_shuf).data);
      perf2(i) = EVALFUNC(y, pred2');
   end
else
   pred1 = double(model.predict(py.numpy.array(tXtest).reshape(int64(-1), int64(1))).data);
   perf1 = EVALFUNC(y, pred1');
   for i=1:length(featImp)
      % Shuffle the i-th feature
      X_shuf = tXtest;
      X_shuf(:,i) = tXtest(randperm(size(X_shuf, 1)), i);

      % Predict the new performance.
      pred2 = double(model.predict(py.numpy.array(X_shuf).reshape(int64(-1), int64(1))).data);
      perf2(i) = EVALFUNC(y, pred2');
   end
end

%Calculate feature importance depending on metric.
switch char(EVALFUNC)
    % 0-inf metrics; high is better performance.
    case {'ACCURACY', 'TPR', 'SENSITIVITY', 'PPV', 'AUC', 'BAC', 'FSCORE', 'BAC2', 'SCC', 'PSI', 'GMEAN'}
        featImp = perf1 - perf2;

    % -1 to 1 metrics; positive is better performance.
    case {'MCC', 'CC'}
        %Normalise prediction performance to [0,1]. 
        perf1 = (perf1 + 1) / 2;
        perf2 = (perf2 + 1) ./ 2;
        featImp = perf1 - perf2;

    % 0-inf metrics; low is better performance. 
    case {'MSE', 'NRMSD', 'RMSD', 'MAERR', 'ECE', 'NNP', 'FPR'}
        featImp = perf2 - perf1;
end
end
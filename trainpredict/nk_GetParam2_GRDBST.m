% ==========================================================================
% FORMAT [param, model] = nk_GetParam_GRDBST(Y, label, ModelOnly, Params)
% ==========================================================================
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris, 03/2017

function [param, model] = nk_GetParam2_GRDBST(Y, label, ModelOnly, Params)
global EVALFUNC MODELDIR MODEFL

param = [];
options = nk_GenMatLearnOptions(Params);
%maxIters = uint32(options.maxIters);
%options.maxTreeDepth = uint32(options.maxTreeDepth);
%options.loss = 'squaredloss';
%model = SQBMatrixTrain( single(Y), label, maxIters, options );
switch MODEFL
    case 'classification'
        feat = Y;
        lab = label;
        n_est = int64(options.maxIters);
        l = string(options.loss);
        lr = double(options.learningRate);
        subsamp = double(options.subsamplingFactor);
        n_maxdepth = int64(options.maxTreeDepth);

        model = py.sklearn.ensemble.GradientBoostingClassifier(n_estimators = n_est, ...
            loss = l, ...
            learning_rate = lr, ...
            subsample = subsamp, ...
            max_depth = n_maxdepth, ...
            random_state = int8(42));

        % model = pyrunfile('cv_py_classGRDBST_train.py', 'model_file', ...
        %     feat = Y, lab = label, ...
        %     n_est = int64(options.maxIters), ...
        %     l = string(options.loss), ...
        %     lr = double(options.learningRate), ...
        %     subsamp = double(options.subsamplingFactor),...
        %     n_maxdepth = int64(options.maxTreeDepth), ...
        %     rootdir = MODELDIR);
     case 'regression'
        feat = Y; 
        lab = label;
        n_est = int64(options.maxIters);
        l = string(options.loss);
        lr = double(options.learningRate);
        subsamp = double(options.subsamplingFactor);
        n_maxdepth = int64(options.maxTreeDepth);
        
        model = py.sklearn.ensemble.GradientBoostingRegressor(loss = l, ...
            learning_rate = lr, ...
            n_estimators = n_est, ...
            subsample = subsamp, ...
            max_depth = n_maxdepth); 

        % model = pyrunfile('cv_py_regGRDBST_train.py', 'model_file', ...
        %     feat = Y, lab = label, ...
        %     n_est = int64(options.maxIters), ...
        %     l = string(options.loss), ...
        %     lr = double(options.learningRate), ...
        %     subsamp = double(options.subsamplingFactor),...
        %     n_maxfeat = int64(options.maxTreeDepth), ...
        %     rootdir = MODELDIR);

end

%sklearn errors when size(Y,2) = 1, ndarray needs reshaping 
if size(feat,1) == 1 && size(feat,2) == 1
    model = model.fit(py.numpy.array(feat).reshape(int64(1), int64(1)), double(lab'));
elseif size(feat, 2) == 1
    model = model.fit(py.numpy.array(feat).reshape(int64(-1), int64(1)), double(lab'));
elseif size(feat, 1) == 1
    model = model.fit(py.numpy.array(feat).reshape(int64(1), int64(-1)), double(lab'));
else 
    model = model.fit(double(feat), double(lab));
end


% is this part still necessary?
if ~ModelOnly
    [param.target, param.dec_values] = nk_GetTestPerf_GRDBST([], Y, label, model) ;
    param.val = EVALFUNC(label, param.target);
end
end
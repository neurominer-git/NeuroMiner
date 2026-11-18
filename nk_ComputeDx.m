function [D, refScore, scoreDomain] = nk_ComputeDx(SVM, MD, Z, W, context)
%NK_COMPUTEDX Exact model-input component contributions.
%   [D, refScore, scoreDomain] = nk_ComputeDx(SVM,MD,Z,W,context)
%
%   SVM.prog is the outer learner key; SVM.matLRN.algo{1} selects matLearn.
%   Z has all fitted model input features, in their native order.
%   W, when supplied, is an exact coefficient vector on the SAME feature
%   axis. A valid W is used directly and never replaced with a model-
%   extracted coefficient vector. W=[] requests model-based extraction.
%   For LIBSVM/LIBLIN, supplied W is the historically filtered and
%   normalized weight vector, thus preserving existing Dx semantics.
%   Nonlinear learners must receive W=[]; they use the actual fitted MD.
%
%   context.mode: 'regression'/'classification'; 'survival' for WBLCOX.
%   context.trainZ: fitted training coordinates required by linear RVMs.
%   context.reference: explicit neural-network reference coordinates.
%
%   Outputs: D is subjects x fitted-model features. refScore is a native
%   raw-score intercept/reference. For historical normalized SVM weights
%   it is NaN, since no consistent normalized intercept is supplied.
%   scoreDomain identifies the model-specific score scale. The function
%   does not modify the fitted model, score, feature alignment, or maps.


switch SVM.prog
    case {'LIBSVM','LIBLIN'}
        if strcmp(SVM.prog,'LIBSVM')
            assert(any(strcmp(SVM.kernel.kernstr, ...
                {' -t 0',' -t 4',' -t 5','lin','linear','none'})), ...
                'nk:dxKernelSVM', 'Dx requires a linear SVM primal weight vector.');
        end
        if isempty(W), W = nk_GetPrimalW(MD); end
        D = applyWeights(Z,W);
        refScore = NaN;
        scoreDomain = 'legacy_linear_svm_weighted_coordinates';
        return

    case {'GLMFIT','ELASVM','WBLCOX'}
        if isempty(W)
            out = nk_DxLinearExact(SVM.prog,MD,Z);
            [D,refScore,scoreDomain] = unpackAffine(out);
        else
            D = applyWeights(Z,W);
            switch SVM.prog
                case 'GLMFIT'
                    refScore = MD.beta(1);
                    scoreDomain = 'glm_linear_predictor';
                case 'ELASVM'
                    refScore = 0;
                    scoreDomain = 'elasvm_pre_sigmoid';
                case 'WBLCOX'
                    refScore = 0;
                    scoreDomain = 'cox_log_relative_hazard';
            end
        end
        return

    case 'GLMNET'
        requireNoSurrogate(W,SVM.prog);
        out = nk_DxLinearExact('GLMNET',MD,Z);

    case 'BAYLIN'
        requireNoSurrogate(W,SVM.prog);
        out = nk_DxLinearExact('BAYLIN',MD,Z);

    case 'BLOREG'
        requireNoSurrogate(W,SVM.prog);
        % Only the native non-kernel fitted predictor has this contract.
        assert(strcmp(SVM.kernel.kernstr,'none'), 'nk:dxBLOREGKernel', ...
            'Kernel BLOREG is not a verified exact component decomposition.');
        out = nk_DxLinearExact('BLOREG_DIRECT',MD,Z);

    case 'MikRVM'
        requireNoSurrogate(W,SVM.prog);
        assert(any(strcmp(SVM.kernel.kernstr,{'lin','linear',' -t 0'})), ...
            'nk:dxMikRVMKernel','Only fitted linear-kernel MikRVM is supported.');
        out = nk_DxLinearExact('MIKRVM_LINEAR',MD,Z,context.trainZ);

    case 'MVTRVR'
        requireNoSurrogate(W,SVM.prog);
        assert(strcmp(context.mode,'regression'), 'nk:dxMVTRVRTask', ...
            'Only single-output MVTRVR regression has been validated.');
        assert(any(strcmp(SVM.kernel.kernstr,{'lin','linear',' -t 0','lin_kernel'})), ...
            'nk:dxMVTRVRKernel', 'Only linear-kernel MVTRVR is supported.');
        out = nk_DxLinearExact('MVTRVR_LINEAR_REGRESSION',MD,Z,context.trainZ);

    case 'DECTRE'
        requireNoSurrogate(W,SVM.prog);
        assert(strcmp(context.mode,'classification'),'nk:dxDECTRETask', ...
            'Only DECTRE binary classification has been validated.');
        out = nk_DxTreeExact('DECTRE',MD,Z);

    case 'RNDFOR'
        requireNoSurrogate(W,SVM.prog);
        switch context.mode
            case 'regression',     out = nk_DxTreeExact('RNDFOR_REGRESSION',MD,Z);
            case 'classification', out = nk_DxTreeExact('RNDFOR_CLASSIFICATION',MD,Z);
            otherwise, error('nk:dxForestTask','Unsupported random-forest prediction mode.');
        end

    case 'GRDBST'
        requireNoSurrogate(W,SVM.prog);
        switch context.mode
            case 'regression',     out = nk_DxTreeExact('GRDBST_REGRESSION',MD,Z);
            case 'classification', out = nk_DxTreeExact('GRDBST_CLASSIFICATION',MD,Z);
            otherwise, error('nk:dxBoostTask','Unsupported gradient-boosting prediction mode.');
        end

    case 'MLPERC'
        requireNoSurrogate(W,SVM.prog);
        out = nk_DxMLPExact(MD,Z,context.reference,context.mode,'MLPERC');

    case 'TFDEEP'
        requireNoSurrogate(W,SVM.prog);
        % The trained network class and hidden activation are the actual
        % model authority; they are not inferred from visualization weights.
        [framework,activation] = tfdeepArchitecture(MD);
        out = nk_DxMLPExact(MD,Z,context.reference,context.mode,framework,activation);

    case 'matLRN'
        algo = SVM.matLRN.algo{1};
        switch SVM.matLRN.learner.framework
            case 'regression'
                switch algo
                    % nm2-allow: matLearn writer defines these seven distinct affine algorithms.
                    case {'L1','L2','leastSquares','NB','Huber','ARD','student'}
                        method = matLearnAffineMethod(algo);
                        checkMatLearnConfiguration(method,MD,Z);
                        if isempty(W)
                            out = nk_DxLinearExact(method,MD,Z);
                        else
                            D = applyWeights(Z,W);
                            [refScore,scoreDomain] = matLearnAffineMetadata(method,MD);
                            return
                        end
                    case 'stump'
                        requireNoSurrogate(W,SVM.prog);
                        out = nk_DxTreeExact('MATLRN_REGSTUMP_CONSTANT',MD,Z);
                    case 'MLP'
                        requireNoSurrogate(W,SVM.prog);
                        out = nk_DxMLPExact(MD,Z,context.reference,'regression','matLRN_MLP');
                    case {'NW','local','mean','GAM'}
                        error('nk:dxUnsupportedMatLearn', ...
                            'No validated component Dx contract for matLearn regression %s.',algo);
                    otherwise
                        error('nk:dxUnknownMatLearn','Unknown matLearn regression %s.',algo);
                end
            case 'binaryclass'
                switch algo
                    % nm2-allow: matLearn writer defines these six affine classifiers.
                    case {'SVM','HSVM','SSVM','logistic','elastic_net','exponential'}
                        method = matLearnAffineMethod(algo);
                        checkMatLearnConfiguration(method,MD,Z);
                        if isempty(W)
                            out = nk_DxLinearExact(method,MD,Z);
                        else
                            D = applyWeights(Z,W);
                            [refScore,scoreDomain] = matLearnAffineMetadata(method,MD);
                            return
                        end
                    case 'stump'
                        requireNoSurrogate(W,SVM.prog);
                        out = nk_DxTreeExact('MATLRN_STUMP_CLASSIFICATION',MD,Z);
                    case 'brokenStump'
                        requireNoSurrogate(W,SVM.prog);
                        out = nk_DxTreeExact('MATLRN_BROKENSTUMP_CLASSIFICATION',MD,Z);
                    case 'randomForest'
                        requireNoSurrogate(W,SVM.prog);
                        out = nk_DxTreeExact('MATLRN_RANDOMFOREST_CLASSIFICATION',MD,Z);
                    case 'MLP'
                        requireNoSurrogate(W,SVM.prog);
                        out = nk_DxMLPExact(MD,Z,context.reference,'classification','matLRN_MLP');
                    case {'boosting','extreme','Cauchit'}
                        error('nk:dxUnsupportedMatLearn', ...
                            'No validated component Dx contract for matLearn classification %s.',algo);
                    otherwise
                        error('nk:dxUnknownMatLearn','Unknown matLearn classification %s.',algo);
                end
            otherwise
                error('nk:dxMatLearnFramework', 'Unrecognized fitted matLearn framework.');
        end

    case {'MEXELM','MKLRVM','MVTRVM','kNNMEX','IMRELF','SEQOPT', ...
          'ROBSVM','CCSSVM','FAMRVR','LOGREG','MSTOOL'}
        error('nk:dxUnsupported','No validated complete component Dx contract for %s.',SVM.prog);
    otherwise
        error('nk:dxUnknownLearner','Unrecognized SVM.prog %s.',SVM.prog);
end

D = out.contributions;
if any(strcmp(SVM.prog,{'MLPERC','TFDEEP'})) || ...
        (strcmp(SVM.prog,'matLRN') && strcmp(SVM.matLRN.algo{1},'MLP'))
    refScore = out.referenceScore;
else
    refScore = out.intercept;
end
scoreDomain = out.domain;
end

function D = applyWeights(Z,W)
% nm2-allow: an optional externally supplied coefficient vector needs exact model-feature axis identity.
assert(isvector(W) && numel(W)==size(Z,2) && all(isfinite(W(:))), ...
    'nk:dxWeightAxis', ...
    'Supplied Dx coefficients must be finite, one per fitted input feature.');
D = bsxfun(@times,Z,reshape(W,1,[]));
end

function requireNoSurrogate(W,learner)
assert(isempty(W),'nk:dxSurrogateWeight', ...
    'The %s learner needs fitted-model Dx; supplied importance weights are not coefficients.',learner);
end

function [D,refScore,scoreDomain] = unpackAffine(out)
D = out.contributions;
refScore = out.intercept;
scoreDomain = out.domain;
end

function method = matLearnAffineMethod(algo)
switch algo
    case 'L1', method = 'MATLRN_L1';
    case 'L2', method = 'MATLRN_L2';
    case 'leastSquares', method = 'MATLRN_LEASTSQUARES';
    case 'NB', method = 'MATLRN_NB';
    case 'Huber', method = 'MATLRN_HUBER';
    case 'ARD', method = 'MATLRN_ARD';
    case 'student', method = 'MATLRN_STUDENT';
    case 'SVM', method = 'MATLRN_SVM';
    case 'HSVM', method = 'MATLRN_HSVM';
    case 'SSVM', method = 'MATLRN_SSVM';
    case 'logistic', method = 'MATLRN_LOGISTIC';
    case 'elastic_net', method = 'MATLRN_ELASTIC_NET';
    case 'exponential', method = 'MATLRN_EXPONENTIAL';
    otherwise, error('nk:dxMatLearnAffine','Unrecognized affine matLearn method.');
end
end

function checkMatLearnConfiguration(method,MD,Z)
switch method
    case 'MATLRN_L2'
        if MD.addBias
            expected = (1:size(Z,2)+1)';
        else
            expected = (1:size(Z,2))';
        end
        assert(isequal(MD.features(:),expected),'nk:dxMatLearnFeatureOrder', ...
            'matLearn L2 uses an unverified selected or reordered feature axis.');
    case 'MATLRN_ARD'
        assert(MD.scale==0,'nk:dxMatLearnARD','Scaled matLearn ARD is unverified.');
    case 'MATLRN_STUDENT'
        assert(MD.poly==1,'nk:dxMatLearnStudent','Polynomial Student regression is unverified.');
    case {'MATLRN_HSVM','MATLRN_SSVM'}
        assert(MD.kernel==0,'nk:dxMatLearnKernel','Kernelized matLearn SVM is unverified.');
    case 'MATLRN_EXPONENTIAL'
        assert(MD.addBias==1,'nk:dxMatLearnExponential', ...
            'Exponential-loss model without its fitted bias is unverified.');
end
end

function [b,domain] = matLearnAffineMetadata(method,MD)
switch method
    case 'MATLRN_L2',           domain = 'matlrn_l2_linear_predictor';
    case 'MATLRN_LOGISTIC',     domain = 'matlrn_logistic_logit';
    case 'MATLRN_LEASTSQUARES', domain = 'matlrn_least_squares_linear_predictor';
    otherwise,                  domain = 'matlrn_affine_native_score';
end
if strcmp(method,'MATLRN_LEASTSQUARES')
    b = 0;
elseif MD.addBias
    b = MD.w(1);
else
    b = 0;
end
end

function [source,activation] = tfdeepArchitecture(MD)
% The two model types are constructed by nk_GetParam2_TFDEEP.
% Read the activation from the fitted network, not a guessed grid index.
modelType = char(py.str(py.type(MD)));
if contains(modelType,'train_pytorch_model.TorchMLP')
    source = 'TFDEEP_pytorch';
    roots = cell(py.list(MD.children()));
    assert(numel(roots)==1,'nk:dxTorchArchitecture','Unexpected TorchMLP root.');
    modules = cell(py.list(roots{1}.children()));
    assert(numel(modules)>=3,'nk:dxTorchArchitecture','Unexpected TorchMLP layers.');
    activationType = char(py.str(py.type(modules{2})));
    if contains(activationType,'ReLU')
        activation = 'relu';
    elseif contains(activationType,'Tanh')
        activation = 'tanh';
    elseif contains(activationType,'Sigmoid')
        activation = 'sigmoid';
    elseif contains(activationType,'Identity')
        activation = 'linear';
    elseif contains(activationType,'Softplus')
        activation = 'softplus';
    elseif contains(activationType,'ELU')
        activation = 'elu';
    else
        error('nk:dxTorchActivation','Unverified TorchMLP activation module.');
    end
elseif contains(modelType,'Sequential')
    source = 'TFDEEP_tensorflow';
    layers = cell(py.list(MD.layers));
    assert(numel(layers)>=2,'nk:dxTFArchitecture','Unexpected Keras Dense stack.');
    activation = char(py.getattr(layers{1}.activation,'__name__'));
else
    error('nk:dxTFModelType','Unverified TFDEEP fitted model class.');
end
end

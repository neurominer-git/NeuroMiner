function out = nk_DxLinearExact(learner, model, Z, varargin)
%NM2DX_LINEAR  Independent, exact fractionation in an affine model space.
%  out = nm2dx_linear(learner, fittedModel, heldOutModelCoordinates)
%
%  Does not change the fitted model or call the production Dx pathway.
%  Only the four source-verified raw-score contracts below are accepted.
%  GLMNET: final fitted lambda, link scale, no offset, elnet/lognet only.
%  GLMFIT: ordinary identity/logit link fitted by nk_GetParam2_GLMFIT.
%  ELASVM: raw predictor X*model.beta before sigmoid/centering.
%  WBLCOX: log-relative-hazard X*model.beta (not risk probability).
%  BAYLIN: scikit-learn fitted coef_/intercept_ (raw predict output).
%  BLOREG: direct non-kernel fitted alpha (logit before sigmoid).
%  matLRN: selected affine L2 regression and logistic implementations.
%  MikRVM/MVTRVR: linear-kernel primal projection of fitted dual weights.
%
%  Z MUST be the exact held-out feature/component coordinates presented
%  to the trained predictor, in the original fitted order. No rotation,
%  standardization, alignment, feature selection or calibration occurs here.

switch learner
    case 'GLMFIT'
        coef = full(model.beta(:));
        b = coef(1);
        w = coef(2:end);
        domain = 'glm_linear_predictor';
    case 'GLMNET'
        switch model.class
            case {'elnet','lognet'}
                assert(~model.offset, 'nm2dx:offsetUnsupported', ...
                    'GLMNET models with fitted offsets are not in this exact-Dx pilot.');
            otherwise
                error('nm2dx:unsupportedGLMNETClass', ...
                    'GLMNET class %s is not a verified single-output affine contract.', model.class);
        end
        % The native nk_GetTestPerf_GLMNET uses p(:,end) after
        % glmnetPredict(model,Z), whose default is link and entire path.
        b = double(model.a0(end));
        w = full(model.beta(:,end));
        domain = 'glmnet_last_lambda_link';
    case 'ELASVM'
        b = 0;
        w = model.beta(:);
        domain = 'elasvm_pre_sigmoid';
    case 'WBLCOX'
        b = 0;
        w = model.beta(:);
        domain = 'cox_log_relative_hazard';
    case 'BAYLIN'
        % nk_GetParam2_BAYLIN fits an sklearn affine regressor. Its current
        % nk_GetTestPerf_BAYLIN returns model.predict (raw) in BOTH modes.
        % Python array conversion follows the backend's existing py.array
        % bridge convention; it never fits or transforms the model.
        b = double(model.intercept_);
        w = double(py.array.array('d', model.coef_));
        w = w(:);
        domain = 'baylin_sklearn_linear_predictor';
    case 'BLOREG_DIRECT'
        % Only the non-kernel nk_GetParam2_BLOREG branch: md.alpha is
        % defined in the original feature coordinates, with no intercept.
        % Kernel BLOREG needs a different representation and is excluded.
        b = 0;
        w = model.alpha(:);
        domain = 'blogreg_direct_logit';
    case 'MATLRN_L2'
        % ml_regression_L2 fits the optional bias as coefficient 1;
        % this pilot admits only its default complete feature selection.
        if model.addBias
            b = model.w(1);
            w = model.w(2:end);
            expectedFeatures = (1:size(Z,2)+1)';
        else
            b = 0;
            w = model.w(:);
            expectedFeatures = (1:size(Z,2))';
        end
        assert(isequal(model.features(:),expectedFeatures), ...
            'nm2dx:matLRNFeatureSelection', ...
            'matLearn L2 subset/reordered feature selection not admitted.');
        domain = 'matlrn_l2_linear_predictor';
    case 'MATLRN_LOGISTIC'
        % ml_binaryclass_logistic.predict returns sigmoid(logit)-0.5;
        % fitted w is ordered as [bias; input coefficients] when addBias=1.
        if model.addBias
            b = model.w(1);
            w = model.w(2:end);
        else
            b = 0;
            w = model.w(:);
        end
        domain = 'matlrn_logistic_logit';
    case 'MATLRN_LEASTSQUARES'
        % ml_regression_leastSquares predicts directly in input coordinates;
        % unlike most matLearn regressors it stores model.weights, not w.
        b = 0;
        w = model.weights(:);
        domain = 'matlrn_least_squares_linear_predictor';
    case {'MATLRN_L1','MATLRN_NB','MATLRN_HUBER','MATLRN_ARD', ...
          'MATLRN_STUDENT','MATLRN_SVM','MATLRN_HSVM', ...
          'MATLRN_SSVM','MATLRN_ELASTIC_NET','MATLRN_EXPONENTIAL'}
        % Each enumerated source-verified learner predicts with an affine
        % expression in the original input coordinates. This switch is
        % intentionally closed: it is not a generic matLearn coefficient
        % accessor or a second learner registry.
        switch learner
            case 'MATLRN_ARD'
                assert(model.scale == 0, 'nm2dx:scaledARDNotInL4', ...
                    'This experiment admits unscaled matLearn ARD only.');
            case 'MATLRN_STUDENT'
                assert(model.poly == 1, 'nm2dx:polynomialStudentNotInL4', ...
                    'This experiment admits Student-t regression with poly=1 only.');
            case {'MATLRN_HSVM','MATLRN_SSVM'}
                assert(model.kernel == 0, 'nm2dx:kernelMatLearnNotInL4', ...
                    'Kernelized matLearn hinge SVM is outside the affine contract.');
            case 'MATLRN_EXPONENTIAL'
                % The producer unconditionally persists addBias=1.
                % L4 explicitly trains with addBias=1 to preserve parity.
                assert(model.addBias == 1, 'nm2dx:exponentialBias', ...
                    'The tested exponential-loss predictor expects an intercept.');
        end
        if model.addBias
            b = model.w(1);
            w = model.w(2:end);
        else
            b = 0;
            w = model.w(:);
        end
        domain = 'matlrn_affine_native_score';
    case 'MIKRVM_LINEAR'
        % SB1_KernelFunction(train, test, 'lin') = test*train'.
        % Hence K*inference = test*(train'*inference).
        assert(numel(varargin) == 1, 'nm2dx:trainingCoordinatesRequired', ...
            'Linear MikRVM requires the exact training coordinates.');
        trainZ = varargin{1};
        assert(size(trainZ,1) == numel(model.inference), ...
            'nm2dx:kernelTrainAxis', 'MikRVM dual coefficients do not match training rows.');
        assert(size(trainZ,2) == size(Z,2), ...
            'nm2dx:kernelFeatureAxis', 'MikRVM training and test feature axes differ.');
        b = 0;
        w = trainZ' * model.inference(:);
        domain = 'mikrvm_linear_primal';
    case 'MVTRVR_LINEAR_REGRESSION'
        % Regression predictor uses test*train(rv,:)'*weights.
        assert(numel(varargin) == 1, 'nm2dx:trainingCoordinatesRequired', ...
            'Linear MVTRVR requires the exact training coordinates.');
        trainZ = varargin{1};
        assert(size(trainZ,2) == size(Z,2), ...
            'nm2dx:kernelFeatureAxis', 'MVTRVR training and test feature axes differ.');
        assert(size(model.weights,2) == 1, ...
            'nm2dx:multiOutputNotSupported', 'Only single-output MVTRVR is admitted.');
        assert(numel(model.rv) == numel(model.weights), ...
            'nm2dx:kernelTrainAxis', 'MVTRVR weights and relevance indices differ in length.');
        b = 0;
        w = trainZ(model.rv,:)' * model.weights(:);
        domain = 'mvtrvr_linear_regression_primal';
    otherwise
        error('nm2dx:unsupportedLearner', ...
            'No source-verified exact affine Dx contract for learner %s.', learner);
end
assert(size(Z,2) == numel(w), ...
    'nm2dx:coordinateMismatch', 'Held-out feature axis does not match fitted coefficient axis.');
assert(isscalar(b) && isfinite(b) && all(isfinite(w)) && all(isfinite(Z(:))), ...
    'nm2dx:nonfinite', 'Model coefficients, intercept and coordinates must be finite.');

D = Z .* reshape(w,1,[]);
raw = b + sum(D,2);
out = struct('learner',learner, 'domain',domain, 'contributions',D, ...
    'intercept',b, 'weights',w, 'rawScore',raw);
end

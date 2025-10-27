function [algostr, probflag] = determine_probflag(SVM)

probflag = false;
switch SVM.prog
    case {'MikSVM','MKLRVM'}
            algostr = 'RVM probability';
            probflag = true;
    case 'LIBSVM'
        if SVM.LIBSVM.Optimization.b
            algostr = 'SVM probability [Platt''s method]';
            probflag = true;
        elseif isfield(SVM,'BBQ') && SVM.BBQ.flag==1
            algostr = 'SVM probability [Bayesian Binning into Quantiles]';
            probflag = true;
        else
            algostr = 'SVM decision score';
        end
    case 'MVTRVR'
        algostr = 'RVR score';
        probflag = true;
    case 'MEXELM'
        algostr = 'ELM score';
        probflag = true;
    case 'LIBLIN'
        switch SVM.LIBLIN.classifier
            case {0,6}
                algostr = 'LR';
            otherwise
                algostr = 'SVM';
        end
        switch SVM.LIBLIN.b
            case 0
                algostr = [algostr ' Score'];
            case 1
                algostr = [algostr ' Probability'];
                probflag = true;
        end
    case 'matLRN'
        algostr = sprintf('matLearn algorithm [ %s ]',char(SVM.matLRN.algo));
    case 'RNDFOR'
        algostr = 'Random Forest [ probability ]';
        probflag = true;
    case 'GRDBST'
        algostr = 'Gradient Boosting [ probability ]';
        probflag = true;
    case 'GLMNET'
        algostr = 'Elastic net logistic regression [ probability ]';
        probflag = true;
    case 'ELASVM'
        algostr = 'Support vector elastic net [ probability ]';
        probflag = true;
    case 'MLPERC'
        algostr = 'Multi-layer perceptron [ probability ]';
        probflag = true;

    case 'BAYLIN'
        algostr = 'Bayesian ridge [ probability ]';
        probflag = true;

    case 'TFDEEP'
        algostr = 'Tensorflow neural [ probability ]';
        probflag = true;
    case 'GLMFIT'
        algostr = 'Univariate logistic regression [ probability ]';
        probflag = true;
    case 'SEQOPT'
        algostr = 'Sequential optiimization algorithm [ score ]';
    case 'kNNMEX'
        algostr = 'k-Nearest Neighbor classifier [ score ]';
    case 'BLOREG'
        algostr = 'Bayesian Sparse Logistic Regression [ probability ]';
        probflag = true;
    case 'WBLCOX'
        algostr = sprintf('Willbur-Cox proportional hazards model: predicted risk');
        probflag = true;
    otherwise
        algostr = [SVM.prog ' score'];
end
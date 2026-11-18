classdef NMLearnerLibrary
% NMLearnerLibrary
% -------------------------------------------------------------------------
% Compact learner metadata and legacy-default source for the modular ML port.
% This file intentionally keeps learner defaults, kernel defaults, and legacy
% grid-field names in one auditable place. It does not call interactive legacy
% configurators and it does not change nk_Model_config/nk_Grid_config.
% -------------------------------------------------------------------------

    methods (Static)

        function mode = taskMode(ctx)
        % taskMode  Resolve the active NeuroMiner learning task mode from a context struct.
        %   Accepts lightweight ctx, ctx.taskMode, ctx.modeflag, or ctx.NM.modeflag forms and
        %   returns the string used by learner/default factories to branch between classification
        %   and regression without requiring the full NM project struct.
            %
            % ctx.taskMode: explicit task-mode string used first when ctx.modeflag is absent.
            % ctx.modeflag: NeuroMiner task-mode flag, usually classification or regression.
            % ctx.NM: optional NM struct whose NM.modeflag is used when no direct context mode is supplied.

            mode = 'classification';
            if nargin < 1 || isempty(ctx), return; end
            if isstruct(ctx)
                if isfield(ctx,'modeflag') && ~isempty(ctx.modeflag)
                    mode = char(ctx.modeflag); return;
                end
                if isfield(ctx,'taskMode') && ~isempty(ctx.taskMode)
                    mode = char(ctx.taskMode); return;
                end
                if isfield(ctx,'NM') && isstruct(ctx.NM) && isfield(ctx.NM,'modeflag') && ~isempty(ctx.NM.modeflag)
                    mode = char(ctx.NM.modeflag); return;
                end
            end
        end

        function gp = defaultGridParam(mode)
        % defaultGridParam  Return the default legacy SVM.GridParam criterion for a task mode.
        %   Maps classification to accuracy-like GridParam=1 and regression to MAE GridParam=18;
        %   downstream defaultConfig and model-selection defaults use this code when no user
        %   criterion has been selected.

            if nargin < 1 || isempty(mode), mode = 'classification'; end
            if strcmpi(mode,'regression')
                gp = 18;
            else
                gp = 1;
            end
        end

        function ids = ids(ctx)
        % ids  List learner identifiers available for the resolved task mode.
        %   Returns canonical legacy/program ids used by UI enums, default-state generation, and
        %   validation. Regression excludes classifiers that have no supported regression backend.

            if nargin < 1, ctx = struct(); end
            mode = NMLearnerLibrary.taskMode(ctx);
            switch lower(mode)
                case 'regression'
                    ids = {'LIBSVM','LIBLIN','MikRVM','MVTRVR','BAYLIN','GLMFIT', ...
                           'RNDFOR','matLRN','GLMNET','GRDBST','MLPERC','TFDEEP','WBLCOX'};
                otherwise
                    ids = {'LIBSVM','LIBLIN','ELASVM','MEXELM','MikRVM','MKLRVM','MVTRVR', ...
                           'BLOREG','BAYLIN','kNNMEX','IMRELF','GLMFIT','DECTRE', ...
                           'RNDFOR','matLRN','GLMNET','GRDBST','MLPERC','TFDEEP','ROBSVM','SEQOPT','WBLCOX'};
            end
        end

        function vals = enumValues(ctx)
        % enumValues  Convert task-mode learner identifiers into UI/RAG enum records.
        %   Each cell contains value/label fields; labels are produced by title() while values remain
        %   the canonical ids expected by NMMLModule.toLegacy and TrainParam.SVM.prog.

            ids = NMLearnerLibrary.ids(ctx);
            vals = cell(size(ids));
            for i = 1:numel(ids)
                vals{i} = struct('value',ids{i},'label',NMLearnerLibrary.title(ids{i}));
            end
        end

        function title = title(algorithm)
        % title  Return a readable learner label for a legacy or modular learner id.
        %   Used by schemas, UI selectors, and documentation extraction; unknown ids are preserved
        %   verbatim rather than rejected so imported legacy configurations remain inspectable.

            alg = char(algorithm);
            switch upper(alg)
                case 'LIBSVM', title = 'LIBSVM';
                case 'LIBLIN', title = 'LIBLINEAR';
                case 'GLMNET', title = 'GLMNET elastic-net GLM';
                case 'GRDBST', title = 'Gradient boosting';
                case 'RNDFOR', title = 'Random forest';
                case 'MLPERC', title = 'scikit-learn MLP';
                case 'TFDEEP', title = 'TensorFlow/PyTorch deep network';
                case 'BAYLIN', title = 'Bayesian/ARD linear model';
                case 'DECTRE', title = 'Decision tree';
                case 'KNNMEX', title = 'k-nearest neighbours';
                case 'GLMFIT', title = 'MATLAB GLM fit';
                case 'IMRELF', title = 'IMRelief';
                case 'MIKRVM', title = 'Sparse Bayesian RVM';
                case 'MKLRVM', title = 'Multiple-kernel RVM';
                case 'MVTRVR', title = 'Multivariate relevance-vector regression';
                case 'MEXELM', title = 'Extreme learning machine';
                case 'BLOREG', title = 'Bayesian logistic regression';
                case 'SEQOPT', title = 'Sequential optimization';
                case 'WBLCOX', title = 'Weibull-Cox proportional hazards';
                case 'MATLRN', title = 'matLearn learner';
                otherwise, title = alg;
            end
        end

        function tf = isModernParamLearner(algorithm)
        % isModernParamLearner  Identify learners whose trainable options are stored as Params arrays.
        %   The result steers NMLearnerSchemaRegistry and NMMLModule toward learner-specific option
        %   schemas instead of the older flat-GRD hyperparameter shelves.

            tf = any(strcmpi(char(algorithm), {'GLMNET','GRDBST','ROBSVM','ELASVM','MLPERC','TFDEEP','BAYLIN'}));
        end

        function tf = usesKernel(algorithm)
        % usesKernel  Report whether a learner exposes kernel settings in the modular ML schema.
        %   Non-kernel algorithms are hidden from kernel UI sections and exported without kernel-range
        %   shelves, while legacy kernel-capable learners retain their SVM.kernel contract.

            tf = ~any(strcmpi(char(algorithm), {'IMRELF','kNNMEX','LIBLIN','ROBSVM','GLMFIT','MEXELM', ...
                 'DECTRE','RNDFOR','GLMNET','GRDBST','SEQOPT','WBLCOX','ELASVM','MLPERC','TFDEEP','BAYLIN'}));
        end

        function cfg = defaultConfig(algorithm, ctx)
        % defaultConfig  Build the canonical modular ML configuration for one learner.
        %   This is the main default factory used by NMMLModule, UI initialization, and scripted API
        %   calls; it materializes algorithm, criterion, fixed settings, kernel settings, hyperparameter
        %   shelves, optimizer settings, model-selection settings, post-processing flags, and raw
        %   legacy-preservation fields without mutating NM.

            if nargin < 1 || isempty(algorithm), algorithm = 'LIBSVM'; end
            if nargin < 2, ctx = struct(); end
            mode = NMLearnerLibrary.taskMode(ctx);
            cfg = struct();
            cfg.algorithm = NMLearnerLibrary.canonicalId(algorithm);
            cfg.performanceCriterion = NMLearnerLibrary.defaultGridParam(mode);
            cfg.fixedSettings = NMLearnerLibrary.defaultFixedSettings(cfg.algorithm, mode, ctx);
            cfg.kernelSettings = NMLearnerLibrary.defaultKernelSettings(cfg.algorithm, mode);
            cfg.hyperparameters = NMLearnerLibrary.defaultHyperparameters(cfg.algorithm, mode);
            cfg.optimizationSettings = NMLearnerLibrary.defaultOptimizationSettings();
            cfg.modelSelectionSettings = NMLearnerLibrary.defaultModelSelectionSettings(cfg.performanceCriterion);
            cfg.postProcessingSettings = struct('detrendOrThresholdOptimization', false);
            cfg.legacySVM = struct();
            cfg.legacyGRD = struct();
        end

        function alg = canonicalId(algorithm)
        % canonicalId  Normalize learner identifiers while preserving recognized legacy spelling.
        %   Performs case-insensitive matching against supported ids and returns the canonical token
        %   used in SVM.prog, schema maps, and switch branches; unknown tokens pass through unchanged
        %   for round-trip compatibility with imported projects.

            alg0 = strtrim(char(algorithm));
            ids = {'LIBSVM','LIBLIN','ELASVM','MEXELM','MKLRVM','MVTRVR','BLOREG','BAYLIN', ...
                   'kNNMEX','IMRELF','GLMFIT','DECTRE','RNDFOR','matLRN','GLMNET','GRDBST', ...
                   'MLPERC','TFDEEP','ROBSVM','MikRVM','SEQOPT','WBLCOX'};
            alg = alg0;
            for i = 1:numel(ids)
                if strcmpi(alg0, ids{i}), alg = ids{i}; return; end
            end
        end

        function fixed = defaultFixedSettings(algorithm, mode, ctx)
            % defaultFixedSettings  Return non-optimized learner settings for the canonical ML config.
            %
            % These defaults populate cfg.fixedSettings and later export to learner-specific SVM fields
            % such as SVM.LIBSVM, SVM.LIBLIN, SVM.RVM, SVM.SEQOPT, or SVM.WBLCOX. Context-dependent
            % defaults, for example survival interval timing, are resolved here.
            %
            % ctx.NM: provides the current NeuroMiner structure to preprocessing execution helpers without direct global access.
            % ctx.time: exposes the time execution-context value to preprocessing/runtime code.

            if nargin < 2 || isempty(mode), mode = 'classification'; end
            if nargin < 3, ctx = struct(); end
            alg = NMLearnerLibrary.canonicalId(algorithm);
            fixed = struct();
            switch alg
                case 'LIBSVM'
                    if strcmpi(mode,'regression'), classifier = 3; else, classifier = 0; end
                    fixed.LIBSVMver = 0;
                    fixed.classifier = classifier;
                    fixed.Optimization = struct('b',0,'m',500,'e',0.001,'h',1,'nu',0.5,'p',0.8);
                    fixed.Weighting = 0;
                    fixed.quiet = '';
                case 'LIBLIN'
                    if strcmpi(mode,'regression'), classifier = 11; else, classifier = 0; end
                    fixed.classifier = classifier;
                    fixed.Weighting = 0;
                    fixed.b = 0;
                    fixed.tolerance = 0.01;
                    fixed.quiet = 1;
                    fixed.bias = -1;
                    fixed.NonRegBias = false;
                    fixed.AutoC = false;
                case 'GLMNET'
                    if strcmpi(mode,'regression'), fixed.family = 'gaussian'; else, fixed.family = 'binomial'; end
                case 'DECTRE'
                    fixed = struct();
                case 'RNDFOR'
                    fixed = struct();
                case 'matLRN'
                    fw = NMLearnerSchemaRegistry.matLearnFramework(mode);
                    fixed = struct();
                    fixed.learner = struct('framework', fw, 'options', struct());
                    fixed.algo = NMLearnerSchemaRegistry.defaultMatLearnAlgorithm(mode);
                case 'MikRVM'
                    fixed = struct('UserOpt', [], 'ParamSet', [], 'LikelihoodModel', 'GAUSS');
                case 'MKLRVM'
                    fixed = struct('converg',1,'funcname_learn','train_mRVM1', ...
                        'funcname_predict','predict_mRVM','plot_flag',0,'standardize_flag',1, ...
                        'nmax',[],'RVMalgo','RVM1');
                case 'MVTRVR'
                    fixed.iter = 20;
                case 'SEQOPT'
                    % A one-row default sequence keeps the optimizer-facing
                    % parameter shelf structurally defined. Real legacy
                    % imports preserve user-defined SVM.SEQOPT.C.
                    fixed.C = 1;
                    fixed.PerfMode = 1;
                    fixed.AnchorType = 1;
                    fixed.ReplaceMode = 1;
                    fixed.Mode = 1;
                case 'WBLCOX'
                    interval = 1;
                    if isstruct(ctx) && isfield(ctx,'NM') && isstruct(ctx.NM) && isfield(ctx.NM,'time') && ~isempty(ctx.NM.time)
                        try, interval = median(ctx.NM.time); catch, interval = 1; end
                    elseif isstruct(ctx) && isfield(ctx,'time') && ~isempty(ctx.time)
                        try, interval = median(ctx.time); catch, interval = 1; end
                    end
                    fixed.interval = interval;
                    fixed.predict_time = false;
                    fixed.MaxIter = 1000;
                    fixed.MaxFunEvals = 1000;
                    fixed.TolX = 1e-05;
                    fixed.TolFun = 1e-05;
                    fixed.Algorithm = 'sqp';
                otherwise
                    fixed = struct();
            end
        end

        function kernel = defaultKernelSettings(algorithm, mode) %#ok<INUSD>
        % defaultKernelSettings  Return the default kernel descriptor for a learner.
        %   Supplies SVM.kernel-compatible fields for kernel-capable legacy backends and a neutral
        %   linear/no-kernel descriptor for algorithms that need the field only for compatibility.

            alg = NMLearnerLibrary.canonicalId(algorithm);
            if strcmp(alg,'LIBSVM')
                kernel = struct('kerndef',1,'kernstr',' -t 0','kerndesc','Linear');
            elseif any(strcmp(alg, {'MikRVM','MKLRVM','MVTRVR'}))
                kernel = struct('kerndef',1,'kernstr','lin','kerndesc','Linear');
            elseif strcmp(alg,'MEXELM')
                kernel = struct('kerndef',1,'kernstr','lin_elm','kerndesc','linear');
            else
                kernel = struct('kerndef',1,'kernstr','lin','kerndesc','No Kernel');
            end
        end

        function hp = defaultHyperparameters(algorithm, mode)
        % defaultHyperparameters  Build the default trainable hyperparameter shelves for a learner.
        %   Combines legacy flat-GRD ranges, random-forest and special-learner ranges, and modern
        %   Params-array schemas from NMLearnerSchemaRegistry. The result feeds cfg.hyperparameters
        %   and is exported by NMMLModule.toLegacy into GRD.* fields.

            alg = NMLearnerLibrary.canonicalId(algorithm);
            hp = struct();
            switch lower(mode)
                case 'regression'
                    hp.Cparams = 2.^(-6:1:0);
                otherwise
                    hp.Cparams = 2.^(-6:1:4);
            end
            hp.Gparams = 2.^(-15:2:3);
            hp.Epsparams = [0.05 0.075 0.1 0.125 0.15 0.2];
            hp.Nuparams = [0.2 0.5 0.7];
            hp.Tolparams = [1e-6 1e-5 1e-4 1e-3 1e-2];
            hp.PolyCoefparams = 0;
            hp.PolyDegrparams = 3;
            hp.WLiters = [2 4 6 8 10];
            hp.Neuronparams = [25 50 75 100];
            hp.Kparams = 7;
            hp.Weightparams = 1;
            hp.Leafparams = logspace(1,2,10);
            hp.Treeparams = 100;
            hp.NumDparams = -1;
            hp.RFCritdefsparams = 1;
            if strcmpi(mode,'regression'), hp.RFMaxDparams = 1.0; else, hp.RFMaxDparams = 0; end
            hp.RFMinSSplitparams = 2;
            hp.RFMinSLeafparams = 1;
            hp.RFMinWFLeafparams = 0.0;
            hp.RFMaxLeafNparams = 0;
            hp.RFMinImpDecrparams = 0.0;
            hp.RFBootstrapparams = 1;
            hp.RFOobScoreparams = 0;
            if strcmpi(mode,'classification'), hp.RFClassWeightparams = 0; end
            hp.RFCcpAlphaparams = 0.0;
            hp.RFMaxSampparams = 0;
            hp.CutOffparams = 10;
            hp.LimsLparams = 50;
            hp.LimsUparams = 50;
            hp.CoxCutoffparams = 20:10:80;
            hp.learnerParams = struct('name',{},'range',{});
            hp.learnerOptions = struct();

            if strcmp(alg,'IMRELF')
                hp.Cparams = [0.5 1 2 4 8 16 32];
                hp.Gparams = [0.5 .1 0.05 0.01 0.005 0.001];
            end

            if strcmp(alg,'matLRN')
                hp.learnerParams = NMLearnerSchemaRegistry.defaultParamsForMatLearn(mode);
                hp.learnerOptions = struct();
            elseif NMLearnerLibrary.isModernParamLearner(alg)
                hp.learnerParams = NMLearnerSchemaRegistry.defaultParamsForCoreLearner(alg, mode);
                param = NMLearnerLibrary.legacyLearnerParamDefaults(alg, mode);
                if isfield(param,'options'), hp.learnerOptions = param.options; end
                if isfield(param,'learner') && isfield(param.learner,'options')
                    hp.learnerOptions = param.learner.options;
                end
            else
                hp.learnerParams = NMLearnerSchemaRegistry.defaultParamsForFlatGRD(alg, mode);
                hp.learnerOptions = struct();
            end
        end

        function opt = defaultOptimizationSettings()
        % defaultOptimizationSettings  Return backend-compatible hyperparameter optimizer defaults.
        %   Provides brute-force, simulated-annealing, and Bayesian option structs, including legacy
        %   alias fields that NMMLModule.normalizeOptMode and optimizer dry-run checks expect.

            opt = struct();
            opt.type = 'brute-force';
            opt.SimAneal = struct('T', 1, 'max_initial_jump', 10, 'alpha', 0.95, ...
                'random_jump_prob', 0.2, 'max_iter', 100, 'reheating_iter', 10, 'reheating_alpha', 1.2);
            opt.SimAnneal = opt.SimAneal;
            opt.Bayes = struct('max_iter', 100, 'max_iter_no_change', 25, 'num_seed', 100, ...
                'mode', 'lcb', 'CritMode', 'lcb', 'LCBkappa', 2, 'EIjitter', 1e-6, ...
                'kappa', 2, 'ei_jitter', 1e-6, 'kernel_function', 'squaredexponential');
        end

        function ns = defaultModelSelectionSettings(gridParam)
        % defaultModelSelectionSettings  Return cross-parameter model-selection defaults.
        %   Initializes GridMaxType, NodeSelect, and OptRegul fields for GRD export; the default
        %   percentile direction is adjusted when the chosen GridParam is a lower-is-better criterion.

            if nargin < 1, gridParam = 1; end
            ns = struct();
            ns.GridMaxType = 1;
            ns.NodeSelect = struct('mode',1,'perc',95,'percvec',75:5:95);
            ns.OptRegul = struct('flag',0,'type',1,'lambda',1,'big_gamma',0.5, ...
                'RegulTypeComplexity', struct('type',1), 'RegulTypeDiversity', struct('type',1));
            if NMLearnerLibrary.isLowerBetter(gridParam)
                ns.NodeSelect.perc = 5;
                ns.NodeSelect.percvec = 5:5:25;
            end
        end

        function tf = isLowerBetter(gridParam)
        % isLowerBetter  Identify legacy GridParam criteria optimized by minimization.
        %   Criterion direction is read from criterionCatalog, the single authority shared with the UI.

            tf = false;
            if ~isnumeric(gridParam) || ~isscalar(gridParam) || ~isfinite(gridParam), return; end
            catalog = NMLearnerLibrary.criterionCatalog();
            idx = find([catalog.code] == double(gridParam), 1, 'first');
            if ~isempty(idx), tf = strcmp(catalog(idx).direction, 'minimize'); end
        end

        function catalog = criterionCatalog()
        % criterionCatalog  Define GridParam identity, task mode, direction and Results Viewer display metadata.
        %   This metadata is the single current authority for criterion selectors, validation,
        %   model-selection direction and criterion presentation. Fixed display domains reproduce
        %   nk_GetScaleYAxisLabel; target-dependent MSE/MAE maxima remain nonnegative/data-scaled.

            rows = { ...
                1,'Accuracy','classification','maximize','Accuracy [%]','ACCURACY','bounded',0,100,NaN,'','acc'; ...
                2,'True positive rate','classification','maximize','Sensitivity [%]','SENSITIVITY','bounded',0,100,NaN,'','sens'; ...
                3,'Specificity','classification','maximize','Specificity [%]','SPECIFICITY','bounded',0,100,NaN,'','spec'; ...
                4,'False positive rate','classification','minimize','False Positive Rate [%]','FPR','bounded',0,100,NaN,'','FPR'; ...
                5,'Positive predictive value','classification','maximize','Positive Predictive Value [%]','PPV','bounded',0,100,NaN,'','PPV'; ...
                6,'Matthews correlation coefficient','classification','maximize','Matthews Correlation Coefficient','MCC','bounded',-1,1,0,'Neutral','MCC'; ...
                7,'Area under the curve','classification','maximize','Area-Under-the-Curve','AUC','bounded',0,1,0.5,'Chance','AUC'; ...
                13,'Geometric mean','classification','maximize','Gmean','GMEAN','bounded',0,1,NaN,'','GMean'; ...
                14,'Balanced accuracy','classification','maximize','Balanced Accuracy [%]','BAC','bounded',0,100,50,'Chance','BAC'; ...
                15,'F-score','classification','maximize','F1-Score','FSCORE','bounded',0,100,NaN,'','Fscore'; ...
                17,'Enhanced balanced accuracy','classification','maximize','Enhanced Balanced Accuracy [%]','BAC2','bounded',0,100,50,'Chance',''; ...
                19,'Prognostic Summary Index','classification','maximize','Prognostic Summary Index [%]','PSI','bounded',-100,100,0,'Neutral','PSI'; ...
                20,'Number Needed to Predict','classification','minimize','Number Needed to Predict','NNP','bounded',0,10,NaN,'','NNP'; ...
                21,'Expected Calibration Error','classification','minimize','Expected Calibration Error','ECE','bounded',0,1,NaN,'','ECE'; ...
                22,'Positive Likelihood Ratio','classification','maximize','Positive Likelihood Ratio','pLR','bounded',0,15,NaN,'','pLR'; ...
                23,'Negative Likelihood Ratio','classification','minimize','Negative Likelihood Ratio','nLR','bounded',0,1,NaN,'','nLR'; ...
                9,'Mean Squared Error','regression','minimize','Mean squared error','MSE','nonnegative',0,NaN,NaN,'','MSE'; ...
                10,'Squared correlation coefficient (R^2)','regression','maximize','Squared correlation coefficient [% explained variance]','SCC','bounded',0,100,NaN,'',''; ...
                11,'Normalized RMSD','regression','minimize','Normalized root of mean squared deviation [%]','NRMSD','bounded',0,100,NaN,'','NRMSD'; ...
                12,'RMSD','regression','minimize','Root of mean squared deviation','RMSD','bounded',0,1,NaN,'',''; ...
                16,'Pearson correlation coefficient (R)','regression','maximize','correlation coefficient','CC','bounded',-1,1,0,'Neutral','r'; ...
                18,'Mean absolute error','regression','minimize','Mean Average Error [Label Range]','MAE','nonnegative',0,NaN,NaN,'','MAE'; ...
                24,'Tail-weighted MSE','regression','minimize','Tail-weighted Mean squared error','MSEINVDENS','bounded',0,1,NaN,'',''};
            catalog = struct('code',{},'label',{},'mode',{},'direction',{},'displayLabel',{},'shortLabel',{}, ...
                'scaleMode',{},'scaleMinimum',{},'scaleMaximum',{},'referenceValue',{},'referenceLabel',{},'metricId',{});
            for i = 1:size(rows,1)
                catalog(i) = struct('code',rows{i,1},'label',rows{i,2},'mode',rows{i,3},'direction',rows{i,4}, ...
                    'displayLabel',rows{i,5},'shortLabel',rows{i,6},'scaleMode',rows{i,7}, ...
                    'scaleMinimum',rows{i,8},'scaleMaximum',rows{i,9},'referenceValue',rows{i,10},'referenceLabel',rows{i,11},'metricId',rows{i,12}); %#ok<AGROW>
            end
        end

        function vals = evalCriterionValues(mode)
        % evalCriterionValues  Return task-mode-specific GridParam selector values.
        %   Produces value/label records for classification or regression criteria. The numeric values
        %   are the legacy SVM.GridParam codes consumed by nk_Grid_config and model optimization.

            if nargin < 1 || isempty(mode), mode = 'classification'; end
            catalog = NMLearnerLibrary.criterionCatalog();
            catalog = catalog(strcmpi({catalog.mode}, char(mode)));
            vals = cell(numel(catalog),1);
            for i = 1:numel(catalog)
                vals{i} = struct('value',catalog(i).code,'label',catalog(i).label, ...
                    'direction',catalog(i).direction,'symbol',catalog(i).shortLabel);
            end
        end

        function vals = nodeSelectionValues()
        % Canonical model-selection values, labels and symbolic API tokens.
            rows = { ...
                1,'Single optimum model','single_optimum'; ...
                2,'Aggregate models above/below percentile','fixed_percentile'; ...
                4,'Variable-threshold percentile ensemble','variable_percentile'};
            vals = cell(size(rows,1),1);
            for k = 1:size(rows,1)
                vals{k} = struct('value',rows{k,1},'label',rows{k,2},'symbol',rows{k,3});
            end
        end

        function code = symbolicValue(value, choices)
        % Interpret one symbolic setting from its existing labelled choice records.
            code = value;
            switch class(value)
                case {'char','string'}
                    entries = [choices{:}];
                    idx = find(strcmp(char(value),{entries.symbol}),1);
                    if isempty(idx)
                        error('NMMLModule:invalidConfig','Invalid categorical symbol "%s".',char(value));
                    end
                    code = entries(idx).value;
            end
        end

        function vals = enumFromPairs(pairs)
        % enumFromPairs  Convert two-column value/label pairs into UI enum cell records.
        %   Small serialization helper used throughout the ML metadata layer; it preserves numeric
        %   and string values so the browser state can round-trip to legacy backend codes.

            vals = cell(size(pairs,1),1);
            for i = 1:size(pairs,1)
                vals{i} = struct('value',pairs{i,1},'label',pairs{i,2});
                if size(pairs,2)==3, vals{i}.symbol = pairs{i,3}; end
            end
        end

        function vals = libsvmClassifierValues(mode)
        % libsvmClassifierValues  Return LIBSVM classifier/regressor type choices for a task mode.
        %   The values are legacy LIBSVM type codes stored under cfg.fixedSettings.classifier and
        %   exported to SVM.LIBSVM.classifier.

            if strcmpi(mode,'regression')
                vals = NMLearnerLibrary.enumFromPairs({3,'epsilon-SVR','epsilon_svr';4,'nu-SVR','nu_svr'});
            else
                vals = NMLearnerLibrary.enumFromPairs({0,'C-SVC','c_svc';1,'nu-SVC','nu_svc';2,'one-class SVM','one_class_svm';3,'one-class / legacy variant','one_class_legacy'});
            end
        end

        function vals = liblinClassifierValues(mode)
        % liblinClassifierValues  Return LIBLINEAR classifier/regressor type choices for a task mode.
        %   The values are legacy LIBLINEAR solver codes used in cfg.fixedSettings.classifier and
        %   exported to SVM.LIBLIN.classifier.

            if strcmpi(mode,'regression')
                vals = NMLearnerLibrary.enumFromPairs({11,'L2-loss epsilon SVR (primal)','l2_epsilon_svr_primal';12,'L2-loss epsilon SVR (dual)','l2_epsilon_svr_dual';13,'L1-loss epsilon SVR (dual)','l1_epsilon_svr_dual'});
            else
                vals = NMLearnerLibrary.enumFromPairs({0,'L2 logistic regression (primal)','l2_logreg_primal';1,'L2-loss SVC (dual)','l2_svc_dual';2,'L2-loss SVC (primal)','l2_svc_primal';3,'L1-loss SVC (dual)','l1_svc_dual';5,'L1-regularized L2-loss SVC','l1_regularized_l2_svc';6,'L1-regularized logistic regression','l1_logreg';7,'L2 logistic regression (dual)','l2_logreg_dual'});
            end
        end

        function values = learnerFixedChoices(algorithm,mode)
        % Categorical fixed-learner settings: canonical symbolic API and UI metadata.
            switch NMLearnerLibrary.canonicalId(algorithm)
                case 'LIBSVM'
                    values = struct( ...
                        'LIBSVMver',{NMLearnerLibrary.enumFromPairs({ ...
                            0,'LIBSVM 3.12','libsvm_3_12';1,'LIBSVM 2.9.1','libsvm_2_9_1'; ...
                            2,'LIBSVM 2.89','libsvm_2_89';3,'LIBSVM 2.89 PLUS','libsvm_2_89_plus'})}, ...
                        'classifier',{NMLearnerLibrary.libsvmClassifierValues(mode)});
                case 'LIBLIN'
                    values = struct( ...
                        'classifier',{NMLearnerLibrary.liblinClassifierValues(mode)}, ...
                        'bias',{NMLearnerLibrary.enumFromPairs({-1,'No','no_bias';1,'Yes','bias'})});
                case 'MKLRVM'
                    values = struct('converg',{NMLearnerLibrary.enumFromPairs({ ...
                        1,'Trivial change in hyperpriors','hyperpriors'; ...
                        2,'Trivial change + minimum iterations','hyperpriors_min_iterations'; ...
                        3,'Maximum iterations','max_iterations'})});
                case 'SEQOPT'
                    values = struct( ...
                        'Mode',{NMLearnerLibrary.enumFromPairs({1,'The sample to be deferred','sample_to_defer';2,'The entire population','whole_population'})}, ...
                        'ReplaceMode',{NMLearnerLibrary.enumFromPairs({1,'Sequential replacement','sequential_replacement';2,'Integrative mean across deferral nodes','integrative_mean'})}, ...
                        'AnchorType',{NMLearnerLibrary.enumFromPairs({1,'Decision boundary','decision_boundary';2,'Median decision score','median_score'})}, ...
                        'PerfMode',{NMLearnerLibrary.enumFromPairs({1,'Current optimization criterion','criterion';2,'Mean decision distance between classes','decision_distance'})});
                otherwise
                    values = struct();
            end
        end

        function vals = glmnetFamilyValues(mode)
        % glmnetFamilyValues  Return GLMNET family choices for classification or regression.
        %   Used by the learner settings section to constrain cfg.fixedSettings.family before export
        %   to SVM.GLMNET.family.

            if strcmpi(mode,'regression')
                vals = NMLearnerLibrary.enumFromPairs({'gaussian','Gaussian';'poisson','Poisson';'cox','Cox'});
            else
                vals = NMLearnerLibrary.enumFromPairs({'binomial','Binomial';'multinomial','Multinomial'});
            end
        end

        function ids = kernelLearnerIds()
        % kernelLearnerIds  List learners for which kernel controls may be shown.
        %   NMMLModule.uiFields uses this list as a visibility gate for SVM.kernel settings and
        %   downstream kernel-dependent hyperparameter shelves.

            ids = {'LIBSVM','ROBSVM','MikRVM','FAMRVR','MKLRVM','MVTRVR','LSTSVM','BLOREG','MEXELM'};
        end

        function vals = kernelValues(algorithm)
        % kernelValues  Return algorithm-specific kernel selector records.
        %   Encodes the legacy kernel strings used by LIBSVM/RVM-style backends and provides the
        %   labels shown in the modular ML UI; unknown kernel-capable learners fall back to the
        %   LIBSVM-style kernel string convention.

            alg = NMLearnerLibrary.canonicalId(algorithm);
            switch alg
                case {'MikRVM','FAMRVR'}
                    vals = NMLearnerLibrary.enumFromPairs({'lin','Linear','linear';'rbf','Gaussian','rbf';'expo','Exponential','exponential';'laplace','Laplacian','laplacian';'polyN','Polynomial of order N','polynomial_n';'hpolyN','Homogeneous polynomial of order N','homogeneous_polynomial_n';'spline','Linear spline','linear_spline';'cauchy','Cauchy','cauchy';'cubic','Cubic','cubic';'r','Distance','distance';'tps','Thin plate spline','thin_plate_spline';'bubble','Neighbourhood indicator','neighborhood_indicator'});
                case {'MKLRVM','MVTRVR'}
                    vals = NMLearnerLibrary.enumFromPairs({'lin','Linear','linear';'poly','Polynomial','polynomial';'rbf','RBF/Gaussian','rbf'});
                case 'BLOREG'
                    vals = NMLearnerLibrary.enumFromPairs({'none','No kernel','none';'lin','Linear','linear'});
                case 'MEXELM'
                    vals = NMLearnerLibrary.enumFromPairs({'lin_elm','Linear ELM','linear'});
                otherwise
                    vals = NMLearnerLibrary.enumFromPairs({' -t 0','Linear','linear';' -t 1','Polynomial','polynomial';' -t 2','RBF/Gaussian','rbf';' -t 3','Sigmoid','sigmoid';' -t 4','Graph/custom kernel','graph_custom';' -t 6','Laplacian','laplacian';' -t 7','Exponential','exponential'});
            end
        end

        function value = kernelValue(algorithm, selected)
        % kernelValue  Translate a documented kernel symbol to its backend selector.
            values = NMLearnerLibrary.kernelValues(algorithm);
            entries = [values{:}];
            names = {entries.symbol};
            legacy = {entries.value};
            ix = find(strcmp(selected,names));
            if isempty(ix), ix = find(strcmp(selected,legacy)); end
            assert(isscalar(ix),'NMLearnerLibrary:kernelValue', ...
                'Kernel setting must match exactly one declared %s kernel.',algorithm);
            value = legacy{ix};
        end

        function symbol = kernelSymbol(algorithm, value)
        % kernelSymbol  Reverse-map the documented kernel selector for scripts.
            values = NMLearnerLibrary.kernelValues(algorithm);
            entries = [values{:}];
            ix = find(strcmp(value,{entries.value}));
            assert(isscalar(ix),'NMLearnerLibrary:kernelSymbol', ...
                'Kernel value is not declared for %s.',algorithm);
            symbol = entries(ix).symbol;
        end

        function param = legacyLearnerParamDefaults(algorithm, mode)
        % legacyLearnerParamDefaults  Obtain trainable option defaults from legacy learner configurators.
        %   When the corresponding nk_*_config function is on the MATLAB path, this method queries it
        %   in non-interactive/default mode; otherwise it falls back to local option definitions. It is
        %   the bridge from legacy option metadata to modular Params-array schemas.

            alg = NMLearnerLibrary.canonicalId(algorithm);
            param = struct();
            framework = mode;
            try
                switch alg
                    case {'GLMNET','GRDBST'}
                        if exist('nk_GLMNET_config','file') == 2
                            param = nk_GLMNET_config(alg, [], true, framework); return;
                        end
                    case 'MLPERC'
                        if exist('nk_MLPERC_config','file') == 2
                            param = nk_MLPERC_config(alg, [], true, framework); return;
                        end
                    case 'TFDEEP'
                        if exist('nk_TFDEEP_config','file') == 2
                            param = nk_TFDEEP_config(alg, [], true, framework); return;
                        end
                    case 'BAYLIN'
                        if exist('nk_BAYLIN_config','file') == 2
                            param = nk_BAYLIN_config(alg, [], true, framework); return;
                        end
                    case 'ROBSVM'
                        if exist('nk_ROBSVM_config','file') == 2
                            fw = framework;
                            if strcmpi(fw,'classification'), fw = 'binaryclass'; end
                            param = nk_ROBSVM_config(alg, [], fw, true); return;
                        end
                end
            catch ME
                warning('NMLearnerLibrary:legacyDefaultsFailed', ...
                    'Falling back to local defaults for %s: %s', alg, ME.message);
            end
            opt = NMLearnerLibrary.fallbackOptions(alg, framework);
            param.options = opt;
            param.Params = struct('name',{},'range',{});
            if ~isempty(opt) && isfield(opt,'name')
                for i = 1:numel(opt.name)
                    param.Params(i).name = opt.name{i}; %#ok<AGROW>
                    param.Params(i).range = opt.def{i}; %#ok<AGROW>
                end
            end
        end

        function opt = fallbackOptions(algorithm, framework)
        % fallbackOptions  Return local option metadata when legacy learner configurators are unavailable.
        %   Provides desc/format/sel/def/name arrays for modern learners so schema generation and
        %   scripted API defaults remain usable without launching or depending on interactive CLI code.

            alg = NMLearnerLibrary.canonicalId(algorithm);
            opt = struct('desc',{{}},'format',{{}},'sel',{{}},'def',{{}},'name',{{}});
            switch alg
                case 'GLMNET'
                    opt.desc = {'Define mixing factor alpha','Define minimum lambda','Define number of lambdas','Define max variables','Standardize input'};
                    opt.format = {'e','e','i','i','yes|no'};
                    opt.sel = {[],[],[],[],[1 0]};
                    opt.def = {0.5, 0.001, 100, Inf, 0};
                    opt.name = {'alpha','lambda_min','nlambda','dfmax','standardize'};
                case 'GRDBST'
                    opt.desc = {'Max boosting iterations','Loss','Learning rate','Subsampling factor','Max tree depth'};
                    if strcmpi(framework,'regression')
                        opt.sel = {[], {'squared_error','absolute_error','huber','quantile'}, [], [], []};
                        opt.def = {100, 'squared_error', 0.1, 1.0, 3};
                        opt.format = {'i','squared_error|absolute_error|huber|quantile','e','e','e'};
                    else
                        opt.sel = {[], {'log_loss','exponential'}, [], [], []};
                        opt.def = {100, 'log_loss', 0.1, 1.0, 3};
                        opt.format = {'i','log_loss|exponential','e','e','e'};
                    end
                    opt.name = {'maxIters','loss','learningRate','subsamplingFactor','maxTreeDepth'};
                case 'MLPERC'
                    opt.name = {'MLPERC_hidden_layer_sizes','MLPERC_activation','MLPERC_solver','MLPERC_alpha', ...
                        'MLPERC_batch_size','MLPERC_learning_rate','MLPERC_learning_rate_init','MLPERC_power_t', ...
                        'MLPERC_max_iter','MLPERC_random_state','MLPERC_tol','MLPERC_warm_start','MLPERC_momentum', ...
                        'MLPERC_nesterovs_momentum','MLPERC_early_stopping','MLPERC_validation_fraction', ...
                        'MLPERC_beta_1','MLPERC_beta_2','MLPERC_epsilon','MLPERC_n_iter_no_change','MLPERC_max_fun'};
                    opt.def = {[100,100],'relu','adam',0.0001,200,'constant',0.001,0.5,1000,45,1e-4,0,0.9,1,0,0.1,0.9,0.999,1e-8,10,15000};
                    opt.desc = opt.name; opt.format = repmat({'any'}, size(opt.name)); opt.sel = repmat({[]}, size(opt.name));
                case 'BAYLIN'
                    opt.name = {'BAYLIN_estimator','BAYLIN_n_iter','BAYLIN_tol','BAYLIN_alpha_1','BAYLIN_alpha_2', ...
                        'BAYLIN_lambda_1','BAYLIN_lambda_2','BAYLIN_fit_intercept','BAYLIN_compute_score','BAYLIN_threshold_lambda'};
                    opt.def = {'BayesianRidge',300,1e-3,1e-6,1e-6,1e-6,1e-6,1,0,1e4};
                    opt.desc = opt.name; opt.format = repmat({'any'}, size(opt.name)); opt.sel = repmat({[]}, size(opt.name));
                case 'TFDEEP'
                    opt.name = {'TFDEEP_hidden_layer_sizes','TFDEEP_framework','TFDEEP_activation','TFDEEP_solver', ...
                        'TFDEEP_alpha','TFDEEP_batch_size','TFDEEP_learning_rate_init','TFDEEP_max_iter', ...
                        'TFDEEP_random_state','TFDEEP_class_weighting','TFDEEP_early_stopping','TFDEEP_patience', ...
                        'TFDEEP_loss','TFDEEP_validation','TFDEEP_validation_fraction','TFDEEP_files'};
                    if strcmpi(framework,'regression'), loss = 'mean_squared_error'; else, loss = 'categorical_crossentropy'; end
                    opt.def = {[100,100],'tensorflow','relu','adam',0.0001,200,0.001,10,45,0,1,5,loss,1,0.1,'none'};
                    opt.desc = opt.name; opt.format = repmat({'any'}, size(opt.name)); opt.sel = repmat({[]}, size(opt.name));
                case 'ROBSVM'
                    opt.name = {'nsplit','wins','learner','cost','nu','epsilon','kernelFunc','kernelOptions'};
                    if strcmpi(framework,'regression'), learner = '-s 3'; else, learner = '-s 0'; end
                    opt.def = {3,4,learner,1,0.5,0.1,[],[]};
                    opt.desc = opt.name; opt.format = repmat({'any'}, size(opt.name)); opt.sel = repmat({[]}, size(opt.name));
                case 'ELASVM'
                    opt.name = {'L1-budget','lambda','Solver','epsilon'};
                    opt.def = {[1 2 4 8 16], [0.0625 0.125 0.25 0.5 1 2 4], 2, 0.01};
                    opt.desc = opt.name; opt.format = repmat({'any'}, size(opt.name)); opt.sel = repmat({[]}, size(opt.name));
            end
        end
    end
end

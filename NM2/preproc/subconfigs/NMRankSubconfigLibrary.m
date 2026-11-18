classdef NMRankSubconfigLibrary
% NMRankSubconfigLibrary
% -------------------------------------------------------------------------
% Schema and legacy mapping helpers for nested rankfeat algorithm
% configurators. The goal is to mirror nk_Rank_config and the algorithm-
% specific legacy configurators without flattening all options into the
% parent rankfeat page.
% -------------------------------------------------------------------------

    methods (Static)
        function specMap = specs(ctx)
            % specs  Return the nested subconfiguration schema map for supported methods.
            %   Used by parent modules, UI builders, and documentation extraction so method-specific
            %   options remain centralized in this library.

            if nargin < 1, ctx = struct(); end
            algs = NMRankSubconfigLibrary.algorithmIds();
            specMap = struct();
            for i = 1:numel(algs)
                specMap.(NMRankSubconfigLibrary.safeField(algs{i})) = NMRankSubconfigLibrary.spec(algs{i}, ctx);
            end
        end

        function ids = algorithmIds()
            % algorithmIds  Return supported feature-ranking algorithm identifiers.
            %   Used by rank-feature UI/API selectors and validation before nested algorithm
            %   defaults are requested.

            ids = {'pearson','spearman','gflip','simba','imrelief','idetect','relief', ...
                   'libsvm','liblin','fscore','auc','feast','anova','pls','rgs','varfeat','extern','extern2'};
        end

        function spec = spec(alg, ctx)
            % spec  Return the schema for one nested method/algorithm.
            %   The returned schema drives defaultParams, validateParams, UI rendering, and legacy
            %   conversion for the parent preprocessing module.

            if nargin < 2, ctx = struct(); end %#ok<INUSD>
            alg = lower(char(alg));
            spec = struct();
            spec.id = alg;
            spec.kind = 'rank-algorithm-subconfig';
            spec.title = NMRankSubconfigLibrary.title(alg);
            spec.description = NMRankSubconfigLibrary.description(alg);
            spec.fields = {};
            spec.cliConfigurator = '';
            spec.status = 'ported';

            switch alg
                case {'pearson','spearman','auc','anova','varfeat','extern','extern2'}
                    spec.fields = {};
                    spec.status = 'no-extra-parameters';

                case 'fscore'
                    spec.fields = { ...
                        struct('name','fscoreType','type','enum','default','mean','label','F-score computation method', ...
                            'values',{{'mean','median'}}, ...
                            'help','Choose mean/standard-deviation or median/interquartile-range scaling.'), ...
                        struct('name','weightMode','type','enum','default','none','label','Class-imbalance weighting mode', ...
                            'values',{{'none','auto','manual'}}, ...
                            'help','The old menu exposes none/auto, but keeps a manual branch in the code. The browser/API preserves manual as an explicit option.'), ...
                        struct('name','weightsVar','type','workspace_var','default','','label','Manual sample-weight vector', ...
                            'visibleIf',struct('field','weightMode','equals','manual'), ...
                            'workspaceFilter',struct('numericOnly',true,'columnVectorRowsFromContext','nSubjects'), ...
                    'help','Workspace vector of manual sample weights for the F-score procedure.'), ...
                        struct('name','bootstrapIterations','type','integer','default',0,'min',0,'label','Bootstrap iterations', ...
                    'help','Number of F-score bootstrap iterations; zero disables bootstrapping.')};

                case 'relief'
                    spec.fields = { ...
                        struct('name','k','type','numeric_vector','default',10,'label','Number(s) of nearest neighbours','allowEmpty',false, ...
                    'help','Nearest-neighbour count candidate(s) for the selected ranking method.')};

                case 'gflip'
                    spec.cliConfigurator = 'nk_Gflip_config';
                    spec.fields = { ...
                        struct('name','startPoints','type','integer','default',1,'min',1,'label','# starting points', ...
                    'help','Number of independent starting points for ranking optimization.'), ...
                        struct('name','maxIter','type','integer','default',5,'min',1,'label','Maximum # of iterations', ...
                    'help','Maximum number of ranking-optimization iterations.'), ...
                        struct('name','blockSize','type','integer','default',1,'min',1,'label','Block size', ...
                    'help','Number of features processed as one update block.'), ...
                        struct('name','utility','type','enum','default','linear','label','Utility function', ...
                            'values',{{'zero-one','linear','sigmoid'}}, ...
                    'help','Select the utility function used to optimize the selected ranking method.'), ...
                        struct('name','betaMode','type','enum','default','auto','label','Sigmoid beta mode', ...
                            'values',{{'auto','manual'}}, ...
                            'visibleIf',struct('field','utility','equals','sigmoid'), ...
                    'help','Choose automatic or manually specified beta for the selected utility/kernel.'), ...
                        struct('name','beta','type','numeric_vector','default',1,'label','Sigmoid beta value(s)', ...
                            'allowEmpty',false, ...
                            'visibleIf',struct('field','betaMode','equals','manual'), ...
                    'help','Beta parameter candidate(s) used when manual beta is selected.'), ...
                        struct('name','binMode','type','enum','default','auto','label','Multi-group processing', ...
                            'values',{{'auto','multi-group','pairwise'}}, ...
                            'help','auto reproduces the old default: multi-group if >2 groups, otherwise pairwise.'), ...
                        struct('name','gpu','type','boolean','default',false,'label','GPU flag', ...
                    'help','Enable GPU execution for the selected ranking algorithm.')};

                case 'simba'
                    spec.cliConfigurator = 'nk_Simba_config';
                    spec.fields = { ...
                        struct('name','startPoints','type','integer','default',1,'min',1,'label','# starting points', ...
                    'help','Number of independent starting points for ranking optimization.'), ...
                        struct('name','maxIter','type','integer','default',5,'min',1,'label','Maximum # of iterations', ...
                    'help','Maximum number of ranking-optimization iterations.'), ...
                        struct('name','iterAbortCrit','type','number','default',100,'min',0,'label','Feature-stability stopping criterion [%]', ...
                    'help','Percentage feature-stability threshold for early termination of Simba iterations.'), ...
                        struct('name','blockSize','type','integer','default',1,'min',1,'label','Block size', ...
                    'help','Number of features processed as one update block.'), ...
                        struct('name','utility','type','enum','default','linear','label','Utility function', ...
                            'values',{{'linear','sigmoid'}}, ...
                    'help','Select the utility function used to optimize the selected ranking method.'), ...
                        struct('name','betaMode','type','enum','default','auto','label','Sigmoid beta mode', ...
                            'values',{{'auto','manual'}}, ...
                            'visibleIf',struct('field','utility','equals','sigmoid'), ...
                    'help','Choose automatic or manually specified beta for the selected utility/kernel.'), ...
                        struct('name','beta','type','numeric_vector','default',1,'label','Sigmoid beta value(s)', ...
                            'allowEmpty',false, ...
                            'visibleIf',struct('field','betaMode','equals','manual'), ...
                    'help','Beta parameter candidate(s) used when manual beta is selected.'), ...
                        struct('name','binMode','type','enum','default','auto','label','Multi-group processing', ...
                            'values',{{'auto','multi-group','pairwise'}}, ...
                            'help','auto reproduces the old default: multi-group if >2 groups and BINMOD is false, otherwise pairwise.'), ...
                        struct('name','gpu','type','boolean','default',false,'label','GPU flag', ...
                    'help','Enable GPU execution for the selected ranking algorithm.')};

                case {'imrelief','idetect'}
                    spec.cliConfigurator = 'nk_IMRelief_config';
                    spec.fields = { ...
                        struct('name','distance','type','enum','default','block','label','Distance measure', ...
                            'values',{{'block','euclidean'}}, ...
                    'help','Choose block or Euclidean distance for IMRelief/iDetect.'), ...
                        struct('name','sigma','type','numeric_vector','default',2,'label','Sigma parameter(s)','allowEmpty',false, ...
                    'help','Sigma candidate(s) for the IMRelief/iDetect distance kernel.'), ...
                        struct('name','lambda','type','numeric_vector','default',0.1,'label','Lambda parameter(s)','allowEmpty',false, ...
                    'help','Lambda candidate(s) for the IMRelief/iDetect optimization.'), ...
                        struct('name','maxiter','type','integer','default',10,'min',1,'label','Maximum iterations', ...
                    'help','Maximum number of IMRelief/iDetect iterations.'), ...
                        struct('name','plotfigure','type','boolean','default',false,'label','Plot learning process', ...
                    'help','Display the ranking algorithm learning-progress figure.')};

                case 'rgs'
                    spec.cliConfigurator = 'nk_RGS_config';
                    spec.fields = { ...
                        struct('name','numStarts','type','integer','default',2,'min',1,'label','# starting points', ...
                    'help','Number of random starts for RGS ranking optimization.'), ...
                        struct('name','epochs','type','integer','default',1,'min',1,'label','# epochs', ...
                    'help','Number of RGS optimization epochs.'), ...
                        struct('name','betaMode','type','enum','default','auto','label','Gaussian beta mode', ...
                            'values',{{'auto','manual'}}, ...
                    'help','Choose automatic or manually specified beta for the selected utility/kernel.'), ...
                        struct('name','beta','type','numeric_vector','default',1,'label','Beta value(s)', ...
                            'allowEmpty',false, 'visibleIf',struct('field','betaMode','equals','manual'), ...
                    'help','Beta parameter candidate(s) used when manual beta is selected.'), ...
                        struct('name','kMode','type','enum','default','auto','label','Nearest-neighbour K mode', ...
                            'values',{{'auto','manual'}}, ...
                    'help','Choose automatically determined or manually supplied nearest-neighbour counts.'), ...
                        struct('name','k','type','numeric_vector','default',8,'label','# nearest neighbours', ...
                            'allowEmpty',false, 'visibleIf',struct('field','kMode','equals','manual'), ...
                    'help','Nearest-neighbour count candidate(s) for the selected ranking method.'), ...
                        struct('name','verbose','type','boolean','default',true,'label','Verbose', ...
                    'help','Print RGS progress information during optimization.')};

                case 'feast'
                    spec.cliConfigurator = 'nk_FEAST_config';
                    spec.fields = { ...
                        struct('name','binningMode','type','enum','default','discretize','label','Binning mode', ...
                            'values',{{'discretize','symbolize'}}, ...
                    'help','Choose discretization or symbolization before FEAST feature selection.'), ...
                        struct('name','binStart','type','number','default',0,'label','Discretization bin start', ...
                            'visibleIf',struct('field','binningMode','equals','discretize'), ...
                    'help','Starting value for FEAST discretization bins.'), ...
                        struct('name','binStep','type','number','default',0.5,'min',eps,'label','Discretization bin step', ...
                            'visibleIf',struct('field','binningMode','equals','discretize'), ...
                    'help','Step size between FEAST discretization bins.'), ...
                        struct('name','binStop','type','number','default',4,'label','Discretization bin stop', ...
                            'visibleIf',struct('field','binningMode','equals','discretize'), ...
                    'help','Last value for FEAST discretization bins.'), ...
                        struct('name','symbolMinBin','type','integer','default',3,'min',2,'label','Symbolization minimum bins', ...
                            'visibleIf',struct('field','binningMode','equals','symbolize'), ...
                    'help','Minimum candidate number of FEAST symbolization bins.'), ...
                        struct('name','symbolMaxBin','type','integer','default',25,'min',2,'label','Symbolization maximum bins', ...
                            'visibleIf',struct('field','binningMode','equals','symbolize'), ...
                    'help','Maximum candidate number of FEAST symbolization bins.'), ...
                        struct('name','symbolSeqLength','type','integer','default',4,'min',1,'label','Symbolization sequence length', ...
                            'visibleIf',struct('field','binningMode','equals','symbolize'), ...
                    'help','Length of the FEAST symbol sequence.'), ...
                        struct('name','symbolStdNum','type','number','default',3,'min',0,'label','Symbolization STD range', ...
                            'visibleIf',struct('field','binningMode','equals','symbolize'), ...
                    'help','Standard-deviation range of FEAST symbolization.'), ...
                        struct('name','method','type','enum','default','jmi','label','FEAST algorithm', ...
                            'values',{{'mim','mrmr','cmim','jmi','disr','cife','icap','condred','cmi','mifs'}}, ...
                    'help','Select the algorithm used by the FEAST or PLS ranking subconfiguration.'), ...
                        struct('name','mifsBeta','type','numeric_vector','default',1,'label','MIFS beta value(s)', ...
                            'allowEmpty',false, 'visibleIf',struct('field','method','equals','mifs'), ...
                    'help','Beta candidate(s) for the mutual-information feature-selection criterion.'), ...
                        struct('name','numFeat','type','numeric_vector','default',10,'label','Number(s) of features to extract', ...
                            'allowInf',true,'allowEmpty',false, ...
                            'help','Use Inf to return all ranked features.')};

                case 'pls'
                    spec.cliConfigurator = 'nk_PLS_config';
                    spec.fields = { ...
                        struct('name','method','type','enum','default','pls','label','PLS method', ...
                            'values',{{'pls','spls'}}, ...
                    'help','Select the algorithm used by the FEAST or PLS ranking subconfiguration.'), ...
                        struct('name','labelMatrixSource','type','enum','default','nm_labels','label','V matrix source', ...
                            'values',{{'nm_labels','nm_covars','workspace','legacy'}}, ...
                    'help','Choose the source of the response/design matrix V for PLS ranking.'), ...
                        struct('name','covariateColumns','type','numeric_vector','default',[],'label','Covariate column indices', ...
                            'allowEmpty',true, 'visibleIf',struct('field','labelMatrixSource','equals','nm_covars'), ...
                    'help','Covariate columns defining the PLS ranking response/design matrix V.'), ...
                        struct('name','workspaceMatrixVar','type','workspace_var','default','','label','Workspace V matrix variable', ...
                            'visibleIf',struct('field','labelMatrixSource','equals','workspace'), ...
                            'workspaceFilter',struct('numericOnly',true,'rowCountFromContext','nSubjects'), ...
                    'help','Workspace variable containing the PLS ranking response/design matrix V.'), ...
                        struct('name','cu','type','numeric_vector','default',1,'label','Sparse PLS U constraint(s)', ...
                            'allowEmpty',false, 'visibleIf',struct('field','method','equals','spls'), ...
                    'help','Sparsity constraint candidate(s) for PLS U weights.'), ...
                        struct('name','cv','type','numeric_vector','default',1,'label','Sparse PLS V constraint(s)', ...
                            'allowEmpty',false, 'visibleIf',struct('field','method','equals','spls'), ...
                    'help','Sparsity constraint candidate(s) for PLS V weights.')};

                case {'libsvm','liblin'}
                    spec.status = 'legacy-svm-wrapper';
                    if strcmp(alg,'libsvm'), spec.cliConfigurator = 'nk_LIBSVM_config'; else, spec.cliConfigurator = 'nk_LIBLIN_config'; end
                    spec.description = [spec.description ' Classification settings are configured on this dedicated page.'];
                    spec.fields = { ...
                        struct('name','legacyNotice','type','readonly','default','Advanced SVM/LIBLINEAR settings from an existing configuration are retained. This page exposes the editable settings supported here.','label','Status', ...
                    'help','Read-only notice describing an imported legacy learner configuration.'), ...
                        struct('name','slackParam','type','numeric_vector','default',1,'label','Slack/Nu-SVC parameter(s)','allowEmpty',false, ...
                    'help','Slack or Nu-SVC hyperparameter candidate(s) for the ranking SVM.'), ...
                        struct('name','epsilonParam','type','numeric_vector','default',0.1,'label','Epsilon-SVR parameter(s)','allowEmpty',true, ...
                    'help','Epsilon-SVR hyperparameter candidate(s) for the ranking SVM.'), ...
                        struct('name','nuParam','type','numeric_vector','default',0.5,'label','Nu-SVR parameter(s)','allowEmpty',true, ...
                    'help','Nu-SVR hyperparameter candidate(s) for the ranking SVM.'), ...
                        struct('name','liblinTolerance','type','numeric_vector','default',[],'label','LIBLINEAR tolerance parameter(s)', ...
                            'allowEmpty',true, 'visibleIf',struct('field','__algorithm','equals','liblin'), ...
                    'help','Convergence tolerance candidate(s) for LIBLINEAR ranking.')};

                otherwise
                    spec.status = 'unknown';
                    spec.fields = {};
            end
        end

        function cfg = defaultParams(alg, ctx)
            % defaultParams  Return default parameters for a nested method/algorithm.
            %   Defaults come from the method schema and are normalized before parent modules embed
            %   them into canonical configs.

            if nargin < 2, ctx = struct(); end
            cfg = NMConfigTools.defaultsFromSpec(NMRankSubconfigLibrary.spec(alg, ctx));
        end

        function [cfg, report] = validateParams(alg, cfg, ctx, strict)
            % validateParams  Validate nested method/algorithm parameters.
            %   Returns normalized params and a report so parent modules can distinguish strict API
            %   errors from permissive legacy import repair.

            if nargin < 3, ctx = struct(); end
            if nargin < 4, strict = false; end
            spec = NMRankSubconfigLibrary.spec(alg, ctx);
            [cfg, report] = NMConfigTools.validateConfig(spec, cfg, ctx, strict);
        end

        function params = normalizeParams(alg, params, ctx)
            % normalizeParams  Normalize nested parameters or raise if validation fails.
            %   Used immediately before legacy export so generated ACTPARAM branches use canonical,
            %   backend-compatible values.

            if nargin < 2 || isempty(params) || ~isstruct(params), params = struct(); end
            if nargin < 3, ctx = struct(); end
            [params, report] = NMRankSubconfigLibrary.validateParams(alg, params, ctx, false);
            if ~report.ok
                error('NMRankSubconfigLibrary:invalidParams', '%s', strjoin(report.errors, newline));
            end
        end

        function [RANK, PX] = applyToLegacy(RANK, cfg, ctx, pxAddFcn)
            % applyToLegacy  Write nested method parameters into an existing legacy branch.
            %
            % Parent modules call this while materializing ACTPARAM fields so algorithm-specific
            % translation stays isolated here.
            %
            % cfg.algorithm: stores the selected learner/preprocessing algorithm inside a normalized configuration.
            % cfg.algorithmParams: stores the normalized algorithm params value in the module configuration.

            if nargin < 3, ctx = struct(); end
            if nargin < 4, pxAddFcn = []; end
            alg = lower(char(cfg.algorithm));
            params = struct();
            if isfield(cfg,'algorithmParams') && isstruct(cfg.algorithmParams)
                params = cfg.algorithmParams;
            end
            params = NMRankSubconfigLibrary.normalizeParams(alg, params, ctx);
            PX = [];
            switch alg
                case {'pearson','spearman','auc','anova','varfeat','extern','extern2'}
                    % No nested parameter struct in nk_Rank_config.

                case 'fscore'
                    RANK.FScoreType = params.fscoreType;
                    RANK.WeightMode = params.weightMode;
                    if strcmpi(params.weightMode,'manual') && isfield(params,'weightsVar') && ~isempty(params.weightsVar)
                        RANK.Weights = NMWorkspaceTools.resolve(params.weightsVar, 'base');
                    else
                        RANK.Weights = [];
                    end
                    RANK.B = params.bootstrapIterations;
                    RANK.Nuisance = [];

                case 'relief'
                    RANK.Relief.k = params.k;

                case 'gflip'
                    G = struct();
                    G.gflip.extra_param.start_points = params.startPoints;
                    G.gflip.extra_param.max_iter = params.maxIter;
                    G.gflip.extra_param.block_size = params.blockSize;
                    G.gflip.gpu = logical(params.gpu);
                    [G.gflip.utilfunc, G.gflip.extra_param.utility] = NMRankSubconfigLibrary.gflipUtility(params.utility);
                    if strcmpi(params.utility,'sigmoid') && strcmpi(params.betaMode,'manual')
                        G.gflip.extra_param.beta = params.beta;
                    else
                        G.gflip.extra_param.beta = 'auto';
                    end
                    G.binmode = NMRankSubconfigLibrary.binModeCode(params.binMode, ctx, 'gflip');
                    RANK.gflip = G;
                    if isnumeric(G.gflip.extra_param.beta) && ~isempty(pxAddFcn)
                        PX = pxAddFcn(PX, G.gflip.extra_param.beta, 'Beta', 1, 'replace');
                    end

                case 'simba'
                    S = struct();
                    S.simba.extra_param.start_points = params.startPoints;
                    S.simba.extra_param.max_iter = params.maxIter;
                    S.simba.extra_param.iter_abort_crit = params.iterAbortCrit;
                    S.simba.extra_param.block_size = params.blockSize;
                    S.simba.gpu = logical(params.gpu);
                    [S.simba.utilfunc, S.simba.extra_param.utility] = NMRankSubconfigLibrary.simbaUtility(params.utility);
                    if strcmpi(params.utility,'sigmoid') && strcmpi(params.betaMode,'manual')
                        S.simba.extra_param.beta = params.beta;
                    else
                        S.simba.extra_param.beta = 'auto';
                    end
                    S.binmode = NMRankSubconfigLibrary.binModeCode(params.binMode, ctx, 'simba');
                    RANK.simba = S;
                    if isnumeric(S.simba.extra_param.beta) && ~isempty(pxAddFcn)
                        PX = pxAddFcn(PX, S.simba.extra_param.beta, 'Beta', 1, 'replace');
                    end

                case {'imrelief','idetect'}
                    I = struct();
                    I.distance = params.distance;
                    I.desc = NMRankSubconfigLibrary.title(alg);
                    I.sigma = params.sigma;
                    I.lambda = params.lambda;
                    I.maxiter = params.maxiter;
                    I.plotfigure = logical(params.plotfigure);
                    RANK.(alg) = I;
                    if ~isempty(pxAddFcn)
                        PX = pxAddFcn(PX, I.sigma, 'Sigma', 1, 'replace');
                        PX = pxAddFcn(PX, I.lambda, 'Lambda', 1, '');
                    end

                case 'rgs'
                    R = struct();
                    R.extra_param.num_starts = params.numStarts;
                    R.extra_param.epochs = params.epochs;
                    R.extra_param.verbose = logical(params.verbose);
                    if strcmpi(params.kMode,'manual'), R.extra_param.k = params.k; end
                    if strcmpi(params.betaMode,'manual'), R.extra_param.beta = params.beta; end
                    RANK.RGS = R;
                    if ~isempty(pxAddFcn)
                        if isfield(R.extra_param,'k')
                            PX = pxAddFcn(PX, R.extra_param.k, 'K', 1, 'replace');
                        else
                            PX = [];
                        end
                        if isfield(R.extra_param,'beta')
                            PX = pxAddFcn(PX, R.extra_param.beta, 'Beta', 1, '');
                        end
                    end

                case 'feast'
                    F = struct();
                    F.Method = NMRankSubconfigLibrary.feastMethodCode(params.method);
                    F.MethodStr = params.method;
                    F.NumFeat = params.numFeat;
                    if strcmpi(params.binningMode,'symbolize')
                        F.cmd = 'symbolize';
                        F.SYMBOL.symMinBin = params.symbolMinBin;
                        F.SYMBOL.symMaxBin = params.symbolMaxBin;
                        F.SYMBOL.symSeqLength = params.symbolSeqLength;
                        F.SYMBOL.symStdNum = params.symbolStdNum;
                        if isfield(F,'DISCRET'), F = rmfield(F,'DISCRET'); end
                    else
                        F.cmd = 'discretize';
                        F.DISCRET.binstart = params.binStart;
                        F.DISCRET.binsteps = params.binStep;
                        F.DISCRET.binstop = params.binStop;
                        if isfield(F,'SYMBOL'), F = rmfield(F,'SYMBOL'); end
                    end
                    if strcmpi(params.method,'mifs')
                        F.MethodParams = params.mifsBeta;
                    end
                    RANK.FEAST = F;
                    if ~isempty(pxAddFcn)
                        PX = pxAddFcn(PX, F.NumFeat, 'NumFeat', 1, '');
                    end

                case 'pls'
                    P = struct();
                    P.algostr = params.method;
                    switch lower(char(params.labelMatrixSource))
                        case 'nm_covars'
                            P.uselabel = 2;
                            [NM, ~] = NMRankSubconfigLibrary.resolveNM(ctx);
                            if isempty(NM) || ~isfield(NM,'covars') || isempty(NM.covars)
                                error('NMRankSubconfigLibrary:noCovars','PLS covariate matrix requested but NM.covars is unavailable.');
                            end
                            if isempty(params.covariateColumns)
                                P.covsel = 1:size(NM.covars,2);
                            else
                                P.covsel = params.covariateColumns;
                            end
                            P.V = NM.covars(:,P.covsel);
                        case 'workspace'
                            P.uselabel = 3;
                            if isempty(params.workspaceMatrixVar)
                                error('NMRankSubconfigLibrary:noPLSWorkspace','PLS workspace V matrix source selected but no variable name was provided.');
                            end
                            P.V = NMWorkspaceTools.resolve(params.workspaceMatrixVar, 'base');
                        case 'legacy'
                            if isfield(RANK,'PLS') && isstruct(RANK.PLS)
                                P = NMConfigTools.mergeStruct(RANK.PLS, P);
                            else
                                P.uselabel = 1;
                                P.V = NMRankSubconfigLibrary.dummyLabels(ctx);
                            end
                        otherwise
                            P.uselabel = 1;
                            P.V = NMRankSubconfigLibrary.dummyLabels(ctx);
                    end
                    P.cu = params.cu;
                    P.cv = params.cv;
                    RANK.PLS = P;
                    RANK.label = P.V;
                    switch P.uselabel
                        case 1, RANK.labeldesc = 'NM target label';
                        case 2, RANK.labeldesc = 'NM covariate matrix';
                        case 3, RANK.labeldesc = 'NM user-defined matrix';
                    end
                    if strcmpi(P.algostr,'spls') && ~isempty(pxAddFcn)
                        PX = pxAddFcn(PX, P.cu, 'SPLS-cu', 1, '');
                        PX = pxAddFcn(PX, P.cv, 'SPLS-cv', 1, '');
                    end

                case {'libsvm','liblin'}
                    if ~isfield(RANK,'SVM') || ~isstruct(RANK.SVM), RANK.SVM = struct(); end
                    RANK.SVM.prog = upper(alg);
                    RANK.SVM.kernel.kerndef = 1;
                    if strcmp(alg,'libsvm')
                        RANK.SVM.kernel.kernstr = ' -t 0';
                    else
                        RANK.SVM.kernel.kernstr = 'lin';
                        if ~isempty(params.liblinTolerance)
                            RANK.SVM.LIBLIN.tolerance = params.liblinTolerance;
                            if ~isempty(pxAddFcn)
                                PX = pxAddFcn(PX, params.liblinTolerance, 'TolRank', 1, 'replace');
                            end
                        end
                    end
                    if ~isempty(params.epsilonParam)
                        RANK.SVM.EpsParam = params.epsilonParam;
                        if ~isempty(pxAddFcn), PX = pxAddFcn(PX, params.epsilonParam, 'EpsilonRank', 1, ''); end
                    end
                    if ~isempty(params.nuParam)
                        RANK.SVM.NuParam = params.nuParam;
                        if ~isempty(pxAddFcn), PX = pxAddFcn(PX, params.nuParam, 'NuRank', 1, ''); end
                    end
                    if ~isempty(params.slackParam)
                        RANK.SVM.SlackParam = params.slackParam;
                        if ~isempty(pxAddFcn), PX = pxAddFcn(PX, params.slackParam, 'SlackRank', 1, ''); end
                    end
            end
        end

        function params = fromLegacy(alg, RANK, ctx)
            % fromLegacy  Import nested method parameters from a legacy payload.
            %   Preserves older ACTPARAM fields while returning canonical params suitable for UI
            %   display and later re-export.

            if nargin < 3, ctx = struct(); end
            alg = lower(char(alg));
            params = NMRankSubconfigLibrary.defaultParams(alg, ctx);
            switch alg
                case 'fscore'
                    if isfield(RANK,'FScoreType'), params.fscoreType = RANK.FScoreType; end
                    if isfield(RANK,'WeightMode'), params.weightMode = RANK.WeightMode; end
                    if isfield(RANK,'B'), params.bootstrapIterations = RANK.B; end
                case 'relief'
                    if isfield(RANK,'Relief') && isstruct(RANK.Relief) && isfield(RANK.Relief,'k'), params.k = RANK.Relief.k; end
                case 'gflip'
                    if isfield(RANK,'gflip'), params = NMRankSubconfigLibrary.fromLegacyGflip(params, RANK.gflip); end
                case 'simba'
                    if isfield(RANK,'simba'), params = NMRankSubconfigLibrary.fromLegacySimba(params, RANK.simba); end
                case {'imrelief','idetect'}
                    if isfield(RANK,alg), params = NMRankSubconfigLibrary.fromLegacyIMRelief(params, RANK.(alg)); end
                case 'rgs'
                    if isfield(RANK,'RGS'), params = NMRankSubconfigLibrary.fromLegacyRGS(params, RANK.RGS); end
                case 'feast'
                    if isfield(RANK,'FEAST'), params = NMRankSubconfigLibrary.fromLegacyFEAST(params, RANK.FEAST); end
                case 'pls'
                    if isfield(RANK,'PLS'), params = NMRankSubconfigLibrary.fromLegacyPLS(params, RANK.PLS); end
                case {'libsvm','liblin'}
                    if isfield(RANK,'SVM'), params = NMRankSubconfigLibrary.fromLegacySVM(params, RANK.SVM, alg); end
            end
            params = NMRankSubconfigLibrary.normalizeParams(alg, params, ctx);
        end

        function t = title(alg)
            % title  Return a readable title for a nested method/algorithm.
            %   Used by config schemas, UI controls, and RAG documentation instead of exposing raw
            %   legacy command ids.

            switch lower(char(alg))
                case 'gflip', t = 'G-flip';
                case 'simba', t = 'Simba';
                case 'imrelief', t = 'IMRelief';
                case 'idetect', t = 'I-Detect / IMRelief';
                case 'rgs', t = 'RGS';
                case 'feast', t = 'FEAST mutual-information ranking';
                case 'pls', t = 'Partial least squares';
                case 'libsvm', t = 'Linear SVM ranking (LIBSVM)';
                case 'liblin', t = 'Linear SVM ranking (LIBLINEAR)';
                case 'relief', t = 'Relief';
                case 'fscore', t = 'F-score';
                otherwise, t = upper(char(alg));
            end
        end

        function d = description(alg)
            % description  Return explanatory text for a nested method/algorithm.
            %   Provides human-readable method context for UI help, API users, and documentation
            %   extraction.

            switch lower(char(alg))
                case 'gflip', d = 'Nested configuration ported from nk_Gflip_config.';
                case 'simba', d = 'Nested configuration ported from nk_Simba_config.';
                case {'imrelief','idetect'}, d = 'Nested configuration ported from nk_IMRelief_config.';
                case 'rgs', d = 'Nested configuration ported from nk_RGS_config.';
                case 'feast', d = 'Nested configuration ported from nk_FEAST_config, including FEAST-specific binning settings.';
                case 'pls', d = 'Nested configuration ported from nk_PLS_config. Sparse PLS parameters are PX-active.';
                case {'libsvm','liblin'}, d = 'Transition page for the SVM ranking subconfiguration. Full SVM/LIBLINEAR menu parity will be shared later with the ML learner configurator.';
                otherwise, d = 'This algorithm has no separate nested subconfigurator in the current legacy ranking menu.';
            end
        end
    end

    methods (Static, Access = private)
        function f = safeField(id)
            f = matlab.lang.makeValidName(lower(char(id)));
        end

        function [code, str] = gflipUtility(name)
            switch lower(char(name))
                case 'zero-one', code = 1; str = 'zero-one';
                case 'sigmoid',  code = 3; str = 'sigmoid';
                otherwise,       code = 2; str = 'linear';
            end
        end

        function [code, str] = simbaUtility(name)
            switch lower(char(name))
                case 'sigmoid', code = 2; str = 'sigmoid';
                otherwise,      code = 1; str = 'linear';
            end
        end

        function code = binModeCode(name, ctx, alg)
            s = lower(char(name));
            if strcmp(s,'multi-group'), code = uint8(0); return; end
            if strcmp(s,'pairwise'), code = uint8(1); return; end
            nGroups = NMRankSubconfigLibrary.contextGroupCount(ctx);
            if strcmpi(alg,'simba')
                binmod = NMRankSubconfigLibrary.contextBINMOD(ctx);
                if nGroups > 2 && ~binmod, code = uint8(0); else, code = uint8(1); end
            else
                if nGroups > 2, code = uint8(0); else, code = uint8(1); end
            end
        end

        function n = contextGroupCount(ctx)
            n = 2;
            if isstruct(ctx) && isfield(ctx,'activeLabelNClasses') && ~isempty(ctx.activeLabelNClasses)
                n = double(ctx.activeLabelNClasses);
            elseif isstruct(ctx) && isfield(ctx,'hasNM') && isequal(ctx.hasNM,true)
                error('NMRankSubconfigLibrary:missingClassContext', ...
                    'NM-backed rank configuration requires ctx.activeLabelNClasses from NMPreprocContext.');
            end
        end

        function binmod = contextBINMOD(ctx)
            if isstruct(ctx) && isfield(ctx,'preprocBinmod') && ~isempty(ctx.preprocBinmod)
                binmod = logical(ctx.preprocBinmod);
            elseif isstruct(ctx) && isfield(ctx,'hasNM') && isequal(ctx.hasNM,true)
                error('NMRankSubconfigLibrary:missingBinmodContext', ...
                    'NM-backed rank configuration requires ctx.preprocBinmod from NMPreprocContext.');
            else
                binmod = logical(NMPreprocGlobalOptions.defaultBinmod(ctx));
            end
        end

        function code = feastMethodCode(method)
            methods = {'mim','mrmr','cmim','jmi','disr','cife','icap','condred','cmi','mifs'};
            code = find(strcmpi(char(method), methods), 1);
            if isempty(code), code = 4; end
        end

        function labels = dummyLabels(ctx)
            % dummyLabels  Create dummy one-hot labels for ranking backends when real labels are unavailable.
            %
            % Used by rank-feature legacy translation paths that require label matrices even
            % during schema/import operations.
            %
            % ctx.activeLabel: carries the A2-resolved effective response without re-reading synthetic ctx.NM target state.

            labels = [];
            if ~isstruct(ctx) || ~isfield(ctx,'activeLabel') || isempty(ctx.activeLabel)
                if isstruct(ctx) && isfield(ctx,'hasNM') && isequal(ctx.hasNM,true)
                    error('NMRankSubconfigLibrary:missingActiveLabelContext', ...
                        'NM-backed rank configuration requires ctx.activeLabel from NMPreprocContext.');
                end
                return;
            end
            lab = ctx.activeLabel;
            if ~(isnumeric(lab) || islogical(lab)), return; end
            u = unique(lab(~isnan(lab)));
            labels = zeros(size(lab,1), numel(u));
            for i = 1:numel(u), labels(:,i) = lab == u(i); end
        end

        function [NMout, varind] = resolveNM(ctx)
            % resolveNM  Extract NM and modality index from a context struct.
            %
            % Keeps rank subconfig translation independent of full orchestrator state while still
            % supporting context-aware defaults.
            %
            % ctx.NM: provides the current NeuroMiner structure to preprocessing execution helpers without direct global access.
            % ctx.varind: identifies the modality being preprocessed in the current execution context.

            NMout = []; varind = 1;
            if isstruct(ctx)
                if isfield(ctx,'NM'), NMout = ctx.NM; end
                if isfield(ctx,'varind') && ~isempty(ctx.varind), varind = ctx.varind; end
            end
        end

        function p = fromLegacyGflip(p, G)
            % fromLegacyGflip  Import G-flip-specific ranking parameters from a legacy branch.
            %   Maps nested gflip.extra_param fields into canonical algorithm parameters for UI/API
            %   round-tripping.

            try
                E = G.gflip.extra_param;
                if isfield(E,'start_points'), p.startPoints = E.start_points; end
                if isfield(E,'max_iter'), p.maxIter = E.max_iter; end
                if isfield(E,'block_size'), p.blockSize = E.block_size; end
                if isfield(E,'beta') && isnumeric(E.beta), p.betaMode = 'manual'; p.beta = E.beta; end
                if isfield(G.gflip,'utilfunc')
                    switch G.gflip.utilfunc
                        case 1, p.utility = 'zero-one';
                        case 3, p.utility = 'sigmoid';
                        otherwise, p.utility = 'linear';
                    end
                end
                if isfield(G,'binmode'), if G.binmode==0, p.binMode = 'multi-group'; else, p.binMode = 'pairwise'; end, end
                if isfield(G.gflip,'gpu'), p.gpu = logical(G.gflip.gpu); end
            catch
            end
        end

        function p = fromLegacySimba(p, S)
            % fromLegacySimba  Import Simba-specific ranking parameters from a legacy branch.
            %   Maps nested simba.extra_param fields into canonical algorithm parameters for UI/API
            %   round-tripping.

            try
                E = S.simba.extra_param;
                if isfield(E,'start_points'), p.startPoints = E.start_points; end
                if isfield(E,'max_iter'), p.maxIter = E.max_iter; end
                if isfield(E,'iter_abort_crit'), p.iterAbortCrit = E.iter_abort_crit; end
                if isfield(E,'block_size'), p.blockSize = E.block_size; end
                if isfield(E,'beta') && isnumeric(E.beta), p.betaMode = 'manual'; p.beta = E.beta; end
                if isfield(S.simba,'utilfunc')
                    if S.simba.utilfunc == 2, p.utility = 'sigmoid'; else, p.utility = 'linear'; end
                end
                if isfield(S,'binmode'), if S.binmode==0, p.binMode = 'multi-group'; else, p.binMode = 'pairwise'; end, end
                if isfield(S.simba,'gpu'), p.gpu = logical(S.simba.gpu); end
            catch
            end
        end

        function p = fromLegacyIMRelief(p, I)
            % fromLegacyIMRelief  Import I-Relief-specific ranking parameters from a legacy branch.
            %   Reads distance, sigma, lambda, iteration, and plotting fields into the canonical
            %   rank config.

            if isfield(I,'distance'), p.distance = I.distance; end
            if isfield(I,'sigma'), p.sigma = I.sigma; end
            if isfield(I,'lambda'), p.lambda = I.lambda; end
            if isfield(I,'maxiter'), p.maxiter = I.maxiter; end
            if isfield(I,'plotfigure'), p.plotfigure = logical(I.plotfigure); end
        end

        function p = fromLegacyRGS(p, R)
            % fromLegacyRGS  Import RGS-specific ranking parameters from a legacy branch.
            %   Recovers random-search options and manual beta settings from legacy extra_param
            %   fields.

            if ~isfield(R,'extra_param'), return; end
            E = R.extra_param;
            if isfield(E,'num_starts'), p.numStarts = E.num_starts; end
            if isfield(E,'epochs'), p.epochs = E.epochs; end
            if isfield(E,'verbose'), p.verbose = logical(E.verbose); end
            if isfield(E,'beta') && isnumeric(E.beta), p.betaMode = 'manual'; p.beta = E.beta; end
            if isfield(E,'k') && isnumeric(E.k), p.kMode = 'manual'; p.k = E.k; end
        end

        function p = fromLegacyFEAST(p, F)
            % fromLegacyFEAST  Import FEAST-specific ranking and discretization parameters.
            %   Restores binning/discretization and FEAST method choices into canonical config form.

            if isfield(F,'cmd'), p.binningMode = F.cmd; end
            if isfield(F,'DISCRET')
                D = F.DISCRET;
                p.binningMode = 'discretize';
                if isfield(D,'binstart'), p.binStart = D.binstart; end
                if isfield(D,'binsteps'), p.binStep = D.binsteps; end
                if isfield(D,'binstop'), p.binStop = D.binstop; end
            end
            if isfield(F,'SYMBOL')
                S = F.SYMBOL;
                p.binningMode = 'symbolize';
                if isfield(S,'symMinBin'), p.symbolMinBin = S.symMinBin; end
                if isfield(S,'symMaxBin'), p.symbolMaxBin = S.symMaxBin; end
                if isfield(S,'symSeqLength'), p.symbolSeqLength = S.symSeqLength; end
                if isfield(S,'symStdNum'), p.symbolStdNum = S.symStdNum; end
            end
            methods = {'mim','mrmr','cmim','jmi','disr','cife','icap','condred','cmi','mifs'};
            if isfield(F,'Method') && F.Method >= 1 && F.Method <= numel(methods), p.method = methods{F.Method}; end
            if isfield(F,'MethodStr'), p.method = F.MethodStr; end
            if isfield(F,'MethodParams'), p.mifsBeta = F.MethodParams; end
            if isfield(F,'NumFeat'), p.numFeat = F.NumFeat; end
        end

        function p = fromLegacyPLS(p, P)
            % fromLegacyPLS  Import PLS-ranking parameters from a legacy branch.
            %   Recovers label matrix source, method, and workspace/legacy label settings used by
            %   PLS-based feature weighting.

            if isfield(P,'algostr'), p.method = P.algostr; end
            if isfield(P,'uselabel')
                switch P.uselabel
                    case 2, p.labelMatrixSource = 'nm_covars';
                    case 3, p.labelMatrixSource = 'legacy';
                    otherwise, p.labelMatrixSource = 'nm_labels';
                end
            end
            if isfield(P,'covsel'), p.covariateColumns = P.covsel; end
            if isfield(P,'cu'), p.cu = P.cu; end
            if isfield(P,'cv'), p.cv = P.cv; end
        end

        function p = fromLegacySVM(p, SVM, alg)
            % fromLegacySVM  Import SVM-weighting parameters from a legacy branch.
            %   Maps LIBSVM/LIBLIN tuning fields into canonical ranking config used for re-export.

            if strcmpi(alg,'liblin') && isfield(SVM,'LIBLIN') && isfield(SVM.LIBLIN,'tolerance')
                p.liblinTolerance = SVM.LIBLIN.tolerance;
            end
            if isfield(SVM,'SlackParam'), p.slackParam = SVM.SlackParam; end
            if isfield(SVM,'EpsParam'), p.epsilonParam = SVM.EpsParam; end
            if isfield(SVM,'NuParam'), p.nuParam = SVM.NuParam; end
        end
    end
end

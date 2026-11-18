classdef NMLearnerSchemaRegistry
% NMLearnerSchemaRegistry
% -------------------------------------------------------------------------
% Standardized UI-schema adapter for learner-specific legacy hyperparameter
% shelves. This class is deliberately an adapter only: the authoritative
% backend storage remains NM.TrainParam.GRD, including GRD.(prog).Params and
% GRD.matLearn.Params. Visibility controls what the browser renders; it must
% never delete hidden legacy Params rows.
% -------------------------------------------------------------------------

    methods (Static)
        function S = uiSchemaByAlgorithm(ctx)
        % uiSchemaByAlgorithm  Build the learner-to-schema map used by the ML browser field table.
        %   Iterates over task-mode learner ids and stores each schema under its canonical algorithm
        %   token; NMMLModule.uiFields embeds this map in the learner_param_table descriptor.

            if nargin < 1, ctx = struct(); end
            mode = NMLearnerLibrary.taskMode(ctx);
            ids = NMLearnerLibrary.ids(ctx);
            S = struct();
            for i = 1:numel(ids)
                alg = NMLearnerLibrary.canonicalId(ids{i});
                S.(alg) = NMLearnerSchemaRegistry.schemaForAlgorithm(alg, mode);
            end
        end

        function schema = schemaForAlgorithm(algorithm, mode)
        % schemaForAlgorithm  Dispatch schema construction according to learner storage layout.
        %   matLRN gets nested matLearn schemas, modern learners get Params-array option schemas, and
        %   older backends get flat GRD shelves. This is the main public schema lookup for power-user
        %   code that wants to inspect editable ML hyperparameters.

            if nargin < 2 || isempty(mode), mode = 'classification'; end
            alg = NMLearnerLibrary.canonicalId(algorithm);
            if strcmpi(alg,'matLRN')
                schema = NMLearnerSchemaRegistry.schemaForMatLearn(mode);
            elseif NMLearnerLibrary.isModernParamLearner(alg)
                schema = NMLearnerSchemaRegistry.schemaForCoreLearner(alg, mode);
            else
                schema = NMLearnerSchemaRegistry.schemaForFlatGRD(alg, mode);
            end
        end

        function schema = schemaForCoreLearner(algorithm, mode)
        % schemaForCoreLearner  Build a Params-array schema for modern non-matLearn learners.
        %   Reads option metadata from NMLearnerLibrary.legacyLearnerParamDefaults or fallbackOptions
        %   and converts it into UI/backend field descriptors that export to GRD.(algorithm).Params.

            if nargin < 2 || isempty(mode), mode = 'classification'; end
            alg = NMLearnerLibrary.canonicalId(algorithm);
            param = NMLearnerLibrary.legacyLearnerParamDefaults(alg, mode);
            opt = [];
            if isfield(param,'options') && isstruct(param.options) && isfield(param.options,'name')
                opt = param.options;
            elseif isfield(param,'learner') && isfield(param.learner,'options') && isstruct(param.learner.options)
                opt = param.learner.options;
            end
            if isempty(opt) || ~isstruct(opt) || ~isfield(opt,'name')
                opt = NMLearnerLibrary.fallbackOptions(alg, mode);
            end
            schema = NMLearnerSchemaRegistry.optionsToSchema(alg, opt, 'GRD', alg, 'Params', NMLearnerSchemaRegistry.matLearnFramework(mode));
            schema.displayMode = 'normal';
            schema.framework = mode;
        end

        function schema = schemaForMatLearn(mode)
        % schemaForMatLearn  Build the nested schema catalog for the matLearn wrapper learner.
        %   Resolves the NeuroMiner binaryclass/regression framework, enumerates matLearn sublearners,
        %   and attaches a schema for each sublearner under schemasByAlgorithm.

            if nargin < 1 || isempty(mode), mode = 'classification'; end
            framework = NMLearnerSchemaRegistry.matLearnFramework(mode);
            vals = NMLearnerSchemaRegistry.matLearnAlgorithmValues(mode);
            defaultAlgo = '';
            if ~isempty(vals), defaultAlgo = vals{1}.value; end
            schema = struct();
            schema.algorithm = 'matLRN';
            schema.displayName = 'matLearn learner';
            schema.framework = framework;
            schema.defaultAlgorithm = defaultAlgo;
            schema.algorithmValues = vals;
            schema.schemasByAlgorithm = struct();
            for i = 1:numel(vals)
                alg = vals{i}.value;
                opt = NMLearnerSchemaRegistry.matLearnOptionsForLearner(alg, framework);
                schema.schemasByAlgorithm.(alg) = NMLearnerSchemaRegistry.optionsToSchema(alg, opt, 'GRD', 'matLearn', 'Params', framework);
                schema.schemasByAlgorithm.(alg).framework = framework;
            end
        end

        function vals = matLearnAlgorithmValues(mode)
        % matLearnAlgorithmValues  Return selectable matLearn sublearners for the task framework.
        %   The values are derived from nk_matLearn_getopts_config-compatible option metadata and are
        %   used by NMMLModule fixed settings and default-state generation.

            framework = NMLearnerSchemaRegistry.matLearnFramework(mode);
            opt = NMLearnerSchemaRegistry.matLearnLearnerOptions(framework);
            vals = {};
            if isempty(opt) || ~isfield(opt,'sel'), return; end
            labels = NMLearnerSchemaRegistry.splitFormatLabels(opt.format);
            for i = 1:numel(opt.sel)
                lab = opt.sel{i};
                if i <= numel(labels) && ~isempty(labels{i}), lab = labels{i}; end
                vals{end+1} = struct('value',opt.sel{i},'label',lab); %#ok<AGROW>
            end
        end

        function alg = defaultMatLearnAlgorithm(mode)
        % defaultMatLearnAlgorithm  Return the first available matLearn sublearner for a task mode.
        %   Used as the default cfg.fixedSettings.algo value when a matLearn configuration is created
        %   without an imported legacy selection.

            vals = NMLearnerSchemaRegistry.matLearnAlgorithmValues(mode);
            if isempty(vals), alg = ''; else, alg = vals{1}.value; end
        end

        function framework = matLearnFramework(mode)
        % matLearnFramework  Map NeuroMiner task mode to matLearn framework token.
        %   Converts regression to regression and all other modes to binaryclass, matching the legacy
        %   nk_matLearn_getopts_config convention.

            if strcmpi(mode,'regression')
                framework = 'regression';
            else
                framework = 'binaryclass';
            end
        end

        function params = defaultParamsForAlgorithm(algorithm, mode)
        % defaultParamsForAlgorithm  Return default Params rows for any supported learner.
        %   Builds the relevant schema and extracts name/range pairs, giving scripted code the same
        %   defaults used by the modular UI and NMMLModule.defaultHyperparameters.

            schema = NMLearnerSchemaRegistry.schemaForAlgorithm(algorithm, mode);
            params = NMLearnerSchemaRegistry.paramsFromSchema(schema);
        end

        function params = defaultParamsForCoreLearner(algorithm, mode)
        % defaultParamsForCoreLearner  Return default Params rows for a modern core learner.
        %   This is the public shortcut used by NMLearnerLibrary.defaultHyperparameters when a learner
        %   stores tunable ranges under GRD.(algorithm).Params.

            schema = NMLearnerSchemaRegistry.schemaForCoreLearner(algorithm, mode);
            params = NMLearnerSchemaRegistry.paramsFromSchema(schema);
        end

        function params = defaultParamsForFlatGRD(algorithm, mode)
        % defaultParamsForFlatGRD  Return default flat-GRD shelves as Params-style rows.
        %   Provides a uniform name/range representation for older learners before NMMLModule.toLegacy
        %   expands the rows back into direct GRD fields.

            schema = NMLearnerSchemaRegistry.schemaForFlatGRD(algorithm, mode);
            params = NMLearnerSchemaRegistry.paramsFromSchema(schema);
        end

        function params = defaultParamsForMatLearn(mode, algo)
        % defaultParamsForMatLearn  Return default matLearn sublearner Params rows.
        %   Resolves the requested or default matLearn algorithm and converts its option schema into
        %   name/range rows for cfg.hyperparameters.learnerParams.

            if nargin < 2 || isempty(algo), algo = NMLearnerSchemaRegistry.defaultMatLearnAlgorithm(mode); end
            framework = NMLearnerSchemaRegistry.matLearnFramework(mode);
            opt = NMLearnerSchemaRegistry.matLearnOptionsForLearner(algo, framework);
            schema = NMLearnerSchemaRegistry.optionsToSchema(algo, opt, 'GRD', 'matLearn', 'Params', framework);
            params = NMLearnerSchemaRegistry.paramsFromSchema(schema);
        end

        function schema = schemaForFlatGRD(algorithm, mode)
        % schemaForFlatGRD  Build a visibility-aware schema for legacy flat GRD hyperparameter fields.
        %   Encodes which GRD shelves are relevant for LIBSVM, LIBLIN, IMRELF, random forest, kernels,
        %   and other legacy learners. Visibility rules control browser display only; hidden fields are
        %   not deleted from imported or exported legacy structures.

            if nargin < 2 || isempty(mode), mode = 'classification'; end
            alg = NMLearnerLibrary.canonicalId(algorithm);
            schema = struct();
            schema.algorithm = alg;
            schema.displayName = NMLearnerLibrary.title(alg);
            schema.framework = mode;
            schema.backendRoot = 'GRD';
            schema.backendField = '';
            schema.backendSubfield = '';
            schema.backendLayout = 'flatGRD';
            schema.params = NMLearnerSchemaRegistry.emptyParamSchema();

            P = NMLearnerSchemaRegistry.emptyParamSchema();
            switch alg
                case 'LIBSVM'
                    P = [P, ...
                        NMLearnerSchemaRegistry.flatParam('Cparams','C / slack-regularization range',NMLearnerSchemaRegistry.legacyDefaultValue('Cparams',mode),struct('all',{{struct('field','algorithm','equals','LIBSVM'),struct('field','fixedSettings.classifier','in',{{0,3,4}})}})), ...
                        NMLearnerSchemaRegistry.flatParam('Nuparams','Nu range',NMLearnerSchemaRegistry.legacyDefaultValue('Nuparams',mode),struct('all',{{struct('field','algorithm','equals','LIBSVM'),struct('field','fixedSettings.classifier','in',{{1,4}})}})), ...
                        NMLearnerSchemaRegistry.flatParam('Epsparams','Epsilon-SVR range',NMLearnerSchemaRegistry.legacyDefaultValue('Epsparams',mode),struct('all',{{struct('field','algorithm','equals','LIBSVM'),struct('field','fixedSettings.classifier','equals',3)}})), ...
                        NMLearnerSchemaRegistry.kernelParam('Gparams','Kernel / sigma range',NMLearnerSchemaRegistry.legacyDefaultValue('Gparams',mode),NMLearnerSchemaRegistry.kernelWidthRule()), ...
                        NMLearnerSchemaRegistry.kernelParam('PolyCoefparams','Polynomial / sigmoid coefficient range',NMLearnerSchemaRegistry.legacyDefaultValue('PolyCoefparams',mode),NMLearnerSchemaRegistry.kernelCoefRule()), ...
                        NMLearnerSchemaRegistry.kernelParam('PolyDegrparams','Polynomial degree range',NMLearnerSchemaRegistry.legacyDefaultValue('PolyDegrparams',mode),NMLearnerSchemaRegistry.kernelDegreeRule()), ...
                        NMLearnerSchemaRegistry.kernelParam('WLiters','Weisfeiler-Lehman iterations',NMLearnerSchemaRegistry.legacyDefaultValue('WLiters',mode),NMLearnerSchemaRegistry.wlKernelRule()), ...
                        NMLearnerSchemaRegistry.flatParam('Weightparams','Class / case weighting exponent range',NMLearnerSchemaRegistry.legacyDefaultValue('Weightparams',mode),struct('all',{{struct('field','algorithm','in',{{'LIBSVM','LIBLIN'}}),struct('field','fixedSettings.Weighting','equals',true)}}))];
                case 'LIBLIN'
                    P = [P, ...
                        NMLearnerSchemaRegistry.flatParam('Cparams','C / regularization range',NMLearnerSchemaRegistry.legacyDefaultValue('Cparams',mode),struct('field','algorithm','equals','LIBLIN')), ...
                        NMLearnerSchemaRegistry.flatParam('Epsparams','Epsilon-SVR range',NMLearnerSchemaRegistry.legacyDefaultValue('Epsparams',mode),struct('all',{{struct('field','algorithm','equals','LIBLIN'),struct('field','fixedSettings.classifier','in',{{11,12,13}})}})), ...
                        NMLearnerSchemaRegistry.flatParam('Weightparams','Class / case weighting exponent range',NMLearnerSchemaRegistry.legacyDefaultValue('Weightparams',mode),struct('all',{{struct('field','algorithm','in',{{'LIBSVM','LIBLIN'}}),struct('field','fixedSettings.Weighting','equals',true)}}))];
                case 'IMRELF'
                    P = [P, ...
                        NMLearnerSchemaRegistry.flatParam('Cparams','IMRelief lambda range',NMLearnerSchemaRegistry.legacyDefaultValue('Cparams','IMRELF'),struct('field','algorithm','equals','IMRELF')), ...
                        NMLearnerSchemaRegistry.flatParam('Gparams','IMRelief sigma range',NMLearnerSchemaRegistry.legacyDefaultValue('Gparams','IMRELF'),struct('field','algorithm','equals','IMRELF'))];
                case 'MEXELM'
                    P = [P, ...
                        NMLearnerSchemaRegistry.flatParam('Cparams','Slack / regularization range',NMLearnerSchemaRegistry.legacyDefaultValue('Cparams',mode),struct('field','algorithm','equals','MEXELM')), ...
                        NMLearnerSchemaRegistry.flatParam('Neuronparams','Extreme-learning-machine hidden neurons',NMLearnerSchemaRegistry.legacyDefaultValue('Neuronparams',mode),struct('field','algorithm','equals','MEXELM'))];
                case 'kNNMEX'
                    P = [P, NMLearnerSchemaRegistry.flatParam('Kparams','Nearest-neighbour range',NMLearnerSchemaRegistry.legacyDefaultValue('Kparams',mode),struct('field','algorithm','equals','kNNMEX'))];
                case 'BLOREG'
                    P = [P, NMLearnerSchemaRegistry.flatParam('Tolparams','Bayesian logistic-regression tolerance range',NMLearnerSchemaRegistry.legacyDefaultValue('Tolparams',mode),struct('field','algorithm','equals','BLOREG'))];
                case 'DECTRE'
                    P = [P, NMLearnerSchemaRegistry.flatParam('Leafparams','Decision-tree leafness range',NMLearnerSchemaRegistry.legacyDefaultValue('Leafparams',mode),struct('field','algorithm','equals','DECTRE'))];
                case 'RNDFOR'
                    P = NMLearnerSchemaRegistry.randomForestFlatParams(mode);
                case 'SEQOPT'
                    P = [P, ...
                        NMLearnerSchemaRegistry.flatParam('CutOffparams','SEQOPT threshold count range',NMLearnerSchemaRegistry.legacyDefaultValue('CutOffparams',mode),struct('field','algorithm','equals','SEQOPT')), ...
                        NMLearnerSchemaRegistry.flatParam('LimsLparams','SEQOPT lower population percentage range',NMLearnerSchemaRegistry.legacyDefaultValue('LimsLparams',mode),struct('field','algorithm','equals','SEQOPT')), ...
                        NMLearnerSchemaRegistry.flatParam('LimsUparams','SEQOPT upper population percentage range',NMLearnerSchemaRegistry.legacyDefaultValue('LimsUparams',mode),struct('field','algorithm','equals','SEQOPT'))];
                case 'WBLCOX'
                    P = [P, NMLearnerSchemaRegistry.flatParam('CoxCutoffparams','WBLCOX class-assignment percentile thresholds',NMLearnerSchemaRegistry.legacyDefaultValue('CoxCutoffparams',mode),struct('field','algorithm','equals','WBLCOX'))];
                case {'MikRVM','MKLRVM','MVTRVR'}
                    P = [P, ...
                        NMLearnerSchemaRegistry.kernelParam('Gparams','Kernel / sigma range',NMLearnerSchemaRegistry.legacyDefaultValue('Gparams',mode),NMLearnerSchemaRegistry.kernelWidthRule()), ...
                        NMLearnerSchemaRegistry.kernelParam('PolyCoefparams','Polynomial coefficient range',NMLearnerSchemaRegistry.legacyDefaultValue('PolyCoefparams',mode),NMLearnerSchemaRegistry.kernelCoefRule()), ...
                        NMLearnerSchemaRegistry.kernelParam('PolyDegrparams','Polynomial degree range',NMLearnerSchemaRegistry.legacyDefaultValue('PolyDegrparams',mode),NMLearnerSchemaRegistry.kernelDegreeRule())];
                otherwise
                    % Algorithms without trainable legacy GRD shelves expose an empty schema.
            end
            schema.params = P;
        end

        function params = paramsFromSchema(schema)
        % paramsFromSchema  Extract default Params rows from a schema descriptor.
        %   Converts schema.params into a struct array with name/range fields, preserving the schema
        %   order used by UI tables and legacy GRD export.

            params = struct('name',{},'range',{});
            if isempty(schema) || ~isfield(schema,'params'), return; end
            for i = 1:numel(schema.params)
                params(i).name = schema.params(i).name; %#ok<AGROW>
                params(i).range = schema.params(i).defaultValue; %#ok<AGROW>
            end
        end

        function schema = optionsToSchema(algorithm, opt, backendRoot, backendField, backendSubfield, framework)
        % optionsToSchema  Convert legacy option metadata arrays into modular parameter schema records.
        %   Translates desc/format/sel/def/name metadata into typed UI fields with backend mapping
        %   information. This is the common adapter used for modern learners and matLearn sublearners.

            if nargin < 3, backendRoot = 'GRD'; end
            if nargin < 4, backendField = algorithm; end
            if nargin < 5, backendSubfield = 'Params'; end
            if nargin < 6 || isempty(framework), framework = 'binaryclass'; end
            schema = struct();
            schema.algorithm = algorithm;
            schema.backendRoot = backendRoot;
            schema.backendField = backendField;
            schema.backendSubfield = backendSubfield;
            schema.params = NMLearnerSchemaRegistry.emptyParamSchema();
            if isempty(opt) || ~isstruct(opt) || ~isfield(opt,'name') || isempty(opt.name), return; end
            names = NMLearnerSchemaRegistry.forceCell(opt.name);
            desc = NMLearnerSchemaRegistry.forceCell(NMLearnerSchemaRegistry.getOptField(opt,'desc',cell(size(names))));
            fmt = NMLearnerSchemaRegistry.forceCell(NMLearnerSchemaRegistry.getOptField(opt,'format',cell(size(names))));
            sel = NMLearnerSchemaRegistry.forceCell(NMLearnerSchemaRegistry.getOptField(opt,'sel',cell(size(names))));
            def = NMLearnerSchemaRegistry.forceCell(NMLearnerSchemaRegistry.getOptField(opt,'def',cell(size(names))));
            P = NMLearnerSchemaRegistry.emptyParamSchema();
            for i = 1:numel(names)
                P(i).name = names{i}; %#ok<AGROW>
                P(i).label = NMLearnerSchemaRegistry.scalarText(NMLearnerSchemaRegistry.cellAt(desc,i,names{i}));
                P(i).format = NMLearnerSchemaRegistry.scalarText(NMLearnerSchemaRegistry.cellAt(fmt,i,''));
                P(i).allowedValues = NMLearnerSchemaRegistry.allowedValuesFromFormatAndSel(P(i).format, NMLearnerSchemaRegistry.cellAt(sel,i,[]));
                P(i).defaultValue = NMLearnerSchemaRegistry.cellAt(def,i,[]);
                P(i).visibleNormal = NMLearnerSchemaRegistry.visibleNormal(algorithm, i, numel(names));
                P(i).visibleExpert = true;
                P(i).kind = NMLearnerSchemaRegistry.kindFromFormat(P(i).format);
                P(i).defaultValue = NMLearnerSchemaRegistry.normalizeDefaultForKind(P(i).defaultValue, P(i).kind, P(i).allowedValues);
                P(i).backendRoot = backendRoot;
                P(i).backendField = backendField;
                P(i).backendSubfield = backendSubfield;
                P(i).backendIndex = i;
                P(i).backendColumn = 2;
                P(i).backendLayout = 'paramsArray';
                P(i).visibleIf = [];
                P(i).taskModes = {};
                P(i) = NMLearnerSchemaRegistry.enrichNestedParam(P(i), algorithm, framework);
            end
            schema.params = P;
        end
    end

    methods (Static, Access = private)
        function P = emptyParamSchema()
            P = struct('name',{},'label',{},'format',{},'allowedValues',{},'defaultValue',{}, ...
                'visibleNormal',{},'visibleExpert',{},'kind',{},'backendRoot',{},'backendField',{}, ...
                'backendSubfield',{},'backendIndex',{},'backendColumn',{},'backendLayout',{}, ...
                'visibleIf',{},'taskModes',{},'dependentOn',{},'selectorValues',{},'nestedSchemasByValue',{});
        end

        function tf = visibleNormal(algorithm, idx, n)
            alg = char(algorithm);
            if strcmpi(alg,'MLPERC')
                tf = idx <= 4;
            elseif strcmpi(alg,'TFDEEP')
                tf = idx < n;
            else
                tf = true;
            end
        end

        function P = flatParam(name, label, defaultValue, visibleIf, varargin)
            P = NMLearnerSchemaRegistry.emptyParamSchema();
            P(1).name = char(name);
            P(1).label = char(label);
            P(1).format = 'e';
            P(1).allowedValues = {};
            P(1).defaultValue = defaultValue;
            P(1).visibleNormal = true;
            P(1).visibleExpert = true;
            P(1).kind = 'range';
            P(1).backendRoot = 'GRD';
            P(1).backendField = char(name);
            P(1).backendSubfield = '';
            P(1).backendIndex = 0;
            P(1).backendColumn = 0;
            P(1).backendLayout = 'flatGRD';
            P(1).visibleIf = visibleIf;
            P(1).taskModes = {};
            P(1).dependentOn = '';
            P(1).selectorValues = {};
            P(1).nestedSchemasByValue = struct();
            if ~isempty(varargin)
                for kk = 1:2:numel(varargin)
                    P(1).(varargin{kk}) = varargin{kk+1};
                end
            end
        end

        function P = kernelParam(name, label, defaultValue, visibleIf)
            P = NMLearnerSchemaRegistry.flatParam(name, label, defaultValue, visibleIf);
        end

        function rule = kernelWidthRule()
            rule = struct('all',{{struct('field','algorithm','in',{NMLearnerLibrary.kernelLearnerIds()}), ...
                struct('field','kernelSettings.kernstr','in',{{' -t 1',' -t 2',' --t 2','rbf','gauss','gaussian','poly','polynomial','Polynomial','polyN','hpolyN',' -t 6',' -t 7','expo','laplace','cauchy','cubic','tps','r'}})}});
        end

        function rule = kernelCoefRule()
            rule = struct('all',{{struct('field','algorithm','in',{NMLearnerLibrary.kernelLearnerIds()}), ...
                struct('field','kernelSettings.kernstr','in',{{' -t 1','poly','polynomial','Polynomial','polyN',' -t 3'}})}});
        end

        function rule = kernelDegreeRule()
            rule = struct('all',{{struct('field','algorithm','in',{NMLearnerLibrary.kernelLearnerIds()}), ...
                struct('field','kernelSettings.kernstr','in',{{' -t 1','poly','polynomial','Polynomial','polyN','hpolyN'}})}});
        end

        function rule = wlKernelRule()
            rule = struct('all',{{struct('field','algorithm','in',{NMLearnerLibrary.kernelLearnerIds()}), ...
                struct('field','kernelSettings.kernstr','equals',' -t 4'),struct('field','kernelSettings.kerndef','notEquals',8)}});
        end

        function P = randomForestFlatParams(mode)
            P = NMLearnerSchemaRegistry.emptyParamSchema();
            baseRule = struct('field','algorithm','equals','RNDFOR');
            P = [P, ...
                NMLearnerSchemaRegistry.flatParam('Treeparams','Number of decision trees',NMLearnerSchemaRegistry.legacyDefaultValue('Treeparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('NumDparams','Maximum number of features',NMLearnerSchemaRegistry.legacyDefaultValue('NumDparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('RFCritdefsparams','Split-quality criterion',NMLearnerSchemaRegistry.legacyDefaultValue('RFCritdefsparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('RFMaxDparams','Maximum tree depth',NMLearnerSchemaRegistry.legacyDefaultValue('RFMaxDparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('RFMinSSplitparams','Minimum samples to split',NMLearnerSchemaRegistry.legacyDefaultValue('RFMinSSplitparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('RFMinSLeafparams','Minimum samples per leaf',NMLearnerSchemaRegistry.legacyDefaultValue('RFMinSLeafparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('RFMinWFLeafparams','Minimum weighted fraction per leaf',NMLearnerSchemaRegistry.legacyDefaultValue('RFMinWFLeafparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('RFMaxLeafNparams','Maximum leaf nodes',NMLearnerSchemaRegistry.legacyDefaultValue('RFMaxLeafNparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('RFMinImpDecrparams','Minimum impurity decrease',NMLearnerSchemaRegistry.legacyDefaultValue('RFMinImpDecrparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('RFBootstrapparams','Bootstrap samples',NMLearnerSchemaRegistry.legacyDefaultValue('RFBootstrapparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('RFOobScoreparams','Out-of-bag score',NMLearnerSchemaRegistry.legacyDefaultValue('RFOobScoreparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('RFCcpAlphaparams','Minimal cost-complexity pruning alpha',NMLearnerSchemaRegistry.legacyDefaultValue('RFCcpAlphaparams',mode),baseRule), ...
                NMLearnerSchemaRegistry.flatParam('RFMaxSampparams','Maximum bootstrap sample count',NMLearnerSchemaRegistry.legacyDefaultValue('RFMaxSampparams',mode),baseRule)];
            if strcmpi(mode,'classification')
                P = [P, NMLearnerSchemaRegistry.flatParam('RFClassWeightparams','Class weights',NMLearnerSchemaRegistry.legacyDefaultValue('RFClassWeightparams',mode),baseRule)];
            end
        end

        function val = legacyDefaultValue(field, mode)
            if nargin < 2 || isempty(mode), mode = 'classification'; end
            if strcmpi(mode,'IMRELF')
                if strcmp(field,'Cparams'), val = [0.5 1 2 4 8 16 32]; return; end
                if strcmp(field,'Gparams'), val = [0.5 .1 0.05 0.01 0.005 0.001]; return; end
            end
            switch char(field)
                case 'Cparams'
                    if strcmpi(mode,'regression'), val = 2.^(-6:1:0); else, val = 2.^(-6:1:4); end
                case 'Gparams', val = 2.^(-15:2:3);
                case 'Epsparams', val = [0.05 0.075 0.1 0.125 0.15 0.2];
                case 'Nuparams', val = [0.2 0.5 0.7];
                case 'Tolparams', val = [1e-6 1e-5 1e-4 1e-3 1e-2];
                case 'PolyCoefparams', val = 0;
                case 'PolyDegrparams', val = 3;
                case 'WLiters', val = [2 4 6 8 10];
                case 'Neuronparams', val = [25 50 75 100];
                case 'Kparams', val = 7;
                case 'Weightparams', val = 1;
                case 'Leafparams', val = logspace(1,2,10);
                case 'Treeparams', val = 100;
                case 'NumDparams', val = -1;
                case 'RFCritdefsparams', val = 1;
                case 'RFMaxDparams'
                    if strcmpi(mode,'regression'), val = 1.0; else, val = 0; end
                case 'RFMinSSplitparams', val = 2;
                case 'RFMinSLeafparams', val = 1;
                case 'RFMinWFLeafparams', val = 0.0;
                case 'RFMaxLeafNparams', val = 0;
                case 'RFMinImpDecrparams', val = 0.0;
                case 'RFBootstrapparams', val = 1;
                case 'RFOobScoreparams', val = 0;
                case 'RFClassWeightparams', val = 0;
                case 'RFCcpAlphaparams', val = 0.0;
                case 'RFMaxSampparams', val = 0;
                case 'CutOffparams', val = 10;
                case 'LimsLparams', val = 50;
                case 'LimsUparams', val = 50;
                case 'CoxCutoffparams', val = 20:10:80;
                otherwise, val = [];
            end
        end

        function kind = kindFromFormat(fmt)
            f = char(fmt);
            if strcmp(f,'yes|no')
                kind = 'boolean';
            elseif strcmp(f,'model_selector')
                kind = 'model_selector';
            elseif strcmp(f,'options_selector')
                kind = 'options_selector';
            elseif strcmp(f,'kernel_func_selector')
                kind = 'kernel_func_selector';
            elseif strcmp(f,'kernel_params_selector')
                kind = 'kernel_params_selector';
            elseif contains(f,'|')
                kind = 'categorical';
            elseif any(strcmp(f, {'i','e','mlp_struct_def'}))
                kind = 'range';
            elseif strcmp(f,'tf_struct_file_def')
                kind = 'file_list';
            else
                kind = 'value';
            end
        end

        function value = normalizeDefaultForKind(value, kind, allowedValues)
            if strcmp(char(kind),'categorical') && isnumeric(value) && isscalar(value) && ...
                    value >= 1 && value <= numel(allowedValues) && ~isempty(allowedValues)
                cand = allowedValues{value};
                if ischar(cand) || isstring(cand)
                    value = char(cand);
                end
            end
        end

        function vals = allowedValuesFromFormatAndSel(fmt, sel)
            vals = {};
            if iscell(sel) && ~isempty(sel)
                for i = 1:numel(sel)
                    vals{end+1} = sel{i}; %#ok<AGROW>
                end
                return;
            end
            if isnumeric(sel) && ~isempty(sel)
                for i = 1:numel(sel)
                    vals{end+1} = sel(i); %#ok<AGROW>
                end
                return;
            end
            if ischar(fmt) || isstring(fmt)
                labels = NMLearnerSchemaRegistry.splitFormatLabels(char(fmt));
                for i = 1:numel(labels)
                    vals{end+1} = labels{i}; %#ok<AGROW>
                end
            end
        end

        function labels = splitFormatLabels(fmt)
            if isempty(fmt) || ~ischar(fmt) || ~contains(fmt,'|')
                labels = {};
            else
                labels = strsplit(fmt,'|');
                labels = cellfun(@strtrim, labels, 'UniformOutput', false);
            end
        end

        function out = getOptField(opt, field, fallback)
            if isstruct(opt) && isfield(opt,field)
                out = opt.(field);
            else
                out = fallback;
            end
        end

        function c = forceCell(x)
            if iscell(x)
                c = x;
            elseif isstring(x)
                c = cellstr(x);
            elseif ischar(x)
                c = {x};
            elseif isnumeric(x) || islogical(x)
                c = num2cell(x);
            elseif isempty(x)
                c = {};
            else
                c = {x};
            end
        end

        function v = cellAt(c, i, fallback)
            if iscell(c) && numel(c) >= i
                v = c{i};
            else
                v = fallback;
            end
        end

        function s = scalarText(v)
            if isstring(v), v = char(v); end
            if ischar(v)
                s = v;
            elseif iscell(v) && ~isempty(v)
                s = NMLearnerSchemaRegistry.scalarText(v{1});
            elseif isnumeric(v) || islogical(v)
                s = mat2str(v);
            else
                s = '';
            end
        end

        function P = enrichNestedParam(P, algorithm, framework)
            if ~isfield(P,'kind') || isempty(P.kind), return; end
            switch char(P.kind)
                case 'model_selector'
                    vals = NMLearnerSchemaRegistry.matLearnSublearnerValues(framework);
                    P.selectorValues = vals;
                    P.allowedValues = vals;
                case 'options_selector'
                    P.dependentOn = 'subModel';
                    P.nestedSchemasByValue = NMLearnerSchemaRegistry.nestedSchemasForSublearners(framework, P.backendRoot, P.backendField, P.backendSubfield);
                case 'kernel_func_selector'
                    vals = NMLearnerSchemaRegistry.kernelFunctionValues(algorithm);
                    P.selectorValues = vals;
                    P.allowedValues = vals;
                case 'kernel_params_selector'
                    P.dependentOn = 'kernelFunc';
                    P.nestedSchemasByValue = NMLearnerSchemaRegistry.nestedSchemasForKernels(algorithm, framework, P.backendRoot, P.backendField, P.backendSubfield);
            end
        end

        function vals = matLearnSublearnerValues(framework)
            opt = NMLearnerSchemaRegistry.matLearnSublearnerOptions(framework);
            vals = NMLearnerSchemaRegistry.selectorValuesFromOpt(opt, @(v) sprintf('@ml_%s_%s', framework, char(v)));
        end

        function S = nestedSchemasForSublearners(framework, backendRoot, backendField, backendSubfield)
            opt = NMLearnerSchemaRegistry.matLearnSublearnerOptions(framework);
            S = struct();
            if isempty(opt) || ~isfield(opt,'sel'), return; end
            for ii = 1:numel(opt.sel)
                alg = char(opt.sel{ii});
                pOpt = NMLearnerSchemaRegistry.matLearnOptionsForLearner(alg, framework);
                schema = NMLearnerSchemaRegistry.optionsToSchema(alg, pOpt, backendRoot, backendField, backendSubfield, framework);
                schema.framework = framework;
                safe = NMLearnerSchemaRegistry.safeFieldName(alg);
                S.(safe) = schema;
            end
        end

        function vals = kernelFunctionValues(algorithm)
            opt = NMLearnerSchemaRegistry.kernelFunctionOptions(algorithm);
            vals = NMLearnerSchemaRegistry.selectorValuesFromOpt(opt, @(v) v);
        end

        function S = nestedSchemasForKernels(algorithm, framework, backendRoot, backendField, backendSubfield) %#ok<INUSD>
            opt = NMLearnerSchemaRegistry.kernelFunctionOptions(algorithm);
            S = struct();
            if isempty(opt) || ~isfield(opt,'sel'), return; end
            for ii = 1:numel(opt.sel)
                kval = char(opt.sel{ii});
                pOpt = NMLearnerSchemaRegistry.kernelParamsOptions(kval, algorithm, framework);
                schema = NMLearnerSchemaRegistry.optionsToSchema(kval, pOpt, backendRoot, backendField, backendSubfield, framework);
                schema.framework = framework;
                safe = NMLearnerSchemaRegistry.safeFieldName(kval);
                S.(safe) = schema;
            end
        end

        function opt = matLearnSublearnerOptions(framework)
            try
                if exist('nk_matLearn_getopts_config','file') == 2
                    opt = nk_matLearn_getopts_config([], 'get_sublearners', [], [], framework);
                    return;
                end
            catch
            end
            opt = struct('desc','Select sublearner','name','algo','def',1,'format','','sel',{{}});
            switch framework
                case 'regression'
                    opt.format = 'Naive Bayes Squared Loss Linear Regression|Mean regression|Stump regression';
                    opt.sel = {'NB','mean','stump'};
                otherwise
                    opt.format = 'Decision Stump Classifier|Broken Stump Classifier|SVM|Logistic regression with L2-regularization|GLM with extreme link|GLM with Cauchit link|GLM optimizing the exponential loss';
                    opt.sel = {'stump','brokenStump','SVM','logistic','extreme','Cauchit','exponential'};
            end
        end

        function opt = kernelFunctionOptions(algorithm)
            try
                if exist('nk_matLearn_getopts_config','file') == 2
                    opt = nk_matLearn_getopts_config([], 'get_kernel_func', char(algorithm), [], []);
                    return;
                end
            catch
            end
            opt = struct('desc','Select kernel function','def',1,'name','kernelFunc');
            if strcmp(char(algorithm),'ROBSVM')
                opt.format = 'Linear|Polynomial|RBF';
                opt.sel = {'-t 0','-t 1','-t 2'};
            else
                opt.format = 'Linear|Polynomial|RBF';
                opt.sel = {'@ml_kernel_gram','@ml_kernel_poly','@ml_kernel_rbf'};
            end
        end

        function opt = kernelParamsOptions(kval, algorithm, framework) %#ok<INUSD>
            try
                if exist('nk_matLearn_getopts_config','file') == 2
                    opt = nk_matLearn_getopts_config([], 'get_kernel_params', char(kval), [], framework);
                    return;
                end
            catch
            end
            switch char(kval)
                case '@ml_kernel_rbf'
                    opt = NMLearnerSchemaRegistry.opt({'Define sigma of RBF kernel'},{'e'},{{}}, {1}, {'sigma'});
                case '@ml_kernel_poly'
                    opt = NMLearnerSchemaRegistry.opt({'Add bias to the polynomial basis','Define degree of polynomial basis'},{'yes|no','i'},{[1 0],[]}, {1,2}, {'bias','order'});
                case '-t 1'
                    opt = NMLearnerSchemaRegistry.opt({'Define coefficient of polynomial basis','Define degree of polynomial basis'},{'i','i'},{{},{}}, {0,2}, {'coef0','degree'});
                case '-t 2'
                    opt = NMLearnerSchemaRegistry.opt({'Define sigma of RBF kernel'},{'e'},{{}}, {2.^(-10:2:0)}, {'gamma'});
                otherwise
                    opt = [];
            end
        end

        function vals = selectorValuesFromOpt(opt, valueFcn)
            vals = struct('value',{},'label',{},'key',{});
            if isempty(opt) || ~isfield(opt,'sel'), return; end
            labels = NMLearnerSchemaRegistry.splitFormatLabels(opt.format);
            for jj = 1:numel(opt.sel)
                raw = opt.sel{jj};
                lab = char(raw);
                if jj <= numel(labels) && ~isempty(labels{jj}), lab = labels{jj}; end
                val = valueFcn(raw);
                vals(jj).value = val; %#ok<AGROW>
                vals(jj).label = lab; %#ok<AGROW>
                vals(jj).key = NMLearnerSchemaRegistry.safeFieldName(char(raw)); %#ok<AGROW>
            end
        end

        function s = safeFieldName(x)
            s = regexprep(char(x),'[^A-Za-z0-9_]','_');
            if isempty(s), s = 'empty'; end
            if ~isletter(s(1)), s = ['x_' s]; end
            s = matlab.lang.makeValidName(s);
        end

        function opt = matLearnLearnerOptions(framework)
            try
                if exist('nk_matLearn_getopts_config','file') == 2
                    opt = nk_matLearn_getopts_config([], 'get_learners', [], [], framework);
                    return;
                end
            catch
            end
            opt = struct('desc','Select matLearn algorithm','name','algo','def',1,'format','','sel',{{}});
            switch framework
                case 'regression'
                    opt.format = ['Absolute Loss Linear Regression|Squared Loss Linear Regression|Least Squares Regression|Student''s Loss Regression|', ...
                        'K-Nearest Neighbour Regression|Naive Bayes Squared Loss Linear Regression|Multi-layer Perceptron with tanh Activation Function|', ...
                        'Local Regression|Huberized regression|Mean regression|Stump regression|GAM model|Type-2 MLE ARD regression'];
                    opt.sel = {'L1','L2','leastSquares','student','NW','NB','MLP','local','Huber','mean','stump','GAM','ARD'};
                otherwise
                    opt.format = ['Boosting Algorithm|Decision Stump Classifier|Broken Stump Classifier|Huberized hinge-loss SVM|L2-SVM|', ...
                        'Smooth SVM|Logistic regression|Elastic-net logistic regression|Random Forest|Multi-layer Perceptron|', ...
                        'GLM with extreme link|GLM with Cauchit link|GLM exponential loss'];
                    opt.sel = {'boosting','stump','brokenStump','HSVM','SVM','SSVM','logistic','elastic_net','randomForest','MLP','extreme','Cauchit','exponential'};
            end
        end

        function opt = matLearnOptionsForLearner(algo, framework)
            try
                if exist('nk_matLearn_getopts_config','file') == 2
                    opt = nk_matLearn_getopts_config([], 'get_learner_params', char(algo), [], framework);
                    if ~isempty(opt), return; end
                end
            catch
            end
            opt = NMLearnerSchemaRegistry.matLearnFallbackOptions(char(algo), framework);
        end

        function opt = matLearnFallbackOptions(algo, framework)
            opt = struct('desc',{{}},'format',{{}},'sel',{{}},'def',{{}},'name',{{}});
            switch char(algo)
                case {'stump','brokenStump','mean','NW'}
                    opt = [];
                case 'leastSquares'
                    opt = NMLearnerSchemaRegistry.opt({'Define L2-lambda parameter range'},{'e'},{{}}, {0}, {'lambdaL2'});
                case {'L1','L2','NB','SVM','exponential','logistic'}
                    opt = NMLearnerSchemaRegistry.opt({'Add bias','Define L2-lambda parameter range'},{'yes|no','e'},{[1 0],[]}, {1,0}, {'addBias','lambdaL2'});
                case 'elastic_net'
                    opt = NMLearnerSchemaRegistry.opt({'Add bias','Define L1-lambda parameter range','Define L2-lambda parameter range'},{'yes|no','e','e'},{[1 0],[],{}}, {1,0,0}, {'addBias','lambdaL1','lambdaL2'});
                case 'student'
                    opt = NMLearnerSchemaRegistry.opt({'Add bias','Define L2-lambda parameter range','Define polynomial coefficient range'},{'yes|no','e','e'},{[1 0],[],{}}, {1,0,1}, {'addBias','lambdaL2','poly'});
                case 'MLP'
                    if strcmp(framework,'binaryclass')
                        opt = NMLearnerSchemaRegistry.opt({'Define vector of the size of each hidden layer'},{'e'},{{}}, {[3 3 3]}, {'nHidden'});
                    else
                        opt = NMLearnerSchemaRegistry.opt({'Define sizes of hidden layers','Define active function'},{'e','s'},{{},{'tanh'}}, {[3 6 9],'tanh'}, {'nHidden','activFunc'});
                    end
                case 'local'
                    opt = NMLearnerSchemaRegistry.opt({'Select submodel learner','Define submodel options','Number of neighbours','Weighting function'}, ...
                        {'model_selector','options_selector','i','s'},{{},{},{},{}}, {[],[],1,1}, {'subModel','subOptions','k','weightingFunc'});
                case 'Huber'
                    opt = NMLearnerSchemaRegistry.opt({'Add bias','Define L2-lambda parameter range','Define epsilon parameter range'},{'yes|no','e','e'},{[1 0],[],{}}, {1,0,1}, {'addBias','lambdaL2','epsilon'});
                case 'ARD'
                    opt = NMLearnerSchemaRegistry.opt({'Add bias','Define sigma2 parameter'},{'yes|no','e'},{[1 0],[]}, {1,0}, {'addBias','sigma2'});
                case 'GAM'
                    opt = NMLearnerSchemaRegistry.opt({'Define number of iterations','Define function used to determine f''s','Define highest exponent degree','Define smoothness','Define max iterations'}, ...
                        {'e','smooth cubic splines|polynomial regression|linear regresion','e','e','e'},{{},{'sp1','rg','lin'},{},{},{}}, {500,1,2,0.8,500}, {'numIter','subFunc','deg','smoothing','maxIter'});
                case 'boosting'
                    opt = NMLearnerSchemaRegistry.opt({'Select boosting algorithm','Number of weak learners','Select base classifier','Base classifier parameters'}, ...
                        {'ada|logit','e','model_selector','options_selector'},{{'ada','logit'},{},{},{}}, {1,50,[],[]}, {'booster','nBoosts','subModel','subOptions'});
                case 'HSVM'
                    opt = NMLearnerSchemaRegistry.opt({'Add bias','L1-lambda range','L2-lambda range','epsilon range','Enable kernelization','Select kernel function','Kernel parameters'}, ...
                        {'yes|no','e','e','e','yes|no','kernel_func_selector','kernel_params_selector'},{[1 0],[],{},{},{[1 0]},{},{}}, {1,0,0,0.5,0,[],[]}, {'addBias','lambdaL1','lambdaL2','epsilon','kernel','kernelFunc','kernelOptions'});
                case 'SSVM'
                    opt = NMLearnerSchemaRegistry.opt({'Add bias','L2-lambda range','Enable kernelization','Select kernel function','Kernel parameters'}, ...
                        {'yes|no','e','yes|no','kernel_func_selector','kernel_params_selector'},{[1 0],[],{[1 0]},{},{}}, {1,1,0,[],[]}, {'addBias','lambdaL2','kernel','kernelFunc','kernelOptions'});
                case {'extreme','Cauchit'}
                    opt = NMLearnerSchemaRegistry.opt({'Choose distribution','Define threshold'},{'binomial|poisson|gamma|inverse gaussian|normal','e'},{{'binomial','poisson','gamma','inverse gaussian','normal'},{}}, {'binomial',0.5}, {'dist','thresh'});
                case 'randomForest'
                    opt = NMLearnerSchemaRegistry.opt({'Number of models','Bootstrap sample size','Minimum leaf size','Maximum tree depth','Feature fraction'}, ...
                        {'e','e','e','e','e'},{{},{},{},{},{}}, {10,0.7,3,8,0.75}, {'nModels','nSample','minLeafSize','maxDepth','maxFeatures'});
            end
        end

        function opt = opt(desc, format, sel, def, name)
            opt = struct('desc',{desc},'format',{format},'sel',{sel},'def',{def},'name',{name});
        end
    end
end

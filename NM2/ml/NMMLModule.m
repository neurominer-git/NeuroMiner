classdef NMMLModule < handle
% NMMLModule
% -------------------------------------------------------------------------
% Modular ML learner configuration facade for NeuroMiner.
%
% Scope of this first port slice:
%   - canonical learner config structs;
%   - schema-compatible defaults for the browser architecture;
%   - backend-preserving export to NM.TrainParam.SVM / NM.TrainParam.GRD;
%   - import from legacy SVM/GRD without silently dropping unknown fields.
%
% This class deliberately keeps legacy nk_Model_config/nk_Grid_config and the
% nk_MLOptimizer* backend untouched.
% -------------------------------------------------------------------------

    properties
        Id char = 'ml'
        DisplayName char = 'Machine-learning configuration'
    end

    methods
        function obj = NMMLModule() %#ok<MANU>
        % NMMLModule  Construct the modular machine-learning configuration adapter.
        %   The constructor is intentionally side-effect free; state is carried in explicit config
        %   structs and in NMTrainConfigOrchestrator, not inside this module object.

        end

        function spec = configSpec(obj, ctx)
        % configSpec  Return the complete schema for browser and scripted ML configuration.
        %   The spec describes fixed card sections, editable fields, default state, per-algorithm
        %   default states, and the legacy SVM/GRD contract. Power users can inspect this method to
        %   understand which canonical config fields are accepted by validateConfig and toLegacy.

            if nargin < 2, ctx = struct(); end
            mode = NMLearnerLibrary.taskMode(ctx);
            spec = struct();
            spec.id = obj.Id;
            spec.kind = 'ml-module';
            spec.title = obj.DisplayName;
            spec.description = ['Configure the ML learner in fixed sections: optimization criterion, ', ...
                'learner settings, unified hyperparameter ranges, model optimization, ', ...
                'and cross-parameter model selection. The schema encodes the legacy CLI visibility logic. ', ...
                'Learner-specific help: ml.configureHelp(ctx,''algorithm'',''LIBSVM'').'];
            spec.layout = struct('mode','fixed-section-cards', ...
                'leftPanel',true, ...
                'sections',{obj.uiSections()});
            spec.fields = obj.uiFields(ctx, mode);
            spec.defaultState = obj.defaultConfig(ctx);
            spec.defaultStates = obj.defaultStatesByAlgorithm(ctx);
            spec.eceEligibilityRules = obj.eceEligibilityRules(ctx);
            spec.legacyContract = struct('SVM','NM.TrainParam.SVM','GRD','NM.TrainParam.GRD');
        end

        function sections = uiSections(obj) %#ok<MANU>
        % uiSections  Define the fixed high-level sections of the ML configuration surface.
        %   These section records group criterion, learner settings, hyperparameters, optimization,
        %   model selection, post-processing, and hidden legacy-preservation fields for the UI/RAG schema.

            sections = { ...
                struct('id','criterion','title','Optimization criterion','description','Legacy SVM.GridParam model-performance criterion.','fixed',true), ...
                struct('id','learner','title','Learner selection and fixed settings','description','Learning algorithm, fixed backend options, and kernel type where applicable.','fixed',true), ...
                struct('id','hyperparameters','title','Hyperparameter ranges','description','Unified schema view of all trainable GRD shelves, including legacy flat GRD and modern Params-array learners.','fixed',true), ...
                struct('id','optimization','title','Model optimization','description','Brute-force, simulated annealing, or Bayesian hyperparameter optimization.','fixed',true), ...
                struct('id','selection','title','Model-selection strategy','description','Cross-node model selection, ensemble selection, and regularization.','fixed',true), ...
                struct('id','postprocessing','title','Prediction post-processing','description','Optional legacy post-processing of predicted scores/targets.','fixed',true), ...
                struct('id','legacy','title','Legacy compatibility','description','Raw imported SVM/GRD structures retained for round-trip safety.','fixed',true,'uiHidden',true)};
        end

        function fields = uiFields(obj, ctx, mode)
        % uiFields  Build the field descriptors for the modular ML configuration UI/API schema.
        %   Field names map directly to canonical config paths consumed by validateConfig and toLegacy;
        %   visibility rules mirror legacy CLI branching without deleting hidden imported values.

            if nargin < 2, ctx = struct(); end
            if nargin < 3 || isempty(mode), mode = NMLearnerLibrary.taskMode(ctx); end
            fields = {};
            libsvmChoices = NMLearnerLibrary.learnerFixedChoices('LIBSVM',mode);
            liblinChoices = NMLearnerLibrary.learnerFixedChoices('LIBLIN',mode);
            mklChoices = NMLearnerLibrary.learnerFixedChoices('MKLRVM',mode);

            % -----------------------------------------------------------------
            % 1) Optimization criterion
            fields{end+1} = obj.uiField('performanceCriterion','enum','Model performance criterion','criterion', ...
                NMLearnerLibrary.defaultGridParam(mode), 'values', NMLearnerLibrary.evalCriterionValues(mode), ...
                'help', 'Maps to SVM.GridParam and determines whether higher or lower values are preferred.');

            % -----------------------------------------------------------------
            % 2) Learner selection and fixed settings
            fields{end+1} = obj.uiField('algorithm','enum','Learning algorithm','learner','LIBSVM', ...
                'values', NMLearnerLibrary.enumValues(ctx), ...
                'help','Changing the learner resets fixed settings and hyperparameter defaults to the legacy CLI defaults.');
            fields{end+1} = obj.uiField('fixedSettings.algo','enum','matLearn algorithm','learner',NMLearnerSchemaRegistry.defaultMatLearnAlgorithm(mode), ...
                'values',NMLearnerSchemaRegistry.matLearnAlgorithmValues(mode), ...
                'visibleIf',struct('field','algorithm','equals','matLRN'), ...
                'help','Selects the internal matLearn learner. The hyperparameter table below is rebuilt from nk_matLearn_getopts_config metadata.');
            fields{end+1} = obj.uiField('fixedSettings.learner.framework','readonly','matLearn framework','learner',NMLearnerSchemaRegistry.matLearnFramework(mode), ...
                'visibleIf',struct('field','algorithm','equals','matLRN'), ...
                'help','Derived from the current NeuroMiner task mode for backend compatibility.');

            fields{end+1} = obj.uiField('fixedSettings.LIBSVMver','enum','LIBSVM version','learner',0, ...
                'values',libsvmChoices.LIBSVMver, ...
                'visibleIf',struct('field','algorithm','equals','LIBSVM'), ...
                    'help','Select the inherited LIBSVM implementation version.');
            fields{end+1} = obj.uiField('fixedSettings.classifier','enum','LIBSVM classifier / regressor','learner',NMLearnerLibrary.defaultFixedSettings('LIBSVM',mode,ctx).classifier, ...
                'values',libsvmChoices.classifier, ...
                'visibleIf',struct('field','algorithm','equals','LIBSVM'), ...
                'help','Classifier-dependent shelves are exported as C/Nu/Eps parameters, matching nk_Grid_config.');
            fields{end+1} = obj.uiField('fixedSettings.Optimization.b','boolean','Probability estimation','learner',false, ...
                'visibleIf',struct('all',{{struct('field','algorithm','equals','LIBSVM'),struct('field','fixedSettings.classifier','notIn',{{3,4,5}})}}), ...
                    'help','Estimate class probabilities when supported by the LIBSVM type.');
            fields{end+1} = obj.uiField('fixedSettings.Optimization.m','number','Cache size [MB]','learner',500, ...
                'visibleIf',struct('field','algorithm','equals','LIBSVM'), ...
                    'help','Memory cache allocated to LIBSVM optimization, in megabytes.');
            fields{end+1} = obj.uiField('fixedSettings.Optimization.e','number','Termination criterion','learner',0.001, ...
                'visibleIf',struct('field','algorithm','equals','LIBSVM'), ...
                    'help','Stopping tolerance for LIBSVM optimization.');
            fields{end+1} = obj.uiField('fixedSettings.Optimization.h','boolean','Shrinking heuristics','learner',true, ...
                'visibleIf',struct('field','algorithm','equals','LIBSVM'), ...
                    'help','Enable the inherited LIBSVM shrinking heuristic.');
            fields{end+1} = obj.uiField('fixedSettings.Weighting','boolean','Automatic hyperplane weighting','learner',false, ...
                'visibleIf',struct('field','algorithm','in',{{'LIBSVM','LIBLIN','ROBSVM','DECTRE'}}), ...
                    'help','Enable automatic case/class weighting where supported by the learner.');
            fields{end+1} = obj.uiField('fixedSettings.W','numeric_vector','Case-level weighting vector','learner',[], ...
                'visibleIf',struct('all',{{struct('field','algorithm','equals','LIBSVM'),struct('nonEmptyField','fixedSettings.W')}}), ...
                'help','Legacy LIBSVM W vector. Hidden unless imported/defined because its length is data-dependent.');

            fields{end+1} = obj.uiField('fixedSettings.classifier','enum','LIBLINEAR classifier / regressor','learner',NMLearnerLibrary.defaultFixedSettings('LIBLIN',mode,ctx).classifier, ...
                'values',liblinChoices.classifier, ...
                'visibleIf',struct('field','algorithm','equals','LIBLIN'), ...
                'help','Select the LIBLINEAR solver; accepted codes depend on the active task mode.');
            fields{end+1} = obj.uiField('fixedSettings.b','boolean','Output probability scores','learner',false, ...
                'visibleIf',struct('all',{{struct('field','algorithm','equals','LIBLIN'),struct('field','fixedSettings.classifier','in',{{0,6,7}})}}), ...
                    'help','Request LIBLINEAR probability scores for compatible solvers.');
            fields{end+1} = obj.uiField('fixedSettings.tolerance','number','LIBLINEAR tolerance','learner',0.01, ...
                'visibleIf',struct('field','algorithm','equals','LIBLIN'), ...
                    'help','Termination tolerance for the LIBLINEAR solver.');
            fields{end+1} = obj.uiField('fixedSettings.bias','enum','Use bias term','learner',-1, ...
                'values',liblinChoices.bias, ...
                'visibleIf',struct('field','algorithm','equals','LIBLIN'), ...
                    'help','LIBLINEAR intercept: negative code disables the bias feature.');
            fields{end+1} = obj.uiField('fixedSettings.NonRegBias','boolean','Do not regularize bias','learner',false, ...
                'visibleIf',struct('all',{{struct('field','algorithm','equals','LIBLIN'),struct('field','fixedSettings.bias','equals',1),struct('field','fixedSettings.classifier','in',{{0,2,5,6,11}})}}), ...
                    'help','Exclude the LIBLINEAR bias coefficient from regularization when supported.');
            fields{end+1} = obj.uiField('fixedSettings.AutoC','boolean','Auto-optimize LIBLINEAR hyperparameters','learner',false, ...
                'visibleIf',struct('all',{{struct('field','algorithm','equals','LIBLIN'),struct('field','fixedSettings.classifier','in',{{0,2,11}})}}), ...
                    'help','Enable LIBLINEAR automatic selection of the regularization constant.');

            fields{end+1} = obj.uiField('fixedSettings.family','enum','GLMNET family','learner',NMLearnerLibrary.defaultFixedSettings('GLMNET',mode,ctx).family, ...
                'values',NMLearnerLibrary.glmnetFamilyValues(mode), ...
                'visibleIf',struct('field','algorithm','equals','GLMNET'), ...
                    'help','Select the GLMNET response family for the active task mode.');
            fields{end+1} = obj.uiField('fixedSettings.distance','enum','IMRelief distance','learner','block', ...
                'values',NMLearnerLibrary.enumFromPairs({'block','Block distance';'euclidean','Euclidean distance'}), ...
                'visibleIf',struct('field','algorithm','equals','IMRELF'), ...
                    'help','Distance metric used by the IMRelief learner.');
            fields{end+1} = obj.uiField('fixedSettings.maxiter','integer','IMRelief maximum iterations','learner',10, ...
                'visibleIf',struct('field','algorithm','equals','IMRELF'), ...
                    'help','Maximum number of IMRelief optimization iterations.');
            fields{end+1} = obj.uiField('fixedSettings.converg','enum','MKL-RVM convergence criterion','learner',1, ...
                'values',mklChoices.converg, ...
                'visibleIf',struct('field','algorithm','equals','MKLRVM'), ...
                    'help','Choose the inherited convergence criterion for MKL-RVM.');
            fields{end+1} = obj.uiField('fixedSettings.plot_flag','boolean','MKL-RVM plotting','learner',false, ...
                'visibleIf',struct('field','algorithm','equals','MKLRVM'), ...
                    'help','Enable plots while MKL-RVM is trained.');
            fields{end+1} = obj.uiField('fixedSettings.standardize_flag','boolean','MKL-RVM standardize data','learner',true, ...
                'visibleIf',struct('field','algorithm','equals','MKLRVM'), ...
                    'help','Standardize variables within MKL-RVM fitting.');
            fields{end+1} = obj.uiField('fixedSettings.nmax','number','MKL-RVM maximum iterations','learner',[], ...
                'visibleIf',struct('field','algorithm','equals','MKLRVM'), ...
                    'help','Maximum iteration count for MKL-RVM, if specified.');
            fields{end+1} = obj.uiField('fixedSettings.RVMalgo','enum','MKL-RVM algorithm','learner','RVM1', ...
                'values',NMLearnerLibrary.enumFromPairs({'RVM1','RVM1';'RVM2','RVM2'}), ...
                'visibleIf',struct('field','algorithm','equals','MKLRVM'), ...
                    'help','Select the existing RVM1/RVM2 MKL-RVM optimization variant.');
            fields{end+1} = obj.uiField('fixedSettings.iter','integer','MVTRVR iterations','learner',20, ...
                'visibleIf',struct('field','algorithm','equals','MVTRVR'), ...
                    'help','Number of multivariate relevance-vector regression iterations.');
            fields = [fields obj.seqoptFixedFields() obj.wblcoxFixedFields()];

            % -----------------------------------------------------------------
            % 3) Kernel settings
            fields{end+1} = obj.uiField('kernelSettings.kernstr','enum','Kernel type','learner',' -t 0', ...
                'values',NMLearnerLibrary.kernelValues('LIBSVM'), ...
                'visibleIf',struct('field','algorithm','in',{NMLearnerLibrary.kernelLearnerIds()}), ...
                'help','Shown only for learners that operate in kernel space. Non-linear kernels reveal the respective kernel hyperparameter ranges.');
            fields{end+1} = obj.uiField('kernelSettings.customfunc','string','Custom kernel function','learner','', ...
                'visibleIf',struct('all',{{struct('field','algorithm','equals','LIBSVM'),struct('field','kernelSettings.kerndef','equals',8)}}), ...
                    'help','Name of a custom kernel function when the custom kernel is selected.');
            fields{end+1} = obj.uiField('kernelSettings.customfunc_nargin','integer','Number of custom kernel arguments','learner',0, ...
                'visibleIf',struct('all',{{struct('field','algorithm','equals','LIBSVM'),struct('field','kernelSettings.kerndef','equals',8)}}), ...
                    'help','Number of arguments passed to the custom kernel.');

            % -----------------------------------------------------------------
            % 4) Hyperparameter ranges
            fields{end+1} = obj.uiField('hyperparameters.learnerParams','learner_param_table','Trainable hyperparameters','hyperparameters',struct('name',{},'range',{}), ...
                'paramSchemaByAlgorithm',NMLearnerSchemaRegistry.uiSchemaByAlgorithm(ctx), ...
                'displayMode','normal', ...
                'help',['Unified schema view of trainable GRD shelves. Legacy algorithms still export to flat ', ...
                        'NM.TrainParam.GRD fields, whereas modern learners export to GRD.(learner).Params. ', ...
                        'Hidden rows remain stored and are exported unchanged.']);

            % -----------------------------------------------------------------
            % 5) Hyperparameter optimization
            fields{end+1} = obj.uiField('optimizationSettings.type','enum','Hyperparameter optimization method','optimization','brute-force', ...
                'values',NMLearnerLibrary.enumFromPairs({'brute-force','Brute-force grid search';'simanneal','Simulated annealing';'bayesopt','Bayesian optimization'}), ...
                'help','Select brute-force grid search, simulated annealing, or Bayesian optimization.');
            fields = [fields obj.simAnnealFields() obj.bayesOptFields()];

            % -----------------------------------------------------------------
            % 6) Cross-parameter model selection and regularization
            fields{end+1} = obj.uiField('modelSelectionSettings.NodeSelect.mode','enum','Cross-parameter model selection','selection',1, ...
                'values',NMLearnerLibrary.nodeSelectionValues(), ...
                'help','Choose a single optimal model or an ensemble of hyperparameter configurations.');
            fields{end+1} = obj.uiField('modelSelectionSettings.NodeSelect.perc','number','Fixed ensemble percentile','selection',95, ...
                'visibleIf',struct('field','modelSelectionSettings.NodeSelect.mode','equals',2), ...
                'help','Performance percentile defining the fixed model-selection ensemble.');
            fields{end+1} = obj.uiField('modelSelectionSettings.NodeSelect.percvec','numeric_vector','Percentile search vector','selection',75:5:95, ...
                'visibleIf',struct('field','modelSelectionSettings.NodeSelect.mode','equals',4), ...
                'help','Candidate percentile thresholds for the variable-threshold ensemble.');
            % -----------------------------------------------------------------
            % 7) Post-processing and legacy preservation
            fields{end+1} = obj.uiField('postProcessingSettings.detrendOrThresholdOptimization','boolean','Detrend targets / optimize decision threshold','postprocessing',false, ...
                'visibleIf',struct('field','algorithm','notIn',{{'SEQOPT','WBLCOX','DECTRE'}}), ...
                'help','Enable the inherited output detrending or threshold-optimization procedure.');
            fields{end+1} = obj.uiField('legacySVM','struct','Raw imported SVM structure','legacy',struct(),'uiHidden',true);
            fields{end+1} = obj.uiField('legacyGRD','struct','Raw imported GRD structure','legacy',struct(),'uiHidden',true);
        end

        function visible = visibleUIFields(obj, cfg, ctx)
        % visibleUIFields  Return the subset of schema fields visible for a concrete ML config.
        %   The method validates/normalizes cfg non-strictly, applies each fieldVisible rule, and is
        %   used by browser rendering and API clients that want the same context-sensitive view.

            if nargin < 3, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            [cfg, ~] = obj.validateConfig(cfg, ctx, false);
            % Visibility depends only on field rules; per-learner default
            % states assembled by configSpec() are not consulted here.
            visible = obj.filterVisibleFields(obj.uiFields(ctx), cfg, ctx);
        end

        function sectionView = visibleUISections(obj, cfg, ctx)
        % visibleUISections  Annotate section descriptors with visible field names for a config.
        %   Uses visibleUIFields to set visibleFields, hasVisibleFields, and visible flags so the UI can
        %   hide empty sections without changing the canonical config.

            if nargin < 3, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            sectionView = obj.annotateSectionVisibility(obj.uiSections(), obj.visibleUIFields(cfg, ctx));
        end

        function names = visibleLearnerParamNames(obj, cfg, ctx)
        % visibleLearnerParamNames  Return visible learner-parameter rows for the active ML context.
        %   This is the single visibility authority for Params-style learner rows used by the browser
        %   and parent summaries. It applies the same schema visibility rules as the ML configurator.

            if nargin < 3, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            [cfg, ~] = obj.validateConfig(cfg, ctx, false);
            mode = NMLearnerLibrary.taskMode(ctx);
            alg = NMLearnerLibrary.canonicalId(cfg.algorithm);
            schema = NMLearnerSchemaRegistry.schemaForAlgorithm(alg, mode);
            if strcmpi(alg,'matLRN') && isfield(schema,'schemasByAlgorithm')
                subalg = char(string(cfg.fixedSettings.algo));
                if ~isempty(subalg) && isfield(schema.schemasByAlgorithm, subalg)
                    schema = schema.schemasByAlgorithm.(subalg);
                end
            end
            names = {};
            if ~isfield(schema,'params') || isempty(schema.params), return; end
            for ii = 1:numel(schema.params)
                param = schema.params(ii);
                if isfield(param,'visibleNormal') && ~param.visibleNormal, continue; end
                if isfield(param,'taskModes') && ~isempty(param.taskModes) && ...
                        ~any(strcmpi(mode, param.taskModes)), continue; end
                if isfield(param,'visibleIf') && ~isempty(param.visibleIf) && ...
                        ~obj.visibleRuleOk(param.visibleIf, cfg), continue; end
                if isfield(param,'name') && ~isempty(param.name)
                    names{end+1} = char(string(param.name)); %#ok<AGROW>
                end
            end
        end

        function cfg = defaultConfig(obj, ctx, algorithm) %#ok<INUSL>
        % defaultConfig  Return the canonical ML config for a learner and context.
        %   Delegates to NMLearnerLibrary.defaultConfig; this is the recommended power-user entry point
        %   for creating a modifiable MLConfig struct before calling validateConfig or toLegacy.

            if nargin < 2, ctx = struct(); end
            if nargin < 3 || isempty(algorithm), algorithm = 'LIBSVM'; end
            cfg = NMLearnerLibrary.defaultConfig(algorithm, ctx);
        end

        function states = defaultStatesByAlgorithm(obj, ctx)
        % defaultStatesByAlgorithm  Materialize default configs for all learners available in context.
        %   Used by configSpec and UI initialization to allow learner switching without interactive
        %   backend calls. A missing learner default is a configuration error and is not hidden.

            if nargin < 2, ctx = struct(); end
            ids = NMLearnerLibrary.ids(ctx);
            states = struct();
            for i = 1:numel(ids)
                id = NMLearnerLibrary.canonicalId(ids{i});
                states.(id) = obj.defaultConfig(ctx, id);
            end
        end

        function tf = probabilityOutputAvailable(obj, cfg) %#ok<INUSL>
            % Assemble the configured learner settings for determine_probflag.
            svm = struct('prog',cfg.algorithm);
            svm.(cfg.algorithm) = cfg.fixedSettings;
            % nm2-allow: fromLegacy preserves optional SVM.BBQ only for an imported LIBSVM calibration model; NMLearnerLibrary.defaultConfig has an empty legacySVM.
            if strcmp(cfg.algorithm,'LIBSVM') && isfield(cfg.legacySVM,'prog') && ...
                    strcmp(cfg.legacySVM.prog,'LIBSVM') && isfield(cfg.legacySVM,'BBQ') % nm2-allow: nk_BuildCalibrationModel only writes BBQ for calibrated LIBSVM models.
                svm.BBQ = cfg.legacySVM.BBQ;
            end
            [~,tf] = determine_probflag(svm);
        end

        function rules = eceEligibilityRules(obj, ctx)
            % Project backend eligibility into the browser without a second capability table.
            rules = struct('algorithm',{},'paths',{});
            if strcmpi(NMLearnerLibrary.taskMode(ctx),'regression'), return; end
            ids = NMLearnerLibrary.ids(ctx);
            for i = 1:numel(ids)
                cfg = obj.defaultConfig(ctx,ids{i});
                switch cfg.algorithm
                    case 'LIBSVM'
                        paths = {'fixedSettings.Optimization.b','legacySVM.BBQ.flag'};
                    case 'LIBLIN'
                        paths = {'fixedSettings.b'};
                    otherwise
                        if ~obj.probabilityOutputAvailable(cfg), continue; end
                        paths = {};
                end
                rules(end+1) = struct('algorithm',cfg.algorithm,'paths',{paths}); %#ok<AGROW>
            end
        end

        function cfg = setAlgorithm(obj, cfg, algorithm, ctx) %#ok<INUSL>
            % setAlgorithm  Replace the learner branch of an MLConfig while preserving selected state.
            %
            % Builds defaults for the requested algorithm, keeps an existing performance criterion, and
            % retains raw legacy SVM/GRD fields so imported projects can still round-trip safely.
            %
            % cfg.legacyGRD: stores the normalized legacy grd value in the module configuration.
            % cfg.legacySVM: stores the normalized legacy svm value in the module configuration.
            % cfg.performanceCriterion: stores the normalized performance criterion value in the module configuration.

            if nargin < 4, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = struct(); end
            oldLegacySVM = struct(); oldLegacyGRD = struct(); oldPerf = [];
            if isfield(cfg,'legacySVM'), oldLegacySVM = cfg.legacySVM; end
            if isfield(cfg,'legacyGRD'), oldLegacyGRD = cfg.legacyGRD; end
            if isfield(cfg,'performanceCriterion'), oldPerf = cfg.performanceCriterion; end
            cfg = NMLearnerLibrary.defaultConfig(algorithm, ctx);
            if ~isempty(oldPerf)
                oldPerf = NMLearnerLibrary.symbolicValue(oldPerf,NMLearnerLibrary.evalCriterionValues(NMLearnerLibrary.taskMode(ctx)));
                cfg.performanceCriterion = oldPerf;
                cfg.modelSelectionSettings = NMLearnerLibrary.defaultModelSelectionSettings(oldPerf);
            end
            cfg.legacySVM = oldLegacySVM;
            cfg.legacyGRD = oldLegacyGRD;
            if cfg.performanceCriterion == 21 && ~obj.probabilityOutputAvailable(cfg)
                cfg.performanceCriterion = 14;
                cfg.modelSelectionSettings = NMLearnerLibrary.defaultModelSelectionSettings(14);
                warning('NMMLModule:ECERequiresProbabilities', ...
                    'ECE is unavailable for %s without probability output. Criterion changed to BAC.',cfg.algorithm);
            end
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict)
            % validateConfig  Normalize and validate a canonical ML configuration struct.
            %
            % Merges user cfg with learner defaults, canonicalizes cfg.algorithm, checks required config
            % branches, and returns a report. In strict mode it raises NMMLModule:invalidConfig so API
            % callers fail before exporting malformed SVM/GRD.
            %
            % cfg.fixedSettings: stores the normalized fixed settings value in the module configuration.
            % cfg.hyperparameters: stores fixed or default hyperparameter values associated with the selected learner.
            % cfg.kernelSettings: stores the normalized kernel settings value in the module configuration.
            % cfg.modelSelectionSettings: stores the normalized model selection settings value in the module configuration.
            % cfg.optimizationSettings: stores the normalized optimization settings value in the module configuration.
            % cfg.performanceCriterion: stores the normalized performance criterion value in the module configuration.
            %
            % cfg.algorithm: learner identifier canonicalized through NMLearnerLibrary before validating ML branches.

            if nargin < 3, ctx = struct(); end
            if nargin < 4 || isempty(strict), strict = true; end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            if ~isfield(cfg,'algorithm') || isempty(cfg.algorithm), cfg.algorithm = 'LIBSVM'; end
            alg = NMLearnerLibrary.canonicalId(cfg.algorithm);
            base = NMLearnerLibrary.defaultConfig(alg, ctx);
            cfg = obj.mergeStruct(base, cfg);
            cfg.algorithm = alg;
            cfg.performanceCriterion = NMLearnerLibrary.symbolicValue(cfg.performanceCriterion, NMLearnerLibrary.evalCriterionValues(NMLearnerLibrary.taskMode(ctx)));
            cfg.modelSelectionSettings.NodeSelect.mode = NMLearnerLibrary.symbolicValue( ...
                cfg.modelSelectionSettings.NodeSelect.mode,NMLearnerLibrary.nodeSelectionValues());
            fixedChoices = NMLearnerLibrary.learnerFixedChoices(alg,NMLearnerLibrary.taskMode(ctx));
            names = fieldnames(fixedChoices);
            for k = 1:numel(names)
                name = names{k};
                cfg.fixedSettings.(name) = NMLearnerLibrary.symbolicValue( ...
                    cfg.fixedSettings.(name),fixedChoices.(name));
            end
            report = struct('ok',true,'errors',{{}},'warnings',{{}});
            if strcmp(alg,'SEQOPT')
                C = cfg.fixedSettings.C;
                % Browser transport uses trailing zero padding; the backend uses NaN.
                C(C == 0) = NaN;
                if any(isfinite(C(:)) & (C(:) < 1 | C(:) ~= fix(C(:))))
                    report.errors{end+1} = 'Sequence entries must be positive integer prediction-source indices.';
                end
                for row = 1:size(C,1)
                    nodes = C(row,isfinite(C(row,:)));
                    if numel(unique(nodes)) ~= numel(nodes)
                        report.errors{end+1} = sprintf('Sequence %d repeats a prediction source.',row);
                    end
                    if ~isequaln(C(row,:),[nodes NaN(1,size(C,2)-numel(nodes))])
                        report.errors{end+1} = sprintf('Sequence %d contains a gap between prediction sources.',row);
                    end
                end
                cfg.fixedSettings.C = C;
            end
            ids = NMLearnerLibrary.ids(ctx);
            if ~any(strcmpi(cfg.algorithm, ids))
                report.warnings{end+1} = sprintf('Algorithm %s is not in the task-mode list; legacy import/export will still preserve it if possible.', cfg.algorithm);
            end
            if ~(isnumeric(cfg.performanceCriterion) && isscalar(cfg.performanceCriterion))
                report.errors{end+1} = 'performanceCriterion must be a scalar numeric NeuroMiner GridParam code.';
            elseif cfg.performanceCriterion == 21 && ~obj.probabilityOutputAvailable(cfg)
                report.errors{end+1} = 'ECE requires probability output from the configured classification learner.';
            end
            if ~isstruct(cfg.fixedSettings), report.errors{end+1} = 'fixedSettings must be a struct.'; end
            if ~isstruct(cfg.kernelSettings), report.errors{end+1} = 'kernelSettings must be a struct.'; end
            if ~isstruct(cfg.hyperparameters), report.errors{end+1} = 'hyperparameters must be a struct.'; end
            if ~isstruct(cfg.optimizationSettings)
                report.errors{end+1} = 'optimizationSettings must be a struct.';
            else
                optType = '';
                if isfield(cfg.optimizationSettings,'type') && ~isempty(cfg.optimizationSettings.type)
                    optType = lower(strtrim(char(string(cfg.optimizationSettings.type))));
                end
                if ~any(strcmp(optType, {'brute-force','simanneal','bayesopt'}))
                    report.errors{end+1} = sprintf('Unsupported optimizationSettings.type "%s". Use brute-force, simanneal, or bayesopt.', optType);
                else
                    cfg.optimizationSettings.type = optType;
                end
            end
            if ~isstruct(cfg.modelSelectionSettings), report.errors{end+1} = 'modelSelectionSettings must be a struct.'; end
            if isstruct(cfg.modelSelectionSettings) && isfield(cfg.modelSelectionSettings,'OptRegul') && ...
                    isstruct(cfg.modelSelectionSettings.OptRegul) && ~isempty(cfg.modelSelectionSettings.OptRegul)
                optRegul = cfg.modelSelectionSettings.OptRegul;
                if numel(optRegul) > 1, optRegul = optRegul(1); end
                optRegul.flag = false;
                cfg.modelSelectionSettings.OptRegul = optRegul;
            end
            report.ok = isempty(report.errors);
            if report.ok && NMLearnerLibrary.usesKernel(alg) && ...
                    any(strcmp(alg,NMLearnerLibrary.kernelLearnerIds()))
                cfg.kernelSettings.kernstr = NMLearnerLibrary.kernelValue(alg,cfg.kernelSettings.kernstr);
            end
            if strict && ~report.ok
                error('NMMLModule:invalidConfig','Invalid ML configuration:\n%s', strjoin(report.errors, newline));
            end
        end


        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
        % cli_configure  Non-interactive CLI/API configuration entry point for the ML module.
        %   Validates the supplied canonical config and exports legacy SVM/GRD structs without launching
        %   nk_Model_config or nk_Grid_config. act is currently zero and aux carries validation details.

            if nargin < 3, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            [cfg, report] = obj.validateConfig(cfg, ctx, true); %#ok<ASGLU>
            [legacy.SVM, legacy.GRD] = obj.toLegacy(cfg, ctx);
            act = 0;
            aux = struct('validation', report);
        end

        function [cfg, legacy, act, aux] = configure(obj, ctx, cfg)
        % configure  Backward-compatible alias for cli_configure.
        %   Preserves early scaffold call order configure(ctx,cfg) while routing through the validated
        %   non-interactive ML configuration path; kept public to avoid breaking scripts or tests.

            if nargin < 2 || isempty(ctx), ctx = struct(); end
            if nargin < 3, cfg = []; end
            [cfg, legacy, act, aux] = obj.cli_configure(cfg, ctx);
        end

        function h = cli_configureHelp(obj, varargin)
        % Return the authoritative ML schema for agents or print it for human users.
            ctx = struct();
            if ~isempty(varargin), ctx = varargin{1}; end
            opts = struct();
            opts.algorithm = 'Canonical learner identifier, e.g. LIBSVM, LIBLIN, GLMNET.';
            opts.performanceCriterion = 'Criterion shortLabel from NMLearnerLibrary.criterionCatalog(), or legacy GridParam code.';
            opts.hyperparameters = 'Trainable parameter rows from NMLearnerSchemaRegistry.';
            opts.fixedSettings = 'Learner-specific fixed settings (see P11 learner schema).';
            h = NMConfigureAPITools.helpStruct('NMMLModule.cli_configure', ...
                '[cfg, legacy, act, aux] = NMMLModule().cli_configure(existingMLConfig, ctx)', opts, ...
                {'ctx = struct(''modeflag'',''classification''); ml = NMMLModule(); cfg = ml.defaultConfig(ctx); cfg.performanceCriterion = ''AUC''; [cfg, legacy] = ml.cli_configure(cfg,ctx);'});
            h.configSpec = obj.configSpec(ctx);
            if numel(varargin)>1
                assert(numel(varargin)==3, ...
                    'NMMLModule:invalidHelpSelector','Use configureHelp(ctx,''algorithm'',learnerID).');
                assert(strcmp(varargin{2},'algorithm'), ...
                    'NMMLModule:invalidHelpSelector','Use configureHelp(ctx,''algorithm'',learnerID).');
                alg = NMLearnerLibrary.canonicalId(varargin{3});
                assert(any(strcmp(alg,NMLearnerLibrary.ids(ctx))), ...
                    'NMMLModule:invalidHelpSelector','Unknown learner: %s',alg);
                cfg = h.configSpec.defaultStates.(alg);
                fields = {};
                for k = 1:numel(h.configSpec.fields)
                    f = h.configSpec.fields{k};
                    if strcmp(f.section,'learner') && obj.fieldVisible(f,cfg,ctx)
                        fields{end+1} = f; %#ok<AGROW>
                    elseif strcmp(f.type,'learner_param_table')
                        learnerSchema = f.paramSchemaByAlgorithm.(alg);
                    end
                end
                if strcmp(alg,'matLRN')
                    learnerSchema = learnerSchema.schemasByAlgorithm.(cfg.fixedSettings.algo);
                end
                for k = 1:numel(learnerSchema.params)
                    param = learnerSchema.params(k);
                    f = obj.uiField(['hyperparameters.' param.name],param.kind,param.label, ...
                        'hyperparameters',param.defaultValue, ...
                        'help','Candidate parameter range searched during learner optimization.');
                    if ~isempty(param.allowedValues), f.values = param.allowedValues; end
                    fields{end+1} = f; %#ok<AGROW>
                end
                h.learnerSchema = learnerSchema;
                h.configSpec = struct('id',alg,'title',NMLearnerLibrary.title(alg), ...
                    'description','Fixed learner settings and trainable hyperparameters from the existing ML schema.', ...
                    'fields',{fields});
            end
            if nargout == 0, fprintf('%s\n',NMConfigureAPITools.formatConfigSpec(h.configSpec)); end
        end

        function h = configureHelp(obj, varargin)
        % Same structured/help presentation contract as the preprocessing modules.
            h = obj.cli_configureHelp(varargin{:});
            if nargout == 0, fprintf('%s\n',NMConfigureAPITools.formatConfigSpec(h.configSpec)); end
        end

        function ui = ui_configure(obj, cfg, ctx)
        % ui_configure  Return UI-ready schema, state, validation, and visibility for an ML config.
        %   This does not mutate NM or run training; it packages configSpec, normalized state, validation
        %   report, visible fields, and visible sections for browser front ends or scripted inspection.

            if nargin < 3, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            % One schema build and one validation per call; visibility and
            % section flags are derived from that same spec.
            spec = obj.configSpec(ctx);
            visible = obj.filterVisibleFields(spec.fields, cfg, ctx);
            ui = struct('spec',spec,'state',cfg,'validation',report, ...
                'visibleFields',{visible}, ...
                'visibleSections',{obj.annotateSectionVisibility(spec.layout.sections, visible)});
        end

        function [SVM, GRD] = toLegacy(obj, cfg, ctx)
            % toLegacy  Export canonical MLConfig to legacy NM.TrainParam.SVM and GRD structs.
            %
            % This is the principal backend-compatibility function for power users. It validates cfg,
            % preserves compatible imported legacy fields, writes SVM.prog/GridParam/kernel/fixed learner
            % settings, expands hyperparameter rows into GRD shelves, normalizes optimizer/model-selection
            % settings, and rebuilds PX/n_params without fitting a model.
            %
            % cfg.algorithm: stores the selected learner/preprocessing algorithm inside a normalized configuration.
            % cfg.fixedSettings: stores the normalized fixed settings value in the module configuration.
            % cfg.hyperparameters: stores fixed or default hyperparameter values associated with the selected learner.
            % cfg.kernelSettings: stores the normalized kernel settings value in the module configuration.
            % cfg.legacyGRD: stores the normalized legacy grd value in the module configuration.
            % cfg.legacySVM: stores the normalized legacy svm value in the module configuration.
            % cfg.modelSelectionSettings: stores the normalized model selection settings value in the module configuration.
            % cfg.optimizationSettings: stores the normalized optimization settings value in the module configuration.
            % cfg.performanceCriterion: stores the normalized performance criterion value in the module configuration.
            % cfg.postProcessingSettings: stores the normalized post processing settings value in the module configuration.

            if nargin < 3, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            [cfg, report] = obj.validateConfig(cfg, ctx, true); %#ok<ASGLU>
            alg = cfg.algorithm;
            mode = NMLearnerLibrary.taskMode(ctx);

            if isfield(cfg,'legacySVM') && isstruct(cfg.legacySVM) && ~isempty(fieldnames(cfg.legacySVM)) && ...
                    (~isfield(cfg.legacySVM,'prog') || strcmpi(cfg.legacySVM.prog, alg))
                SVM = cfg.legacySVM;
            else
                SVM = struct();
            end
            if isfield(cfg,'legacyGRD') && isstruct(cfg.legacyGRD) && ~isempty(fieldnames(cfg.legacyGRD))
                GRD = cfg.legacyGRD;
            else
                GRD = struct();
            end

            SVM.prog = alg;
            SVM.GridParam = cfg.performanceCriterion;
            if ~isfield(SVM,'Post') || ~isstruct(SVM.Post), SVM.Post = struct(); end
            SVM.Post.Detrend = obj.getBool(cfg.postProcessingSettings, 'detrendOrThresholdOptimization', false);
            SVM.kernel = obj.mergeStruct(NMLearnerLibrary.defaultKernelSettings(alg, mode), cfg.kernelSettings);

            fixed = cfg.fixedSettings;
            switch alg
                case 'LIBSVM'
                    SVM.LIBSVM = obj.mergeStruct(NMLearnerLibrary.defaultFixedSettings('LIBSVM', mode, ctx), fixed);
                case 'LIBLIN'
                    SVM.LIBLIN = obj.mergeStruct(NMLearnerLibrary.defaultFixedSettings('LIBLIN', mode, ctx), fixed);
                    if isfield(SVM.LIBLIN,'b') && SVM.LIBLIN.b
                        SVM.RVMflag = true;
                    end
                case 'GLMNET'
                    SVM.GLMNET = obj.mergeStruct(NMLearnerLibrary.defaultFixedSettings('GLMNET', mode, ctx), fixed);
                case 'MikRVM'
                    SVM.RVMflag = true;
                    if ~isfield(SVM,'RVM') || ~isstruct(SVM.RVM), SVM.RVM = struct(); end
                    SVM.RVM = obj.mergeStruct(NMLearnerLibrary.defaultFixedSettings('MikRVM', mode, ctx), fixed);
                case 'MKLRVM'
                    if ~isfield(SVM,'MKLRVM') || ~isstruct(SVM.MKLRVM), SVM.MKLRVM = struct(); end
                    SVM.MKLRVM = obj.mergeStruct(NMLearnerLibrary.defaultFixedSettings('MKLRVM', mode, ctx), fixed);
                case 'MVTRVR'
                    if ~isfield(SVM,'MVTRVR') || ~isstruct(SVM.MVTRVR), SVM.MVTRVR = struct(); end
                    SVM.MVTRVR = obj.mergeStruct(NMLearnerLibrary.defaultFixedSettings('MVTRVR', mode, ctx), fixed);
                case 'SEQOPT'
                    if ~isfield(SVM,'SEQOPT') || ~isstruct(SVM.SEQOPT), SVM.SEQOPT = struct(); end
                    SVM.SEQOPT = obj.mergeStruct(NMLearnerLibrary.defaultFixedSettings('SEQOPT', mode, ctx), fixed);
                case 'WBLCOX'
                    if ~isfield(SVM,'WBLCOX') || ~isstruct(SVM.WBLCOX), SVM.WBLCOX = struct(); end
                    SVM.WBLCOX = obj.mergeStruct(NMLearnerLibrary.defaultFixedSettings('WBLCOX', mode, ctx), fixed);
                otherwise
                    if ~isfield(SVM, alg) || ~isstruct(SVM.(alg)), SVM.(alg) = struct(); end
                    SVM.(alg) = obj.mergeStruct(SVM.(alg), fixed);
            end

            if any(strcmp(alg, {'kNNMEX','GLMFIT','BAYLIN','MLPERC','TFDEEP','MikRVM'}))
                SVM.RVMflag = true;
            end
            if strcmp(alg,'DECTRE')
                SVM.Post.Detrend = 0;
            end

            GRD = obj.applyHyperparametersToGRD(GRD, cfg.hyperparameters, alg, mode);
            GRD.OptMode = obj.normalizeOptMode(cfg.optimizationSettings);
            ms = obj.normalizeModelSelectionSettings(cfg.modelSelectionSettings, cfg.performanceCriterion);
            defMS = NMLearnerLibrary.defaultModelSelectionSettings(cfg.performanceCriterion);
            if isfield(ms,'GridMaxType')
                GRD.GridMaxType = obj.asNumericScalar(ms.GridMaxType, defMS.GridMaxType);
            else
                GRD.GridMaxType = defMS.GridMaxType;
            end
            if isfield(ms,'NodeSelect')
                GRD.NodeSelect = obj.normalizeNodeSelect(ms.NodeSelect, defMS.NodeSelect);
            else
                GRD.NodeSelect = obj.normalizeNodeSelect(defMS.NodeSelect, defMS.NodeSelect);
            end
            % Last-mile legacy guard: JSON import can turn vectors into columns
            % and enum values into scalar-looking strings.  Keep optimizer-facing
            % fields scalar numeric and percentile vectors as row vectors.
            GRD.NodeSelect.mode = obj.asNumericScalar(GRD.NodeSelect.mode, defMS.NodeSelect.mode);
            if isfield(GRD.NodeSelect,'perc')
                GRD.NodeSelect.perc = obj.asNumericScalar(GRD.NodeSelect.perc, defMS.NodeSelect.perc);
            end
            if isfield(GRD.NodeSelect,'percvec')
                GRD.NodeSelect.percvec = obj.asRowNumeric(GRD.NodeSelect.percvec, defMS.NodeSelect.percvec);
            else
                GRD.NodeSelect.percvec = obj.asRowNumeric(defMS.NodeSelect.percvec, defMS.NodeSelect.percvec);
            end
            if isfield(ms,'OptRegul')
                GRD.OptRegul = obj.normalizeOptRegulSettings(ms.OptRegul, defMS.OptRegul);
            else
                GRD.OptRegul = obj.normalizeOptRegulSettings(defMS.OptRegul, defMS.OptRegul);
            end
            % The browser ML configurator does not currently expose the full
            % legacy OptRegul contract. Keep it hard-disabled until that
            % configurator is restored; imported legacy flag values must not
            % silently reactivate regularized model selection.
            GRD.OptRegul.flag = false;
            GRD.opt_probability = false;
            [GRD.PX, GRD.n_params] = obj.buildPX(SVM, GRD);
        end

        function cfg = fromLegacy(obj, SVM, GRD, ctx)
        % fromLegacy  Import legacy SVM/GRD into the canonical modular MLConfig struct.
        %   Detects SVM.prog, stores raw legacy structs for round-trip safety, extracts criterion, kernel,
        %   fixed settings, hyperparameters, optimizer settings, and model-selection fields, then performs
        %   non-strict validation so partially legacy projects remain inspectable.

            if nargin < 4, ctx = struct(); end
            if nargin < 2 || isempty(SVM), SVM = struct(); end
            if nargin < 3 || isempty(GRD), GRD = struct(); end
            mode = NMLearnerLibrary.taskMode(ctx);
            if isfield(SVM,'prog') && ~isempty(SVM.prog)
                alg = NMLearnerLibrary.canonicalId(SVM.prog);
            else
                alg = 'LIBSVM';
            end
            cfg = NMLearnerLibrary.defaultConfig(alg, ctx);
            cfg.legacySVM = SVM;
            cfg.legacyGRD = GRD;
            cfg.algorithm = alg;
            if isfield(SVM,'GridParam'), cfg.performanceCriterion = SVM.GridParam; end
            if isfield(SVM,'Post') && isfield(SVM.Post,'Detrend')
                cfg.postProcessingSettings.detrendOrThresholdOptimization = logical(SVM.Post.Detrend);
            end
            if isfield(SVM,'kernel') && isstruct(SVM.kernel)
                cfg.kernelSettings = obj.mergeStruct(NMLearnerLibrary.defaultKernelSettings(alg, mode), SVM.kernel);
            end
            if strcmp(alg,'MikRVM') && isfield(SVM,'RVM') && isstruct(SVM.RVM)
                cfg.fixedSettings = SVM.RVM;
            elseif isfield(SVM, alg) && isstruct(SVM.(alg))
                cfg.fixedSettings = SVM.(alg);
            elseif strcmp(alg,'LIBSVM') && isfield(SVM,'LIBSVM')
                cfg.fixedSettings = SVM.LIBSVM;
            elseif strcmp(alg,'LIBLIN') && isfield(SVM,'LIBLIN')
                cfg.fixedSettings = SVM.LIBLIN;
            end
            cfg.hyperparameters = obj.hyperparametersFromGRD(GRD, alg, mode);
            if isfield(GRD,'OptMode'), cfg.optimizationSettings = obj.normalizeOptMode(GRD.OptMode); end
            if isfield(GRD,'GridMaxType'), cfg.modelSelectionSettings.GridMaxType = GRD.GridMaxType; end
            if isfield(GRD,'NodeSelect'), cfg.modelSelectionSettings.NodeSelect = GRD.NodeSelect; end
            if isfield(GRD,'OptRegul')
                defMS = NMLearnerLibrary.defaultModelSelectionSettings(cfg.performanceCriterion);
                cfg.modelSelectionSettings.OptRegul = obj.normalizeOptRegulSettings(GRD.OptRegul, defMS.OptRegul);
                cfg.modelSelectionSettings.OptRegul.flag = false;
            end
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok
                warning('NMMLModule:legacyConfigInvalid','Imported legacy ML config did not validate cleanly: %s', strjoin(report.errors,'; '));
            end
        end


        function shelves = parameterShelves(obj, SVM, GRD)
        % parameterShelves  Return optimizer-facing ML parameter shelves from legacy SVM/GRD.
        %   This audit/test helper exposes the trainable ranges implied by exported legacy structures and
        %   mirrors nk_MLOptimizer_main preparation without invoking cross-validation or model fitting.

            shelves = obj.collectLegacyParamRanges(SVM, GRD);
        end

        function dry = optimizerDryRun(obj, SVM, GRD, varargin)
        % optimizerDryRun  Build optimizer-facing parameter containers without fitting models.
        %   Accepts legacy SVM/GRD and optional nclass/PreML/strict arguments, collects ML shelves, appends
        %   preprocessing shelves when supplied, derives Params/Params_desc/PX/n_params, and reports alias
        %   compatibility for optimization settings. This is a safe API diagnostic for ML export integrity.

            opts = struct('nclass',1,'PreML',[],'strict',true);
            if mod(numel(varargin),2) ~= 0
                error('NMMLModule:optimizerDryRun','Optional arguments must be name/value pairs.');
            end
            for k = 1:2:numel(varargin)
                key = varargin{k};
                if isstring(key), key = char(key); end
                if isfield(opts,key)
                    opts.(key) = varargin{k+1};
                else
                    error('NMMLModule:optimizerDryRun','Unknown option: %s', key);
                end
            end
            if nargin < 2 || isempty(SVM) || ~isstruct(SVM)
                error('NMMLModule:optimizerDryRun','SVM must be a non-empty struct.');
            end
            if nargin < 3 || isempty(GRD) || ~isstruct(GRD)
                error('NMMLModule:optimizerDryRun','GRD must be a non-empty struct.');
            end
            if ~isfield(SVM,'prog') || isempty(SVM.prog)
                error('NMMLModule:optimizerDryRun','SVM.prog is required.');
            end

            errors = {};
            try
                shelves = obj.collectLegacyParamRanges(SVM, GRD);
            catch ME
                if opts.strict, rethrow(ME); end
                shelves = struct('name',{},'range',{});
                errors{end+1} = ME.message; %#ok<AGROW>
            end

            dry = struct();
            dry.ok = isempty(errors);
            dry.errors = errors;
            dry.algorithm = SVM.prog;
            dry.nclass = opts.nclass;
            dry.shelves = shelves;
            dry.Params = cell(opts.nclass,1);
            dry.Params_desc = cell(opts.nclass,1);
            dry.nMLparams = zeros(opts.nclass,1);
            dry.nPreMLparams = zeros(opts.nclass,1);
            dry.ModalityVec = cell(opts.nclass,1);

            baseParams = cell(1,numel(shelves));
            baseDesc = cell(1,numel(shelves));
            for j = 1:numel(shelves)
                baseParams{j} = shelves(j).range;
                baseDesc{j} = shelves(j).name;
            end

            hasPreML = ~isempty(opts.PreML) && isstruct(opts.PreML) && ...
                isfield(opts.PreML,'Params') && isfield(opts.PreML,'Params_desc');
            for c = 1:opts.nclass
                dry.Params{c} = baseParams;
                dry.Params_desc{c} = baseDesc;
                dry.nMLparams(c) = numel(baseParams);
                if hasPreML
                    dry.nPreMLparams(c) = numel(opts.PreML.Params_desc);
                    for p = 1:dry.nPreMLparams(c)
                        dry.Params{c}{end+1} = opts.PreML.Params{p}; %#ok<AGROW>
                        dry.Params_desc{c}{end+1} = opts.PreML.Params_desc{p}; %#ok<AGROW>
                    end
                    if isfield(opts.PreML,'ModalityVec')
                        dry.ModalityVec{c} = opts.PreML.ModalityVec;
                    end
                end
            end

            dry.n_params = obj.gridNodeCount(shelves);
            [dry.PX, dry.n_params_from_px] = obj.buildPX(SVM, GRD);
            dry.OptMode = struct();
            if isfield(GRD,'OptMode'), dry.OptMode = obj.normalizeOptMode(GRD.OptMode); end
            dry.hasBayesAliases = isfield(dry.OptMode,'Bayes') && ...
                isfield(dry.OptMode.Bayes,'LCBkappa') && isfield(dry.OptMode.Bayes,'kappa') && ...
                isfield(dry.OptMode.Bayes,'EIjitter') && isfield(dry.OptMode.Bayes,'ei_jitter');
            dry.hasAnnealAliases = isfield(dry.OptMode,'SimAneal') && isfield(dry.OptMode,'SimAnneal');
        end
    end

    methods (Access = private)
        function visible = filterVisibleFields(obj, fields, cfg, ctx)
        % filterVisibleFields  Apply uiHidden and fieldVisible rules to schema field descriptors.
        %   Single visibility filter shared by visibleUIFields and ui_configure; cfg must already be
        %   normalized by validateConfig.

            visible = {};
            for i = 1:numel(fields)
                f = fields{i};
                if isfield(f,'uiHidden') && f.uiHidden, continue; end
                if obj.fieldVisible(f, cfg, ctx)
                    visible{end+1} = f; %#ok<AGROW>
                end
            end
        end

        function sectionView = annotateSectionVisibility(obj, sectionView, visible) %#ok<INUSL>
        % annotateSectionVisibility  Attach visible field names and flags to section descriptors.
        %   Single section annotator shared by visibleUISections and ui_configure.

            for s = 1:numel(sectionView)
                sid = sectionView{s}.id;
                names = {};
                for j = 1:numel(visible)
                    if isfield(visible{j},'section') && strcmp(visible{j}.section, sid)
                        names{end+1} = visible{j}.name; %#ok<AGROW>
                    end
                end
                sectionView{s}.visibleFields = names;
                sectionView{s}.hasVisibleFields = ~isempty(names);
                hideWhenEmpty = isfield(sectionView{s}, 'hideWhenEmpty') && sectionView{s}.hideWhenEmpty;
                sectionView{s}.visible = ~(hideWhenEmpty && isempty(names));
            end
        end

        function GRD = applyHyperparametersToGRD(obj, GRD, hp, alg, mode) %#ok<INUSL>
            if nargin < 5, mode = 'classification'; end %#ok<NASGU>
            defaults = NMLearnerLibrary.defaultHyperparameters(alg, mode);
            hp = obj.mergeStruct(defaults, hp);
            directFields = {'Cparams','Gparams','Epsparams','Nuparams','Tolparams','PolyCoefparams','PolyDegrparams', ...
                'WLiters','Neuronparams','Kparams','Weightparams','Leafparams','Treeparams','NumDparams', ...
                'RFCritdefsparams','RFMaxDparams','RFMinSSplitparams','RFMinSLeafparams','RFMinWFLeafparams', ...
                'RFMaxLeafNparams','RFMinImpDecrparams','RFBootstrapparams','RFOobScoreparams','RFClassWeightparams', ...
                'RFCcpAlphaparams','RFMaxSampparams','CutOffparams','LimsLparams','LimsUparams','CoxCutoffparams'};
            for i = 1:numel(directFields)
                f = directFields{i};
                if isfield(hp,f), GRD.(f) = hp.(f); end
            end
            if isfield(hp,'learnerParams') && isstruct(hp.learnerParams)
                lp = obj.normalizeLearnerParams(hp.learnerParams);
                for rr = 1:numel(lp)
                    if isfield(lp(rr),'name') && isfield(lp(rr),'range') && any(strcmp(lp(rr).name, directFields))
                        GRD.(lp(rr).name) = lp(rr).range;
                    elseif isfield(lp(rr),'name') && numel(lp(rr).name) >= 16 && strcmp(lp(rr).name(1:16),'customkernel_arg') && isfield(lp(rr),'range')
                        GRD.(lp(rr).name) = lp(rr).range;
                    end
                end
            end
            hpFields = fieldnames(hp);
            for i = 1:numel(hpFields)
                f = hpFields{i};
                if numel(f) >= 16 && strcmp(f(1:16),'customkernel_arg')
                    GRD.(f) = hp.(f);
                end
            end
            if NMLearnerLibrary.isModernParamLearner(alg)
                if ~isfield(GRD, alg) || ~isstruct(GRD.(alg)), GRD.(alg) = struct(); end
                if isfield(hp,'learnerParams') && isstruct(hp.learnerParams)
                    GRD.(alg).Params = obj.normalizeLearnerParams(hp.learnerParams);
                else
                    param = NMLearnerLibrary.legacyLearnerParamDefaults(alg, mode);
                    if isfield(param,'Params'), GRD.(alg).Params = obj.normalizeLearnerParams(param.Params); end
                end
                if isfield(hp,'learnerOptions') && isstruct(hp.learnerOptions) && ~isempty(fieldnames(hp.learnerOptions))
                    GRD.(alg).options = hp.learnerOptions;
                else
                    param = NMLearnerLibrary.legacyLearnerParamDefaults(alg, mode);
                    if isfield(param,'options'), GRD.(alg).options = param.options; end
                    if isfield(param,'learner') && isfield(param.learner,'options'), GRD.(alg).options = param.learner.options; end
                end
            elseif strcmp(alg,'matLRN')
                if ~isfield(GRD,'matLearn') || ~isstruct(GRD.matLearn), GRD.matLearn = struct(); end
                if isfield(hp,'learnerParams') && isstruct(hp.learnerParams)
                    GRD.matLearn.Params = obj.normalizeLearnerParams(hp.learnerParams);
                elseif ~isfield(GRD.matLearn,'Params')
                    GRD.matLearn.Params = struct('name',{},'range',{});
                end
                if isfield(hp,'learnerOptions') && isstruct(hp.learnerOptions) && ~isempty(fieldnames(hp.learnerOptions))
                    GRD.matLearn.options = hp.learnerOptions;
                end
            end
        end

        function hp = hyperparametersFromGRD(obj, GRD, alg, mode) %#ok<INUSL>
            hp = NMLearnerLibrary.defaultHyperparameters(alg, mode);
            directFields = fieldnames(hp);
            for i = 1:numel(directFields)
                f = directFields{i};
                if isfield(GRD,f), hp.(f) = GRD.(f); end
            end
            if isfield(hp,'learnerParams') && isstruct(hp.learnerParams)
                for rr = 1:numel(hp.learnerParams)
                    if isfield(hp.learnerParams(rr),'name')
                        nm = hp.learnerParams(rr).name;
                        if isfield(GRD,nm)
                            hp.learnerParams(rr).range = GRD.(nm);
                        end
                    end
                end
            end
            if NMLearnerLibrary.isModernParamLearner(alg) && isfield(GRD, alg) && isstruct(GRD.(alg))
                if isfield(GRD.(alg),'Params'), hp.learnerParams = GRD.(alg).Params; end
                if isfield(GRD.(alg),'options'), hp.learnerOptions = GRD.(alg).options; end
            elseif strcmp(alg,'matLRN') && isfield(GRD,'matLearn') && isstruct(GRD.matLearn)
                if isfield(GRD.matLearn,'Params'), hp.learnerParams = GRD.matLearn.Params; end
                if isfield(GRD.matLearn,'options'), hp.learnerOptions = GRD.matLearn.options; end
            end
        end

        function opt = normalizeOptMode(obj, opt) %#ok<INUSL>
            defaults = NMLearnerLibrary.defaultOptimizationSettings();
            if nargin < 2 || isempty(opt) || ~isstruct(opt), opt = defaults; return; end
            opt = obj.mergeStruct(defaults, opt);
            if isfield(opt,'SimAneal') && isstruct(opt.SimAneal)
                opt.SimAnneal = opt.SimAneal;
            elseif isfield(opt,'SimAnneal') && isstruct(opt.SimAnneal)
                opt.SimAneal = opt.SimAnneal;
            else
                opt.SimAneal = defaults.SimAneal;
                opt.SimAnneal = defaults.SimAneal;
            end
            if ~isfield(opt,'Bayes') || ~isstruct(opt.Bayes), opt.Bayes = defaults.Bayes; end
            if ~isfield(opt.Bayes,'mode')
                if isfield(opt.Bayes,'CritMode'), opt.Bayes.mode = opt.Bayes.CritMode; else, opt.Bayes.mode = 'lcb'; end
            end
            opt.Bayes.CritMode = opt.Bayes.mode;
            if isfield(opt.Bayes,'kappa') && ~isfield(opt.Bayes,'LCBkappa'), opt.Bayes.LCBkappa = opt.Bayes.kappa; end
            if isfield(opt.Bayes,'ei_jitter') && ~isfield(opt.Bayes,'EIjitter'), opt.Bayes.EIjitter = opt.Bayes.ei_jitter; end
            if ~isfield(opt.Bayes,'LCBkappa'), opt.Bayes.LCBkappa = defaults.Bayes.LCBkappa; end
            if ~isfield(opt.Bayes,'EIjitter'), opt.Bayes.EIjitter = defaults.Bayes.EIjitter; end
            opt.Bayes.kappa = opt.Bayes.LCBkappa;
            opt.Bayes.ei_jitter = opt.Bayes.EIjitter;
        end

        function [PX, nParams] = buildPX(obj, SVM, GRD)
            PX = [];
            params = obj.collectLegacyParamRanges(SVM, GRD);
            if isempty(params)
                nParams = 0;
                return;
            end
            if exist('nk_AddParam','file') ~= 2
                error('NMMLModule:nkAddParamUnavailable', ...
                    'nk_AddParam is required to construct the authoritative ML parameter shelf.');
            end
            % Use nk_AddParam's batch interface so a categorical cell range
            % is one parameter shelf rather than being misread as multiple
            % parameter definitions. For one shelf, duplicate the identical
            % definition to select batch semantics; the second entry simply
            % overwrites the first shelf with the same value.
            ranges = {params.range};
            descs = arrayfun(@(p) ['ML-' p.name], params, 'UniformOutput', false);
            types = repmat({2}, size(ranges));
            if isscalar(ranges), ranges(2)=ranges; descs(2)=descs; types(2)=types; end
            PX = nk_AddParam(ranges, descs, types, []);
            % Legacy nk_Grid_config stores GRD.n_params as the number of
            % grid nodes, not as the number of parameter shelves. Compute it
            % directly from the exported parameter ranges to avoid depending
            % on the availability or exact implementation of nk_AddParam.
            nParams = obj.gridNodeCount(params);
        end

        function params = collectLegacyParamRanges(obj, SVM, GRD)
            params = struct('name',{},'range',{});
            alg = SVM.prog;

            % Slack / regularisation / regression parameters. This ordering
            % follows nk_MLOptimizer_main, which is the runtime consumer of
            % GRD, rather than the interactive menu order in nk_Grid_config.
            switch alg
                case 'MEXELM'
                    if isfield(GRD,'Cparams')
                        params(end+1) = obj.paramShelf('Slack',GRD.Cparams); %#ok<AGROW>
                    end
                case 'LIBSVM'
                    cls = obj.safeClassifierCode(SVM, 'LIBSVM');
                    if cls == 1
                        if isfield(GRD,'Nuparams'), params(end+1) = obj.paramShelf('Nu (SVC)',GRD.Nuparams); end %#ok<AGROW>
                    elseif cls == 4
                        if isfield(GRD,'Cparams'), params(end+1) = obj.paramShelf('Slack',GRD.Cparams); end %#ok<AGROW>
                        if isfield(GRD,'Nuparams'), params(end+1) = obj.paramShelf('Nu (SVR)',GRD.Nuparams); end %#ok<AGROW>
                    elseif cls == 3
                        if isfield(GRD,'Cparams'), params(end+1) = obj.paramShelf('Slack',GRD.Cparams); end %#ok<AGROW>
                        if isfield(GRD,'Epsparams'), params(end+1) = obj.paramShelf('Epsilon',GRD.Epsparams); end %#ok<AGROW>
                    else
                        if isfield(GRD,'Cparams'), params(end+1) = obj.paramShelf('Slack',GRD.Cparams); end %#ok<AGROW>
                    end
                case 'LIBLIN'
                    cls = obj.safeClassifierCode(SVM, 'LIBLIN');
                    if isfield(GRD,'Cparams')
                        params(end+1) = obj.paramShelf('Slack',GRD.Cparams); %#ok<AGROW>
                    end
                    if any(cls == [11 12 13]) && isfield(GRD,'Epsparams')
                        params(end+1) = obj.paramShelf('Epsilon',GRD.Epsparams); %#ok<AGROW>
                    end
                case 'IMRELF'
                    if isfield(GRD,'Cparams')
                        params(end+1) = obj.paramShelf('Lambda',GRD.Cparams); %#ok<AGROW>
                    end
                    if isfield(GRD,'Gparams')
                        params(end+1) = obj.paramShelf('Sigma',GRD.Gparams); %#ok<AGROW>
                    end
            end

            % Kernel parameters. This mirrors the parameter shelves consumed
            % in nk_MLOptimizer_main and keeps custom-kernel arguments alive.
            if isfield(SVM,'kernel') && isfield(SVM.kernel,'kernstr')
                kernstr = SVM.kernel.kernstr;
                switch kernstr
                    case {' -t 0','lin','linear','lin_kernel','none','lin_elm'}
                        % no kernel hyperparameters
                    case {' -t 1','poly','polynomial','Polynomial','polyN','hpolyN'}
                        if isfield(GRD,'Gparams')
                            params(end+1) = obj.paramShelf('Kernel',GRD.Gparams); %#ok<AGROW>
                        end
                        if isfield(GRD,'PolyCoefparams')
                            params(end+1) = obj.paramShelf('Poly coef',GRD.PolyCoefparams); %#ok<AGROW>
                        end
                        if isfield(GRD,'PolyDegrparams')
                            params(end+1) = obj.paramShelf('Poly Degree',GRD.PolyDegrparams); %#ok<AGROW>
                        end
                    case {' -t 2',' --t 2','rbf','gauss','gaussian'}
                        if isfield(GRD,'Gparams')
                            params(end+1) = obj.paramShelf('Kernel',GRD.Gparams); %#ok<AGROW>
                        end
                    case ' -t 3'
                        if isfield(GRD,'Gparams')
                            params(end+1) = obj.paramShelf('Kernel',GRD.Gparams); %#ok<AGROW>
                        end
                        if isfield(GRD,'PolyCoefparams')
                            params(end+1) = obj.paramShelf('Sigmoid coef',GRD.PolyCoefparams); %#ok<AGROW>
                        end
                    case ' -t 4'
                        if isfield(SVM.kernel,'kerndef') && SVM.kernel.kerndef < 8
                            if isfield(GRD,'WLiters')
                                params(end+1) = obj.paramShelf('Kernel',GRD.WLiters); %#ok<AGROW>
                            end
                        elseif isfield(SVM.kernel,'customfunc_nargin') && SVM.kernel.customfunc_nargin >= 1
                            for n = 1:SVM.kernel.customfunc_nargin
                                argName = sprintf('customkernel_arg%d', n);
                                if isfield(GRD,argName)
                                    params(end+1) = obj.paramShelf(sprintf('Kernel function argument %d', n),GRD.(argName)); %#ok<AGROW>
                                end
                            end
                        end
                    otherwise
                        if isfield(SVM,'LIBSVM') && isfield(SVM.LIBSVM,'LIBSVMver') && SVM.LIBSVM.LIBSVMver == 3 && any(strcmp(kernstr, {' -t 4',' -t 5'}))
                            if isfield(GRD,'PolyCoefparams')
                                params(end+1) = obj.paramShelf('Kernel',GRD.PolyCoefparams); %#ok<AGROW>
                            end
                        elseif isfield(SVM,'LIBSVM') && isfield(SVM.LIBSVM,'LIBSVMver') && SVM.LIBSVM.LIBSVMver == 3 && any(strcmp(kernstr, {' -t 6',' -t 7'}))
                            if isfield(GRD,'Gparams')
                                params(end+1) = obj.paramShelf('Kernel',GRD.Gparams); %#ok<AGROW>
                            end
                        elseif isfield(GRD,'Gparams')
                            params(end+1) = obj.paramShelf('Kernel',GRD.Gparams); %#ok<AGROW>
                        end
                end
            end

            % Algorithm-specific parameter shelves.
            switch alg
                case {'matLRN','GLMNET','GRDBST','ROBSVM','ELASVM','BAYLIN'}
                    if strcmp(alg,'matLRN'), F = 'matLearn'; else, F = alg; end
                    if isfield(GRD,F) && isstruct(GRD.(F)) && isfield(GRD.(F),'Params')
                        for j = 1:numel(GRD.(F).Params)
                            if isfield(GRD.(F).Params(j),'name') && isfield(GRD.(F).Params(j),'range')
                                params(end+1) = obj.paramShelf(GRD.(F).Params(j).name,GRD.(F).Params(j).range); %#ok<AGROW>
                            end
                        end
                    end
                case 'MLPERC'
                    if isfield(GRD,'MLPERC') && isstruct(GRD.MLPERC) && isfield(GRD.MLPERC,'Params')
                        for j = 1:numel(GRD.MLPERC.Params)
                            if isfield(GRD.MLPERC.Params(j),'name') && isfield(GRD.MLPERC.Params(j),'range')
                                r = GRD.MLPERC.Params(j).range;
                                if strcmp(GRD.MLPERC.Params(j).name,'MLPERC_hidden_layer_sizes')
                                    r = obj.indexRangeForMatrixOrVector(r);
                                end
                                params(end+1) = obj.paramShelf(GRD.MLPERC.Params(j).name,r); %#ok<AGROW>
                            end
                        end
                    end
                case 'TFDEEP'
                    if isfield(GRD,'TFDEEP') && isstruct(GRD.TFDEEP) && isfield(GRD.TFDEEP,'Params') && ~isempty(GRD.TFDEEP.Params)
                        P = GRD.TFDEEP.Params;
                        if isfield(P(end),'range') && ~(ischar(P(end).range) && strcmp(P(end).range,'none'))
                            r = obj.indexRangeForMatrixOrVector(P(end).range);
                            params(end+1) = obj.paramShelf(P(end).name,r); %#ok<AGROW>
                        else
                            for j = 1:numel(P)-1
                                if isfield(P(j),'name') && isfield(P(j),'range')
                                    r = P(j).range;
                                    if strcmp(P(j).name,'TFDEEP_hidden_layer_sizes')
                                        r = obj.indexRangeForMatrixOrVector(r);
                                    end
                                    params(end+1) = obj.paramShelf(P(j).name,r); %#ok<AGROW>
                                end
                            end
                        end
                    end
                case 'MEXELM'
                    if isfield(GRD,'Neuronparams')
                        params(end+1) = obj.paramShelf('Hidden neurons',GRD.Neuronparams); %#ok<AGROW>
                    end
                case 'kNNMEX'
                    if isfield(GRD,'Kparams')
                        params(end+1) = obj.paramShelf('Nearest neighbors',GRD.Kparams); %#ok<AGROW>
                    end
                case 'BLOREG'
                    if isfield(GRD,'Tolparams')
                        params(end+1) = obj.paramShelf('Tolerance',GRD.Tolparams); %#ok<AGROW>
                    end
                case {'LIBSVM','LIBLIN'}
                    % nk_MLOptimizer_main only exposes class-weight and
                    % cost-complexity lambda shelves when learner weighting
                    % is active. Keep the shelf audit identical to that
                    % runtime condition; a default linear SVM should have
                    % only the Slack shelf.
                    if isfield(SVM,alg) && isfield(SVM.(alg),'Weighting') && SVM.(alg).Weighting
                        if isfield(GRD,'Weightparams')
                            params(end+1) = obj.paramShelf('Weight Factor',GRD.Weightparams); %#ok<AGROW>
                        else
                            params(end+1) = obj.paramShelf('Weight Factor',1); %#ok<AGROW>
                        end
                    end
                case 'DECTRE'
                    if isfield(GRD,'Leafparams')
                        params(end+1) = obj.paramShelf('Leafness',GRD.Leafparams); %#ok<AGROW>
                    end
                case 'RNDFOR'
                    rfFields = {'Treeparams','NumDparams','RFMaxDparams','RFCritdefsparams','RFMinSSplitparams', ...
                        'RFMinSLeafparams','RFMinWFLeafparams','RFMaxLeafNparams','RFMinImpDecrparams','RFBootstrapparams', ...
                        'RFOobScoreparams','RFCcpAlphaparams','RFMaxSampparams','RFClassWeightparams'};
                    rfNames = {'Decision Trees','Num Feats','Max Depth','Criterion','Min Samples Split', ...
                        'Min Samples Leaf','Min Weight Fract Leaf','Max Leaf Nodes','Min Impurity Decrease','Bootstrap', ...
                        'Out-Of-Bag Score','CCP Alpha','Max Sample','Class Weigths'};
                    for j = 1:numel(rfFields)
                        if isfield(GRD,rfFields{j})
                            params(end+1) = obj.paramShelf(rfNames{j},GRD.(rfFields{j})); %#ok<AGROW>
                        end
                    end
                case 'SEQOPT'
                    if isfield(SVM,'SEQOPT') && isfield(SVM.SEQOPT,'C')
                        params(end+1) = obj.paramShelf('Sequence',1:size(SVM.SEQOPT.C,1)); %#ok<AGROW>
                    end
                    if isfield(GRD,'CutOffparams')
                        params(end+1) = obj.paramShelf('%Step',GRD.CutOffparams); %#ok<AGROW>
                    end
                    if isfield(GRD,'LimsLparams')
                        params(end+1) = obj.paramShelf('%L-Population',GRD.LimsLparams); %#ok<AGROW>
                    end
                    if isfield(GRD,'LimsUparams')
                        params(end+1) = obj.paramShelf('%U-Population',GRD.LimsUparams); %#ok<AGROW>
                    end
                case 'WBLCOX'
                    if isfield(GRD,'CoxCutoffparams')
                        params(end+1) = obj.paramShelf('P-Cox-cutoff',GRD.CoxCutoffparams); %#ok<AGROW>
                    end
            end
        end


        function r = indexRangeForMatrixOrVector(obj, val) %#ok<INUSL>
            % Optimizer parity for parameters whose values are row-wise
            % configuration matrices/lists, e.g. *_hidden_layer_sizes and
            % TFDEEP_files. A row vector is one architecture, not multiple
            % scalar hyperparameter values.
            if isnumeric(val) || islogical(val)
                if isempty(val), r = []; else, r = 1:size(val,1); end
            elseif iscell(val)
                r = 1:numel(val);
            elseif isstring(val)
                r = 1:numel(val);
            elseif ischar(val)
                if size(val,1) > 1, r = 1:size(val,1); else, r = 1; end
            else
                r = val;
            end
        end

        function n = gridNodeCount(obj, params) %#ok<INUSL>
            n = 0;
            if isempty(params), return; end
            n = 1;
            for k = 1:numel(params)
                n = n * obj.rangeLength(params(k).range);
            end
        end

        function cls = safeClassifierCode(obj, SVM, alg) %#ok<INUSL>
            cls = NaN;
            try
                if isfield(SVM,alg) && isfield(SVM.(alg),'classifier')
                    cls = double(SVM.(alg).classifier);
                    if ~isempty(cls), cls = cls(1); return; end
                end
                if isfield(SVM,'LIBSVM') && isfield(SVM.LIBSVM,'classifier')
                    cls = double(SVM.LIBSVM.classifier);
                    if ~isempty(cls), cls = cls(1); return; end
                end
            catch
                cls = NaN;
            end
        end

        function n = rangeLength(obj, range) %#ok<INUSL>
            if ischar(range) || isstring(range)
                n = size(range,1);
            elseif isnumeric(range) || islogical(range)
                if isempty(range), n = 0; elseif ismatrix(range) && size(range,1) > 1 && size(range,2) > 1, n = size(range,1); else, n = numel(range); end
            elseif iscell(range)
                n = numel(range);
            else
                n = 1;
            end
        end

        function fs = seqoptFixedFields(obj)
            choices = NMLearnerLibrary.learnerFixedChoices('SEQOPT','classification');
            fs = { ...
                obj.uiField('fixedSettings.Mode','enum','SEQOPT optimization population','learner',1, ...
                    'values',choices.Mode, ...
                    'visibleIf',struct('field','algorithm','equals','SEQOPT'), ...
                    'help','Specify whether SEQOPT optimizes the deferred sample or the whole population.'), ...
                obj.uiField('fixedSettings.ReplaceMode','enum','SEQOPT prediction combination','learner',1, ...
                    'values',choices.ReplaceMode, ...
                    'visibleIf',struct('field','algorithm','equals','SEQOPT'), ...
                    'help','Combine sequential predictions by replacement or mean aggregation.'), ...
                obj.uiField('fixedSettings.AnchorType','enum','SEQOPT deferral-window anchor','learner',1, ...
                    'values',choices.AnchorType, ...
                    'visibleIf',struct('field','algorithm','equals','SEQOPT'), ...
                    'help','Choose the reference for the SEQOPT deferral window.'), ...
                obj.uiField('fixedSettings.PerfMode','enum','SEQOPT deferral optimization criterion','learner',1, ...
                    'values',choices.PerfMode, ...
                    'visibleIf',struct('field','algorithm','equals','SEQOPT'), ...
                    'help','Choose the criterion used by SEQOPT deferral optimization.'), ...
                obj.uiField('fixedSettings.C','sequence_matrix','Prognostic sequences','learner',1, ...
                    'visibleIf',struct('field','algorithm','equals','SEQOPT'), ...
                    'help','Prediction-source sequences encoded as an integer matrix.')};
        end

        function fs = wblcoxFixedFields(obj)
            fs = { ...
                obj.uiField('fixedSettings.interval','number','WBLCOX risk-estimation interval [days]','learner',1, ...
                    'visibleIf',struct('field','algorithm','equals','WBLCOX'), ...
                    'help','Time interval for Weibull-Cox risk estimates, in days.'), ...
                obj.uiField('fixedSettings.predict_time','boolean','Predict time to event','learner',false, ...
                    'visibleIf',struct('field','algorithm','equals','WBLCOX'), ...
                    'help','Predict time to event rather than risk at a fixed interval.'), ...
                obj.uiField('fixedSettings.MaxIter','integer','WBLCOX maximum iterations','learner',1000, ...
                    'visibleIf',struct('field','algorithm','equals','WBLCOX'), ...
                    'help','Maximum optimizer iterations for Weibull-Cox fitting.'), ...
                obj.uiField('fixedSettings.MaxFunEvals','integer','WBLCOX maximum function evaluations','learner',1000, ...
                    'visibleIf',struct('field','algorithm','equals','WBLCOX'), ...
                    'help','Maximum objective evaluations for Weibull-Cox fitting.'), ...
                obj.uiField('fixedSettings.TolX','number','WBLCOX TolX','learner',1e-5, ...
                    'visibleIf',struct('field','algorithm','equals','WBLCOX'), ...
                    'help','Parameter-change tolerance for Weibull-Cox optimization.'), ...
                obj.uiField('fixedSettings.TolFun','number','WBLCOX TolFun','learner',1e-5, ...
                    'visibleIf',struct('field','algorithm','equals','WBLCOX'), ...
                    'help','Objective-change tolerance for Weibull-Cox optimization.'), ...
                obj.uiField('fixedSettings.Algorithm','enum','WBLCOX optimizer algorithm','learner','sqp', ...
                    'values',NMLearnerLibrary.enumFromPairs({'interior-point','interior-point';'trust-region-reflective','trust-region-reflective';'sqp','sqp';'active-set','active-set'}), ...
                    'visibleIf',struct('field','algorithm','equals','WBLCOX'), ...
                    'help','Select the Weibull-Cox optimizer algorithm.')};
        end

        function fs = simAnnealFields(obj)
            vf = struct('field','optimizationSettings.type','equals','simanneal');
            fs = { ...
                obj.uiField('optimizationSettings.SimAneal.T','number','Initial temperature','optimization',1,'visibleIf',vf,'help','Initial temperature controlling acceptance of inferior grid moves.'), ...
                obj.uiField('optimizationSettings.SimAneal.max_initial_jump','integer','Maximum initial jump','optimization',10,'visibleIf',vf,'help','Largest initial step through the grid during annealing.'), ...
                obj.uiField('optimizationSettings.SimAneal.alpha','number','Cooling factor alpha','optimization',0.95,'visibleIf',vf,'help','Temperature multiplier after each cooling step.'), ...
                obj.uiField('optimizationSettings.SimAneal.random_jump_prob','number','Random jump probability','optimization',0.2,'visibleIf',vf,'help','Probability of a random rather than local parameter-grid move.'), ...
                obj.uiField('optimizationSettings.SimAneal.max_iter','integer','Maximum iterations','optimization',100,'visibleIf',vf,'help','Maximum annealing iterations.'), ...
                obj.uiField('optimizationSettings.SimAneal.reheating_iter','integer','Iterations until reheating','optimization',10,'visibleIf',vf,'help','Iteration interval at which the annealing schedule reheats.'), ...
                obj.uiField('optimizationSettings.SimAneal.reheating_alpha','number','Reheating factor','optimization',1.2,'visibleIf',vf,'help','Temperature multiplier at reheating.')};
        end

        function fs = bayesOptFields(obj)
            vf = struct('field','optimizationSettings.type','equals','bayesopt');
            fs = { ...
                obj.uiField('optimizationSettings.Bayes.max_iter','integer','Bayesian optimization maximum iterations','optimization',100,'visibleIf',vf,'help','Maximum Bayesian optimization iterations.'), ...
                obj.uiField('optimizationSettings.Bayes.max_iter_no_change','integer','Maximum iterations without improvement','optimization',25,'visibleIf',vf,'help','Stop after this many iterations without improvement.'), ...
                obj.uiField('optimizationSettings.Bayes.num_seed','integer','Seed iterations','optimization',100,'visibleIf',vf,'help','Number of initial evaluation points used to seed Bayesian optimization.'), ...
                obj.uiField('optimizationSettings.Bayes.kernel_function','enum','Gaussian-process kernel','optimization','squaredexponential', ...
                    'values',NMLearnerLibrary.enumFromPairs({'exponential','exponential';'ardexponential','ARD exponential';'squaredexponential','squared exponential';'ardsquaredexponential','ARD squared exponential';'matern32','Matern 3/2';'ardmatern32','ARD Matern 3/2';'matern52','Matern 5/2';'ardmatern52','ARD Matern 5/2'}), 'visibleIf',vf,'help','Gaussian-process covariance kernel for the Bayesian surrogate.'), ...
                obj.uiField('optimizationSettings.Bayes.mode','enum','Bayesian optimization acquisition','optimization','lcb', ...
                    'values',NMLearnerLibrary.enumFromPairs({'lcb','Lower confidence bound';'ei','Expected improvement'}), 'visibleIf',vf,'help','Acquisition strategy: lower confidence bound or expected improvement.'), ...
                obj.uiField('optimizationSettings.Bayes.LCBkappa','number','LCB kappa','optimization',2, ...
                    'visibleIf',struct('all',{{vf,struct('field','optimizationSettings.Bayes.mode','equals','lcb')}}),'help','Exploration weight used by lower-confidence-bound acquisition.'), ...
                obj.uiField('optimizationSettings.Bayes.EIjitter','number','EI jitter','optimization',1e-6, ...
                    'visibleIf',struct('all',{{vf,struct('field','optimizationSettings.Bayes.mode','equals','ei')}}),'help','Positive jitter used by expected-improvement acquisition.')};
        end

        function f = uiField(obj, path, type, label, section, defaultVal, varargin) %#ok<INUSL>
            f = struct('name',path,'path',path,'type',type,'label',label,'section',section,'default',defaultVal);
            if mod(numel(varargin),2) ~= 0
                error('NMMLModule:uiField','Optional arguments must be key-value pairs.');
            end
            for k = 1:2:numel(varargin)
                f.(varargin{k}) = varargin{k+1};
            end
        end

        function tf = fieldVisible(obj, f, cfg, ctx)
            tf = true;
            if isfield(f,'taskModes')
                mode = NMLearnerLibrary.taskMode(ctx);
                if ~any(strcmpi(mode, f.taskModes)), tf = false; return; end
            end
            if isfield(f,'visibleIf')
                tf = obj.visibleRuleOk(f.visibleIf, cfg);
            end
            if tf && isfield(f,'visibleIfParamGrid') && f.visibleIfParamGrid
                try
                    [SVM, GRD] = obj.toLegacy(cfg, ctx);
                    tf = GRD.n_params > 1;
                catch
                    tf = true;
                end
            end
        end

        function tf = visibleRuleOk(obj, rule, cfg)
            tf = true;
            if isempty(rule), return; end
            if isfield(rule,'all')
                rules = rule.all;
                for i = 1:numel(rules)
                    if ~obj.visibleRuleOk(rules{i}, cfg), tf = false; return; end
                end
            end
            if isfield(rule,'any')
                rules = rule.any;
                anyOk = false;
                for i = 1:numel(rules)
                    if obj.visibleRuleOk(rules{i}, cfg), anyOk = true; break; end
                end
                if ~anyOk, tf = false; return; end
            end
            if isfield(rule,'field')
                val = obj.pathValue(cfg, rule.field, []);
                if isfield(rule,'equals') && ~obj.valueEquals(val, rule.equals), tf = false; return; end
                if isfield(rule,'notEquals') && obj.valueEquals(val, rule.notEquals), tf = false; return; end
                if isfield(rule,'in') && ~obj.valueIn(val, rule.in), tf = false; return; end
                if isfield(rule,'notIn') && obj.valueIn(val, rule.notIn), tf = false; return; end
            end
            if isfield(rule,'andField')
                val = obj.pathValue(cfg, rule.andField, []);
                if isfield(rule,'andEquals') && ~obj.valueEquals(val, rule.andEquals), tf = false; return; end
                if isfield(rule,'andNotEquals') && obj.valueEquals(val, rule.andNotEquals), tf = false; return; end
                if isfield(rule,'andIn') && ~obj.valueIn(val, rule.andIn), tf = false; return; end
                if isfield(rule,'andNotIn') && obj.valueIn(val, rule.andNotIn), tf = false; return; end
            end
            if isfield(rule,'nonEmptyField')
                val = obj.pathValue(cfg, rule.nonEmptyField, []);
                if obj.isEmptyValue(val), tf = false; return; end
            end
            if isfield(rule,'emptyField')
                val = obj.pathValue(cfg, rule.emptyField, []);
                if ~obj.isEmptyValue(val), tf = false; return; end
            end
        end

        function val = pathValue(obj, s, path, defaultVal) %#ok<INUSL>
            val = defaultVal;
            if ~isstruct(s) || isempty(path), return; end
            parts = strsplit(char(path), '.');
            cur = s;
            for i = 1:numel(parts)
                pth = parts{i};
                if isstruct(cur) && isfield(cur, pth)
                    cur = cur.(pth);
                else
                    return;
                end
            end
            val = cur;
        end

        function tf = valueEquals(obj, a, b) %#ok<INUSL>
            if ischar(a) || isstring(a) || ischar(b) || isstring(b)
                tf = strcmpi(char(string(a)), char(string(b)));
            elseif islogical(a) || islogical(b)
                tf = isequal(logical(a), logical(b));
            else
                tf = isequal(a, b);
            end
        end

        function tf = valueIn(obj, val, list)
            if ~iscell(list), list = num2cell(list); end
            tf = false;
            for i = 1:numel(list)
                if obj.valueEquals(val, list{i}), tf = true; return; end
            end
        end

        function tf = isEmptyValue(obj, val) %#ok<INUSL>
            tf = isempty(val);
            if ischar(val) || isstring(val), tf = strlength(string(val)) == 0; end
        end

        function ms = normalizeModelSelectionSettings(obj, ms, gridParam)
            % Normalize model-selection subtree after JSON/browser import.
            % MATLAB jsondecode commonly turns row vectors into column vectors;
            % legacy GRD.NodeSelect.percvec is expected as a row vector. Build
            % scalar structs explicitly and avoid recursive merging here.
            if nargin < 3 || isempty(gridParam), gridParam = 1; end
            def = NMLearnerLibrary.defaultModelSelectionSettings(gridParam);
            if nargin < 2 || isempty(ms) || ~isstruct(ms)
                ms = def;
                return;
            end
            if numel(ms) > 1, ms = ms(1); end

            out = def;
            if isfield(ms,'GridMaxType')
                out.GridMaxType = obj.asNumericScalar(ms.GridMaxType, def.GridMaxType);
            end
            if isfield(ms,'NodeSelect')
                out.NodeSelect = obj.normalizeNodeSelect(ms.NodeSelect, def.NodeSelect);
            else
                out.NodeSelect = obj.normalizeNodeSelect(def.NodeSelect, def.NodeSelect);
            end
            if isfield(ms,'OptRegul')
                out.OptRegul = obj.normalizeOptRegulSettings(ms.OptRegul, def.OptRegul);
            else
                out.OptRegul = obj.normalizeOptRegulSettings(def.OptRegul, def.OptRegul);
            end
            ms = out;
        end

        function ns = normalizeNodeSelect(obj, ns, def)
            if nargin < 3 || isempty(def), def = struct('mode',1,'perc',95,'percvec',75:5:95); end
            if nargin < 2 || isempty(ns) || ~isstruct(ns)
                ns = def;
                return;
            end
            if numel(ns) > 1, ns = ns(1); end
            out = def;
            if isfield(ns,'mode'), out.mode = obj.asNumericScalar(ns.mode, def.mode); end
            if isfield(ns,'perc'), out.perc = obj.asNumericScalar(ns.perc, def.perc); end
            if isfield(ns,'percvec'), out.percvec = obj.asRowNumeric(ns.percvec, def.percvec); else, out.percvec = obj.asRowNumeric(def.percvec, def.percvec); end
            ns = out;
        end

        function or = normalizeOptRegulSettings(obj, or, def)
            if nargin < 3 || isempty(def)
                def = struct('flag',0,'type',1,'lambda',1,'big_gamma',0.5, ...
                    'RegulTypeComplexity', struct('type',1), 'RegulTypeDiversity', struct('type',1));
            end
            if nargin < 2 || isempty(or) || ~isstruct(or)
                or = def;
                return;
            end
            if numel(or) > 1, or = or(1); end
            out = def;
            if isfield(or,'flag'), out.flag = logical(obj.asNumericScalar(or.flag, def.flag)); end
            if isfield(or,'type'), out.type = obj.asNumericScalar(or.type, def.type); end
            if isfield(or,'lambda'), out.lambda = obj.asNumericScalar(or.lambda, def.lambda); end
            if isfield(or,'big_gamma'), out.big_gamma = obj.asNumericScalar(or.big_gamma, def.big_gamma); end
            if isfield(or,'RegulTypeComplexity') && isstruct(or.RegulTypeComplexity) && ~isempty(or.RegulTypeComplexity)
                rtc = or.RegulTypeComplexity;
                if numel(rtc) > 1, rtc = rtc(1); end
                if ~isfield(out,'RegulTypeComplexity') || ~isstruct(out.RegulTypeComplexity), out.RegulTypeComplexity = struct('type',1); end
                if isfield(rtc,'type'), out.RegulTypeComplexity.type = obj.asNumericScalar(rtc.type, 1); end
            end
            if isfield(or,'RegulTypeDiversity') && isstruct(or.RegulTypeDiversity) && ~isempty(or.RegulTypeDiversity)
                rtd = or.RegulTypeDiversity;
                if numel(rtd) > 1, rtd = rtd(1); end
                if ~isfield(out,'RegulTypeDiversity') || ~isstruct(out.RegulTypeDiversity), out.RegulTypeDiversity = struct('type',1); end
                if isfield(rtd,'type'), out.RegulTypeDiversity.type = obj.asNumericScalar(rtd.type, 1); end
            end
            or = out;
        end

        function val = asNumericScalar(obj, val, defaultVal) %#ok<INUSL>
            if nargin < 3, defaultVal = []; end
            if isempty(val)
                val = defaultVal;
            elseif islogical(val)
                val = double(val(1));
            elseif isnumeric(val)
                val = double(val(1));
            elseif ischar(val) || isstring(val)
                tmp = str2double(char(val));
                if isnan(tmp), val = defaultVal; else, val = tmp; end
            else
                val = defaultVal;
            end
        end

        function val = asRowNumeric(obj, val, defaultVal) %#ok<INUSL>
            if nargin < 3, defaultVal = []; end
            if isempty(val)
                val = double(defaultVal(:))';
            elseif isnumeric(val)
                val = double(val(:))';
            elseif islogical(val)
                val = double(val(:))';
            elseif ischar(val) || isstring(val)
                tmp = str2num(char(val)); %#ok<ST2NM>
                if isempty(tmp), val = double(defaultVal(:))'; else, val = double(tmp(:))'; end
            elseif iscell(val)
                try
                    tmp = cell2mat(val);
                    val = double(tmp(:))';
                catch
                    val = double(defaultVal(:))';
                end
            else
                val = double(defaultVal(:))';
            end
        end

        function P = normalizeLearnerParams(obj, P) %#ok<INUSL>
            % Normalise learner-specific Params after JSON/UI import.
            % MATLAB jsondecode commonly turns numeric row vectors into column
            % vectors.  Legacy GRD.(prog).Params expects numeric ranges in row
            % orientation, while categorical ranges must remain cell/string
            % containers and single sentinels such as 'none' must remain char.
            if nargin < 2 || isempty(P)
                P = struct('name',{},'range',{});
                return;
            end
            if ~isstruct(P)
                P = struct('name',{},'range',{});
                return;
            end
            for ii = 1:numel(P)
                if isfield(P(ii),'range')
                    P(ii).range = obj.normalizeLearnerRange(P(ii).range);
                end
                if isfield(P(ii),'name') && isstring(P(ii).name) && isscalar(P(ii).name)
                    P(ii).name = char(P(ii).name);
                end
            end
        end

        function r = normalizeLearnerRange(obj, r) %#ok<INUSL>
            if isempty(r)
                return;
            end
            if isnumeric(r) || islogical(r)
                r = double(r(:))';
            elseif isstring(r)
                if isscalar(r)
                    r = char(r);
                else
                    r = cellstr(r(:))';
                end
            elseif iscell(r)
                % Preserve categorical cell arrays as cellstr row vectors. If
                % the cell contains only numeric/logical scalars, interpret it
                % as a numeric range and return a numeric row vector.
                if all(cellfun(@(x) (isnumeric(x) || islogical(x)) && isscalar(x), r(:)))
                    try
                        r = double(cell2mat(r(:)))';
                    catch
                        r = r(:)';
                    end
                else
                    r = r(:)';
                    for jj = 1:numel(r)
                        if isstring(r{jj}) && isscalar(r{jj})
                            r{jj} = char(r{jj});
                        end
                    end
                end
            end
        end

        function s = paramShelf(obj, name, range) %#ok<INUSL>
            % Construct scalar parameter-shelf structs safely. MATLAB's
            % struct('range', cellArray) expands into a struct array, which
            % breaks params(end+1) assignment for categorical learner ranges.
            s = struct('name', '', 'range', []);
            if isstring(name), name = char(name); end
            s.name = name;
            s.range = range;
        end

        function tf = getBool(obj, s, f, defaultVal) %#ok<INUSL>
            tf = defaultVal;
            if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), tf = logical(s.(f)); end
        end

        function out = mergeStruct(obj, a, b) %#ok<INUSL>
            if nargin < 2 || isempty(a) || ~isstruct(a), a = struct(); end
            if nargin < 3 || isempty(b) || ~isstruct(b), out = a; return; end
            out = a;
            fn = fieldnames(b);
            for i = 1:numel(fn)
                f = fn{i};
                if isfield(out,f) && isstruct(out.(f)) && isstruct(b.(f)) && isscalar(out.(f)) && isscalar(b.(f))
                    out.(f) = obj.mergeStruct(out.(f), b.(f));
                else
                    out.(f) = b.(f);
                end
            end
        end
    end
end

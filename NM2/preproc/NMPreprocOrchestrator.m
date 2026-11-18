classdef NMPreprocOrchestrator < handle
% NMPreprocOrchestrator
% -------------------------------------------------------------------------
% Interface-neutral preprocessing pipeline controller. It now owns two
% stage-specific sequences: subject-specific preprocessing, executed before
% CV splitting, and CV-bound preprocessing, exported to ACTPARAM.
% -------------------------------------------------------------------------

    properties
        Registry
        RuleSet
        SubjectSequence
        CVSequence
        Sequence              % Backward-compatible alias for CVSequence
        Context
        NM
        VarIndex
        GlobalOptions struct = struct()
    end

    methods (Static)
        function obj = fromNM(NM, varind, PREPROC, varargin)
            % fromNM  Create an orchestrator from an NM workspace and modality index.
            %   Loads or defaults NM.TrainParam.PREPROC{varind}, builds a context from NM, imports
            %   legacy state into subject/CV sequences, and retains NM/VarIndex for optional
            %   updateNM().

            if nargin < 2 || isempty(varind)
                if isstruct(NM) && isfield(NM,'ActiveModality'), varind = NM.ActiveModality; else, varind = 1; end
            end
            if nargin < 3
                PREPROC = [];
                if isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                        isfield(NM.TrainParam,'PREPROC') && iscell(NM.TrainParam.PREPROC) && ...
                        numel(NM.TrainParam.PREPROC) >= varind
                    PREPROC = NM.TrainParam.PREPROC{varind};
                end
            end
            ctx = NMPreprocContext.fromNM(NM, varind, varargin{:});
            obj = NMPreprocOrchestrator([], [], ctx);
            obj.NM = NM;
            obj.VarIndex = varind;
            if obj.isMissingLegacyPreproc(PREPROC)
                PREPROC = NMPreprocOrchestrator.defaultSetting(NM, varind, varargin{:});
            end
            obj.importLegacy(PREPROC, ctx);
        end

        function obj = fromLegacy(PREPROC, ctx)
            % fromLegacy  Create an orchestrator directly from a legacy PREPROC branch.
            %   Useful for tests, import tools, and power users who want to inspect or edit
            %   preprocessing without a full NM struct.

            if nargin < 2 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            obj = NMPreprocOrchestrator([], [], ctx);
            obj.importLegacy(PREPROC, ctx);
        end


        function PREPROC = defaultSetting(NM, varind, varargin)
            % defaultSetting  Generate the legacy default PREPROC branch for a modality.
            %   Builds the modular default scale/prune/impute sequence, adapts defaults for NaNs,
            %   regression labels, and label missingness, then materializes the legacy PREPROC
            %   struct.

            % Return the legacy default preprocessing branch that
            % nk_TrainClass_config/nk_DefPREPROC_config would create for a
            % newly configured modality, using the modular module adapters as
            % the single source for individual step defaults.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(varind), varind = 1; end
            ctx = NMPreprocContext.fromNM(NM, varind, varargin{:});
            pp = NMPreprocOrchestrator([], [], ctx);

            scaleModule = pp.Registry.get('scale');
            scaleCfg = scaleModule.defaultConfig(ctx);
            if ~ctx.isSeqoptStacking && ~strcmp(ctx.source,'stacking')
                pruneModule = pp.Registry.get('elimzero');
                pruneCfg = pruneModule.defaultConfig(ctx);
            end

            predictorNaNsForDefault = false;
            if isstruct(ctx) && isfield(ctx, 'hasNaNsInPredictors') && ~isempty(ctx.hasNaNsInPredictors)
                predictorNaNsForDefault = any(logical(ctx.hasNaNsInPredictors(:)));
            end
            if predictorNaNsForDefault && ~ctx.isSeqoptStacking && ~strcmp(ctx.source,'stacking')
                if isfield(scaleCfg,'zeroOutNonFinite')
                    scaleCfg.zeroOutNonFinite = true;
                end
                if isfield(pruneCfg,'pruneNaN')
                    pruneCfg.pruneNaN = false;
                end
                if isfield(pruneCfg,'pruneInf')
                    pruneCfg.pruneInf = false;
                end
            end

            pp.addStepAtStage('cv', 'scale', scaleCfg);
            if ~ctx.isSeqoptStacking && ~strcmp(ctx.source,'stacking')
                pp.addStepAtStage('cv', 'elimzero', pruneCfg);
            end

            if predictorNaNsForDefault && ~strcmp(ctx.source,'stacking') && pp.Registry.has('impute')
                imputeModule = pp.Registry.get('impute');
                insertIndex = pp.CVSequence.numSteps() + 1;
                [imputeOk, ~] = pp.RuleSet.isAvailable(imputeModule.Id, pp.CVSequence.Context, pp.CVSequence, insertIndex);
                if imputeOk
                    pp.addStepAtStage('cv', 'impute', imputeModule.defaultConfig(ctx));
                end
            end

            labelNaNsForDefault = isstruct(ctx) && isfield(ctx,'hasNaNsInLabels') && ...
                ~isempty(ctx.hasNaNsInLabels) && any(logical(ctx.hasNaNsInLabels(:)));
            if labelNaNsForDefault && ~strcmp(ctx.source,'stacking') && pp.Registry.has('labelimpute')
                labelImputeModule = pp.Registry.get('labelimpute');
                insertIndex = pp.CVSequence.numSteps() + 1;
                [labelImputeOk, ~] = pp.RuleSet.isAvailable(labelImputeModule.Id, pp.CVSequence.Context, pp.CVSequence, insertIndex);
                if labelImputeOk
                    pp.addStepAtStage('cv', 'labelimpute', labelImputeModule.defaultConfig(ctx));
                end
            end

            opts = pp.GlobalOptions;
            if isequal(ctx.isRegression,true)
                opts.enableTargetTransform = true;
                opts.targetScale = true;
            end
            pp.GlobalOptions = opts;

            PREPROC = pp.toLegacyPreproc();
            if ~isfield(PREPROC,'FEATSEL') || ~isstruct(PREPROC.FEATSEL)
                PREPROC.FEATSEL = struct();
            end
            if ~isfield(PREPROC.FEATSEL,'active') || isempty(PREPROC.FEATSEL.active)
                PREPROC.FEATSEL.active = 0;
            end
        end

        function tf = isMissingLegacyPreproc(PREPROC)
            % isMissingLegacyPreproc  Detect whether a PREPROC value is absent or structurally empty.
            %   Guards fromNM/defaultSetting so older or incomplete NM structs get a valid modular
            %   default instead of being treated as configured.

            tf = true;
            if nargin < 1 || isempty(PREPROC), return; end
            if ~isstruct(PREPROC), return; end
            if numel(PREPROC) ~= 1, return; end
            fn = fieldnames(PREPROC);
            if isempty(fn), return; end
            structural = {'ACTPARAM','SPATIAL','LABELMOD','FEATSEL'};
            tf = ~any(ismember(structural, fn));
        end

        function nv = structToNameValues(s)
            % structToNameValues  Convert a scalar struct to name/value pairs.
            %   This compatibility utility lets cli_configure accept either struct-style API calls
            %   or explicit name/value arguments.

            nv = {};
            if ~isstruct(s), return; end
            fn = fieldnames(s);
            nv = cell(1, 2*numel(fn));
            for i = 1:numel(fn)
                nv{2*i-1} = fn{i};
                nv{2*i} = s.(fn{i});
            end
        end

        function steps = normalizeStepCells(steps)
            % normalizeStepCells  Normalize incoming step containers to canonical cell-of-struct form.
            %   Used by cli_configure and UI-state application before assigning SubjectSequence or
            %   CVSequence.Steps.

            if nargin < 1 || isempty(steps), steps = {}; return; end
            if isstruct(steps), steps = num2cell(steps); end
            if ~iscell(steps), steps = {}; return; end
            for i = 1:numel(steps)
                if isempty(steps{i}), steps{i} = struct('moduleId','','config',struct()); end
                if ~isstruct(steps{i}), error('NMPreprocOrchestrator:invalidStep', 'Step %d is not a struct.', i); end
                if ~isfield(steps{i},'moduleId'), steps{i}.moduleId = ''; end
                if ~isfield(steps{i},'config'), steps{i}.config = struct(); end
            end
        end
    end

    methods
        function obj = NMPreprocOrchestrator(registry, ruleset, ctx)
            % NMPreprocOrchestrator  Construct a preprocessing orchestrator with subject and CV sequences.
            %   Initializes registry, ruleset, context, global options, and both stage-specific
            %   sequences before any legacy import or scripted configuration.

            if nargin < 1 || isempty(registry), registry = NMModuleRegistry.default(); end
            if nargin < 2 || isempty(ruleset), ruleset = NMPreprocRuleSet.default(); end
            if nargin < 3 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            obj.Registry = registry;
            obj.RuleSet = ruleset;
            obj.Context = ctx;
            obj.SubjectSequence = NMPreprocSequence(registry, ruleset, ctx, 'subject');
            obj.CVSequence = NMPreprocSequence(registry, ruleset, ctx, 'cv');
            obj.Sequence = obj.CVSequence;
            obj.NM = [];
            obj.VarIndex = [];
            obj.GlobalOptions = NMPreprocGlobalOptions.defaultOptions(ctx);
            obj.refreshStageContexts();
        end


        function [obj, PREPROC, report] = cli_configure(obj, varargin)
            % cli_configure  Configure preprocessing from power-user name/value API arguments.
            %   Accepts SubjectSteps, CVSteps, legacy metadata, and GlobalOptions; updates both
            %   sequences, then returns the legacy PREPROC branch plus a report instead of mutating
            %   NM silently.

            % cli_configure Public non-interactive API for assembling a preprocessing branch.
            %
            % Usage:
            %   [pp, PREPROC, report] = pp.cli_configure('SubjectSteps', subjectSteps, 'CVSteps', cvSteps);
            %   [pp, PREPROC, report] = pp.cli_configure(existingState, 'CVSteps', cvSteps);
            report = struct('ok', true, 'errors', {{}}, 'warnings', {{}});
            PREPROC = [];
            if isempty(varargin)
                try
                    PREPROC = obj.toLegacyPreproc();
                catch ME
                    report.ok = false; report.errors{end+1} = ME.message;
                end
                return;
            end
            if numel(varargin) == 1 && isstruct(varargin{1})
                varargin = NMPreprocOrchestrator.structToNameValues(varargin{1});
            end
            if mod(numel(varargin),2) ~= 0
                report.ok = false;
                report.errors{end+1} = 'Preprocessing cli_configure arguments must be name/value pairs.';
                return;
            end
            try
                for k = 1:2:numel(varargin)
                    key = lower(char(string(varargin{k})));
                    val = varargin{k+1};
                    switch key
                        case {'globaloptions','options'}
                            if isstruct(val), obj.GlobalOptions = val; end
                        case {'subjectsteps','subjectsequence'}
                            obj.SubjectSequence.Steps = NMPreprocOrchestrator.normalizeStepCells(val);
                        case {'cvsteps','cvsequence','steps'}
                            obj.CVSequence.Steps = NMPreprocOrchestrator.normalizeStepCells(val);
                        case {'subjectlegacymeta'}
                            if isstruct(val), obj.SubjectSequence.LegacyMeta = val; end
                        case {'cvlegacymeta','legacymeta'}
                            if isstruct(val), obj.CVSequence.LegacyMeta = val; end
                        otherwise
                            error('NMPreprocOrchestrator:unknownCliConfigureOption', 'Unknown preprocessing cli_configure option: %s.', varargin{k});
                    end
                end
                obj.refreshStageContexts();
                PREPROC = obj.toLegacyPreproc();
            catch ME
                report.ok = false;
                report.errors{end+1} = ME.message;
                report.exception = ME.message;
                report.identifier = ME.identifier;
            end
        end

        function [obj, PREPROC, report] = configure(obj, varargin)
            % configure  Compatibility alias for cli_configure.
            %   Preserves configure-style API calls while keeping all preprocessing assembly logic
            %   in cli_configure.

            [obj, PREPROC, report] = obj.cli_configure(varargin{:});
        end

        function h = cli_configureHelp(obj)
            % cli_configureHelp  Return structured help for the orchestrator configuration API.
            %   Documents SubjectSteps, CVSteps, GlobalOptions, and output semantics for power users
            %   and future assistant/RAG tooling.

            opts = struct();
            opts.SubjectSteps = 'Cell array of structs with fields moduleId and config.';
            opts.CVSteps = 'Cell array of structs with fields moduleId and config.';
            opts.GlobalOptions = 'Optional NMPreprocGlobalOptions-compatible struct.';
            h = NMConfigureAPITools.helpStruct('NMPreprocOrchestrator.cli_configure', ...
                '[pp, PREPROC, report] = pp.cli_configure(''SubjectSteps'', subjectSteps, ''CVSteps'', cvSteps)', opts, ...
                {'pp = NMPreprocOrchestrator.fromNM(NM, 1, []); [pp, PREPROC] = pp.cli_configure(''CVSteps'', cvSteps);'});
            h.moduleIds = obj.Registry.list();
            h.moduleSpecs = obj.Registry.configSpecs(obj.Context);
            h.globalOptionsSpec = NMPreprocGlobalOptions.toUISpec(obj.Context, obj.GlobalOptions);
        end

        function h = configureHelp(obj)
            % configureHelp  Compatibility alias for orchestrator configuration help.
            %   Keeps configureHelp and cli_configureHelp synchronized for older callers and
            %   documentation extraction.

            h = obj.cli_configureHelp();
        end

        function refreshStageContexts(obj)
            % refreshStageContexts  Refresh subject and CV sequence contexts from the orchestrator context.
            %   Called after context/global-state changes so rule checks, config specs, and legacy
            %   conversion know the current execution stage.

            base = obj.Context;
            globalOptions = NMPreprocGlobalOptions.normalize(obj.GlobalOptions, base);
            base.preprocBinmod = globalOptions.binmod;
            base.allSequences = {obj.SubjectSequence, obj.CVSequence};
            sctx = base; sctx.executionStage = 'subject';
            cctx = base; cctx.executionStage = 'cv';
            obj.SubjectSequence.setContext(sctx);
            obj.CVSequence.setContext(cctx);
            obj.Sequence = obj.CVSequence;
        end

        function importLegacy(obj, PREPROC, ctx)
            % importLegacy  Import a legacy PREPROC branch into the orchestrator state.
            %   Migrates misplaced label-imputation settings, loads global options, and populates
            %   subject/CV sequences with canonical module steps.

            if nargin < 3 || isempty(ctx), ctx = obj.Context; end
            obj.Context = ctx;
            obj.GlobalOptions = NMPreprocGlobalOptions.fromLegacy(PREPROC, ctx);
            PREPROC = obj.migrateLegacyLabelImputePlacement(PREPROC);
            obj.refreshStageContexts();
            obj.SubjectSequence.fromLegacy(PREPROC, obj.SubjectSequence.Context);
            obj.CVSequence.fromLegacy(PREPROC, obj.CVSequence.Context);
            obj.normalizeLabelImputePlacement();
        end

        function idx = addStep(obj, moduleId, varargin)
            % addStep  Append a CV-bound preprocessing step.
            %   Convenience API over addStepAtStage(cv,...) for the common ACTPARAM sequence used in
            %   model training.

            idx = obj.addStepAtStage('cv', moduleId, varargin{:});
        end

        function idx = addSubjectStep(obj, moduleId, varargin)
            % addSubjectStep  Append a subject-level spatial preprocessing step.
            %   Convenience API over addStepAtStage(subject,...) for PREPROC.SPATIAL operations
            %   applied before CV-bound preprocessing.

            idx = obj.addStepAtStage('subject', moduleId, varargin{:});
        end

        function idx = addStepAtStage(obj, stage, moduleId, varargin)
            % addStepAtStage  Append a preprocessing step to a specific stage.
            %   Resolves the module, parses config, handles label-imputation no-op placement, and
            %   delegates stage-specific insertion to NMPreprocSequence.

            seq = obj.sequenceForStage(stage);
            module = obj.Registry.get(moduleId);
            if strcmpi(module.Id,'labelimpute')
                cfg = module.parseConfig(varargin{:});
                if obj.isNoneLabelImputeConfig(cfg)
                    obj.setGlobalLabelImputeNone(cfg);
                    idx = 0;
                    return;
                end
            end
            info = module.info();
            if isfield(info.capabilities,'requiresSpatialFeatureExtractionAllowed') && info.capabilities.requiresSpatialFeatureExtractionAllowed
                [idx, allowed, reason] = obj.RuleSet.getSpatialExtractorGate(seq, seq.Context);
                if ~allowed
                    error('NMPreprocOrchestrator:spatialExtractorUnavailable','%s', reason);
                end
                seq.insert(idx, module.Id, varargin{:});
            else
                idx = seq.add(moduleId, varargin{:});
            end
            obj.normalizeLabelImputePlacement();
        end

        function idx = addBlock(obj, parentId, parentCfg, childId, childCfg)
            % addBlock  Append a CV-bound parent/child preprocessing block.
            %   Convenience API for modules that must be inserted together, such as dimensionality
            %   reduction plus extraction.

            idx = obj.addBlockAtStage('cv', parentId, parentCfg, childId, childCfg);
        end

        function idx = addBlockAtStage(obj, stage, parentId, parentCfg, childId, childCfg)
            % addBlockAtStage  Append a parent/child block to a selected stage.
            %   Delegates dependency-aware block insertion to the stage sequence after resolving the
            %   requested stage.

            seq = obj.sequenceForStage(stage);
            idx = seq.addBlock(parentId, parentCfg, childId, childCfg);
        end

        function insertStep(obj, idx, moduleId, varargin)
            % insertStep  Insert a CV-bound step at an index.
            %   Convenience wrapper for API/UI callers editing the ACTPARAM sequence.

            obj.insertStepAtStage('cv', idx, moduleId, varargin{:});
        end

        function insertSubjectStep(obj, idx, moduleId, varargin)
            % insertSubjectStep  Insert a subject-level step at an index.
            %   Convenience wrapper for API/UI callers editing the PREPROC.SPATIAL sequence.

            obj.insertStepAtStage('subject', idx, moduleId, varargin{:});
        end

        function insertStepAtStage(obj, stage, idx, moduleId, varargin)
            % insertStepAtStage  Insert a step into the requested stage sequence.
            %   Uses sequence-level parsing and ruleset checks so order constraints remain
            %   centralized.

            seq = obj.sequenceForStage(stage);
            seq.insert(idx, moduleId, varargin{:});
        end

        function removeStep(obj, idx, varargin)
            % removeStep  Remove a CV-bound step or block.
            %   Convenience wrapper for ACTPARAM sequence edits.

            obj.removeStepAtStage('cv', idx, varargin{:});
        end

        function removeStepAtStage(obj, stage, idx, varargin)
            % removeStepAtStage  Remove a step from a requested stage sequence.
            %   Delegates to sequence.remove so block-aware removal and state normalization remain
            %   in one place.

            seq = obj.sequenceForStage(stage);
            seq.remove(idx, varargin{:});
        end

        function moveStep(obj, fromIdx, toIdx)
            % moveStep  Move a CV-bound step or block.
            %   Convenience wrapper for ACTPARAM ordering changes.

            obj.moveStepAtStage('cv', fromIdx, toIdx);
        end

        function moveStepAtStage(obj, stage, fromIdx, toIdx)
            % moveStepAtStage  Move a step or block within a requested stage.
            %   Delegates to sequence.moveBlock; callers should validate after movement to detect
            %   new ordering violations.

            seq = obj.sequenceForStage(stage);
            seq.moveBlock(fromIdx, toIdx);
        end

        function report = validate(obj)
            % validate  Validate global, subject-level, CV-bound, and cross-stage preprocessing constraints.
            %   Combines sequence reports with cross-stage dependency/uniqueness checks and returns
            %   a single report for UI, scripts, and legacy export gates.

            srep = obj.SubjectSequence.validate(obj.SubjectSequence.Context);
            crep = obj.CVSequence.validate(obj.CVSequence.Context);
            report = struct('ok',true,'errors',{{}},'warnings',{{}});
            report.errors = [srep.errors crep.errors obj.crossStageErrors()];
            report.warnings = [srep.warnings crep.warnings obj.crossStageWarnings()];
            report.ok = isempty(report.errors);
            if ~report.ok
                error('NMPreprocOrchestrator:invalidSequence','%s',strjoin(report.errors,newline));
            end
        end

        function projection = ruleProjection(obj)
            % ruleProjection  Resolve browser/API preprocessing legality from MATLAB authorities.
            %   Returns derived RuleSet facts, spatial insertion gates, and soft validation
            %   diagnostics for the current subject/CV state. Nothing in this projection is
            %   persisted as scientific state.
            obj.refreshStageContexts();
            srep = obj.SubjectSequence.validateSoft(obj.SubjectSequence.Context);
            crep = obj.CVSequence.validateSoft(obj.CVSequence.Context);
            errors = [srep.errors crep.errors obj.crossStageErrors()];
            warnings = [srep.warnings crep.warnings obj.crossStageWarnings()];
            sfacts = obj.RuleSet.resolveSequenceFacts(obj.SubjectSequence,true);
            cfacts = obj.RuleSet.resolveSequenceFacts(obj.CVSequence,true);
            allFacts = [sfacts cfacts];
            invalidFacts = cellfun(@(f)~f.valid, allFacts);
            if any(invalidFacts)
                errors = [errors cellfun(@(f)f.error, allFacts(invalidFacts), 'UniformOutput', false)];
            end

            [sidx, sall, sreason, send] = obj.RuleSet.getSpatialExtractorGate( ...
                obj.SubjectSequence,obj.SubjectSequence.Context);
            [cidx, callowed, creason, cend] = obj.RuleSet.getSpatialExtractorGate( ...
                obj.CVSequence,obj.CVSequence.Context);

            projection = struct();
            projection.ok = isempty(errors);
            projection.errors = errors;
            projection.warnings = warnings;
            projection.subject = struct( ...
                'facts',{sfacts}, ...
                'spatialExtractorGate',struct('insertIndex',sidx,'allowed',logical(sall), ...
                    'reason',sreason,'allowedAtEnd',logical(send)));
            projection.cv = struct( ...
                'facts',{cfacts}, ...
                'spatialExtractorGate',struct('insertIndex',cidx,'allowed',logical(callowed), ...
                    'reason',creason,'allowedAtEnd',logical(cend)));
            projection.subject.stepIssues = arrayfun(@(i) obj.SubjectSequence.uiIssueForStep(i), ...
                1:obj.SubjectSequence.numSteps(), 'UniformOutput',false);
            projection.cv.stepIssues = arrayfun(@(i) obj.CVSequence.uiIssueForStep(i), ...
                1:obj.CVSequence.numSteps(), 'UniformOutput',false);
        end

        function mods = getAddableModules(obj, insertIndex, stage)
            % getAddableModules  Return modules that may be inserted at a stage/index.
            %   Delegates to the ruleset and registry so UI pickers and scripts see the same
            %   availability constraints.

            if nargin < 3 || isempty(stage), stage = 'cv'; end
            seq = obj.sequenceForStage(stage);
            if nargin < 2 || isempty(insertIndex), insertIndex = seq.numSteps()+1; end
            mods = obj.RuleSet.getAddableModuleInfos(obj.Registry, seq, seq.Context, insertIndex);
        end

        function mods = getAddableSubjectModules(obj, insertIndex)
            % getAddableSubjectModules  Return addable subject-level modules at a requested position.
            %   Convenience wrapper around getAddableModules(...,subject) for spatial preprocessing
            %   UI/API callers.

            if nargin < 2, insertIndex = []; end
            mods = obj.getAddableModules(insertIndex, 'subject');
        end

        function PREPROC = toLegacyPreproc(obj)
            % toLegacyPreproc  Materialize the full legacy PREPROC branch.
            %   Normalizes label-imputation placement, validates both sequences, merges CV
            %   ACTPARAM/global options with subject SPATIAL steps, and returns the struct assigned
            %   to NM.TrainParam.PREPROC.

            obj.normalizeLabelImputePlacement();
            obj.validate();
            cv = obj.CVSequence.materializeLegacy(obj.CVSequence.Context);
            subj = obj.SubjectSequence.materializeLegacy(obj.SubjectSequence.Context);
            PREPROC = cv;
            PREPROC = NMPreprocGlobalOptions.toLegacy(PREPROC, obj.GlobalOptions, obj.Context);
            if isfield(subj,'SPATIAL') && ~isempty(subj.SPATIAL)
                PREPROC.SPATIAL = subj.SPATIAL;
            elseif isfield(PREPROC,'SPATIAL')
                PREPROC = rmfield(PREPROC,'SPATIAL');
            end
        end

        function updateNM(obj)
            % updateNM  Write the current legacy PREPROC branch back into the bound NM struct.
            %   Only valid for orchestrators created fromNM; it centralizes TrainParam.PREPROC cell
            %   growth and branch assignment.

            if isempty(obj.NM) || isempty(obj.VarIndex)
                error('NMPreprocOrchestrator:noNM','This orchestrator was not created from an NM struct.');
            end
            if ~isfield(obj.NM,'TrainParam') || ~isstruct(obj.NM.TrainParam), obj.NM.TrainParam = struct(); end
            if ~isfield(obj.NM.TrainParam,'PREPROC') || isempty(obj.NM.TrainParam.PREPROC), obj.NM.TrainParam.PREPROC = {}; end
            obj.NM.TrainParam.PREPROC{obj.VarIndex} = obj.toLegacyPreproc();
        end

        function seq = openUI(obj, outDir, ctx, port)
            % openUI  Open the browser preprocessing editor for this orchestrator.
            %   Creates a temporary UI package, serves orchestrator state/specification through the
            %   bridge, and returns a UI session object rather than directly mutating NM.

            % openUI Open the staged preprocessing browser UI.
            %
            % Supported signatures:
            %   obj.openUI()
            %   obj.openUI(outDir)
            %   obj.openUI(outDir, port)              % legacy shorthand
            %   obj.openUI(outDir, ctx)
            %   obj.openUI(outDir, ctx, port)
            %
            % This mirrors the newer training/ML orchestrator signature while
            % preserving the older preprocessing call form where the third
            % argument was the port.
            if nargin < 2 || isempty(outDir)
                outDir = fullfile(tempdir,'nm_preproc_ui_orchestrator');
            end
            if nargin < 3
                ctx = [];
            end
            if nargin < 4
                port = [];
            end

            % Backward compatibility: openUI(outDir, port).
            if isempty(port) && (isnumeric(ctx) || (ischar(ctx) && ~isempty(ctx)) || (isstring(ctx) && isscalar(ctx)))
                port = ctx;
                ctx = [];
            end

            if isempty(ctx)
                ctx = obj.Context;
            end
            % Leave an omitted port empty so nm_open_ui can select a
            % randomized user-local bridge port. An explicitly supplied port
            % remains authoritative for callers that require a fixed endpoint.

            obj.Context = ctx;
            obj.refreshStageContexts();
            NMPreprocUI.open(obj, outDir, ctx, port);
            seq = obj.CVSequence;
        end

        function spec = toUISpec(obj, ctx)
            % toUISpec  Return the full browser/API schema for preprocessing editing.
            %   Combines context summary, global-option schema, subject-sequence schema, CV-sequence
            %   schema, and backward-compatible aliases.

            if nargin >= 2 && ~isempty(ctx)
                obj.Context = ctx;
                obj.refreshStageContexts();
            end
            sSpec = obj.SubjectSequence.toUISpec(obj.SubjectSequence.Context);
            cSpec = obj.CVSequence.toUISpec(obj.CVSequence.Context);
            spec = cSpec;
            spec.kind = 'NMPreprocStagedPipeline';
            spec.title = 'NeuroMiner preprocessing pipeline';
            spec.stageSpecs = struct('subject',sSpec,'cv',cSpec);
            spec.availableModules = cSpec.availableModules;
            spec.globalOptions = NMPreprocGlobalOptions.toUISpec(obj.Context, obj.GlobalOptions);
            spec.schemaVersion = 4;
        end

        function state = toUIState(obj)
            % toUIState  Serialize the orchestrator to lightweight UI state.
            %   Exports global options and both sequences for browser round-trip, keeping legacy
            %   metadata and backward-compatible sequence aliases.

            state = struct();
            state.global = NMPreprocGlobalOptions.normalize(obj.GlobalOptions, obj.Context);
            state.subject = obj.SubjectSequence.toUIState();
            state.cv = obj.CVSequence.toUIState();
            state.sequence = state.cv.sequence; % backward-compatible preview/save fallback
        end

        function applyUIState(obj, state, ctx)
            % applyUIState  Apply browser/API state back to the orchestrator.
            %
            % Normalizes global options and subject/CV sequences, refreshes contexts, and leaves
            % validation/export to later calls.
            %
            % state.cv: carries the cv value between browser/API state and legacy NeuroMiner structures.
            % state.global: carries the global value between browser/API state and legacy NeuroMiner structures.
            % state.sequence: carries the sequence value between browser/API state and legacy NeuroMiner structures.
            % state.subject: carries the subject value between browser/API state and legacy NeuroMiner structures.

            if nargin < 3 || isempty(ctx), ctx = obj.Context; end
            obj.Context = ctx;
            if isfield(state,'global')
                obj.GlobalOptions = NMPreprocGlobalOptions.normalize(state.global, ctx);
            else
                obj.GlobalOptions = NMPreprocGlobalOptions.normalize(obj.GlobalOptions, ctx);
            end
            obj.refreshStageContexts();
            if isfield(state,'subject')
                obj.SubjectSequence.applyUIState(state.subject, obj.SubjectSequence.Context);
            else
                obj.SubjectSequence.Steps = {};
            end
            if isfield(state,'cv')
                obj.CVSequence.applyUIState(state.cv, obj.CVSequence.Context);
            elseif isfield(state,'sequence')
                obj.CVSequence.applyUIState(state, obj.CVSequence.Context);
            end
            obj.normalizeLabelImputePlacement();
        end

        function txt = showDetails(obj, varargin)
            % showDetails  Return or print a two-section description of subject and CV preprocessing.
            %   Used by CLI menus, diagnostics, and power users to inspect the complete
            %   preprocessing branch without reading legacy structs.

            s = obj.SubjectSequence.showDetails('returnText',true,varargin{:});
            c = obj.CVSequence.showDetails('returnText',true,varargin{:});
            txt = sprintf('SUBJECT-SPECIFIC PREPROCESSING\n%s\nCV-BOUND PREPROCESSING\n%s', s, c);
            if nargout == 0, fprintf('%s', txt); end
        end

        function act = cliMenu(obj, parentstr)
            % cliMenu  Launch the legacy-style command-line preprocessing menu.
            %   Provides interactive add/remove/show actions over the same orchestrator/sequence API
            %   used by non-interactive scripts.

            % Minimal staged CLI wrapper. The legacy nk_Preproc_config menu
            % remains the authoritative full CLI; this method keeps the
            % modular orchestrator API usable from the command line.
            if nargin < 2 || isempty(parentstr), parentstr = 'NM preprocessing orchestrator'; end
            if exist('nk_PrintLogo','file') == 2, nk_PrintLogo; end
            fprintf('\n%s\n', obj.showDetails('returnText',true,'compact'));
            actstr = ['Add subject-specific step|Add CV-bound step|' ...
                      'Remove subject-specific step|Remove CV-bound step|' ...
                      'Move subject-specific block|Move CV-bound block|' ...
                      'Validate sequence|Back/Quit'];
            actmnu = [1 2 3 4 5 6 7 0];
            act = nk_input(parentstr,0,'mq',actstr,actmnu);
            switch act
                case 1
                    obj.cliAddStep('subject', parentstr);
                case 2
                    obj.cliAddStep('cv', parentstr);
                case 3
                    idx = nk_input('Remove subject-specific preprocessing step',0,'w1',1);
                    obj.removeStepAtStage('subject', idx);
                case 4
                    idx = nk_input('Remove CV-bound preprocessing step',0,'w1',1);
                    obj.removeStepAtStage('cv', idx);
                case 5
                    fromIdx = nk_input('Move subject-specific block from step',0,'w1',1);
                    toIdx   = nk_input('Move subject-specific block to position',0,'w1',1);
                    obj.moveStepAtStage('subject', fromIdx, toIdx);
                case 6
                    fromIdx = nk_input('Move CV-bound block from step',0,'w1',1);
                    toIdx   = nk_input('Move CV-bound block to position',0,'w1',1);
                    obj.moveStepAtStage('cv', fromIdx, toIdx);
                case 7
                    rep = obj.validate();
                    if rep.ok, fprintf('\nSequence validation passed.\n'); else, fprintf('\n%s\n', strjoin(rep.errors,newline)); end
            end
        end

        function txt = showAddable(obj, insertIndex, stage)
            % showAddable  Return or print addable modules for a stage/index.
            %   Formats ruleset availability output for CLI diagnostics and power-user inspection.

            if nargin < 3 || isempty(stage), stage = 'cv'; end
            if nargin < 2 || isempty(insertIndex), insertIndex = obj.sequenceForStage(stage).numSteps()+1; end
            mods = obj.getAddableModules(insertIndex, stage);
            lines = {};
            lines{end+1} = sprintf('Addable %s preprocessing modules at position %d:', stage, insertIndex); %#ok<AGROW>
            if isempty(mods)
                lines{end+1} = '  <none>'; %#ok<AGROW>
            else
                for i = 1:numel(mods)
                    lines{end+1} = sprintf('  %2d | %-18s %s', i, mods{i}.id, mods{i}.displayName); %#ok<AGROW>
                end
            end
            txt = sprintf('%s\n', lines{:});
            if nargout == 0, fprintf('%s', txt); end
        end
    end

    methods (Access = private)
        function seq = sequenceForStage(obj, stage)
            stage = lower(char(stage));
            switch stage
                case {'subject','noncv','non-cv'}
                    seq = obj.SubjectSequence;
                case {'cv','actparam'}
                    seq = obj.CVSequence;
                otherwise
                    error('NMPreprocOrchestrator:badStage','Unknown preprocessing stage: %s', stage);
            end
        end

        function errs = crossStageErrors(obj)
            errs = {};
            ids = [obj.collectUniqueIds(obj.SubjectSequence), obj.collectUniqueIds(obj.CVSequence)];
            for i = 1:numel(ids)
                id = ids{i};
                if ~obj.Registry.has(id), continue; end
                m = obj.Registry.get(id); info = m.info();
                if isfield(info.capabilities,'uniqueAcrossStages') && info.capabilities.uniqueAcrossStages
                    n = obj.countModule(id, obj.SubjectSequence) + obj.countModule(id, obj.CVSequence);
                    if n > 1
                        errs{end+1} = sprintf('Module %s may occur only once across subject-specific and CV-bound preprocessing.', m.Id); %#ok<AGROW>
                    end
                end
            end
            nSpatial = obj.countSpatialFeatureExtractors(obj.SubjectSequence) + obj.countSpatialFeatureExtractors(obj.CVSequence);
            if nSpatial > 1
                errs{end+1} = 'Only one spatial feature extractor is allowed across subject-specific and CV-bound preprocessing. JuSpace and ROI means are mutually exclusive once selected in either stage.'; %#ok<AGROW>
            end
        end

        function ids = collectUniqueIds(obj, seq)
            ids = {};
            for i = 1:numel(seq.Steps)
                ids{end+1} = obj.Registry.canonicalId(seq.Steps{i}.moduleId); %#ok<AGROW>
            end
            ids = unique(ids);
        end

        function n = countSpatialFeatureExtractors(obj, seq)
            n = 0;
            for i = 1:numel(seq.Steps)
                if obj.RuleSet.stepIsSpatialFeatureExtractor(seq, seq.Steps{i})
                    n = n + 1;
                end
            end
        end

        function warns = crossStageWarnings(obj)
            warns = {};
            subjHasSpatialExtractor = false;
            for ii = 1:numel(obj.SubjectSequence.Steps)
                if obj.RuleSet.stepIsSpatialFeatureExtractor(obj.SubjectSequence, obj.SubjectSequence.Steps{ii})
                    subjHasSpatialExtractor = true;
                    break;
                end
            end
            if ~subjHasSpatialExtractor, return; end
            for jj = 1:numel(obj.CVSequence.Steps)
                if obj.RuleSet.stepIsDimensionalityReductionLike(obj.CVSequence, obj.CVSequence.Steps{jj})
                    warns{end+1} = sprintf(['Subject-specific spatial feature extraction is followed by CV-bound %s. ', ...
                        'This stacks spatial feature extraction with a dimensionality-reduction-like operation; ', ...
                        'it is technically allowed but should be justified scientifically.'], obj.CVSequence.Steps{jj}.moduleId); %#ok<AGROW>
                    break;
                end
            end
            for jj = 1:numel(obj.CVSequence.Steps)
                if obj.RuleSet.stepUsesExternalFeatureWeights(obj.CVSequence.Steps{jj})
                    warns{end+1} = sprintf(['Subject-specific spatial feature extraction is followed by CV-bound %s using an external feature-weight vector. ', ...
                        'The external vector must match the post-JuSpace/ROImeans feature space; otherwise execution will fail.'], obj.CVSequence.Steps{jj}.moduleId); %#ok<AGROW>
                    break;
                end
            end
        end

        function PREPROC = migrateLegacyLabelImputePlacement(obj, PREPROC)
            if isempty(PREPROC) || ~isstruct(PREPROC), return; end
            if ~isfield(PREPROC,'LABELMOD') || ~isstruct(PREPROC.LABELMOD) || ...
                    ~isfield(PREPROC.LABELMOD,'LABELIMPUTE') || isempty(PREPROC.LABELMOD.LABELIMPUTE)
                return;
            end
            L = PREPROC.LABELMOD.LABELIMPUTE;
            if ~isfield(L,'method') || isempty(L.method), L.method = 'none'; end
            if ~isfield(L,'k') || isempty(L.k), L.k = 7; end
            if obj.isNoneLabelImputeConfig(L), return; end

            % Non-'none' label propagation is a CV-bound preprocessing step,
            % because its position determines which feature representation is
            % available to nk_PerfImputeLabelObj / act_labelimpute.
            PREPROC = obj.removeGlobalLabelImputeFromPreproc(PREPROC);
            if ~obj.preprocHasLabelImputeActparam(PREPROC)
                if ~isfield(PREPROC,'ACTPARAM') || isempty(PREPROC.ACTPARAM)
                    PREPROC.ACTPARAM = {};
                end
                PREPROC.ACTPARAM{end+1} = struct('cmd','labelimpute','LABELIMPUTE',L);
            end
            obj.GlobalOptions.enableLabelImpute = false;
            obj.GlobalOptions.labelImputeMethod = 'none';
            obj.GlobalOptions.labelImputeK = double(L.k);
        end

        function normalizeLabelImputePlacement(obj)
            % Enforce one public contract for all entry points:
            %   method == 'none'  -> global LABELMOD/final label handling
            %   method ~= 'none'  -> CV-bound ACTPARAM labelimpute step
            if ~obj.Registry.has('labelimpute'), return; end
            module = obj.Registry.get('labelimpute');
            needsValidation = false;

            % 1) A CV-bound labelimpute step with method 'none' belongs to
            % the global/final label-handling area instead.
            rem = [];
            for i = 1:numel(obj.CVSequence.Steps)
                st = obj.CVSequence.Steps{i};
                if strcmpi(obj.Registry.canonicalId(st.moduleId),'labelimpute') && obj.isNoneLabelImputeConfig(st.config)
                    obj.setGlobalLabelImputeNone(st.config);
                    rem(end+1) = i; %#ok<AGROW>
                end
            end
            if ~isempty(rem)
                obj.CVSequence.Steps(rem) = [];
                needsValidation = true;
            end

            % 2) A non-'none' global label-imputation selection is moved into
            % the CV pipeline. It is appended by the programmatic API; the UI
            % performs the same move interactively and the user can reposition it.
            if isfield(obj.GlobalOptions,'enableLabelImpute') && logical(obj.GlobalOptions.enableLabelImpute) && ...
                    isfield(obj.GlobalOptions,'labelImputeMethod') && ~strcmpi(char(obj.GlobalOptions.labelImputeMethod),'none')
                cfg = obj.labelImputeConfigFromGlobal();
                found = false;
                for i = 1:numel(obj.CVSequence.Steps)
                    if strcmpi(obj.Registry.canonicalId(obj.CVSequence.Steps{i}.moduleId),'labelimpute')
                        obj.CVSequence.Steps{i}.config = module.parseConfig(cfg);
                        found = true;
                        needsValidation = true;
                        break;
                    end
                end
                if ~found
                    obj.CVSequence.add(module.Id, cfg);
                    needsValidation = false; % add() validated the final sequence.
                end
                obj.GlobalOptions.enableLabelImpute = false;
                obj.GlobalOptions.labelImputeMethod = 'none';
            end
            if needsValidation
                obj.CVSequence.validateSoft(obj.CVSequence.Context);
            end
        end

        function cfg = labelImputeConfigFromGlobal(obj)
            cfg = struct();
            if isfield(obj.GlobalOptions,'labelImputeMethod'), cfg.method = obj.GlobalOptions.labelImputeMethod; else, cfg.method = 'none'; end
            if isfield(obj.GlobalOptions,'labelImputeK'), cfg.k = obj.GlobalOptions.labelImputeK; else, cfg.k = 7; end
        end

        function setGlobalLabelImputeNone(obj, cfg)
            if nargin < 2 || isempty(cfg), cfg = struct(); end
            obj.GlobalOptions.enableLabelImpute = true;
            obj.GlobalOptions.labelImputeMethod = 'none';
            if isfield(cfg,'k') && ~isempty(cfg.k), obj.GlobalOptions.labelImputeK = double(cfg.k); end
        end

        function tf = isNoneLabelImputeConfig(~, cfg)
            tf = true;
            if isempty(cfg), return; end
            if isfield(cfg,'LABELIMPUTE'), cfg = cfg.LABELIMPUTE; end
            if isfield(cfg,'method') && ~isempty(cfg.method)
                tf = strcmpi(char(cfg.method),'none');
            end
        end

        function tf = preprocHasLabelImputeActparam(~, PREPROC)
            tf = false;
            if ~isfield(PREPROC,'ACTPARAM') || isempty(PREPROC.ACTPARAM), return; end
            for i = 1:numel(PREPROC.ACTPARAM)
                A = PREPROC.ACTPARAM{i};
                if isstruct(A) && isfield(A,'cmd') && strcmpi(char(A.cmd),'labelimpute')
                    tf = true; return;
                end
            end
        end

        function PREPROC = removeGlobalLabelImputeFromPreproc(~, PREPROC)
            if ~isfield(PREPROC,'LABELMOD') || ~isstruct(PREPROC.LABELMOD), return; end
            LM = PREPROC.LABELMOD;
            if isfield(LM,'LABELIMPUTE'), LM = rmfield(LM,'LABELIMPUTE'); end
            if isfield(LM,'cmd') && strcmpi(char(LM.cmd),'labelimpute'), LM = rmfield(LM,'cmd'); end
            if isempty(fieldnames(LM))
                PREPROC = rmfield(PREPROC,'LABELMOD');
            else
                PREPROC.LABELMOD = LM;
            end
        end

        function cliAddStep(obj, stage, parentstr)
            seq = obj.sequenceForStage(stage);
            mods = obj.getAddableModules(seq.numSteps()+1, stage);
            if isempty(mods)
                fprintf('\nNo %s preprocessing module is currently addable in this context.\n', stage);
                return;
            end
            actstr = ''; actmnu = [];
            for i = 1:numel(mods)
                if isempty(actstr), actstr = mods{i}.displayName; else, actstr = [actstr '|' mods{i}.displayName]; end %#ok<AGROW>
                actmnu(end+1) = i; %#ok<AGROW>
            end
            cmd = nk_input(sprintf('Select %s preprocessing type', stage),0,'mq',actstr,actmnu);
            if ~cmd, return; end
            module = obj.Registry.get(mods{cmd}.id);
            ctx = seq.Context; ctx.parentstr = parentstr;
            cfg = module.defaultConfig(ctx);
            [cfg, ~] = module.cli_configure(cfg, ctx); %#ok<ASGLU>
            parentStep = struct('moduleId',module.Id,'config',cfg);
            children = obj.RuleSet.autoChildSteps(module.Id, obj.Registry, parentStep);
            if ~isempty(children)
                child = obj.Registry.get(children{1}.moduleId);
                childCfg = children{1}.config;
                [childCfg, ~] = child.cli_configure(childCfg, ctx); %#ok<ASGLU>
                obj.addBlockAtStage(stage, module.Id, cfg, child.Id, childCfg);
            else
                obj.addStepAtStage(stage, module.Id, cfg);
            end
        end

        function n = countModule(obj, id, seq)
            n = 0; id = obj.Registry.canonicalId(id);
            for i = 1:numel(seq.Steps)
                if strcmp(obj.Registry.canonicalId(seq.Steps{i}.moduleId), id), n = n + 1; end
            end
        end
    end
end

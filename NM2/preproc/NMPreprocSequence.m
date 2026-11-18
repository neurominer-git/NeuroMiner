classdef NMPreprocSequence < handle
% NMPreprocSequence
% -------------------------------------------------------------------------
% Programmatic, registry-backed preprocessing pipeline builder.
% It is deliberately independent of concrete preprocessing names: all step
% defaults, validation, legacy conversion, and UI schemas come from modules.
% -------------------------------------------------------------------------

    properties
        Registry
        RuleSet
        Context struct = struct()
        LegacyMeta struct = struct()
        Steps cell = {}
        ExecutionStage char = 'cv'
        ValidationReport struct = struct('ok',true,'errors',{{}},'warnings',{{}})
    end

    methods
        function obj = NMPreprocSequence(registry, ruleset, ctx, executionStage)
            % NMPreprocSequence  Construct a stage-specific preprocessing sequence.
            %
            % Binds a registry, ruleset, context, and stage name (subject or CV) to an ordered set
            % of canonical module steps.
            %
            % ctx.executionStage: exposes the execution stage execution-context value to preprocessing/runtime code.

            if nargin < 1 || isempty(registry), registry = NMModuleRegistry.default(); end
            if nargin < 2 || isempty(ruleset), ruleset = NMPreprocRuleSet.default(); end
            if nargin < 3 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            if nargin < 4 || isempty(executionStage)
                if isstruct(ctx) && isfield(ctx,'executionStage') && ~isempty(ctx.executionStage)
                    executionStage = char(ctx.executionStage);
                else
                    executionStage = 'cv';
                end
            end
            obj.Registry = registry;
            obj.RuleSet = ruleset;
            obj.ExecutionStage = lower(char(executionStage));
            ctx.executionStage = obj.ExecutionStage;
            obj.Context = ctx;
        end

        function setContext(obj, ctx)
            % setContext  Update the context used by this sequence.
            %   The orchestrator calls this when switching NM/modality/stage facts so subsequent
            %   schemas, validation, and legacy conversion see the correct state.

            if nargin < 2 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            obj.Context = ctx;
        end

        function setExecutionStage(obj, executionStage)
            % setExecutionStage  Change whether this sequence represents subject-level or CV-bound preprocessing.
            %   Updates the stage label and context flag used by ruleset availability, legacy
            %   export, and UI schema generation.

            if nargin < 2 || isempty(executionStage), executionStage = 'cv'; end
            obj.ExecutionStage = lower(char(executionStage));
            obj.Context.executionStage = obj.ExecutionStage;
        end

        function idx = add(obj, moduleId, varargin)
            % add  Append a module step after validating availability at the end of the sequence.
            %   Parses the module config, enforces ruleset constraints, and stores the canonical
            %   step struct used by later legacy conversion.

            idx = numel(obj.Steps) + 1;
            obj.insert(idx, moduleId, varargin{:});
        end

        function idx = addBlock(obj, parentId, parentCfg, childId, childCfg)
            % addBlock  Append a parent/child preprocessing block.
            %   Used for modules whose sequence rules require a companion child step, such as
            %   reduction followed by dimension extraction.

            % Add a two-step producer/consumer block with explicit configs.
            % This is mainly useful for rankfeat->extfeat and later
            % reducedim/remvarcomp->extdim. The generic ruleset still
            % validates the resulting sequence.
            if nargin < 3 || isempty(parentCfg), parentCfg = struct(); end
            if nargin < 5 || isempty(childCfg), childCfg = struct(); end
            idx = numel(obj.Steps) + 1;
            pmod = obj.Registry.get(parentId);
            cmod = obj.Registry.get(childId);
            obj.RuleSet.assertCanInsert(pmod.Id, obj.Context, obj, idx);
            parseCtx = struct('nm2PreprocContext', obj.Context);
            pcfg = pmod.parseConfig(parseCtx, parentCfg);
            ccfg = cmod.parseConfig(parseCtx, childCfg);
            obj.Steps = [obj.Steps, {obj.makeStep(pmod.Id, pcfg)}, {obj.makeStep(cmod.Id, ccfg)}];
            obj.validate(obj.Context);
        end

        function insert(obj, idx, moduleId, varargin)
            % insert  Insert a module step at a requested position.
            %   This is the indexed API behind orchestrator insertion and UI drag/drop logic; it
            %   checks rule availability before mutating the sequence.

            if idx < 1 || idx > numel(obj.Steps)+1
                error('NMPreprocSequence:badIndex','Insert index out of range.');
            end
            module = obj.Registry.get(moduleId);
            obj.RuleSet.assertCanInsert(module.Id, obj.Context, obj, idx);
            parseCtx = struct('nm2PreprocContext', obj.Context);
            cfg = module.parseConfig(parseCtx, varargin{:});
            step = obj.makeStep(module.Id, cfg);
            obj.Steps = [obj.Steps(1:idx-1), {step}, obj.Steps(idx:end)];
            obj.applyAutoChild(idx);
            obj.validate(obj.Context);
        end

        function remove(obj, idx, varargin)
            % remove  Remove one step or a parent/child block from the sequence.
            %   The method respects block semantics when requested so dependent child steps are not
            %   accidentally left orphaned.

            obj.assertIndex(idx);
            cascade = true;
            if ~isempty(varargin)
                for k = 1:2:numel(varargin)
                    if strcmpi(varargin{k},'cascade'), cascade = logical(varargin{k+1}); end
                end
            end
            if cascade
                remIdx = obj.RuleSet.removalIndices(obj, idx);
            else
                remIdx = idx;
            end
            obj.Steps(remIdx) = [];
            obj.validate(obj.Context);
        end

        function move(obj, fromIdx, toIdx)
            % move  Compatibility wrapper for moving one preprocessing block.
            %   Delegates to moveBlock so existing API callers get dependency-aware movement rather
            %   than raw single-step reordering.

            obj.moveBlock(fromIdx, toIdx);
        end

        function moveBlock(obj, fromIdx, toIdx)
            % moveBlock  Move a step or dependency block to a new index.
            %   Used by interactive ordering tools; validation is expected after movement because
            %   sequence constraints can depend on neighboring steps.

            obj.assertIndex(fromIdx);
            if toIdx < 1 || toIdx > numel(obj.Steps)
                error('NMPreprocSequence:badIndex','Target index out of range.');
            end
            block = obj.RuleSet.blockIndices(obj, fromIdx);
            moving = obj.Steps(block);
            keep = true(1,numel(obj.Steps)); keep(block) = false;
            rest = obj.Steps(keep);
            % Convert target position into the coordinate system after block removal.
            nBefore = sum(block < toIdx);
            toIdx2 = toIdx - nBefore;
            if toIdx2 < 1, toIdx2 = 1; end
            if toIdx2 > numel(rest)+1, toIdx2 = numel(rest)+1; end
            obj.Steps = [rest(1:toIdx2-1), moving, rest(toIdx2:end)];
            obj.validate(obj.Context);
        end

        function replaceConfig(obj, idx, cfg)
            % replaceConfig  Replace the canonical config of an existing step.
            %   Validates the new config through the owning module and updates only that step,
            %   preserving sequence order and module identity.

            obj.assertIndex(idx);
            st = obj.Steps{idx};
            module = obj.Registry.get(st.moduleId);
            [cfg, report] = module.validateConfig(cfg, obj.Context, true);
            if ~report.ok
                error('NMPreprocSequence:invalidConfig','%s',strjoin(report.errors,newline));
            end
            st.config = cfg;
            obj.Steps{idx} = st;
            obj.validate(obj.Context);
        end

        function n = numSteps(obj)
            % numSteps  Return the number of configured steps.
            %   Used by UI insertion logic, addable-module checks, and scripts that need to reason
            %   about sequence positions.

            n = numel(obj.Steps);
        end

        function st = getStep(obj, idx)
            % getStep  Return one stored step struct by index.
            %   The returned struct contains moduleId and canonical config and is used by UI
            %   inspectors and scripted sequence manipulation.

            obj.assertIndex(idx); st = obj.Steps{idx};
        end

        function report = validate(obj, ctx)
            % validate  Validate this sequence in its current context.
            %   Runs ruleset order/dependency checks plus module-level config validation and returns
            %   combined errors/warnings for the orchestrator and UI.

            if nargin < 2 || isempty(ctx), ctx = obj.Context; end
            report = obj.validateSoft(ctx);
            if ~report.ok
                error('NMPreprocSequence:invalidSequence','%s',strjoin(report.errors,newline));
            end
        end

        function report = validateSoft(obj, ctx)
            % validateSoft  Validate the sequence without throwing.
            %   Aggregates module-level config reports, ruleset sequence diagnostics, and UI issue
            %   annotations so callers can display problems before deciding whether to export.

            % validateSoft validates restored/stored preprocessing sequences
            % without throwing. Interactive insert/move/replace operations still
            % use validate(), whereas UI rehydration uses this path so that a
            % now-inapplicable legacy step can be shown and removed instead of
            % preventing the configurator from opening.
            if nargin < 2 || isempty(ctx), ctx = obj.Context; end
            report = struct('ok',true,'errors',{{}},'warnings',{{}});
            ids = cell(1,numel(obj.Steps));
            for i = 1:numel(obj.Steps)
                try
                    ids{i} = obj.Registry.canonicalId(obj.Steps{i}.moduleId);
                catch ME
                    ids{i} = '';
                    report.errors{end+1} = sprintf('Step %d: could not resolve module id: %s', i, ME.message); %#ok<AGROW>
                end
            end
            for i = 1:numel(obj.Steps)
                st = obj.Steps{i};
                try
                    module = obj.Registry.get(st.moduleId);
                    [cfg, vr] = module.validateConfig(st.config, ctx, true);
                    obj.Steps{i}.config = cfg;
                    if isstruct(vr) && isfield(vr,'ok') && ~vr.ok
                        errs = {};
                        if isfield(vr,'errors'), errs = vr.errors; end
                        if isempty(errs), errs = {'Configuration did not pass validation.'}; end
                        report.errors = [report.errors, cellfun(@(x) sprintf('Step %d/%s: %s', i, st.moduleId, x), errs, 'UniformOutput', false)]; %#ok<AGROW>
                    end
                    mi = module.info(); seq = mi.sequence;
                    if isfield(seq,'allowMultiple') && ~seq.allowMultiple && sum(strcmp(obj.Registry.canonicalId(module.Id), ids)) > 1
                        report.errors{end+1} = sprintf('Module %s may occur only once.', module.Id); %#ok<AGROW>
                    end
                catch ME
                    modId = '';
                    try, modId = char(string(st.moduleId)); catch, end
                    report.errors{end+1} = sprintf('Step %d/%s: %s', i, modId, ME.message); %#ok<AGROW>
                end
            end
            try
                rr = obj.RuleSet.validateSequence(obj, obj.Registry, ctx);
                report.errors = [report.errors rr.errors];
                report.warnings = [report.warnings rr.warnings];
            catch ME
                report.errors{end+1} = ME.message; %#ok<AGROW>
            end
            report.ok = isempty(report.errors);
            obj.ValidationReport = report;
        end


        function issue = uiIssueForStep(obj, idx)
            % uiIssueForStep  Return the most relevant validation issue for one UI step card.
            %   Looks up cached validation errors/warnings and converts them to a severity/message
            %   struct used by browser previews.

            issue = struct('hasIssue',false,'severity','','message','');
            try
                if idx < 1 || idx > numel(obj.Steps), return; end
                rep = obj.ValidationReport;
                errMsgs = obj.messagesForStep(rep, idx, 'errors');
                warnMsgs = obj.messagesForStep(rep, idx, 'warnings');
                if ~isempty(errMsgs)
                    issue.hasIssue = true;
                    issue.severity = 'error';
                    issue.message = strjoin(errMsgs, newline);
                elseif ~isempty(warnMsgs)
                    issue.hasIssue = true;
                    issue.severity = 'warning';
                    issue.message = strjoin(warnMsgs, newline);
                end
            catch
                issue = struct('hasIssue',false,'severity','','message','');
            end
        end

        function msgs = messagesForStep(obj, rep, idx, fieldName) %#ok<INUSL>
            % messagesForStep  Extract validation messages that refer to one step.
            %   Filters report errors or warnings by step index so UI cards and diagnostics can
            %   localize sequence problems.

            msgs = {};
            try
                if ~isstruct(rep) || ~isfield(rep, fieldName), return; end
                src = rep.(fieldName);
                if ischar(src) || isstring(src), src = cellstr(src); end
                if isempty(src), return; end
                if ~iscell(src), src = num2cell(src); end
                pat = sprintf('Step %d/', round(double(idx)));
                for jj = 1:numel(src)
                    msg = char(string(src{jj}));
                    if startsWith(strtrim(msg), pat)
                        msgs{end+1} = msg; %#ok<AGROW>
                    end
                end
            catch
                msgs = {};
            end
        end

        function PREPROC = toLegacy(obj, ctx)
            % toLegacy  Convert this sequence to a legacy PREPROC branch for its stage.
            %   Standalone export validates the sequence before materialization.

            if nargin < 2 || isempty(ctx), ctx = obj.Context; end
            obj.validate(ctx);
            PREPROC = obj.materializeLegacy(ctx);
        end

        function fromLegacy(obj, PREPROC, ctx)
            % fromLegacy  Populate the sequence from a legacy PREPROC branch.
            %   Decodes subject-level SPATIAL or CV-bound ACTPARAM commands into canonical module
            %   steps while preserving import metadata for round trips.

            if nargin < 3 || isempty(ctx), ctx = obj.Context; end
            obj.Steps = {};
            obj.LegacyMeta = struct();
            if isempty(PREPROC), return; end
            obj.LegacyMeta = PREPROC;
            if strcmpi(obj.ExecutionStage,'subject')
                if isfield(obj.LegacyMeta,'ACTPARAM'), obj.LegacyMeta = rmfield(obj.LegacyMeta,'ACTPARAM'); end
                if isfield(obj.LegacyMeta,'SPATIAL'), obj.LegacyMeta = rmfield(obj.LegacyMeta,'SPATIAL'); end
                if ~isfield(PREPROC,'SPATIAL') || isempty(PREPROC.SPATIAL), return; end
                spatial = PREPROC.SPATIAL;
                if iscell(spatial), spatial = [spatial{:}]; end
                for i = 1:numel(spatial)
                    legacy = spatial(i);
                    if ~isstruct(legacy), continue; end
                    moduleId = obj.moduleIdFromSpatial(legacy);
                    if isempty(moduleId), continue; end
                    if ~obj.Registry.has(moduleId)
                        warning('NMPreprocSequence:unknownSpatialStep','Skipping unregistered spatial step: %s', moduleId);
                        continue;
                    end
                    module = obj.Registry.get(moduleId);
                    cfg = module.fromLegacy(legacy, ctx);
                    obj.Steps{end+1} = obj.makeStep(module.Id, cfg); %#ok<AGROW>
                end
                obj.validateSoft(ctx);
                return;
            end
            if isfield(obj.LegacyMeta,'ACTPARAM'), obj.LegacyMeta = rmfield(obj.LegacyMeta,'ACTPARAM'); end
            if isfield(obj.LegacyMeta,'SPATIAL'), obj.LegacyMeta = rmfield(obj.LegacyMeta,'SPATIAL'); end
            if ~isfield(PREPROC,'ACTPARAM'), return; end
            for i = 1:numel(PREPROC.ACTPARAM)
                legacy = PREPROC.ACTPARAM{i};
                if ~isfield(legacy,'cmd'), continue; end
                if ~obj.Registry.has(legacy.cmd)
                    warning('NMPreprocSequence:unknownLegacyStep','Skipping unregistered legacy step: %s', legacy.cmd);
                    continue;
                end
                module = obj.Registry.get(legacy.cmd);
                cfg = module.fromLegacy(legacy, ctx);
                obj.Steps{end+1} = obj.makeStep(module.Id, cfg); %#ok<AGROW>
            end
            obj.validateSoft(ctx);
        end

        function state = toUIState(obj)
            % toUIState  Serialize the current sequence to lightweight UI state.
            %   Exports step ids, configs, and legacy metadata without heavy NM data, enabling
            %   browser round-trips and state persistence.

            state = struct();
            state.executionStage = obj.ExecutionStage;
            steps = cell(1,numel(obj.Steps));
            for i = 1:numel(obj.Steps)
                st = obj.Steps{i};
                issue = obj.uiIssueForStep(i);
                st.invalid = logical(issue.hasIssue);
                st.invalidSeverity = char(string(issue.severity));
                st.invalidReason = char(string(issue.message));
                steps{i} = NMConfigTools.jsonSafe(st);
            end
            state.sequence = struct('steps',{steps});
        end

        function applyUIState(obj, state, ctx)
            % applyUIState  Replace sequence contents from UI/API state.
            %
            % Normalizes incoming step cells and stage metadata before validation/export, keeping
            % UI edits on the canonical module path.
            %
            % state.sequence: carries the sequence value between browser/API state and legacy NeuroMiner structures.

            if nargin < 3 || isempty(ctx), ctx = obj.Context; end %#ok<NASGU>
            obj.Steps = {};
            if ~isfield(state,'sequence') || ~isfield(state.sequence,'steps'), return; end
            steps = state.sequence.steps;
            if isstruct(steps), steps = num2cell(steps); end
            for i = 1:numel(steps)
                st = steps{i};
                if ~isfield(st,'moduleId') || ~obj.Registry.has(st.moduleId), continue; end
                module = obj.Registry.get(st.moduleId);
                parseCtx = struct('nm2PreprocContext', ctx);
                cfg = module.parseConfig(parseCtx, st.config);
                if ~isfield(st,'uid') || isempty(st.uid), st.uid = obj.makeUid(module.Id); end
                if ~isfield(st,'enabled'), st.enabled = true; end
                st.moduleId = module.Id; st.config = cfg;
                obj.Steps{end+1} = st; 
            end
            obj.validateSoft(ctx);
        end

        function spec = toUISpec(obj, ctx)
            % toUISpec  Return the UI/API schema for this sequence.
            %   Combines addable module metadata and step schemas so the browser can render valid
            %   controls without hard-coded module knowledge.

            if nargin < 2 || isempty(ctx), ctx = obj.Context; end
            metas = obj.Registry.infos(); specs = obj.Registry.configSpecs(ctx);
            % A module may be unavailable at the current end position but still
            % valid as an insertion before an image-space-invalidating step
            % such as dimensionality reduction. Therefore the UI selector gets
            % modules addable at any legal insertion point; the browser and
            % ruleset still validate the exact requested position.
            ids = obj.Registry.list(); addable = {}; seen = containers.Map('KeyType','char','ValueType','logical');
            for ii = 1:numel(ids)
                ctx2 = ctx; ctx2.internalForAdd = true; ctx2.ignoreCurrentSequenceForSelector = true;
                for pos = 1:(numel(obj.Steps)+1)
                    % The browser selector must contain all modules that are
                    % eligible for the current stage/context, even if the module
                    % is already present. The browser then applies the live
                    % current-state filter after add/remove/move operations. If
                    % we remove already-selected singleton modules here, e.g.
                    % smoothing, they cannot reappear after the user removes
                    % the corresponding step without regenerating the whole UI.
                    [ok, reasons] = obj.RuleSet.isAvailable(ids{ii}, ctx2, obj, pos); %#ok<ASGLU>
                    if ok
                        info = metas{ii}; info.available = true; info.unavailableReasons = {};
                        key = lower(info.id);
                        if ~isKey(seen,key), addable{end+1} = info; seen(key) = true; end %#ok<AGROW>
                        break;
                    end
                end
            end
            spec = struct();
            spec.kind = 'NMPreprocPipeline';
            spec.executionStage = obj.ExecutionStage;
            if strcmpi(obj.ExecutionStage,'subject')
                spec.title = 'Subject-specific preprocessing';
            else
                spec.title = 'CV-bound preprocessing';
            end
            spec.availableModules = addable;
            spec.allModules = metas;
            spec.moduleSpecs = specs;
            spec.rules = obj.RuleSet.toUISpec(ctx);
            spec.resolvedStepFacts = obj.RuleSet.resolveSequenceFacts(obj, true);
            defaultFacts = cell(1,numel(ids));
            for ii = 1:numel(ids)
                module = obj.Registry.get(ids{ii});
                step = struct('moduleId',module.Id,'config',NMConfigTools.defaultsFromSpec(specs{ii}));
                defaultFacts{ii} = struct('id',module.Id,'facts',obj.RuleSet.resolveStepFacts(obj,step));
            end
            spec.defaultRuleFacts = defaultFacts;
            [gateIndex, gateAllowed, gateReason, gateAllowedAtEnd] = obj.RuleSet.getSpatialExtractorGate(obj,ctx);
            spec.spatialExtractorGate = struct('insertIndex',gateIndex,'allowed',logical(gateAllowed), ...
                'reason',gateReason,'allowedAtEnd',logical(gateAllowedAtEnd));
            spec.context = NMPreprocContext.toUISummary(ctx);
            if exist('NMManualLinks','class') == 8
                spec.manualBaseUrl = NMManualLinks.basePreprocManual();
                spec.manualLinks = NMManualLinks.preprocLinks();
            else
                spec.manualBaseUrl = '';
                spec.manualLinks = struct();
            end
            spec.schemaVersion = 2;
        end



        function [Yout, trainedSteps] = fitTransform(obj, Y, ctx)
            % fitTransform  Fit and apply all executable steps to a training feature matrix.
            %   Runs the sequence in order through executeStep(mode="fit"), returning transformed
            %   training data plus per-step trained state for later application.

            % Fit all enabled preprocessing steps on Y and return the
            % transformed matrix plus per-step trained legacy parameters.
            if nargin < 3 || isempty(ctx), ctx = obj.Context; end
            obj.validate(ctx);
            Yout = Y;
            trainedSteps = cell(1,0);
            for i = 1:numel(obj.Steps)
                st = obj.Steps{i};
                if isfield(st,'enabled') && ~st.enabled, continue; end
                module = obj.Registry.get(st.moduleId);
                stepCtx = ctx;
                stepCtx.config = st.config;
                stepCtx.stepIndex = i;
                stepCtx.previousTrainedSteps = trainedSteps;
                [Yout, trained] = module.execute(Yout, [], 'fit', stepCtx);
                trainedSteps{end+1} = struct( ... 
                    'uid', st.uid, ...
                    'moduleId', module.Id, ...
                    'config', st.config, ...
                    'trained', trained);
            end
        end

        function Yout = transform(obj, Y, trainedSteps, ctx)
            % transform  Apply trained preprocessing steps to a new feature matrix.
            %   Replays stored trained step states in order and skips empty states, providing the
            %   application/OOCV counterpart to fitTransform.

            % Apply previously fitted preprocessing steps to new data.
            if nargin < 4 || isempty(ctx), ctx = obj.Context; end
            Yout = Y;
            if isempty(trainedSteps), return; end
            for i = 1:numel(trainedSteps)
                ts = trainedSteps{i};
                if ~isfield(ts,'moduleId') || ~obj.Registry.has(ts.moduleId)
                    error('NMPreprocSequence:badTrainedStep','Trained step %d has no registered moduleId.', i);
                end
                module = obj.Registry.get(ts.moduleId);
                stepCtx = ctx;
                if isfield(ts,'config'), stepCtx.config = ts.config; end
                stepCtx.stepIndex = i;
                if isfield(ts,'trained'), trained = ts.trained; else, trained = []; end
                stepCtx.previousTrainedSteps = trainedSteps(1:max(i-1,0));
                [Yout, ~] = module.execute(Yout, trained, 'transform', stepCtx);
            end
        end

        function [YtrOut, YtsOut, trainedSteps] = fitApply(obj, Ytr, Yts, ctx)
            % fitApply  Fit preprocessing on training data and apply it to test data.
            %   Convenience API for fold-wise code: fitTransform runs on Ytr and transform applies
            %   the trained states to Yts.

            % Convenience method for train/test validation of leakage-safe
            % preprocessing. Parameters are learned on Ytr and then applied
            % to Yts.
            if nargin < 4 || isempty(ctx), ctx = obj.Context; end
            [YtrOut, trainedSteps] = obj.fitTransform(Ytr, ctx);
            YtsOut = obj.transform(Yts, trainedSteps, ctx);
        end

        function [Yout, trained] = executeStep(obj, idx, Y, trained, mode, ctx)
            % executeStep  Execute one configured step in fit or transform mode.
            %
            % Resolves the step module, attaches step config to context, and delegates to the
            % module execute method while preserving trained-state output.
            %
            % Execute a single configured step. Use empty trained + 'fit' to
            % learn parameters; pass returned trained + 'transform' to apply.
            %
            % ctx.config: provides the module configuration currently being validated or executed.
            % ctx.stepIndex: exposes the step index execution-context value to preprocessing/runtime code.
            if nargin < 4, trained = []; end
            if nargin < 5 || isempty(mode), mode = 'fit'; end
            if nargin < 6 || isempty(ctx), ctx = obj.Context; end
            obj.assertIndex(idx);
            st = obj.Steps{idx};
            module = obj.Registry.get(st.moduleId);
            ctx.config = st.config;
            ctx.stepIndex = idx;
            [Yout, trained] = module.execute(Y, trained, mode, ctx);
        end

        function txt = showDetails(obj, varargin)
            % showDetails  Return or print a maintainable text description of the sequence.
            %   Used by CLI menus, diagnostics, and power users to inspect configured steps,
            %   configs, and legacy metadata.

            % showDetails Print a NeuroMiner-style overview of the configured
            % preprocessing sequence.
            %
            % Examples:
            %   seq.showDetails()
            %   seq.showDetails('all')
            %   seq.showDetails('steps',[2 5 6])
            %   txt = seq.showDetails('steps',[1 3],'verbosity','full','returnText',true)
            %
            % Options:
            %   'all'                  show all steps (default)
            %   'steps', [idx ...]     show selected step indices
            %   'verbosity'            'compact', 'normal', or 'full'
            %   'includeDisabled'      true/false, include disabled steps
            %   'showLegacy'           true/false, print legacy ACTPARAM summary
            %   'returnText'           true/false, also return text without relying on evalc
            %   'fid' or 'fileID'      output stream, default 1
            opts = obj.parseShowDetailsOptions(varargin{:});
            txt = obj.buildDetailsText(opts);
            if ~opts.returnText || nargout == 0
                fprintf(opts.fid, '%s', txt);
            end
        end

        function txt = explain(obj)
            % explain  Return an explanatory struct for one step or the whole sequence.
            %   Combines module metadata, config, validation, and sequence position so API users can
            %   understand what will be exported to legacy PREPROC.

            lines = cell(1,numel(obj.Steps));
            for i = 1:numel(obj.Steps)
                st = obj.Steps{i}; module = obj.Registry.get(st.moduleId);
                lines{i} = sprintf('%02d. %s (%s)', i, module.DisplayName, st.moduleId);
            end
            txt = strjoin(lines, newline);
        end
    end



    methods (Access = {?NMPreprocOrchestrator})
        function PREPROC = materializeLegacy(obj, ctx)
            % materializeLegacy  Serialize canonical sequence state after owner validation.
            %   Restricted to the defining class and NMPreprocOrchestrator so callers cannot bypass
            %   standalone toLegacy validation.

            PREPROC = obj.LegacyMeta;
            if strcmpi(obj.ExecutionStage,'subject')
                if isfield(PREPROC,'ACTPARAM'), PREPROC = rmfield(PREPROC,'ACTPARAM'); end
                if numel(obj.Steps) == 0
                    if isfield(PREPROC,'SPATIAL'), PREPROC = rmfield(PREPROC,'SPATIAL'); end
                    return;
                end
                spatialCells = cell(1,numel(obj.Steps));
                for i = 1:numel(obj.Steps)
                    st = obj.Steps{i}; module = obj.Registry.get(st.moduleId);
                    if ismethod(module,'toLegacySubject')
                        spatialCells{i} = module.toLegacySubject(st.config, ctx);
                    else
                        spatialCells{i} = module.toLegacy(st.config, ctx);
                    end
                end
                PREPROC.SPATIAL = obj.structCellToArray(spatialCells);
                return;
            end
            if isfield(PREPROC,'SPATIAL'), PREPROC = rmfield(PREPROC,'SPATIAL'); end
            actparam = {};
            for i = 1:numel(obj.Steps)
                st = obj.Steps{i}; module = obj.Registry.get(st.moduleId);
                legacy = module.toLegacy(st.config, ctx);
                actparam{end+1} = legacy; %#ok<AGROW>
            end
            if isempty(actparam)
                if isfield(PREPROC,'ACTPARAM'), PREPROC = rmfield(PREPROC,'ACTPARAM'); end
            else
                PREPROC.ACTPARAM = actparam;
            end
            if ~isfield(PREPROC,'BINMOD'), PREPROC.BINMOD = 1; end
        end
    end

    methods (Access = private)
        function step = makeStep(obj, moduleId, cfg)
            step = struct();
            step.uid = obj.makeUid(moduleId);
            step.moduleId = moduleId;
            step.enabled = true;
            step.config = cfg;
        end

        function uid = makeUid(~, moduleId)
            uid = sprintf('%s_%s', moduleId, char(java.util.UUID.randomUUID()));
            uid = regexprep(uid, '[^A-Za-z0-9_]', '_');
        end

        function arr = structCellToArray(~, cells)
            if isempty(cells), arr = struct([]); return; end
            fields = {};
            for ii = 1:numel(cells)
                if isempty(cells{ii}), cells{ii} = struct(); end
                fields = union(fields, fieldnames(cells{ii}));
            end
            arr = repmat(cell2struct(cell(numel(fields),1), fields(:), 1), 1, numel(cells));
            for ii = 1:numel(cells)
                fn = fieldnames(cells{ii});
                for jj = 1:numel(fn)
                    arr(ii).(fn{jj}) = cells{ii}.(fn{jj});
                end
            end
        end

        function moduleId = moduleIdFromSpatial(obj, legacy) %#ok<INUSL>
            moduleId = '';
            if isfield(legacy,'cmd') && ~isempty(legacy.cmd)
                cmd = char(legacy.cmd);
                if any(strcmpi(cmd, {'smoothing','waveletSpatial','JuSpace','ROImeans','spatiallegacy','graphComputation'}))
                    moduleId = cmd;
                    return;
                end
            end
            if ~isfield(legacy,'cubetype') || isempty(legacy.cubetype), return; end
            switch double(legacy.cubetype)
                case 1
                    moduleId = '';
                case 4
                    moduleId = 'smoothing';
                case 5
                    moduleId = 'JuSpace';
                case 7
                    moduleId = 'ROImeans';
                case 9
                    moduleId = 'waveletSpatial';
                otherwise
                    moduleId = 'spatiallegacy';
            end
        end

        function assertIndex(obj, idx)
            if idx < 1 || idx > numel(obj.Steps)
                error('NMPreprocSequence:badIndex','Step index out of range.');
            end
        end



        function opts = parseShowDetailsOptions(obj, varargin)
            opts = struct();
            opts.steps = 1:numel(obj.Steps);
            opts.verbosity = 'normal';
            opts.includeDisabled = true;
            opts.showLegacy = false;
            opts.returnText = false;
            opts.fid = 1;
            opts.title = 'NeuroMiner preprocessing sequence';
            opts.showValidation = true;

            if nargin < 2 || isempty(varargin), return; end
            i = 1;
            while i <= numel(varargin)
                key = varargin{i};
                if isnumeric(key)
                    opts.steps = key(:)';
                    i = i + 1;
                    continue;
                end
                if isstring(key), key = char(key); end
                if ~ischar(key)
                    error('NMPreprocSequence:badShowDetailsOption','Unsupported showDetails option at position %d.', i);
                end
                k = lower(strtrim(key));
                switch k
                    case 'all'
                        opts.steps = 1:numel(obj.Steps);
                        i = i + 1;
                    case {'compact','normal','full'}
                        opts.verbosity = k;
                        i = i + 1;
                    case {'steps','step','indices','idx'}
                        if i == numel(varargin)
                            error('NMPreprocSequence:badShowDetailsOption','Option ''steps'' requires an index vector.');
                        end
                        opts.steps = varargin{i+1};
                        opts.steps = opts.steps(:)';
                        i = i + 2;
                    case {'verbosity','detail','details'}
                        if i == numel(varargin)
                            error('NMPreprocSequence:badShowDetailsOption','Option ''verbosity'' requires a value.');
                        end
                        val = varargin{i+1}; if isstring(val), val = char(val); end
                        val = lower(char(val));
                        if ~any(strcmp(val, {'compact','normal','full'}))
                            error('NMPreprocSequence:badShowDetailsOption','Verbosity must be compact, normal, or full.');
                        end
                        opts.verbosity = val;
                        i = i + 2;
                    case {'includedisabled','showdisabled'}
                        [opts.includeDisabled, i] = obj.readOptionalLogical(varargin, i, true);
                    case {'enabledonly'}
                        opts.includeDisabled = false;
                        i = i + 1;
                    case {'showlegacy','legacy','includelegacy'}
                        [opts.showLegacy, i] = obj.readOptionalLogical(varargin, i, true);
                    case {'returntext','text'}
                        [opts.returnText, i] = obj.readOptionalLogical(varargin, i, true);
                    case {'fid','fileid'}
                        if i == numel(varargin)
                            error('NMPreprocSequence:badShowDetailsOption','Option ''fid'' requires a file identifier.');
                        end
                        opts.fid = varargin{i+1};
                        i = i + 2;
                    case {'title','header'}
                        if i == numel(varargin)
                            error('NMPreprocSequence:badShowDetailsOption','Option ''title'' requires a string.');
                        end
                        opts.title = char(varargin{i+1});
                        i = i + 2;
                    otherwise
                        error('NMPreprocSequence:badShowDetailsOption','Unknown showDetails option: %s.', key);
                end
            end
            if isempty(opts.steps)
                opts.steps = [];
            elseif ~isnumeric(opts.steps) || any(opts.steps < 1) || any(opts.steps > numel(obj.Steps)) || any(opts.steps ~= round(opts.steps))
                error('NMPreprocSequence:badIndex','showDetails step indices are out of range.');
            end
        end

        function [val, nextIdx] = readOptionalLogical(~, args, idx, defaultVal)
            val = defaultVal;
            nextIdx = idx + 1;
            if idx < numel(args)
                cand = args{idx+1};
                if islogical(cand) || (isnumeric(cand) && isscalar(cand))
                    val = logical(cand);
                    nextIdx = idx + 2;
                elseif ischar(cand) || isstring(cand)
                    s = lower(char(cand));
                    if any(strcmp(s, {'true','yes','on','1'}))
                        val = true; nextIdx = idx + 2;
                    elseif any(strcmp(s, {'false','no','off','0'}))
                        val = false; nextIdx = idx + 2;
                    end
                end
            end
        end

        function txt = buildDetailsText(obj, opts)
            lines = {};
            lines{end+1} = obj.makeRule('~', 72); 
            lines{end+1} = sprintf('\t%s', opts.title); 
            lines{end+1} = obj.makeRule('~', 72); 
            lines{end+1} = sprintf('No. of configured preprocessing steps: %d', numel(obj.Steps)); 
        
            if isempty(opts.steps)
                lines{end+1} = 'Selected steps: <none>'; 
                txt = sprintf('%s\n', lines{:});
                return;
            elseif numel(opts.steps) == numel(obj.Steps) && all(opts.steps == 1:numel(obj.Steps))
                lines{end+1} = 'Selected steps: all'; 
            else
                lines{end+1} = sprintf('Selected steps: %s', mat2str(opts.steps)); 
            end
        
            try
                vr = obj.validate(obj.Context);
            catch ME
                vr = struct('ok', false, 'errors', {{ME.message}}, 'warnings', {{}});
            end
        
            if opts.showValidation
                if vr.ok
                    lines{end+1} = 'Sequence validation: passed'; 
                else
                    lines{end+1} = 'Sequence validation: failed'; 
                    for e = 1:numel(vr.errors)
                        lines{end+1} = sprintf('\t! %s', vr.errors{e}); 
                    end
                end
            end
        
            lines{end+1} = obj.makeRule('-', 72); 
        
            for ii = 1:numel(opts.steps)
                i = opts.steps(ii);
                st = obj.Steps{i};
        
                if isfield(st, 'enabled') && ~st.enabled && ~opts.includeDisabled
                    continue;
                end
        
                module = obj.Registry.get(st.moduleId);
                meta = module.info();
                spec = module.configSpec(obj.Context);
        
                enabledStr = 'enabled';
                if isfield(st, 'enabled') && ~st.enabled
                    enabledStr = 'disabled';
                end
        
                lines{end+1} = sprintf('Step %d: %s  [%s | %s]', ...
                    i, module.DisplayName, module.Id, enabledStr); 
                lines{end+1} = sprintf('\tClass        : %s', meta.className); 
        
                if ~strcmp(opts.verbosity, 'compact')
                    if isfield(spec, 'description') && ~isempty(spec.description)
                        lines{end+1} = sprintf('\tPurpose      : %s', ...
                            obj.compactWhitespace(spec.description)); 
                    end
                    lines = obj.appendCapabilityLines(lines, meta);
                    lines = obj.appendSequenceConstraintLines(lines, meta, module.Id);
                end
        
                if strcmp(opts.verbosity, 'compact')
                    lines{end+1} = sprintf('\tConfig       : %s', ...
                        obj.configOneLine(module, st.config)); 
                else
                    lines{end+1} = sprintf('\tConfiguration:'); 
                    lines = obj.appendConfigLines(lines, module, st.config, spec, opts.verbosity);
                end
        
                if opts.showLegacy
                    lines = obj.appendLegacyLines(lines, module, st.config);
                end
        
                if ii < numel(opts.steps)
                    lines{end+1} = obj.makeRule('-', 72); 
                end
            end
        
            lines{end+1} = obj.makeRule('=', 72); 
            txt = sprintf('%s\n', lines{:});
        end

        function lines = appendCapabilityLines(obj, lines, meta) %#ok<INUSL>
            c = meta.capabilities;
            cap = {};
            if isfield(c,'trainFoldEstimated') && c.trainFoldEstimated, cap{end+1} = 'train-fold estimated'; end 
            if isfield(c,'usesLabels') && c.usesLabels, cap{end+1} = 'uses labels'; end 
            if isfield(c,'changesFeatureSpace') && c.changesFeatureSpace, cap{end+1} = 'changes feature space'; else, cap{end+1} = 'preserves feature space'; end 
            if isfield(c,'supportsMissingData') && c.supportsMissingData, cap{end+1} = 'supports missing data'; end 
            if isfield(c,'legacyBackend') && c.legacyBackend, cap{end+1} = 'legacy backend'; end 
            if isempty(cap), cap = {'not specified'}; end
            lines{end+1} = sprintf('\tCapabilities : %s', strjoin(cap, '; ')); 
        end

        function lines = appendSequenceConstraintLines(obj, lines, meta, moduleId) %#ok<INUSL>
            s = meta.sequence;
            seq = {};
            if isfield(s,'allowMultiple') && ~s.allowMultiple, seq{end+1} = 'single occurrence only'; end 
            ruleTxt = obj.RuleSet.describe(moduleId);
            if ~isempty(ruleTxt) && ~strcmp(ruleTxt,'none'), seq{end+1} = ruleTxt; end
            if isempty(seq), seq = {'none'}; end
            lines{end+1} = sprintf('\tSequence     : %s', strjoin(seq, '; ')); 
        end

        function lines = appendConfigLines(obj, lines, module, cfg, spec, verbosity)
            [cfg, report] = module.validateConfig(cfg, obj.Context, false);
            if ~report.ok
                for e = 1:numel(report.errors)
                    lines{end+1} = sprintf('\t\t! %s', report.errors{e}); 
                end
            end
            fields = {};
            if isfield(spec,'fields') && ~isempty(spec.fields)
                fields = spec.fields;
                if isstruct(fields), fields = num2cell(fields); end
            end
            seen = {};
            for fidx = 1:numel(fields)
                f = fields{fidx};
                if ~isfield(f,'name') || isempty(f.name), continue; end
                name = f.name; seen{end+1} = name; 
                if isfield(cfg,name), val = cfg.(name); else, val = []; end
                label = name;
                if isfield(f,'label') && ~isempty(f.label), label = f.label; end
                typ = '';
                if isfield(f,'type') && ~isempty(f.type), typ = f.type; end
                lines{end+1} = sprintf('\t\t- %-28s : %s', obj.withFieldName(label, name), obj.valueToString(val)); 
                if strcmp(verbosity,'full')
                    if ~isempty(typ)
                        lines{end+1} = sprintf('\t\t  %-28s   %s', 'type', typ); 
                    end
                    if isfield(f,'help') && ~isempty(f.help)
                        lines{end+1} = sprintf('\t\t  %-28s   %s', 'help', obj.compactWhitespace(f.help)); 
                    end
                    if isfield(f,'default')
                        lines{end+1} = sprintf('\t\t  %-28s   %s', 'default', obj.valueToString(f.default)); 
                    end
                end
            end
            cfgNames = fieldnames(cfg);
            extra = setdiff(cfgNames, seen);
            for e = 1:numel(extra)
                lines{end+1} = sprintf('\t\t- %-28s : %s', ['extra.' extra{e}], obj.valueToString(cfg.(extra{e}))); 
            end
        end

        function s = configOneLine(obj, module, cfg)
            spec = module.configSpec(obj.Context);
            fields = {};
            if isfield(spec,'fields') && ~isempty(spec.fields)
                fields = spec.fields;
                if isstruct(fields), fields = num2cell(fields); end
            end
            parts = {};
            for i = 1:numel(fields)
                f = fields{i};
                if ~isfield(f,'name') || ~isfield(cfg,f.name), continue; end
                parts{end+1} = sprintf('%s=%s', f.name, obj.valueToString(cfg.(f.name))); 
                if numel(parts) >= 5, break; end
            end
            if isempty(parts), s = '<default/empty>'; else, s = strjoin(parts, ', '); end
        end

        function lines = appendLegacyLines(obj, lines, module, cfg)
            try
                legacy = module.toLegacy(cfg, obj.Context);
                fn = fieldnames(legacy);
                lines{end+1} = sprintf('\tLegacy export:'); 
                for i = 1:numel(fn)
                    lines{end+1} = sprintf('\t\t- %-20s : %s', fn{i}, obj.valueToString(legacy.(fn{i}))); 
                end
            catch ME
                lines{end+1} = sprintf('\tLegacy export: failed (%s)', ME.message); 
            end
        end

        function s = valueToString(obj, val) %#ok<INUSL>
            s = NMConfigTools.formatValue(val, 'maxLen', 120, 'smallVectorLimit', 12);
        end

        function s = withFieldName(~, label, name)
            if strcmp(label, name)
                s = name;
            else
                s = sprintf('%s [%s]', label, name);
            end
        end

        function s = compactWhitespace(~, s)
            if isempty(s), s = ''; return; end
            s = regexprep(char(s), '\s+', ' ');
            s = strtrim(s);
        end

        function r = makeRule(~, ch, n)
            r = repmat(ch, 1, n);
        end

        function s = sizeString(~, sz)
            s = sprintf('%dx', sz);
            if ~isempty(s), s = s(1:end-1); end
        end

        function applyAutoChild(obj, idx)
            st = obj.Steps{idx};
            children = obj.RuleSet.autoChildSteps(st.moduleId, obj.Registry, st);
            for c = 1:numel(children)
                childId = children{c}.moduleId;
                childCfg = obj.inheritChildConfig(st, childId, children{c}.config);
                if idx+c-1 == numel(obj.Steps) || ~strcmp(obj.Registry.canonicalId(obj.Steps{idx+c}.moduleId), obj.Registry.canonicalId(childId))
                    obj.Steps = [obj.Steps(1:idx+c-1), {obj.makeStep(childId, childCfg)}, obj.Steps(idx+c:end)];
                end
            end
        end

        function childCfg = inheritChildConfig(obj, parentStep, childId, childCfg) %#ok<INUSL>
            if nargin < 4 || isempty(childCfg), childCfg = struct(); end
            if strcmp(obj.Registry.canonicalId(childId),'extdim') && isfield(parentStep,'config')
                pcfg = parentStep.config;
                pid = obj.Registry.canonicalId(parentStep.moduleId);
                if strcmp(pid,'reducedim')
                    if isfield(pcfg,'method'), childCfg.redMode = pcfg.method; end
                    if isfield(pcfg,'percMode'), childCfg.percMode = pcfg.percMode; end
                    if isfield(pcfg,'fitDim'), childCfg.dims = pcfg.fitDim; childCfg.scheduleMode = 'user'; end
                elseif strcmp(pid,'remvarcomp')
                    if isfield(pcfg,'reductionMethod'), childCfg.redMode = pcfg.reductionMethod; end
                    if isfield(pcfg,'dimensionMode')
                        if strcmp(pcfg.dimensionMode,'percentage'), childCfg.percMode = 'percentage'; else, childCfg.percMode = 'absolute'; end
                    end
                    if isfield(pcfg,'fitDim'), childCfg.dims = pcfg.fitDim; childCfg.scheduleMode = 'user'; end
                end
            end
        end
    end
end

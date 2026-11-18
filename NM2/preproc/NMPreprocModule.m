classdef NMPreprocModule
% NMPreprocModule
% -------------------------------------------------------------------------
% Base class for registry-driven NeuroMiner preprocessing modules.
%
% Design rule for the first vertical slice:
%   - canonical config structs are the public API;
%   - toLegacy/fromLegacy preserve current ACTPARAM compatibility;
%   - legacy nk_input configurators remain available through cli_configure;
%   - legacy nk_Perf*Obj functions remain the numerical backend.
% -------------------------------------------------------------------------

    properties (SetAccess = protected)
        Id char = ''
        DisplayName char = ''
        LegacyField char = ''
        Category char = 'preprocessing'
        Aliases cell = {}
        Capabilities struct = struct()
        Sequence struct = struct()
    end

    methods
        function obj = NMPreprocModule(id, legacyField, displayName)
            % NMPreprocModule  Construct the common preprocessing-module adapter state.
            %   Initializes canonical id, display name, legacy-field binding, capability flags, and
            %   sequencing metadata consumed by the registry, ruleset, sequence builder, UI schemas,
            %   and legacy export path.

            if nargin >= 1 && ~isempty(id), obj.Id = id; end
            if nargin >= 2 && ~isempty(legacyField), obj.LegacyField = legacyField; end
            if nargin >= 3 && ~isempty(displayName), obj.DisplayName = displayName; else, obj.DisplayName = obj.Id; end
            obj.Capabilities = struct( ...
                'requiresLabels', false, ...
                'usesLabels', false, ...
                'changesFeatureSpace', false, ...
                'supportsMissingData', true, ...
                'supportsHyperparameters', false, ...
                'trainFoldEstimated', true, ...
                'legacyBackend', true, ...
                'executionStages', {{'cv'}}, ...
                'imagingOnly', false, ...
                'requiresImageSpace', false, ...
                'isImageSpaceTerminal', false, ...
                'requiresSpatialFeatureExtractionAllowed', false, ...
                'spatialFeatureExtractionFlagEffect', 'preserve', ...
                'invalidatesImageSpace', false, ...
                'restoresImageSpace', false, ...
                'isSpatialFeatureExtractor', false, ...
                'isDimensionalityReductionLike', false, ...
                'uniqueAcrossStages', false, ...
                'legacySubjectTarget', '', ...
                'legacyCVTarget', 'ACTPARAM');
            % Intrinsic per-module cardinality only. Cross-step producer/consumer
            % and ordering grammar is owned by NMPreprocRuleSet.
            obj.Sequence = struct('allowMultiple', true);
        end

        function meta = info(obj)
            % info  Return machine-readable module metadata for registries and documentation.
            %   The struct mirrors the public adapter identity, aliases, capabilities, sequencing
            %   intrinsic cardinality, and class name so UI/RAG/API layers can inspect a module
            %   without touching its internals. Cross-step grammar is exported by NMPreprocRuleSet.

            meta = struct();
            meta.id = obj.Id;
            meta.displayName = obj.DisplayName;
            meta.legacyField = obj.LegacyField;
            meta.category = obj.Category;
            meta.aliases = obj.Aliases;
            meta.capabilities = obj.Capabilities;
            meta.sequence = obj.Sequence;
            meta.className = class(obj);
        end

        function txt = help(obj)
            % help  Return a compact human-readable module description.
            %   This summary is derived from info() and is reused by generic configSpec output, CLI
            %   help, and documentation extraction when subclasses do not provide richer prose.

            meta = obj.info();
            txt = sprintf('%s preprocessing step.', meta.displayName);
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the minimal canonical configuration schema for a module.
            %   Subclasses extend this base schema with fields and descriptions; defaultConfig,
            %   validateConfig, UI rendering, CLI helpers, and RAG extraction all depend on this
            %   schema contract.

            spec = struct();
            spec.id = obj.Id;
            spec.kind = 'preproc-module';
            spec.title = obj.DisplayName;
            spec.description = obj.help();
            spec.legacyField = obj.LegacyField;
            spec.capabilities = obj.Capabilities;
            spec.sequence = obj.Sequence;
            spec.fields = {};
        end

        function cfg = defaultConfig(obj, ctx)
            % defaultConfig  Create a canonical config struct from the module schema.
            %   Uses NMConfigTools.defaultsFromSpec on configSpec(ctx), making the schema the single
            %   source of default values for scripted API calls, UI initialization, and legacy
            %   import repair.

            if nargin < 2, ctx = struct(); end
            cfg = NMConfigTools.defaultsFromSpec(obj.configSpec(ctx));
        end

        function cfg = parseConfig(obj, varargin)
            % parseConfig  Parse and validate user-supplied module configuration arguments.
            %   Merges name/value pairs or structs with schema defaults and raises a module-specific
            %   error if strict validation fails; this is the main power-user entry point for
            %   building step configs programmatically.

            ctx = struct();
            if ~isempty(varargin) && isstruct(varargin{1}) && isfield(varargin{1},'nm2PreprocContext')
                ctx = varargin{1}.nm2PreprocContext;
                varargin = varargin(2:end);
            end
            defaults = obj.defaultConfig(ctx);
            cfg = NMConfigTools.nameValueToStruct(defaults, varargin{:});
            [cfg, report] = obj.validateConfig(cfg, ctx, true);
            if ~report.ok
                error('NMPreprocModule:invalidConfig', '%s config invalid:\n%s', obj.Id, strjoin(report.errors, newline));
            end
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict)
            % validateConfig  Validate a canonical module config against the module schema.
            %   Returns normalized cfg plus a report used by scripts, UI state application, and
            %   legacy conversion; strict=false supports permissive import of older ACTPARAM
            %   payloads.

            if nargin < 3, ctx = struct(); end
            if nargin < 4 || isempty(strict), strict = true; end
            [cfg, report] = NMConfigTools.validateConfig(obj.configSpec(ctx), cfg, ctx, strict);
        end

        function ui = ui_configure(obj, cfg, ctx)
            % ui_configure  Package a module schema, state, and validation report for UI rendering.
            %   This non-mutating adapter endpoint lets the browser/UI layer inspect editable fields
            %   without invoking legacy nk_input configurators or changing NM.TrainParam.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            ui = struct('spec', obj.configSpec(ctx), 'state', cfg, 'validation', report);
        end


        function h = cli_configureHelp(obj, varargin)
            % cli_configureHelp  Return structured help for the generic CLI/API configuration call.
            %   The help payload documents expected config/context arguments and is used by
            %   power-user guidance and future assistant/RAG layers when a subclass does not
            %   override CLI help.

            ctx = NMPreprocContext.empty();
            algo = '';
            switch numel(varargin)
                case 0
                case 1
                    ctx = varargin{1};
                case 2
                    assert(strcmp(varargin{1},'algo'), ...
                        'Use configureHelp(''algo'',method) for nested help.');
                    algo = varargin{2};
                case 3
                    ctx = varargin{1};
                    assert(strcmp(varargin{2},'algo'), ...
                        'Use configureHelp(ctx,''algo'',method) for context-specific nested help.');
                    algo = varargin{3};
                otherwise
                    error('NMPreprocModule:invalidHelpArguments', ...
                        'Use configureHelp(), configureHelp(ctx), or configureHelp(''algo'',method).');
            end
            info = obj.info();
            opts = struct();
            opts.config = 'Optional module config struct. Name/value parsing is module-specific; pass an existing config to modify/revalidate it.';
            opts.context = 'Optional NMPreprocContext or compatible struct. Set invokeLegacyCLI=false/defaultsOnly=true for non-interactive export.';
            h = NMConfigureAPITools.helpStruct([class(obj) '.cli_configure'], ...
                '[cfg, legacyParam, act, aux] = module.cli_configure(existingConfig, ctx)', opts, ...
                {sprintf(['registry = NMModuleRegistry.default(); module = registry.get(''%s''); ', ...
                'ctx = NMPreprocContext.empty(); ctx.invokeLegacyCLI = false; ', ...
                'cfg = module.defaultConfig(ctx); ', ...
                '[cfg, legacyParam, act, aux] = module.cli_configure(cfg, ctx);'], obj.Id)});
            h.moduleId = obj.Id;
            h.title = info.displayName;
            h.description = obj.help();
            h.configSpec = obj.configSpec(ctx);
            if ~isempty(algo)
                h.configSpec = NMConfigureAPITools.subconfigSpec(h.configSpec,algo);
                h.title = h.configSpec.title;
                h.description = h.configSpec.description;
            end
            if nargout == 0
                fprintf('%s\n',NMConfigureAPITools.formatConfigSpec(h.configSpec));
            end
        end

        function h = configureHelp(obj, varargin)
            % configureHelp  Compatibility alias for module configuration help.
            %   Delegates to cli_configureHelp so older configure-style callers and newer CLI/API
            %   documentation paths expose identical guidance.

            if nargout == 0
                obj.cli_configureHelp(varargin{:});
            else
                h = obj.cli_configureHelp(varargin{:});
            end
        end

        function [cfg, legacyParam, act, aux] = cli_configure(obj, cfg, ctx) %#ok<INUSD>
            % cli_configure  Default non-interactive module configuration path.
            %   Returns canonical cfg, its legacy representation, and inactive act/aux flags;
            %   subclasses override this when a legacy nk_input configurator or module-specific
            %   auxiliary payload must be supported.

            % Default no-op. Subclasses delegate to legacy nk_input-based
            % configurators. The return shape is canonical config + legacy.
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacyParam = obj.toLegacy(cfg, ctx);
            act = 0; aux = [];
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert canonical module config to a generic legacy ACTPARAM branch.
            %   Subclasses usually override this to emit exact legacy fields; the base
            %   implementation records the command id and, when available, stores cfg under the
            %   module LegacyField.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            legacy = struct();
            legacy.cmd = obj.Id;
            if ~isempty(obj.LegacyField)
                legacy.(obj.LegacyField) = cfg;
            end
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import a generic legacy ACTPARAM branch into canonical config form.
            %   Reads the module LegacyField when present, falls back to defaults, and performs
            %   permissive validation so legacy projects can be inspected even when older settings
            %   are incomplete.

            if nargin < 2 || isempty(legacy), legacy = struct(); end
            if ~isempty(obj.LegacyField) && isfield(legacy,obj.LegacyField)
                cfg = legacy.(obj.LegacyField);
            else
                cfg = obj.defaultConfig();
            end
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok
                warning('NMPreprocModule:legacyConfigInvalid', 'Legacy config for %s did not validate cleanly: %s', obj.Id, strjoin(report.errors,'; '));
            end
        end

        function [prepared, runtime] = prepare4CV(obj, cfg, ctx) %#ok<INUSD>
            % prepare4CV  Prepare fold-estimated runtime settings from a canonical module config.
            %   The base implementation returns the legacy payload and an empty runtime struct;
            %   subclasses may override this when CV preparation needs cached fit-time state.

            prepared = obj.toLegacy(cfg, ctx);
            runtime = struct();
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Execute one modular preprocessing step on a feature matrix.
            %   The base class deliberately errors because numerical fit/transform behavior is
            %   module-specific and usually delegates to a legacy nk_Perf*Obj backend.

            error('NMPreprocModule:notImplemented', 'execute() is not implemented for module %s.', obj.Id);
        end

        function [SrcParam, InputParam, TrParami, actparam] = executeInCV(obj, SrcParam, InputParam, TrParam, TrParami, actparam) %#ok<INUSD>
            % executeInCV  Execute a module inside the legacy CV preprocessing scaffold.
            %   The base class deliberately errors; modules that support full legacy-core execution
            %   must define how SrcParam/InputParam/TrParam/actparam are transformed.

            error('NMPreprocModule:notImplemented', 'executeInCV() is not implemented for module %s.', obj.Id);
        end
    end

    methods (Access = protected)
        function parentstr = getParentString(~, ctx)
            parentstr = '';
            if nargin >= 2 && isstruct(ctx) && isfield(ctx,'parentstr'), parentstr = ctx.parentstr; end
        end

        function defaultsfl = getDefaultsFlag(~, ctx)
            defaultsfl = false;
            if nargin >= 2 && isstruct(ctx)
                if isfield(ctx,'defaultsfl'), defaultsfl = ctx.defaultsfl; end
                if isfield(ctx,'defaultsOnly'), defaultsfl = ctx.defaultsOnly; end
            end
        end

        function tf = functionExists(~, fname)
            tf = exist(fname,'file') == 2 || exist(fname,'builtin') == 5;
        end

        function tf = shouldCallLegacyCLI(obj, ctx)
            % defaultsOnly is used by non-interactive smoke tests and API
            % round trips. Some legacy configurators ignore the defaults
            % flag and still invoke nk_input; keep them out unless the
            % caller explicitly requests interactive legacy configuration.
            tf = true;
            if nargin >= 2 && isstruct(ctx)
                if isfield(ctx,'invokeLegacyCLI')
                    tf = logical(ctx.invokeLegacyCLI);
                    return;
                end
            end
            if obj.getDefaultsFlag(ctx)
                tf = false;
            end
        end

        function code = boolToLegacyYesNo(~, tf)
            if tf, code = 1; else, code = 2; end
        end

        function tf = legacyYesNoToBool(~, code, defaultVal)
            if nargin < 3, defaultVal = true; end
            if isempty(code), tf = defaultVal; return; end
            tf = code == 1 || isequal(code,true);
        end

        function requireNkAddParam(obj)
            if ~obj.functionExists('nk_AddParam')
                error('NMPreprocModule:missingNkAddParam', ...
                    ['nk_AddParam is required to export %s because PX defines ', ...
                     'the NeuroMiner preprocessing hyperparameter shelf. Add ', ...
                     'the NeuroMiner config helper directory to the MATLAB path.'], obj.Id);
            end
        end

        function PX = pxReset(obj, PX)
            if nargin < 2, PX = []; end %#ok<INUSD>
            obj.requireNkAddParam();
            PX = nk_AddParam([], [], [], [], 'reset');
        end

        function PX = pxAdd(obj, PX, vals, desc, typ, mode)
            obj.requireNkAddParam();
            if nargin < 6, mode = ''; end
            if isempty(mode)
                PX = nk_AddParam(vals, desc, typ, PX);
            else
                PX = nk_AddParam(vals, desc, typ, PX, mode);
            end
        end

        function tf = pxHasParams(~, PX)
            tf = false;
            if isempty(PX) || ~isstruct(PX) || ~isfield(PX,'Px') || isempty(PX.Px), return; end
            try
                params = {PX.Px.Params};
                tf = any(cellfun(@(x) ~isempty(x), params));
            catch
                try
                    tf = ~isempty(PX.Px.Params);
                catch
                    tf = false;
                end
            end
        end
    end
end

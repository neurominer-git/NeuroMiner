classdef NMLegacySpatialModule < NMPreprocModule
% NMLegacySpatialModule
% -------------------------------------------------------------------------
% Raw-preservation adapter for legacy PREPROC.SPATIAL entries whose canonical
% modular port is not implemented yet, e.g. absolute-difference filtering or
% cube-variance filtering. It is not addable from the UI.
% -------------------------------------------------------------------------

    methods
        function obj = NMLegacySpatialModule()
            % NMLegacySpatialModule  Construct the Legacy spatial operation preprocessing adapter.
            %   Registers module id 'spatiallegacy' with legacy branch 'SPATIAL' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('spatiallegacy','SPATIAL','Imported spatial operation');
            obj.Category = 'subject-preprocessing';
            obj.Aliases = {'spatial_legacy','spatialfilter','spatial'};
            obj.Capabilities.executionStages = {'subject'};
            obj.Capabilities.imagingOnly = true;
            obj.Capabilities.requiresImageSpace = true;
            obj.Capabilities.trainFoldEstimated = false;
            obj.Capabilities.legacySubjectTarget = 'PREPROC.SPATIAL';
            obj.Capabilities.legacyCVTarget = '';
            obj.Sequence.allowMultiple = true;
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Legacy spatial operation.
            %   Defines editable fields for the module that adapts unported subject-level spatial
            %   legacy operations to the modular preprocessing sequence. The schema feeds
            %   defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = 'Imported spatial preprocessing operation preserved for compatibility with existing analyses.';
            spec.unported = true;
            spec.fields = {struct('name','rawLegacy','type','struct','default',struct(),'label','Raw legacy SPATIAL structure','uiHidden',true, ...
                    'help','Original imported SPATIAL command payload retained without reinterpretation for legacy round trips.')};
        end

        function cfg = defaultConfig(obj, ctx) %#ok<INUSD>
            % defaultConfig  Return default canonical config for Legacy spatial operation.
            %   Creates the raw-preservation or schema-derived defaults that scripts and legacy
            %   import use before validation and legacy branch 'SPATIAL' export.

            cfg = struct('rawLegacy',struct('cmd',obj.Id,'cubetype',uint8(1)));
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict) %#ok<INUSD>
            % validateConfig  Validate and normalize Legacy spatial operation configuration.
            %
            % Checks canonical config fields and nested method settings before scripted use,
            % UI-state application, and legacy conversion to legacy branch 'SPATIAL'.
            %
            % cfg.rawLegacy: preserves the original legacy configuration fragment for compatibility/audit use.

            if nargin < 2 || isempty(cfg) || ~isstruct(cfg), cfg = obj.defaultConfig(); end
            if ~isfield(cfg,'rawLegacy') || ~isstruct(cfg.rawLegacy), cfg.rawLegacy = struct('cmd',obj.Id); end
            report = struct('ok',true,'errors',{{}},'warnings',{{}});
        end

        function legacy = toLegacySubject(obj, cfg, ctx) %#ok<INUSD>
            % toLegacySubject  Return the raw or default legacy SPATIAL branch for an unported spatial operation.
            %
            % Preserves imported spatial settings and keeps subject-level legacy operations
            % round-trippable through the modular sequence.
            %
            % cfg.rawLegacy: preserves the original legacy configuration fragment for compatibility/audit use.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if isfield(cfg,'rawLegacy') && isstruct(cfg.rawLegacy), legacy = cfg.rawLegacy; else, legacy = struct(); end
            if ~isfield(legacy,'cmd') || isempty(legacy.cmd), legacy.cmd = obj.Id; end
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Legacy spatial operation config to legacy preprocessing fields.
            %   Validates/normalizes canonical cfg and materializes legacy branch 'SPATIAL' for the
            %   CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.

            legacy = obj.toLegacySubject(cfg, ctx);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Legacy spatial operation for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok
                error('NMLegacySpatialModule:invalidConfig', '%s', strjoin(report.errors, newline));
            end
            legacy = obj.toLegacySubject(cfg, ctx);
            act = 0;
            aux = [];
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Fit or apply the Legacy spatial operation runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfSpatialChain,
            %   nm_preproc_spatial_param_from_context.

            % Programmatic single-step subject-spatial execution. Complex
            % multi-step subject-spatial chains should prefer
            % nm_preproc_scaffold_apply_subject_spatial, which delegates the
            % whole PREPROC.SPATIAL array to nk_PerfSpatialChain.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.
            if nargin < 5 || isempty(mode), mode = 'fit'; end %#ok<NASGU>
            if nargin < 6 || isempty(ctx), ctx = struct(); end
            cfg = struct();
            if isstruct(ctx) && isfield(ctx,'config') && isstruct(ctx.config), cfg = ctx.config; end
            if isempty(fieldnames(cfg)), cfg = obj.defaultConfig(ctx); end
            legacy = obj.toLegacySubject(cfg, ctx);
            PREPROC = struct('SPATIAL', legacy);
            Param = nm_preproc_spatial_param_from_context(Y, ctx);
            if exist('nk_PerfSpatialChain','file') ~= 2
                error([class(obj) ':missingBackend'], 'nk_PerfSpatialChain.m is required for programmatic spatial execution.');
            end
            [Yout, branchTable] = nk_PerfSpatialChain(Y, PREPROC, Param);
            trained = struct('moduleId',obj.Id, 'config',cfg, 'legacySPATIAL',legacy, ...
                'branchTable',branchTable, 'mode','deterministic_subject_spatial');
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Legacy spatial operation settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            if nargin < 2 || isempty(legacy), legacy = struct('cmd',obj.Id); end
            if ~isfield(legacy,'cmd') || isempty(legacy.cmd), legacy.cmd = obj.Id; end
            cfg = struct('rawLegacy',legacy);
        end
    end
end

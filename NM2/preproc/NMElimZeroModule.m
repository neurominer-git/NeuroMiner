classdef NMElimZeroModule < NMPreprocModule
% Canonical adapter for NeuroMiner feature pruning / elimzero preprocessing.

    methods
        function obj = NMElimZeroModule()
            % NMElimZeroModule  Construct the Prune invalid / zero-variance features preprocessing adapter.
            %   Registers module id 'elimzero' with legacy branch 'PRUNE' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('elimzero','PRUNE','Prune invalid / zero-variance features');
            obj.Capabilities.changesFeatureSpace = true;
            obj.Capabilities.supportsHyperparameters = true;
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Prune invalid / zero-variance features.
            %   Defines editable fields for the module that removes invalid, non-finite, all-zero,
            %   or near-constant predictor columns according to PRUNE settings. The schema feeds
            %   defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = 'Remove zero-variance, NaN, Inf, or single-value dominated features.';
            spec.fields = { ...
                struct('name','pruneZeroVariance','type','boolean','default',true,'label','Prune zero-variance features', ...
                    'help','Remove predictor features with zero variance.'), ...
                struct('name','pruneNaN','type','boolean','default',true,'label','Prune features with NaNs', ...
                    'help','Remove predictor features according to the inherited PRUNE.nan setting for NaN values.'), ...
                struct('name','pruneInf','type','boolean','default',true,'label','Prune features with Infs', ...
                    'help','Remove predictor features according to the inherited PRUNE.inf setting for infinite values.'), ...
                struct('name','singleValuePercent','type','numeric_vector','default',[],'allowEmpty',true,'label','Single-value cutoff percent', ...
                    'help','Optional percentage cutoff for features dominated by a single value; empty leaves this criterion inactive.') };
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert Prune invalid / zero-variance features config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'PRUNE' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.pruneInf: stores the normalized prune inf value in the module configuration.
            % cfg.pruneNaN: stores the normalized prune nan value in the module configuration.
            % cfg.pruneZeroVariance: stores the normalized prune zero variance value in the module configuration.
            % cfg.singleValuePercent: stores the normalized single value percent value in the module configuration.

            cfg = obj.parseConfig(cfg);
            P = struct();
            P.zero = obj.boolToLegacyYesNo(cfg.pruneZeroVariance);
            P.nan  = obj.boolToLegacyYesNo(cfg.pruneNaN);
            P.inf  = obj.boolToLegacyYesNo(cfg.pruneInf);
            P.perc = cfg.singleValuePercent;
            legacy = struct('cmd',obj.Id,'PRUNE',P,'PX',obj.buildPX(P));
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Prune invalid / zero-variance features settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isfield(legacy,'PRUNE'), P = legacy.PRUNE; else, P = legacy; end
            if isfield(P,'zero'), cfg.pruneZeroVariance = obj.legacyYesNoToBool(P.zero,true); end
            if isfield(P,'nan'),  cfg.pruneNaN = obj.legacyYesNoToBool(P.nan,true); end
            if isfield(P,'inf'),  cfg.pruneInf = obj.legacyYesNoToBool(P.inf,true); end
            if isfield(P,'perc'), cfg.singleValuePercent = P.perc; end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Prune invalid / zero-variance features for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_Prune_config')
                [P, PX, act] = nk_Prune_config(legacy.PRUNE, legacy.PX, obj.getParentString(ctx), obj.getDefaultsFlag(ctx));
                legacy.PRUNE = P; legacy.PX = PX; legacy.cmd = obj.Id;
                cfg = obj.fromLegacy(legacy, ctx);
                aux = struct('PX',PX);
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Fit or apply the Prune invalid / zero-variance features runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfElimZeroObj.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end %#ok<NASGU>
            if nargin < 3 || isempty(trained)
                cfg = obj.defaultConfig();
                if isfield(ctx,'config'), cfg = ctx.config; end
                legacy = obj.toLegacy(cfg, ctx);
                [Yout, trained] = nk_PerfElimZeroObj(Y, legacy.PRUNE);
            else
                Yout = nk_PerfElimZeroObj(Y, trained);
            end
        end
    end

    methods (Access = private)
        function PX = buildPX(obj, P)
            % nk_Prune_config registers only the single-value percentage
            % threshold as a preprocessing hyperparameter.
            if isfield(P,'perc') && ~isempty(P.perc)
                PX = obj.pxAdd([], P.perc, 'PrunePerc', 1);
            else
                PX = obj.pxReset([]);
            end
        end

        function cfg = validateOrError(obj, cfg)
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMElimZeroModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end
    end
end

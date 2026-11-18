classdef NMUnitNormalizeModule < NMPreprocModule
% Canonical adapter for NeuroMiner unit-normalization preprocessing.

    methods
        function obj = NMUnitNormalizeModule()
            % NMUnitNormalizeModule  Construct the Unit normalization preprocessing adapter.
            %   Registers module id 'unitnormalize' with legacy branch 'UNITNORM' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('unitnormalize','UNITNORM','Unit normalization');
            obj.Aliases = {'unitnorm'};
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Unit normalization.
            %   Defines editable fields for the module that normalizes samples or features to unit
            %   norm through the legacy backend. The schema feeds defaultConfig, validateConfig,
            %   browser rendering, CLI/API help, and RAG documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = 'Normalize each feature to unit vector length.';
            spec.fields = { ...
                struct('name','norm','type','enum','default','l1','label','Norm','values',{{'l1','l2'}}, ...
                    'help','Choose the L1 or L2 vector norm for feature normalization.'), ...
                struct('name','zeroOutNonFinite','type','boolean','default',true,'label','Zero-out non-finite values', ...
                    'help','Replace non-finite normalized values with zero using the inherited zerooutflag option.') };
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert Unit normalization config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'UNITNORM' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.norm: stores the normalized norm value in the module configuration.
            % cfg.zeroOutNonFinite: stores the normalized zero out non finite value in the module configuration.

            cfg = obj.parseConfig(cfg);
            L = struct();
            L.UNITNORM = 1;
            if strcmpi(cfg.norm,'l2'), L.METHOD = 2; else, L.METHOD = 1; end
            L.zerooutflag = obj.boolToLegacyYesNo(cfg.zeroOutNonFinite);
            legacy = L; legacy.cmd = obj.Id;
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Unit normalization settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig(); L = legacy;
            if isfield(L,'METHOD') && L.METHOD == 2, cfg.norm = 'l2'; else, cfg.norm = 'l1'; end
            if isfield(L,'zerooutflag'), cfg.zeroOutNonFinite = obj.legacyYesNoToBool(L.zerooutflag,true); end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Unit normalization for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_Unitnorm_config')
                [legacy, act] = nk_Unitnorm_config(legacy, obj.getParentString(ctx), obj.getDefaultsFlag(ctx));
                legacy.cmd = obj.Id;
                cfg = obj.fromLegacy(legacy, ctx);
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Fit or apply the Unit normalization runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfUnitNormObj.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end %#ok<NASGU>
            if nargin < 3 || isempty(trained)
                cfg = obj.defaultConfig();
                if isfield(ctx,'config'), cfg = ctx.config; end
                legacy = obj.toLegacy(cfg, ctx);
                IN = struct('normMethod', legacy.METHOD, 'zerooutflag', legacy.zerooutflag);
                [Yout, trained] = nk_PerfUnitNormObj(Y, IN);
            else
                Yout = nk_PerfUnitNormObj(Y, trained);
            end
        end
    end

    methods (Access = private)
        function cfg = validateOrError(obj, cfg)
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMUnitNormalizeModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end
    end
end

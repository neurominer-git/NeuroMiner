classdef NMScaleModule < NMPreprocModule
% Canonical adapter for NeuroMiner scale preprocessing.

    methods
        function obj = NMScaleModule()
            % NMScaleModule  Construct the Scaling preprocessing adapter.
            %   Registers module id 'scale' with legacy branch 'SCALE' and sets capability/sequence
            %   flags used by NMModuleRegistry, NMPreprocRuleSet, NMPreprocSequence, and UI/API
            %   schema generation.

            obj@NMPreprocModule('scale','SCALE','Scaling');
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Scaling.
            %   Defines editable fields for the module that scales predictor values and handles
            %   non-finite values before modelling. The schema feeds defaultConfig, validateConfig,
            %   browser rendering, CLI/API help, and RAG documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = 'Scale features using parameters estimated in the training fold. Symmetric scaling preserves the zero decision boundary.';
            % The schema describes all inherited values so an existing min-max
            % configuration remains visible and can be explicitly corrected.
            % The stacking policy is enforced by validateConfig below.
            ranges = { ...
                struct('value','zero_one','label','Min-max scaling [0, 1]'), ...
                struct('value','minus_one_one','label','Min-max scaling [-1, 1]'), ...
                struct('value','symmetric_one_one','label','Symmetric scaling [-1, 1] (zero-preserving)')};
            defaultRange = 'zero_one';
            zeroOutDefault = true;
            if isequal(ctx,struct()), ctx = NMPreprocContext.empty(); end
            if strcmp(ctx.source,'stacking')
                defaultRange = 'symmetric_one_one';
                zeroOutDefault = false;
            end
            spec.fields = { ...
                struct('name','acrossMatrix','type','boolean','default',false,'label','Scale across whole matrix','help','Apply one scaling transformation across the complete feature matrix rather than feature-wise.'), ...
                struct('name','range','type','enum','default',defaultRange,'label','Scaling range','values',{ranges}, ...
                    'help','Symmetric [-1,1] scaling divides by the training maximum absolute value, leaving the decision boundary at zero. Stacking uses this method exclusively.'), ...
                struct('name','zeroOutNonFinite','type','boolean','default',zeroOutDefault,'label','Zero-out non-finite values', ...
                    'help','Disable this when subsequent imputation must process entirely missing prediction sources.') };
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict)
            % Stacking cannot shift the zero decision boundary. Keep every
            % schema enum visible so a stored min-max choice can be replaced.
            if isequal(ctx,struct()), ctx = NMPreprocContext.empty(); end
            [cfg, report] = validateConfig@NMPreprocModule(obj, cfg, ctx, strict);
            if strcmp(ctx.source,'stacking') && ~strcmp(cfg.range,'symmetric_one_one')
                report.errors{end+1} = ...
                    'Stacking requires symmetric scaling that preserves zero. Select "Symmetric scaling [-1, 1] (zero-preserving)".';
                report.ok = false;
            end
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert Scaling config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'SCALE' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.acrossMatrix: stores the normalized across matrix value in the module configuration.
            % cfg.range: stores the normalized range value in the module configuration.
            % cfg.zeroOutNonFinite: stores the normalized zero out non finite value in the module configuration.

            [cfg, report] = obj.validateConfig(cfg, ctx, true);
            if ~report.ok
                error('NMScaleModule:invalidConfig','%s',strjoin(report.errors,newline));
            end
            S = struct();
            S.AcMatFl = logical(cfg.acrossMatrix);
            switch cfg.range
                case 'zero_one'
                    S.ZeroOne = 1;
                case 'minus_one_one'
                    S.ZeroOne = 2;
                case 'symmetric_one_one'
                    S.ZeroOne = 3;
            end
            S.zerooutflag = obj.boolToLegacyYesNo(cfg.zeroOutNonFinite);
            legacy = struct('cmd',obj.Id,'SCALE',S);
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Scaling settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isfield(legacy,'SCALE'), S = legacy.SCALE; else, S = legacy; end
            if isfield(S,'AcMatFl'), cfg.acrossMatrix = logical(S.AcMatFl); end
            switch S.ZeroOne
                case 2
                    cfg.range = 'minus_one_one';
                case 3
                    cfg.range = 'symmetric_one_one';
            end
            if isfield(S,'zerooutflag'), cfg.zeroOutNonFinite = obj.legacyYesNoToBool(S.zerooutflag,true); end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Scaling for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx);
            aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_Scale_config')
                [S, act] = nk_Scale_config(legacy.SCALE, obj.getParentString(ctx), obj.getDefaultsFlag(ctx));
                legacy.SCALE = S; legacy.cmd = obj.Id;
                cfg = obj.fromLegacy(legacy, ctx);
                [~, report] = obj.validateConfig(cfg, ctx, true);
                if ~report.ok
                    error('NMScaleModule:stackingRange', ...
                        'Stacking prediction scores require symmetric scaling that preserves the zero decision boundary.');
                end
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Fit or apply the Scaling runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfScaleObj.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end %#ok<NASGU>
            if nargin < 3 || isempty(trained)
                cfg = obj.defaultConfig();
                if isfield(ctx,'config'), cfg = ctx.config; end
                legacy = obj.toLegacy(cfg, ctx);
                [Yout, trained] = nk_PerfScaleObj(Y, legacy.SCALE);
            else
                Yout = nk_PerfScaleObj(Y, trained);
            end
        end
    end

    methods (Access = private)
        function cfg = validateOrError(obj, cfg)
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMScaleModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end
    end
end

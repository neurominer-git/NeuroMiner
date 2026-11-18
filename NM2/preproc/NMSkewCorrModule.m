classdef NMSkewCorrModule < NMPreprocModule
% Canonical adapter for NeuroMiner skewness correction preprocessing.

    methods
        function obj = NMSkewCorrModule()
            % NMSkewCorrModule  Construct the Skewness correction preprocessing adapter.
            %   Registers module id 'skewcorr' with legacy branch 'SKEWCORR' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('skewcorr','SKEWCORR','Skewness correction');
            obj.Capabilities.supportsHyperparameters = true;
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Skewness correction.
            %   Defines editable fields for the module that applies skewness correction to predictor
            %   distributions. The schema feeds defaultConfig, validateConfig, browser rendering,
            %   CLI/API help, and RAG documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = 'Correct skewed feature distributions using log, Box-Cox, or Yeo-Johnson transformations.';
            spec.fields = { ...
                struct('name','transform','type','enum','default','yeojohnson','label','Transform','values',{{'log','boxcox','yeojohnson'}}, ...
                    'help','Select logarithmic, Box-Cox, or Yeo-Johnson distribution transformation.'), ...
                struct('name','skewThreshold','type','numeric_vector','default',2,'label','Absolute skewness threshold', ...
                    'help','Absolute skewness threshold used to select features for correction.'), ...
                struct('name','boxcoxLambdaMode','type','enum','default','auto','label','Box-Cox lambda mode','values',{{'auto','manual'}}, ...
                    'help','Estimate lambda automatically or use the specified boxcoxLambda.'), ...
                struct('name','boxcoxLambda','type','numeric_vector','default',0,'label','Manual Box-Cox lambda', ...
                    'help','Manual Box-Cox lambda candidate(s), used when boxcoxLambdaMode is manual.'), ...
                struct('name','yjLambdaMode','type','enum','default','auto','label','Yeo-Johnson lambda mode','values',{{'auto','manual'}}, ...
                    'help','Estimate lambda automatically or use the specified yjLambda.'), ...
                struct('name','yjLambda','type','numeric_vector','default',0,'label','Manual Yeo-Johnson lambda', ...
                    'help','Manual Yeo-Johnson lambda candidate(s), used when yjLambdaMode is manual.'), ...
                struct('name','calibrationUse','type','integer','default',2,'min',1,'max',2,'uiHidden',true,'label','Calibration data use code', ...
                    'help','Inherited CALIBUSE: 1 = calibration data, 2 = training data (default).') };
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert Skewness correction config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'SKEWCORR' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.boxcoxLambda: stores the normalized boxcox lambda value in the module configuration.
            % cfg.boxcoxLambdaMode: stores the normalized boxcox lambda mode value in the module configuration.
            % cfg.calibrationUse: stores the normalized calibration use value in the module configuration.
            % cfg.skewThreshold: stores the normalized skew threshold value in the module configuration.
            % cfg.transform: stores the normalized transform value in the module configuration.
            % cfg.yjLambda: stores the normalized yj lambda value in the module configuration.
            % cfg.yjLambdaMode: stores the normalized yj lambda mode value in the module configuration.

            cfg = obj.parseConfig(cfg);
            S = struct();
            S.transformMethod = cfg.transform;
            S.SkewThr = cfg.skewThreshold;
            S.BoxCoxLambdaType = cfg.boxcoxLambdaMode;
            S.BoxCoxLambdaVal = cfg.boxcoxLambda;
            S.YJLambdaType = cfg.yjLambdaMode;
            S.YJLambdaVal = cfg.yjLambda;
            S.CALIBUSE = cfg.calibrationUse;
            PX = obj.buildPX(S);
            legacy = struct('cmd',obj.Id,'SKEWCORR',S,'PX',PX);
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Skewness correction settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isfield(legacy,'SKEWCORR'), S = legacy.SKEWCORR; else, S = legacy; end
            if isfield(S,'transformMethod'), cfg.transform = S.transformMethod; end
            if isfield(S,'SkewThr'), cfg.skewThreshold = S.SkewThr; end
            if isfield(S,'BoxCoxLambdaType'), cfg.boxcoxLambdaMode = S.BoxCoxLambdaType; end
            if isfield(S,'BoxCoxLambdaVal'), cfg.boxcoxLambda = S.BoxCoxLambdaVal; end
            if isfield(S,'YJLambdaType'), cfg.yjLambdaMode = S.YJLambdaType; end
            if isfield(S,'YJLambdaVal'), cfg.yjLambda = S.YJLambdaVal; end
            if isfield(S,'CALIBUSE') && ~isempty(S.CALIBUSE), cfg.calibrationUse = S.CALIBUSE; end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Skewness correction for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_SkewCorr_config')
                [S, PX, act] = nk_SkewCorr_config(legacy.SKEWCORR, legacy.PX, obj.getParentString(ctx), obj.getDefaultsFlag(ctx));
                legacy.SKEWCORR = S; legacy.PX = PX; legacy.cmd = obj.Id;
                cfg = obj.fromLegacy(legacy, ctx);
                aux = struct('PX',PX);
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Fit or apply the Skewness correction runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfSkewCorrObj.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end %#ok<NASGU>
            if nargin < 3 || isempty(trained)
                cfg = obj.defaultConfig();
                if isfield(ctx,'config'), cfg = ctx.config; end
                legacy = obj.toLegacy(cfg, ctx);
                [Yout, trained] = nk_PerfSkewCorrObj(Y, legacy.SKEWCORR);
            else
                trained.trained = true;
                Yout = nk_PerfSkewCorrObj(Y, trained);
            end
        end
    end

    methods (Access = private)
        function PX = buildPX(obj, S)
            % Mirrors nk_SkewCorr_config:updatePX. PX is deliberately built
            % through nk_AddParam because downstream preprocessing-shelf
            % ramification consumes PX.Px and PX.opt.
            PX = [];
            PX = obj.pxAdd(PX, S.SkewThr, 'skewthr', 1);
            if strcmpi(S.transformMethod,'boxcox') && strcmpi(S.BoxCoxLambdaType,'manual')
                PX = obj.pxAdd(PX, S.BoxCoxLambdaVal, 'boxcoxlambda', 2);
            end
            if strcmpi(S.transformMethod,'yeojohnson') && strcmpi(S.YJLambdaType,'manual')
                PX = obj.pxAdd(PX, S.YJLambdaVal, 'yjlambda', 3);
            end
            if ~obj.pxHasParams(PX)
                PX = obj.pxReset(PX);
            end
        end

        function cfg = validateOrError(obj, cfg)
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMSkewCorrModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end
    end
end

classdef NMImputeModule < NMPreprocModule
% Canonical adapter for NeuroMiner imputation preprocessing.

    methods
        function obj = NMImputeModule()
            % NMImputeModule  Construct the Imputation preprocessing adapter.
            %   Registers module id 'impute' with legacy branch 'IMPUTE' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('impute','IMPUTE','Imputation');
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Imputation.
            %   Defines editable fields for the module that imputes missing predictor values in
            %   CV-bound preprocessing folds. The schema feeds defaultConfig, validateConfig,
            %   browser rendering, CLI/API help, and RAG documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Impute missing feature values before model fitting. ', ...
                'k-nearest-neighbour parameters are shown only for kNN methods, ', ...
                'and hybrid parameters only for hybrid imputation.'];

            knnMethods = {'cityblock','euclidean','seuclidean','cosine','hamming','jaccard','hybrid','SeqkNN'};

            spec.fields = { ...
                struct('name','method','type','enum','default','SeqkNN','label','Imputation method', ...
                    'values',{{'median','mean','cityblock','euclidean','SeqkNN','downshift','seuclidean','cosine','hamming','jaccard','hybrid'}}, ...
                    'help',['Median/single-mean methods perform case-wise replacement from selected features; ', ...
                            'mean uses group-based feature means; kNN variants require k; ', ...
                            'hybrid adapts the distance measure to nominal versus ordinal/continuous features.']), ...
                struct('name','featureScope','type','enum','default','all','label','Features to impute', ...
                    'values',{{'all','subspace'}}, ...
                    'help','Use all available features, or restrict imputation to a user-defined feature subspace.'), ...
                struct('name','blockIndexVar','type','numeric_vector','default',[],'allowEmpty',true,'label','Feature subspace mask', ...
                    'visibleIf',struct('field','featureScope','equals','subspace'), ...
                    'help','Logical feature mask encoded as 0/1 values. Its length must equal the number of features when that context is known.'), ...
                struct('name','k','type','integer','default',7,'min',1,'label','Number of nearest neighbours', ...
                    'visibleIf',struct('field','method','in',{knnMethods}), ...
                    'help','Number of neighbours used by distance-based and SeqkNN imputation; ignored by methods that do not use neighbours.'), ...
                struct('name','hybridNominalMethod','type','enum','default','jaccard','label','Hybrid method for nominal features', ...
                    'values',{{'jaccard','hamming'}}, ...
                    'visibleIf',struct('field','method','equals','hybrid'), ...
                    'help','Distance metric applied to nominal features by hybrid imputation: Jaccard or Hamming.'), ...
                struct('name','hybridContinuousMethod','type','enum','default','euclidean','label','Hybrid method for ordinal / continuous features', ...
                    'values',{{'cityblock','euclidean','SeqkNN','seuclidean','cosine'}}, ...
                    'visibleIf',struct('field','method','equals','hybrid'), ...
                    'help','Distance metric applied to ordinal and continuous features by hybrid imputation.'), ...
                struct('name','hybridCutoff','type','integer','default',3,'min',1,'label','Maximum unique values for nominal imputation', ...
                    'visibleIf',struct('field','method','equals','hybrid'), ...
                    'help','Maximum number of distinct observed values for treating a feature as nominal during hybrid imputation.') };
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert Imputation config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'IMPUTE' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.blockIndexVar: stores the canonical 0/1 feature-subspace mask.
            % cfg.featureScope: stores the normalized feature scope value in the module configuration.
            % cfg.hybridContinuousMethod: stores the normalized hybrid continuous method value in the module configuration.
            % cfg.hybridCutoff: stores the normalized hybrid cutoff value in the module configuration.
            % cfg.hybridNominalMethod: stores the normalized hybrid nominal method value in the module configuration.
            % cfg.k: stores the normalized k value in the module configuration.
            % cfg.method: stores the selected algorithmic method inside a normalized module configuration.

            cfg = obj.parseConfig(cfg);
            I = struct();
            I.method = obj.methodToLegacy(cfg.method);
            I.k = cfg.k;
            if isfield(cfg,'featureScope') && strcmpi(char(cfg.featureScope),'subspace') && isfield(cfg,'blockIndexVar') && ~isempty(cfg.blockIndexVar)
                I.blockind = logical(cfg.blockIndexVar(:).');
            else
                I.blockind = [];
            end
            I.hybrid = struct('method1',cfg.hybridNominalMethod,'method2',cfg.hybridContinuousMethod,'cutoff',cfg.hybridCutoff);
            legacy = struct('cmd',obj.Id,'IMPUTE',I);
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict)
            % validateConfig  Validate and normalize the canonical imputation feature mask.
            %   Legacy IMPUTE.blockind is a logical feature mask, not a workspace-variable name.

            if nargin < 3 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(strict), strict = true; end
            if isfield(cfg,'blockIndexVar') && islogical(cfg.blockIndexVar)
                cfg.blockIndexVar = double(cfg.blockIndexVar);
            end
            [cfg, report] = validateConfig@NMPreprocModule(obj, cfg, ctx, strict);
            if ~report.ok, return; end
            if isfield(cfg,'featureScope') && strcmpi(char(cfg.featureScope),'all')
                cfg.blockIndexVar = [];
            elseif isfield(cfg,'featureScope') && strcmpi(char(cfg.featureScope),'subspace')
                mask = cfg.blockIndexVar;
                if strict && isempty(mask)
                    report.errors{end+1} = 'Field blockIndexVar must define a non-empty 0/1 feature mask when featureScope is subspace.';
                elseif any(mask(:) ~= 0 & mask(:) ~= 1)
                    report.errors{end+1} = 'Field blockIndexVar must contain only 0/1 values.';
                elseif isfield(ctx,'nFeatures') && ~isempty(ctx.nFeatures) && numel(mask) ~= double(ctx.nFeatures)
                    report.errors{end+1} = sprintf('Field blockIndexVar must contain exactly %g values for this feature space.', double(ctx.nFeatures));
                end
                report.ok = isempty(report.errors);
            end
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Imputation settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isfield(legacy,'IMPUTE'), I = legacy.IMPUTE; else, I = legacy; end
            if isfield(I,'method'), cfg.method = obj.methodFromLegacy(I.method); end
            if isfield(I,'k'), cfg.k = I.k; end
            if isfield(I,'blockind') && ~isempty(I.blockind)
                cfg.featureScope = 'subspace';
                cfg.blockIndexVar = double(I.blockind(:).');
            else
                cfg.featureScope = 'all';
                cfg.blockIndexVar = [];
            end
            if isfield(I,'hybrid')
                if isfield(I.hybrid,'method1'), cfg.hybridNominalMethod = I.hybrid.method1; end
                if isfield(I.hybrid,'method2'), cfg.hybridContinuousMethod = I.hybrid.method2; end
                if isfield(I.hybrid,'cutoff'), cfg.hybridCutoff = I.hybrid.cutoff; end
            end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Imputation for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_Impute_config')
                NM = NMConfigTools.getField(ctx,'NM',[]);
                varind = NMConfigTools.getField(ctx,'varind',1);
                [I, act] = nk_Impute_config(NM, legacy.IMPUTE, varind, obj.getParentString(ctx), obj.getDefaultsFlag(ctx));
                legacy.IMPUTE = I; legacy.cmd = obj.Id;
                cfg = obj.fromLegacy(legacy, ctx);
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Fit or apply the Imputation runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfImputeObj.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end %#ok<NASGU>
            if nargin < 3 || isempty(trained)
                cfg = obj.defaultConfig();
                if isfield(ctx,'config'), cfg = ctx.config; end
                legacy = obj.toLegacy(cfg, ctx);
                IN = legacy.IMPUTE;
                if ~isfield(IN,'X') || isempty(IN.X), IN.X = Y; end
                [Yout, trained] = nk_PerfImputeObj(Y, IN);
            else
                Yout = nk_PerfImputeObj(Y, trained);
            end
        end
    end

    methods (Access = private)
        function m = methodToLegacy(~, m)
            m = char(m);
            if strcmpi(m,'median')
                m = 'singlemean';
            end
        end

        function m = methodFromLegacy(~, m)
            m = char(m);
            if strcmpi(m,'singlemean')
                m = 'median';
            end
        end

        function cfg = validateOrError(obj, cfg)
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMImputeModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end
    end
end

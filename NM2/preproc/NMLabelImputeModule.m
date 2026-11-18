classdef NMLabelImputeModule < NMPreprocModule
% NMLabelImputeModule
% -------------------------------------------------------------------------
% Canonical adapter for legacy NeuroMiner label propagation/imputation.
%
% This module does not transform the feature matrix directly. In the legacy
% preprocessing engine, nk_GenPreprocSequence stores LABELIMPUTE in
% InputParam.P{i}; nk_PerfPreprocessObj_core then imputes missing training
% labels into SrcParam.TrL_imputed by calling nk_PerfImputeLabelObj.
% -------------------------------------------------------------------------

    methods
        function obj = NMLabelImputeModule()
            % NMLabelImputeModule  Construct the Label imputation preprocessing adapter.
            %   Registers module id 'labelimpute' with legacy branch 'LABELIMPUTE' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('labelimpute','LABELIMPUTE','Label imputation');
            obj.Capabilities.requiresLabels = true;
            obj.Capabilities.usesLabels = true;
            obj.Capabilities.changesFeatureSpace = false;
            obj.Capabilities.supportsMissingData = true;
            obj.Capabilities.trainFoldEstimated = true;
            obj.Sequence.allowMultiple = false;
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Label imputation.
            %   Defines editable fields for the module that configures label imputation for
            %   incomplete labels inside the legacy CV preprocessing engine. The schema feeds
            %   defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Propagate labels to training instances with missing outcome labels. ', ...
                'The imputation model is estimated within the training fold.'];
            spec.fields = { ...
                struct('name','method','type','enum','default','manhattan','label','Label propagation method', ...
                    'values',{{ ...
                        struct('value','none','label','Move to global/final handling (method = none)'), ...
                        struct('value','ml','label','Use selected supervised learner'), ...
                        struct('value','manhattan','label','KNN: Manhattan distance'), ...
                        struct('value','euclidean','label','KNN: Euclidean distance'), ...
                        struct('value','seuclidean','label','KNN: standardized Euclidean distance'), ...
                        struct('value','cosine','label','KNN: cosine similarity'), ...
                        struct('value','hamming','label','KNN: Hamming distance'), ...
                        struct('value','jaccard','label','KNN: Jaccard distance') }}, ...
                    'help','Choose the label propagation method: none, the configured learner, or a KNN distance metric. The model is fitted within the training fold.'), ...
                struct('name','k','type','integer','default',7,'min',1,'label','Number of nearest neighbours', ...
                    'visibleIf',struct('field','method','notIn',{{'none','ml'}}), ...
                    'help','Number of neighbours used by KNN-based label-propagation methods.'), ...
                struct('name','legacyLABELIMPUTE','type','struct','default',struct(),'label','Raw legacy LABELIMPUTE structure','uiHidden',true, ...
                    'help','Retained imported LABELIMPUTE settings for legacy configuration round trips.') };
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert Label imputation config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'LABELIMPUTE' for
            % the CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.k: stores the normalized k value in the module configuration.
            % cfg.method: stores the selected algorithmic method inside a normalized module configuration.

            cfg = obj.parseConfig(cfg);
            L = struct();
            L.k = cfg.k;
            L.method = char(cfg.method);
            legacy = struct('cmd',obj.Id,'LABELIMPUTE',L);
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Label imputation settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isfield(legacy,'LABELIMPUTE')
                L = legacy.LABELIMPUTE;
            else
                L = legacy;
            end
            if isfield(L,'method') && ~isempty(L.method)
                cfg.method = obj.canonicalMethod(L.method);
            end
            if isfield(L,'k') && ~isempty(L.k)
                cfg.k = L.k;
            end
            if ~isempty(L) && isstruct(L)
                cfg.legacyLABELIMPUTE = L;
            end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Label imputation for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_LabelImpute_config')
                [L, act] = nk_LabelImpute_config(legacy.LABELIMPUTE, obj.getParentString(ctx), obj.getDefaultsFlag(ctx));
                legacy.LABELIMPUTE = L; legacy.cmd = obj.Id;
                cfg = obj.fromLegacy(legacy, ctx);
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Provide the feature-matrix shim for Label imputation.
            %
            % The feature matrix is intentionally unchanged; the legacy CV engine applies label
            % imputation to labels/metadata during full preprocessing execution.
            %
            % The numerical feature matrix is unchanged. Full CV execution is
            % performed by the legacy act_labelimpute branch in
            % nk_PerfPreprocessObj_core, which writes SrcParam.TrL_imputed.
            %
            % ctx.config: provides the module configuration currently being validated or executed.
            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end %#ok<NASGU>
            Yout = Y;
            if nargin < 3 || isempty(trained)
                cfg = obj.defaultConfig();
                if isfield(ctx,'config'), cfg = ctx.config; end
                legacy = obj.toLegacy(cfg, ctx);
                trained = legacy.LABELIMPUTE;
                trained.noFeatureTransform = true;
                trained.note = 'Label imputation is applied by the legacy CV preprocessing engine, not by feature-matrix smoke execution.';
            end
        end
    end

    methods (Access = private)
        function cfg = validateOrError(obj, cfg)
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMLabelImputeModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end

        function m = canonicalMethod(~, m)
            m = lower(char(m));
            switch m
                case {'cityblock','manhattan'}
                    m = 'manhattan';
                case {'dist','dist2','euclid','euclidean'}
                    m = 'euclidean';
                case {'seuclid','seuclidean'}
                    m = 'seuclidean';
                case {'cos','cosine'}
                    m = 'cosine';
                case {'ham','hamming'}
                    m = 'hamming';
                case {'jac','jaccard'}
                    m = 'jaccard';
                case {'learner','supervised','ml'}
                    m = 'ml';
                otherwise
                    m = 'none';
            end
        end
    end
end

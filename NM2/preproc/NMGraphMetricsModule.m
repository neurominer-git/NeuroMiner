classdef NMGraphMetricsModule < NMPreprocModule
% NMGraphMetricsModule
% -------------------------------------------------------------------------
% Canonical adapter for legacy graph-metric computation.
% -------------------------------------------------------------------------

    methods
        function obj = NMGraphMetricsModule()
            % NMGraphMetricsModule  Construct the Graph metrics preprocessing adapter.
            %   Registers module id 'graphMetrics' with legacy branch 'GRAPHMETRICS' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('graphMetrics','GRAPHMETRICS','Graph metrics');
            obj.Category = 'graph-preprocessing';
            obj.Aliases = {'graphmetrics'};
            obj.Capabilities.executionStages = {'cv'};
            obj.Capabilities.changesFeatureSpace = true;
            obj.Capabilities.invalidatesImageSpace = true;
            obj.Capabilities.isDimensionalityReductionLike = true;
            obj.Sequence.allowMultiple = false;
        end

        function spec = configSpec(obj, ctx)
            % configSpec  Return the canonical API/UI schema for Graph metrics.
            %   Defines editable fields for the module that maps graph representations to
            %   graph-metric feature vectors. The schema feeds defaultConfig, validateConfig,
            %   browser rendering, CLI/API help, and RAG documentation extraction.

            if nargin < 2, ctx = struct(); end %#ok<INUSD>
            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Compute graph-theoretical metrics from upper-triangle connectivity edge vectors. ', ...
                'Only metrics supported by the current implementation are offered for new pipelines.'];
            spec.fields = { ...
                struct('name','computeMetrics','type','boolean','default',true,'label','Compute graph metrics', ...
                    'help','Enable graph-metric extraction from the connectivity representation.'), ...
                struct('name','selectedMetricIdx','type','numeric_vector','default',[1 2 3 4 7 8 9 10],'label','Selected metric indices', ...
                    'allowEmpty',false,'min',1,'max',14, ...
                    'help','Available metrics include degree, strength, betweenness, clustering, diameter, transitivity, eigenvector centrality, local/global efficiency and radius.'), ...
                struct('name','legacyGRAPHMETRICS','type','struct','default',struct(),'label','Raw legacy GRAPHMETRICS structure','uiHidden',true, ...
                    'help','Imported GRAPHMETRICS parameters retained for legacy configuration round trips.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Imported graph-metric PX settings retained for legacy configuration round trips.') };
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict)
            % validateConfig  Validate and normalize Graph metrics configuration.
            %
            % Checks canonical config fields and nested method settings before scripted use,
            % UI-state application, and legacy conversion to legacy branch 'GRAPHMETRICS'.
            %
            % cfg.computeMetrics: stores the normalized compute metrics value in the module configuration.
            % cfg.selectedMetricIdx: stores the normalized selected metric idx value in the module configuration.

            if nargin < 3, ctx = struct(); end
            if nargin < 4, strict = true; end
            [cfg, report] = validateConfig@NMPreprocModule(obj, cfg, ctx, strict);
            if ~report.ok, return; end
            if strict && cfg.computeMetrics && isempty(cfg.selectedMetricIdx)
                report.errors{end+1} = 'At least one graph metric must be selected.';
            end
            bad = intersect(cfg.selectedMetricIdx(:)', [11 13 14]);
            if ~isempty(bad)
                report.warnings{end+1} = sprintf('Graph metric indices %s are marked as not working in the legacy backend.', mat2str(bad));
            end
            report.ok = isempty(report.errors);
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Graph metrics config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'GRAPHMETRICS' for
            % the CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.computeMetrics: stores the normalized compute metrics value in the module configuration.
            % cfg.legacyGRAPHMETRICS: stores the normalized legacy graphmetrics value in the module configuration.
            % cfg.selectedMetricIdx: stores the normalized selected metric idx value in the module configuration.

            if nargin < 3, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end %#ok<INUSD>
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok, error('NMGraphMetricsModule:invalidConfig','%s',strjoin(report.errors,newline)); end
            if isfield(cfg,'legacyGRAPHMETRICS') && isstruct(cfg.legacyGRAPHMETRICS) && ~isempty(fieldnames(cfg.legacyGRAPHMETRICS))
                G = cfg.legacyGRAPHMETRICS;
            else
                G = struct();
            end
            G.metric = obj.boolToLegacyYesNo(logical(cfg.computeMetrics));
            G.metricslist = obj.metricIdxToLegacy(cfg.selectedMetricIdx);
            legacy = struct('cmd',obj.Id,'GRAPHMETRICS',G,'PX',obj.emptyPX(cfg));
        end

        function cfg = fromLegacy(obj, legacy, ctx)
            % fromLegacy  Import legacy Graph metrics settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            if nargin < 3, ctx = struct(); end
            cfg = obj.defaultConfig(ctx);
            if isempty(legacy), return; end
            if isfield(legacy,'GRAPHMETRICS'), G = legacy.GRAPHMETRICS; else, G = legacy; end
            cfg.legacyGRAPHMETRICS = G;
            if isfield(legacy,'PX') && isstruct(legacy.PX), cfg.legacyPX = legacy.PX; end
            if isfield(G,'metric'), cfg.computeMetrics = obj.legacyYesNoToBool(G.metric, true); end
            if isfield(G,'metrics'), cfg.computeMetrics = obj.legacyYesNoToBool(G.metrics, cfg.computeMetrics); end
            if isfield(G,'metricslist') && ~isempty(G.metricslist)
                cfg.selectedMetricIdx = obj.metricIdxFromLegacy(G.metricslist);
            end
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok
                warning('NMGraphMetricsModule:legacyImport','Imported graph-metrics config did not validate cleanly: %s', strjoin(report.errors,'; '));
            end
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Graph metrics for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('cv_graphMetrics_config')
                parentstr = obj.getParentString(ctx);
                G = legacy.GRAPHMETRICS; PX = legacy.PX;
                act = 1;
                while act > 0
                    [G, PX, act] = cv_graphMetrics_config(G, PX, parentstr);
                end
                legacy = struct('cmd',obj.Id,'GRAPHMETRICS',G,'PX',PX);
                cfg = obj.fromLegacy(legacy, ctx);
            else
                act = 0;
            end
        end
    end

    methods (Access = private)
        function C = metricIdxToLegacy(obj, idx)
            idx = unique(idx(:)','stable');
            C = cell(1,numel(idx));
            names = obj.metricNames();
            for i = 1:numel(idx)
                k = idx(i);
                s = struct();
                if k >= 1 && k <= numel(names), s.id = names{k}; else, s.id = sprintf('metric_%d', k); end
                s.listidx = k;
                C{i} = s;
            end
        end

        function idx = metricIdxFromLegacy(~, C)
            idx = [];
            if isstruct(C), C = num2cell(C); end
            for i = 1:numel(C)
                x = C{i};
                try
                    if isfield(x,'listidx'), idx(end+1) = double(x.listidx); end %#ok<AGROW>
                catch
                end
            end
            idx = unique(idx,'stable');
        end

        function names = metricNames(~)
            names = {'degree (local)','strength (local)','betweenness (local)', ...
                'clustering coefficient (local)','clustering coefficient (global)', ...
                'diameter','transitivity (global)','eigenvector', ...
                'efficiency (local)','efficiency (global)','closeness','radius','pagerank','distance'};
        end

        function PX = emptyPX(~, cfg)
            if nargin >= 2 && isfield(cfg,'legacyPX') && isstruct(cfg.legacyPX) && ~isempty(fieldnames(cfg.legacyPX))
                PX = cfg.legacyPX;
                if ~isfield(PX,'opt'), PX.opt = []; end
            else
                PX = struct('opt',[]);
            end
        end
    end
end

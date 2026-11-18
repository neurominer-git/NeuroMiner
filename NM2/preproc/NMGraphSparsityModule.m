classdef NMGraphSparsityModule < NMPreprocModule
% NMGraphSparsityModule
% -------------------------------------------------------------------------
% Canonical adapter for legacy graph sparsity thresholding.
% -------------------------------------------------------------------------

    methods
        function obj = NMGraphSparsityModule()
            % NMGraphSparsityModule  Construct the Graph sparsity thresholding preprocessing adapter.
            %   Registers module id 'graphSparsity' with legacy branch 'GRAPHSPARSITY' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('graphSparsity','GRAPHSPARSITY','Graph sparsity thresholding');
            obj.Category = 'graph-preprocessing';
            obj.Aliases = {'graphsparsity'};
            obj.Capabilities.executionStages = {'cv'};
            obj.Capabilities.changesFeatureSpace = true;
            obj.Capabilities.supportsHyperparameters = true;
            obj.Sequence.allowMultiple = false;
        end

        function spec = configSpec(obj, ctx)
            % configSpec  Return the canonical API/UI schema for Graph sparsity thresholding.
            %   Defines editable fields for the module that applies graph sparsity or thresholding
            %   rules before graph metrics are computed. The schema feeds defaultConfig,
            %   validateConfig, browser rendering, CLI/API help, and RAG documentation extraction.

            if nargin < 2, ctx = struct(); end %#ok<INUSD>
            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Apply graph-edge sparsity thresholding. Values are edge-retention fractions ', ...
                'in the interval (0,1].'];
            spec.fields = { ...
                struct('name','sparsityPerc','type','numeric_vector','default',[],'label','Edge-retention fraction(s)', ...
                    'allowEmpty',true,'min',0,'max',1, ...
                    'help','Enter one or more edge-retention fractions, for example 0.10 0.20. Multiple values define optimization candidates.'), ...
                struct('name','legacyGRAPHSPARSITY','type','struct','default',struct(),'label','Raw legacy GRAPHSPARSITY structure','uiHidden',true, ...
                    'help','Imported GRAPHSPARSITY thresholding settings retained for legacy configuration round trips.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Imported graph-sparsity PX settings retained for legacy configuration round trips.') };
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict)
            % validateConfig  Validate and normalize Graph sparsity thresholding configuration.
            %
            % Checks canonical config fields and nested method settings before scripted use,
            % UI-state application, and legacy conversion to legacy branch 'GRAPHSPARSITY'.
            %
            % cfg.sparsityPerc: stores the normalized sparsity perc value in the module configuration.

            if nargin < 3, ctx = struct(); end
            if nargin < 4, strict = true; end
            [cfg, report] = validateConfig@NMPreprocModule(obj, cfg, ctx, strict);
            if ~isempty(cfg.sparsityPerc) && any(cfg.sparsityPerc(:) <= 0)
                report.errors{end+1} = 'Graph sparsity fractions must be > 0 and <= 1.';
            end
            report.ok = isempty(report.errors);
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Graph sparsity thresholding config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'GRAPHSPARSITY'
            % for the CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.legacyGRAPHSPARSITY: stores the normalized legacy graphsparsity value in the module configuration.
            % cfg.sparsityPerc: stores the normalized sparsity perc value in the module configuration.

            if nargin < 3, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end %#ok<INUSD>
            cfg = obj.parseConfig(cfg);
            if isfield(cfg,'legacyGRAPHSPARSITY') && isstruct(cfg.legacyGRAPHSPARSITY) && ~isempty(fieldnames(cfg.legacyGRAPHSPARSITY))
                G = cfg.legacyGRAPHSPARSITY;
            else
                G = struct();
            end
            G.perc = cfg.sparsityPerc;
            PX = obj.sparsityPX(cfg.sparsityPerc, cfg);
            legacy = struct('cmd',obj.Id,'GRAPHSPARSITY',G,'PX',PX);
        end

        function cfg = fromLegacy(obj, legacy, ctx)
            % fromLegacy  Import legacy Graph sparsity thresholding settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            if nargin < 3, ctx = struct(); end
            cfg = obj.defaultConfig(ctx);
            if isempty(legacy), return; end
            if isfield(legacy,'GRAPHSPARSITY'), G = legacy.GRAPHSPARSITY; else, G = legacy; end
            cfg.legacyGRAPHSPARSITY = G;
            if isfield(G,'perc'), cfg.sparsityPerc = G.perc; end
            if isfield(legacy,'PX') && isstruct(legacy.PX), cfg.legacyPX = legacy.PX; end
            cfg = obj.parseConfig(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Graph sparsity thresholding for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('cv_graphSparsity_config')
                parentstr = obj.getParentString(ctx);
                G = legacy.GRAPHSPARSITY; PX = legacy.PX;
                act = 1;
                while act > 0
                    [G, PX, act] = cv_graphSparsity_config(G, PX, parentstr);
                end
                legacy = struct('cmd',obj.Id,'GRAPHSPARSITY',G,'PX',PX);
                cfg = obj.fromLegacy(legacy, ctx);
            else
                act = 0;
            end
        end
    end

    methods (Access = private)
        function PX = sparsityPX(obj, vals, cfg)
            if nargin >= 3 && isfield(cfg,'legacyPX') && isstruct(cfg.legacyPX) && ~isempty(fieldnames(cfg.legacyPX))
                PX = cfg.legacyPX;
            else
                PX = [];
            end
            if isempty(vals)
                try
                    PX = obj.pxReset([]); PX.opt = [];
                catch
                    PX = struct('opt',[]);
                end
                return;
            end
            try
                PX = obj.pxAdd([], vals, 'SparsityPerc', 1, '');
                if exist('allcomb','file') == 2
                    PX.opt = allcomb(PX.Px.Params,'matlab');
                else
                    PX.opt = vals(:);
                end
            catch
                PX = struct('opt', vals(:));
            end
        end
    end
end

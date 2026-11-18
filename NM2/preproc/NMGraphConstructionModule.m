classdef NMGraphConstructionModule < NMPreprocModule
% NMGraphConstructionModule
% -------------------------------------------------------------------------
% Canonical adapter for legacy graph construction preprocessing.
%
% The legacy backend has two conceptually different modes:
%   - Normative network + 1: CV-bound, because it can depend on a training /
%     calibration reference group.
%   - KL divergence: deterministic image-space feature extraction from atlas
%     density distributions; this can be used either subject-specifically
%     (exported through PREPROC.SPATIAL) or CV-bound (exported through
%     ACTPARAM), subject to the same image-space gate as JuSpace/ROImeans.
% -------------------------------------------------------------------------

    methods
        function obj = NMGraphConstructionModule()
            % NMGraphConstructionModule  Construct the Graph construction preprocessing adapter.
            %   Registers module id 'graphComputation' with legacy branch 'GRAPHCONSTRUCTION' and
            %   sets capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('graphComputation','GRAPHCONSTRUCTION','Graph construction');
            obj.Category = 'graph-preprocessing';
            obj.Aliases = {'graphconstruction','graphConstruction'};
            obj.Capabilities.executionStages = {'subject','cv'};
            obj.Capabilities.changesFeatureSpace = true;
            obj.Capabilities.trainFoldEstimated = true;
            obj.Capabilities.supportsHyperparameters = false;
            obj.Capabilities.legacySubjectTarget = 'PREPROC.SPATIAL';
            obj.Capabilities.legacyCVTarget = 'ACTPARAM';
            obj.Sequence.allowMultiple = false;
        end

        function spec = configSpec(obj, ctx)
            % configSpec  Return the canonical API/UI schema for Graph construction.
            %   Defines editable fields for the module that constructs graph representations from
            %   modality data before graph-derived feature computation. The schema feeds
            %   defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            if nargin < 2 || isempty(ctx), ctx = struct(); end
            spec = configSpec@NMPreprocModule(obj, ctx);
            stage = obj.contextStage(ctx);
            if strcmpi(stage,'subject')
                methodDefault = 'KL divergence';
                methodValues = {'KL divergence'};
                descr = ['Construct subject-specific KL-divergence graph features from image-space data. ', ...
                    'Subject-stage graph construction is exported through PREPROC.SPATIAL and follows the same image-space gate as JuSpace/ROImeans.'];
            else
                methodDefault = 'Normative network + 1';
                methodValues = {'Normative network + 1','KL divergence'};
                descr = ['Construct individual graph/connectivity features using the legacy cv_graph_PerfGraphConstruction backend. ', ...
                    'Normative network + 1 is CV-bound; KL divergence may also be used subject-specifically.'];
            end

            bm = [];
            if isstruct(ctx) && isfield(ctx,'brainmask'), bm = ctx.brainmask; end
            spec.description = descr;
            spec.fields = { ...
                struct('name','method','type','enum','default',methodDefault,'label','Graph construction method', ...
                    'values',{methodValues}, ...
                    'help','KL divergence is an image-space terminal feature extractor; Normative network + 1 uses a reference/calibration group and is CV-bound.'), ...
                struct('name','simMeasure','type','enum','default','Mutual information','label','Similarity measure', ...
                    'values',{{'Mutual information','Pearson correlation','Spearman`s rho','Kendall`s Tau','Kendall`s tau'}}, ...
                    'visibleIf',struct('field','method','equals','Normative network + 1'), ...
                    'help','Similarity measure used to construct a normative network from the reference group; available only for Normative network + 1.'), ...
                struct('name','referenceSource','type','enum','default','calibration','label','Reference group source', ...
                    'values',{{'calibration','file','workspace','legacy'}}, ...
                    'visibleIf',struct('field','method','equals','Normative network + 1'), ...
                    'help','Use calibration data, an external text/CSV file, a workspace variable/expression, or preserve an imported reference-group setting.'), ...
                struct('name','referenceFile','type','file_path','default','','label','Reference group file', ...
                    'selectorMode','file','multiple',false,'fileFilter','*.txt;*.csv;*.mat', ...
                    'visibleIf',struct('all',{{struct('field','method','equals','Normative network + 1'),struct('field','referenceSource','equals','file')}}), ...
                    'help','File containing the reference group for normative graph construction; used when the source is file.'), ...
                struct('name','referenceWorkspaceExpr','type','string','default','','label','Reference group workspace variable/expression', ...
                    'visibleIf',struct('all',{{struct('field','method','equals','Normative network + 1'),struct('field','referenceSource','equals','workspace')}}), ...
                    'help','Workspace variable or expression identifying the normative reference group; used when the source is workspace.'), ...
                struct('name','parcellationAtlasPath','type','file_path','default','','label','Parcellation atlas', ...
                    'selectorMode','file','multiple',false,'fileFilter','*.nii;*.nii.gz;*.img', ...
                    'visibleIf',struct('field','method','equals','KL divergence'), ...
                    'help','Atlas image used to extract ROI density distributions for symmetric KL divergence.'), ...
                struct('name','brainmask','type','any','default',bm,'label','Brain mask','uiHidden',true, ...
                    'help','Inherited brain-mask payload used by the image-space KL-divergence graph constructor.'), ...
                struct('name','brainmaskSummary','type','readonly','default',obj.anyToString(bm),'label','Brain mask', ...
                    'visibleIf',struct('field','method','equals','KL divergence'), ...
                    'help','Read-only summary of the brain mask available to image-space KL-divergence construction.'), ...
                struct('name','legacyRefGroup','type','any','default',[],'label','Raw legacy reference group','uiHidden',true, ...
                    'help','Imported reference-group setting retained when preserving an existing graph-construction configuration.'), ...
                struct('name','legacyGRAPHCONSTRUCTION','type','struct','default',struct(),'label','Raw legacy GRAPHCONSTRUCTION structure','uiHidden',true, ...
                    'help','Imported GRAPHCONSTRUCTION parameters retained for legacy configuration round trips.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Imported graph-construction PX settings retained for legacy configuration round trips.') };
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict)
            % validateConfig  Validate and normalize Graph construction configuration.
            %
            % Checks canonical config fields and nested method settings before scripted use,
            % UI-state application, and legacy conversion to legacy branch 'GRAPHCONSTRUCTION'.
            %
            % cfg.brainmask: stores the normalized brainmask value in the module configuration.
            % cfg.method: stores the selected algorithmic method inside a normalized module configuration.

            if nargin < 3, ctx = struct(); end
            if nargin < 4, strict = true; end
            [cfg, report] = validateConfig@NMPreprocModule(obj, cfg, ctx, strict);
            if ~report.ok, return; end
            cfg.method = obj.canonicalMethod(cfg.method);
            if strcmpi(obj.contextStage(ctx),'subject') && ~strcmp(cfg.method,'KL divergence')
                report.errors{end+1} = 'Subject-specific graph construction supports only KL divergence.';
            end
            if strcmp(cfg.method,'KL divergence')
                if isempty(obj.getcfg(cfg,'parcellationAtlasPath',''))
                    report.warnings{end+1} = 'KL graph construction requires a parcellation atlas before execution.';
                end
                bm = [];
                if isstruct(ctx) && isfield(ctx,'brainmask'), bm = ctx.brainmask; end
                if isempty(bm) && (~isfield(cfg,'brainmask') || isempty(cfg.brainmask))
                    report.warnings{end+1} = 'KL graph construction requires an imaging brain mask before execution.';
                end
            end
            report.ok = isempty(report.errors);
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Graph construction config to legacy preprocessing fields.
            %   Validates/normalizes canonical cfg and materializes legacy branch
            %   'GRAPHCONSTRUCTION' for the CV-bound PREPROC/ACTPARAM path consumed by legacy
            %   training backends.

            if nargin < 3, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            cfg = obj.parseConfigWithCtx(cfg, ctx);
            [G, PX] = obj.configToLegacyParts(cfg, ctx);
            legacy = struct('cmd',obj.Id,'GRAPHCONSTRUCTION',G,'PX',PX);
        end

        function legacy = toLegacySubject(obj, cfg, ctx)
            % toLegacySubject  Convert graph-construction config to a subject-level legacy SPATIAL step.
            %
            % Used when graph construction is applied before CV-bound feature processing; stores
            % the same canonical config under a SPATIAL command branch.
            %
            % cfg.method: stores the selected algorithmic method inside a normalized module configuration.

            if nargin < 3, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            cfg = obj.parseConfigWithCtx(cfg, ctx);
            if ~strcmp(obj.canonicalMethod(cfg.method),'KL divergence')
                error('NMGraphConstructionModule:subjectMode','Subject-specific graph construction supports only KL divergence.');
            end
            [G, PX] = obj.configToLegacyParts(cfg, ctx);
            legacy = struct('cmd',obj.Id,'GRAPHCONSTRUCTION',G,'PX',PX);
        end

        function cfg = fromLegacy(obj, legacy, ctx)
            % fromLegacy  Import legacy Graph construction settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            if nargin < 3, ctx = struct(); end
            cfg = obj.defaultConfig(ctx);
            if isempty(legacy), return; end
            if isfield(legacy,'GRAPHCONSTRUCTION'), G = legacy.GRAPHCONSTRUCTION; else, G = legacy; end
            cfg.legacyGRAPHCONSTRUCTION = G;
            if isfield(legacy,'PX') && isstruct(legacy.PX), cfg.legacyPX = legacy.PX; end
            if isfield(G,'method') && ~isempty(G.method), cfg.method = obj.canonicalMethod(G.method); end
            if isfield(G,'simMeasure') && ~isempty(G.simMeasure), cfg.simMeasure = obj.canonicalSimMeasure(G.simMeasure); end
            if isfield(G,'parcellation') && ~isempty(G.parcellation), cfg.parcellationAtlasPath = char(G.parcellation); end
            if isfield(G,'brainmask') && ~isempty(G.brainmask), cfg.brainmask = G.brainmask; end
            if isfield(G,'refGroup')
                cfg.legacyRefGroup = G.refGroup;
                if isequal(G.refGroup,-1)
                    cfg.referenceSource = 'calibration';
                elseif ischar(G.refGroup) || isstring(G.refGroup)
                    s = char(G.refGroup);
                    if exist(s,'file') == 2
                        cfg.referenceSource = 'file'; cfg.referenceFile = s;
                    else
                        cfg.referenceSource = 'workspace'; cfg.referenceWorkspaceExpr = s;
                    end
                else
                    cfg.referenceSource = 'legacy';
                end
            end
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok
                warning('NMGraphConstructionModule:legacyImport','Imported graph-construction config did not validate cleanly: %s', strjoin(report.errors,'; '));
            end
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Graph construction for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('cv_graphConstruction_config')
                parentstr = obj.getParentString(ctx);
                G = legacy.GRAPHCONSTRUCTION; PX = legacy.PX;
                brainmask = ctx.brainmask;
                act = 1;
                while act > 0
                    [G, PX, act] = cv_graphConstruction_config(G, PX, brainmask, parentstr);
                end
                legacy = struct('cmd',obj.Id,'GRAPHCONSTRUCTION',G,'PX',PX);
                cfg = obj.fromLegacy(legacy, ctx);
            else
                act = 0;
            end
        end
    end

    methods (Access = private)
        function cfg = parseConfigWithCtx(obj, cfg, ctx)
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok, error('NMGraphConstructionModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end

        function [G, PX] = configToLegacyParts(obj, cfg, ctx)
            if isfield(cfg,'legacyGRAPHCONSTRUCTION') && isstruct(cfg.legacyGRAPHCONSTRUCTION) && ~isempty(fieldnames(cfg.legacyGRAPHCONSTRUCTION))
                G = cfg.legacyGRAPHCONSTRUCTION;
            else
                G = struct();
            end
            G.method = obj.canonicalMethod(cfg.method);
            PX = obj.emptyPX();
            switch G.method
                case 'KL divergence'
                    G.parcellation = char(obj.getcfg(cfg,'parcellationAtlasPath',''));
                    bm = [];
                    if isstruct(ctx) && isfield(ctx,'brainmask'), bm = ctx.brainmask; end
                    if isempty(bm) && isfield(cfg,'brainmask'), bm = cfg.brainmask; end
                    G.brainmask = bm;
                otherwise
                    G.simMeasure = obj.canonicalSimMeasure(obj.getcfg(cfg,'simMeasure','Mutual information'));
                    G.refGroup = obj.referenceGroupFromConfig(cfg);
            end
            if isfield(cfg,'legacyPX') && isstruct(cfg.legacyPX) && ~isempty(fieldnames(cfg.legacyPX))
                % Preserve imported non-empty PX shelves, but graph construction
                % currently has no active hyperparameter in the legacy configurator.
                PX = cfg.legacyPX;
                if ~isfield(PX,'opt'), PX.opt = []; end
            end
        end

        function rg = referenceGroupFromConfig(obj, cfg)
            src = obj.getcfg(cfg,'referenceSource','calibration');
            switch lower(char(src))
                case 'calibration'
                    rg = -1;
                case 'file'
                    rg = char(obj.getcfg(cfg,'referenceFile',''));
                case 'workspace'
                    rg = char(obj.getcfg(cfg,'referenceWorkspaceExpr',''));
                otherwise
                    if isfield(cfg,'legacyRefGroup') && ~isempty(cfg.legacyRefGroup)
                        rg = cfg.legacyRefGroup;
                    else
                        rg = -1;
                    end
            end
        end

        function PX = emptyPX(obj)
            try
                PX = obj.pxReset([]);
            catch
                PX = struct('opt',[]);
            end
            try
                PX.opt = [];
            catch
            end
        end

        function s = contextStage(~, ctx)
            s = 'cv';
            if isstruct(ctx) && isfield(ctx,'executionStage') && ~isempty(ctx.executionStage)
                s = lower(char(ctx.executionStage));
            end
        end

        function m = canonicalMethod(~, m)
            if isstring(m), m = char(m); end
            if isempty(m), m = 'Normative network + 1'; return; end
            if strcmpi(char(m),'KL divergence')
                m = 'KL divergence';
            else
                m = 'Normative network + 1';
            end
        end

        function s = canonicalSimMeasure(~, s)
            if isstring(s), s = char(s); end
            if isempty(s), s = 'Mutual information'; return; end
            switch lower(strtrim(char(s)))
                case lower('Pearson correlation')
                    s = 'Pearson correlation';
                case lower('Spearman`s rho')
                    s = 'Spearman`s rho';
                case {lower('Kendall`s tau'), lower('Kendall`s Tau')}
                    s = 'Kendall`s Tau';
                otherwise
                    s = 'Mutual information';
            end
        end

        function s = anyToString(~, x)
            if isempty(x), s = ''; return; end
            if ischar(x), s = x; return; end
            if isstring(x), s = char(strjoin(x, '; ')); return; end
            if iscell(x)
                try, s = strjoin(cellfun(@char,x,'UniformOutput',false), '; '); return; catch, end
            end
            try, s = mat2str(x); catch, s = '<value>'; end
        end

        function v = getcfg(~, s, name, def)
            v = def;
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), v = s.(name); end
        end
    end
end

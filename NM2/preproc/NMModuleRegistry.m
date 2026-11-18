classdef NMModuleRegistry < handle
% NMModuleRegistry
% -------------------------------------------------------------------------
% Generic registry for NeuroMiner modules. The sequence builder, browser UI,
% CLI bridge, and future agentic API all use this surface rather than hard-
% coding preprocessing function names.
% -------------------------------------------------------------------------

    properties (Access = private)
        Modules
        AliasToId
    end

    methods (Static)
        function r = default()
            % default  Build the standard NeuroMiner preprocessing-module registry.
            %   Registers the ported modular adapters and legacy placeholders in the order used by
            %   preprocessing builders, UI module pickers, and legacy import/export.

            r = NMModuleRegistry();
            r.register(NMImputeModule());
            r.register(NMLabelImputeModule());
            r.register(NMSmoothingModule());
            r.register(NMWaveletSpatialModule());
            r.register(NMJuSpaceModule());
            r.register(NMROIMeansModule());
            r.register(NMLegacySpatialModule());
            r.register(NMScaleModule());
            r.register(NMStandardizeModule());
            r.register(NMUnitNormalizeModule());
            r.register(NMDiscSymModule());
            r.register(NMElimZeroModule());
            r.register(NMSkewCorrModule());
            r.register(NMCopyFeatModule());
            r.register(NMRankFeatModule());
            r.register(NMExtFeatModule());
            r.register(NMReducedimModule());
            r.register(NMRemVarCompModule());
            r.register(NMExtDimModule());
            r.register(NMCorrectNuisModule());
            r.register(NMRemMeanDiffModule());
            r.register(NMDevMapModule());
            r.register(NMGraphConstructionModule());
            r.register(NMGraphSparsityModule());
            r.register(NMGraphMetricsModule());
            r.registerLegacyPreprocPlaceholders();
        end
    end

    methods
        function obj = NMModuleRegistry()
            % NMModuleRegistry  Construct an empty preprocessing-module registry.
            %   Creates id and alias maps; callers normally use default(), but tests or extensions
            %   may instantiate a registry and register custom NMPreprocModule subclasses.

            obj.Modules = containers.Map('KeyType','char','ValueType','any');
            obj.AliasToId = containers.Map('KeyType','char','ValueType','char');
        end

        function register(obj, module)
            % register  Register one NMPreprocModule instance and its aliases.
            %   Updates the canonical id map and alias map used by has(), get(), sequence
            %   construction, UI addable-module lists, and legacy command import.

            if ~isa(module,'NMPreprocModule')
                error('NMModuleRegistry:invalidModule','Registered object must derive from NMPreprocModule.');
            end
            id = lower(module.Id);
            if obj.Modules.isKey(id)
                error('NMModuleRegistry:duplicate','Module id already registered: %s', id);
            end
            obj.Modules(id) = module;
            obj.AliasToId(id) = id;
            for i = 1:numel(module.Aliases)
                obj.AliasToId(lower(module.Aliases{i})) = id;
            end
        end

        function tf = has(obj, id)
            % has  Test whether a module id or alias is known to the registry.
            %   Used before resolving user/API supplied ids and by rule checks that must tolerate
            %   legacy aliases without throwing.

            tf = obj.AliasToId.isKey(lower(char(id)));
        end

        function module = get(obj, id)
            % get  Resolve a module id or alias to its registered module object.
            %   This is the primary entry point for scripts and orchestrators that need module
            %   defaults, validation, legacy conversion, or execution adapters.

            key = lower(char(id));
            if ~obj.AliasToId.isKey(key)
                error('NMModuleRegistry:notFound','Unknown module: %s', char(id));
            end
            module = obj.Modules(obj.AliasToId(key));
        end

        function ids = list(obj)
            % list  Return sorted canonical module ids registered in this registry.
            %   Used by inventory, UI picker construction, and documentation extraction; aliases are
            %   not returned here.

            ids = sort(obj.Modules.keys);
        end

        function metas = infos(obj)
            % infos  Return metadata structs for all registered modules.
            %   Calls each module info() method so maintainers and UI/RAG layers can inspect
            %   capabilities and sequencing constraints without constructing configs.

            ids = obj.list();
            metas = cell(1,numel(ids));
            for i = 1:numel(ids), metas{i} = obj.Modules(ids{i}).info(); end
        end

        function specs = configSpecs(obj, ctx)
            % configSpecs  Return configuration schemas for all registered modules in a context.
            %   Each schema is produced by the owning module and therefore reflects task, modality,
            %   and context-dependent options available to API users.

            if nargin < 2, ctx = struct(); end
            ids = obj.list();
            specs = cell(1,numel(ids));
            for i = 1:numel(ids), specs{i} = obj.Modules(ids{i}).configSpec(ctx); end
        end



        function id = canonicalId(obj, id)
            % canonicalId  Normalize a user-supplied module id or alias to the registry canonical id.
            %   This protects public API calls and legacy import paths from case differences and
            %   historical command aliases while preserving unknown ids as lower-case tokens.

            key = lower(char(id));
            if obj.AliasToId.isKey(key)
                id = obj.AliasToId(key);
            else
                id = key;
            end
        end

        function registerLegacyPreprocPlaceholders(obj)
            % registerLegacyPreprocPlaceholders  Register raw-preservation placeholders for legacy preprocessing commands.
            %   Keeps not-yet-ported ACTPARAM commands visible and round-trippable so importing old
            %   projects does not silently drop preprocessing steps.

            % Dependency rules are already known for several modules whose
            % canonical configurators are not yet ported. Register raw legacy
            % placeholders so existing PREPROC.ACTPARAM sequences can be
            % imported, displayed, validated, and exported without loss.
            defs = { ...
                'correctnuis',      'Regress out nuisance covariates'; ...
                'normalize',        'Normalize to group mean'; ...
                'labelimpute',      'Propagate labels'; ...
                'rankfeat',         'Rank, weight, or mask features'; ...
                'extfeat',          'Apply feature-ranking action'; ...
                'reducedim',        'Dimensionality reduction'; ...
                'extdim',           'Extract subspaces'; ...
                'remvarcomp',       'Remove variance components'; ...
                'devmap',           'Deviation mapping'; ...
                'graphComputation', 'Graph construction'; ...
                'graphSparsity',    'Graph sparsity thresholding'; ...
                'graphMetrics',     'Graph metrics'; ...
                'JuSpace',          'JuSpace neuromap correlations'; ...
                'ROImeans',         'ROI mean extraction'; ...
                'customPreproc',    'Custom preprocessing function'};
            for i = 1:size(defs,1)
                if ~obj.has(defs{i,1})
                    obj.register(NMLegacyPreprocModule(defs{i,1}, defs{i,2}));
                end
            end
        end

        function T = summary(obj)
            % summary  Return a table-style registry summary for maintainers and UI diagnostics.
            %   The table exposes ids, display names, legacy fields, class names, and capability
            %   flags used to audit the active preprocessing API surface.

            ids = obj.list();
            displayName = cell(numel(ids),1);
            legacyField = cell(numel(ids),1);
            className = cell(numel(ids),1);
            changesFeatureSpace = false(numel(ids),1);
            for i = 1:numel(ids)
                m = obj.Modules(ids{i}); info = m.info();
                displayName{i} = info.displayName;
                legacyField{i} = info.legacyField;
                className{i} = info.className;
                changesFeatureSpace(i) = info.capabilities.changesFeatureSpace;
            end
            T = table(ids(:), displayName, legacyField, className, changesFeatureSpace, ...
                'VariableNames', {'Id','DisplayName','LegacyField','ClassName','ChangesFeatureSpace'});
        end
    end
end

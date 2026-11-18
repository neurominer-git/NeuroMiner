classdef NMSmoothingModule < NMPreprocModule
% NMSmoothingModule
% -------------------------------------------------------------------------
% Subject-specific Gaussian smoothing adapter for legacy nk_Spatial_config
% cubetype == 4. This module is deliberately non-CV for now. Reslicing is
% not implemented here and must not be placed before smoothing later.
% -------------------------------------------------------------------------

    methods
        function obj = NMSmoothingModule()
            % NMSmoothingModule  Construct the Gaussian smoothing preprocessing adapter.
            %   Registers module id 'smoothing' with legacy branch 'SPATIAL' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('smoothing','SPATIAL','Gaussian smoothing');
            obj.Category = 'subject-preprocessing';
            obj.Aliases = {'spatialsmoothing','gaussiansmoothing'};
            obj.Capabilities.executionStages = {'subject'};
            obj.Capabilities.imagingOnly = true;
            obj.Capabilities.requiresImageSpace = true;
            obj.Capabilities.isImageSpaceTerminal = false;
            obj.Capabilities.uniqueAcrossStages = false;
            obj.Capabilities.trainFoldEstimated = false;
            obj.Capabilities.changesFeatureSpace = false;
            obj.Capabilities.legacySubjectTarget = 'PREPROC.SPATIAL';
            obj.Capabilities.legacyCVTarget = '';
            obj.Sequence.allowMultiple = false;
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Gaussian smoothing.
            %   Defines editable fields for the module that adds Gaussian smoothing as a
            %   subject-level spatial preprocessing step. The schema feeds defaultConfig,
            %   validateConfig, browser rendering, CLI/API help, and RAG documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Gaussian smoothing in image space before CV splitting. ', ...
                'It may precede JuSpace or ROI-mean extraction, but it may not follow either because those modules leave image space.'];
            spec.fields = { ...
                struct('name','fwhm','type','numeric_vector','default',8,'label','Gaussian filter width [mm]', ...
                    'help','Gaussian filter width in millimetres. Multiple values define candidate smoothing widths for optimization.'), ...
                struct('name','legacySPATIAL','type','struct','default',struct(),'label','Raw legacy SPATIAL structure','uiHidden',true, ...
                    'help','Preserved imported SPATIAL fields; the selected FWHM values remain authoritative when exporting this step.') };
        end

        function legacy = toLegacySubject(obj, cfg, ctx)
            % toLegacySubject  Convert smoothing settings to a subject-level SPATIAL legacy step.
            %
            % Creates the Gaussian-smoothing branch consumed by nk_PerfSpatialChain before
            % CV-bound preprocessing starts.
            %
            % Inputs
            %   cfg.fwhm: complete vector of candidate Gaussian FWHM values in millimetres.
            %   cfg.legacySPATIAL: imported non-parameter spatial fields retained for round trips.
            %
            % Authority and flow
            %   cfg.fwhm is the sole authority for the Gaussian candidate values. The legacy
            %   nk_AddParam(...,'replace') configurator contract rebuilds the FWHM entry in the
            %   retained PX shell so all configurators use the same parameter authority.
            %
            % Scientific/state contract
            %   cubefwhm, PX.Px.Params and PX.opt represent the same candidate set. This producer
            %   preserves the legacy row-vector shape for cubefwhm/PX.Px.Params and one PX.opt row
            %   per candidate, establishing the identity consumed by training and replay.
            %
            % Materialization and performance
            %   Metadata-only conversion; no image data or files are read or materialized.
            %
            % Failure semantics
            %   Missing nk_AddParam or invalid parameter construction fails explicitly.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end %#ok<INUSD>
            cfg = obj.validateOrError(cfg);
            if isfield(cfg,'legacySPATIAL') && isstruct(cfg.legacySPATIAL) && ~isempty(fieldnames(cfg.legacySPATIAL))
                legacy = cfg.legacySPATIAL;
            else
                legacy = struct();
            end
            legacy.cmd = obj.Id;
            legacy.cubetype = uint8(4);
            legacy.cubefwhm = cfg.fwhm(:)';
            PX = [];
            if isfield(legacy,'PX') && isstruct(legacy.PX), PX = legacy.PX; end
            legacy.PX = nk_AddParam(legacy.cubefwhm, 'FWHM', 0, PX, 'replace');
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Gaussian smoothing config to legacy preprocessing fields.
            %   Validates/normalizes canonical cfg and materializes legacy branch 'SPATIAL' for the
            %   CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.

            legacy = obj.toLegacySubject(cfg, ctx);
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Gaussian smoothing settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isempty(legacy), return; end
            cfg.legacySPATIAL = legacy;
            if isfield(legacy,'cubefwhm') && ~isempty(legacy.cubefwhm), cfg.fwhm = legacy.cubefwhm; end
            cfg = obj.validateOrError(cfg);
        end


        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Fit or apply the Gaussian smoothing runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfSpatialChain,
            %   nm_preproc_spatial_param_from_context.

            % Programmatic single-step subject-spatial execution. Complex
            % multi-step subject-spatial chains should prefer
            % nm_preproc_scaffold_apply_subject_spatial, which delegates the
            % whole PREPROC.SPATIAL array to nk_PerfSpatialChain.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.
            if nargin < 5 || isempty(mode), mode = 'fit'; end %#ok<NASGU>
            if nargin < 6 || isempty(ctx), ctx = struct(); end
            cfg = struct();
            if isstruct(ctx) && isfield(ctx,'config') && isstruct(ctx.config), cfg = ctx.config; end
            if isempty(fieldnames(cfg)), cfg = obj.defaultConfig(ctx); end
            legacy = obj.toLegacySubject(cfg, ctx);
            PREPROC = struct('SPATIAL', legacy);
            Param = nm_preproc_spatial_param_from_context(Y, ctx);
            if exist('nk_PerfSpatialChain','file') ~= 2
                error([class(obj) ':missingBackend'], 'nk_PerfSpatialChain.m is required for programmatic spatial execution.');
            end
            [Yout, branchTable] = nk_PerfSpatialChain(Y, PREPROC, Param);
            trained = struct('moduleId',obj.Id, 'config',cfg, 'legacySPATIAL',legacy, ...
                'branchTable',branchTable, 'mode','deterministic_subject_spatial');
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Gaussian smoothing for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacySubject(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_Spatial_config')
                parentstr = obj.getParentString(ctx);
                brainmask = ctx.brainmask;
                Thresh = ctx.spatialThresh;
                SPATIAL = legacy; PX = [];
                if isfield(legacy,'PX'), PX = legacy.PX; end
                [SPATIAL, PX] = nk_Spatial_config(SPATIAL, PX, obj.getDefaultsFlag(ctx), parentstr, brainmask, Thresh);
                if ~isempty(SPATIAL), SPATIAL.PX = PX; end
                legacy = SPATIAL;
                cfg = obj.fromLegacy(legacy, ctx);
            end
            act = 0;
        end
    end

    methods (Access = private)
        function cfg = validateOrError(obj, cfg)
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMSmoothingModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end
    end
end

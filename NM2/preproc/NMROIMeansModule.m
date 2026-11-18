classdef NMROIMeansModule < NMPreprocModule
% NMROIMeansModule
% -------------------------------------------------------------------------
% Dual-stage adapter for ROI mean extraction. It can be placed either in the
% subject-specific image-space preprocessing sequence or in the CV-bound
% preprocessing chain, but only once globally.
% -------------------------------------------------------------------------

    methods
        function obj = NMROIMeansModule()
            % NMROIMeansModule  Construct the ROI mean extraction preprocessing adapter.
            %   Registers module id 'ROImeans' with legacy branch 'ROIMEANS' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('ROImeans','ROIMEANS','ROI mean extraction');
            obj.Category = 'imaging-preprocessing';
            obj.Aliases = {'roimeans','roi_means','roi'};
            obj.Capabilities.executionStages = {'subject','cv'};
            obj.Capabilities.imagingOnly = true;
            obj.Capabilities.requiresImageSpace = true;
            obj.Capabilities.isImageSpaceTerminal = true;
            obj.Capabilities.requiresSpatialFeatureExtractionAllowed = true;
            obj.Capabilities.spatialFeatureExtractionFlagEffect = 'disable';
            obj.Capabilities.invalidatesImageSpace = true;
            obj.Capabilities.isSpatialFeatureExtractor = true;
            obj.Capabilities.isDimensionalityReductionLike = true;
            obj.Capabilities.uniqueAcrossStages = true;
            obj.Capabilities.changesFeatureSpace = true;
            obj.Capabilities.legacySubjectTarget = 'PREPROC.SPATIAL';
            obj.Capabilities.legacyCVTarget = 'ACTPARAM';
            obj.Sequence.allowMultiple = false;
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for ROI mean extraction.
            %   Defines editable fields for the module that collapses voxel/image features into
            %   ROI-level means using a legacy spatial ROI configuration. The schema feeds
            %   defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Extract mean values from atlas-defined ROIs. The module can be applied either subject-wise ', ...
                'or within the CV-bound pipeline, but not in both stages simultaneously.'];
            spec.fields = { ...
                struct('name','atlasPath','type','file_path','default','','label','Atlas image path(s)', ...
                    'help','Select or import the atlas image used to define ROIs before running this step.'), ...
                struct('name','atlasDir','type','file_path','default','','label','Atlas directory', ...
                    'help','Directory containing the atlas resources used by this step.'), ...
                struct('name','complete','type','boolean','default',false,'label','ROI atlas import complete', ...
                    'help','Indicates whether atlas preparation for this step is complete.'), ...
                struct('name','legacyROIMEANS','type','struct','default',struct(),'label','Raw legacy ROIMEANS structure','uiHidden',true, ...
                    'help','Preserved imported ROIMEANS parameters for legacy configuration round trips.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Preserved imported PX parameters for legacy configuration round trips.') };
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert ROI mean extraction config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'ROIMEANS' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.legacyPX: preserves legacy PX parameters when a module cannot yet express every field canonically.

            cfg = obj.validateOrError(cfg);
            R = obj.configToROIMEANS(cfg);
            legacy = struct('cmd',obj.Id,'ROIMEANS',R);
            if isfield(cfg,'legacyPX') && isstruct(cfg.legacyPX) && ~isempty(fieldnames(cfg.legacyPX))
                legacy.PX = cfg.legacyPX;
            end
        end

        function legacy = toLegacySubject(obj, cfg, ctx)
            % toLegacySubject  Convert ROI-mean configuration to a subject-level legacy SPATIAL step.
            %   Materializes atlas/ROI settings for PREPROC.SPATIAL so image features can be
            %   collapsed before model training.

            act = obj.toLegacy(cfg, ctx);
            legacy = struct();
            legacy.cmd = obj.Id;
            legacy.cubetype = uint8(7);
            legacy.ROIMEANS = act.ROIMEANS;
            if isfield(act,'PX'), legacy.PX = act.PX; end
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy ROI mean extraction settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isempty(legacy), return; end
            if isfield(legacy,'ROIMEANS'), R = legacy.ROIMEANS; else, R = legacy; end
            cfg.legacyROIMEANS = R;
            if isfield(legacy,'PX') && isstruct(legacy.PX), cfg.legacyPX = legacy.PX; end
            if isfield(R,'atlas') && ~isempty(R.atlas), cfg.atlasPath = obj.anyToString(R.atlas); end
            if isfield(R,'AtlasDir') && ~isempty(R.AtlasDir), cfg.atlasDir = char(R.AtlasDir); end
            if isfield(R,'completeflag') && ~isempty(R.completeflag), cfg.complete = logical(R.completeflag); end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure ROI mean extraction for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('cv_ROImeans_config')
                parentstr = obj.getParentString(ctx);
                brainmask = ctx.brainmask;
                Thresh = ctx.spatialThresh;
                R = legacy.ROIMEANS;
                act = 1;
                while act > 0
                    [R, act] = cv_ROImeans_config(R, brainmask, Thresh, parentstr);
                end
                legacy = struct('cmd',obj.Id,'ROIMEANS',R);
                cfg = obj.fromLegacy(legacy, ctx);
            else
                act = 0;
            end
        end
    end

    methods (Access = private)
        function cfg = validateOrError(obj, cfg)
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMROIMeansModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end

        function R = configToROIMEANS(~, cfg)
            if isfield(cfg,'legacyROIMEANS') && isstruct(cfg.legacyROIMEANS) && ~isempty(fieldnames(cfg.legacyROIMEANS))
                R = cfg.legacyROIMEANS;
            else
                R = struct();
            end
            if isfield(cfg,'atlasPath') && ~isempty(cfg.atlasPath), R.atlas = char(cfg.atlasPath); end
            if isfield(cfg,'atlasDir') && ~isempty(cfg.atlasDir), R.AtlasDir = char(cfg.atlasDir); end
            if isfield(cfg,'complete'), R.completeflag = logical(cfg.complete); end
        end

        function s = anyToString(~, x)
            if ischar(x), s = strtrim(x); return; end
            if isstring(x), s = strjoin(cellstr(x(:))', ', '); return; end
            if iscell(x), s = strjoin(cellfun(@char, x(:)', 'UniformOutput', false), ', '); return; end
            s = '';
        end
    end
end

classdef NMExtDimModule < NMPreprocModule
% NMExtDimModule
% -------------------------------------------------------------------------
% Child module for extracting subspaces/components from a previously fitted
% dimensionality-reduction model. This step owns the dimensionality
% optimization shelf and prevents unnecessary recomputation of the projection.
% -------------------------------------------------------------------------

    methods
        function obj = NMExtDimModule()
            % NMExtDimModule  Construct the Extract dimensions preprocessing adapter.
            %   Registers module id 'extdim' with legacy branch 'EXTDIM' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('extdim','EXTDIM','Extract dimensions');
            obj.Capabilities.requiresLabels = false;
            obj.Capabilities.usesLabels = false;
            obj.Capabilities.changesFeatureSpace = true;
            obj.Capabilities.spatialFeatureExtractionFlagEffect = 'disable';
            obj.Capabilities.invalidatesImageSpace = true;
            obj.Capabilities.isDimensionalityReductionLike = true;
            obj.Capabilities.supportsHyperparameters = true;
            obj.Capabilities.supportsMissingData = false;
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Extract dimensions.
            %   Defines editable fields for the module that extracts a selected subset of dimensions
            %   from a previously fitted dimensionality-reduction model. The schema feeds
            %   defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Extract one or more dimensionalities from the immediately preceding dimensionality-reduction or ', ...
                'variance-component projection. Candidate dimensionalities can be optimized without refitting the projection for every candidate.'];
            spec.fields = { ...
                struct('name','redMode','type','enum','default','PCA','label','Parent reduction mode', ...
                    'values',{{'PCA','t-SNE','SparsePCA','LDA','GDA','PLS','fastICA','RobPCA','FactorAnalysis','NNMF','NeNMF','LPP','LLTSA','LMNN','NCA','Laplacian','LLE'}}, ...
                    'help','Usually inherited from the immediately preceding reducedim/remvarcomp step.'), ...
                struct('name','percMode','type','enum','default','absolute','label','Extraction dimensionality mode', ...
                    'values',{{'absolute','percentage','energy'}}, ...
                    'help','Interpret extracted dimensionalities as absolute component counts, percentage, or retained energy.'), ...
                struct('name','scheduleMode','type','enum','default','user','label','Extraction schedule mode', ...
                    'values',{{'user','linear','geometric','power'}}, ...
                    'help','Enter candidate dimensions directly or generate a linear, geometric, or power-law sequence.'), ...
                struct('name','dims','type','numeric_vector','default',10,'label','User-defined extracted dimensionalities', ...
                    'allowEmpty',false,'visibleIf',struct('field','scheduleMode','equals','user'), ...
                    'help','One or more extraction dimensions used when the schedule mode is user.'), ...
                struct('name','rangeMin','type','number','default',1,'label','Schedule minimum', ...
                    'visibleIf',struct('field','scheduleMode','equals','linear'), ...
                    'help','First dimension candidate for the linear extraction schedule.'), ...
                struct('name','rangeMax','type','number','default',10,'label','Schedule maximum', ...
                    'visibleIf',struct('field','scheduleMode','equals','linear'), ...
                    'help','Last dimension candidate for the linear extraction schedule.'), ...
                struct('name','rangeN','type','integer','default',10,'min',1,'label','Number of scheduled values', ...
                    'visibleIf',struct('field','scheduleMode','equals','linear'), ...
                    'help','Number of candidates in the linear extraction schedule.'), ...
                struct('name','geoMin','type','number','default',1,'min',eps,'label','Geometric minimum', ...
                    'visibleIf',struct('field','scheduleMode','equals','geometric'), ...
                    'help','Positive starting dimension for the geometric extraction schedule.'), ...
                struct('name','geoMax','type','number','default',10,'min',eps,'label','Geometric maximum', ...
                    'visibleIf',struct('field','scheduleMode','equals','geometric'), ...
                    'help','Positive ending dimension for the geometric extraction schedule.'), ...
                struct('name','geoN','type','integer','default',10,'min',1,'label','Number of geometric values', ...
                    'visibleIf',struct('field','scheduleMode','equals','geometric'), ...
                    'help','Number of candidates in the geometric extraction schedule.'), ...
                struct('name','powerMin','type','number','default',1,'label','Power-law minimum', ...
                    'visibleIf',struct('field','scheduleMode','equals','power'), ...
                    'help','Starting dimension for the power-law extraction schedule.'), ...
                struct('name','powerMax','type','number','default',10,'label','Power-law maximum', ...
                    'visibleIf',struct('field','scheduleMode','equals','power'), ...
                    'help','Ending dimension for the power-law extraction schedule.'), ...
                struct('name','powerN','type','integer','default',10,'min',1,'label','Number of power-law values', ...
                    'visibleIf',struct('field','scheduleMode','equals','power'), ...
                    'help','Number of candidates in the power-law extraction schedule.'), ...
                struct('name','powerAlpha','type','number','default',2,'min',eps,'label','Power-law alpha', ...
                    'visibleIf',struct('field','scheduleMode','equals','power'), ...
                    'help','Exponent controlling the spacing of candidates in the power-law schedule.'), ...
                struct('name','legacyEXTDIM','type','struct','default',struct(),'label','Raw legacy EXTDIM structure','uiHidden',true, ...
                    'help','Imported EXTDIM configuration retained for legacy parameter round trips.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Imported PX optimization shelf retained for legacy dimension-candidate round trips.') };
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Extract dimensions config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'EXTDIM' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.legacyEXTDIM: stores the normalized legacy extdim value in the module configuration.
            % cfg.percMode: stores the normalized perc mode value in the module configuration.
            % cfg.redMode: stores the normalized red mode value in the module configuration.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            cfg = obj.parseConfig(cfg);
            EXTDIM = struct();
            if isfield(cfg,'legacyEXTDIM') && isstruct(cfg.legacyEXTDIM) && ~isempty(fieldnames(cfg.legacyEXTDIM))
                EXTDIM = cfg.legacyEXTDIM;
            end
            EXTDIM.RedMode = char(cfg.redMode);
            EXTDIM.PercMode = obj.percModeCode(cfg.percMode);
            EXTDIM.dims = obj.computeDims(cfg);
            PX = obj.pxAdd([], [], [], 1, 'reset');
            PX = obj.pxAdd(PX, EXTDIM.dims, 'dimensions', 1, '');
            legacy = struct('cmd',obj.Id,'EXTDIM',EXTDIM,'PX',PX);

            % Important: do not collapse multi-valued EXTDIM.dims here.
            % In the legacy NM execution path, toLegacy/nk_GenPreprocSequence
            % stores the complete PX.opt range in InputParam.P{i}.opt.
            % nk_PerfPreprocessObj_core then selects the active row via
            % ActParam.opt = O(l,:) and act_extdim copies that scalar/current
            % value to InputParam.P{i}.opt before nk_PerfExtDimObj is called.
            % Collapsing or validating scalar-ness here breaks that canonical
            % hyperparameter-shelf logic.  For the lightweight direct
            % execute() path only, scalar IN.opt is attached below after
            % toLegacy(), because that path does not go through the core loop.
            legacy.Params_desc = 'dimensions';
            if numel(EXTDIM.dims) == 1
                legacy.opt = EXTDIM.dims(1);
            end
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Extract dimensions settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isempty(legacy), return; end
            if isfield(legacy,'EXTDIM'), EXTDIM = legacy.EXTDIM; else, EXTDIM = legacy; end
            cfg.legacyEXTDIM = EXTDIM;
            if isfield(legacy,'PX') && isstruct(legacy.PX) && ~isempty(legacy.PX)
                cfg.legacyPX = legacy.PX;
            else
                cfg.legacyPX = struct();
            end
            if isfield(EXTDIM,'RedMode'), cfg.redMode = char(EXTDIM.RedMode); end
            if isfield(EXTDIM,'PercMode'), cfg.percMode = obj.percModeName(EXTDIM.PercMode); end
            if isfield(EXTDIM,'dims'), cfg.dims = EXTDIM.dims; cfg.scheduleMode = 'user'; end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Extract dimensions for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_ExtDim_config')
                parentstr = obj.getParentString(ctx);
                dims = legacy.EXTDIM.dims;
                PercMode = legacy.EXTDIM.PercMode;
                RedMode = legacy.EXTDIM.RedMode;
                act = 1;
                while act > 0
                    [dims, PercMode, act] = nk_ExtDim_config(RedMode, PercMode, dims, 0, parentstr);
                end
                legacy.EXTDIM.dims = dims;
                legacy.EXTDIM.PercMode = PercMode;
                legacy.EXTDIM.RedMode = RedMode;
                legacy.PX = obj.pxAdd([], [], [], 1, 'reset');
                legacy.PX = obj.pxAdd(legacy.PX, dims, 'dimensions', 1, '');
                cfg = obj.fromLegacy(legacy, ctx);
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx)
            % execute  Fit or apply the Extract dimensions runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfExtDimObj.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end
            if exist('nk_PerfExtDimObj','file') ~= 2
                error('NMExtDimModule:missingBackend','nk_PerfExtDimObj is not on the MATLAB path.');
            end
            switch lower(char(mode))
                case 'fit'
                    cfg = obj.defaultConfig();
                    if isfield(ctx,'config'), cfg = ctx.config; end
                    legacy = obj.toLegacy(cfg, ctx);
                    % nk_PerfExtDimObj expects the legacy wrapper structure,
                    % not only legacy.EXTDIM.  The wrapper must contain
                    % IN.EXTDIM plus the parent projection model in IN.mpp.
                    IN = legacy;
                    if ~isfield(IN,'opt') || isempty(IN.opt)
                        % Lightweight direct execution path: no
                        % nk_PerfPreprocessObj_core hyperparameter loop is
                        % present, so a single extraction dimensionality must be
                        % available. Multi-valued schedules should be executed
                        % through the legacy-core/scaffold path.
                        IN.opt = obj.runtimeOptFromDims(IN.EXTDIM.dims);
                    end
                    IN = obj.attachParentProjectionModel(IN, ctx);
                    [Yout, trained] = nk_PerfExtDimObj(Y, IN);
                case 'transform'
                    if isempty(trained)
                        error('NMExtDimModule:noTrained','extdim transform requires trained EXTDIM parameters.');
                    end
                    [Yout, trained] = nk_PerfExtDimObj(Y, trained);
                otherwise
                    error('NMExtDimModule:badMode','Unknown execution mode: %s', char(mode));
            end
        end
    end

    methods (Access = private)
        function IN = attachParentProjectionModel(~, IN, ctx)
            % attachParentProjectionModel
            % -----------------------------------------------------------------
            % ExtDim is a child of reducedim/remvarcomp. It does not learn a new
            % projection model; it extracts dimensions from the immediately
            % preceding trained projection.  The legacy backend expects this
            % projection at IN.mpp and the extraction settings at IN.EXTDIM.
            % -----------------------------------------------------------------
            if isfield(IN,'mpp') && ~isempty(IN.mpp)
                return;
            end

            if ~isfield(ctx,'previousTrainedSteps') || isempty(ctx.previousTrainedSteps)
                error('NMExtDimModule:noParentProjection', ...
                    ['ExtDim requires an immediately preceding reducedim/remvarcomp ', ...
                     'step with a trained projection model. No previous trained ', ...
                     'step was available.']);
            end

            prev = ctx.previousTrainedSteps{end};
            if ~isfield(prev,'trained') || ~isstruct(prev.trained)
                error('NMExtDimModule:noParentProjection', ...
                    'The previous step has no trained parameter structure.');
            end

            tr = prev.trained;
            if isfield(tr,'mpp') && ~isempty(tr.mpp)
                IN.mpp = tr.mpp;
                return;
            end

            % Defensive fallback for wrappers that store the reduction object
            % under nested legacy fields.
            if isfield(tr,'DR') && isstruct(tr.DR) && isfield(tr.DR,'mpp') && ~isempty(tr.DR.mpp)
                IN.mpp = tr.DR.mpp;
                return;
            end
            if isfield(tr,'REDUCEDIM') && isstruct(tr.REDUCEDIM) && isfield(tr.REDUCEDIM,'mpp') && ~isempty(tr.REDUCEDIM.mpp)
                IN.mpp = tr.REDUCEDIM.mpp;
                return;
            end
            if isfield(tr,'REMVARCOMP') && isstruct(tr.REMVARCOMP) && isfield(tr.REMVARCOMP,'mpp') && ~isempty(tr.REMVARCOMP.mpp)
                IN.mpp = tr.REMVARCOMP.mpp;
                return;
            end

            error('NMExtDimModule:noParentProjection', ...
                ['The previous step did not expose a trained projection model ', ...
                 'in a field named mpp. ExtDim cannot be applied.']);
        end

        function dims = computeDims(obj, cfg)
            switch lower(char(cfg.scheduleMode))
                case 'linear'
                    dims = linspace(cfg.rangeMin, cfg.rangeMax, max(1, round(cfg.rangeN)));
                case 'geometric'
                    dims = logspace(log10(cfg.geoMin), log10(cfg.geoMax), max(1, round(cfg.geoN)));
                case 'power'
                    t = linspace(0,1,max(1,round(cfg.powerN)));
                    dims = cfg.powerMin + (cfg.powerMax - cfg.powerMin) .* (t .^ cfg.powerAlpha);
                otherwise
                    dims = cfg.dims;
            end
            if obj.percModeCode(cfg.percMode) == 1
                dims = unique(max(1, round(dims(:)')));
            else
                dims = max(0, min(1, dims(:)'));
            end
        end

        function code = percModeCode(~, name)
            if isnumeric(name), code = name; return; end
            switch lower(char(name))
                case 'percentage', code = 2;
                case 'energy',     code = 3;
                otherwise,         code = 1;
            end
        end

        function name = percModeName(~, code)
            switch code
                case 2, name = 'percentage';
                case 3, name = 'energy';
                otherwise, name = 'absolute';
            end
        end

        function opt = runtimeOptFromDims(~, dims)
            opt = dims;
            if isempty(opt)
                error('NMExtDimModule:missingOpt', ...
                    'ExtDim requires a current extraction dimensionality in EXTDIM.dims.');
            end
            if numel(opt) ~= 1
                error('NMExtDimModule:unexpandedHyperparameter', ...
                    ['ExtDim received multiple extraction dimensionalities (%s). ', ...
                     'This step must be executed after hyperparameter expansion, ', ...
                     'so that exactly one current value is mapped to IN.opt.'], ...
                     mat2str(opt));
            end
            opt = opt(1);
        end

        function cfg = validateOrError(obj, cfg)
            if isfield(cfg,'legacyPX') && isempty(cfg.legacyPX) && ~isstruct(cfg.legacyPX), cfg.legacyPX = struct(); end
            if isfield(cfg,'legacyEXTDIM') && isempty(cfg.legacyEXTDIM) && ~isstruct(cfg.legacyEXTDIM), cfg.legacyEXTDIM = struct(); end
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMExtDimModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end
    end
end

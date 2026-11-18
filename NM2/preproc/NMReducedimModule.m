classdef NMReducedimModule < NMPreprocModule
% NMReducedimModule
% -------------------------------------------------------------------------
% Canonical adapter for NeuroMiner dimensionality reduction.  The module
% fits a reduction model; the following extdim child should own the
% dimensionality optimization grid whenever several extracted dimensionalities
% are evaluated.
% -------------------------------------------------------------------------

    methods
        function obj = NMReducedimModule()
            % NMReducedimModule  Construct the Dimensionality reduction preprocessing adapter.
            %   Registers module id 'reducedim' with legacy branch 'DR' and sets capability/sequence
            %   flags used by NMModuleRegistry, NMPreprocRuleSet, NMPreprocSequence, and UI/API
            %   schema generation.

            obj@NMPreprocModule('reducedim','DR','Dimensionality reduction');
            obj.Capabilities.requiresLabels = false;
            obj.Capabilities.usesLabels = true;
            obj.Capabilities.changesFeatureSpace = true;
            obj.Capabilities.spatialFeatureExtractionFlagEffect = 'disable';
            obj.Capabilities.invalidatesImageSpace = true;
            obj.Capabilities.isDimensionalityReductionLike = true;
            obj.Capabilities.supportsHyperparameters = true;
            obj.Capabilities.supportsMissingData = false;
        end

        function spec = configSpec(obj, ctx)
            % configSpec  Return the canonical API/UI schema for Dimensionality reduction.
            %   Defines editable fields for the module that fits or applies dimensionality-reduction
            %   models such as PCA/PLS/ICA through the legacy backend. The schema feeds
            %   defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            if nargin < 2, ctx = struct(); end
            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Fit a dimensionality-reduction model within the training fold. ', ...
                'For dimensionality optimization, fit one sufficiently large mapping here and let the following extraction step evaluate alternative dimensionalities.'];
            methods = NMDimRedSubconfigLibrary.methodIds();
            spec.fields = { ...
                struct('name','method','type','enum','default','PCA','label','Dimensionality-reduction method', ...
                    'values',{methods}, ...
                    'help','Choose the dimensionality-reduction algorithm; methodParams contains its existing nested schema.'), ...
                struct('name','fitDim','type','numeric_vector','default',0.8,'label','Fitted projection dimensionality', ...
                    'allowEmpty',false, ...
                    'help','This should usually be scalar. If extdim follows, set this to the maximum/sufficient projection size and optimize extracted dimensions in extdim.'), ...
                struct('name','percMode','type','enum','default','energy','label','Fitted dimensionality mode', ...
                    'values',{{'absolute','percentage','energy'}}, ...
                    'help','Choose a fixed number of components, a percentage of available components, or an explained-energy target. Percentage and energy modes are available for PCA-based methods.'), ...
                struct('name','templateProcrustes','type','boolean','default',false,'label','Use Procrustes template alignment', ...
                    'help','Apply Procrustes alignment when generating the dimensionality-reduction template.'), ...
                struct('name','useAllTrainingForTemplate','type','boolean','default',false,'label','Use all training data for template generation', ...
                    'help','Use the complete available training set to construct the projection template.'), ...
                struct('name','calibUse','type','integer','default',2,'label','Calibration-data use flag','uiHidden',true, ...
                    'help','Inherited calibration-data code for template fitting; 1 selects calibration data and 2 selects training data.'), ...
                struct('name','methodParams','type','subconfig','default',struct(),'label','Method-specific parameters', ...
                    'subconfigSelector','method', ...
                    'subconfigSpecs',NMDimRedSubconfigLibrary.specs(ctx), ...
                    'help','Opens a separate nested page for the selected dimensionality-reduction method.'), ...
                struct('name','legacyDR','type','struct','default',struct(),'label','Raw legacy DR structure','uiHidden',true, ...
                    'help','Imported dimensionality-reduction settings retained for legacy configuration round trips.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Imported PX optimization parameters retained for legacy configuration round trips.') };
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Dimensionality reduction config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'DR' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.calibUse: stores the normalized calib use value in the module configuration.
            % cfg.fitDim: stores the normalized fit dim value in the module configuration.
            % cfg.legacyDR: stores the normalized legacy dr value in the module configuration.
            % cfg.method: stores the selected algorithmic method inside a normalized module configuration.
            % cfg.percMode: stores the normalized perc mode value in the module configuration.
            % cfg.templateProcrustes: stores the normalized template procrustes value in the module configuration.
            % cfg.useAllTrainingForTemplate: stores the normalized use all training for template value in the module configuration.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            cfg = obj.parseConfig(cfg);
            cfg = obj.normalizeNested(cfg, ctx);

            if isfield(cfg,'legacyDR') && isstruct(cfg.legacyDR) && ~isempty(fieldnames(cfg.legacyDR))
                DR = cfg.legacyDR;
            else
                DR = struct();
            end
            cfg.method = NMDimRedSubconfigLibrary.canonicalMethod(cfg.method);
            DR.RedMode = char(cfg.method);
            DR.dims = cfg.fitDim;
            DR.PercMode = obj.percModeCode(cfg.percMode);
            DR.CALIBUSE = cfg.calibUse;

            pxAddFcn = @(PX0, vals, desc, typ, mode) obj.pxAdd(PX0, vals, desc, typ, mode);
            [DR, PX] = NMDimRedSubconfigLibrary.applyToLegacy(DR, cfg, ctx, pxAddFcn);

            % Legacy main configurator adds the dimensionality parameter after
            % method-specific settings. With a scalar fitDim this creates a
            % single shelf branch; with a vector it preserves legacy behavior.
            PX = obj.pxAdd(PX, DR.dims, 'dimensions', 1, '');
            DR.EXTOPT = numel(DR.dims) < 2;
            DR.CALIBUSE = cfg.calibUse;

            legacy = struct('cmd',obj.Id,'DR',DR,'PX',PX, ...
                'TEMPLPROC',logical(cfg.templateProcrustes), ...
                'USEALL',logical(cfg.useAllTrainingForTemplate));
        end

        function cfg = fromLegacy(obj, legacy, ctx)
            % fromLegacy  Import legacy Dimensionality reduction settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            if nargin < 3, ctx = struct(); end
            cfg = obj.defaultConfig(ctx);
            if isempty(legacy), return; end
            if isfield(legacy,'DR'), DR = legacy.DR; else, DR = legacy; end
            cfg.legacyDR = DR;
            if isfield(legacy,'PX') && isstruct(legacy.PX) && ~isempty(legacy.PX)
                cfg.legacyPX = legacy.PX;
            else
                cfg.legacyPX = struct();
            end
            if isfield(DR,'RedMode') && ~isempty(DR.RedMode), cfg.method = char(DR.RedMode); end
            if isfield(DR,'dims'), cfg.fitDim = DR.dims; end
            if isfield(DR,'PercMode'), cfg.percMode = obj.percModeName(DR.PercMode); end
            if isfield(DR,'CALIBUSE'), cfg.calibUse = DR.CALIBUSE; end
            if isfield(legacy,'TEMPLPROC'), cfg.templateProcrustes = logical(legacy.TEMPLPROC); end
            if isfield(legacy,'USEALL'), cfg.useAllTrainingForTemplate = logical(legacy.USEALL); end
            try
                cfg.methodParams = NMDimRedSubconfigLibrary.fromLegacy(cfg.method, DR, ctx);
            catch ME
                warning('NMReducedimModule:subconfigImport', ...
                    'Could not import nested dimensionality-reduction subconfig for %s: %s', cfg.method, ME.message);
                cfg.methodParams = struct();
            end
            cfg = obj.validateOrError(cfg, ctx);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Dimensionality reduction for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_DimRed_main_config')
                parentstr = obj.getParentString(ctx);
                DR = legacy.DR; PX = legacy.PX;
                TEMPLPROC = legacy.TEMPLPROC; USEALL = legacy.USEALL;
                act = 1;
                while act > 0
                    [DR, PX, TEMPLPROC, USEALL, act] = nk_DimRed_main_config(DR, PX, TEMPLPROC, USEALL, parentstr);
                end
                if ~isempty(DR)
                    legacy = struct('cmd',obj.Id,'DR',DR,'PX',PX,'TEMPLPROC',TEMPLPROC,'USEALL',USEALL);
                    cfg = obj.fromLegacy(legacy, ctx);
                end
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx)
            % execute  Fit or apply the Dimensionality reduction runtime transform.
            %
            % Uses ctx.config when supplied, translates it to legacy settings, and delegates
            % fit/transform to the legacy backend while returning Yout and trained state. Direct
            % execution/configuration path references nk_PerfRedObj.
            %
            % ctx.labels: exposes the labels execution-context value to preprocessing/runtime code.
            % ctx.NM: provides the current NeuroMiner structure to preprocessing execution helpers without direct global access.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end
            switch lower(char(mode))
                case 'fit'
                    cfg = obj.defaultConfig(ctx);
                    if isfield(ctx,'config'), cfg = ctx.config; end
                    legacy = obj.toLegacy(cfg, ctx);
                    IN = legacy;
                    IN.TrX = Y;
                    if isfield(ctx,'NM') && isstruct(ctx.NM) && isfield(ctx.NM,'label')
                        IN.DR.labels = ctx.NM.label;
                    elseif isfield(ctx,'labels')
                        IN.DR.labels = ctx.labels;
                    else
                        IN.DR.labels = ones(size(Y,1),1);
                    end
                    if exist('nk_PerfRedObj','file') ~= 2
                        error('NMReducedimModule:missingBackend','nk_PerfRedObj is not on the MATLAB path.');
                    end
                    [Yout, trained] = nk_PerfRedObj(Y, IN);
                    trained.mappedX = Yout;
                case 'transform'
                    if isempty(trained)
                        error('NMReducedimModule:noTrained','reducedim transform requires trained reduction parameters.');
                    end
                    if exist('nk_PerfRedObj','file') ~= 2
                        error('NMReducedimModule:missingBackend','nk_PerfRedObj is not on the MATLAB path.');
                    end
                    Yout = nk_PerfRedObj(Y, trained);
                otherwise
                    error('NMReducedimModule:badMode','Unknown execution mode: %s', char(mode));
            end
        end
    end

    methods (Access = private)
        function cfg = normalizeNested(obj, cfg, ctx) %#ok<INUSL>
            if ~isfield(cfg,'methodParams') || ~isstruct(cfg.methodParams)
                cfg.methodParams = struct();
            end
            cfg.methodParams = NMDimRedSubconfigLibrary.normalizeParams(cfg.method, cfg.methodParams, ctx);
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

        function cfg = validateOrError(obj, cfg, ctx)
            if nargin < 3, ctx = struct(); end
            if isfield(cfg,'legacyPX') && isempty(cfg.legacyPX) && ~isstruct(cfg.legacyPX), cfg.legacyPX = struct(); end
            if isfield(cfg,'legacyDR') && isempty(cfg.legacyDR) && ~isstruct(cfg.legacyDR), cfg.legacyDR = struct(); end
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok, error('NMReducedimModule:invalidConfig','%s',strjoin(report.errors,newline)); end
            cfg = obj.normalizeNested(cfg, ctx);
        end
    end
end

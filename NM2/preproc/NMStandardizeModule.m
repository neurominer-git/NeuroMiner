classdef NMStandardizeModule < NMPreprocModule
% NMStandardizeModule
% Canonical adapter for NeuroMiner standardization preprocessing.
%
% Backward-compatibility note:
% nk_Standardize_config writes a comparatively rich ACTPARAM struct:
%   METHOD, sIND, dIND, WINSOPT, IQRFUN, zerooutflag, CALIBUSE, PX, cmd
% The public/canonical config is intentionally simpler, but toLegacy() must
% still emit the complete legacy shape because nk_GenPreprocSequence and
% nk_PerfPreprocessObj_core expect these fields to exist.

    methods
        function obj = NMStandardizeModule()
            % NMStandardizeModule  Construct the Standardization preprocessing adapter.
            %   Registers module id 'standardize' with legacy branch 'STANDARD' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('standardize','STANDARD','Standardization');
        end

        function spec = configSpec(obj, ctx)
            % configSpec  Return the canonical API/UI schema for Standardization.
            %   Defines editable fields for the module that standardizes predictor values using
            %   fold-estimated centering/scaling rules. The schema feeds defaultConfig,
            %   validateConfig, browser rendering, CLI/API help, and RAG documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = 'Center and scale features using parameters estimated from the training fold.';
            spec.fields = { ...
                struct('name','method','type','enum','default','median','label','Estimator','values',{{'median','mean','mean_center','l1_median_center','qn','sn'}}, ...
                    'help','Median/mean standardization, mean or L1-median centering, or robust Qn/Sn standardization.'), ...
                struct('name','useIQR','type','boolean','default',true,'label','Use IQR for median standardization', ...
                    'help','Use the interquartile range instead of the alternative spread estimator for median-based standardization.'), ...
                struct('name','winsorizeSD','type','numeric_vector','default',[],'allowEmpty',true,'label','Winsorization limits in SD units', ...
                    'help','Optional winsorization cutoffs expressed in standard deviation units; empty disables this setting.'), ...
                struct('name','zeroOutNonFinite','type','boolean','default',true,'label','Zero-out completely non-finite features', ...
                    'help','Replace non-finite standardized values with zero according to the legacy zerooutflag setting.'), ...
                struct('name','sourceIndex','type','covariate_indices','default',[],'allowEmpty',true,'multiple',true,'label','Source covariates', ...
                    'help','Select covariate columns used to define the subgroup or reference set from which the standardization model is estimated.'), ...
                struct('name','destinationIndex','type','covariate_indices','default',[],'allowEmpty',true,'multiple',true,'label','Destination covariates', ...
                    'help','Select covariate columns defining the subgroup or cases to which the learned standardization model is applied.'), ...
                struct('name','sourceIndexVar','type','workspace_var','default','','label','Optional source-index workspace variable','uiHidden',true,'help','Legacy/deferred source-index variable reference retained for imported configurations.'), ...
                struct('name','destinationIndexVar','type','workspace_var','default','','label','Optional destination-index workspace variable','uiHidden',true, ...
                    'help','Retained legacy workspace-variable reference for selecting destination covariate indices.'), ...
                struct('name','calibrationUse','type','integer','default',2,'min',1,'max',2,'uiHidden',true,'label','Calibration data use code','help','Silent legacy CALIBUSE code. 1 = calibration data, 2 = training data. Default 2 = do not use calibration data.') };
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert Standardization config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'STANDARD' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.calibrationUse: stores the normalized calibration use value in the module configuration.
            % cfg.method: stores the selected algorithmic method inside a normalized module configuration.
            % cfg.useIQR: stores the normalized use iqr value in the module configuration.
            % cfg.winsorizeSD: stores the normalized winsorize sd value in the module configuration.
            % cfg.zeroOutNonFinite: stores the normalized zero out non finite value in the module configuration.

            cfg = obj.parseConfig(cfg);

            L = struct();
            L.METHOD      = obj.methodToLegacy(cfg.method);
            L.sIND        = obj.resolveIndexField(cfg, 'sourceIndex', 'sourceIndexVar');
            L.dIND        = obj.resolveIndexField(cfg, 'destinationIndex', 'destinationIndexVar');
            L.WINSOPT     = cfg.winsorizeSD;
            L.IQRFUN      = obj.boolToLegacyYesNo(cfg.useIQR);     % legacy: 1=yes, 2=no
            L.zerooutflag = obj.boolToLegacyYesNo(cfg.zeroOutNonFinite);
            L.CALIBUSE    = cfg.calibrationUse;
            L.PX          = obj.buildPX(L.WINSOPT);
            L.cmd         = obj.Id;

            legacy = L;
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Standardization settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            L = legacy;
            if isfield(L,'STANDARD'), L = L.STANDARD; end

            if isfield(L,'METHOD'),      cfg.method = obj.methodFromLegacy(L.METHOD); end
            if isfield(L,'IQRFUN'),      cfg.useIQR = obj.legacyYesNoToBool(L.IQRFUN,true); end
            if isfield(L,'WINSOPT'),     cfg.winsorizeSD = L.WINSOPT; end
            if isfield(L,'zerooutflag'), cfg.zeroOutNonFinite = obj.legacyYesNoToBool(L.zerooutflag,true); end
            if isfield(L,'CALIBUSE') && ~isempty(L.CALIBUSE), cfg.calibrationUse = L.CALIBUSE; end

            if isfield(L,'sIND') && ~isempty(L.sIND)
                if isnumeric(L.sIND)
                    cfg.sourceIndex = L.sIND;
                elseif ischar(L.sIND) || isstring(L.sIND)
                    cfg.sourceIndexVar = char(L.sIND);
                end
            end
            if isfield(L,'dIND') && ~isempty(L.dIND)
                if isnumeric(L.dIND)
                    cfg.destinationIndex = L.dIND;
                elseif ischar(L.dIND) || isstring(L.dIND)
                    cfg.destinationIndexVar = char(L.dIND);
                end
            end

            % Preserve original PX if the legacy config was imported. This
            % avoids losing older hyperparameter-chain metadata on a no-op
            % import/export round-trip.
            if isfield(L,'PX')
                cfg.legacyPX = L.PX;
            end

            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Standardization for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_Standardize_config')
                [legacy, act] = nk_Standardize_config(legacy, obj.getParentString(ctx), obj.getDefaultsFlag(ctx));
                legacy.cmd = obj.Id;
                cfg = obj.fromLegacy(legacy, ctx);
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Fit or apply the Standardization runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfStandardizeObj.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end %#ok<NASGU>
            if nargin < 3 || isempty(trained)
                cfg = obj.defaultConfig();
                if isfield(ctx,'config'), cfg = ctx.config; end
                legacy = obj.toLegacy(cfg, ctx);
                legacy.method = legacy.METHOD;
                [Yout, trained] = nk_PerfStandardizeObj(Y, legacy);
            else
                trained.trained = true;
                Yout = nk_PerfStandardizeObj(Y, trained);
            end
        end
    end

    methods (Access = private)
        function s = methodToLegacy(~, m)
            switch lower(char(m))
                case 'median',           s = 'standardization using median';
                case 'mean',             s = 'standardization using mean';
                case 'mean_center',      s = 'mean-centering';
                case 'l1_median_center', s = 'l1-median centering';
                case 'qn',               s = 'qn-standardization';
                case 'sn',               s = 'sn-standardization';
                otherwise,               s = char(m);
            end
        end

        function m = methodFromLegacy(~, s)
            switch lower(char(s))
                case 'standardization using median', m = 'median';
                case 'standardization using mean',   m = 'mean';
                case 'mean-centering',               m = 'mean_center';
                case 'l1-median centering',          m = 'l1_median_center';
                case 'qn-standardization',           m = 'qn';
                case 'sn-standardization',           m = 'sn';
                otherwise,                           m = 'median';
            end
        end

        function ind = resolveIndexField(~, cfg, numericField, varField)
            ind = [];
            if isfield(cfg, numericField) && ~isempty(cfg.(numericField))
                ind = cfg.(numericField);
                return;
            end
            if isfield(cfg, varField) && ~isempty(cfg.(varField))
                % Keep the variable name only as an explicit deferred
                % reference. The browser UI does not evaluate MATLAB code.
                % The orchestrator can later resolve this before execution.
                ind = cfg.(varField);
            end
        end

        function PX = buildPX(obj, winsopt)
            % Reproduce nk_Standardize_config semantics exactly for the
            % winsorization hyperparameter shelf. Do not synthesize PX by hand:
            % PX.Px and PX.opt are consumed later when NeuroMiner builds the
            % preprocessing/ML hyperparameter cube.
            if ~obj.functionExists('nk_AddParam')
                error('NMStandardizeModule:missingNkAddParam', ...
                    ['nk_AddParam is required to export the standardization ', ...
                     'configuration because PX defines the winsorization ', ...
                     'hyperparameter shelf. Add the NeuroMiner config helpers ', ...
                     'to the MATLAB path.']);
            end

            if isempty(winsopt)
                PX = nk_AddParam([], 'winsopt', 1, [], 'reset');
            else
                PX = nk_AddParam(winsopt, 'winsopt', 1, []);
            end

            % nk_Standardize_config performs this final normalization before
            % saving STANDARD.PX. Keep that behavior when allcomb is available;
            % otherwise leave the nk_AddParam-generated opt field unchanged.
            if isfield(PX,'Px') && isfield(PX.Px,'Params') && ~isempty(PX.Px.Params)
                if obj.functionExists('allcomb')
                    PX.opt = allcomb(PX.Px.Params,'matlab');
                end
            else
                PX.opt = [];
            end
        end

        function cfg = validateOrError(obj, cfg)
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok
                error('NMStandardizeModule:invalidConfig','%s',strjoin(report.errors,newline));
            end
        end
    end
end

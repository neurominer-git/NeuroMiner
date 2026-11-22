classdef NMCorrectNuisModule < NMPreprocModule
% NMCorrectNuisModule
% -------------------------------------------------------------------------
% Canonical adapter for NeuroMiner's nuisance-correction preprocessing step
% (legacy cmd: correctnuis; legacy configurator: nk_UnivCorrProcs_config).
%
% The module intentionally preserves legacy ACTPARAM semantics. Fold-specific
% expansion of TrCovars/TsCovars, ComBat model matrices, spline maps, subgroup
% slicing and OOCV handling remains owned by nk_GenPreprocSequence.m and the
% runtime nk_PerfPreprocessObj_core.m path.
% -------------------------------------------------------------------------

    methods
        function obj = NMCorrectNuisModule()
            % NMCorrectNuisModule  Construct the Correct nuisance / batch effects preprocessing adapter.
            %   Registers module id 'correctnuis' with command-specific legacy fields and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('correctnuis','','Correct nuisance / batch effects');
            obj.Capabilities.requiresLabels = false;
            obj.Capabilities.usesLabels = true;       % ComBat may retain NM.label variance.
            obj.Capabilities.changesFeatureSpace = false;
            obj.Capabilities.supportsMissingData = false;
            obj.Capabilities.supportsHyperparameters = true;  % DIR lambda is exported as a PX shelf for optimization.
            obj.Capabilities.trainFoldEstimated = true;
            obj.Sequence.allowMultiple = true;
        end

        function spec = configSpec(obj, ctx)
            % configSpec  Return the canonical API/UI schema for Correct nuisance / batch effects.
            %   Defines editable fields for the module that configures nuisance regression,
            %   ComBat/CovBat harmonization, or Disparate Impact Removal before model training. The
            %   schema feeds defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            if nargin < 2, ctx = struct(); end
            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.title = obj.DisplayName;
            spec.description = ['Remove or harmonize nuisance effects using partial correlations/residualization, ', ...
                'ComBat/CovBat, or Disparate Impact Removal.'];
            spec.legacyConfigurator = 'nk_UnivCorrProcs_config';
            spec.fields = { ...
                struct('name','method','type','enum','default','partial','label','Nuisance-correction method', ...
                    'values',{{'partial','combat','dir'}}, ...
                    'help','Choose residualization, ComBat/CovBat harmonization, or Disparate Impact Removal.'), ...
                struct('name','methodConfig','type','subconfig','default',struct(),'label','Method-specific parameters', ...
                    'subconfigSelector','method', ...
                    'subconfigSpecs',NMNuisanceSubconfigLibrary.specs(ctx), ...
                    'help','Open the nested page for partial correlation, ComBat/CovBat, or Disparate Impact Removal settings.'), ...
                struct('name','featureMask','type','numeric_vector','default',[],'allowEmpty',true,'label','Optional feature mask/index', ...
                    'help','Optionally restrict nuisance correction to a selected subset of features.'), ...
                struct('name','legacyACTPARAM','type','struct','default',struct(),'label','Raw imported ACTPARAM','uiHidden',true, ...
                    'help','Imported ACTPARAM nuisance-correction settings retained for legacy round trips.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw imported PX','uiHidden',true, ...
                    'help','Imported PX optimization parameters retained for legacy round trips.') };
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict)
            % validateConfig  Validate and normalize Correct nuisance / batch effects configuration.
            %
            % Checks canonical config fields and nested method settings before scripted use,
            % UI-state application, and legacy conversion to command-specific legacy fields.
            %
            % cfg.method: stores the selected algorithmic method inside a normalized module configuration.
            % cfg.methodConfig: stores the normalized method config value in the module configuration.

            if nargin < 3, ctx = struct(); end
            if nargin < 4 || isempty(strict), strict = true; end
            [cfg, report] = validateConfig@NMPreprocModule(obj, cfg, ctx, strict);
            if ~report.ok, return; end
            cfg.method = NMNuisanceSubconfigLibrary.canonMethod(cfg.method);
            cfg.methodConfig = obj.normalizeMethodConfig(cfg.method, cfg.methodConfig, ctx);
            try
                obj.validateMethodConfig(cfg.method, cfg.methodConfig, ctx, strict);
            catch ME
                report.errors{end+1} = ME.message;
            end
            report.ok = isempty(report.errors);
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Correct nuisance / batch effects config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes command-specific legacy fields
            % for the CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.featureMask: stores the normalized feature mask value in the module configuration.
            % cfg.legacyACTPARAM: stores the normalized legacy actparam value in the module configuration.
            % cfg.legacyPX: preserves legacy PX parameters when a module cannot yet express every field canonically.
            % cfg.method: stores the selected algorithmic method inside a normalized module configuration.
            % cfg.methodConfig: stores the normalized method config value in the module configuration.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            [cfg, report] = obj.validateConfig(cfg, ctx, true);
            if ~report.ok
                error('NMCorrectNuisModule:invalidConfig','%s',strjoin(report.errors,newline));
            end

            if isfield(cfg,'legacyACTPARAM') && isstruct(cfg.legacyACTPARAM) && ~isempty(fieldnames(cfg.legacyACTPARAM))
                legacy = cfg.legacyACTPARAM;
            else
                legacy = struct();
            end

            method = NMNuisanceSubconfigLibrary.canonMethod(cfg.method);
            mcfg = cfg.methodConfig;
            legacy.METHOD = NMNuisanceSubconfigLibrary.methodCode(method);

            % Shared legacy defaults, matching nk_UnivCorrProcs_config.
            legacy.COVAR = 1;
            legacy.INTERCEPT = 2;
            legacy.COVDIR = 1;
            legacy.MBATCHUSE = 1;
            legacy.MBATCH = [];
            legacy.REFERENCE_LEVEL = [];
            legacy.MCOVARUSE = 1;
            legacy.MCOVAR = [];
            legacy.MCOVARREM = [];
            legacy.MCOVARLABEL = 1;
            legacy.LAMBDA = 0.8;
            legacy.COVBAT_MODE = 1;
            legacy.COVBAT_K = [];
            legacy.COVBAT_VAR = 0.95;
            legacy.DISTYPE = 1;
            legacy.MCOVAR_TYPE = {};
            legacy.MCOVAR_SPLINE_DF = [];
            legacy.UNSEENBATCH_MODE = 1;
            legacy.UNSEENBATCH_ALPHA = 0.7;

            switch method
                case 'partial'
                    legacy.COVAR = mcfg.covariates;
                    legacy.INTERCEPT = obj.boolToLegacyIntercept(mcfg.includeIntercept);
                    if strcmpi(mcfg.covariateDirection,'increase'), legacy.COVDIR = 2; else, legacy.COVDIR = 1; end
                    if isfield(legacy,'BETAEXT'), legacy = rmfield(legacy,'BETAEXT'); end
                    if isfield(mcfg,'useExternalBeta') && mcfg.useExternalBeta
                        legacy.BETAEXT = obj.resolveWorkspaceOrLegacy(mcfg.externalBetaSource, mcfg.externalBetaWorkspaceVar, mcfg.externalBetaMatrix, 'external beta matrix');
                    end
                    legacy = obj.setSubgroupField(legacy, mcfg, ctx);

                case 'combat'
                    legacy.MBATCHUSE = NMNuisanceSubconfigLibrary.yesNo(mcfg.useBatch);
                    if mcfg.useBatch
                        legacy.MBATCH = mcfg.batchCovariate;
                        if ~isempty(mcfg.batchCovariate), legacy.COVAR = mcfg.batchCovariate; else, legacy.COVAR = []; end
                    else
                        legacy.MBATCH = [];
                        legacy.COVAR = [];
                    end
                    legacy.REFERENCE_LEVEL = mcfg.referenceBatch;
                    legacy.MCOVARLABEL = NMNuisanceSubconfigLibrary.yesNo(mcfg.retainLabels);
                    legacy.MCOVARUSE = NMNuisanceSubconfigLibrary.yesNo(mcfg.includeCovariates);
                    if mcfg.includeCovariates
                        legacy.MCOVAR = mcfg.covariates;
                        legacy.MCOVARREM = mcfg.removeCovariatePositions;
                        legacy.MCOVAR_TYPE = NMNuisanceSubconfigLibrary.parseCovariateTypes(mcfg.covariateTypes);
                        legacy.MCOVAR_SPLINE_DF = mcfg.splineDF;
                    else
                        legacy.MCOVAR = [];
                        legacy.MCOVARREM = [];
                        legacy.MCOVAR_TYPE = {};
                        legacy.MCOVAR_SPLINE_DF = [];
                    end
                    legacy.COVBAT_MODE = NMNuisanceSubconfigLibrary.covbatModeCode(mcfg.combatVariant);
                    legacy.COVBAT_K = mcfg.covbatK;
                    legacy.COVBAT_VAR = mcfg.covbatVar;
                    if legacy.COVBAT_MODE == 2 && isempty(legacy.COVBAT_K) && isempty(legacy.COVBAT_VAR)
                        legacy.COVBAT_VAR = 0.95;
                    end
                    legacy.UNSEENBATCH_MODE = NMNuisanceSubconfigLibrary.unseenBatchModeCode(mcfg.unseenBatchMode);
                    legacy.UNSEENBATCH_ALPHA = mcfg.unseenBatchAlpha;
                    legacy = obj.setSubgroupField(legacy, mcfg, ctx);

                case 'dir'
                    legacy.COVAR = mcfg.categoricalCovariates;
                    legacy.DISTYPE = NMNuisanceSubconfigLibrary.distributionCode(mcfg.distribution);
                    legacy.LAMBDA = mcfg.lambda(:)';
                    legacy = obj.setSubgroupField(legacy, mcfg, ctx);
                    legacy.PX = obj.pxReset();
                    legacy.PX = obj.pxAdd(legacy.PX, legacy.LAMBDA, 'DIR-Lambda', 1);
            end

            if isfield(cfg,'featureMask') && ~isempty(cfg.featureMask)
                legacy.featind = cfg.featureMask;
            elseif isfield(legacy,'featind') && isempty(cfg.featureMask)
                legacy = rmfield(legacy,'featind');
            end

            if ~strcmp(method,'dir')
                preserveLegacyPX = isfield(cfg,'legacyPX') && isstruct(cfg.legacyPX) && ~isempty(fieldnames(cfg.legacyPX)) && ...
                    isfield(cfg,'legacyACTPARAM') && isstruct(cfg.legacyACTPARAM) && ...
                    isfield(cfg.legacyACTPARAM,'METHOD') && isequal(double(cfg.legacyACTPARAM.METHOD), double(legacy.METHOD));
                if preserveLegacyPX
                    legacy.PX = cfg.legacyPX;
                elseif isfield(legacy,'PX')
                    % Avoid carrying a stale DIR-lambda shelf when a legacy
                    % correctnuis step is modified to partial/ComBat.
                    legacy = rmfield(legacy,'PX');
                end
            end
            legacy.cmd = obj.Id;
        end

        function cfg = fromLegacy(obj, legacy, ctx)
            % fromLegacy  Import legacy Correct nuisance / batch effects settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            if nargin < 3, ctx = struct(); end
            cfg = obj.defaultConfig(ctx);
            if isempty(legacy), return; end
            cfg.legacyACTPARAM = legacy;
            if isfield(legacy,'PX') && isstruct(legacy.PX) && ~isempty(legacy.PX)
                cfg.legacyPX = legacy.PX;
            else
                cfg.legacyPX = struct();
            end
            if isfield(legacy,'featind'), cfg.featureMask = legacy.featind; end
            if isfield(legacy,'METHOD'), cfg.method = NMNuisanceSubconfigLibrary.methodName(legacy.METHOD); end
            cfg.methodConfig = obj.legacyToMethodConfig(cfg.method, legacy, ctx);
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok
                warning('NMCorrectNuisModule:legacyConfigInvalid','Legacy correctnuis configuration did not validate cleanly: %s', strjoin(report.errors,'; '));
            end
        end

        function [cfg, legacyParam, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Correct nuisance / batch effects for scripted or legacy CLI workflows.
            %
            % The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            % permits, subclasses may delegate to legacy nk_input configurators while preserving
            % canonical config output.
            %
            % ctx.NM: provides the current NeuroMiner structure to preprocessing execution helpers without direct global access.
            % ctx.varind: identifies the modality being preprocessed in the current execution context.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            if nargin < 3, ctx = struct(); end
            legacyParam = obj.toLegacy(cfg, ctx);
            act = 0; aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_UnivCorrProcs_config') && isfield(ctx,'NM') && ~isempty(ctx.NM)
                parentstr = obj.getParentString(ctx);
                defaultsfl = obj.getDefaultsFlag(ctx);
                varind = 1; if isfield(ctx,'varind') && ~isempty(ctx.varind), varind = ctx.varind; end
                [legacyParam, act] = nk_UnivCorrProcs_config(ctx.NM, legacyParam, varind, parentstr, defaultsfl);
                legacyParam.cmd = obj.Id;
                cfg = obj.fromLegacy(legacyParam, ctx);
            end
        end
    end

    methods (Access = private)
        function cfg = normalizeMethodConfig(obj, method, cfg, ctx) %#ok<INUSL>
            if nargin < 4, ctx = struct(); end
            if isempty(cfg) || ~isstruct(cfg), cfg = struct(); end
            spec = NMNuisanceSubconfigLibrary.byMethod(method, ctx);
            cfg = NMConfigTools.mergeDefaults(spec, cfg);
            % Normalize possible JSON/string array artefacts.
            if isfield(cfg,'covariateTypes') && isstring(cfg.covariateTypes)
                cfg.covariateTypes = char(cfg.covariateTypes);
            end
            if strcmpi(NMNuisanceSubconfigLibrary.canonMethod(method), 'combat')
                cfg = obj.syncCombatCovariateTable(cfg, ctx);
            end
        end

        function validateMethodConfig(obj, method, cfg, ctx, strict) %#ok<INUSD>
            switch NMNuisanceSubconfigLibrary.canonMethod(method)
                case 'partial'
                    obj.assertNumericVector(cfg.covariates, 'partial covariates', false);
                    if strict && cfg.useExternalBeta && strcmpi(cfg.externalBetaSource,'workspace') && isempty(cfg.externalBetaWorkspaceVar)
                        error('NMCorrectNuisModule:missingBeta','External beta source is workspace but no workspace variable is selected.');
                    end
                case 'combat'
                    if strict && cfg.useBatch && isempty(cfg.batchCovariate)
                        error('NMCorrectNuisModule:missingBatch','ComBat batch correction is enabled but no batch covariate is selected.');
                    end
                    if cfg.includeCovariates
                        obj.assertNumericVector(cfg.covariates, 'ComBat covariates', true);
                        if ~isempty(cfg.removeCovariatePositions) && ~isempty(cfg.covariates)
                            if any(cfg.removeCovariatePositions < 1) || any(cfg.removeCovariatePositions > numel(cfg.covariates))
                                error('NMCorrectNuisModule:badRemoveIdx','removeCovariatePositions must index positions in the selected ComBat covariates vector.');
                            end
                        end
                        if ~isempty(cfg.splineDF) && ~isempty(cfg.covariates) && numel(cfg.splineDF) ~= numel(cfg.covariates)
                            error('NMCorrectNuisModule:badSplineDF','splineDF must be empty or have one value per selected ComBat covariate.');
                        end
                        types = NMNuisanceSubconfigLibrary.parseCovariateTypes(cfg.covariateTypes);
                        if ~isempty(types) && ~isempty(cfg.covariates) && numel(types) ~= numel(cfg.covariates)
                            error('NMCorrectNuisModule:badCovTypes','covariateTypes must be empty or contain one entry per selected ComBat covariate.');
                        end
                    end
                case 'dir'
                    obj.assertNumericVector(cfg.categoricalCovariates, 'DIR categorical covariates', ~strict);
                    obj.assertNumericVector(cfg.lambda, 'DIR lambda', ~strict);
                    if any(cfg.lambda(:) < 0) || any(cfg.lambda(:) > 1)
                        error('NMCorrectNuisModule:badLambda','DIR lambda must be a scalar or vector within [0,1].');
                    end
            end
        end

        function cfg = legacyToMethodConfig(obj, method, legacy, ctx)
            cfg = obj.normalizeMethodConfig(method, struct(), ctx);
            switch NMNuisanceSubconfigLibrary.canonMethod(method)
                case 'partial'
                    if isfield(legacy,'COVAR'), cfg.covariates = legacy.COVAR; end
                    if isfield(legacy,'INTERCEPT'), cfg.includeIntercept = obj.legacyInterceptToBool(legacy.INTERCEPT); end
                    if isfield(legacy,'COVDIR') && legacy.COVDIR == 2, cfg.covariateDirection = 'increase'; else, cfg.covariateDirection = 'attenuate'; end
                    if isfield(legacy,'BETAEXT') && ~isempty(legacy.BETAEXT)
                        cfg.useExternalBeta = true;
                        cfg.externalBetaSource = 'legacy';
                        cfg.externalBetaMatrix = legacy.BETAEXT;
                    end
                    cfg = obj.legacySubgroupToConfig(cfg, legacy);
                case 'combat'
                    if isfield(legacy,'MBATCHUSE'), cfg.useBatch = NMNuisanceSubconfigLibrary.fromYesNo(legacy.MBATCHUSE,true); end
                    if isfield(legacy,'MBATCH'), cfg.batchCovariate = legacy.MBATCH; end
                    if isempty(cfg.batchCovariate) && isfield(legacy,'COVAR') && cfg.useBatch, cfg.batchCovariate = legacy.COVAR; end
                    if isfield(legacy,'REFERENCE_LEVEL'), cfg.referenceBatch = legacy.REFERENCE_LEVEL; end
                    if isfield(legacy,'MCOVARUSE'), cfg.includeCovariates = NMNuisanceSubconfigLibrary.fromYesNo(legacy.MCOVARUSE,true); end
                    if isfield(legacy,'MCOVAR'), cfg.covariates = legacy.MCOVAR; end
                    if isfield(legacy,'MCOVARREM'), cfg.removeCovariatePositions = legacy.MCOVARREM; end
                    if isfield(legacy,'MCOVARLABEL'), cfg.retainLabels = NMNuisanceSubconfigLibrary.fromYesNo(legacy.MCOVARLABEL,true); end
                    if isfield(legacy,'MCOVAR_TYPE') && ~isempty(legacy.MCOVAR_TYPE)
                        cfg.covariateTypes = strjoin(cellfun(@char, legacy.MCOVAR_TYPE(:)', 'UniformOutput', false), ',');
                    end
                    if isfield(legacy,'MCOVAR_SPLINE_DF'), cfg.splineDF = legacy.MCOVAR_SPLINE_DF; end
                    if isfield(legacy,'COVBAT_MODE'), cfg.combatVariant = NMNuisanceSubconfigLibrary.covbatModeName(legacy.COVBAT_MODE); end
                    if isfield(legacy,'COVBAT_K'), cfg.covbatK = legacy.COVBAT_K; end
                    if isfield(legacy,'COVBAT_VAR'), cfg.covbatVar = legacy.COVBAT_VAR; end
                    if isfield(legacy,'UNSEENBATCH_MODE'), cfg.unseenBatchMode = NMNuisanceSubconfigLibrary.unseenBatchModeName(legacy.UNSEENBATCH_MODE); end
                    if isfield(legacy,'UNSEENBATCH_ALPHA'), cfg.unseenBatchAlpha = legacy.UNSEENBATCH_ALPHA; end
                    cfg = obj.legacySubgroupToConfig(cfg, legacy);
                case 'dir'
                    if isfield(legacy,'COVAR'), cfg.categoricalCovariates = legacy.COVAR; end
                    if isfield(legacy,'DISTYPE'), cfg.distribution = NMNuisanceSubconfigLibrary.distributionName(legacy.DISTYPE); end
                    if isfield(legacy,'LAMBDA'), cfg.lambda = legacy.LAMBDA; end
                    cfg = obj.legacySubgroupToConfig(cfg, legacy);
            end
        end

        function cfg = syncCombatCovariateTable(obj, cfg, ctx)
            % Browser UI emits a compact covariateDetails.rows table, while
            % the legacy runtime consumes MCOVAR / MCOVARREM / MCOVAR_TYPE /
            % MCOVAR_SPLINE_DF. Keep the table as a derived UI view and keep
            % the legacy-aligned fields authoritative for scripted workflows.
            if nargin < 3, ctx = struct(); end

            detailsHasRows = isfield(cfg,'covariateDetails') && isstruct(cfg.covariateDetails) && ...
                isfield(cfg.covariateDetails,'rows') && ~isempty(cfg.covariateDetails.rows);

            if detailsHasRows
                rows = cfg.covariateDetails.rows;
                if iscell(rows), rows = [rows{:}]; end
                covs = [];
                rempos = [];
                types = {};
                dfs = [];
                for r = 1:numel(rows)
                    row = rows(r);
                    useRow = true;
                    if isfield(row,'use'), useRow = logical(row.use); end
                    if isfield(row,'selected'), useRow = logical(row.selected); end
                    if ~useRow, continue; end
                    if ~isfield(row,'index') || isempty(row.index), continue; end
                    idx = double(row.index);
                    if ~isfinite(idx) || idx < 1, continue; end
                    covs(end+1) = idx; %#ok<AGROW>
                    pos = numel(covs);
                    removeRow = false;
                    if isfield(row,'remove') && ~isempty(row.remove), removeRow = logical(row.remove); end
                    if isfield(row,'removeVariance') && ~isempty(row.removeVariance), removeRow = logical(row.removeVariance); end
                    if removeRow, rempos(end+1) = pos; end %#ok<AGROW>
                    if isfield(row,'type') && ~isempty(row.type)
                        types{end+1} = NMNuisanceSubconfigLibrary.canonCovType(row.type); %#ok<AGROW>
                    else
                        types{end+1} = obj.inferCovariateTypeFromContext(ctx, idx); %#ok<AGROW>
                    end
                    if isfield(row,'splineDF') && ~isempty(row.splineDF)
                        dfs(end+1) = obj.normalizeSplineDFValue(row.splineDF); %#ok<AGROW>
                    else
                        dfs(end+1) = 0; %#ok<AGROW>
                    end
                end
                cfg.covariates = covs;
                cfg.removeCovariatePositions = rempos;
                cfg.covariateTypes = types;
                cfg.splineDF = dfs;
            end

            if ~isfield(cfg,'covariates') || isempty(cfg.covariates)
                cfg.covariates = [];
                cfg.removeCovariatePositions = [];
                cfg.covariateTypes = '';
                cfg.splineDF = [];
                cfg.covariateDetails = struct('rows',[]);
                return;
            end

            cfg.covariates = double(cfg.covariates(:))';
            cfg.covariates = cfg.covariates(isfinite(cfg.covariates) & cfg.covariates >= 1);
            if isempty(cfg.covariates)
                cfg.removeCovariatePositions = [];
                cfg.covariateTypes = '';
                cfg.splineDF = [];
                cfg.covariateDetails = struct('rows',[]);
                return;
            end

            if ~isfield(cfg,'removeCovariatePositions') || isempty(cfg.removeCovariatePositions)
                cfg.removeCovariatePositions = [];
            else
                rem = double(cfg.removeCovariatePositions(:))';
                rem = rem(isfinite(rem) & rem >= 1 & rem <= numel(cfg.covariates));
                cfg.removeCovariatePositions = unique(round(rem));
            end

            types = NMNuisanceSubconfigLibrary.parseCovariateTypes(cfg.covariateTypes);
            if ~isempty(types) && numel(types) ~= numel(cfg.covariates)
                types = {};
            end
            if isempty(types)
                types = cell(1,numel(cfg.covariates));
                for i = 1:numel(cfg.covariates)
                    types{i} = obj.inferCovariateTypeFromContext(ctx, cfg.covariates(i));
                end
            end
            cfg.covariateTypes = types;

            if ~isfield(cfg,'splineDF') || isempty(cfg.splineDF)
                cfg.splineDF = zeros(1,numel(cfg.covariates));
            else
                df = double(cfg.splineDF(:))';
                if numel(df) == numel(cfg.covariates)
                    df(~isfinite(df)) = 0;
                    cfg.splineDF = arrayfun(@(x) obj.normalizeSplineDFValue(x), df);
                else
                    cfg.splineDF = zeros(1,numel(cfg.covariates));
                end
            end

            cfg.covariateDetails = obj.buildCombatCovariateDetails(cfg, ctx);
        end

        function details = buildCombatCovariateDetails(obj, cfg, ctx)
            if nargin < 3, ctx = struct(); end
            covs = [];
            if isfield(cfg,'covariates') && ~isempty(cfg.covariates)
                covs = double(cfg.covariates(:))';
            end
            rows = struct('index',{},'name',{},'selected',{},'remove',{},'type',{},'splineDF',{});
            if isempty(covs)
                details = struct('rows',rows);
                return;
            end
            types = NMNuisanceSubconfigLibrary.parseCovariateTypes(cfg.covariateTypes);
            if numel(types) ~= numel(covs), types = {}; end
            df = [];
            if isfield(cfg,'splineDF') && ~isempty(cfg.splineDF) && numel(cfg.splineDF)==numel(covs)
                df = double(cfg.splineDF(:))';
            end
            rem = [];
            if isfield(cfg,'removeCovariatePositions') && ~isempty(cfg.removeCovariatePositions)
                rem = double(cfg.removeCovariatePositions(:))';
            end
            for i = 1:numel(covs)
                idx = covs(i);
                row = struct();
                row.index = idx;
                row.name = obj.covariateNameFromContext(ctx, idx);
                row.selected = true;
                row.remove = any(rem == i);
                if isempty(types)
                    row.type = obj.inferCovariateTypeFromContext(ctx, idx);
                else
                    row.type = types{i};
                end
                if isempty(df)
                    row.splineDF = 0;
                else
                    row.splineDF = obj.normalizeSplineDFValue(df(i));
                end
                rows(end+1) = row; %#ok<AGROW>
            end
            details = struct('rows',rows);
        end

        function df = normalizeSplineDFValue(~, value)
            % Browser UI exposes only none/2/3/4/5. Keep legacy 0/1 imports
            % as no-spline and clamp larger finite values into the valid range.
            try
                df = round(double(value));
            catch
                df = 0;
            end
            if isempty(df) || ~isfinite(df(1)) || df(1) < 2
                df = 0;
            else
                df = min(5, max(2, df(1)));
            end
        end

        function typ = inferCovariateTypeFromContext(~, ctx, idx)
            typ = 'continuous';
            if ~isstruct(ctx) || ~isfield(ctx,'covarOptions') || isempty(ctx.covarOptions), return; end
            opts = ctx.covarOptions;
            if isstruct(opts), opts = num2cell(opts); end
            for i = 1:numel(opts)
                o = opts{i};
                if isfield(o,'index') && double(o.index) == double(idx) && isfield(o,'inferredType') && ~isempty(o.inferredType)
                    typ = NMNuisanceSubconfigLibrary.canonCovType(o.inferredType);
                    return;
                end
            end
        end

        function name = covariateNameFromContext(~, ctx, idx)
            name = sprintf('Covariate %d', idx);
            if ~isstruct(ctx) || ~isfield(ctx,'covarOptions') || isempty(ctx.covarOptions), return; end
            opts = ctx.covarOptions;
            if isstruct(opts), opts = num2cell(opts); end
            for i = 1:numel(opts)
                o = opts{i};
                if isfield(o,'index') && double(o.index) == double(idx)
                    if isfield(o,'name') && ~isempty(o.name), name = char(o.name); return; end
                    if isfield(o,'label') && ~isempty(o.label), name = char(o.label); return; end
                end
            end
        end

        function legacy = setSubgroupField(obj, legacy, mcfg, ctx) %#ok<INUSD>
            if isfield(legacy,'SUBGROUP'), legacy = rmfield(legacy,'SUBGROUP'); end
            if ~isfield(mcfg,'subgroupSource'), return; end
            switch lower(char(mcfg.subgroupSource))
                case 'none'
                    % Leave absent. The old configurator sometimes used NaN
                    % transiently, but runtime checks are cleaner with absence.
                case 'workspace'
                    legacy.SUBGROUP = obj.resolveWorkspaceVector(mcfg.subgroupWorkspaceVar, 'subgroup vector');
                case 'legacy'
                    if isfield(mcfg,'subgroupVector') && ~isempty(mcfg.subgroupVector)
                        legacy.SUBGROUP = mcfg.subgroupVector;
                    end
            end
        end

        function cfg = legacySubgroupToConfig(~, cfg, legacy)
            if isfield(legacy,'SUBGROUP') && ~isempty(legacy.SUBGROUP) && ~(isscalar(legacy.SUBGROUP) && isnumeric(legacy.SUBGROUP) && isnan(legacy.SUBGROUP))
                cfg.subgroupSource = 'legacy';
                cfg.subgroupVector = legacy.SUBGROUP;
            end
        end

        function val = resolveWorkspaceOrLegacy(obj, source, varName, legacyValue, label)
            switch lower(char(source))
                case 'workspace'
                    val = obj.resolveWorkspaceVector(varName, label);
                case 'legacy'
                    val = legacyValue;
                    if isempty(val), error('NMCorrectNuisModule:missingLegacyValue','No imported legacy value is available for %s.', label); end
                otherwise
                    val = [];
            end
        end

        function val = resolveWorkspaceVector(~, varName, label)
            if nargin < 3, label = 'workspace value'; end
            if isempty(varName)
                error('NMCorrectNuisModule:missingWorkspaceVar','No workspace variable selected for %s.', label);
            end
            val = NMWorkspaceTools.resolve(varName, 'base');
            if ~(isnumeric(val) || islogical(val))
                error('NMCorrectNuisModule:badWorkspaceValue','%s must be numeric/logical.', label);
            end
        end

        function assertNumericVector(~, val, label, allowEmpty)
            if nargin < 4, allowEmpty = true; end
            if isempty(val) && allowEmpty, return; end
            if ~(isnumeric(val) && isvector(val) && all(isfinite(val(:))))
                error('NMCorrectNuisModule:badVector','%s must be a finite numeric vector.', label);
            end
        end

        function code = boolToLegacyIntercept(~, tf)
            % nk_UnivCorrProcs_config uses INTERCEPT=2 for yes, 1 for no.
            if tf, code = 2; else, code = 1; end
        end

        function tf = legacyInterceptToBool(~, code)
            if isempty(code), tf = true; else, tf = double(code) == 2; end
        end
    end
end

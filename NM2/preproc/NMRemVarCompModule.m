classdef NMRemVarCompModule < NMPreprocModule
% NMRemVarCompModule
% -------------------------------------------------------------------------
% Canonical adapter for NeuroMiner's variance-component removal step
% (legacy command: remvarcomp).  This module mirrors nk_Remvarcomp_config.m:
% it defines a target vector/matrix G, identifies variance components in a
% PCA/fastICA projection according to a correlation/ANOVA criterion, and
% optionally reconstructs adjusted matrices back into input space.
% -------------------------------------------------------------------------

    methods
        function obj = NMRemVarCompModule()
            % NMRemVarCompModule  Construct the Remove variance components preprocessing adapter.
            %   Registers module id 'remvarcomp' with legacy branch 'REMVARCOMP' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('remvarcomp','REMVARCOMP','Remove variance components');
            obj.Capabilities.requiresLabels = false;
            obj.Capabilities.usesLabels = false;
            obj.Capabilities.changesFeatureSpace = true;
            obj.Capabilities.spatialFeatureExtractionFlagEffect = 'disable_unless_backprojected';
            obj.Capabilities.invalidatesImageSpace = true;
            obj.Capabilities.restoresImageSpace = true;
            obj.Capabilities.isDimensionalityReductionLike = true;
            obj.Capabilities.supportsHyperparameters = true;
            obj.Capabilities.supportsMissingData = false;
        end

        function spec = configSpec(obj, ctx)
            % configSpec  Return the canonical API/UI schema for Remove variance components.
            %
            % Defines editable fields for the module that removes variance components using
            % PCA/ICA/wavelet residualization branches. The schema feeds defaultConfig,
            % validateConfig, browser rendering, CLI/API help, and RAG documentation extraction.
            %
            % ctx.isImaging: exposes the is imaging execution-context value to preprocessing/runtime code.

            if nargin < 2, ctx = struct(); end
            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Identify and remove variance components associated with a user-defined target vector or matrix. ', ...
                'A following dimensionality-extraction step can optimize projection dimensionality without repeatedly refitting the projection.'];
            methodValues = {'PCA','fastICA'};
            imagingCtx = true;
            try
                if isfield(ctx,'isImaging') && ~isempty(ctx.isImaging)
                    imagingCtx = logical(ctx.isImaging);
                end
            catch
                imagingCtx = true;
            end
            if imagingCtx
                methodValues = [methodValues {'waveletPCA','waveletICA','waveletDirect'}];
            end

            spec.fields = { ...
                struct('name','reductionMethod','type','enum','default','PCA','label','Dimensionality-reduction method', ...
                    'values',{methodValues}, ...
                    'help','Choose PCA, fastICA, wavelet-PCA, wavelet-ICA or direct wavelet attenuation. Wavelet methods require image-space input.'), ...
                struct('name','targetSource','type','enum','default','workspace','label','Nuisance target G source', ...
                    'values',{{'workspace','nm_covars','nm_label','legacy'}}, ...
                    'help','Define the nuisance target used for training-fold association estimation from a workspace variable, selected covariates, outcome labels, or an imported target matrix.'), ...
                struct('name','targetWorkspaceVar','type','workspace_var','default','','label','Workspace nuisance target G variable', ...
                    'visibleIf',struct('field','targetSource','equals','workspace'), ...
                    'workspaceFilter',struct('numericOnly',true,'rowCountFromContext','nSubjects'), ...
                    'help','Numeric vector or matrix with one row per subject/case.'), ...
                struct('name','covariateColumns','type','covariate_indices','default',[],'label','Nuisance target covariate column(s)', ...
                    'allowEmpty',true,'visibleIf',struct('field','targetSource','equals','nm_covars'), ...
                    'help','Select one or more covariates as the nuisance target. If empty, all available covariates are used.'), ...
                struct('name','correlationMethod','type','enum','default','Pearson','label','Association metric for nuisance target G', ...
                    'values',{{'Pearson','Spearman','ANOVA'}}, ...
                    'help','Choose Pearson, Spearman, or ANOVA to quantify component association with the nuisance target.'), ...
                struct('name','criterion','type','enum','default','corr','label','Metric for component identification', ...
                    'values',{{'corr','pval'}}, ...
                    'visibleIf',struct('field','reductionMethod','in',{{'PCA','fastICA'}}), ...
                    'help','Use an association coefficient or a p-value for component identification.'), ...
                struct('name','correlationThreshold','type','numeric_vector','default',0.5,'label','Metric cutoff(s)', ...
                    'allowEmpty',false, ...
                    'visibleIf',struct('field','reductionMethod','in',{{'PCA','fastICA'}}), ...
                    'help','Association threshold for component selection. Multiple values define optimization candidates. Hidden for wavelet-PCA/ICA because those methods use continuous association weights.'), ...
                struct('name','operator','type','enum','default','gt','label','Variance extraction operator', ...
                    'values',{{'gt','ge','lt','le'}}, ...
                    'visibleIf',struct('field','reductionMethod','in',{{'PCA','fastICA'}}), ...
                    'help','Comparison operator used with the association threshold. Hidden for wavelet-PCA/ICA because no hard threshold is used.'), ...
                struct('name','backProject','type','boolean','default',false,'label','Back-project / reconstruct adjusted data to input space', ...
                    'visibleIf',struct('field','reductionMethod','in',{{'PCA','fastICA','waveletPCA','waveletICA','waveletDirect'}}), ...
                    'help','When enabled, reconstruct the adjusted data in the original input space; otherwise return the reduced representation.'), ...
                struct('name','waveletDirectFinalEmbeddingMethod','type','enum','default','PCA','label','Final PCA/ICA projection after waveletDirect correction', ...
                    'values',{{'PCA','fastICA'}}, ...
                    'visibleIf',struct('all',{{struct('field','reductionMethod','equals','waveletDirect'),struct('field','backProject','equals',false)}}), ...
                    'help','For waveletDirect with back-projection disabled, select PCA or fastICA as the final projection; the projection is fitted on corrected training data and reused for test data.'), ...
                struct('name','subgroupMode','type','enum','default','all_training','label','Training data for projection model', ...
                    'values',{{'all_training','workspace_training_subset','random_training_subset','all_calibration','workspace_calibration_subset','random_calibration_subset'}}, ...
                    'visibleIf',struct('field','backProject','equals',false), ...
                    'help','Optional subgroup operation applied during reconstruction/back-projection. Hidden when reconstruction is disabled.'), ...
                struct('name','subgroupWorkspaceVar','type','workspace_var','default','','label','Subset indicator variable', ...
                    'visibleIf',struct('all',{{struct('field','backProject','equals',false),struct('field','subgroupMode','in',{{'workspace_training_subset','workspace_calibration_subset'}})}}), ...
                    'workspaceFilter',struct('numericOnly',true,'rowCountFromContext','nSubjects'), ...
                    'help','Logical/numeric index vector used for user-defined training/calibration subsets.'), ...
                struct('name','subgroupPercent','type','number','default',50,'min',0,'max',100,'label','Random subset percentage', ...
                    'visibleIf',struct('all',{{struct('field','backProject','equals',false),struct('field','subgroupMode','in',{{'random_training_subset','random_calibration_subset'}})}}), ...
                    'help','Percentage of cases sampled for the selected random training/calibration subgroup.'), ...
                struct('name','dimensionMode','type','enum','default','percentage','label','Projection dimensionality mode', ...
                    'values',{{'fixed','percentage'}}, ...
                    'visibleIf',struct('all',{{struct('field','backProject','equals',false),struct('any',{{struct('field','reductionMethod','in',{{'PCA','waveletPCA'}}),struct('all',{{struct('field','reductionMethod','equals','waveletDirect'),struct('field','waveletDirectFinalEmbeddingMethod','equals','PCA')}})}})}}), ...
                    'help','Choose a fixed number of components or a percentage-based dimensionality. Percentage mode is available for PCA-based projections; fastICA uses a fixed component count.'), ...
                struct('name','fitDim','type','numeric_vector','default',1,'label','Projection dimensionality/variance retention', ...
                    'allowEmpty',false, ...
                    'visibleIf',struct('field','backProject','equals',false), ...
                    'help','Projection dimensionality. Multiple values define optimization candidates; for fastICA they are interpreted as fixed numbers of independent components.'), ...
                struct('name','fastICAParams','type','subconfig','default',struct(),'label','fastICA parameters', ...
                    'visibleIf',struct('field','reductionMethod','equals','fastICA'), ...
                    'subconfigSelector','reductionMethod', ...
                    'subconfigSpecs',obj.fastICASubconfigSpec(ctx), ...
                    'help','Opens the cv_fastICA_config-equivalent nested page.'), ...
                struct('name','waveletParams','type','subconfig','default',struct(),'label','Wavelet RemVarComp parameters', ...
                    'visibleIf',struct('field','reductionMethod','in',{{'waveletPCA','waveletICA','waveletDirect'}}), ...
                    'subconfigSelector','reductionMethod', ...
                    'subconfigSpecs',NMRemVarCompWaveletSubconfigLibrary.specs(ctx), ...
                    'help','Configure signed wavelet bands, protected covariates, and soft supervised nuisance attenuation. The main back-project/reconstruct checkbox determines image-space versus reduced-space output.'), ...
                struct('name','legacyREMVARCOMP','type','struct','default',struct(),'label','Raw legacy REMVARCOMP structure','uiHidden',true, ...
                    'help','Imported REMVARCOMP settings retained for legacy configuration round trips.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Imported PX optimization parameters retained for legacy configuration round trips.') };
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Remove variance components config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'REMVARCOMP' for
            % the CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.backProject: stores the normalized back project value in the module configuration.
            % cfg.correlationMethod: stores the normalized correlation method value in the module configuration.
            % cfg.correlationThreshold: stores the normalized correlation threshold value in the module configuration.
            % cfg.criterion: stores the normalized criterion value in the module configuration.
            % cfg.dimensionMode: stores the normalized dimension mode value in the module configuration.
            % cfg.fastICAParams: stores the normalized fast icaparams value in the module configuration.
            % cfg.fitDim: stores the normalized fit dim value in the module configuration.
            % cfg.legacyREMVARCOMP: stores the normalized legacy remvarcomp value in the module configuration.
            % cfg.operator: stores the normalized operator value in the module configuration.
            % cfg.reductionMethod: stores the normalized reduction method value in the module configuration.
            % cfg.waveletDirectFinalEmbeddingMethod: stores the normalized wavelet direct final embedding method value in the module configuration.
            % cfg.waveletParams: stores the normalized wavelet params value in the module configuration.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            cfg = obj.parseConfig(cfg);

            if isfield(cfg,'legacyREMVARCOMP') && isstruct(cfg.legacyREMVARCOMP) && ~isempty(fieldnames(cfg.legacyREMVARCOMP))
                R = cfg.legacyREMVARCOMP;
            else
                R = struct();
            end

            R.redmethod  = obj.redMethodCode(cfg.reductionMethod);
            R.G          = obj.resolveTargetMatrix(cfg, ctx);
            R.corrmeth   = obj.corrMethodCode(cfg.correlationMethod);
            R.corrthresh = cfg.correlationThreshold;
            R.corrcrit   = char(cfg.criterion);
            R.varop      = char(cfg.operator);
            R.recon      = obj.boolToLegacyYesNo(logical(cfg.backProject));
            R.SUBGROUP   = obj.subgroupToLegacy(cfg, ctx);

            if R.redmethod == 2
                R.dimmode = 1;
                R.dims = cfg.fitDim;
                fcfg = obj.normalizeFastICAParams(cfg.fastICAParams, ctx);
                R.tolerance     = fcfg.tolerance;
                R.max_iters     = fcfg.max_iters;
                R.algorithm_opt = char(fcfg.algorithm_opt);
                R.whiten_opt    = char(fcfg.whiten_opt);
                R.fun_opt       = char(fcfg.fun_opt);
            elseif any(R.redmethod == [3 4 5])
                % Wavelet RemVarComp uses nk_PerfRedObj inside each signed
                % wavelet band. The wavelet subconfiguration determines
                % whether the adjusted result is recomposed into image space
                % or returned as a concatenated wavelet-component embedding.
                R.dims = cfg.fitDim;
                if R.redmethod == 4
                    R.dimmode = 1;
                else
                    R.dimmode = obj.dimModeCode(cfg.dimensionMode);
                end
                wcfg = cfg.waveletParams;
                if ~isstruct(wcfg), wcfg = struct(); end
                if logical(cfg.backProject)
                    wcfg.outputDomain = 'image';
                else
                    wcfg.outputDomain = 'embedding';
                end
                if R.redmethod == 5
                    if isfield(cfg,'waveletDirectFinalEmbeddingMethod') && ~isempty(cfg.waveletDirectFinalEmbeddingMethod)
                        wcfg.finalEmbeddingMethod = char(cfg.waveletDirectFinalEmbeddingMethod);
                    else
                        wcfg.finalEmbeddingMethod = 'PCA';
                    end
                end
                wcfgRaw = wcfg;
                R.WAVELETREMVARCOMP = NMRemVarCompWaveletSubconfigLibrary.toLegacy(cfg.reductionMethod, wcfgRaw, ctx);
                wcfg = NMRemVarCompWaveletSubconfigLibrary.normalizeParams(cfg.reductionMethod, wcfgRaw, ctx);
                R.WAVELETREMVARCOMP.PROTECTED = struct();
                R.WAVELETREMVARCOMP.PROTECTED.matrix = obj.resolveProtectedMatrix(wcfg, ctx);
                R.WAVELETREMVARCOMP.PROTECTED.useLabel = isfield(wcfg,'protectLabel') && logical(wcfg.protectLabel);
                if isfield(wcfg,'protectedCovariateColumns'), R.WAVELETREMVARCOMP.PROTECTED.covariateColumns = wcfg.protectedCovariateColumns; end
                if isfield(wcfg,'protectedWorkspaceVar'), R.WAVELETREMVARCOMP.PROTECTED.workspaceVar = wcfg.protectedWorkspaceVar; end
                if logical(cfg.backProject)
                    R.recon = 1;
                else
                    R.recon = 2;
                end
                if R.redmethod == 4 || (R.redmethod == 5 && isfield(R.WAVELETREMVARCOMP,'finalEmbeddingMethod') && strcmpi(char(R.WAVELETREMVARCOMP.finalEmbeddingMethod),'fastICA'))
                    R.tolerance     = R.WAVELETREMVARCOMP.fastICA.tolerance;
                    R.max_iters     = R.WAVELETREMVARCOMP.fastICA.max_iters;
                    R.algorithm_opt = char(R.WAVELETREMVARCOMP.fastICA.algorithm_opt);
                    R.whiten_opt    = char(R.WAVELETREMVARCOMP.fastICA.whiten_opt);
                    R.fun_opt       = char(R.WAVELETREMVARCOMP.fastICA.fun_opt);
                end
            else
                R.dimmode = obj.dimModeCode(cfg.dimensionMode);
                R.dims = cfg.fitDim;
            end

            PX = obj.pxAdd([], [], [], 1, 'reset');
            % The legacy cv_fastICA_config registers these two shelves.  In
            % nk_Remvarcomp_config the subsequent CorrThresh registration uses
            % 'replace', which can accidentally remove them. The modular export
            % preserves the intended dynamic fields while keeping descriptor
            % names identical to cv_fastICA_config.
            if R.redmethod == 2 || R.redmethod == 4 || (R.redmethod == 5 && isfield(R,'WAVELETREMVARCOMP') && isfield(R.WAVELETREMVARCOMP,'finalEmbeddingMethod') && strcmpi(char(R.WAVELETREMVARCOMP.finalEmbeddingMethod),'fastICA'))
                PX = obj.pxAdd(PX, R.tolerance, 'FastICA_tol', 1, '');
                PX = obj.pxAdd(PX, R.max_iters, 'FastICA_max_iter', 1, '');
            end
            if ~any(R.redmethod == [3 4 5])
                PX = obj.pxAdd(PX, R.corrthresh, 'CorrThresh', 1, '');
            end
            PX = obj.pxAdd(PX, R.dims,       'Dims',       1, '');

            legacy = struct('cmd',obj.Id,'REMVARCOMP',R,'PX',PX);
        end

        function cfg = fromLegacy(obj, legacy, ctx)
            % fromLegacy  Import legacy Remove variance components settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            if nargin < 3, ctx = struct(); end
            cfg = obj.defaultConfig(ctx);
            if isempty(legacy), return; end
            if isfield(legacy,'REMVARCOMP'), R = legacy.REMVARCOMP; else, R = legacy; end
            cfg.legacyREMVARCOMP = R;
            if isfield(legacy,'PX') && isstruct(legacy.PX) && ~isempty(legacy.PX)
                cfg.legacyPX = legacy.PX;
            else
                cfg.legacyPX = struct();
            end
            if isfield(R,'redmethod'), cfg.reductionMethod = obj.redMethodName(R.redmethod); end
            if isfield(R,'G')
                cfg.targetSource = 'legacy';
            end
            if isfield(R,'corrmeth'), cfg.correlationMethod = obj.corrMethodName(R.corrmeth); end
            if isfield(R,'corrthresh'), cfg.correlationThreshold = R.corrthresh; end
            if isfield(R,'corrcrit'), cfg.criterion = char(R.corrcrit); end
            if isfield(R,'varop'), cfg.operator = char(R.varop); end
            if isfield(R,'recon'), cfg.backProject = obj.legacyYesNoToBool(R.recon, false); end
            if isfield(R,'dims'), cfg.fitDim = R.dims; end
            if isfield(R,'dimmode'), cfg.dimensionMode = obj.dimModeName(R.dimmode); end
            if isfield(R,'SUBGROUP'), cfg = obj.subgroupFromLegacy(cfg, R.SUBGROUP); end
            if strcmp(cfg.reductionMethod,'fastICA')
                fp = obj.defaultFastICAParams(ctx);
                if isfield(R,'tolerance'), fp.tolerance = R.tolerance; end
                if isfield(R,'max_iters'), fp.max_iters = R.max_iters; end
                if isfield(R,'algorithm_opt'), fp.algorithm_opt = R.algorithm_opt; end
                if isfield(R,'whiten_opt'), fp.whiten_opt = R.whiten_opt; end
                if isfield(R,'fun_opt'), fp.fun_opt = R.fun_opt; end
                cfg.fastICAParams = obj.normalizeFastICAParams(fp, ctx);
            elseif any(strcmp(cfg.reductionMethod, {'waveletPCA','waveletICA','waveletDirect'}))
                if isfield(R,'WAVELETREMVARCOMP') && isstruct(R.WAVELETREMVARCOMP)
                    cfg.waveletParams = NMRemVarCompWaveletSubconfigLibrary.fromLegacy(cfg.reductionMethod, R.WAVELETREMVARCOMP, ctx);
                else
                    cfg.waveletParams = NMRemVarCompWaveletSubconfigLibrary.defaultParams(cfg.reductionMethod, ctx);
                end
                if isfield(R,'recon') && isequal(R.recon,2)
                    cfg.backProject = false;
                elseif isfield(R,'recon')
                    cfg.backProject = obj.legacyYesNoToBool(R.recon, false);
                end
                if isfield(R,'WAVELETREMVARCOMP') && isstruct(R.WAVELETREMVARCOMP) && isfield(R.WAVELETREMVARCOMP,'finalEmbeddingMethod')
                    cfg.waveletDirectFinalEmbeddingMethod = char(R.WAVELETREMVARCOMP.finalEmbeddingMethod);
                end
            end
            cfg = obj.validateOrError(cfg, ctx);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Remove variance components for scripted or legacy CLI workflows.
            %
            % The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            % permits, subclasses may delegate to legacy nk_input configurators while preserving
            % canonical config output.
            %
            % ctx.NM: provides the current NeuroMiner structure to preprocessing execution helpers without direct global access.
            % ctx.varind: identifies the modality being preprocessed in the current execution context.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_Remvarcomp_config')
                if ~isfield(ctx,'NM') || isempty(ctx.NM)
                    error('NMRemVarCompModule:missingNM','Legacy CLI configuration requires ctx.NM.');
                end
                varind = [];
                if isfield(ctx,'varind'), varind = ctx.varind; end
                parentstr = obj.getParentString(ctx);
                R = legacy.REMVARCOMP; PX = legacy.PX;
                [R, PX] = nk_Remvarcomp_config(ctx.NM, varind, R, PX, parentstr);
                legacy = struct('cmd',obj.Id,'REMVARCOMP',R,'PX',PX);
                cfg = obj.fromLegacy(legacy, ctx);
                act = 0;
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx)
            % execute  Fit or apply the Remove variance components runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfAdjForCovarsUsingPCAObj.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end
            if exist('nk_PerfAdjForCovarsUsingPCAObj','file') ~= 2
                error('NMRemVarCompModule:missingBackend','nk_PerfAdjForCovarsUsingPCAObj is not on the MATLAB path.');
            end
            switch lower(char(mode))
                case 'fit'
                    cfg = obj.defaultConfig(ctx);
                    if isfield(ctx,'config'), cfg = ctx.config; end
                    legacy = obj.toLegacy(cfg, ctx);
                    R = legacy.REMVARCOMP;
                    [Yout, trained] = nk_PerfAdjForCovarsUsingPCAObj(Y, R, Y);
                case 'transform'
                    if isempty(trained)
                        error('NMRemVarCompModule:noTrained','remvarcomp transform requires trained parameters.');
                    end
                    Yout = nk_PerfAdjForCovarsUsingPCAObj(Y, trained);
                otherwise
                    error('NMRemVarCompModule:badMode','Unknown execution mode: %s', char(mode));
            end
        end
    end

    methods (Access = private)
        function map = fastICASubconfigSpec(obj, ctx) %#ok<INUSL>
            fp = obj.defaultFastICAParams(ctx);
            s = struct();
            s.id = 'fastICA';
            s.kind = 'remvarcomp-fastica-subconfig';
            s.title = 'fastICA settings';
            s.description = 'Nested configuration equivalent to cv_fastICA_config for the remvarcomp step.';
            s.cliConfigurator = 'cv_fastICA_config';
            s.fields = { ...
                struct('name','tolerance','type','numeric_vector','default',fp.tolerance,'allowEmpty',false,'label','Tolerance parameter(s)', ...
                    'help','Convergence-tolerance candidates for fastICA variance-component decomposition.'), ...
                struct('name','max_iters','type','numeric_vector','default',fp.max_iters,'allowEmpty',false,'label','Maximum iteration value(s)', ...
                    'help','Maximum iteration candidates for fastICA variance-component decomposition.'), ...
                struct('name','algorithm_opt','type','enum','default',fp.algorithm_opt,'label','fastICA algorithm', ...
                    'values',{{'parallel','deflation'}}, ...
                    'help','Choose parallel or deflationary fastICA estimation.'), ...
                struct('name','whiten_opt','type','enum','default',fp.whiten_opt,'label','Whitening strategy', ...
                    'values',{{'unit-variance','arbitrary-variance'}}, ...
                    'help','Choose unit-variance or arbitrary-variance whitening in fastICA.'), ...
                struct('name','fun_opt','type','enum','default',fp.fun_opt,'label','G-function', ...
                    'values',{{'logcosh','exp','cube'}}, ...
                    'help','Choose the fastICA contrast nonlinearity.') };
            map = struct('fastica',s);
        end

        function fp = defaultFastICAParams(~, ctx) %#ok<INUSD>
            fp = struct('tolerance',1e-4,'max_iters',200, ...
                'algorithm_opt','parallel','whiten_opt','unit-variance','fun_opt','logcosh');
        end

        function fp = normalizeFastICAParams(obj, fp, ctx)
            if nargin < 2 || isempty(fp) || ~isstruct(fp), fp = obj.defaultFastICAParams(ctx); end
            m = obj.fastICASubconfigSpec(ctx);
            sp = struct('fields',{m.fastica.fields});
            [fp, rep] = NMConfigTools.validateConfig(sp, fp, ctx, false);
            if ~rep.ok, error('NMRemVarCompModule:invalidFastICA','%s',strjoin(rep.errors,newline)); end
        end

        function G = resolveTargetMatrix(~, cfg, ctx)
            switch lower(char(cfg.targetSource))
                case 'workspace'
                    if isempty(cfg.targetWorkspaceVar)
                        error('NMRemVarCompModule:missingTarget','remvarcomp requires a workspace target G variable.');
                    end
                    G = NMWorkspaceTools.resolve(cfg.targetWorkspaceVar, 'base');
                case 'nm_covars'
                    if ~isfield(ctx,'NM') || ~isstruct(ctx.NM) || ~isfield(ctx.NM,'covars') || isempty(ctx.NM.covars)
                        error('NMRemVarCompModule:missingCovars','targetSource=nm_covars requires NM.covars.');
                    end
                    if isempty(cfg.covariateColumns)
                        G = ctx.NM.covars;
                    else
                        G = ctx.NM.covars(:,cfg.covariateColumns);
                    end
                case 'nm_label'
                    if ~isfield(ctx,'NM') || ~isstruct(ctx.NM) || ~isfield(ctx.NM,'label') || isempty(ctx.NM.label)
                        error('NMRemVarCompModule:missingLabel','targetSource=nm_label requires NM.label.');
                    end
                    G = ctx.NM.label;
                    if isvector(G), G = G(:); end
                case 'legacy'
                    if isfield(cfg,'legacyREMVARCOMP') && isstruct(cfg.legacyREMVARCOMP) && isfield(cfg.legacyREMVARCOMP,'G')
                        G = cfg.legacyREMVARCOMP.G;
                    else
                        error('NMRemVarCompModule:missingLegacyTarget','targetSource=legacy requires imported REMVARCOMP.G.');
                    end
                otherwise
                    error('NMRemVarCompModule:badTargetSource','Unknown targetSource: %s', char(cfg.targetSource));
            end
            if ~isnumeric(G) && ~islogical(G)
                error('NMRemVarCompModule:badTarget','REMVARCOMP.G must be numeric/logical.');
            end
            if isvector(G), G = G(:); end
            if isfield(ctx,'nSubjects') && ~isempty(ctx.nSubjects) && size(G,1) ~= ctx.nSubjects
                error('NMRemVarCompModule:targetRows','REMVARCOMP.G must have %d rows; current size is %s.', ctx.nSubjects, mat2str(size(G)));
            end
        end

        function P = resolveProtectedMatrix(~, wcfg, ctx)
            P = [];
            if nargin < 2 || isempty(wcfg) || ~isstruct(wcfg), return; end
            if nargin < 3, ctx = struct(); end
            mats = {};
            if isfield(wcfg,'protectLabel') && logical(wcfg.protectLabel)
                if isfield(ctx,'NM') && isstruct(ctx.NM) && isfield(ctx.NM,'label') && ~isempty(ctx.NM.label)
                    lab = ctx.NM.label;
                    if isvector(lab), lab = lab(:); end
                    mats{end+1} = lab; %#ok<AGROW>
                end
            end
            if isfield(wcfg,'protectedCovariateColumns') && ~isempty(wcfg.protectedCovariateColumns)
                if ~isfield(ctx,'NM') || ~isstruct(ctx.NM) || ~isfield(ctx.NM,'covars') || isempty(ctx.NM.covars)
                    error('NMRemVarCompModule:missingProtectedCovars','Protected NM.covars columns were selected but NM.covars is unavailable.');
                end
                mats{end+1} = ctx.NM.covars(:,wcfg.protectedCovariateColumns); %#ok<AGROW>
            end
            if isfield(wcfg,'protectedWorkspaceVar') && ~isempty(wcfg.protectedWorkspaceVar)
                W = NMWorkspaceTools.resolve(wcfg.protectedWorkspaceVar, 'base');
                if isvector(W), W = W(:); end
                mats{end+1} = W; %#ok<AGROW>
            end
            if isempty(mats), return; end
            P = cat(2, mats{:});
            if ~isnumeric(P) && ~islogical(P)
                error('NMRemVarCompModule:badProtected','Protected covariates must be numeric/logical.');
            end
            if isfield(ctx,'nSubjects') && ~isempty(ctx.nSubjects) && size(P,1) ~= ctx.nSubjects
                error('NMRemVarCompModule:protectedRows','Protected covariates must have %d rows; current size is %s.', ctx.nSubjects, mat2str(size(P)));
            end
            P = double(P);
        end

        function S = subgroupToLegacy(~, cfg, ctx) %#ok<INUSD>
            S = struct();
            switch lower(char(cfg.subgroupMode))
                case 'workspace_training_subset'
                    S.flag = 2;
                    S.ind = NMWorkspaceTools.resolve(cfg.subgroupWorkspaceVar, 'base');
                    S.ind = logical(S.ind(:));
                case 'random_training_subset'
                    S.flag = 3;
                    S.indperc = cfg.subgroupPercent;
                case 'all_calibration'
                    S.flag = 4;
                case 'workspace_calibration_subset'
                    S.flag = 5;
                    S.ind = NMWorkspaceTools.resolve(cfg.subgroupWorkspaceVar, 'base');
                    S.ind = logical(S.ind(:));
                case 'random_calibration_subset'
                    S.flag = 6;
                    S.indperc = cfg.subgroupPercent;
                otherwise
                    S.flag = 1;
            end
        end

        function cfg = subgroupFromLegacy(~, cfg, S)
            if ~isstruct(S) || ~isfield(S,'flag'), return; end
            switch S.flag
                case 2, cfg.subgroupMode = 'workspace_training_subset';
                case 3, cfg.subgroupMode = 'random_training_subset';
                case 4, cfg.subgroupMode = 'all_calibration';
                case 5, cfg.subgroupMode = 'workspace_calibration_subset';
                case 6, cfg.subgroupMode = 'random_calibration_subset';
                otherwise, cfg.subgroupMode = 'all_training';
            end
            if isfield(S,'indperc'), cfg.subgroupPercent = S.indperc; end
            % Imported explicit subset vectors are preserved in legacyREMVARCOMP
            % but are not round-tripped through a workspace variable name.
        end

        function code = redMethodCode(~, v)
            if isnumeric(v), code = v; return; end
            switch lower(char(v))
                case 'fastica',    code = 2;
                case 'waveletpca', code = 3;
                case 'waveletica', code = 4;
                case {'waveletdirect','waveletcoeff','waveletmap'}, code = 5;
                otherwise,         code = 1;
            end
        end
        function name = redMethodName(~, code)
            switch double(code)
                case 2, name = 'fastICA';
                case 3, name = 'waveletPCA';
                case 4, name = 'waveletICA';
                case 5, name = 'waveletDirect';
                otherwise, name = 'PCA';
            end
        end
        function code = corrMethodCode(~, v)
            if isnumeric(v), code = v; return; end
            switch lower(char(v))
                case 'spearman', code = 2;
                case 'anova',    code = 3;
                otherwise,       code = 1;
            end
        end
        function name = corrMethodName(~, code)
            switch code
                case 2, name = 'Spearman';
                case 3, name = 'ANOVA';
                otherwise, name = 'Pearson';
            end
        end
        function code = dimModeCode(~, v)
            if isnumeric(v), code = v; return; end
            if strcmpi(char(v),'fixed'), code = 1; else, code = 3; end
        end
        function name = dimModeName(~, code)
            if isequal(code,1), name = 'fixed'; else, name = 'percentage'; end
        end
        function cfg = validateOrError(obj, cfg, ctx)
            if nargin < 3, ctx = struct(); end
            if isfield(cfg,'legacyPX') && isempty(cfg.legacyPX) && ~isstruct(cfg.legacyPX), cfg.legacyPX = struct(); end
            if isfield(cfg,'legacyREMVARCOMP') && isempty(cfg.legacyREMVARCOMP) && ~isstruct(cfg.legacyREMVARCOMP), cfg.legacyREMVARCOMP = struct(); end
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok, error('NMRemVarCompModule:invalidConfig','%s',strjoin(report.errors,newline)); end
            if strcmpi(cfg.reductionMethod,'fastICA')
                cfg.fastICAParams = obj.normalizeFastICAParams(cfg.fastICAParams, ctx);
            elseif any(strcmpi(cfg.reductionMethod, {'waveletPCA','waveletICA','waveletDirect'}))
                cfg.waveletParams = NMRemVarCompWaveletSubconfigLibrary.normalizeParams(cfg.reductionMethod, cfg.waveletParams, ctx);
            end
        end
    end
end

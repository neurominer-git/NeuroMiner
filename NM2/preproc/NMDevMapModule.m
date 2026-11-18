classdef NMDevMapModule < NMPreprocModule
% NMDevMapModule
% -------------------------------------------------------------------------
% Canonical adapter for NeuroMiner's deviation-mapping preprocessing step
% (legacy command: devmap).  The step learns a normative PLS/sPLS model that
% predicts feature data from an external covariate/design matrix and replaces
% the features by deviations from that normative reconstruction.
% -------------------------------------------------------------------------

    methods
        function obj = NMDevMapModule()
            % NMDevMapModule  Construct the Deviation mapping preprocessing adapter.
            %   Registers module id 'devmap' with legacy branch 'DEVMAP' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('devmap','DEVMAP','Deviation mapping');
            obj.Capabilities.requiresLabels = false;
            obj.Capabilities.usesLabels = false;
            obj.Capabilities.changesFeatureSpace = false;
            obj.Capabilities.supportsHyperparameters = true;
            obj.Capabilities.supportsMissingData = false;
        end

        function spec = configSpec(obj, ctx)
            % configSpec  Return the canonical API/UI schema for Deviation mapping.
            %   Defines editable fields for the module that creates deviation-map features from a
            %   covariate/design-driven normative reconstruction model. The schema feeds
            %   defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            if nargin < 2, ctx = struct(); end %#ok<NASGU>
            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Deviation-based feature weighting/mapping. The module fits a PLS or sparse PLS ', ...
                'normative model from a user-defined covariate/design matrix to the feature matrix and returns ', ...
                'feature deviations from the normative reconstruction.'];
            spec.fields = { ...
                struct('name','algorithm','type','enum','default','pls','label','Normative algorithm', ...
                    'values',{{'pls','spls'}}, ...
                    'help','Choose PLS or sparse PLS. Sparse PLS additionally exposes optimization of component sparsity.'), ...
                struct('name','covariateSource','type','enum','default','workspace','label','Covariate/design matrix source', ...
                    'values',{{'workspace','nm_covars','legacy'}}, ...
                    'help','Choose how the normative-design matrix is supplied for model fitting.'), ...
                struct('name','covariateWorkspaceVar','type','workspace_var','default','','label','Workspace covariate/design matrix', ...
                    'visibleIf',struct('field','covariateSource','equals','workspace'), ...
                    'workspaceFilter',struct('numericOnly',true,'rowCountFromContext','nSubjects'), ...
                    'help','Numeric vector/matrix with one row per subject/case. Do not use the target labels.'), ...
                struct('name','covariateColumns','type','covariate_indices','default',[],'label','Covariate column(s)', ...
                    'allowEmpty',true,'visibleIf',struct('field','covariateSource','equals','nm_covars'), ...
                    'help','Select one or more available covariates. If empty, all available covariates are used.'), ...
                struct('name','covariateDescription','type','string','default','','label','Covariate matrix description', ...
                    'visibleIf',struct('field','covariateSource','notEquals','legacy'), ...
                    'help','Optional short description of the normative covariate/design matrix. If empty, the source name is used.'), ...
                struct('name','subgroupSource','type','enum','default','none','label','Compute normative model in subgroup', ...
                    'values',{{'none','workspace','legacy'}}, ...
                    'help','Optional logical vector defining the cases used to fit the normative model.'), ...
                struct('name','subgroupWorkspaceVar','type','workspace_var','default','','label','Workspace subgroup indicator', ...
                    'visibleIf',struct('field','subgroupSource','equals','workspace'), ...
                    'workspaceFilter',struct('numericOnly',true,'rowCountFromContext','nSubjects'), ...
                    'help','Logical/numeric vector with one element per subject/case. Non-zero entries define the normative-model subgroup.'), ...
                struct('name','sparseU','type','numeric_vector','default',1,'label','sPLS U sparsity parameter(s)', ...
                    'allowEmpty',false,'visibleIf',struct('field','algorithm','equals','spls'), ...
                    'help','Sparse-PLS feature-side sparsity parameter. Valid values range from 1 to approximately the square root of the input dimensionality.'), ...
                struct('name','sparseV','type','numeric_vector','default',1,'label','sPLS V sparsity parameter(s)', ...
                    'allowEmpty',false,'visibleIf',struct('field','algorithm','equals','spls'), ...
                    'help','Sparse-PLS covariate-side sparsity parameter. For a single covariate it is fixed to 1.'), ...
                struct('name','nComponents','type','integer','default',1,'min',1,'label','Number of PLS components','uiHidden',true, ...
                    'help','Number of latent components used by the normative model.'), ...
                struct('name','leaveOneOut','type','boolean','default',false,'label','Leave-one-out normative reconstruction','uiHidden',true, ...
                    'help','Leave-one-out estimation option for the normative model.'), ...
                struct('name','legacyDEVMAP','type','struct','default',struct(),'label','Raw legacy DEVMAP structure','uiHidden',true, ...
                    'help','Imported DEVMAP parameters retained for lossless legacy configuration round trips.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Imported PX hyperparameter settings retained for lossless legacy configuration round trips.') };
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Deviation mapping config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'DEVMAP' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.algorithm: stores the selected learner/preprocessing algorithm inside a normalized configuration.
            % cfg.leaveOneOut: stores the normalized leave one out value in the module configuration.
            % cfg.legacyDEVMAP: stores the normalized legacy devmap value in the module configuration.
            % cfg.nComponents: stores the normalized n components value in the module configuration.
            % cfg.sparseU: stores the normalized sparse u value in the module configuration.
            % cfg.sparseV: stores the normalized sparse v value in the module configuration.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            cfg = obj.validateOrError(cfg, ctx);

            if isfield(cfg,'legacyDEVMAP') && isstruct(cfg.legacyDEVMAP) && ~isempty(fieldnames(cfg.legacyDEVMAP))
                D = cfg.legacyDEVMAP;
            else
                D = struct();
            end

            D.algostr = char(cfg.algorithm);
            [D.covmat, D.covdesc] = obj.resolveCovariateMatrix(cfg, ctx);
            D.glabel  = obj.resolveSubgroup(cfg, ctx);
            if ~isempty(D.covmat)
                D.ncomp = size(D.covmat,2);
            else
                D.ncomp = cfg.nComponents;
            end
            D.loo = logical(cfg.leaveOneOut);

            if strcmpi(D.algostr,'spls')
                D.cu = cfg.sparseU;
                if ~isempty(D.covmat) && size(D.covmat,2) > 1
                    D.cv = cfg.sparseV;
                else
                    % Legacy nk_Devmap_config fixes SPLS-cv to 1 if only one
                    % covariate column is available.
                    D.cv = 1;
                end
            else
                D = obj.removeIfPresent(D, {'cu','cv'});
            end

            PX = obj.buildPX(D);
            D.PX = PX;
            legacy = struct('cmd',obj.Id,'DEVMAP',D,'PX',PX);
        end

        function cfg = fromLegacy(obj, legacy, ctx)
            % fromLegacy  Import legacy Deviation mapping settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            if nargin < 3, ctx = struct(); end
            cfg = obj.defaultConfig(ctx);
            if isempty(legacy), return; end
            if isfield(legacy,'DEVMAP'), D = legacy.DEVMAP; else, D = legacy; end
            cfg.legacyDEVMAP = D;
            if isfield(legacy,'PX') && isstruct(legacy.PX) && ~isempty(legacy.PX)
                cfg.legacyPX = legacy.PX;
            elseif isfield(D,'PX') && isstruct(D.PX) && ~isempty(D.PX)
                cfg.legacyPX = D.PX;
            else
                cfg.legacyPX = struct();
            end

            if isfield(D,'algostr') && ~isempty(D.algostr), cfg.algorithm = char(D.algostr); end
            if isfield(D,'covmat') && ~isempty(D.covmat), cfg.covariateSource = 'legacy'; end
            if isfield(D,'covdesc') && ~isempty(D.covdesc), cfg.covariateDescription = char(D.covdesc); end
            if isfield(D,'glabel') && ~isempty(D.glabel), cfg.subgroupSource = 'legacy'; end
            if isfield(D,'cu') && ~isempty(D.cu), cfg.sparseU = D.cu; end
            if isfield(D,'cv') && ~isempty(D.cv), cfg.sparseV = D.cv; end
            if isfield(D,'ncomp') && ~isempty(D.ncomp), cfg.nComponents = D.ncomp; end
            if isfield(D,'loo') && ~isempty(D.loo), cfg.leaveOneOut = logical(D.loo); end
            cfg = obj.validateOrError(cfg, ctx);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Deviation mapping for scripted or legacy CLI workflows.
            %
            % The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            % permits, subclasses may delegate to legacy nk_input configurators while preserving
            % canonical config output.
            %
            % ctx.NM: provides the current NeuroMiner structure to preprocessing execution helpers without direct global access.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_Devmap_config')
                if ~isfield(ctx,'NM') || isempty(ctx.NM)
                    error('NMDevMapModule:missingNM','Legacy CLI configuration requires ctx.NM.');
                end
                parentstr = obj.getParentString(ctx);
                D = legacy.DEVMAP; PX = legacy.PX;
                [D, PX] = nk_Devmap_config(D, PX, ctx.NM, obj.getDefaultsFlag(ctx), parentstr);
                legacy = struct('cmd',obj.Id,'DEVMAP',D,'PX',PX);
                cfg = obj.fromLegacy(legacy, ctx);
                act = 0;
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx)
            % execute  Fit or apply the Deviation mapping runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfDevMapObj.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end
            if exist('nk_PerfDevMapObj','file') ~= 2
                error('NMDevMapModule:missingBackend','nk_PerfDevMapObj is not on the MATLAB path.');
            end
            switch lower(char(mode))
                case 'fit'
                    cfg = obj.defaultConfig(ctx);
                    if isfield(ctx,'config'), cfg = ctx.config; end
                    legacy = obj.toLegacy(cfg, ctx);
                    IN = struct('DEVMAP',legacy.DEVMAP);
                    [Yout, trained] = nk_PerfDevMapObj(Y, IN);
                case 'transform'
                    if isempty(trained)
                        error('NMDevMapModule:noTrained','devmap transform requires trained parameters.');
                    end
                    Yout = nk_PerfDevMapObj(Y, trained);
                otherwise
                    error('NMDevMapModule:badMode','Unknown execution mode: %s', char(mode));
            end
        end
    end

    methods (Access = private)
        function PX = buildPX(obj, D)
            if strcmpi(D.algostr,'spls')
                PX = [];
                if isfield(D,'cu') && ~isempty(D.cu)
                    PX = obj.pxAdd(PX, D.cu, 'SPLS-cu', 1, '');
                end
                if isfield(D,'cv') && ~isempty(D.cv)
                    PX = obj.pxAdd(PX, D.cv, 'SPLS-cv', 1, '');
                end
                if ~obj.pxHasParams(PX), PX = obj.pxReset(PX); end
            else
                PX = obj.pxReset([]);
            end
        end

        function [C, desc] = resolveCovariateMatrix(~, cfg, ctx)
            desc = char(cfg.covariateDescription);
            switch lower(char(cfg.covariateSource))
                case 'workspace'
                    if isempty(cfg.covariateWorkspaceVar)
                        error('NMDevMapModule:missingCovariateMatrix','devmap requires a workspace covariate/design matrix.');
                    end
                    C = NMWorkspaceTools.resolve(cfg.covariateWorkspaceVar, 'base');
                    if isempty(desc), desc = char(cfg.covariateWorkspaceVar); end
                case 'nm_covars'
                    if ~isfield(ctx,'NM') || ~isstruct(ctx.NM) || ~isfield(ctx.NM,'covars') || isempty(ctx.NM.covars)
                        error('NMDevMapModule:missingCovars','covariateSource=nm_covars requires NM.covars.');
                    end
                    if isempty(cfg.covariateColumns)
                        C = ctx.NM.covars;
                        if isempty(desc), desc = 'NM.covars'; end
                    else
                        C = ctx.NM.covars(:,cfg.covariateColumns);
                        if isempty(desc), desc = sprintf('NM.covars(:,%s)', mat2str(cfg.covariateColumns)); end
                    end
                case 'legacy'
                    if isfield(cfg,'legacyDEVMAP') && isstruct(cfg.legacyDEVMAP) && isfield(cfg.legacyDEVMAP,'covmat')
                        C = cfg.legacyDEVMAP.covmat;
                        if isfield(cfg.legacyDEVMAP,'covdesc') && ~isempty(cfg.legacyDEVMAP.covdesc)
                            desc = cfg.legacyDEVMAP.covdesc;
                        end
                    else
                        C = [];
                    end
                otherwise
                    error('NMDevMapModule:badCovariateSource','Unknown covariate source: %s', char(cfg.covariateSource));
            end
            if ~isempty(C)
                if ~(isnumeric(C) || islogical(C)) || ~ismatrix(C)
                    error('NMDevMapModule:badCovariateMatrix','DEVMAP covariate/design matrix must be numeric/logical and two-dimensional.');
                end
                if isfield(ctx,'nSubjects') && ~isempty(ctx.nSubjects) && ctx.nSubjects > 0 && size(C,1) ~= ctx.nSubjects
                    error('NMDevMapModule:badCovariateRows','DEVMAP covariate matrix has %d rows but the active NM context expects %d subjects/cases.', size(C,1), ctx.nSubjects);
                end
            end
            if isempty(desc), desc = 'undefined'; end
        end

        function g = resolveSubgroup(~, cfg, ctx)
            switch lower(char(cfg.subgroupSource))
                case 'none'
                    g = [];
                case 'workspace'
                    if isempty(cfg.subgroupWorkspaceVar)
                        error('NMDevMapModule:missingSubgroup','subgroupSource=workspace requires subgroupWorkspaceVar.');
                    end
                    g = NMWorkspaceTools.resolve(cfg.subgroupWorkspaceVar, 'base');
                    if ~(isnumeric(g) || islogical(g)) || ~isvector(g)
                        error('NMDevMapModule:badSubgroup','DEVMAP subgroup indicator must be a numeric/logical vector.');
                    end
                    g = logical(g(:));
                    if isfield(ctx,'nSubjects') && ~isempty(ctx.nSubjects) && ctx.nSubjects > 0 && numel(g) ~= ctx.nSubjects
                        error('NMDevMapModule:badSubgroupRows','DEVMAP subgroup has %d elements but the active NM context expects %d subjects/cases.', numel(g), ctx.nSubjects);
                    end
                case 'legacy'
                    if isfield(cfg,'legacyDEVMAP') && isstruct(cfg.legacyDEVMAP) && isfield(cfg.legacyDEVMAP,'glabel')
                        g = cfg.legacyDEVMAP.glabel;
                    else
                        g = [];
                    end
                otherwise
                    error('NMDevMapModule:badSubgroupSource','Unknown subgroup source: %s', char(cfg.subgroupSource));
            end
        end

        function cfg = validateOrError(obj, cfg, ctx)
            if nargin < 3, ctx = struct(); end
            if isfield(cfg,'legacyPX') && isempty(cfg.legacyPX) && ~isstruct(cfg.legacyPX), cfg.legacyPX = struct(); end
            if isfield(cfg,'legacyDEVMAP') && isempty(cfg.legacyDEVMAP) && ~isstruct(cfg.legacyDEVMAP), cfg.legacyDEVMAP = struct(); end
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok, error('NMDevMapModule:invalidConfig','%s',strjoin(report.errors,newline)); end
            if ~any(strcmpi(cfg.algorithm, {'pls','spls'}))
                error('NMDevMapModule:badAlgorithm','DEVMAP algorithm must be pls or spls.');
            end
        end

        function S = removeIfPresent(~, S, names)
            for i = 1:numel(names)
                if isfield(S,names{i}), S = rmfield(S,names{i}); end
            end
        end
    end
end

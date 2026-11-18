classdef NMRankFeatModule < NMPreprocModule
% NMRankFeatModule
% -------------------------------------------------------------------------
% Canonical adapter for NeuroMiner feature ranking / weighting.
%
% The module owns a clean canonical configuration, but still exports to the
% legacy ACTPARAM.RANK/PX structure and delegates numerical work to
% nk_PerfFeatRankObj. It is a producer step: the immediately following
% extfeat step consumes the computed weighting vector.
% -------------------------------------------------------------------------

    methods
        function obj = NMRankFeatModule()
            % NMRankFeatModule  Construct the Feature ranking / weighting preprocessing adapter.
            %   Registers module id 'rankfeat' with legacy branch 'RANK' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('rankfeat','RANK','Feature ranking / weighting');
            obj.Capabilities.requiresLabels = true;
            obj.Capabilities.usesLabels = true;
            obj.Capabilities.changesFeatureSpace = false;
            obj.Capabilities.supportsHyperparameters = true;
            obj.Capabilities.supportsMissingData = true;
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Feature ranking / weighting.
            %   Defines editable fields for the module that configures feature ranking, feature
            %   weighting, or external ranking import before downstream selection. The schema feeds
            %   defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Compute a feature ranking / weighting vector in the training fold. ', ...
                'The resulting weights are consumed by an immediately following extfeat action step.'];
            spec.fields = { ...
                struct('name','algorithm','type','enum','default','pearson','label','Ranking algorithm', ...
                    'values',{{'pearson','spearman','auc','fscore','anova','pls','relief','imrelief','idetect','simba','gflip','libsvm','liblin','rgs','feast','varfeat','extern','extern2'}}, ...
                    'help','Select the ranking or feature-weighting algorithm; algorithm-specific options are in algorithmParams.'), ...
                struct('name','weightMethod','type','enum','default','upweight','label','Use ranking to', ...
                    'values',{{'upweight','downweight'}}, ...
                    'visibleIf',struct('field','algorithm','notIn',{{'extern','extern2','pls'}}), ...
                    'help','Choose whether the computed feature ranking increases or decreases feature weights.'), ...
                struct('name','labelSource','type','enum','default','nm_target','label','Ranking target source', ...
                    'values',{{'nm_target','workspace','legacy'}}, ...
                    'visibleIf',struct('field','algorithm','notIn',{{'extern','extern2','pls'}}), ...
                    'help','Use the canonical NeuroMiner target unless a different workspace label should define the ranking target.'), ...
                struct('name','labelVar','type','workspace_var','default','','label','Workspace label variable', ...
                    'visibleIf',struct('field','labelSource','equals','workspace','andField','algorithm','andNotIn',{{'extern','extern2','pls'}}), ...
                    'workspaceFilter',struct('numericOnly',true,'columnVectorRowsFromContext','nSubjects'), ...
                    'autoSetTaskField','rankType', ...
                    'autoSetTaskHintField','rankTaskHint', ...
                    'help','Numeric/logical vector with one row per subject. The task type is auto-detected but can be overridden.'), ...
                struct('name','rankType','type','enum','default','auto','label','Task induced by custom target', ...
                    'values',{{'auto','classification','regression','task'}}, ...
                    'uiValues',{{'auto','classification','regression'}}, ...
                    'visibleIf',struct('field','labelSource','equals','workspace','andField','algorithm','andNotIn',{{'extern','extern2','pls'}},'nonEmptyField','labelVar'), ...
                    'help','Only needed when the ranking target is not the canonical NM label. auto inspects the selected workspace label and chooses classification or regression conservatively.'), ...
                struct('name','rankTaskHint','type','readonly','default','','label','Auto-detected target type', ...
                    'visibleIf',struct('field','labelSource','equals','workspace','andField','algorithm','andNotIn',{{'extern','extern2','pls'}},'nonEmptyField','labelVar'), ...
                    'help','Read-only task type inferred from the selected workspace ranking target.'), ...
                struct('name','externalSource','type','enum','default','workspace','label','External ranking source', ...
                    'values',{{'workspace','file','nm_weight_map','legacy'}}, ...
                    'visibleIf',struct('field','algorithm','equals','extern'), ...
                    'help','Select a workspace vector/matrix, a new image file, an existing NeuroMiner weighting map, or a previously imported ranking definition.'), ...
                struct('name','externalWorkspaceVar','type','workspace_var','default','','label','External ranking workspace variable', ...
                    'visibleIf',struct('field','algorithm','equals','extern','andField','externalSource','andEquals','workspace'), ...
                    'workspaceFilter',struct('numericOnly',true,'featureCompatible',true), ...
                    'help','Numeric vector with numel = number of active features, or numeric matrix with size(...,2) equal to the active feature count.'), ...
                struct('name','externalFile','type','file_path','default','','label','External NIfTI/GIfTI/surface ranking file', ...
                    'visibleIf',struct('field','algorithm','equals','extern','andField','externalSource','andEquals','file'), ...
                    'fileFilter','*.nii;*.nii.gz;*.img;*.hdr;*.gii;*.mgz;*.mgh', ...
                    'help','The selected image is loaded and vectorized against the active NeuroMiner mask before ranking is applied.'), ...
                struct('name','externalFileResolvedMat','type','string','default','','label','Resolved external ranking sidecar','uiHidden',true, ...
                    'help','Read-only path of the resolved external ranking MAT sidecar.'), ...
                struct('name','externalFileImportSummary','type','string','default','','label','External ranking import summary','uiHidden',true, ...
                    'help','Read-only summary of the external ranking file import.'), ...
                struct('name','externalFileThresholdSummary','type','string','default','','label','External ranking threshold summary','uiHidden',true, ...
                    'help','Read-only summary of thresholding the imported ranking map.'), ...
                struct('name','externalNMWeightIndex','type','integer','default',1,'min',1,'label','Dataset weighting image index', ...
                    'visibleIf',struct('field','algorithm','equals','extern','andField','externalSource','andEquals','nm_weight_map'), ...
                    'help','Index of the existing NM weighting image selected for external ranking.'), ...
                struct('name','takeAbs','type','boolean','default',true,'label','Postprocess: absolute weights', ...
                    'help','Use absolute feature-weight magnitudes in ranking postprocessing.'), ...
                struct('name','scaleWeights','type','boolean','default',true,'label','Postprocess: scale weights to [0,1]', ...
                    'help','Rescale ranking weights to the unit interval during postprocessing.'), ...
                struct('name','replaceZeroNaNWithRealMin','type','boolean','default',true,'label','Postprocess: replace zeros/NaNs with realmin', ...
                    'help','Replace zero or NaN ranking weights with realmin during postprocessing.'), ...
                struct('name','replaceInfWithMax','type','boolean','default',true,'label','Postprocess: replace Infs with max', ...
                    'help','Replace infinite ranking weights with the maximum finite weight during postprocessing.'), ...
                struct('name','algorithmParams','type','subconfig','default',struct(),'label','Algorithm-specific parameters', ...
                    'subconfigSelector','algorithm', ...
                    'subconfigSpecs', NMRankSubconfigLibrary.specs(ctx), ...
                    'help','Open the settings page for the selected ranking algorithm.'), ...
                struct('name','legacyRANK','type','struct','default',struct(),'label','Raw legacy RANK structure','uiHidden',true, ...
                    'help','Imported RANK settings retained for legacy configuration round trips.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Imported PX optimization parameters retained for legacy configuration round trips.') };
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Feature ranking / weighting config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'RANK' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.algorithm: stores the selected learner/preprocessing algorithm inside a normalized configuration.
            % cfg.legacyPX: preserves legacy PX parameters when a module cannot yet express every field canonically.
            % cfg.legacyRANK: stores the normalized legacy rank value in the module configuration.
            % cfg.replaceInfWithMax: stores the normalized replace inf with max value in the module configuration.
            % cfg.replaceZeroNaNWithRealMin: stores the normalized replace zero nanwith real min value in the module configuration.
            % cfg.scaleWeights: stores the normalized scale weights value in the module configuration.
            % cfg.takeAbs: stores the normalized take abs value in the module configuration.
            % cfg.weightMethod: stores the normalized weight method value in the module configuration.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            cfg = obj.parseConfig(cfg);

            if isfield(cfg,'legacyRANK') && isstruct(cfg.legacyRANK) && ~isempty(fieldnames(cfg.legacyRANK))
                RANK = cfg.legacyRANK;
            else
                RANK = struct();
            end
            if isfield(cfg,'legacyPX') && isstruct(cfg.legacyPX) && ~isempty(fieldnames(cfg.legacyPX))
                PX = cfg.legacyPX;
            else
                PX = [];
            end

            RANK.weightmethod = obj.weightMethodCode(cfg.weightMethod);
            RANK.algostr = lower(char(cfg.algorithm));
            RANK.TakeAbs = logical(cfg.takeAbs);
            RANK.Scale = logical(cfg.scaleWeights);
            RANK.ReplZeroNaNwithRealMin = logical(cfg.replaceZeroNaNWithRealMin);
            RANK.ReplInfwithMax = logical(cfg.replaceInfWithMax);

            % Legacy compatibility for old displays that distinguish Pearson
            % and Spearman through both algostr and Pearson.
            if strcmpi(RANK.algostr,'pearson')
                RANK.Pearson = 1;
            elseif strcmpi(RANK.algostr,'spearman')
                RANK.Pearson = 2;
            end

            pxAddFcn = @(PX0, vals, desc, typ, mode) obj.pxAdd(PX0, vals, desc, typ, mode);
            [RANK, PXalg] = NMRankSubconfigLibrary.applyToLegacy(RANK, cfg, ctx, pxAddFcn);
            if obj.pxHasParams(PXalg), PX = PXalg; end

            isExternal = any(strcmpi(RANK.algostr, {'extern','extern2'}));
            if isExternal
                RANK = obj.configureExternalRanking(RANK, cfg, ctx);
                if isfield(RANK,'label'), RANK = rmfield(RANK,'label'); end
                if isfield(RANK,'labeldesc'), RANK = rmfield(RANK,'labeldesc'); end
                if isfield(RANK,'ranktype_desc'), RANK = rmfield(RANK,'ranktype_desc'); end
            elseif ~strcmpi(RANK.algostr,'pls')
                [label, labeldesc, ranktype, taskHint] = obj.resolveLabel(cfg, ctx, RANK);
                RANK.ranktype = ranktype;
                if ~isempty(label)
                    RANK.label = label;
                    RANK.labeldesc = labeldesc;
                elseif ~isfield(RANK,'labeldesc')
                    RANK.labeldesc = 'unresolved target label';
                end
                if ~isempty(taskHint)
                    RANK.ranktype_desc = taskHint;
                end
            else
                RANK.ranktype = obj.resolveRankTypeCode(cfg, [], ctx, RANK);
                if ~isfield(RANK,'labeldesc')
                    RANK.labeldesc = 'PLS target matrix';
                end
            end

            PX = obj.buildPXFromRank(RANK, PX);
            legacy = struct('cmd',obj.Id,'RANK',RANK);
            if ~isempty(PX), legacy.PX = PX; end
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Feature ranking / weighting settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isempty(legacy), return; end
            if isfield(legacy,'RANK'), RANK = legacy.RANK; else, RANK = legacy; end
            cfg.legacyRANK = RANK;
            if isfield(legacy,'PX') && isstruct(legacy.PX) && ~isempty(legacy.PX)
                cfg.legacyPX = legacy.PX;
            else
                % Older NM configurations may contain PX = [] for ranking
                % methods without hyperparameter shelves. Keep the canonical
                % hidden field structurally valid; do not treat empty PX as
                % an error during legacy import.
                cfg.legacyPX = struct();
            end

            if isfield(RANK,'algostr') && ~isempty(RANK.algostr)
                cfg.algorithm = lower(char(RANK.algostr));
            end
            try
                cfg.algorithmParams = NMRankSubconfigLibrary.fromLegacy(cfg.algorithm, RANK, ctx);
            catch ME
                warning('NMRankFeatModule:subconfigImport', ...
                    'Could not import nested rankfeat subconfig for %s: %s', cfg.algorithm, ME.message);
                cfg.algorithmParams = struct();
            end

            if strcmpi(cfg.algorithm,'extern')
                if isfield(RANK,'V') && ~isempty(RANK.V) && ~isfield(RANK,'EXTERN')
                    cfg.externalSource = 'nm_weight_map';
                    if isnumeric(RANK.V), cfg.externalNMWeightIndex = RANK.V(1); end
                elseif isfield(RANK,'F') && ~isempty(RANK.F)
                    cfg.externalSource = 'file';
                    cfg.externalFile = char(RANK.F);
                elseif isfield(RANK,'EXTERN')
                    cfg.externalSource = 'legacy';
                end
            end
            if isfield(RANK,'ranktype')
                cfg.rankType = obj.rankTypeName(RANK.ranktype);
            end
            if isfield(RANK,'weightmethod')
                cfg.weightMethod = obj.weightMethodName(RANK.weightmethod);
            end
            if isfield(RANK,'TakeAbs'), cfg.takeAbs = logical(RANK.TakeAbs); end
            if isfield(RANK,'Scale'), cfg.scaleWeights = logical(RANK.Scale); end
            if isfield(RANK,'ReplZeroNaNwithRealMin'), cfg.replaceZeroNaNWithRealMin = logical(RANK.ReplZeroNaNwithRealMin); end
            if isfield(RANK,'ReplInfwithMax'), cfg.replaceInfWithMax = logical(RANK.ReplInfwithMax); end
            if isfield(RANK,'labeldesc') && ~strcmpi(RANK.labeldesc,'NM target label')
                cfg.labelSource = 'legacy';
            end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Feature ranking / weighting for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_Rank_config')
                [NM, varind] = obj.resolveNM(ctx);
                if isempty(NM)
                    error('NMRankFeatModule:noNM','Legacy rankfeat CLI configuration requires ctx.NM from the preprocessing context.');
                end
                parentstr = obj.getParentString(ctx);
                [legacy.RANK, PX] = nk_Rank_config(legacy.RANK, obj.getLegacyPX(legacy), NM, varind, [], parentstr);
                if ~isempty(PX), legacy.PX = PX; elseif isfield(legacy,'PX'), legacy = rmfield(legacy,'PX'); end
                legacy.cmd = obj.Id;
                cfg = obj.fromLegacy(legacy, ctx);
                act = 0;
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx)
            % execute  Execute the no-op feature-copy adapter.
            %
            % Returns the input feature matrix unchanged while preserving the trained-state shape
            % expected by modular fit/transform smoke tests.
            %
            % ctx.config: provides the module configuration currently being validated or executed.
            % ctx.curlabel: exposes the curlabel execution-context value to preprocessing/runtime code.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end
            Yout = Y;
            switch lower(char(mode))
                case 'fit'
                    cfg = obj.defaultConfig();
                    if isfield(ctx,'config'), cfg = ctx.config; end
                    legacy = obj.toLegacy(cfg, ctx);
                    RANK = legacy.RANK;
                    if isfield(ctx,'curlabel') && ~isempty(ctx.curlabel)
                        RANK.curlabel = ctx.curlabel;
                    elseif isfield(RANK,'label') && ~isempty(RANK.label)
                        RANK.curlabel = RANK.label;
                    end
                    if ~isfield(RANK,'curlabel') || isempty(RANK.curlabel)
                        error('NMRankFeatModule:noLabel','rankfeat execution requires RANK.curlabel, RANK.label, or ctx.curlabel.');
                    end
                    if isfield(legacy,'PX') && ~isempty(legacy.PX)
                        RANK = obj.attachPxToRank(RANK, legacy.PX);
                    end
                    trained = nk_PerfFeatRankObj(Y, RANK);
                case 'transform'
                    % Ranking itself does not change the feature matrix.
                    if isempty(trained)
                        error('NMRankFeatModule:noTrained','rankfeat transform requires trained ranking parameters.');
                    end
                otherwise
                    error('NMRankFeatModule:badMode','Unknown execution mode: %s', char(mode));
            end
        end
    end

    methods
        function out = importExternalRankingForUI(obj, cfg, ctx, tmpDir)
            % importExternalRankingForUI  Import an external ranking/weight vector for UI-assisted rank-feature configuration.
            %
            % Reads the user-selected source, validates feature length where possible, and returns
            % canonical config fragments consumed by rank-feature UI state.
            %
            % importExternalRankingForUI
            % Live browser-bridge entry point for external image ranking maps.
            %
            % This performs the executable legacy nk_Rank_config behaviour
            % during the active UI session, but does not send the large
            % RANK.EXTERN vector through JSON. Instead, the resolved RANK
            % structure is stored as a MATLAB .mat sidecar and the browser
            % receives only a compact config patch plus a green/red status
            % message.
            %
            % cfg.legacyRANK: stores the normalized legacy rank value in the module configuration.
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(tmpDir), tmpDir = tempdir; end
            if ~exist(tmpDir,'dir'), mkdir(tmpDir); end

            cfg = obj.parseConfig(cfg);
            RANK = struct();
            if isfield(cfg,'legacyRANK') && isstruct(cfg.legacyRANK) && ~isempty(fieldnames(cfg.legacyRANK))
                RANK = cfg.legacyRANK;
            end
            RANK.algostr = 'extern';
            RANK = obj.configureExternalRankingFromFile(RANK, cfg, ctx);

            token = ['rank_external_' strrep(char(java.util.UUID.randomUUID()),'-','_')];
            matFile = fullfile(tmpDir, [token '.mat']);
            save(matFile, 'RANK', '-v7');

            extSize = size(RANK.EXTERN);
            msg = sprintf('External ranking image loaded into NM parameter workspace: %s -> RANK.EXTERN [%s %s].', ...
                char(RANK.F), obj.sizeString(extSize), class(RANK.EXTERN));
            patch = struct();
            patch.externalFile = char(RANK.F);
            patch.externalFileResolvedMat = matFile;
            patch.externalFileImportSummary = msg;
            if isfield(RANK,'THRESH')
                try
                    patch.externalFileThresholdSummary = NMConfigTools.formatValue(RANK.THRESH);
                catch
                    patch.externalFileThresholdSummary = '<resolved>';
                end
            end
            out = struct('ok',true, ...
                         'message',msg, ...
                         'matFile',matFile, ...
                         'file',char(RANK.F), ...
                         'externClass',class(RANK.EXTERN), ...
                         'externSize',extSize, ...
                         'configPatch',patch);
        end
    end

    methods (Access = private)
        function RANK = configureExternalRanking(obj, RANK, cfg, ctx)
            src = 'workspace';
            if isfield(cfg,'externalSource') && ~isempty(cfg.externalSource), src = lower(char(cfg.externalSource)); end

            switch src
                case 'workspace'
                    if isfield(cfg,'externalWorkspaceVar') && ~isempty(cfg.externalWorkspaceVar)
                        val = NMWorkspaceTools.resolve(cfg.externalWorkspaceVar, 'base');
                        nFeat = obj.contextFeatureCount(ctx);
                        NMWorkspaceTools.assertFeatureCompatible(val, nFeat, sprintf('External ranking variable %s', cfg.externalWorkspaceVar));
                        RANK.EXTERN = val;
                        if isfield(RANK,'F'), RANK = rmfield(RANK,'F'); end
                        if isfield(RANK,'V'), RANK = rmfield(RANK,'V'); end
                    elseif ~isfield(RANK,'EXTERN')
                        error('NMRankFeatModule:missingExternalRanking', ...
                            'External ranking selected, but no externalWorkspaceVar is defined and legacyRANK.EXTERN is absent.');
                    else
                        nFeat = obj.contextFeatureCount(ctx);
                        NMWorkspaceTools.assertFeatureCompatible(RANK.EXTERN, nFeat, 'legacyRANK.EXTERN');
                    end

                case 'nm_weight_map'
                    [NM, varind] = obj.resolveNM(ctx);
                    if isempty(NM) || ~isfield(NM,'datadescriptor') || ...
                            numel(NM.datadescriptor) < varind || ~isstruct(NM.datadescriptor{varind}) || ...
                            ~isfield(NM.datadescriptor{varind},'Yw') || isempty(NM.datadescriptor{varind}.Yw)
                        error('NMRankFeatModule:noNMWeightMap', ...
                            'The active modality does not expose the backend-consumed NM.datadescriptor{%g}.Yw weighting matrix.', varind);
                    end
                    idx = 1;
                    if isfield(cfg,'externalNMWeightIndex') && ~isempty(cfg.externalNMWeightIndex), idx = cfg.externalNMWeightIndex; end
                    nMaps = size(NM.datadescriptor{varind}.Yw, 1);
                    if idx > nMaps
                        error('NMRankFeatModule:badNMWeightIndex', ...
                            'Requested NM weighting map index %g, but NM.datadescriptor{%g}.Yw contains %g map row(s).', idx, varind, nMaps);
                    end
                    RANK.V = idx;
                    for staleField = {'EXTERN','EXTERN_source','EXTERN_index','F'}
                        if isfield(RANK,staleField{1}), RANK = rmfield(RANK,staleField{1}); end
                    end

                case 'file'
                    % The resolved RANK.EXTERN already belongs to this selected file.
                    % Ordinary preprocessing edits must not reopen a NIfTI and
                    % re-vectorize it against the active brain mask.
                    if isfield(RANK,'F') && isfield(RANK,'EXTERN') && ... % nm2-allow: NMRankFeatModule.fromLegacy preserves optional resolved image payload written by configureExternalRankingFromFile
                            ~isempty(RANK.EXTERN) && ...
                            strcmp(obj.cleanExternalFilePath(RANK.F), obj.cleanExternalFilePath(cfg.externalFile))
                        NMWorkspaceTools.assertFeatureCompatible(RANK.EXTERN, ...
                            obj.contextFeatureCount(ctx), 'resolved external ranking image');
                    else
                        RANK = obj.configureExternalRankingFromFile(RANK, cfg, ctx);
                    end

                case 'legacy'
                    if ~isfield(RANK,'EXTERN') && ~isfield(RANK,'V')
                        error('NMRankFeatModule:legacyExternalMissing', 'externalSource=legacy requires legacyRANK.EXTERN or legacyRANK.V.');
                    end
                    if isfield(RANK,'EXTERN')
                        nFeat = obj.contextFeatureCount(ctx);
                        NMWorkspaceTools.assertFeatureCompatible(RANK.EXTERN, nFeat, 'legacyRANK.EXTERN');
                    end

                otherwise
                    error('NMRankFeatModule:badExternalSource','Unknown externalSource: %s.', src);
            end
        end

        function RANK = configureExternalRankingFromFile(obj, RANK, cfg, ctx)
            % Reproduce the executable legacy behaviour of nk_Rank_config for
            % external image-based ranking maps. The legacy configurator did
            % not only store the selected filename; it immediately read the
            % image/surface and resolved it into RANK.EXTERN in the active NM
            % feature space.
            RANK0 = obj.tryLoadResolvedExternalRankingSidecar(cfg, ctx);
            if ~isempty(RANK0)
                RANK = RANK0;
                return;
            end

            filePath = '';
            if isfield(cfg,'externalFile') && ~isempty(cfg.externalFile)
                filePath = char(cfg.externalFile);
            end

            imgtype = obj.resolveExternalImageType(ctx);

            if isempty(filePath)
                if ~obj.functionExists('nk_FileSelector')
                    error('NMRankFeatModule:noFileSelector', ...
                        'externalSource=file requires externalFile or nk_FileSelector on the MATLAB path.');
                end
                [F, V0] = nk_FileSelector(1, imgtype, 'Select Ranking Map', '.*');
            else
                filePath = obj.cleanExternalFilePath(filePath);
                obj.assertExternalFileExists(filePath);
                [F, V0] = obj.directReadExternalRankingFile(filePath, imgtype);
            end

            if isempty(F)
                error('NMRankFeatModule:externalFileCancelled', 'No external ranking image was selected.');
            end

            RANK.F = F;
            RANK.V = {V0};

            switch lower(char(imgtype))
                case {'spm','nifti'}
                    if ~obj.functionExists('spm_vol')
                        error('NMRankFeatModule:noSPM', 'SPM is required to import NIfTI/SPM external ranking images.');
                    end
                    if ~obj.functionExists('nk_ReturnSubSpaces')
                        error('NMRankFeatModule:noReturnSubSpaces', ...
                            'nk_ReturnSubSpaces is required to vectorize external ranking images in the active NM mask.');
                    end
                    [brainmask, Thresh] = obj.requireSpatialGeometry(ctx);
                    Vm = spm_vol(brainmask);
                    [RANK.EXTERN, RANK.THRESH] = nk_ReturnSubSpaces(RANK.V, Vm, 1, 1, Thresh);

                case 'surf'
                    if isfield(RANK.V{1}, 'cdata')
                        RANK.EXTERN = RANK.V{1}.cdata;
                    else
                        if ~obj.functionExists('MRIread')
                            error('NMRankFeatModule:noMRIread', ...
                                'Surface external ranking import requires cdata from SurfaceReader or MRIread on the MATLAB path.');
                        end
                        RANK.EXTERN = MRIread(RANK.F);
                    end

                otherwise
                    error('NMRankFeatModule:badImageType', 'Unsupported external ranking image type: %s.', char(imgtype));
            end

            nFeat = obj.contextFeatureCount(ctx);
            NMWorkspaceTools.assertFeatureCompatible(RANK.EXTERN, nFeat, 'image-derived RANK.EXTERN');
        end


        function RANK = tryLoadResolvedExternalRankingSidecar(obj, cfg, ctx)
            RANK = [];
            if ~isfield(cfg,'externalFileResolvedMat') || isempty(cfg.externalFileResolvedMat), return; end
            matFile = char(cfg.externalFileResolvedMat);
            if exist(matFile,'file') ~= 2, return; end
            S = load(matFile, 'RANK');
            if ~isfield(S,'RANK') || ~isstruct(S.RANK) || ~isfield(S.RANK,'EXTERN') || isempty(S.RANK.EXTERN)
                error('NMRankFeatModule:invalidResolvedSidecar', ...
                    'Resolved external-ranking sidecar does not contain a non-empty RANK.EXTERN: %s', matFile);
            end
            if isfield(cfg,'externalFile') && ~isempty(cfg.externalFile) && isfield(S.RANK,'F') && ~isempty(S.RANK.F)
                cfgFile = obj.cleanExternalFilePath(cfg.externalFile);
                rankFile = obj.cleanExternalFilePath(S.RANK.F);
                if ~isempty(cfgFile) && ~strcmpi(cfgFile, rankFile)
                    return;
                end
            end
            nFeat = obj.contextFeatureCount(ctx);
            NMWorkspaceTools.assertFeatureCompatible(S.RANK.EXTERN, nFeat, 'sidecar image-derived RANK.EXTERN');
            RANK = S.RANK;
        end

        function imgtype = resolveExternalImageType(~, ctx)
            if ~isstruct(ctx) || ~isfield(ctx,'datasource') || isempty(ctx.datasource)
                error('NMRankFeatModule:missingDatasource', ...
                    'External ranking image import requires the canonical preprocessing-context datasource.');
            end
            imgtype = char(ctx.datasource);
            if ~any(strcmp(imgtype, {'spm','nifti','surf'}))
                error('NMRankFeatModule:badImageType', ...
                    'External ranking image import is not defined for datasource %s.', imgtype);
            end
        end

        function [F, V0] = directReadExternalRankingFile(obj, filePath, imgtype)
            F = obj.cleanExternalFilePath(filePath);
            switch lower(char(imgtype))
                case {'spm','nifti'}
                    if obj.functionExists('nk_CheckComprFile')
                        F = nk_CheckComprFile(F);
                    end
                    if ~obj.functionExists('spm_vol')
                        error('NMRankFeatModule:noSPM', 'SPM is required to read NIfTI/SPM external ranking images.');
                    end
                    V0 = spm_vol(F);
                case 'surf'
                    if obj.functionExists('SurfaceReader')
                        V0 = SurfaceReader(F);
                    elseif obj.functionExists('MRIread')
                        V0 = MRIread(F);
                    else
                        error('NMRankFeatModule:noSurfaceReader', ...
                            'Surface external ranking import requires SurfaceReader or MRIread on the MATLAB path.');
                    end
                otherwise
                    error('NMRankFeatModule:badImageType', 'Unsupported external ranking image type: %s.', char(imgtype));
            end
        end

        function filePath = cleanExternalFilePath(~, filePath)
            if isempty(filePath), return; end
            if iscell(filePath), filePath = char(filePath{1}); end
            filePath = char(filePath);
            filePath = deblank(filePath);
            if size(filePath,1) > 1
                filePath = deblank(filePath(1,:));
            end
            filePath = regexprep(filePath,',\d+$','');
        end

        function assertExternalFileExists(obj, filePath)
            fp = obj.cleanExternalFilePath(filePath);
            if isempty(fp) || exist(fp,'file') ~= 2
                error('NMRankFeatModule:externalFileNotFound', 'External ranking image file not found: %s', fp);
            end
        end

        function [brainmask, Thresh] = requireSpatialGeometry(~, ctx)
            if ~isstruct(ctx) || ~isfield(ctx,'brainmask') || isempty(ctx.brainmask)
                error('NMRankFeatModule:noBrainmask', ...
                    'External volumetric ranking import requires ctx.brainmask from NMPreprocContext.');
            end
            if ~isfield(ctx,'spatialThresh') || isempty(ctx.spatialThresh)
                error('NMRankFeatModule:noThresholdContext', ...
                    'External volumetric ranking import requires ctx.spatialThresh from NMPreprocContext.');
            end
            brainmask = ctx.brainmask;
            Thresh = ctx.spatialThresh;
        end

        function nFeat = contextFeatureCount(~, ctx)
            nFeat = [];
            if isstruct(ctx) && isfield(ctx,'nFeatures') && ~isempty(ctx.nFeatures), nFeat = ctx.nFeatures; end
        end

        function [label, labeldesc, ranktype, taskHint] = resolveLabel(obj, cfg, ctx, RANK)
            label = []; labeldesc = ''; taskHint = '';
            ranktype = 1;
            switch lower(char(cfg.labelSource))
                case 'nm_target'
                    defaultsOnly = isstruct(ctx) && isfield(ctx,'defaultsOnly') && logical(ctx.defaultsOnly);
                    if defaultsOnly && (~isfield(ctx,'activeLabel') || isempty(ctx.activeLabel))
                        label = [];
                        labeldesc = 'unresolved target label';
                        taskHint = '';
                    else
                        if ~isstruct(ctx) || ~isfield(ctx,'activeLabel') || isempty(ctx.activeLabel) || ...
                                ~isfield(ctx,'modeflag') || isempty(ctx.modeflag)
                            error('NMRankFeatModule:noTargetContext', ...
                                'Canonical NM-target ranking requires activeLabel and modeflag from NMPreprocContext.');
                        end
                        label = ctx.activeLabel;
                        labeldesc = 'NM target label';
                        taskHint = char(ctx.modeflag);
                    end
                    ranktype = 1;

                case 'workspace'
                    if ~isempty(cfg.labelVar)
                        try
                            label = evalin('base', cfg.labelVar);
                            labeldesc = sprintf('workspace variable: %s', cfg.labelVar);
                        catch ME
                            error('NMRankFeatModule:badWorkspaceVar','Could not resolve label workspace variable %s: %s', cfg.labelVar, ME.message);
                        end
                    end
                    [ranktype, taskHint] = obj.resolveCustomLabelRankType(cfg, label);

                case 'legacy'
                    if isfield(RANK,'label'), label = RANK.label; end
                    if isfield(RANK,'labeldesc'), labeldesc = RANK.labeldesc; else, labeldesc = 'legacy label'; end
                    if isfield(RANK,'ranktype') && isnumeric(RANK.ranktype) && isscalar(RANK.ranktype)
                        ranktype = RANK.ranktype;
                    else
                        [ranktype, taskHint] = obj.resolveCustomLabelRankType(cfg, label);
                    end
            end
        end

        function [ranktype, taskHint] = resolveCustomLabelRankType(obj, cfg, label)
            taskHint = '';
            requested = 'auto';
            if isfield(cfg,'rankType') && ~isempty(cfg.rankType), requested = lower(char(cfg.rankType)); end
            switch requested
                case 'classification'
                    ranktype = 2; taskHint = 'classification (user override)'; return;
                case 'regression'
                    ranktype = 3; taskHint = 'regression (user override)'; return;
            end
            info = NMWorkspaceTools.inferTaskType(label);
            switch lower(info.taskType)
                case 'classification'
                    ranktype = 2;
                case 'regression'
                    ranktype = 3;
                otherwise
                    error('NMRankFeatModule:ambiguousCustomTarget', ...
                        ['Could not infer whether the custom ranking target is categorical or continuous. ', ...
                         'Set rankType to classification or regression explicitly. Reason: %s'], info.reason);
            end
            taskHint = sprintf('%s (auto: %s)', info.taskType, info.reason);
        end

        function ranktype = resolveRankTypeCode(obj, cfg, label, ctx, RANK) %#ok<INUSL>
            if nargin < 5, RANK = struct(); end
            src = 'nm_target';
            if isfield(cfg,'labelSource') && ~isempty(cfg.labelSource), src = lower(char(cfg.labelSource)); end
            switch src
                case 'nm_target'
                    ranktype = 1;
                case 'workspace'
                    [ranktype, ~] = obj.resolveCustomLabelRankType(cfg, label);
                case 'legacy'
                    if isstruct(RANK) && isfield(RANK,'ranktype') && isnumeric(RANK.ranktype) && isscalar(RANK.ranktype)
                        ranktype = RANK.ranktype;
                    else
                        [ranktype, ~] = obj.resolveCustomLabelRankType(cfg, label);
                    end
                otherwise
                    ranktype = 1;
            end
        end

        function [NMout, varind] = resolveNM(~, ctx)
            NMout = []; varind = 1;
            if ~isstruct(ctx), return; end
            if isfield(ctx,'NM'), NMout = ctx.NM; end
            if isfield(ctx,'varind') && ~isempty(ctx.varind), varind = ctx.varind; end
        end


        function s = sizeString(~, sz)
            sz = double(sz);
            if isempty(sz), s = '0x0'; return; end
            s = sprintf('%dx', sz);
            s = s(1:end-1);
        end

        function PX = getLegacyPX(~, legacy)
            if isfield(legacy,'PX'), PX = legacy.PX; else, PX = []; end
        end

        function PX = buildPXFromRank(obj, RANK, PXin)
            % Reconstruct the ranking hyperparameter shelf according to
            % nk_Rank_config. For imported legacy configurations that use a
            % parameterized sub-configurator, this keeps the downstream
            % preprocessing/ML ramification cube intact.
            PX = [];
            alg = '';
            if isfield(RANK,'algostr') && ~isempty(RANK.algostr), alg = lower(char(RANK.algostr)); end

            switch alg
                case 'gflip'
                    if obj.hasNestedNumeric(RANK, {'gflip','gflip','extra_param','beta'})
                        PX = obj.pxAdd(PX, RANK.gflip.gflip.extra_param.beta, 'Beta', 1, 'replace');
                    end

                case 'simba'
                    if obj.hasNestedNumeric(RANK, {'simba','simba','extra_param','beta'})
                        PX = obj.pxAdd(PX, RANK.simba.simba.extra_param.beta, 'Beta', 1, 'replace');
                    end

                case {'idetect','imrelief'}
                    if isfield(RANK,alg) && isstruct(RANK.(alg))
                        S = RANK.(alg);
                        if isfield(S,'sigma') && isnumeric(S.sigma)
                            PX = obj.pxAdd(PX, S.sigma, 'Sigma', 1, 'replace');
                        end
                        if isfield(S,'lambda') && isnumeric(S.lambda)
                            PX = obj.pxAdd(PX, S.lambda, 'Lambda', 1);
                        end
                    end

                case {'libsvm','liblin'}
                    if isfield(RANK,'SVM') && isstruct(RANK.SVM)
                        SVM = RANK.SVM;
                        if isfield(SVM,'LIBLIN') && isstruct(SVM.LIBLIN) && ...
                                isfield(SVM.LIBLIN,'tolerance') && ~isempty(SVM.LIBLIN.tolerance)
                            PX = obj.pxAdd(PX, SVM.LIBLIN.tolerance, 'TolRank', 1, 'replace');
                        end
                        if isfield(SVM,'EpsParam') && isnumeric(SVM.EpsParam)
                            PX = obj.pxAdd(PX, SVM.EpsParam, 'EpsilonRank', 1);
                        end
                        if isfield(SVM,'NuParam') && isnumeric(SVM.NuParam)
                            PX = obj.pxAdd(PX, SVM.NuParam, 'NuRank', 1);
                        end
                        if isfield(SVM,'SlackParam') && isnumeric(SVM.SlackParam)
                            PX = obj.pxAdd(PX, SVM.SlackParam, 'SlackRank', 1);
                        end
                    end

                case 'rgs'
                    if obj.hasNestedNumeric(RANK, {'RGS','extra_param','k'})
                        PX = obj.pxAdd(PX, RANK.RGS.extra_param.k, 'K', 1, 'replace');
                    end
                    if obj.hasNestedNumeric(RANK, {'RGS','extra_param','beta'})
                        PX = obj.pxAdd(PX, RANK.RGS.extra_param.beta, 'Beta', 1);
                    end

                case 'feast'
                    if obj.hasNestedNumeric(RANK, {'FEAST','NumFeat'})
                        PX = obj.pxAdd(PX, RANK.FEAST.NumFeat, 'NumFeat', 1);
                    end

                case 'relief'
                    if obj.hasNestedNumeric(RANK, {'Relief','k'})
                        PX = obj.pxAdd(PX, RANK.Relief.k, 'K', 1);
                    end

                case 'pls'
                    if isfield(RANK,'PLS') && isstruct(RANK.PLS) && ...
                            isfield(RANK.PLS,'algostr') && strcmpi(RANK.PLS.algostr,'spls')
                        if isfield(RANK.PLS,'cu') && isnumeric(RANK.PLS.cu)
                            PX = obj.pxAdd(PX, RANK.PLS.cu, 'SPLS-cu', 1);
                        end
                        if isfield(RANK.PLS,'cv') && isnumeric(RANK.PLS.cv)
                            PX = obj.pxAdd(PX, RANK.PLS.cv, 'SPLS-cv', 1);
                        end
                    end
            end

            % If the current algorithm has no recognized hyperparameter but
            % the object was imported from legacy NM, preserve its old PX
            % rather than silently dropping an optimization dimension.
            if ~obj.pxHasParams(PX)
                if obj.pxHasParams(PXin)
                    PX = PXin;
                else
                    PX = [];
                end
            end
        end

        function tf = hasNestedNumeric(~, s, path)
            tf = false;
            cur = s;
            for i = 1:numel(path)
                key = path{i};
                if ~isstruct(cur) || ~isfield(cur,key), return; end
                cur = cur.(key);
            end
            tf = isnumeric(cur) && ~isempty(cur);
        end

        function name = rankTypeName(~, code)
            switch code
                case 2, name = 'classification';
                case 3, name = 'regression';
                otherwise, name = 'auto';
            end
        end

        function code = weightMethodCode(~, name)
            switch lower(char(name))
                case 'downweight', code = 2;
                otherwise, code = 1;
            end
        end

        function name = weightMethodName(~, code)
            if code == 2, name = 'downweight'; else, name = 'upweight'; end
        end

        function RANK = attachPxToRank(~, RANK, PX)
            if isfield(PX,'opt'), RANK.opt = PX.opt; end
            if isfield(PX,'Px')
                if isfield(PX.Px,'Params'), RANK.Params = PX.Px.Params; end
                if isfield(PX.Px,'Params_desc'), RANK.Params_desc = PX.Px.Params_desc; end
            end
        end

        function cfg = validateOrError(obj, cfg)
            if isfield(cfg,'legacyPX') && isempty(cfg.legacyPX) && ~isstruct(cfg.legacyPX)
                cfg.legacyPX = struct();
            end
            if isfield(cfg,'legacyRANK') && isempty(cfg.legacyRANK) && ~isstruct(cfg.legacyRANK)
                cfg.legacyRANK = struct();
            end
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMRankFeatModule:invalidConfig','%s',strjoin(report.errors,newline)); end
            if isfield(cfg,'algorithm')
                try
                    cfg.algorithmParams = NMRankSubconfigLibrary.normalizeParams(cfg.algorithm, cfg.algorithmParams, struct());
                catch
                    % Keep legacy imports permissive. toLegacy() performs the
                    % strict algorithm-parameter validation with context.
                    if ~isfield(cfg,'algorithmParams') || ~isstruct(cfg.algorithmParams)
                        cfg.algorithmParams = struct();
                    end
                end
            end
        end
    end
end

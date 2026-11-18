classdef NMPreprocContext
% NMPreprocContext
% -------------------------------------------------------------------------
% Small, explicit context extractor for the registry-driven preprocessing
% orchestrator.  The context deliberately contains only scalar/summary facts
% that affect availability and dependency logic. It does not serialize large
% data matrices into the browser UI.
% -------------------------------------------------------------------------

    methods (Static)
        function ctx = empty()
            % empty  Create an empty preprocessing context with stable schema defaults.
            %   The returned struct contains the fields expected by modules, rule checks, UI
            %   schemas, and legacy translators, avoiding dynamic field assumptions in downstream
            %   code.

            ctx = struct();
            ctx.varind = [];
            ctx.hasNM = false;
            ctx.NM = [];
            ctx.modeflag = '';
            ctx.originalModeflag = '';
            ctx.activeModality = [];
            ctx.isImaging = [];
            ctx.isExpert = [];
            ctx.isDev = [];
            ctx.hasCovars = [];
            ctx.nCovars = [];
            ctx.covarNames = {};
            ctx.covarOptions = {};
            ctx.hasNaNsInPredictors = [];
            ctx.hasNaNsInLabels = [];
            ctx.hasAlternativeLabel = false;
            ctx.activeLabel = [];
            ctx.activeLabelNClasses = [];
            ctx.preprocBinmod = [];
            ctx.forceMultiGroupBinmod = false;
            ctx.randDecompose = [];
            ctx.isStackingInputLayer = [];
            ctx.isStackingAnalysisLayer = [];
            ctx.isSeqoptStacking = false;
            ctx.isRegression = [];
            ctx.isClassification = [];
            ctx.isMultiClass = [];
            ctx.hasFusion = [];
            ctx.nFeatures = [];
            ctx.nSubjects = [];
            ctx.activeDataIsOutsourced = [];
            ctx.datasource = '';
            ctx.datatype = [];
            ctx.surfaceGeometryContract = struct();
            ctx.surfaceSpatialAvailable = false;
            ctx.brainmask = [];
            ctx.spatialThresh = [];
            ctx.spatialMaskOperator = '';
            ctx.spatialMaskValue = [];
            ctx.juSpaceRoot = '';
            ctx.hasJuSpaceDir = false;
            ctx.allowUnportedModules = false;
            ctx.strictAvailability = false;
            ctx.source = 'empty';
        end

        function ctx = fromNM(NM, varind, varargin)
            % fromNM  Derive the preprocessing context from canonical NM authorities.
            %   Reads only facts required by preprocessing availability, module schemas and
            %   execution. Effective-target semantics come from NMAlternativeLabelTools and
            %   modality summaries from the focused NMModalityInfoTools preprocessing query.

            if nargin < 2 || isempty(varind)
                if isstruct(NM) && isfield(NM,'ActiveModality') && ~isempty(NM.ActiveModality)
                    varind = NM.ActiveModality;
                else
                    varind = 1;
                end
            end

            ctx = NMPreprocContext.empty();
            ctx.hasNM = true;
            ctx.NM = NMPreprocContext.lightNMForContext(NM, varind);
            ctx.varind = varind;
            ctx.source = 'NM';

            global EXPERT DEV
            ctx.isExpert = ~isempty(EXPERT) && logical(EXPERT);
            ctx.isDev = ~isempty(DEV) && logical(DEV);

            if isfield(NM,'ActiveModality'), ctx.activeModality = NM.ActiveModality; end
            if isfield(NM,'modeflag') && ~isempty(NM.modeflag)
                ctx.originalModeflag = char(NM.modeflag);
            end
            ctx.modeflag = NMAlternativeLabelTools.effectiveMode(NM);
            LABEL = NMAlternativeLabelTools.extractLabel(NM);
            ctx.hasAlternativeLabel = isfield(LABEL,'flag') && LABEL.flag == 1;
            if isfield(NM,'label') || (ctx.hasAlternativeLabel && isfield(LABEL,'newlabel'))
                ctx.activeLabel = NMAlternativeLabelTools.activeLabel(NM);
            end

            if isfield(NM,'TrainParam') && isstruct(NM.TrainParam)
                TP = NM.TrainParam;
                if isfield(TP,'RAND') && isstruct(TP.RAND) && isfield(TP.RAND,'Decompose')
                    ctx.randDecompose = TP.RAND.Decompose;
                    ctx.forceMultiGroupBinmod = isequal(TP.RAND.Decompose,2);
                end
                if isfield(TP,'STACKING') && isstruct(TP.STACKING) && isfield(TP.STACKING,'flag')
                    ctx.isStackingInputLayer = TP.STACKING.flag == 1;
                    ctx.isStackingAnalysisLayer = TP.STACKING.flag == 2;
                end
                if isfield(TP,'FUSION') && isstruct(TP.FUSION) && isfield(TP.FUSION,'flag')
                    ctx.hasFusion = TP.FUSION.flag == 1;
                end
                if isfield(TP,'PREPROC') && iscell(TP.PREPROC) && numel(TP.PREPROC) >= varind && ...
                        isstruct(TP.PREPROC{varind}) && isfield(TP.PREPROC{varind},'BINMOD') && ...
                        ~isempty(TP.PREPROC{varind}.BINMOD)
                    ctx.preprocBinmod = double(logical(TP.PREPROC{varind}.BINMOD));
                end
            end

            if isempty(ctx.preprocBinmod)
                ctx.preprocBinmod = NMPreprocGlobalOptions.defaultBinmod(ctx);
            elseif ctx.forceMultiGroupBinmod
                ctx.preprocBinmod = 0;
            end

            ctx.isRegression = strcmpi(ctx.modeflag,'regression');
            ctx.isClassification = strcmpi(ctx.modeflag,'classification');

            modalityInfo = NMModalityInfoTools.preprocContextInfo(NM, varind);
            ctx.isImaging = modalityInfo.isImaging;
            ctx.nFeatures = NMPreprocContext.knownCount(modalityInfo.nFeatures);
            ctx.nSubjects = NMPreprocContext.knownCount(modalityInfo.nSubjects);
            if strcmp(modalityInfo.storageMode,'external')
                ctx.activeDataIsOutsourced = true;
            elseif strcmp(modalityInfo.storageMode,'memory')
                ctx.activeDataIsOutsourced = false;
            end
            if ~strcmp(modalityInfo.datasource,'unknown')
                ctx.datasource = modalityInfo.datasource;
            end
            if isfield(NM,'brainmask') && numel(NM.brainmask) >= varind
                ctx.brainmask = NM.brainmask{varind};
            end
            if isfield(NM,'datadescriptor') && numel(NM.datadescriptor) >= varind
                dd = NM.datadescriptor{varind};
                ctx.datatype = dd.type;
                if strcmp(ctx.datasource,'surf')
                    ctx.surfaceGeometryContract = dd.input_settings.surfaceGeometryContract;
                    c = ctx.surfaceGeometryContract;
                    ctx.surfaceSpatialAvailable = ~isempty(fieldnames(c)) && c.nativeAvailable && ...
                        isequal(c.vertexCount,ctx.nFeatures);
                end
                if isfield(dd,'input_settings') && isfield(dd.input_settings,'Thresh')
                    ctx.spatialThresh = dd.input_settings.Thresh;
                end
                if isfield(dd,'threshop') && ~isempty(dd.threshop)
                    op = dd.threshop;
                    if iscell(op), op = op{1}; end
                    ctx.spatialMaskOperator = char(string(op));
                end
                if isfield(dd,'threshval') && ~isempty(dd.threshval)
                    ctx.spatialMaskValue = dd.threshval;
                end
            end

            ctx.hasCovars = isfield(NM,'covars') && ~isempty(NM.covars);
            [ctx.nCovars, ctx.covarNames, ctx.covarOptions] = NMPreprocContext.detectCovariateInfo(NM);

            hasNativeLabel = isfield(NM,'label') && ~isempty(NM.label);
            hasAlternativeLabel = ctx.hasAlternativeLabel && isfield(LABEL,'newlabel') && ~isempty(LABEL.newlabel);
            if hasNativeLabel || hasAlternativeLabel
                if isnumeric(ctx.activeLabel) || islogical(ctx.activeLabel)
                    ctx.hasNaNsInLabels = any(isnan(ctx.activeLabel(:)));
                else
                    ctx.hasNaNsInLabels = false;
                end
                [ctx.isMultiClass, ctx.activeLabelNClasses] = NMAlternativeLabelTools.effectiveClassInfo(NM);
            else
                ctx.hasNaNsInLabels = false;
                ctx.activeLabelNClasses = [];
                ctx.isMultiClass = false;
            end

            ctx.hasNaNsInPredictors = NMPreprocContext.detectPredictorNaNs(NM, varind);
            [ctx.juSpaceRoot, ctx.hasJuSpaceDir] = NMPreprocContext.detectJuSpaceRoot();

            ctx = NMPreprocContext.mergeNameValue(ctx, varargin{:});
            if strcmp(ctx.source,'stacking')
                ml = NMTrainConfigOrchestrator.fromNM(NM, [], struct());
                ctx.isSeqoptStacking = strcmp(ml.MLConfig.algorithm,'SEQOPT');
            end
        end

        function ctx = fromNameValue(varargin)
            % fromNameValue  Create a manual preprocessing context from name/value arguments.
            %   Starts from empty() and merges caller-provided overrides, which is useful for tests
            %   and scripted API usage without a full NM workspace.

            ctx = NMPreprocContext.empty();
            ctx.source = 'manual';
            ctx = NMPreprocContext.mergeNameValue(ctx, varargin{:});
        end

        function ctx = mergeNameValue(ctx, varargin)
            % mergeNameValue  Merge struct or name/value overrides into an existing context.
            %   This small API utility is used by fromNM/fromNameValue to let power users override
            %   context facts while preserving the fixed context schema.

            if isempty(varargin), return; end
            if numel(varargin) == 1 && isstruct(varargin{1})
                ctx = NMConfigTools.mergeStruct(ctx, varargin{1});
                return;
            end
            if mod(numel(varargin),2) ~= 0
                error('NMPreprocContext:nameValue','Context arguments must be name/value pairs or a struct.');
            end
            for i = 1:2:numel(varargin)
                k = char(varargin{i});
                if ~isvarname(k), error('NMPreprocContext:nameValue','Invalid context field: %s', k); end
                ctx.(k) = varargin{i+1};
            end
        end

        function small = toUISummary(ctx)
            % toUISummary  Reduce a full preprocessing context to UI/RAG-safe summary fields.
            %   Drops heavy NM payloads while keeping the modality/task/covariate/datasource facts
            %   needed by browser state, diagnostics, and documentation.

            % Keep browser export compact and non-sensitive. Large fields are
            % deliberately excluded.
            keep = {'varind','modeflag','activeModality','isImaging','isExpert','isDev', ...
                'hasCovars','nCovars','covarNames','covarOptions','hasNaNsInPredictors','hasNaNsInLabels', ...
                'hasAlternativeLabel','originalModeflag','activeLabelNClasses','forceMultiGroupBinmod','randDecompose', ...
                'isStackingInputLayer','isStackingAnalysisLayer','isSeqoptStacking', ...
                'isRegression','isClassification','isMultiClass','hasFusion', ...
                'nFeatures','nSubjects','activeDataIsOutsourced','datasource','surfaceSpatialAvailable', ...
                'juSpaceRoot','hasJuSpaceDir', ...
                'allowUnportedModules','strictAvailability','source'};
            small = struct();
            for i = 1:numel(keep)
                if isfield(ctx,keep{i}), small.(keep{i}) = ctx.(keep{i}); end
            end
        end
    end

    methods (Static, Access = private)

        function lite = lightNMForContext(NM, varind)
            lite = struct();
            mode = NMAlternativeLabelTools.effectiveMode(NM);
            if ~isempty(mode), lite.modeflag = mode; end
            if isfield(NM,'time'), lite.time = NM.time; end
            LABEL = NMAlternativeLabelTools.extractLabel(NM);
            hasActiveLabel = (isfield(LABEL,'flag') && LABEL.flag == 1 && isfield(LABEL,'newlabel') && ~isempty(LABEL.newlabel)) || ...
                (isfield(NM,'label') && ~isempty(NM.label));
            if hasActiveLabel, lite.label = NMAlternativeLabelTools.activeLabel(NM); end
            if isfield(NM,'covars'), lite.covars = NM.covars; end
            if isfield(NM,'covnames'), lite.covnames = NM.covnames; end
            if isfield(NM,'datadescriptor')
                lite.datadescriptor = cell(1, max(varind, numel(NM.datadescriptor)));
                if numel(NM.datadescriptor) >= varind, lite.datadescriptor{varind} = NM.datadescriptor{varind}; end
            end
            if isfield(NM,'brainmask')
                lite.brainmask = cell(1, max(varind, numel(NM.brainmask)));
                if numel(NM.brainmask) >= varind, lite.brainmask{varind} = NM.brainmask{varind}; end
            end
            if isfield(NM,'TrainParam') && isstruct(NM.TrainParam)
                TP = NM.TrainParam;
                lite.TrainParam = struct();
                if isfield(TP,'PREPROC') && iscell(TP.PREPROC)
                    lite.TrainParam.PREPROC = cell(1, max(varind, numel(TP.PREPROC)));
                    if numel(TP.PREPROC) >= varind && isstruct(TP.PREPROC{varind}) && isfield(TP.PREPROC{varind},'BINMOD')
                        lite.TrainParam.PREPROC{varind}.BINMOD = TP.PREPROC{varind}.BINMOD;
                    end
                end
                if isfield(TP,'LABEL'), lite.TrainParam.LABEL = TP.LABEL; end
                if isfield(TP,'RAND'), lite.TrainParam.RAND = TP.RAND; end
                if isfield(TP,'STACKING'), lite.TrainParam.STACKING = TP.STACKING; end
                if isfield(TP,'FUSION'), lite.TrainParam.FUSION = TP.FUSION; end
            end
        end

        function [juSpaceRoot, hasJuSpaceDir] = detectJuSpaceRoot()
            p = which('neurominer.m');
            if isempty(p), p = which('nk_Utilities.m'); end
            if isempty(p)
                juSpaceRoot = '';
                hasJuSpaceDir = false;
                return;
            end
            juSpaceRoot = fullfile(fileparts(p),'JuSpace');
            hasJuSpaceDir = exist(juSpaceRoot,'dir') == 7;
        end

        function [nCovars, covarNames, covarOptions] = detectCovariateInfo(NM)
            if ~isfield(NM,'covars') || isempty(NM.covars)
                nCovars = 0;
                covarNames = {};
                covarOptions = {};
                return;
            end
            if ~(isnumeric(NM.covars) || islogical(NM.covars)) || ~ismatrix(NM.covars)
                error('NMPreprocContext:invalidCovariates', ...
                    'NM.covars must be a numeric/logical subjects-by-covariates matrix.');
            end

            nCovars = size(NM.covars,2);
            covarNames = {};
            if isfield(NM,'covnames') && ~isempty(NM.covnames)
                covarNames = NM.covnames;
                if isstring(covarNames), covarNames = cellstr(covarNames(:)); end
                if ischar(covarNames), covarNames = cellstr(covarNames); end
                if ~iscell(covarNames)
                    error('NMPreprocContext:invalidCovariateNames','NM.covnames must be text or a cell array of names.');
                end
                covarNames = covarNames(:)';
            end
            if isempty(covarNames)
                covarNames = arrayfun(@(i)sprintf('Covariate %d',i),1:nCovars,'UniformOutput',false);
            elseif numel(covarNames) ~= nCovars
                error('NMPreprocContext:covariateNameCount', ...
                    'NM.covnames contains %d name(s), but NM.covars has %d column(s).', numel(covarNames), nCovars);
            end

            covarOptions = cell(1,nCovars);
            for i = 1:nCovars
                nm = covarNames{i};
                if isstring(nm) && isscalar(nm), nm = char(nm); end
                if ~ischar(nm) || size(nm,1) ~= 1
                    error('NMPreprocContext:invalidCovariateName','NM.covnames{%d} must be scalar text.',i);
                end
                inferredType = NMPreprocContext.inferNumericCovariateType(NM.covars(:,i));
                covarOptions{i} = struct('index',i,'name',nm,'label',sprintf('%d | %s',i,nm), ...
                    'inferredType',inferredType);
            end
        end

        function typ = inferNumericCovariateType(v)
            % Match the legacy ComBat infer_covtype value rule. NM2 exposes
            % legacy binary as the canonical browser category 'categorical'.
            v = double(v(:));
            v = v(~isnan(v));
            u = unique(v);
            k = numel(u);
            if k <= 1
                typ = 'continuous';
            elseif k == 2
                typ = 'categorical';
            elseif all(mod(u,1) == 0) && k <= 7
                typ = 'ordinal';
            elseif k <= 7
                typ = 'categorical';
            else
                typ = 'continuous';
            end
        end

        function n = knownCount(value)
            n = [];
            if isnumeric(value) && isscalar(value) && isfinite(value)
                n = double(value);
            end
        end

        function tf = detectPredictorNaNs(NM, varind)
            tf = false;
            if ~isfield(NM,'Y') || isempty(NM.Y), return; end
            if isfield(NM,'TrainParam') && isfield(NM.TrainParam,'FUSION') && ...
                    isstruct(NM.TrainParam.FUSION) && isfield(NM.TrainParam.FUSION,'flag') && ...
                    NM.TrainParam.FUSION.flag == 1 && isfield(NM.TrainParam.FUSION,'M')
                modalities = round(double(NM.TrainParam.FUSION.M(:)'));
                modalities = modalities(isfinite(modalities) & modalities >= 1 & modalities <= numel(NM.Y));
                modalities = unique(modalities, 'stable');
                if isempty(modalities), tf = []; return; end
            else
                modalities = round(double(varind));
                if ~isfinite(modalities) || modalities < 1 || modalities > numel(NM.Y), tf = []; return; end
            end
            anyUnknown = false;
            for mi = modalities
                status = NMModalityInfoTools.predictorNaNStatus(NM, mi, 1e7);
                if isequal(status, true)
                    tf = true;
                    return;
                end
                anyUnknown = anyUnknown || isempty(status);
            end
            if anyUnknown, tf = []; end
        end
    end
end

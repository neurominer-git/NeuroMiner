classdef NMModelExportRuntimeTools
% NMModelExportRuntimeTools
% -------------------------------------------------------------------------
% Browser/runtime state helpers for exporting optimized NeuroMiner model and
% preprocessing parameters.  The class is read-only; execution is routed
% through NMRunTools.exportModels.
% -------------------------------------------------------------------------

    methods (Static)
        function state = uiState(NM, spec)
            % uiState  Build the browser/API state for the optimized-model export runner.
            %
            % Reads analysis cards, selection, GridAct state, options and export artifact summaries into one fixed schema. The method is read-only; NMRunTools.exportModels performs the actual export.
            %
            % spec.deferArtifactScan: supplies the defer artifact scan value in the public API/import specification.
            % spec.options: carries additional runner/API options forwarded to lower-level runtime helpers.
            % spec.selectedAnalysisIndices: limits the runtime action to selected analysis indices.
            if nargin < 2 || isempty(spec), spec = struct(); end
            deferArtifactScan = isstruct(spec) && isfield(spec,'deferArtifactScan') && logical(spec.deferArtifactScan);
            analyses = NMModelExportRuntimeTools.analysisCards(NM, struct('deferArtifactScan',deferArtifactScan,'useArtifactCache',true));
            selected = NMModelExportRuntimeTools.normalizeIndexVector(NMModelExportRuntimeTools.fieldOr(spec,'selectedAnalysisIndices',[]));
            if isempty(selected), selected = NMModelExportRuntimeTools.defaultSelection(analyses); end
            grid = NMModelExportRuntimeTools.gridStateForSelection(NM, selected);
            options = NMModelExportRuntimeTools.defaultOptions();
            if isstruct(spec) && isfield(spec,'options') && isstruct(spec.options)
                options = NMModelExportRuntimeTools.mergeStruct(options, spec.options);
            end
            if deferArtifactScan
                artifactSummary = NMModelExportRuntimeTools.lightExportArtifactSummary(NM, selected, options);
            else
                artifactSummary = NMModelExportRuntimeTools.exportArtifactSummary(NM, selected, options, grid);
            end
            state = struct('ok',true, 'message','Model-export runtime state derived.', ...
                'analyses',analyses, 'selectedAnalysisIndices',selected, 'grid',grid, ...
                'options',options, 'artifactSummary',artifactSummary, 'dynamicControls',struct());
            [state.canRun, state.runReason] = NMModelExportRuntimeTools.validateExecutable(NM, selected, options, grid, true);
            state.canGenerateScript = state.canRun;
            state.scriptReason = state.runReason;
        end

        function opts = defaultOptions()
            % defaultOptions  Return default optimized-model export options.
            %
            % Provides the noninteractive defaults for auto/manual artifact resolution and cache use. Callers merge user selections into this struct before validating exportability.
            opts = struct('exportOptModel',true, 'exportOptPreproc',true, ...
                'overwrite',false, 'saveCV1',false);
        end

        function cards = analysisCards(NM, opts)
            % analysisCards  Summarize analyses available for model export.
            %
            % Builds read-only cards from NM.analysis and lightweight artifact status so the browser can select export targets without touching analysis definitions.
            %
            % opts.deferArtifactScan: postpones artifact discovery so the caller can update state without filesystem scanning.
            % opts.useArtifactCache: allows reuse of previously discovered runtime artifacts when the request permits it.
            if nargin < 2 || isempty(opts), opts = struct(); end
            deferArtifactScan = isstruct(opts) && isfield(opts,'deferArtifactScan') && logical(opts.deferArtifactScan);
            useArtifactCache = isstruct(opts) && isfield(opts,'useArtifactCache') && NMModelExportRuntimeTools.toLogical(opts.useArtifactCache, false);
            if exist('NMAnalysisManagerTools','class') == 8
                list = NMAnalysisManagerTools.listAnalyses(NM);
            else
                list = NMModelExportRuntimeTools.emptyAnalysisList(NM);
            end
            detail = NMModelExportRuntimeTools.emptyExportSummary();
            template = struct('index',0,'id','','description','','rootdir','','status',NaN, ...
                'enabled',false,'disabledReason','','enabledReason','', ...
                'ix',0,'jx',0,'trainedCells',0,'gridAct',[],'artifactSummary',detail);
            n = max(0,double(NMModelExportRuntimeTools.fieldOr(list,'count',0)));
            cards = repmat(template,1,n);
            for i = 1:n
                A = NM.analysis{i};
                [ix,jx] = NMModelExportRuntimeTools.analysisGridDims(NM,i);
                status = NMModelExportRuntimeTools.fieldOr(A,'status',NaN);
                gdOK = isfield(A,'GDdims') && ~isempty(A.GDdims) && iscell(A.GDdims) && isstruct(A.GDdims{1});
                trainedMask = false(ix,jx);
                if gdOK && isfield(A.GDdims{1},'GridAct') && ~isempty(A.GDdims{1}.GridAct)
                    trainedMask = logical(A.GDdims{1}.GridAct);
                end
                trainedCells = nnz(trainedMask);
                enabled = isfinite(status) && status >= 1 && gdOK && trainedCells > 0;
                reason = '';
                if ~enabled
                    reason = 'Train at least one CV2 partition successfully before exporting models.';
                end
                cards(i) = template;
                cards(i).index = i;
                if isfield(list,'ids') && numel(list.ids)>=i, cards(i).id = list.ids{i}; else, cards(i).id = NMModelExportRuntimeTools.fieldOr(A,'id',sprintf('Analysis %d',i)); end
                if isfield(list,'descriptions') && numel(list.descriptions)>=i, cards(i).description = list.descriptions{i}; else, cards(i).description = NMModelExportRuntimeTools.fieldOr(A,'desc',cards(i).id); end
                if isfield(list,'rootdirs') && numel(list.rootdirs)>=i, cards(i).rootdir = list.rootdirs{i}; else, cards(i).rootdir = NMModelExportRuntimeTools.fieldOr(A,'rootdir',''); end
                if isempty(cards(i).rootdir) || exist(cards(i).rootdir,'dir') ~= 7
                    enabled = false;
                    reason = 'Analysis root path is stale or missing. Relink analysis root before exporting models.';
                end
                cards(i).status = status;
                cards(i).enabled = enabled;
                cards(i).disabledReason = reason;
                cards(i).enabledReason = 'Trained CV2 partitions are available for model export.';
                cards(i).ix = ix; cards(i).jx = jx; cards(i).trainedCells = trainedCells;
                cards(i).gridAct = trainedMask;
                if deferArtifactScan
                    cards(i).artifactSummary = NMModelExportRuntimeTools.lightExportArtifactSummary(NM, i, NMModelExportRuntimeTools.defaultOptions());
                else
                    cardOptions = NMModelExportRuntimeTools.defaultOptions();
                    cardOptions.useArtifactCache = useArtifactCache;
                    cards(i).artifactSummary = NMModelExportRuntimeTools.exportArtifactSummary(NM, i, cardOptions, struct());
                end
            end
        end

        function summary = lightExportArtifactSummary(NM, selected, opts) %#ok<INUSD>
            % lightExportArtifactSummary  Return cached or summary-only export-artifact status for selected analyses.
            %
            % Provides a fast initial summary when full filesystem scanning is deferred. It preserves the export runner schema and is replaced by exportArtifactSummary before execution when needed.
            selected = NMModelExportRuntimeTools.normalizeIndexVector(selected);
            if isempty(selected)
                summary = repmat(NMModelExportRuntimeTools.emptyExportSummary(),1,0);
                return;
            end
            summary = repmat(NMModelExportRuntimeTools.emptyExportSummary(),1,numel(selected));
            for kk = 1:numel(selected)
                idx = selected(kk);
                S = NMModelExportRuntimeTools.emptyExportSummary();
                S.analysisIndex = idx;
                if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis) && idx >= 1 && idx <= numel(NM.analysis) && isstruct(NM.analysis{idx})
                    A = NM.analysis{idx};
                    S.exportDir = NMModelExportRuntimeTools.exportDir(A);
                    S.dataId = NMModelExportRuntimeTools.dataId(NM,A);
                end
                S.coverageText = 'loading';
                S.message = 'Export artifact availability is still being resolved.';
                summary(kk) = S;
            end
        end

        function summary = exportArtifactSummary(NM, selected, opts, grid)
            % exportArtifactSummary  Resolve optimized-model export artifacts for selected analyses and CV cells.
            %
            % Combines selection, options and GridAct state to identify existing model/preprocessing artifacts that can satisfy an export request. The method is read-only and feeds run/script enablement decisions.
            %
            % opts.exportOptModel: configures optional export opt model behavior for this call.
            if nargin < 3 || isempty(opts), opts = NMModelExportRuntimeTools.defaultOptions(); end
            if nargin < 4, grid = struct(); end
            selected = NMModelExportRuntimeTools.normalizeIndexVector(selected);
            if isempty(selected)
                summary = repmat(NMModelExportRuntimeTools.emptyExportSummary(),1,0);
                return;
            end
            summary = repmat(NMModelExportRuntimeTools.emptyExportSummary(),1,numel(selected));
            for kk = 1:numel(selected)
                idx = selected(kk);
                if idx < 1 || ~isfield(NM,'analysis') || idx > numel(NM.analysis) || ~isstruct(NM.analysis{idx})
                    summary(kk) = NMModelExportRuntimeTools.emptyExportSummary();
                    summary(kk).analysisIndex = idx;
                    summary(kk).message = 'Analysis does not exist.';
                    continue;
                end
                A = NM.analysis{idx};
                S = NMModelExportRuntimeTools.emptyExportSummary();
                S.analysisIndex = idx;
                S.exportDir = NMModelExportRuntimeTools.exportDir(A);
                S.dataId = NMModelExportRuntimeTools.dataId(NM,A);
                [ix,jx] = NMModelExportRuntimeTools.analysisGridDims(NM,idx);
                if isstruct(grid) && isfield(grid,'GridAct') && ~isempty(grid.GridAct) && isequal(size(grid.GridAct),[ix jx])
                    G = logical(grid.GridAct);
                elseif isfield(A,'GDdims') && ~isempty(A.GDdims) && isfield(A.GDdims{1},'GridAct')
                    G = logical(A.GDdims{1}.GridAct);
                else
                    G = true(ix,jx);
                end
                S.nExpected = max(0, nnz(G));
                if isempty(S.exportDir) || exist(S.exportDir,'dir') ~= 7
                    S.coverageText = sprintf('No export directory found (%s).', S.exportDir);
                    S.message = 'No optimized model/preprocessing export artifacts were found.';
                    summary(kk) = S;
                    continue;
                end
                S.nOptModelFiles = NMModelExportRuntimeTools.countFiles(S.exportDir, 'OptModel', S.dataId);
                S.nOptPreprocFiles = NMModelExportRuntimeTools.countFiles(S.exportDir, 'OptPreprocParam', S.dataId);
                S.optModelAvailable = S.nExpected > 0 && S.nOptModelFiles >= S.nExpected;
                S.optPreprocAvailable = S.nOptPreprocFiles > 0;
                S.coverageText = sprintf('OptModel files: %d; OptPreprocParam files: %d; selected CV2 partitions: %d', ...
                    S.nOptModelFiles, S.nOptPreprocFiles, S.nExpected);
                if NMModelExportRuntimeTools.toLogical(NMModelExportRuntimeTools.fieldOr(opts,'exportOptModel',true),true) && S.nOptModelFiles < S.nExpected
                    S.message = 'Some selected CV2 partitions do not yet have exported optimized ML model files.';
                else
                    S.message = 'Export artifact summary derived from the analysis opt directory.';
                end
                summary(kk) = S;
            end
        end

        function [ok, msg] = validateExecutable(~, selected, opts, grid, allowExecution)
            % validateExecutable  Decide whether the current model-export state can be executed.
            %
            % Checks analysis selection, GridAct coverage and artifact availability when precomputed inputs are required. The boolean/message result blocks invalid export calls before NMRunTools.exportModels is invoked.
            %
            % opts.exportOptModel: configures optional export opt model behavior for this call.
            % opts.exportOptPreproc: configures optional export opt preproc behavior for this call.
            ok = false;
            selected = NMModelExportRuntimeTools.normalizeIndexVector(selected);
            if isempty(selected), msg = 'Select at least one trained analysis.'; return; end
            exportModel = NMModelExportRuntimeTools.toLogical(NMModelExportRuntimeTools.fieldOr(opts,'exportOptModel',true), true);
            exportPreproc = NMModelExportRuntimeTools.toLogical(NMModelExportRuntimeTools.fieldOr(opts,'exportOptPreproc',true), true);
            if ~exportModel && ~exportPreproc
                msg = 'Select optimized ML models, optimized preprocessing parameters, or both.'; return;
            end
            if isstruct(grid) && isfield(grid,'visible') && grid.visible && isfield(grid,'proceedAllowed') && ~grid.proceedAllowed
                msg = 'Select at least one CV2 partition.'; return;
            end
            ok = logical(allowExecution);
            if ok
                msg = 'Ready to export trained model artifacts.';
            else
                msg = 'Model export is not executable for the current selection.';
            end
        end

        function grid = gridStateForSelection(NM, selected)
            % gridStateForSelection  Build the CV2 GridAct picker state for selected export analyses.
            %
            % Derives perm/fold dimensions from selected analyses and normalizes GridAct through NMRuntimeGridTools. The result constrains export to explicit CV cells without mutating NM.
            selected = NMModelExportRuntimeTools.normalizeIndexVector(selected);
            grid = struct('visible',false,'hiddenByLegacyRule',false,'proceedAllowed',false, ...
                'reason','Select at least one trained analysis.','ix',0,'jx',0,'GridAct',false(0,0),'state',struct());
            if isempty(selected), return; end
            dims = zeros(numel(selected),2); masks = cell(1,numel(selected));
            for ii=1:numel(selected)
                [dims(ii,1),dims(ii,2)] = NMModelExportRuntimeTools.analysisGridDims(NM,selected(ii));
                A = NM.analysis{selected(ii)};
                if isfield(A,'GDdims') && ~isempty(A.GDdims) && isfield(A.GDdims{1},'GridAct')
                    masks{ii} = logical(A.GDdims{1}.GridAct);
                else
                    masks{ii} = false(dims(ii,1),dims(ii,2));
                end
            end
            if any(dims(:)<1) || any(~isfinite(dims(:)))
                grid.reason = 'At least one selected analysis has no valid CV2 grid.'; return;
            end
            same = all(dims(:,1)==dims(1,1)) && all(dims(:,2)==dims(1,2));
            if ~same
                grid.visible = false; grid.hiddenByLegacyRule = true; grid.proceedAllowed = true;
                grid.reason = 'Selected analyses have different CV2 grid sizes. The legacy model-export runner will operate on all trained CV2 partitions per analysis.';
                return;
            end
            G = true(dims(1,1),dims(1,2));
            for ii=1:numel(masks), G = G & masks{ii}; end
            grid.visible = true; grid.hiddenByLegacyRule = false; grid.proceedAllowed = nnz(G)>0;
            grid.reason = 'Select trained CV2 partitions to export.';
            grid.ix = dims(1,1); grid.jx = dims(1,2); grid.GridAct = G;
            if exist('NMRuntimeGridTools','class') == 8
                grid.state = NMRuntimeGridTools.state(grid.ix, grid.jx, G, struct('requireAny',true));
            end
        end
    end

    methods (Static, Access=private)
        function selected = defaultSelection(analyses)
            selected = [];
            for i=1:numel(analyses)
                if isfield(analyses(i),'enabled') && analyses(i).enabled, selected = analyses(i).index; return; end
            end
        end

        function S = emptyExportSummary()
            S = struct('analysisIndex',0,'exportDir','','dataId','','nExpected',NaN, ...
                'nOptModelFiles',0,'nOptPreprocFiles',0,'optModelAvailable',false, ...
                'optPreprocAvailable',false,'coverageText','not found', ...
                'message','No export artifacts inspected.');
        end

        function list = emptyAnalysisList(NM)
            n=0; if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis), n=numel(NM.analysis); end
            list=struct('count',n,'ids',{{}},'descriptions',{{}},'rootdirs',{{}},'status',nan(1,n));
            for i=1:n
                A=NM.analysis{i}; list.ids{i}=NMModelExportRuntimeTools.fieldOr(A,'id',sprintf('Analysis %d',i));
                list.descriptions{i}=NMModelExportRuntimeTools.fieldOr(A,'desc',list.ids{i}); list.rootdirs{i}=NMModelExportRuntimeTools.fieldOr(A,'rootdir','');
                list.status(i)=NMModelExportRuntimeTools.fieldOr(A,'status',NaN);
            end
        end

        function opts = mergeStruct(opts, override)
            f=fieldnames(override); for i=1:numel(f), opts.(f{i})=override.(f{i}); end
        end

        function [ix,jx] = analysisGridDims(NM,idx)
            ix=0; jx=0;
            if isfield(NM.analysis{idx},'params') && isfield(NM.analysis{idx}.params,'cv') && isfield(NM.analysis{idx}.params.cv,'TrainInd')
                [ix,jx]=size(NM.analysis{idx}.params.cv.TrainInd);
            elseif isfield(NM.analysis{idx},'GDdims') && ~isempty(NM.analysis{idx}.GDdims) && isfield(NM.analysis{idx}.GDdims{1},'GridAct')
                [ix,jx]=size(NM.analysis{idx}.GDdims{1}.GridAct);
            end
        end

        function p = exportDir(A)
            p=''; if ~isstruct(A) || ~isfield(A,'rootdir') || isempty(A.rootdir), return; end
            p=fullfile(char(string(A.rootdir)),'opt');
        end

        function id = dataId(NM,A)
            id='';
            if isstruct(NM) && isfield(NM,'id') && ~isempty(NM.id), id=char(string(NM.id)); end
            if isempty(id) && isstruct(A) && isfield(A,'id') && ~isempty(A.id), id=char(string(A.id)); end
            id = regexprep(id,'^ID','');
        end

        function n = countFiles(rootdir, artifactName, dataId)
            n=0; if isempty(rootdir) || exist(rootdir,'dir')~=7, return; end
            patterns = {sprintf('*%s*ID%s*.mat',artifactName,dataId), sprintf('*%s*_ID%s*.mat',artifactName,dataId), sprintf('*%s*%s*.mat',artifactName,dataId), sprintf('*%s*.mat',artifactName)};
            seen = containers.Map('KeyType','char','ValueType','logical');
            for p=1:numel(patterns)
                D=dir(fullfile(rootdir,'**',patterns{p})); D=D(~[D.isdir]);
                for i=1:numel(D)
                    f=fullfile(D(i).folder,D(i).name);
                    if ~isKey(seen,f), seen(f)=true; n=n+1; end
                end
            end
        end

        function tf = toLogical(v, defaultValue)
            tf = logical(defaultValue);
            if islogical(v) || isnumeric(v)
                tf = logical(v);
            else
                tf = any(strcmpi(strtrim(char(string(v))), {'1','true','on','yes'}));
            end
        end

        function v = fieldOr(s, field, default)
            v = default;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field)), v = s.(field); end
        end

        function indices = normalizeIndexVector(x)
            if isempty(x), indices=[]; return; end
            if iscell(x), x=[x{:}]; end
            indices = unique(double(x(:)')); indices = indices(isfinite(indices) & indices>=1);
        end
    end
end

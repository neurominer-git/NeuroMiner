classdef NMMLIRuntimeTools
% NMMLIRuntimeTools
% -------------------------------------------------------------------------
% ML-interpretation runner state and MLIdatamat artifact inspection helpers.
% This class is scoped to the browser/API port of nk_MLInterpreterPrep.  It
% is read-only; execution is handled by NMRunTools/NMMLIRunnerUI.
% -------------------------------------------------------------------------

    methods (Static)
        function state = uiState(NM, spec)
            % uiState  Build the browser/API state for the ML-interpretation runner.
            %
            % Reads analysis cards, current selection, grid state, runtime options and artifact summaries into one fixed schema. The method is read-only; it prepares the runner page before NMRunTools executes legacy ML-interpretation code.
            %
            % spec.deferArtifactScan: supplies the defer artifact scan value in the public API/import specification.
            % spec.options: carries additional runner/API options forwarded to lower-level runtime helpers.
            % spec.selectedAnalysisIndices: limits the runtime action to selected analysis indices.
            if nargin < 2 || isempty(spec), spec = struct(); end
            deferArtifactScan = isstruct(spec) && isfield(spec,'deferArtifactScan') && logical(spec.deferArtifactScan);
            oocvMode = NM.defs.analyses_locked;
            analyses = NMMLIRuntimeTools.analysisCards(NM, struct('deferArtifactScan',deferArtifactScan || oocvMode,'useArtifactCache',true));
            selected = NMMLIRuntimeTools.normalizeIndexVector(NMMLIRuntimeTools.fieldOr(spec,'selectedAnalysisIndices',[]));
            if isempty(selected), selected = NMMLIRuntimeTools.defaultSelection(analyses); end
            grid = NMMLIRuntimeTools.gridStateForSelection(NM, selected);
            options = NMMLIRuntimeTools.defaultOptions();
            if isstruct(spec) && isfield(spec,'options') && isstruct(spec.options)
                options = NMMLIRuntimeTools.mergeStruct(options, spec.options);
            end
            resolverOptions = options;
            resolverOptions.useArtifactCache = true;
            if oocvMode && isempty(options.oocvIndex)
                artifactSummary = struct([]);
            elseif deferArtifactScan
                artifactSummary = NMMLIRuntimeTools.lightMLIArtifactSummary(NM, selected, options);
            else
                artifactSummary = NMMLIRuntimeTools.mliArtifactSummary(NM, selected, resolverOptions, grid);
            end
            state = struct('ok',true, 'message','ML-interpretation runtime state derived.', ...
                'analyses',analyses, 'selectedAnalysisIndices',selected, 'grid',grid, ...
                'options',options, 'operationModes',NMMLIRuntimeTools.operationModes(), ...
                'artifactSummary',artifactSummary, 'dynamicControls',struct());
            state.canRun = ~isempty(selected) && (~grid.visible || grid.proceedAllowed);
            state.runReason = 'Ready to run ML interpretation.';
            if isempty(selected), state.runReason = 'Select at least one trained analysis.';
            elseif grid.visible && ~grid.proceedAllowed, state.runReason = 'Select at least one CV2 partition.'; end
            state.canGenerateScript = state.canRun;
            state.scriptReason = state.runReason;
        end

        function opts = defaultOptions()
            % defaultOptions  Return default ML-interpretation runner options.
            %
            % Provides the noninteractive defaults for artifact resolution, scratch/precomputed mode and cache behavior. Callers merge user options over this struct before validating executable state.
            opts = struct('operationMode','auto', 'manualArtifactMode','none', 'manualFiles',struct('mliDataMasterFile','','mliDataFiles',{{}}), ...
                'overwrite',false, 'overwritePermutations',false, 'recomputeEstimates',false, ...
                'saveParameters',false, 'loadParameters',false, 'saveCV1',false, ...
                'exportRelevanceMaps',false, 'surfaceExportFormat','source', ...
                'selectSamples','all', 'sampleIDs',{{}}, 'oocvIndex',[]);
        end

        function modes = operationModes()
            % operationModes  List supported ML-interpretation runner input modes.
            %
            % Returns the mode descriptors used by the browser and script generator to distinguish scratch execution, auto-discovered artifacts and manually selected precomputed artifacts.
            modes = struct('key',{'auto','scratch','mlidatamat'}, ...
                'label',{'Auto','Compute from scratch','Use MLIdatamat'});
        end

        function cards = analysisCards(NM, opts)
            % analysisCards  Summarize analyses available to the ML-interpretation runner.
            %
            % Builds read-only analysis cards from NM.analysis and lightweight artifact indicators. The cards drive selection controls without mutating analysis definitions.
            %
            % opts.deferArtifactScan: postpones artifact discovery so the caller can update state without filesystem scanning.
            % opts.useArtifactCache: allows reuse of previously discovered runtime artifacts when the request permits it.
            if nargin < 2 || isempty(opts), opts = struct(); end
            deferArtifactScan = isstruct(opts) && isfield(opts,'deferArtifactScan') && logical(opts.deferArtifactScan);
            useArtifactCache = isstruct(opts) && isfield(opts,'useArtifactCache') && NMMLIRuntimeTools.toLogical(opts.useArtifactCache, false);
            list = NMAnalysisManagerTools.listAnalyses(NM);
            detail = NMMLIRuntimeTools.emptyMLISummary();
            template = struct('index',0,'id','','description','','rootdir','','status',NaN, ...
                'enabled',false,'disabledReason','','enabledReason','', ...
                'ix',0,'jx',0,'trainedCells',0,'gridAct',[],'spatialMapsAvailable',false,'artifactSummary',detail);
            n = list.count;
            cards = repmat(template,1,n);
            for i = 1:n
                A = NM.analysis{i};
                [ix,jx] = NMMLIRuntimeTools.analysisGridDims(NM,i);
                status = list.status(i);
                gdOK = isfield(A,'GDdims') && ~isempty(A.GDdims) && iscell(A.GDdims) && isstruct(A.GDdims{1});
                trainedMask = false(ix,jx);
                if gdOK && isfield(A.GDdims{1},'GridAct') && ~isempty(A.GDdims{1}.GridAct)
                    trainedMask = logical(A.GDdims{1}.GridAct);
                end
                trainedCells = nnz(trainedMask);
                enabled = isfinite(status) && status >= 1 && gdOK && trainedCells > 0;
                reason = '';
                if ~enabled
                    reason = 'Train at least one CV2 partition successfully before running ML interpretation.';
                end
                cards(i) = template;
                cards(i).index = i;
                cards(i).id = list.ids{i};
                cards(i).description = list.descriptions{i};
                cards(i).rootdir = list.rootdirs{i};
                if isempty(cards(i).rootdir) || exist(cards(i).rootdir,'dir') ~= 7
                    enabled = false;
                    reason = 'Analysis root path is stale or missing. Relink analysis root before running ML interpretation.';
                end
                cards(i).status = status;
                cards(i).enabled = enabled;
                cards(i).disabledReason = reason;
                cards(i).enabledReason = 'Trained-model artifacts are available for ML interpretation.';
                cards(i).ix = ix; cards(i).jx = jx; cards(i).trainedCells = trainedCells;
                cards(i).gridAct = trainedMask;
                members = A.params.TrainParam.FUSION.M;
                cards(i).spatialMapsAvailable = any(arrayfun(@(v) NMModalityInfoTools.isImaging(NM,v), members));
                if ~NM.defs.analyses_locked
                    if deferArtifactScan
                        cards(i).artifactSummary = NMMLIRuntimeTools.lightMLIArtifactSummary(NM, i, NMMLIRuntimeTools.defaultOptions());
                    else
                        cardOptions = NMMLIRuntimeTools.defaultOptions();
                        cardOptions.useArtifactCache = useArtifactCache;
                        cards(i).artifactSummary = NMMLIRuntimeTools.mliArtifactSummary(NM, i, cardOptions, struct());
                    end
                end
            end
        end

        function summary = lightMLIArtifactSummary(NM, selected, opts)
            % lightMLIArtifactSummary  Return cached or summary-only MLIdatamat status for selected analyses.
            %
            % Avoids expensive artifact scanning during initial page load while preserving the runner state schema. A later full mliArtifactSummary call can resolve concrete files and grid coverage.
            if nargin < 3 || isempty(opts), opts = NMMLIRuntimeTools.defaultOptions(); end %#ok<INUSD>
            selected = NMMLIRuntimeTools.normalizeIndexVector(selected);
            if isempty(selected)
                summary = repmat(NMMLIRuntimeTools.emptyMLISummary(),1,0);
                return;
            end
            summary = repmat(NMMLIRuntimeTools.emptyMLISummary(),1,numel(selected));
            for kk = 1:numel(selected)
                idx = selected(kk);
                S = NMMLIRuntimeTools.emptyMLISummary();
                S.analysisIndex = idx;
                if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis) && idx >= 1 && idx <= numel(NM.analysis) && isstruct(NM.analysis{idx})
                    A = NM.analysis{idx};
                    S.inputDir = NMMLIRuntimeTools.mliInputDefaultDir(A, []);
                    S.resultDir = NMMLIRuntimeTools.mliResultDir(A, []);
                    S.dataId = NMMLIRuntimeTools.dataId(NM,A);
                end
                S.coverageText = 'loading';
                S.message = 'MLIdatamat artifact availability is still being resolved.';
                summary(kk) = S;
            end
        end

        function summary = mliArtifactSummary(NM, selected, opts, grid)
            % mliArtifactSummary  Resolve MLIdatamat artifacts for selected analyses and CV grid cells.
            %
            % Combines analysis selection, options and GridAct state to report precomputed MLI artifacts that can satisfy the requested run. The method is read-only and feeds run/script enablement decisions.
            selected = NMMLIRuntimeTools.normalizeIndexVector(selected);
            if isempty(selected)
                summary = repmat(NMMLIRuntimeTools.emptyMLISummary(),1,0);
                return;
            end
            summary = repmat(NMMLIRuntimeTools.emptyMLISummary(),1,numel(selected));
            for kk = 1:numel(selected)
                idx = selected(kk);
                if idx < 1 || ~isfield(NM,'analysis') || idx > numel(NM.analysis) || ~isstruct(NM.analysis{idx})
                    summary(kk) = NMMLIRuntimeTools.emptyMLISummary();
                    summary(kk).analysisIndex = idx;
                    summary(kk).message = 'Analysis does not exist.';
                    continue;
                end
                A = NM.analysis{idx};
                S = NMMLIRuntimeTools.emptyMLISummary();
                S.analysisIndex = idx;
                S.inputDir = NMMLIRuntimeTools.mliInputDefaultDir(A, opts.oocvIndex);
                S.resultDir = NMMLIRuntimeTools.mliResultDir(A, opts.oocvIndex);
                S.dataId = NMMLIRuntimeTools.dataId(NM,A);
                [ix,jx] = NMMLIRuntimeTools.analysisGridDims(NM,idx);
                if isstruct(grid) && isfield(grid,'GridAct') && ~isempty(grid.GridAct) && isequal(size(grid.GridAct),[ix jx])
                    G = logical(grid.GridAct);
                elseif isfield(A,'GDdims') && ~isempty(A.GDdims) && isfield(A.GDdims{1},'GridAct')
                    G = logical(A.GDdims{1}.GridAct);
                else
                    G = true(ix,jx);
                end
                S.nExpected = max(0, nnz(G));
                S.availableGrid = false(ix,jx);
                manual = strcmp(opts.manualArtifactMode,'mlidatamat');
                if manual && ~isempty(opts.manualFiles.mliDataMasterFile)
                    S.inputDir = fileparts(opts.manualFiles.mliDataMasterFile);
                elseif manual && ~isempty(opts.manualFiles.mliDataFiles)
                    S.inputDir = fileparts(opts.manualFiles.mliDataFiles{1});
                end
                useCache = ~manual && NMMLIRuntimeTools.cacheRequested(opts);
                cacheKey = '';
                if useCache
                    cacheKey = NMMLIRuntimeTools.mliArtifactCacheKey(idx, S, G);
                    [cacheHit, cachedSummary] = NMRuntimeArtifactCacheTools.cache('mli','get', cacheKey, []);
                    if cacheHit
                        summary(kk) = cachedSummary;
                        summary(kk).cache = NMRuntimeArtifactCacheTools.info(true, true, cacheKey);
                        continue;
                    end
                end
                S.nExistingResults = NMMLIRuntimeTools.countMLIResults(S.resultDir, S.dataId);
                if isempty(S.inputDir) || exist(S.inputDir,'dir') ~= 7
                    S.coverageText = sprintf('No MLIdatamat directory found (%s).', S.inputDir);
                    S.recommendedOperationMode = 'scratch';
                    S.message = 'No reusable MLIdatamat artifacts were found; compute from scratch.';
                    S.cache = NMRuntimeArtifactCacheTools.info(useCache, false, cacheKey);
                    if useCache, NMRuntimeArtifactCacheTools.cache('mli','put', cacheKey, S); end
                    summary(kk)=S; continue;
                end
                if manual
                    S.masterFile = opts.manualFiles.mliDataMasterFile;
                else
                    S.masterFile = NMMLIRuntimeTools.findMLIMasterFile(S.inputDir, S.dataId);
                end
                if ~isempty(S.masterFile)
                    master = load(S.masterFile,'featmat','datid');
                    if ~strcmp(master.datid, NM.id)
                        error('NMMLIRuntimeTools:masterIdMismatch', 'MLIdatamat master has a different data ID: %s', S.masterFile);
                    end
                    fileGrid = master.featmat;
                    validateattributes(fileGrid,{'cell'},{'size',size(G)},mfilename,'featmat');
                    files = fileGrid(~cellfun(@isempty,fileGrid));
                elseif manual
                    files = opts.manualFiles.mliDataFiles;
                else
                    files = NMMLIRuntimeTools.findMLIFiles(S.inputDir,S.dataId);
                end
                checkDir = '';
                if ~isempty(opts.oocvIndex)
                    checkDir = S.resultDir;
                end
                if ~isempty(checkDir) && ~isempty(S.masterFile) && ~strcmpi(fileparts(S.masterFile),checkDir)
                    error('NMMLIRuntimeTools:wrongOOCVMaster','Selected master file is outside OOCV container %d.',opts.oocvIndex);
                end
                mapped = NMRuntimeGridTools.fileGrid(files,logical(A.GDdims{1}.GridAct),S.dataId,checkDir,'MLIdatamat');
                S.availableGrid = ~cellfun(@isempty,mapped);
                if ~isempty(S.masterFile) && ~isequal(mapped(G),fileGrid(G))
                    error('NMMLIRuntimeTools:masterPartitionMismatch', 'MLIdatamat master does not match stored CV2 coordinates: %s', S.masterFile);
                end
                S.files = files;
                S.nFiles = numel(files);
                S.nAvailable = nnz(~cellfun(@isempty,mapped) & G);
                S.available = S.nExpected > 0 && S.nAvailable >= S.nExpected;
                S.overlap = S.nAvailable > 0;
                nMissing = S.nExpected - S.nAvailable;
                S.coverageText = sprintf('%d/%d selected CV2 partitions available; %d missing; %d file(s) found', ...
                    S.nAvailable,S.nExpected,nMissing,S.nFiles);
                if nMissing
                    S.message = 'MLIdatamat artifacts are partial. Only matching CV2 partitions will be interpreted.';
                else
                    S.message = 'MLIdatamat artifacts cover the selected CV2 partitions.';
                end
                S.recommendedOperationMode = 'scratch';
                S.cache = NMRuntimeArtifactCacheTools.info(useCache, false, cacheKey);
                if useCache, NMRuntimeArtifactCacheTools.cache('mli','put', cacheKey, S); end
                summary(kk)=S;
            end
        end

        function grid = gridStateForSelection(NM, selected)
            % gridStateForSelection  Build the CV2 GridAct picker state for selected ML-interpretation analyses.
            %
            % Derives perm/fold dimensions from selected analyses and normalizes GridAct through NMRuntimeGridTools. The result constrains execution to explicit CV cells without changing NM.
            selected = NMMLIRuntimeTools.normalizeIndexVector(selected);
            grid = struct('visible',false,'hiddenByLegacyRule',false,'proceedAllowed',false, ...
                'reason','Select at least one trained analysis.','ix',0,'jx',0,'GridAct',false(0,0),'state',struct());
            if isempty(selected), return; end
            dims = zeros(numel(selected),2); masks = cell(1,numel(selected));
            for ii=1:numel(selected)
                [dims(ii,1),dims(ii,2)] = NMMLIRuntimeTools.analysisGridDims(NM,selected(ii));
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
                grid.reason = 'Selected analyses have different CV2 grid sizes. The legacy ML-interpretation runner will operate on all trained CV2 partitions per analysis.';
                return;
            end
            G = true(dims(1,1),dims(1,2));
            for ii=1:numel(masks), G = G & masks{ii}; end
            grid.visible = true; grid.hiddenByLegacyRule = false; grid.proceedAllowed = nnz(G)>0;
            grid.reason = 'Select trained CV2 partitions to interpret.';
            grid.ix = dims(1,1); grid.jx = dims(1,2); grid.GridAct = G;
            if exist('NMRuntimeGridTools','class') == 8
                grid.state = NMRuntimeGridTools.state(grid.ix, grid.jx, G, struct('requireAny',true));
            end
        end

        function p = mliResultDir(A,oocvIndex)
            folder = 'MLI';
            if ~isempty(oocvIndex)
                folder = sprintf('OOCV_%d_MLI',oocvIndex);
            end
            p = fullfile(A.rootdir,A.params.TrainParam.SVM.prog,folder);
        end
    end

    methods (Static, Access=private)
        function selected = defaultSelection(analyses)
            selected = [];
            for i=1:numel(analyses)
                if isfield(analyses(i),'enabled') && analyses(i).enabled, selected = analyses(i).index; return; end
            end
        end

        function S = emptyMLISummary()
            S = struct('analysisIndex',0,'inputDir','','resultDir','','dataId','','available',false, ...
                'overlap',false,'recommendedOperationMode','scratch','nExpected',NaN,'nAvailable',0,'nFiles',0, ...
                'nExistingResults',0,'coverageText','not found','message','No MLIdatamat artifacts inspected.', ...
                'masterFile','','files',{{}},'availableGrid',false(0,0), 'cache',NMRuntimeArtifactCacheTools.info(false,false,''));
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

        function p = mliInputDefaultDir(A,oocvIndex)
            if ~isempty(oocvIndex)
                p = NMMLIRuntimeTools.mliResultDir(A,oocvIndex);
                return;
            end
            p = '';
            if ~isstruct(A) || ~isfield(A,'GDdims') || isempty(A.GDdims) || ~isfield(A.GDdims{1},'RootPath'), return; end
            root=A.GDdims{1}.RootPath; if iscell(root), root=root{1}; end
            p=fullfile(char(string(root)),'MLI');
        end

    end

    methods (Static)
        function id = dataId(NM,A)
            id='';
            if isstruct(NM) && isfield(NM,'id') && ~isempty(NM.id), id=char(string(NM.id)); end
            if isempty(id) && isstruct(A) && isfield(A,'id') && ~isempty(A.id), id=char(string(A.id)); end
            id = regexprep(id,'^ID','');
        end
    end

    methods (Static, Access=private)
        function path = findMLIMasterFile(rootdir,dataId)
            path=''; if isempty(rootdir) || exist(rootdir,'dir')~=7, return; end
            D=dir(fullfile(rootdir,sprintf('*MLIdatamatMaster_ID%s.mat',dataId)));
            if ~isempty(D)
                path=fullfile(D(1).folder,D(1).name);
            end
        end

        function files = findMLIFiles(rootdir,dataId)
            files={}; if isempty(rootdir) || exist(rootdir,'dir')~=7, return; end
            D=dir(fullfile(rootdir,'**',sprintf('*MLIdatamat*_ID%s.mat',dataId)));
            D=D(~[D.isdir] & ~contains({D.name},'MLIdatamatMaster'));
            files=fullfile({D.folder},{D.name});
        end

        function n = countMLIResults(resultDir,dataId)
            n=0; if isempty(resultDir) || exist(resultDir,'dir')~=7, return; end
            D=dir(fullfile(resultDir,sprintf('*MLIresults_ID%s.mat',dataId)));
            n=numel(D(~[D.isdir]));
        end

        function tf = cacheRequested(opts)
            tf = isstruct(opts) && isfield(opts,'useArtifactCache') && NMMLIRuntimeTools.toLogical(opts.useArtifactCache, false);
        end

        function key = mliArtifactCacheKey(idx, S, G)
            key = strjoin({ ...
                'NMMLIArtifact:v1', ...
                sprintf('analysis=%d', double(idx)), ...
                ['input=' NMMLIRuntimeTools.safeKeyText(S.inputDir)], ...
                ['result=' NMMLIRuntimeTools.safeKeyText(S.resultDir)], ...
                ['dataId=' NMMLIRuntimeTools.safeKeyText(S.dataId)], ...
                sprintf('grid=%dx%d:%s', size(G,1), size(G,2), mat2str(find(logical(G))')), ...
                ['dir=' NMMLIRuntimeTools.directorySignature(S.inputDir)]}, '|');
        end

        function sig = directorySignature(rootdir)
            if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                sig = 'missing';
                return;
            end
            L = dir(rootdir);
            names = {L.name};
            keep = ~ismember(names,{'.','..'});
            L = L(keep);
            if isempty(L)
                sig = 'root#0#0#0';
            else
                stamps = [L.datenum];
                bytes = [L.bytes];
                sig = sprintf('root#%d#%.0f#%.0f#%.0f', numel(L), ...
                    sum(round(stamps(:) * 86400)), max(round(stamps(:) * 86400)), sum(double(bytes(:))));
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

        function txt = safeKeyText(x)
            txt = regexprep(char(string(x)),'[|\n\r]','_');
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

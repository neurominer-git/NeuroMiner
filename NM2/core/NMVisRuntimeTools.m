classdef NMVisRuntimeTools
% NMVisRuntimeTools
% -------------------------------------------------------------------------
% Visualization-runner state and artifact inspection helpers.  This class is
% intentionally scoped to the browser/API port of nk_VisModelsPrep.  It is
% read-only: visualization execution is handled by NMRunTools/NMVisRunnerUI.
% -------------------------------------------------------------------------

    methods (Static)
        function state = uiState(NM, spec)
            % uiState  Build the browser/API state for the visualization runner.
            %
            % Reads analysis cards, current selection, grid state, runtime options and artifact summaries into one fixed schema. The method is read-only; it prepares the runner page before NMRunTools executes legacy visualization code.
            %
            % spec.deferArtifactScan: supplies the defer artifact scan value in the public API/import specification.
            % spec.options: carries additional runner/API options forwarded to lower-level runtime helpers.
            % spec.selectedAnalysisIndices: limits the runtime action to selected analysis indices.
            if nargin < 2 || isempty(spec), spec = struct(); end
            deferArtifactScan = isstruct(spec) && isfield(spec,'deferArtifactScan') && logical(spec.deferArtifactScan);
            analyses = NMVisRuntimeTools.analysisCards(NM, struct('deferArtifactScan',deferArtifactScan,'useArtifactCache',true));
            selected = NMVisRuntimeTools.normalizeIndexVector(NMVisRuntimeTools.fieldOr(spec,'selectedAnalysisIndices',[]));
            if isempty(selected), selected = NMVisRuntimeTools.defaultSelection(analyses); end
            grid = NMVisRuntimeTools.gridStateForSelection(NM, selected);
            options = NMVisRuntimeTools.defaultOptions();
            if isstruct(spec) && isfield(spec,'options') && isstruct(spec.options)
                options = NMVisRuntimeTools.mergeStruct(options, spec.options);
            end
            resolverOptions = options;
            resolverOptions.useArtifactCache = true;
            if deferArtifactScan
                artifactSummary = NMVisRuntimeTools.lightVisArtifactSummary(NM, selected, options);
            else
                artifactSummary = NMVisRuntimeTools.visArtifactSummary(NM, selected, resolverOptions, grid);
            end
            state = struct('ok',true, 'message','Visualization runtime state derived.', ...
                'analyses',analyses, 'selectedAnalysisIndices',selected, 'grid',grid, ...
                'options',options, 'operationModes',NMVisRuntimeTools.operationModes(), ...
                'artifactSummary',artifactSummary);
            [state.canRun, state.runReason] = NMVisRuntimeTools.validateExecutable(NM, selected, options, grid, false);
            state.canGenerateScript = false;
            state.scriptReason = 'Visualization runtime-script generation will be enabled after NMRunTools.visualizeModels is implemented.';
        end

        function opts = defaultOptions()
            % defaultOptions  Return default visualization runner options.
            %
            % Provides the noninteractive defaults for artifact resolution, scratch/precomputed mode and cache behavior. Callers merge user options over this struct before validating executable state.
            opts = struct('operationMode','auto', 'manualArtifactMode','none', 'manualFiles',struct(), ...
                'overwrite',false, 'operateAtCV1',false, 'saveParameters',false, 'loadParameters',false, ...
                'writeCV2Maps',false, 'cvrNorm','sd', 'decompMode',false, 'lowMemory',false, ...
                'simCorrMethod','spearman', 'simCorrThresh',0.5, 'corrCompCutoff',0.3, ...
                'selCompCutoff',0.1, 'pruneMode','fraction', 'pruneFraction',0.30);
        end

        function modes = operationModes()
            % operationModes  List supported visualization runner input modes.
            %
            % Returns the mode descriptors used by the browser and script generator to distinguish scratch execution, auto-discovered artifacts and manually selected precomputed artifacts.
            modes = struct('key',{'auto','scratch','visdatamat'}, ...
                'label',{'Auto','Compute from scratch','Use VISdatamat'});
        end

        function cards = analysisCards(NM, opts)
            % analysisCards  Summarize analyses available to the visualization runner.
            %
            % Builds read-only analysis cards from NM.analysis and lightweight artifact indicators. The cards drive selection controls without mutating analysis definitions.
            %
            % opts.deferArtifactScan: postpones artifact discovery so the caller can update state without filesystem scanning.
            % opts.useArtifactCache: allows reuse of previously discovered runtime artifacts when the request permits it.
            if nargin < 2 || isempty(opts), opts = struct(); end
            deferArtifactScan = isstruct(opts) && isfield(opts,'deferArtifactScan') && logical(opts.deferArtifactScan);
            useArtifactCache = isstruct(opts) && isfield(opts,'useArtifactCache') && NMVisRuntimeTools.toLogical(opts.useArtifactCache, false);
            list = NMAnalysisManagerTools.listAnalyses(NM);
            detail = NMVisRuntimeTools.emptyVisSummary();
            template = struct('index',0,'id','','description','','rootdir','','status',NaN, ...
                'enabled',false,'disabledReason','','enabledReason','','requiresOverwrite',false, ...
                'ix',0,'jx',0,'trainedCells',0,'gridAct',[],'artifactSummary',detail, ...
                'containsImagingData',false,'permfl',false,'sigfl',false,'permmode',[], ...
                'decompAvailable',false,'lowMemoryVisible',true);
            n = list.count;
            cards = repmat(template,1,n);
            for i = 1:n
                A = NM.analysis{i};
                [ix,jx] = NMVisRuntimeTools.analysisGridDims(NM,i);
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
                    reason = 'Train at least one CV2 partition successfully before running model visualization.';
                end
                cards(i) = template;
                cards(i).index = i;
                cards(i).id = list.ids{i};
                cards(i).description = list.descriptions{i};
                cards(i).rootdir = list.rootdirs{i};
                if isempty(cards(i).rootdir) || exist(cards(i).rootdir,'dir') ~= 7
                    enabled = false;
                    reason = 'Analysis root path is stale or missing. Relink analysis root before running model visualization.';
                end
                cards(i).status = status;
                cards(i).enabled = enabled;
                cards(i).disabledReason = reason;
                cards(i).enabledReason = 'Trained-model artifacts are available for visualization.';
                cards(i).requiresOverwrite = isfield(A,'visdata') && ~isempty(A.visdata);
                cards(i).ix = ix; cards(i).jx = jx; cards(i).trainedCells = trainedCells;
                cards(i).gridAct = trainedMask;
                if deferArtifactScan
                    cards(i).artifactSummary = NMVisRuntimeTools.lightVisArtifactSummary(NM, i, NMVisRuntimeTools.defaultOptions());
                else
                    cardOptions = NMVisRuntimeTools.defaultOptions();
                    cardOptions.useArtifactCache = useArtifactCache;
                    cards(i).artifactSummary = NMVisRuntimeTools.visArtifactSummary(NM, i, cardOptions, struct());
                end
                cards(i).containsImagingData = NMVisRuntimeTools.containsImaging(NM,i);
                [cards(i).permfl,cards(i).sigfl,cards(i).permmode] = NMVisRuntimeTools.permFlags(A);
                d = NMVisRuntimeTools.decompFlags(A);
                cards(i).decompAvailable = any(d);
                cards(i).lowMemoryVisible = NMVisRuntimeTools.lowMemoryVisible(d);
            end
        end

        function summary = lightVisArtifactSummary(NM, selected, opts)
            % lightVisArtifactSummary  Return cached or summary-only VISdatamat status for selected analyses.
            %
            % Avoids expensive artifact scanning during initial page load while preserving the visualization runner state schema. A later full visArtifactSummary call resolves files and grid coverage.
            if nargin < 3 || isempty(opts), opts = NMVisRuntimeTools.defaultOptions(); end
            selected = NMVisRuntimeTools.normalizeIndexVector(selected);
            if isempty(selected)
                summary = repmat(NMVisRuntimeTools.emptyVisSummary(),1,0);
                return;
            end
            summary = repmat(NMVisRuntimeTools.emptyVisSummary(),1,numel(selected));
            for kk = 1:numel(selected)
                idx = selected(kk);
                S = NMVisRuntimeTools.emptyVisSummary();
                S.analysisIndex = idx;
                if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis) && idx >= 1 && idx <= numel(NM.analysis) && isstruct(NM.analysis{idx})
                    A = NM.analysis{idx};
                    S.rootdir = NMVisRuntimeTools.visDefaultDir(A, NMVisRuntimeTools.optionDecompMode(opts));
                    S.dataId = NMVisRuntimeTools.dataId(NM,A);
                end
                S.coverageText = 'loading';
                S.message = 'VISdatamat artifact availability is still being resolved.';
                summary(kk) = S;
            end
        end

        function summary = visArtifactSummary(NM, selected, opts, grid)
            % visArtifactSummary  Resolve VISdatamat artifacts for selected analyses and CV grid cells.
            %
            % Combines selection, options and GridAct state to report visualization artifacts that can satisfy the requested run. The method is read-only and feeds run/script enablement decisions.
            selected = NMVisRuntimeTools.normalizeIndexVector(selected);
            if isempty(selected)
                summary = repmat(NMVisRuntimeTools.emptyVisSummary(),1,0);
                return;
            end
            summary = repmat(NMVisRuntimeTools.emptyVisSummary(),1,numel(selected));
            for kk = 1:numel(selected)
                idx = selected(kk);
                if idx < 1 || ~isfield(NM,'analysis') || idx > numel(NM.analysis) || ~isstruct(NM.analysis{idx})
                    summary(kk) = NMVisRuntimeTools.emptyVisSummary();
                    summary(kk).analysisIndex = idx;
                    summary(kk).message = 'Analysis does not exist.';
                    continue;
                end
                A = NM.analysis{idx};
                S = NMVisRuntimeTools.emptyVisSummary();
                S.analysisIndex = idx;
                S.rootdir = NMVisRuntimeTools.visDefaultDir(A, NMVisRuntimeTools.optionDecompMode(opts));
                S.dataId = NMVisRuntimeTools.dataId(NM,A);
                [ix,jx] = NMVisRuntimeTools.analysisGridDims(NM,idx);
                if isstruct(grid) && isfield(grid,'GridAct') && ~isempty(grid.GridAct) && isequal(size(grid.GridAct),[ix jx])
                    G = logical(grid.GridAct);
                elseif isfield(A,'GDdims') && ~isempty(A.GDdims) && isfield(A.GDdims{1},'GridAct')
                    G = logical(A.GDdims{1}.GridAct);
                else
                    G = true(ix,jx);
                end
                S.nExpected = max(0, nnz(G));
                useCache = NMVisRuntimeTools.cacheRequested(opts);
                cacheKey = '';
                doProfile = NMVisRuntimeTools.profileEnabled();
                if useCache
                    tCacheKey = tic;
                    cacheKey = NMVisRuntimeTools.visArtifactCacheKey(idx, S, G, NMVisRuntimeTools.optionDecompMode(opts));
                    [cacheHit, cachedSummary] = NMRuntimeArtifactCacheTools.cache('vis','get', cacheKey, []);
                    NMVisRuntimeTools.profileLog(doProfile, ...
                        '[nm-prof]     VIS artifact cache lookup analysis=%d: %.3fs (%s)\n', ...
                        double(idx), toc(tCacheKey), NMRuntimeArtifactCacheTools.hitMissText(cacheHit));
                    if cacheHit
                        summary(kk) = cachedSummary;
                        summary(kk).cache = NMRuntimeArtifactCacheTools.info(true, true, cacheKey);
                        continue;
                    end
                end
                tInspect = tic;
                if isempty(S.rootdir) || exist(S.rootdir,'dir') ~= 7
                    S.coverageText = sprintf('No VISdatamat directory found (%s).', S.rootdir);
                    S.recommendedOperationMode = 'scratch';
                    S.message = 'No reusable VISdatamat artifacts were found; compute from scratch.';
                    S.cache = NMRuntimeArtifactCacheTools.info(useCache, false, cacheKey);
                    if useCache, NMRuntimeArtifactCacheTools.cache('vis','put', cacheKey, S); end
                    summary(kk)=S; continue;
                end
                S.masterFile = NMVisRuntimeTools.findVisMasterFile(S.rootdir, S.dataId);
                if ~isempty(S.masterFile)
                    [mAvail, mExpected, mOK, mMsg, mGrid] = NMVisRuntimeTools.visMasterCoverage(S.masterFile, S.dataId, G);
                    if mOK
                        S.availableGrid = mGrid;
                        S.nExpected = mExpected;
                        S.nAvailable = mAvail;
                        S.nFiles = 1;
                        S.files = {S.masterFile};
                        S.available = S.nExpected > 0 && S.nAvailable >= S.nExpected;
                        nMissing = max(0, S.nExpected - S.nAvailable);
                        if nMissing > 0
                            S.coverageText = sprintf('%d/%d selected CV2 cells are listed in VISdataMaster; %d cell(s) will be computed in scratch/resume mode', ...
                                S.nAvailable, S.nExpected, nMissing);
                            S.message = 'VISdataMaster is partially populated. Auto/scratch-resume will reuse existing cells and compute missing selected CV2 cells when overwrite is off.';
                        else
                            S.coverageText = sprintf('%d/%d selected CV2 cells are listed in VISdataMaster; no missing cells', ...
                                S.nAvailable, S.nExpected);
                            S.message = 'VISdataMaster already covers the selected CV2 cells. Auto/scratch-resume will reuse them when overwrite is off.';
                        end
                        S.recommendedOperationMode = 'scratch';
                        S.cache = NMRuntimeArtifactCacheTools.info(useCache, false, cacheKey);
                        if useCache, NMRuntimeArtifactCacheTools.cache('vis','put', cacheKey, S); end
                        NMVisRuntimeTools.profileLog(doProfile, ...
                            '[nm-prof]     VIS artifact inspect analysis=%d: %.3fs (master=1, cache=%d)\n', ...
                            double(idx), toc(tInspect), double(useCache));
                        summary(kk)=S; continue;
                    elseif ~isempty(mMsg)
                        S.message = mMsg;
                    end
                end
                files = NMVisRuntimeTools.findVisFiles(S.rootdir, S.dataId);
                S.files = files;
                S.nFiles = numel(files);
                S.nAvailable = NMVisRuntimeTools.estimateCVCellCoverage(files, G);
                S.available = S.nExpected > 0 && S.nAvailable >= S.nExpected;
                nMissing = max(0, S.nExpected - S.nAvailable);
                if nMissing > 0
                    S.coverageText = sprintf('%d/%d selected CV2 cells already have VISdatamat files; %d cell(s) will be computed in scratch/resume mode; %d file(s) found', ...
                        S.nAvailable, S.nExpected, nMissing, S.nFiles);
                    S.message = 'VISdatamat artifacts are partially available. Auto/scratch-resume will reuse existing files and compute missing selected CV2 cells when overwrite is off.';
                else
                    S.coverageText = sprintf('%d/%d selected CV2 cells already have VISdatamat files; no missing cells; %d file(s) found', ...
                        S.nAvailable, S.nExpected, S.nFiles);
                    S.message = 'VISdatamat artifacts already cover the selected CV2 cells. Auto/scratch-resume will reuse them when overwrite is off.';
                end
                S.recommendedOperationMode = 'scratch';
                S.cache = NMRuntimeArtifactCacheTools.info(useCache, false, cacheKey);
                if useCache, NMRuntimeArtifactCacheTools.cache('vis','put', cacheKey, S); end
                NMVisRuntimeTools.profileLog(doProfile, ...
                    '[nm-prof]     VIS artifact inspect analysis=%d: %.3fs (master=0, files=%d, cache=%d)\n', ...
                    double(idx), toc(tInspect), double(S.nFiles), double(useCache));
                summary(kk)=S;
            end
        end

        function [ok, msg] = validateExecutable(~, selected, opts, grid, allowExecution)
            % validateExecutable  Decide whether the current visualization runner state can be executed.
            %
            % Checks analysis selection, option mode, GridAct coverage and artifact availability when precomputed inputs are required. The boolean/message result is used by run and script buttons before legacy runtime code is invoked.
            %
            % opts.operationMode: selects the runner operation mode requested by the caller.
            ok = false;
            selected = NMVisRuntimeTools.normalizeIndexVector(selected);
            if isempty(selected), msg = 'Select at least one trained analysis.'; return; end
            if isstruct(grid) && isfield(grid,'visible') && grid.visible && isfield(grid,'proceedAllowed') && ~grid.proceedAllowed
                msg = 'Select at least one CV2 cell.'; return;
            end
            mode = char(string(NMVisRuntimeTools.fieldOr(opts,'operationMode','auto')));
            if strcmpi(mode,'visdatamat') && isstruct(grid) && isfield(grid,'artifactSummary') %#ok<*BDSCA>
                % Reserved for later run validation.
            end
            ok = logical(allowExecution);
            if ok
                msg = 'Ready to run model visualization.';
            else
                msg = 'Visualization execution is not enabled yet. This page currently validates selections and artifact state only.';
            end
        end

        function grid = gridStateForSelection(NM, selected)
            % gridStateForSelection  Build the CV2 GridAct picker state for selected visualization analyses.
            %
            % Derives perm/fold dimensions from selected analyses and normalizes GridAct through NMRuntimeGridTools. The result constrains execution to explicit CV cells without changing NM.
            selected = NMVisRuntimeTools.normalizeIndexVector(selected);
            grid = struct('visible',false,'hiddenByLegacyRule',false,'proceedAllowed',false, ...
                'reason','Select at least one trained analysis.','ix',0,'jx',0,'GridAct',false(0,0),'state',struct());
            if isempty(selected), return; end
            dims = zeros(numel(selected),2); masks = cell(1,numel(selected));
            for ii=1:numel(selected)
                [dims(ii,1),dims(ii,2)] = NMVisRuntimeTools.analysisGridDims(NM,selected(ii));
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
                grid.reason = 'Selected analyses have different CV2 grid sizes. The legacy visualization runner will operate on all trained cells per analysis.';
                return;
            end
            G = true(dims(1,1),dims(1,2));
            for ii=1:numel(masks), G = G & masks{ii}; end
            grid.visible = true; grid.hiddenByLegacyRule = false; grid.proceedAllowed = nnz(G)>0;
            grid.reason = 'Select trained CV2 permutation/fold cells to visualize.';
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
        function S = emptyVisSummary()
            S = struct('analysisIndex',0,'rootdir','','dataId','','available',false, ...
                'recommendedOperationMode','scratch','nExpected',NaN,'nAvailable',0,'nFiles',0, ...
                'coverageText','not found','message','No VISdatamat artifacts inspected.', ...
                'masterFile','','files',{{}}, 'availableGrid',[], 'cache',NMRuntimeArtifactCacheTools.info(false,false,''));
        end
        function opts = mergeStruct(opts, override)
            f=fieldnames(override); for i=1:numel(f), opts.(f{i})=override.(f{i}); end
        end
        function [ix,jx] = analysisGridDims(NM,idx)
            ix=0; jx=0;
            if ~isstruct(NM)||~isfield(NM,'analysis')||~iscell(NM.analysis)||idx<1||idx>numel(NM.analysis)||~isstruct(NM.analysis{idx}), return; end
            A=NM.analysis{idx};
            if isfield(A,'params')&&isstruct(A.params)&&isfield(A.params,'cv')&&isstruct(A.params.cv)&&isfield(A.params.cv,'TrainInd')
                [ix,jx]=size(A.params.cv.TrainInd);
            elseif isfield(A,'GDdims')&&iscell(A.GDdims)&&~isempty(A.GDdims)&&isstruct(A.GDdims{1})&&isfield(A.GDdims{1},'GridAct')
                [ix,jx]=size(A.GDdims{1}.GridAct);
            end
        end
        function p = visDefaultDir(A, compwise)
            p=''; if ~isstruct(A) || ~isfield(A,'GDdims') || isempty(A.GDdims) || ~isfield(A.GDdims{1},'RootPath'), return; end
            root=A.GDdims{1}.RootPath; if iscell(root), root=root{1}; end
            [permfl,sigfl,permmode]=NMVisRuntimeTools.permFlags(A);
            if permfl
                switch permmode
                    case 1, visdir='VISUAL_L'; case 2, visdir='VISUAL_F'; case 3, visdir='VISUAL_LF'; case 4, visdir='VISUAL_COVAR'; otherwise, error('NMVisRuntimeTools:InvalidPermutationMode','Unsupported visualization permutation mode: %g.',double(permmode)); end
            elseif sigfl
                visdir='VISUAL_P';
            else
                visdir='VISUAL';
            end
            if logical(compwise), visdir=[visdir 'c']; end
            p=fullfile(char(string(root)),visdir);
        end
        function id = dataId(NM,A)
            id=''; if isstruct(A) && isfield(A,'id') && ~isempty(A.id), id=char(string(A.id)); end
            if isempty(id) && isstruct(NM) && isfield(NM,'id') && ~isempty(NM.id), id=char(string(NM.id)); end
            id = regexprep(id,'^ID','');
        end
        function path = findVisMasterFile(rootdir,dataId)
            path=''; if isempty(rootdir) || exist(rootdir,'dir')~=7, return; end
            patterns = {sprintf('*VISdataMaster*ID%s*.mat',dataId), sprintf('*VISdataMaster*%s*.mat',dataId), '*VISdataMaster*.mat'};
            for p=1:numel(patterns)
                D=dir(fullfile(rootdir,patterns{p}));
                D=D(~[D.isdir]);
                if ~isempty(D), path=fullfile(D(1).folder,D(1).name); return; end
            end
        end

        function [nAvail,nExpected,ok,msg,availableGrid] = visMasterCoverage(path,dataId,G)
            nAvail=0; nExpected=max(0,nnz(G)); ok=false; msg=''; availableGrid=[];
            if isempty(path) || exist(path,'file')~=2, msg='VISdataMaster file is not readable.'; return; end
            try
                S=load(path,'featmat','datid');
            catch ME
                msg=sprintf('Could not read VISdataMaster: %s (%s)', ME.message, ME.identifier); return;
            end
            if isfield(S,'datid') && ~isempty(S.datid) && ~strcmp(char(string(S.datid)),char(string(dataId)))
                msg='VISdataMaster data ID does not match current NM.id.'; return;
            end
            if ~isfield(S,'featmat') || isempty(S.featmat)
                msg='VISdataMaster contains no featmat field.'; return;
            end
            ok=true;
            try
                if iscell(S.featmat) && isequal(size(S.featmat),size(G))
                    availableGrid=~cellfun(@isempty,S.featmat);
                    nAvail=nnz(availableGrid & logical(G));
                elseif iscell(S.featmat) && numel(S.featmat)==numel(G)
                    availableGrid=reshape(~cellfun(@isempty,S.featmat),size(G));
                    nAvail=nnz(availableGrid & logical(G));
                else
                    nAvail=double(~isempty(S.featmat));
                    nExpected=max(1,nExpected);
                end
            catch
                [nAvail,~]=NMVisRuntimeTools.cellCoverage(S.featmat);
                nAvail=min(nAvail,nExpected);
            end
        end

        function [nAvail,nTotal] = cellCoverage(x)
            if iscell(x)
                nAvail=0; nTotal=numel(x);
                for cc=1:numel(x)
                    if iscell(x{cc})
                        [a,t]=NMVisRuntimeTools.cellCoverage(x{cc});
                        nAvail=nAvail+a;
                        if t>0, nTotal=nTotal+t-1; end
                    elseif ~isempty(x{cc})
                        nAvail=nAvail+1;
                    end
                end
            else
                nTotal=1;
                nAvail=double(~isempty(x));
            end
        end

        function files = findVisFiles(rootdir,dataId)
            files={}; if isempty(rootdir) || exist(rootdir,'dir')~=7, return; end
            doProfile = NMVisRuntimeTools.profileEnabled();
            tScan = tic;
            patterns = {sprintf('*VISdatamat*ID%s*.mat',dataId), sprintf('*VISdatamat*%s*.mat',dataId), '*VISdatamat*.mat'};
            seen = containers.Map('KeyType','char','ValueType','logical');
            for p=1:numel(patterns)
                D=dir(fullfile(rootdir,'**',patterns{p}));
                for i=1:numel(D)
                    f=fullfile(D(i).folder,D(i).name);
                    if ~isKey(seen,f), seen(f)=true; files{end+1}=f; end %#ok<AGROW>
                end
            end
            NMVisRuntimeTools.profileLog(doProfile, ...
                '[nm-prof]       VIS recursive CV2-file scan: %.3fs (files=%d)\n', toc(tScan), double(numel(files)));
        end
        function n = estimateCVCellCoverage(files,G)
            if isempty(G), n=0; return; end
            if isempty(files), n=0; return; end
            % VISdatamat files are not guaranteed to expose a uniform index variable.
            % Use a conservative lower bound from filename/master counts.
            n = min(nnz(G), numel(files));
        end
        function tf = containsImaging(NM,idx)
            if exist('nk_CheckContainsImagingData','file')~=2
                error('NMVisRuntimeTools:MissingImagingDetector','nk_CheckContainsImagingData.m is required to resolve visualization imaging capability.');
            end
            tf=logical(nk_CheckContainsImagingData(NM,idx));
            if ~isscalar(tf), error('NMVisRuntimeTools:InvalidImagingCapability','Imaging capability resolution must return one logical value per analysis.'); end
        end
        function [permfl,sigfl,permmode] = permFlags(A)
            permfl=false; sigfl=false; permmode=[];
            if ~isstruct(A)||~isfield(A,'params')||~isstruct(A.params)||~isfield(A.params,'TrainParam')||~isstruct(A.params.TrainParam)|| ...
                    ~isfield(A.params.TrainParam,'FUSION')||~isstruct(A.params.TrainParam.FUSION)||~isfield(A.params.TrainParam.FUSION,'M')|| ...
                    ~isfield(A.params.TrainParam,'VIS')||~iscell(A.params.TrainParam.VIS), return; end
            varind=A.params.TrainParam.FUSION.M;
            for i=1:numel(varind)
                vi=double(varind(i));
                if ~isscalar(vi)||~isfinite(vi)||vi<1||vi~=round(vi)||vi>numel(A.params.TrainParam.VIS)
                    error('NMVisRuntimeTools:InvalidVISIndex','Visualization permutation configuration references an invalid VIS index.');
                end
                V=A.params.TrainParam.VIS{vi}; if ~isstruct(V)||~isfield(V,'PERM')||isempty(V.PERM), continue; end
                if ~isstruct(V.PERM), error('NMVisRuntimeTools:InvalidPermutationContract','VIS.PERM must be a structure when present.'); end
                flag=false; sigflag=false;
                if isfield(V.PERM,'flag')&&~isempty(V.PERM.flag)
                    if ~(islogical(V.PERM.flag)||isnumeric(V.PERM.flag))||~isscalar(V.PERM.flag)||~isfinite(double(V.PERM.flag)), error('NMVisRuntimeTools:InvalidPermutationContract','VIS.PERM.flag must be one finite logical/numeric value.'); end
                    flag=logical(V.PERM.flag);
                end
                if isfield(V.PERM,'sigflag')&&~isempty(V.PERM.sigflag)
                    if ~(islogical(V.PERM.sigflag)||isnumeric(V.PERM.sigflag))||~isscalar(V.PERM.sigflag)||~isfinite(double(V.PERM.sigflag)), error('NMVisRuntimeTools:InvalidPermutationContract','VIS.PERM.sigflag must be one finite logical/numeric value.'); end
                    sigflag=logical(V.PERM.sigflag);
                end
                if flag, permfl=true; if isfield(V.PERM,'mode'), permmode=V.PERM.mode; end
                elseif sigflag, sigfl=true; end
                break;
            end
        end
        function d = decompFlags(A)
            FUSION=A.params.TrainParam.FUSION;
            switch FUSION.flag
                case {0,1}, PREPROCs=A.params.TrainParam.PREPROC(FUSION.M(1));
                case 2, PREPROCs=A.params.TrainParam.PREPROC(FUSION.M);
                case 3
                    nM=numel(FUSION.M); PREPROCs=cell(1,nM);
                    for n=1:nM, PREPROCs{n}=A.params.TrainParam.STRAT{FUSION.M(n)}.PREPROC; end
                otherwise
                    error('NMVisRuntimeTools:badFusionFlag', 'Unsupported visualization fusion flag: %g.', double(FUSION.flag));
            end
            d=false(1,numel(PREPROCs));
            for i=1:numel(PREPROCs), d(i)=nk_DetIfDimRefInPREPROC(PREPROCs{i},i); end
            if any(d) && FUSION.flag==1, d=true(1,numel(d)); end
        end
        function tf = lowMemoryVisible(d)
            tf = isempty(d) || (isscalar(d) && ~d) || sum(d)<numel(d);
        end
        function tf = optionDecompMode(opts)
            tf = isstruct(opts) && isfield(opts,'decompMode') && logical(opts.decompMode);
        end
        function tf = cacheRequested(opts)
            tf = isstruct(opts) && isfield(opts,'useArtifactCache') && NMVisRuntimeTools.toLogical(opts.useArtifactCache, false);
        end

        function key = visArtifactCacheKey(idx, S, G, decompMode)
            key = strjoin({ ...
                'NMVisArtifact:v1', ...
                sprintf('analysis=%d', double(idx)), ...
                ['root=' NMVisRuntimeTools.safeKeyText(S.rootdir)], ...
                ['dataId=' NMVisRuntimeTools.safeKeyText(S.dataId)], ...
                sprintf('decomp=%d', double(decompMode)), ...
                sprintf('grid=%dx%d:%s', size(G,1), size(G,2), mat2str(find(logical(G))')), ...
                ['dir=' NMVisRuntimeTools.directorySignature(S.rootdir)]}, '|');
        end

        function sig = directorySignature(rootdir)
            if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                sig = 'missing';
                return;
            end
            chunks = {'unreadable'};
            try
                L = dir(rootdir);
                names = {L.name};
                keep = ~ismember(names,{'.','..'});
                L = L(keep);
                D = L([L.isdir]);
                chunks = cell(1, 1 + numel(D));
                if isempty(L)
                    chunks{1} = 'root#0#0#0';
                else
                    stamps = [L.datenum];
                    bytes = [L.bytes];
                    chunks{1} = sprintf('root#%d#%.0f#%.0f#%.0f', numel(L), ...
                        sum(round(stamps(:) * 86400)), max(round(stamps(:) * 86400)), sum(double(bytes(:))));
                end
                for ii = 1:numel(D)
                    d = fullfile(D(ii).folder, D(ii).name);
                    try
                        C = dir(d);
                        cn = {C.name};
                        ck = ~ismember(cn,{'.','..'});
                        C = C(ck);
                        if isempty(C)
                            chunks{ii+1} = sprintf('%s#0#0#0', NMVisRuntimeTools.safeKeyText(D(ii).name));
                        else
                            cstamps = [C.datenum];
                            cbytes = [C.bytes];
                            chunks{ii+1} = sprintf('%s#%d#%.0f#%.0f#%.0f', NMVisRuntimeTools.safeKeyText(D(ii).name), numel(C), ...
                                sum(round(cstamps(:) * 86400)), max(round(cstamps(:) * 86400)), sum(double(cbytes(:))));
                        end
                    catch
                        chunks{ii+1} = sprintf('%s#unreadable', NMVisRuntimeTools.safeKeyText(D(ii).name));
                    end
                end
            catch
                chunks = {'unreadable'};
            end
            sig = strjoin(chunks, ';');
        end



        function tf = toLogical(v, defaultValue)
            tf = logical(defaultValue);
            try
                if islogical(v) || isnumeric(v)
                    tf = logical(v);
                else
                    tf = any(strcmpi(strtrim(char(string(v))), {'1','true','on','yes'}));
                end
            catch
                tf = logical(defaultValue);
            end
        end

        function txt = safeKeyText(v)
            try
                txt = char(string(v));
            catch
                txt = '';
            end
            txt = strrep(txt, '|', '/');
            txt = strrep(txt, char(10), ' ');
            txt = strrep(txt, char(13), ' ');
        end

        function tf = profileEnabled()
            tf = false;
            try
                env = getenv('NM_UI_PROFILE');
                if ~isempty(env)
                    tf = any(strcmpi(strtrim(env), {'1','true','on','yes'}));
                end
            catch
                tf = false;
            end
        end

        function profileLog(enabled, varargin)
            if ~enabled, return; end
            try
                fprintf(varargin{:});
            catch
            end
        end

        function v = fieldOr(s, field, default)
            v=default; if isstruct(s) && isfield(s,field) && ~isempty(s.(field)), v=s.(field); end
        end
        function indices = normalizeIndexVector(x)
            if isempty(x), indices=[]; return; end
            if iscell(x), x=[x{:}]; end
            indices = unique(double(x(:)')); indices = indices(isfinite(indices) & indices>=1);
        end
    end
end

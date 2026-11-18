classdef NMPreprocessRunnerUI
% NMPreprocessRunnerUI
% -------------------------------------------------------------------------
% Dedicated browser page for the legacy preprocessing runtime stage.
%
% The page is an app/workbench child entry point around NMRunTools and
% NMRuntimeActionTools.  It mirrors the dynamic controls exposed by
% nk_PreprocessPrep without calling that legacy Prep function directly from
% JavaScript.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(NM, outDir, ctx)
            % export  Create the browser preprocessing runtime runner session.
            %
            % Writes the runner HTML, initial artifact/grid state and shared assets, then stores the
            % session NM for service requests. This prepares the preprocessing runtime workflow page but
            % leaves actual run/script execution to the MATLAB service handler.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_preprocess_runner_ui'); end
            if nargin < 3, ctx = struct(); end

            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_preprocess_runner_ui');
            NMDataIOUI.saveSessionNM(NM, dirs.tmpDir);

            if NMUISessionTools.fastChildOpen(ctx)
                state = NMPreprocessRunnerUI.bootstrapState(ctx);
            else
                state = NMPreprocessRunnerUI.stateFromNM(NM, ctx);
            end
            stateJson = NMConfigTools.writeJsonAliases({ ...
                fullfile(dirs.tmpDir,'preprocess_runner_state.json'), ...
                fullfile(dirs.tmpDir,'current_config.json'), ...
                fullfile(dirs.tmpDir,'param.json')}, state, 'preprocessing runner state');

            htmlPath = fullfile(dirs.webDir, 'nm_preprocess_runner.html');
            NMPreprocessRunnerUI.writeTextFile(htmlPath, NMPreprocessRunnerUI.htmlTextFromJson(stateJson));
            NMPreprocessRunnerUI.copyAssets(dirs.webDir);
            NMPreprocUI.writeBridge(fullfile(dirs.pyDir,'nm_bridge_server.py'));

            paths = struct('root', dirs.root, 'webRoot', dirs.webRoot, 'webDir', dirs.webDir, ...
                'tmpDir', dirs.tmpDir, 'html', htmlPath, 'preprocessRunnerHtml', htmlPath, ...
                'entryHtml', 'nm_preprocess_runner.html', 'entryHtmlPath', htmlPath, ...
                'state', fullfile(dirs.tmpDir,'preprocess_runner_state.json'));
        end

        function NM = importUpdated(NM, pathsOrWebDir, ctx)
            % importUpdated  Return the session NM after the preprocessing runtime runner closes.
            %
            % Reloads session NM written by service calls and clears the transient copy. Runner pages are
            % primarily runtime launchers, so most state is refreshed through explicit services rather
            % than direct browser mutation.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(pathsOrWebDir), return; end
            tmpDir = NMDataIOUI.pathsTmpDir(pathsOrWebDir);
            if isempty(tmpDir), return; end
            [NM2, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
            if ok, NM = NM2; end
            NMDataIOUI.clearSessionNM(tmpDir);
        end

        function state = stateFromNM(NM, ctx, opts)
            % stateFromNM  Build artifact and option state for the preprocessing runtime runner.
            %
            % Derives available analyses, CV grid selections and runtime artifacts from NM through the
            % relevant runtime resolver. The method is read-only and provides the state consumed by
            % runner JavaScript.
            %
            % opts.deferArtifactScan: postpones artifact discovery so the caller can update state without filesystem scanning.

            if nargin < 2, ctx = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            if nargin < 1 || isempty(NM), NM = struct(); end
            deferArtifactScan = isstruct(opts) && isfield(opts,'deferArtifactScan') && logical(opts.deferArtifactScan);
            if exist('NMStatusGuardTools','class') == 8
                defs = NMStatusGuardTools.defsState(NM);
                workflow = NMStatusGuardTools.workflowStatus(NM);
            else
                defs = struct('import_finished',false,'analyses_locked',false);
                workflow = struct('ok',false,'message','NMStatusGuardTools is not available.', ...
                    'import_finished',false,'setup_ok',false,'analyses_locked',false, ...
                    'analyses_exist',false,'analyses_ready',false,'completed_analyses',false(1,0), ...
                    'status_analyses',NaN(1,0));
            end
            analyses = NMPreprocessRunnerUI.analysisCards(NM, defs, deferArtifactScan);
            selected = NMPreprocessRunnerUI.defaultSelection(analyses);
            grid = NMPreprocessRunnerUI.gridStateForSelection(NM, selected);

            state = struct();
            state.page = 'preprocess_runner';
            state.defs = defs;
            state.workflowStatus = workflow;
            state.analyses = analyses;
            if exist('NMAnalysisManagerTools','class') == 8
                state.analysisList = NMAnalysisManagerTools.listAnalyses(NM);
            else
                state.analysisList = struct();
            end
            state.selectedAnalysisIndices = selected;
            state.grid = grid;
            state.options = NMPreprocessRunnerUI.defaultOptions();
            state.canRun = ~deferArtifactScan && ~isempty(selected) && logical(grid.proceedAllowed);
            state.loading = false;
            state.analysesLoading = false;
            state.artifactsLoading = deferArtifactScan;
            if deferArtifactScan
                state.statusMessage = 'Loading runtime feasibility and artifact availability from MATLAB.';
            else
                state.statusMessage = NMPreprocessRunnerUI.statusMessage(defs, workflow, analyses);
            end
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'preprocess_runner');
        end

        function state = bootstrapState(ctx)
            % bootstrapState  Build a minimal preprocessing runtime runner state for fast navigation.
            %
            % Uses app context to render the page shell before the full artifact resolver runs. The
            % complete state is requested immediately through the MATLAB bridge.

            if nargin < 1, ctx = struct(); end
            defs = struct('import_finished',false,'analyses_locked',false);
            workflow = struct('ok',true,'message','Preprocessing runner is loading the current NeuroMiner state.', ...
                'import_finished',false,'setup_ok',false,'analyses_locked',false, ...
                'analyses_exist',false,'analyses_ready',false,'completed_analyses',false(1,0), ...
                'status_analyses',NaN(1,0));
            grid = struct('visible',false, 'hiddenByLegacyRule',false, 'proceedAllowed',false, ...
                'reason','Loading CV2 partition state from MATLAB.', 'ix',0, 'jx',0, ...
                'state',struct(), 'GridAct',false(0,0));
            analysisTemplate = struct('index',0,'id','','description','','rootdir','', ...
                'status',NaN,'enabled',false,'disabledReason','','requiresOverwrite',false,'ix',0,'jx',0);
            state = struct();
            state.page = 'preprocess_runner';
            state.defs = defs;
            state.workflowStatus = workflow;
            state.analyses = repmat(analysisTemplate, 1, 0);
            state.analysisList = struct();
            state.selectedAnalysisIndices = [];
            state.grid = grid;
            state.options = NMPreprocessRunnerUI.defaultOptions();
            state.canRun = false;
            state.loading = true;
            state.analysesLoading = true;
            state.artifactsLoading = true;
            state.statusMessage = 'Loading analyses...';
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'preprocess_runner');
        end

        function [handled, out] = handleMatlabService(NM, req, tmpDir, ctx)
            % handleMatlabService  Dispatch preprocessing runtime runner service requests.
            %
            % Handles refresh, artifact resolution, run and script-generation operations by loading
            % session NM and delegating to NMPreprocRuntimeTools. Responses include updated runner state
            % and explicit diagnostics for the browser message strip.

            handled = false;
            out = struct();
            if nargin < 4, ctx = struct(); end
            if nargin < 3, tmpDir = ''; end
            op = NMPreprocessRunnerUI.requestOperation(req);
            if isempty(op), return; end
            switch lower(op)
                case {'preprocess_runner_refresh','preprocess_runner_state'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    if ~ok, sessionNM = NM; end
                    state = NMPreprocessRunnerUI.stateFromNM(sessionNM, ctx);
                    out = struct('ok',true,'message','Preprocessing runner state refreshed.', 'state',state, 'operation',op);
                case {'preprocess_runner_refresh_light','preprocess_runner_state_light'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    if ~ok, sessionNM = NM; end
                    state = NMPreprocessRunnerUI.stateFromNM(sessionNM, ctx, struct('deferArtifactScan',true));
                    out = struct('ok',true,'message','Analyses loaded. Runtime feasibility is still being resolved.', 'state',state, 'operation',op);
                case {'preprocess_runner_run'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    if ~ok, sessionNM = NM; end
                    try
                        plan = NMPreprocessRunnerUI.requestPlan(req);
                        plan = NMPreprocessRunnerUI.attachRuntimeProgressContext(plan, req, tmpDir);
                        [sessionNM, runOut] = NMPreprocessRunnerUI.runPreprocessing(sessionNM, plan);
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMPreprocessRunnerUI.stateFromNM(sessionNM, ctx);
                        out = struct('ok',true, 'message',runOut.message, 'operation',op, ...
                            'state',state, 'result',runOut);
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Running preprocessing failed.', 2);
                    end
                case {'preprocess_runner_generate_script'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    if ~ok, sessionNM = NM; end
                    try
                        plan = NMPreprocessRunnerUI.requestPlan(req);
                        genOut = NMPreprocessRunnerUI.generateRuntimeScript(sessionNM, plan);
                        out = struct('ok',true, 'message',genOut.message, 'operation',op, ...
                            'scripts',{genOut.scripts});
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Generating the runtime script failed.', 2);
                    end
                otherwise
                    handled = true;
                    out = struct('ok',false,'message',sprintf('Unsupported preprocessing-runner operation: %s', op), ...
                        'error',sprintf('Unsupported preprocessing-runner operation: %s', op));
            end
        end

        function txt = htmlTextFromJson(stateJson)
            % htmlTextFromJson  Build the preprocessing runtime runner HTML shell.
            %
            % Creates the static page frame, embeds the state reference and loads shared
            % runner/grid-picker/navigation assets. All scientific/runtime decisions remain in
            % MATLAB-side service calls.

            jsState = NMPreprocUI.jsonTextForScript(stateJson);
            assetTag = NMPreprocessRunnerUI.assetCacheTag();
            nl = newline;
            L = { ...
'<!doctype html>'
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
'<title>NeuroMiner preprocessing runner</title>'
['<link rel="stylesheet" href="NMTrainTemplateUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModuleNavigationRail.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisManagerUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMRuntimeGridPicker.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModal.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMRuntimeProgressViewer.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisCardSelector.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMPreprocessRunnerUI.css?v=' assetTag '">']
['<style>' NMUIMessageTools.css() '</style>']
'</head><body class="nmHasNavRail">'
'<header>'
'  <div><div class="crumb">Main interface / model discovery</div><div class="title">Preprocess features</div></div>'
'  <div class="headerActions"><button id="finish" class="primary" type="button">Finish / close</button></div>'
'</header>'
'<main class="wrap prWrap"><section class="panel prPanel">'
'  <div class="prPanelHead"><div><h1>Configure and run NeuroMiner preprocessing</h1></div></div>'
'  <div class="prLayout">'
'    <section class="card prConfigPanel">'
'      <div class="prSectionHeader"><h2>Runtime configuration</h2><span id="selectedSummary" class="muted"></span></div>'
'      <div class="field"><label class="nmRunnerSectionTitle">Preprocessing artifact handling</label><label><input id="overwriteExisting" type="checkbox"> Overwrite existing preprocessing outputs</label></div>'
'      <div class="field"><label><input id="useExistingParameters" type="checkbox" checked> Reuse existing preprocessing parameters</label></div>'
'      <div id="writeParametersField" class="field"><label><input id="writeParameters" type="checkbox"> Save newly estimated preprocessing parameters</label><div class="help">Write the estimated preprocessing parameters to disk so they can be reused in later runs. This can substantially increase disk usage.</div></div>'
'      <div id="gridSection" class="field">'
'        <label class="nmRunnerSectionTitle">CV2 partitions</label>'
'        <div id="gridReason" class="help"></div>'
'        <div id="gridPicker"></div>'
'      </div>'
'      <div id="gridHiddenNote" class="field hidden"><label class="nmRunnerSectionTitle">CV2 partitions</label><div class="help">Selected analyses have different CV2 grid structures. Each analysis will run all CV2 cells.</div></div>'
'      <div class="actions prRunRow"><button id="runPreprocessing" class="primary nmActionButton" type="button">Run preprocessing</button><button id="generateRuntimeScript" class="nmActionButton" type="button">Generate runtime script</button></div>'
'      <div id="runHint" class="muted"></div>'
'    </section>'
'    <section class="card prAnalysisPanel">'
'      <div class="prSectionHeader"><h2>Analysis selection</h2><span class="muted">Select one or more analyses</span></div>'
'      <div id="analysisList" class="amAnalysisList prAnalysisList"></div>'
'    </section>'
'  </div>'
'</section></main>'
['<script>window.NM_PREPROCESS_RUNNER_STATE = ' jsState ';</script>']
['<script>' NMUIMessageTools.script() '</script>']
['<script>window.NM_MODULE_NAV_CONTEXT = {currentModule:"preprocess"};</script>']
['<script src="NMRuntimeGridPicker.js?v=' assetTag '"></script>']
['<script src="NMModal.js?v=' assetTag '"></script>']
['<script src="NMRuntimeProgressViewer.js?v=' assetTag '"></script>']
['<script src="NMRuntimeJobClient.js?v=' assetTag '"></script>']
['<script src="NMAnalysisCardSelector.js?v=' assetTag '"></script>']
['<script src="NMModuleIconSet.js?v=' assetTag '"></script>']
['<script src="NMModuleNavigationRail.js?v=' assetTag '"></script>']
['<script src="NMRunnerStateManager.js?v=' assetTag '"></script>']
['<script src="NMPreprocessRunnerUI_main.js?v=' assetTag '"></script>']
'</body></html>'};
            txt = strjoin(L, nl);
        end

        function copyAssets(webDir)
            % copyAssets  Copy static assets for the preprocessing runtime runner page.
            %
            % Copies runner JavaScript/CSS plus shared navigation, icon, picker and message-strip assets
            % into the exported web directory. It keeps page export self-contained for the bridge.

            srcDir = fileparts(mfilename('fullpath'));
            assets = {'NMTrainTemplateUI.css','NMModuleIconSet.js','NMModuleNavigationRail.js','NMModuleNavigationRail.css','NMAnalysisManagerUI.css','NMRuntimeGridPicker.js', ...
                'NMRuntimeGridPicker.css','NMModal.js','NMModal.css','NMRuntimeProgressViewer.js','NMRuntimeProgressViewer.css','NMRuntimeJobClient.js', ...
                'NMAnalysisCardSelector.js','NMAnalysisCardSelector.css','NMRunnerStateManager.js','NMPreprocessRunnerUI_main.js','NMPreprocessRunnerUI.css'};
            for i = 1:numel(assets)
                src = fullfile(srcDir, assets{i});
                if exist(src,'file') == 2
                    copyfile(src, fullfile(webDir, assets{i}), 'f');
                end
            end
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the preprocessing runner text-writer entry point.
            %
            %   NMPreprocessRunnerUI.writeTextFile(path,txt) delegates generated runner HTML and script
            %   text output to NMSerializationTools while retaining preprocessing-runner diagnostics.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMPreprocessRunnerUI:writeFailed', 'Could not write %s.', 'fwrite-input-char');
        end
        function tag = assetCacheTag()
            % assetCacheTag  Return the cache-busting token used by preprocessing runner assets.
            %
            % Provides a stable query-string/version tag for browser asset reloads after runner UI
            % changes. It has no effect on preprocessing configuration or runtime execution.

            try
                tag = char(java.util.UUID.randomUUID());
            catch
                tag = strrep(sprintf('%.10f', now), '.', '_');
            end
        end
    end

    methods (Static, Access = private)
        function cards = analysisCards(NM, defs, deferArtifactScan)
            if nargin < 3 || isempty(deferArtifactScan), deferArtifactScan = false; end
            list = NMAnalysisManagerTools.listAnalyses(NM);
            template = struct('index',0, 'id','', 'description','', 'rootdir','', ...
                'status',NaN, 'enabled',false, 'disabledReason','', ...
                'requiresOverwrite',false, 'ix',0, 'jx',0);
            cards = repmat(template, 1, max(0, double(list.count)));
            for i = 1:list.count
                [ix, jx] = NMPreprocessRunnerUI.analysisGridDims(NM, i);
                enabled = false;
                reason = 'Preprocessing runner feasibility has not been evaluated.';
                requiresOverwrite = false;
                if deferArtifactScan || ~list.rootExists(i)
                    if ~defs.import_finished
                        reason = 'Finalize training data import before running preprocessing.';
                    elseif defs.analyses_locked
                        reason = 'Application/OOCV mode is active. Discovery-stage preprocessing is locked.';
                    elseif ~list.rootExists(i)
                        reason = 'Analysis root path is stale or missing. Relink it before running.';
                    elseif ix < 1 || jx < 1
                        reason = 'Analysis has no valid CV2 TrainInd grid.';
                    else
                        enabled = true;
                        reason = 'Loading runtime feasibility and artifact availability.';
                    end
                else
                    rt = struct('ok',false,'message','Runtime state unavailable.','actions',struct());
                    if exist('NMRuntimeActionTools','class') == 8
                        try
                            rt = NMRuntimeActionTools.runtimeState(NM, struct('analysisIndex',i,'entryPoint','preprocess_runner','useArtifactCache',true));
                        catch ME % nm2-allow: NMUIErrorTools carries caught runtime-state diagnostic
                            rt = NMUIErrorTools.exceptionStruct(ME, 'preprocess_runner_runtime_state', 'Checking runtime readiness failed.', 2);
                            rt.actions = struct();
                        end
                    end
                    if isstruct(rt) && isfield(rt,'actions') && isstruct(rt.actions) && isfield(rt.actions,'preprocess')
                        enabled = logical(rt.actions.preprocess.enabled);
                        requiresOverwrite = logical(rt.actions.preprocess.requiresOverwrite);
                        if enabled
                            reason = char(string(rt.actions.preprocess.enabledReason));
                        else
                            reason = char(string(rt.actions.preprocess.disabledReason));
                        end
                    elseif ~defs.import_finished
                        reason = 'Finalize training data import before running preprocessing.';
                    end
                end
                card = template;
                card.index = i;
                card.id = list.ids{i};
                card.description = list.descriptions{i};
                card.rootdir = list.rootdirs{i};
                card.status = list.status(i);
                card.enabled = enabled;
                card.disabledReason = reason;
                card.requiresOverwrite = requiresOverwrite;
                card.ix = ix;
                card.jx = jx;
                cards(i) = card;
            end
        end

        function selected = defaultSelection(analyses)
            selected = [];
            for i = 1:numel(analyses)
                a = analyses(i);
                if isstruct(a) && isfield(a,'enabled') && logical(a.enabled)
                    selected = double(a.index);
                    return;
                end
            end
        end

        function grid = gridStateForSelection(NM, selected)
            selected = NMPreprocessRunnerUI.normalizeIndexVector(selected);
            grid = struct('visible',false, 'hiddenByLegacyRule',false, 'proceedAllowed',false, ...
                'reason','Select at least one executable analysis.', 'ix',0, 'jx',0, ...
                'state',struct(), 'GridAct',false(0,0));
            if isempty(selected), return; end
            dims = zeros(numel(selected),2);
            for i = 1:numel(selected)
                [dims(i,1), dims(i,2)] = NMPreprocessRunnerUI.analysisGridDims(NM, selected(i));
            end
            if any(dims(:) < 1) || any(~isfinite(dims(:)))
                grid.reason = 'At least one selected analysis has no valid CV2 TrainInd grid.';
                return;
            end
            sameGrid = all(dims(:,1) == dims(1,1)) && all(dims(:,2) == dims(1,2));
            if ~sameGrid
                grid.visible = false;
                grid.hiddenByLegacyRule = true;
                grid.proceedAllowed = true;
                grid.reason = 'Selected analyses have different CV2 grid sizes; each analysis will run all CV2 cells.';
                return;
            end
            G = true(dims(1,1), dims(1,2));
            grid.visible = true;
            grid.proceedAllowed = true;
            grid.reason = 'Select the CV2 permutation/fold cells to preprocess.';
            grid.ix = dims(1,1);
            grid.jx = dims(1,2);
            grid.GridAct = G;
            grid.state = NMRuntimeGridTools.state(grid.ix, grid.jx, G, struct('requireAny',true));
        end

        function opts = defaultOptions()
            opts = struct('overwrite',false, 'useExistingParameters',true, ...
                'writeParameters',false);
        end

        function msg = statusMessage(defs, workflow, analyses)
            if ~defs.import_finished
                msg = 'Training data import is not finalized. Finalize DataIO before running preprocessing.';
            elseif defs.analyses_locked
                msg = 'Application/OOCV mode is active. Discovery-stage preprocessing is locked.';
            elseif isstruct(workflow) && isfield(workflow,'setup_ok') && ~logical(workflow.setup_ok)
                msg = 'Complete the NM parameter workspace before running preprocessing.';
            elseif isempty(analyses)
                msg = 'Create at least one analysis snapshot before running preprocessing.';
            else
                msg = 'Select one or more analyses, select CV2 partitions where available, then run preprocessing.';
            end
        end

        function [NM, out] = runPreprocessing(NM, plan)
            indices = NMPreprocessRunnerUI.normalizeIndexVector(plan.analysisIndices);
            if isempty(indices)
                error('NMPreprocessRunnerUI:noAnalysisSelected', 'Select at least one analysis before running preprocessing.');
            end
            if isfield(plan,'options') && isstruct(plan.options)
                opts = plan.options;
            else
                opts = struct();
            end
            % The standalone preprocessing runner always writes PreprocData.
            % Suppressing this would discard the runner's primary artifact and
            % break downstream Train-ML-from-PreprocData workflows.
            if ~isfield(opts,'overwrite'), opts.overwrite = false; end
            if ~isfield(opts,'useExistingParameters'), opts.useExistingParameters = true; end
            if ~isfield(opts,'writeParameters'), opts.writeParameters = false; end
            gridVisible = isfield(plan,'gridVisible') && logical(plan.gridVisible);
            gridHiddenByLegacyRule = isfield(plan,'gridHiddenByLegacyRule') && logical(plan.gridHiddenByLegacyRule);
            if ~gridVisible && ~gridHiddenByLegacyRule
                gridInfo = NMPreprocessRunnerUI.gridStateForSelection(NM, indices);
                gridVisible = logical(gridInfo.visible);
                gridHiddenByLegacyRule = logical(gridInfo.hiddenByLegacyRule);
            end
            runtimeUI = [];
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                runtimeUI = plan.runtimeUI;
                global UI
                UI = runtimeUI;
                NMRuntimeProgressTools.writeGenericProgressSafe('Preprocessing progress', ...
                    sprintf('Preparing preprocessing for %d analysis/analyses.', numel(indices)), ...
                    0, 'Initialization', true);
            end
            results = cell(1,numel(indices));
            try
                for k = 1:numel(indices)
                    idx = indices(k);
                    spec = NMPreprocessRunnerUI.buildPreprocessSpec(NM, plan, opts, idx, gridVisible);
                    if ~isempty(runtimeUI)
                        spec.UI = runtimeUI;
                        if ischar(spec.gridAction) || isstring(spec.gridAction)
                            [ix, jx] = NMPreprocessRunnerUI.analysisGridDims(NM, idx);
                            nCells = ix * jx;
                        else
                            nCells = nnz(logical(spec.gridAction));
                        end
                        beforePct = 100 * (k - 1) / max(1, numel(indices));
                        NMRuntimeProgressTools.writeGenericProgressSafe('Preprocessing progress', ...
                            sprintf('Running analysis %d of %d across %d selected CV2 partition(s).', ...
                            k, numel(indices), nCells), beforePct, ...
                            sprintf('Analysis %d', idx), true);
                    end
                    [NM, runOut] = NMRunTools.preprocessAnalysis(NM, idx, spec);
                    results{k} = runOut;
                    if ~isempty(runtimeUI)
                        afterPct = 100 * k / max(1, numel(indices));
                        NMRuntimeProgressTools.writeGenericProgressSafe('Preprocessing progress', ...
                            sprintf('Completed analysis %d of %d.', k, numel(indices)), ...
                            afterPct, sprintf('Analysis %d', idx), false);
                    end
                end
                if ~isempty(runtimeUI)
                    NMRuntimeProgressTools.finish(runtimeUI, 'Preprocessing completed.', ...
                        'NM Preprocessing Progress Viewer');
                end
            catch ME
                if ~isempty(runtimeUI)
                    NMRuntimeProgressTools.fail(runtimeUI, 'NMPreprocessRunnerUI.runPreprocessing', ME);
                end
                rethrow(ME);
            end
            out = struct('ok',true, 'message',sprintf('Preprocessing completed for %d analysis/analyses.', numel(indices)), ...
                'analysisIndices',indices, 'results',{results});
        end

        function spec = buildPreprocessSpec(NM, plan, opts, idx, gridVisible)
            % Single source of truth for the preprocessing spec. Both the live
            % runner (runPreprocessing) and the generated runtime script derive
            % their spec here so they can never drift apart.
            spec = struct();
            spec.overwrite = logical(opts.overwrite);
            spec.savePreproc = true;
            spec.useExistingParameters = logical(opts.useExistingParameters);
            spec.writeParameters = logical(opts.writeParameters) && ~logical(opts.useExistingParameters);
            spec.devMode = false;
            if gridVisible
                spec.hideGrid = false;
                spec.gridAction = NMPreprocessRunnerUI.requestGridAct(plan, NM, idx);
            else
                spec.hideGrid = true;
                spec.gridAction = 'all';
            end
        end

        function out = generateRuntimeScript(NM, plan)
            % Generate a standalone MATLAB runtime script per selected analysis,
            % written into that analysis's root directory. Each script rebuilds
            % the exact spec the runner would use and calls the public API
            % entry point NMRunTools.preprocessAnalysis. The script assumes the
            % corresponding NM structure is loaded in the workspace as `NM`.
            indices = NMPreprocessRunnerUI.normalizeIndexVector(plan.analysisIndices);
            if isempty(indices)
                error('NMPreprocessRunnerUI:noAnalysisSelected', 'Select at least one analysis before generating a runtime script.');
            end
            if isfield(plan,'options') && isstruct(plan.options)
                opts = plan.options;
            else
                opts = struct();
            end
            if ~isfield(opts,'overwrite'), opts.overwrite = false; end
            if ~isfield(opts,'useExistingParameters'), opts.useExistingParameters = true; end
            if ~isfield(opts,'writeParameters'), opts.writeParameters = false; end
            gridVisible = isfield(plan,'gridVisible') && logical(plan.gridVisible);
            gridHiddenByLegacyRule = isfield(plan,'gridHiddenByLegacyRule') && logical(plan.gridHiddenByLegacyRule);
            if ~gridVisible && ~gridHiddenByLegacyRule
                gridInfo = NMPreprocessRunnerUI.gridStateForSelection(NM, indices);
                gridVisible = logical(gridInfo.visible);
                gridHiddenByLegacyRule = logical(gridInfo.hiddenByLegacyRule);
            end

            list = NMAnalysisManagerTools.listAnalyses(NM);
            scripts = {};
            for k = 1:numel(indices)
                idx = indices(k);
                spec = NMPreprocessRunnerUI.buildPreprocessSpec(NM, plan, opts, idx, gridVisible);
                rootdir = '';
                if isstruct(list) && isfield(list,'rootdirs') && iscell(list.rootdirs) && idx <= numel(list.rootdirs)
                    rootdir = char(string(list.rootdirs{idx}));
                end
                analysisId = '';
                if isstruct(list) && isfield(list,'ids') && iscell(list.ids) && idx <= numel(list.ids)
                    analysisId = char(string(list.ids{idx}));
                end
                if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                    error('NMPreprocessRunnerUI:noAnalysisRoot', ...
                        'Analysis %d has no accessible root directory; cannot write a runtime script.', idx);
                end
                fname = sprintf('NM_preprocess_analysis_%d.m', idx);
                fpath = fullfile(rootdir, fname);
                txt = NMPreprocessRunnerUI.scriptTextForSpec(idx, analysisId, spec);
                NMPreprocessRunnerUI.writeTextFile(fpath, txt);
                scripts{end+1} = struct('analysisIndex',idx, 'id',analysisId, 'path',fpath); %#ok<AGROW>
            end
            out = struct('ok',true, ...
                'message',sprintf('Generated %d runtime script(s).', numel(scripts)), ...
                'scripts',{scripts});
        end

        function txt = scriptTextForSpec(idx, analysisId, spec)
            nl = newline;
            gridLiteral = NMPreprocessRunnerUI.gridActionLiteral(spec.gridAction);
            gridComment = NMPreprocessRunnerUI.gridActionComment(spec.gridAction);
            L = { ...
sprintf('%% NM_preprocess_analysis_%d.m', idx)
'% ========================================================================='
'% NeuroMiner runtime script  --  generated by the preprocessing runner'
'% ========================================================================='
sprintf('%% Analysis %d%s', idx, NMPreprocessRunnerUI.idComment(analysisId))
'%'
'% WHAT THIS SCRIPT DOES'
'%   It reproduces, from the MATLAB command line, the preprocessing run you'
'%   configured in the browser UI. Instead of clicking "Run preprocessing",'
'%   you can run (or schedule, or version-control) this script. It performs'
'%   exactly the same work, because it calls the same public NeuroMiner API'
'%   entry point the UI uses: NMRunTools.preprocessAnalysis.'
'%'
'% PREREQUISITE -- the NM structure'
'%   NeuroMiner keeps your project in a single struct conventionally named'
'%   `NM` (analyses, data, CV structure, parameters). This script expects'
'%   that struct to already be loaded in your workspace as `NM`. Typical'
'%   ways to get it there:'
'%     * It is already in the base workspace from your current NM session, or'
'%     * load a saved project:   S = load(''my_project.mat'');  NM = S.NM;'
'%   The script does not load NM itself, so it stays valid regardless of'
'%   where your project file lives.'
'%'
'% THE spec STRUCT -- one field at a time'
'%   spec controls how preprocessing runs. Every field below mirrors the'
'%   documented inputs of NMRunTools.preprocessAnalysis; the values were'
'%   filled in from your UI selections.'
'% -------------------------------------------------------------------------'
''
'if exist(''NM'',''var'') ~= 1'
'    error([''This script needs your NeuroMiner project in the workspace. '' ...'
'        ''Load it first, e.g.  S = load(''''my_project.mat'''');  NM = S.NM;'']);'
'end'
''
'spec = struct();'
''
'% overwrite: recompute and overwrite existing PreprocData / parameter files.'
'%   false = keep existing outputs where present (faster, resumable);'
'%   true  = force regeneration even if outputs already exist.'
sprintf('spec.overwrite             = %s;', NMPreprocessRunnerUI.boolLiteral(spec.overwrite))
''
'% savePreproc: write the PreprocData artifacts to disk. The standalone'
'%   preprocessing runner always keeps this true -- PreprocData is its'
'%   primary output and downstream Train-ML-from-PreprocData workflows need it.'
'spec.savePreproc           = true;'
''
'% useExistingParameters: when matching preprocessing parameter files already'
'%   exist, reuse them instead of estimating new ones.'
'%   true  = reuse when available (consistent, faster);'
'%   false = always estimate parameters fresh.'
sprintf('spec.useExistingParameters = %s;', NMPreprocessRunnerUI.boolLiteral(spec.useExistingParameters))
''
'% writeParameters: write the computed preprocessing parameter files to disk.'
'%   Only meaningful when parameters are estimated (i.e. not reused), so the'
'%   UI gates this on useExistingParameters being false. Can use notable disk.'
sprintf('spec.writeParameters       = %s;', NMPreprocessRunnerUI.boolLiteral(spec.writeParameters))
''
'% devMode: scalar logical replacement for the legacy global DEV flag.'
'%   Leave false for normal runs.'
'spec.devMode               = false;'
''
'% hideGrid: suppress interactive CV2 grid selection where supported.'
'%   true  = process the grid non-interactively (all cells, or the matrix'
'%           given in gridAction below);'
'%   false = an explicit GridAct matrix is supplied.'
sprintf('spec.hideGrid              = %s;', NMPreprocessRunnerUI.boolLiteral(spec.hideGrid))
''
'% gridAction: which CV2 permutation/fold cells to preprocess.'
sprintf('%%   %s', gridComment)
'%   ''all''             = every CV2 cell of the analysis''s grid.'
'%   logical([...])    = an explicit ix-by-jx mask; rows are permutations,'
'%                       columns are folds, 1 = process this cell.'
sprintf('spec.gridAction            = %s;', gridLiteral)
''
'% -------------------------------------------------------------------------'
'% RUN IT'
'%   preprocessAnalysis returns the updated NM (with preprocessing results'
'%   recorded) and a runOut struct describing what happened. It internally'
'%   asserts that NM is in training-configuration mode and that the analysis'
'%   is ready, so you get the same safety checks as the UI.'
'%'
'%   runOut fields include: ok, message, analysisIndex, GridAct (the grid'
'%   actually processed), and artifactState (what now exists on disk).'
'% -------------------------------------------------------------------------'
sprintf('[NM, runOut] = NMRunTools.preprocessAnalysis(NM, %d, spec);', idx)
'disp(runOut.message);'
''
'% Tip: after this completes, `NM` in your workspace holds the updated project.'
'% Save it if you want to persist the new state:  save(''my_project.mat'', ''NM'');'
''};
            txt = strjoin(L(:)', nl);
        end

        function s = gridActionComment(gridAction)
            if ischar(gridAction) || isstring(gridAction)
                s = 'Your selection: run all CV2 cells of this analysis.';
            else
                G = logical(gridAction);
                n = sum(G(:));
                [ix, jx] = size(G);
                s = sprintf('Your selection: %d of %d CV2 cells (%dx%d grid).', n, ix*jx, ix, jx);
            end
        end

        function s = boolLiteral(v)
            if logical(v), s = 'true'; else, s = 'false'; end
        end

        function s = idComment(analysisId)
            if isempty(analysisId), s = ''; else, s = sprintf(': %s', analysisId); end
        end

        function s = gridActionLiteral(gridAction)
            % 'all' renders as a string literal; an explicit GridAct logical
            % matrix renders as a MATLAB logical-matrix literal.
            if ischar(gridAction) || isstring(gridAction)
                s = sprintf('''%s''', char(string(gridAction)));
                return;
            end
            G = logical(gridAction);
            [ix, jx] = size(G);
            if ix == 0 || jx == 0
                s = '''all''';
                return;
            end
            rows = cell(1, ix);
            for i = 1:ix
                vals = arrayfun(@(b) sprintf('%d', b), G(i,:), 'UniformOutput', false);
                rows{i} = strjoin(vals, ' ');
            end
            s = ['logical([' strjoin(rows, '; ') '])'];
        end

        function G = requestGridAct(plan, NM, idx)
            if isfield(plan,'GridAct') && ~isempty(plan.GridAct)
                raw = plan.GridAct;
            else
                [ix,jx] = NMPreprocessRunnerUI.analysisGridDims(NM, idx);
                raw = true(ix,jx);
            end
            [ix,jx] = NMPreprocessRunnerUI.analysisGridDims(NM, idx);
            if iscell(raw)
                G = false(numel(raw), numel(raw{1}));
                for i = 1:numel(raw)
                    row = raw{i};
                    if iscell(row), row = cell2mat(row); end
                    G(i,1:numel(row)) = logical(row);
                end
            else
                G = logical(raw);
            end
            G = NMRuntimeGridTools.normalize(ix, jx, G);
            [ok,msg] = NMRuntimeGridTools.validate(G, true);
            if ~ok
                error('NMPreprocessRunnerUI:badGridAct', '%s', msg);
            end
        end

        function plan = attachRuntimeProgressContext(plan, req, tmpDir)
            taskId = '';
            if isstruct(req) && isfield(req,'progressTaskId') && ~isempty(req.progressTaskId)
                taskId = char(string(req.progressTaskId));
            elseif isstruct(req) && isfield(req,'extra') && isstruct(req.extra) && ...
                    isfield(req.extra,'progressTaskId') && ~isempty(req.extra.progressTaskId)
                taskId = char(string(req.extra.progressTaskId));
            end
            if isempty(taskId), return; end
            plan.runtimeUI = NMRuntimeProgressTools.browserRuntimeContext(tmpDir, taskId, ...
                struct('source','preprocess_runner', 'chartEnabled',true, ...
                'suppressNativeViewer',true, 'progressTitle','NM Preprocessing Progress Viewer', ...
                'progressLowerTitle','Preprocessing progress'));
        end

        function plan = requestPlan(req)
            plan = struct('analysisIndices',[], 'options',struct(), 'GridAct',[], ...
                'gridVisible',false, 'gridHiddenByLegacyRule',false);
            if isstruct(req) && isfield(req,'plan') && isstruct(req.plan)
                p = req.plan;
            elseif isstruct(req) && isfield(req,'extra') && isstruct(req.extra) && isfield(req.extra,'plan') && isstruct(req.extra.plan)
                p = req.extra.plan;
            else
                p = struct();
            end
            if isfield(p,'analysisIndices'), plan.analysisIndices = p.analysisIndices; end
            if isfield(p,'analysisIndex'), plan.analysisIndices = p.analysisIndex; end
            if isfield(p,'options') && isstruct(p.options), plan.options = p.options; end
            if isfield(p,'GridAct'), plan.GridAct = p.GridAct; end
            if isfield(p,'gridVisible'), plan.gridVisible = logical(p.gridVisible); end
            if isfield(p,'gridHiddenByLegacyRule'), plan.gridHiddenByLegacyRule = logical(p.gridHiddenByLegacyRule); end
        end

        function indices = normalizeIndexVector(x)
            if isempty(x), indices = []; return; end
            if iscell(x), x = cell2mat(x); end
            indices = unique(round(double(x(:)')),'stable');
            indices(~isfinite(indices) | indices < 1) = [];
        end

        function [ix, jx] = analysisGridDims(NM, idx)
            ix = 0; jx = 0;
            try
                if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis) && idx >= 1 && idx <= numel(NM.analysis)
                    A = NM.analysis{idx};
                    if isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'cv') && ...
                            isstruct(A.params.cv) && isfield(A.params.cv,'TrainInd') && ~isempty(A.params.cv.TrainInd)
                        [ix,jx] = size(A.params.cv.TrainInd);
                    end
                end
            catch
                ix = 0; jx = 0;
            end
        end

        function op = requestOperation(req)
            op = '';
            if isstruct(req) && isfield(req,'operation') && ~isempty(req.operation)
                op = char(string(req.operation));
            elseif isstruct(req) && isfield(req,'action') && ~isempty(req.action)
                op = char(string(req.action));
            end
        end

    end
end

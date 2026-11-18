classdef NMMLOptimizerRunnerUI
% NMMLOptimizerRunnerUI
% -------------------------------------------------------------------------
% Dedicated browser page for the legacy ML optimizer / training runtime.
%
% The page is an app/workbench child entry point around NMRunTools.  It
% mirrors the relevant runtime dynamics of nk_MLOptimizerPrep while reusing
% shared runner components: NMAnalysisCardSelector, NMRuntimeGridPicker and
% NMModal.  JavaScript never calls nk_MLOptimizerPrep directly.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(NM, outDir, ctx)
            % export  Create the browser ML training runner session.
            %
            % Writes the runner HTML, initial artifact/grid state and shared assets, then stores the
            % session NM for service requests. This prepares the ML training workflow page but leaves
            % actual run/script execution to the MATLAB service handler.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_ml_train_runner_ui'); end
            if nargin < 3, ctx = struct(); end

            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_ml_train_runner_ui');
            NMDataIOUI.saveSessionNM(NM, dirs.tmpDir);

            if NMUISessionTools.fastChildOpen(ctx)
                state = NMMLOptimizerRunnerUI.bootstrapState(ctx);
            else
                state = NMMLOptimizerRunnerUI.stateFromNM(NM, ctx);
            end
            stateJson = NMConfigTools.writeJsonAliases({ ...
                fullfile(dirs.tmpDir,'ml_train_runner_state.json'), ...
                fullfile(dirs.tmpDir,'current_config.json'), ...
                fullfile(dirs.tmpDir,'param.json')}, state, 'ML training runner state');

            htmlPath = fullfile(dirs.webDir, 'nm_ml_train_runner.html');
            NMMLOptimizerRunnerUI.writeTextFile(htmlPath, NMMLOptimizerRunnerUI.htmlTextFromJson(stateJson));
            NMMLOptimizerRunnerUI.copyAssets(dirs.webDir);
            NMPreprocUI.writeBridge(fullfile(dirs.pyDir,'nm_bridge_server.py'));

            paths = struct('root', dirs.root, 'webRoot', dirs.webRoot, 'webDir', dirs.webDir, ...
                'tmpDir', dirs.tmpDir, 'html', htmlPath, 'mlTrainRunnerHtml', htmlPath, ...
                'entryHtml', 'nm_ml_train_runner.html', 'entryHtmlPath', htmlPath, ...
                'state', fullfile(dirs.tmpDir,'ml_train_runner_state.json'));
        end

        function NM = importUpdated(NM, pathsOrWebDir, ctx)
            % importUpdated  Return the session NM after the ML training runner closes.
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
            % stateFromNM  Build artifact and option state for the ML training runner.
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
            analyses = NMMLOptimizerRunnerUI.analysisCards(NM, defs, deferArtifactScan);
            selected = NMMLOptimizerRunnerUI.defaultSelection(analyses);
            grid = NMMLOptimizerRunnerUI.gridStateForSelection(NM, selected);

            state = struct();
            state.page = 'ml_train_runner';
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
            state.options = NMMLOptimizerRunnerUI.defaultOptions();
            state.operationModes = NMMLOptimizerRunnerUI.operationModes();
            state.canRun = ~deferArtifactScan && ~isempty(selected) && logical(grid.proceedAllowed);
            state.loading = false;
            state.analysesLoading = false;
            state.artifactsLoading = deferArtifactScan;
            if deferArtifactScan
                state.statusMessage = 'Loading artifact availability and ML-runtime feasibility from MATLAB.';
            else
                state.statusMessage = NMMLOptimizerRunnerUI.statusMessage(defs, workflow, analyses);
            end
            state.debugOptionsVisible = NMMLOptimizerRunnerUI.debugOptionsVisible();
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'ml_train_runner');
        end

        function state = bootstrapState(ctx)
            % bootstrapState  Build a minimal ML training runner state for fast navigation.
            %
            % Uses app context to render the page shell before the full artifact resolver runs. The
            % complete state is requested immediately through the MATLAB bridge.

            if nargin < 1, ctx = struct(); end
            defs = struct('import_finished',false,'analyses_locked',false);
            workflow = struct('ok',true,'message','ML-training runner is loading the current NeuroMiner state.', ...
                'import_finished',false,'setup_ok',false,'analyses_locked',false, ...
                'analyses_exist',false,'analyses_ready',false,'completed_analyses',false(1,0), ...
                'status_analyses',NaN(1,0));
            grid = struct('visible',false, 'hiddenByLegacyRule',false, 'proceedAllowed',false, ...
                'reason','Loading CV2 partition state from MATLAB.', 'ix',0, 'jx',0, ...
                'state',struct(), 'GridAct',false(0,0));
            analysisTemplate = struct('index',0,'id','','description','','rootdir','', ...
                'status',NaN,'enabled',false,'disabledReason','','enabledReason','', ...
                'requiresOverwrite',false,'ix',0,'jx',0,'recommendedOperationMode','scratch', ...
                'preprocAvailable',false,'cvDatamatAvailable',false,'cvResultsAvailable',false, ...
                'isStackingAnalysis',false, ...
                'stackingScratchAvailable',true,'stackingScratchReason','', ...
                'artifactSummary',NMMLOptimizerRunnerUI.emptyArtifactSummary());
            state = struct();
            state.page = 'ml_train_runner';
            state.defs = defs;
            state.workflowStatus = workflow;
            state.analyses = repmat(analysisTemplate, 1, 0);
            state.analysisList = struct();
            state.selectedAnalysisIndices = [];
            state.grid = grid;
            state.options = NMMLOptimizerRunnerUI.defaultOptions();
            state.operationModes = NMMLOptimizerRunnerUI.operationModes();
            state.canRun = false;
            state.loading = true;
            state.analysesLoading = true;
            state.artifactsLoading = true;
            state.statusMessage = 'Loading analyses...';
            state.debugOptionsVisible = NMMLOptimizerRunnerUI.debugOptionsVisible();
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'ml_train_runner');
        end

        function [handled, out] = handleMatlabService(NM, req, tmpDir, ctx)
            % handleMatlabService  Dispatch ML training runner service requests.
            %
            % Handles refresh, artifact resolution, run and script-generation operations by loading
            % session NM and delegating to NMRunTools/NMTrainConfigOrchestrator. Responses include
            % updated runner state and explicit diagnostics for the browser message strip.

            handled = false;
            out = struct();
            if nargin < 4, ctx = struct(); end
            if nargin < 3, tmpDir = ''; end
            op = NMMLOptimizerRunnerUI.requestOperation(req);
            if isempty(op), return; end
            switch lower(op)
                case {'ml_train_runner_refresh','ml_train_runner_state'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    if ~ok, sessionNM = NM; end
                    state = NMMLOptimizerRunnerUI.stateFromNM(sessionNM, ctx);
                    out = struct('ok',true,'message','ML training runner state refreshed.', 'state',state, 'operation',op);
                case {'ml_train_runner_refresh_light','ml_train_runner_state_light'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    if ~ok, sessionNM = NM; end
                    state = NMMLOptimizerRunnerUI.stateFromNM(sessionNM, ctx, struct('deferArtifactScan',true));
                    out = struct('ok',true,'message','Analyses loaded. Artifact availability is still being resolved.', 'state',state, 'operation',op);
                case {'ml_train_runner_run'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    if ~ok, sessionNM = NM; end
                    try
                        plan = NMMLOptimizerRunnerUI.requestPlan(req);
                        plan = NMMLOptimizerRunnerUI.attachRuntimeProgressContext(plan, req, tmpDir);
                        [sessionNM, runOut] = NMMLOptimizerRunnerUI.runTraining(sessionNM, plan);
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMMLOptimizerRunnerUI.stateFromNM(sessionNM, ctx);
                        out = struct('ok',true, 'message',runOut.message, 'operation',op, ...
                            'state',state, 'result',runOut);
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Running ML training failed.', 2);
                    end
                case {'ml_train_runner_generate_script'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    if ~ok, sessionNM = NM; end
                    try
                        plan = NMMLOptimizerRunnerUI.requestPlan(req);
                        genOut = NMMLOptimizerRunnerUI.generateRuntimeScript(sessionNM, plan);
                        out = struct('ok',true, 'message',genOut.message, 'operation',op, ...
                            'scripts',{genOut.scripts});
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Generating the ML-training runtime script failed.', 2);
                    end
                case {'ml_train_runner_pick_artifact'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    if ~ok, sessionNM = NM; end
                    try
                        out = NMMLOptimizerRunnerUI.pickArtifactFile(sessionNM, req);
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Selecting an artifact file failed.', 2);
                    end
                otherwise
                    handled = true;
                    out = struct('ok',false,'message',sprintf('Unsupported ML-training runner operation: %s', op), ...
                        'error',sprintf('Unsupported ML-training runner operation: %s', op));
            end
        end

        function txt = htmlTextFromJson(stateJson)
            % htmlTextFromJson  Build the ML training runner HTML shell.
            %
            % Creates the static page frame, embeds the state reference and loads shared
            % runner/grid-picker/navigation assets. All scientific/runtime decisions remain in
            % MATLAB-side service calls.

            jsState = NMPreprocUI.jsonTextForScript(stateJson);
            assetTag = NMMLOptimizerRunnerUI.assetCacheTag();
            nl = newline;
            L = { ...
'<!doctype html>'
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
'<title>NeuroMiner ML training runner</title>'
['<link rel="stylesheet" href="NMTrainTemplateUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModuleNavigationRail.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisManagerUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMRuntimeGridPicker.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModal.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisCardSelector.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMManualArtifactFileList.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMMLOptimizerRunnerUI.css?v=' assetTag '">']
['<style>' NMUIMessageTools.css() '</style>']
'</head><body class="nmHasNavRail">'
'<header>'
'  <div><div class="crumb">Main interface / model discovery</div><div class="title">Train supervised models</div></div>'
'  <div class="headerActions"><button id="finish" class="primary" type="button">Finish / close</button></div>'
'</header>'
'<main class="wrap mlrWrap"><section class="panel mlrPanel">'
'  <div class="mlrPanelHead"><div><h1>Configure and run NeuroMiner ML training</h1></div></div>'
'  <div class="mlrLayout">'
'    <section class="card mlrConfigPanel">'
'      <div class="mlrSectionHeader"><h2>Runtime configuration</h2><span id="selectedSummary" class="muted"></span></div>'
'      <div id="artifactSummary" class="nmRuntimeArtifactSummary mlrArtifactSummary mlrArtifactSummaryTop"></div>'
'      <div class="field"><label class="nmRunnerSectionTitle" for="operationMode">Training input stage</label><select id="operationMode"><option value="auto">Auto: use best available artifact</option><option value="scratch">Compute from scratch</option><option value="preproc">Use existing PreprocData</option><option value="datamat">Use existing CVdatamat</option><option value="results">Use existing CVresults</option></select><div id="modeHelp" class="help"></div></div>'
'      <div id="manualArtifactField" class="field"><label class="nmRunnerSectionTitle" for="manualArtifactMode">Manual artifact override</label><div class="mlrArtifactOverride"><select id="manualArtifactMode"><option value="none">None — use automatic resolver</option><option value="preproc">Select PreprocMaster or CV2 PreprocData</option><option value="datamat">Select CVdataMaster or CV2 CVdatamats</option><option value="results">Select CVresultsMaster or CVresults</option></select><button id="pickArtifactFile" type="button">Pick file(s)…</button></div><div id="manualArtifactSummary" class="help">No manual artifact file selected.</div></div>'
'      <div class="field"><label class="nmRunnerSectionTitle">ML training artifact handling</label><label><input id="overwriteExisting" type="checkbox"> Overwrite existing training outputs</label></div>'
'      <div class="field"><label><input id="updateExisting" type="checkbox" checked> Refresh derived summaries when using existing artifacts</label></div>'
'      <div id="debugOptions" class="field hidden"><label><input id="debugAll" type="checkbox"> Save all trained models and training data</label><label><input id="debugOpt" type="checkbox"> Save chosen optimum results with models</label><div class="help">Developer/debugging options are shown only in non-deployed DEV mode.</div></div>'
'      <div id="gridSection" class="field">'
'        <label class="nmRunnerSectionTitle">CV2 partitions</label>'
'        <div id="gridReason" class="help"></div>'
'        <div id="gridPicker"></div>'
'      </div>'
'      <div id="gridHiddenNote" class="field hidden"><label class="nmRunnerSectionTitle">CV2 partitions</label><div class="help">The CV2 grid picker is hidden by the legacy runtime rule. Each selected analysis will run all applicable CV2 partitions.</div></div>'
'      <div class="actions mlrRunRow"><button id="runMLTraining" class="primary nmActionButton" type="button">Run ML training</button><button id="generateRuntimeScript" class="nmActionButton" type="button">Generate runtime script</button></div>'
'      <div id="runHint" class="help"></div>'
'      <div id="mlRuntimeProgressHost" class="hidden"></div>'
'    </section>'
'    <section class="card mlrAnalysisPanel">'
'      <div class="mlrSectionHeader"><h2>Analyses</h2><span class="muted">Select one or more analyses</span></div>'
'      <div id="analysisList" class="mlrAnalysisList"></div>'
'    </section>'
'  </div>'
'</section></main>'
['<script>window.NM_ML_TRAIN_RUNNER_STATE = ' jsState ';</script>']
['<script>' NMUIMessageTools.script() '</script>']
['<script>window.NM_MODULE_NAV_CONTEXT = {currentModule:"mltrain"};</script>']
['<script src="NMRuntimeGridPicker.js?v=' assetTag '"></script>']
['<script src="NMModal.js?v=' assetTag '"></script>']
['<script src="NMAnalysisCardSelector.js?v=' assetTag '"></script>']
['<script src="NMManualArtifactFileList.js?v=' assetTag '"></script>']
['<script src="NMModuleIconSet.js?v=' assetTag '"></script>']
['<script src="NMModuleNavigationRail.js?v=' assetTag '"></script>']
['<script src="NMRuntimeJobClient.js?v=' assetTag '"></script>']
['<script src="NMRunnerStateManager.js?v=' assetTag '"></script>']
['<script src="NMMLOptimizerRunnerUI_main.js?v=' assetTag '"></script>']
'</body></html>'};
            txt = strjoin(L, nl);
        end

        function copyAssets(webDir)
            % copyAssets  Copy static assets for the ML training runner page.
            %
            % Copies runner JavaScript/CSS plus shared navigation, icon, picker and message-strip assets
            % into the exported web directory. It keeps page export self-contained for the bridge.

            src = fileparts(which('NMMLOptimizerRunnerUI.m'));
            files = {'NMMLOptimizerRunnerUI.css','NMRunnerStateManager.js','NMMLOptimizerRunnerUI_main.js', ...
                'NMRuntimeGridPicker.js','NMRuntimeGridPicker.css','NMModal.js','NMModal.css', ...
                'NMAnalysisCardSelector.js','NMAnalysisCardSelector.css', ...
                'NMManualArtifactFileList.js','NMManualArtifactFileList.css', ...
                'NMTrainTemplateUI.css','NMModuleIconSet.js','NMModuleNavigationRail.js','NMModuleNavigationRail.css','NMRuntimeProgressViewer.js','NMRuntimeProgressViewer.css','NMRuntimeJobClient.js','NMAnalysisManagerUI.css'};
            for i = 1:numel(files)
                s = fullfile(src, files{i});
                if exist(s,'file'), copyfile(s, fullfile(webDir, files{i}), 'f'); end
            end
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the ML-training runner text-writer entry point.
            %
            %   NMMLOptimizerRunnerUI.writeTextFile(path,txt) delegates generated HTML or auxiliary text
            %   output to NMSerializationTools while retaining the ML-training runner error identifier.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMMLOptimizerRunnerUI:writeFailed', 'Could not write %s', 'fwrite-input-char');
        end
    end

    methods (Static, Access = private)
        function opts = defaultOptions()
            opts = struct('operationMode','auto', 'manualArtifactMode','none', 'manualFiles',struct(), ...
                'overwrite',false, 'update',true, 'debugall',false, 'debugopt',false);
        end

        function modes = operationModes()
            modes = struct('key',{'auto','scratch','preproc','datamat','results'}, ...
                'label',{'Auto','Compute from scratch','Use PreprocData','Use CVdatamat','Use CVresults'});
        end

        function tf = debugOptionsVisible()
            tf = false;
            try
                global DEV
                tf = ~isdeployed && ~isempty(DEV) && logical(DEV);
            catch
                tf = false;
            end
        end

        function cards = analysisCards(NM, defs, deferArtifactScan)
            if nargin < 3 || isempty(deferArtifactScan), deferArtifactScan = false; end
            list = NMAnalysisManagerTools.listAnalyses(NM);
            template = struct('index',0, 'id','', 'description','', 'rootdir','', ...
                'status',NaN, 'enabled',false, 'disabledReason','', 'enabledReason','', ...
                'requiresOverwrite',false, 'ix',0, 'jx',0, 'recommendedOperationMode','scratch', ...
                'preprocAvailable',false, 'cvDatamatAvailable',false, 'cvResultsAvailable',false, ...
                'isStackingAnalysis',false, 'stackingScratchAvailable',true, 'stackingScratchReason','', ...
                'artifactSummary',NMMLOptimizerRunnerUI.emptyArtifactSummary());
            cards = repmat(template, 1, max(0, double(list.count)));
            for i = 1:list.count
                enabled = false;
                reason = 'ML-training runner feasibility has not been evaluated.';
                enabledReason = '';
                requiresOverwrite = false;
                recommended = 'scratch';
                preprocAvailable = false;
                cvDatamatAvailable = false;
                cvResultsAvailable = false;
                artifactSummary = NMMLOptimizerRunnerUI.emptyArtifactSummary();
                isStackingAnalysis = false;
                stackingScratchAvailable = true;
                stackingScratchReason = '';
                [ix, jx] = NMMLOptimizerRunnerUI.analysisGridDims(NM, i);
                if deferArtifactScan || ~list.rootExists(i)
                    isStackingAnalysis = NMMLOptimizerRunnerUI.isStackingAnalysis(NM, i);
                    if ~defs.import_finished
                        reason = 'Finalize training data import before running ML training.';
                    elseif defs.analyses_locked
                        reason = 'Application/OOCV mode is active. Discovery-stage ML training is locked.';
                    elseif ~list.rootExists(i)
                        reason = 'Analysis root path is stale or missing. Relink it before running.';
                    elseif ix < 1 || jx < 1
                        reason = 'Analysis has no valid CV2 TrainInd grid.';
                    else
                        enabled = true;
                        enabledReason = 'Loading artifact availability and ML-runtime feasibility.';
                        reason = enabledReason;
                    end
                else
                    rt = struct('ok',false,'message','Runtime state unavailable.','actions',struct(),'artifacts',struct());
                    if exist('NMRuntimeActionTools','class') == 8
                        try
                            rt = NMRuntimeActionTools.runtimeState(NM, struct('analysisIndex',i,'entryPoint','ml_train_runner','useArtifactCache',true));
                        catch ME % nm2-allow: NMUIErrorTools carries caught runtime-state diagnostic
                            rt = NMUIErrorTools.exceptionStruct(ME, 'ml_train_runner_runtime_state', 'Checking runtime readiness failed.', 2);
                            rt.actions = struct(); rt.artifacts = struct();
                        end
                    end
                    if isstruct(rt) && isfield(rt,'artifacts') && isstruct(rt.artifacts)
                    if isfield(rt.artifacts,'recommendedTrainEntryPoint') && ~isempty(rt.artifacts.recommendedTrainEntryPoint)
                        recommended = char(string(rt.artifacts.recommendedTrainEntryPoint));
                    end
                    preprocAvailable = NMMLOptimizerRunnerUI.artifactAvailable(rt.artifacts, 'preprocData');
                    cvDatamatAvailable = NMMLOptimizerRunnerUI.artifactAvailable(rt.artifacts, 'cvDatamat');
                    cvResultsAvailable = NMMLOptimizerRunnerUI.artifactAvailable(rt.artifacts, 'cvResults');
                    artifactSummary = NMMLOptimizerRunnerUI.artifactSummaryFromState(rt.artifacts);
                    if isfield(rt.artifacts,'stacking') && isstruct(rt.artifacts.stacking) && ...
                            isfield(rt.artifacts.stacking,'enabled') && ~isempty(rt.artifacts.stacking.enabled)
                        isStackingAnalysis = logical(rt.artifacts.stacking.enabled);
                        if isfield(rt.artifacts.stacking,'scratchAvailable') && ~isempty(rt.artifacts.stacking.scratchAvailable)
                            stackingScratchAvailable = logical(rt.artifacts.stacking.scratchAvailable);
                        else
                            stackingScratchAvailable = false;
                        end
                        if isfield(rt.artifacts.stacking,'message') && ~isempty(rt.artifacts.stacking.message)
                            stackingScratchReason = char(string(rt.artifacts.stacking.message));
                        end
                    end
                end
                if isstruct(rt) && isfield(rt,'actions') && isstruct(rt.actions) && isfield(rt.actions,'trainML')
                    enabled = logical(rt.actions.trainML.enabled);
                    requiresOverwrite = logical(rt.actions.trainML.requiresOverwrite);
                    if enabled
                        enabledReason = char(string(rt.actions.trainML.enabledReason));
                    else
                        reason = char(string(rt.actions.trainML.disabledReason));
                    end
                elseif ~defs.import_finished
                    reason = 'Finalize training data import before running ML training.';
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
                card.enabledReason = enabledReason;
                card.requiresOverwrite = requiresOverwrite;
                card.ix = ix;
                card.jx = jx;
                card.recommendedOperationMode = recommended;
                card.preprocAvailable = preprocAvailable;
                card.cvDatamatAvailable = cvDatamatAvailable;
                card.cvResultsAvailable = cvResultsAvailable;
                card.isStackingAnalysis = isStackingAnalysis;
                card.stackingScratchAvailable = stackingScratchAvailable;
                card.stackingScratchReason = stackingScratchReason;
                card.artifactSummary = artifactSummary;
                cards(i) = card;
            end
        end

        function summary = emptyArtifactSummary()
            itemTemplate = struct('available',false,'coverageText','not found','reason','', ...
                'masterFile','', 'firstFile','', 'files',{{}}, ...
                'nAvailable',0, 'nExpected',NaN, 'nLogicalAvailable',0, 'nLogicalExpected',NaN, ...
                'nPhysicalAvailable',0, 'nPhysicalExpected',NaN, 'cellAvailableMask',[]);
            summary = struct('recommended','scratch', 'rootdir','', 'algorithmRootdir','', ...
                'preprocRootdir','', 'cvDataRootdir','', 'cvResultsRootdir','', 'dataId','', ...
                'preprocData',itemTemplate, ...
                'cvDatamat',itemTemplate, ...
                'cvResults',itemTemplate, ...
                'stacking',struct('enabled',false,'scratchAvailable',true,'coverageText','','message','', ...
                'cellAvailableMask',[], 'childInputs',[]));
        end

        function summary = artifactSummaryFromState(artifacts)
            summary = NMMLOptimizerRunnerUI.emptyArtifactSummary();
            if ~isstruct(artifacts), return; end
            if isfield(artifacts,'recommendedTrainEntryPoint') && ~isempty(artifacts.recommendedTrainEntryPoint)
                summary.recommended = char(string(artifacts.recommendedTrainEntryPoint));
            end
            if isfield(artifacts,'rootdir') && ~isempty(artifacts.rootdir)
                summary.rootdir = char(string(artifacts.rootdir));
                summary.preprocRootdir = summary.rootdir;
            end
            if isfield(artifacts,'algorithmRootdir') && ~isempty(artifacts.algorithmRootdir)
                summary.algorithmRootdir = char(string(artifacts.algorithmRootdir));
                summary.cvDataRootdir = summary.algorithmRootdir;
                summary.cvResultsRootdir = summary.algorithmRootdir;
            end
            if isfield(artifacts,'dataId') && ~isempty(artifacts.dataId)
                summary.dataId = char(string(artifacts.dataId));
            end
            summary.preprocData = NMMLOptimizerRunnerUI.artifactSummaryItem(artifacts, 'preprocData');
            summary.cvDatamat = NMMLOptimizerRunnerUI.artifactSummaryItem(artifacts, 'cvDatamat');
            summary.cvResults = NMMLOptimizerRunnerUI.artifactSummaryItem(artifacts, 'cvResults');
            if isfield(artifacts,'stacking') && isstruct(artifacts.stacking)
                S = artifacts.stacking;
                if isfield(S,'enabled') && ~isempty(S.enabled), summary.stacking.enabled = logical(S.enabled); end
                if isfield(S,'scratchAvailable') && ~isempty(S.scratchAvailable), summary.stacking.scratchAvailable = logical(S.scratchAvailable); end
                if isfield(S,'coverageText') && ~isempty(S.coverageText), summary.stacking.coverageText = char(string(S.coverageText)); end
                if isfield(S,'message') && ~isempty(S.message), summary.stacking.message = char(string(S.message)); end
                if isfield(S,'cellAvailableMask') && ~isempty(S.cellAvailableMask), summary.stacking.cellAvailableMask = S.cellAvailableMask; end
                if isfield(S,'childInputs') && ~isempty(S.childInputs), summary.stacking.childInputs = S.childInputs; end
            end
        end

        function item = artifactSummaryItem(artifacts, field)
            item = struct('available',false,'coverageText','not found','reason','', ...
                'masterFile','', 'firstFile','', 'files',{{}}, ...
                'nAvailable',0, 'nExpected',NaN, 'nLogicalAvailable',0, 'nLogicalExpected',NaN, ...
                'nPhysicalAvailable',0, 'nPhysicalExpected',NaN, 'cellAvailableMask',[]);
            if ~isstruct(artifacts) || ~isfield(artifacts,field) || ~isstruct(artifacts.(field)), return; end
            A = artifacts.(field);
            if isfield(A,'available') && ~isempty(A.available), item.available = logical(A.available); end
            if isfield(A,'coverageText') && ~isempty(A.coverageText), item.coverageText = char(string(A.coverageText)); end
            if isfield(A,'reason') && ~isempty(A.reason), item.reason = char(string(A.reason)); end
            if isfield(A,'masterFile') && ~isempty(A.masterFile), item.masterFile = char(string(A.masterFile)); end
            numericFields = {'nAvailable','nExpected','nLogicalAvailable','nLogicalExpected','nPhysicalAvailable','nPhysicalExpected'};
            for nf = 1:numel(numericFields)
                f = numericFields{nf};
                if isfield(A,f) && ~isempty(A.(f))
                    item.(f) = double(A.(f));
                end
            end
            if isfield(A,'cellAvailableMask') && ~isempty(A.cellAvailableMask)
                item.cellAvailableMask = logical(A.cellAvailableMask);
            end
            if isfield(A,'files') && ~isempty(A.files)
                files = cellstr(A.files);
                files = files(~cellfun(@isempty, files));
                item.files = files;
                if ~isempty(files), item.firstFile = files{1}; end
            end
        end

        function tf = artifactAvailable(artifacts, field)
            tf = false;
            if isstruct(artifacts) && isfield(artifacts, field) && isstruct(artifacts.(field)) && ...
                    isfield(artifacts.(field),'available') && ~isempty(artifacts.(field).available)
                tf = logical(artifacts.(field).available);
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

        function msg = statusMessage(defs, workflow, analyses)
            if isstruct(workflow) && isfield(workflow,'ok') && ~logical(workflow.ok)
                msg = char(string(workflow.message));
            elseif ~logical(defs.import_finished)
                msg = 'Finalize training data import before running ML training.';
            elseif logical(defs.analyses_locked)
                msg = 'ML training is disabled in application/OOCV mode.';
            elseif isempty(analyses)
                msg = 'Create at least one analysis before running ML training.';
            else
                msg = 'Select analyses, choose a training input stage, then run or generate a reproducible script.';
            end
        end

        function grid = gridStateForSelection(NM, selected)
            selected = NMMLOptimizerRunnerUI.normalizeIndexVector(selected);
            grid = struct('visible',false, 'hiddenByLegacyRule',false, 'proceedAllowed',false, ...
                'reason','Select at least one executable analysis.', 'ix',0, 'jx',0, ...
                'state',struct(), 'GridAct',false(0,0));
            if isempty(selected), return; end
            dims = zeros(numel(selected),2);
            for i = 1:numel(selected)
                [dims(i,1), dims(i,2)] = NMMLOptimizerRunnerUI.analysisGridDims(NM, selected(i));
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
                grid.reason = 'Selected analyses have different CV2 grid sizes; each analysis will run all CV2 partitions.';
                return;
            end
            G = true(dims(1,1), dims(1,2));
            grid.visible = true;
            grid.proceedAllowed = true;
            grid.reason = 'Select the CV2 permutation/fold cells to train.';
            grid.ix = dims(1,1);
            grid.jx = dims(1,2);
            grid.GridAct = G;
            grid.state = NMRuntimeGridTools.state(dims(1,1), dims(1,2), G, struct('requireAny',true));
        end

        function [NM, out] = runTraining(NM, plan)
            indices = NMMLOptimizerRunnerUI.normalizeIndexVector(plan.analysisIndices);
            if isempty(indices)
                error('NMMLOptimizerRunnerUI:noAnalysisSelected', 'Select at least one analysis before running ML training.');
            end
            opts = NMMLOptimizerRunnerUI.optionsFromPlan(plan);
            gridVisible = isfield(plan,'gridVisible') && logical(plan.gridVisible);
            gridHiddenByLegacyRule = isfield(plan,'gridHiddenByLegacyRule') && logical(plan.gridHiddenByLegacyRule);
            if ~gridVisible && ~gridHiddenByLegacyRule
                gridInfo = NMMLOptimizerRunnerUI.gridStateForSelection(NM, indices);
                gridVisible = logical(gridInfo.visible);
            end
            runtimeUI = [];
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                runtimeUI = plan.runtimeUI;
                NMRuntimeProgressTools.start(runtimeUI, 'NM Training Progress Viewer', 'Preparing CV2 partition processing.');
            end
            results = cell(1,numel(indices));
            try
                for k = 1:numel(indices)
                    idx = indices(k);
                    spec = NMMLOptimizerRunnerUI.buildTrainSpec(NM, plan, opts, idx, gridVisible, numel(indices));
                    [NM, runOut] = NMRunTools.trainAnalysis(NM, idx, spec);
                    results{k} = runOut;
                end
                if ~isempty(runtimeUI)
                    NMRuntimeProgressTools.finish(runtimeUI, 'ML training completed.');
                end
            catch ME
                if ~isempty(runtimeUI)
                    NMRuntimeProgressTools.fail(runtimeUI, 'NMMLOptimizerRunnerUI.runTraining', ME);
                end
                rethrow(ME);
            end
            out = struct('ok',true, 'message',sprintf('ML training completed for %d analysis/analyses.', numel(indices)), ...
                'analysisIndices',indices, 'results',{results});
        end

        function spec = buildTrainSpec(NM, plan, opts, idx, gridVisible, nSelected)
            if nargin < 6 || isempty(nSelected), nSelected = numel(NMMLOptimizerRunnerUI.normalizeIndexVector(plan.analysisIndices)); end
            requested = NMMLOptimizerRunnerUI.safeMode(opts.operationMode, 'auto');
            manualMode = NMMLOptimizerRunnerUI.safeMode(NMMLOptimizerRunnerUI.fieldOr(opts,'manualArtifactMode','none'), 'none');
            manualFiles = struct();
            if isfield(opts,'manualFiles') && isstruct(opts.manualFiles), manualFiles = opts.manualFiles; end
            if ~strcmp(manualMode,'none') && nSelected > 1
                error('NMMLOptimizerRunnerUI:manualArtifactMultiAnalysis', ...
                    'Manual artifact override is only supported for one selected analysis at a time.');
            end
            if gridVisible
                requestedGridAction = NMMLOptimizerRunnerUI.requestGridAct(plan, NM, idx);
            else
                requestedGridAction = 'all';
            end
            effectiveMode = NMMLOptimizerRunnerUI.resolveEffectiveMode(NM, idx, requested, manualMode, requestedGridAction, manualFiles);
            spec = struct();
            spec.operationMode = effectiveMode;
            spec.requestedOperationMode = requested;
            spec.manualArtifactMode = manualMode;
            spec.overwrite = logical(NMMLOptimizerRunnerUI.fieldOr(opts,'overwrite',false));
            spec.update = logical(NMMLOptimizerRunnerUI.fieldOr(opts,'update',true));
            spec.debugall = logical(NMMLOptimizerRunnerUI.fieldOr(opts,'debugall',false));
            spec.debugopt = logical(NMMLOptimizerRunnerUI.fieldOr(opts,'debugopt',false));
            spec.devMode = false;
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                spec.UI = plan.runtimeUI;
                spec.UI.analysisIndex = double(idx);
            end
            if gridVisible && ~strcmp(effectiveMode,'results')
                spec.hideGrid = false;
                spec.gridAction = requestedGridAction;
            else
                spec.hideGrid = true;
                spec.gridAction = 'all';
            end
            if strcmp(effectiveMode,'scratch')
                NMMLOptimizerRunnerUI.assertScratchInputsReady(NM, idx, spec.gridAction);
            elseif strcmp(manualMode,'none')
                [spec.gridAction, ~] = NMMLOptimizerRunnerUI.assertAutoArtifactGridCoverage(NM, idx, effectiveMode, spec.gridAction);
                spec = NMMLOptimizerRunnerUI.attachAutoArtifactFiles(NM, idx, spec, effectiveMode);
            else
                [spec.gridAction, ~] = NMMLOptimizerRunnerUI.intersectManualArtifactGrid(spec.gridAction, effectiveMode, manualFiles);
            end
            spec = NMMLOptimizerRunnerUI.attachManualFiles(spec, effectiveMode, manualMode, manualFiles);
        end

        function mode = resolveEffectiveMode(NM, idx, requested, manualMode, gridAction, manualFiles)
            if nargin < 5, gridAction = 'all'; end
            if nargin < 6 || isempty(manualFiles), manualFiles = struct(); end
            if ~strcmp(manualMode,'none')
                mode = manualMode;
                return;
            end
            if ~strcmp(requested,'auto')
                mode = requested;
            else
                artifacts = NMRuntimeActionTools.artifactState(NM, struct('analysisIndex',idx,'useArtifactCache',true));
                mode = 'scratch';
                item = NMMLOptimizerRunnerUI.artifactStateItemForMode(artifacts, 'results');
                if NMMLOptimizerRunnerUI.artifactStateItemUsable(item, 'results')
                    mode = 'results';
                    return;
                end
                if NMMLOptimizerRunnerUI.autoArtifactOverlapCount(artifacts, 'datamat', gridAction) > 0
                    mode = 'datamat';
                    return;
                end
                if NMMLOptimizerRunnerUI.autoArtifactOverlapCount(artifacts, 'preproc', gridAction) > 0
                    mode = 'preproc';
                    return;
                end
            end
        end

        function assertScratchInputsReady(NM, idx, gridAction)
            % assertScratchInputsReady  Validate external inputs required before scratch training.
            %
            % Authority and flow: ordinary analyses require no pre-existing artifact; their modality
            % and preprocessing context is materialized by NMRunTools and nk_GetAnalModalInfo_config.
            % Stacking is the sole exception because scratch execution consumes resident first-tier
            % CVdatamats. This method validates their selected-CV2 coverage before execution.
            %
            % Failure semantics: missing, incompatible or incomplete stacking input coverage raises
            % an explicit error. Non-stacking analyses return without inspecting stream count.
            artifacts = NMRuntimeActionTools.artifactState(NM, struct('analysisIndex',idx));
            isStacking = isstruct(artifacts) && isfield(artifacts,'stacking') && isstruct(artifacts.stacking) && ...
                isfield(artifacts.stacking,'enabled') && logical(artifacts.stacking.enabled);
            if ~isStacking, return; end
            S = artifacts.stacking;
            if ~isfield(S,'cellAvailableMask') || isempty(S.cellAvailableMask)
                msg = 'first-tier CVdatamat input completeness could not be determined.';
                if isfield(S,'message') && ~isempty(S.message), msg = char(string(S.message)); end
                error('NMMLOptimizerRunnerUI:stackingScratchBlocked', ...
                    'Scratch training is unavailable for stacking analysis %d because %s', idx, msg);
            end
            mask = logical(S.cellAvailableMask);
            if ischar(gridAction) || isstring(gridAction)
                G = true(size(mask));
            else
                G = logical(gridAction);
                if ~isequal(size(G), size(mask))
                    error('NMMLOptimizerRunnerUI:stackingGridMismatch', ...
                        'The selected CV2 grid does not match the first-tier stacking input grid for analysis %d.', idx);
                end
            end
            nSel = nnz(G);
            nMissing = nnz(G & ~mask);
            if nSel < 1
                error('NMMLOptimizerRunnerUI:emptyGrid', 'Select at least one CV2 partition for analysis %d.', idx);
            end
            if nMissing > 0
                error('NMMLOptimizerRunnerUI:stackingScratchBlocked', ...
                    ['Scratch training is unavailable for stacking analysis %d because first-tier CVdatamat inputs ', ...
                     'are missing for %d/%d selected CV2 partitions. Use the Grid picker to select complete cells, ', ...
                     'or train/generate the missing first-tier CVdatamats first.'], idx, nMissing, nSel);
            end
        end

        function [gridAction, nOverlap] = assertAutoArtifactGridCoverage(NM, idx, mode, gridAction)
            mode = char(string(mode));
            nOverlap = NaN;
            if ~ismember(mode, {'preproc','datamat'})
                return;
            end
            artifacts = NMRuntimeActionTools.artifactState(NM, struct('analysisIndex',idx,'useArtifactCache',true));
            item = NMMLOptimizerRunnerUI.artifactStateItemForMode(artifacts, mode);
            if ~isstruct(item)
                error('NMMLOptimizerRunnerUI:missingAutoArtifact', ...
                    '%s mode found no auto-discovered artifact state for analysis %d.', NMMLOptimizerRunnerUI.modeText(mode), idx);
            end
            [gridAction, nOverlap, knownMask] = NMMLOptimizerRunnerUI.intersectArtifactGrid(gridAction, item);
            if knownMask
                if nOverlap < 1
                    error('NMMLOptimizerRunnerUI:autoArtifactGridNoOverlap', ...
                        ['The selected CV2 grid has no overlap with auto-discovered %s artifacts for analysis %d. ', ...
                         'Select at least one covered cell or choose another input stage.'], ...
                        NMMLOptimizerRunnerUI.modeText(mode), idx);
                end
            elseif ~NMMLOptimizerRunnerUI.artifactStateItemUsable(item, mode)
                error('NMMLOptimizerRunnerUI:missingAutoArtifact', ...
                    '%s mode requires at least one auto-discovered artifact for analysis %d.', ...
                    NMMLOptimizerRunnerUI.modeText(mode), idx);
            end
        end

        function nOverlap = autoArtifactOverlapCount(artifacts, mode, gridAction)
            nOverlap = 0;
            item = NMMLOptimizerRunnerUI.artifactStateItemForMode(artifacts, mode);
            if ~isstruct(item) || ~NMMLOptimizerRunnerUI.artifactStateItemUsable(item, mode), return; end
            [~, nOverlap, knownMask] = NMMLOptimizerRunnerUI.intersectArtifactGrid(gridAction, item);
            if ~knownMask && NMMLOptimizerRunnerUI.artifactStateItemUsable(item, mode)
                nOverlap = 1;
            end
        end

        function [gridActionOut, nOverlap, knownMask] = intersectArtifactGrid(gridAction, item)
            gridActionOut = gridAction;
            nOverlap = NaN;
            knownMask = false;
            if ~isstruct(item) || ~isfield(item,'cellAvailableMask') || isempty(item.cellAvailableMask)
                return;
            end
            mask = logical(item.cellAvailableMask);
            if isempty(mask)
                return;
            end
            knownMask = true;
            if ischar(gridAction) || isstring(gridAction)
                G = true(size(mask));
            else
                G = logical(gridAction);
                if ~isequal(size(G), size(mask))
                    error('NMMLOptimizerRunnerUI:artifactGridMismatch', ...
                        'The selected CV2 grid size does not match the artifact coverage mask.');
                end
            end
            G2 = G & mask;
            nOverlap = nnz(G2);
            if nOverlap > 0
                gridActionOut = G2;
            end
        end

        function [gridActionOut, nOverlap] = intersectManualArtifactGrid(gridAction, effectiveMode, manualFiles)
            gridActionOut = gridAction;
            nOverlap = NaN;
            mode = char(string(effectiveMode));
            if ~ismember(mode, {'preproc','datamat'}) || ischar(gridAction) || isstring(gridAction) || ~isstruct(manualFiles)
                return;
            end
            [files, hasMaster] = NMMLOptimizerRunnerUI.manualPerCellFilesForMode(mode, manualFiles);
            if hasMaster || isempty(files)
                return;
            end
            mask = NMMLOptimizerRunnerUI.manualArtifactMaskFromFiles(files, mode, size(logical(gridAction)));
            if isempty(mask)
                return;
            end
            G2 = logical(gridAction) & mask;
            nOverlap = nnz(G2);
            if nOverlap < 1
                error('NMMLOptimizerRunnerUI:manualArtifactGridNoOverlap', ...
                    ['The selected CV2 grid has no overlap with the manually selected %s artifacts. ', ...
                     'Select at least one matching CV2 partition or choose different artifacts.'], NMMLOptimizerRunnerUI.modeText(mode));
            end
            gridActionOut = G2;
        end

        function [files, hasMaster] = manualPerCellFilesForMode(mode, manualFiles)
            files = {};
            hasMaster = false;
            switch char(string(mode))
                case 'preproc'
                    hasMaster = isfield(manualFiles,'preprocMasterFile') && ~isempty(manualFiles.preprocMasterFile);
                    if isfield(manualFiles,'preprocDataFiles') && ~isempty(manualFiles.preprocDataFiles)
                        files = cellstr(manualFiles.preprocDataFiles);
                    end
                case 'datamat'
                    hasMaster = isfield(manualFiles,'cvDataMasterFile') && ~isempty(manualFiles.cvDataMasterFile);
                    if isfield(manualFiles,'cvDataMatFiles') && ~isempty(manualFiles.cvDataMatFiles)
                        files = cellstr(manualFiles.cvDataMatFiles);
                    end
            end
            files = files(~cellfun(@isempty, files));
        end

        function mask = manualArtifactMaskFromFiles(files, mode, gridSize)
            key = 'preprocData';
            if strcmp(mode,'datamat'), key = 'cvDatamat'; end
            [mask,~] = NMRuntimeActionTools.cvCellCoverageMaskFromFiles(files,key,1,gridSize);
            if ~isempty(mask) && ~any(mask(:)), mask = []; end
        end

        function spec = attachAutoArtifactFiles(NM, idx, spec, mode)
            if ~ismember(char(string(mode)), {'preproc','datamat','results'})
                return;
            end
            artifacts = NMRuntimeActionTools.artifactState(NM, struct('analysisIndex',idx,'useArtifactCache',true));
            item = NMMLOptimizerRunnerUI.artifactStateItemForMode(artifacts, mode);
            if ~isstruct(item) || ~NMMLOptimizerRunnerUI.artifactStateItemUsable(item, mode)
                error('NMMLOptimizerRunnerUI:missingAutoArtifact', ...
                    '%s mode requires at least one auto-discovered artifact for analysis %d.', ...
                    NMMLOptimizerRunnerUI.modeText(mode), idx);
            end
            switch char(string(mode))
                case 'preproc'
                    if isfield(item,'files') && ~isempty(item.files)
                        spec.preprocDataFiles = cellstr(item.files);
                    elseif isfield(item,'masterFile') && ~isempty(item.masterFile)
                        spec.preprocMasterFile = char(string(item.masterFile));
                    end
                case 'datamat'
                    if isfield(item,'files') && ~isempty(item.files)
                        spec.cvDataMatFiles = cellstr(item.files);
                    elseif isfield(item,'masterFile') && ~isempty(item.masterFile)
                        spec.cvDataMasterFile = char(string(item.masterFile));
                    end
                case 'results'
                    if isfield(item,'files') && ~isempty(item.files)
                        spec.gdanalmat = cellstr(item.files);
                    elseif isfield(item,'masterFile') && ~isempty(item.masterFile)
                        spec.cvResultsMasterFile = char(string(item.masterFile));
                    end
            end
        end

        function item = artifactStateItemForMode(artifacts, mode)
            item = [];
            if ~isstruct(artifacts), return; end
            switch char(string(mode))
                case 'preproc', field = 'preprocData';
                case 'datamat', field = 'cvDatamat';
                case 'results', field = 'cvResults';
                otherwise, field = '';
            end
            if ~isempty(field) && isfield(artifacts, field) && isstruct(artifacts.(field))
                item = artifacts.(field);
            end
        end

        function tf = artifactStateItemUsable(item, mode)
            if nargin < 2 || isempty(mode), mode = ''; end
            mode = char(string(mode));
            tf = isstruct(item) && ( ...
                (isfield(item,'available') && ~isempty(item.available) && logical(item.available)) || ...
                (isfield(item,'nLogicalAvailable') && ~isempty(item.nLogicalAvailable) && double(item.nLogicalAvailable) > 0) || ...
                (isfield(item,'nAvailable') && ~isempty(item.nAvailable) && double(item.nAvailable) > 0) || ...
                (isfield(item,'files') && ~isempty(item.files)) );
            if ~tf && strcmp(mode,'results') && isstruct(item)
                tf = (isfield(item,'masterFile') && ~isempty(item.masterFile)) || ...
                    (isfield(item,'masterFiles') && ~isempty(item.masterFiles));
            end
        end

        function txt = modeText(mode)
            switch char(string(mode))
                case 'preproc', txt = 'PreprocData';
                case 'datamat', txt = 'CVdatamat';
                case 'results', txt = 'CVresults';
                otherwise, txt = char(string(mode));
            end
        end

        function spec = attachManualFiles(spec, effectiveMode, manualMode, manualFiles)
            if strcmp(manualMode,'none') || ~isstruct(manualFiles), return; end
            switch effectiveMode
                case 'preproc'
                    if isfield(manualFiles,'preprocMasterFile') && ~isempty(manualFiles.preprocMasterFile)
                        spec.preprocMasterFile = char(string(manualFiles.preprocMasterFile));
                    elseif isfield(manualFiles,'preprocDataFiles') && ~isempty(manualFiles.preprocDataFiles)
                        spec.preprocDataFiles = cellstr(manualFiles.preprocDataFiles);
                    end
                case 'datamat'
                    if isfield(manualFiles,'cvDataMasterFile') && ~isempty(manualFiles.cvDataMasterFile)
                        spec.cvDataMasterFile = char(string(manualFiles.cvDataMasterFile));
                    elseif isfield(manualFiles,'cvDataMatFiles') && ~isempty(manualFiles.cvDataMatFiles)
                        spec.cvDataMatFiles = cellstr(manualFiles.cvDataMatFiles);
                    end
                case 'results'
                    if isfield(manualFiles,'cvResultsMasterFile') && ~isempty(manualFiles.cvResultsMasterFile)
                        spec.cvResultsMasterFile = char(string(manualFiles.cvResultsMasterFile));
                    elseif isfield(manualFiles,'gdanalmat') && ~isempty(manualFiles.gdanalmat)
                        spec.gdanalmat = cellstr(manualFiles.gdanalmat);
                    end
            end
        end

        function out = generateRuntimeScript(NM, plan)
            indices = NMMLOptimizerRunnerUI.normalizeIndexVector(plan.analysisIndices);
            if isempty(indices)
                error('NMMLOptimizerRunnerUI:noAnalysisSelected', 'Select at least one analysis before generating a runtime script.');
            end
            opts = NMMLOptimizerRunnerUI.optionsFromPlan(plan);
            gridVisible = isfield(plan,'gridVisible') && logical(plan.gridVisible);
            gridHiddenByLegacyRule = isfield(plan,'gridHiddenByLegacyRule') && logical(plan.gridHiddenByLegacyRule);
            if ~gridVisible && ~gridHiddenByLegacyRule
                gridInfo = NMMLOptimizerRunnerUI.gridStateForSelection(NM, indices);
                gridVisible = logical(gridInfo.visible);
            end
            list = NMAnalysisManagerTools.listAnalyses(NM);
            scripts = {};
            for k = 1:numel(indices)
                idx = indices(k);
                spec = NMMLOptimizerRunnerUI.buildTrainSpec(NM, plan, opts, idx, gridVisible, numel(indices));
                rootdir = NMMLOptimizerRunnerUI.analysisRootFromList(list, idx);
                analysisId = NMMLOptimizerRunnerUI.analysisIdFromList(list, idx);
                if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                    error('NMMLOptimizerRunnerUI:noAnalysisRoot', ...
                        'Analysis %d has no accessible root directory; cannot write a runtime script.', idx);
                end
                fname = sprintf('NM_train_analysis_%d.m', idx);
                fpath = fullfile(rootdir, fname);
                txt = NMMLOptimizerRunnerUI.scriptTextForSpec(idx, analysisId, spec);
                NMMLOptimizerRunnerUI.writeTextFile(fpath, txt);
                scripts{end+1} = struct('analysisIndex',idx, 'id',analysisId, 'path',fpath); %#ok<AGROW>
            end
            out = struct('ok',true, 'message',sprintf('Generated %d ML-training runtime script(s).', numel(scripts)), ...
                'scripts',{scripts});
        end

        function [filters, title] = artifactPickerFilters(mode, dataId)
            dataId = char(string(dataId));
            if ~isempty(dataId)
                if startsWith(dataId, 'ID')
                    idSuffix = dataId;
                else
                    idSuffix = ['ID' dataId];
                end
            else
                idSuffix = '';
            end
            switch mode
                case 'preproc'
                    title = NMMLOptimizerRunnerUI.pickerTitle('Select PreprocData master artifact', dataId);
                    filters = NMMLOptimizerRunnerUI.filterRows({ ...
                        NMMLOptimizerRunnerUI.idPattern('*PreprocMaster*%s*.mat', idSuffix), 'Matching PreprocMaster for this NM.id'; ...
                        NMMLOptimizerRunnerUI.idPattern('*PreprocData*%s*.mat', idSuffix), 'Matching PreprocData files for this NM.id'; ...
                        '*PreprocMaster*.mat', 'PreprocMaster MAT files'; ...
                        '*PreprocData*.mat', 'PreprocData MAT files'; ...
                        '*.mat', 'All MAT files'});
                case 'datamat'
                    title = NMMLOptimizerRunnerUI.pickerTitle('Select CVdatamat master artifact', dataId);
                    filters = NMMLOptimizerRunnerUI.filterRows({ ...
                        NMMLOptimizerRunnerUI.idPattern('*CVdataMaster*%s*.mat', idSuffix), 'Matching CVdataMaster for this NM.id'; ...
                        NMMLOptimizerRunnerUI.idPattern('*CVdatamat*%s*.mat', idSuffix), 'Matching CVdatamat files for this NM.id'; ...
                        '*CVdataMaster*.mat', 'CVdataMaster MAT files'; ...
                        '*CVdatamat*.mat', 'CVdatamat MAT files'; ...
                        '*.mat', 'All MAT files'});
                case 'results'
                    title = NMMLOptimizerRunnerUI.pickerTitle('Select CVresultsMaster or CVresults artifact', dataId);
                    filters = NMMLOptimizerRunnerUI.filterRows({ ...
                        NMMLOptimizerRunnerUI.idPattern('*CVresultsMaster*%s*.mat', idSuffix), 'Matching CVresultsMaster for this NM.id'; ...
                        NMMLOptimizerRunnerUI.idPattern('*CVresults*%s*.mat', idSuffix), 'Matching CVresults files for this NM.id'; ...
                        '*CVresultsMaster*.mat', 'CVresultsMaster MAT files'; ...
                        '*CVresults*.mat', 'CVresults MAT files'; ...
                        '*.mat', 'All MAT files'});
                otherwise
                    error('NMMLOptimizerRunnerUI:badArtifactMode', 'Select PreprocData, CVdatamat or CVresults before picking a file.');
            end
        end

        function title = pickerTitle(base, dataId)
            if isempty(dataId)
                title = base;
            else
                title = sprintf('%s for NM.id %s', base, dataId);
            end
        end

        function pattern = idPattern(fmt, idSuffix)
            if isempty(idSuffix)
                pattern = '';
            else
                pattern = sprintf(fmt, idSuffix);
            end
        end

        function rows = filterRows(rows)
            keep = true(size(rows,1),1);
            for i = 1:size(rows,1)
                keep(i) = ~isempty(rows{i,1});
            end
            rows = rows(keep,:);
        end

        function out = pickArtifactFile(~, ~)
            % Deprecated: runner pages now use /api/pickpath directly so the
            % OS-native file picker can support multi-file selection and the
            % same bridge path used by DataIO.
            out = struct('ok',false,'message','Manual artifact selection is handled by the browser OS file picker (/api/pickpath).', ...
                'cancelled',false,'deprecated',true);
        end

        function txt = scriptTextForSpec(idx, analysisId, spec)
            nl = newline;
            gridLiteral = NMMLOptimizerRunnerUI.gridActionLiteral(spec.gridAction);
            gridComment = NMMLOptimizerRunnerUI.gridActionComment(spec.gridAction);
            L = { ...
sprintf('%% NM_train_analysis_%d.m', idx)
'% ========================================================================='
'% NeuroMiner runtime script  --  generated by the ML training runner'
'% ========================================================================='
sprintf('%% Analysis %d%s', idx, NMMLOptimizerRunnerUI.idComment(analysisId))
'%'
'% WHAT THIS SCRIPT DOES'
'%   It reproduces, from the MATLAB command line, the ML-training run you'
'%   configured in the browser UI. It calls the public NeuroMiner API entry'
'%   point NMRunTools.trainAnalysis, not the legacy interactive menu.'
'%'
'% PREREQUISITE -- the NM structure'
'%   This script expects your NeuroMiner project struct to be loaded in the'
'%   workspace as `NM` before execution.'
'% -------------------------------------------------------------------------'
''
'if exist(''NM'',''var'') ~= 1'
'    error([''This script needs your NeuroMiner project in the workspace. '' ...'
'        ''Load it first, e.g.  S = load(''''my_project.mat'''');  NM = S.NM;'']);'
'end'
''
'spec = struct();'
''
'% operationMode: resolved training input stage. The browser may have used'
'%   Auto, but this generated script stores the effective mode so it is'
'%   reproducible at generation time.'
sprintf('spec.operationMode          = ''%s'';', char(string(spec.operationMode)))
sprintf('spec.requestedOperationMode = ''%s'';', char(string(NMMLOptimizerRunnerUI.fieldOr(spec,'requestedOperationMode',spec.operationMode))))
''
'% overwrite: allow the legacy optimizer to overwrite downstream training'
'%   outputs for the selected stage.'
sprintf('spec.overwrite              = %s;', NMMLOptimizerRunnerUI.boolLiteral(spec.overwrite))
''
'% update: refresh derived summaries when starting from existing artifacts.'
sprintf('spec.update                 = %s;', NMMLOptimizerRunnerUI.boolLiteral(spec.update))
''
'% debugall/debugopt: developer-only model-saving flags; leave false for'
'%   normal runs.'
sprintf('spec.debugall               = %s;', NMMLOptimizerRunnerUI.boolLiteral(spec.debugall))
sprintf('spec.debugopt               = %s;', NMMLOptimizerRunnerUI.boolLiteral(spec.debugopt))
'spec.devMode                = false;'
''
'% hideGrid/gridAction: selected CV2 permutation/fold cells.'
sprintf('%%   %s', gridComment)
sprintf('spec.hideGrid               = %s;', NMMLOptimizerRunnerUI.boolLiteral(spec.hideGrid))
sprintf('spec.gridAction             = %s;', gridLiteral)
''};
            artifactLines = NMMLOptimizerRunnerUI.manualFileScriptLines(spec);
            artifactLines = artifactLines(:)';
            trailerLines = { ...
'% -------------------------------------------------------------------------'
'% RUN IT'
'%   trainAnalysis returns the updated NM and a runOut struct. The updated NM'
'%   contains trained GDdims/results after successful execution.'
'% -------------------------------------------------------------------------'
sprintf('[NM, runOut] = NMRunTools.trainAnalysis(NM, %d, spec);', idx)
'disp(runOut.message);'
''
'% Tip: save NM after this completes if you want to persist the new state.'
'%   save(''my_project.mat'', ''NM'');'
''};
            L = [L(:)' artifactLines trailerLines(:)'];
            txt = strjoin(L, nl);
        end

        function L = manualFileScriptLines(spec)
            L = cell(1,0);
            manualMode = char(string(NMMLOptimizerRunnerUI.fieldOr(spec,'manualArtifactMode','none')));
            if strcmpi(manualMode,'none')
                sourceLabel = 'Resolved artifact input';
            else
                sourceLabel = 'Manual artifact override';
            end
            if isfield(spec,'preprocMasterFile') && ~isempty(spec.preprocMasterFile)
                L = [L {'' sprintf('%% %s: PreprocMaster file.', sourceLabel) sprintf('spec.preprocMasterFile    = %s;', NMMLOptimizerRunnerUI.stringLiteral(spec.preprocMasterFile))}];
            elseif isfield(spec,'preprocDataFiles') && ~isempty(spec.preprocDataFiles)
                L = [L {'' sprintf('%% %s: PreprocData files.', sourceLabel) sprintf('spec.preprocDataFiles     = %s;', NMMLOptimizerRunnerUI.cellStringLiteral(spec.preprocDataFiles))}];
            end
            if isfield(spec,'cvDataMasterFile') && ~isempty(spec.cvDataMasterFile)
                L = [L {'' sprintf('%% %s: CVdataMaster file.', sourceLabel) sprintf('spec.cvDataMasterFile     = %s;', NMMLOptimizerRunnerUI.stringLiteral(spec.cvDataMasterFile))}];
            elseif isfield(spec,'cvDataMatFiles') && ~isempty(spec.cvDataMatFiles)
                L = [L {'' sprintf('%% %s: CVdatamat files.', sourceLabel) sprintf('spec.cvDataMatFiles       = %s;', NMMLOptimizerRunnerUI.cellStringLiteral(spec.cvDataMatFiles))}];
            end
            if isfield(spec,'cvResultsMasterFile') && ~isempty(spec.cvResultsMasterFile)
                L = [L {'' sprintf('%% %s: CVresultsMaster file.', sourceLabel) sprintf('spec.cvResultsMasterFile  = %s;', NMMLOptimizerRunnerUI.stringLiteral(spec.cvResultsMasterFile))}];
            elseif isfield(spec,'gdanalmat') && ~isempty(spec.gdanalmat)
                L = [L {'' sprintf('%% %s: CVresults file(s).', sourceLabel) sprintf('spec.gdanalmat            = %s;', NMMLOptimizerRunnerUI.cellStringLiteral(spec.gdanalmat))}];
            end
            L = L(:)';
        end

        function plan = attachRuntimeProgressContext(plan, req, tmpDir)
            taskId = NMMLOptimizerRunnerUI.requestChar(req, 'progressTaskId', '');
            if isempty(taskId) && isstruct(req) && isfield(req,'extra') && isstruct(req.extra)
                taskId = NMMLOptimizerRunnerUI.requestChar(req.extra, 'progressTaskId', '');
            end
            if isempty(taskId)
                return;
            end
            minInterval = NMMLOptimizerRunnerUI.requestNumeric(req, 'progressChartMinIntervalSeconds', 0);
            if isstruct(req) && isfield(req,'extra') && isstruct(req.extra)
                minInterval = NMMLOptimizerRunnerUI.requestNumeric(req.extra, 'progressChartMinIntervalSeconds', minInterval);
            end
            plan.runtimeUI = NMRuntimeProgressTools.browserRuntimeContext(tmpDir, taskId, ...
                struct('source','ml_train_runner', 'chartEnabled',true, ...
                    'suppressNativeViewer',true, 'chartMinIntervalSeconds',minInterval));
        end

        function opts = optionsFromPlan(plan)
            if isfield(plan,'options') && isstruct(plan.options)
                opts = plan.options;
            else
                opts = struct();
            end
            d = NMMLOptimizerRunnerUI.defaultOptions();
            f = fieldnames(d);
            for i = 1:numel(f)
                if ~isfield(opts,f{i}) || isempty(opts.(f{i})), opts.(f{i}) = d.(f{i}); end
            end
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

        function G = requestGridAct(plan, NM, idx)
            if isfield(plan,'GridAct') && ~isempty(plan.GridAct)
                raw = plan.GridAct;
            else
                [ix,jx] = NMMLOptimizerRunnerUI.analysisGridDims(NM, idx);
                raw = true(ix,jx);
            end
            [ix,jx] = NMMLOptimizerRunnerUI.analysisGridDims(NM, idx);
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
                error('NMMLOptimizerRunnerUI:badGridAct', '%s', msg);
            end
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

        function tf = isStackingAnalysis(NM, idx)
            tf = false;
            try
                TP = NM.analysis{idx}.params.TrainParam;
                tf = isfield(TP,'STACKING') && isstruct(TP.STACKING) && ...
                    isfield(TP.STACKING,'flag') && ~isempty(TP.STACKING.flag) && ...
                    round(double(TP.STACKING.flag)) == 1;
            catch
                tf = false;
            end
        end

        function v = fieldOr(s, field, default)
            v = default;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field))
                v = s.(field);
            end
        end

        function v = requestField(req, field, default)
            v = default;
            if isstruct(req) && isfield(req, field)
                v = req.(field);
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

        function v = requestChar(req, field, default)
            v = default;
            if isstruct(req) && isfield(req, field) && ~isempty(req.(field))
                try
                    v = char(string(req.(field)));
                catch
                    v = default;
                end
            end
        end

        function v = requestNumeric(req, field, default)
            v = default;
            if isstruct(req) && isfield(req, field) && ~isempty(req.(field))
                try
                    raw = double(req.(field));
                    if isscalar(raw) && isfinite(raw), v = raw; end
                catch
                    v = default;
                end
            end
        end

        function mode = safeMode(mode, default)
            mode = lower(strtrim(char(string(mode))));
            allowed = {'none','auto','scratch','preproc','preprocdata','datamat','cvdatamat','results','cvresults'};
            if ~any(strcmp(mode, allowed)), mode = default; end
            switch mode
                case 'preprocdata'
                    mode = 'preproc';
                case 'cvdatamat'
                    mode = 'datamat';
                case 'cvresults'
                    mode = 'results';
            end
        end

        function rootdir = analysisRootFromList(list, idx)
            rootdir = '';
            if isstruct(list) && isfield(list,'rootdirs') && iscell(list.rootdirs) && idx <= numel(list.rootdirs)
                rootdir = char(string(list.rootdirs{idx}));
            end
        end

        function analysisId = analysisIdFromList(list, idx)
            analysisId = '';
            if isstruct(list) && isfield(list,'ids') && iscell(list.ids) && idx <= numel(list.ids)
                analysisId = char(string(list.ids{idx}));
            end
        end

        function s = gridActionComment(gridAction)
            if ischar(gridAction) || isstring(gridAction)
                s = 'Your selection: run all CV2 partitions of this analysis.';
            else
                G = logical(gridAction);
                n = sum(G(:));
                [ix, jx] = size(G);
                s = sprintf('Your selection: %d of %d CV2 partitions (%dx%d grid).', n, ix*jx, ix, jx);
            end
        end

        function s = boolLiteral(v)
            if logical(v), s = 'true'; else, s = 'false'; end
        end

        function s = idComment(analysisId)
            if isempty(analysisId), s = ''; else, s = sprintf(': %s', analysisId); end
        end

        function s = stringLiteral(v)
            s = ['''' strrep(char(string(v)), '''', '''''') ''''];
        end

        function s = cellStringLiteral(C)
            if ischar(C) || isstring(C), C = cellstr(C); end
            if ~iscell(C), C = {C}; end
            vals = cellfun(@(x) NMMLOptimizerRunnerUI.stringLiteral(x), C(:)', 'UniformOutput', false);
            s = ['{' strjoin(vals, ', ') '}'];
        end

        function s = gridActionLiteral(gridAction)
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

        function tag = assetCacheTag()
            try
                tag = char(java.util.UUID.randomUUID());
            catch
                tag = strrep(sprintf('%.10f', now), '.', '_');
            end
        end

    end
end

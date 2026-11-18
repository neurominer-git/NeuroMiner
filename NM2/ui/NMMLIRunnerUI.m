classdef NMMLIRunnerUI
% NMMLIRunnerUI
% -------------------------------------------------------------------------
% Dedicated browser shell for the NeuroMiner ML-interpretation runtime.
% The page exposes legacy-derived MLI options, trained-analysis selection,
% MLIdatamat resolver summaries, manual MLIdatamat selection, and execution
% through NMRunTools.interpretModels.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(NM, outDir, ctx)
            % export  Create the browser ML-interpretation runner session.
            %
            % Writes the runner HTML, initial artifact/grid state and shared assets, then stores the
            % session NM for service requests. This prepares the ML-interpretation workflow page but
            % leaves actual run/script execution to the MATLAB service handler.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_mli_runner_ui'); end
            if nargin < 3, ctx = struct(); end
            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_mli_runner_ui');
            NMDataIOUI.saveSessionNM(NM, dirs.tmpDir);
            if NMUISessionTools.fastChildOpen(ctx)
                state = NMMLIRunnerUI.bootstrapState(ctx);
            else
                state = NMMLIRunnerUI.stateFromNM(NM, ctx);
            end
            stateJson = NMConfigTools.writeJsonAliases({fullfile(dirs.tmpDir,'mli_runner_state.json'), ...
                fullfile(dirs.tmpDir,'current_config.json'), fullfile(dirs.tmpDir,'param.json')}, state, 'MLI runner state');
            htmlPath = fullfile(dirs.webDir, 'nm_mli_runner.html');
            NMMLIRunnerUI.writeTextFile(htmlPath, NMMLIRunnerUI.htmlTextFromJson(stateJson));
            NMMLIRunnerUI.copyAssets(dirs.webDir);
            NMPreprocUI.writeBridge(fullfile(dirs.pyDir,'nm_bridge_server.py'));
            paths = struct('root',dirs.root, 'webRoot',dirs.webRoot, 'webDir',dirs.webDir, 'tmpDir',dirs.tmpDir, ...
                'html',htmlPath, 'mliRunnerHtml',htmlPath, 'entryHtml','nm_mli_runner.html', ...
                'entryHtmlPath',htmlPath, 'state',fullfile(dirs.tmpDir,'mli_runner_state.json'));
        end

        function NM = importUpdated(NM, pathsOrWebDir, ctx)
            % importUpdated  Return the session NM after the ML-interpretation runner closes.
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
            % stateFromNM  Build artifact and option state for the ML-interpretation runner.
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
                workflow = struct('ok',false,'message','NMStatusGuardTools is not available.');
            end
            opts = NMMLIRunnerUI.requestPlan(struct('plan',opts));
            runtimeOptions = NMMLIRunnerUI.optionsFromPlan(opts);
            runtimeOptions.oocvIndex = opts.oocvIndex;
            mli = NMMLIRuntimeTools.uiState(NM, struct('deferArtifactScan',deferArtifactScan, ...
                'selectedAnalysisIndices',opts.analysisIndices,'options',runtimeOptions));
            state = struct();
            state.page = 'mli_runner';
            state.defs = defs;
            state.workflowStatus = workflow;
            state.analyses = mli.analyses;
            if exist('NMAnalysisManagerTools','class') == 8
                state.analysisList = NMAnalysisManagerTools.listAnalyses(NM);
            else
                state.analysisList = struct();
            end
            state.selectedAnalysisIndices = mli.selectedAnalysisIndices;
            state.grid = mli.grid;
            state.options = mli.options;
            state.operationModes = mli.operationModes;
            state.artifactSummary = mli.artifactSummary;
            state.dynamicControls = mli.dynamicControls;
            state.oocvMode = logical(defs.analyses_locked);
            state.oocv = struct('containers',struct([]));
            state.readiness = struct([]);
            if state.oocvMode && ~deferArtifactScan
                state.oocv = NMDataIOBrowserModeTools.oocvManagerState(NM);
                for a = mli.analyses([mli.analyses.enabled])
                    for c = state.oocv.containers
                        r = NMRunTools.oocvReadiness(NM, a.index, c.index);
                        state.readiness = [state.readiness struct('analysisIndex',a.index, ...
                            'oocvIndex',c.index,'ready',r.ready)]; %#ok<AGROW>
                    end
                end
            end
            state.canRun = ~deferArtifactScan && mli.canRun;
            state.canGenerateScript = state.canRun;
            state.loading = false;
            state.analysesLoading = false;
            state.artifactsLoading = deferArtifactScan;
            if deferArtifactScan
                messages = {'Loading MLIdatamat artifact availability from MATLAB.', 'Loading independent OOCV datasets from MATLAB.'};
                state.statusMessage = messages{1 + state.oocvMode};
            else
                state.statusMessage = NMMLIRunnerUI.statusMessage(defs, workflow, mli.analyses);
            end
            state.executionMessage = 'ML interpretation uses NMRunTools.interpretModels and the selected runtime state.';
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'mli_runner');
        end

        function state = bootstrapState(ctx)
            % bootstrapState  Build a minimal ML-interpretation runner state for fast navigation.
            %
            % Uses app context to render the page shell before the full artifact resolver runs. The
            % complete state is requested immediately through the MATLAB bridge.

            if nargin < 1, ctx = struct(); end
            defs = struct('import_finished',false,'analyses_locked',false);
            workflow = struct('ok',true,'message','ML-interpretation runner is loading the current NeuroMiner state.');
            grid = struct('visible',false, 'hiddenByLegacyRule',false, 'proceedAllowed',false, ...
                'reason','Loading ML-interpretation grid state from MATLAB.', 'ix',0, 'jx',0, ...
                'state',struct(), 'GridAct',false(0,0));
            state = struct();
            state.page = 'mli_runner';
            state.defs = defs;
            state.workflowStatus = workflow;
            state.analyses = [];
            state.analysisList = struct();
            state.selectedAnalysisIndices = [];
            state.grid = grid;
            state.options = struct();
            state.operationModes = [];
            state.artifactSummary = [];
            state.dynamicControls = struct();
            state.oocvMode = false;
            state.oocv = struct('containers',struct([]));
            state.readiness = struct([]);
            state.canRun = false;
            state.canGenerateScript = false;
            state.loading = true;
            state.analysesLoading = true;
            state.artifactsLoading = true;
            state.statusMessage = 'Loading analyses...';
            state.executionMessage = 'ML interpretation uses NMRunTools.interpretModels and the selected runtime state.';
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'mli_runner');
        end

        function [handled, out] = handleMatlabService(NM, req, tmpDir, ctx)
            % handleMatlabService  Dispatch ML-interpretation runner service requests.
            %
            % Handles refresh, artifact resolution, run and script-generation operations by loading
            % session NM and delegating to NMMLIRuntimeTools. Responses include updated runner state and
            % explicit diagnostics for the browser message strip.

            handled = false; out = struct(); if nargin < 4, ctx = struct(); end
            op = NMMLIRunnerUI.requestOperation(req); if isempty(op), return; end
            switch lower(op)
                case {'mli_runner_refresh','mli_runner_state'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    state = NMMLIRunnerUI.stateFromNM(sessionNM, ctx, NMMLIRunnerUI.requestPlan(req));
                    out = struct('ok',true,'message','ML-interpretation runner state refreshed.','operation',op,'state',state);
                case {'mli_runner_refresh_light','mli_runner_state_light'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    state = NMMLIRunnerUI.stateFromNM(sessionNM, ctx, struct('deferArtifactScan',true));
                    out = struct('ok',true,'message','Analyses loaded. MLIdatamat availability is still being resolved.','operation',op,'state',state);
                case {'mli_runner_run'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    plan = struct();
                    try
                        plan = NMMLIRunnerUI.requestPlan(req);
                        plan = NMMLIRunnerUI.attachRuntimeProgressContext(plan, req, tmpDir);
                        [sessionNM, runOut] = NMMLIRunnerUI.runMLI(sessionNM, plan);
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMMLIRunnerUI.stateFromNM(sessionNM, ctx, plan);
                        out = struct('ok',true,'message',runOut.message,'operation',op,'state',state,'result',runOut);
                    catch ME % nm2-allow: Runtime progress is closed and NMUIErrorTools reports the caught exception
                        NMMLIRunnerUI.failRuntimeProgressIfPresent(plan, ME, 'ML-interpretation progress failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Running ML interpretation failed.', 2);
                    end
                case {'mli_runner_generate_script'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    plan = struct();
                    try
                        plan = NMMLIRunnerUI.requestPlan(req);
                        genOut = NMMLIRunnerUI.generateRuntimeScript(sessionNM, plan);
                        out = struct('ok',true,'message',genOut.message,'operation',op,'scripts',{genOut.scripts});
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Generating the ML-interpretation runtime script failed.', 2);
                    end
                otherwise
                    handled = true;
                    out = struct('ok',false,'message',sprintf('Unsupported MLI-runner operation: %s', op), ...
                        'error',sprintf('Unsupported MLI-runner operation: %s', op));
            end
        end

        function txt = htmlTextFromJson(stateJson)
            % htmlTextFromJson  Build the ML-interpretation runner HTML shell.
            %
            % Creates the static page frame, embeds the state reference and loads shared
            % runner/grid-picker/navigation assets. All scientific/runtime decisions remain in
            % MATLAB-side service calls.

            jsState = NMPreprocUI.jsonTextForScript(stateJson);
            assetTag = NMMLIRunnerUI.assetCacheTag(); nl = newline;
            L = { ...
'<!doctype html>'
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
'<title>NeuroMiner ML interpretation runner</title>'
['<link rel="stylesheet" href="NMTrainTemplateUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModuleNavigationRail.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisManagerUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMRuntimeGridPicker.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModal.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMOOCVContainerSelector.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisCardSelector.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMManualArtifactFileList.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMRuntimeProgressViewer.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMMLIRunnerUI.css?v=' assetTag '">']
['<style>' NMUIMessageTools.css() '</style>']
'</head><body class="nmHasNavRail">'
'<header>'
'  <div><div class="crumb">Main interface / post-training discovery</div><div class="title">ML interpretation</div></div>'
'  <div class="headerActions"><button id="finish" class="primary" type="button">Finish / close</button></div>'
'</header>'
'<main class="wrap mliWrap"><section class="panel mliPanel">'
'  <div class="mliPanelHead"><div><h1>Configure NeuroMiner ML interpretation</h1></div></div>'
'  <div class="mliLayout">'
'    <section class="card mliConfigPanel">'
'      <div class="mliSectionHeader"><h2>Runtime configuration</h2><span id="selectedSummary" class="muted"></span></div>'
'      <div id="oocvDatasetField" class="field oocvDatasetField hidden"></div>'
'      <div id="artifactSummary" class="nmRuntimeArtifactSummary mliArtifactSummary"></div>'
'      <div class="field"><label class="nmRunnerSectionTitle" for="operationMode">MLI input stage</label><select id="operationMode"><option value="auto">Auto: scratch/resume using legacy MLI state</option><option value="scratch">Compute from scratch</option><option value="mlidatamat">Use existing MLIdatamat</option></select></div>'
'      <div id="manualArtifactField" class="field"><label class="nmRunnerSectionTitle" for="manualArtifactMode">Manual MLIdatamat override</label><div class="mliArtifactOverride"><select id="manualArtifactMode"><option value="none">None — use automatic resolver</option><option value="mlidatamat">Select MLIdatamat master or CV2 MLIdatamats</option></select><button id="pickArtifactFile" type="button">Pick file(s)…</button></div><div id="manualArtifactSummary" class="help">No manual MLIdatamat artifact selected.</div></div>'
'      <div class="field"><label class="nmRunnerSectionTitle">MLI artifact handling</label></div>'
'      <div id="scratchOptions" class="field mliOptionGroup"><label><input id="overwriteExisting" type="checkbox"> Overwrite existing MLIdatamat outputs</label><label><input id="saveParameters" type="checkbox"> Save newly computed preprocessing/model parameters</label><label><input id="loadParameters" type="checkbox"> Reuse saved preprocessing/model parameters</label><label><input id="saveCV1" type="checkbox"> Save large runtime containers at CV1 level</label></div>'
'      <div id="estimateOptions" class="field mliOptionGroup"><label><input id="overwritePermutations" type="checkbox"> Overwrite existing permutation file</label><label><input id="recomputeEstimates" type="checkbox"> Recompute prediction-change estimates</label></div>'
'      <div id="spatialMapsField" class="field"><label><input id="writeRelevanceMaps" type="checkbox"> Write spatial subject relevance maps</label><label for="surfaceExportFormat">Surface output format</label><select id="surfaceExportFormat"><option value="source">Match DataIO surface format</option><option value="gii">GIFTI (.func.gii)</option><option value="mgh">MGH (.mgh)</option><option value="mgz">MGZ (.mgz)</option></select><div class="help">Voxel maps use NIfTI; surface maps use the selected format. ROI and tabular relevance values remain in the analysis results.</div></div>'
'      <div class="field"><label for="sampleMode">Samples</label><select id="sampleMode"><option value="all">All samples</option><option value="selected">User-defined sample IDs</option></select><textarea id="sampleIDs" rows="3" placeholder="One sample ID per line, or comma-separated"></textarea></div>'
'      <div id="gridSection" class="field"><label class="nmRunnerSectionTitle">CV2 partitions</label><div id="gridReason" class="help"></div><div id="gridPicker"></div></div>'
'      <div id="gridHiddenNote" class="field hidden"><label class="nmRunnerSectionTitle">CV2 partitions</label><div class="help">The CV2 grid picker is hidden by the legacy MLI rule. Each selected analysis will use its trained CV2 partitions.</div></div>'
'      <div class="actions mliRunRow"><button id="runMLI" class="primary nmActionButton" type="button" disabled>Run ML interpretation</button><button id="generateRuntimeScript" class="nmActionButton" type="button" disabled>Generate runtime script</button></div>'
'      <div id="runHint" class="help"></div>'
'    </section>'
'    <section class="card mliAnalysisPanel"><div class="mliSectionHeader"><h2>Analyses</h2><span class="muted">Select one or more trained analyses</span></div><div id="analysisList" class="mliAnalysisList"></div></section>'
'  </div>'
'</section></main>'
['<script>window.NM_MLI_RUNNER_STATE = ' jsState ';</script>']
['<script>' NMUIMessageTools.script() '</script>']
['<script>window.NM_MODULE_NAV_CONTEXT = {currentModule:"mli"};</script>']
['<script src="NMRuntimeGridPicker.js?v=' assetTag '"></script>']
['<script src="NMModal.js?v=' assetTag '"></script>']
['<script src="NMOOCVContainerSelector.js?v=' assetTag '"></script>']
['<script src="NMAnalysisCardSelector.js?v=' assetTag '"></script>']
['<script src="NMManualArtifactFileList.js?v=' assetTag '"></script>']
['<script src="NMRuntimeProgressViewer.js?v=' assetTag '"></script>']
['<script src="NMRuntimeJobClient.js?v=' assetTag '"></script>']
['<script src="NMModuleIconSet.js?v=' assetTag '"></script>']
['<script src="NMModuleNavigationRail.js?v=' assetTag '"></script>']
['<script src="NMRunnerStateManager.js?v=' assetTag '"></script>']
['<script src="NMMLIRunnerUI_main.js?v=' assetTag '"></script>']
'</body></html>'};
            txt = strjoin(L, nl);
        end

        function copyAssets(webDir)
            % copyAssets  Copy static assets for the ML-interpretation runner page.
            %
            % Copies runner JavaScript/CSS plus shared navigation, icon, picker and message-strip assets
            % into the exported web directory. It keeps page export self-contained for the bridge.

            src = fileparts(which('NMMLIRunnerUI.m'));
            files = {'NMMLIRunnerUI.css','NMRunnerStateManager.js','NMMLIRunnerUI_main.js','NMRuntimeGridPicker.js','NMRuntimeGridPicker.css', ...
                'NMModal.js','NMModal.css','NMOOCVContainerSelector.js','NMOOCVContainerSelector.css','NMAnalysisCardSelector.js','NMAnalysisCardSelector.css', ...
                'NMManualArtifactFileList.js','NMManualArtifactFileList.css','NMRuntimeProgressViewer.js','NMRuntimeProgressViewer.css', ...
                'NMRuntimeJobClient.js','NMTrainTemplateUI.css','NMModuleIconSet.js','NMModuleNavigationRail.js','NMModuleNavigationRail.css','NMAnalysisManagerUI.css'};
            for i=1:numel(files)
                s = fullfile(src, files{i}); if exist(s,'file'), copyfile(s, fullfile(webDir, files{i}), 'f'); end
            end
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the ML-interpretation runner text-writer entry point.
            %
            %   NMMLIRunnerUI.writeTextFile(path,txt) delegates generated HTML or auxiliary text output
            %   to NMSerializationTools while retaining the runner-specific error identifier. It is file
            %   packaging plumbing and does not execute interpretation jobs.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMMLIRunnerUI:writeFailed', 'Could not write %s', 'fwrite-input-char');
        end
    end

    methods (Static, Access=private)
        function plan = attachRuntimeProgressContext(plan, req, tmpDir)
            taskId = char(string(NMMLIRunnerUI.fieldOr(req, 'progressTaskId', '')));
            if isempty(taskId) && isstruct(req) && isfield(req,'extra') && isstruct(req.extra)
                taskId = char(string(NMMLIRunnerUI.fieldOr(req.extra, 'progressTaskId', '')));
            end
            if isempty(taskId)
                return;
            end
            minInterval = NMMLIRunnerUI.fieldOr(req, 'progressChartMinIntervalSeconds', 0.15);
            if isstruct(req) && isfield(req,'extra') && isstruct(req.extra)
                minInterval = NMMLIRunnerUI.fieldOr(req.extra, 'progressChartMinIntervalSeconds', minInterval);
            end
            validateattributes(minInterval, {'numeric'}, {'scalar','finite','nonnegative'});
            plan.runtimeUI = NMRuntimeProgressTools.browserRuntimeContext(tmpDir, taskId, ...
                struct('source','mli_runner', 'chartEnabled',true, ...
                    'suppressNativeViewer',true, 'chartMinIntervalSeconds',minInterval, ...
                    'progressTitle','ML interpretation progress', 'progressLowerTitle','Interpretation progress'));
        end

        function failRuntimeProgressIfPresent(plan, ME, source)
            if nargin < 3 || isempty(source), source = 'Runtime progress failed.'; end
            if isstruct(plan) && isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                NMRuntimeProgressTools.fail(plan.runtimeUI, source, ME);
            end
        end

        function plan = requestPlan(req)
            plan = struct();
            if isstruct(req) && isfield(req,'plan') && isstruct(req.plan), plan = req.plan; end
            if ~isfield(plan,'analysisIndices'), plan.analysisIndices = []; end
            if ~isfield(plan,'gridAction'), plan.gridAction = []; end
            if ~isfield(plan,'options') || ~isstruct(plan.options), plan.options = struct(); end
            if ~isfield(plan,'oocvIndex'), plan.oocvIndex = []; end
            if ~isfield(plan.options,'manualFiles') || ~isstruct(plan.options.manualFiles)
                plan.options.manualFiles = struct();
            end
            mf = plan.options.manualFiles;
            if ~isfield(mf,'mliDataMasterFile'), mf.mliDataMasterFile = ''; end
            if ~isfield(mf,'mliDataFiles'), mf.mliDataFiles = {}; end
            if isempty(mf.mliDataFiles), mf.mliDataFiles = {}; else, mf.mliDataFiles = cellstr(mf.mliDataFiles); end
            plan.options.manualFiles = mf;
        end

        function [NM, out] = runMLI(NM, plan)
            % runMLI  Execute the selected analyses through the public MLI runner API.
            %
            % Purpose
            %   Resolve one browser/runtime plan into per-analysis MLI specs, execute them
            %   sequentially, and aggregate computation plus optional relevance-map export status.
            %
            % Inputs/outputs
            %   NM is the active project state; plan contains selected analysis indices, CV2
            %   grid state, runtime UI context and normalized browser options. Returns updated NM
            %   plus one runner result containing per-analysis outputs and export counts.
            %
            % Authority and flow
            %   NMRunTools.interpretModels owns computation and post-run export. This method only
            %   orchestrates selected analyses and reports their already-resolved outcomes.
            %
            % Scientific/state contract
            %   Relevance-map export is optional presentation/materialization output and cannot
            %   alter MLI results or scientific selection.
            %
            % Materialization/performance
            %   O(A) orchestration for A analyses plus the downstream runtime/export costs. It
            %   never copies subject-by-feature MLI matrices.
            %
            % Failure semantics / side effects
            %   Runtime computation errors propagate to the durable-job owner. Per-file export
            %   errors remain in each analysis export report while completed MLI results persist.
            %   Progress side-channel start/finish messages are updated when a runtime UI exists.
            indices = NMMLIRunnerUI.normalizeIndexVector(plan.analysisIndices);
            if isempty(indices)
                error('NMMLIRunnerUI:noAnalysisSelected', 'Select at least one trained analysis before running ML interpretation.');
            end
            opts = NMMLIRunnerUI.optionsFromPlan(plan);
            gridVisible = isfield(plan,'gridVisible') && logical(plan.gridVisible);
            gridHiddenByLegacyRule = isfield(plan,'gridHiddenByLegacyRule') && logical(plan.gridHiddenByLegacyRule);
            if ~gridVisible && ~gridHiddenByLegacyRule
                gridInfo = NMMLIRuntimeTools.gridStateForSelection(NM, indices);
                gridVisible = logical(gridInfo.visible);
            end
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                NMRuntimeProgressTools.start(plan.runtimeUI, 'ML interpretation progress', 'Preparing ML-interpretation runtime.');
            end
            results = cell(1,numel(indices));
            for k = 1:numel(indices)
                idx = indices(k);
                spec = NMMLIRunnerUI.buildMLISpec(NM, plan, opts, idx, gridVisible, numel(indices));
                [NM, runOut] = NMRunTools.interpretModels(NM, idx, spec);
                results{k} = runOut;
            end
            exportFiles = 0; exportErrors = 0; exportRequested = false;
            for k = 1:numel(results)
                R = results{k};
                if isstruct(R) && isfield(R,'relevanceMapExportReport') && isstruct(R.relevanceMapExportReport)
                    ER = R.relevanceMapExportReport;
                    exportFiles = exportFiles + double(NMMLIRunnerUI.fieldOr(ER,'nFiles',0));
                    exportErrors = exportErrors + double(NMMLIRunnerUI.fieldOr(ER,'nErrors',0));
                end
            end
            exportRequested = logical(opts.exportRelevanceMaps);
            message = sprintf('ML interpretation completed for %d analysis/analyses.', numel(indices));
            if exportRequested
                message = sprintf('%s Wrote %d relevance map(s)',message,exportFiles);
                if exportErrors > 0, message = sprintf('%s with %d export error(s).',message,exportErrors); else, message = [message '.']; end
            end
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                NMRuntimeProgressTools.finish(plan.runtimeUI, message, 'ML interpretation progress');
            end
            out = struct('ok',true,'message',message, ...
                'analysisIndices',indices,'results',{results}, ...
                'relevanceMapExportRequested',exportRequested,'relevanceMapFileCount',exportFiles,'relevanceMapErrorCount',exportErrors);
        end

        function spec = buildMLISpec(NM, plan, opts, idx, gridVisible, nSelected)
            if nargin < 6 || isempty(nSelected), nSelected = numel(NMMLIRunnerUI.normalizeIndexVector(plan.analysisIndices)); end
            requested = opts.operationMode;
            manualMode = opts.manualArtifactMode;
            manualFiles = struct(); if isfield(opts,'manualFiles') && isstruct(opts.manualFiles), manualFiles = opts.manualFiles; end
            if ~strcmp(manualMode,'none') && nSelected > 1
                error('NMMLIRunnerUI:manualArtifactMultiAnalysis', 'Manual MLIdatamat artifact override is only supported for one selected analysis at a time.');
            end
            if ~strcmp(manualMode,'none')
                effective = 'mlidatamat';
            elseif strcmp(requested,'auto')
                effective = 'scratch';
            else
                effective = requested;
            end
            spec = rmfield(opts,'manualFiles');
            if NM.defs.analyses_locked
                validateattributes(plan.oocvIndex,{'numeric'},{'scalar','integer','positive'});
                spec.oocvIndex = plan.oocvIndex;
            end
            spec.operationMode = effective;
            spec.requestedOperationMode = requested;
            spec.devMode = false;
            if gridVisible
                spec.hideGrid = false;
                spec.gridAction = NMMLIRunnerUI.requestGridAct(plan, NM, idx);
            else
                spec.hideGrid = true;
                if isfield(NM.analysis{idx},'GDdims') && ~isempty(NM.analysis{idx}.GDdims) && isfield(NM.analysis{idx}.GDdims{1},'GridAct')
                    spec.gridAction = logical(NM.analysis{idx}.GDdims{1}.GridAct);
                else
                    spec.gridAction = 'analysis';
                end
            end
            if strcmp(manualMode,'mlidatamat')
                if isfield(manualFiles,'mliDataMasterFile') && ~isempty(manualFiles.mliDataMasterFile)
                    spec.mliDataMasterFile = char(string(manualFiles.mliDataMasterFile));
                elseif isfield(manualFiles,'mliDataFiles') && ~isempty(manualFiles.mliDataFiles)
                    spec.mliDataFiles = cellstr(manualFiles.mliDataFiles);
                else
                    error('NMMLIRunnerUI:missingManualMLIDataFile', 'Pick an MLIdatamat master or CV2-level MLIdatamat artifact, or set manual override to None.');
                end
            end
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                spec.UI = plan.runtimeUI;
            end
        end

        function opts = optionsFromPlan(plan)
            opts = NMMLIRuntimeTools.defaultOptions();
            if isstruct(plan) && isfield(plan,'options') && isstruct(plan.options)
                f = intersect(fieldnames(plan.options),fieldnames(opts),'stable');
                for i=1:numel(f), opts.(f{i}) = plan.options.(f{i}); end
            end
        end

        function G = requestGridAct(plan, NM, idx)
            if isstruct(plan) && isfield(plan,'gridAction') && ~isempty(plan.gridAction)
                G = logical(plan.gridAction);
            elseif isfield(NM.analysis{idx},'GDdims') && ~isempty(NM.analysis{idx}.GDdims) && isfield(NM.analysis{idx}.GDdims{1},'GridAct')
                G = logical(NM.analysis{idx}.GDdims{1}.GridAct);
            else
                [ix,jx] = size(NM.analysis{idx}.params.cv.TrainInd);
                G = true(ix,jx);
            end
        end

        function out = generateRuntimeScript(NM, plan)
            indices = NMMLIRunnerUI.normalizeIndexVector(plan.analysisIndices);
            if isempty(indices)
                error('NMMLIRunnerUI:noAnalysisSelected', 'Select at least one trained analysis before generating a runtime script.');
            end
            opts = NMMLIRunnerUI.optionsFromPlan(plan);
            gridVisible = isfield(plan,'gridVisible') && logical(plan.gridVisible);
            gridHiddenByLegacyRule = isfield(plan,'gridHiddenByLegacyRule') && logical(plan.gridHiddenByLegacyRule);
            if ~gridVisible && ~gridHiddenByLegacyRule
                gridInfo = NMMLIRuntimeTools.gridStateForSelection(NM, indices);
                gridVisible = logical(gridInfo.visible);
            end
            if exist('NMAnalysisManagerTools','class') == 8, list = NMAnalysisManagerTools.listAnalyses(NM); else, list = struct(); end
            scripts = {};
            for k=1:numel(indices)
                idx = indices(k);
                spec = NMMLIRunnerUI.buildMLISpec(NM, plan, opts, idx, gridVisible, numel(indices));
                rootdir = NMMLIRunnerUI.analysisRootFromList(list, NM, idx);
                analysisId = NMMLIRunnerUI.analysisIdFromList(list, NM, idx);
                if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                    error('NMMLIRunnerUI:noAnalysisRoot', 'Analysis %d has no accessible root directory; cannot write a runtime script.', idx);
                end
                suffix = '';
                if NM.defs.analyses_locked, suffix = sprintf('_OOCV_%d', plan.oocvIndex); end
                fpath = fullfile(rootdir, sprintf('NM_interpret_analysis_%d%s.m', idx, suffix));
                NMMLIRunnerUI.writeTextFile(fpath, NMMLIRunnerUI.scriptTextForSpec(idx, analysisId, spec));
                scripts{end+1} = struct('analysisIndex',idx,'id',analysisId,'path',fpath); %#ok<AGROW>
            end
            out = struct('ok',true,'message',sprintf('Generated %d ML-interpretation runtime script(s).', numel(scripts)),'scripts',{scripts});
        end

        function txt = scriptTextForSpec(idx, analysisId, spec)
            specLiteral = NMMLIRunnerUI.structLiteral(spec, 'spec');
            txt = sprintf(['%% NeuroMiner runtime script -- generated by the ML-interpretation runner\n' ...
                '%% Analysis: %d (%s)\n' ...
                '%% This script reproduces the browser configuration by calling the public API.\n\n' ...
                'if ~exist(''NM'',''var'')\n' ...
                '    error(''This script needs your NeuroMiner project struct in the workspace as NM.'');\n' ...
                'end\n\n' ...
                '%s\n' ...
                '[NM, mliOut] = NMRunTools.interpretModels(NM, %d, spec);\n' ...
                'disp(mliOut.message);\n'], idx, analysisId, specLiteral, idx);
        end

        function rootdir = analysisRootFromList(list, NM, idx)
            rootdir = '';
            if isstruct(list) && isfield(list,'rootdirs') && numel(list.rootdirs) >= idx, rootdir = char(string(list.rootdirs{idx})); end
            if isempty(rootdir) && isfield(NM.analysis{idx},'rootdir'), rootdir = char(string(NM.analysis{idx}.rootdir)); end
        end

        function id = analysisIdFromList(list, NM, idx)
            id = sprintf('Analysis %d', idx);
            if isstruct(list) && isfield(list,'ids') && numel(list.ids) >= idx, id = char(string(list.ids{idx})); end
            if isempty(id) && isfield(NM.analysis{idx},'id'), id = char(string(NM.analysis{idx}.id)); end
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

        function txt = structLiteral(s, name)
            lines = {sprintf('%s = struct();', name)};
            f = fieldnames(s);
            for i=1:numel(f)
                val = s.(f{i});
                lines{end+1} = sprintf('%s.%s = %s;', name, f{i}, NMMLIRunnerUI.literal(val)); %#ok<AGROW>
            end
            txt = strjoin(lines, newline);
        end

        function lit = literal(v)
            if islogical(v) || isnumeric(v)
                if isempty(v), lit = '[]'; else, lit = mat2str(v); end
            elseif ischar(v) || isstring(v)
                lit = sprintf('''%s''', strrep(char(string(v)), '''', ''''''));
            elseif iscell(v)
                parts = cell(size(v));
                for i=1:numel(v), parts{i} = NMMLIRunnerUI.literal(v{i}); end
                lit = ['{' strjoin(parts(:)', ', ') '}'];
            elseif isstruct(v)
                if isempty(fieldnames(v)), lit = 'struct()'; return; end
                pairs = {};
                f = fieldnames(v);
                for i=1:numel(f), pairs{end+1} = sprintf('''%s'', %s', f{i}, NMMLIRunnerUI.literal(v.(f{i}))); end %#ok<AGROW>
                lit = ['struct(' strjoin(pairs, ', ') ')'];
            else
                lit = '[]';
            end
        end

        function msg = statusMessage(defs, workflow, analyses)
            if isstruct(defs) && isfield(defs,'analyses_locked') && defs.analyses_locked
                msg = 'OOCV ML interpretation: select a ready independent data container and trained analyses.'; return;
            end
            n = 0; for i=1:numel(analyses), if analyses(i).enabled, n=n+1; end, end
            if n < 1, msg = 'Train at least one CV2 partition successfully before running ML interpretation.';
            else, msg = sprintf('%d/%d analyses are trained and available for ML interpretation.', n, numel(analyses)); end
            if isstruct(workflow) && isfield(workflow,'message') && ~isempty(workflow.message) && n<1
                msg = sprintf('%s %s', msg, char(string(workflow.message)));
            end
        end

        function op = requestOperation(req)
            op=''; if isstruct(req) && isfield(req,'operation') && ~isempty(req.operation), op=char(string(req.operation)); elseif isstruct(req) && isfield(req,'action') && ~isempty(req.action), op=char(string(req.action)); end
        end



        function tag = assetCacheTag()
            try, tag = char(matlab.lang.internal.uuid); catch, tag = char(java.util.UUID.randomUUID); end
        end
    end
end

classdef NMVisRunnerUI
% NMVisRunnerUI
% -------------------------------------------------------------------------
% Dedicated browser shell for the NeuroMiner model-visualization runtime.
% The page exposes legacy-derived dynamics, trained-analysis selection,
% VISdatamat resolver summaries, manual VISdataMaster / CV2-level VISdatamat
% selection, and execution through NMRunTools.visualizeModels.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(NM, outDir, ctx)
            % export  Create the browser visualization runner session.
            %
            % Writes the runner HTML, initial artifact/grid state and shared assets, then stores the
            % session NM for service requests. This prepares the visualization workflow page but leaves
            % actual run/script execution to the MATLAB service handler.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_vis_runner_ui'); end
            if nargin < 3, ctx = struct(); end
            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_vis_runner_ui');
            NMDataIOUI.saveSessionNM(NM, dirs.tmpDir);
            if NMUISessionTools.fastChildOpen(ctx)
                state = NMVisRunnerUI.bootstrapState(ctx);
            else
                state = NMVisRunnerUI.stateFromNM(NM, ctx);
            end
            stateJson = NMConfigTools.writeJsonAliases({fullfile(dirs.tmpDir,'vis_runner_state.json'), ...
                fullfile(dirs.tmpDir,'current_config.json'), fullfile(dirs.tmpDir,'param.json')}, state, 'Visualization runner state');
            htmlPath = fullfile(dirs.webDir, 'nm_vis_runner.html');
            NMVisRunnerUI.writeTextFile(htmlPath, NMVisRunnerUI.htmlTextFromJson(stateJson));
            NMVisRunnerUI.copyAssets(dirs.webDir);
            NMPreprocUI.writeBridge(fullfile(dirs.pyDir,'nm_bridge_server.py'));
            paths = struct('root',dirs.root, 'webRoot',dirs.webRoot, 'webDir',dirs.webDir, 'tmpDir',dirs.tmpDir, ...
                'html',htmlPath, 'visRunnerHtml',htmlPath, 'entryHtml','nm_vis_runner.html', ...
                'entryHtmlPath',htmlPath, 'state',fullfile(dirs.tmpDir,'vis_runner_state.json'));
        end

        function NM = importUpdated(NM, pathsOrWebDir, ctx)
            % importUpdated  Return the session NM after the visualization runner closes.
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
            % stateFromNM  Build artifact and option state for the visualization runner.
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
            vis = NMVisRuntimeTools.uiState(NM, struct('deferArtifactScan',deferArtifactScan));
            state = struct();
            state.page = 'vis_runner';
            state.defs = defs;
            state.workflowStatus = workflow;
            state.analyses = vis.analyses;
            state.selectedAnalysisIndices = vis.selectedAnalysisIndices;
            state.grid = vis.grid;
            state.options = vis.options;
            state.operationModes = vis.operationModes;
            state.artifactSummary = vis.artifactSummary;
            state.canRun = ~deferArtifactScan;
            state.canGenerateScript = ~deferArtifactScan;
            state.loading = false;
            state.analysesLoading = false;
            state.artifactsLoading = deferArtifactScan;
            if deferArtifactScan
                state.statusMessage = 'Loading VISdatamat artifact availability from MATLAB.';
            else
                state.statusMessage = NMVisRunnerUI.statusMessage(defs, workflow, vis.analyses);
            end
            state.executionMessage = 'Visualization execution uses NMRunTools.visualizeModels and the selected runtime state.';
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'vis_runner');
        end

        function state = bootstrapState(ctx)
            % bootstrapState  Build a minimal visualization runner state for fast navigation.
            %
            % Uses app context to render the page shell before the full artifact resolver runs. The
            % complete state is requested immediately through the MATLAB bridge.

            if nargin < 1, ctx = struct(); end
            defs = struct('import_finished',false,'analyses_locked',false);
            workflow = struct('ok',true,'message','Visualization runner is loading the current NeuroMiner state.');
            grid = struct('visible',false, 'hiddenByLegacyRule',false, 'proceedAllowed',false, ...
                'reason','Loading visualization grid state from MATLAB.', 'ix',0, 'jx',0, ...
                'state',struct(), 'GridAct',false(0,0));
            state = struct();
            state.page = 'vis_runner';
            state.defs = defs;
            state.workflowStatus = workflow;
            state.analyses = [];
            state.selectedAnalysisIndices = [];
            state.grid = grid;
            state.options = struct();
            state.operationModes = [];
            state.artifactSummary = [];
            state.canRun = false;
            state.canGenerateScript = false;
            state.loading = true;
            state.analysesLoading = true;
            state.artifactsLoading = true;
            state.statusMessage = 'Loading analyses...';
            state.executionMessage = 'Visualization execution uses NMRunTools.visualizeModels and the selected runtime state.';
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'vis_runner');
        end

        function [handled, out] = handleMatlabService(NM, req, tmpDir, ctx)
            % handleMatlabService  Dispatch visualization runner service requests.
            %
            % Handles refresh, artifact resolution, run and script-generation operations by loading
            % session NM and delegating to NMVisRuntimeTools. Responses include updated runner state and
            % explicit diagnostics for the browser message strip.

            handled = false; out = struct(); if nargin < 4, ctx = struct(); end
            op = NMVisRunnerUI.requestOperation(req); if isempty(op), return; end
            switch lower(op)
                case {'vis_runner_refresh','vis_runner_state'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    state = NMVisRunnerUI.stateFromNM(sessionNM, ctx);
                    out = struct('ok',true,'message','Visualization runner state refreshed.','operation',op,'state',state);
                case {'vis_runner_refresh_light','vis_runner_state_light'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    state = NMVisRunnerUI.stateFromNM(sessionNM, ctx, struct('deferArtifactScan',true));
                    out = struct('ok',true,'message','Analyses loaded. VISdatamat availability is still being resolved.','operation',op,'state',state);
                case {'vis_runner_pick_artifact'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    try
                        out = NMVisRunnerUI.pickVISDataFile(sessionNM, req);
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Selecting a VISdatamat file failed.', 2);
                    end
                case {'vis_runner_run'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    plan = struct();
                    try
                        plan = NMVisRunnerUI.requestPlan(req);
                        plan = NMVisRunnerUI.attachRuntimeProgressContext(plan, req, tmpDir);
                        [sessionNM, runOut] = NMVisRunnerUI.runVisualization(sessionNM, plan);
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMVisRunnerUI.stateFromNM(sessionNM, ctx);
                        out = struct('ok',true,'message',runOut.message,'operation',op,'state',state,'result',runOut);
                    catch ME % nm2-allow: Runtime progress is closed and NMUIErrorTools reports the caught exception
                        NMVisRunnerUI.failRuntimeProgressIfPresent(plan, ME, 'Visualization progress failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Running model visualization failed.', 2);
                    end
                case {'vis_runner_generate_script'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    plan = struct();
                    try
                        plan = NMVisRunnerUI.requestPlan(req);
                        genOut = NMVisRunnerUI.generateRuntimeScript(sessionNM, plan);
                        out = struct('ok',true,'message',genOut.message,'operation',op,'scripts',{genOut.scripts});
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Generating the visualization runtime script failed.', 2);
                    end
                otherwise
                    handled = true;
                    out = struct('ok',false,'message',sprintf('Unsupported visualization-runner operation: %s', op), ...
                        'error',sprintf('Unsupported visualization-runner operation: %s', op));
            end
        end

        function txt = htmlTextFromJson(stateJson)
            % htmlTextFromJson  Build the visualization runner HTML shell.
            %
            % Creates the static page frame, embeds the state reference and loads shared
            % runner/grid-picker/navigation assets. All scientific/runtime decisions remain in
            % MATLAB-side service calls.

            jsState = NMPreprocUI.jsonTextForScript(stateJson);
            assetTag = NMVisRunnerUI.assetCacheTag(); nl = newline;
            L = { ...
'<!doctype html>'
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
'<title>NeuroMiner model visualization runner</title>'
['<link rel="stylesheet" href="NMTrainTemplateUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModuleNavigationRail.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisManagerUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMRuntimeGridPicker.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModal.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisCardSelector.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMManualArtifactFileList.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMRuntimeProgressViewer.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMVisRunnerUI.css?v=' assetTag '">']
['<style>' NMUIMessageTools.css() '</style>']
'</head><body class="nmHasNavRail">'
'<header>'
'  <div><div class="crumb">Main interface / post-training discovery</div><div class="title">Model visualization</div></div>'
'  <div class="headerActions"><button id="finish" class="primary" type="button">Finish / close</button></div>'
'</header>'
'<main class="wrap visWrap"><section class="panel visPanel">'
'  <div class="visPanelHead"><div><h1>Configure NeuroMiner model visualization</h1></div></div>'
'  <div class="visLayout">'
'    <section class="card visConfigPanel">'
'      <div class="visSectionHeader"><h2>Runtime configuration</h2><span id="selectedSummary" class="muted"></span></div>'
'      <div id="artifactSummary" class="nmRuntimeArtifactSummary visArtifactSummary"></div>'
'      <div class="field"><label class="nmRunnerSectionTitle" for="operationMode">Visualization input stage</label><select id="operationMode"><option value="auto">Auto: scratch/resume using legacy VISdatamat state</option><option value="scratch">Compute from scratch</option><option value="visdatamat">Use existing VISdataMaster / VISdatamats</option></select><div id="modeHelp" class="help"></div></div>'
'      <div id="manualArtifactField" class="field"><label class="nmRunnerSectionTitle" for="manualArtifactMode">Manual VISdata artifact override</label><div class="visArtifactOverride"><select id="manualArtifactMode"><option value="none">None — use automatic resolver</option><option value="visdatamat">Select VISdataMaster or CV2 VISdatamats</option></select><button id="pickArtifactFile" type="button">Pick file(s)…</button></div><div id="manualArtifactSummary" class="help">No manual VISdata artifact selected.</div></div>'
'      <div id="scratchOptions" class="field visOptionGroup"><label class="nmRunnerSectionTitle">Visualization artifact handling</label><label><input id="overwriteExisting" type="checkbox"> Overwrite existing VISdatamat outputs</label><label><input id="operateAtCV1" type="checkbox"> Operate at CV1 level</label><label><input id="saveParameters" type="checkbox"> Save newly computed preprocessing/model parameters</label><label><input id="loadParameters" type="checkbox"> Reuse saved preprocessing/model parameters</label></div>'
'      <div id="mapOptions" class="field hidden"><label><input id="writeCV2Maps" type="checkbox"> Write CV2-level CVR and consistency maps to disk</label></div>'
'      <div class="field"><label class="nmRunnerSectionTitle" for="cvrNorm">CVR normalization</label><select id="cvrNorm"><option value="sd">Use standard deviation</option><option value="sem">Use SEM</option></select></div>'
'      <div id="decompOptions" class="field hidden"><label><input id="decompMode" type="checkbox"> Back-project factorization components separately</label><div id="decompAdvanced" class="visNestedOptions hidden"><label>Similarity method <select id="simCorrMethod"><option>spearman</option><option>pearson</option><option>pearson_dice</option><option>cosine</option><option>euclidean</option><option>bicor</option></select></label><label>Realignment threshold <input id="simCorrThresh" type="number" min="0" max="1" step="0.01" value="0.5"></label><label>Component similarity cutoff <input id="corrCompCutoff" type="number" min="0" max="1" step="0.01" value="0.3"></label><label>Component presence cutoff <input id="selCompCutoff" type="number" min="0" max="1" step="0.01" value="0.1"></label><label>Pruning mode <select id="pruneMode"><option value="fraction">fraction</option><option value="ram">ram</option></select></label><label>Pruning fraction <input id="pruneFraction" type="number" min="0" max="1" step="0.01" value="0.30"></label></div></div>'
'      <div id="lowMemoryField" class="field"><label><input id="lowMemory" type="checkbox"> Low-memory mode</label></div>'
'      <div id="extraLabelNote" class="field hidden"><label>Extra-label visualization</label><div class="help">Available in the legacy backend for this analysis, but the browser extra-label editor is not yet implemented.</div></div>'
'      <div id="gridSection" class="field"><label class="nmRunnerSectionTitle">CV2 partitions</label><div id="gridReason" class="help"></div><div id="gridPicker"></div></div>'
'      <div id="gridHiddenNote" class="field hidden"><label class="nmRunnerSectionTitle">CV2 partitions</label><div class="help">The CV2 grid picker is hidden by the legacy visualization rule. Each selected analysis will use its trained CV2 cells.</div></div>'
'      <div class="actions visRunRow"><button id="runVisualization" class="primary nmActionButton" type="button" disabled>Run visualization</button><button id="generateRuntimeScript" class="nmActionButton" type="button" disabled>Generate runtime script</button></div>'
'      <div id="runHint" class="help"></div>'
'    </section>'
'    <section class="card visAnalysisPanel"><div class="visSectionHeader"><h2>Analyses</h2><span class="muted">Select one or more trained analyses</span></div><div id="analysisList" class="visAnalysisList"></div></section>'
'  </div>'
'</section></main>'
['<script>window.NM_VIS_RUNNER_STATE = ' jsState ';</script>']
['<script>' NMUIMessageTools.script() '</script>']
['<script>window.NM_MODULE_NAV_CONTEXT = {currentModule:"visualization"};</script>']
['<script src="NMRuntimeGridPicker.js?v=' assetTag '"></script>']
['<script src="NMModal.js?v=' assetTag '"></script>']
['<script src="NMAnalysisCardSelector.js?v=' assetTag '"></script>']
['<script src="NMManualArtifactFileList.js?v=' assetTag '"></script>']
['<script src="NMRuntimeProgressViewer.js?v=' assetTag '"></script>']
['<script src="NMRuntimeJobClient.js?v=' assetTag '"></script>']
['<script src="NMModuleIconSet.js?v=' assetTag '"></script>']
['<script src="NMModuleNavigationRail.js?v=' assetTag '"></script>']
['<script src="NMRunnerStateManager.js?v=' assetTag '"></script>']
['<script src="NMVisRunnerUI_main.js?v=' assetTag '"></script>']
'</body></html>'};
            txt = strjoin(L, nl);
        end

        function copyAssets(webDir)
            % copyAssets  Copy static assets for the visualization runner page.
            %
            % Copies runner JavaScript/CSS plus shared navigation, icon, picker and message-strip assets
            % into the exported web directory. It keeps page export self-contained for the bridge.

            src = fileparts(which('NMVisRunnerUI.m'));
            files = {'NMVisRunnerUI.css','NMRunnerStateManager.js','NMVisRunnerUI_main.js','NMRuntimeGridPicker.js','NMRuntimeGridPicker.css', ...
                'NMModal.js','NMModal.css','NMAnalysisCardSelector.js','NMAnalysisCardSelector.css', ...
                'NMManualArtifactFileList.js','NMManualArtifactFileList.css','NMRuntimeProgressViewer.js','NMRuntimeProgressViewer.css','NMRuntimeJobClient.js', ...
                'NMTrainTemplateUI.css','NMModuleIconSet.js','NMModuleNavigationRail.js','NMModuleNavigationRail.css','NMAnalysisManagerUI.css'};
            for i=1:numel(files)
                s = fullfile(src, files{i}); if exist(s,'file'), copyfile(s, fullfile(webDir, files{i}), 'f'); end
            end
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the visualization runner text-writer entry point.
            %
            %   NMVisRunnerUI.writeTextFile(path,txt) delegates generated visualization-runner HTML or
            %   script text output to NMSerializationTools while retaining runner-specific diagnostics.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMVisRunnerUI:writeFailed', 'Could not write %s', 'fwrite-input-char');
        end
    end

    methods (Static, Access=private)
        function plan = attachRuntimeProgressContext(plan, req, tmpDir)
            taskId = NMVisRunnerUI.requestChar(req, 'progressTaskId', '');
            if isempty(taskId) && isstruct(req) && isfield(req,'extra') && isstruct(req.extra)
                taskId = NMVisRunnerUI.requestChar(req.extra, 'progressTaskId', '');
            end
            if isempty(taskId)
                return;
            end
            minInterval = NMVisRunnerUI.requestNumeric(req, 'progressChartMinIntervalSeconds', 0.15);
            if isstruct(req) && isfield(req,'extra') && isstruct(req.extra)
                minInterval = NMVisRunnerUI.requestNumeric(req.extra, 'progressChartMinIntervalSeconds', minInterval);
            end
            plan.runtimeUI = NMRuntimeProgressTools.browserRuntimeContext(tmpDir, taskId, ...
                struct('source','vis_runner', 'chartEnabled',true, ...
                    'suppressNativeViewer',true, 'chartMinIntervalSeconds',minInterval, ...
                    'progressTitle','Model visualization progress', 'progressLowerTitle','Visualization progress'));
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
        end

        function [NM, out] = runVisualization(NM, plan)
            indices = NMVisRunnerUI.normalizeIndexVector(plan.analysisIndices);
            if isempty(indices)
                error('NMVisRunnerUI:noAnalysisSelected', 'Select at least one trained analysis before running visualization.');
            end
            opts = NMVisRunnerUI.optionsFromPlan(plan);
            gridVisible = isfield(plan,'gridVisible') && logical(plan.gridVisible);
            gridHiddenByLegacyRule = isfield(plan,'gridHiddenByLegacyRule') && logical(plan.gridHiddenByLegacyRule);
            if ~gridVisible && ~gridHiddenByLegacyRule
                gridInfo = NMVisRuntimeTools.gridStateForSelection(NM, indices);
                gridVisible = logical(gridInfo.visible);
            end
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                NMRuntimeProgressTools.start(plan.runtimeUI, 'Model visualization progress', 'Preparing visualization runtime.');
            end
            results = cell(1,numel(indices));
            for k = 1:numel(indices)
                idx = indices(k);
                spec = NMVisRunnerUI.buildVisualizeSpec(NM, plan, opts, idx, gridVisible, numel(indices));
                [NM, runOut] = NMRunTools.visualizeModels(NM, idx, spec);
                results{k} = runOut;
            end
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                NMRuntimeProgressTools.finish(plan.runtimeUI, 'Model visualization completed.', 'Model visualization progress');
            end
            out = struct('ok',true,'message',sprintf('Model visualization completed for %d analysis/analyses.', numel(indices)), ...
                'analysisIndices',indices,'results',{results});
        end

        function spec = buildVisualizeSpec(NM, plan, opts, idx, gridVisible, nSelected)
            if nargin < 6 || isempty(nSelected), nSelected = numel(NMVisRunnerUI.normalizeIndexVector(plan.analysisIndices)); end
            requested = NMVisRunnerUI.safeMode(NMVisRunnerUI.fieldOr(opts,'operationMode','auto'), 'auto');
            manualMode = NMVisRunnerUI.safeMode(NMVisRunnerUI.fieldOr(opts,'manualArtifactMode','none'), 'none');
            manualFiles = struct(); if isfield(opts,'manualFiles') && isstruct(opts.manualFiles), manualFiles = opts.manualFiles; end
            if ~strcmp(manualMode,'none') && nSelected > 1
                error('NMVisRunnerUI:manualArtifactMultiAnalysis', 'Manual VISdata artifact override is only supported for one selected analysis at a time.');
            end
            if ~strcmp(manualMode,'none')
                effective = 'visdatamat';
            elseif strcmp(requested,'auto')
                % Browser Auto is the legacy scratch/resume mode: lfl=1 with
                % overwrite=false reuses existing VISdatamat files and computes
                % missing selected CV2 cells. The generated script stores this
                % effective mode for reproducibility while retaining the
                % requestedOperationMode metadata.
                effective = 'scratch';
            else
                effective = requested;
            end
            spec = struct();
            spec.operationMode = effective;
            spec.requestedOperationMode = requested;
            spec.manualArtifactMode = manualMode;
            spec.overwrite = logical(NMVisRunnerUI.fieldOr(opts,'overwrite',false));
            spec.operateAtCV1 = logical(NMVisRunnerUI.fieldOr(opts,'operateAtCV1',false));
            spec.saveParameters = logical(NMVisRunnerUI.fieldOr(opts,'saveParameters',false));
            spec.loadParameters = logical(NMVisRunnerUI.fieldOr(opts,'loadParameters',false));
            spec.writeCV2Maps = logical(NMVisRunnerUI.fieldOr(opts,'writeCV2Maps',false));
            spec.cvrNorm = char(string(NMVisRunnerUI.fieldOr(opts,'cvrNorm','sd')));
            spec.decompMode = logical(NMVisRunnerUI.fieldOr(opts,'decompMode',false));
            spec.lowMemory = logical(opts.lowMemory);
            spec.simCorrMethod = char(string(NMVisRunnerUI.fieldOr(opts,'simCorrMethod','spearman')));
            spec.simCorrThresh = double(NMVisRunnerUI.fieldOr(opts,'simCorrThresh',0.5));
            spec.corrCompCutoff = double(NMVisRunnerUI.fieldOr(opts,'corrCompCutoff',0.3));
            spec.selCompCutoff = double(NMVisRunnerUI.fieldOr(opts,'selCompCutoff',0.1));
            spec.pruneMode = char(string(NMVisRunnerUI.fieldOr(opts,'pruneMode','fraction')));
            spec.pruneFraction = double(NMVisRunnerUI.fieldOr(opts,'pruneFraction',0.30));
            spec.devMode = false;
            if gridVisible
                spec.hideGrid = false;
                spec.gridAction = NMVisRunnerUI.requestGridAct(plan, NM, idx);
            else
                spec.hideGrid = true;
                if isfield(NM.analysis{idx},'GDdims') && ~isempty(NM.analysis{idx}.GDdims) && isfield(NM.analysis{idx}.GDdims{1},'GridAct')
                    spec.gridAction = logical(NM.analysis{idx}.GDdims{1}.GridAct);
                else
                    spec.gridAction = 'analysis';
                end
            end
            if strcmp(manualMode,'visdatamat')
                if isfield(manualFiles,'visDataMasterFile') && ~isempty(manualFiles.visDataMasterFile)
                    spec.visDataMasterFile = char(string(manualFiles.visDataMasterFile));
                elseif isfield(manualFiles,'visDataFiles') && ~isempty(manualFiles.visDataFiles)
                    spec.visDataFiles = cellstr(manualFiles.visDataFiles);
                else
                    error('NMVisRunnerUI:missingManualVISDataFile', 'Pick a VISdataMaster or CV2-level VISdatamat artifact, or set manual override to None.');
                end
            end
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                spec.UI = plan.runtimeUI;
            end
        end

        function opts = optionsFromPlan(plan)
            opts = NMVisRuntimeTools.defaultOptions();
            if isstruct(plan) && isfield(plan,'options') && isstruct(plan.options)
                f = fieldnames(plan.options);
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
            indices = NMVisRunnerUI.normalizeIndexVector(plan.analysisIndices);
            if isempty(indices)
                error('NMVisRunnerUI:noAnalysisSelected', 'Select at least one trained analysis before generating a runtime script.');
            end
            opts = NMVisRunnerUI.optionsFromPlan(plan);
            gridVisible = isfield(plan,'gridVisible') && logical(plan.gridVisible);
            gridHiddenByLegacyRule = isfield(plan,'gridHiddenByLegacyRule') && logical(plan.gridHiddenByLegacyRule);
            if ~gridVisible && ~gridHiddenByLegacyRule
                gridInfo = NMVisRuntimeTools.gridStateForSelection(NM, indices);
                gridVisible = logical(gridInfo.visible);
            end
            if exist('NMAnalysisManagerTools','class') == 8, list = NMAnalysisManagerTools.listAnalyses(NM); else, list = struct(); end
            scripts = {};
            for k=1:numel(indices)
                idx = indices(k);
                spec = NMVisRunnerUI.buildVisualizeSpec(NM, plan, opts, idx, gridVisible, numel(indices));
                rootdir = NMVisRunnerUI.analysisRootFromList(list, NM, idx);
                analysisId = NMVisRunnerUI.analysisIdFromList(list, NM, idx);
                if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                    error('NMVisRunnerUI:noAnalysisRoot', 'Analysis %d has no accessible root directory; cannot write a runtime script.', idx);
                end
                fpath = fullfile(rootdir, sprintf('NM_visualize_analysis_%d.m', idx));
                NMVisRunnerUI.writeTextFile(fpath, NMVisRunnerUI.scriptTextForSpec(idx, analysisId, spec));
                scripts{end+1} = struct('analysisIndex',idx,'id',analysisId,'path',fpath); %#ok<AGROW>
            end
            out = struct('ok',true,'message',sprintf('Generated %d visualization runtime script(s).', numel(scripts)),'scripts',{scripts});
        end

        function txt = scriptTextForSpec(idx, analysisId, spec)
            specLiteral = NMVisRunnerUI.structLiteral(spec, 'spec');
            txt = sprintf(['%% NeuroMiner runtime script -- generated by the model visualization runner\n' ...
                '%% Analysis: %d (%s)\n' ...
                '%% This script reproduces the browser configuration by calling the public API.\n\n' ...
                'if ~exist(''NM'',''var'')\n' ...
                '    error(''This script needs your NeuroMiner project struct in the workspace as NM.'');\n' ...
                'end\n\n' ...
                '%s\n' ...
                '[NM, visOut] = NMRunTools.visualizeModels(NM, %d, spec);\n' ...
                'disp(visOut.message);\n'], idx, analysisId, specLiteral, idx);
        end

        function rootdir = analysisRootFromList(list, NM, idx)
            rootdir = '';
            try
                if isstruct(list) && isfield(list,'rootdirs') && numel(list.rootdirs) >= idx, rootdir = char(string(list.rootdirs{idx})); end
            catch, rootdir = ''; end
            if isempty(rootdir)
                try, rootdir = char(string(NM.analysis{idx}.rootdir)); catch, rootdir = ''; end
            end
        end

        function id = analysisIdFromList(list, NM, idx)
            id = sprintf('Analysis %d', idx);
            try
                if isstruct(list) && isfield(list,'ids') && numel(list.ids) >= idx, id = char(string(list.ids{idx})); end
            catch, id = sprintf('Analysis %d', idx); end
            if isempty(id)
                try, id = char(string(NM.analysis{idx}.id)); catch, id = sprintf('Analysis %d', idx); end
            end
        end

        function mode = safeMode(x, default)
            mode = lower(strtrim(char(string(x)))); if isempty(mode), mode = default; end
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
                lines{end+1} = sprintf('%s.%s = %s;', name, f{i}, NMVisRunnerUI.literal(val)); %#ok<AGROW>
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
                for i=1:numel(v), parts{i} = NMVisRunnerUI.literal(v{i}); end
                lit = ['{' strjoin(parts(:)', ', ') '}'];
            elseif isstruct(v)
                if isempty(fieldnames(v)), lit = 'struct()'; return; end
                pairs = {};
                f = fieldnames(v);
                for i=1:numel(f), pairs{end+1} = sprintf('''%s'', %s', f{i}, NMVisRunnerUI.literal(v.(f{i}))); end %#ok<AGROW>
                lit = ['struct(' strjoin(pairs, ', ') ')'];
            else
                lit = '[]';
            end
        end

        function msg = statusMessage(defs, workflow, analyses)
            if isstruct(defs) && isfield(defs,'analyses_locked') && defs.analyses_locked
                msg = 'Visualization is a discovery-stage module and is disabled in application/OOCV mode.'; return;
            end
            n = 0; for i=1:numel(analyses), if analyses(i).enabled, n=n+1; end, end
            if n < 1, msg = 'Train at least one CV2 partition successfully before running model visualization.';
            else, msg = sprintf('%d/%d analyses are trained and available for visualization-state inspection.', n, numel(analyses)); end
            if isstruct(workflow) && isfield(workflow,'message') && ~isempty(workflow.message) && n<1
                msg = sprintf('%s %s', msg, char(string(workflow.message)));
            end
        end
        function out = pickVISDataFile(~, ~)
            % Deprecated: runner pages now use /api/pickpath directly so the
            % OS-native picker supports multi-file selection and shared bridge
            % behavior.
            out = struct('ok',false,'message','Manual VISdata artifact selection is handled by the browser OS file picker (/api/pickpath).', ...
                'cancelled',false,'deprecated',true);
        end

        function filters = visFilters(dataId)
            rows = {};
            if ~isempty(dataId), rows(end+1,:) = {sprintf('*VISdatamat*ID%s*.mat', dataId), 'Matching CV2-level VISdatamat for this NM.id'}; end %#ok<AGROW>
            rows(end+1,:) = {'*VISdatamat*.mat','CV2-level VISdatamat MAT files'};
            rows(end+1,:) = {'*.mat','All MAT files'};
            filters = rows;
        end
        function v = requestChar(req, field, default)
            if nargin < 3, default = ''; end
            v = default;
            if isstruct(req) && isfield(req,field) && ~isempty(req.(field))
                v = char(string(req.(field)));
            end
        end
        function v = requestNumeric(req, field, default)
            if nargin < 3, default = NaN; end
            v = default;
            if isstruct(req) && isfield(req,field) && ~isempty(req.(field))
                tmp = double(req.(field));
                if isscalar(tmp) && isfinite(tmp), v = tmp; end
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

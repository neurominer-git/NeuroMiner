classdef NMModelExportRunnerUI
% NMModelExportRunnerUI
% -------------------------------------------------------------------------
% Dedicated browser shell for exporting optimized NeuroMiner model and
% preprocessing parameters through NMRunTools.exportModels.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(NM, outDir, ctx)
            % export  Create the browser model export runner session.
            %
            % Writes the runner HTML, initial artifact/grid state and shared assets, then stores the
            % session NM for service requests. This prepares the model export workflow page but leaves
            % actual run/script execution to the MATLAB service handler.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_model_export_runner_ui'); end
            if nargin < 3, ctx = struct(); end
            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_model_export_runner_ui');
            NMDataIOUI.saveSessionNM(NM, dirs.tmpDir);
            if NMUISessionTools.fastChildOpen(ctx)
                state = NMModelExportRunnerUI.bootstrapState(ctx);
            else
                state = NMModelExportRunnerUI.stateFromNM(NM, ctx);
            end
            stateJson = NMConfigTools.writeJsonAliases({fullfile(dirs.tmpDir,'model_export_runner_state.json'), ...
                fullfile(dirs.tmpDir,'current_config.json'), fullfile(dirs.tmpDir,'param.json')}, state, 'Model export runner state');
            htmlPath = fullfile(dirs.webDir, 'nm_model_export_runner.html');
            NMModelExportRunnerUI.writeTextFile(htmlPath, NMModelExportRunnerUI.htmlTextFromJson(stateJson));
            NMModelExportRunnerUI.copyAssets(dirs.webDir);
            NMPreprocUI.writeBridge(fullfile(dirs.pyDir,'nm_bridge_server.py'));
            paths = struct('root',dirs.root, 'webRoot',dirs.webRoot, 'webDir',dirs.webDir, 'tmpDir',dirs.tmpDir, ...
                'html',htmlPath, 'modelExportRunnerHtml',htmlPath, 'entryHtml','nm_model_export_runner.html', ...
                'entryHtmlPath',htmlPath, 'state',fullfile(dirs.tmpDir,'model_export_runner_state.json'));
        end

        function NM = importUpdated(NM, pathsOrWebDir, ctx)
            % importUpdated  Return the session NM after the model export runner closes.
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
            % stateFromNM  Build artifact and option state for the model export runner.
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
            exportState = NMModelExportRuntimeTools.uiState(NM, struct('deferArtifactScan',deferArtifactScan));
            state = struct();
            state.page = 'model_export_runner';
            state.defs = defs;
            state.workflowStatus = workflow;
            state.analyses = exportState.analyses;
            if exist('NMAnalysisManagerTools','class') == 8
                state.analysisList = NMAnalysisManagerTools.listAnalyses(NM);
            else
                state.analysisList = struct();
            end
            state.selectedAnalysisIndices = exportState.selectedAnalysisIndices;
            state.grid = exportState.grid;
            state.options = exportState.options;
            state.artifactSummary = exportState.artifactSummary;
            state.dynamicControls = exportState.dynamicControls;
            state.canRun = ~deferArtifactScan && exportState.canRun;
            state.canGenerateScript = state.canRun;
            state.loading = false;
            state.analysesLoading = false;
            state.artifactsLoading = deferArtifactScan;
            if deferArtifactScan
                state.statusMessage = 'Loading export-artifact availability from MATLAB.';
            else
                state.statusMessage = NMModelExportRunnerUI.statusMessage(workflow, exportState.analyses);
            end
            state.executionMessage = 'Model export uses NMRunTools.exportModels and the selected runtime state.';
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'model_export_runner');
        end

        function state = bootstrapState(ctx)
            % bootstrapState  Build a minimal model export runner state for fast navigation.
            %
            % Uses app context to render the page shell before the full artifact resolver runs. The
            % complete state is requested immediately through the MATLAB bridge.

            if nargin < 1, ctx = struct(); end
            defs = struct('import_finished',false,'analyses_locked',false);
            workflow = struct('ok',true,'message','Model export runner is loading the current NeuroMiner state.');
            grid = struct('visible',false, 'hiddenByLegacyRule',false, 'proceedAllowed',false, ...
                'reason','Loading model-export grid state from MATLAB.', 'ix',0, 'jx',0, ...
                'state',struct(), 'GridAct',false(0,0));
            state = struct();
            state.page = 'model_export_runner';
            state.defs = defs;
            state.workflowStatus = workflow;
            state.analyses = [];
            state.analysisList = struct();
            state.selectedAnalysisIndices = [];
            state.grid = grid;
            state.options = struct();
            state.artifactSummary = [];
            state.dynamicControls = struct();
            state.canRun = false;
            state.canGenerateScript = false;
            state.loading = true;
            state.analysesLoading = true;
            state.artifactsLoading = true;
            state.statusMessage = 'Loading analyses...';
            state.executionMessage = 'Model export uses NMRunTools.exportModels and the selected runtime state.';
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'model_export_runner');
        end

        function [handled, out] = handleMatlabService(NM, req, tmpDir, ctx)
            % handleMatlabService  Dispatch model export runner service requests.
            %
            % Handles refresh, artifact resolution, run and script-generation operations by loading
            % session NM and delegating to NMModelExportRuntimeTools. Responses include updated runner
            % state and explicit diagnostics for the browser message strip.

            handled = false; out = struct(); if nargin < 4, ctx = struct(); end
            op = NMModelExportRunnerUI.requestOperation(req); if isempty(op), return; end
            switch lower(op)
                case {'model_export_runner_refresh','model_export_runner_state'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    state = NMModelExportRunnerUI.stateFromNM(sessionNM, ctx);
                    out = struct('ok',true,'message','Model export runner state refreshed.','operation',op,'state',state);
                case {'model_export_runner_refresh_light','model_export_runner_state_light'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    state = NMModelExportRunnerUI.stateFromNM(sessionNM, ctx, struct('deferArtifactScan',true));
                    out = struct('ok',true,'message','Analyses loaded. Export artifact availability is still being resolved.','operation',op,'state',state);
                case {'model_export_runner_run'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    plan = struct();
                    try
                        plan = NMModelExportRunnerUI.requestPlan(req);
                        plan = NMModelExportRunnerUI.attachRuntimeProgressContext(plan, req, tmpDir);
                        [sessionNM, runOut] = NMModelExportRunnerUI.runExport(sessionNM, plan);
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMModelExportRunnerUI.stateFromNM(sessionNM, ctx);
                        out = struct('ok',true,'message',runOut.message,'operation',op,'state',state,'result',runOut);
                    catch ME % nm2-allow: Runtime progress is closed and NMUIErrorTools reports the caught exception
                        NMModelExportRunnerUI.failRuntimeProgressIfPresent(plan, ME, 'Model export progress failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Running model export failed.', 2);
                    end
                case {'model_export_runner_generate_script'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    plan = struct();
                    try
                        plan = NMModelExportRunnerUI.requestPlan(req);
                        genOut = NMModelExportRunnerUI.generateRuntimeScript(sessionNM, plan);
                        out = struct('ok',true,'message',genOut.message,'operation',op,'scripts',{genOut.scripts});
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Generating the model-export runtime script failed.', 2);
                    end
                otherwise
                    handled = true;
                    out = struct('ok',false,'message',sprintf('Unsupported model-export runner operation: %s', op), ...
                        'error',sprintf('Unsupported model-export runner operation: %s', op));
            end
        end

        function txt = htmlTextFromJson(stateJson)
            % htmlTextFromJson  Build the model export runner HTML shell.
            %
            % Creates the static page frame, embeds the state reference and loads shared
            % runner/grid-picker/navigation assets. All scientific/runtime decisions remain in
            % MATLAB-side service calls.

            jsState = NMPreprocUI.jsonTextForScript(stateJson);
            assetTag = NMModelExportRunnerUI.assetCacheTag(); nl = newline;
            L = { ...
'<!doctype html>'
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
'<title>NeuroMiner model export</title>'
['<link rel="stylesheet" href="NMTrainTemplateUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModuleNavigationRail.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisManagerUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMRuntimeGridPicker.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModal.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisCardSelector.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMRuntimeProgressViewer.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModelExportRunnerUI.css?v=' assetTag '">']
['<style>' NMUIMessageTools.css() '</style>']
'</head><body class="nmHasNavRail">'
'<header>'
'  <div><div class="crumb">Main interface / post-training discovery</div><div class="title">Model export</div></div>'
'  <div class="headerActions"><button id="finish" class="primary" type="button">Finish / close</button></div>'
'</header>'
'<main class="wrap modelExportWrap"><section class="panel modelExportPanel">'
'  <div class="modelExportPanelHead"><div><h1>Configure NeuroMiner model export</h1><div id="modelExportStatus" class="summary modelExportStatusSummary"></div></div></div>'
'  <div class="modelExportLayout">'
'    <section class="card modelExportConfigPanel">'
'      <div class="modelExportSectionHeader"><h2>Runtime configuration</h2><span id="selectedSummary" class="muted">No analysis selected</span></div>'
'      <div id="artifactSummary" class="nmRuntimeArtifactSummary modelExportArtifactSummary"></div>'
'      <div class="field modelExportOptionGroup"><label class="nmRunnerSectionTitle">Export targets</label><label><input id="exportOptModel" type="checkbox" checked> Export optimized ML models</label><label><input id="exportOptPreproc" type="checkbox" checked> Export optimized preprocessing parameters</label></div>'
'      <div class="field modelExportOptionGroup"><label class="nmRunnerSectionTitle">Export options</label><label><input id="overwriteExisting" type="checkbox"> Overwrite existing export artifacts</label><label id="saveCV1Row"><input id="saveCV1" type="checkbox"> Save preprocessing parameters at CV1 level</label></div>'
'      <div id="gridSection" class="field"><label class="nmRunnerSectionTitle">CV2 partitions</label><div id="gridReason" class="help"></div><div id="gridPicker"></div></div>'
'      <div id="gridHiddenNote" class="field hidden"><label class="nmRunnerSectionTitle">CV2 partitions</label><div class="help">The CV2 grid picker is hidden because the selected analyses do not share the same CV2 grid. Each selected analysis will use its trained CV2 partitions.</div></div>'
'      <div class="actions modelExportRunRow"><button id="runModelExport" class="primary nmActionButton" type="button" disabled>Run model export</button><button id="generateRuntimeScript" class="nmActionButton" type="button" disabled>Generate runtime script</button></div>'
'      <div id="runHint" class="help"></div>'
'    </section>'
'    <section class="card modelExportAnalysisPanel"><div class="modelExportSectionHeader"><h2>Analyses</h2><span class="muted">Select one or more trained analyses</span></div><div id="analysisList" class="modelExportAnalysisList"></div></section>'
'  </div>'
'</section></main>'
['<script>window.NM_MODEL_EXPORT_RUNNER_STATE = ' jsState ';</script>']
['<script>' NMUIMessageTools.script() '</script>']
['<script>window.NM_MODULE_NAV_CONTEXT = {currentModule:"model_export"};</script>']
['<script src="NMRuntimeGridPicker.js?v=' assetTag '"></script>']
['<script src="NMModal.js?v=' assetTag '"></script>']
['<script src="NMAnalysisCardSelector.js?v=' assetTag '"></script>']
['<script src="NMRuntimeProgressViewer.js?v=' assetTag '"></script>']
['<script src="NMRuntimeJobClient.js?v=' assetTag '"></script>']
['<script src="NMModuleIconSet.js?v=' assetTag '"></script>']
['<script src="NMModuleNavigationRail.js?v=' assetTag '"></script>']
['<script src="NMRunnerStateManager.js?v=' assetTag '"></script>']
['<script src="NMModelExportRunnerUI_main.js?v=' assetTag '"></script>']
'</body></html>'};
            txt = strjoin(L,nl);
        end

        function copyAssets(webDir)
            % copyAssets  Copy static assets for the model export runner page.
            %
            % Copies runner JavaScript/CSS plus shared navigation, icon, picker and message-strip assets
            % into the exported web directory. It keeps page export self-contained for the bridge.

            src = fileparts(mfilename('fullpath'));
            files = {'NMModelExportRunnerUI.css','NMRunnerStateManager.js','NMModelExportRunnerUI_main.js','NMRuntimeGridPicker.js','NMRuntimeGridPicker.css', ...
                'NMModal.js','NMModal.css','NMAnalysisCardSelector.js','NMAnalysisCardSelector.css', ...
                'NMRuntimeProgressViewer.js','NMRuntimeProgressViewer.css','NMRuntimeJobClient.js','NMTrainTemplateUI.css','NMModuleIconSet.js','NMModuleNavigationRail.js','NMModuleNavigationRail.css','NMAnalysisManagerUI.css'};
            for i=1:numel(files)
                s = fullfile(src, files{i}); if exist(s,'file'), copyfile(s, fullfile(webDir, files{i}), 'f'); end
            end
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the model-export runner text-writer entry point.
            %
            %   NMModelExportRunnerUI.writeTextFile(path,txt) delegates generated model-export UI and
            %   script text output to NMSerializationTools while retaining runner-specific diagnostics.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMModelExportRunnerUI:writeFailed', 'Could not write %s', 'fwrite-input-char');
        end
    end

    methods (Static, Access=private)
        function plan = attachRuntimeProgressContext(plan, req, tmpDir)
            taskId = NMModelExportRunnerUI.requestChar(req, 'progressTaskId', '');
            if isempty(taskId) && isstruct(req) && isfield(req,'extra') && isstruct(req.extra)
                taskId = NMModelExportRunnerUI.requestChar(req.extra, 'progressTaskId', '');
            end
            if isempty(taskId), return; end
            minInterval = NMModelExportRunnerUI.requestNumeric(req, 'progressChartMinIntervalSeconds', 0.15);
            if isstruct(req) && isfield(req,'extra') && isstruct(req.extra)
                minInterval = NMModelExportRunnerUI.requestNumeric(req.extra, 'progressChartMinIntervalSeconds', minInterval);
            end
            plan.runtimeUI = NMRuntimeProgressTools.browserRuntimeContext(tmpDir, taskId, ...
                struct('source','model_export_runner', 'chartEnabled',true, ...
                    'suppressNativeViewer',true, 'chartMinIntervalSeconds',minInterval, ...
                    'progressTitle','Model export progress', 'progressLowerTitle','Model export progress'));
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

        function [NM, out] = runExport(NM, plan)
            indices = NMModelExportRunnerUI.normalizeIndexVector(plan.analysisIndices);
            if isempty(indices)
                error('NMModelExportRunnerUI:noAnalysisSelected', 'Select at least one trained analysis before exporting models.');
            end
            opts = NMModelExportRunnerUI.optionsFromPlan(plan);
            gridVisible = isfield(plan,'gridVisible') && logical(plan.gridVisible);
            gridHiddenByLegacyRule = isfield(plan,'gridHiddenByLegacyRule') && logical(plan.gridHiddenByLegacyRule);
            if ~gridVisible && ~gridHiddenByLegacyRule
                gridInfo = NMModelExportRuntimeTools.gridStateForSelection(NM, indices);
                gridVisible = logical(gridInfo.visible);
            end
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                NMRuntimeProgressTools.start(plan.runtimeUI, 'Model export progress', 'Preparing model-export runtime.');
            end
            results = cell(1,numel(indices));
            for k = 1:numel(indices)
                idx = indices(k);
                spec = NMModelExportRunnerUI.buildExportSpec(NM, plan, opts, idx, gridVisible);
                [NM, runOut] = NMRunTools.exportModels(NM, idx, spec);
                results{k} = runOut;
            end
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                NMRuntimeProgressTools.finish(plan.runtimeUI, 'Model export completed.', 'Model export progress');
            end
            out = struct('ok',true,'message',sprintf('Model export completed for %d analysis/analyses.', numel(indices)), ...
                'analysisIndices',indices,'results',{results});
        end

        function spec = buildExportSpec(NM, plan, opts, idx, gridVisible)
            spec = struct();
            spec.exportOptModel = logical(NMModelExportRunnerUI.fieldOr(opts,'exportOptModel',true));
            spec.exportOptPreproc = logical(NMModelExportRunnerUI.fieldOr(opts,'exportOptPreproc',true));
            spec.overwrite = logical(NMModelExportRunnerUI.fieldOr(opts,'overwrite',false));
            spec.saveCV1 = logical(NMModelExportRunnerUI.fieldOr(opts,'saveCV1',false));
            spec.devMode = false;
            if gridVisible
                spec.hideGrid = false;
                spec.gridAction = NMModelExportRunnerUI.requestGridAct(plan, NM, idx);
            else
                spec.hideGrid = true;
                if isfield(NM.analysis{idx},'GDdims') && ~isempty(NM.analysis{idx}.GDdims) && isfield(NM.analysis{idx}.GDdims{1},'GridAct')
                    spec.gridAction = logical(NM.analysis{idx}.GDdims{1}.GridAct);
                else
                    spec.gridAction = 'analysis';
                end
            end
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                spec.UI = plan.runtimeUI;
            end
        end

        function opts = optionsFromPlan(plan)
            opts = NMModelExportRuntimeTools.defaultOptions();
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
            indices = NMModelExportRunnerUI.normalizeIndexVector(plan.analysisIndices);
            if isempty(indices)
                error('NMModelExportRunnerUI:noAnalysisSelected', 'Select at least one trained analysis before generating a runtime script.');
            end
            opts = NMModelExportRunnerUI.optionsFromPlan(plan);
            gridVisible = isfield(plan,'gridVisible') && logical(plan.gridVisible);
            gridHiddenByLegacyRule = isfield(plan,'gridHiddenByLegacyRule') && logical(plan.gridHiddenByLegacyRule);
            if ~gridVisible && ~gridHiddenByLegacyRule
                gridInfo = NMModelExportRuntimeTools.gridStateForSelection(NM, indices);
                gridVisible = logical(gridInfo.visible);
            end
            if exist('NMAnalysisManagerTools','class') == 8, list = NMAnalysisManagerTools.listAnalyses(NM); else, list = struct(); end
            scripts = {};
            for k=1:numel(indices)
                idx = indices(k);
                spec = NMModelExportRunnerUI.buildExportSpec(NM, plan, opts, idx, gridVisible);
                rootdir = NMModelExportRunnerUI.analysisRootFromList(list, NM, idx);
                analysisId = NMModelExportRunnerUI.analysisIdFromList(list, NM, idx);
                if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                    error('NMModelExportRunnerUI:noAnalysisRoot', 'Analysis %d has no accessible root directory; cannot write a runtime script.', idx);
                end
                fpath = fullfile(rootdir, sprintf('NM_export_models_analysis_%d.m', idx));
                NMModelExportRunnerUI.writeTextFile(fpath, NMModelExportRunnerUI.scriptTextForSpec(idx, analysisId, spec));
                scripts{end+1} = struct('analysisIndex',idx,'id',analysisId,'path',fpath); %#ok<AGROW>
            end
            out = struct('ok',true,'message',sprintf('Generated %d model-export runtime script(s).', numel(scripts)),'scripts',{scripts});
        end

        function txt = scriptTextForSpec(idx, analysisId, spec)
            specLiteral = NMModelExportRunnerUI.structLiteral(spec, 'spec');
            txt = sprintf(['%% NeuroMiner runtime script -- generated by the model-export runner\n' ...
                '%% Analysis: %d (%s)\n' ...
                '%% This script reproduces the browser configuration by calling the public API.\n\n' ...
                'if ~exist(''NM'',''var'')\n' ...
                '    error(''This script needs your NeuroMiner project struct in the workspace as NM.'');\n' ...
                'end\n\n' ...
                '%s\n' ...
                '[NM, exportOut] = NMRunTools.exportModels(NM, %d, spec);\n' ...
                'disp(exportOut.message);\n'], idx, analysisId, specLiteral, idx);
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

        function lit = literal(v)
            if islogical(v) || isnumeric(v)
                if isempty(v), lit = '[]'; else, lit = mat2str(v); end
            elseif ischar(v) || isstring(v)
                lit = sprintf('''%s''', strrep(char(string(v)), '''', ''''''));
            elseif iscell(v)
                parts = cell(size(v));
                for i=1:numel(v), parts{i} = NMModelExportRunnerUI.literal(v{i}); end
                lit = ['{' strjoin(parts(:)', ', ') '}'];
            elseif isstruct(v)
                if isempty(fieldnames(v)), lit = 'struct()'; return; end
                pairs = {};
                f = fieldnames(v);
                for i=1:numel(f), pairs{end+1} = sprintf('''%s'', %s', f{i}, NMModelExportRunnerUI.literal(v.(f{i}))); end %#ok<AGROW>
                lit = ['struct(' strjoin(pairs, ', ') ')'];
            else
                lit = '[]';
            end
        end

        function txt = structLiteral(s, name)
            lines = {sprintf('%s = struct();', name)};
            f = fieldnames(s);
            for i=1:numel(f)
                lines{end+1} = sprintf('%s.%s = %s;', name, f{i}, NMModelExportRunnerUI.literal(s.(f{i}))); %#ok<AGROW>
            end
            txt = strjoin(lines, newline);
        end

        function msg = statusMessage(workflow, analyses)
            n = 0; for i=1:numel(analyses), if analyses(i).enabled, n=n+1; end, end
            if n < 1, msg = 'Train at least one CV2 partition successfully before exporting model artifacts.';
            else, msg = sprintf('%d/%d analyses are trained and available for model export.', n, numel(analyses)); end
            if isstruct(workflow) && isfield(workflow,'message') && ~isempty(workflow.message) && n<1
                msg = sprintf('%s %s', msg, char(string(workflow.message)));
            end
        end

        function op = requestOperation(req)
            op=''; if isstruct(req) && isfield(req,'operation') && ~isempty(req.operation), op=char(string(req.operation)); elseif isstruct(req) && isfield(req,'action') && ~isempty(req.action), op=char(string(req.action)); end
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

        function v = fieldOr(s, field, default)
            v = default;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field)), v = s.(field); end
        end

        function indices = normalizeIndexVector(x)
            if isempty(x), indices=[]; return; end
            if iscell(x), x=[x{:}]; end
            indices = unique(double(x(:)')); indices = indices(isfinite(indices) & indices>=1);
        end

        function tag = assetCacheTag()
            try, tag = char(matlab.lang.internal.uuid); catch, tag = char(java.util.UUID.randomUUID); end
        end
    end
end

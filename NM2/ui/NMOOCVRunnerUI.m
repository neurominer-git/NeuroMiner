classdef NMOOCVRunnerUI
% NMOOCVRunnerUI
% -------------------------------------------------------------------------
% Browser runner for applying trained NeuroMiner analyses to one explicit
% OOCV/application dataset through NMRunTools.applyOOCV.
%
% The runner deliberately consumes the existing DataIO OOCV overview
% authority (NMDataIOBrowserModeTools.oocvManagerState) rather than
% reconstructing OOCV-container metadata or import controls.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(NM, outDir, ctx)
            % export  Create the browser OOCV application-runner session.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_oocv_runner_ui'); end
            if nargin < 3, ctx = struct(); end
            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_oocv_runner_ui');
            NMDataIOUI.saveSessionNM(NM, dirs.tmpDir);
            if NMUISessionTools.fastChildOpen(ctx)
                state = NMOOCVRunnerUI.bootstrapState(ctx);
            else
                state = NMOOCVRunnerUI.stateFromNM(NM, ctx);
            end
            stateJson = NMConfigTools.writeJsonAliases({fullfile(dirs.tmpDir,'oocv_runner_state.json'), ...
                fullfile(dirs.tmpDir,'current_config.json'), fullfile(dirs.tmpDir,'param.json')}, state, 'OOCV runner state');
            htmlPath = fullfile(dirs.webDir, 'nm_oocv_runner.html');
            NMSerializationTools.writeTextFile(htmlPath, NMOOCVRunnerUI.htmlTextFromJson(stateJson), 'NMOOCVRunnerUI:writeFailed', 'Could not write %s', 'fwrite-input-char');
            NMOOCVRunnerUI.copyAssets(dirs.webDir);
            NMPreprocUI.writeBridge(fullfile(dirs.pyDir,'nm_bridge_server.py'));
            paths = struct('root',dirs.root, 'webRoot',dirs.webRoot, 'webDir',dirs.webDir, 'tmpDir',dirs.tmpDir, ...
                'html',htmlPath, 'oocvRunnerHtml',htmlPath, 'entryHtml','nm_oocv_runner.html', ...
                'entryHtmlPath',htmlPath, 'state',fullfile(dirs.tmpDir,'oocv_runner_state.json'));
        end

        function NM = importUpdated(NM, pathsOrWebDir, ctx) %#ok<INUSD>
            % importUpdated  Return the session NM after the OOCV runner closes.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(pathsOrWebDir), return; end
            tmpDir = NMDataIOUI.pathsTmpDir(pathsOrWebDir);
            if isempty(tmpDir), return; end
            [NM2, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
            if ok, NM = NM2; end
            NMDataIOUI.clearSessionNM(tmpDir);
        end

        function state = stateFromNM(NM, ctx)
            % stateFromNM  Build the OOCV runner projection from established authorities.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2, ctx = struct(); end
            defs = NMStatusGuardTools.defsState(NM);
            workflow = NMStatusGuardTools.workflowStatus(NM);
            analysisList = NMAnalysisManagerTools.listAnalyses(NM);
            analyses = NMOOCVRunnerUI.analysisCards(NM, analysisList);
            oocv = NMDataIOBrowserModeTools.oocvManagerState(NM);

            state = struct();
            state.page = 'oocv_runner';
            state.defs = defs;
            state.workflowStatus = workflow;
            state.analysisList = analysisList;
            state.analyses = analyses;
            state.oocv = oocv;
            state.readiness = NMOOCVRunnerUI.readinessPairs(NM, analyses, oocv);
            state.options = NMOOCVRunnerUI.defaultOptions();
            state.selectedAnalysisIndex = NMOOCVRunnerUI.firstEnabledAnalysis(analyses);
            state.selectedOOCVIndex = NMOOCVRunnerUI.firstOOCVIndex(oocv);
            state.artifactSummary = struct();
            state.backendAvailable = exist('NMRunTools','class') == 8 && exist('nk_OOCVPrep','file') == 2 && exist('nk_OOCV','file') == 2;
            state.canRunBase = logical(defs.analyses_locked) && state.backendAvailable && ...
                ~isempty(state.selectedAnalysisIndex) && ~isempty(state.selectedOOCVIndex);
            state.statusMessage = NMOOCVRunnerUI.statusMessage(state);
            state.executionMessage = ['Model application is executed only through NMRunTools.applyOOCV. ' ...
                'OOCV dataset metadata and readiness remain owned by DataIO.'];
            state.loading = false;
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'oocv_runner');
        end

        function state = bootstrapState(ctx)
            % bootstrapState  Build a minimal shell state for fast workbench navigation.
            if nargin < 1, ctx = struct(); end
            state = struct();
            state.page = 'oocv_runner';
            state.defs = struct('import_finished',false,'analyses_locked',false);
            state.workflowStatus = struct('ok',true,'message','Loading OOCV runner state.');
            state.analysisList = struct();
            state.analyses = struct([]);
            state.oocv = struct('containerField','OOCV','nTrainingModalities',0,'containers',struct([]), ...
                'nContainers',0,'activeIndex',[]);
            state.readiness = struct([]);
            state.options = NMOOCVRunnerUI.defaultOptions();
            state.artifactSummary = struct();
            state.selectedAnalysisIndex = [];
            state.selectedOOCVIndex = [];
            state.backendAvailable = false;
            state.canRunBase = false;
            state.statusMessage = 'Loading trained analyses and OOCV/application datasets...';
            state.executionMessage = 'Model application uses NMRunTools.applyOOCV.';
            state.loading = true;
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'oocv_runner');
        end

        function state = lightStateFromNM(NM, ctx)
            % Project the authoritative analysis list before full OOCV readiness loading.
            state = NMOOCVRunnerUI.bootstrapState(ctx);
            state.analysisList = NMAnalysisManagerTools.listAnalyses(NM);
            state.analyses = NMOOCVRunnerUI.analysisCards(NM, state.analysisList);
            state.selectedAnalysisIndex = NMOOCVRunnerUI.firstEnabledAnalysis(state.analyses);
            state.statusMessage = 'Loading OOCV/application datasets and readiness...';
        end

        function [handled, out] = handleMatlabService(NM, req, tmpDir, ctx)
            % handleMatlabService  Dispatch OOCV runner refresh, preprocessing, run and script requests.
            handled = false; out = struct(); if nargin < 4, ctx = struct(); end
            op = NMOOCVRunnerUI.requestOperation(req); if isempty(op), return; end
            switch lower(op)
                case {'oocv_runner_refresh','oocv_runner_state','oocv_runner_refresh_light'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    if strcmpi(op,'oocv_runner_refresh_light')
                        state = NMOOCVRunnerUI.lightStateFromNM(sessionNM, ctx);
                    else
                        state = NMOOCVRunnerUI.stateFromNM(sessionNM, ctx);
                        plan = NMOOCVRunnerUI.requestPlan(req,sessionNM);
                        if ~isempty(plan.artifactDir)
                            [~,state.artifactSummary] = NMRunTools.resolveOOCVDataMat(sessionNM, ...
                                plan.analysisIndex,plan.oocvIndex,plan.artifactDir,plan.options.manualFiles,plan.options);
                        end
                    end
                    out = struct('ok',true,'message','OOCV runner state refreshed.','operation',op,'state',state);
                case {'oocv_runner_run'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    plan = struct();
                    try
                        plan = NMOOCVRunnerUI.requestPlan(req,sessionNM);
                        plan = NMOOCVRunnerUI.attachRuntimeProgressContext(plan, req, tmpDir);
                        [sessionNM, runOut] = NMOOCVRunnerUI.runApplication(sessionNM, plan);
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMOOCVRunnerUI.stateFromNM(sessionNM, ctx);
                        out = struct('ok',true,'message',runOut.message,'operation',op,'state',state,'result',runOut);
                    catch ME % nm2-allow: Runtime progress is closed and NMUIErrorTools reports the caught exception
                        NMOOCVRunnerUI.failRuntimeProgressIfPresent(plan, ME);
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Running OOCV model application failed.', 2);
                    end
                case {'oocv_runner_generate_script'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    try
                        plan = NMOOCVRunnerUI.requestPlan(req,sessionNM);
                        genOut = NMOOCVRunnerUI.generateRuntimeScript(sessionNM, plan);
                        out = struct('ok',true,'message',genOut.message,'operation',op,'script',genOut.script);
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Generating the OOCV runtime script failed.', 2);
                    end
                case {'oocv_runner_prepare_preproc'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    try
                        [analind, oocvind, preprocIndex] = NMOOCVRunnerUI.requestPreprocSelection(req);
                        editor = NMOOCVApplicationPreprocTools.configuratorEditor(sessionNM, analind, oocvind, preprocIndex);
                        module = sprintf('preproc_var%d', preprocIndex);
                        NMUIStateTools.writeConfiguratorChild(tmpDir, module, editor.state);
                        specJson = NMConfigTools.writeJson(fullfile(tmpDir,[module '_spec.json']), editor.spec);
                        stateJson = NMConfigTools.writeJson(fullfile(tmpDir,[module '_param.json']), editor.state);
                        workspaceJson = '[]';
                        workspacePath = fullfile(tmpDir,'workspace.json');
                        if exist(workspacePath,'file') == 2, workspaceJson = fileread(workspacePath); end
                        webDir = fileparts(tmpDir);
                        if isstruct(ctx) && isfield(ctx,'NMAppSharedSession') && logical(ctx.NMAppSharedSession) && ...
                                isfield(ctx,'NMAppWebDir') && ~isempty(ctx.NMAppWebDir)
                            webDir = char(string(ctx.NMAppWebDir));
                        end
                        childHtml = fullfile(webDir,'nm_preproc_pipeline_ui.html');
                        NMPreprocUI.writeHtmlFromJson(childHtml, specJson, stateJson, workspaceJson);
                        out = struct('ok',true,'message','OOCV application preprocessing editor prepared.', ...
                            'operation',op,'module',module,'editor',rmfield(editor,{'spec','state'}), ...
                            'editorState',editor.state);
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Preparing OOCV application preprocessing failed.', 2);
                    end
                case {'oocv_runner_apply_preproc'}
                    handled = true;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir); if ~ok, sessionNM = NM; end
                    try
                        [analind, oocvind, preprocIndex] = NMOOCVRunnerUI.requestPreprocSelection(req);
                        module = sprintf('preproc_var%d', preprocIndex);
                        editorState = NMUIStateTools.readConfiguratorChild(tmpDir, module);
                        if isempty(fieldnames(editorState))
                            error('NMOOCVRunnerUI:MissingPreprocState', ...
                                'OOCV application preprocessing STATE is not initialized for PREPROC{%d}.', preprocIndex);
                        end
                        editorState = NMConfigTools.charifyStrings(editorState);
                        sessionNM = NMOOCVApplicationPreprocTools.applyConfiguratorState( ...
                            sessionNM, analind, oocvind, preprocIndex, editorState);
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMOOCVRunnerUI.stateFromNM(sessionNM, ctx);
                        out = struct('ok',true,'message','OOCV application preprocessing was saved.', ...
                            'operation',op,'state',state,'module',module);
                    catch ME % nm2-allow: NMUIErrorTools preserves MATLAB exception details in this service response
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Saving OOCV application preprocessing failed.', 2);
                    end
                otherwise
                    handled = true;
                    out = struct('ok',false,'message',sprintf('Unsupported OOCV runner operation: %s', op), ...
                        'error',sprintf('Unsupported OOCV runner operation: %s', op));
            end
        end

        function txt = htmlTextFromJson(stateJson)
            % htmlTextFromJson  Build the OOCV runner HTML shell.
            jsState = NMPreprocUI.jsonTextForScript(stateJson);
            assetTag = '20261117_runner_heading_size_v6'; nl = newline;
            L = { ...
'<!doctype html>'
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
'<title>Model application to OOCV data</title>'
['<link rel="stylesheet" href="NMTrainTemplateUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModuleNavigationRail.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisManagerUI.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMRuntimeGridPicker.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMManualArtifactFileList.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMModal.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMOOCVContainerSelector.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMAnalysisCardSelector.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMRuntimeProgressViewer.css?v=' assetTag '">']
['<link rel="stylesheet" href="NMOOCVRunnerUI.css?v=' assetTag '">']
['<style>' NMUIMessageTools.css() '</style>']
'</head><body class="nmHasNavRail">'
'<header>'
'  <div><div class="crumb">Main interface / application-OOCV</div><div class="title">Model application to OOCV data</div></div>'
'  <div class="headerActions"><button id="finish" class="primary" type="button">Finish / close</button></div>'
'</header>'
'<main class="wrap oocvRunnerWrap"><section class="panel oocvRunnerPanel">'
'  <div class="oocvRunnerLayout">'
'    <section class="card oocvConfigPanel">'
'      <div class="oocvRunnerSectionHeader"><h2>Runtime configuration</h2></div>'
'      <div class="field oocvDatasetField"></div>'
'      <div id="applicationPreprocField" class="field hidden"><div class="oocvRunnerSectionHeader"><label class="nmRunnerSectionTitle">Application-specific preprocessing</label><span id="applicationPreprocStatus" class="muted"></span></div><div id="applicationPreprocBranches"></div><div class="help">The trained preprocessing sequence is shown read-only. Only OOCV-specific imputation permitted for the selected analysis/application pair can be added or changed.</div></div>'
'      <div id="artifactSummary" class="nmRuntimeArtifactSummary oocvArtifactSummary"></div>'
'      <div class="field"><label class="nmRunnerSectionTitle" for="operationMode">OOCV input mode</label><select id="operationMode"><option value="auto">Auto — scratch/resume</option><option value="scratch">Scratch/resume</option><option value="precomputed">Precomputed OOCVdatamat only</option></select></div>'
'      <div class="field"><label class="nmRunnerSectionTitle" for="manualArtifactMode">Manual OOCV artifact override</label><select id="manualArtifactMode"><option value="none">Automatic discovery</option><option value="oocvdatamat">Select OOCVdatamat files</option></select><button id="pickArtifactFile" type="button">Pick file(s)…</button><div id="manualArtifactSummary" class="help"></div></div>'
'      <div class="field"><label class="nmRunnerSectionTitle">OOCV artifact handling</label><label><input id="overwriteExisting" type="checkbox"> Overwrite existing OOCVdatamat files</label></div>'
'      <div class="field"><label class="nmRunnerSectionTitle">Optimized runtime parameters</label><label><input id="saveParams" type="checkbox"> Save recomputed preprocessing/model parameters</label><label id="saveCV1Row" class="hidden"><input id="saveCV1" type="checkbox"> Save preprocessing parameters at CV1 level</label></div>'
'      <div id="permutationGroup" class="field hidden"><label class="nmRunnerSectionTitle">Permutation analysis</label><label><input id="permutationTest" type="checkbox"> Test model performance by label permutation</label><label id="nPermsRow" class="oocvInlineOption hidden">Permutations <input id="nPerms" type="number" min="1" step="1" value="1000"></label></div>'
'      <div id="gridSection" class="field"><label class="nmRunnerSectionTitle">CV2 partitions</label><div id="gridPicker"></div></div>'
'      <div class="actions oocvRunRow"><button id="runOOCV" class="primary nmActionButton" type="button" disabled>Run OOCV application</button><button id="generateRuntimeScript" class="nmActionButton" type="button" disabled>Generate runtime script</button></div>'
'      <div id="runHint" class="help"></div>'
'    </section>'
'    <section class="card oocvAnalysisPanel">'
'      <div class="oocvRunnerSectionHeader"><h2>Analysis selection</h2><span class="muted">Select one trained analysis</span></div>'
'      <div id="analysisList" class="amAnalysisList oocvAnalysisList"></div>'
'    </section>'
'  </div>'
'</section></main>'
'<div class="modal" id="applicationPreprocModal"><div class="modalBox"><div class="modalHead"><div><b id="applicationPreprocModalTitle">OOCV application preprocessing</b><div class="path" id="applicationPreprocModalPath">Selected analysis / OOCV application</div></div><button id="applicationPreprocBack" type="button">Back to OOCV runner</button></div><iframe id="applicationPreprocFrame" title="OOCV application preprocessing configurator"></iframe></div></div>'
['<script>window.NM_OOCV_RUNNER_STATE = ' jsState ';</script>']
['<script>' NMUIMessageTools.script() '</script>']
['<script>window.NM_MODULE_NAV_CONTEXT = {currentModule:"oocv"};</script>']
['<script src="NMRuntimeGridPicker.js?v=' assetTag '"></script>']
['<script src="NMManualArtifactFileList.js?v=' assetTag '"></script>']
['<script src="NMModal.js?v=' assetTag '"></script>']
['<script src="NMOOCVContainerSelector.js?v=' assetTag '"></script>']
['<script src="NMAnalysisCardSelector.js?v=' assetTag '"></script>']
['<script src="NMRuntimeProgressViewer.js?v=' assetTag '"></script>']
['<script src="NMRuntimeJobClient.js?v=' assetTag '"></script>']
['<script src="NMModuleIconSet.js?v=' assetTag '"></script>']
['<script src="NMModuleNavigationRail.js?v=' assetTag '"></script>']
['<script src="NMRunnerStateManager.js?v=' assetTag '"></script>']
['<script src="NMOOCVRunnerUI_main.js?v=' assetTag '"></script>']
'</body></html>'};
            txt = strjoin(L,nl);
        end

        function copyAssets(webDir)
            % copyAssets  Copy static and shared assets for the OOCV runner.
            src = fileparts(mfilename('fullpath'));
            files = {'NMOOCVRunnerUI.css','NMRunnerStateManager.js','NMOOCVRunnerUI_main.js','NMRuntimeGridPicker.js','NMRuntimeGridPicker.css','NMManualArtifactFileList.js','NMManualArtifactFileList.css', ...
                'NMModal.js','NMModal.css','NMOOCVContainerSelector.js','NMOOCVContainerSelector.css','NMAnalysisCardSelector.js','NMAnalysisCardSelector.css', ...
                'NMRuntimeProgressViewer.js','NMRuntimeProgressViewer.css','NMRuntimeJobClient.js','NMTrainTemplateUI.css', ...
                'NMModuleIconSet.js','NMModuleNavigationRail.js','NMModuleNavigationRail.css','NMAnalysisManagerUI.css'};
            for i=1:numel(files)
                s = fullfile(src, files{i}); if exist(s,'file'), copyfile(s, fullfile(webDir, files{i}), 'f'); end
            end
        end

    end

    methods (Static, Access=private)
        function analyses = analysisCards(NM, list)
            analyses = repmat(struct('index',0,'id','','description','','rootdir','','status',NaN, ...
                'enabled',false,'disabledReason','','ix',0,'jx',0,'GridAct',false(0,0)),1,0);
            if list.count == 0, return; end
            for i = 1:list.count
                A = NM.analysis{i};
                if isempty(A) || ~isstruct(A), continue; end
                c = struct('index',i,'id',list.ids{i},'description',list.descriptions{i}, ...
                    'rootdir',list.rootdirs{i},'status',list.status(i),'enabled',false, ...
                    'disabledReason','','ix',0,'jx',0,'GridAct',false(0,0));
                if isfield(A,'params') && isstruct(A.params) && isfield(A.params,'cv') && isstruct(A.params.cv) && isfield(A.params.cv,'TrainInd')
                    [c.ix,c.jx] = size(A.params.cv.TrainInd);
                end
                if isfield(A,'GDdims') && ~isempty(A.GDdims) && iscell(A.GDdims) && isstruct(A.GDdims{1}) && isfield(A.GDdims{1},'GridAct') && ~isempty(A.GDdims{1}.GridAct)
                    c.GridAct = logical(A.GDdims{1}.GridAct);
                    [c.ix,c.jx] = size(c.GridAct);
                elseif c.ix > 0 && c.jx > 0
                    c.GridAct = true(c.ix,c.jx);
                end
                c.enabled = isfinite(c.status) && c.status >= 1 && list.rootExists(i);
                if ~list.rootExists(i), c.disabledReason = 'Analysis root path is stale or missing. Relink the analysis root in Analysis Manager before OOCV application.'; elseif ~c.enabled, c.disabledReason = 'Analysis has no completed trained result state.'; end
                analyses(end+1) = c; %#ok<AGROW>
            end
        end

        function pairs = readinessPairs(NM, analyses, oocv)
            pairs = repmat(struct('analysisIndex',0,'oocvIndex',0,'ready',false,'message','', ...
                'requiredModalities',[],'labelsKnown',[],'nCases',[],'applicationPreproc',struct()),1,0);
            containers = oocv.containers;
            if isempty(analyses) || isempty(containers), return; end
            for a = 1:numel(analyses)
                if ~analyses(a).enabled, continue; end
                for c = 1:numel(containers)
                    p = struct('analysisIndex',analyses(a).index,'oocvIndex',containers(c).index,'ready',false, ...
                        'message','OOCV/application readiness was not evaluated.','requiredModalities',[], ...
                        'labelsKnown',containers(c).labelsKnown, ...
                        'nCases',containers(c).nCases, 'applicationPreproc',struct());
                    try
                        r = NMRunTools.oocvReadiness(NM, p.analysisIndex, p.oocvIndex);
                        p.ready = logical(r.ready);
                        p.message = r.message;
                        p.requiredModalities = r.requiredModalities;
                        p.labelsKnown = r.labelsKnown;
                        p.nCases = r.nCases;
                        p.applicationPreproc = NMOOCVRunnerUI.applicationPreprocSummary(NM, p.analysisIndex, p.oocvIndex, r);
                    catch ME % nm2-allow: NMUIErrorTools renders readiness failure in OOCV card message
                        p.ready = false;
                        p.message = NMUIErrorTools.messageWithStack(ME, 'OOCV readiness check failed.', 2);
                    end
                    pairs(end+1) = p; %#ok<AGROW>
                end
            end
        end

        function summary = applicationPreprocSummary(NM, analind, oocvind, readiness)
            summary = struct('supported',false,'fusionMode','','branches',struct([]),'hasConfigurableBranch',false);
            r = readiness.applicationPreproc;
            if isempty(r), return; end
            summary.supported = logical(r.assessmentSupported);
            summary.fusionMode = r.fusionMode;
            if ~summary.supported || isempty(r.branches), return; end
            B = r.branches;
            out = repmat(struct('preprocIndex',0,'modalities',[],'fusionMode','', ...
                'featureImputationAvailable',false,'labelImputationAvailable',false, ...
                'nActiveRows',0,'nMissingPredictorRows',0,'nMissingLabelRows',0, ...
                'configured',false,'canConfigure',false),1,numel(B));
            for ii = 1:numel(B)
                b = B(ii);
                out(ii).preprocIndex = double(b.preprocIndex);
                out(ii).modalities = double(b.modalities);
                out(ii).fusionMode = char(string(b.fusionMode));
                out(ii).featureImputationAvailable = logical(b.specialFeatureImputationAvailable);
                out(ii).labelImputationAvailable = double(b.nActiveOOCVRowsWithMissingLabels) > 0;
                out(ii).nActiveRows = double(b.nActiveOOCVRows);
                out(ii).nMissingPredictorRows = double(b.nActiveOOCVRowsWithMissingPredictors);
                out(ii).nMissingLabelRows = double(b.nActiveOOCVRowsWithMissingLabels);
                out(ii).configured = ~isempty(NMOOCVApplicationPreprocTools.branchPreproc( ...
                    NM, analind, oocvind, out(ii).preprocIndex));
                out(ii).canConfigure = out(ii).featureImputationAvailable || ...
                    out(ii).labelImputationAvailable || out(ii).configured;
            end
            summary.branches = out;
            summary.hasConfigurableBranch = any([out.canConfigure]);
        end

        function opts = defaultOptions()
            opts = struct('operationMode','auto','manualArtifactMode','none', ...
                'manualFiles',struct('oocvDataMasterFile','','oocvDataFiles',{{}},'enabled',false), ...
                'overwrite',false,'saveparam',false,'saveCV1',false, ...
                'permutationTest',false,'nPerms',1000);
        end

        function idx = firstEnabledAnalysis(analyses)
            idx = [];
            if isempty(analyses), return; end
            k = find([analyses.enabled],1,'first');
            if ~isempty(k), idx = analyses(k).index; end
        end

        function idx = firstOOCVIndex(oocv)
            idx = oocv.activeIndex;
            if ~isempty(idx), return; end
            cs = oocv.containers;
            if ~isempty(cs), idx = cs(1).index; end
        end

        function msg = statusMessage(state)
            if ~logical(state.defs.analyses_locked)
                msg = 'Activate Application/OOCV mode before applying trained models to independent data.';
                return;
            end
            if ~state.backendAvailable
                msg = 'The OOCV application backend is not available on the MATLAB path.';
                return;
            end
            if isempty(state.analyses) || ~any([state.analyses.enabled])
                msg = 'No completed trained analysis is available for OOCV application.';
                return;
            end
            if state.oocv.nContainers < 1
                msg = 'No OOCV/application dataset is available. Import one with the OOCV Data Manager first.';
                return;
            end
            msg = 'Select one trained analysis and one OOCV/application dataset.';
        end

        function plan = attachRuntimeProgressContext(plan, req, tmpDir)
            taskId = NMOOCVRunnerUI.requestChar(req, 'progressTaskId', '');
            if isempty(taskId) && isstruct(req) && isfield(req,'extra') && isstruct(req.extra)
                taskId = NMOOCVRunnerUI.requestChar(req.extra, 'progressTaskId', '');
            end
            if isempty(taskId), return; end
            minInterval = NMOOCVRunnerUI.requestNumeric(req, 'progressChartMinIntervalSeconds', 0.10);
            if isstruct(req) && isfield(req,'extra') && isstruct(req.extra)
                minInterval = NMOOCVRunnerUI.requestNumeric(req.extra, 'progressChartMinIntervalSeconds', minInterval);
            end
            plan.runtimeUI = NMRuntimeProgressTools.browserRuntimeContext(tmpDir, taskId, ...
                struct('source','oocv_runner', 'chartEnabled',true, 'suppressNativeViewer',true, ...
                    'chartMinIntervalSeconds',minInterval, 'progressTitle','NM OOCV Application Progress', ...
                    'progressLowerTitle','OOCV application progress'));
        end

        function failRuntimeProgressIfPresent(plan, ME)
            if isstruct(plan) && isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                NMRuntimeProgressTools.fail(plan.runtimeUI, 'OOCV application failed.', ME);
            end
        end

        function [analind, oocvind, preprocIndex] = requestPreprocSelection(req)
            analind = NMOOCVRunnerUI.scalarIndex(req.analysisIndex, 'analysis');
            oocvind = NMOOCVRunnerUI.scalarIndex(req.oocvIndex, 'OOCV dataset');
            preprocIndex = NMOOCVRunnerUI.scalarIndex(req.preprocIndex, 'preprocessing branch');
        end

        function plan = requestPlan(req, NM)
            plan = struct();
            if isstruct(req) && isfield(req,'plan') && isstruct(req.plan), plan = req.plan; end
            if ~isfield(plan,'analysisIndex'), plan.analysisIndex = []; end
            if ~isfield(plan,'oocvIndex'), plan.oocvIndex = []; end
            if ~isfield(plan,'gridAction'), plan.gridAction = []; end
            defaults = NMOOCVRunnerUI.defaultOptions();
            if isfield(plan,'options') && isstruct(plan.options)
                defaults = NMConfigTools.mergeStruct(defaults,plan.options);
            end
            defaults.manualFiles.enabled = strcmp(defaults.manualArtifactMode,'oocvdatamat');
            plan.options = defaults;
            plan.artifactDir = '';
            if ~isempty(plan.analysisIndex) && ~isempty(plan.oocvIndex) && ...
                    plan.analysisIndex >= 1 && plan.oocvIndex >= 1 && ...
                    plan.analysisIndex <= numel(NM.analysis) && plan.oocvIndex <= numel(NM.OOCV)
                A = NM.analysis{plan.analysisIndex};
                if isempty(plan.gridAction), plan.gridAction = A.GDdims{1}.GridAct; end
                root = A.GDdims{1}.RootPath;
                if iscell(root), root = root{1}; end
                plan.artifactDir = fullfile(root,sprintf('OOCV_%d',plan.oocvIndex));
                if isfield(A,'OOCV') && numel(A.OOCV) >= plan.oocvIndex && ...
                        ~isempty(A.OOCV{plan.oocvIndex}) && isfield(A.OOCV{plan.oocvIndex},'RootPath')
                    plan.artifactDir = A.OOCV{plan.oocvIndex}.RootPath;
                    if iscell(plan.artifactDir), plan.artifactDir = plan.artifactDir{1}; end
                end
            end
        end

        function [NM, out] = runApplication(NM, plan)
            [analind, oocvind] = NMOOCVRunnerUI.validateSelection(NM, plan);
            spec = NMOOCVRunnerUI.executionSpec(NM,analind,oocvind,plan);
            if spec.permutationTest
                ready = NMRunTools.oocvReadiness(NM, analind, oocvind);
                if ~isequal(ready.labelsKnown,true)
                    error('NMOOCVRunnerUI:permutationNeedsLabels', ...
                        'Permutation analysis requires known labels in the selected OOCV/application dataset.');
                end
            end
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                NMRuntimeProgressTools.start(plan.runtimeUI, 'NM OOCV Application Progress', ...
                    sprintf('Preparing analysis %d for OOCV/application dataset %d.', analind, oocvind));
                spec.UI = plan.runtimeUI;
            end
            [NM, runOut] = NMRunTools.applyOOCV(NM, analind, oocvind, spec);
            if isfield(plan,'runtimeUI') && isstruct(plan.runtimeUI)
                NMRuntimeProgressTools.finish(plan.runtimeUI, 'OOCV model application completed.', 'NM OOCV Application Progress');
            end
            out = struct('ok',true,'message',runOut.message,'analysisIndex',analind,'oocvIndex',oocvind,'result',runOut);
        end

        function spec = executionSpec(NM,analind,oocvind,plan)
            opts = plan.options;
            spec = struct('operationMode',opts.operationMode, 'overwrite',logical(opts.overwrite), ...
                'saveparam',logical(opts.saveparam), 'saveCV1',logical(opts.saveparam && opts.saveCV1), ...
                'loadparam',false, 'permutationTest',logical(opts.permutationTest), ...
                'nPerms',max(1,round(double(opts.nPerms))), 'hideGrid',false);
            trained = logical(NM.analysis{analind}.GDdims{1}.GridAct);
            spec.gridAction = logical(plan.gridAction) & trained;
            if ~any(strcmp(spec.operationMode,{'auto','scratch','precomputed'}))
                error('NMOOCVRunnerUI:badMode','Unsupported OOCV operation mode: %s',spec.operationMode);
            end
            if strcmp(spec.operationMode,'precomputed')
                [spec.oocvmat,artifacts] = NMRunTools.resolveOOCVDataMat(NM,analind,oocvind, ...
                    plan.artifactDir,plan.options.manualFiles,plan.options);
                if ~artifacts.precomputedSupported
                    error('NMOOCVRunnerUI:multiStreamPrecomputed', '%s', artifacts.coverageText);
                end
                spec.gridAction = spec.gridAction & ~cellfun(@isempty,spec.oocvmat);
                spec.oocvmat(~spec.gridAction) = {[]};
            end
            if spec.permutationTest && ~spec.overwrite && ~strcmp(spec.operationMode,'precomputed')
                error('NMOOCVRunnerUI:permutationNeedsOverwrite', ...
                    'Enable overwrite to regenerate permutation OOCVdatamats; scratch reuse may contain no permutation data.');
            end
            if ~any(spec.gridAction(:))
                error('NMOOCVRunnerUI:noExecutableCV2','No selected trained CV2 partitions are executable with the selected mode/artifacts.');
            end
        end

        function [analind, oocvind] = validateSelection(NM, plan)
            analind = NMOOCVRunnerUI.scalarIndex(plan.analysisIndex, 'analysis');
            oocvind = NMOOCVRunnerUI.scalarIndex(plan.oocvIndex, 'OOCV dataset');
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || analind > numel(NM.analysis) || isempty(NM.analysis{analind})
                error('NMOOCVRunnerUI:badAnalysis', 'Selected analysis %d does not exist.', analind);
            end
            if ~isfield(NM,'OOCV') || ~iscell(NM.OOCV) || oocvind > numel(NM.OOCV) || isempty(NM.OOCV{oocvind})
                error('NMOOCVRunnerUI:badOOCV', 'Selected OOCV/application dataset %d does not exist.', oocvind);
            end
        end

        function idx = scalarIndex(x, label)
            if isempty(x) || ~isnumeric(x) || ~isscalar(x) || ~isfinite(x)
                error('NMOOCVRunnerUI:missingSelection', 'Select one %s before proceeding.', label);
            end
            idx = round(double(x));
            if idx < 1, error('NMOOCVRunnerUI:badSelection', 'Selected %s index must be >= 1.', label); end
        end

        function out = generateRuntimeScript(NM, plan)
            [analind, oocvind] = NMOOCVRunnerUI.validateSelection(NM, plan);
            spec = NMOOCVRunnerUI.executionSpec(NM,analind,oocvind,plan);
            rootdir = '';
            if isfield(NM.analysis{analind},'rootdir'), rootdir = char(string(NM.analysis{analind}.rootdir)); end
            if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                error('NMOOCVRunnerUI:noAnalysisRoot', ...
                    'Analysis %d has no accessible root directory; cannot write an OOCV runtime script.', analind);
            end
            fpath = fullfile(rootdir, sprintf('NM_oocv_analysis_%d_dataset_%d.m', analind, oocvind));
            NMSerializationTools.writeTextFile(fpath, NMOOCVRunnerUI.scriptText(analind,oocvind,spec), ...
                'NMOOCVRunnerUI:writeFailed', 'Could not write %s', 'fwrite-input-char');
            out = struct('ok',true,'message',sprintf('Generated OOCV runtime script: %s', fpath), ...
                'script',struct('analysisIndex',analind,'oocvIndex',oocvind,'path',fpath));
        end

        function txt = scriptText(analind, oocvind, spec)
            gridLine = 'spec.gridAction = ''analysis'';';
            if ~ischar(spec.gridAction) && ~isstring(spec.gridAction)
                gridLine = sprintf('spec.gridAction = logical(%s);', mat2str(logical(spec.gridAction)));
            end
            txt = sprintf(['%% NeuroMiner runtime script -- generated by the OOCV application runner\n' ...
                '%% Analysis %d / OOCV application dataset %d\n\n' ...
                'if ~exist(''NM'',''var'')\n' ...
                '    error(''This script needs your NeuroMiner project struct in the workspace as NM.'');\n' ...
                'end\n\n' ...
                'spec = struct();\n' ...
                'spec.operationMode = ''%s'';\n' ...
                'spec.overwrite = %s;\n' ...
                'spec.saveparam = %s;\n' ...
                'spec.saveCV1 = %s;\n' ...
                'spec.loadparam = false;\n' ...
                'spec.permutationTest = %s;\n' ...
                'spec.nPerms = %d;\n' ...
                'spec.hideGrid = false;\n' ...
                '%s\n\n' ...
                '[NM, oocvOut] = NMRunTools.applyOOCV(NM, %d, %d, spec);\n' ...
                'disp(oocvOut.message);\n'], ...
                analind, oocvind, spec.operationMode, NMOOCVRunnerUI.logicalLiteral(spec.overwrite), ...
                NMOOCVRunnerUI.logicalLiteral(spec.saveparam), NMOOCVRunnerUI.logicalLiteral(spec.saveCV1), ...
                NMOOCVRunnerUI.logicalLiteral(spec.permutationTest), spec.nPerms, gridLine, analind, oocvind);
            if strcmp(spec.operationMode,'precomputed')
                rows = sprintf('spec.oocvmat = cell(%d,%d);\n',size(spec.oocvmat));
                for k = find(~cellfun(@isempty,spec.oocvmat))'
                    [p,f] = ind2sub(size(spec.oocvmat),k);
                    rows = [rows sprintf('spec.oocvmat{%d,%d} = ''%s'';\n', ...
                        p,f,strrep(spec.oocvmat{k},'''',''''''))]; %#ok<AGROW>
                end
                txt = strrep(txt,'[NM, oocvOut] =',[rows '[NM, oocvOut] =']);
            end
        end

        function s = logicalLiteral(v)
            if logical(v), s = 'true'; else, s = 'false'; end
        end


        function op = requestOperation(req)
            op = '';
            if isstruct(req)
                if isfield(req,'operation') && ~isempty(req.operation), op = char(string(req.operation));
                elseif isfield(req,'op') && ~isempty(req.op), op = char(string(req.op));
                end
            end
        end

        function v = requestChar(req, name, defaultValue)
            v = defaultValue;
            if isstruct(req) && isfield(req,name) && ~isempty(req.(name)), v = char(string(req.(name))); end
        end

        function v = requestNumeric(req, name, defaultValue)
            v = defaultValue;
            if isstruct(req) && isfield(req,name) && ~isempty(req.(name))
                x = double(req.(name));
                if isscalar(x) && isfinite(x), v = x; end
            end
        end

    end
end

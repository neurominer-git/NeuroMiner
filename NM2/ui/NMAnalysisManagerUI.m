classdef NMAnalysisManagerUI
% NMAnalysisManagerUI
% -------------------------------------------------------------------------
% Browser-side analysis-manager page for NeuroMiner.
%
% This page is a thin UI/service wrapper around NMAnalysisManagerTools. It
% intentionally reuses the existing NM browser CSS and session-NM store; it
% must not mutate NM.analysis directly.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(NM, outDir, ctx)
            % export  Create the browser page/session artifacts for this UI component.
            %
            % Writes the HTML entry point, initial JSON state, shared assets and bridge resources
            % required by the browser shell. The method stores or references session state for later
            % service calls and is the normal entry point for scripted or app-level launch code.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_analysis_manager_ui'); end
            if nargin < 3, ctx = struct(); end %#ok<NASGU>

            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_analysis_manager_ui');
            outDir = dirs.root;
            webRoot = dirs.webRoot;
            webDir = dirs.webDir;
            pyDir = dirs.pyDir;
            tmpDir = dirs.tmpDir;

            NMDataIOUI.saveSessionNM(NM, tmpDir);
            state = NMAnalysisManagerUI.stateFromNM(NM, ctx);
            stateJson = NMConfigTools.writeJsonAliases({ ...
                fullfile(tmpDir,'analysis_manager_state.json'), ...
                fullfile(tmpDir,'current_config.json'), ...
                fullfile(tmpDir,'param.json')}, state, 'analysis manager state');

            htmlPath = fullfile(webDir, 'nm_analysis_manager.html');
            NMAnalysisManagerUI.writeTextFile(htmlPath, NMAnalysisManagerUI.htmlTextFromJson(stateJson));
            NMAnalysisManagerUI.copyAssets(webDir);
            NMPreprocUI.writeBridge(fullfile(pyDir,'nm_bridge_server.py'));

            paths = struct('root', outDir, 'webRoot', webRoot, 'webDir', webDir, ...
                'tmpDir', tmpDir, 'html', htmlPath, 'analysisManagerHtml', htmlPath, ...
                'entryHtml', 'nm_analysis_manager.html', 'entryHtmlPath', htmlPath, ...
                'state', fullfile(tmpDir,'analysis_manager_state.json'));
        end

        function NM = importUpdated(NM, pathsOrWebDir, ctx)
            % importUpdated  Reconcile browser-session state back into the MATLAB caller.
            %
            % Loads the session NM or edited configuration snapshot produced by browser service calls,
            % returns the input object when no update exists, and clears transient session storage when
            % the UI lifecycle is complete.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(pathsOrWebDir), return; end
            tmpDir = NMDataIOUI.pathsTmpDir(pathsOrWebDir);
            if isempty(tmpDir), return; end
            [NM2, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
            if ok, NM = NM2; end
            NMDataIOUI.clearSessionNM(tmpDir);
        end

        function state = stateFromNM(NM, ctx)
            % stateFromNM  Build browser-facing state from the current NM structure.
            %
            % Extracts only the fields required by this page, attaches app/session context where needed
            % and leaves the NM modelling structure unchanged. Browser service handlers use the same
            % state builder after mutations to refresh the page consistently.

            if nargin < 1 || isempty(NM), NM = struct(); end
            defs = NMStatusGuardTools.defsState(NM);
            analyses = NMAnalysisManagerTools.listAnalyses(NM);
            state = struct();
            state.page = 'analysis_manager';
            state.defs = defs;
            state.analyses = analyses;
            state.canCreate = defs.import_finished && ~defs.analyses_locked;
            state.canEditTrainingAnalyses = defs.import_finished && ~defs.analyses_locked;
            state.hasCompletedAnalysis = NMStatusGuardTools.hasCompletedAnalysis(NM);
            state.showApplicationTransition = state.hasCompletedAnalysis;
            state.canActivateApplicationMode = defs.import_finished && ~defs.analyses_locked && state.hasCompletedAnalysis;
            state.actionLabels = NMAnalysisManagerUI.actionLabels();
            state.statusMessage = NMAnalysisManagerUI.statusMessage(state);
            state.defaultCreateSpec = NMAnalysisManagerTools.defaultCreateSpec();
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'analysis_manager');
        end

        function [handled, out] = handleMatlabService(NM, req, tmpDir, ctx)
            % handleMatlabService  Dispatch browser bridge requests for this UI component.
            %
            % Decodes the request operation, loads session state when needed, delegates domain work to
            % the relevant core/runtime tools and returns a structured response for the message strip and
            % page refresh logic. Unknown operations leave handled=false.

            handled = false;
            out = struct();
            if nargin < 4, ctx = struct(); end %#ok<NASGU>
            if nargin < 3, tmpDir = ''; end
            op = NMAnalysisManagerUI.requestOperation(req);
            if isempty(op), return; end
            switch lower(op)
                case {'analysis_manager_refresh','analysis_manager_list'}
                    handled = true;
                    [sessionNM, ~] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    state = NMAnalysisManagerUI.stateFromNM(sessionNM, ctx);
                    out = struct('ok',true,'message','Analysis manager refreshed.','state',state,'operation',op);
                case {'analysis_manager_create'}
                    handled = true;
                    [sessionNM, ~] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    spec = NMAnalysisManagerUI.createSpecFromRequest(req);
                    try
                        [sessionNM, mgrOut] = NMAnalysisManagerTools.createAnalysis(sessionNM, spec);
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMAnalysisManagerUI.stateFromNM(sessionNM, ctx);
                        out = NMAnalysisManagerUI.serviceOK(op, mgrOut.message, state, mgrOut);
                    catch ME
                        out = NMAnalysisManagerUI.serviceError(op, ME, 'Creating the analysis failed.');
                    end
                case {'analysis_manager_reset'}
                    handled = true;
                    [sessionNM, ~] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    analind = NMAnalysisManagerUI.requestAnalysisIndex(req);
                    try
                        [sessionNM, mgrOut] = NMAnalysisManagerTools.resetParameters(sessionNM, analind, struct('resetMode','complete_reset'));
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMAnalysisManagerUI.stateFromNM(sessionNM, ctx);
                        out = NMAnalysisManagerUI.serviceOK(op, mgrOut.message, state, mgrOut);
                    catch ME
                        out = NMAnalysisManagerUI.serviceError(op, ME, 'Resetting analysis parameters failed.');
                    end
                case {'analysis_manager_restore_template'}
                    handled = true;
                    [sessionNM, ~] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    analind = NMAnalysisManagerUI.requestAnalysisIndex(req);
                    try
                        [sessionNM, mgrOut] = NMAnalysisManagerTools.restoreTemplateFromAnalysis(sessionNM, analind, struct());
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMAnalysisManagerUI.stateFromNM(sessionNM, ctx);
                        out = NMAnalysisManagerUI.serviceOK(op, mgrOut.message, state, mgrOut);
                    catch ME
                        out = NMAnalysisManagerUI.serviceError(op, ME, 'Restoring the analysis template failed.');
                    end
                case {'analysis_manager_inspect','analysis_manager_canvas_detail'}
                    handled = true;
                    [sessionNM, ~] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    analind = NMAnalysisManagerUI.requestAnalysisIndex(req);
                    try
                        if strcmpi(op,'analysis_manager_inspect')
                            inspectOut = NMAnalysisManagerTools.inspectAnalysis(sessionNM, analind, struct());
                            state = NMAnalysisManagerUI.stateFromNM(sessionNM, ctx);
                            out = NMAnalysisManagerUI.serviceOK(op, inspectOut.message, state, inspectOut);
                        else
                            detailOut = NMAnalysisManagerTools.inspectCanvasNodeDetail(sessionNM, analind, char(req.nodeId));
                            out = NMAnalysisManagerUI.serviceOK(op, 'Canvas node details prepared.', [], detailOut);
                        end
                    catch ME
                        out = NMAnalysisManagerUI.serviceError(op, ME, 'Inspecting the analysis failed.');
                    end
                case {'analysis_manager_export_methods'}
                    handled = true;
                    [sessionNM, ~] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    analind = NMAnalysisManagerUI.requestAnalysisIndex(req);
                    try
                        mgrOut = NMAnalysisManagerTools.exportMethodsSummary(sessionNM, analind, req.exportRoot);
                        out = NMAnalysisManagerUI.serviceOK(op, mgrOut.message, [], mgrOut);
                    % nm2-allow: NMAnalysisManagerUI serviceError returns the caught exception through the browser diagnostic contract.
                    catch ME
                        out = NMAnalysisManagerUI.serviceError(op, ME, 'Exporting the analysis methods summary failed.');
                    end
                case {'analysis_manager_relink_root'}
                    handled = true;
                    [spec, relinkContext] = NMAnalysisManagerUI.relinkSpecFromRequest(req);
                    if strcmp(spec.selectionKind,'bulk_parent')
                        analind = req.analysisIndex;
                    else
                        analind = NMAnalysisManagerUI.requestAnalysisIndex(req);
                    end
                    [sessionNM, ~] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    try
                        [sessionNM, mgrOut] = NMAnalysisManagerTools.relinkAnalysisRoot(sessionNM, analind, spec);
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = [];
                        if strcmp(relinkContext.originatingPage, 'analysis_manager')
                            state = NMAnalysisManagerUI.stateFromNM(sessionNM, ctx);
                        end
                        out = NMAnalysisManagerUI.serviceOK(op, mgrOut.message, state, mgrOut);
                    catch ME
                        out = NMAnalysisManagerUI.serviceError(op, ME, 'Relinking the analysis root failed.');
                    end
                case {'analysis_manager_run_runtime_plan'}
                    handled = true;
                    [sessionNM, ~] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    plan = NMAnalysisManagerUI.requestRuntimePlan(req);
                    runtimeUI = [];
                    taskId = '';
                    if isstruct(req) && isfield(req,'progressTaskId') && ~isempty(req.progressTaskId)
                        taskId = char(string(req.progressTaskId));
                    elseif isstruct(req) && isfield(req,'extra') && isstruct(req.extra) && ...
                            isfield(req.extra,'progressTaskId') && ~isempty(req.extra.progressTaskId)
                        taskId = char(string(req.extra.progressTaskId));
                    end
                    if ~isempty(taskId)
                        runtimeUI = NMRuntimeProgressTools.browserRuntimeContext(tmpDir, taskId, ...
                            struct('source','analysis_manager', 'chartEnabled',true, ...
                            'suppressNativeViewer',true, 'progressTitle','NM Runtime Progress Viewer', ...
                            'progressLowerTitle','Runtime progress'));
                    end
                    try
                        [sessionNM, runOut] = NMRuntimeActionTools.runPlan(sessionNM, plan, runtimeUI);
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMAnalysisManagerUI.stateFromNM(sessionNM, ctx);
                        inspectOut = NMAnalysisManagerTools.inspectAnalysis(sessionNM, runOut.analysisIndex, struct());
                        runOut.inspection = inspectOut;
                        out = NMAnalysisManagerUI.serviceOK(op, runOut.message, state, runOut);
                    catch ME
                        out = NMAnalysisManagerUI.serviceError(op, ME, 'Running the selected runtime action plan failed.');
                    end
                case {'analysis_manager_delete'}
                    handled = true;
                    [sessionNM, ~] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    analind = NMAnalysisManagerUI.requestAnalysisIndex(req);
                    wipe = NMAnalysisManagerUI.requestLogical(req, 'wipe', false);
                    try
                        [sessionNM, mgrOut] = NMAnalysisManagerTools.deleteAnalyses(sessionNM, analind, struct('wipe',wipe));
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMAnalysisManagerUI.stateFromNM(sessionNM, ctx);
                        out = NMAnalysisManagerUI.serviceOK(op, mgrOut.message, state, mgrOut);
                    catch ME
                        out = NMAnalysisManagerUI.serviceError(op, ME, 'Deleting the analysis failed.');
                    end
                case {'analysis_manager_activate_application_mode'}
                    handled = true;
                    [sessionNM, ~] = NMDataIOUI.loadSessionNM(NM, tmpDir);
                    try
                        [sessionNM, mgrOut] = NMAnalysisManagerTools.activateApplicationMode(sessionNM, struct());
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        state = NMAnalysisManagerUI.stateFromNM(sessionNM, ctx);
                        out = NMAnalysisManagerUI.serviceOK(op, mgrOut.message, state, mgrOut);
                    catch ME
                        out = NMAnalysisManagerUI.serviceError(op, ME, 'Activating application/OOCV mode failed.');
                    end
            end
        end

        function txt = htmlTextFromJson(stateJson)
            % htmlTextFromJson  Build the HTML shell around a serialized initial state.
            %
            % Embeds or references the JSON state and loads the CSS/JavaScript assets that define this
            % page. The generated document is intentionally thin; MATLAB-side services remain behind the
            % bridge.

            jsState = NMPreprocUI.jsonTextForScript(stateJson);
            nl = newline;
            L = [ ...
                NMAnalysisManagerUI.htmlDocumentHead(), ...
                NMAnalysisManagerUI.htmlHeader(), ...
                NMAnalysisManagerUI.htmlMainShell(), ...
                NMAnalysisManagerUI.htmlScripts(jsState)];
            txt = strjoin(L, nl);
        end

        function L = htmlDocumentHead()
            % htmlDocumentHead  Return the analysis-manager document head lines.
            %
            % Supplies the page title, CSS links and shared message-strip style used by htmlTextFromJson.
            % This is presentation scaffolding only; analysis state is injected separately through the
            % initial JSON payload.

            L = { ...
'<!doctype html>'; ...
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'; ...
'<title>NeuroMiner analysis manager</title>'; ...
'<link rel="stylesheet" href="NMModuleNavigationRail.css">'; ...
'<link rel="stylesheet" href="NMModal.css">'; ...
'<link rel="stylesheet" href="NMRuntimeProgressViewer.css">'; ...
'<link rel="stylesheet" href="NMTrainTemplateUI.css">'; ...
'<link rel="stylesheet" href="NMAnalysisManagerUI.css">'; ...
['<style>' NMUIMessageTools.css() '</style>']; ...
'</head><body class="nmHasNavRail">'};
            L = L(:)';
        end

        function L = htmlHeader()
            % htmlHeader  Return the fixed analysis-manager header markup.
            %
            % Defines the top-page title and primary navigation affordances for the browser shell.
            % Runtime analysis data are not embedded here; dynamic cards are populated by JavaScript from
            % stateFromNM/service responses.

            L = { ...
'<header>'; ...
'  <div><div class="crumb">Model training</div><div class="title">NeuroMiner analysis manager</div></div>'; ...
'  <div class="headerActions"><button id="finish" class="primary" type="button">Finish / close</button></div>'; ...
'</header>'};
            L = L(:)';
        end

        function L = htmlMainShell()
            % htmlMainShell  Return the analysis-manager main container layout.
            %
            % Creates the browser regions used for analysis lists, creation forms, inspection details and
            % action buttons. The method defines structural placeholders rather than performing analysis
            % operations.

            createPanel = NMAnalysisManagerUI.htmlCreatePanelLines();
            analysisPanel = NMAnalysisManagerUI.htmlAnalysisPanelLines();
            inspectionPanel = NMAnalysisManagerUI.htmlInspectionPanelLines();
            L = [ ...
                {'<main class="wrap amWrap"><section id="analysisManagerPanel" class="panel amPanel">'; ...
                 '  <div class="amPanelHead"><div><h1>Analysis manager</h1><div id="analysisStatus" class="summary amStatusSummary"></div></div></div>'; ...
                 '  <div class="amLayout">'}; ...
                createPanel(:); ...
                analysisPanel(:); ...
                inspectionPanel(:); ...
                {'  </div>'; ...
                 '</section></main>'}];
            L = L(:)';
        end

        function L = htmlCreatePanelLines()
            % htmlCreatePanelLines  Return markup for creating or resetting analyses.
            %
            % Defines the browser controls that collect create/reset options before service calls reach
            % NMAnalysisManagerTools. It does not validate or write NM itself.

            L = { ...
'    <section class="card amCreatePanel">'; ...
'      <h2>Create analysis</h2>'; ...
'      <div class="field"><label for="analysisId">Analysis ID</label><input id="analysisId" class="textInput" type="text" placeholder="Required short analysis ID" required></div>'; ...
'      <div class="field"><label for="analysisDescription">Description</label><textarea id="analysisDescription" class="textInput" rows="3" placeholder="Required short analysis description" required></textarea></div>'; ...
'      <div class="field"><label for="analysisParentDir">Parent directory</label><div class="amPathRow"><input id="analysisParentDir" class="textInput" type="text" placeholder="Required parent directory"><button id="pickAnalysisParentDir" type="button" title="Pick parent directory">Pick</button></div></div>'; ...
'      <div class="field"><label for="analysisIndex">Target analysis index</label><div class="amCreateRow"><input id="analysisIndex" class="textInput" type="number" min="1" step="1" placeholder="next available"><button id="createAnalysis" class="primary compact" type="button">Create analysis</button></div></div>'; ...
'      <div class="muted" id="createHint"></div>'; ...
'      <div id="applicationTransitionBlock" class="amApplicationTransition hidden">'; ...
'        <div class="amSectionHeader"><h2>Application/OOCV transition</h2><button id="applicationHelpButton" class="amHelpButton" type="button" aria-expanded="false" title="Explain application/OOCV transition">?</button></div>'; ...
'        <div class="summary" id="applicationSummary"></div>'; ...
'        <button id="activateApplicationMode" class="primary amApplicationButton" type="button">Activate application/OOCV mode</button>'; ...
'        <div id="applicationHelpText" class="amHelpPopover amHelpWarning hidden">Activating application/OOCV mode locks training-analysis editing and enables OOCV/application data management. Treat this transition as irreversible: reopening training-analysis editing after external validation/application data have been introduced would risk information leakage between discovery/training data and external validation data.</div>'; ...
'      </div>'; ...
'    </section>'};
            L = L(:)';
        end

        function L = htmlAnalysisPanelLines()
            % htmlAnalysisPanelLines  Return markup for the analysis-card list region.
            %
            % Provides the container that JavaScript fills from the analysis summaries generated by
            % stateFromNM. It keeps card rendering separated from MATLAB-side analysis enumeration.

            L = { ...
'    <section class="card amAnalysisPanel">'; ...
'      <h2>Configured analyses</h2>'; ...
'      <div id="analysisList" class="amAnalysisList"></div>'; ...
'    </section>'};
            L = L(:)';
        end

        function L = htmlInspectionPanelLines()
            % htmlInspectionPanelLines  Return markup for read-only analysis inspection output.
            %
            % Defines the destination for detailed template/canvas diagnostics returned by inspect
            % service calls. The method does not query NM directly.

            L = { ...
'    <aside id="analysisInspectionPanel" class="card amInspectionPanel hidden">'; ...
'      <div class="amInspectionHeader"><h2>Analysis inspection</h2><button id="closeInspectionPanel" type="button" title="Close inspection panel">Close</button></div>'; ...
'      <div id="analysisInspectionContent" class="amInspectionContent muted">Select an analysis and click Inspect analysis configuration.</div>'; ...
'    </aside>'};
            L = L(:)';
        end

        function L = htmlScripts(jsState)
            % htmlScripts  Return script tags and initial-state bootstrap lines.
            %
            % Loads shared navigation, icon and analysis-manager JavaScript after making the serialized
            % state path available to the browser runtime. It is called only while constructing the HTML
            % shell.

            L = { ...
['<script>window.NM_ANALYSIS_MANAGER_STATE = ' jsState ';</script>']; ...
'<script>window.NM_MODULE_NAV_CONTEXT = {currentModule:"analysis_manager"};</script>'; ...
['<script>' NMUIMessageTools.script() '</script>']; ...
'<script src="NMModuleIconSet.js"></script>'; ...
'<script src="NMModuleNavigationRail.js"></script>'; ...
'<script src="NMModal.js"></script>'; ...
'<script src="NMRuntimeJobClient.js"></script>'; ...
'<script src="NMRuntimeProgressViewer.js"></script>'; ...
'<script src="NMAnalysisManagerUI_main.js"></script>'; ...
'</body></html>'};
            L = L(:)';
        end

        function labels = actionLabels()
            % actionLabels  Return stable display labels for analysis-manager actions.
            %
            % Centralizes text shown on buttons/cards so JavaScript and MATLAB service responses describe
            % the same operations. It is read-only and independent of current NM state.

            labels = struct();
            labels.delete = 'Delete';
            labels.deleteWipe = 'Delete and wipe from disk';
            labels.inspect = 'Inspect analysis configuration';
            labels.methodsSummary = 'Export analysis methods';
            labels.reset = 'Reset using current NM parameter template';
            labels.restoreTemplate = 'Reset current NM parameter template from this analysis';
            labels.train = 'Run ML training';
            labels.visualize = 'Run model visualisation';
            labels.interpret = 'Run ML Interpreter';
            labels.export = 'Export models';
            labels.applyOOCV = 'Apply to OOCV data';
            labels.relinkRoot = 'Relink analysis root';
        end

        function copyAssets(webDir)
            % copyAssets  Copy static browser assets required by this UI page.
            %
            % Copies the JavaScript, CSS, icon and shared visualization assets next to the generated HTML
            % entry point. Optional files are skipped only where the owning UI already treats them as
            % optional.

            srcDir = fileparts(mfilename('fullpath'));
            assets = {'NMModal.css','NMRuntimeProgressViewer.css','NMTrainTemplateUI.css','NMAnalysisManagerUI.css', ...
                'NMModal.js','NMRuntimeJobClient.js','NMRuntimeProgressViewer.js','NMAnalysisManagerUI_main.js', ...
                'NMModuleIconSet.js','NMModuleNavigationRail.js','NMModuleNavigationRail.css'};
            for i = 1:numel(assets)
                src = fullfile(srcDir, assets{i});
                if exist(src,'file') == 2
                    copyfile(src, fullfile(webDir, assets{i}), 'f');
                end
            end
        end
    end

    methods (Static, Access = private)
        function msg = statusMessage(state)
            if state.defs.analyses_locked
                msg = 'Application/OOCV mode is active. Training analysis creation and template mutation are locked.';
            elseif ~state.defs.import_finished
                msg = 'Training data import is not finalized. Finalize DataIO before creating analyses.';
            else
                msg = '';
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

        function spec = createSpecFromRequest(req)
            spec = NMAnalysisManagerTools.defaultCreateSpec();
            payload = struct();
            if isstruct(req) && isfield(req,'analysisSpec') && isstruct(req.analysisSpec)
                payload = req.analysisSpec;
            elseif isstruct(req) && isfield(req,'extra') && isstruct(req.extra) && isfield(req.extra,'analysisSpec') && isstruct(req.extra.analysisSpec)
                payload = req.extra.analysisSpec;
            end
            names = fieldnames(payload);
            for i = 1:numel(names)
                spec.(names{i}) = payload.(names{i});
            end
        end

        function idx = requestAnalysisIndex(req)
            idx = [];
            names = {'analysisIndex','analind','index'};
            for i = 1:numel(names)
                if isstruct(req) && isfield(req,names{i}) && ~isempty(req.(names{i}))
                    idx = round(double(req.(names{i}))); return;
                end
                if isstruct(req) && isfield(req,'extra') && isstruct(req.extra) && isfield(req.extra,names{i}) && ~isempty(req.extra.(names{i}))
                    idx = round(double(req.extra.(names{i}))); return;
                end
            end
            error('NMAnalysisManagerUI:missingAnalysisIndex','No analysis index was supplied.');
        end

        function tf = requestLogical(req, name, defaultValue)
            tf = defaultValue;
            if isstruct(req) && isfield(req,name) && ~isempty(req.(name))
                tf = logical(req.(name)); return;
            end
            if isstruct(req) && isfield(req,'extra') && isstruct(req.extra) && isfield(req.extra,name) && ~isempty(req.extra.(name))
                tf = logical(req.extra.(name)); return;
            end
        end

        function [spec, relinkContext] = relinkSpecFromRequest(req)
            % relinkSpecFromRequest  Normalize relink selection and originating page.
            relinkContext = struct('originatingPage','analysis_manager');
            if isfield(req,'originatingPage')
                originatingPage = req.originatingPage;
                if ~((ischar(originatingPage) && isrow(originatingPage)) || ...
                        (isstring(originatingPage) && isscalar(originatingPage))) || ...
                        ~any(strcmp(originatingPage, {'analysis_manager','workbench'}))
                    error('NMAnalysisManagerUI:badRelinkOriginatingPage', ...
                        'Relink originatingPage must be analysis_manager or workbench.');
                end
                relinkContext.originatingPage = char(originatingPage);
            end
            spec = struct('newRootDir','', 'selectionKind','auto');
            pathNames = {'newRootDir','newParentDir','parentdir','rootdir'};
            for i = 1:numel(pathNames)
                if isstruct(req) && isfield(req,pathNames{i}) && ~isempty(req.(pathNames{i}))
                    spec.newRootDir = char(string(req.(pathNames{i}))); break;
                end
                if isstruct(req) && isfield(req,'extra') && isstruct(req.extra) && ...
                        isfield(req.extra,pathNames{i}) && ~isempty(req.extra.(pathNames{i}))
                    spec.newRootDir = char(string(req.extra.(pathNames{i}))); break;
                end
            end
            if isempty(spec.newRootDir) && isstruct(req) && isfield(req,'relinkSpec') && isstruct(req.relinkSpec)
                if isfield(req.relinkSpec,'newRootDir') && ~isempty(req.relinkSpec.newRootDir)
                    spec.newRootDir = char(string(req.relinkSpec.newRootDir));
                elseif isfield(req.relinkSpec,'newParentDir') && ~isempty(req.relinkSpec.newParentDir)
                    spec.newRootDir = char(string(req.relinkSpec.newParentDir));
                end
            end
            if isempty(spec.newRootDir)
                error('NMAnalysisManagerUI:missingRelinkRoot', 'No new analysis root or parent directory was supplied.');
            end

            if isstruct(req) && isfield(req,'selectionKind') && ~isempty(req.selectionKind)
                spec.selectionKind = char(string(req.selectionKind));
            elseif isstruct(req) && isfield(req,'extra') && isstruct(req.extra) && ...
                    isfield(req.extra,'selectionKind') && ~isempty(req.extra.selectionKind)
                spec.selectionKind = char(string(req.extra.selectionKind));
            elseif isstruct(req) && isfield(req,'relinkSpec') && isstruct(req.relinkSpec) && ...
                    isfield(req.relinkSpec,'selectionKind') && ~isempty(req.relinkSpec.selectionKind)
                spec.selectionKind = char(string(req.relinkSpec.selectionKind));
            end
        end

        function plan = requestRuntimePlan(req)
            plan = struct();
            if isstruct(req) && isfield(req,'runtimePlan') && isstruct(req.runtimePlan)
                plan = req.runtimePlan;
            elseif isstruct(req) && isfield(req,'extra') && isstruct(req.extra) && isfield(req.extra,'runtimePlan') && isstruct(req.extra.runtimePlan)
                plan = req.extra.runtimePlan;
            end
            if ~isfield(plan,'analysisIndex') || isempty(plan.analysisIndex)
                plan.analysisIndex = NMAnalysisManagerUI.requestAnalysisIndex(req);
            end
        end

        function out = serviceOK(op, message, state, details)
            out = details;
            out.ok = true;
            out.message = message;
            out.operation = op;
            if ~isempty(state), out.state = state; end
            out.strip = struct('severity','ok','text',message);
        end

        function out = serviceError(op, ME, fallbackMessage)
            out = NMUIErrorTools.exceptionStruct(ME, op, fallbackMessage, 2);
            out.messages = NMDataIOMessageTools.fromException(ME, ['NMAnalysisManagerUI.' op]);
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the Analysis Manager UI text-writer entry point.
            %
            %   NMAnalysisManagerUI.writeTextFile(path,txt) writes generated shell files through the
            %   shared serialization helper and retains the historical fprintf-based writer semantics.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMAnalysisManagerUI:writeFailed', 'Could not write %s.', 'fprintf-s');
        end
    end
end

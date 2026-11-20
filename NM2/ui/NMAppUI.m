classdef NMAppUI
% NMAppUI
% -------------------------------------------------------------------------
% App-level browser UI launcher/dispatcher for NeuroMiner.
%
% The default entry point is the NM workbench.  Existing module-specific
% entry points remain available for standalone/debug scenarios, while the
% workbench can host validated modules as child pages in one shared bridge
% session.
% -------------------------------------------------------------------------

    methods (Static)
        function NM = open(NM, outDir, ctx, port, initialPage, sessionOptions, varargin)
            % open  Launch the NM 2.0 app shell at the requested page.
            %
            % Creates an app-level session state, exports the workbench shell, starts the local browser
            % bridge and imports the session NM after the browser closes. It is the primary interactive
            % entry point for multi-page NM 2.0 use. sessionOptions carries explicit
            % startup query parameters from openWorkbench. This launcher never
            % discovers abandoned sessions or asks to recover a previous run.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_app_ui'); end
            if nargin < 3 || isempty(ctx), ctx = struct(); end
            if nargin < 4, port = []; end
            if nargin < 5 || isempty(initialPage), initialPage = 'landing'; end
            if nargin < 6, sessionOptions = struct(); end
            if ~isstruct(ctx), ctx = struct(); end
            trackSession = ~isempty(varargin) && logical(varargin{1});
            NM = NMDataIOFeatureQCTools.normalizePersistedNMQC(NM);

            while true
                app = NMAppUI.createAppState(NM, ctx, initialPage);
                paths = NMAppUI.export(app, outDir, ctx);
                if trackSession
                    global UI
                    UI.sessionTmpDir = paths.tmpDir;
                end
                NMUIStateTools.initialize(paths.tmpDir, NM, initialPage);
                handler = @(req, tmpDir) NMAppUI.handleMatlabService(app, req, tmpDir, ctx);
                uiTarget = 'browser-default';
                if isstruct(ctx) && isfield(ctx,'uiTarget') && ~isempty(ctx.uiTarget)
                    uiTarget = char(string(ctx.uiTarget));
                end

                if ~isfield(sessionOptions,'InitialQuery') && strcmp(initialPage,'dataio') && isfield(ctx,'NMAppDataIOScope') && ~isempty(ctx.NMAppDataIOScope)
                    if strcmpi(char(string(ctx.NMAppDataIOScope)),'oocv')
                        sessionOptions.InitialQuery = struct('moduleKey','oocv_dataio');
                    elseif strcmpi(char(string(ctx.NMAppDataIOScope)),'training')
                        sessionOptions.InitialQuery = struct('moduleKey','dataio');
                    end
                end
                [~, bridgeResult] = nm_open_ui(paths.webDir, port, paths.entryHtml, handler, uiTarget, sessionOptions);

                NM = NMAppUI.importUpdated(app, paths, ctx);
                unfinished = isstruct(bridgeResult) && isfield(bridgeResult,'unfinished') && logical(bridgeResult.unfinished);
                if ~unfinished
                    NMUIStateTools.remove(paths.tmpDir);
                else
                    % Intentional Quit after browser loss returns the materialized NM to
                    % the caller while retaining the UI checkpoint. Keep its compatibility
                    % fingerprint aligned with that returned NM for a later restart.
                    NMUIStateTools.refreshContext(paths.tmpDir, NM);
                end
                restartRequested = isstruct(bridgeResult) && isfield(bridgeResult,'restartRequested') && logical(bridgeResult.restartRequested);
                restartReady = restartRequested && isfield(bridgeResult,'restartReady') && logical(bridgeResult.restartReady);
                if restartRequested && ~restartReady
                    return
                end
                if ~restartReady
                    break
                end
                initialPage = 'landing';
                sessionOptions = struct();
                ctx = NMAppUI.freshGraphicsRestartContext(ctx);
            end
        end

        function ctx = freshGraphicsRestartContext(ctx)
            % Drop only session/navigation identity before the explicit GPU-host restart.
            if ~isstruct(ctx), ctx = struct(); return; end
            fields = {'NMAppSharedSession','NMAppWebDir','NMAppTmpDir','NMAppRecoveredSession', ...
                'NMAppCaller','NMAppReturnPage','NMAppChildPage','NMAppDataIOScope'};
            present = fields(isfield(ctx,fields));
            if ~isempty(present), ctx = rmfield(ctx,present); end
        end

        function NM = openWorkbench(NM, outDir, ctx, port, applicationStartup)
            % openWorkbench  Launch the workbench, optionally recovering at nm startup.
            %
            % Authority and flow
            %   nm.m alone supplies applicationStartup=true. Omitted/false opens
            %   a workbench without abandoned-session discovery. Shared-session
            %   contexts never scan. Child navigation uses prepareChildPage and
            %   returnFromChildPage inside the existing bridge, not this launcher.
            % Side effects and failure semantics
            %   At application startup, scans isolated session metadata and asks
            %   before adopting/discarding a checkpoint via NMUIStateTools. Its
            %   errors propagate. No scientific payload is inferred from STATE.
            %   Accepted recovery passes the existing directory/context and
            %   navigation query to open; live-browser reconnect stays in the bridge.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_app_ui'); end
            if nargin < 3 || isempty(ctx), ctx = struct(); end
            if nargin < 4, port = []; end
            if nargin < 5, applicationStartup = false; end
            if ~islogical(applicationStartup) || ~isscalar(applicationStartup)
                error('NMAppUI:invalidApplicationStartup','applicationStartup must be a scalar logical.');
            end
            initialPage = 'landing';
            recovered = false;
            recoveryModuleKey = '';
            if ~isstruct(ctx), ctx = struct(); end
            isShared = isfield(ctx,'NMAppSharedSession') && ~isempty(ctx.NMAppSharedSession) && logical(ctx.NMAppSharedSession);
            if applicationStartup && ~isShared
                recoveryRoot = NMUISessionTools.sessionRoot(outDir, 'nm_app_ui');
                candidates = NMUIStateTools.findRecoverable(NM, recoveryRoot);
                [recoveryAction, recoveryCandidate] = NMUIStateTools.prompt(candidates);
                if strcmp(recoveryAction,'dismiss')
                    NMUIStateTools.quiesce(recoveryCandidate, false);
                    NMUIStateTools.remove(recoveryCandidate.tmpDir);
                elseif strcmp(recoveryAction,'recover')
                    NMUIStateTools.quiesce(recoveryCandidate, true);
                    NMUIStateTools.refreshContext(recoveryCandidate.tmpDir, NM);
                    ctx.NMAppSharedSession = true;
                    ctx.NMAppWebDir = recoveryCandidate.webDir;
                    ctx.NMAppTmpDir = recoveryCandidate.tmpDir;
                    ctx.NMAppRecoveredSession = true;
                    ctx.showStartupSplash = false;
                    initialPage = NMUIStateTools.recoveryPage(recoveryCandidate.state, initialPage);
                    recoveryModuleKey = NMUIStateTools.recoveryModuleKey(recoveryCandidate.state);
                    recoveryReturnToWorkbench = NMUIStateTools.recoveryReturnToWorkbench(recoveryCandidate.state);
                    if recoveryReturnToWorkbench || ~strcmp(initialPage,'landing')
                        ctx.NMAppCaller = 'workbench';
                        ctx.NMAppReturnPage = NMUIStateTools.recoveryReturnPage(recoveryCandidate.state);
                        ctx.NMAppChildPage = char(string(initialPage));
                    end
                    if strcmp(initialPage,'dataio')
                        if strcmpi(recoveryModuleKey,'oocv_dataio'), ctx.NMAppDataIOScope = 'oocv';
                        elseif strcmpi(recoveryModuleKey,'dataio'), ctx.NMAppDataIOScope = 'training'; end
                    end
                    if ~strcmp(initialPage,'landing')
                        % Recovery starts in a child; refresh the reused workbench shell now.
                        state = NMWorkbenchUI.stateFromNM(NM, ctx);
                        NMWorkbenchUI.writeShell(state, recoveryCandidate.webDir, recoveryCandidate.tmpDir);
                    end
                    recovered = true;
                end
            end

            sessionOptions = struct();
            if recovered && ~isempty(recoveryModuleKey)
                sessionOptions.InitialQuery = struct('moduleKey',recoveryModuleKey);
            end
            NM = NMAppUI.open(NM, outDir, ctx, port, initialPage, sessionOptions, applicationStartup);
        end

        function NM = openTemplate(NM, outDir, ctx, port)
            % openTemplate  Open the template configurator from the app shell.
            %
            % Builds an app state with the requested initial page and delegates to open so that session
            % export, browser launch and post-close NM import follow the same lifecycle as other NM 2.0
            % pages.

            if nargin < 2, outDir = []; end
            if nargin < 3, ctx = struct(); end
            if nargin < 4, port = []; end
            NM = NMAppUI.open(NM, outDir, ctx, port, 'template');
        end

        function NM = openDataIO(NM, outDir, ctx, port)
            % openDataIO  Open the DataIO/import browser from the app shell.
            %
            % Builds an app state with the requested initial page and delegates to open so that session
            % export, browser launch and post-close NM import follow the same lifecycle as other NM 2.0
            % pages.

            if nargin < 2, outDir = []; end
            if nargin < 3, ctx = struct(); end
            if nargin < 4, port = []; end
            NM = NMAppUI.open(NM, outDir, ctx, port, 'dataio');
        end

        function NM = openAnalysisManager(NM, outDir, ctx, port)
            % openAnalysisManager  Open the analysis manager from the app shell.
            %
            % Builds an app state with the requested initial page and delegates to open so that session
            % export, browser launch and post-close NM import follow the same lifecycle as other NM 2.0
            % pages.

            if nargin < 2, outDir = []; end
            if nargin < 3, ctx = struct(); end
            if nargin < 4, port = []; end
            NM = NMAppUI.open(NM, outDir, ctx, port, 'analysis_manager');
        end

        function NM = openPreprocessRunner(NM, outDir, ctx, port)
            % openPreprocessRunner  Open the preprocessing runner from the app shell.
            %
            % Builds an app state with the requested initial page and delegates to open so that session
            % export, browser launch and post-close NM import follow the same lifecycle as other NM 2.0
            % pages.

            if nargin < 2, outDir = []; end
            if nargin < 3, ctx = struct(); end
            if nargin < 4, port = []; end
            NM = NMAppUI.open(NM, outDir, ctx, port, 'preprocess');
        end

        function NM = openMLOptimizer(NM, outDir, ctx, port)
            % openMLOptimizer  Open the ML training runner from the app shell.
            %
            % Builds an app state with the requested initial page and delegates to open so that session
            % export, browser launch and post-close NM import follow the same lifecycle as other NM 2.0
            % pages.

            if nargin < 2, outDir = []; end
            if nargin < 3, ctx = struct(); end
            if nargin < 4, port = []; end
            NM = NMAppUI.open(NM, outDir, ctx, port, 'mltrain');
        end

        function NM = openVisualization(NM, outDir, ctx, port)
            % openVisualization  Open the visualization runner from the app shell.
            %
            % Builds an app state with the requested initial page and delegates to open so that session
            % export, browser launch and post-close NM import follow the same lifecycle as other NM 2.0
            % pages.

            if nargin < 2, outDir = []; end
            if nargin < 3, ctx = struct(); end
            if nargin < 4, port = []; end
            NM = NMAppUI.open(NM, outDir, ctx, port, 'visualization');
        end

        function NM = openMLInterpreter(NM, outDir, ctx, port)
            % openMLInterpreter  Open the ML-interpretation runner from the app shell.
            %
            % Builds an app state with the requested initial page and delegates to open so that session
            % export, browser launch and post-close NM import follow the same lifecycle as other NM 2.0
            % pages.

            if nargin < 2, outDir = []; end
            if nargin < 3, ctx = struct(); end
            if nargin < 4, port = []; end
            NM = NMAppUI.open(NM, outDir, ctx, port, 'mli');
        end

        function paths = export(app, outDir, ctx)
            % export  Export the app workbench shell and session resources.
            %
            % Creates the top-level workbench HTML, writes page-routing state, copies shared UI assets
            % and stores the NM session object for child-page services. This method prepares the app
            % shell but does not launch the browser.

            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_app_ui'); end
            if nargin < 3, ctx = struct(); end

            switch lower(app.InitialPage)
                case {'landing','workbench','main','menu'}
                    paths = NMWorkbenchUI.export(app.NM, outDir, ctx);
                    paths.appPage = 'workbench';
                    paths.entryHtml = 'nm_workbench.html';
                    paths.entryHtmlPath = paths.workbenchHtml;
                case {'template','train_template','train','config'}
                    paths = NMTrainTemplateUI.export(app.TrainTemplateOrch, outDir, ctx);
                    paths.appPage = 'template';
                    paths.entryHtml = 'nm_train_template_menu.html';
                    paths.entryHtmlPath = paths.menuHtml;
                case {'dataio','data','loaddata','import'}
                    paths = NMDataIOUI.export(app.NM, outDir, ctx);
                    paths.appPage = 'dataio';
                    paths.entryHtml = 'nm_dataio_overview.html';
                    paths.entryHtmlPath = paths.dataioHtml;
                case {'analysis_manager','analysis','analyses','manager'}
                    paths = NMAnalysisManagerUI.export(app.NM, outDir, ctx);
                    paths.appPage = 'analysis_manager';
                    paths.entryHtml = 'nm_analysis_manager.html';
                    paths.entryHtmlPath = paths.analysisManagerHtml;
                case {'preprocess','preprocessing','preprocess_runner','run_preprocessing'}
                    paths = NMPreprocessRunnerUI.export(app.NM, outDir, ctx);
                    paths.appPage = 'preprocess_runner';
                    paths.entryHtml = 'nm_preprocess_runner.html';
                    paths.entryHtmlPath = paths.preprocessRunnerHtml;
                case {'mltrain','ml_training','ml_optimizer','ml_train_runner','run_ml_training'}
                    paths = NMMLOptimizerRunnerUI.export(app.NM, outDir, ctx);
                    paths.appPage = 'ml_train_runner';
                    paths.entryHtml = 'nm_ml_train_runner.html';
                    paths.entryHtmlPath = paths.mlTrainRunnerHtml;
                case {'visualization','vis','vis_runner','model_visualization','run_visualization'}
                    paths = NMVisRunnerUI.export(app.NM, outDir, ctx);
                    paths.appPage = 'vis_runner';
                    paths.entryHtml = 'nm_vis_runner.html';
                    paths.entryHtmlPath = paths.visRunnerHtml;
                case {'mli','ml_interpretation','ml_interpreter','mli_runner','run_mli'}
                    paths = NMMLIRunnerUI.export(app.NM, outDir, ctx);
                    paths.appPage = 'mli_runner';
                    paths.entryHtml = 'nm_mli_runner.html';
                    paths.entryHtmlPath = paths.mliRunnerHtml;
                case {'model_export','export','export_models','model_export_runner','run_model_export'}
                    paths = NMModelExportRunnerUI.export(app.NM, outDir, ctx);
                    paths.appPage = 'model_export_runner';
                    paths.entryHtml = 'nm_model_export_runner.html';
                    paths.entryHtmlPath = paths.modelExportRunnerHtml;
                case {'oocv','oocv_runner','oocv_application','run_oocv'}
                    paths = NMOOCVRunnerUI.export(app.NM, outDir, ctx);
                    paths.appPage = 'oocv_runner';
                    paths.entryHtml = 'nm_oocv_runner.html';
                    paths.entryHtmlPath = paths.oocvRunnerHtml;
                case {'synth_coordinator','synth'}
                    paths = NMSynthCoordinatorUI.export(app.NM, outDir, ctx);
                    paths.appPage = 'synth_coordinator';
                    paths.entryHtml = 'nm_synth_coordinator.html';
                    paths.entryHtmlPath = paths.html;
                case {'results_alpha','results_viewer_alpha','browser_results','nm_results_viewer_alpha'}
                    paths = NMResultsViewerUI.export(app.NM, outDir, ctx);
                    paths.appPage = 'results_viewer_alpha';
                    paths.entryHtml = 'nm_results_viewer_alpha.html';
                    paths.entryHtmlPath = paths.resultsViewerAlphaHtml;
                otherwise
                    error('NMAppUI:unsupportedPage', ...
                        'Unsupported NM browser app page: %s', app.InitialPage);
            end
        end

        function NM = importUpdated(app, paths, ctx)
            % importUpdated  Recover the current NM from an app-shell session.
            %
            % Reads the session NM written by workbench or child-page service calls and returns it to the
            % MATLAB caller. It also clears the session cache unless the context explicitly keeps the
            % session alive.
            %
            % ctx.materializeTemplateOnClose: exposes the materialize template on close execution-context value to preprocessing/runtime code.

            if nargin < 3, ctx = struct(); end

            switch lower(app.InitialPage)
                case {'landing','workbench','main','menu'}
                    NM = NMWorkbenchUI.importUpdated(app.NM, paths, ctx);
                case {'template','train_template','train','config'}
                    app.TrainTemplateOrch = NMTrainTemplateUI.importUpdated(app.TrainTemplateOrch, paths, ctx);
                    materializeOnClose = isstruct(ctx) && isfield(ctx,'materializeTemplateOnClose') && ...
                        logical(ctx.materializeTemplateOnClose);
                    if materializeOnClose
                        % nm.m's main parameter-workspace action must return an
                        % executable legacy TrainParam snapshot. Standalone
                        % browser launches keep the lighter getNM() behaviour so
                        % embedded editor returns do not materialize expensive
                        % preprocessing side effects unless explicitly requested.
                        NM = app.TrainTemplateOrch.toNM(app.TrainTemplateOrch.NM, ctx);
                    else
                        NM = app.TrainTemplateOrch.getNM();
                    end
                case {'dataio','data','loaddata','import'}
                    NM = NMDataIOUI.importUpdated(app.NM, paths, ctx);
                case {'analysis_manager','analysis','analyses','manager'}
                    NM = NMAnalysisManagerUI.importUpdated(app.NM, paths, ctx);
                case {'preprocess','preprocessing','preprocess_runner','run_preprocessing'}
                    NM = NMPreprocessRunnerUI.importUpdated(app.NM, paths, ctx);
                case {'mltrain','ml_training','ml_optimizer','ml_train_runner','run_ml_training'}
                    NM = NMMLOptimizerRunnerUI.importUpdated(app.NM, paths, ctx);
                case {'visualization','vis','vis_runner','model_visualization','run_visualization'}
                    NM = NMVisRunnerUI.importUpdated(app.NM, paths, ctx);
                case {'mli','ml_interpretation','ml_interpreter','mli_runner','run_mli'}
                    NM = NMMLIRunnerUI.importUpdated(app.NM, paths, ctx);
                case {'model_export','export','export_models','model_export_runner','run_model_export'}
                    NM = NMModelExportRunnerUI.importUpdated(app.NM, paths, ctx);
                case {'oocv','oocv_runner','oocv_application','run_oocv'}
                    NM = NMOOCVRunnerUI.importUpdated(app.NM, paths, ctx);
                case {'synth_coordinator','synth'}
                    NM = app.NM;
                case {'results_alpha','results_viewer_alpha','browser_results','nm_results_viewer_alpha'}
                    NM = NMResultsViewerUI.importUpdated(app.NM, paths, ctx);
                otherwise
                    NM = app.NM;
            end
            app.NM = NM;
        end

        function [handled, out] = handleMatlabService(app, req, tmpDir, ctx)
            % handleMatlabService  Route browser requests between the workbench and child pages.
            %
            % Recognizes app-level operations, loads session state, dispatches workbench actions such as
            % locking/import transitions, and forwards page-specific requests to the owning UI service
            % handler. The method is the central bridge dispatcher for the browser shell.

            handled = false;
            out = struct();
            if nargin < 4, ctx = struct(); end

            op = NMAppUI.requestOperation(req);
            if isempty(op), return; end
            opl = lower(op);

            if startsWith(opl, 'app_')
                handled = true;
                out = NMAppUI.handleAppService(app, req, tmpDir, ctx);
                return;
            end

            if startsWith(opl, 'train_template_') || strcmp(opl, 'preproc_resolve_rule_state')
                if isempty(app.TrainTemplateOrch)
                    [sessionNM, ~] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                    app.TrainTemplateOrch = NMTrainTemplateOrchestrator.fromNM(sessionNM, 1, ctx);
                end
                pageCtx = NMAppUI.pageServiceContext(app, ctx, tmpDir, 'template');
                [handled, out] = NMTrainTemplateUI.handleMatlabService(app.TrainTemplateOrch, req, tmpDir, pageCtx);
                return;
            end

            if startsWith(opl, 'dataio_')
                [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                if ok, app.NM = sessionNM; end
                dataIOScope = '';
                if isstruct(app.Context) && isfield(app.Context,'NMAppDataIOScope') && ~isempty(app.Context.NMAppDataIOScope)
                    dataIOScope = lower(strtrim(char(string(app.Context.NMAppDataIOScope))));
                end
                pageCtx = NMAppUI.pageServiceContext(app, ctx, tmpDir, 'dataio');
                if ~isempty(dataIOScope), pageCtx.NMAppDataIOScope = dataIOScope; end
                [handled, out] = NMDataIOUI.handleMatlabService(app.NM, req, tmpDir, pageCtx);
                if handled && isstruct(out) && isfield(out,'state') && isstruct(out.state) && ~isempty(dataIOScope)
                    out.state = NMAppUI.projectDataIOState(out.state, dataIOScope);
                end
                return;
            end

            if startsWith(opl, 'analysis_manager_')
                % The analysis-manager service owns the session-NM load/save for
                % each operation. Avoid an app-level pre-load and unconditional
                % post-load here: create/overwrite actions snapshot large NM
                % structures, and copying the same session object around this
                % call makes the browser action visibly slower without changing
                % the authoritative session state. returnFromChildPage performs
                % the required rehydration before the workbench is shown again.
                pageCtx = NMAppUI.pageServiceContext(app, ctx, tmpDir, 'analysis_manager');
                [handled, out] = NMAnalysisManagerUI.handleMatlabService(app.NM, req, tmpDir, pageCtx);
                return;
            end

            if startsWith(opl, 'preprocess_runner_')
                [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                if ok, app.NM = sessionNM; end
                pageCtx = NMAppUI.pageServiceContext(app, ctx, tmpDir, 'preprocess_runner');
                [handled, out] = NMPreprocessRunnerUI.handleMatlabService(app.NM, req, tmpDir, pageCtx);
                if handled && isstruct(out) && isfield(out,'state')
                    [sessionNM2, ok2] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                    if ok2, app.NM = sessionNM2; end
                end
                return;
            end

            if startsWith(opl, 'ml_train_runner_')
                [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                if ok, app.NM = sessionNM; end
                pageCtx = NMAppUI.pageServiceContext(app, ctx, tmpDir, 'ml_train_runner');
                [handled, out] = NMMLOptimizerRunnerUI.handleMatlabService(app.NM, req, tmpDir, pageCtx);
                if handled && isstruct(out) && isfield(out,'state')
                    [sessionNM2, ok2] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                    if ok2, app.NM = sessionNM2; end
                end
                return;
            end

            if startsWith(opl, 'vis_runner_')
                [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                if ok, app.NM = sessionNM; end
                pageCtx = NMAppUI.pageServiceContext(app, ctx, tmpDir, 'vis_runner');
                [handled, out] = NMVisRunnerUI.handleMatlabService(app.NM, req, tmpDir, pageCtx);
                if handled && isstruct(out) && isfield(out,'state')
                    [sessionNM2, ok2] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                    if ok2, app.NM = sessionNM2; end
                end
                return;
            end

            if startsWith(opl, 'mli_runner_')
                [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                if ok, app.NM = sessionNM; end
                pageCtx = NMAppUI.pageServiceContext(app, ctx, tmpDir, 'mli_runner');
                [handled, out] = NMMLIRunnerUI.handleMatlabService(app.NM, req, tmpDir, pageCtx);
                if handled && isstruct(out) && isfield(out,'state')
                    [sessionNM2, ok2] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                    if ok2, app.NM = sessionNM2; end
                end
                return;
            end

            if startsWith(opl, 'model_export_runner_')
                [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                if ok, app.NM = sessionNM; end
                pageCtx = NMAppUI.pageServiceContext(app, ctx, tmpDir, 'model_export_runner');
                [handled, out] = NMModelExportRunnerUI.handleMatlabService(app.NM, req, tmpDir, pageCtx);
                if handled && isstruct(out) && isfield(out,'state')
                    [sessionNM2, ok2] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                    if ok2, app.NM = sessionNM2; end
                end
                return;
            end

            if startsWith(opl, 'oocv_runner_')
                [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                if ok, app.NM = sessionNM; end
                pageCtx = NMAppUI.pageServiceContext(app, ctx, tmpDir, 'oocv_runner');
                [handled, out] = NMOOCVRunnerUI.handleMatlabService(app.NM, req, tmpDir, pageCtx);
                if handled && isstruct(out) && isfield(out,'state')
                    [sessionNM2, ok2] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                    if ok2, app.NM = sessionNM2; end
                end
                return;
            end

            if startsWith(opl, 'synth_coordinator_')
                pageCtx = NMAppUI.pageServiceContext(app, ctx, tmpDir, 'synth_coordinator');
                [handled, out] = NMSynthCoordinatorUI.handleMatlabService(app.NM, req, tmpDir, pageCtx);
                return;
            end

            if startsWith(opl, 'results_viewer_')
                % Viewer, report, and output operations share one Results Viewer service
                % boundary and must be routed before generic bridge fallback.
                [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                if ok, app.NM = sessionNM; end
                pageCtx = NMAppUI.pageServiceContext(app, ctx, tmpDir, 'results_viewer_alpha');
                [handled, out] = NMResultsViewerUI.handleMatlabService(app.NM, req, tmpDir, pageCtx);
                if handled && isstruct(out) && isfield(out,'state')
                    [sessionNM2, ok2] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                    if ok2, app.NM = sessionNM2; end
                end
                return;
            end

        end

        function pageCtx = pageServiceContext(app, ctx, tmpDir, page)
            % pageServiceContext  Derive context passed to a child page service/export call.
            %
            % Combines app context with the current web/tmp directories and target page identifier so
            % child UIs inherit navigation, profile and fast-open behavior without depending on global
            % state.

            pageCtx = ctx;
            isWorkbench = any(strcmp(lower(app.InitialPage), {'landing','workbench','main','menu'}));
            if isWorkbench && ~isempty(tmpDir)
                webDir = fileparts(char(string(tmpDir)));
                if ~isempty(webDir)
                    pageCtx = NMUISessionTools.childContext(ctx, webDir, tmpDir, page);
                end
            end
        end

        function app = createAppState(NM, ctx, initialPage)
            % createAppState  Initialize the mutable app-session object used by the bridge.
            %
            % Stores the input NM, launch context, initial page and optional train-template orchestrator
            % in a handle object shared by bridge closures. This keeps browser navigation state explicit
            % during a multi-page session.


            app = NMAppSessionState();
            app.NM = NM;
            app.Context = ctx;
            app.InitialPage = char(string(initialPage));
            app.TrainTemplateOrch = [];

            switch lower(app.InitialPage)
                case {'landing','workbench','main','menu'}
                    % Workbench starts lightweight; child pages prepare their
                    % page-specific state inside the shared session on demand.
                case {'template','train_template','train','config'}
                    app.TrainTemplateOrch = NMTrainTemplateOrchestrator.fromNM(NM, 1, ctx);
                case {'dataio','data','loaddata','import'}
                    % DataIO uses the shared session-NM store.
                case {'analysis_manager','analysis','analyses','manager'}
                    % Analysis-manager state is exported by NMAnalysisManagerUI.
                case {'preprocess','preprocessing','preprocess_runner','run_preprocessing'}
                    % Preprocessing runner uses the shared session-NM store.
                case {'mltrain','ml_training','ml_optimizer','ml_train_runner','run_ml_training'}
                    % ML training runner uses the shared session-NM store.
                case {'visualization','vis','vis_runner','model_visualization','run_visualization'}
                    % Visualization runner uses the shared session-NM store.
                case {'mli','ml_interpretation','ml_interpreter','mli_runner','run_mli'}
                    % ML-interpretation runner uses the shared session-NM store.
                case {'model_export','export','export_models','model_export_runner','run_model_export'}
                    % Model-export runner uses the shared session-NM store.
                case {'oocv','oocv_runner','oocv_application','run_oocv'}
                    % OOCV runner uses the shared session-NM store.
                case {'synth_coordinator','synth'}
                    % SYNTH coordinator uses the shared session-NM store.
                case {'results_alpha','results_viewer_alpha','browser_results','nm_results_viewer_alpha'}
                    % Alpha browser Results Viewer uses the shared session-NM store.
                otherwise
                    error('NMAppUI:unsupportedPage', ...
                        'Unsupported NM browser app page: %s', app.InitialPage);
            end
        end

        function op = requestOperation(req)
            % requestOperation  Extract the operation token from a browser request.
            %
            % Reads either operation or action fields and normalizes them to a character command used by
            % service dispatch. It performs no validation beyond empty handling.
            %
            % req.action: selects the requested service action in a UI bridge or runner dispatch request.
            % req.operation: selects the requested operation within an action family.

            op = '';
            if isstruct(req) && isfield(req, 'operation') && ~isempty(req.operation)
                op = char(string(req.operation));
            elseif isstruct(req) && isfield(req, 'action') && ~isempty(req.action)
                op = char(string(req.action));
            end
        end

        function out = handleAppService(app, req, tmpDir, ctx)
            % handleAppService  Execute app-level workbench service operations.
            %
            % Handles operations that belong to the shell rather than to a child page, including page
            % preparation, returns, locking transitions and result-viewer launch preparation. It returns
            % structured ok/message payloads for the browser.

            doProfile = NMAppUI.profileEnabled();
            tTotal = tic;
            op = lower(NMAppUI.requestOperation(req));
            profileId = NMAppUI.requestChar(req, 'profileId', '-');
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s] app service ENTER op=%s\n', profileId, op);
            switch op
                case {'app_workbench_save_nm','app_workbench_load_nm'}
                    fp = req.path;
                    if strcmp(op, 'app_workbench_save_nm')
                        NM = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                        nmInfo = whos('NM');
                        if nmInfo.bytes < 2^31
                            save(fp, 'NM', '-v7');
                        else
                            save(fp, 'NM', '-v7.3');
                        end
                        out = struct('ok',true,'message',sprintf('NM structure saved to %s.',fp));
                    else
                        S = load(fp,'NM');
                        if ~isfield(S,'NM') || ~isstruct(S.NM) || ~isscalar(S.NM) || ...
                                ~isfield(S.NM,'defs') || ~isstruct(S.NM.defs)
                            error('NMAppUI:invalidNMFile','File %s does not contain a valid NM structure.',fp);
                        end
                        NM = NMDataIOFeatureQCTools.normalizePersistedNMQC(S.NM);
                        NMDataIOUI.saveSessionNM(NM, tmpDir);
                        app.NM = NM;
                        app.TrainTemplateOrch = [];
                        priorUIState = NMUIStateTools.read(tmpDir);
                        NMUIStateTools.remove(tmpDir);
                        newUIState = NMUIStateTools.initialize(tmpDir, NM, 'workbench');
                        newUIState.transport = priorUIState.transport;
                        NMUIStateTools.write(tmpDir, newUIState);
                        out = struct('ok',true,'message',sprintf('NM structure loaded from %s.',fp));
                    end
                case 'app_workbench_refresh'
                    t = tic;
                    [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                    NMAppUI.profileLog(doProfile, '[nm-prof]   app workbench loadSessionNM: %.3fs (ok=%d)\n', toc(t), double(ok));
                    if ok, app.NM = sessionNM; end
                    NMWorkbenchUI.completeInitialPresentation(fileparts(tmpDir), tmpDir);
                    t = tic;
                    state = NMWorkbenchUI.stateFromNM(app.NM, ctx);
                    state.showStartupSplash = false;
                    NMAppUI.profileLog(doProfile, '[nm-prof]   app workbench stateFromNM:  %.3fs\n', toc(t));
                    out = struct('ok', true, 'message', 'Workbench refreshed.', 'state', state);
                case 'app_workbench_lock_training_data'
                    out = NMAppUI.lockTrainingDataFromWorkbench(app, tmpDir, ctx);
                case 'app_workbench_lock_models'
                    out = NMAppUI.lockModelsFromWorkbench(app, tmpDir, ctx);
                case 'app_workbench_scramble_lock_models'
                    out = NMAppUI.scrambleAndLockModelsFromWorkbench(app, tmpDir, ctx);
                case 'app_prepare_page'
                    out = NMAppUI.prepareChildPage(app, req, tmpDir, ctx);
                case 'app_child_return'
                    out = NMAppUI.returnFromChildPage(app, req, tmpDir, ctx);
                otherwise
                    out = struct('ok', false, 'message', sprintf('Unsupported app service operation: %s', op), ...
                        'error', sprintf('Unsupported app service operation: %s', op));
            end
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s] app service TOTAL op=%s: %.3fs\n', profileId, op, toc(tTotal));
        end

        function out = lockTrainingDataFromWorkbench(app, tmpDir, ctx)
            % lockTrainingDataFromWorkbench  Finalize training import from the workbench.
            %
            % Loads the session NM, sets the import-finished state through the status guard path and
            % writes the updated NM back to session storage. This is the workbench transition into
            % analysis/template configuration, not a DataIO mutation routine.

            doProfile = NMAppUI.profileEnabled();
            tTotal = tic;
            try
                t = tic;
                [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                NMAppUI.profileLog(doProfile, '[nm-prof]   app lock training-data loadSessionNM: %.3fs (ok=%d)\n', toc(t), double(ok));
                if ok, app.NM = sessionNM; end
                if isstruct(app.NM) && isfield(app.NM,'defs') && isstruct(app.NM.defs) && ...
                        isfield(app.NM.defs,'import_finished') && logical(app.NM.defs.import_finished)
                    state = NMWorkbenchUI.stateFromNM(app.NM, ctx);
                    out = struct('ok', true, 'message', 'Training data are already locked/finalized.', 'state', state);
                    NMAppUI.profileLog(doProfile, '[nm-prof] app lockTrainingDataFromWorkbench TOTAL already-locked: %.3fs\n', toc(tTotal));
                    return;
                end
                [NM2, messages] = NMDataIOBrowserModeTools.finalizeTrainingImport(app.NM);
                strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Training data import finalized.');
                if NMDataIOMessageTools.hasFatal(messages)
                    out = struct('ok', false, 'blocking', true, 'message', strip.text, ...
                        'strip', strip, 'messages', messages, 'operation', 'app_workbench_lock_training_data');
                    NMAppUI.profileLog(doProfile, '[nm-prof] app lockTrainingDataFromWorkbench TOTAL blocked: %.3fs\n', toc(tTotal));
                    return;
                end
                app.NM = NM2;
                NMDataIOUI.saveSessionNM(app.NM, tmpDir);
                state = NMWorkbenchUI.stateFromNM(app.NM, ctx);
                out = struct('ok', true, 'message', strip.text, 'strip', strip, ...
                    'messages', messages, 'state', state, 'operation', 'app_workbench_lock_training_data');
            catch ME % nm2-allow: NMUIErrorTools preserves the stack while DataIO keeps domain diagnostics
                messages = NMDataIOMessageTools.fromException(ME, 'NMAppUI.lockTrainingDataFromWorkbench');
                strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Locking training data failed.');
                out = NMUIErrorTools.exceptionStruct(ME, 'app_workbench_lock_training_data', 'Locking training data failed.', 2);
                out.strip = strip;
                out.messages = messages;
                out.message = strip.text;
            end
            NMAppUI.profileLog(doProfile, '[nm-prof] app lockTrainingDataFromWorkbench TOTAL: %.3fs\n', toc(tTotal));
        end

        function out = lockModelsFromWorkbench(app, tmpDir, ctx)
            % lockModelsFromWorkbench  Activate application mode from the workbench when analyses are
            % available.
            %
            % Checks completed-analysis status through NMStatusGuardTools before locking model
            % training/application state, then persists the updated session NM. It keeps application-mode
            % activation outside DataIO import.

            doProfile = NMAppUI.profileEnabled();
            tTotal = tic;
            try
                t = tic;
                [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                NMAppUI.profileLog(doProfile, '[nm-prof]   app lock models loadSessionNM: %.3fs (ok=%d)\n', toc(t), double(ok));
                if ok, app.NM = sessionNM; end
                if isstruct(app.NM) && isfield(app.NM,'defs') && isstruct(app.NM.defs) && ...
                        isfield(app.NM.defs,'analyses_locked') && logical(app.NM.defs.analyses_locked)
                    state = NMWorkbenchUI.stateFromNM(app.NM, ctx);
                    out = struct('ok', true, 'message', 'Application/OOCV mode is already active and trained models are locked.', 'state', state);
                    NMAppUI.profileLog(doProfile, '[nm-prof] app lockModelsFromWorkbench TOTAL already-locked: %.3fs\n', toc(tTotal));
                    return;
                end
                [NM2, lockOut] = NMAnalysisManagerTools.activateApplicationMode(app.NM, struct());
                app.NM = NM2;
                NMDataIOUI.saveSessionNM(app.NM, tmpDir);
                state = NMWorkbenchUI.stateFromNM(app.NM, ctx);
                msg = 'Application/OOCV mode activated and trained models locked.';
                if isstruct(lockOut) && isfield(lockOut,'message') && ~isempty(lockOut.message)
                    msg = char(string(lockOut.message));
                end
                out = struct('ok', true, 'message', msg, 'state', state, ...
                    'operation', 'app_workbench_lock_models', 'lockReport', lockOut);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'app_workbench_lock_models', 'Locking trained models failed.', 2);
            end
            NMAppUI.profileLog(doProfile, '[nm-prof] app lockModelsFromWorkbench TOTAL: %.3fs\n', toc(tTotal));
        end


        function out = scrambleAndLockModelsFromWorkbench(app, tmpDir, ctx)
            % scrambleAndLockModelsFromWorkbench  Run the explicit model-locking stress/diagnostic
            % transition.
            %
            % Applies the same session-NM persistence pattern as normal locking while using the
            % status-guard operation intended for controlled scrambling/locking tests. Browser callers
            % receive refreshed workbench state and diagnostics.

            doProfile = NMAppUI.profileEnabled();
            tTotal = tic;
            try
                t = tic;
                [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
                NMAppUI.profileLog(doProfile, '[nm-prof]   app scramble+lock loadSessionNM: %.3fs (ok=%d)\n', toc(t), double(ok));
                if ok, app.NM = sessionNM; end
                if ~isstruct(app.NM) || ~isfield(app.NM,'defs') || ~isstruct(app.NM.defs) || ...
                        ~isfield(app.NM.defs,'export_state') || ~isstruct(app.NM.defs.export_state) || ...
                        ~isfield(app.NM.defs.export_state,'export_finished') || ~logical(app.NM.defs.export_state.export_finished)
                    error('NMAppUI:exportRequiredBeforeScramble', ...
                        'Export optimized ML models and preprocessing parameters before scrambling training data for sharing.');
                end
                [NM2, scrambleReport] = NMPrivacyTools.scrambleInputFeaturesForSharing(app.NM, struct());
                [NM2, lockOut] = NMAnalysisManagerTools.activateApplicationMode(NM2, struct());
                app.NM = NM2;
                NMDataIOUI.saveSessionNM(app.NM, tmpDir);
                state = NMWorkbenchUI.stateFromNM(app.NM, ctx);
                msg = 'Training data scrambled for sharing; Application/OOCV mode activated and trained models locked.';
                out = struct('ok', true, 'message', msg, 'state', state, ...
                    'operation', 'app_workbench_scramble_lock_models', ...
                    'scrambleReport', scrambleReport, 'lockReport', lockOut);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'app_workbench_scramble_lock_models', 'Scrambling and locking trained models failed.', 2);
            end
            NMAppUI.profileLog(doProfile, '[nm-prof] app scrambleAndLockModelsFromWorkbench TOTAL: %.3fs\n', toc(tTotal));
        end

        function out = prepareChildPage(app, req, tmpDir, ctx)
            % prepareChildPage  Export a child page and return browser navigation metadata.
            %
            % Loads the session NM, chooses the requested child module, exports that page into the shared
            % session directories and returns a route descriptor for the app shell. It is the app-level
            % adapter between workbench buttons and page-specific export methods.

            doProfile = NMAppUI.profileEnabled();
            tTotal = tic;
            page = NMAppUI.requestChar(req, 'page', '');
            moduleKey = lower(strtrim(NMAppUI.requestChar(req, 'moduleKey', '')));
            profileId = NMAppUI.requestChar(req, 'profileId', '-');
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s] app prepareChildPage ENTER page=%s\n', profileId, page);
            if isempty(page)
                out = struct('ok', false, 'message', 'No workbench page was requested.', 'error', 'Missing page.');
                NMAppUI.profileLog(doProfile, '[nm-prof] app prepareChildPage TOTAL page=<missing>: %.3fs\n', toc(tTotal));
                return;
            end
            t = tic;
            [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s]   app prepare loadSessionNM: %.3fs (ok=%d)\n', profileId, toc(t), double(ok));
            if ok, app.NM = sessionNM; end
            dataIOScope = '';
            if any(strcmp(lower(page), {'dataio','data','loaddata','import'}))
                if strcmp(moduleKey, 'dataio')
                    dataIOScope = 'training';
                elseif strcmp(moduleKey, 'oocv_dataio')
                    dataIOScope = 'oocv';
                end
                if ~isstruct(app.Context), app.Context = struct(); end
                if isempty(dataIOScope)
                    if isfield(app.Context,'NMAppDataIOScope'), app.Context = rmfield(app.Context,'NMAppDataIOScope'); end
                else
                    app.Context.NMAppDataIOScope = dataIOScope;
                end
            end
            t = tic;
            webDir = fileparts(tmpDir);
            childCtx = NMUISessionTools.childContext(ctx, webDir, tmpDir, page);
            if isfield(req,'parentPage')
                assert(strcmp(page,'template') && strcmp(req.parentPage,'synth_coordinator'), ...
                    'NMAppUI:invalidParentPage', 'Unsupported parent page for this child.');
                childCtx.NMAppReturnPage = 'nm_synth_coordinator.html';
            end
            if ~isempty(dataIOScope), childCtx.NMAppDataIOScope = dataIOScope; end
            childCtx.materializeTemplateOnClose = true;
            childCtx.NMAppFastChildOpen = true;
            childCtx.NMProfileId = profileId;
            childCtx.profile = doProfile;
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s]   app prepare child context: %.3fs\n', profileId, toc(t));

            tExport = tic;
            switch lower(page)
                case {'dataio','data','loaddata','import'}
                    paths = NMDataIOUI.export(app.NM, [], childCtx);
                    entryHtml = 'nm_dataio_overview.html';
                    entryHtmlPath = paths.dataioHtml;
                    appPage = 'dataio';
                case {'template','train_template','train','config'}
                    t = tic;
                    app.TrainTemplateOrch = NMTrainTemplateOrchestrator.fromNM(app.NM, 1, childCtx);
                    NMAppUI.profileLog(doProfile, '[nm-prof rid=%s]   app prepare template fromNM: %.3fs\n', profileId, toc(t));
                    t = tic;
                    paths = NMTrainTemplateUI.export(app.TrainTemplateOrch, [], childCtx);
                    NMAppUI.profileLog(doProfile, '[nm-prof rid=%s]   app prepare template UI export: %.3fs\n', profileId, toc(t));
                    entryHtml = 'nm_train_template_menu.html';
                    entryHtmlPath = paths.menuHtml;
                    appPage = 'template';
                case {'analysis_manager','analysis','analyses','manager'}
                    paths = NMAnalysisManagerUI.export(app.NM, [], childCtx);
                    entryHtml = 'nm_analysis_manager.html';
                    entryHtmlPath = paths.analysisManagerHtml;
                    appPage = 'analysis_manager';
                case {'preprocess','preprocessing','preprocess_runner','run_preprocessing'}
                    paths = NMPreprocessRunnerUI.export(app.NM, [], childCtx);
                    entryHtml = 'nm_preprocess_runner.html';
                    entryHtmlPath = paths.preprocessRunnerHtml;
                    appPage = 'preprocess_runner';
                case {'mltrain','ml_training','ml_optimizer','ml_train_runner','run_ml_training'}
                    paths = NMMLOptimizerRunnerUI.export(app.NM, [], childCtx);
                    entryHtml = 'nm_ml_train_runner.html';
                    entryHtmlPath = paths.mlTrainRunnerHtml;
                    appPage = 'ml_train_runner';
                case {'visualization','vis','vis_runner','model_visualization','run_visualization'}
                    paths = NMVisRunnerUI.export(app.NM, [], childCtx);
                    entryHtml = 'nm_vis_runner.html';
                    entryHtmlPath = paths.visRunnerHtml;
                    appPage = 'vis_runner';
                case {'mli','ml_interpretation','ml_interpreter','mli_runner','run_mli'}
                    paths = NMMLIRunnerUI.export(app.NM, [], childCtx);
                    entryHtml = 'nm_mli_runner.html';
                    entryHtmlPath = paths.mliRunnerHtml;
                    appPage = 'mli_runner';
                case {'model_export','export','export_models','model_export_runner','run_model_export'}
                    paths = NMModelExportRunnerUI.export(app.NM, [], childCtx);
                    entryHtml = 'nm_model_export_runner.html';
                    entryHtmlPath = paths.modelExportRunnerHtml;
                    appPage = 'model_export_runner';
                case {'oocv','oocv_runner','oocv_application','run_oocv'}
                    paths = NMOOCVRunnerUI.export(app.NM, [], childCtx);
                    entryHtml = 'nm_oocv_runner.html';
                    entryHtmlPath = paths.oocvRunnerHtml;
                    appPage = 'oocv_runner';
                case {'synth_coordinator','synth'}
                    paths = NMSynthCoordinatorUI.export(app.NM, [], childCtx);
                    entryHtml = 'nm_synth_coordinator.html';
                    entryHtmlPath = paths.html;
                    appPage = 'synth_coordinator';
                case {'results_alpha','results_viewer_alpha','browser_results','nm_results_viewer_alpha'}
                    paths = NMResultsViewerUI.export(app.NM, [], childCtx);
                    entryHtml = 'nm_results_viewer_alpha.html';
                    entryHtmlPath = paths.resultsViewerAlphaHtml;
                    appPage = 'results_viewer_alpha';
                otherwise
                    out = struct('ok', false, 'message', sprintf('Workbench page is not implemented yet: %s', page), ...
                        'error', sprintf('Workbench page is not implemented yet: %s', page));
                    return;
            end
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s]   app prepare export page=%s: %.3fs\n', profileId, appPage, toc(tExport));
            t = tic;
            out = struct('ok', true, 'message', sprintf('Prepared %s inside the active workbench session.', appPage), ...
                'page', appPage, 'entryHtml', entryHtml, 'entryHtmlPath', entryHtmlPath);
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s]   app prepare result assembly: %.3fs\n', profileId, toc(t));
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s] app prepareChildPage TOTAL page=%s: %.3fs\n', profileId, appPage, toc(tTotal));
        end

        function out = returnFromChildPage(app, req, tmpDir, ctx)
            % returnFromChildPage  Re-import state after returning from a child page.
            %
            % Calls the appropriate child UI import method, writes the resulting NM back to the app
            % session and returns refreshed workbench state. This closes the loop for child pages that
            % can update configuration or runtime state.

            doProfile = NMAppUI.profileEnabled();
            tTotal = tic;
            source = lower(NMAppUI.requestChar(req, 'source', ''));
            profileId = NMAppUI.requestChar(req, 'profileId', '-');
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s] app returnFromChildPage ENTER source=%s\n', profileId, source);
            t = tic;
            [sessionNM, ok] = NMDataIOUI.loadSessionNM(app.NM, tmpDir);
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s]   app return loadSessionNM: %.3fs (ok=%d)\n', profileId, toc(t), double(ok));
            if ok, app.NM = sessionNM; end
            t = tic;
            childCtx = NMUISessionTools.childContext(ctx, fileparts(tmpDir), tmpDir, source);
            childCtx.materializeTemplateOnClose = true;
            childCtx.NMAppKeepSessionAfterImport = true;
            childCtx.NMProfileId = profileId;
            childCtx.profile = doProfile;
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s]   app return child context: %.3fs\n', profileId, toc(t));

            try
                tImport = tic;
                switch source
                    case {'template','train_template','train_template_menu'}
                        % Template services materialize each accepted keyed change directly to the
                        % authoritative session NM. The load above is therefore the complete return
                        % operation; do not replay nm2_state through importUpdated/toNM here.
                    case {'dataio','dataio_overview'}
                        app.NM = NMDataIOUI.importUpdated(app.NM, struct('tmpDir', tmpDir), childCtx);
                        NMDataIOUI.saveSessionNM(app.NM, tmpDir);
                    case {'synth_coordinator'}
                        % SYNTH run services already saved their resulting NM in the shared session.
                    case {'analysis_manager'}
                        % Analysis-manager operations have already saved the
                        % authoritative session NM. The load at function entry
                        % rehydrates app.NM; do not immediately save the same
                        % large object again.
                    case {'preprocess_runner','preprocess','preprocessing'}
                        app.NM = NMPreprocessRunnerUI.importUpdated(app.NM, struct('tmpDir', tmpDir), childCtx);
                        NMDataIOUI.saveSessionNM(app.NM, tmpDir);
                    case {'ml_train_runner','mltrain','ml_training','ml_optimizer'}
                        app.NM = NMMLOptimizerRunnerUI.importUpdated(app.NM, struct('tmpDir', tmpDir), childCtx);
                        NMDataIOUI.saveSessionNM(app.NM, tmpDir);
                    case {'vis_runner','visualization','vis','model_visualization'}
                        app.NM = NMVisRunnerUI.importUpdated(app.NM, struct('tmpDir', tmpDir), childCtx);
                        NMDataIOUI.saveSessionNM(app.NM, tmpDir);
                    case {'mli_runner','mli','ml_interpretation','ml_interpreter'}
                        app.NM = NMMLIRunnerUI.importUpdated(app.NM, struct('tmpDir', tmpDir), childCtx);
                        NMDataIOUI.saveSessionNM(app.NM, tmpDir);
                    case {'model_export_runner','model_export','export','export_models'}
                        app.NM = NMModelExportRunnerUI.importUpdated(app.NM, struct('tmpDir', tmpDir), childCtx);
                        NMDataIOUI.saveSessionNM(app.NM, tmpDir);
                    case {'oocv_runner','oocv','oocv_application'}
                        app.NM = NMOOCVRunnerUI.importUpdated(app.NM, struct('tmpDir', tmpDir), childCtx);
                        NMDataIOUI.saveSessionNM(app.NM, tmpDir);
                    otherwise
                        if ok, NMDataIOUI.saveSessionNM(app.NM, tmpDir); end
                end
                NMAppUI.profileLog(doProfile, '[nm-prof rid=%s]   app return import/save source=%s: %.3fs\n', profileId, source, toc(tImport));
                % Child controllers navigate immediately and none consume a returned workbench STATE;
                % the workbench rebuilds its state after navigation.
                out = struct('ok', true, 'message', 'Returned to the NeuroMiner workbench.');
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'app_child_return', 'Returning to the NeuroMiner workbench failed.', 2);
            end
            NMAppUI.profileLog(doProfile, '[nm-prof rid=%s] app returnFromChildPage TOTAL source=%s: %.3fs\n', profileId, source, toc(tTotal));
        end

        function v = requestChar(req, field, default)
            % requestChar  Read a character field from a browser request with fallback.
            %
            % Normalizes string-like request fields for app routing and child-page selection. It is a
            % small request-parsing helper and does not inspect NM.

            v = default;
            if isstruct(req) && isfield(req, field) && ~isempty(req.(field))
                try
                    v = char(string(req.(field)));
                catch
                    v = default;
                end
            end
        end

        function state = projectDataIOState(state, scope)
            % projectDataIOState  Project an explicit Workbench DataIO view without mutating NM state.
            %
            % Training-data inspection remains the finalized/locked training manager even when the
            % global workbench is in Application/OOCV mode. The OOCV DataIO card continues to select
            % the OOCV manager. Only serialized UI mode/permissions/messages are projected here.

            scope = lower(strtrim(char(string(scope))));
            if isempty(scope), return; end
            if ~isstruct(state) || ~isfield(state,'defs') || ~isstruct(state.defs)
                error('NMAppUI:invalidDataIOState', ...
                    'Explicit DataIO routing requires a state payload with defs.');
            end
            oldMode = '';
            if isfield(state,'dataIOMode') && ~isempty(state.dataIOMode)
                oldMode = char(string(state.dataIOMode));
            end
            switch scope
                case 'training'
                    if isfield(state.defs,'import_finished') && logical(state.defs.import_finished)
                        mode = 'training_data_manager';
                    else
                        mode = 'training_import';
                    end
                case 'oocv'
                    if ~isfield(state.defs,'analyses_locked') || ~logical(state.defs.analyses_locked)
                        error('NMAppUI:oocvDataIOBeforeApplicationMode', ...
                            'OOCV DataIO is not available before Application/OOCV mode is activated.');
                    end
                    mode = 'oocv_data_manager';
                otherwise
                    error('NMAppUI:invalidDataIOScope', 'Unsupported DataIO scope: %s', scope);
            end
            state.dataIOMode = mode;
            state.permissions = NMDataIOBrowserModeTools.permissionsFromMode(mode, state.defs);
            if ~isempty(oldMode) && ~strcmp(oldMode, mode) && ...
                    isfield(state,'messages') && iscell(state.messages) && ~isempty(state.messages) && ...
                    (ischar(state.messages{1}) || (isstring(state.messages{1}) && isscalar(state.messages{1})))
                oldMsg = NMDataIOBrowserModeTools.modeMessage(oldMode);
                if strcmp(char(string(state.messages{1})), oldMsg)
                    state.messages{1} = NMDataIOBrowserModeTools.modeMessage(mode);
                end
            end
        end

        function tf = profileEnabled()
            % profileEnabled  Report whether UI profiling logs are enabled.
            %
            % Reads the environment/profile flag used by app routing diagnostics. It is intentionally
            % side-effect free so callers can guard profileLog cheaply.

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
            % profileLog  Emit a timestamped app-routing profiling message when enabled.
            %
            % Writes lightweight timing/debug output for workbench-to-runner navigation and service
            % dispatch. It does not affect browser responses or NM state.

            if ~enabled, return; end
            try
                fprintf(varargin{:});
            catch
            end
        end
    end
end

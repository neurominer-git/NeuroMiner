classdef NMWorkbenchUI
% NMWorkbenchUI
% -------------------------------------------------------------------------
% Browser landing page / workbench shell for NeuroMiner.
%
% The workbench is the default app-level UI.  It exposes the currently
% validated browser modules as child pages of one shared bridge session and
% keeps downstream modules visible but disabled until their browser/API path
% is implemented and validated.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(NM, outDir, ctx)
            % export  Export the NM 2.0 workbench landing page.
            %
            % Writes the workbench HTML, initial state JSON, shared assets and session NM used by
            % app-level navigation. It prepares the landing page but does not run DataIO or modelling
            % operations.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_app_ui'); end
            if nargin < 3, ctx = struct(); end

            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_app_ui');
            NMDataIOUI.saveSessionNM(NM, dirs.tmpDir);

            state = NMWorkbenchUI.stateFromNM(NM, ctx);
            htmlPath = NMWorkbenchUI.writeShell(state, dirs.webDir, dirs.tmpDir);
            NMWorkbenchUI.copyAssets(dirs.webDir);
            NMPreprocUI.writeBridge(fullfile(dirs.pyDir,'nm_bridge_server.py'));

            paths = struct('root', dirs.root, 'webRoot', dirs.webRoot, 'webDir', dirs.webDir, ...
                'tmpDir', dirs.tmpDir, 'html', htmlPath, 'workbenchHtml', htmlPath, ...
                'entryHtml', 'nm_workbench.html', 'entryHtmlPath', htmlPath, ...
                'state', fullfile(dirs.tmpDir,'workbench_state.json'));
        end

        function htmlPath = writeShell(state, webDir, tmpDir)
            % Workbench HTML and its JSON aliases have one session-local writer.
            stateJson = NMConfigTools.writeJsonAliases({ ...
                fullfile(tmpDir,'workbench_state.json'), ...
                fullfile(tmpDir,'workbench_current_config.json')}, state, 'NM workbench state');
            htmlPath = fullfile(webDir, 'nm_workbench.html');
            NMWorkbenchUI.writeTextFile(htmlPath, NMWorkbenchUI.htmlTextFromJson(stateJson));
        end

        function completeInitialPresentation(webDir, tmpDir)
            % The initial page has loaded; later entries into this shell do not replay its splash.
            state = NMConfigTools.readJson(fullfile(tmpDir,'workbench_state.json'));
            if ~state.showStartupSplash, return; end
            state.showStartupSplash = false;
            NMWorkbenchUI.writeShell(state, webDir, tmpDir);
        end

        function NM = importUpdated(NM, pathsOrWebDir, ctx)
            % importUpdated  Return session NM after leaving the workbench.
            %
            % Loads the session NM persisted by workbench/app services and clears the temporary store
            % when appropriate. It is the lifecycle counterpart to export.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(pathsOrWebDir), return; end
            tmpDir = NMDataIOUI.pathsTmpDir(pathsOrWebDir);
            if isempty(tmpDir), return; end
            [NM2, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
            if ok, NM = NM2; end
            NMDataIOUI.clearSessionNM(tmpDir);
        end

        function state = stateFromNM(NM, ctx)
            % stateFromNM  Build the workbench landing-page state from NM.
            %
            % Summarizes import-finalization, analysis-lock and completed-analysis status so the browser
            % can enable or disable workflow entry points. The method is read-only.

            if nargin < 2, ctx = struct(); end
            if nargin < 1 || isempty(NM), NM = struct(); end

            workflow = NMStatusGuardTools.workflowStatus(NM);
            defs = struct('import_finished',logical(workflow.import_finished), ...
                'analyses_locked',logical(workflow.analyses_locked), ...
                'data_scrambled',logical(NMWorkbenchUI.dataScrambledFlag(NM, workflow)));
            state = struct();
            state.page = 'workbench';
            state.title = 'NM2 workbench';
            state.showStartupSplash = true;
            if isstruct(ctx)
                if isfield(ctx,'showStartupSplash') && ~isempty(ctx.showStartupSplash)
                    state.showStartupSplash = logical(ctx.showStartupSplash);
                end
            end
            state.defs = defs;
            state.workflowStatus = workflow;
            state.mode = NMWorkbenchUI.modeKey(NM, workflow);
            state.modeLabel = NMWorkbenchUI.modeLabel(state.mode);
            state.modeflag = NMWorkbenchUI.safeModeFlag(NM);
            state.exportState = NMWorkbenchUI.exportState(NM);
            state.cwd = pwd;
            state.committedModalityCount = NMDataIOBrowserModeTools.committedModalityCount(NM);
            state.analysisCount = NMWorkbenchUI.analysisCount(NM);
            state.completedAnalysisCount = NMWorkbenchUI.completedAnalysisCount(NM, workflow);
            state.hasCompletedAnalysis = state.completedAnalysisCount > 0;
            state.modules = NMWorkbenchUI.modulesState(NM, state, workflow);
            state.summary = NMWorkbenchUI.summaryState(state);
            state.message = NMWorkbenchUI.statusMessage(state);
            state.appContext = struct('caller','standalone','returnToWorkbench',false,'returnPage','');
        end

        function txt = htmlTextFromJson(stateJson)
            % htmlTextFromJson  Build the workbench HTML shell from state JSON.
            %
            % Creates the landing-page document, embeds the initial state reference and loads shared
            % navigation/message/icon assets. Workflow buttons call app services rather than executing
            % MATLAB code in the browser.

            jsState = NMPreprocUI.jsonTextForScript(stateJson);
            nl = newline;
            L = { ...
'<!doctype html>'
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
'<title>NM2 workbench</title>'
['<script>window.NM_WORKBENCH_STATE = ' jsState ';</script>']
'<script>(function(){const root=document.documentElement;if(window.NM_WORKBENCH_STATE.showStartupSplash){root.classList.add("nmSplashPending");}else{root.classList.add("nmSplashResolved");}})();</script>'
'<link rel="stylesheet" href="NMTrainTemplateUI.css">'
'<link rel="stylesheet" href="NMModuleNavigationRail.css">'
'<link rel="stylesheet" href="NMWorkbenchUI.css">'
'<link rel="stylesheet" href="NMModal.css">'
['<style>' NMUIMessageTools.css() '</style>']
'</head><body class="nmHasNavRail">'
'<header class="wbHeader"><div><div class="title">Main interface</div></div><div class="headerActions"><button id="wbContributors" type="button">Contributors</button><button id="loadNM" type="button">Load NM</button><button id="saveNM" type="button">Save NM</button><button id="finish" class="primary" type="button">Quit NM</button></div></header>'
'<main class="wbShell">'
'  <div class="wbStartupWordmark" aria-hidden="true"><span class="wbBrandNM">NM</span><span class="wbBrandTwo">2</span></div>'
'  <section class="wbHero panel">'
'    <div class="wbHeroText"><h1><span class="wbBrandNM">NM</span><span class="wbBrandTwo">2</span><span class="wbBrandWork"> workbench</span></h1><p class="wbHeroLead">Build, train, inspect and apply NeuroMiner workflows from one workbench.</p><p id="workbenchMessage" class="muted">Loading workbench state...</p></div>'
'    <div class="wbStatusGrid" id="statusGrid"></div>'
'  </section>'
'  <section class="wbSection wbWorkflowSection">'
'    <div class="wbSectionHead"><h2>Stage 1 — Training data setup</h2><span class="wbStageStateIcon" aria-hidden="true"></span></div>'
'    <div class="wbModuleGrid wbStageGrid" id="trainingDataModules"></div>'
'  </section>'
'  <section class="wbSection wbWorkflowSection wbGateSection wbTrainingGateSection" id="trainingLockSection"><div class="wbSectionHead"><h2>Training data gate</h2><span class="wbGateStateIcon" aria-hidden="true"></span></div><div class="wbModuleGrid wbStageGrid gate" id="trainingLockModules"></div></section>'
'  <div class="wbWorkflowDivider wbImportDivider" id="importFinalizedDivider" hidden><span>Training data finalized</span></div>'
'  <section class="wbSection wbWorkflowSection">'
'    <div class="wbSectionHead"><h2>Stage 2 — Training and model analysis</h2><span class="wbStageStateIcon" aria-hidden="true"></span></div>'
'    <div class="wbModuleGrid wbStageGrid" id="trainingAnalysisModules"></div>'
'    <div class="wbModuleGrid wbStageGrid compact" id="modelExportModules"></div>'
'  </section>'
'  <section class="wbSection wbWorkflowSection wbGateSection">'
'    <div class="wbSectionHead"><h2>Model Application Gate — Lock models / activate OOCV mode</h2><span class="wbGateStateIcon" aria-hidden="true"></span></div>'
'    <div class="wbModuleGrid wbStageGrid gate" id="modelLockModules"></div>'
'  </section>'
'  <div class="wbWorkflowDivider wbApplicationDivider" id="applicationStageDivider" hidden><span>OOCV Mode Activated</span></div>'
'  <section class="wbSection wbWorkflowSection">'
'    <div class="wbSectionHead"><h2>Stage 3 — External validation and application</h2><span class="wbStageStateIcon" aria-hidden="true"></span></div>'
'    <div class="wbModuleGrid wbStageGrid" id="applicationModules"></div>'
'  </section>'
'  <div class="wbBottomToolbar" id="workbenchBottomToolbar">'
'  <section class="wbSection wbWorkflowSection">'
'    <div class="wbSectionHead"><h2>Results and inspection</h2></div>'
'    <div class="wbModuleGrid wbStageGrid compact" id="resultsModules"></div>'
'  </section>'
'  <section class="wbSection wbWorkflowSection">'
'    <div class="wbSectionHead"><h2>Utilities</h2></div>'
'    <div class="wbModuleGrid wbStageGrid compact" id="utilityModules"></div>'
'  </section>'
'  </div>'
'</main>'
'<script>window.NM_MODULE_NAV_CONTEXT = {currentModule:"workbench"};</script>'
['<script>' NMUIMessageTools.script() '</script>']
'<script src="NMModuleIconSet.js"></script>'
'<script src="NMModuleNavigationRail.js"></script>'
'<script src="NMModal.js"></script>'
'<script src="NMWorkbenchUI_main.js"></script>'
'<script>(function(){const root=document.documentElement;const initialPixelScale=(window.devicePixelRatio||1)*((window.visualViewport&&window.visualViewport.scale)||1);let baseScale=3.45;function syncWatermarkZoom(){const cs=getComputedStyle(root);if(!root.dataset.nmWatermarkSized){const w=(cs.getPropertyValue("--nm-brand-final-width")||"250px").trim();baseScale=parseFloat(cs.getPropertyValue("--nm-brand-final-scale"))||3.45;root.style.setProperty("--nm-brand-final-width",w);root.dataset.nmWatermarkSized="1";}const currentPixelScale=(window.devicePixelRatio||1)*((window.visualViewport&&window.visualViewport.scale)||1);const compensation=currentPixelScale>0?initialPixelScale/currentPixelScale:1;root.style.setProperty("--nm-brand-final-scale-live",String(baseScale*compensation));}syncWatermarkZoom();window.addEventListener("resize",syncWatermarkZoom,{passive:true});if(window.visualViewport)window.visualViewport.addEventListener("resize",syncWatermarkZoom,{passive:true});if(!root.classList.contains("nmSplashPending"))return;const finish=function(){root.classList.remove("nmSplashPending","nmStartupSplash");root.classList.add("nmSplashResolved");};if(window.matchMedia&&window.matchMedia("(prefers-reduced-motion: reduce)").matches){finish();return;}const start=function(){root.classList.remove("nmSplashPending");root.classList.add("nmStartupSplash");const shell=document.querySelector(".wbShell");if(shell)shell.addEventListener("animationend",function(ev){if(ev.animationName==="nm2BrainStartup")finish();});window.setTimeout(finish,5600);};if(window.NM_HTML_RELAY_CHANNEL){window.NM_HTML_RELAY_CHANNEL.layoutReady.then(start);}else{window.requestAnimationFrame(function(){window.requestAnimationFrame(start);});}})();</script>'
'</body></html>'};
            txt = strjoin(L, nl);
        end

        function copyAssets(webDir)
            % copyAssets  Copy static assets used by the workbench page.
            %
            % Copies workbench CSS/JavaScript plus shared navigation, icon and message assets into the
            % exported web directory. It keeps the landing-page export self-contained.

            src = fileparts(which('NMWorkbenchUI.m'));
            files = {'NMWorkbenchUI.css','NMWorkbenchUI_main.js','NMTrainTemplateUI.css', ...
                'NMModuleIconSet.js','NMModuleNavigationRail.js','NMModuleNavigationRail.css','NMModal.js','NMModal.css','NMRuntimeProgressViewer.js','NMRuntimeProgressViewer.css'};
            for i = 1:numel(files)
                s = fullfile(src, files{i});
                if exist(s,'file'), copyfile(s, fullfile(webDir, files{i}), 'f'); end
            end
            copyfile(fullfile(fileparts(which('nm.m')),'LICENCE.txt'),fullfile(webDir,'LICENCE.txt'),'f');
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the workbench UI text-writer entry point.
            %
            %   NMWorkbenchUI.writeTextFile(path,txt) delegates generated workbench browser files to
            %   NMSerializationTools while retaining the workbench-specific diagnostic identifier.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMWorkbenchUI:writeFailed', 'Could not write %s', 'fwrite-input-char');
        end
    end

    methods (Static, Access = private)
        function E = exportState(NM)
            E = struct('models_exported',false, 'preproc_exported',false, ...
                'export_finished',false, 'timestamp','', 'analyses',[]);
            if isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs) && ...
                    isfield(NM.defs,'export_state') && isstruct(NM.defs.export_state)
                old = NM.defs.export_state;
                if isfield(old,'models_exported'), E.models_exported = logical(old.models_exported); end
                if isfield(old,'preproc_exported'), E.preproc_exported = logical(old.preproc_exported); end
                if isfield(old,'export_finished'), E.export_finished = logical(old.export_finished); end
                if isfield(old,'timestamp'), E.timestamp = char(string(old.timestamp)); end
                if isfield(old,'analyses') && ~isempty(old.analyses), E.analyses = double(old.analyses(:)'); end
            end
        end


        function tf = dataScrambledFlag(NM, workflow)
            tf = false;
            if isstruct(workflow) && isfield(workflow,'data_scrambled') && ~isempty(workflow.data_scrambled)
                tf = logical(workflow.data_scrambled);
                return;
            end
            if isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs) && ...
                    isfield(NM.defs,'data_scrambled') && ~isempty(NM.defs.data_scrambled)
                tf = logical(NM.defs.data_scrambled);
            end
        end

        function key = modeKey(NM, defs)
            if ~defs.import_finished
                key = 'data_input';
            elseif defs.analyses_locked
                if isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs) && ...
                        isfield(NM.defs,'data_scrambled') && logical(NM.defs.data_scrambled)
                    key = 'model_export';
                else
                    key = 'application';
                end
            else
                key = 'model_discovery';
            end
        end

        function txt = modeLabel(key)
            switch char(string(key))
                case 'data_input'
                    txt = 'Data input mode';
                case 'model_discovery'
                    txt = 'Model discovery mode';
                case 'application'
                    txt = 'Model application mode';
                case 'model_export'
                    txt = 'Model export mode';
                otherwise
                    txt = 'Unknown mode';
            end
        end

        function txt = safeModeFlag(NM)
            txt = '';
            if isstruct(NM) && isfield(NM,'modeflag') && ~isempty(NM.modeflag)
                txt = char(string(NM.modeflag));
            end
        end

        function txt = modelTypeText(NM)
            modeflag = NMWorkbenchUI.safeModeFlag(NM);
            switch lower(char(string(modeflag)))
                case 'regression'
                    txt = 'regressors';
                otherwise
                    txt = 'classifiers';
            end
        end

        function n = analysisCount(NM)
            n = 0;
            if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis)
                n = numel(NM.analysis);
            end
        end

        function n = completedAnalysisCount(NM, workflow)
            n = 0;
            if nargin >= 2 && isstruct(workflow) && isfield(workflow,'completed_analyses') && ~isempty(workflow.completed_analyses)
                n = sum(logical(workflow.completed_analyses(:)));
                return;
            end
            if exist('NMStatusGuardTools','class') == 8
                v = NMStatusGuardTools.analysisStatusVector(NM);
                n = sum(isfinite(v(:)) & v(:) >= 1);
                return;
            end
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis), return; end
            for i = 1:numel(NM.analysis)
                A = NM.analysis{i};
                if isstruct(A) && isfield(A,'status') && ~isempty(A.status) && any(double(A.status(:)) >= 1)
                    n = n + 1;
                end
            end
        end

        function modules = modulesState(NM, state, workflow) %#ok<INUSD>
            % modulesState mirrors the stage-wise NM workflow: training data
            % setup -> locked discovery/model-analysis runtime -> model lock
            % -> external validation/application -> utilities.  Cards may be
            % visible before their implementation is complete, but unavailable
            % cards must report a concrete blocker.
            modules = cell(1,16);
            defs = struct('import_finished',logical(workflow.import_finished), ...
                'analyses_locked',logical(workflow.analyses_locked), ...
                'data_scrambled',logical(NMWorkbenchUI.dataScrambledFlag(NM, workflow)));
            analysesExist = logical(workflow.analyses_exist) || NMWorkbenchUI.analysisCount(NM) > 0;
            trainedOK = logical(workflow.analyses_ready) || any(logical(workflow.completed_analyses));
            mdltypestr = NMWorkbenchUI.modelTypeText(NM);
            % nm2-allow: Only NMSimulationTools.createSyntheticTemplate creates this optional domain.
            placeholder=isfield(NM,'SYNTH') && isfield(NM.SYNTH,'fullySyntheticDefinition');

            dataTitle = 'Training data import';
            dataDesc = 'Import, inspect, QC, finalize, externalize and relink discovery/training data.';
            dataKind = 'module';
            if defs.import_finished
                dataTitle = 'Training data inspection';
                dataDesc = 'Inspect finalized training data, run diagnostics, relink files or maintain externalized data containers.';
                dataKind = 'module lockedAvailable';
            end
            modules{1} = NMWorkbenchUI.module('dataio', dataTitle, dataDesc, ...
                'training_data', ~placeholder, ...
                NMWorkbenchUI.reason(placeholder,'SYNTH input is locked.'), ...
                'Open Data Manager', 'dataio', ...
                'data_manager', dataKind, NMWorkbenchUI.statusLabel(defs.import_finished, 'finalized', 'active'), ...
                NMWorkbenchUI.statusTone(defs.import_finished, 'ok', 'active'));

            canLockTrainingData = ~defs.import_finished && NMDataIOBrowserModeTools.trainingImportReady(NM);
            lockTrainingDataReason = NMWorkbenchUI.reason( ...
                ~defs.import_finished && ~canLockTrainingData, ...
                'Complete and commit all training modalities before locking training data.');
            modules{2} = NMWorkbenchUI.module('lock_data', 'Lock training data', ...
                'Finalize the discovery dataset before analysis initialization. Structural training-data edits are locked after this gate.', ...
                'training_data', canLockTrainingData, lockTrainingDataReason, 'Lock training data', 'lock_data', ...
                'lock', 'gate', '', 'neutral', defs.import_finished);

            discoveryKind = 'module';
            if defs.analyses_locked
                discoveryKind = 'module locked';
            end

            templateOK = defs.import_finished && ~defs.analyses_locked;
            templateReason = NMWorkbenchUI.reason(~defs.import_finished, ...
                'Finalize training data import before configuring the training template.', ...
                defs.analyses_locked, 'Training-template editing is locked in application/OOCV mode.');
            modules{3} = NMWorkbenchUI.module('template', 'Configuration', ...
                'Define cross-validation, preprocessing, learner, ensemble, visualization and MLI template settings.', ...
                'training_analysis', templateOK, templateReason, 'Open template configurator', 'template', ...
                'template', discoveryKind, '', 'neutral');

            managerOK = defs.import_finished && ~defs.analyses_locked && logical(workflow.setup_ok) && ~placeholder;
            setupReason = 'Complete the NM parameter workspace before initializing or running analyses.';
            if ~logical(workflow.setup_ok) && ~isempty(workflow.paramstr)
                setupReason = sprintf('Configuration incomplete: %s. Return to Configuration to resolve these settings.', ...
                    workflow.paramstr);
            end
            managerReason = NMWorkbenchUI.reason(~defs.import_finished, ...
                'Finalize training data import before creating or managing analyses.', ...
                defs.analyses_locked, 'Analysis initialization and analysis-snapshot maintenance are locked in application/OOCV mode.', ...
                ~logical(workflow.setup_ok), setupReason);
            modules{4} = NMWorkbenchUI.module('analysis_manager', 'Analysis initialization', ...
                'Create, inspect, reset, restore, relink or delete analysis snapshots.', ...
                'training_analysis', managerOK, managerReason, 'Open analysis manager', 'analysis_manager', ...
                'analysis_manager', discoveryKind, '', 'neutral');

            runtimeBaseReason = NMWorkbenchUI.reason(placeholder, ...
                'SYNTH placeholders cannot be trained directly.', ~defs.import_finished, ...
                'Finalize training data import before running discovery-stage runtime modules.', ...
                defs.analyses_locked, 'Discovery-stage runtime modules are locked in application/OOCV mode.', ...
                ~logical(workflow.setup_ok), setupReason, ...
                ~analysesExist, 'Initialize at least one analysis before running this module.');
            preprocessBackendOK = exist('NMPreprocessRunnerUI','class') == 8 && exist('NMRunTools','class') == 8 && ...
                any(strcmp(NMRunTools.availableRunners(), 'preprocessAnalysis'));
            preprocessOK = isempty(runtimeBaseReason) && preprocessBackendOK;
            preprocessReason = NMWorkbenchUI.reason(~isempty(runtimeBaseReason), runtimeBaseReason, ...
                ~preprocessBackendOK, 'Dedicated preprocessing browser page is not yet implemented and validated.');
            modules{5} = NMWorkbenchUI.module('preprocess', 'Preprocessing', ...
                'Run or script preprocessing-stage artifacts for selected analyses and CV2 partitions.', ...
                'training_analysis', preprocessOK, preprocessReason, 'Open preprocessing', 'preprocess', ...
                'preprocessing', discoveryKind, '', 'neutral');

            mlTrainBackendOK = exist('NMMLOptimizerRunnerUI','class') == 8 && exist('NMRunTools','class') == 8 && ...
                any(strcmp(NMRunTools.availableRunners(), 'trainAnalysis'));
            mlTrainOK = isempty(runtimeBaseReason) && mlTrainBackendOK;
            mlTrainReason = NMWorkbenchUI.reason(~isempty(runtimeBaseReason), runtimeBaseReason, ...
                ~mlTrainBackendOK, 'Dedicated ML-training browser page is not yet implemented and validated.');
            modules{6} = NMWorkbenchUI.module('mltrain', ['ML training (' mdltypestr ')'], ...
                'Train supervised models from scratch, PreprocData, CVdatamat or CVresults.', ...
                'training_analysis', mlTrainOK, mlTrainReason, 'Open ML training', 'mltrain', ...
                'ml_training', discoveryKind, '', 'neutral');

            visBackendOK = exist('NMVisRunnerUI','class') == 8;
            visOK = trainedOK && ~defs.analyses_locked && visBackendOK;
            visReason = NMWorkbenchUI.reason(~trainedOK, ...
                'Train at least one CV2 partition successfully before opening model visualization.', ...
                defs.analyses_locked, 'Model visualization is a discovery-stage module and is disabled in application/OOCV mode.', ...
                ~visBackendOK, 'Visualization runner workbench has not yet been implemented.');
            modules{7} = NMWorkbenchUI.module('visualization', 'Visualization', ...
                'Configure and compute discovery-stage model-visualization outputs.', ...
                'training_analysis', visOK, visReason, 'Open visualization', 'visualization', ...
                'visualization', discoveryKind, '', 'neutral');

            mliBackendOK = exist('NMMLIRunnerUI','class') == 8 && exist('NMRunTools','class') == 8 && ...
                any(strcmp(NMRunTools.availableRunners(), 'interpretModels'));
            mliOK = trainedOK && ~defs.analyses_locked && mliBackendOK;
            mliReason = NMWorkbenchUI.reason(~trainedOK, ...
                'Train at least one CV2 partition successfully before opening ML interpretation.', ...
                defs.analyses_locked, 'ML interpretation is a discovery-stage module and is disabled in application/OOCV mode.', ...
                ~mliBackendOK, 'MLI runner/workbench API has not yet been implemented and validated.');
            modules{8} = NMWorkbenchUI.module('mli', 'ML interpretation', ...
                'Interpret discovery/training-set predictions and model behavior.', ...
                'training_analysis', mliOK, mliReason, 'Open ML interpretation', 'mli', ...
                'mli', discoveryKind, '', 'neutral');

            exportBackendOK = exist('NMModelExportRunnerUI','class') == 8 && exist('NMRunTools','class') == 8 && ...
                any(strcmp(NMRunTools.availableRunners(), 'exportModels'));
            exportFinished = isstruct(state) && isfield(state,'exportState') && isstruct(state.exportState) && ...
                isfield(state.exportState,'export_finished') && logical(state.exportState.export_finished);
            exportOK = trainedOK && exportBackendOK && ~defs.data_scrambled;
            exportReason = NMWorkbenchUI.reason(~trainedOK, 'Train at least one CV2 partition successfully before exporting model parameters.', ...
                defs.data_scrambled, 'Training data have been scrambled for sharing. Model export is disabled in this workspace.', ...
                ~exportBackendOK, 'Model-export browser runner is not yet implemented and validated.');
            exportKind = 'module';
            if defs.data_scrambled
                exportKind = 'module locked';
            end
            modules{9} = NMWorkbenchUI.module('model_export', 'Model export', ...
                'Save optimized ML model containers and optimized preprocessing parameters before application-mode transition or model sharing.', ...
                'model_export', exportOK, exportReason, 'Open model export', 'model_export', ...
                'model_export', exportKind, NMWorkbenchUI.statusLabel(exportFinished, 'exported', 'optional'), ...
                NMWorkbenchUI.statusTone(exportFinished, 'ok', 'neutral'));

            resultsAlphaBackendOK = exist('NMResultsViewerUI','class') == 8 && exist('NMResultsViewerTools','class') == 8;
            resultsAlphaOK = trainedOK && resultsAlphaBackendOK;
            resultsAlphaReason = NMWorkbenchUI.reason(~trainedOK, ...
                'Train at least one CV2 partition successfully before opening the alpha browser Results Viewer.', ...
                ~resultsAlphaBackendOK, 'Alpha browser Results Viewer is not available on the MATLAB path.');
            modules{10} = NMWorkbenchUI.module('results_alpha', 'NM2 Results Viewer', ...
                'Explore analysis results, performance, feature patterns, model interpretation and external-validation outputs in an interactive workspace.', ...
                'results', resultsAlphaOK, resultsAlphaReason, 'Open NM2 Results Viewer', 'results_alpha', ...
                'results', 'inspection alpha', 'alpha', 'warn');

            modelLockOK = defs.import_finished && trainedOK && ~defs.analyses_locked;
            modelLockReason = NMWorkbenchUI.reason(~defs.import_finished, 'Finalize training data before model locking is possible.', ...
                ~trainedOK, 'Complete at least one analysis before activating application/OOCV mode.', ...
                defs.analyses_locked, 'Application/OOCV mode is already active.');
            modules{11} = NMWorkbenchUI.module('lock_models', 'Lock trained models / activate Application-OOCV mode', ...
                'Locks discovery-model editing and enables external validation/application workflows. This is the normal application-mode transition and does not scramble training data.', ...
                'model_lock', modelLockOK, modelLockReason, 'Lock trained models', 'lock_models', ...
                'lock', 'gate', '', 'neutral', defs.analyses_locked);

            scrambleLockOK = exportFinished && ~defs.data_scrambled && (modelLockOK || defs.analyses_locked);
            scrambleLockReason = NMWorkbenchUI.reason(~defs.import_finished, 'Finalize training data before creating a shareable scrambled workspace.', ...
                ~trainedOK, 'Complete at least one analysis before creating a shareable scrambled workspace.', ...
                ~exportFinished, 'Export optimized ML models and preprocessing parameters before creating a shareable scrambled workspace.');
            if defs.analyses_locked
                scrambleTitle = 'Scramble training data for sharing';
                scrambleDesc = 'Replace training features by same-dimensional random double matrices. Use this only for sharing trained model workspaces without original data.';
                scrambleButton = 'Scramble training data';
            else
                scrambleTitle = 'Scramble training data for sharing & lock';
                scrambleDesc = 'Replace training features by same-dimensional random double matrices, then activate Application/OOCV mode. Use this only for sharing trained model workspaces without original data.';
                scrambleButton = 'Scramble training data & lock';
            end
            modules{16} = NMWorkbenchUI.module('scramble_lock_models', scrambleTitle, ...
                scrambleDesc, ...
                'model_lock', scrambleLockOK, scrambleLockReason, scrambleButton, 'scramble_lock_models', ...
                'scramble', 'gate danger', 'destructive', 'danger', defs.data_scrambled);

            oocvDataOK = defs.analyses_locked;
            oocvDataReason = NMWorkbenchUI.reason(~defs.analyses_locked, 'Activate application/OOCV mode before importing independent application data.');
            modules{12} = NMWorkbenchUI.module('oocv_dataio', 'OOCV data import', ...
                'Import and manage independent external-validation/application data.', ...
                'application', oocvDataOK, oocvDataReason, 'Open OOCV Data Manager', 'dataio', ...
                'oocv_dataio', 'module', '', 'neutral');

            hasReadyOOCVData = NMDataIOOOCVReadinessTools.anyReadyContainer(NM);
            oocvRunnerBackendOK = exist('NMOOCVRunnerUI','class') == 8 && exist('NMRunTools','class') == 8 && ...
                exist('NMDataIOBrowserModeTools','class') == 8 && exist('nk_OOCVPrep','file') == 2 && exist('nk_OOCV','file') == 2;
            oocvRunnerOK = defs.analyses_locked && trainedOK && hasReadyOOCVData && oocvRunnerBackendOK;
            oocvRunnerReason = NMWorkbenchUI.reason(~defs.analyses_locked, 'Activate application/OOCV mode before applying models to independent data.', ...
                ~trainedOK, 'Complete at least one analysis before applying models to OOCV data.', ...
                ~hasReadyOOCVData, 'Complete at least one OOCV/application dataset in DataIO before applying trained models.', ...
                ~oocvRunnerBackendOK, 'The browser OOCV runner, DataIO readiness authority or legacy OOCV backend is not available on the MATLAB path.');
            modules{13} = NMWorkbenchUI.module('oocv', 'Model application to OOCV data', ...
                'Apply trained and locked models to one selected independent OOCV/application dataset.', ...
                'application', oocvRunnerOK, oocvRunnerReason, 'Open OOCV application', 'oocv_runner', ...
                'oocv_model_application', 'module', '', 'neutral');

            oocvMliOK = defs.analyses_locked && trainedOK && hasReadyOOCVData && mliBackendOK;
            modules{14} = NMWorkbenchUI.module('oocv_mli', 'OOCV ML interpretation', ...
                'Interpret model predictions and explanation outputs in independent application data.', ...
                'application', oocvMliOK, ...
                NMWorkbenchUI.reason(~defs.analyses_locked, 'Activate application/OOCV mode before running OOCV ML interpretation.', ...
                ~trainedOK, 'Complete at least one trained analysis before interpreting external data.', ...
                ~hasReadyOOCVData, 'Import a ready OOCV dataset in DataIO first.', ...
                ~mliBackendOK, 'MLI runner or legacy interpretation backend is unavailable.'), 'Open OOCV MLI', 'mli', ...
                'mli', 'module', '', 'neutral');

            synthOK = ~defs.analyses_locked && ...
                (defs.import_finished || state.committedModalityCount==0);
            synthReason = NMWorkbenchUI.reason(defs.analyses_locked, ...
                'SYNTH is unavailable in OOCV/application mode.', ...
                ~defs.import_finished && state.committedModalityCount>0, ...
                'Finalize the pending training import before opening SYNTH.');
            modules{15} = NMWorkbenchUI.module('synth_coordinator', 'SYNTH coordinator', ...
                'Simulate predictive performance across sample sizes for cohort-size planning, using existing or fully synthetic data with the current NM parameter template.', ...
                'utilities', synthOK, synthReason, 'Open SYNTH coordinator', 'synth_coordinator', ...
                'synth_coordinator', 'utility', '', 'neutral');
        end

        function m = module(key, title, description, group, enabled, disabledReason, buttonLabel, page, icon, kind, statusLabel, statusTone, hidden)
            if nargin < 9, icon = ''; end
            if nargin < 10 || isempty(kind), kind = 'module'; end
            if nargin < 11, statusLabel = ''; end
            if nargin < 12 || isempty(statusTone), statusTone = 'neutral'; end
            if nargin < 13 || isempty(hidden), hidden = false; end
            m = struct('key', key, 'title', title, 'description', description, ...
                'group', group, 'enabled', logical(enabled), 'hidden', logical(hidden), ...
                'disabledReason', disabledReason, 'buttonLabel', buttonLabel, 'page', page, ...
                'icon', icon, 'kind', kind, 'statusLabel', statusLabel, 'statusTone', statusTone);
        end

        function txt = statusLabel(condition, trueText, falseText)
            if logical(condition)
                txt = trueText;
            else
                txt = falseText;
            end
        end

        function txt = statusTone(condition, trueText, falseText)
            if logical(condition)
                txt = trueText;
            else
                txt = falseText;
            end
        end


        function v = fieldOr(s, field, default)
            v = default;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                v = s.(field);
            end
        end

        function txt = reason(varargin)
            txt = '';
            for i = 1:2:numel(varargin)
                if logical(varargin{i})
                    txt = varargin{i+1};
                    return;
                end
            end
        end

        function s = summaryState(state)
            s = cell(1,5);
            s{1} = struct('label','Mode', 'value', state.modeLabel);
            s{2} = struct('label','Modalities', 'value', sprintf('%d committed', double(state.committedModalityCount)));
            s{3} = struct('label','Analyses', 'value', sprintf('%d configured', double(state.analysisCount)));
            s{4} = struct('label','Completed', 'value', sprintf('%d finished', double(state.completedAnalysisCount)));
            if isfield(state,'exportState') && isstruct(state.exportState) && isfield(state.exportState,'export_finished') && logical(state.exportState.export_finished)
                exportValue = 'complete';
            else
                exportValue = 'pending';
            end
            s{5} = struct('label','Export', 'value', exportValue);
        end

        function msg = statusMessage(state)
            if isfield(state,'workflowStatus') && isstruct(state.workflowStatus) && ...
                    isfield(state.workflowStatus,'ok') && ~logical(state.workflowStatus.ok)
                msg = char(string(state.workflowStatus.message));
                return;
            end
            switch state.mode
                case 'data_input'
                    msg = 'Import and finalize the training dataset before model discovery starts.';
                case 'model_discovery'
                    if isfield(state,'workflowStatus') && isstruct(state.workflowStatus) && ~logical(state.workflowStatus.setup_ok)
                        msg = 'Training data are locked. Complete the model configuration before initializing analyses.';
                    elseif state.hasCompletedAnalysis
                        msg = 'Completed analyses are available for inspection and post-training processing.';
                    else
                        msg = 'Configure the template, initialize analyses, then run preprocessing and ML training.';
                    end
                case 'application'
                    msg = 'Application mode is active. Import independent data and apply locked trained models.';
                otherwise
                    msg = 'Model export mode is active.';
            end
        end
    end
end

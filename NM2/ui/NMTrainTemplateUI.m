classdef NMTrainTemplateUI
% NMTrainTemplateUI
% -------------------------------------------------------------------------
% Minimal persistent browser shell for the main NeuroMiner training-parameter
% template menu. The shell hosts one modal configurator at a time and reuses
% the existing preprocessing and ML browser pages with module-scoped JSON
% state files served by the common bridge.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(orch, outDir, ctx)
            % export  Export the full NM training-template configurator.
            %
            % Serializes the orchestrator menu state, module specs, workspace catalog and NM-derived
            % dashboard data, then writes the browser page and assets. This is the main UI entry point
            % for power users configuring NeuroMiner analyses before training.

            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_train_template_ui'); end
            if nargin < 3, ctx = struct(); end
            if nargin < 1 || isempty(orch)
                orch = NMTrainTemplateOrchestrator.fromNM(struct(), 1, ctx);
            end
            if ~isa(orch, 'NMTrainTemplateOrchestrator')
                error('NMTrainTemplateUI:invalidInput', 'Expected an NMTrainTemplateOrchestrator object.');
            end
            doProfile = NMTrainTemplateUI.profileEnabled(ctx);
            profileId = '-';
            if isstruct(ctx) && isfield(ctx,'NMProfileId') && ~isempty(ctx.NMProfileId)
                profileId = char(string(ctx.NMProfileId));
            end
            fastChildOpen = NMUISessionTools.fastChildOpen(ctx);
            tExport = tic;
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] trainTemplate export ENTER (modalities=%d, fastChildOpen=%d)\n', profileId, double(orch.NumModalities), double(fastChildOpen));

            t = tic;
            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_train_template_ui');
            outDir = dirs.root;
            webRoot = dirs.webRoot;
            webDir = dirs.webDir;
            pyDir = dirs.pyDir;
            tmpDir = dirs.tmpDir;
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   export session dirs:       %.3fs\n', profileId, toc(t));

            % One session-wide nm2_state.json owns uncommitted configurator state.
            % On a cross-MATLAB recovery the existing configurator section is
            % preserved; ordinary entry refreshes it from the live orchestrator.
            t = tic;
            NMUIStateTools.initialize(tmpDir, orch.NM, 'template');
            globalRFEState = orch.RFE;
            if orch.FusionFlag == 3
                globalRFEState = NMRFETools.stateFromNM(orch.NM, orch.VarIndex, 0);
            end
            if ~globalRFEState.rfePresent
                orch.NM.TrainParam.RFE = NMRFETools.defaultSetting(orch.NM, orch.VarIndex, 0);
                if orch.FusionFlag ~= 3
                    orch.RFE = NMRFETools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                end
            end
            % Persist first-entry TrainParam initialization as well as missing
            % RFE defaults; the browser session must own the completed setup.
            NMDataIOUI.saveSessionNM(orch.NM, tmpDir);
            isRecovery = NMTrainTemplateUI.isConfiguratorRecovery(ctx, tmpDir);
            deferChildBootstrap = fastChildOpen || isRecovery;
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   export session state init/recovery: %.3fs (recovery=%d)\n', ...
                profileId, toc(t), double(isRecovery));

            t = tic;
            workspaceCtx = NMTrainTemplateUI.workspaceCatalogContext(orch, ctx);
            try
                workspace = NMWorkspaceTools.catalog('base', workspaceCtx);
            catch
                workspace = {};
            end
            workspaceJson = NMConfigTools.writeJson(fullfile(tmpDir,'workspace.json'), workspace);
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   export workspace catalog: %.3fs\n', profileId, toc(t));

            t = tic;
            menuState = struct();
            if isRecovery
                menuState = NMUIStateTools.readConfiguratorMenu(tmpDir);
            end
            hadSavedMenu = ~isempty(fieldnames(menuState));
            if ~hadSavedMenu
                menuState = orch.menuState(struct('includeCanvas', ~deferChildBootstrap, ...
                    'profile', doProfile, 'profileId', profileId));
                NMUIStateTools.clearConfiguratorChildren(tmpDir);
            end
            menuState = NMUISessionTools.attachAppContextToState(ctx, menuState, 'template');
            workflow = NMStatusGuardTools.workflowStatus(orch.NM);
            menuState.readinessDiagnostic = workflow.paramstr;
            menuState = NMTrainTemplateUI.enrichMenuStateForExport(menuState, tmpDir);
            if ~isRecovery || ~hadSavedMenu
                NMUIStateTools.writeConfiguratorMenu(tmpDir, menuState);
            end
            menuSpecJson = NMConfigTools.writeJson(fullfile(tmpDir,'menu_spec.json'), NMTrainTemplateUI.menuSpec(orch)); %#ok<NASGU>
            menuStateJson = NMConfigTools.writeJson(fullfile(tmpDir,'menu_param.json'), menuState);
            NMCVPartitionTools.writePlotContext(orch.NM, fullfile(tmpDir,'cv_plot_context.mat'));
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   export menu/json:        %.3fs\n', profileId, toc(t));

            tPreproc = tic;
            preprocHtml = fullfile(webDir,'nm_preproc_pipeline_ui.html');
            mlHtml = fullfile(webDir,'nm_train_ml_ui.html');
            if deferChildBootstrap
                % Fast workbench entry defers scientific child-state materialization,
                % but the renderer shells themselves must already exist before an
                % iframe can navigate to them. Their embedded payloads are unused
                % in this mode because module-scoped STATE/spec are read through
                % the authenticated bridge after the child page loads.
                NMPreprocUI.writeHtmlFromJson(preprocHtml, '{}', '{}', workspaceJson);
                NMPreprocUI.writeHtmlFromJson(mlHtml, '{}', '{}', workspaceJson);
                writtenPreproc = 0;
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   export preproc states:    %.3fs (written=0/%d, lazy=1, deferred=1)\n', profileId, toc(tPreproc), double(orch.NumModalities));
            else
                initialPreproc = NMTrainTemplateUI.initialPreprocExportIndices(orch);
                writtenPreproc = 0;
                for jj = 1:numel(initialPreproc)
                    i = initialPreproc(jj);
                    if i >= 1 && i <= orch.NumModalities && ~isempty(orch.Preproc{i})
                        NMTrainTemplateUI.writePreprocStateFiles(orch, i, tmpDir, preprocHtml, workspaceJson);
                        writtenPreproc = writtenPreproc + 1;
                    end
                end
                if writtenPreproc == 0 && orch.NumModalities >= 1 && ~isempty(orch.Preproc{1})
                    NMTrainTemplateUI.writePreprocStateFiles(orch, 1, tmpDir, preprocHtml, workspaceJson);
                    writtenPreproc = 1;
                end
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   export preproc states:    %.3fs (written=%d/%d, lazy=1)\n', profileId, toc(tPreproc), double(writtenPreproc), double(orch.NumModalities));
            end

            t = tic;
            % Dedicated stacker preprocessing is materialized only when stacking is the active analysis.
            % Other contexts prepare it on first explicit child open.
            if ~deferChildBootstrap && orch.isStackingEnabled()
                sspec = orch.StackingPreproc.toUISpec();
                sstate = NMUIStateTools.readConfiguratorChild(tmpDir,'preproc_stacking');
                if isempty(fieldnames(sstate))
                    sstate = orch.StackingPreproc.toUIState();
                    NMUIStateTools.writeConfiguratorChild(tmpDir,'preproc_stacking',sstate);
                end
                sspecJson = NMConfigTools.writeJson(fullfile(tmpDir,'preproc_stacking_spec.json'), sspec);
                sstateJson = NMConfigTools.writeJson(fullfile(tmpDir,'preproc_stacking_param.json'), sstate);
                if ~exist(preprocHtml,'file')
                    NMPreprocUI.writeHtmlFromJson(preprocHtml, sspecJson, sstateJson, workspaceJson);
                end
            end
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   export stacking state:    %.3fs%s\n', profileId, toc(t), NMTrainTemplateUI.deferredSuffix(fastChildOpen));

            t = tic;
            % Global ML belongs to stacking and no-/early-/intermediate-fusion analyses.
            % Late fusion prepares only its selected STRAT learner branches.
            if ~deferChildBootstrap && (orch.isStackingEnabled() || orch.FusionFlag ~= 3)
                NMTrainTemplateUI.writeMLStateFiles(orch, 'ml_global', tmpDir, mlHtml, workspaceJson, ctx);
            end
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   export global ML state:   %.3fs%s\n', profileId, toc(t), NMTrainTemplateUI.deferredSuffix(fastChildOpen));

            tLate = tic;
            % Late-fusion STRAT states are needed only for modalities selected by the active strategy.
            if orch.FusionFlag == 3 && ~deferChildBootstrap
                lateIdx = orch.FusionModalities;
                for i = lateIdx
                    mpfx = sprintf('ml_var%d', i);
                    NMTrainTemplateUI.writeMLStateFiles(orch, mpfx, tmpDir, mlHtml, workspaceJson, ctx);
                end
            else
                lateIdx = [];
            end
            if orch.FusionFlag == 3
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   export late-fusion ML:   %.3fs (modalities=%d)%s\n', profileId, toc(tLate), double(numel(lateIdx)), NMTrainTemplateUI.deferredSuffix(fastChildOpen));
            end

            t = tic;
            menuHtml = fullfile(webDir,'nm_train_template_menu.html');
            NMTrainTemplateUI.writeTextFile(menuHtml, NMTrainTemplateUI.htmlTextFromJson(menuStateJson));
            NMPreprocUI.writeBridge(fullfile(pyDir,'nm_bridge_server.py'));
            NMTrainTemplateUI.copyRendererAssets(webDir);
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   export html/assets:      %.3fs\n', profileId, toc(t));
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] trainTemplate export TOTAL: %.3fs\n', profileId, toc(tExport));

            paths = struct('root',outDir,'webRoot',webRoot,'webDir',webDir,'tmpDir',tmpDir, ...
                'html',menuHtml, 'menuHtml',menuHtml, 'preprocHtml',preprocHtml, 'mlHtml',mlHtml, ...
                'menuState',NMUIStateTools.statePath(tmpDir));
        end

        function orch = importUpdated(orch, pathsOrWebDir, ctx)
            % importUpdated  Import the edited training template from the browser session.
            %
            % Reads session NM/orchestrator state written by service calls, applies browser edits where
            % available and returns the updated orchestrator. It is the bridge between interactive
            % template editing and MATLAB-side template materialization.

            if nargin < 3, ctx = struct(); end %#ok<NASGU>
            if isstruct(pathsOrWebDir) && isfield(pathsOrWebDir,'tmpDir')
                tmpDir = pathsOrWebDir.tmpDir;
            else
                tmpDir = fullfile(pathsOrWebDir, 'tmp');
            end
            if ~exist(tmpDir,'dir')
                error('NMTrainTemplateUI:missingTmpDir', 'UI tmp directory not found: %s', tmpDir);
            end
            doProfile = NMTrainTemplateUI.profileEnabled(ctx);
            profileId = '-';
            if isstruct(ctx) && isfield(ctx,'NMProfileId') && ~isempty(ctx.NMProfileId)
                profileId = char(string(ctx.NMProfileId));
            end
            tImportTotal = tic;
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] importUpdated ENTER\n', profileId);

            t = tic;
            % One read of nm2_state.json serves the menu and every child slot;
            % NMUIStateTools.read already returns charified content.
            cfgState = NMUIStateTools.readConfigurator(tmpDir);
            menu = cfgState.menu;
            if ~isempty(fieldnames(menu))
                altBefore = orch.AlternativeLabel;
                orch.applyMenuState(menu);
                if ~isequaln(altBefore, orch.AlternativeLabel)
                    orch.applyAlternativeLabelContext(ctx);
                    return;
                end
                if ~isempty(orch.Synth) && isstruct(orch.Synth)
                    orch.NM = NMSynthTools.applyToNM(orch.NM, orch.Synth);
                    orch.Synth = NMSynthTools.stateFromNM(orch.NM);
                end
                if ~isempty(orch.Multi) && isstruct(orch.Multi)
                    orch.NM = NMMULTITools.applyToNM(orch.NM, orch.Multi, orch.VarIndex, orch.FusionFlag);
                    orch.Multi = NMMULTITools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                end
                if ~isempty(orch.RFE) && isstruct(orch.RFE)
                    orch.NM = NMRFETools.applyToNM(orch.NM, orch.RFE, orch.VarIndex, orch.FusionFlag);
                    orch.RFE = NMRFETools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                end
                if ~isempty(orch.Vis) && isstruct(orch.Vis)
                    orch.NM = NMVISTools.applyToNM(orch.NM, orch.Vis, orch.VarIndex, orch.FusionFlag);
                    orch.Vis = NMVISTools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                end
                if ~isempty(orch.MLI) && isstruct(orch.MLI)
                    orch.NM = NMMLITools.applyToNM(orch.NM, orch.MLI, orch.VarIndex, orch.FusionFlag);
                    orch.MLI = NMMLITools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                end
                % CV Build/Load/Save actions are executed immediately through
                % the MATLAB bridge while the browser is open. importUpdated only
                % mirrors the latest menu JSON into the orchestrator; it must not
                % run the full template export path at session shutdown.
            end
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   importUpdated menu/modules: %.3fs\n', profileId, toc(t));

            t = tic;
            for i = 1:orch.NumModalities
                state = NMUIStateTools.configuratorChild(cfgState, sprintf('preproc_var%d', i));
                if ~isempty(fieldnames(state))
                    pp = orch.materializePreprocBranch(i, false);
                    pp.applyUIState(state, pp.Context);
                end
            end

            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   importUpdated preproc children: %.3fs\n', profileId, toc(t));

            t = tic;
            state = NMUIStateTools.configuratorChild(cfgState, 'preproc_stacking');
            if ~isempty(fieldnames(state))
                pp = orch.materializePreprocBranch(1, true);
                pp.applyUIState(state, pp.Context);
            end

            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   importUpdated stacking preproc: %.3fs\n', profileId, toc(t));

            t = tic;
            state = NMUIStateTools.configuratorChild(cfgState, 'ml_global');
            if ~isempty(fieldnames(state))
                mlOrch = orch.materializeMLBranch('ml_global', ctx);
                [state, report] = mlOrch.ML.validateConfig(state, mlOrch.context(struct()), false);
                if ~report.ok
                    error('NMTrainTemplateUI:invalidMLState', ...
                        'Updated global ML UI state is invalid:\n%s', strjoin(report.errors, newline));
                end
                mlOrch.MLConfig = state;
            end

            if orch.FusionFlag == 3
                for i = 1:orch.NumModalities
                    state = NMUIStateTools.configuratorChild(cfgState, sprintf('ml_var%d', i));
                    if ~isempty(fieldnames(state))
                        mlOrch = orch.materializeMLBranch(sprintf('ml_var%d',i), ctx);
                        [state, report] = mlOrch.ML.validateConfig(state, mlOrch.context(struct()), false);
                        if ~report.ok
                            error('NMTrainTemplateUI:invalidMLState', ...
                                'Updated late-fusion STRAT{%d} ML UI state is invalid:\n%s', i, strjoin(report.errors, newline));
                        end
                        mlOrch.MLConfig = state;
                    end
                end
            end
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   importUpdated ML children: %.3fs\n', profileId, toc(t));
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] importUpdated TOTAL: %.3fs\n', profileId, toc(tImportTotal));
        end

        function orch = open(orch, outDir, ctx, port)
            % open  Launch the training-template configurator through the browser bridge.
            %
            % Exports the template UI, opens it interactively and imports any edited configuration after
            % the page closes. This is the normal MATLAB entry point for browser-based template
            % configuration.

            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_train_template_ui'); end
            if nargin < 3, ctx = struct(); end
            if nargin < 4, port = []; end
            doProfile = NMTrainTemplateUI.profileEnabled();
            tOpen = tic;
            t = tic;
            paths = NMTrainTemplateUI.export(orch, outDir, ctx);
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof] trainTemplate open export: %.3fs\n', toc(t));
            handler = @(req, tmpDir) NMTrainTemplateUI.handleMatlabService(orch, req, tmpDir, ctx);
            t = tic;
            nm_open_ui(paths.webDir, port, 'nm_train_template_menu.html', handler);
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof] trainTemplate open bridge session returned: %.3fs\n', toc(t));
            t = tic;
            orch = NMTrainTemplateUI.importUpdated(orch, paths, ctx);
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof] trainTemplate open importUpdated: %.3fs\n', toc(t));
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof] trainTemplate open TOTAL: %.3fs\n', toc(tOpen));
            % Do not call toNM unconditionally at browser shutdown. Menu actions
            % that must affect the internal NM immediately (for example CV
            % Build/Load/Save) are executed by the MATLAB bridge while the UI is
            % open. A final unconditional toNM would replay all configurators and
            % can re-trigger expensive module side effects such as external-rank
            % image import.
        end

        function [handled, out] = handleMatlabService(orch, req, tmpDir, ctx)
            % handleMatlabService  Dispatch training-template browser service requests.
            %
            % Routes menu application, canvas detail, modality diagnostics, dashboard, runner-preparation
            % and export/snapshot operations to focused service helpers. It reloads/persists session
            % orchestrator state so UI edits and backend NM template state stay synchronized.
            %
            % req.action: selects the requested service action in a UI bridge or runner dispatch request.
            % req.operation: selects the requested operation within an action family.

            handled = false;
            out = struct();
            if nargin < 4, ctx = struct(); end %#ok<NASGU>
            op = '';
            if isstruct(req) && isfield(req,'operation') && ~isempty(req.operation)
                op = char(string(req.operation));
            elseif isstruct(req) && isfield(req,'action') && ~isempty(req.action)
                op = char(string(req.action));
            end
            % nm2-allow: NMSimulationTools creates the optional SYNTH placeholder marker.
            if isfield(orch.NM,'SYNTH') && isfield(orch.NM.SYNTH,'fullySyntheticDefinition')
                allowed={'train_template_apply_menu','train_template_apply_cv','train_template_apply_preproc', ...
                    'train_template_apply_ml','train_template_apply_multi'};
                if startsWith(op,'train_template_apply_') && ~any(strcmp(op,allowed))
                    error('NMTrainTemplateUI:syntheticScope', ...
                        'Only CV, PREPROC, ML and applicable MULTI can be configured for SYNTH.');
                end
                if strcmp(op,'train_template_apply_multi') && ...
                        orch.NM.SYNTH.fullySyntheticDefinition.classCount<=2
                    error('NMTrainTemplateUI:syntheticScope','MULTI requires three or more classes.');
                end
            end
            switch lower(op)
                case 'train_template_apply_cv'
                    handled = true;
                    out = NMTrainTemplateUI.applyCVService(orch, req, tmpDir);
                case 'train_template_apply_preproc'
                    handled = true;
                    out = NMTrainTemplateUI.applyPreprocService(orch, req, tmpDir);
                case 'train_template_prepare_preproc'
                    handled = true;
                    out = NMTrainTemplateUI.preparePreprocService(orch, req, tmpDir);
                case {'rankfeat_import_external_file','preproc_resolve_rule_state'}
                    handled = true;
                    reqCtx = struct();
                    if isfield(req,'context') && isstruct(req.context), reqCtx = NMConfigTools.charifyStrings(req.context); end
                    idx = orch.VarIndex;
                    if isfield(reqCtx,'varind') && ~isempty(reqCtx.varind), idx = reqCtx.varind; end
                    isStacking = isfield(reqCtx,'source') && strcmp(reqCtx.source,'stacking');
                    pp = orch.materializePreprocBranch(idx, isStacking);
                    [~, out] = NMPreprocUI.handleMatlabService(req, tmpDir, pp.Context, pp.Registry, pp.RuleSet);
                    if strcmpi(op,'preproc_resolve_rule_state') && ~isStacking && isfield(out,'ruleProjection')
                        [~, ~, ~, out.ruleProjection] = orch.mixedEarlyFusionPreprocGuard(out.ruleProjection);
                    end
                case 'train_template_prepare_ml'
                    handled = true;
                    out = NMTrainTemplateUI.prepareMLService(orch, req, tmpDir, ctx);
                case 'train_template_copy_preproc'
                    handled = true;
                    out = NMTrainTemplateUI.copyPreprocService(orch, req, tmpDir);
                case 'train_template_apply_ml'
                    handled = true;
                    out = NMTrainTemplateUI.applyMLService(orch, req, tmpDir);
                case 'train_template_apply_menu'
                    handled = true;
                    out = NMTrainTemplateUI.applyMenuService(orch, req, tmpDir, ctx);
                case 'train_template_canvas_detail'
                    handled = true;
                    out = NMTrainTemplateUI.canvasDetailService(orch, req, tmpDir);
                case 'train_template_modality_diagnostics'
                    handled = true;
                    out = NMTrainTemplateUI.modalityDiagnosticsService(orch, req, tmpDir);
                case 'train_template_open_modality_qc_report'
                    handled = true;
                    out = NMTrainTemplateUI.openModalityQCReportService(orch, req, tmpDir);
                case 'train_template_data_dashboard'
                    handled = true;
                    out = NMTrainTemplateUI.dataDashboardService(orch, req, tmpDir);
                case 'train_template_apply_synth'
                    handled = true;
                    out = NMTrainTemplateUI.applySynthService(orch, req, tmpDir);
                case 'train_template_apply_multi'
                    handled = true;
                    out = NMTrainTemplateUI.applyMULTIService(orch, req, tmpDir);
                case 'train_template_apply_rfe'
                    handled = true;
                    out = NMTrainTemplateUI.applyRFEService(orch, req, tmpDir);
                case 'train_template_refresh_rfe'
                    handled = true;
                    out = NMTrainTemplateUI.refreshRFEService(orch, req, tmpDir);
                case 'train_template_apply_vis'
                    handled = true;
                    out = NMTrainTemplateUI.applyVISService(orch, req, tmpDir);
                case 'train_template_refresh_vis'
                    handled = true;
                    out = NMTrainTemplateUI.refreshVISService(orch, req, tmpDir);
                case 'train_template_refresh_mli'
                    handled = true;
                    out = NMTrainTemplateUI.refreshMLIService(orch, req, tmpDir);
                case 'train_template_apply_mli'
                    handled = true;
                    out = NMTrainTemplateUI.applyMLIService(orch, req, tmpDir);
                case 'train_template_apply_sav'
                    handled = true;
                    out = NMTrainTemplateUI.applySAVService(orch, req, tmpDir);
                case 'train_template_export_scaffold'
                    handled = true;
                    out = NMTrainTemplateUI.exportScaffoldService(orch, req, tmpDir, ctx);
                case 'train_template_save_snapshot'
                    handled = true;
                    out = NMTrainTemplateUI.saveSnapshotService(orch, req, tmpDir, ctx);
                case 'train_template_load_snapshot_preview'
                    handled = true;
                    out = NMTrainTemplateUI.loadSnapshotPreviewService(orch, req, tmpDir, ctx);
                case 'train_template_apply_snapshot'
                    handled = true;
                    out = NMTrainTemplateUI.applySnapshotService(orch, req, tmpDir, ctx);
                case 'train_template_export_methods_summary'
                    handled = true;
                    out = NMTrainTemplateUI.exportMethodsSummaryService(orch, req, tmpDir, ctx);
                case 'train_template_mli_import_atlas'
                    handled = true;
                    out = NMTrainTemplateUI.importMLIAtlasService(orch, req, tmpDir);
                case 'train_template_mli_preview_descriptor'
                    handled = true;
                    out = NMTrainTemplateUI.previewMLIDescriptorService(orch, req, tmpDir);
                case 'train_template_mli_import_descriptor'
                    handled = true;
                    out = NMTrainTemplateUI.importMLIDescriptorService(orch, req, tmpDir);
            end
            mutatingOps = {'train_template_apply_cv','train_template_apply_preproc','train_template_copy_preproc', ...
                'train_template_apply_ml','train_template_apply_menu','train_template_apply_synth', ...
                'train_template_apply_multi','train_template_apply_rfe','train_template_apply_vis', ...
                'train_template_apply_mli','train_template_apply_sav','train_template_apply_snapshot', ...
                'train_template_mli_import_atlas','train_template_mli_import_descriptor'};
            if handled && any(strcmp(lower(op),mutatingOps)) && isstruct(out) && isfield(out,'ok') && logical(out.ok)
                didChange = true;
                if isfield(out,'changed'), didChange = logical(out.changed); end
                if didChange
                    key = erase(lower(op), 'train_template_apply_');
                    if strcmp(key,'copy_preproc'), key = 'preproc'; end
                    edited = isfield(req,'changedPaths') && ~isempty(req.changedPaths);
                    edited = edited || (isfield(req,'childChangedPaths') && ~isempty(req.childChangedPaths));
                    if strcmp(key,'cv') && isfield(req,'cvAction')
                        edited = any(strcmp(req.cvAction, {'build','load'}));
                    elseif any(strcmp(key, {'rfe','vis','mli','sav','multi','synth'}))
                        branch = req.state.(key);
                        edited = logical(branch.([key 'Dirty']));
                    end
                    if edited && any(strcmp(key, {'cv','preproc','ml','rfe','vis','mli','sav','multi','synth'}))
                        if any(strcmp(key, {'preproc','ml'})) && isfield(req,'module') && ~isempty(req.module)
                            moduleKey = char(string(req.module));
                            if ~strcmp(moduleKey,'ml_global'), key = moduleKey; end
                        elseif strcmp(key,'rfe') && orch.FusionFlag == 3
                            key = sprintf('rfe_var%d',orch.VarIndex);
                        end
                        orch.CommittedConfigurators = unique([orch.CommittedConfigurators, {key}], 'stable');
                        out.canvasDirty = true;
                        out.canvasDirtyReason = 'Configurator commit status changed; canvas refresh pending.';
                        if isfield(out,'state')
                            out.state.canvasDirty = true;
                            out.state.canvasDirtyReason = out.canvasDirtyReason;
                        end
                    end
                    NMDataIOUI.saveSessionNM(orch.NM,tmpDir);
                    workflow = NMStatusGuardTools.workflowStatus(orch.NM);
                    out.readinessDiagnostic = workflow.paramstr;
                end
            end
        end

        function out = applyMenuService(orch, req, tmpDir, ctx)
            % applyMenuService  Apply browser menu edits to the orchestrator and refresh template state.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if nargin < 4, ctx = struct(); end
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            doProfile = NMTrainTemplateUI.profileEnabled(req);
            profileId = '-';
            if isstruct(req) && isfield(req,'profileId') && ~isempty(req.profileId)
                profileId = char(string(req.profileId));
            end
            includeCanvas = NMTrainTemplateUI.requestIncludeCanvas(req);
            try
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] applyMenuService ENTER\n', profileId);
                tTotal = tic;
                ctxBefore = orch.refreshContextSnapshot();
                altBefore = orch.AlternativeLabel;

                t1 = tic;
                [changedPaths, changedPathsSupplied] = NMTrainTemplateUI.requestChangedPaths(req);
                if changedPathsSupplied
                    orch.applyMenuState(menuState, changedPaths);
                else
                    orch.applyMenuState(menuState);
                end
                rebuiltForLabelContext = ~isequaln(altBefore, orch.AlternativeLabel);
                % Alternative-label edits change the effective supervised task. Materialize that
                % change at its LABEL authority, then rebuild the captured live orchestrator so
                % preprocessing/ML and Canvas cannot retain the pre-label task context.
                if rebuiltForLabelContext
                    orch.applyAlternativeLabelContext(ctx);
                end
                applyDt = toc(t1);
                ctxAfter = orch.refreshContextSnapshot();
                stackingSourcesChanged = ~isequal(ctxBefore.stackingSelectedAnalyses, ctxAfter.stackingSelectedAnalyses);
                needsRefresh = ~rebuiltForLabelContext && orch.refreshContextChanged(ctxBefore, ctxAfter);
                refreshDt = 0;
                if needsRefresh
                    tr = tic;
                    orch.refreshActiveConfiguratorStates();
                    refreshDt = toc(tr);
                    refreshTxt = 'refresh';
                elseif rebuiltForLabelContext
                    refreshTxt = 'alternative-label rebuild';
                else
                    refreshTxt = 'refresh skipped';
                end
                resetConfiguratorChildren = rebuiltForLabelContext || needsRefresh;
                if resetConfiguratorChildren
                    NMTrainTemplateUI.invalidateChildConfiguratorFiles(tmpDir);
                end
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyMenuState only:      %.3fs\n', profileId, applyDt);
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   %s: %.3fs\n', profileId, refreshTxt, refreshDt);
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyMenuState + %s: %.3fs\n', profileId, refreshTxt, applyDt + refreshDt);

                t2 = tic;
                fresh = orch.menuState(struct('includeCanvas', includeCanvas, 'profile', doProfile, 'profileId', profileId));
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   menuState() rebuild:       %.3fs\n', profileId, toc(t2));

                t3 = tic;
                fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh, tmpDir);
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   enrichForExport:           %.3fs\n', profileId, toc(t3));

                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] applyMenuService TOTAL:     %.3fs\n', profileId, toc(tTotal));

                menuChanged = ~changedPathsSupplied || ~isempty(changedPaths);
                out = struct('ok', true, 'message', 'Main menu context was applied to the internal NM state.', ...
                    'state', fresh, 'resetConfiguratorChildren', resetConfiguratorChildren, ...
                    'sequenceSourcesChanged', stackingSourcesChanged, 'changed', menuChanged);
            catch ME % nm2-allow: NMUIErrorTools creates the structured diagnostic response for this caught failure
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_apply_menu', ...
                    'Applying the training-template menu failed.', 2);
            end
        end


        function out = canvasDetailService(orch, req, tmpDir) %#ok<INUSD>
            % canvasDetailService  Return read-only canvas/detail information for the selected template.
            %
            % component.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.detailMode: carries the detail mode value from the browser/service request payload.
            % req.node: carries the node value from the browser/service request payload.
            % req.nodeId: carries the node id value from the browser/service request payload.
            % req.state: carries the current serialized browser state for service dispatch.

            try
                doProfile = NMTrainTemplateUI.profileEnabled(req);
                tTotal = tic;
                state = struct();
                if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                    state = NMConfigTools.charifyStrings(req.state);
                end
                audit = [];
                if isstruct(state) && isfield(state,'audit')
                    audit = state.audit;
                end
                if isempty(audit)
                    audit = orch.auditCurrentState(state);
                end
                node = struct();
                if isstruct(req) && isfield(req,'node') && isstruct(req.node)
                    node = NMConfigTools.charifyStrings(req.node);
                end
                nodeId = '';
                if isfield(node,'id') && ~isempty(node.id)
                    nodeId = char(string(node.id));
                elseif isstruct(req) && isfield(req,'nodeId') && ~isempty(req.nodeId)
                    nodeId = char(string(req.nodeId));
                end
                if isempty(fieldnames(node))
                    error('NMTrainTemplateUI:missingCanvasNode', 'No canvas node was supplied for detail generation.');
                end
                if isstruct(req) && isfield(req,'detailMode') && ~isempty(req.detailMode)
                    node.detailMode = char(string(req.detailMode));
                end
                tDetail = tic;
                detail = orch.canvasNodeDetail(node, state, audit);
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof] canvasDetailService node=%s detail: %.3fs total: %.3fs\n', ...
                    nodeId, toc(tDetail), toc(tTotal));
                out = struct('ok', true, 'nodeId', nodeId, 'detail', detail);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_canvasDetailService', 'canvasDetailService failed.', 2);
            end
        end

        function out = modalityDiagnosticsService(orch, req, tmpDir) %#ok<INUSD>
            % modalityDiagnosticsService  Return DataIO/modality diagnostics for a selected modality.
            %
            % card.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.modalityIndex: selects the modality addressed by a browser or runner request.

            try
                idx = NaN;
                if isstruct(req) && isfield(req,'modalityIndex') && ~isempty(req.modalityIndex)
                    idx = round(double(req.modalityIndex));
                end
                if ~isfinite(idx) || idx < 1
                    error('NMTrainTemplateUI:invalidModalityIndex', 'A valid modalityIndex is required for canvas modality diagnostics.');
                end
                info = NMModalityInfoTools.fromNM(orch.NM, idx, struct('ScanInMemory', false));
                fs = info.featureStats;
                keys = {'Index'; 'Name'; 'Source'; 'Storage mode'; 'Cases'; 'Observed cases'; 'Features'; 'Matrix class'; ...
                    'Missingness'; 'Complete cases'; 'Partly missing cases'; 'Complete-NaN cases'; 'All-NaN features'; ...
                    'Constant features'; 'Feature mean range'; 'Feature SD range'; 'Mask/space'; 'Source files'};
                vals = {sprintf('%g', idx); ...
                    NMTrainTemplateUI.valueText(info.label); ...
                    NMTrainTemplateUI.valueText(info.datasource); ...
                    NMTrainTemplateUI.valueText(info.storageMode); ...
                    NMTrainTemplateUI.numberText(info.nSubjects); ...
                    NMTrainTemplateUI.numberText(info.nObservedCases); ...
                    NMTrainTemplateUI.numberText(info.nFeatures); ...
                    NMTrainTemplateUI.valueText(info.matrixClass); ...
                    NMTrainTemplateUI.missingnessText(info); ...
                    NMTrainTemplateUI.numberText(fs.nCompleteCases); ...
                    NMTrainTemplateUI.numberText(fs.nPartialMissingCases); ...
                    NMTrainTemplateUI.numberText(fs.nAllNaNCases); ...
                    NMTrainTemplateUI.numberText(fs.nAllNaNFeatures); ...
                    NMTrainTemplateUI.numberText(fs.nConstantFeatures); ...
                    NMTrainTemplateUI.rangeText(fs.featureMeanMin, fs.featureMeanMax); ...
                    NMTrainTemplateUI.rangeText(fs.featureSDMin, fs.featureSDMax); ...
                    NMTrainTemplateUI.valueText(info.maskSummary); ...
                    NMTrainTemplateUI.numberText(info.nSourceFiles)};
                rowTemplate = struct('key','','value','');
                rows = repmat(rowTemplate, numel(keys), 1);
                for rr = 1:numel(keys)
                    rows(rr).key = keys{rr};
                    rows(rr).value = vals{rr};
                end
                diagnostics = info.diagnostics;
                [previewPayload, previewRows] = NMTrainTemplateUI.persistedModalityPreview(orch.NM, idx, info);
                qc = NMTrainTemplateUI.persistedModalityQC(orch.NM, idx);
                qcSummary = NMTrainTemplateUI.persistedQCSummary(qc);
                qcDashboard = NMTrainTemplateUI.persistedQCDashboard(qc);
                metadataDashboard = NMTrainTemplateUI.persistedSubjectMetadataDashboard(orch.NM, idx);
                reportRef = NMTrainTemplateUI.persistedQCReport(qc);
                hasPreview = isstruct(previewPayload) && isfield(previewPayload,'rows') && ~isempty(previewPayload.rows);
                hasQC = isstruct(qcDashboard) && isfield(qcDashboard,'available') && logical(qcDashboard.available);
                hasReport = isstruct(reportRef) && ~isempty(fieldnames(reportRef));
                if hasPreview
                    inspectLabel = 'Show subject table';
                else
                    inspectLabel = 'No subject table available';
                end
                out = struct('ok', true, 'title', sprintf('Diagnostics modality #%g', idx), ...
                    'subtitle', 'Quality-control summary and stored modality information.', ...
                    'rows', rows, 'preview', previewPayload, 'previewRows', previewRows, 'diagnostics', {diagnostics}, ...
                    'hasPersistedPreview', hasPreview, 'hasPersistedQC', hasQC, 'hasPersistedQCReport', hasReport, ...
                    'inspectionButtonLabel', inspectLabel, 'qcSummary', qcSummary, 'qcDashboard', qcDashboard, ...
                    'metadataDashboard', metadataDashboard, 'qcReport', reportRef);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_modalityDiagnosticsService', 'modalityDiagnosticsService failed.', 2);
            end
        end

        function out = openModalityQCReportService(orch, req, tmpDir) %#ok<INUSD>
            % openModalityQCReportService  Open or return a persisted QC report reference for a modality.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.modalityIndex: selects the modality addressed by a browser or runner request.

            try
                idx = NaN;
                if isstruct(req) && isfield(req,'modalityIndex') && ~isempty(req.modalityIndex)
                    idx = round(double(req.modalityIndex));
                end
                if ~isfinite(idx) || idx < 1
                    error('NMTrainTemplateUI:invalidModalityIndex', 'A valid modalityIndex is required to open a modality QC report.');
                end
                qc = NMTrainTemplateUI.persistedModalityQC(orch.NM, idx);
                reportRef = NMTrainTemplateUI.persistedQCReport(qc);
                pathToOpen = '';
                if isstruct(reportRef) && isfield(reportRef,'pdfPath') && exist(char(reportRef.pdfPath),'file') == 2
                    pathToOpen = char(reportRef.pdfPath);
                elseif isstruct(reportRef) && isfield(reportRef,'htmlPath') && exist(char(reportRef.htmlPath),'file') == 2
                    pathToOpen = char(reportRef.htmlPath);
                end
                if isempty(pathToOpen)
                    error('NMTrainTemplateUI:missingQCReport', 'No readable saved QC report file was found for modality #%g.', idx);
                end
                web(pathToOpen, '-browser');
                out = struct('ok', true, 'message', sprintf('Opened modality #%g QC report: %s', idx, pathToOpen), 'path', pathToOpen);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_openModalityQCReportService', 'openModalityQCReportService failed.', 2);
            end
        end

        function out = dataDashboardService(orch, req, tmpDir) %#ok<INUSD>
            % dataDashboardService  Build the label, covariate, modality-preview and QC dashboard payload.
            %
            % shown in the template UI.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.kind: carries the kind value from the browser/service request payload.

            try
                kind = '';
                if isstruct(req) && isfield(req,'kind') && ~isempty(req.kind)
                    kind = lower(char(string(req.kind)));
                end
                switch kind
                    case 'labels'
                        dashboard = NMTrainTemplateUI.labelDashboard(orch.NM);
                        out = struct('ok', true, 'kind', 'labels', 'title', 'Label Dashboard', ...
                            'subtitle', 'Current analysis labels used for model training.', 'dashboard', dashboard);
                    case 'covariates'
                        dashboard = NMTrainTemplateUI.covariateDashboard(orch.NM);
                        out = struct('ok', true, 'kind', 'covariates', 'title', 'Covariate Dashboard', ...
                            'subtitle', 'Covariates available for preprocessing and model analysis.', 'dashboard', dashboard);
                    otherwise
                        error('NMTrainTemplateUI:unknownDataDashboard', 'Unknown canvas data-dashboard kind: %s.', kind);
                end
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_dataDashboardService', 'dataDashboardService failed.', 2);
            end
        end

        function dashboard = labelDashboard(NM)
            % labelDashboard  Summarize labels for the template data dashboard.
            %
            % Extracts task mode, class/regression summaries and missing-label information from NM so the
            % template UI can explain the supervised target before analysis creation. It is read-only.

            itemTemplate = NMTrainTemplateUI.subjectMetadataItemTemplate();
            dashboard = struct('available', false, 'mode', '', 'nSubjects', NaN, 'nItems', 0, ...
                'items', repmat(itemTemplate, 0, 1), 'message', 'No labels are available.');
            [Y, mode, names, groups] = NMTrainTemplateUI.labelMatrixAndNames(NM);
            if isempty(Y), return; end
            dashboard.available = true;
            dashboard.mode = mode;
            dashboard.nSubjects = size(Y,1);
            if strcmp(mode, 'classification')
                item = NMTrainTemplateUI.subjectMetadataItemTemplate();
                item.name = 'label';
                item.label = 'Class label';
                item.role = 'label';
                item = NMTrainTemplateUI.summarizeCategoricalVector(Y(:,1), item, groups);
                dashboard.items = item;
                dashboard.nItems = 1;
            else
                nCols = size(Y,2);
                items = repmat(itemTemplate, nCols, 1);
                for ii = 1:nCols
                    label = sprintf('Label %d', ii);
                    if numel(names) >= ii && ~isempty(names{ii}), label = char(string(names{ii})); end
                    items(ii) = NMTrainTemplateUI.summarizeSubjectMetadataColumn(Y(:,ii), sprintf('label_%d', ii), label, 'label');
                end
                dashboard.items = items;
                dashboard.nItems = numel(items);
            end
            dashboard.message = '';
        end

        function dashboard = covariateDashboard(NM)
            % covariateDashboard  Summarize covariate and global-variable metadata for the dashboard.
            %
            % Reads NM covariate/global settings and prepares compact statistics/labels used by browser
            % cards. It does not modify covariate definitions.

            itemTemplate = NMTrainTemplateUI.subjectMetadataItemTemplate();
            dashboard = struct('available', false, 'mode', 'covariates', 'nSubjects', NaN, 'nItems', 0, ...
                'items', repmat(itemTemplate, 0, 1), 'message', 'No covariates are available.');
            if ~isstruct(NM) || ~isfield(NM,'covars') || isempty(NM.covars), return; end
            X = NM.covars;
            if ~isnumeric(X) && ~iscell(X), return; end
            names = {};
            if isfield(NM,'covnames') && ~isempty(NM.covnames)
                raw = NM.covnames;
                if iscell(raw), names = cellfun(@(x) char(string(x)), raw(:), 'UniformOutput', false);
                elseif isstring(raw) || ischar(raw), names = cellstr(string(raw)); end
            end
            nCols = size(X,2);
            items = repmat(itemTemplate, nCols, 1);
            for ii = 1:nCols
                label = sprintf('Covariate %d', ii);
                if numel(names) >= ii && ~isempty(names{ii}), label = char(string(names{ii})); end
                items(ii) = NMTrainTemplateUI.summarizeSubjectMetadataColumn(X(:,ii), label, label, 'covariate');
            end
            dashboard.available = true;
            dashboard.nSubjects = size(X,1);
            dashboard.items = items;
            dashboard.nItems = numel(items);
            dashboard.message = '';
        end

        function [Y, mode, names, groups] = labelMatrixAndNames(NM)
            % labelMatrixAndNames  Resolve response vectors and display names from NM.
            %
            % Normalizes classification/regression labels, alternative-label names and group labels into
            % a matrix/name representation consumed by dashboard summaries. No relabeling or imputation
            % is performed.

            Y = []; mode = ''; names = {}; groups = {};
            if ~isstruct(NM) || ~isfield(NM,'label') || isempty(NM.label), return; end
            LABEL = NMAlternativeLabelTools.extractLabel(NM);
            altActive = isfield(LABEL,'flag') && LABEL.flag == 1;
            Y = NMAlternativeLabelTools.activeLabel(NM);
            if isvector(Y), Y = Y(:); end
            mode = lower(char(string(NMAlternativeLabelTools.effectiveMode(NM))));
            if contains(mode, 'class'), mode = 'classification'; else, mode = 'regression'; end
            if altActive
                if isfield(LABEL,'newlabelname') && ~isempty(LABEL.newlabelname), names = {char(string(LABEL.newlabelname))}; end
                if isfield(LABEL,'newgroupnames') && ~isempty(LABEL.newgroupnames), groups = cellstr(string(LABEL.newgroupnames)); end
            else
                if isfield(NM,'labelnames') && ~isempty(NM.labelnames)
                    raw = NM.labelnames;
                    if iscell(raw), names = cellfun(@(x) char(string(x)), raw(:), 'UniformOutput', false);
                    elseif isstring(raw) || ischar(raw), names = cellstr(string(raw)); end
                end
                if isfield(NM,'groupnames') && ~isempty(NM.groupnames)
                    raw = NM.groupnames;
                    if iscell(raw), groups = cellfun(@(x) char(string(x)), raw(:), 'UniformOutput', false);
                    elseif isstring(raw) || ischar(raw), groups = cellstr(string(raw)); end
                end
            end
        end

        function [preview, rows] = persistedModalityPreview(NM, idx, info, maxRows)
            % persistedModalityPreview  Read a bounded preview table for a committed modality.
            %
            % Uses persisted DataIO preview artifacts when available to populate the template data
            % dashboard without recomputing import previews. It returns browser rows and keeps NM
            % unchanged.

            if nargin < 4 || isempty(maxRows), maxRows = 50; end
            preview = struct();
            rows = struct([]);
            if isstruct(NM) && isfield(NM,'datadescriptor') && numel(NM.datadescriptor) >= idx && isstruct(NM.datadescriptor{idx}) && ...
                    isfield(NM.datadescriptor{idx},'input_settings') && isstruct(NM.datadescriptor{idx}.input_settings) && ...
                    isfield(NM.datadescriptor{idx}.input_settings,'preview') && isstruct(NM.datadescriptor{idx}.input_settings.preview)
                preview = NMDataIOUI.previewForBrowser(NM.datadescriptor{idx}.input_settings.preview, 1, maxRows);
                rows = NMTrainTemplateUI.previewRowsFromPayload(preview, maxRows);
            end
        end

        function dashboard = persistedSubjectMetadataDashboard(NM, idx)
            % persistedSubjectMetadataDashboard  Build subject-metadata summaries for one modality.
            %
            % Combines persisted preview and DataIO descriptor metadata to explain labels, covariates and
            % globals associated with a modality card. It is used by the template dashboard after import
            % finalization.

            itemTemplate = NMTrainTemplateUI.subjectMetadataItemTemplate();
            dashboard = struct('available', false, 'nSubjects', NaN, 'nItems', 0, ...
                'items', repmat(itemTemplate, 0, 1), 'message', 'No stored subject metadata are available for this modality.');
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || numel(NM.datadescriptor) < idx || ...
                    ~isstruct(NM.datadescriptor{idx}) || ~isfield(NM.datadescriptor{idx},'input_settings') || ...
                    ~isstruct(NM.datadescriptor{idx}.input_settings)
                return;
            end
            io = NM.datadescriptor{idx}.input_settings;
            if ~isfield(io,'preview') || ~isstruct(io.preview)
                return;
            end
            T = NMTrainTemplateUI.previewArtifactTable(io.preview);
            if isempty(T) || height(T) < 1
                dashboard.message = 'The stored subject table does not contain metadata rows.';
                return;
            end
            dashboard.available = true;
            dashboard.nSubjects = height(T);
            varNames = T.Properties.VariableNames;
            globalCol = NMTrainTemplateUI.metadataColumnName(varNames, 'globalValue');
            if isempty(globalCol)
                dashboard.message = 'No stored global variable is available for this modality.';
                return;
            end
            label = NMTrainTemplateUI.metadataGlobalLabel(io);
            item = NMTrainTemplateUI.summarizeSubjectMetadataColumn(T.(globalCol), 'globalValue', label, 'global');
            if logical(item.available)
                dashboard.items = item;
                dashboard.nItems = 1;
                dashboard.message = '';
            else
                dashboard.message = 'No variable global metadata are available for this modality.';
            end
        end

        function T = previewArtifactTable(preview)
            % previewArtifactTable  Convert a persisted preview artifact into a MATLAB table.
            %
            % Normalizes stored table/cell/struct preview formats so dashboard code can inspect columns
            % consistently. It does not query the original input source.

            T = table();
            if ~isstruct(preview), return; end
            if isfield(preview,'rowTable') && istable(preview.rowTable)
                T = preview.rowTable;
            elseif isfield(preview,'rows') && isstruct(preview.rows) && ~isempty(preview.rows)
                T = struct2table(preview.rows(:));
            end
        end

        function names = metadataCovariateNames(io)
            % metadataCovariateNames  Resolve covariate display names from DataIO metadata.
            %
            % Reads explicit covariate names when present and returns stable names for dashboard cards
            % and axis labels. Generic fallbacks are used only when metadata are absent.

            names = {};
            if ~isstruct(io) || ~isfield(io,'covariateNames') || isempty(io.covariateNames), return; end
            raw = io.covariateNames;
            if iscell(raw)
                names = cell(numel(raw), 1);
                for ii = 1:numel(raw)
                    names{ii} = char(string(raw{ii}));
                end
            elseif ischar(raw) || isstring(raw)
                tmp = cellstr(string(raw(:)));
                names = tmp(:);
            end
            keep = false(numel(names), 1);
            for ii = 1:numel(names)
                keep(ii) = ~isempty(strtrim(names{ii}));
            end
            names = names(keep);
        end

        function label = metadataGlobalLabel(io)
            % metadataGlobalLabel  Resolve the display label for global variables.
            %
            % Translates DataIO global-variable metadata into the label shown in subject-metadata cards.
            % The method is read-only and does not change global correction settings.

            label = 'Global variable';
            if isstruct(io) && isfield(io,'globalName') && ~isempty(io.globalName)
                label = char(string(io.globalName));
            end
        end

        function col = metadataColumnName(varNames, wanted)
            % metadataColumnName  Match a requested metadata role to an available preview column.
            %
            % Looks up labels, covariates or globals by preferred names while tolerating absent columns.
            % Dashboard builders use it to avoid hard-coded column positions.

            col = '';
            if isempty(varNames) || isempty(wanted), return; end
            wanted = char(string(wanted));
            idx = find(strcmp(varNames, wanted), 1);
            if ~isempty(idx)
                col = varNames{idx};
            end
        end

        function template = subjectMetadataItemTemplate()
            % subjectMetadataItemTemplate  Return the fixed schema for dashboard metadata summary items.
            %
            % Creates a stable struct used for label/covariate/global summaries so browser code receives
            % predictable fields regardless of variable type.

            levelTemplate = struct('label','','count',0,'percent',NaN);
            template = struct('available', false, 'name','', 'label','', 'role','', 'kind','', ...
                'n',0, 'nMissing',0, 'nUnique',NaN, 'isConstant', false, 'allowPie', false, ...
                'min',NaN, 'p25',NaN, 'median',NaN, 'p75',NaN, 'max',NaN, 'mean',NaN, 'sd',NaN, ...
                'histCounts',[], 'histEdges',[], 'levels',repmat(levelTemplate,0,1), 'message','');
        end

        function item = summarizeSubjectMetadataColumn(values, name, label, role)
            % summarizeSubjectMetadataColumn  Summarize one subject-metadata column for the dashboard.
            %
            % Dispatches numeric versus categorical summarization and annotates the result with
            % role/name/label metadata. The method is read-only and preserves source values.

            item = NMTrainTemplateUI.subjectMetadataItemTemplate();
            item.name = char(string(name));
            item.label = char(string(label));
            item.role = char(string(role));
            item.n = numel(values);
            numeric = NMTrainTemplateUI.numericVectorFromValue(values);
            if numel(numeric) == numel(values) && any(isfinite(numeric))
                finiteVals = numeric(isfinite(numeric));
                uniqueVals = unique(finiteVals(:));
                if NMTrainTemplateUI.metadataTreatNumericAsCategorical(finiteVals, uniqueVals)
                    item = NMTrainTemplateUI.summarizeSubjectMetadataCategorical(values, item);
                else
                    item = NMTrainTemplateUI.summarizeSubjectMetadataNumeric(numeric, item);
                end
            else
                item = NMTrainTemplateUI.summarizeSubjectMetadataCategorical(values, item);
            end
        end

        function item = summarizeSubjectMetadataNumeric(x, item)
            % summarizeSubjectMetadataNumeric  Compute numeric metadata summary statistics.
            %
            % Calculates finite counts, missingness, range, mean and categorical treatment hints for
            % numeric labels/covariates/globals shown in the dashboard. It does not require Statistics
            % Toolbox functions.

            finiteMask = isfinite(double(x(:)));
            xf = double(x(finiteMask));
            item.n = numel(x);
            item.nMissing = numel(x) - numel(xf);
            item.kind = 'numeric';
            if isempty(xf)
                item.message = 'No numeric values are available.';
                return;
            end
            item.available = true;
            item.nUnique = numel(unique(xf));
            item.isConstant = item.nUnique <= 1;
            pct = NMTrainTemplateUI.percentilesNoToolbox(xf, [25 50 75]);
            item.min = min(xf);
            item.p25 = pct(1);
            item.median = pct(2);
            item.p75 = pct(3);
            item.max = max(xf);
            item.mean = mean(xf);
            if numel(xf) > 1, item.sd = std(xf, 0); else, item.sd = 0; end
            if ~item.isConstant
                [counts, edges] = NMTrainTemplateUI.histogramForVector(xf, 24);
                item.histCounts = counts;
                item.histEdges = edges;
                if item.nUnique < 100
                    item.levels = NMTrainTemplateUI.levelCountsFromFiniteNumeric(xf);
                    item.allowPie = ~isempty(item.levels);
                end
            else
                item.message = 'Value is constant across subjects.';
            end
        end

        function levels = levelCountsFromFiniteNumeric(xf)
            % levelCountsFromFiniteNumeric  Count distinct finite numeric levels for categorical display.
            %
            % Builds level/count pairs from finite numeric values so low-cardinality numeric covariates
            % or labels can be displayed as categories.

            levelTemplate = struct('label','','count',0,'percent',NaN);
            levels = repmat(levelTemplate, 0, 1);
            if isempty(xf), return; end
            [u, ~, ic] = unique(double(xf(:)));
            if numel(u) >= 100, return; end
            counts = accumarray(ic, 1, [numel(u), 1]);
            [counts, order] = sort(counts, 'descend');
            u = u(order);
            denom = max(1, numel(xf));
            levels = repmat(levelTemplate, numel(u), 1);
            for ii = 1:numel(u)
                levels(ii).label = NMTrainTemplateUI.compactNumberText(u(ii));
                levels(ii).count = double(counts(ii));
                levels(ii).percent = 100 * double(counts(ii)) / double(denom);
            end
        end

        function tf = metadataTreatNumericAsCategorical(finiteVals, uniqueVals)
            % metadataTreatNumericAsCategorical  Decide whether numeric metadata should be displayed
            % categorically.
            %
            % Uses cardinality and value pattern heuristics to distinguish continuous covariates from
            % class-like or ordinal numeric fields for dashboard rendering.

            tf = false;
            if isempty(finiteVals) || isempty(uniqueVals), return; end
            if numel(uniqueVals) > 12, return; end
            if all(abs(uniqueVals - round(uniqueVals)) < 1e-9)
                tf = true;
            end
        end

        function item = summarizeSubjectMetadataCategorical(values, item)
            % summarizeSubjectMetadataCategorical  Summarize a nonnumeric metadata column.
            %
            % Computes levels, counts and missingness for categorical/string metadata used in
            % subject-metadata dashboard cards. Source values are not modified.

            labels = NMTrainTemplateUI.metadataValueLabels(values);
            missing = cellfun(@isempty, labels);
            labels = labels(~missing);
            item.n = numel(missing);
            item.nMissing = sum(missing);
            item.kind = 'categorical';
            if isempty(labels)
                item.message = 'No categorical values are available.';
                return;
            end
            [u, ~, ic] = unique(labels(:));
            counts = accumarray(ic, 1, [numel(u), 1]);
            [counts, order] = sort(counts, 'descend');
            u = u(order);
            item.available = true;
            item.nUnique = numel(u);
            item.isConstant = item.nUnique <= 1;
            nShow = min(99, numel(u));
            levelTemplate = struct('label','','count',0,'percent',NaN);
            levels = repmat(levelTemplate, nShow, 1);
            denom = max(1, numel(labels));
            for ii = 1:nShow
                levels(ii).label = char(string(u{ii}));
                levels(ii).count = double(counts(ii));
                levels(ii).percent = 100 * double(counts(ii)) / double(denom);
            end
            item.levels = levels;
            if item.isConstant
                item.message = 'Value is constant across subjects.';
            elseif numel(u) > nShow
                item.message = sprintf('Showing %g of %g levels.', double(nShow), double(numel(u)));
            end
        end

        function item = summarizeCategoricalVector(values, item, levelNames)
            % summarizeCategoricalVector  Count categorical levels with optional display labels.
            %
            % Normalizes cell/string/numeric categorical values into level/count rows for UI rendering.
            % Optional level names are used only for display.

            item = NMTrainTemplateUI.summarizeSubjectMetadataCategorical(values, item);
            if nargin < 3 || isempty(levelNames) || ~isstruct(item) || isempty(item.levels), return; end
            for ii = 1:numel(item.levels)
                lab = strtrim(char(string(item.levels(ii).label)));
                num = str2double(lab);
                if isfinite(num)
                    idx = round(num);
                    if idx >= 1 && idx <= numel(levelNames) && ~isempty(levelNames{idx})
                        item.levels(ii).label = char(string(levelNames{idx}));
                    end
                end
            end
        end

        function labels = metadataValueLabels(values)
            % metadataValueLabels  Extract display labels for metadata values.
            %
            % Returns labels encoded in categorical or table metadata when available so dashboard
            % summaries can show meaningful category names.

            if istable(values), values = table2cell(values); end
            if iscategorical(values)
                labels = cellstr(values(:));
            elseif isstring(values) || ischar(values)
                labels = cellstr(string(values(:)));
            elseif isnumeric(values) || islogical(values)
                raw = values(:);
                labels = cell(numel(raw), 1);
                for ii = 1:numel(raw)
                    if isnumeric(raw(ii)) && isfinite(double(raw(ii)))
                        labels{ii} = NMTrainTemplateUI.compactNumberText(double(raw(ii)));
                    elseif islogical(raw(ii))
                        labels{ii} = char(string(raw(ii)));
                    else
                        labels{ii} = '';
                    end
                end
            elseif iscell(values)
                labels = cell(numel(values), 1);
                for ii = 1:numel(values)
                    v = values{ii};
                    if isempty(v)
                        labels{ii} = '';
                    elseif isnumeric(v) && isscalar(v) && isfinite(double(v))
                        labels{ii} = NMTrainTemplateUI.compactNumberText(double(v));
                    elseif islogical(v) && isscalar(v)
                        labels{ii} = char(string(v));
                    else
                        labels{ii} = char(string(v));
                    end
                end
            else
                labels = cell(numel(values), 1);
                for ii = 1:numel(labels), labels{ii} = ''; end
            end
            for ii = 1:numel(labels)
                labels{ii} = strtrim(char(string(labels{ii})));
                if strcmp(labels{ii}, '<missing>') || strcmpi(labels{ii}, 'nan')
                    labels{ii} = '';
                end
            end
        end

        function txt = compactNumberText(x)
            % compactNumberText  Format numeric values for compact dashboard display.
            %
            % Produces short stable text for counts, ranges and summary statistics without changing the
            % underlying numeric values.

            if ~isfinite(double(x)), txt = ''; return; end
            ax = abs(double(x));
            if ax ~= 0 && (ax >= 100000 || ax < 0.001)
                txt = sprintf('%.3g', double(x));
            elseif ax >= 100
                txt = sprintf('%.1f', double(x));
            elseif ax >= 10
                txt = sprintf('%.2f', double(x));
            else
                txt = sprintf('%.3f', double(x));
            end
            txt = regexprep(txt, '0+$', '');
            txt = regexprep(txt, '\.$', '');
        end

        function qc = persistedModalityQC(NM, idx)
            % persistedModalityQC  Read persisted QC information for a modality.
            %
            % Retrieves QC payload/report/cache fields stored in NM.datadescriptor during import so the
            % template UI can expose QC status without rerunning import diagnostics.

            qc = struct();
            if isstruct(NM) && isfield(NM,'datadescriptor') && numel(NM.datadescriptor) >= idx && isstruct(NM.datadescriptor{idx}) && ...
                    isfield(NM.datadescriptor{idx},'QC') && isstruct(NM.datadescriptor{idx}.QC)
                qc = NM.datadescriptor{idx}.QC;
            elseif isstruct(NM) && isfield(NM,'QC') && iscell(NM.QC) && numel(NM.QC) >= idx && isstruct(NM.QC{idx})
                qc = NM.QC{idx};
            end
        end

        function report = persistedQCReport(qc)
            % persistedQCReport  Extract the persisted QC report reference from a QC artifact.
            %
            % Normalizes report-path/report-HTML metadata for dashboard links and service calls. It does
            % not open files itself.

            report = struct();
            if isstruct(qc) && isfield(qc,'report') && isstruct(qc.report)
                if isfield(qc.report,'htmlPath') && ~isempty(qc.report.htmlPath), report.htmlPath = char(string(qc.report.htmlPath)); end
                if isfield(qc.report,'pdfPath') && ~isempty(qc.report.pdfPath), report.pdfPath = char(string(qc.report.pdfPath)); end
                if isfield(qc.report,'bundleDir') && ~isempty(qc.report.bundleDir), report.bundleDir = char(string(qc.report.bundleDir)); end
                if isfield(qc.report,'generatedAt') && ~isempty(qc.report.generatedAt), report.generatedAt = char(string(qc.report.generatedAt)); end
            end
        end

        function summary = persistedQCSummary(qc)
            % persistedQCSummary  Extract compact QC summary information for a modality.
            %
            % Reads summary fields generated by DataIO/QC import pathways so dashboard cards can display
            % availability, warnings and aggregate metrics.

            dashboard = NMTrainTemplateUI.persistedQCDashboard(qc);
            rowTemplate = struct('key','','value','');
            rows = repmat(rowTemplate, 0, 1);
            if isstruct(dashboard) && isfield(dashboard,'available') && logical(dashboard.available)
                keys = {'QC subjects'; 'QC features'; 'Feature space'; 'Primary score'; 'Available QC metrics'};
                vals = {NMTrainTemplateUI.numberText(NMTrainTemplateUI.fieldOr(dashboard,'nSubjects',NaN)); ...
                    NMTrainTemplateUI.numberText(NMTrainTemplateUI.fieldOr(dashboard,'nFeatures',NaN)); ...
                    NMTrainTemplateUI.valueText(NMTrainTemplateUI.fieldOr(dashboard,'featureSpace','')); ...
                    NMTrainTemplateUI.valueText(NMTrainTemplateUI.fieldOr(dashboard,'primaryScore','')); ...
                    NMTrainTemplateUI.numberText(numel(NMTrainTemplateUI.fieldOr(dashboard,'metrics',repmat(struct(),0,1))))};
                rows = repmat(rowTemplate, numel(keys), 1);
                for ii = 1:numel(keys)
                    rows(ii).key = keys{ii};
                    rows(ii).value = vals{ii};
                end
            end
            if isstruct(qc) && isfield(qc,'savedAt') && ~isempty(qc.savedAt)
                n0 = numel(rows);
                tmp = repmat(rowTemplate, n0 + 1, 1);
                if n0 > 0, tmp(1:n0) = rows; end
                tmp(n0 + 1) = struct('key','QC saved at', 'value', NMTrainTemplateUI.valueText(qc.savedAt));
                rows = tmp;
            end
            summary = struct('rows', rows);
        end

        function dashboard = persistedQCDashboard(qc)
            % persistedQCDashboard  Build browser dashboard content from a persisted QC payload.
            %
            % Summarizes QC metrics, report links and top subject outliers for the modality card. It is
            % read-only and uses the cached payload rather than recalculating QC.

            metricTemplate = NMTrainTemplateUI.qcMetricTemplate();
            dashboard = struct('available', false, 'sourceType', '', 'featureSpace', '', 'primaryScore', '', ...
                'nSubjects', NaN, 'nFeatures', NaN, 'nMetrics', 0, 'nHiddenMetrics', 0, 'viewerAvailable', false, ...
                'reportAvailable', false, 'metrics', repmat(metricTemplate, 0, 1), 'hiddenMetricLabels', {{}} , ...
                'message', 'No saved QC results are available for this modality.');
            payload = struct();
            if isstruct(qc) && isfield(qc,'payload') && isstruct(qc.payload)
                payload = qc.payload;
            end
            if ~isstruct(payload) || isempty(fieldnames(payload))
                return;
            end
            nSubjects = NMTrainTemplateUI.safeScalar(NMTrainTemplateUI.fieldOr(payload,'nSubjects',NaN));
            caseIds = NMTrainTemplateUI.qcCaseIds(payload, nSubjects);
            if ~isfinite(nSubjects) || nSubjects < 1
                nSubjects = numel(caseIds);
            end
            if ~isfinite(nSubjects) || nSubjects < 1
                dashboard.message = 'Saved QC results are available, but the subject count could not be inferred.';
                return;
            end
            dashboard.available = true;
            dashboard.message = '';
            dashboard.sourceType = NMTrainTemplateUI.valueText(NMTrainTemplateUI.fieldOr(payload,'sourceType',''));
            dashboard.featureSpace = NMTrainTemplateUI.valueText(NMTrainTemplateUI.fieldOr(payload,'featureSpace',''));
            dashboard.primaryScore = NMTrainTemplateUI.valueText(NMTrainTemplateUI.fieldOr(payload,'primaryScore',''));
            dashboard.nSubjects = double(nSubjects);
            dashboard.nFeatures = NMTrainTemplateUI.safeScalar(NMTrainTemplateUI.fieldOr(payload,'nFeatures',NaN));
            dashboard.viewerAvailable = NMTrainTemplateUI.qcViewerAvailable(payload);
            dashboard.reportAvailable = isstruct(qc) && isfield(qc,'report') && isstruct(qc.report) && ~isempty(fieldnames(qc.report));
            metricNames = NMTrainTemplateUI.qcMetricCandidateNames(payload, nSubjects);
            metrics = repmat(metricTemplate, numel(metricNames), 1);
            keep = false(numel(metricNames), 1);
            hiddenLabels = cell(numel(metricNames), 1);
            nHidden = 0;
            for ii = 1:numel(metricNames)
                name = metricNames{ii};
                if isempty(name) || ~isfield(payload, name), continue; end
                if NMTrainTemplateUI.skipQCDashboardMetric(name)
                    nHidden = nHidden + 1;
                    hiddenLabels{nHidden} = NMTrainTemplateUI.qcMetricLabel(name);
                    continue;
                end
                vec = NMTrainTemplateUI.numericVectorFromValue(payload.(name));
                if numel(vec) ~= nSubjects, continue; end
                metrics(ii) = NMTrainTemplateUI.summarizeQCMetric(name, vec, caseIds, dashboard.primaryScore);
                if ~logical(metrics(ii).hasVariation)
                    nHidden = nHidden + 1;
                    hiddenLabels{nHidden} = metrics(ii).label;
                    continue;
                end
                keep(ii) = true;
            end
            metrics = metrics(keep);
            dashboard.metrics = metrics;
            dashboard.nMetrics = numel(metrics);
            dashboard.nHiddenMetrics = nHidden;
            dashboard.hiddenMetricLabels = hiddenLabels(1:nHidden);
            if dashboard.nMetrics == 0
                dashboard.message = 'Saved QC results are available, but no variable subject-level QC distributions were found.';
            end
        end

        function tf = qcViewerAvailable(payload)
            % qcViewerAvailable  Decide whether a persisted QC payload can support viewer plots.
            %
            % Checks for metric vectors and case alignment needed by subject/group QC viewers. The result
            % controls UI affordances only.

            tf = false;
            if ~isstruct(payload) || ~isfield(payload,'viewerOverlay') || ~isstruct(payload.viewerOverlay), return; end
            vo = payload.viewerOverlay;
            if isfield(vo,'cacheToken') && ~isempty(vo.cacheToken)
                tf = true;
            end
            if isfield(vo,'persistedCacheFile') && ~isempty(vo.persistedCacheFile) && exist(char(string(vo.persistedCacheFile)),'file') == 2
                tf = true;
            end
        end

        function template = qcMetricTemplate()
            % qcMetricTemplate  Return the fixed schema for QC metric dashboard entries.
            %
            % Creates predictable fields for metric labels, summary statistics and outlier rows so
            % browser cards can render heterogeneous QC payloads consistently.

            template = struct('name','', 'label','', 'n',0, 'nMissing',0, 'min',NaN, 'p05',NaN, 'p25',NaN, ...
                'median',NaN, 'p75',NaN, 'p95',NaN, 'max',NaN, 'mean',NaN, 'sd',NaN, ...
                'histCounts',[], 'histEdges',[], 'topOutliers',repmat(struct('rank',NaN,'caseId','','value',NaN),0,1), ...
                'isPrimary',false, 'hasVariation', false);
        end

        function caseIds = qcCaseIds(payload, nSubjects)
            % qcCaseIds  Resolve case identifiers for QC metric rows.
            %
            % Uses payload case IDs when present and otherwise builds stable subject-number labels. This
            % preserves row alignment for dashboard outlier lists.

            n = NMTrainTemplateUI.safeScalar(nSubjects);
            if ~isfinite(n) || n < 0, n = 0; end
            caseIds = cell(max(0, round(n)), 1);
            for ii = 1:numel(caseIds)
                caseIds{ii} = sprintf('case_%g', ii);
            end
            if isstruct(payload) && isfield(payload,'caseIds') && ~isempty(payload.caseIds)
                raw = payload.caseIds;
                if iscell(raw)
                    m = min(numel(raw), numel(caseIds));
                    for ii = 1:m
                        if ~isempty(raw{ii}), caseIds{ii} = char(string(raw{ii})); end
                    end
                elseif isstring(raw) || ischar(raw)
                    rawCell = cellstr(string(raw(:)));
                    m = min(numel(rawCell), numel(caseIds));
                    caseIds(1:m) = rawCell(1:m);
                end
            end
        end

        function names = qcMetricCandidateNames(payload, nSubjects)
            % qcMetricCandidateNames  List QC payload fields that can be summarized as metrics.
            %
            % Filters payload fields by vector length and numeric convertibility so dashboard summaries
            % ignore metadata and non-metric fields.

            preferred = {'rmsZ'; 'meanAbsZ'; 'meanZ'; 'sdZ'; 'maxAbsZ'; ...
                'missingFeatureRateBySubject'; 'zeroFeatureRateBySubject'; 'outlierFeatureRateBySubject'; ...
                'nMissingFeaturesBySubject'; 'nZeroFeaturesBySubject'; 'nOutlierFeaturesBySubject'; ...
                'nValidFeaturesBySubject'; 'nFiniteFeaturesBySubject'};
            allFields = fieldnames(payload);
            tmp = cell(numel(preferred) + numel(allFields), 1);
            n = 0;
            for ii = 1:numel(preferred)
                if isfield(payload, preferred{ii})
                    n = n + 1;
                    tmp{n} = preferred{ii};
                end
            end
            for ii = 1:numel(allFields)
                name = allFields{ii};
                if any(strcmp(tmp(1:n), name)), continue; end
                if any(strcmp(name, {'schemaVersion','sourceType','featureSpace','primaryScore','nSubjects','nFeatures','caseIds','viewerOverlay','reportPayload','qcCacheToken','maskFile'}))
                    continue;
                end
                vec = NMTrainTemplateUI.numericVectorFromValue(payload.(name));
                if numel(vec) == nSubjects
                    n = n + 1;
                    tmp{n} = name;
                end
            end
            names = tmp(1:n);
        end

        function tf = skipQCDashboardMetric(name)
            % skipQCDashboardMetric  Exclude bookkeeping fields from QC metric summaries.
            %
            % Keeps case IDs, labels and internal fields out of dashboard metric cards while allowing
            % genuine QC variables to be displayed.

            key = lower(regexprep(char(string(name)), '[^a-z0-9]', ''));
            tf = false;
            if isempty(key), tf = true; return; end
            if contains(key, 'index') || contains(key, 'flag') || contains(key, 'constant') || contains(key, 'allnan') || contains(key, 'row')
                tf = true;
            end
        end

        function metric = summarizeQCMetric(name, vec, caseIds, primaryScore)
            % summarizeQCMetric  Compute summary and outlier rows for one QC metric.
            %
            % Calculates finite counts, robust percentiles and top outliers for a metric vector aligned
            % to case IDs. It does not modify or threshold the underlying QC payload.

            metric = NMTrainTemplateUI.qcMetricTemplate();
            metric.name = char(string(name));
            metric.label = NMTrainTemplateUI.qcMetricLabel(metric.name);
            x = double(vec(:));
            finiteMask = isfinite(x);
            xf = x(finiteMask);
            metric.n = numel(x);
            metric.nMissing = numel(x) - numel(xf);
            metric.isPrimary = strcmpi(metric.name, char(string(primaryScore)));
            if isempty(xf), return; end
            pct = NMTrainTemplateUI.percentilesNoToolbox(xf, [5 25 50 75 95]);
            metric.min = min(xf);
            metric.p05 = pct(1);
            metric.p25 = pct(2);
            metric.median = pct(3);
            metric.p75 = pct(4);
            metric.p95 = pct(5);
            metric.max = max(xf);
            metric.hasVariation = isfinite(metric.min) && isfinite(metric.max) && metric.max > metric.min;
            metric.mean = mean(xf);
            if numel(xf) > 1
                metric.sd = std(xf, 0);
            else
                metric.sd = 0;
            end
            if ~logical(metric.hasVariation)
                return;
            end
            [counts, edges] = NMTrainTemplateUI.histogramForVector(xf, 12);
            metric.histCounts = counts;
            metric.histEdges = edges;
            if metric.isPrimary
                metric.topOutliers = NMTrainTemplateUI.topQCOutliers(x, finiteMask, caseIds, 10);
            end
        end

        function label = qcMetricLabel(name)
            % qcMetricLabel  Convert QC metric field names into readable labels.
            %
            % Maps known QC variables to scientific display labels and applies a readable fallback for
            % unknown payload fields. This label is used in dashboard cards and viewer controls.

            switch char(string(name))
                case 'rmsZ'
                    label = 'RMS z';
                case 'meanAbsZ'
                    label = 'Mean |z|';
                case 'meanZ'
                    label = 'Mean z';
                case 'sdZ'
                    label = 'SD z';
                case 'maxAbsZ'
                    label = 'Max |z|';
                case 'missingFeatureRateBySubject'
                    label = 'Missing-feature rate';
                case 'zeroFeatureRateBySubject'
                    label = 'Zero-feature rate';
                case 'outlierFeatureRateBySubject'
                    label = 'Outlier-feature rate';
                case 'nMissingFeaturesBySubject'
                    label = 'Missing features';
                case 'nZeroFeaturesBySubject'
                    label = 'Zero features';
                case 'nOutlierFeaturesBySubject'
                    label = 'Outlier features';
                case 'nValidFeaturesBySubject'
                    label = 'Valid features';
                case 'nFiniteFeaturesBySubject'
                    label = 'Finite features';
                otherwise
                    label = regexprep(char(string(name)), '([a-z])([A-Z])', '$1 $2');
            end
        end

        function vec = numericVectorFromValue(v)
            % numericVectorFromValue  Convert a payload value into a numeric column vector when possible.
            %
            % Accepts numeric, logical, cell or table-derived values and returns NaN where conversion is
            % not meaningful. It supports QC/metadata summarization without mutating payloads.

            vec = [];
            if isnumeric(v) || islogical(v)
                vec = double(v(:));
                return;
            end
            if iscell(v)
                vec = NaN(numel(v), 1);
                for ii = 1:numel(v)
                    vi = v{ii};
                    if isnumeric(vi) && isscalar(vi)
                        vec(ii) = double(vi);
                    elseif islogical(vi) && isscalar(vi)
                        vec(ii) = double(vi);
                    elseif ischar(vi) || isstring(vi)
                        d = str2double(char(string(vi)));
                        if isfinite(d), vec(ii) = d; end
                    end
                end
            end
        end

        function s = safeScalar(v)
            % safeScalar  Return a finite scalar or NaN for summary formatting.
            %
            % Normalizes percentile/count outputs before text formatting so dashboard code handles empty
            % or invalid calculations consistently.

            s = NaN;
            if isnumeric(v) && isscalar(v)
                s = double(v);
            elseif islogical(v) && isscalar(v)
                s = double(v);
            elseif ischar(v) || isstring(v)
                d = str2double(char(string(v)));
                if isfinite(d), s = d; end
            end
        end

        function q = percentilesNoToolbox(x, probs)
            % percentilesNoToolbox  Compute percentiles without requiring Statistics Toolbox.
            %
            % Implements the small percentile calculation needed by UI summaries using sorted finite
            % values. It keeps the dashboard independent of optional MATLAB toolboxes.

            x = sort(double(x(:)));
            probs = double(probs(:)');
            q = NaN(size(probs));
            n = numel(x);
            if n < 1, return; end
            if n == 1
                q(:) = x(1);
                return;
            end
            pos = 1 + (n - 1) .* probs ./ 100;
            lo = floor(pos);
            hi = ceil(pos);
            frac = pos - lo;
            for ii = 1:numel(probs)
                q(ii) = x(lo(ii)) .* (1 - frac(ii)) + x(hi(ii)) .* frac(ii);
            end
        end

        function [counts, edges] = histogramForVector(x, nBins)
            % histogramForVector  Build histogram counts and edges for dashboard vectors.
            %
            % Computes bounded histogram data from finite values so browser charts can render
            % label/covariate/QC distributions without MATLAB graphics.

            if nargin < 2 || isempty(nBins), nBins = 12; end
            x = double(x(:));
            x = x(isfinite(x));
            counts = [];
            edges = [];
            if isempty(x), return; end
            xmin = min(x);
            xmax = max(x);
            if xmin == xmax
                edges = [xmin - 0.5, xmax + 0.5];
                counts = numel(x);
                return;
            end
            edges = linspace(xmin, xmax, max(2, round(nBins) + 1));
            counts = histcounts(x, edges);
        end

        function rows = topQCOutliers(x, finiteMask, caseIds, maxRows)
            % topQCOutliers  Identify top subject-level QC outliers for dashboard display.
            %
            % Ranks finite metric values, attaches case IDs and returns a bounded row list for the QC
            % dashboard. It does not mark subjects as excluded.

            if nargin < 4 || isempty(maxRows), maxRows = 10; end
            rowTemplate = struct('rank',NaN,'caseId','','value',NaN);
            rows = repmat(rowTemplate, 0, 1);
            if isempty(x) || ~any(finiteMask), return; end
            idx = find(finiteMask(:));
            [~, order] = sort(double(x(idx)), 'descend');
            n = min([maxRows, numel(order), numel(idx)]);
            rows = repmat(rowTemplate, n, 1);
            for rr = 1:n
                sourceIdx = idx(order(rr));
                rows(rr).rank = rr;
                if sourceIdx <= numel(caseIds)
                    rows(rr).caseId = char(string(caseIds{sourceIdx}));
                else
                    rows(rr).caseId = sprintf('case_%g', sourceIdx);
                end
                rows(rr).value = double(x(sourceIdx));
            end
        end

        function rows = previewRowsFromPayload(preview, maxRows)
            % previewRowsFromPayload  Extract browser preview rows from a persisted preview payload.
            %
            % Returns a bounded row subset from persisted preview structures for display in modality
            % cards. It avoids rereading original import files.

            if nargin < 2 || isempty(maxRows), maxRows = 50; end
            rows = struct([]);
            if ~isstruct(preview) || ~isfield(preview,'rows') || isempty(preview.rows), return; end
            r = preview.rows;
            n = min(maxRows, numel(r));
            rows = r(1:n);
        end

        function v = fieldOr(s, name, defaultVal)
            % fieldOr  Read a struct field with a default fallback.
            %
            % Returns the fallback when the source is not a struct or the field is absent/empty. This
            % local helper keeps dashboard extraction explicit about missing metadata.

            v = defaultVal;
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
                v = s.(name);
            end
        end

        function txt = valueText(v)
            % valueText  Format arbitrary values for browser text fields.
            %
            % Converts numbers, strings, logicals and empty values into safe compact display text for
            % dashboard cells. It is not used for serialization back to NM.

            if isempty(v), txt = '—'; return; end
            txt = char(string(v));
            if isempty(strtrim(txt)), txt = '—'; end
        end

        function txt = numberText(v)
            % numberText  Format numeric summary values for dashboard display.
            %
            % Produces stable finite/NaN text for counts, percentiles and ranges shown in UI cards.

            if isnumeric(v) && isscalar(v) && isfinite(double(v))
                txt = sprintf('%g', double(v));
            else
                txt = '—';
            end
        end

        function txt = rangeText(a, b)
            % rangeText  Format a numeric min/max range for the dashboard.
            %
            % Combines two scalar values into compact range text while handling missing endpoints
            % explicitly.

            aa = NMTrainTemplateUI.numberText(a);
            bb = NMTrainTemplateUI.numberText(b);
            if strcmp(aa,'—') && strcmp(bb,'—')
                txt = '—';
            else
                txt = sprintf('%s to %s', aa, bb);
            end
        end

        function txt = missingnessText(info)
            % missingnessText  Format missing-value counts and percentages.
            %
            % Turns summary missingness fields into readable UI text for label, covariate and QC cards.

            if info.missingnessKnown
                n = NMTrainTemplateUI.numberText(info.nNaN);
                f = info.nanFraction;
                if isnumeric(f) && isscalar(f) && isfinite(double(f))
                    txt = sprintf('%s NaN value(s); %.3g%%', n, 100*double(f));
                else
                    txt = sprintf('%s NaN value(s)', n);
                end
            else
                txt = 'not scanned in lightweight export';
            end
        end

        function tf = profileEnabled(req)
            % profileEnabled  Determine whether template-UI profiling is enabled for a request.
            %
            % Reads request/context flags used to emit performance diagnostics during service handling.
            % It does not alter service behavior.
            %
            % req.nmProfile: carries the nm profile value from the browser/service request payload.
            % req.profile: carries the profile value from the browser/service request payload.
            % req.profileEnabled: carries the profile enabled value from the browser/service request payload.

            tf = false;
            try
                env = getenv('NM_UI_PROFILE');
                if ~isempty(env)
                    tf = any(strcmpi(strtrim(env), {'1','true','on','yes'}));
                end
            catch
                tf = false;
            end
            try
                if nargin >= 1 && isstruct(req)
                    if isfield(req,'profile')
                        tf = logical(req.profile);
                    elseif isfield(req,'profileEnabled')
                        tf = logical(req.profileEnabled);
                    elseif isfield(req,'nmProfile')
                        tf = logical(req.nmProfile);
                    end
                end
            catch
            end
        end

        function profileLog(enabled, varargin)
            % profileLog  Emit a template-UI profiling message when enabled.
            %
            % Writes timestamped diagnostic output around slow service paths such as dashboard
            % construction and child-page export.

            if ~enabled, return; end
            try
                fprintf(varargin{:});
            catch
            end
        end

        function tf = requestIncludeCanvas(req)
            % requestIncludeCanvas  Read whether a service response should include canvas state.
            %
            % Interprets browser request flags so service handlers can avoid returning heavy canvas
            % payloads unless the UI needs them.
            %
            % req.includeCanvas: carries the include canvas value from the browser/service request payload.
            % req.state: carries the current serialized browser state for service dispatch.

            tf = true;
            try
                if isstruct(req) && isfield(req,'includeCanvas')
                    tf = logical(req.includeCanvas);
                    return;
                end
                if isstruct(req) && isfield(req,'state') && isstruct(req.state) && isfield(req.state,'uiViewMode')
                    tf = strcmpi(char(string(req.state.uiViewMode)), 'canvas');
                end
            catch
                tf = true;
            end
        end

        function [paths, supplied] = requestChangedPaths(req)
            % requestChangedPaths  Read exact nm2_state menu paths supplied by the browser.
            % An explicitly empty list means that no parent-menu setting changed.
            supplied = isstruct(req) && isfield(req,'changedPaths');
            paths = {};
            if ~supplied, return; end
            raw = req.changedPaths;
            if isempty(raw), return; end
            paths = cellstr(string(raw(:)));
            paths = paths(~cellfun(@isempty,paths));
        end

        function keyedResponse = applyServiceMenuState(orch, state, req, ownedRoots)
            % applyServiceMenuState  Apply exact browser paths and identify a domain-only fast response.
            [paths, supplied] = NMTrainTemplateUI.requestChangedPaths(req);
            if supplied, orch.applyMenuState(state, paths); else, orch.applyMenuState(state); end
            keyedResponse = supplied;
            if keyedResponse && ~isempty(paths)
                roots = cellfun(@(p) strtok(char(string(p)),'.'), paths, 'UniformOutput', false);
                keyedResponse = all(ismember(roots, cellstr(string(ownedRoots(:)))));
            end
        end

        function out = finishDomainService(orch, req, tmpDir, keyedResponse, domain, value, message, reason, canvasDirty)
            % finishDomainService  Return one keyed modal branch or the legacy complete parent state.
            if keyedResponse
                out = struct('ok',true,'message',message,'canvasDirty',logical(canvasDirty),'canvasDirtyReason',reason);
                out.(domain) = value;
                out.auditSummary = orch.auditSummary(orch.auditCurrentState());
                return;
            end
            includeCanvas = NMTrainTemplateUI.requestIncludeCanvas(req);
            fresh = orch.menuState(struct('includeCanvas',includeCanvas,'profile',NMTrainTemplateUI.profileEnabled(req)));
            if ~includeCanvas, fresh.canvasDirty = true; fresh.canvasDirtyReason = reason; end
            fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh,tmpDir);
            out = struct('ok',true,'message',message,'state',fresh);
            out.(domain) = fresh.(domain);
        end

        function [paths, supplied] = requestChildChangedPaths(req)
            % requestChildChangedPaths  Read exact child-configurator STATE paths supplied by the browser.
            supplied = isstruct(req) && isfield(req,'childChangedPaths');
            paths = {};
            if ~supplied, return; end
            raw = req.childChangedPaths;
            if isempty(raw), return; end
            paths = cellstr(string(raw(:)));
            paths = paths(~cellfun(@isempty,paths));
        end

        function value = statePathGet(state, path)
            parts = regexp(char(string(path)),'\.','split');
            value = state;
            for i = 1:numel(parts)
                name = parts{i};
                if isempty(name) || ~isstruct(value) || ~isfield(value,name)
                    error('NMTrainTemplateUI:badChangedPath','Changed STATE path does not exist: %s',char(string(path)));
                end
                value = value.(name);
            end
        end

        function state = statePathSet(state, path, value)
            parts = regexp(char(string(path)),'\.','split');
            if isempty(parts) || any(cellfun(@isempty,parts))
                error('NMTrainTemplateUI:badChangedPath','Invalid changed STATE path: %s',char(string(path)));
            end
            if numel(parts) == 1
                state.(parts{1}) = value;
                return;
            end
            head = parts{1};
            if ~isfield(state,head) || ~isstruct(state.(head)), state.(head) = struct(); end
            state.(head) = NMTrainTemplateUI.statePathSet(state.(head),strjoin(parts(2:end),'.'),value);
        end

        function st = preprocChildStep(state, stage, idx)
            if ~isfield(state,stage) || ~isstruct(state.(stage)) || ...
                    ~isfield(state.(stage),'sequence') || ~isstruct(state.(stage).sequence) || ...
                    ~isfield(state.(stage).sequence,'steps')
                error('NMTrainTemplateUI:badChangedPath','Preprocessing STATE does not contain stage %s.',stage);
            end
            steps = state.(stage).sequence.steps;
            if iscell(steps)
                if idx < 1 || idx > numel(steps), error('NMTrainTemplateUI:badChangedPath','Preprocessing step index is out of range.'); end
                st = steps{idx};
            else
                if idx < 1 || idx > numel(steps), error('NMTrainTemplateUI:badChangedPath','Preprocessing step index is out of range.'); end
                st = steps(idx);
            end
        end

        function applyPreprocChildPaths(pp, state, paths)
            % applyPreprocChildPaths  Apply only browser-declared preprocessing STATE changes.
            if isempty(paths), return; end
            if any(strcmp(paths,'*'))
                pp.applyUIState(state,pp.Context);
                return;
            end

            paths = cellstr(string(paths(:)));
            subjectStructural = any(strcmp(paths,'subject.sequence.steps'));
            cvStructural = any(strcmp(paths,'cv.sequence.steps'));

            globalCfg = pp.GlobalOptions;
            globalChanged = false;
            patches = struct('stage',{},'idx',{},'cfg',{});
            for i = 1:numel(paths)
                path = char(string(paths{i}));
                if startsWith(path,'global.')
                    suffix = char(extractAfter(path,'global.'));
                    incoming = NMTrainTemplateUI.statePathGet(state.global,suffix);
                    globalCfg = NMTrainTemplateUI.statePathSet(globalCfg,suffix,incoming);
                    globalChanged = true;
                    continue;
                end

                tok = regexp(path,'^(subject|cv)\.sequence\.steps\.(\d+)\.config(?:\.(.+))?$','tokens','once');
                if ~isempty(tok)
                    stage = tok{1}; idx = str2double(tok{2});
                    if (strcmp(stage,'subject') && subjectStructural) || (strcmp(stage,'cv') && cvStructural)
                        continue;
                    end
                    suffix = '';
                    if numel(tok) >= 3 && ~isempty(tok{3}), suffix = tok{3}; end
                    incomingStep = NMTrainTemplateUI.preprocChildStep(state,stage,idx);
                    hit = find(strcmp({patches.stage},stage) & [patches.idx] == idx,1);
                    if isempty(hit)
                        if strcmp(stage,'subject'), seq = pp.SubjectSequence; else, seq = pp.CVSequence; end
                        hit = numel(patches) + 1;
                        patches(hit).stage = stage;
                        patches(hit).idx = idx;
                        patches(hit).cfg = seq.getStep(idx).config;
                    end
                    if isempty(suffix)
                        patches(hit).cfg = incomingStep.config;
                    else
                        incoming = NMTrainTemplateUI.statePathGet(incomingStep.config,suffix);
                        patches(hit).cfg = NMTrainTemplateUI.statePathSet(patches(hit).cfg,suffix,incoming);
                    end
                    continue;
                end

                if strcmp(path,'subject.sequence.steps') || strcmp(path,'cv.sequence.steps')
                    continue;
                end
                error('NMTrainTemplateUI:badChangedPath','Unsupported preprocessing changed STATE path: %s',path);
            end

            if globalChanged
                pp.GlobalOptions = NMPreprocGlobalOptions.normalize(globalCfg,pp.Context);
            end
            if subjectStructural
                pp.SubjectSequence.applyUIState(state.subject,pp.SubjectSequence.Context);
            end
            if cvStructural
                pp.CVSequence.applyUIState(state.cv,pp.CVSequence.Context);
            end
            for i = 1:numel(patches)
                if strcmp(patches(i).stage,'subject'), seq = pp.SubjectSequence; else, seq = pp.CVSequence; end
                seq.replaceConfig(patches(i).idx,patches(i).cfg);
            end
        end

        function syncMLStatePaths(orch, tmpDir, module, paths)
            % syncMLStatePaths  Apply only browser-declared ML STATE changes and materialize that ML branch to NM.
            if isempty(paths), return; end
            state = NMUIStateTools.readConfiguratorChild(tmpDir,module);
            if isempty(fieldnames(state))
                error('NMTrainTemplateUI:missingMLState','ML STATE slot is not initialized: %s',module);
            end
            state = NMConfigTools.charifyStrings(state);
            mlOrch = orch.materializeMLBranch(module, struct());
            if any(strcmp(paths,'*'))
                next = state;
            else
                next = mlOrch.MLConfig;
                for i = 1:numel(paths)
                    path = char(string(paths{i}));
                    incoming = NMTrainTemplateUI.statePathGet(state,path);
                    next = NMTrainTemplateUI.statePathSet(next,path,incoming);
                end
            end
            [next,report] = mlOrch.ML.validateConfig(next,mlOrch.context(struct()),false);
            if ~report.ok
                error('NMTrainTemplateUI:invalidMLState','Updated ML UI state is invalid:\n%s',strjoin(report.errors,newline));
            end
            mlOrch.MLConfig = next;
            if strcmp(module,'ml_global')
                mlOrch.VarIndex = [];
            end
            orch.NM = mlOrch.toNM(orch.NM);
        end

        function out = preparePreprocService(orch, req, tmpDir)
            % preparePreprocService  Prepare one preprocessing child editor.
            % Existing semantic child STATE is reused. Static renderer metadata is
            % regenerated only when missing; dynamic RuleSet facts are refreshed on accepted edits.
            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            doProfile = NMTrainTemplateUI.profileEnabled(req);
            profileId = '-';
            if isstruct(req) && isfield(req,'profileId') && ~isempty(req.profileId)
                profileId = char(string(req.profileId));
            end
            tTotal = tic;
            module = '';
            if isstruct(req) && isfield(req,'module') && ~isempty(req.module)
                module = char(string(req.module));
            end
            NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s] preparePreprocService ENTER module=%s\n',profileId,module);
            try
                t = tic;
                if isempty(module), module = NMTrainTemplateUI.preprocModuleNameForOrch(orch); end
                [idx, isStacking] = NMTrainTemplateUI.parsePreprocModuleName(module, orch.VarIndex);
                NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s]   preparePreproc module resolution: %.3fs\n',profileId,toc(t));

                t = tic;
                editorState = NMUIStateTools.readConfiguratorChild(tmpDir,module);
                stateExists = ~isempty(fieldnames(editorState));
                NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s]   preparePreproc STATE read:        %.3fs (exists=%d)\n',profileId,toc(t),double(stateExists));

                if isStacking
                    specPath = fullfile(tmpDir,'preproc_stacking_spec.json');
                else
                    specPath = fullfile(tmpDir,sprintf('preproc_var%d_spec.json',idx));
                end
                needAuthority = ~stateExists || exist(specPath,'file') ~= 2;
                t = tic;
                if needAuthority, orch.materializePreprocBranch(idx, isStacking); end
                NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s]   preparePreproc child materialize:  %.3fs (needed=%d)\n',profileId,toc(t),double(needAuthority));

                if isStacking
                    t = tic;
                    if exist(specPath,'file') ~= 2
                        NMConfigTools.writeJson(specPath, orch.StackingPreproc.toUISpec());
                    end
                    if ~stateExists, editorState = orch.StackingPreproc.toUIState(); end
                    NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s]   preparePreproc spec/state build:  %.3fs\n',profileId,toc(t));
                    t = tic;
                    out = struct('ok',true,'module',module,'prepared',true,'alreadyPrepared',stateExists, ...
                        'editorState',editorState,'message','Stacking preprocessing state is available.');
                    NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s]   preparePreproc result assembly:   %.3fs\n',profileId,toc(t));
                    NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s] preparePreprocService module=%s TOTAL: %.3fs\n',profileId,module,toc(tTotal));
                    return;
                end
                if idx < 1 || idx > orch.NumModalities
                    error('NMTrainTemplateUI:badPreprocModule','Invalid preprocessing module index: %s.',module);
                end

                t = tic;
                if exist(specPath,'file') ~= 2
                    NMConfigTools.writeJson(specPath,NMTrainTemplateUI.preprocSpecForParent(orch,orch.Preproc{idx}));
                end
                if ~stateExists, editorState = orch.Preproc{idx}.toUIState(); end
                NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s]   preparePreproc spec/state build:  %.3fs\n',profileId,toc(t));

                t = tic;
                out = struct('ok',true,'module',module,'modalityIndex',double(idx), ...
                    'prepared',true,'alreadyPrepared',stateExists,'editorState',editorState, ...
                    'message',sprintf('Preprocessing state is available for modality #%d.',double(idx)));
                NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s]   preparePreproc result assembly:   %.3fs\n',profileId,toc(t));
                NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s] preparePreprocService module=%s TOTAL: %.3fs\n',profileId,module,toc(tTotal));
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_preparePreprocService', 'preparePreprocService failed.', 2);
            end
        end

        function refreshPreprocDynamicSpec(orch, pp, specPath, applyParentPolicy)
            % refreshPreprocDynamicSpec  Refresh only sequence-dependent RuleSet facts in cached SPEC.
            % Static renderer/module metadata remains unchanged across preprocessing STATE edits.
            if exist(specPath,'file') ~= 2, return; end
            spec = NMConfigTools.charifyStrings(NMConfigTools.readJson(specPath));
            projection = pp.ruleProjection();
            if applyParentPolicy
                [~, ~, ~, projection] = orch.mixedEarlyFusionPreprocGuard(projection);
            end
            for stage = {'subject','cv'}
                name = stage{1};
                spec.stageSpecs.(name).resolvedStepFacts = projection.(name).facts;
                spec.stageSpecs.(name).spatialExtractorGate = projection.(name).spatialExtractorGate;
            end
            % Preserve the established top-level CV aliases exported by NMPreprocOrchestrator.toUISpec.
            spec.resolvedStepFacts = projection.cv.facts;
            spec.spatialExtractorGate = projection.cv.spatialExtractorGate;
            NMConfigTools.writeJson(specPath,spec);
        end

        function spec = preprocSpecForParent(orch, pp)
            % preprocSpecForParent  Add parent-owned mixed-fusion policy to MATLAB-derived facts.
            spec = pp.toUISpec();
            if orch.FusionFlag ~= 1 || ~orch.selectedFusionMixesImaging(), return; end
            stages = {'subject','cv'};
            for ss = 1:numel(stages)
                stage = stages{ss};
                sp = spec.stageSpecs.(stage);
                for ii = 1:numel(sp.resolvedStepFacts)
                    fact = sp.resolvedStepFacts{ii};
                    [bad, reason] = orch.mixedEarlyFusionFactReason(fact);
                    fact.mixedEarlyFusionBlocked = logical(bad);
                    fact.mixedEarlyFusionReason = reason;
                    sp.resolvedStepFacts{ii} = fact;
                end
                for ii = 1:numel(sp.defaultRuleFacts)
                    fact = sp.defaultRuleFacts{ii}.facts;
                    [bad, reason] = orch.mixedEarlyFusionFactReason(fact);
                    fact.mixedEarlyFusionBlocked = logical(bad);
                    fact.mixedEarlyFusionReason = reason;
                    sp.defaultRuleFacts{ii}.facts = fact;
                end
                spec.stageSpecs.(stage) = sp;
            end
        end

        function invalidateChildConfiguratorFiles(tmpDir)
            % invalidateChildConfiguratorFiles  Remove child renderer specs whose
            % scientific context was superseded. Mutable child STATE is cleared
            % by the browser through the nm2_state.json bridge transaction.
            if nargin < 1 || isempty(tmpDir) || exist(tmpDir,'dir') ~= 7, return; end
            for pattern = {'preproc_*_spec.json','ml_*_spec.json'}
                stale = dir(fullfile(tmpDir, pattern{1}));
                for i = 1:numel(stale), delete(fullfile(stale(i).folder, stale(i).name)); end
            end
        end

        function indices = initialPreprocExportIndices(orch)
            % initialPreprocExportIndices  Choose preprocessing modules to expose in child-page export.
            %
            % Uses the orchestrator/template context to decide which modality/module indices should be
            % serialized when opening the preprocessing editor.

            indices = [];
            try
                if isempty(orch) || orch.NumModalities < 1, return; end
                if orch.FusionFlag == 1 && ~isempty(orch.FusionModalities)
                    idx = round(double(orch.FusionModalities(1)));
                else
                    idx = round(double(orch.VarIndex));
                end
                if ~isfinite(idx) || idx < 1 || idx > orch.NumModalities, idx = 1; end
                indices = unique(idx, 'stable');
            catch
                indices = 1;
            end
        end

        function [pspecJson, pstateJson] = writePreprocStateFiles(orch, idx, tmpDir, preprocHtml, workspaceJson)
            % writePreprocStateFiles  Materialize immutable child bootstrap files
            % while keeping mutable preprocessing configuration in NM2 STATE.
            if idx < 1 || idx > orch.NumModalities
                error('NMTrainTemplateUI:badPreprocIndex','Invalid preprocessing modality index: %g.',double(idx));
            end
            if isempty(orch.Preproc{idx})
                error('NMTrainTemplateUI:missingPreprocOrchestrator','No preprocessing orchestrator is available for modality #%d.',double(idx));
            end
            pfx = sprintf('preproc_var%d',idx);
            pspec = NMTrainTemplateUI.preprocSpecForParent(orch,orch.Preproc{idx});
            pstate = NMUIStateTools.readConfiguratorChild(tmpDir,pfx);
            if isempty(fieldnames(pstate))
                pstate = orch.Preproc{idx}.toUIState();
                NMUIStateTools.writeConfiguratorChild(tmpDir,pfx,pstate);
            end
            pspecJson = NMConfigTools.writeJson(fullfile(tmpDir,[pfx '_spec.json']),pspec);
            pstateJson = NMConfigTools.writeJson(fullfile(tmpDir,[pfx '_param.json']),pstate);
            if nargin >= 4 && ~isempty(preprocHtml) && ~exist(preprocHtml,'file')
                if nargin < 5 || isempty(workspaceJson), workspaceJson = fullfile(tmpDir,'workspace.json'); end
                NMPreprocUI.writeHtmlFromJson(preprocHtml,pspecJson,pstateJson,workspaceJson);
            end
        end

        function [mlSpecJson, mlStateJson] = writeMLStateFiles(orch, module, tmpDir, mlHtml, workspaceJson, ctx)
            % writeMLStateFiles  Materialize immutable ML bootstrap files while
            % keeping mutable learner configuration in NM2 STATE.
            if nargin < 6, ctx = struct(); end
            module = char(string(module));
            if isempty(module), module = 'ml_global'; end
            if strcmp(module,'ml_global')
                mui = orch.MLGlobal.ui_configure(ctx);
            elseif startsWith(module,'ml_var')
                idx = str2double(extractAfter(module,'ml_var'));
                if ~isfinite(idx) || idx < 1 || idx > orch.NumModalities
                    error('NMTrainTemplateUI:badMLModule','Invalid ML module: %s.',module);
                end
                mui = orch.MLStrat{idx}.ui_configure(ctx);
            else
                error('NMTrainTemplateUI:badMLModule','Invalid ML module: %s.',module);
            end
            mlState = NMUIStateTools.readConfiguratorChild(tmpDir,module);
            if isempty(fieldnames(mlState))
                mlState = mui.state;
                NMUIStateTools.writeConfiguratorChild(tmpDir,module,mlState);
            end
            mui.spec.sequenceSources = orch.sequenceSourceCatalog(module);
            mlSpecJson = NMConfigTools.writeJson(fullfile(tmpDir,[module '_spec.json']),mui.spec);
            mlStateJson = NMConfigTools.writeJson(fullfile(tmpDir,[module '_param.json']),mlState);
            if nargin >= 4 && ~isempty(mlHtml) && ~exist(mlHtml,'file')
                if nargin < 5 || isempty(workspaceJson), workspaceJson = fullfile(tmpDir,'workspace.json'); end
                NMPreprocUI.writeHtmlFromJson(mlHtml,mlSpecJson,mlStateJson,workspaceJson);
            end
        end

        function out = prepareMLService(orch, req, tmpDir, ctx)
            % prepareMLService  Prepare one ML child editor from canonical
            % configurator STATE or, when no draft exists, the live orchestrator.
            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if nargin < 4, ctx = struct(); end
            doProfile = NMTrainTemplateUI.profileEnabled(req);
            profileId = '-';
            if isstruct(req) && isfield(req,'profileId') && ~isempty(req.profileId)
                profileId = char(string(req.profileId));
            end
            tTotal = tic;
            module = '';
            if isstruct(req) && isfield(req,'module') && ~isempty(req.module), module = char(string(req.module)); end
            NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s] prepareMLService ENTER module=%s\n',profileId,module);
            try
                t = tic;
                if isempty(module), module = 'ml_global'; end
                editorState = NMUIStateTools.readConfiguratorChild(tmpDir,module);
                stateExists = ~isempty(fieldnames(editorState));
                specPath = fullfile(tmpDir,[module '_spec.json']);
                NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s]   prepareML STATE read/module resolve: %.3fs (exists=%d)\n',profileId,toc(t),double(stateExists));

                specExists = exist(specPath,'file') == 2;
                needAuthority = ~specExists || ~stateExists;
                t = tic;
                mlOrch = [];
                if needAuthority, mlOrch = orch.materializeMLBranch(module, ctx); end
                NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s]   prepareML child materialize:          %.3fs (needed=%d)\n',profileId,toc(t),double(needAuthority));

                t = tic;
                if ~specExists
                    mlCtx = mlOrch.context(ctx);
                    spec = mlOrch.ML.configSpec(mlCtx);
                    spec.sequenceSources = orch.sequenceSourceCatalog(module);
                    NMConfigTools.writeJson(specPath,spec);
                end
                if ~stateExists, editorState = mlOrch.MLConfig; end
                NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s]   prepareML spec/state build:           %.3fs (spec=%d state=%d)\n', ...
                    profileId,toc(t),double(specExists),double(stateExists));

                t = tic;
                out = struct('ok',true,'module',module,'prepared',true,'alreadyPrepared',stateExists, ...
                    'editorState',editorState,'message','Machine-learning state is available.');
                NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s]   prepareML result assembly:            %.3fs\n',profileId,toc(t));
                NMTrainTemplateUI.profileLog(doProfile,'[nm-prof rid=%s] prepareMLService module=%s TOTAL: %.3fs\n',profileId,module,toc(tTotal));
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_prepareMLService', 'prepareMLService failed.', 2);
            end
        end

        function suffix = deferredSuffix(tf)
            % deferredSuffix  Return label text for deferred child-page state.
            %
            % Adds a short suffix used in service messages when child-page preparation defers heavy state
            % resolution. It is presentation-only.

            if tf
                suffix = ' (deferred=1)';
            else
                suffix = '';
            end
        end

        function out = applyCVService(orch, req, tmpDir)
            % applyCVService  Apply cross-validation menu edits to the orchestrator and rebuild dependent.
            %
            % template state.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.actionName: carries the action name value from the browser/service request payload.
            % req.cvAction: carries the cv action value from the browser/service request payload.
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            menuState = struct();
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = NMConfigTools.charifyStrings(NMUIStateTools.readConfiguratorMenu(tmpDir));
            end
            action = '';
            if isstruct(req) && isfield(req,'cvAction') && ~isempty(req.cvAction)
                action = lower(char(string(req.cvAction)));
            elseif isstruct(req) && isfield(req,'actionName') && ~isempty(req.actionName)
                action = lower(char(string(req.actionName)));
            end

            if ~isfield(menuState,'cv') || ~isstruct(menuState.cv)
                menuState.cv = orch.CVPartition;
            end
            includeCanvas = NMTrainTemplateUI.requestIncludeCanvas(req);
            switch action
                case 'build'
                    menuState.cv.cvBuildRequested = true;
                    menuState.cv.cvLoadRequested = false;
                    menuState.cv.cvSaveRequested = false;
                case 'load'
                    menuState.cv.cvLoadRequested = true;
                    menuState.cv.cvBuildRequested = false;
                case 'save'
                    menuState.cv.cvSaveRequested = true;
                otherwise
                    menuState.cv.cvBuildRequested = false;
                    menuState.cv.cvLoadRequested = false;
                    menuState.cv.cvSaveRequested = false;
            end

            try
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {'cv'});
                orch.NM = NMCVPartitionTools.applyToNM(orch.NM, orch.CVPartition);
                orch.CVPartition = NMCVPartitionTools.stateFromNM(orch.NM);
                if ~isempty(orch.Multi) && isstruct(orch.Multi)
                    orch.Multi = NMMULTITools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                    orch.NM = NMMULTITools.applyToNM(orch.NM, orch.Multi, orch.VarIndex, orch.FusionFlag);
                    orch.Multi = NMMULTITools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                end
                if keyedResponse
                    fast = NMTrainTemplateUI.enrichMenuStateForExport(struct('cv',orch.CVPartition), tmpDir);
                    NMCVPartitionTools.writePlotContext(orch.NM, fullfile(tmpDir,'cv_plot_context.mat'));
                    out = struct('ok',true,'message',NMTrainTemplateUI.cvServiceMessage(action,orch.NM), ...
                        'cv',fast.cv,'multi',orch.Multi, ...
                        'hasCV',isfield(orch.NM,'cv') && ~isempty(orch.NM.cv), ...
                        'canvasDirty',true,'canvasDirtyReason','Cross-validation configuration changed; canvas refresh was deferred.');
                    return;
                end
                fresh = orch.menuState(struct('includeCanvas', includeCanvas, 'profile', NMTrainTemplateUI.profileEnabled(req)));
                if ~includeCanvas
                    fresh.canvasDirty = true;
                    fresh.canvasDirtyReason = 'Cross-validation configuration changed; canvas refresh was deferred.';
                end
                fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh, tmpDir);
                NMCVPartitionTools.writePlotContext(orch.NM, fullfile(tmpDir,'cv_plot_context.mat'));
                out = struct('ok', true, 'message', NMTrainTemplateUI.cvServiceMessage(action, orch.NM), ...
                    'cv', fresh.cv, 'state', fresh, 'hasCV', isfield(orch.NM,'cv') && ~isempty(orch.NM.cv));
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_applyCVService', 'applyCVService failed.', 2);
            end
        end


        function out = applyMLService(orch, req, tmpDir)
            % applyMLService  Apply machine-learning module configuration returned from a child editor.
            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            doProfile = NMTrainTemplateUI.profileEnabled(req);
            profileId = '-';
            if isstruct(req) && isfield(req,'profileId') && ~isempty(req.profileId)
                profileId = char(string(req.profileId));
            end
            module = 'ml_global';
            if isstruct(req) && isfield(req,'module') && ~isempty(req.module), module = char(string(req.module)); end
            tTotal = tic;
            t = tic;
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] applyMLService ENTER; request state decode: %.3fs\n', profileId, toc(t));
            try
                includeCanvas = NMTrainTemplateUI.requestIncludeCanvas(req);
                [changedPaths, changedPathsSupplied] = NMTrainTemplateUI.requestChangedPaths(req);
                [childPaths, childPathsSupplied] = NMTrainTemplateUI.requestChildChangedPaths(req);

                t = tic;
                if changedPathsSupplied
                    orch.applyMenuState(menuState, changedPaths);
                else
                    orch.applyMenuState(menuState);
                end
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyML applyMenuState:      %.3fs\n', profileId, toc(t));

                t = tic;
                if childPathsSupplied
                    NMTrainTemplateUI.syncMLStatePaths(orch,tmpDir,module,childPaths);
                else
                    NMTrainTemplateUI.syncMLStatesFromState(orch,tmpDir);
                end
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyML sync child ML state: %.3fs\n', profileId, toc(t));


                if childPathsSupplied && isempty(childPaths) && changedPathsSupplied && isempty(changedPaths)
                    out = struct('ok',true,'message','Machine-learning configuration was unchanged.','changed',false);
                    NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] applyMLService TOTAL: %.3fs\n', profileId, toc(tTotal));
                    return;
                end

                t = tic;
                fresh = orch.menuState(struct('includeCanvas', includeCanvas, 'profile', doProfile, 'profileId', profileId));
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyML menuState rebuild:   %.3fs\n', profileId, toc(t));
                if ~includeCanvas
                    fresh.canvasDirty = true;
                    fresh.canvasDirtyReason = 'Machine-learning configuration changed; canvas refresh was deferred.';
                end

                t = tic;
                fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh, tmpDir);
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyML enrich/export state: %.3fs\n', profileId, toc(t));

                t = tic;
                out = struct('ok', true, 'message', 'Machine-learning configuration was applied to the internal ML branch.', ...
                    'state', fresh, 'mlSummary', fresh.mlSummary, 'changed', true);
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyML result assembly:     %.3fs\n', profileId, toc(t));
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_applyMLService', 'applyMLService failed.', 2);
            end
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] applyMLService TOTAL: %.3fs\n', profileId, toc(tTotal));
        end

        function out = applyPreprocService(orch, req, tmpDir)
            % applyPreprocService  Apply preprocessing edits using browser-declared child STATE paths.
            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            doProfile = NMTrainTemplateUI.profileEnabled(req);
            profileId = '-';
            if isstruct(req) && isfield(req,'profileId') && ~isempty(req.profileId)
                profileId = char(string(req.profileId));
            end
            tTotal = tic;
            t = tic;
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            module = '';
            if isstruct(req) && isfield(req,'module') && ~isempty(req.module), module = char(string(req.module)); end
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] applyPreprocService ENTER module=%s; request state decode: %.3fs\n', profileId, module, toc(t));
            try
                includeCanvas = NMTrainTemplateUI.requestIncludeCanvas(req);
                [changedPaths, changedPathsSupplied] = NMTrainTemplateUI.requestChangedPaths(req);
                [childPaths, childPathsSupplied] = NMTrainTemplateUI.requestChildChangedPaths(req);

                t = tic;
                if isempty(module), module = NMTrainTemplateUI.preprocModuleNameForOrch(orch); end
                [idx, isStacking] = NMTrainTemplateUI.parsePreprocModuleName(module, orch.VarIndex);
                childChanged = ~childPathsSupplied || ~isempty(childPaths);
                pfeDeactivate = false;
                if childChanged && ~isStacking
                    ppCheck = orch.materializePreprocBranch(idx, false);
                    childState = NMUIStateTools.readConfiguratorChild(tmpDir,module);
                    if isempty(fieldnames(childState))
                        error('NMTrainTemplateUI:missingPreprocState','Preprocessing STATE slot is not initialized: %s',module);
                    end
                    subjectSteps = childState.subject.sequence.steps;
                    cvSteps = childState.cv.sequence.steps;
                    if isstruct(subjectSteps), subjectSteps = num2cell(subjectSteps); end
                    if isstruct(cvSteps), cvSteps = num2cell(cvSteps); end
                    eligibility = ppCheck.RuleSet.crossCVFeatureIdentity( ...
                        ppCheck.Registry, subjectSteps, cvSteps);
                    activePFE = logical(orch.RFE.Filter.PFE.flag) || logical(orch.RFE.Wrapper.PFE.flag);
                    pfeDeactivate = activePFE && ~eligibility.eligible;
                    if pfeDeactivate && ~isfield(req,'confirmPFEDeactivation')
                        out = struct('ok',true,'requiresConfirmation',true,'reason', ...
                            [eligibility.reason,' Continue and disable active Cross-CV1 feature stability?']);
                        return;
                    end
                    if pfeDeactivate && ~logical(req.confirmPFEDeactivation)
                        error('NMTrainTemplateUI:PFEConfirmationRequired', ...
                            'Preprocessing cannot be committed without confirming PFE deactivation.');
                    end
                end
                if changedPathsSupplied
                    orch.applyMenuState(menuState, changedPaths);
                else
                    orch.applyMenuState(menuState);
                end
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyPreproc applyMenuState:        %.3fs\n', profileId, toc(t));

                t = tic;
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyPreproc module resolution:     %.3fs\n', profileId, toc(t));
                t = tic;
                if childChanged
                    orch.materializePreprocBranch(idx, isStacking);
                    if isStacking
                        st = NMUIStateTools.readConfiguratorChild(tmpDir,'preproc_stacking');
                        if isempty(fieldnames(st)), error('NMTrainTemplateUI:missingPreprocState','Preprocessing STATE slot is not initialized: preproc_stacking'); end
                        st = NMConfigTools.charifyStrings(st);
                        if childPathsSupplied
                            NMTrainTemplateUI.applyPreprocChildPaths(orch.StackingPreproc,st,childPaths);
                        else
                            orch.StackingPreproc.applyUIState(st,orch.StackingPreproc.Context);
                        end
                        if ~isfield(orch.NM,'TrainParam') || ~isstruct(orch.NM.TrainParam), orch.NM.TrainParam = struct(); end
                        if ~isfield(orch.NM.TrainParam,'STACKING') || ~isstruct(orch.NM.TrainParam.STACKING), orch.NM.TrainParam.STACKING = struct(); end
                        orch.NM.TrainParam.STACKING.PREPROC = orch.StackingPreproc.toLegacyPreproc();
                        msg = 'Stacker preprocessing was synchronized to the NM.TrainParam.STACKING.PREPROC branch.';
                    else
                        if idx < 1 || idx > orch.NumModalities, error('NMTrainTemplateUI:badPreprocModule','Invalid preprocessing module index: %s',module); end
                        st = NMUIStateTools.readConfiguratorChild(tmpDir,sprintf('preproc_var%d',idx));
                        if isempty(fieldnames(st)), error('NMTrainTemplateUI:missingPreprocState','Preprocessing STATE slot is not initialized: preproc_var%d',idx); end
                        st = NMConfigTools.charifyStrings(st);
                        if childPathsSupplied
                            NMTrainTemplateUI.applyPreprocChildPaths(orch.Preproc{idx},st,childPaths);
                        else
                            orch.Preproc{idx}.applyUIState(st,orch.Preproc{idx}.Context);
                        end
                        PREPROC = orch.Preproc{idx}.toLegacyPreproc();
                        nextNM = NMTrainTemplateUI.commitLegacyPreprocToNM(orch.NM,PREPROC,idx,orch);
                        if pfeDeactivate
                            inactiveRFE = orch.RFE;
                            inactiveRFE.Filter.PFE.flag = 0;
                            inactiveRFE.Wrapper.PFE.flag = 0;
                            inactiveRFE.rfeDirty = true;
                            nextNM = NMRFETools.applyToNM(nextNM,inactiveRFE,orch.VarIndex,orch.FusionFlag);
                        end
                        orch.NM = nextNM;
                        if pfeDeactivate
                            orch.RFE = NMRFETools.stateFromNM(orch.NM,orch.VarIndex,orch.FusionFlag);
                        end
                        msg = sprintf('Preprocessing was synchronized to NM.TrainParam.PREPROC for modality #%d.',idx);
                    end
                    if isStacking
                        ppChanged = orch.StackingPreproc;
                        specPath = fullfile(tmpDir,'preproc_stacking_spec.json');
                    else
                        ppChanged = orch.Preproc{idx};
                        specPath = fullfile(tmpDir,sprintf('preproc_var%d_spec.json',idx));
                    end
                    NMTrainTemplateUI.refreshPreprocDynamicSpec(orch,ppChanged,specPath,~isStacking);
                else
                    msg = 'Preprocessing configuration was unchanged.';
                end
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyPreproc child read/apply/legacy: %.3fs\n', profileId, toc(t));

                parentChanged = ~changedPathsSupplied || ~isempty(changedPaths);
                if childChanged || parentChanged
                    orch.NM.TrainParam.ActiveModality = orch.VarIndex;
                end

                if childPathsSupplied && isempty(childPaths) && changedPathsSupplied && isempty(changedPaths)
                    out = struct('ok',true,'message',msg,'changed',false);
                    NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] applyPreprocService TOTAL: %.3fs\n', profileId, toc(tTotal));
                    return;
                end

                t = tic;
                if childChanged
                    if ~isempty(orch.Vis) && isstruct(orch.Vis), orch.Vis = NMVISTools.normalizeState(orch.NM,orch.Vis,orch.VarIndex,orch.FusionFlag); end
                    if ~isempty(orch.MLI) && isstruct(orch.MLI), orch.MLI = NMMLITools.normalizeState(orch.NM,orch.MLI,orch.VarIndex,orch.FusionFlag); end
                end
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyPreproc VIS/MLI normalize:      %.3fs\n', profileId, toc(t));

                t = tic;
                fresh = orch.menuState(struct('includeCanvas', includeCanvas, 'profile', doProfile, 'profileId', profileId));
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyPreproc menuState rebuild:     %.3fs\n', profileId, toc(t));
                if ~includeCanvas
                    fresh.canvasDirty = true;
                    fresh.canvasDirtyReason = 'Preprocessing configuration changed; canvas refresh was deferred.';
                end
                t = tic;
                fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh,tmpDir);
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyPreproc enrich/export state:   %.3fs\n', profileId, toc(t));

                t = tic;
                out = struct('ok',true,'message',msg,'state',fresh,'preprocSummary',fresh.preprocSummary,'changed',true);
                NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s]   applyPreproc result assembly:       %.3fs\n', profileId, toc(t));
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_applyPreprocService', 'applyPreprocService failed.', 2);
            end
            NMTrainTemplateUI.profileLog(doProfile, '[nm-prof rid=%s] applyPreprocService TOTAL: %.3fs\n', profileId, toc(tTotal));
        end

        function out = copyPreprocService(orch, req, tmpDir)
            % copyPreprocService  Copy preprocessing configuration between modalities according to the.
            %
            % browser request.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.sourceModality: carries the source modality value from the browser/service request payload.
            % req.state: carries the current serialized browser state for service dispatch.
            % req.targetModalities: carries the target modalities value from the browser/service request payload.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            try
                includeCanvas = NMTrainTemplateUI.requestIncludeCanvas(req);
                orch.applyMenuState(menuState);
                source = orch.VarIndex;
                if isstruct(req) && isfield(req,'sourceModality') && ~isempty(req.sourceModality)
                    source = round(double(req.sourceModality));
                end
                targets = [];
                if isstruct(req) && isfield(req,'targetModalities') && ~isempty(req.targetModalities)
                    targets = round(double(req.targetModalities(:)'));
                end
                if isempty(targets)
                    error('NMTrainTemplateUI:noCopyTargets', 'No target modalities were selected.');
                end
                if source < 1 || source > orch.NumModalities
                    error('NMTrainTemplateUI:badCopySource', 'Invalid source modality index: %g.', double(source));
                end

                % Synchronize browser preprocessing state files into the
                % orchestrator before calling the public API. Materialize only
                % branches with a live child draft plus the selected source.
                orch.materializePreprocBranch(source, false);
                for ii = 1:orch.NumModalities
                    st = NMUIStateTools.readConfiguratorChild(tmpDir,sprintf('preproc_var%d',ii));
                    if ~isempty(fieldnames(st))
                        orch.materializePreprocBranch(ii, false);
                        st = NMConfigTools.charifyStrings(st);
                        orch.Preproc{ii}.applyUIState(st,orch.Preproc{ii}.Context);
                    end
                end
                if ~isfield(orch.NM,'TrainParam') || ~isstruct(orch.NM.TrainParam), orch.NM.TrainParam = struct(); end
                if ~isfield(orch.NM.TrainParam,'PREPROC') || ~iscell(orch.NM.TrainParam.PREPROC)
                    orch.NM.TrainParam.PREPROC = cell(1, orch.NumModalities);
                end
                if numel(orch.NM.TrainParam.PREPROC) < orch.NumModalities
                    orch.NM.TrainParam.PREPROC{orch.NumModalities} = [];
                end
                orch.NM.TrainParam.PREPROC{source} = orch.Preproc{source}.toLegacyPreproc();

                [NM2, apiOut] = NMTrainTemplateAPITools.copyPreprocessingSetup(orch.NM, struct( ...
                    'sourceModality', source, ...
                    'targetModalities', targets, ...
                    'copyMode', 'replace', ...
                    'requireUnlocked', true, ...
                    'validateTargets', true));
                orch.NM = NM2;
                for kk = 1:numel(apiOut.copiedModalities)
                    tgt = apiOut.copiedModalities(kk);
                    if tgt >= 1 && tgt <= orch.NumModalities
                        orch.Preproc{tgt} = [];
                        orch.materializePreprocBranch(tgt, false);
                    end
                end
                orch.NM.TrainParam.ActiveModality = orch.VarIndex;
                fresh = orch.menuState(struct('includeCanvas', includeCanvas, 'profile', NMTrainTemplateUI.profileEnabled(req)));
                if ~includeCanvas
                    fresh.canvasDirty = true;
                    fresh.canvasDirtyReason = 'Preprocessing setup copy changed one or more modality branches; canvas refresh was deferred.';
                end
                fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh, tmpDir);
                copiedChildren = struct();
                for kk = 1:numel(apiOut.copiedModalities)
                    tgt = apiOut.copiedModalities(kk);
                    copiedChildren.(sprintf('preproc_var%d',tgt)) = orch.Preproc{tgt}.toUIState();
                end
                out = struct('ok',true,'message',apiOut.message,'state',fresh,'copyReport',apiOut, ...
                    'configuratorChildren',copiedChildren);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_copyPreprocService', 'copyPreprocService failed.', 2);
            end
        end

        function out = applySynthService(orch, req, tmpDir)
            % applySynthService  Apply synthetic-data augmentation settings to the training template.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            try
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {'synth'});
                orch.NM = NMSynthTools.applyToNM(orch.NM, orch.Synth);
                orch.Synth = NMSynthTools.stateFromNM(orch.NM);
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'synth',orch.Synth, ...
                    'Synthetic-data configuration was applied to the internal NM.TrainParam.SYNTH.', ...
                    'Synthetic-data configuration changed; canvas refresh was deferred.',true);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_applySynthService', 'applySynthService failed.', 2);
            end
        end

        function out = applyMULTIService(orch, req, tmpDir)
            % applyMULTIService  Apply multi-class configuration to the appropriate TrainParam branch.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            try
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {'multi'});
                orch.NM = NMMULTITools.applyToNM(orch.NM, orch.Multi, orch.VarIndex, orch.FusionFlag);
                orch.Multi = NMMULTITools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'multi',orch.Multi, ...
                    'Multi-class configuration was applied to the internal MULTI branch.', ...
                    'Multi-class configuration changed; canvas refresh was deferred.',true);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_applyMULTIService', 'applyMULTIService failed.', 2);
            end
        end


        function out = applyRFEService(orch, req, tmpDir)
            % applyRFEService  Apply feature-selection/RFE configuration to global or modality-specific.
            %
            % template state.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            try
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {'rfe'});
                [pfeIdx, pfeStacking] = NMTrainTemplateUI.parsePreprocModuleName( ...
                    NMTrainTemplateUI.preprocModuleNameForOrch(orch),orch.VarIndex);
                pp = orch.materializePreprocBranch(pfeIdx, pfeStacking);
                eligibility = pp.RuleSet.crossCVFeatureIdentity( ...
                    pp.Registry, pp.SubjectSequence.Steps, pp.CVSequence.Steps);
                if ~eligibility.eligible
                    orch.RFE.Filter.PFE.flag = 0;
                    orch.RFE.Wrapper.PFE.flag = 0;
                end
                orch.NM = NMRFETools.applyToNM(orch.NM, orch.RFE, orch.VarIndex, orch.FusionFlag);
                orch.RFE = NMRFETools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                orch.RFE.rfePFEEligibility = eligibility;
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'rfe',orch.RFE, ...
                    'Ensemble-learning strategies were applied to the internal RFE branch.', ...
                    'Ensemble configuration changed; canvas refresh was deferred.',true);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_applyRFEService', 'applyRFEService failed.', 2);
            end
        end


        function out = refreshRFEService(orch, req, tmpDir)
            % refreshRFEService  Refresh PreML from the materialized PREPROC branch on RFE entry.
            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            try
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {});
                orch.RFE = NMRFETools.refreshPreML(orch.NM, orch.RFE, orch.VarIndex, orch.FusionFlag);
                [pfeIdx, pfeStacking] = NMTrainTemplateUI.parsePreprocModuleName( ...
                    NMTrainTemplateUI.preprocModuleNameForOrch(orch),orch.VarIndex);
                pp = orch.materializePreprocBranch(pfeIdx, pfeStacking);
                eligibility = pp.RuleSet.crossCVFeatureIdentity( ...
                    pp.Registry, pp.SubjectSequence.Steps, pp.CVSequence.Steps);
                if ~eligibility.eligible && ...
                        (logical(orch.RFE.Filter.PFE.flag) || logical(orch.RFE.Wrapper.PFE.flag))
                    orch.RFE.Filter.PFE.flag = 0;
                    orch.RFE.Wrapper.PFE.flag = 0;
                    orch.RFE.rfeDirty = true;
                    orch.NM = NMRFETools.applyToNM(orch.NM, orch.RFE, orch.VarIndex, orch.FusionFlag);
                    orch.RFE = NMRFETools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                end
                orch.RFE.rfePFEEligibility = eligibility;
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'rfe',orch.RFE, ...
                    'Ensemble-learning configuration refreshed from the current preprocessing and ML optimization state.', ...
                    'Ensemble-learning context changed; canvas refresh was deferred.',false);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_refreshRFEService', 'refreshRFEService failed.', 2);
            end
        end


        function out = applyVISService(orch, req, tmpDir)
            % applyVISService  Apply visualization settings to NM.TrainParam.VIS through the orchestrator.
            %
            % path.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            try
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {'vis'});
                NMTrainTemplateUI.syncMLStatesFromState(orch, tmpDir);
                orch.Vis = NMVISTools.normalizeState(orch.NM, orch.Vis, orch.VarIndex, orch.FusionFlag);
                orch.NM = NMVISTools.applyToNM(orch.NM, orch.Vis, orch.VarIndex, orch.FusionFlag);
                orch.Vis = NMVISTools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'vis',orch.Vis, ...
                    'Visualization options were applied to the internal VIS branch.', ...
                    'Visualization configuration changed; canvas refresh was deferred.',true);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_applyVISService', 'applyVISService failed.', 2);
            end
        end

        function out = refreshVISService(orch, req, tmpDir)
            % refreshVISService  Refresh visualization menu state from the current NM/template context.
            %
            % without writing edits.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            try
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {});
                NMTrainTemplateUI.syncMLStatesFromState(orch, tmpDir);
                orch.Vis = NMVISTools.normalizeState(orch.NM, orch.Vis, orch.VarIndex, orch.FusionFlag);
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'vis',orch.Vis, ...
                    'Visualization options refreshed from the current ML configuration.', ...
                    'Visualization context changed; canvas refresh was deferred.',false);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_refreshVISService', 'refreshVISService failed.', 2);
            end
        end

        function out = refreshMLIService(orch, req, tmpDir)
            % refreshMLIService  Refresh ML-interpretation menu state from the current NM/template.
            %
            % context without writing edits.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            try
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {});
                orch.MLI = NMMLITools.normalizeState(orch.NM, orch.MLI, orch.VarIndex, orch.FusionFlag);
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'mli',orch.MLI, ...
                    'Interpretable ML configuration refreshed for the active modality.', ...
                    'Interpretable ML context changed; canvas refresh was deferred.',false);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_refreshMLIService', 'refreshMLIService failed.', 2);
            end
        end

        function out = applyMLIService(orch, req, tmpDir)
            % applyMLIService  Apply ML-interpretation settings, including atlas/descriptor state, to the.
            %
            % template.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            try
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {'mli'});
                orch.MLI = NMMLITools.normalizeState(orch.NM, orch.MLI, orch.VarIndex, orch.FusionFlag);
                orch.NM = NMMLITools.applyToNM(orch.NM, orch.MLI, orch.VarIndex, orch.FusionFlag);
                orch.MLI = NMMLITools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'mli',orch.MLI, ...
                    'Interpretable ML configuration was applied to the internal MLI branch.', ...
                    'Interpretable ML configuration changed; canvas refresh was deferred.',true);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_applyMLIService', 'applyMLIService failed.', 2);
            end
        end

        function out = applySAVService(orch, req, tmpDir)
            % applySAVService  Apply model-saving and verbosity settings to the training template.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            try
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {'sav','verbosity','verbosityValue'});
                orch.NM = NMSAVTools.applyToNM(orch.NM, orch.SAV);
                orch.SAV = NMSAVTools.stateFromNM(orch.NM);
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'sav',orch.SAV, ...
                    'Saving and verbosity options were applied to NM.TrainParam.SAV and NM.TrainParam.verbosity.', ...
                    'Saving/verbosity configuration changed; canvas refresh was deferred.',true);
                out.savSummary = out.sav.savSummary;
                out.verbositySummary = out.sav.verbositySummary;
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_applySAVService', 'applySAVService failed.', 2);
            end
        end

        function out = importMLIAtlasService(orch, req, tmpDir)
            % importMLIAtlasService  Import an MLI atlas file through the MATLAB service path and update.
            %
            % MLI state.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.atlasFile: carries the atlas file value from the browser/service request payload.
            % req.path: carries the path value from the browser/service request payload.
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            try
                if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                    menuState = NMConfigTools.charifyStrings(req.state);
                else
                    menuState = struct();
                end
                atlasFile = '';
                if isstruct(req) && isfield(req,'atlasFile') && ~isempty(req.atlasFile)
                    atlasFile = char(string(req.atlasFile));
                elseif isstruct(req) && isfield(req,'path') && ~isempty(req.path)
                    atlasFile = char(string(req.path));
                end
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {'mli'});
                [~, MLI] = NMMLITools.importAtlasFile(orch.NM, orch.MLI, orch.VarIndex, orch.FusionFlag, atlasFile);
                % Commit the fully materialized legacy MLI immediately. Do not
                % rebuild from the flat browser state here, because atlasvec is
                % intentionally not serialized through JSON.
                orch.NM = NMMLITools.applyLegacyToNM(orch.NM, MLI, orch.VarIndex, orch.FusionFlag);
                orch.MLI = NMMLITools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                orch.MLI.mliPresent = true;
                orch.MLI.mliDirty = true;
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'mli',orch.MLI, ...
                    orch.MLI.mliAtlasImportSummary,'Interpretable ML atlas changed; canvas refresh was deferred.',true);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_importMLIAtlasService', 'importMLIAtlasService failed.', 2);
            end
        end

        function out = previewMLIDescriptorService(orch, req, tmpDir)
            % previewMLIDescriptorService  Preview an MLI descriptor CSV before committing it to template
            % state.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            try
                [menuState, csvFile] = NMTrainTemplateUI.mliDescriptorRequestState(req);
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {'mli'});
                preview = NMMLITools.previewDescriptorFile(csvFile, NMTrainTemplateUI.flatGetField(orch.MLI,'mliCsvDelim','space'));
                orch.MLI = NMTrainTemplateUI.mergeFlatStruct(orch.MLI, preview);
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'mli',orch.MLI, ...
                    'Atlas descriptor preview updated.','Training-template context changed; canvas refresh was deferred.',false);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_previewMLIDescriptorService', 'previewMLIDescriptorService failed.', 2);
            end
        end

        function out = importMLIDescriptorService(orch, req, tmpDir)
            % importMLIDescriptorService  Import an MLI descriptor CSV and update the MLI
            % atlas/descriptor state.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            csvFile = '';
            try
                [menuState, csvFile] = NMTrainTemplateUI.mliDescriptorRequestState(req);
                keyedResponse = NMTrainTemplateUI.applyServiceMenuState(orch, menuState, req, {'mli'});
                [~, MLI] = NMMLITools.importDescriptorFile(orch.NM, orch.MLI, orch.VarIndex, orch.FusionFlag, csvFile);
                % Commit the fully materialized legacy MLI immediately. Do not
                % rebuild from the flat browser state here, because csvnum,
                % csvdesc, and the descriptor table are intentionally not
                % serialized through JSON.
                orch.NM = NMMLITools.applyLegacyToNM(orch.NM, MLI, orch.VarIndex, orch.FusionFlag);
                orch.MLI = NMMLITools.stateFromNM(orch.NM, orch.VarIndex, orch.FusionFlag);
                try
                    preview = NMMLITools.previewDescriptorFile(csvFile, NMTrainTemplateUI.flatGetField(menuState.mli,'mliCsvDelim','space'));
                    orch.MLI = NMTrainTemplateUI.mergeFlatStruct(orch.MLI, preview);
                catch
                end
                orch.MLI.mliPresent = true;
                orch.MLI.mliDirty = true;
                out = NMTrainTemplateUI.finishDomainService(orch,req,tmpDir,keyedResponse,'mli',orch.MLI, ...
                    orch.MLI.mliCsvImportSummary,'Interpretable ML descriptor changed; canvas refresh was deferred.',true);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_importMLIDescriptorService', 'importMLIDescriptorService failed.', 2);
                try
                    delim = 'space';
                    if exist('menuState','var') && isstruct(menuState) && isfield(menuState,'mli') && isstruct(menuState.mli) && isfield(menuState.mli,'mliCsvDelim')
                        delim = menuState.mli.mliCsvDelim;
                    end
                    preview = NMMLITools.previewDescriptorFile(csvFile, delim);
                    orch.MLI = NMTrainTemplateUI.mergeFlatStruct(orch.MLI, preview);
                    fresh = orch.menuState();
                    fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh, tmpDir);
                    out.mli = fresh.mli;
                    out.state = fresh;
                catch
                end
            end
        end

        function out = exportScaffoldService(orch, req, tmpDir, ctx)
            % exportScaffoldService  Export a reproducible script/scaffold for the current template
            % configuration.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if nargin < 4, ctx = struct(); end
            try
                if exist('nm_train_template_generate_scaffold_code','file') ~= 2
                    error('NMTrainTemplateUI:noScaffoldExporter', ...
                        'nm_train_template_generate_scaffold_code.m is not on the MATLAB path.');
                end
                exportRoot = NMTrainTemplateUI.reqChar(req, 'exportRoot', '');
                if isempty(exportRoot)
                    exportRoot = fullfile(pwd, 'NM_train_template_exports');
                end
                if ~exist(exportRoot,'dir'), mkdir(exportRoot); end
                stamp = datestr(now, 'yyyymmdd_HHMMSS');
                outDir = NMTrainTemplateUI.uniqueExportDir(fullfile(exportRoot, ['nm_train_template_scaffold_' stamp]));

                % Mirror the current browser JSON into the orchestrator before
                % taking the scaffold snapshot. CV build/load/save requests are
                % disabled because Patch I.1 is a preflight scaffold, not a
                % backend execution path.
                orch = NMTrainTemplateUI.importUpdated(orch, struct('tmpDir', tmpDir), ctx);
                orch.CVPartition = NMTrainTemplateUI.cvStateWithoutSideEffects(orch.CVPartition);
                NMscaffold = orch.toNM(orch.NM, ctx);
                out = nm_train_template_generate_scaffold_code(NMscaffold, outDir, ctx);
                out.exportRoot = exportRoot;
                fresh = orch.menuState();
                fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh, tmpDir);
                out.state = fresh;
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_exportScaffoldService', 'exportScaffoldService failed.', 2);
            end
        end


        function out = saveSnapshotService(orch, req, tmpDir, ctx)
            % saveSnapshotService  Save a template/orchestrator snapshot for later restoration.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if nargin < 4, ctx = struct(); end
            try
                if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                    orch.applyMenuState(NMConfigTools.charifyStrings(req.state));
                    orch.refreshActiveConfiguratorStates();
                end
                outDir = NMTrainTemplateUI.reqChar(req, 'exportRoot', '');
                outFile = NMTrainTemplateUI.reqChar(req, 'filename', '');
                if isempty(outFile)
                    if isempty(outDir), outDir = pwd; end
                    outFile = outDir;
                end
                metadata = struct('source','browser-header-save', 'tmpDir',tmpDir);
                [snapshot, savedFile] = nm_train_template_save_snapshot(orch, outFile, ctx, metadata);
                fresh = orch.menuState();
                fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh, tmpDir);
                out = struct('ok',true, 'message','Training template snapshot saved.', ...
                    'file',savedFile, 'snapshotTimestamp',snapshot.timestamp, ...
                    'auditSummary',snapshot.auditSummary, 'state',fresh);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_saveSnapshotService', 'saveSnapshotService failed.', 2);
            end
        end

        function out = loadSnapshotPreviewService(orch, req, tmpDir, ctx)
            % loadSnapshotPreviewService  Read a snapshot summary before applying it to the current
            % template.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if nargin < 4, ctx = struct(); end
            try
                snapshotFile = NMTrainTemplateUI.reqChar(req, 'filename', '');
                if isempty(snapshotFile), error('NMTrainTemplateUI:noSnapshotFile','No snapshot file was selected.'); end
                preview = nm_train_template_load_snapshot_preview(orch.NM, snapshotFile, ctx, orch.VarIndex);
                fresh = orch.menuState();
                fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh, tmpDir);
                out = struct('ok',true, 'message','Snapshot preview completed. No current TrainParam was overwritten.', ...
                    'preview',preview, 'state',fresh);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_loadSnapshotPreviewService', 'loadSnapshotPreviewService failed.', 2);
            end
        end

        function out = applySnapshotService(orch, req, tmpDir, ctx)
            % applySnapshotService  Apply a saved template snapshot to the current orchestrator/session.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.allowHardErrors: carries the allow hard errors value from the browser/service request payload.
            % req.confirmApply: carries the confirm apply value from the browser/service request payload.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if nargin < 4, ctx = struct(); end
            try
                snapshotFile = NMTrainTemplateUI.reqChar(req, 'filename', '');
                if isempty(snapshotFile), error('NMTrainTemplateUI:noSnapshotFile','No snapshot file was selected.'); end
                confirmApply = false;
                if isstruct(req) && isfield(req,'confirmApply'), confirmApply = logical(req.confirmApply); end
                options = struct();
                if isstruct(req) && isfield(req,'allowHardErrors'), options.allowHardErrors = logical(req.allowHardErrors); end
                [orch, report] = nm_train_template_apply_snapshot(orch, snapshotFile, confirmApply, ctx, options); %#ok<ASGLU>
                NMTrainTemplateUI.invalidateChildConfiguratorFiles(tmpDir);
                fresh = report.state;
                fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh, tmpDir);
                out = struct('ok',true,'message',report.message,'state',fresh, ...
                    'preview',report.preview,'auditSummary',report.auditSummary, ...
                    'resetConfiguratorChildren',true);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_applySnapshotService', 'applySnapshotService failed.', 2);
            end
        end

        function out = exportMethodsSummaryService(orch, req, tmpDir, ctx)
            % exportMethodsSummaryService  Export a methods-summary document/payload from the current.
            %
            % template state.
            %
            % Loads the current session/orchestrator context, delegates the domain operation to the
            % appropriate core tool and returns a structured ok/message/state payload for the browser.
            % This service boundary is where UI requests become template changes or read-only
            % diagnostics.
            %
            % req.state: carries the current serialized browser state for service dispatch.

            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if nargin < 4, ctx = struct(); end
            try
                if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                    orch.applyMenuState(NMConfigTools.charifyStrings(req.state));
                    orch.refreshActiveConfiguratorStates();
                end
                orch.materializeOverviewChildren(ctx);
                exportRoot = NMTrainTemplateUI.reqChar(req, 'exportRoot', '');
                if isempty(exportRoot), exportRoot = pwd; end
                [txt, outFile] = nm_train_template_export_methods_summary(orch, exportRoot, ctx); %#ok<ASGLU>
                fresh = orch.menuState();
                fresh = NMTrainTemplateUI.enrichMenuStateForExport(fresh, tmpDir);
                out = struct('ok',true, 'message','Methods/configuration summary exported.', ...
                    'file',outFile, 'state',fresh);
            catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
                out = NMUIErrorTools.exceptionStruct(ME, 'train_template_exportMethodsSummaryService', 'exportMethodsSummaryService failed.', 2);
            end
        end

        function state = cvStateWithoutSideEffects(state)
            % cvStateWithoutSideEffects  Remove transient CV fields before returning browser state.
            %
            % Strips service-only side effects from cross-validation state so the browser receives a
            % stable configuration snapshot. It does not recompute CV partitions.
            %
            % state.cvBuildRequested: carries the cv build requested value between browser/API state and legacy NeuroMiner structures.
            % state.cvLoadRequested: carries the cv load requested value between browser/API state and legacy NeuroMiner structures.
            % state.cvSaveRequested: carries the cv save requested value between browser/API state and legacy NeuroMiner structures.

            if isempty(state) || ~isstruct(state), state = struct(); end
            state.cvBuildRequested = false;
            state.cvLoadRequested = false;
            state.cvSaveRequested = false;
        end

        function outDir = uniqueExportDir(outDir)
            % uniqueExportDir  Derive a non-overwriting output directory for exports.
            %
            % Appends a numeric suffix when the requested export directory already exists. This protects
            % scaffold/snapshot output without changing the requested base path semantics.

            base = outDir;
            k = 1;
            while exist(outDir, 'dir')
                k = k + 1;
                outDir = sprintf('%s_%02d', base, k);
            end
            mkdir(outDir);
        end

        function val = reqChar(req, field, default)
            % reqChar  Read a character field from a browser request.
            %
            % Normalizes string-like request values used by template services and returns a
            % caller-supplied default when absent.

            val = default;
            if isstruct(req) && isfield(req, field) && ~isempty(req.(field))
                try
                    val = char(string(req.(field)));
                catch
                    val = default;
                end
            end
        end

        function [menuState, csvFile] = mliDescriptorRequestState(req)
            % mliDescriptorRequestState  Extract MLI descriptor state and CSV path from a request.
            %
            % Reads descriptor import/preview fields submitted by the browser and returns both the
            % updated menu state and selected CSV file. It does not parse the descriptor itself.
            %
            % req.csvFile: carries the csv file value from the browser/service request payload.
            % req.path: carries the path value from the browser/service request payload.
            % req.state: carries the current serialized browser state for service dispatch.

            if isstruct(req) && isfield(req,'state') && isstruct(req.state)
                menuState = NMConfigTools.charifyStrings(req.state);
            else
                menuState = struct();
            end
            csvFile = '';
            if isstruct(req) && isfield(req,'csvFile') && ~isempty(req.csvFile)
                csvFile = char(string(req.csvFile));
            elseif isstruct(req) && isfield(req,'path') && ~isempty(req.path)
                csvFile = char(string(req.path));
            elseif isstruct(menuState) && isfield(menuState,'mli') && isstruct(menuState.mli) && isfield(menuState.mli,'mliCsvFile')
                csvFile = char(string(menuState.mli.mliCsvFile));
            end
        end

        function v = flatGetField(s, name, default)
            % flatGetField  Read a field from a flat struct with fallback.
            %
            % Supports service request parsing where browser payloads are decoded into shallow MATLAB
            % structs. Missing or empty fields return the provided default.

            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                v = s.(name);
            else
                v = default;
            end
        end

        function out = mergeFlatStruct(base, add)
            % mergeFlatStruct  Merge two flat structs for service-state construction.
            %
            % Copies fields from an additive struct into a base struct without recursive merging. It is
            % used for compact browser payload assembly.

            out = base;
            if ~isstruct(out), out = struct(); end
            if ~isstruct(add), return; end
            f = fieldnames(add);
            for i = 1:numel(f)
                out.(f{i}) = add.(f{i});
            end
        end

        function module = preprocModuleNameForOrch(orch)
            % preprocModuleNameForOrch  Resolve the preprocessing module identifier represented by an
            % orchestrator.
            %
            % Reads module/orchestrator metadata to identify the modality or stacking preprocessing
            % branch being edited by a child page.

            if orch.isStackingEnabled()
                module = 'preproc_stacking';
                return;
            end
            idx = orch.VarIndex;
            if orch.FusionFlag == 1 && ~isempty(orch.FusionModalities)
                idx = orch.FusionModalities(1);
            end
            module = sprintf('preproc_var%d', idx);
        end

        function [idx, isStacking] = parsePreprocModuleName(module, fallbackIdx)
            % parsePreprocModuleName  Parse modality and stacking information from a preprocessing module
            % name.
            %
            % Interprets naming conventions used when exporting preprocessing child editors so returned
            % edits can be committed to the correct NM branch.

            if nargin < 2 || isempty(fallbackIdx), fallbackIdx = 1; end
            isStacking = strcmpi(strtrim(char(string(module))), 'preproc_stacking');
            idx = round(double(fallbackIdx));
            if isStacking, return; end
            tok = regexp(char(string(module)), '^preproc_var(\d+)$', 'tokens', 'once');
            if ~isempty(tok)
                idx = str2double(tok{1});
            end
            if ~isfinite(idx) || idx < 1, idx = round(double(fallbackIdx)); end
        end

        function NM = commitLegacyPreprocToNM(NM, PREPROC, idx, orch)
            % commitLegacyPreprocToNM  Commit a legacy PREPROC struct back to the correct NM template
            % branch.
            %
            % Writes child-editor preprocessing output into NM.TrainParam at the modality or stacking
            % location represented by the orchestrator. This is the service-side materialization point
            % for preprocessing edits.

            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), NM.TrainParam = struct(); end
            NM.TrainParam.FUSION.flag = orch.FusionFlag;
            NM.TrainParam.FUSION.M = orch.FusionModalities;
            NM.TrainParam.ActiveModality = orch.VarIndex;
            if orch.FusionFlag == 3
                if ~isfield(NM.TrainParam,'STRAT') || ~iscell(NM.TrainParam.STRAT)
                    NM.TrainParam.STRAT = cell(1, max(orch.NumModalities, idx));
                end
                if numel(NM.TrainParam.STRAT) < idx, NM.TrainParam.STRAT{idx} = []; end
                if isempty(NM.TrainParam.STRAT{idx}) || ~isstruct(NM.TrainParam.STRAT{idx})
                    NM.TrainParam.STRAT{idx} = struct();
                end
                NM.TrainParam.STRAT{idx}.PREPROC = PREPROC;
                return;
            end
            if ~isfield(NM.TrainParam,'PREPROC') || ~iscell(NM.TrainParam.PREPROC)
                NM.TrainParam.PREPROC = cell(1, max(orch.NumModalities, idx));
            end
            if numel(NM.TrainParam.PREPROC) < max(orch.NumModalities, idx)
                NM.TrainParam.PREPROC{max(orch.NumModalities, idx)} = [];
            end
            if orch.FusionFlag == 1
                mods = orch.FusionModalities;
                if isempty(mods), mods = idx; end
                dst = mods(1);
                if ~isfinite(dst) || dst < 1, dst = idx; end
                if numel(NM.TrainParam.PREPROC) < dst, NM.TrainParam.PREPROC{dst} = []; end
                NM.TrainParam.PREPROC{dst} = PREPROC;
            else
                NM.TrainParam.PREPROC{idx} = PREPROC;
            end
        end

        function syncMLStatesFromState(orch, tmpDir)
            % syncMLStatesFromState  Synchronize pending learner configurations
            % from the single session-wide NM2 configurator STATE.
            if nargin < 2 || isempty(tmpDir) || ~exist(tmpDir,'dir'), return; end
            state = NMUIStateTools.readConfiguratorChild(tmpDir,'ml_global');
            if ~isempty(fieldnames(state))
                orch.materializeMLBranch('ml_global', struct());
                state = NMConfigTools.charifyStrings(state);
                [state, report] = orch.MLGlobal.ML.validateConfig(state,orch.MLGlobal.context(struct()),false);
                if ~report.ok
                    error('NMTrainTemplateUI:invalidMLState','Updated global ML UI state is invalid:\n%s',strjoin(report.errors,newline));
                end
                orch.MLGlobal.MLConfig = state;
            end
            if ~isfield(orch.NM,'TrainParam') || ~isstruct(orch.NM.TrainParam), orch.NM.TrainParam = struct(); end
            orch.NM.TrainParam.FUSION.flag = orch.FusionFlag;
            orch.NM.TrainParam.FUSION.M = orch.FusionModalities;
            if orch.FusionFlag == 3
                if ~isfield(orch.NM.TrainParam,'STRAT') || ~iscell(orch.NM.TrainParam.STRAT), orch.NM.TrainParam.STRAT = cell(1,orch.NumModalities); end
                if numel(orch.NM.TrainParam.STRAT) < orch.NumModalities, orch.NM.TrainParam.STRAT{orch.NumModalities} = []; end
                for i = 1:orch.NumModalities
                    state = NMUIStateTools.readConfiguratorChild(tmpDir,sprintf('ml_var%d',i));
                    if ~isempty(fieldnames(state))
                        orch.materializeMLBranch(sprintf('ml_var%d',i), struct());
                        state = NMConfigTools.charifyStrings(state);
                        [state, report] = orch.MLStrat{i}.ML.validateConfig(state,orch.MLStrat{i}.context(struct()),false);
                        if ~report.ok
                            error('NMTrainTemplateUI:invalidMLState','Updated late-fusion STRAT{%d} ML UI state is invalid:\n%s',i,strjoin(report.errors,newline));
                        end
                        orch.MLStrat{i}.MLConfig = state;
                    end
                    orch.materializeMLBranch(sprintf('ml_var%d',i), struct());
                    if numel(orch.MLStrat) >= i && ~isempty(orch.MLStrat{i})
                        orch.MLStrat{i}.VarIndex = i;
                        orch.NM = orch.MLStrat{i}.toNM(orch.NM);
                    end
                end
            else
                orch.materializeMLBranch('ml_global', struct());
                orch.MLGlobal.VarIndex = [];
                orch.NM = orch.MLGlobal.toNM(orch.NM);
            end
        end

        function tf = isConfiguratorRecovery(ctx, tmpDir)
            tf = isstruct(ctx) && isfield(ctx,'NMAppRecoveredSession') && ...
                ~isempty(ctx.NMAppRecoveredSession) && logical(ctx.NMAppRecoveredSession);
            % A recovered browser can have been abandoned inside a preprocessing
            % child; its navigation path need not identify the parent template.
            % The app's verified recovery flag owns the retained-session identity.
        end

        function state = enrichMenuStateForExport(state, tmpDir)
            % enrichMenuStateForExport  Attach export-specific context to template menu state.
            %
            % Adds transient paths and child-page metadata needed by generated scaffolds or exported
            % summaries. The enrichment is for output generation and not a persistent NM schema change.
            %
            % state.altLabelCandidates: carries the alt label candidates value between browser/API state and legacy NeuroMiner structures.
            % state.cv: carries the cv value between browser/API state and legacy NeuroMiner structures.

            workspace = {};
            wp = fullfile(tmpDir, 'workspace.json');
            if exist(wp,'file')
                try
                    workspace = NMConfigTools.charifyStrings(NMConfigTools.readJson(wp));
                catch
                    workspace = {};
                end
            end
            state.altLabelCandidates = NMAlternativeLabelTools.workspaceCandidates(workspace);
            if isfield(state,'cv') && isstruct(state.cv)
                state.cv.cvVectorCandidates = NMCVPartitionTools.workspaceCandidates(workspace);
            end
        end

        function msg = cvServiceMessage(action, NM)
            % cvServiceMessage  Build a user-facing message for CV service actions.
            %
            % Formats cross-validation apply/reset/update outcomes using the current NM state so browser
            % feedback matches the operation just performed.

            switch lower(char(string(action)))
                case 'build'
                    if isfield(NM,'cv') && ~isempty(NM.cv)
                        msg = 'CV structure built.';
                    else
                        msg = 'No CV structure was created. Build or load a CV structure before initializing analyses.';
                    end
                case 'load'
                    msg = 'CV structure loaded.';
                case 'save'
                    msg = 'CV structure saved.';
                otherwise
                    msg = '';
            end
        end

        function spec = menuSpec(orch)
            % menuSpec  Return the template menu specification for the browser.
            %
            % Retrieves the orchestrator-controlled schema that JavaScript uses to render configuration
            % panels. It is the UI-facing contract for available template controls.

            spec = struct();
            spec.kind = 'train-template-menu';
            spec.title = 'NeuroMiner parameter template';
            spec.numModalities = orch.NumModalities;
            spec.modalityLabels = {orch.ModalityLabels{:}};
            spec.stackingAvailable = orch.StackingAvailable;
            spec.alternativeLabelAvailable = true;
            spec.crossValidationAvailable = true;
        end

        function copyRendererAssets(webDir)
            % copyRendererAssets  Copy training-template renderer assets to the web directory.
            %
            % Copies JavaScript, CSS, icons, plotting and navigation assets required by the template
            % configurator. It performs packaging only and does not alter configuration.

            srcDir = fileparts(mfilename('fullpath'));
            assets = {'NMExpressionTools.js','NMPreprocUI_main.js','NMPreprocUI.css','NMSequenceBuilder.js','NMSequenceBuilder.css','NMTrainTemplateUI_main.js','NMTrainTemplateUI.css','NMConfigAuditRefresh.png','NMContextHelp.js','NMTrainTemplateRFEUI.js','RFE_Context_Help.html','CV_Context_Help.html','Stacking_Context_Help.html','Alternative_Label_Context_Help.html','Synth_Context_Help.html','MLI_Context_Help.html','VIS_Context_Help.html','NMTrainTemplateVISUI.js','NMTrainTemplateMULTIUI.js','NMTrainTemplateMLIUI.js','NMTrainTemplateSAVUI.js','NMModuleIconSet.js','NMModuleNavigationRail.js','NMModuleNavigationRail.css','NMModal.js','NMModal.css','NMRuntimeProgressViewer.js','NMRuntimeProgressViewer.css'};
            for i = 1:numel(assets)
                src = fullfile(srcDir, assets{i});
                if exist(src,'file') == 2
                    copyfile(src, fullfile(webDir, assets{i}), 'f');
                end
            end
        end

        function txt = htmlText(state)
            % htmlText  Build the training-template HTML shell from in-memory state.
            %
            % Serializes the initial state and delegates to htmlTextFromJson so callers can write a
            % complete browser page without prewriting JSON files.

            if nargin < 1 || isempty(state), state = struct(); end
            txt = NMTrainTemplateUI.htmlTextFromJson(NMConfigTools.encodeJson(state, 'menu html state'));
        end

        function txt = htmlTextFromJson(stateJson)
            % htmlTextFromJson  Build the training-template HTML shell from a state JSON reference.
            %
            % Creates the static document that loads the renderer, navigation rail, dashboard/canvas
            % assets and service bridge. The page receives configuration through JSON and subsequent
            % service calls.

            jsState = NMPreprocUI.jsonTextForScript(stateJson);
            nl = newline;
            L = { ...
'<!doctype html>'
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
'<title>NeuroMiner parameter template</title>'
'<link rel="stylesheet" href="NMModuleNavigationRail.css">'
'<link rel="stylesheet" href="NMTrainTemplateUI.css">'
['<style>' NMUIMessageTools.css() '</style>']
'</head><body class="nmHasNavRail">'
'<header><div><div class="crumb" id="crumb">Define parameter template</div><div class="title">NeuroMiner parameter template</div></div><div class="headerActions"><button id="saveTrainTemplate" type="button">Save training template</button><button id="loadTrainTemplate" type="button">Load training template</button><button id="toggleCanvasView" type="button">Canvas view</button><button id="exportTrainScaffold" type="button">Export MATLAB scaffold</button><button id="finish" class="primary">Finish / close</button></div></header>'
'<div id="menuView" class="wrap"><section class="panel"><h1>Main NM parameter-template menu</h1><div class="grid"><div class="card"><h2>Analysis context</h2><div class="field okField" id="auditField"><div class="inlineActions auditHeading"><label>Configuration audit</label><button id="refreshAudit" type="button" title="Refresh configuration audit" aria-label="Refresh configuration audit"><img src="NMConfigAuditRefresh.png" alt="" width="20" height="20" aria-hidden="true"></button></div><div class="summary" id="auditSummary">No audit status available.</div></div><div class="field hidden" id="stackingField"><label>Meta-learning / stacking</label><div class="summary" id="stackingSummary">Stacking unavailable.</div><div class="muted">Stacking is visible only when at least two completed analyses share the same CV setup.</div></div><div id="fusionBlock"><div class="field"><label for="fusionFlag">Fusion strategy</label><select id="fusionFlag"></select><div class="muted" id="routingInfo">The fusion strategy controls whether NeuroMiner trains one model from the selected data or combines information across modalities. For late fusion, select the modality you want to configure before opening preprocessing or machine-learning settings.</div></div><div class="field hidden" id="fusionModalitiesField"><label>Modalities included in fusion</label><button id="chooseFusionModalities" type="button">Choose modalities...</button><div id="fusionSummary" class="summary"></div></div><div class="field" id="activeModalityField"><label for="activeModality">Active modality for configuration</label><select id="activeModality"></select><button id="copyPreprocSetup" type="button" class="copyPreprocButton">Copy preprocessing setup to other modalities...</button><div class="muted" id="copyPreprocHint">Copies only preprocessing; learner, CV, data and labels are unchanged.</div></div></div><div class="status" id="fusionInfo"></div><div class="field" id="altLabelField"><label>Alternative label</label><div class="summary" id="altLabelSummary">Default NM.label is used.</div></div><div class="field hidden" id="multiLabelField"><label>Multi-label target selection</label><button id="chooseMultiLabels" type="button">Choose labels...</button><div class="summary" id="multiLabelSummary"></div></div><div class="field" id="cvField"><label>Cross-validation</label><div class="summary" id="cvSummary">Default cross-validation settings.</div></div><div class="field" id="synthField"><label>Synthetic data generation</label><div class="summary" id="synthSummary">Synthetic data generation disabled.</div></div><div class="field" id="preprocField"><label>Preprocessing pipeline</label><div class="summary" id="preprocSummary">No preprocessing status available.</div></div><div class="field" id="mlField"><label>Machine learning</label><div class="summary" id="mlSummary">Machine-learning defaults.</div></div><div class="field hidden" id="multiField"><label>Multi-class configuration</label><div class="summary" id="multiSummary">Multi-class configuration unavailable.</div></div><div class="field" id="rfeField"><label>Ensemble learning strategies</label><div class="summary" id="rfeSummary">Filter- and wrapper-based ensemble learning disabled.</div></div><div class="field" id="visField"><label>Visualization options</label><div class="summary" id="visSummary">Visualization defaults.</div></div><div class="field" id="mliField"><label>Interpretable machine learning</label><div class="summary" id="mliSummary">Interpretable ML parameters are not configured.</div></div></div><div class="card"><h2>Configurators</h2><div class="actions"><button id="openStackingConfig" class="primary hidden" type="button">Open stacking configuration</button><button id="openAltLabelConfig" class="primary" type="button">Open alternative-label configuration</button><button id="openCVConfig" class="primary" type="button">Open cross-validation configuration</button><button id="openSynthConfig" class="primary" type="button">Open synthetic-data configuration</button><button id="openPreproc" class="primary">Open preprocessing pipeline</button><button id="openML" class="primary">Open machine-learning configuration</button><button id="openMULTIConfig" class="primary hidden" type="button">Open multi-class configuration</button><button id="openRFEConfig" class="primary" type="button">Open ensemble learning configuration</button><button id="openVISConfig" class="primary" type="button">Open visualization configuration</button><button id="openMLIConfig" class="primary" type="button">Open interpretable ML configuration</button></div></div></div></section></div>'
'<div id="canvasView" class="canvasView hidden"><div class="appMenuStrip" id="canvasMenuStrip"><button class="analysisBtn primary" type="button" data-open="openStackingConfig" title="Configure stacking of predictions from completed analyses">Stacking</button><button class="analysisBtn primary" type="button" data-open="openAltLabelConfig" title="Configure an alternative target label for training">Alt label</button><button class="analysisBtn hidden" type="button" data-open="chooseMultiLabels" title="Select the labels used for multi-label training" data-requires="multiLabelAvailable">Labels</button><button class="analysisBtn primary" type="button" data-open="openCVConfig" title="Configure cross-validation partitions and folds">CV</button><button class="analysisBtn primary" type="button" data-open="openSynthConfig" title="Configure synthetic training-data generation">Synthetic</button><button class="analysisBtn primary" type="button" data-open="openPreproc" title="Configure the preprocessing pipeline">Preprocessing</button><button class="analysisBtn primary" type="button" data-open="openML" title="Configure machine-learning algorithms and hyperparameters">ML</button><button class="analysisBtn hidden" id="canvasOpenMULTIConfig" type="button" data-open="openMULTIConfig" title="Configure multiclass decision strategies" data-requires="multiAvailable">MULTI</button><button class="analysisBtn primary" type="button" data-open="openRFEConfig" title="Configure ensemble learning strategies">Ensemble</button><button class="analysisBtn primary" type="button" data-open="openVISConfig" title="Configure model visualization and permutation testing">VIS</button><button class="analysisBtn primary" type="button" data-open="openMLIConfig" title="Configure interpretable machine-learning analyses">MLI</button><button class="analysisBtn primary" type="button" data-open="openSAVConfig" title="Configure model-saving settings and the output prefix">Saving</button><button class="utilityBtn" type="button" id="toggleCanvasOrientation" title="Switch between horizontal and vertical flow layouts">Flow: horizontal</button><button class="utilityBtn" type="button" id="loadCanvasDetailsAll" title="Load rich details for all visible canvas cards">ⓘ all</button><button class="utilityBtn" type="button" id="exportCanvasSVG" title="Export the Canvas flowchart as an SVG vector image">Export SVG</button><button class="utilityBtn" type="button" id="exportMethodsSummary" title="Export a summary of the configured analysis methods">Export methods summary</button></div><div class="canvasLayout"><main id="flowCanvas" class="flowCanvas"></main><aside id="canvasDetails" class="canvasDetails"><button id="canvasInspectorCollapse" class="canvasInspectorToggle" type="button" title="Collapse info panel" aria-label="Collapse info panel">›</button><div id="canvasDetailsContent"><h2>Canvas details</h2><div>Select a node to inspect summaries and audit messages. Double-click a node to open the corresponding configurator.</div></div></aside><button id="canvasInspectorExpand" class="canvasInspectorFloatingToggle hidden" type="button" title="Expand info panel" aria-label="Expand info panel">i</button><div id="canvasNodeInfo" class="canvasNodeInfo hidden" role="dialog" aria-label="Canvas node details"></div></div></div>'
'<div id="canvasModalityDiagnosticsModal" class="modal hidden" aria-hidden="true"><div class="modalBox canvasModalityDiagBox"><div class="modalHead"><div><b id="canvasModalityDiagTitle">Modality diagnostics</b><div id="canvasModalityDiagSubtitle" class="path">Committed modality inspection</div></div><button id="closeCanvasModalityDiagnosticsModal" type="button">Return to canvas</button></div><div id="canvasModalityDiagBody" class="canvasModalityDiagBody"></div></div></div>'
'<div class="selectorModal" id="rfeConfigModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Ensemble learning strategies</b><div class="muted">Choose filter, wrapper, and CV2 ensemble-prediction settings.</div></div><button id="closeRFEConfig" type="button">Close</button></div>'
'<div class="selectorBody"><div class="rfeLayout"><div class="rfeSide"><button class="rfeTab active" data-tab="overview" type="button">Overview</button><button class="rfeTab" data-tab="filter" type="button">Filter strategy</button><button class="rfeTab" data-tab="wrapper" type="button">Wrapper strategy</button><button class="rfeTab" data-tab="pfe" type="button">Feature stability (CV1)</button><div id="rfePFEUnavailableMessage" class="muted hidden" style="font-size:12px;padding:4px 9px"></div><button class="rfeTab" data-tab="cv2" type="button">CV2 / ensemble prediction</button></div><div><div class="rfePane" id="rfePane_overview"><h2>Overview</h2><div class="field"><label><input id="rfeFilterEnabled" type="checkbox"> Use filter-based ensemble generation</label></div><div class="field"><label><input id="rfeWrapperEnabled" type="checkbox"> Use wrapper-based ensemble generation</label></div><div class="field" id="rfeRetrainImmediateField"><label><input id="rfeRetrainImmediate" type="checkbox"> Skip CV1 cycle and train on the full CV1 training/test data</label><div class="muted">Visible only when no filter/wrapper step is active and no hyperparameter optimization is required.</div></div></div><div class="rfePane hidden" id="rfePane_filter"><h2>Filter strategy</h2><div id="rfeFilterOptions"><div class="rfeMini"><h3>General filter settings</h3><div class="twocol"><div class="field"><label for="rfeFilterMinNum">Minimum number of features</label><input id="rfeFilterMinNum" class="textInput" type="number" step="1" min="1"></div><div class="field" id="rfeFilterMetricField"><label for="rfeFilterMetric">Decision source for ensemble construction</label><select id="rfeFilterMetric"><option value="1">Predicted labels / hard decisions</option><option value="2">Algorithm scores / soft decisions</option></select></div></div><div class="field" id="rfeFilterBinmodeField"><label for="rfeFilterBinmode">Multiclass ranking mode</label><select id="rfeFilterBinmode"><option value="1">Binary / pairwise</option><option value="0">Multi-group</option></select></div><div class="field"><label><input id="rfeFilterSubspace" type="checkbox"> Evaluate feature subspaces instead of applying a fixed rank threshold</label></div></div><div class="rfeMini"><h3>Filter method</h3><div class="field"><label for="rfeFilterType">Filter method</label><select id="rfeFilterType"></select></div></div><div class="rfeMini"><h3>Method-specific settings</h3><div id="rfeFilterMethodPearson" class="rfeMethodBlock"><div class="field"><label for="rfeFilterPearson">Correlation type</label><select id="rfeFilterPearson"><option value="1">Pearson</option><option value="2">Spearman</option></select></div></div><div id="rfeFilterMethodFEAST" class="rfeMethodBlock hidden"><div class="twocol"><div class="field"><label for="rfeFEASTMethod">FEAST method</label><select id="rfeFEASTMethod"><option value="1">MIM</option><option value="2">MRMR</option><option value="3">CMIM</option><option value="4">JMI</option><option value="5">DISR</option><option value="6">CIFE</option><option value="7">ICAP</option><option value="8">CondRed</option><option value="9">CMI</option><option value="10">MIFS</option></select></div><div class="field"><label for="rfeFEASTNumFeat">Number/range of features</label><input id="rfeFEASTNumFeat" class="textInput" type="text" placeholder="e.g. 10 20 30"></div></div></div><div id="rfeFilterMethodMRMR" class="rfeMethodBlock hidden"><div class="twocol"><div class="field"><label for="rfeMRMRScheme">MRMR scheme</label><select id="rfeMRMRScheme"><option value="1">MID</option><option value="2">MIQ</option></select></div><div class="field"><label for="rfeMRMRNumFeat">Number/range of features</label><input id="rfeMRMRNumFeat" class="textInput" type="text" placeholder="e.g. 10 20 30"></div></div></div><div id="rfeFilterMethodSimba" class="rfeMethodBlock hidden"><div class="twocol"><div class="field"><label for="rfeSimbaStart">Starting points</label><input id="rfeSimbaStart" class="textInput" type="number" step="1" min="1"></div><div class="field"><label for="rfeSimbaMaxIter">Maximum iterations</label><input id="rfeSimbaMaxIter" class="textInput" type="number" step="1" min="1"></div></div><div class="twocol"><div class="field"><label for="rfeSimbaAbort">Stability stopping criterion [%]</label><input id="rfeSimbaAbort" class="textInput" type="number" step="1"></div><div class="field"><label for="rfeSimbaBlock">Block size</label><input id="rfeSimbaBlock" class="textInput" type="number" step="1" min="1"></div></div><div class="twocol"><div class="field"><label for="rfeSimbaUtility">Utility function</label><select id="rfeSimbaUtility"><option value="1">Linear</option><option value="2">Sigmoid</option></select></div><div class="field"><label for="rfeSimbaBeta">Beta</label><input id="rfeSimbaBeta" class="textInput" type="text" placeholder="auto or numeric range"></div></div></div><div id="rfeFilterMethodGflip" class="rfeMethodBlock hidden"><div class="twocol"><div class="field"><label for="rfeGflipStart">Starting points</label><input id="rfeGflipStart" class="textInput" type="number" step="1" min="1"></div><div class="field"><label for="rfeGflipMaxIter">Maximum iterations</label><input id="rfeGflipMaxIter" class="textInput" type="number" step="1" min="1"></div></div><div class="twocol"><div class="field"><label for="rfeGflipBlock">Block size</label><input id="rfeGflipBlock" class="textInput" type="number" step="1" min="1"></div><div class="field"><label for="rfeGflipUtility">Utility function</label><select id="rfeGflipUtility"><option value="1">Zero-one</option><option value="2">Linear</option><option value="3">Sigmoid</option></select></div></div><div class="twocol"><div class="field"><label for="rfeGflipBeta">Beta</label><input id="rfeGflipBeta" class="textInput" type="text" placeholder="auto or numeric range"></div><div class="field"><label><input id="rfeGflipLimFeat" type="checkbox"> Limit subsequent feature subspaces to Gflip-selected features</label></div></div></div><div id="rfeFilterMethodIMRelief" class="rfeMethodBlock hidden"><div class="twocol"><div class="field"><label for="rfeIMReliefDistance">Distance</label><select id="rfeIMReliefDistance"><option value="block">Block distance</option><option value="euclidean">Euclidean distance</option></select></div><div class="field"><label for="rfeIMReliefMaxiter">Maximum iterations</label><input id="rfeIMReliefMaxiter" class="textInput" type="number" step="1" min="1"></div></div><div class="twocol"><div class="field"><label for="rfeIMReliefSigma">Sigma range</label><input id="rfeIMReliefSigma" class="textInput" type="text"></div><div class="field"><label for="rfeIMReliefLambda">Lambda range</label><input id="rfeIMReliefLambda" class="textInput" type="text"></div></div><div class="field"><label><input id="rfeIMReliefPlot" type="checkbox"> Plot IMRelief learning process</label></div></div><div id="rfeFilterMethodRGS" class="rfeMethodBlock hidden"><div class="twocol"><div class="field"><label for="rfeRGSStarts">Starting points</label><input id="rfeRGSStarts" class="textInput" type="number" step="1" min="1"></div><div class="field"><label for="rfeRGSEpochs">Epochs</label><input id="rfeRGSEpochs" class="textInput" type="number" step="1" min="1"></div></div><div class="twocol"><div class="field"><label for="rfeRGSK">k range (blank = automatic)</label><input id="rfeRGSK" class="textInput" type="text"></div><div class="field"><label for="rfeRGSBeta">Beta range (blank = automatic)</label><input id="rfeRGSBeta" class="textInput" type="text"></div></div><div class="field"><label><input id="rfeRGSVerbose" type="checkbox"> Verbose output</label></div></div><div id="rfeFilterMethodRSS" class="rfeMethodBlock hidden"><div class="twocol"><div class="field"><label for="rfeRSSPerms">Permutations</label><input id="rfeRSSPerms" class="textInput" type="number" step="1" min="1"></div><div class="field"><label for="rfeRSSMin">Minimum feature percentage</label><input id="rfeRSSMin" class="textInput" type="number" step="1"></div></div><div class="field"><label for="rfeRSSMax">Maximum feature percentage</label><input id="rfeRSSMax" class="textInput" type="number" step="1"></div></div><div id="rfeFilterMethodRelief" class="rfeMethodBlock hidden"><div class="field"><label for="rfeReliefK">Nearest neighbours k</label><input id="rfeReliefK" class="textInput" type="number" step="1" min="1"></div></div><div id="rfeFilterMethodNone" class="rfeMethodBlock hidden"><div class="muted">No additional method-specific settings.</div></div></div><div id="rfeFilterSubspaceBlock" class="rfeMini"><h3>Subspace evaluation</h3><div class="twocol"><div class="field"><label for="rfeFilterCostFun">Target population / cost function</label><select id="rfeFilterCostFun"><option value="1">CV1 training criterion</option><option value="2">CV1 test criterion</option><option value="3">CV1 training + test criterion</option></select></div><div class="field"><label for="rfeFilterSubSpaceStrategy">Subspace selection strategy</label><select id="rfeFilterSubSpaceStrategy"><option value="1">Winner takes all</option><option value="2">Within range of optimum</option><option value="3">Percentile cutoff</option><option value="4">All subspaces</option></select></div></div><div class="twocol"><div class="field"><label for="rfeFilterSubSpaceCrit">Subspace range / percentile</label><input id="rfeFilterSubSpaceCrit" class="textInput" type="number" step="0.1"></div><div class="field"><label for="rfeFilterSubSpaceStepping">Subspace stepping</label><input id="rfeFilterSubSpaceStepping" class="textInput" type="number" step="0.1" min="0"></div></div><div class="twocol"><div class="field"><label for="rfeFilterEnsConstructMode">Subspace ensemble construction</label><select id="rfeFilterEnsConstructMode"><option value="0">Aggregate / winner strategy</option><option value="1">Backward elimination</option><option value="2">Forward selection</option><option value="4">Probabilistic feature construction</option><option value="5">Boosting</option></select></div><div class="field"><label for="rfeFilterEnsMinNum">Minimum selected classifiers/features</label><input id="rfeFilterEnsMinNum" class="textInput" type="number" step="1" min="1"></div></div><div class="field"><label for="rfeFilterEnsPerc">Agreement percentage for probabilistic feature construction</label><input id="rfeFilterEnsPerc" class="textInput" type="number" step="1" min="0" max="100"></div><div id="rfeFilterBoostBlock" class="rfeMini hidden"><h3>Boosting configuration</h3><div class="twocol"><div class="field" id="rfeFilterBoostClassModeField"><label for="rfeFilterBoostMode">Boosting mode</label><select id="rfeFilterBoostMode"><option value="ridge">Ridge / MSE stacking</option><option value="logloss">Log-loss / cross-entropy</option><option value="expgrad">Exponentiated-gradient weighting</option></select></div><div class="field"><label for="rfeFilterBoostLambda">Lambda / L2 penalty</label><input id="rfeFilterBoostLambda" class="textInput" type="number" step="0.0001" min="0"></div></div><div class="twocol"><div class="field"><label for="rfeFilterBoostAlpha">Diversity weight alpha</label><input id="rfeFilterBoostAlpha" class="textInput" type="number" step="0.001" min="0"></div><div class="field"><label for="rfeFilterBoostWThreshold">Low-weight threshold</label><input id="rfeFilterBoostWThreshold" class="textInput" type="number" step="0.001" min="0"></div></div><div class="twocol"><div class="field" id="rfeFilterBoostUseLogitsField"><label><input id="rfeFilterBoostUseLogits" type="checkbox"> Use logits for score transformation</label></div><div class="field" id="rfeFilterBoostClipField"><label for="rfeFilterBoostClip">Probability clipping for log-loss</label><input id="rfeFilterBoostClip" class="textInput" type="number" step="0.0000001" min="0" max="0.5"></div></div><div id="rfeFilterBoostExpgradBlock"><div class="twocol"><div class="field"><label for="rfeFilterBoostEta">Exponentiated-gradient eta</label><input id="rfeFilterBoostEta" class="textInput" type="number" step="0.001" min="0"></div><div class="field"><label for="rfeFilterBoostT">Exponentiated-gradient iterations</label><input id="rfeFilterBoostT" class="textInput" type="number" step="1" min="1"></div></div><div class="field"><label><input id="rfeFilterBoostShareWeights" type="checkbox"> Share weights across dichotomizers/classes</label></div></div><div class="field" id="rfeFilterBoostDivSourceField"><label for="rfeFilterBoostDiversitySource">Boosting diversity metric</label><select id="rfeFilterBoostDiversitySource"><option value="entropy">Vote entropy</option><option value="kappaa">1 - double-fault A</option><option value="kappaq">-Q statistic</option><option value="kappaf">1 - Fleiss kappa / 2</option><option value="lobag">-LoBag ED</option></select></div><div id="rfeFilterBoostRegKernelBlock"><div class="twocol"><div class="field"><label for="rfeFilterBoostKernelRegMode">Regression diversity kernel</label><select id="rfeFilterBoostKernelRegMode"><option value="residual-cov">Residual covariance</option><option value="residual-corr">Residual correlation</option><option value="residual-lapl">Residual Laplacian</option></select></div><div class="field"><label for="rfeFilterBoostKernelDiagMode">Kernel diagonal</label><select id="rfeFilterBoostKernelDiagMode"><option value="one">One</option><option value="zero">Zero</option><option value="keep">Keep</option></select></div></div><div class="twocol"><div class="field"><label for="rfeFilterBoostKernelScaleTo">Kernel scaling</label><select id="rfeFilterBoostKernelScaleTo"><option value="HHT">Match HHT norm</option><option value="unit">Unit norm</option></select></div><div class="field"><label for="rfeFilterBoostKernelTau">Auto-alpha tau</label><input id="rfeFilterBoostKernelTau" class="textInput" type="number" step="0.01" min="0" max="0.5"></div></div><div class="field"><label><input id="rfeFilterBoostKernelAutoAlpha" type="checkbox"> Use auto-alpha for regression diversity kernel</label></div></div></div></div><div id="rfeFilterRankModeBlock" class="rfeMini"><h3>Rank-threshold mode</h3><div class="field"><label for="rfeFilterRankThresh">Percentile cut-off threshold</label><input id="rfeFilterRankThresh" class="textInput" type="number" step="1" min="0" max="100"></div></div></div></div><div class="rfePane hidden" id="rfePane_wrapper"><h2>Wrapper strategy</h2><div id="rfeWrapperOptions"><div class="twocol"><div class="field"><label for="rfeWrapperType">Wrapper algorithm</label><select id="rfeWrapperType"><option value="1">Greedy feature selection</option><option value="2">Simulated annealing</option><option value="3">Genetic algorithm</option><option value="4">Particle swarm optimization</option><option value="5">Path finder algorithm</option></select></div><div class="field"><label for="rfeWrapperDatamode">CV1 data partitions for optimization</label><select id="rfeWrapperDatamode"><option value="1">CV1 training data</option><option value="2">CV1 test data</option><option value="3">CV1 full partition</option><option value="4">CV1 training + test data</option></select></div></div><div class="field" id="rfeWrapperOptField"><label for="rfeWrapperOptflag">Parameter-optimization handling</label><select id="rfeWrapperOptflag"><option value="1">Learn wrapper only at parameter optimum</option><option value="2">Learn wrapper across optimization grid</option></select></div><div id="rfeWrapperSubspaceBlock" class="rfeMini"><h3>Wrapper evaluation within filter-derived subspaces</h3><div class="field"><label><input id="rfeWrapperSubspace" type="checkbox"> Evaluate features within pre-defined filter subspaces</label></div><div class="twocol"><div class="field"><label for="rfeWrapperSubSpaceStepping">Subspace stepping</label><input id="rfeWrapperSubSpaceStepping" class="textInput" type="number" step="0.1" min="0"></div><div class="field"><label for="rfeWrapperEnsConstructMode">Ensemble construction</label><select id="rfeWrapperEnsConstructMode"><option value="0">Aggregate / winner strategy</option><option value="1">Backward elimination</option><option value="2">Forward selection</option><option value="4">Probabilistic feature construction</option><option value="5">Boosting</option></select></div></div></div><div id="rfeWrapperMethodGreedy" class="rfeMini"><h3>Greedy search</h3><div class="twocol"><div class="field"><label for="rfeGreedyDirection">Direction</label><select id="rfeGreedyDirection"><option value="1">Forward</option><option value="2">Backward</option></select></div><div class="field"><label for="rfeGreedyWeightSort">Feature sorting criterion</label><select id="rfeGreedyWeightSort"><option value="1">Prediction performance</option><option value="2">Linear weights / Guyon</option></select></div></div><div class="twocol"><div class="field"><label for="rfeGreedyEarlyThresh">Early stopping threshold</label><input id="rfeGreedyEarlyThresh" class="textInput" type="number" step="0.1"></div><div class="field"><label for="rfeGreedyEarlyPerc">Early stopping mode</label><select id="rfeGreedyEarlyPerc"><option value="1">Percentage</option><option value="0">Absolute number of features</option></select></div></div><div class="twocol"><div class="field"><label for="rfeGreedyFeatStep">Feature stepping [%]</label><input id="rfeGreedyFeatStep" class="textInput" type="number" step="0.1" min="0"></div><div class="field"><label for="rfeGreedyFeatRand">Random block percentage</label><input id="rfeGreedyFeatRand" class="textInput" type="number" step="0.1" min="0"></div></div><div class="field"><label for="rfeGreedyKnee">Kneepoint detection</label><select id="rfeGreedyKnee"><option value="1">Enabled</option><option value="2">Disabled</option></select></div><div id="rfeGreedyCritGapBlock"><div class="field"><label><input id="rfeGreedyCritGapFlag" type="checkbox"> Critical-gap based early stopping</label></div><div class="field" id="rfeGreedyCritGapCritField"><label for="rfeGreedyCritGapCrit">Critical gap [%]</label><input id="rfeGreedyCritGapCrit" class="textInput" type="number" step="1"></div></div><div id="rfeAdaptiveBlock" class="rfeMini"><h3>Adaptive wrapper</h3><div class="field"><label><input id="rfeAdEnable" type="checkbox"> Enable adaptive wrapper</label><div class="muted">Visible when ordinary early stopping is disabled by setting the early-stop threshold to 0.</div></div><div id="rfeAdOptions"><div class="field"><label><input id="rfeAdAuto" type="checkbox"> Auto mode</label></div><div class="twocol"><div class="field"><label for="rfeAdLambda">Lambda</label><input id="rfeAdLambda" class="textInput" type="number" step="0.001"></div><div class="field"><label for="rfeAdKNN">kNN neighbours</label><input id="rfeAdKNN" class="textInput" type="number" step="1" min="1"></div></div><div class="twocol"><div class="field"><label for="rfeAdGamma">Gamma</label><input id="rfeAdGamma" class="textInput" type="number" step="0.001"></div><div class="field"><label for="rfeAdRmax">rmax</label><input id="rfeAdRmax" class="textInput" type="number" step="0.1"></div></div><div class="twocol"><div class="field"><label for="rfeAdEta0">eta0</label><input id="rfeAdEta0" class="textInput" type="number" step="0.0001"></div><div class="field"><label for="rfeAdEta1">eta1</label><input id="rfeAdEta1" class="textInput" type="number" step="0.0001"></div></div><div class="twocol"><div class="field"><label for="rfeAdC">φ center c</label><input id="rfeAdC" class="textInput" type="number" step="0.01"></div><div class="field"><label for="rfeAdW">φ half-width w</label><input id="rfeAdW" class="textInput" type="number" step="0.01"></div></div><div class="twocol"><div class="field"><label for="rfeAdBetaWell">β well</label><input id="rfeAdBetaWell" class="textInput" type="number" step="0.01"></div><div class="field"><label for="rfeAdBetaHi">β high</label><input id="rfeAdBetaHi" class="textInput" type="number" step="0.01"></div></div><div class="twocol"><div class="field"><label for="rfeAdSigmaLo">σ low</label><input id="rfeAdSigmaLo" class="textInput" type="number" step="0.001"></div><div class="field"><label for="rfeAdSigmaHi">σ high</label><input id="rfeAdSigmaHi" class="textInput" type="number" step="0.001"></div></div><canvas id="rfeAdaptiveCanvas" class="rfePlot" width="560" height="220"></canvas></div></div></div><div id="rfeWrapperMethodSA" class="rfeMini hidden"><h3>Simulated annealing</h3><div class="twocol"><div class="field"><label for="rfeSAc">c</label><input id="rfeSAc" class="textInput" type="number" step="0.01"></div><div class="field"><label for="rfeSAT">T</label><input id="rfeSAT" class="textInput" type="number" step="0.01"></div></div><div class="twocol"><div class="field"><label for="rfeSAT_stop">T_stop</label><input id="rfeSAT_stop" class="textInput" type="number" step="0.000001"></div><div class="field"><label for="rfeSAalpha">alpha</label><input id="rfeSAalpha" class="textInput" type="number" step="0.01"></div></div><div class="twocol"><div class="field"><label for="rfeSAitt_max">Maximum iterations</label><input id="rfeSAitt_max" class="textInput" type="number" step="1"></div><div class="field"><label for="rfeSAkc">kc</label><input id="rfeSAkc" class="textInput" type="number" step="0.1"></div></div><div class="twocol"><div class="field"><label for="rfeSARep_T_max">Rep_T_max</label><input id="rfeSARep_T_max" class="textInput" type="number" step="1"></div><div class="field"><label for="rfeSARep_accept_max">Rep_accept_max</label><input id="rfeSARep_accept_max" class="textInput" type="number" step="1"></div></div></div><div id="rfeWrapperMethodGA" class="rfeMini hidden"><h3>Genetic algorithm</h3><div class="twocol"><div class="field"><label for="rfeGAN">Population size N</label><input id="rfeGAN" class="textInput" type="number" step="1"></div><div class="field"><label for="rfeGAmax_Iter">Maximum iterations</label><input id="rfeGAmax_Iter" class="textInput" type="number" step="1"></div></div><div class="twocol"><div class="field"><label for="rfeGACR">Crossover rate</label><input id="rfeGACR" class="textInput" type="number" step="0.01"></div><div class="field"><label for="rfeGAMR">Mutation rate</label><input id="rfeGAMR" class="textInput" type="number" step="0.01"></div></div></div><div id="rfeWrapperMethodPSO" class="rfeMini hidden"><h3>Particle swarm optimization</h3><div class="twocol"><div class="field"><label for="rfePSON">Swarm size N</label><input id="rfePSON" class="textInput" type="number" step="1"></div><div class="field"><label for="rfePSOmax_Iter">Maximum iterations</label><input id="rfePSOmax_Iter" class="textInput" type="number" step="1"></div></div><div class="twocol"><div class="field"><label for="rfePSOc1">c1</label><input id="rfePSOc1" class="textInput" type="number" step="0.01"></div><div class="field"><label for="rfePSOc2">c2</label><input id="rfePSOc2" class="textInput" type="number" step="0.01"></div></div><div class="twocol"><div class="field"><label for="rfePSOw">w</label><input id="rfePSOw" class="textInput" type="number" step="0.01"></div><div class="field"><label for="rfePSOthres">Threshold</label><input id="rfePSOthres" class="textInput" type="number" step="0.01"></div></div><div class="twocol"><div class="field"><label for="rfePSOlb">Lower bound</label><input id="rfePSOlb" class="textInput" type="number" step="0.01"></div><div class="field"><label for="rfePSOub">Upper bound</label><input id="rfePSOub" class="textInput" type="number" step="0.01"></div></div></div><div id="rfeWrapperMethodPFA" class="rfeMini hidden"><h3>Path finder algorithm</h3><div class="twocol"><div class="field"><label for="rfePFAN">Population size N</label><input id="rfePFAN" class="textInput" type="number" step="1"></div><div class="field"><label for="rfePFAmax_Iter">Maximum iterations</label><input id="rfePFAmax_Iter" class="textInput" type="number" step="1"></div></div><div class="twocol"><div class="field"><label for="rfePFAlb">Lower bound</label><input id="rfePFAlb" class="textInput" type="number" step="0.01"></div><div class="field"><label for="rfePFAub">Upper bound</label><input id="rfePFAub" class="textInput" type="number" step="0.01"></div></div><div class="field"><label for="rfePFAthres">Threshold</label><input id="rfePFAthres" class="textInput" type="number" step="0.01"></div></div></div></div><div class="rfePane hidden" id="rfePane_pfe"><h2>Feature stability across CV1 partitions</h2><p class="muted" id="rfePFEEligibilityMessage"></p><div id="rfePFEFilterPanel"><div class="rfeMini"><h3>Cross-CV1 probabilistic feature extraction</h3><div class="field"><label><input id="rfeFilterPFEFlag" type="checkbox"> Optimize feature selection across CV1 partitions</label></div><div id="rfeFilterPFEOptions"><div class="twocol"><div class="field"><label for="rfeFilterPFEMode">Mode</label><select id="rfeFilterPFEMode"><option value="1">Agreement with tolerance window</option><option value="2">Absolute number of most consistent features</option><option value="3">Percentage of most consistent features</option></select></div><div class="field"><label for="rfeFilterPFEPerc">Cutoff / number / percentage</label><input id="rfeFilterPFEPerc" class="textInput" type="number" step="1"></div></div><div class="twocol"><div class="field"><label for="rfeFilterPFETolWin">Tolerance window [%]</label><input id="rfeFilterPFETolWin" class="textInput" type="number" step="1"></div><div class="field"><label for="rfeFilterPFEMinNum">Minimum number of features</label><input id="rfeFilterPFEMinNum" class="textInput" type="number" step="1" min="1"></div></div><div class="field"><label><input id="rfeFilterPFEPrune" type="checkbox"> Prune/retrain individual models instead of using one optimized mask</label></div></div></div></div><div id="rfePFEWrapperPanel"><div class="rfeMini"><h3>Cross-CV1 probabilistic feature extraction</h3><div class="field"><label><input id="rfeWrapperPFEFlag" type="checkbox"> Optimize wrapper-selected feature masks across CV1 partitions</label></div><div id="rfeWrapperPFEOptions"><div class="twocol"><div class="field"><label for="rfeWrapperPFEMode">Mode</label><select id="rfeWrapperPFEMode"><option value="1">Agreement with tolerance window</option><option value="2">Absolute number of most consistent features</option><option value="3">Percentage of most consistent features</option></select></div><div class="field"><label for="rfeWrapperPFEPerc">Cutoff / number / percentage</label><input id="rfeWrapperPFEPerc" class="textInput" type="number" step="1"></div></div><div class="twocol"><div class="field"><label for="rfeWrapperPFETolWin">Tolerance window [%]</label><input id="rfeWrapperPFETolWin" class="textInput" type="number" step="1"></div><div class="field"><label for="rfeWrapperPFEMinNum">Minimum number of features</label><input id="rfeWrapperPFEMinNum" class="textInput" type="number" step="1" min="1"></div></div><div class="field"><label><input id="rfeWrapperPFEPrune" type="checkbox"> Prune/retrain individual models instead of using one optimized mask</label></div></div></div></div></div><div class="rfePane hidden" id="rfePane_cv2"><h2>CV2 / ensemble prediction</h2><div class="field"><label><input id="rfeClassRetrain" type="checkbox"> Retrain classifiers with the full CV1 partition</label></div><div class="field" id="rfeCV2MetricField"><label for="rfeCV2Metric">CV2 ensemble metric</label><select id="rfeCV2Metric"><option value="1">Target matrix / majority voting</option><option value="2">Decision/probability value matrix</option></select></div><div class="field"><label for="rfeAggregationLevel">Aggregating predictions across CV2 permutations</label><select id="rfeAggregationLevel"><option value="0">Mean ensemble prediction across CV2 permutations</option><option value="1">Grand ensemble prediction across CV2 permutations</option></select></div></div></div></div></div></div></div>'
'<div class="selectorModal" id="fusionSelectorModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Select modalities for fusion</b><div class="muted">Select at least two modalities. Each modality is shown on one line.</div></div><button id="cancelFusionSelection" type="button">Cancel</button></div><div class="selectorBody"><div id="fusionSelectorList" class="selectorList"></div><div class="status" id="fusionSelectorStatus"></div><div class="actions"><button id="confirmFusionSelection" class="primary" type="button">Confirm selection</button></div></div></div></div>'
'<div class="selectorModal" id="multiLabelSelectorModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Select target labels</b><div class="muted">Select one or more columns from NM.label. This selector is unavailable while an alternative label is active.</div></div><button id="cancelMultiLabelSelection" type="button">Cancel</button></div><div class="selectorBody"><div id="multiLabelSelectorList" class="selectorList"></div><div class="status" id="multiLabelSelectorStatus"></div><div class="actions"><button id="confirmMultiLabelSelection" class="primary" type="button">Confirm selection</button></div></div></div></div>'
'<div class="selectorModal" id="copyPreprocModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Copy preprocessing setup</b><div class="muted" id="copyPreprocSourceTitle">Copy the active modality preprocessing branch to selected target modalities.</div></div><button id="cancelCopyPreproc" type="button">Cancel</button></div><div class="selectorBody"><div class="field"><label>Source preprocessing chain</label><div id="copyPreprocChain" class="preprocChain"></div><div id="copyPreprocSourceSummary" class="summary"></div></div><div class="field"><label>Target modalities</label><div class="row"><button id="copyPreprocSelectAll" type="button">Select all</button><button id="copyPreprocUnselectAll" type="button">Unselect all</button><button id="copyPreprocSelectSplitSiblings" type="button" class="hidden">Select atlas-split siblings</button></div><div id="copyPreprocTargetList" class="selectorList"></div></div><div class="status" id="copyPreprocStatus"></div><div class="actions"><button id="confirmCopyPreproc" class="primary" type="button">Copy setup</button></div></div></div></div>'
'<div class="selectorModal" id="altLabelModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Alternative label</b></div><button id="closeAltLabelConfig" type="button">Close</button></div>'
'<div class="selectorBody"><div class="field"><label><input id="altLabelEnabled" type="checkbox"> Use alternative label</label></div><div id="altLabelOptions" class="hidden"><div class="field"><label for="altLabelSourceVar">Label variable</label><select id="altLabelSourceVar"></select></div><div class="field"><label for="altLabelName">New label name</label><input id="altLabelName" class="textInput" type="text" placeholder="Alternative label"></div><div class="field"><label for="altLabelMode">Learning framework</label><select id="altLabelMode"><option value="classification">Classification</option><option value="regression">Regression</option></select></div><div class="field hidden" id="altLabelGroupNamesField"><label for="altLabelGroupNames">Group names, comma-separated</label><input id="altLabelGroupNames" class="textInput" type="text" placeholder="Group 1, Group 2"></div></div><div class="status hidden" id="altLabelStatus"></div></div></div></div>'

'<div class="selectorModal" id="synthConfigModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Synthetic-data configuration</b><div class="muted"></div></div><button id="closeSynthConfig" type="button">Close</button></div>'
'<div class="selectorBody"><div class="field"><label><input id="synthEnabled" type="checkbox"> Generate synthetic data</label></div><div id="synthOptions" class="hidden"><div class="field"><label for="synthMethod">Synthetic data generation method</label><select id="synthMethod"><option value="1">kNN-based</option><option value="2">ADASYN</option><option value="3">PCAGauss</option><option value="4">Gaussian mixture model</option><option value="5">Gaussian copula</option></select></div><div class="twocol"><div class="field"><label for="synthStandardizeData">Standardization before distance analysis</label><select id="synthStandardizeData"><option value="1">Standardize data</option><option value="2">Data already standardized / not needed</option></select></div><div class="field"><label for="synthWrite2Disk">Synthetic data management</label><select id="synthWrite2Disk"><option value="1">Use data permanently by writing it to disk</option><option value="2">Recreate data in each model training run</option></select></div></div><div class="field"><label for="synthUncertaintyScale">Population uncertainty scale (0 = fixed distribution)</label><input id="synthUncertaintyScale" class="textInput" type="number" min="0" step="0.1"></div><div id="synthMethodKNN"><div class="twocol"><div class="field"><label for="synthK">Nearest neighbours for interpolation</label><input id="synthK" class="textInput" type="number" min="1" step="1"></div><div class="field"><label for="synthDistanceMeasure">Distance measure</label><select id="synthDistanceMeasure"><option value="Euclidean">Euclidean</option><option value="Manhattan">Manhattan</option><option value="Cosine">Cosine</option><option value="Mahalanobis">Mahalanobis</option></select></div></div><div class="field"><label for="synthNumSyntheticObservations1" data-help-topic="synthNumSyntheticObservations">Number of synthetic observations</label><input id="synthNumSyntheticObservations1" class="textInput synthNSyn" type="number" min="0" step="1"></div></div><div id="synthMethodADASYN"><div class="twocol"><div class="field"><label for="synthBeta">Beta value for degree of balancing</label><input id="synthBeta" class="textInput" type="number" min="0" max="1" step="0.01"></div><div class="field"><label for="synthKDensity">k for density estimation</label><input id="synthKDensity" class="textInput" type="number" min="1" step="1"></div></div><div class="field"><label for="synthKSMOTE">k for SMOTE</label><input id="synthKSMOTE" class="textInput" type="number" min="1" step="1"></div></div><div id="synthMethodPCAGauss"><div class="field"><label for="synthNumSyntheticObservations3" data-help-topic="synthNumSyntheticObservations">Number of synthetic observations</label><input id="synthNumSyntheticObservations3" class="textInput synthNSyn" type="number" min="0" step="1"></div></div><div id="synthMethodGMM"><div class="twocol"><div class="field"><label for="synthNComponentsText">Range of Gaussian components</label><input id="synthNComponentsText" class="textInput" type="text" placeholder="e.g. 1 2 3 4"></div><div class="field"><label for="synthMinMethod">Metric for selecting the number of components</label><select id="synthMinMethod"><option value="1">Bayesian Information Criterion (BIC)</option><option value="2">Akaike Information Criterion (AIC)</option></select></div></div><div class="field"><label for="synthNumSyntheticObservations4" data-help-topic="synthNumSyntheticObservations">Number of synthetic observations</label><input id="synthNumSyntheticObservations4" class="textInput synthNSyn" type="number" min="0" step="1"></div></div><div id="synthMethodCopula"><div class="field"><label for="synthNumSyntheticObservations5" data-help-topic="synthNumSyntheticObservations">Number of synthetic observations</label><input id="synthNumSyntheticObservations5" class="textInput synthNSyn" type="number" min="0" step="1"></div></div></div></div></div></div>'
'<div class="selectorModal" id="cvConfigModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Cross-validation configuration</b><div class="muted">Set CV1/CV2 partitioning, or load a saved CV structure.</div></div><button id="closeCVConfig" type="button">Close</button></div>'
'<div class="selectorBody"><div class="field"><label for="cvFramework">Cross-validation framework</label><select id="cvFramework"><option value="1">Pooled cross-validation</option><option value="2">Outer Leave-Group-Out / Inner pooled</option><option value="3">Nested Leave-Group-Out</option><option value="4">Outer Leave-Group-Out / Inner Leave-Group-In</option></select></div><div class="twocol"><div class="field" id="cvOuterModeField"><label for="cvOuterMode">Outer CV2 partitioning</label><select id="cvOuterMode"><option value="kfold">Repeated K-fold</option><option value="loo">Leave-one-out</option></select></div><div class="field" id="cvInnerModeField"><label for="cvInnerMode">Inner CV1 partitioning</label><select id="cvInnerMode"><option value="kfold">Repeated K-fold</option><option value="loo">Leave-one-out</option></select></div></div><div class="twocol"><div class="field" id="cvOuterPermField"><label for="cvOuterPerm">Outer CV2 permutations</label><input id="cvOuterPerm" class="textInput" type="number" min="1" step="1"></div><div class="field" id="cvOuterFoldField"><label for="cvOuterFold">Outer CV2 folds</label><input id="cvOuterFold" class="textInput" type="number" min="2" step="1"></div></div><div class="twocol"><div class="field" id="cvInnerPermField"><label for="cvInnerPerm">Inner CV1 permutations</label><input id="cvInnerPerm" class="textInput" type="number" min="1" step="1"></div><div class="field" id="cvInnerFoldField"><label for="cvInnerFold">Inner CV1 folds</label><input id="cvInnerFold" class="textInput" type="number" min="2" step="1"></div></div><div id="cvOuterGroupField" class="field hidden"><label for="cvOuterGroupSourceVar">Outer CV2 group-index variable</label><select id="cvOuterGroupSourceVar"></select><div class="summary" id="cvOuterGroupSummary"></div></div><div id="cvInnerGroupField" class="field hidden"><label for="cvInnerGroupSourceVar">Inner CV1 group-index variable</label><select id="cvInnerGroupSourceVar"></select><div class="summary" id="cvInnerGroupSummary"></div></div><div id="cvDecomposeField" class="field hidden"><label for="cvDecompose">Multi-class decomposition</label><select id="cvDecompose"><option value="1">One-vs-one</option><option value="2">One-vs-all</option><option value="9">Multi-group / no decomposition</option></select><div class="summary" id="cvDecomposeInfo"></div></div><div class="field"><label><input id="cvEqEnabled" type="checkbox"> Equalize CV1 training partitions by undersampling</label></div><div id="cvEqOptions" class="hidden"><div id="cvEqRegression" class="hidden"><div class="field"><label for="cvEqTarget">Equalization target</label><select id="cvEqTarget"><option value="label">NM.label</option><option value="covariate">Covariate</option></select></div><div class="field hidden" id="cvEqCovariateField"><label for="cvEqCovariateIndex">Covariate</label><select id="cvEqCovariateIndex"></select></div><div class="twocol"><div class="field"><label for="cvEqMinCount">Minimum observations at lower histogram end</label><input id="cvEqMinCount" class="textInput" type="number" min="1" step="1"></div><div class="field"><label for="cvEqMaxCount">Minimum observations at upper histogram end</label><input id="cvEqMaxCount" class="textInput" type="number" min="1" step="1"></div></div><div class="field"><label for="cvEqBinCount">Histogram bins</label><input id="cvEqBinCount" class="textInput" type="number" min="2" step="1"></div><div class="inlineActions" id="cvEqHistogramActions"><button id="cvPlotOriginal" type="button">Inspect original histogram</button><button id="cvPlotEqualized" type="button">Inspect equalized CV1 histogram</button></div></div><div id="cvEqClassification" class="hidden"><div class="field"><label for="cvEqPosNegRatio">Target bigger/smaller class ratio</label><input id="cvEqPosNegRatio" class="textInput" type="number" min="0.01" step="0.01"></div></div><div class="field"><label><input id="cvEqAddRemoved2Test" type="checkbox"> Shuffle removed observations to CV1 test data</label></div></div><div id="cvConstrainedField" class="field hidden"><label><input id="cvConstrainedCV" type="checkbox"> Constrain pooled CV by group-index variable</label><div id="cvConstrainedOptions" class="hidden"><select id="cvConstrainedSourceVar"></select><div class="summary" id="cvConstrainedSummary"></div></div></div><div class="field"><label><input id="cvOnlyGroupFlag" type="checkbox"> Use part of the sample as exclusive test data</label></div><div id="cvOnlyGroupOptions" class="hidden"><div class="field"><label for="cvOnlyGroupSourceVar">Index variable for exclusive test cases</label><select id="cvOnlyGroupSourceVar"></select><div class="summary" id="cvOnlyGroupSummary"></div></div><div class="field"><label for="cvOnlyGroupLevel">CV level</label><select id="cvOnlyGroupLevel" disabled><option value="1">CV2 test data</option></select><div class="muted">Only CV2 test data is currently implemented.</div></div></div><div class="field hidden" id="cvAppendModeField"><label for="cvAppendMode">Build mode</label><select id="cvAppendMode"><option value="0">Rebuild / do not append</option><option value="1">Append to outer CV cycle</option><option value="2">Append to inner CV cycles</option><option value="3">Rebuild CV structure without new permutations</option></select></div><div class="field"><label>Load/save CV structure and settings</label><div class="inlineActions"><button id="cvPickLoad" type="button">Select CV .mat to load...</button><button id="cvPickSave" type="button">Select save directory...</button></div><input id="cvLoadPath" class="textInput" type="text" placeholder="Path to CVstruct_*.mat"><input id="cvSavePath" class="textInput" type="text" placeholder="Path to save CVstruct_*.mat" style="margin-top:8px"></div><div class="actions"><button id="cvBuild" class="primary" type="button">Build Cross-Validation structure</button><button id="cvLoad" type="button">Load Cross-Validation structure</button><button id="cvSave" type="button">Save Cross-Validation structure</button></div><div class="status" id="cvConfigInfo"></div></div></div></div>'
'<div class="selectorModal" id="cvBuildConfirmModal"><div class="selectorBox"><div class="selectorHead"><div><b>Build Cross-Validation structure</b><div class="muted">An existing compatible CV structure is available. Choose how the new CV structure should be handled.</div></div></div>'
'<div class="selectorBody"><div class="field"><label for="cvBuildAppendChoice">Build mode</label><select id="cvBuildAppendChoice"><option value="0">Overwrite existing CV structure</option><option value="1">Append to outer CV cycle</option><option value="2">Append to inner CV cycles</option><option value="3">Rebuild CV structure without new permutations</option></select></div><div class="actions"><button id="cvBuildConfirmProceed" class="primary" type="button">Proceed</button><button id="cvBuildConfirmAbort" type="button">Abort</button></div></div></div></div>'
'<div class="selectorModal" id="stackingConfigModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Stacking configuration</b><div class="muted">Configure meta-learning using completed first-level analyses with compatible CV partitions.</div></div><button id="closeStackingConfig" type="button">Close</button></div>'
'<div class="selectorBody"><div class="field"><label for="stackingFlag">Activating stacking using predictions generated by other analyses</label><select id="stackingFlag"><option value="2">Disabled</option><option value="1">Enabled</option></select></div><div id="stackingOptions" class="hidden"><div class="field"><label data-help-topic="stackingSelectedAnalyses">First-level analyses entering the stacker</label><button id="chooseStackingAnalyses" type="button">Select analyses...</button><div id="stackingAnalysesSummary" class="summary"></div></div><div class="field hidden" id="stackingDetails"><label for="stackingFeatureNameMode">Feature-name extraction</label><select id="stackingFeatureNameMode"><option value="1">Automatically from selected analyses</option><option value="2">Manually from MATLAB workspace variable</option></select><div class="field hidden" id="stackingFeatureNameVariableField"><label for="stackingFeatureNameVariable">Workspace variable containing feature names</label><input id="stackingFeatureNameVariable" class="textInput" type="text" placeholder="e.g. stackerFeatureNames"></div><div class="field"><label for="stackingPredictionMode">Extract predictions from</label><select id="stackingPredictionMode"><option value="1">CV1 training data</option><option value="2">CV1 test data</option></select></div></div></div><div class="status" id="stackingConfigInfo"></div></div></div></div>'
'<div class="selectorModal" id="stackingAnalysisModal"><div class="selectorBox wide"><div class="selectorHead"><div><b>Select first-level analyses for stacking</b><div class="muted">Select at least two completed analyses with compatible CV partitions.</div></div><button id="cancelStackingSelection" type="button">Cancel</button></div><div class="selectorBody"><div id="stackingAnalysisList" class="selectorList"></div><div class="status" id="stackingAnalysisStatus"></div><div class="actions"><button id="confirmStackingSelection" class="primary" type="button">Confirm selection</button></div></div></div></div>'
'<div class="modal" id="modal"><div class="modalBox"><div class="modalHead"><div><b id="modalTitle">Configurator</b><div class="path" id="modalPath">Define parameter template</div></div><button id="forceBack">Close</button></div>'
'<iframe id="editorFrame" title="NeuroMiner configurator"></iframe></div></div>'
'<script>window.NM_MENU_STATE=__NM_MENU_STATE__;</script>'
'<script>window.NM_MODULE_NAV_CONTEXT = {currentModule:"template"};</script>'
['<script>' NMUIMessageTools.script() '</script>']
'<script src="NMModuleIconSet.js"></script>'
'<script src="NMModuleNavigationRail.js"></script>'
'<script src="NMContextHelp.js"></script>'
'<script src="NMTrainTemplateRFEUI.js"></script>'
'<script src="NMTrainTemplateVISUI.js"></script>'
'<script src="NMTrainTemplateMULTIUI.js"></script>'
'<script src="NMTrainTemplateMLIUI.js"></script>'
'<script src="NMTrainTemplateSAVUI.js"></script>'
'<script src="NMTrainTemplateUI_main.js"></script></body></html>'};
            txt = strjoin(L, nl);
            txt = strrep(txt, '__NM_MENU_STATE__', jsState);
        end

        function ctx = workspaceCatalogContext(orch, ctx)
            % workspaceCatalogContext  Build workspace-catalog context for template child pages.
            %
            % Combines orchestrator and app context so child editors can expose MATLAB workspace
            % candidates without directly resolving values in the browser.
            %
            % ctx.nSubjects: exposes the n subjects execution-context value to preprocessing/runtime code.

            if nargin < 2 || isempty(ctx), ctx = struct(); end
            if isfield(orch.NM,'cases') && ~isempty(orch.NM.cases)
                ctx.nSubjects = double(numel(orch.NM.cases));
            elseif isfield(orch.NM,'n_subjects_all') && ~isempty(orch.NM.n_subjects_all)
                ctx.nSubjects = double(orch.NM.n_subjects_all);
            elseif isfield(orch.NM,'label') && ~isempty(orch.NM.label)
                ctx.nSubjects = double(size(orch.NM.label,1));
            end
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the training-template UI text-writer entry point.
            %
            %   NMTrainTemplateUI.writeTextFile(path,txt) delegates generated training-template browser
            %   files to NMSerializationTools while retaining the public wrapper and UI diagnostics.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMTrainTemplateUI:writeFile', 'Could not write %s.', 'fwrite-input-char');
        end
    end
end

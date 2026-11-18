classdef NMDataIOUI
% NMDataIOUI
% -------------------------------------------------------------------------
% Purpose:
%   Browser-service/export boundary for NeuroMiner DataIO. It serializes authoritative MATLAB
%   state to the browser, dispatches explicit service operations, and reimports the session NM.
%
% Authority boundary:
%   Scientific validation/materialization remains in DataIO MATLAB authorities. Browser
%   mandatory-field borders and panel help are navigation projections only. Provenance help-file
%   identity comes from NMDataIOStateTools.sourceTypeCatalogue().
%
% Help rendering:
%   Browser and html-relay sessions use the same responsive in-page help drawer. Provenance
%   help pages are copied into the exported UI bundle and addressed by stable anchors.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(NM, outDir, ctx)
            % export  Write the browser DataIO UI bundle and initial MATLAB session state.
            %
            % paths = NMDataIOUI.export(NM, outDir, ctx) resolves the session
            % directories, serializes the current overview/import state, writes the entry
            % HTML and assets, and stores NM in the MATLAB-side session cache.
            % Creates/updates files below outDir and initializes a session key.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_dataio_ui'); end
            if nargin < 3, ctx = struct(); end %#ok<NASGU>
            NM = NMAnalysisManagerTools.reconcileOOCVAnalysisUse(NM);

            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_dataio_ui');
            outDir = dirs.root;
            webRoot = dirs.webRoot;
            webDir = dirs.webDir;
            pyDir = dirs.pyDir;
            tmpDir = dirs.tmpDir;

            NMDataIOUI.saveSessionNM(NM, tmpDir);
            NMUIStateTools.initialize(tmpDir, NM, 'dataio');
            state = NMDataIOUI.stateFromNM(NM, ctx);
            stateJson = jsonencode(state);

            htmlPath = fullfile(webDir, 'nm_dataio_overview.html');
            NMDataIOUI.writeTextFile(htmlPath, NMDataIOUI.htmlTextFromJson(stateJson));
            NMDataIOUI.copyAssets(webDir);
            NMPreprocUI.writeBridge(fullfile(pyDir,'nm_bridge_server.py'));

            paths = struct('root', outDir, 'webRoot', webRoot, 'webDir', webDir, ...
                'tmpDir', tmpDir, 'html', htmlPath, 'dataioHtml', htmlPath, ...
                'entryHtml', 'nm_dataio_overview.html', ...
                'entryHtmlPath', htmlPath, ...
                'state', NMUIStateTools.statePath(tmpDir));
        end

        function NM = importUpdated(NM, pathsOrWebDir, ctx)
            % IMPORTUPDATED  Rehydrate NM after a browser DataIO session returns to MATLAB.
            %
            %   NM = NMDataIOUI.importUpdated(NM, pathsOrWebDir, ctx) loads the session
            %   copy of NM when present, preserves meaningful incomplete draft input settings,
            %   and clears the session unless the caller requested session retention.
            %   Invariant: committed modality data are imported only from the session copy.
            %#ok<INUSD>
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(pathsOrWebDir), return; end
            tmpDir = NMDataIOUI.pathsTmpDir(pathsOrWebDir);
            if isempty(tmpDir), return; end
            [NM2, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
            if ok, NM = NM2; end
            NM = NMAnalysisManagerTools.reconcileOOCVAnalysisUse(NM);

            % Preserve incomplete browser import contracts. The browser keeps
            % its live semantic input in the session-wide nm2_state.json DataIO section; on return to MATLAB,
            % copy a deliberately incomplete legacy IO struct into
            % NM.datadescriptor{x}.input_settings if the form was actually
            % edited.  This mirrors the legacy DataIO pattern without creating
            % feature data until commit.
            state = NMDataIOUI.readSessionState(tmpDir);
            if isstruct(state) && isfield(state,'matrixImport') && isstruct(state.matrixImport)
                [NM, saved] = NMDataIOUI.persistDraftInputSettings(NM, state.matrixImport);
                if saved
                    NMDataIOUI.saveSessionNM(NM, tmpDir);
                end
            end
            if ~NMUISessionTools.keepSessionAfterImport(ctx)
                NMDataIOUI.clearSessionNM(tmpDir);
            end
        end

        function NM = openStandalone(NM, outDir, ctx, port)
            % OPENSTANDALONE  Export and launch the standalone browser DataIO application.
            %
            %   NM = NMDataIOUI.openStandalone(NM, outDir, ctx, port) writes the UI bundle,
            %   serves it through the local bridge, dispatches MATLAB service requests, and
            %   imports the updated session NM when the browser closes.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_dataio_ui'); end
            if nargin < 3 || isempty(ctx), ctx = struct(); end
            if nargin < 4, port = []; end
            paths = NMDataIOUI.export(NM, outDir, ctx);
            handler = @(req, tmpDir) NMDataIOUI.handleMatlabService(NM, req, tmpDir, ctx);
            [~, bridgeResult] = nm_open_ui(paths.webDir, port, paths.entryHtml, handler);
            NM = NMDataIOUI.importUpdated(NM, paths, ctx);
            if ~isstruct(bridgeResult) || ~isfield(bridgeResult,'unfinished') || ~logical(bridgeResult.unfinished)
                NMUIStateTools.remove(paths.tmpDir);
            else
                NMUIStateTools.refreshContext(paths.tmpDir, NM);
            end
        end

        function state = stateFromNM(NM, ctx, overviewOpts)
            % STATEFROMNM  Build the serialized DataIO overview/import state from NM.
            %
            %   state = NMDataIOUI.stateFromNM(NM, ctx, overviewOpts) summarizes committed
            %   modalities, permissions, workspace variables, OOCV state, inspection artifacts,
            %   and restorable draft input settings for the browser. The default overview path
            %   avoids expensive in-memory rescans of large feature matrices.
            if nargin < 2 || isempty(ctx), ctx = struct(); end
            if nargin < 3 || isempty(overviewOpts)
                % Default overview export must be cheap.  Commit-time imports
                % cache modalityInfo/featureStats; avoid rescanning large
                % in-memory imaging matrices on every return to overview.
                overviewOpts = struct('ScanInMemory', false, 'MaxScanElements', Inf);
            else
                if ~isstruct(overviewOpts), overviewOpts = struct(); end
                if ~isfield(overviewOpts,'ScanInMemory') || isempty(overviewOpts.ScanInMemory)
                    overviewOpts.ScanInMemory = false;
                end
                if ~isfield(overviewOpts,'MaxScanElements') || isempty(overviewOpts.MaxScanElements)
                    overviewOpts.MaxScanElements = Inf;
                end
            end
            state = NMModalityInfoTools.overviewState(NM, overviewOpts);
            state = NMModalityInfoTools.sanitizeStateForUI(state);
            state.sourceTypeCatalogue = NMDataIOStateTools.sourceTypeCatalogue();
            state.covariateSummary = NMDataIOUI.covariateSummaryFromNM(NM);
            state.committedModalityCount = NMDataIOUI.committedModalityCount(NM);
            state.defs = NMDataIOBrowserModeTools.defsState(NM);
            state.dataIOMode = NMDataIOBrowserModeTools.dataIOModeFromDefs(state.defs);
            if isstruct(ctx) && isfield(ctx,'NMAppDataIOScope') && ~isempty(ctx.NMAppDataIOScope)
                scope = lower(strtrim(char(string(ctx.NMAppDataIOScope))));
                if strcmp(scope,'training')
                    if isfield(state.defs,'import_finished') && logical(state.defs.import_finished)
                        state.dataIOMode = 'training_data_manager';
                    else
                        state.dataIOMode = 'training_import';
                    end
                elseif strcmp(scope,'oocv')
                    if ~isfield(state.defs,'analyses_locked') || ~logical(state.defs.analyses_locked)
                        error('NMDataIOUI:oocvBeforeApplicationMode', ...
                            'OOCV DataIO is not available before Application/OOCV mode is activated.');
                    end
                    state.dataIOMode = 'oocv_data_manager';
                else
                    error('NMDataIOUI:invalidDataIOScope','Unsupported DataIO scope: %s',scope);
                end
            end
            state.permissions = NMDataIOBrowserModeTools.permissionsFromMode(state.dataIOMode, state.defs);
            try
                state.workspaceCatalog = NMWorkspaceTools.catalog('base', ctx);
            catch
                state.workspaceCatalog = {};
            end
            state.oocv = NMDataIOBrowserModeTools.oocvManagerState(NM);
            state.trainingCaseAxisPolicy = NMDataIOImportTools.trainingCaseAxisPolicy(NM);
            state.inspectionArtifacts = NMDataIOUI.inspectionArtifactsState(NM);
            state.ui = struct();
            state.ui.initialTab = 'overview';
            state.ui.readOnly = false;
            state.ui.refreshLoadsExternal = false;
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'dataio');
            state.matrixImport = NMDataIOStateTools.defaultMatrixState(NM, []);
            state.matrixImport.importTarget = struct();
            state.matrixImport.draftDirty = false;
            draftIndex = NMDataIOUI.findRestorableDraftInputSettingsIndex(NM);
            if isfinite(draftIndex) && draftIndex >= 1
                ii = draftIndex;
                try
                    state.matrixImport = NMDataIOStateTools.ioToState(NM.datadescriptor{ii}.input_settings);
                    state.matrixImport.varind = double(ii);
                    if isfield(state.matrixImport,'importTarget') && isstruct(state.matrixImport.importTarget)
                        state.matrixImport.importTarget.varind = double(ii);
                    end
                    state.matrixImport = NMDataIOUI.attachPersistedInspectionToImportState(NM, state.matrixImport, ii, '');
                    state.matrixImport.draftDirty = false;
                    if isfield(state.matrixImport,'matrix')
                        state.matrixImport.matrix.sourceType = state.matrixImport.sourceType;
                    end
                catch ME
                    state.messages = {sprintf('Could not restore the previous unfinished DataIO import. Reopen the modality import and reselect its inputs if needed. Error: %s (%s)', ME.message, ME.identifier)};
                end
            end
            if exist('NMDataIODatabaseTools','class') == 8 || exist('NMDataIODatabaseTools','file') == 2
                try
                    state.databaseCapabilities = NMDataIODatabaseTools.capabilities();
                catch ME
                    state.databaseCapabilities = struct('ok', false, 'blocking', true, ...
                        'message', sprintf('Database capability check failed: %s (%s)', ME.message, ME.identifier));
                end
            else
                state.databaseCapabilities = struct('ok', false, 'blocking', true, ...
                    'message', 'Database connector helper NMDataIODatabaseTools.m is not available on the MATLAB path.');
            end
            if ~isfield(state,'messages') || isempty(state.messages)
                baseMsg = NMDataIOBrowserModeTools.modeMessage(state.dataIOMode);
                if isfield(state,'databaseCapabilities') && isstruct(state.databaseCapabilities) && isfield(state.databaseCapabilities,'message') && ...
                        strcmp(state.dataIOMode, 'training_import')
                    state.messages = {[baseMsg ' ' state.databaseCapabilities.message]};
                else
                    state.messages = {baseMsg};
                end
            end
            state.generatedAt = datestr(now, 30);
        end

        function [handled, out] = handleMatlabService(NM, req, tmpDir, ctx)
            % handleMatlabService  Dispatch browser DataIO service requests into MATLAB code.
            %
            % [handled, out] = NMDataIOUI.handleMatlabService(NM, req, tmpDir, ctx)
            % decodes the requested operation, loads the session NM when needed, invokes the
            % appropriate probe/preview/commit/viewer handler, and returns a JSON-serializable
            % service payload. Preview and successful Feature-QC operations persist their bounded
            % resumable artifacts automatically; source/model mutation remains confined to explicit
            % commit/save/session actions.
            %
            % req.diagnostics: carries the diagnostics value from the browser/service request payload.
            % req.exactElementLimit: carries the exact element limit value from the browser/service request payload.
            % req.extra: carries the extra value from the browser/service request payload.
            % req.hardElementLimit: carries the hard element limit value from the browser/service request payload.
            % req.index: carries the index value from the browser/service request payload.
            % req.modalityIndex: selects the modality addressed by a browser or runner request.
            % req.preview: carries the preview value from the browser/service request payload.
            % req.qc: carries the qc value from the browser/service request payload.
            % req.report: carries the report value from the browser/service request payload.
            % req.varind: carries the varind value from the browser/service request payload.
            handled = false;
            out = struct();
            if nargin < 4, ctx = struct(); end
            if nargin < 3, tmpDir = ''; end
            op = NMDataIOUI.requestOperation(req);
            if isempty(op), return; end
            doProfile = NMDataIOProfileTools.enabled(req, ctx);
            tService = tic;
            NMDataIOProfileTools.log(doProfile, 'service %s ENTER', NMDataIOProfileTools.opLabel(op));
            tLoad = tic;
            [sessionNM, ~] = NMDataIOUI.loadSessionNM(NM, tmpDir);
            NMDataIOProfileTools.log(doProfile, 'service %s loadSessionNM: %.3fs (%s)', NMDataIOProfileTools.opLabel(op), toc(tLoad), NMDataIOProfileTools.nmSizeSummary(sessionNM));
            cleanupProfile = onCleanup(@() NMDataIOProfileTools.log(doProfile, 'service %s TOTAL: %.3fs', NMDataIOProfileTools.opLabel(op), toc(tService))); %#ok<NASGU>

            switch lower(op)
                case {'dataio_get_overview','dataio_refresh_overview'}
                    handled = true;
                    try
                        if strcmpi(op, 'dataio_refresh_overview')
                            overviewOpts = struct('ScanInMemory', true, 'MaxScanElements', Inf);
                            overviewMessage = 'DataIO overview refreshed; in-memory modality statistics were explicitly recomputed where available.';
                        else
                            overviewOpts = struct('ScanInMemory', false, 'MaxScanElements', Inf);
                            overviewMessage = 'DataIO overview loaded from the saved modality summary.';
                        end
                        state = NMDataIOUI.stateFromNM(sessionNM, ctx, overviewOpts);
                        out = struct('ok', true, 'message', overviewMessage, 'state', state);
                    catch ME % nm2-allow: NMUIErrorTools canonical service report retains source stack
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                    end

                case {'dataio_export_api_recipe'}
                    handled = true;
                    try
                        outputDir = NMDataIOUI.requestTextField(req, {'outputDir','directory','folder','path'});
                        modalityIndex = [];
                        if isstruct(req)
                            candidates = {'modalityIndex','varind','index'};
                            for ci = 1:numel(candidates)
                                if isfield(req, candidates{ci}) && ~isempty(req.(candidates{ci}))
                                    modalityIndex = req.(candidates{ci});
                                    break;
                                end
                            end
                            if isempty(modalityIndex) && isfield(req,'extra') && isstruct(req.extra)
                                for ci = 1:numel(candidates)
                                    if isfield(req.extra, candidates{ci}) && ~isempty(req.extra.(candidates{ci}))
                                        modalityIndex = req.extra.(candidates{ci});
                                        break;
                                    end
                                end
                            end
                        end
                        if isempty(modalityIndex), modalityIndex = 'all'; end
                        exportOut = NMDataIOCodeExportTools.writeImportFunction(sessionNM, outputDir, struct('ModalityIndex', modalityIndex));
                        msg = exportOut.message;
                        if isfield(exportOut,'functionFile') && ~isempty(exportOut.functionFile)
                            msg = sprintf('%s Function: %s', msg, exportOut.functionFile);
                        end
                        out = exportOut;
                        out.ok = true;
                        out.message = msg;
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOCodeExportTools.writeImportFunction');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Exporting DataIO API recipe failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_export_qc_sidecar'}
                    handled = true;
                    try
                        sidecarRoot = NMDataIOUI.requestTextField(req, {'qcSidecarRoot','sidecarRoot','outputDir','directory','folder','path'});
                        modalityIndex = 'all';
                        if isstruct(req)
                            if isfield(req,'modalityIndex') && ~isempty(req.modalityIndex)
                                modalityIndex = req.modalityIndex;
                            elseif isfield(req,'varind') && ~isempty(req.varind)
                                modalityIndex = req.varind;
                            elseif isfield(req,'index') && ~isempty(req.index)
                                modalityIndex = req.index;
                            elseif isfield(req,'extra') && isstruct(req.extra)
                                if isfield(req.extra,'modalityIndex') && ~isempty(req.extra.modalityIndex), modalityIndex = req.extra.modalityIndex; end
                            end
                        end
                        targetSpec = struct();
                        if isstruct(req)
                            targetSpec = NMDataIOUI.qcSidecarExportTargetFromRequest(req);
                        end
                        [NM2, exportMessages, exportSummary] = NMDataIOUI.exportQCSidecarsFromNM(sessionNM, modalityIndex, sidecarRoot, tmpDir, targetSpec);
                        NMDataIOUI.saveSessionNM(NM2, tmpDir);
                        state = NMDataIOUI.stateFromNM(NM2, ctx, struct('ScanInMemory', false));
                        strip = NMDataIOMessageTools.highestPriorityStrip(exportMessages, 'QC data exported.');
                        out = struct('ok', ~strip.blocking, 'blocking', strip.blocking, 'message', strip.text, 'strip', strip, ...
                            'messages', NMDataIOMessageTools.forDiagnosticsPanel(exportMessages), 'state', state, ...
                            'exportSummary', exportSummary, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.exportQCSidecarsFromNM');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Could not export the QC data.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_prepare_add_modality'}
                    handled = true;
                    try
                        importState = NMDataIOModalityMutationTools.prepareAddState(sessionNM);
                        out = struct('ok', true, 'message', sprintf('Prepared import target for new modality %g.', double(importState.varind)), ...
                            'matrixImport', importState, 'statePatch', importState, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.prepareAddModality');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Preparing add-modality state failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_prepare_replace_modality','dataio_prepare_resume_modality'}
                    handled = true;
                    try
                        varind = NMDataIOUI.requestModalityIndex(req);
                        if strcmp(op, 'dataio_prepare_replace_modality')
                            existingMode = 'replace';
                            fallback = sprintf('Prepared modification target for modality %g.', double(varind));
                        else
                            existingMode = 'resume';
                            fallback = sprintf('Prepared resume target for modality %g.', double(varind));
                        end
                        [importState, messages] = NMDataIOModalityMutationTools.prepareExistingState(sessionNM, varind, existingMode);
                        if ~NMDataIOMessageTools.hasFatal(messages) && strcmp(existingMode,'replace')
                            [sessionNM, transitionMessages] = NMDataIOModalityMutationTools.beginModification(sessionNM, varind);
                            messages = [messages; transitionMessages];
                            if ~NMDataIOMessageTools.hasFatal(messages)
                                NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                            end
                        end
                        importState = NMDataIOUI.attachPersistedInspectionToImportState(sessionNM, importState, varind, tmpDir);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, fallback);
                        out = struct('ok', ~NMDataIOMessageTools.hasFatal(messages), 'blocking', NMDataIOMessageTools.hasFatal(messages), ...
                            'message', strip.text, 'strip', strip, 'messages', messages, 'matrixImport', importState, ...
                            'statePatch', importState, 'state', NMDataIOUI.stateFromNM(sessionNM, ctx), 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.prepareExistingModality');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Preparing existing-modality state failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_externalize_modality'}
                    handled = true;
                    try
                        varind = NMDataIOUI.requestModalityIndex(req);
                        outputDir = NMDataIOUI.requestTextField(req, {'outputDir','directory','folder','path'});
                        [NM2, messages, outPath] = NMDataIOExternalStorageTools.externalizeModality(sessionNM, varind, outputDir);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Externalized modality %g.', double(varind)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'outputPath', outPath, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.externalizeModality');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Externalizing modality failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_relink_modality'}
                    handled = true;
                    try
                        varind = NMDataIOUI.requestModalityIndex(req);
                        matFile = NMDataIOUI.requestTextField(req, {'matFile','file','path','linkPath'});
                        [NM2, messages] = NMDataIOExternalStorageTools.relinkModality(sessionNM, varind, matFile);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Relinked modality %g.', double(varind)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.relinkModality');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Relinking modality failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_modality_resources'}
                    handled = true;
                    try
                        varind = NMDataIOUI.requestModalityIndex(req);
                        resources = NMDataIOResourceRelinkTools.list(sessionNM, varind);
                        summary = NMDataIOResourceRelinkTools.summary(resources);
                        out = struct('ok', true, 'resources', resources, 'resourceSummary', summary, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.modalityResources');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Reading modality resources failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_relink_modality_resource'}
                    handled = true;
                    try
                        varind = NMDataIOUI.requestModalityIndex(req);
                        resourceId = NMDataIOUI.requestTextField(req, {'resourceId'});
                        resourcePath = NMDataIOUI.requestTextField(req, {'resourcePath'});
                        [NM2, messages, resources] = NMDataIOResourceRelinkTools.relink(sessionNM, varind, resourceId, resourcePath);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Relinked modality %g resource.', double(varind)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, ...
                                'state', state, 'resources', resources, 'resourceSummary', NMDataIOResourceRelinkTools.summary(resources), 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, ...
                                'messages', messages, 'resources', resources, 'resourceSummary', NMDataIOResourceRelinkTools.summary(resources), 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.relinkModalityResource');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Relinking modality resource failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_preview_modality_resource_root'}
                    handled = true;
                    try
                        varind = NMDataIOUI.requestModalityIndex(req);
                        rootDir = NMDataIOUI.requestTextField(req, {'rootDir'});
                        resourceIds = NMDataIOStateTools.asCaseCell(req.resourceIds);
                        replacements = NMDataIOResourceRelinkTools.locateUnderRoot(sessionNM,varind,resourceIds,rootDir);
                        out = struct('ok',true,'replacements',replacements,'operation',op);
                    catch ME % nm2-allow: DataIO browser ingress reports root path lookup failures
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'Locating modality resources failed.', 2);
                    end

                case {'dataio_relink_modality_resources'}
                    handled = true;
                    try
                        varind = NMDataIOUI.requestModalityIndex(req);
                        [NM2,messages,resources] = NMDataIOResourceRelinkTools.relinkMany(sessionNM,varind,req.resourceReplacements);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages,'Relinked selected modality resources.');
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2,tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2,ctx);
                            out = struct('ok',true,'message',strip.text,'strip',strip,'messages',messages, ...
                                'state',state,'resources',resources,'resourceSummary',NMDataIOResourceRelinkTools.summary(resources),'operation',op);
                        else
                            out = struct('ok',false,'blocking',true,'message',strip.text,'strip',strip,'messages',messages,'operation',op);
                        end
                    catch ME % nm2-allow: DataIO browser ingress reports scientific relink validation failures
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.relinkModalityResources');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Relinking modality resources failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_reimport_linked_modality'}
                    handled = true;
                    try
                        varind = NMDataIOUI.requestModalityIndex(req);
                        [NM2, messages] = NMDataIOExternalStorageTools.reimportLinkedModality(sessionNM, varind);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Re-imported modality %g.', double(varind)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.reimportLinkedModality');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Re-importing linked modality failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_delete_covariates'}
                    handled = true;
                    [NM2, messages] = NMDataIOModalityMutationTools.deleteCovariates(sessionNM, req.covariateIndices);
                    strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Covariates deleted.');
                    if NMDataIOMessageTools.hasFatal(messages)
                        out = struct('ok', false, 'blocking', true, 'message', strip.text, ...
                            'strip', strip, 'messages', messages, 'operation', op);
                    else
                        NMDataIOUI.saveSessionNM(NM2, tmpDir);
                        state = NMDataIOUI.stateFromNM(NM2, ctx);
                        out = struct('ok', true, 'message', strip.text, 'strip', strip, ...
                            'messages', messages, 'state', state, 'operation', op);
                    end

                case {'dataio_delete_modality'}
                    handled = true;
                    try
                        varind = NMDataIOUI.requestModalityIndex(req);
                        [NM2, messages] = NMDataIOModalityMutationTools.deleteModality(sessionNM, varind);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Deleted modality %g.', double(varind)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.deleteModality');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Deleting modality failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_delete_all_modalities'}
                    handled = true;
                    try
                        [NM2, messages] = NMDataIOModalityMutationTools.deleteAll(sessionNM);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Deleted all modalities.');
                        NMDataIOUI.saveSessionNM(NM2, tmpDir);
                        state = NMDataIOUI.stateFromNM(NM2, ctx);
                        out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.deleteAllModalities');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Deleting all modalities failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end


                case {'dataio_finalize_training_import'}
                    handled = true;
                    try
                        [NM2, messages] = NMDataIOBrowserModeTools.finalizeTrainingImport(sessionNM);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Training data import finalized.');
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOBrowserModeTools.finalizeTrainingImport');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Finalizing training data import failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_cancel_import'}
                    handled = true;
                    try
                        state = NMDataIOUI.stateFromNM(sessionNM, ctx);
                        state.matrixImport = NMDataIOStateTools.defaultMatrixState(sessionNM, []);
                        state.matrixImport.draftDirty = false;
                        out = struct('ok', true, 'message', 'Import task cancelled. No imported data were changed.', ...
                            'state', state, 'matrixImport', state.matrixImport, 'statePatch', state.matrixImport, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.cancelImport');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Cancelling import task failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_create_oocv_container'}
                    handled = true;
                    try
                        reqState = NMDataIOUI.requestState(req);
                        [NM2, target, messages] = NMDataIOBrowserModeTools.createOOCVContainer(sessionNM, reqState);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Created OOCV/application dataset %g.', double(target.containerIndex)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, ...
                                'state', state, 'importTarget', target, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOBrowserModeTools.createOOCVContainer');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Creating OOCV/application dataset failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_delete_oocv_container'}
                    handled = true;
                    try
                        containerIndex = NMDataIOUI.requestContainerIndex(req);
                        [NM2, messages] = NMDataIOBrowserModeTools.deleteOOCVContainer(sessionNM, containerIndex);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Deleted OOCV/application dataset %g.', double(containerIndex)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOBrowserModeTools.deleteOOCVContainer');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Deleting OOCV/application dataset failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_preview_oocv_groups','dataio_set_oocv_groups','dataio_clear_oocv_groups'}
                    handled = true;
                    try
                        reqState = NMDataIOUI.requestState(req);
                        containerIndex = NMDataIOUI.requestContainerIndex(req);
                        commitGroups = strcmp(op,'dataio_set_oocv_groups') || strcmp(op,'dataio_clear_oocv_groups');
                        if strcmp(op,'dataio_clear_oocv_groups'), reqState.clear = true; end
                        [NM2, grouping, messages] = NMDataIOBrowserModeTools.configureOOCVGroups(sessionNM, containerIndex, reqState, commitGroups);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'OOCV study-group configuration not evaluated.');
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            if commitGroups, NMDataIOUI.saveSessionNM(NM2, tmpDir); end
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, ...
                                'state', state, 'grouping', grouping, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, ...
                                'messages', messages, 'grouping', grouping, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOBrowserModeTools.configureOOCVGroups');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'OOCV study-group configuration failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_set_oocv_labels_known'}
                    handled = true;
                    try
                        reqState = NMDataIOUI.requestState(req);
                        containerIndex = NMDataIOUI.requestContainerIndex(req);
                        labelsKnown = NMDataIOBrowserModeTools.specLogical(reqState, {'labelsKnown','labels_known'}, false);
                        [NM2, messages] = NMDataIOBrowserModeTools.setOOCVLabelsKnown(sessionNM, containerIndex, labelsKnown);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Updated OOCV/application dataset %g label availability.', double(containerIndex)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOBrowserModeTools.setOOCVLabelsKnown');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Updating OOCV/application label availability failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_rename_oocv_container'}
                    handled = true;
                    try
                        containerIndex = NMDataIOUI.requestContainerIndex(req);
                        newDesc = NMDataIOUI.requestTextField(req, {'description','desc','name','newName'});
                        [NM2, messages] = NMDataIOBrowserModeTools.renameOOCVContainer(sessionNM, containerIndex, newDesc);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Renamed OOCV/application dataset %g.', double(containerIndex)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOBrowserModeTools.renameOOCVContainer');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Renaming OOCV/application dataset failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_prepare_oocv_modality'}
                    handled = true;
                    try
                        reqState = NMDataIOUI.requestState(req);
                        containerIndex = NMDataIOUI.requestContainerIndex(req);
                        varind = NMDataIOUI.requestModalityIndex(req);
                        [importState, messages] = NMDataIOBrowserModeTools.prepareOOCVImportState(sessionNM, containerIndex, varind, reqState);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Prepared OOCV/application import target for dataset %g modality %g.', double(containerIndex), double(varind)));
                        out = struct('ok', ~NMDataIOMessageTools.hasFatal(messages), 'blocking', NMDataIOMessageTools.hasFatal(messages), ...
                            'message', strip.text, 'strip', strip, 'messages', messages, 'matrixImport', importState, ...
                            'statePatch', importState, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOBrowserModeTools.prepareOOCVImportState');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Preparing OOCV/application import state failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_externalize_oocv_modality'}
                    handled = true;
                    try
                        containerIndex = NMDataIOUI.requestContainerIndex(req);
                        varind = NMDataIOUI.requestModalityIndex(req);
                        outputDir = NMDataIOUI.requestTextField(req, {'outputDir','directory','folder','path'});
                        target = struct('scope','oocv','containerField','OOCV','containerIndex',containerIndex,'varind',varind);
                        [NM2, messages, outPath] = NMDataIOExternalStorageTools.externalizeModality(sessionNM, varind, outputDir, target);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Externalized OOCV/application dataset %g modality %g.', double(containerIndex), double(varind)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'outputPath', outPath, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.externalizeOOCVModality');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Externalizing OOCV/application modality failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_relink_oocv_modality'}
                    handled = true;
                    try
                        containerIndex = NMDataIOUI.requestContainerIndex(req);
                        varind = NMDataIOUI.requestModalityIndex(req);
                        matFile = NMDataIOUI.requestTextField(req, {'matFile','file','path','linkPath'});
                        target = struct('scope','oocv','containerField','OOCV','containerIndex',containerIndex,'varind',varind);
                        [NM2, messages] = NMDataIOExternalStorageTools.relinkModality(sessionNM, varind, matFile, target);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Relinked OOCV/application dataset %g modality %g.', double(containerIndex), double(varind)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.relinkOOCVModality');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Relinking OOCV/application modality failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_reimport_oocv_modality'}
                    handled = true;
                    try
                        containerIndex = NMDataIOUI.requestContainerIndex(req);
                        varind = NMDataIOUI.requestModalityIndex(req);
                        target = struct('scope','oocv','containerField','OOCV','containerIndex',containerIndex,'varind',varind);
                        [NM2, messages] = NMDataIOExternalStorageTools.reimportLinkedModality(sessionNM, varind, target);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, sprintf('Re-imported OOCV/application dataset %g modality %g.', double(containerIndex), double(varind)));
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'state', state, 'operation', op);
                        else
                            out = struct('ok', false, 'blocking', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.reimportOOCVModality');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Re-importing OOCV/application modality failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end


                case {'dataio_itemselector_prepare'}
                    handled = true;
                    try
                        tReq = tic;
                        selState = NMDataIOUI.requestState(req);
                        NMDataIOProfileTools.log(doProfile, '%s requestState: %.3fs', NMDataIOProfileTools.opLabel(op), toc(tReq));
                        opts = struct();
                        opts.ProfileEnabled = doProfile;
                        opts.ProfileLabel = NMDataIOProfileTools.opLabel(op);
                        if isfield(req,'exactElementLimit'), opts.ExactElementLimit = req.exactElementLimit; end
                        if isfield(req,'hardElementLimit'), opts.HardElementLimit = req.hardElementLimit; end
                        if isfield(req,'materializationCacheKey'), opts.MaterializationCacheKey = req.materializationCacheKey; end
                        tPrepare = tic;
                        out = NMDataIOItemSelectorPackageTools.preparePackage(sessionNM, selState, tmpDir, opts);
                        NMDataIOProfileTools.log(doProfile, '%s preparePackage: %.3fs', NMDataIOProfileTools.opLabel(op), toc(tPrepare));
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.itemSelectorPrepare');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Preparing item selector failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToInspect = false;
                    end

                case {'dataio_itemselector_apply'}
                    handled = true;
                    try
                        selState = NMDataIOUI.requestState(req);
                        token = NMDataIOUI.requestTextField(req, {'token','itemSelectorToken'});
                        out = NMDataIOItemSelectorPackageTools.applyMasks(selState, tmpDir, token, struct());
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.itemSelectorApply');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Applying item selector selection failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_itemselector_close'}
                    handled = true;
                    try
                        token = NMDataIOUI.requestTextField(req, {'token','itemSelectorToken'});
                        out = NMDataIOItemSelectorPackageTools.closePackage(tmpDir, token);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools canonical service report retains source stack
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                    end

                case {'dataio_roi_cat12_inspect'}
                    handled = true;
                    try
                        filePath = NMDataIOUI.requestString(req, 'filePath', '');
                        out = NMDataIOROIDirectTools.inspectCAT12(filePath);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.roiCAT12Inspect');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'CAT12 ROI inspection failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_source_variables','dataio_list_source_variables','dataio_probe_variables'}
                    handled = true;
                    try
                        varState = NMDataIOUI.requestState(req);
                        if isempty(fieldnames(varState))
                            varState = NMDataIOStateTools.defaultMatrixState(sessionNM, []);
                        end
                        out = NMDataIOProbeTools.sourceVariableProbe(sessionNM, varState);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.sourceVariableProbe');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Could not read the selected source variables.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_label_definition_probe'}
                    handled = true;
                    try
                        labelState = NMDataIOUI.requestState(req);
                        if isempty(fieldnames(labelState))
                            labelState = NMDataIOStateTools.defaultMatrixState(sessionNM, []);
                        end
                        out = NMDataIOProbeTools.labelDefinitionProbe(sessionNM, labelState);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.labelDefinitionProbe');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Could not inspect the selected label definition.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_refresh_table_cache','dataio_clear_table_cache'}
                    handled = true;
                    try
                        if exist('NMDataIOTableReadTools','class') == 8 || exist('NMDataIOTableReadTools','file') == 2
                            NMDataIOTableReadTools.clearCache();
                        end
                        if exist('NMDataIOImportTools','class') == 8 || exist('NMDataIOImportTools','file') == 2
                            NMDataIOImportTools.clearPreparedTableCache();
                        end
                        if exist('NMDataIOMaterializationCache','class') == 8 || exist('NMDataIOMaterializationCache','file') == 2
                            NMDataIOMaterializationCache.clearFamily('matrix');
                        end
                        messages = NMDataIOMessageTools.make('ok', false, 'dataio_refresh_table_cache', ...
                            'Previously read table data and the retained matrix Preview were cleared. Run Preview again to read the source again.', 0, 'green*');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Table data reloaded.');
                        out = struct('ok', true, 'message', strip.text, 'strip', strip, 'messages', messages, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.refreshTableCache');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Could not reload the table data.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_database_capabilities','dataio_database_status'}
                    handled = true;
                    try
                        caps = NMDataIODatabaseTools.capabilities();
                        out = struct('ok', true, 'message', caps.message, 'databaseCapabilities', caps, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.databaseCapabilities');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Database capability check failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_database_namespaces','dataio_database_list_namespaces'}
                    handled = true;
                    try
                        dbState = NMDataIOUI.requestState(req);
                        if isempty(fieldnames(dbState))
                            dbState = NMDataIOStateTools.defaultMatrixState(sessionNM, []);
                        end
                        kind = NMDataIOUI.requestTextField(req, {'namespaceKind','kind'});
                        if isempty(kind), kind = 'database'; end
                        IO = NMDataIOStateTools.stateToIO(dbState, sessionNM);
                        listing = NMDataIODatabaseTools.listNamespaces(IO, kind, struct());
                        msg = sprintf('Found %g %s choice(s).', numel(listing.names), listing.kind);
                        out = struct('ok', true, 'message', msg, 'namespace', listing, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.databaseNamespaces');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Could not list the available databases or schemas.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_database_tables','dataio_database_list_tables'}
                    handled = true;
                    try
                        dbState = NMDataIOUI.requestState(req);
                        if isempty(fieldnames(dbState))
                            dbState = NMDataIOStateTools.defaultMatrixState(sessionNM, []);
                        end
                        IO = NMDataIOStateTools.stateToIO(dbState, sessionNM);
                        listing = NMDataIODatabaseTools.listTables(IO, struct());
                        msg = sprintf('Detected %g database table/view object(s).', numel(listing.entries));
                        out = struct('ok', true, 'message', msg, 'database', listing, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.databaseTables');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Database table listing failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_table_headers','dataio_probe_headers','dataio_header_probe'}
                    handled = true;
                    try
                        tHeaderState = tic;
                        headerState = NMDataIOUI.requestState(req);
                        NMDataIOProfileTools.log(doProfile, '%s requestState: %.3fs', NMDataIOProfileTools.opLabel(op), toc(tHeaderState));
                        if isempty(fieldnames(headerState))
                            headerState = NMDataIOStateTools.defaultMatrixState(sessionNM, []);
                        end
                        headerOpts = struct('MaxRows', NMDataIOUI.requestNumber(req, 'maxRows', 30), ...
                            'ProfileEnabled', doProfile);
                        tHeaderProbe = tic;
                        out = NMDataIOProbeTools.tableHeaderProbe(sessionNM, headerState, headerOpts);
                        NMDataIOProfileTools.log(doProfile, '%s tableHeaderProbe: %.3fs', NMDataIOProfileTools.opLabel(op), toc(tHeaderProbe));
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.tableHeaderProbe');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Could not read the selected table columns.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_validate_import','dataio_validate_matrix_state'}
                    handled = true;
                    try
                        probeState = NMDataIOUI.requestState(req);
                        if isempty(fieldnames(probeState))
                            probeState = NMDataIOStateTools.defaultMatrixState(sessionNM, []);
                        end
                        out = NMDataIOProbeTools.validateMatrixState(sessionNM, probeState);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.validateMatrixState');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Matrix-state validation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_preview'}
                    handled = true;
                    try
                        tReq = tic;
                        previewState = NMDataIOUI.requestState(req);
                        if isempty(fieldnames(previewState)), previewState = NMDataIOStateTools.defaultMatrixState(sessionNM, []); end
                        NMDataIOProfileTools.log(doProfile, '%s requestState: %.3fs', NMDataIOProfileTools.opLabel(op), toc(tReq));
                        opts = NMDataIOUI.previewOptions(req);
                        opts.tmpDir = tmpDir;
                        opts.ProgressTaskId = NMDataIOUI.requestString(req, 'progressTaskId', '');
                        opts.ProfileEnabled = doProfile;
                        opts.ProfileLabel = NMDataIOProfileTools.opLabel(op);

                        % Training input_settings is the MATLAB-side repository for the current
                        % import definition and the template inherited by OOCV. Synchronize that
                        % repository before training retained-materialization identity is computed;
                        % OOCV draft persistence remains at the successful Preview producer boundary.
                        previewNM = sessionNM;
                        previewTarget = NMDataIOImportTargetTools.normalize(previewNM, previewState);
                        if NMDataIOUI.hasExplicitImportTarget(previewState) && ~NMDataIOImportTargetTools.isOOCV(previewTarget)
                            [previewNM, inputSaved, inputMessage] = NMDataIOUI.persistDraftInputSettings(previewNM, previewState);
                            if ~inputSaved
                                error('NMDataIOUI:previewInputSettingsNotPersisted','%s',inputMessage);
                            end
                        end

                        tPreview = tic;
                        if NMDataIOStateTools.isImageIO(previewState)
                            out = NMDataIOImportTools.imagePreview(previewNM, previewState, opts);
                        elseif NMDataIOStateTools.isConnectivityState(previewState)
                            out = NMDataIOUI.connectivityPreview(previewNM, previewState, opts);
                        elseif NMDataIOStateTools.isROIState(previewState)
                            out = NMDataIOUI.roiPreview(previewNM, previewState, opts);
                        else
                            out = NMDataIOImportTools.matrixPreview(previewNM, previewState, opts);
                        end
                        if isfield(out,'ok') && isequal(out.ok, true)
                            sessionNM = previewNM;
                            qcArtifact = out.qc;
                            [sessionNM, persistMessages] = NMDataIOUI.saveInspectionArtifactsToNM(sessionNM, previewState, out.preview, qcArtifact, struct(), tmpDir, '');
                            out.previewPersisted = ~NMDataIOMessageTools.hasFatal(persistMessages);
                            out.qcPersisted = out.previewPersisted;
                            if out.previewPersisted, NMDataIOUI.saveSessionNM(sessionNM, tmpDir); end
                            out.messages = [out.messages(:); NMDataIOMessageTools.forDiagnosticsPanel(persistMessages)];
                            out.summary = NMDataIOMessageTools.summarize(out.messages);
                            out.strip = NMDataIOMessageTools.highestPriorityStrip(out.messages, 'Preview completed.');
                            out.message = out.strip.text;
                            out.blocking = out.strip.blocking;
                            out.ok = ~out.strip.blocking;
                        end
                        NMDataIOProfileTools.log(doProfile, '%s integrated Preview backend: %.3fs', NMDataIOProfileTools.opLabel(op), toc(tPreview));
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.preview');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Preview failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_connectivity_selector_package','dataio_connectivity_node_selector'}
                    handled = true;
                    try
                        selectorState = NMDataIOUI.requestState(req);
                        if isempty(fieldnames(selectorState))
                            selectorState = NMDataIOStateTools.defaultMatrixState(sessionNM, []);
                        end
                        out = NMDataIOUI.connectivitySelectorPackage(sessionNM, selectorState);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.connectivitySelectorPackage');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Connectivity node-selector preparation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_connectivity_qc_group','dataio_connectivity_group_qc_viewer'}
                    handled = true;
                    try
                        viewerState = NMDataIOUI.requestState(req);
                        opts = struct();
                        opts.metricKey = NMDataIOUI.requestString(req, 'metricKey', 'group_mean');
                        opts.zThreshold = NMDataIOUI.requestNumber(req, 'zThreshold', 3);
                        opts.MaterializationCacheKey = NMDataIOUI.requestString(req, 'materializationCacheKey', '');
                        out = NMDataIOUI.connectivityQCGroupViewer(sessionNM, viewerState, opts);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.connectivityQCGroupViewer');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Connectivity group QC viewer preparation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_connectivity_qc_subject','dataio_connectivity_subject_qc_viewer'}
                    handled = true;
                    try
                        viewerState = NMDataIOUI.requestState(req);
                        opts = struct();
                        opts.metricKey = NMDataIOUI.requestString(req, 'metricKey', 'subject_value');
                        opts.rowIndex = NMDataIOUI.requestNumber(req, 'rowIndex', 1);
                        opts.zThreshold = NMDataIOUI.requestNumber(req, 'zThreshold', 3);
                        opts.MaterializationCacheKey = NMDataIOUI.requestString(req, 'materializationCacheKey', '');
                        opts.reuseStaticMetadata = logical(NMDataIOUI.requestNumber(req, 'reuseStaticMetadata', 0));
                        out = NMDataIOUI.connectivityQCSubjectViewer(sessionNM, viewerState, opts);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.connectivityQCSubjectViewer');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Connectivity subject QC viewer preparation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_connectivity_table_schema','dataio_inspect_connectivity_table_schema'}
                    handled = true;
                    try
                        tableVariable = NMDataIOUI.requestString(req, 'tableVariable', '');
                        out = NMDataIOConnectivityTools.inspectTableSchema(tableVariable);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.connectivityTableSchema');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Connectivity table-schema inspection failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_connectivity_mat_variables','dataio_inspect_connectivity_mat_variables'}
                    handled = true;
                    try
                        filePath = NMDataIOUI.requestString(req, 'filePath', '');
                        if isempty(filePath)
                            stReq = NMDataIOUI.requestState(req);
                            specReq = NMDataIOStateTools.stateToConnectivitySpec(stReq, sessionNM);
                            if isfield(specReq,'files') && ~isempty(specReq.files)
                                filePath = char(string(specReq.files{1}));
                            elseif isfield(specReq,'classFileLists') && ~isempty(specReq.classFileLists)
                                cls = specReq.classFileLists;
                                for ci = 1:numel(cls)
                                    if isstruct(cls(ci)) && isfield(cls(ci),'files') && ~isempty(cls(ci).files)
                                        filePath = char(string(cls(ci).files{1}));
                                        break;
                                    end
                                end
                            end
                        end
                        out = NMDataIOConnectivityTools.inspectMatMatrixVariables(filePath);
                        out.strip = NMDataIOMessageTools.highestPriorityStrip(out.messages, out.message);
                        out.messages = NMDataIOMessageTools.forDiagnosticsPanel(out.messages);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.connectivityMatVariables');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Connectivity MAT-variable inspection failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_atlas_descriptor_candidates','dataio_detect_atlas_descriptor_candidates'}
                    handled = true;
                    try
                        atlasFile = NMDataIOUI.requestString(req, 'atlasFile', '');
                        out = NMDataIOAtlasDescriptorTools.detectAtlasDescriptorCandidates(atlasFile);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.atlasDescriptorCandidates');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Could not inspect the selected atlas/ROI information file.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_atlas_descriptor_inspect','dataio_inspect_atlas_descriptor'}
                    handled = true;
                    try
                        atlasFile = NMDataIOUI.requestString(req, 'atlasFile', '');
                        descriptorFile = NMDataIOUI.requestString(req, 'descriptorFile', '');
                        kind = lower(NMDataIOUI.requestString(req, 'kind', 'image'));
                        opts = struct();
                        opts.delimiter = NMDataIOUI.requestString(req, 'delimiter', 'auto');
                        opts.hasHeader = NMDataIOUI.requestString(req, 'hasHeader', 'auto');
                        opts.idColumn = NMDataIOUI.requestString(req, 'idColumn', '');
                        opts.nameColumn = NMDataIOUI.requestString(req, 'nameColumn', '');
                        if strcmp(kind,'connectivity')
                            opts.xColumn = NMDataIOUI.requestString(req, 'xColumn', '');
                            opts.yColumn = NMDataIOUI.requestString(req, 'yColumn', '');
                            opts.zColumn = NMDataIOUI.requestString(req, 'zColumn', '');
                            opts.coordinateSpace = 'MNI';
                            opts.coordinateUnits = 'mm';
                            connSpec = struct('atlasFile',atlasFile,'atlasLabelFile',descriptorFile, ...
                                'atlasLabelDelimiter',opts.delimiter,'atlasLabelHasHeader',opts.hasHeader, ...
                                'atlasLabelIDColumn',opts.idColumn,'atlasLabelNameColumn',opts.nameColumn, ...
                                'atlasLabelXColumn',opts.xColumn,'atlasLabelYColumn',opts.yColumn,'atlasLabelZColumn',opts.zColumn, ...
                                'nodeCoordinateSpace','MNI','nodeCoordinateUnits','mm');
                            out = NMDataIOConnectivityTools.inspectNodeLocalization(connSpec);
                            dropFields = intersect(fieldnames(out), {'descriptorTable','orderedTable','nodeCoordinates','coordinateSource'});
                            if ~isempty(dropFields), out = rmfield(out, dropFields); end
                            if isfield(out,'atlasLocalization') && isstruct(out.atlasLocalization) && isfield(out.atlasLocalization,'coordinates')
                                out.atlasLocalization = rmfield(out.atlasLocalization,'coordinates');
                            end
                        else
                            out = NMDataIOAtlasDescriptorTools.inspectAtlasDescriptor(atlasFile, descriptorFile, opts);
                        end
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.atlasDescriptorInspect');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Could not inspect the selected atlas/ROI information file.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_persisted_preview_page','dataio_preview_page'}
                    handled = true;
                    try
                        varind = NMDataIOUI.requestModalityIndex(req);
                        page = NMDataIOUI.requestNumber(req, 'page', 1);
                        pageSize = NMDataIOUI.requestNumber(req, 'pageSize', 30);
                        dd = NMDataIOUI.localDescriptor(sessionNM, varind);
                        if ~isstruct(dd) || ~isfield(dd,'input_settings') || ~isstruct(dd.input_settings) || ...
                                ~isfield(dd.input_settings,'preview') || ~isstruct(dd.input_settings.preview)
                            error('NMDataIOUI:missingPersistedPreview', 'No persisted DataIO preview is stored for modality #%g.', double(varind));
                        end
                        preview = NMDataIOUI.previewForBrowser(dd.input_settings.preview, page, pageSize);
                        out = struct('ok', true, 'message', sprintf('Loaded persisted preview page %g for modality #%g.', double(page), double(varind)), ...
                            'preview', preview, 'previewPersisted', true, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.persistedPreviewPage');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Loading persisted preview page failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_generate_qc_report','dataio_qc_report_generate'}
                    handled = true;
                    try
                        reportState = NMDataIOUI.requestState(req);
                        if isempty(fieldnames(reportState))
                            reportState = NMDataIOStateTools.defaultMatrixState(sessionNM, []);
                        end
                        qcPayload = struct();
                        if isstruct(req) && isfield(req,'qc') && isstruct(req.qc)
                            qcPayload = NMConfigTools.charifyStrings(req.qc);
                        end
                        diagPayload = struct();
                        if isstruct(req) && isfield(req,'diagnostics') && isstruct(req.diagnostics)
                            diagPayload = NMConfigTools.charifyStrings(req.diagnostics);
                        end
                        [qcPayload, qcCacheMessages] = NMDataIOFeatureQCTools.loadCachedQCForReport(qcPayload, tmpDir);
                        if ~isempty(qcCacheMessages)
                            if ~isfield(diagPayload, 'messages') || isempty(diagPayload.messages)
                                diagPayload.messages = qcCacheMessages;
                            else
                                try
                                    diagPayload.messages = [diagPayload.messages(:); qcCacheMessages(:)];
                                catch
                                    diagPayload.messages = qcCacheMessages;
                                end
                            end
                        end
                        opts = struct();
                        opts.tmpDir = tmpDir;
                        opts.ProgressTaskId = NMDataIOUI.requestString(req, 'progressTaskId', '');
                        opts.outputDir = NMDataIOUI.requestString(req, 'outputDir', '');
                        opts.subjectMetric = NMDataIOUI.requestString(req, 'subjectMetric', 'rmsZ');
                        opts.zThreshold = NMDataIOUI.requestNumber(req, 'zThreshold', 3);
                        opts.FeatureTableExportLimit = NMDataIOUI.requestNumber(req, 'featureTableExportLimit', 10000);
                        opts.openHtml = true;
                        out = NMDataIOQCReportTools.generateFromImportState(sessionNM, reportState, qcPayload, diagPayload, opts);
                        out.reportPersisted = false;
                        out.reportPersistenceMessage = '';
                        if isfield(out,'ok') && isequal(out.ok,true)
                            [sessionNM, reportPersistMessages] = NMDataIOUI.saveInspectionArtifactsToNM( ...
                                sessionNM, reportState, struct(), struct(), out, tmpDir, '');
                            out.reportPersisted = ~NMDataIOMessageTools.hasFatal(reportPersistMessages);
                            if out.reportPersisted
                                NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                                out.reportPersistenceMessage = 'QC report reference persisted to the resumable DataIO session.';
                            end
                            if isfield(out,'messages') && ~isempty(out.messages)
                                allMessages = [out.messages(:); NMDataIOMessageTools.forDiagnosticsPanel(reportPersistMessages)];
                            else
                                allMessages = NMDataIOMessageTools.forDiagnosticsPanel(reportPersistMessages);
                            end
                            out.messages = allMessages;
                            out.summary = NMDataIOMessageTools.summarize(allMessages);
                            out.strip = NMDataIOMessageTools.highestPriorityStrip(allMessages, 'QC report generated.');
                            out.message = out.strip.text;
                            out.blocking = out.strip.blocking;
                            out.ok = ~out.strip.blocking;
                            if ~out.reportPersisted, out.reportPersistenceMessage = out.strip.text; end
                        end
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.qcReport');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'QC report generation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_open_qc_report','dataio_open_persisted_qc_report'}
                    handled = true;
                    try
                        reportPayload = struct();
                        if isstruct(req) && isfield(req,'report') && isstruct(req.report)
                            reportPayload = NMConfigTools.charifyStrings(req.report);
                        end
                        [openedPath, openMessages] = NMDataIOUI.openQCReportReference(reportPayload);
                        strip = NMDataIOMessageTools.highestPriorityStrip(openMessages, sprintf('Opened QC report: %s', openedPath));
                        out = struct('ok', ~strip.blocking, 'message', strip.text, 'strip', strip, ...
                            'messages', NMDataIOMessageTools.forDiagnosticsPanel(openMessages), 'path', openedPath, 'operation', op);
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.openQCReportReference');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Opening QC report failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_image_viewer_prepare_volume','dataio_prepare_image_viewer_volume'}
                    handled = true;
                    try
                        imageFile = NMDataIOUI.requestString(req, 'imageFile', '');
                        maskFile = NMDataIOUI.requestString(req, 'maskFile', '');
                        opts = struct();
                        opts.sliceIndex = NMDataIOUI.requestNumber(req, 'sliceIndex', NaN);
                        opts.spaceDefType = NMDataIOUI.requestString(req, 'spaceDefType', 'brainmask');
                        opts.tmpDir = tmpDir;
                        opts.spaceDefType = NMDataIOUI.requestString(req, 'spaceDefType', 'brainmask');
                        opts.atlasLabelFile = NMDataIOUI.requestString(req, 'atlasLabelFile', '');
                        opts.atlasLabelDelimiter = NMDataIOUI.requestString(req, 'atlasLabelDelimiter', 'auto');
                        opts.atlasLabelHasHeader = NMDataIOUI.requestString(req, 'atlasLabelHasHeader', 'auto');
                        opts.atlasLabelIDColumn = NMDataIOUI.requestString(req, 'atlasLabelIDColumn', '');
                        opts.atlasLabelNameColumn = NMDataIOUI.requestString(req, 'atlasLabelNameColumn', '');
                        out = NMDataIOImagePreviewTools.prepareAxialVolume(imageFile, maskFile, opts);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.imageViewerPrepareVolume');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Imaging viewer volume preparation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_matrix_feature_profile','dataio_prepare_matrix_feature_profile'}
                    handled = true;
                    try
                        profileState = NMDataIOUI.requestState(req);
                        if isempty(fieldnames(profileState))
                            profileState = NMDataIOStateTools.defaultMatrixState(sessionNM, []);
                        end
                        rowIndex = NMDataIOUI.requestNumber(req, 'rowIndex', 1);
                        opts = struct();
                        if NMDataIOStateTools.isROIState(profileState)
                            error('NMDataIOUI:tabularFeatureQCOnly', ...
                                'The feature-QC profile service is confined to tabular non-imaging data. ROI QC is rendered through its spatial template viewer.');
                        end
                        opts.maxPoints = NMDataIOUI.requestNumber(req, 'maxPoints', 6000);
                        opts.maxBins = NMDataIOUI.requestNumber(req, 'maxBins', 1000);
                        opts.histBins = NMDataIOUI.requestNumber(req, 'histBins', 48);
                        opts.featureQuery = NMDataIOUI.requestString(req, 'featureQuery', '');
                        opts.featureZMin = NMDataIOUI.requestNumber(req, 'featureZMin', NaN);
                        opts.featureZMax = NMDataIOUI.requestNumber(req, 'featureZMax', NaN);
                        opts.maxFeatureResults = NMDataIOUI.requestNumber(req, 'maxFeatureResults', 20);
                        out = NMDataIOFeatureQCTools.prepareMatrixFeatureProfile(sessionNM, profileState, rowIndex, opts);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.matrixFeatureProfile');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Matrix feature-QC profile preparation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_roi_viewer_prepare_subject','dataio_prepare_roi_viewer_subject'}
                    handled = true;
                    try
                        cacheToken = NMDataIOUI.requestString(req, 'cacheToken', '');
                        rowIndex = NMDataIOUI.requestNumber(req, 'rowIndex', 1);
                        opts = struct('tmpDir',tmpDir,'ProfileEnabled',doProfile, ...
                            'sliceIndex',NMDataIOUI.requestNumber(req,'sliceIndex',NaN));
                        out = NMDataIOFeatureQCTools.prepareROISubjectSpatialPayload(cacheToken,rowIndex,opts);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.roiViewerSubject');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'ROI subject viewer preparation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_roi_viewer_prepare_qc_overlay','dataio_prepare_roi_viewer_qc_overlay'}
                    handled = true;
                    try
                        cacheToken = NMDataIOUI.requestString(req, 'cacheToken', '');
                        metricKey = NMDataIOUI.requestString(req, 'metricKey', 'subject_z');
                        opts = struct('tmpDir',tmpDir,'metricKey',metricKey,'ProfileEnabled',doProfile, ...
                            'zThreshold',NMDataIOUI.requestNumber(req,'zThreshold',3), ...
                            'sliceIndex',NMDataIOUI.requestNumber(req,'sliceIndex',NaN));
                        if strcmpi(strtrim(metricKey),'subject_z')
                            rowIndex = NMDataIOUI.requestNumber(req, 'rowIndex', 1);
                            profile = NMDataIOFeatureQCTools.prepareROIFeatureProfile(cacheToken, rowIndex, struct('tmpDir',tmpDir,'maxPoints',1e9));
                            if ~isstruct(profile) || ~isfield(profile,'ok') || ~logical(profile.ok)
                                out = struct('ok',false,'message',NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(profile,'message','The ROI Feature-QC profile could not be prepared.')),'operation',op);
                            elseif isfield(profile,'downsampled') && logical(profile.downsampled)
                                out = struct('ok',false,'message','Spatial ROI Feature QC requires all ROI values, but only a subset is available. Run Preview again before opening the spatial QC viewer.','operation',op);
                            else
                                opts.metricLabel = 'Subject ROI z-score';
                                opts.overlayKind = 'subject_z';
                                out = NMDataIOFeatureQCTools.prepareROIViewerPayload(cacheToken, profile.z, opts);
                                out.rowIndex = double(profile.rowIndex);
                                out.caseId = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(profile,'caseId',''));
                                out.label = NMDataIOUI.localFieldOr(profile,'label',[]);
                                out.rmsZ = NMDataIOUI.localFieldOr(profile,'rmsZ',NaN);
                                out.maxAbsZ = NMDataIOUI.localFieldOr(profile,'maxAbsZ',NaN);
                            end
                        else
                            % Group-level ROI QC is computed from resident feature moments/counts and
                            % expanded through the same canonical atlas/annotation authority as subject maps.
                            out = NMDataIOFeatureQCTools.prepareROIViewerPayload(cacheToken, [], opts);
                            out.groupQCMode = true;
                            out.rowIndex = NaN;
                        end
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.roiViewerQCOverlay');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Spatial ROI Feature-QC preparation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_surface_viewer_prepare_mesh','dataio_prepare_surface_viewer_mesh'}
                    handled = true;
                    try
                        surfaceFile = NMDataIOUI.requestString(req, 'surfaceFile', '');
                        geometryFile = NMDataIOUI.requestString(req, 'geometryFile', '');
                        opts = struct();
                        opts.tmpDir = tmpDir;
                        opts.rowIndex = NMDataIOUI.requestNumber(req, 'rowIndex', NaN);
                        opts.groupQCMode = NMDataIOUI.requestNumber(req, 'groupQCMode', 0);
                        out = NMDataIOSurfaceTools.prepareSurfaceViewerMesh(surfaceFile, geometryFile, opts);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.surfaceViewerPrepareMesh');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Surface viewer mesh preparation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_surface_viewer_prepare_qc_overlay','dataio_prepare_surface_viewer_qc_overlay'}
                    handled = true;
                    try
                        surfaceFile = NMDataIOUI.requestString(req, 'surfaceFile', '');
                        cacheToken = NMDataIOUI.requestString(req, 'cacheToken', '');
                        opts = struct();
                        opts.tmpDir = tmpDir;
                        opts.metricKey = NMDataIOUI.requestString(req, 'metricKey', 'subject_z');
                        opts.zThreshold = NMDataIOUI.requestNumber(req, 'zThreshold', NaN);
                        opts.rowIndex = NMDataIOUI.requestNumber(req, 'rowIndex', NaN);
                        out = NMDataIOFeatureQCTools.prepareSurfaceViewerQCOverlay(surfaceFile, cacheToken, opts);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.surfaceViewerQCOverlay');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Surface viewer QC overlay preparation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_image_viewer_prepare_qc_overlay','dataio_prepare_image_viewer_qc_overlay'}
                    handled = true;
                    try
                        imageFile = NMDataIOUI.requestString(req, 'imageFile', '');
                        maskFile = NMDataIOUI.requestString(req, 'maskFile', '');
                        cacheToken = NMDataIOUI.requestString(req, 'cacheToken', '');
                        opts = struct();
                        opts.sliceIndex = NMDataIOUI.requestNumber(req, 'sliceIndex', NaN);
                        opts.tmpDir = tmpDir;
                        opts.metricKey = NMDataIOUI.requestString(req, 'metricKey', 'subject_z');
                        opts.zThreshold = NMDataIOUI.requestNumber(req, 'zThreshold', NaN);
                        opts.spaceDefType = NMDataIOUI.requestString(req, 'spaceDefType', 'brainmask');
                        out = NMDataIOFeatureQCTools.prepareImageViewerQCOverlay(imageFile, maskFile, cacheToken, opts);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.imageViewerQCOverlay');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Imaging viewer QC z-score overlay preparation failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_image_viewer_render','dataio_render_image_overlay'}
                    handled = true;
                    try
                        imageFile = NMDataIOUI.requestString(req, 'imageFile', '');
                        maskFile = NMDataIOUI.requestString(req, 'maskFile', '');
                        opts = struct();
                        opts.sliceIndex = NMDataIOUI.requestNumber(req, 'sliceIndex', NaN);
                        opts.maskOpacity = NMDataIOUI.requestNumber(req, 'maskOpacity', 0.35);
                        opts.spaceDefType = NMDataIOUI.requestString(req, 'spaceDefType', 'brainmask');
                        out = NMDataIOImagePreviewTools.renderAxialOverlay(imageFile, maskFile, opts);
                        out.operation = op;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.imageViewer');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Imaging viewer render failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                    end

                case {'dataio_apply_feature_case_selection'}
                    handled = true;
                    % Selection is maintained in browser state; this operation
                    % validates and echoes the supplied state without committing.
                    try
                        selState = NMDataIOUI.requestState(req);
                        out = NMDataIOProbeTools.validateMatrixState(sessionNM, selState);
                        out.operation = op;
                        out.message = 'Feature/case selection accepted in browser state. Run Preview before commit.';
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.applySelection');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Selection update failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end

                case {'dataio_save_draft','dataio_save_input_settings','dataio_persist_input_settings'}
                    handled = true;
                    try
                        draftState = NMDataIOUI.requestState(req);
                        if isempty(fieldnames(draftState))
                            draftState = NMDataIOStateTools.defaultMatrixState(sessionNM, []);
                        end
                        [NM2, saved, message] = NMDataIOUI.persistDraftInputSettings(sessionNM, draftState);
                        if saved
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            out = struct('ok', true, 'saved', true, 'message', message, 'state', state, 'operation', op);
                        else
                            out = struct('ok', true, 'saved', false, 'message', message, 'operation', op);
                        end
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.saveDraft');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Could not save the unfinished DataIO import settings.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.saved = false;
                    end

                case {'dataio_commit_import'}
                    handled = true;
                    try
                        tReq = tic;
                        importState = NMDataIOUI.requestState(req);
                        if isempty(fieldnames(importState)), importState = NMDataIOStateTools.defaultMatrixState(sessionNM, []); end
                        NMDataIOProfileTools.log(doProfile, '%s requestState: %.3fs', NMDataIOProfileTools.opLabel(op), toc(tReq));
                        commitOpts = struct('ProfileEnabled', doProfile, 'ProfileLabel', NMDataIOProfileTools.opLabel(op), ...
                            'tmpDir', tmpDir, 'ProgressTaskId', NMDataIOUI.requestString(req, 'progressTaskId', ''), ...
                            'MaterializationCacheKey', NMDataIOUI.requestString(req, 'materializationCacheKey', ''), ...
                            'RequireRetainedMaterialization', logical(NMDataIOUI.requestNumber(req, 'previewPerformed', 0)));
                        tCommit = tic;
                        if NMDataIOStateTools.isImageIO(importState)
                            result = NMDataIOImportTools.commitImageImport(sessionNM, importState, commitOpts);
                        elseif NMDataIOStateTools.isConnectivityState(importState)
                            result = NMDataIOUI.commitConnectivityImport(sessionNM, importState, commitOpts);
                        elseif NMDataIOStateTools.isROIState(importState)
                            result = NMDataIOUI.commitROIImport(sessionNM, importState, commitOpts);
                        else
                            result = NMDataIOImportTools.commitMatrixImport(sessionNM, importState, commitOpts);
                        end
                        NMDataIOProfileTools.log(doProfile, '%s integrated Commit backend: %.3fs', NMDataIOProfileTools.opLabel(op), toc(tCommit));
                        NM2 = result.NM;
                        result = rmfield(result, 'NM');
                        if result.ok
                            if isfield(result,'qc') && isstruct(result.qc) && ~isempty(fieldnames(result.qc))
                                persistableQC = result.qc;
                                [NM2, persistMessages] = NMDataIOUI.saveInspectionArtifactsToNM(NM2, importState, struct(), persistableQC, struct(), tmpDir, '');
                                result.messages = [result.messages(:); NMDataIOMessageTools.forDiagnosticsPanel(persistMessages)];
                                result.summary = NMDataIOMessageTools.summarize(result.messages);
                            end
                            commitVarind = NMDataIOStateTools.pick(importState, {'varind'}, NaN);
                            if isfield(result,'varind') && ~isempty(result.varind), commitVarind = result.varind; end
                            if isfinite(double(commitVarind)) && double(commitVarind) >= 1
                                commitTarget = NMDataIOImportTargetTools.normalize(NM2, importState, commitVarind);
                                if ~NMDataIOImportTargetTools.isOOCV(commitTarget) && ...
                                        NMDataIOModalityMutationTools.requiresRecommit(sessionNM, commitVarind)
                                    NM2 = NMDataIOModalityMutationTools.markCommitted(NM2, commitVarind);
                                end
                            end
                            tSave = tic;
                            NMDataIOUI.saveSessionNM(NM2, tmpDir);
                            NMDataIOProfileTools.log(doProfile, '%s saveSessionNM: %.3fs (%s)', NMDataIOProfileTools.opLabel(op), toc(tSave), NMDataIOProfileTools.nmSizeSummary(NM2));
                            tState = tic;
                            state = NMDataIOUI.stateFromNM(NM2, ctx);
                            NMDataIOProfileTools.log(doProfile, '%s stateFromNM: %.3fs', NMDataIOProfileTools.opLabel(op), toc(tState));
                            result.state = state;
                            result.message = sprintf('%s\nOverview refreshed from the imported NM2 data.', result.message);
                        end
                        result.operation = op;
                        out = result;
                    catch ME % nm2-allow: NMUIErrorTools report supplements structured NMDataIOMessageTools diagnostics
                        messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.commitImport');
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'DataIO import commit failed.');
                        out = NMUIErrorTools.exceptionStruct(ME, op, 'DataIO service operation failed.', 2);
                        out.messages = messages;
                        out.strip = strip;
                        out.message = strip.text;
                        out.readyToImport = false;
                    end
            end
        end

        function probe = enrichROIProbe(probe,IO,roiOut,spec)
            % ENRICHROIPROBE  Add direct-ROI source identity, provenance, and bounded QC to a matrix probe.
            if nargin < 1 || ~isstruct(probe), probe=struct(); end
            if nargin < 2 || ~isstruct(IO), IO=struct(); end
            if nargin < 3 || ~isstruct(roiOut), roiOut=struct(); end
            if nargin < 4 || ~isstruct(spec), spec=struct(); end
            Y=NMDataIOUI.localFieldOr(IO,'Y',[]);
            probe.datasource='roi';
            probe.groupmodeName='ROI parcel matrix';
            probe.sourceFormat=char(string(NMDataIOUI.localFieldOr(spec,'sourceFormat','')));
            switch probe.sourceFormat
                case 'cat12_files', probe.sourceFormatName='CAT12 catROI subject files';
                case 'workspace_matrix', probe.sourceFormatName='workspace ROI matrix';
                case 'workspace_table', probe.sourceFormatName='workspace ROI table';
                case 'table_file', probe.sourceFormatName='ROI table file';
                otherwise, probe.sourceFormatName=probe.sourceFormat;
            end
            if ~isempty(Y)
                probe.nSubjectsRaw=double(size(Y,1));
                probe.nFeaturesRaw=double(size(Y,2));
                probe.matrixSummary=sprintf('%g case row(s) x %g ROI feature(s)',size(Y,1),size(Y,2));
            end
            ids=NMDataIOUI.localAsCellstr(NMDataIOUI.localFieldOr(IO,'ID',{}));
            if ~isempty(ids), probe.caseIdSummary=sprintf('%g case ID(s) resolved',numel(ids)); end
            names=NMDataIOUI.localAsCellstr(NMDataIOUI.localFieldOr(IO,'featnames',{}));
            if ~isempty(names), probe.featureNamesSummary=sprintf('%g ROI name(s) identified',numel(names)); end
            labels=NMDataIOUI.localFieldOr(IO,'label',[]);
            probe.hasLabels=~isempty(labels);
            probe.nLabelTargets=double(size(labels,2));
            if probe.hasLabels
                probe.labelSummary=sprintf('%g label row(s) resolved',size(labels,1));
            else
                probe.labelSummary='not supplied';
            end
            covars=NMDataIOUI.localFieldOr(IO,'covars',[]);
            probe.hasCovariates=~isempty(covars);
            probe.nCovariates=double(size(covars,2));
            probe.labelMode=char(string(NMDataIOUI.localFieldOr(spec,'labelMode','')));
            if strcmp(probe.labelMode,'legacy_groups'), probe.labelModeName='Implicit labels from class file lists';
            elseif strcmp(probe.labelMode,'metadata'), probe.labelModeName='Explicit labels from metadata';
            else, probe.labelModeName=probe.labelMode; end
            probe.caseIDMode=char(string(NMDataIOUI.localFieldOr(spec,'caseIDMode','')));
            if strcmp(probe.caseIDMode,'legacy_spm'), probe.caseIDModeName='Filename-derived case IDs';
            elseif strcmp(probe.caseIDMode,'explicit'), probe.caseIDModeName='Explicit case IDs';
            else, probe.caseIDModeName=probe.caseIDMode; end
            probe.auxiliaryAlignmentMode=char(string(NMDataIOUI.localFieldOr(spec,'auxiliaryAlignmentMode','')));
            if strcmp(probe.auxiliaryAlignmentMode,'case_id'), probe.auxiliaryAlignmentModeName='Case-ID mapping';
            elseif strcmp(probe.auxiliaryAlignmentMode,'row_order'), probe.auxiliaryAlignmentModeName='Explicit row order';
            else, probe.auxiliaryAlignmentModeName=probe.auxiliaryAlignmentMode; end
            probe.cat12Atlas=char(string(NMDataIOUI.localFieldOr(spec,'cat12Atlas','')));
            probe.cat12Measure=char(string(NMDataIOUI.localFieldOr(spec,'cat12Measure','')));
            srcMeta=NMDataIOUI.localFieldOr(roiOut,'sourceMetadata',struct());
            probe.cat12Version=char(string(NMDataIOUI.localFieldOr(srcMeta,'cat12Version','')));
            probe.nSourceFiles=0;
            if strcmp(probe.sourceFormat,'cat12_files')
                probe.nSourceFiles=double(numel(NMDataIOUI.localAsCellstr(NMDataIOUI.localFieldOr(spec,'files',{}))));
                if strcmp(probe.labelMode,'legacy_groups')
                    classLists=NMDataIOUI.localFieldOr(spec,'classFileLists',{});
                    if iscell(classLists), probe.nSourceFiles=double(sum(cellfun(@numel,classLists))); end
                end
            end
            groupNames=NMDataIOUI.localAsCellstr(NMDataIOUI.localFieldOr(spec,'groupNames',{}));
            groupSizes=double(NMDataIOUI.localFieldOr(spec,'groupSizes',[]));
            probe.groupSummary='';
            if strcmp(probe.labelMode,'legacy_groups') && ~isempty(groupNames) && numel(groupNames)==numel(groupSizes)
                parts=cell(1,numel(groupNames));
                for gi=1:numel(groupNames), parts{gi}=sprintf('%s: %g',groupNames{gi},groupSizes(gi)); end
                probe.groupSummary=strjoin(parts,', ');
            end
            probe.nWeightingMaps=double(size(NMDataIOUI.localFieldOr(IO,'Yw',[]),1));
            probe.hasWeightingMaps=probe.nWeightingMaps>0;
            prov=NMDataIOUI.localFieldOr(roiOut,'roiProvenance',struct());
            probe.roiMappingValidated=isstruct(prov) && logical(NMDataIOUI.localFieldOr(prov,'ok',false));
            probe.nCanonicalROIs=double(NMDataIOUI.localFieldOr(prov,'nColumns',NaN));
            coords=NMDataIOUI.localFieldOr(prov,'mniCoordinates',[]);
            probe.nMniCoordinates=0;
            if isnumeric(coords) && size(coords,2)==3, probe.nMniCoordinates=double(sum(all(isfinite(coords),2))); end
            probe.spatialKind=''; probe.spatialReferenceSummary='';
            refs=NMDataIOUI.localFieldOr(prov,'spatialReferences',struct([]));
            if isstruct(refs) && ~isempty(refs)
                ref=refs(1);
                probe.spatialKind=char(string(NMDataIOUI.localFieldOr(ref,'kind','')));
                if strcmp(probe.spatialKind,'volumetric_atlas'), probe.spatialKindName='Volumetric labelled atlas';
                elseif strcmp(probe.spatialKind,'surface_annotation'), probe.spatialKindName='Surface annotation';
                else, probe.spatialKindName=probe.spatialKind; end
                refFiles=NMDataIOUI.localAsCellstr(NMDataIOUI.localFieldOr(ref,'sourceFiles',{}));
                if ~isempty(refFiles), probe.spatialReferenceSummary=strjoin(refFiles,'; '); end
            end
            if isfield(roiOut,'importReport') && isstruct(roiOut.importReport), probe.importReport=roiOut.importReport; end
        end

        function out = roiPreview(NM,state,opts)
            % roiPreview  Preview/QC a retained canonical ROI materialization.
            if nargin < 3 || isempty(opts), opts=struct(); end
            progressTask = NMProgressTools.fromOptions(opts, 'Preparing ROI preview', 'Reading ROI data and computing mandatory QC.');
            opts.ProgressTask = progressTask;
            [entry, cacheHit, cacheKey] = NMDataIOImportTools.materializeROIImport(NM,state,opts);
            out=NMDataIOImportTools.emptyServiceOut('roiPreview');
            if NMDataIOMessageTools.hasFatal(entry.messages)
                out=NMDataIOImportTools.finishServiceOut(out,entry.messages);
                NMProgressTools.finish(progressTask,out.message);
                return;
            end
            progressTask = NMProgressTools.phase(progressTask, 'roi_preview_rows', 98, 100, 'Preparing the ROI Preview table.');
            page=NMDataIOImportTools.opt(opts,'Page',1); pageSize=NMDataIOImportTools.opt(opts,'PageSize',30); maxCols=NMDataIOImportTools.opt(opts,'MaxColumns',20);
            [preview,~]=NMDataIOImportTools.previewFromIO(entry.IO,page,pageSize,maxCols);
            preview.roiViewerReference=entry.viewerReference;
            out=NMDataIOImportTools.finishServiceOut(out,entry.messages);
            out.preview=preview; out.probe=NMDataIOUI.enrichROIProbe(entry.probe,entry.IO,entry.sourcePayload,entry.spec); out.qc=entry.qc; out.cacheHit=cacheHit; out.materializationCacheKey=cacheKey;
            out.roiProvenance=entry.sourcePayload.roiProvenance; out.roiImportReport=entry.sourcePayload.importReport;
            out.roiViewerReference=entry.viewerReference; out.statePatch=entry.statePatch;
            NMProgressTools.finish(progressTask,out.message);
        end

        function probe = enrichConnectivityProbe(probe, IO, connOut, spec)
            % ENRICHCONNECTIVITYPROBE  Add connectivity-specific provenance and probe metadata.
            if nargin < 1 || ~isstruct(probe), probe = struct(); end
            if nargin < 2 || ~isstruct(IO), IO = struct(); end
            if nargin < 3 || ~isstruct(connOut), connOut = struct(); end
            if nargin < 4 || ~isstruct(spec), spec = struct(); end
            prov = NMDataIOUI.localFieldOr(connOut,'provenance',struct());
            report = NMDataIOUI.localFieldOr(connOut,'importReport',struct());
            probe.datasource = 'connectivity';
            probe.groupmodeName = 'connectivity edge matrix';
            probe.sourceFormat = char(string(NMDataIOUI.localFieldOr(prov,'sourceFormat',NMDataIOUI.localFieldOr(spec,'sourceFormat',''))));
            switch probe.sourceFormat
                case 'file_per_subject', probe.sourceFormatName = 'subject-level connectivity matrix files';
                case 'array3d', probe.sourceFormatName = '3-D connectivity array';
                case 'vectorized', probe.sourceFormatName = 'vectorized edge matrix';
                case 'table', probe.sourceFormatName = 'connectivity edge table';
                otherwise, probe.sourceFormatName = probe.sourceFormat;
            end
            probe.nNodes = double(NMDataIOUI.localFieldOr(prov,'nNodes',NaN));
            probe.nEdges = double(NMDataIOUI.localFieldOr(prov,'nEdges',probe.nFeaturesRaw));
            if isfinite(probe.nSubjectsRaw) && isfinite(probe.nEdges)
                probe.matrixSummary = sprintf('%g prepared case row(s) x %g retained ROI-to-ROI edge feature(s)',probe.nSubjectsRaw,probe.nEdges);
            end
            if isfinite(probe.nNodes) && isfinite(probe.nEdges)
                probe.featureNamesSummary = sprintf('%g ROI node(s), %g retained edge feature(s)',probe.nNodes,probe.nEdges);
            end
            ids = NMDataIOUI.localAsCellstr(NMDataIOUI.localFieldOr(IO,'ID',{}));
            if ~isempty(ids), probe.caseIdSummary = sprintf('%g source Case ID(s) resolved',numel(ids)); end
            labels = NMDataIOUI.localFieldOr(IO,'label',[]);
            probe.hasLabels = ~isempty(labels);
            probe.nLabelTargets = double(size(labels,2));
            if probe.hasLabels, probe.labelSummary = sprintf('%g label row(s) resolved',size(labels,1)); else, probe.labelSummary = 'not supplied'; end
            covars = NMDataIOUI.localFieldOr(IO,'covars',[]);
            probe.hasCovariates = ~isempty(covars);
            probe.nCovariates = double(size(covars,2));
            probe.caseIDMode = char(string(NMDataIOUI.localFieldOr(spec,'caseIDMode','')));
            if strcmp(probe.caseIDMode,'filename'), probe.caseIDModeName = 'Filename-derived case IDs';
            elseif strcmp(probe.caseIDMode,'explicit'), probe.caseIDModeName = 'Explicit case IDs';
            else, probe.caseIDModeName = probe.caseIDMode; end
            probe.labelMode = char(string(NMDataIOUI.localFieldOr(report,'labelMode',NMDataIOUI.localFieldOr(spec,'labelMode',''))));
            if strcmp(probe.labelMode,'legacy_groups'), probe.labelModeName = 'Implicit labels from class file lists';
            elseif strcmp(probe.labelMode,'metadata'), probe.labelModeName = 'Explicit labels from metadata';
            else, probe.labelModeName = probe.labelMode; end
            probe.auxiliaryAlignmentMode = char(string(NMDataIOUI.localFieldOr(report,'auxiliaryAlignmentMode',NMDataIOUI.localFieldOr(spec,'auxiliaryAlignmentMode',''))));
            if strcmp(probe.auxiliaryAlignmentMode,'case_id'), probe.auxiliaryAlignmentModeName = 'Case-ID mapping';
            elseif strcmp(probe.auxiliaryAlignmentMode,'row_order'), probe.auxiliaryAlignmentModeName = 'Explicit row order';
            else, probe.auxiliaryAlignmentModeName = probe.auxiliaryAlignmentMode; end
            groupNames = NMDataIOUI.localAsCellstr(NMDataIOUI.localFieldOr(report,'groupNames',{}));
            groupSizes = double(NMDataIOUI.localFieldOr(report,'groupSizes',[]));
            probe.groupSummary = '';
            if ~isempty(groupNames) && numel(groupNames) == numel(groupSizes)
                parts = cell(1,numel(groupNames));
                for gi = 1:numel(groupNames), parts{gi} = sprintf('%s: %g',groupNames{gi},groupSizes(gi)); end
                probe.groupSummary = strjoin(parts,', ');
            end
            probe.matrixType = char(string(NMDataIOUI.localFieldOr(prov,'matrixType','')));
            probe.triangle = char(string(NMDataIOUI.localFieldOr(prov,'triangle','')));
            probe.includeDiagonal = logical(NMDataIOUI.localFieldOr(prov,'includeDiagonal',false));
            probe.sidecarFile = char(string(NMDataIOUI.localFieldOr(prov,'atlasLabelFile','')));
            probe.atlasFile = char(string(NMDataIOUI.localFieldOr(prov,'atlasFile','')));
            probe.atlasLocalizationUsed = logical(NMDataIOUI.localFieldOr(prov,'atlasLocalizationUsed',false));
            loc = NMDataIOUI.localFieldOr(prov,'nodeLocalizationSummary',struct());
            probe.nOriginalNodes = double(NMDataIOUI.localFieldOr(prov,'originalNNodes',probe.nNodes));
            probe.nLocalizedNodes = double(NMDataIOUI.localFieldOr(loc,'nLocalized',probe.nNodes));
            probe.nDroppedNodes = double(NMDataIOUI.localFieldOr(loc,'nDropped',0));
            probe.coordinateSpace = char(string(NMDataIOUI.localFieldOr(prov,'nodeCoordinateSpace','')));
            probe.coordinateUnits = char(string(NMDataIOUI.localFieldOr(prov,'nodeCoordinateUnits','')));
            fileInfo = NMDataIOUI.localFieldOr(prov,'fileInfo',struct());
            sourceFiles = NMDataIOUI.localAsCellstr(NMDataIOUI.localFieldOr(fileInfo,'files',{}));
            probe.nSourceFiles = double(numel(sourceFiles));
            weight = NMDataIOUI.localFieldOr(prov,'weighting',struct());
            probe.hasWeightingMaps = logical(NMDataIOUI.localFieldOr(prov,'hasWeightingMaps',false));
            probe.nWeightingMaps = double(NMDataIOUI.localFieldOr(weight,'nWeightingMaps',0));
            sel = NMDataIOUI.localFieldOr(prov,'subspaceSelection',struct());
            probe.subspaceEnabled = logical(NMDataIOUI.localFieldOr(sel,'enabled',false));
            probe.subspaceSummary = '';
            if probe.subspaceEnabled
                probe.subspaceSummary = sprintf('%s: %g/%g edges retained',char(string(NMDataIOUI.localFieldOr(sel,'mode','selection'))), ...
                    double(NMDataIOUI.localFieldOr(sel,'nSelectedEdges',probe.nEdges)),double(NMDataIOUI.localFieldOr(sel,'nOriginalEdges',probe.nEdges)));
            end
            if isstruct(report), probe.importReport = report; end
        end


        function out = connectivityPreview(NM, state, opts)
            % connectivityPreview  Preview/QC a retained canonical connectivity materialization.
            if nargin < 3 || isempty(opts), opts=struct(); end
            progressTask=NMProgressTools.fromOptions(opts,'Preparing connectivity preview','Reading connectivity data and computing mandatory QC.');
            opts.ProgressTask=progressTask;
            [entry,cacheHit,cacheKey]=NMDataIOImportTools.materializeConnectivityImport(NM,state,opts);
            out=NMDataIOImportTools.emptyServiceOut('connectivityPreview');
            if NMDataIOMessageTools.hasFatal(entry.messages), out=NMDataIOImportTools.finishServiceOut(out,entry.messages); NMProgressTools.finish(progressTask,out.message); return; end
            progressTask=NMProgressTools.phase(progressTask,'connectivity_preview_rows',98,100,'Preparing the connectivity Preview table.');
            page=NMDataIOImportTools.opt(opts,'Page',1); pageSize=NMDataIOImportTools.opt(opts,'PageSize',30); maxCols=NMDataIOImportTools.opt(opts,'MaxColumns',20);
            [preview,~]=NMDataIOImportTools.previewFromIO(entry.IO,page,pageSize,maxCols);
            out=NMDataIOImportTools.finishServiceOut(out,entry.messages); out.preview=preview; out.probe=NMDataIOUI.enrichConnectivityProbe(entry.probe,entry.IO,entry.sourcePayload,entry.spec); out.qc=entry.qc; out.cacheHit=cacheHit; out.materializationCacheKey=cacheKey;
            out.statePatch=state; out.connectivity=entry.sourcePayload.importReport;
            NMProgressTools.finish(progressTask,out.message);
        end

        function out = connectivitySelectorPackage(NM, state)
            % CONNECTIVITYSELECTORPACKAGE  Prepare node/edge selector data for connectivity UI.
            %
            %   out = NMDataIOUI.connectivitySelectorPackage(NM, state) resolves the source
            %   connectivity payload and returns a browser package containing node labels,
            %   edge-selection metadata, preview matrices, and import diagnostics.
            out = NMDataIOImportTools.emptyServiceOut('connectivitySelectorPackage');
            try
                spec = NMDataIOStateTools.stateToConnectivitySpec(state, NM);
                [connOut, messages] = NMDataIOConnectivityTools.resolveConnectivityPayload(spec);
                if NMDataIOMessageTools.hasFatal(messages)
                    out = NMDataIOImportTools.finishServiceOut(out, messages);
                    out.selectorPackage = struct();
                    return;
                end
                prov = connOut.provenance;
                edgeIndex = double(NMDataIOUI.localFieldOr(prov, 'edgeIndex', []));
                nodeIDs = NMDataIOUI.localNumericVector(NMDataIOUI.localFieldOr(prov, 'nodeIDs', []));
                nodeLabels = NMDataIOUI.localAsCellstr(NMDataIOUI.localFieldOr(prov, 'nodeLabels', {}));
                edgeNames = NMDataIOUI.localAsCellstr(NMDataIOUI.localFieldOr(prov, 'edgeNames', NMDataIOUI.localFieldOr(connOut, 'featnames', {})));
                nNodes = double(NMDataIOUI.localFieldOr(prov, 'nNodes', numel(nodeIDs)));
                if isempty(nodeIDs) && nNodes > 0, nodeIDs = 1:nNodes; end
                if isempty(nodeLabels) && nNodes > 0
                    nodeLabels = arrayfun(@(id)sprintf('ROI_%g', id), nodeIDs, 'UniformOutput', false);
                end
                if isempty(edgeIndex) || size(edgeIndex,2) ~= 2 || numel(nodeLabels) ~= nNodes || numel(nodeIDs) ~= nNodes
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'NMDataIOUI.connectivitySelectorPackage', ...
                        'Connectivity node selector requires loaded ROI nodes, ROI labels, and edge definitions.', 1, 'red*')];
                    out = NMDataIOImportTools.finishServiceOut(out, messages);
                    out.selectorPackage = struct();
                    return;
                end
                if size(connOut.Y,2) ~= size(edgeIndex,1)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'NMDataIOUI.connectivitySelectorPackage', ...
                        sprintf('The connectivity node selector cannot be prepared because the data contain %g edge columns but the edge definition contains %g rows.', size(connOut.Y,2), size(edgeIndex,1)), 1, 'red*')];
                    out = NMDataIOImportTools.finishServiceOut(out, messages);
                    out.selectorPackage = struct();
                    return;
                end
                Y = double(connOut.Y);
                edgeMean = nan(1, size(Y,2));
                for ei = 1:size(Y,2)
                    v = Y(:,ei);
                    v = v(isfinite(v));
                    if ~isempty(v), edgeMean(ei) = mean(v); end
                end
                nodeTable = NMDataIOUI.localFieldOr(prov, 'nodeTable', table());
                metaColumns = {};
                metaText = cell(nNodes,0);
                if istable(nodeTable) && height(nodeTable) == nNodes
                    metaColumns = nodeTable.Properties.VariableNames;
                    metaText = cell(nNodes, numel(metaColumns));
                    for ci = 1:numel(metaColumns)
                        colText = NMDataIOUI.localTableColumnText(nodeTable.(metaColumns{ci}));
                        if numel(colText) == nNodes
                            metaText(:,ci) = colText(:);
                        else
                            metaText(:,ci) = repmat({''}, nNodes, 1);
                        end
                    end
                end
                pkg = struct();
                pkg.nodeIDs = nodeIDs(:)';
                pkg.nodeLabels = nodeLabels(:)';
                pkg.nodeMetadataColumns = metaColumns(:)';
                pkg.nodeMetadataText = metaText;
                % Connectivity selector arrays cross the JSON bridge as bounded numeric
                % plotting payloads under NMConfigTools.allowBrowserJsonNumericArray.
                pkg.edgeIndex = edgeIndex;
                                pkg.edgeNames = edgeNames(:)';
                pkg.edgeMean = edgeMean(:)';
                pkg.nNodes = nNodes;
                pkg.nEdges = size(edgeIndex,1);
                pkg.nCases = size(connOut.Y,1);
                pkg.matrixType = char(string(NMDataIOUI.localFieldOr(prov, 'matrixType', NMDataIOUI.localFieldOr(spec, 'matrixType', 'undirected'))));
                pkg.includeDiagonal = NMDataIOUI.localLogicalScalar(NMDataIOUI.localFieldOr(prov, 'includeDiagonal', NMDataIOUI.localFieldOr(spec, 'includeDiagonal', false)));
                pkg.valueLabel = 'group mean connection strength';
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'NMDataIOUI.connectivitySelectorPackage', ...
                    sprintf('Prepared the connectivity node selector for %g node(s), %g edge(s), and %g case(s).', nNodes, size(edgeIndex,1), size(connOut.Y,1)), 0, 'green*')];
                out = NMDataIOImportTools.finishServiceOut(out, messages);
                out.selectorPackage = pkg;
            catch ME
                messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.connectivitySelectorPackage');
                out = NMDataIOImportTools.finishServiceOut(out, messages);
                out.selectorPackage = struct();
            end
        end

        function out = connectivityQCGroupViewer(NM, state, opts)
            % connectivityQCGroupViewer  Build group QC from the aligned retained Preview materialization.
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            out = NMDataIOImportTools.emptyServiceOut('connectivityQCGroupViewer');
            cacheKey = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(opts, 'MaterializationCacheKey', ''));
            identityState = NMDataIOImportTools.materializationIdentityState(NM,state);
            [cacheHit, entry] = NMDataIOMaterializationCache.get('connectivity', identityState, cacheKey);
            if ~cacheHit || ~isstruct(entry) || ~isfield(entry,'IO') || ~isstruct(entry.IO)
                messages = NMDataIOMessageTools.make('danger', true, 'NMDataIOUI.connectivityQCGroupViewer', ...
                    'Run Preview before opening connectivity QC.', 1, 'red*');
                out = NMDataIOImportTools.finishServiceOut(out, messages);
                out.viewerPackage = struct();
                return;
            end
            try
                pkg = NMDataIOUI.connectivityMatrixViewerPackage(entry.IO, entry.qc, opts, []);
                messages = NMDataIOMessageTools.make('ok', false, 'NMDataIOUI.connectivityQCGroupViewer', ...
                    sprintf('Prepared group-level connectivity QC viewer for %g aligned case(s), %g ROI node(s), and %g retained edge(s).', size(entry.IO.Y,1), pkg.nNodes, pkg.nEdges), 0, 'green*');
                out = NMDataIOImportTools.finishServiceOut(out, messages);
                out.viewerPackage = pkg;
            catch ME
                messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.connectivityQCGroupViewer');
                out = NMDataIOImportTools.finishServiceOut(out, messages);
                out.viewerPackage = struct();
            end
        end

        function out = connectivityQCSubjectViewer(NM, state, opts)
            % connectivityQCSubjectViewer  Build subject QC from the aligned retained Preview materialization.
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            out = NMDataIOImportTools.emptyServiceOut('connectivityQCSubjectViewer');
            cacheKey = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(opts, 'MaterializationCacheKey', ''));
            identityState = NMDataIOImportTools.materializationIdentityState(NM,state);
            [cacheHit, entry] = NMDataIOMaterializationCache.get('connectivity', identityState, cacheKey);
            if ~cacheHit || ~isstruct(entry) || ~isfield(entry,'IO') || ~isstruct(entry.IO)
                messages = NMDataIOMessageTools.make('danger', true, 'NMDataIOUI.connectivityQCSubjectViewer', ...
                    'Run Preview before opening connectivity QC.', 1, 'red*');
                out = NMDataIOImportTools.finishServiceOut(out, messages);
                out.viewerPackage = struct();
                return;
            end
            try
                rowIndex = round(double(NMDataIOUI.localFieldOr(opts, 'rowIndex', 1)));
                messages = NMDataIOMessageTools.emptyMessages();
                nRows = size(entry.IO.Y,1);
                if ~isfinite(rowIndex) || rowIndex < 1 || rowIndex > nRows
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'NMDataIOUI.connectivityQCSubjectViewer.row', ...
                        sprintf('Requested connectivity QC case row %g is outside the aligned Preview range 1..%g.', rowIndex, nRows), 1, 'red*')];
                    out = NMDataIOImportTools.finishServiceOut(out, messages);
                    out.viewerPackage = struct();
                    return;
                end
                pkg = NMDataIOUI.connectivityMatrixViewerPackage(entry.IO, entry.qc, opts, rowIndex);
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'NMDataIOUI.connectivityQCSubjectViewer', ...
                    sprintf('Prepared subject-level connectivity QC viewer for aligned row %g (%s).', rowIndex, pkg.caseId), 0, 'green*')];
                out = NMDataIOImportTools.finishServiceOut(out, messages);
                out.viewerPackage = pkg;
            catch ME
                messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOUI.connectivityQCSubjectViewer');
                out = NMDataIOImportTools.finishServiceOut(out, messages);
                out.viewerPackage = struct();
            end
        end

        function pkg = connectivityMatrixViewerPackage(IO, qc, opts, rowIndex)
            % CONNECTIVITYMATRIXVIEWERPACKAGE  Build connectivity QC matrices from retained QC statistics.
            % Case-indexed subject values and Case IDs come from aligned IO. Edge identity and
            % group moments come from the mandatory QC object computed once during Preview.
            if nargin < 2 || isempty(qc), qc = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            if nargin < 4, rowIndex = []; end
            if ~isstruct(IO) || ~isfield(IO,'Y') || ~isnumeric(IO.Y) || isempty(IO.Y)
                error('NMDataIOUI:connectivityViewerDataUnavailable', ...
                    'Connectivity QC requires the aligned numeric Preview matrix. Run Preview again.');
            end
            if ~isstruct(qc) || ~isfield(qc,'connectivity') || ~isstruct(qc.connectivity)
                error('NMDataIOUI:connectivityViewerQCUnavailable', ...
                    'Connectivity QC statistics are not available from the retained Preview. Run Preview again.');
            end
            Y = IO.Y;
            if ~isa(Y,'double'), Y = double(Y); end
            connQC = qc.connectivity;
            edgeIndex = connQC.edgeIndex;
            if isempty(edgeIndex) || size(edgeIndex,2) ~= 2 || size(edgeIndex,1) ~= size(Y,2)
                error('NMDataIOUI:connectivityViewerEdgeMismatch', ...
                    'Connectivity QC cannot be displayed because the retained edge definition does not match the prepared Preview features. Run Preview again.');
            end
            nNodes = connQC.nNodes;
            nodeLabels = connQC.nodeLabels;
            if numel(nodeLabels) ~= nNodes
                error('NMDataIOUI:connectivityViewerNodeLabels', 'Retained node labels do not match the prepared QC node axis.');
            end
            nodeIDs = connQC.nodeIDs;
            if numel(nodeIDs) ~= nNodes
                error('NMDataIOUI:connectivityViewerNodeIDs', 'Retained node IDs do not match the prepared QC node axis.');
            end
            edgeNames = connQC.edgeNames;
            if numel(edgeNames) ~= size(edgeIndex,1)
                error('NMDataIOUI:connectivityViewerFeatureNames', ...
                    'Connectivity QC cannot be displayed because the retained QC feature names do not match the retained edge definition. Run Preview again.');
            end
            caseIds = NMDataIOUI.localAsCellstr(NMDataIOUI.localFieldOr(IO, 'ID', {}));
            if numel(caseIds) ~= size(Y,1)
                error('NMDataIOUI:connectivityViewerCaseIds', ...
                    'Connectivity QC cannot be displayed because the prepared Preview Case IDs do not match the aligned data rows. Run Preview again.');
            end
            matrixType = connQC.matrixType;
            meanVec = connQC.edgeMean;
            sdVec = connQC.edgeSD;
            missingVec = connQC.edgeMissingRate;
            if numel(meanVec) ~= size(edgeIndex,1) || numel(sdVec) ~= size(edgeIndex,1) || numel(missingVec) ~= size(edgeIndex,1)
                error('NMDataIOUI:connectivityViewerMoments', ...
                    'Connectivity QC cannot be displayed because retained group edge statistics are incomplete. Run Preview again.');
            end
            pkg = struct();
            pkg.schemaVersion = 1;
            pkg.viewerKind = 'connectivity_qc_matrix';
            pkg.mode = 'group';
            pkg.metricKey = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(opts, 'metricKey', 'group_mean'));
            pkg.nSubjects = size(Y,1);
            pkg.nNodes = double(nNodes);
            pkg.nEdges = size(edgeIndex,1);
            pkg.matrixType = matrixType;
            reuseStaticMetadata = NMDataIOUI.localLogicalScalar(NMDataIOUI.localFieldOr(opts, 'reuseStaticMetadata', false));
            if ~reuseStaticMetadata
                pkg.nodeIDs = nodeIDs(:)';
                pkg.nodeLabels = nodeLabels(:)';
                pkg.edgeIndex = edgeIndex;
                pkg.includeDiagonal = connQC.includeDiagonal;
                pkg.edgeMean = meanVec(:)';
                pkg.edgeSD = sdVec(:)';
                pkg.edgeMissingRate = missingVec(:)';
                pkg.edgeSpaceQC = connQC.edgeSpaceQC;
            end
            matrixOpts = struct('matrixType',matrixType);
            if isempty(rowIndex)
                pkg.groupMeanMatrix = NMDataIOConnectivityTools.edgeVectorToMatrix(meanVec, edgeIndex, nNodes, matrixOpts);
                pkg.groupSDMatrix = NMDataIOConnectivityTools.edgeVectorToMatrix(sdVec, edgeIndex, nNodes, matrixOpts);
                pkg.groupMissingRateMatrix = NMDataIOConnectivityTools.edgeVectorToMatrix(missingVec, edgeIndex, nNodes, matrixOpts);
                pkg.caseId = '';
                pkg.rowIndex = NaN;
                return;
            end
            rowIndex = round(double(rowIndex));
            if ~isfinite(rowIndex) || rowIndex < 1 || rowIndex > size(Y,1)
                error('NMDataIOUI:connectivityViewerRow', ...
                    'The requested connectivity QC row is outside the aligned Preview case axis.');
            end
            x = Y(rowIndex,:);
            pkg.mode = 'subject';
            pkg.rowIndex = double(rowIndex);
            pkg.caseId = caseIds{rowIndex};
            pkg.subjectEdgeValues = x(:)';
            rmsZ = qc.rmsZ;
            meanAbsZ = qc.meanAbsZ;
            maxAbsZ = qc.maxAbsZ;
            missingRate = qc.missingFeatureRateBySubject;
            nFinite = qc.nFiniteFeaturesBySubject;
            pkg.subjectQC = struct('rmsZ',NaN,'meanAbsZ',NaN,'maxAbsZ',NaN,'missingEdgeRate',NaN,'nValidEdges',NaN);
            if numel(rmsZ) >= rowIndex, pkg.subjectQC.rmsZ = rmsZ(rowIndex); end
            if numel(meanAbsZ) >= rowIndex, pkg.subjectQC.meanAbsZ = meanAbsZ(rowIndex); end
            if numel(maxAbsZ) >= rowIndex, pkg.subjectQC.maxAbsZ = maxAbsZ(rowIndex); end
            if numel(missingRate) >= rowIndex, pkg.subjectQC.missingEdgeRate = missingRate(rowIndex); end
            if numel(nFinite) >= rowIndex, pkg.subjectQC.nValidEdges = nFinite(rowIndex); end
        end

        function metrics = connectivityViewerMetricList()
            % CONNECTIVITYVIEWERMETRICLIST  Return supported connectivity QC viewer metrics.
            %
            %   metrics = NMDataIOUI.connectivityViewerMetricList() defines metric keys, labels,
            %   group/subject level, and display scale semantics used by the connectivity viewer.
            metrics = struct('key',{},'label',{},'level',{},'scale',{});
            metrics(end+1) = struct('key','group_mean','label','Group mean connectivity','level','group','scale','signed');
            metrics(end+1) = struct('key','group_sd','label','Group SD','level','group','scale','sequential');
            metrics(end+1) = struct('key','group_missing_rate','label','Group missing-rate','level','group','scale','rate');
            metrics(end+1) = struct('key','subject_value','label','Subject connectivity','level','subject','scale','signed');
            metrics(end+1) = struct('key','subject_z','label','Subject z-score vs group','level','subject','scale','signed');
            metrics(end+1) = struct('key','subject_abs_z','label','Subject |z| vs group','level','subject','scale','sequential');
            metrics(end+1) = struct('key','subject_missing','label','Subject missing-edge mask','level','subject','scale','rate');
        end

        function result = commitROIImport(NM,state,opts)
            if nargin < 3 || isempty(opts), opts=struct(); end
            progressTask=NMProgressTools.fromOptions(opts,'Committing ROI import','Checking the current ROI Preview data.'); opts.ProgressTask=progressTask;
            cacheKeyHint=NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(opts,'MaterializationCacheKey',''));
            opts.RequireRetainedMaterialization=logical(NMDataIOUI.localFieldOr(opts,'RequireRetainedMaterialization',~isempty(cacheKeyHint)));
            [entry,cacheHit]=NMDataIOImportTools.materializeROIImport(NM,state,opts);
            if NMDataIOMessageTools.hasFatal(entry.messages)
                result=NMDataIOImportTools.emptyServiceOut('commitROIImport'); result=NMDataIOImportTools.finishServiceOut(result,entry.messages); result.NM=NM; return;
            end
            IO=entry.IO; IO.selCases=NMDataIOMaterializationCache.caseSelection(state,size(IO.Y,1));
            [result,~]=NMDataIOImportTools.commitMaterializedMatrixIO(NM,IO,entry.messages);
            if result.ok
                [roiContainer,roiMessages]=NMDataIOImportTargetTools.getContainer(result.NM,result.importTarget);
                if NMDataIOMessageTools.hasFatal(roiMessages)
                    result=NMDataIOImportTools.finishServiceOut(result,[result.messages;roiMessages]);
                else
                    result.roiProvenance=roiContainer.datadescriptor{result.varind}.roiProvenance;
                    result.globalVolumeCorrection=roiContainer.datadescriptor{result.varind}.globalVolumeCorrection;
                    result.roiImportReport=entry.sourcePayload.importReport;
                end
            end
            result.qc=entry.qc; result.cacheHit=cacheHit;
            if result.ok, NMDataIOMaterializationCache.clearFamily('roi'); end
            NMProgressTools.finish(progressTask,result.message);
        end

        function result = commitConnectivityImport(NM,state,opts)
            if nargin < 3 || isempty(opts), opts=struct(); end
            progressTask=NMProgressTools.fromOptions(opts,'Committing connectivity import','Checking the current connectivity Preview data.'); opts.ProgressTask=progressTask;
            cacheKeyHint=NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(opts,'MaterializationCacheKey',''));
            opts.RequireRetainedMaterialization=logical(NMDataIOUI.localFieldOr(opts,'RequireRetainedMaterialization',~isempty(cacheKeyHint)));
            [entry,cacheHit]=NMDataIOImportTools.materializeConnectivityImport(NM,state,opts);
            if NMDataIOMessageTools.hasFatal(entry.messages)
                result=NMDataIOImportTools.emptyServiceOut('commitConnectivityImport'); result=NMDataIOImportTools.finishServiceOut(result,entry.messages); result.NM=NM; return;
            end
            IO=entry.IO; IO.selCases=NMDataIOMaterializationCache.caseSelection(state,size(IO.Y,1));
            [result,~]=NMDataIOImportTools.commitMaterializedMatrixIO(NM,IO,entry.messages);
            if result.ok
                result.connectivity=entry.sourcePayload.provenance;
                result.connectivityImportReport=entry.sourcePayload.importReport;
                if isstruct(entry.compatibility) && ~isempty(fieldnames(entry.compatibility)), result.connectivityCompatibility=entry.compatibility; end
            end
            result.qc=entry.qc; result.cacheHit=cacheHit;
            if result.ok, NMDataIOMaterializationCache.clearFamily('connectivity'); end
            NMProgressTools.finish(progressTask,result.message);
        end

        function artifacts = inspectionArtifactsState(NM)
            % INSPECTIONARTIFACTSSTATE  Summarize persisted preview/QC artifacts for all modalities.
            %
            %   artifacts = NMDataIOUI.inspectionArtifactsState(NM) returns fixed-schema artifact
            %   summaries used by the browser diagnostics and inspection panels. It does not
            %   compute new QC data.
            template = NMDataIOUI.inspectionArtifactTemplate();
            n = 0;
            if isstruct(NM) && isfield(NM,'datadescriptor') && iscell(NM.datadescriptor), n = numel(NM.datadescriptor); end
            if n <= 0
                artifacts = repmat(template, 0, 1);
                return;
            end
            artifacts = repmat(template, n, 1);
            for ii = 1:n
                art = NMDataIOUI.persistedInspectionArtifactSummary(NM, ii);
                artifacts(ii,1) = orderfields(art, template);
            end
        end

        function art = inspectionArtifactTemplate()
            % INSPECTIONARTIFACTTEMPLATE  Return an empty fixed-schema inspection artifact summary.
            %
            %   art = NMDataIOUI.inspectionArtifactTemplate() defines the browser-facing fields
            %   for persisted preview/QC/report availability, labels, target scope, and metadata.
            art = struct('modalityIndex', NaN, 'hasPreview', false, 'hasQC', false, 'hasQCReport', false, ...
                'hasQCSidecar', false, 'hasQCViewerCache', false, 'previewRows', 0, 'previewTotalRows', 0, 'previewGeneratedAt', '', 'previewError', '', ...
                'qcSummary', struct(), 'qcSavedAt', '', 'qcSidecarRoot', '', 'qcSidecarFile', '', ...
                'qcSidecarRelPath', '', 'qcCacheDurability', '', 'qcCacheStatus', '');
        end

        function state = attachPersistedInspectionToImportState(NM, state, varind, tmpDir)
            % attachPersistedInspectionToImportState  Attach cached inspection artifacts to state.
            %
            % state = NMDataIOUI.attachPersistedInspectionToImportState(NM, state, varind,
            % tmpDir) adds persisted preview/QC/report summaries for the selected modality so
            % the browser can restore inspection panels without recomputing artifacts.
            %
            % state.matrix: carries the matrix value between browser/API state and legacy NeuroMiner structures.
            % state.messages: carries the messages value between browser/API state and legacy NeuroMiner structures.
            % state.persistedInspection: carries the persisted inspection value between browser/API state and legacy NeuroMiner structures.
            % state.persistedQC: carries the persisted qc value between browser/API state and legacy NeuroMiner structures.
            % state.preview: stores the latest non-committing preview/probe payload associated with the browser state.
            % state.varind: selects the active modality index represented by the browser/API state.
            if nargin < 2 || ~isstruct(state), state = struct(); end
            % Rehydration is authoritative for the supplied NM container: discard any
            % derived inspection payload already carried by a pre-transition state.
            if isfield(state,'preview'), state = rmfield(state,'preview'); end
            if isfield(state,'persistedQC'), state = rmfield(state,'persistedQC'); end
            if isfield(state,'matrix') && isstruct(state.matrix) && isfield(state.matrix,'preview')
                state.matrix = rmfield(state.matrix,'preview');
            end
            if nargin < 4, tmpDir = ''; end
            if nargin < 3 || isempty(varind) || ~isfinite(double(varind))
                if isfield(state,'varind') && ~isempty(state.varind), varind = state.varind; else, varind = NaN; end
            end
            varind = round(double(varind));
            if ~isfinite(varind) || varind < 1, return; end
            target = NMDataIOImportTargetTools.normalize(NM, state, varind);
            art = NMDataIOUI.persistedInspectionArtifactSummaryForTarget(NM, target, varind);
            state.persistedInspection = art;
            dd = NMDataIOUI.localDescriptorForTarget(NM, target, varind);
            if isstruct(dd) && isfield(dd,'input_settings') && isstruct(dd.input_settings) && isfield(dd.input_settings,'preview') && isstruct(dd.input_settings.preview)
                state.preview = NMDataIOUI.previewForBrowser(dd.input_settings.preview, 1, 30);
                if isfield(state,'matrix') && isstruct(state.matrix), state.matrix.preview = state.preview; end
            end
            if isstruct(dd) && isfield(dd,'QC') && isstruct(dd.QC)
                qcObj = dd.QC;
                if isfield(qcObj,'payload') && isstruct(qcObj.payload)
                    [qcObj.payload, cacheMessages] = NMDataIOFeatureQCTools.rehydrateViewerOverlayCache(qcObj.payload, tmpDir);
                    if ~isempty(cacheMessages)
                        if ~isfield(state,'messages') || ~iscell(state.messages), state.messages = {}; end
                        for mi = 1:numel(cacheMessages)
                            if isfield(cacheMessages(mi),'text') && ~isempty(cacheMessages(mi).text)
                                state.messages{end+1} = cacheMessages(mi).text; %#ok<AGROW>
                            end
                        end
                    end
                    qcObj.payload = NMDataIOFeatureQCTools.prepareQCForBrowser(qcObj.payload, struct());
                end
                state.persistedQC = qcObj;
            end
        end

        function art = persistedInspectionArtifactSummary(NM, varind)
            % PERSISTEDINSPECTIONARTIFACTSUMMARY  Summarize cached artifacts for one modality.
            %
            %   art = NMDataIOUI.persistedInspectionArtifactSummary(NM, varind) inspects the
            %   modality descriptor and returns browser-ready flags and summaries for preview,
            %   QC payloads, viewer caches, reports, and QC sidecar export paths.
            art = NMDataIOUI.inspectionArtifactTemplate();
            art.modalityIndex = double(varind);
            dd = NMDataIOUI.localDescriptor(NM, varind);
            if ~isstruct(dd), return; end
            if isfield(dd,'input_settings') && isstruct(dd.input_settings) && isfield(dd.input_settings,'preview') && isstruct(dd.input_settings.preview)
                art.hasPreview = true;
                p = dd.input_settings.preview;
                if isfield(p,'rowTable') && istable(p.rowTable)
                    art.previewRows = double(height(p.rowTable));
                elseif isfield(p,'rows') && isstruct(p.rows)
                    art.previewRows = double(numel(p.rows));
                elseif isfield(p,'rowIndex')
                    art.previewRows = double(numel(p.rowIndex));
                end
                if isfield(p,'nRows') && isnumeric(p.nRows) && isscalar(p.nRows), art.previewTotalRows = double(p.nRows); end
                if isfield(p,'generatedAt'), art.previewGeneratedAt = NMDataIOUI.localAsChar(p.generatedAt); end
            end
            if isfield(dd,'QC') && isstruct(dd.QC)
                art.hasQC = true;
                if isfield(dd.QC,'report') && isstruct(dd.QC.report) && ~isempty(fieldnames(dd.QC.report)), art.hasQCReport = true; end
                if isfield(dd.QC,'payload') && isstruct(dd.QC.payload)
                    q = dd.QC.payload;
                    qs = struct();
                    fields = {'featureSpace','method','scoreName','primaryScore','nSubjects','nFeatures','nValidFeatures','outlierZThreshold','qcCacheToken','qcCacheKind'};
                    for fi = 1:numel(fields)
                        f = fields{fi};
                        if isfield(q,f) && ~isempty(q.(f)), qs.(f) = q.(f); end
                    end
                    if isfield(q,'viewerOverlay') && isstruct(q.viewerOverlay)
                        vo = q.viewerOverlay;
                        overlayFields = {'cacheStatus','cacheDurability','persistedCacheKind','sidecarRoot','sidecarRelPath','sidecarAbsPath','persistedCacheFile','persistedCacheSavedAt'};
                        for oi = 1:numel(overlayFields)
                            f = overlayFields{oi};
                            if isfield(vo,f) && ~isempty(vo.(f)), qs.(f) = vo.(f); end
                        end
                        cacheFile = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(vo,'persistedCacheFile', NMDataIOUI.localFieldOr(vo,'sidecarAbsPath','')));
                        art.qcSidecarFile = cacheFile;
                        art.qcSidecarRoot = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(vo,'sidecarRoot',''));
                        art.qcSidecarRelPath = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(vo,'sidecarRelPath',''));
                        art.qcCacheDurability = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(vo,'cacheDurability',''));
                        art.qcCacheStatus = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(vo,'cacheStatus',''));
                        cacheToken = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(vo,'cacheToken', NMDataIOUI.localFieldOr(vo,'persistedCacheToken','')));
                        art.hasQCViewerCache = ~isempty(cacheToken) || ~isempty(cacheFile);
                        art.hasQCSidecar = ~isempty(cacheFile) && exist(cacheFile,'file') == 2;
                    end
                    art.qcSummary = qs;
                end
                if isfield(dd.QC,'savedAt'), art.qcSavedAt = NMDataIOUI.localAsChar(dd.QC.savedAt); end
            end
        end

        function preview = persistablePreviewArtifact(previewPayload)
            % PERSISTABLEPREVIEWARTIFACT  Persist a browser-safe, bounded DataIO preview artifact.
            %
            % Purpose and ownership:
            %   Stores already computed preview content only; it never rereads source data. Matrix,
            %   table, connectivity and ROI previews share one numeric-value transport contract:
            %   nested scalar cell rows. File-level image/surface previews use table-backed rows.
            %
            % Invariants / materialization:
            %   Preview row/column order and values are unchanged. Browser-roundtripped numeric
            %   matrices are restored to nested scalar rows before persistence so the generic JSON
            %   heavy-array filter cannot replace visible preview values during resume. Work is
            %   bounded by the preview page, not by full modality dimensionality.
            preview = NMConfigTools.charifyStrings(previewPayload);
            if ~isfield(preview,'type') || isempty(preview.type), preview.type = 'source_preview'; end
            preview.readOnly = true;
            if isfield(preview,'values') && (isnumeric(preview.values) || islogical(preview.values))
                preview.values = NMDataIOImportTools.matrixToNestedCell(preview.values);
            end
            if isfield(preview,'rows') && isstruct(preview.rows) && ~isempty(preview.rows)
                try
                    rowTable = struct2table(preview.rows(:), 'AsArray', true);
                    preview.rowTable = rowTable;
                    preview.rowStorage = 'table';
                    preview.rowStorageVersion = 1;
                    preview.nRows = double(height(rowTable));
                    preview.rows = struct([]);
                    preview.browserRowsStored = 0;
                catch ME
                    error('NMDataIOUI:previewRowTableConversionFailed', ...
                        'Could not save the Preview rows for later use: %s (%s)', ME.message, ME.identifier);
                end
            elseif isfield(preview,'rowTable') && istable(preview.rowTable)
                preview.rowStorage = 'table';
                preview.rowStorageVersion = 1;
                preview.nRows = double(height(preview.rowTable));
                preview.rows = struct([]);
                preview.browserRowsStored = 0;
            end
        end

        function browserPreview = previewForBrowser(preview, page, pageSize)
            % PREVIEWFORBROWSER  Project persisted preview state into the browser transport contract.
            %
            % Purpose and ownership:
            %   This is the persisted-preview MATLAB -> browser boundary. It pages table-backed
            %   file previews and ensures matrix-style numeric values use nested scalar rows before
            %   generic bridge serialization. It does not resolve or materialize source data.
            %
            % Invariants / compatibility:
            %   Scientific values and row/column order are preserved exactly. Numeric values from
            %   older persisted artifacts are normalized here so existing NM sessions rehydrate
            %   correctly without source rereading or a provenance-specific fallback.
            if nargin < 2 || isempty(page), page = 1; end
            if nargin < 3 || isempty(pageSize), pageSize = 30; end
            page = round(double(page));
            if ~isfinite(page) || page < 1, page = 1; end
            pageSize = round(double(pageSize));
            if ~isfinite(pageSize) || pageSize < 1, pageSize = 30; end
            pageSize = min(500, pageSize);
            browserPreview = preview;
            if isfield(preview,'values') && (isnumeric(preview.values) || islogical(preview.values))
                browserPreview.values = NMDataIOImportTools.matrixToNestedCell(preview.values);
            end
            if isfield(browserPreview,'rowTable'), browserPreview = rmfield(browserPreview,'rowTable'); end
            if isfield(browserPreview,'rowStorageVersion'), browserPreview = rmfield(browserPreview,'rowStorageVersion'); end
            if isfield(preview,'rowTable') && istable(preview.rowTable)
                n = height(preview.rowTable);
                first = min(n + 1, (page - 1) * pageSize + 1);
                last = min(n, first + pageSize - 1);
                if first <= n
                    rows = table2struct(preview.rowTable(first:last, :), 'ToScalar', false);
                else
                    rows = struct([]);
                end
                browserPreview.rows = rows;
                browserPreview.nRows = double(n);
                browserPreview.page = double(page);
                browserPreview.pageSize = double(pageSize);
                browserPreview.paged = true;
                browserPreview.persistedPreview = true;
                browserPreview.rowStorage = 'table';
                browserPreview.browserRowOffset = double(max(0, first - 1));
                browserPreview.browserRowsStored = double(numel(rows));
            elseif isfield(preview,'rows') && isstruct(preview.rows)
                rowsAll = preview.rows(:);
                n = double(numel(rowsAll));
                first = min(n + 1, (page - 1) * pageSize + 1);
                last = min(n, first + pageSize - 1);
                if first <= n, rows = rowsAll(first:last); else, rows = struct([]); end
                browserPreview.rows = rows;
                browserPreview.nRows = double(n);
                browserPreview.page = double(page);
                browserPreview.pageSize = double(pageSize);
                browserPreview.paged = n > pageSize;
                browserPreview.persistedPreview = true;
                browserPreview.browserRowOffset = double(max(0, first - 1));
                browserPreview.browserRowsStored = double(numel(rows));
            end
        end

        function dd = localDescriptor(NM, varind)
            % LOCALDESCRIPTOR  Read a modality descriptor from the training NM container.
            %
            %   dd = NMDataIOUI.localDescriptor(NM, varind) returns NM.datadescriptor{varind}
            %   when available, otherwise an empty struct. It is a public compatibility helper
            %   for UI/session code that needs descriptor-safe access.
            dd = struct();
            if isstruct(NM) && isfield(NM,'datadescriptor') && iscell(NM.datadescriptor) && numel(NM.datadescriptor) >= varind && isstruct(NM.datadescriptor{varind})
                dd = NM.datadescriptor{varind};
            end
        end

        function dd = localDescriptorForTarget(NM, target, varind)
            % LOCALDESCRIPTORFORTARGET  Read a descriptor from training or OOCV target scope.
            %
            %   dd = NMDataIOUI.localDescriptorForTarget(NM, target, varind) resolves the
            %   requested target container and returns the modality descriptor when present.
            dd = struct();
            if nargin < 3 || isempty(varind) || ~isfinite(double(varind)), return; end
            varind = round(double(varind));
            target = NMDataIOImportTargetTools.normalize(NM, target, varind);
            if NMDataIOImportTargetTools.isOOCV(target)
                [D, messages] = NMDataIOImportTargetTools.getContainer(NM, target);
                if NMDataIOMessageTools.hasFatal(messages) || ~isstruct(D) || ~isfield(D,'datadescriptor') || ~iscell(D.datadescriptor) || numel(D.datadescriptor) < varind
                    return;
                end
                if isstruct(D.datadescriptor{varind}), dd = D.datadescriptor{varind}; end
            else
                dd = NMDataIOUI.localDescriptor(NM, varind);
            end
        end

        function art = persistedInspectionArtifactSummaryForTarget(NM, target, varind)
            % PERSISTEDINSPECTIONARTIFACTSUMMARYFORTARGET  Summarize cached artifacts by target.
            %
            %   art = NMDataIOUI.persistedInspectionArtifactSummaryForTarget(NM, target, varind)
            %   builds the same browser artifact summary as the training helper, but resolves the
            %   descriptor from an explicit training/OOCV target container.
            target = NMDataIOImportTargetTools.normalize(NM, target, varind);
            if NMDataIOImportTargetTools.isOOCV(target)
                [D, messages] = NMDataIOImportTargetTools.getContainer(NM, target);
                if NMDataIOMessageTools.hasFatal(messages)
                    art = NMDataIOUI.inspectionArtifactTemplate();
                    art.modalityIndex = double(varind);
                    return;
                end
                art = NMDataIOUI.persistedInspectionArtifactSummary(D, varind);
            else
                art = NMDataIOUI.persistedInspectionArtifactSummary(NM, varind);
            end
        end

        function [NM, messages] = saveInspectionArtifactsToNM(NM, state, previewPayload, qcPayload, reportPayload, tmpDir, qcSidecarRoot)
            % SAVEINSPECTIONARTIFACTSTONM  Persist inspection artifacts at their producer boundary.
            %
            % Purpose and authority:
            %   Shared persistence authority used by successful Preview, Feature-QC, and QC-report
            %   producers. Browser controls do not own a second/manual save path. Successful Preview
            %   first persists the canonical source/role input contract through persistDraftInputSettings,
            %   then the selected training/OOCV descriptor receives the supplied artifact/cache fields.
            %
            % Scientific/state and materialization contract:
            %   QC case identity is aligned to the target descriptor before persistence. Heavy
            %   volumetric/surface viewer materialization is delegated to persistViewerOverlayCache;
            %   this function does not recompute QC, reread source data, atlases, or annotations.
            %   It is therefore safe at the producer boundary but is not an interactive QC producer.
            %
            % Failure semantics and side effects:
            %   Invalid target identity is blocking. Writes descriptor artifact metadata and may copy
            %   an already-computed QC viewer sidecar to its resumable location; callers save the NM
            %   session only after these diagnostics are non-fatal.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 6, tmpDir = ''; end
            if nargin < 7, qcSidecarRoot = ''; end
            varind = NMDataIOUI.artifactModalityIndex(NM, state);
            if ~isfinite(varind) || varind < 1
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'dataio.saveInspection.modality', ...
                    'Could not save Preview/QC information because the target modality could not be identified.', 1, 'red*')];
                return;
            end
            varind = round(double(varind));
            target = NMDataIOImportTargetTools.normalize(NM, state, varind);
            [D, targetMessages] = NMDataIOUI.inspectionTargetContainer(NM, target);
            messages = [messages; targetMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if ~isfield(D,'datadescriptor') || ~iscell(D.datadescriptor)
                D.datadescriptor = cell(1, varind);
            elseif numel(D.datadescriptor) < varind
                D.datadescriptor{varind} = [];
            end
            if isempty(D.datadescriptor{varind}) || ~isstruct(D.datadescriptor{varind})
                D.datadescriptor{varind} = struct();
            end
            if ~isfield(D.datadescriptor{varind},'input_settings') || ~isstruct(D.datadescriptor{varind}.input_settings)
                D.datadescriptor{varind}.input_settings = struct();
            end
            havePreview = isstruct(previewPayload) && ~isempty(fieldnames(previewPayload));
            if havePreview
                if NMDataIOUI.hasExplicitImportTarget(state)
                    [NM, inputSaved, inputMessage] = NMDataIOUI.persistDraftInputSettings(NM, state);
                    if ~inputSaved
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'dataio.saveInspection.inputSettings', ...
                            inputMessage, 1, 'red*')];
                        return;
                    end
                    [D, targetMessages] = NMDataIOUI.inspectionTargetContainer(NM, target);
                    messages = [messages; targetMessages];
                    if NMDataIOMessageTools.hasFatal(messages), return; end
                end
                preview = NMDataIOUI.persistablePreviewArtifact(previewPayload);
                preview.persistedAt = datestr(now, 30);
                preview.persistedBy = 'NMDataIOUI.saveInspectionArtifactsToNM';
                D.datadescriptor{varind}.input_settings.preview = preview;
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'dataio.saveInspection.preview', ...
                    sprintf('Saved the current DataIO Preview for %s modality %g.', NMDataIOUI.targetPathLabel(target), varind), 0, 'green*')];
            end
            haveQC = isstruct(qcPayload) && ~isempty(fieldnames(qcPayload));
            haveReport = isstruct(reportPayload) && ~isempty(fieldnames(reportPayload));
            if haveQC || haveReport
                if ~isfield(D.datadescriptor{varind},'QC') || ~isstruct(D.datadescriptor{varind}.QC)
                    D.datadescriptor{varind}.QC = struct();
                end
                if haveQC
                    [qcPayload, caseMessages] = NMDataIOUI.alignQCPayloadCaseIdsToTarget(D, varind, qcPayload, target);
                    messages = [messages; caseMessages];
                    sidecarOpts = struct('ModalityIndex', double(varind), 'Force', false, ...
                        'Scope', NMDataIOUI.targetScopeLabel(target), 'ContainerIndex', NMDataIOUI.targetContainerIndex(target));
                    [qcPayload, cacheMessages] = NMDataIOFeatureQCTools.persistViewerOverlayCache(qcPayload, tmpDir, qcSidecarRoot, sidecarOpts);
                    messages = [messages; cacheMessages];
                    if ~isempty(NMDataIOUI.localAsChar(qcSidecarRoot))
                        NM = NMDataIOUI.recordQCSidecarRoot(NM, qcSidecarRoot);
                    end
                    D.datadescriptor{varind}.QC.payload = qcPayload;
                    D.datadescriptor{varind}.QC.savedAt = datestr(now,30);
                    messages = [messages; NMDataIOMessageTools.make('ok', false, 'dataio.saveInspection.qc', ...
                        sprintf('Saved QC results for %s modality %g.', NMDataIOUI.targetPathLabel(target), varind), 0, 'green*')];
                end
                if haveReport
                    report = NMDataIOUI.normalizeQCReportReference(reportPayload);
                    if ~isempty(fieldnames(report))
                        D.datadescriptor{varind}.QC.report = report;
                        messages = [messages; NMDataIOMessageTools.make('ok', false, 'dataio.saveInspection.report', ...
                            sprintf('Saved QC report information for %s modality %g.', NMDataIOUI.targetPathLabel(target), varind), 0, 'green*')];
                    end
                end
            end
            NM = NMDataIOUI.setInspectionTargetContainer(NM, target, D);
            if isempty(messages)
                messages = [messages; NMDataIOMessageTools.make('info', false, 'dataio.saveInspection.noop', ...
                    'No new Preview, QC, or report information was supplied.', 0, 'blue')];
            end
        end

        function [qcPayload, messages] = alignQCPayloadCaseIdsToTarget(D, varind, qcPayload, target)
            % ALIGNQCPAYLOADCASEIDSTOTARGET  Align QC payload case IDs with a target descriptor.
            %
            %   [qcPayload, messages] = NMDataIOUI.alignQCPayloadCaseIdsToTarget(D, varind,
            %   qcPayload, target) compares QC payload case IDs with descriptor cases and returns
            %   a corrected payload or explicit diagnostics.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 4 || isempty(target), target = struct('scope','training'); end
            if ~isstruct(qcPayload) || ~isstruct(D) || ~isfield(D,'cases') || isempty(D.cases)
                return;
            end
            canonical = NMDataIOUI.localAsCellstr(D.cases);
            canonical = canonical(:);
            if isempty(canonical), return; end
            rawIds = NMDataIOUI.qcPayloadCaseIds(qcPayload);
            if isempty(rawIds), return; end
            rawIds = rawIds(:);
            n = numel(rawIds);
            if numel(canonical) ~= n
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'dataio.qc.caseIdAlign.size', ...
                    sprintf(['QC Case IDs were not aligned to %s because the numbers of cases differ ' ...
                    '(%d QC Case IDs vs. %d dataset Case IDs).'], NMDataIOUI.targetPathLabel(target), n, numel(canonical)), 2, 'orange')];
                return;
            end
            if numel(unique(canonical)) ~= n
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'dataio.qc.caseIdAlign.duplicates', ...
                    sprintf('QC Case IDs were not aligned because the Case IDs in %s are not unique.', NMDataIOUI.targetPathLabel(target)), 2, 'orange')];
                return;
            end
            if isequal(canonical(:), rawIds(:)), return; end
            qcPayload = NMDataIOUI.setQCPayloadCaseIds(qcPayload, canonical);
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'dataio.qc.caseIdAlign', ...
                sprintf('Aligned QC Case IDs to the dataset Case IDs for %s modality %d.', NMDataIOUI.targetPathLabel(target), round(double(varind))), 0, 'green')];
        end

        function ids = qcPayloadCaseIds(qcPayload)
            % QCPAYLOADCASEIDS  Extract case IDs from supported QC payload layouts.
            %
            %   ids = NMDataIOUI.qcPayloadCaseIds(qcPayload) reads case identifiers from common
            %   QC payload fields and returns a column cellstr, or an empty cell array if absent.
            ids = {};
            if ~isstruct(qcPayload), return; end
            if isfield(qcPayload,'caseIds') && ~isempty(qcPayload.caseIds)
                ids = NMDataIOUI.localAsCellstr(qcPayload.caseIds);
                ids = ids(:);
                return;
            end
            if isfield(qcPayload,'subjectStats') && isstruct(qcPayload.subjectStats) && ...
                    isfield(qcPayload.subjectStats,'caseIds') && ~isempty(qcPayload.subjectStats.caseIds)
                ids = NMDataIOUI.localAsCellstr(qcPayload.subjectStats.caseIds);
                ids = ids(:);
            end
        end

        function qcPayload = setQCPayloadCaseIds(qcPayload, ids)
            % SETQCPAYLOADCASEIDS  Write case IDs into supported QC payload layouts.
            %
            %   qcPayload = NMDataIOUI.setQCPayloadCaseIds(qcPayload, ids) updates recognized
            %   case-ID fields consistently while preserving unrelated QC payload content.
            ids = NMDataIOUI.localAsCellstr(ids);
            ids = ids(:);
            if ~isstruct(qcPayload), return; end
            if isfield(qcPayload,'caseIds') || ~isfield(qcPayload,'subjectStats') || ~isstruct(qcPayload.subjectStats)
                qcPayload.caseIds = ids;
            end
            if isfield(qcPayload,'subjectStats') && isstruct(qcPayload.subjectStats) && isfield(qcPayload.subjectStats,'caseIds')
                qcPayload.subjectStats.caseIds = ids;
            end
        end

        function [NM, messages, summary] = exportQCSidecarsFromNM(NM, modalityIndex, qcSidecarRoot, tmpDir, targetSpec)
            % EXPORTQCSIDECARSFROMNM  Export persisted QC payload/report sidecars for modalities.
            %
            %   [NM, messages, summary] = NMDataIOUI.exportQCSidecarsFromNM(...) writes QC
            %   sidecar files for selected descriptors, records the export root, and returns
            %   diagnostics plus a per-modality summary.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 4, tmpDir = ''; end
            if nargin < 5 || isempty(targetSpec), targetSpec = struct('scope','training'); end
            target = NMDataIOImportTargetTools.normalize(NM, targetSpec, 1);
            summary = struct('requested', modalityIndex, 'exported', 0, 'skipped', 0, ...
                'root', NMDataIOUI.localAsChar(qcSidecarRoot), 'scope', NMDataIOUI.targetScopeLabel(target), ...
                'containerIndex', NMDataIOUI.targetContainerIndex(target));
            qcSidecarRoot = NMDataIOUI.localAsChar(qcSidecarRoot);
            if isempty(qcSidecarRoot)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'dataio.qcSidecar.root', ...
                    'Select a writable folder for the exported QC data.', 1, 'red*')];
                return;
            end
            if exist(qcSidecarRoot,'dir') ~= 7
                [ok,msg] = mkdir(qcSidecarRoot);
                if ~ok
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'dataio.qcSidecar.mkdir', ...
                        sprintf('Could not create the QC-data folder %s: %s', qcSidecarRoot, msg), 1, 'red*')];
                    return;
                end
            end
            [D, targetMessages] = NMDataIOUI.inspectionTargetContainer(NM, target);
            messages = [messages; targetMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            indices = NMDataIOUI.resolveQCSidecarExportIndicesInContainer(D, modalityIndex);
            if isempty(indices)
                messages = [messages; NMDataIOMessageTools.make('warn', true, 'dataio.qcSidecar.empty', ...
                    sprintf('No %s modalities with QC data were available for export.', NMDataIOUI.targetPathLabel(target)), 1, 'orange')];
                return;
            end
            NM = NMDataIOUI.recordQCSidecarRoot(NM, qcSidecarRoot);
            for ii = 1:numel(indices)
                varind = indices(ii);
                if ~isfield(D,'datadescriptor') || ~iscell(D.datadescriptor) || numel(D.datadescriptor) < varind || ...
                        ~isstruct(D.datadescriptor{varind}) || ~isfield(D.datadescriptor{varind},'QC') || ...
                        ~isstruct(D.datadescriptor{varind}.QC) || ~isfield(D.datadescriptor{varind}.QC,'payload') || ...
                        ~isstruct(D.datadescriptor{varind}.QC.payload)
                    summary.skipped = summary.skipped + 1;
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'dataio.qcSidecar.skip', ...
                        sprintf('%s modality %g has no saved QC results and was skipped.', NMDataIOUI.targetPathLabel(target), varind), 2, 'orange')]; %#ok<AGROW>
                    continue;
                end
                qcPayload = D.datadescriptor{varind}.QC.payload;
                [qcPayload, caseMessages] = NMDataIOUI.alignQCPayloadCaseIdsToTarget(D, varind, qcPayload, target);
                messages = [messages; caseMessages]; %#ok<AGROW>
                sidecarOpts = struct('ModalityIndex', double(varind), 'Force', true, ...
                    'Scope', NMDataIOUI.targetScopeLabel(target), 'ContainerIndex', NMDataIOUI.targetContainerIndex(target));
                [qcPayload, cacheMessages] = NMDataIOFeatureQCTools.persistViewerOverlayCache(qcPayload, tmpDir, qcSidecarRoot, sidecarOpts);
                messages = [messages; cacheMessages]; %#ok<AGROW>
                D.datadescriptor{varind}.QC.payload = qcPayload;
                if isfield(qcPayload,'viewerOverlay') && isstruct(qcPayload.viewerOverlay) && ...
                        strcmpi(NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(qcPayload.viewerOverlay,'cacheStatus','')), 'available')
                    D.datadescriptor{varind}.QC.savedAt = datestr(now,30);
                    summary.exported = summary.exported + 1;
                else
                    summary.skipped = summary.skipped + 1;
                end
            end
            NM = NMDataIOUI.setInspectionTargetContainer(NM, target, D);
            if summary.exported > 0
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'dataio.qcSidecar.export', ...
                    sprintf('Exported QC data for %g %s modality/modalities to %s.', summary.exported, NMDataIOUI.targetPathLabel(target), qcSidecarRoot), 0, 'green*')];
            end
        end

        function indices = resolveQCSidecarExportIndices(NM, modalityIndex)
            % RESOLVEQCSIDECAREXPORTINDICES  Select training modalities for QC sidecar export.
            %
            %   indices = NMDataIOUI.resolveQCSidecarExportIndices(NM, modalityIndex) returns
            %   either a requested modality index or all training descriptors that contain
            %   persisted QC data.
            indices = NMDataIOUI.resolveQCSidecarExportIndicesInContainer(NM, modalityIndex);
        end

        function indices = resolveQCSidecarExportIndicesInContainer(D, modalityIndex)
            % RESOLVEQCSIDECAREXPORTINDICESINCONTAINER  Select QC-exportable descriptors in a container.
            %
            %   indices = NMDataIOUI.resolveQCSidecarExportIndicesInContainer(D, modalityIndex)
            %   applies the sidecar export selection logic to a descriptor container struct.
            n = 0;
            if isstruct(D) && isfield(D,'datadescriptor') && iscell(D.datadescriptor), n = numel(D.datadescriptor); end
            if n < 1
                indices = zeros(0,1);
                return;
            end
            if nargin < 2 || isempty(modalityIndex)
                modalityIndex = 'all';
            end
            if ischar(modalityIndex) || isstring(modalityIndex)
                txt = lower(strtrim(char(string(modalityIndex))));
                if strcmp(txt,'all')
                    tmp = zeros(n,1);
                    count = 0;
                    for ii = 1:n
                        if NMDataIOUI.descriptorHasQCViewerCache(D, ii)
                            count = count + 1;
                            tmp(count) = ii;
                        end
                    end
                    indices = tmp(1:count);
                    return;
                end
                val = str2double(txt);
            else
                val = double(modalityIndex);
                if ~isempty(val), val = val(1); else, val = NaN; end
            end
            val = round(double(val));
            if isfinite(val) && val >= 1 && val <= n && NMDataIOUI.descriptorHasQCViewerCache(D, val)
                indices = val;
            else
                indices = zeros(0,1);
            end
        end

        function tf = descriptorHasQCViewerCache(D, varind)
            % DESCRIPTORHASQCVIEWERCACHE  Test whether a descriptor has reusable QC viewer cache.
            %
            %   tf = NMDataIOUI.descriptorHasQCViewerCache(D, varind) checks recognized cache
            %   fields for browser QC viewer artifacts without recomputing QC metrics.
            tf = false;
            if ~isstruct(D) || ~isfield(D,'datadescriptor') || ~iscell(D.datadescriptor) || numel(D.datadescriptor) < varind
                return;
            end
            dd = D.datadescriptor{varind};
            if ~isstruct(dd) || ~isfield(dd,'QC') || ~isstruct(dd.QC) || ~isfield(dd.QC,'payload') || ~isstruct(dd.QC.payload)
                return;
            end
            q = dd.QC.payload;
            if ~isfield(q,'viewerOverlay') || ~isstruct(q.viewerOverlay), return; end
            token = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(q.viewerOverlay,'cacheToken', NMDataIOUI.localFieldOr(q.viewerOverlay,'persistedCacheToken','')));
            cacheFile = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(q.viewerOverlay,'persistedCacheFile', NMDataIOUI.localFieldOr(q.viewerOverlay,'sidecarAbsPath','')));
            tf = ~isempty(token) || ~isempty(cacheFile);
        end

        function [D, messages] = inspectionTargetContainer(NM, target)
            % INSPECTIONTARGETCONTAINER  Resolve the descriptor container for an inspection target.
            %
            %   [D, messages] = NMDataIOUI.inspectionTargetContainer(NM, target) returns the
            %   training NM container or an OOCV/application container plus diagnostics when the
            %   target cannot be resolved.
            messages = NMDataIOMessageTools.emptyMessages();
            target = NMDataIOImportTargetTools.normalize(NM, target);
            if NMDataIOImportTargetTools.isOOCV(target)
                [D, messages] = NMDataIOImportTargetTools.getContainer(NM, target);
            else
                D = NM;
            end
        end

        function NM = setInspectionTargetContainer(NM, target, D)
            % SETINSPECTIONTARGETCONTAINER  Write an updated descriptor container back into NM.
            %
            %   NM = NMDataIOUI.setInspectionTargetContainer(NM, target, D) stores training or
            %   OOCV/application descriptor changes after artifact persistence.
            target = NMDataIOImportTargetTools.normalize(NM, target);
            if NMDataIOImportTargetTools.isOOCV(target)
                NM = NMDataIOImportTargetTools.setContainer(NM, target, D);
            else
                NM = D;
            end
        end

        function label = targetPathLabel(target)
            % TARGETPATHLABEL  Return a human-readable path label for an inspection target.
            %
            %   label = NMDataIOUI.targetPathLabel(target) formats training/OOCV target location
            %   metadata for browser messages and exported artifact summaries.
            target = NMDataIOImportTargetTools.normalize(struct(), target);
            if NMDataIOImportTargetTools.isOOCV(target)
                label = sprintf('NM.%s{%g}', target.containerField, double(target.containerIndex));
            else
                label = 'NM';
            end
        end

        function label = targetScopeLabel(target)
            % TARGETSCOPELABEL  Return the display label for an inspection target scope.
            %
            %   label = NMDataIOUI.targetScopeLabel(target) converts target scope metadata into
            %   concise user-facing labels such as training or OOCV/application.
            target = NMDataIOImportTargetTools.normalize(struct(), target);
            if NMDataIOImportTargetTools.isOOCV(target), label = 'oocv'; else, label = 'training'; end
        end

        function idx = targetContainerIndex(target)
            % TARGETCONTAINERINDEX  Extract the container index from an inspection target.
            %
            %   idx = NMDataIOUI.targetContainerIndex(target) returns a finite rounded index for
            %   target containers such as OOCV sets, or NaN when no valid index is present.
            idx = NaN;
            if isstruct(target) && isfield(target,'containerIndex') && ~isempty(target.containerIndex)
                raw = double(target.containerIndex);
                if ~isempty(raw) && isfinite(raw(1)), idx = round(raw(1)); end
            end
        end

        function target = qcSidecarExportTargetFromRequest(req)
            % qcSidecarExportTargetFromRequest  Decode QC sidecar export target metadata.
            %
            % target = NMDataIOUI.qcSidecarExportTargetFromRequest(req) extracts scope,
            % container index, and modality index fields from a browser service request.
            %
            % req.importTarget: carries the import target value from the browser/service request payload.
            % req.target: carries the target value from the browser/service request payload.
            target = struct('scope','training');
            if nargin < 1 || ~isstruct(req), return; end
            fields = {'scope','containerField','containerIndex','labels_known','description'};
            for ii = 1:numel(fields)
                f = fields{ii};
                if isfield(req,f) && ~isempty(req.(f)), target.(f) = req.(f); end
            end
            if isfield(req,'importTarget') && isstruct(req.importTarget)
                tgt = req.importTarget;
                for ii = 1:numel(fields)
                    f = fields{ii};
                    if isfield(tgt,f) && ~isempty(tgt.(f)), target.(f) = tgt.(f); end
                end
            elseif isfield(req,'target') && isstruct(req.target)
                tgt = req.target;
                for ii = 1:numel(fields)
                    f = fields{ii};
                    if isfield(tgt,f) && ~isempty(tgt.(f)), target.(f) = tgt.(f); end
                end
            end
        end

        function tf = modalityHasPersistedQC(NM, varind)
            % MODALITYHASPERSISTEDQC  Test whether a training modality has persisted QC payloads.
            %
            %   tf = NMDataIOUI.modalityHasPersistedQC(NM, varind) checks the selected training
            %   descriptor for cached QC payload/report fields.
            tf = false;
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || numel(NM.datadescriptor) < varind
                return;
            end
            dd = NM.datadescriptor{varind};
            tf = isstruct(dd) && isfield(dd,'QC') && isstruct(dd.QC) && isfield(dd.QC,'payload') && ...
                isstruct(dd.QC.payload) && ~isempty(fieldnames(dd.QC.payload));
        end

        function tf = modalityHasQCViewerCache(NM, varind)
            % MODALITYHASQCVIEWERCACHE  Test whether a training modality has QC viewer cache.
            %
            %   tf = NMDataIOUI.modalityHasQCViewerCache(NM, varind) checks the selected training
            %   descriptor for reusable browser QC viewer artifacts.
            tf = NMDataIOUI.descriptorHasQCViewerCache(NM, varind);
        end

        function NM = recordQCSidecarRoot(NM, qcSidecarRoot)
            % RECORDQCSIDECARROOT  Record the last QC sidecar export root in NM definitions.
            %
            %   NM = NMDataIOUI.recordQCSidecarRoot(NM, qcSidecarRoot) stores the root path in
            %   NM.defs for later browser/export defaults. It initializes NM.defs when needed.
            qcSidecarRoot = NMDataIOUI.localAsChar(qcSidecarRoot);
            if isempty(qcSidecarRoot), return; end
            if ~isfield(NM,'defs') || ~isstruct(NM.defs), NM.defs = struct(); end
            if ~isfield(NM.defs,'storage') || ~isstruct(NM.defs.storage), NM.defs.storage = struct(); end
            NM.defs.storage.qcSidecarRoot = qcSidecarRoot;
            NM.defs.storage.qcSidecarRootMode = 'user_selected';
            NM.defs.storage.qcSidecarUpdatedAt = datestr(now,30);
        end

        function varind = artifactModalityIndex(NM, state)
            % artifactModalityIndex  Resolve the modality index for artifact persistence.
            %
            % varind = NMDataIOUI.artifactModalityIndex(NM, state) extracts a valid target
            % modality from importTarget or falls back to state.varind when possible.
            %
            % state.importTarget: identifies whether the DataIO operation targets training, OOCV/application data, or a specific container.
            %
            % state.varind: preferred modality index for preview/QC artifact persistence before falling back to state.importTarget or NM defaults.
            varind = NaN;
            if isstruct(state) && isfield(state,'varind') && ~isempty(state.varind)
                varind = double(state.varind);
            end
            if (~isfinite(varind) || varind < 1) && isstruct(state) && isfield(state,'importTarget') && isstruct(state.importTarget) && ...
                    isfield(state.importTarget,'varind') && ~isempty(state.importTarget.varind)
                varind = double(state.importTarget.varind);
            end
            if (~isfinite(varind) || varind < 1)
                varind = NMDataIOStateTools.defaultVarind(NM);
            end
            varind = round(double(varind));
        end

        function [openedPath, messages] = openQCReportReference(report)
            % OPENQCREPORTREFERENCE  Open a persisted QC report reference through the OS shell.
            %
            %   [openedPath, messages] = NMDataIOUI.openQCReportReference(report) normalizes the
            %   report reference, validates file existence, opens it when possible, and returns
            %   explicit diagnostics.
            messages = NMDataIOMessageTools.emptyMessages();
            openedPath = '';
            if nargin < 1 || ~isstruct(report) || isempty(fieldnames(report))
                messages = [messages; NMDataIOMessageTools.make('warn', true, 'dataio.qcReportOpen.empty', ...
                    'No QC report reference was supplied.', 1, 'orange')];
                return;
            end
            candidates = { ...
                NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(report,'pdfPath', NMDataIOUI.localFieldOr(report,'pdfFile',''))), ...
                NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(report,'htmlPath', NMDataIOUI.localFieldOr(report,'htmlFile',''))), ...
                NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(report,'bundleDir',''))};
            for ci = 1:numel(candidates)
                candidate = candidates{ci};
                if isempty(candidate), continue; end
                if exist(candidate,'file') == 2 || exist(candidate,'dir') == 7
                    openedPath = candidate;
                    break;
                end
            end
            if isempty(openedPath)
                messages = [messages; NMDataIOMessageTools.make('warn', true, 'dataio.qcReportOpen.missingFile', ...
                    'The persisted QC report reference does not point to a readable file or directory.', 1, 'orange')];
                return;
            end
            web(openedPath, '-browser');
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'dataio.qcReportOpen.opened', ...
                sprintf('Opened QC report reference: %s', openedPath), 0, 'green*')];
        end

        function report = normalizeQCReportReference(src)
            % NORMALIZEQCREPORTREFERENCE  Normalize supported QC report reference layouts.
            %
            %   report = NMDataIOUI.normalizeQCReportReference(src) converts char/string/struct
            %   report metadata into a fixed schema containing path, type, label, and existence
            %   fields for browser display and opening.
            report = struct();
            if nargin < 1 || ~isstruct(src), return; end
            htmlPath = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(src,'htmlFile', NMDataIOUI.localFieldOr(src,'htmlPath','')));
            pdfPath = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(src,'pdfFile', NMDataIOUI.localFieldOr(src,'pdfPath','')));
            bundleDir = NMDataIOUI.localAsChar(NMDataIOUI.localFieldOr(src,'bundleDir',''));
            if ~isempty(htmlPath), report.htmlPath = htmlPath; end
            if ~isempty(pdfPath), report.pdfPath = pdfPath; end
            if ~isempty(bundleDir), report.bundleDir = bundleDir; end
            report.generatedAt = datestr(now, 30);
            report.source = 'NMDataIOQCReportTools.generateFromImportState';
        end

        function op = requestOperation(req)
            % requestOperation  Extract the requested browser service operation.
            %
            % op = NMDataIOUI.requestOperation(req) reads operation aliases from a request and
            % returns a normalized character operation key, or an empty string if absent.
            %
            % req.action: selects the requested service action in a UI bridge or runner dispatch request.
            % req.operation: selects the requested operation within an action family.
            op = '';
            if isstruct(req) && isfield(req,'operation') && ~isempty(req.operation)
                op = char(string(req.operation));
            elseif isstruct(req) && isfield(req,'action') && ~isempty(req.action)
                op = char(string(req.action));
            end
        end

        function txt = requestString(req, field, defaultValue)
            % REQUESTSTRING  Extract a string field from a browser service request.
            %
            %   txt = NMDataIOUI.requestString(req, field, defaultValue) returns the requested
            %   field as char text, falling back to defaultValue for missing or empty values.
            if nargin < 3, defaultValue = ''; end
            txt = defaultValue;
            if isstruct(req) && isfield(req, field) && ~isempty(req.(field))
                txt = char(string(req.(field)));
            end
        end

        function val = requestNumber(req, field, defaultValue)
            % REQUESTNUMBER  Extract a numeric scalar field from a browser service request.
            %
            %   val = NMDataIOUI.requestNumber(req, field, defaultValue) converts numeric or
            %   textual request values to double and returns the default when conversion fails.
            if nargin < 3, defaultValue = NaN; end
            val = defaultValue;
            if isstruct(req) && isfield(req, field) && ~isempty(req.(field))
                raw = req.(field);
                if ischar(raw) || isstring(raw)
                    tmp = str2double(char(string(raw)));
                else
                    tmp = double(raw);
                end
                if isscalar(tmp) && (isfinite(tmp) || isnan(defaultValue)), val = tmp; end
            end
        end

        function state = requestState(req)
            % REQUESTSTATE  Extract import state from a browser service request.
            %
            %   state = NMDataIOUI.requestState(req) returns req.state when present, otherwise
            %   reconstructs state from legacy top-level request fields used by older clients.
            state = struct();
            if ~isstruct(req), return; end
            candidates = {'state','importState','matrixState','config'};
            for i = 1:numel(candidates)
                if isfield(req, candidates{i}) && isstruct(req.(candidates{i}))
                    state = NMConfigTools.charifyStrings(req.(candidates{i}));
                    return;
                end
            end
        end


        function txt = requestTextField(req, names)
            % requestTextField  Return the first nonempty text value from request fields.
            %
            % txt = NMDataIOUI.requestTextField(req, names) scans field aliases in order and
            % returns the first nonempty char/string value as char text.
            %
            % req.extra: carries the extra value from the browser/service request payload.
            txt = '';
            if ~isstruct(req), return; end
            for i = 1:numel(names)
                nm = names{i};
                if isfield(req,nm) && ~isempty(req.(nm))
                    txt = char(string(req.(nm)));
                    return;
                end
            end
            if isfield(req,'extra') && isstruct(req.extra)
                for i = 1:numel(names)
                    nm = names{i};
                    if isfield(req.extra,nm) && ~isempty(req.extra.(nm))
                        txt = char(string(req.extra.(nm)));
                        return;
                    end
                end
            end
        end

        function varind = requestModalityIndex(req)
            % REQUESTMODALITYINDEX  Resolve a modality index from request or embedded state.
            %
            %   varind = NMDataIOUI.requestModalityIndex(req) checks direct request fields and
            %   state/importTarget aliases, returning a finite rounded modality index or NaN.
            varind = NaN;
            if ~isstruct(req), return; end
            candidates = {'modalityIndex','varind','index'};
            for i = 1:numel(candidates)
                if isfield(req, candidates{i}) && ~isempty(req.(candidates{i}))
                    v = req.(candidates{i});
                    if isnumeric(v) || islogical(v)
                        varind = double(v);
                    else
                        varind = str2double(char(string(v)));
                    end
                    return;
                end
            end
            st = NMDataIOUI.requestState(req);
            if isstruct(st) && isfield(st,'varind') && ~isempty(st.varind)
                if isnumeric(st.varind) || islogical(st.varind)
                    varind = double(st.varind);
                else
                    varind = str2double(char(string(st.varind)));
                end
            end
        end

        function idx = requestContainerIndex(req)
            % REQUESTCONTAINERINDEX  Resolve an OOCV/application container index from a request.
            %
            %   idx = NMDataIOUI.requestContainerIndex(req) reads direct and nested target fields
            %   and returns a finite rounded container index or NaN.
            idx = NaN;
            if ~isstruct(req), return; end
            candidates = {'containerIndex','oocvIndex','oocvind','datasetIndex'};
            for i = 1:numel(candidates)
                if isfield(req, candidates{i}) && ~isempty(req.(candidates{i}))
                    v = req.(candidates{i});
                    if isnumeric(v) || islogical(v)
                        idx = double(v);
                    else
                        idx = str2double(char(string(v)));
                    end
                    idx = max(1, round(idx));
                    return;
                end
            end
            st = NMDataIOUI.requestState(req);
            for i = 1:numel(candidates)
                if isstruct(st) && isfield(st, candidates{i}) && ~isempty(st.(candidates{i}))
                    v = st.(candidates{i});
                    if isnumeric(v) || islogical(v)
                        idx = double(v);
                    else
                        idx = str2double(char(string(v)));
                    end
                    idx = max(1, round(idx));
                    return;
                end
            end
            idx = 1;
        end

        function opts = previewOptions(req)
            % previewOptions  Extract preview pagination options from a service request.
            %
            % opts = NMDataIOUI.previewOptions(req) returns Page, PageSize, and MaxColumns
            % values using browser request aliases and conservative defaults.
            %
            % req.maxColumns: carries the max columns value from the browser/service request payload.
            % req.page: carries the page value from the browser/service request payload.
            % req.pageSize: carries the page size value from the browser/service request payload.
            % req.progressTaskId: carries the progress task id value from the browser/service request payload.
            opts = struct();
            if ~isstruct(req), return; end
            if isfield(req,'page'), opts.Page = req.page; end
            if isfield(req,'pageSize'), opts.PageSize = req.pageSize; end
            if isfield(req,'maxColumns'), opts.MaxColumns = req.maxColumns; end
            if isfield(req,'progressTaskId'), opts.ProgressTaskId = NMDataIOUI.requestString(req, 'progressTaskId', ''); end; if isfield(req,'materializationCacheKey'), opts.MaterializationCacheKey = NMDataIOUI.requestString(req, 'materializationCacheKey', ''); end
        end

        function [NM, saved, message] = persistDraftInputSettings(NM, state)
            % persistDraftInputSettings  Store meaningful incomplete import settings in NM.
            %
            % [NM, saved, message] = NMDataIOUI.persistDraftInputSettings(NM, state) converts
            % a browser import state to a draft IO contract and stores it in the selected
            % descriptor when the caller requests persistence of meaningful, uncommitted user input.
            %
            % state.importTarget: identifies whether the DataIO operation targets training, OOCV/application data, or a specific container.
            % state.varind: selects the active modality index represented by the browser/API state.
            saved = false;
            message = 'No unfinished import settings were saved.';
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || ~isstruct(state), return; end
            if ~NMDataIOUI.hasExplicitImportTarget(state)
                message = 'The unfinished import settings were not saved because no active modality import was selected.';
                return;
            end
            target = NMDataIOImportTargetTools.normalize(NM, state, state.importTarget.varind);
            targetMessages = NMDataIOImportTargetTools.validateForImport(NM, target);
            if NMDataIOMessageTools.hasFatal(targetMessages)
                strip = NMDataIOMessageTools.highestPriorityStrip(targetMessages, 'The unfinished import settings cannot be saved for this target.');
                message = strip.text;
                return;
            end
            varind = round(double(target.varind));
            if ~isfinite(varind) || varind < 1
                message = 'The unfinished import settings were not saved because the active modality number is invalid.';
                return;
            end
            state.varind = varind;
            state.importTarget = target;
            [D, targetMessages] = NMDataIOUI.inspectionTargetContainer(NM, target);
            if NMDataIOMessageTools.hasFatal(targetMessages)
                strip = NMDataIOMessageTools.highestPriorityStrip(targetMessages, 'The modality for these unfinished import settings could not be identified.');
                message = strip.text;
                return;
            end
            mode = lower(char(string(target.mode)));
            hasCommittedTarget = NMDataIOUI.hasCommittedFeatureData(D, varind);
            requiresRecommit = NMDataIOModalityMutationTools.requiresRecommit(D, varind);
            resumeModification = hasCommittedTarget && requiresRecommit && strcmp(mode, 'resume');
            if hasCommittedTarget && ~strcmp(mode, 'replace') && ~resumeModification
                message = sprintf('The unfinished import settings were not saved because modality %d is already complete. Choose Modify if you intend to change it.', varind);
                return;
            end
            if ~hasCommittedTarget && strcmp(mode, 'replace')
                message = sprintf('The unfinished import settings were not saved because modality %d has no completed feature data to modify. Use Resume or start a new import instead.', varind);
                return;
            end
            IO = NMDataIOStateTools.stateToIO(state, NM, varind);
            IO.importTarget = target;
            IO.varind = varind;
            IO.completed = false;
            IO.draft = true;
            if requiresRecommit || strcmp(mode,'replace'), IO.requiresRecommit = true; end
            IO.draftSavedAt = datestr(now, 30);
            IO.draftSource = 'NMDataIOUI';
            if ~NMDataIOUI.hasMeaningfulDraft(IO)
                return;
            end
            IO = NMDataIOUI.stripDraftInputSettings(IO);
            IO = NMDataIOImportTools.enrichInputSettingsFromIO(IO, IO);
            if ~isfield(D,'datadescriptor') || ~iscell(D.datadescriptor)
                D.datadescriptor = {};
            end
            while numel(D.datadescriptor) < varind
                D.datadescriptor{end+1} = struct(); %#ok<AGROW>
            end
            if isempty(D.datadescriptor{varind}) || ~isstruct(D.datadescriptor{varind})
                D.datadescriptor{varind} = struct();
            end
            if ~hasCommittedTarget
                dsDraft = '';
                stDraft = '';
                if isfield(IO,'datasource'), dsDraft = lower(char(string(IO.datasource))); end
                if isfield(IO,'sourceType'), stDraft = lower(char(string(IO.sourceType))); end
                if strcmp(stDraft,'connectivity') || (isfield(IO,'sourceFamily') && strcmpi(char(string(IO.sourceFamily)), 'connectivity'))
                    D.datadescriptor{varind}.type = 0;
                    D.datadescriptor{varind}.source = 'connectivity';
                elseif strcmp(dsDraft,'surf') || strcmp(stDraft,'surface-list')
                    D.datadescriptor{varind}.type = 2;
                    D.datadescriptor{varind}.source = 'image';
                elseif strcmp(stDraft,'image-list') || any(strcmp(dsDraft, {'nifti','spm','image'}))
                    D.datadescriptor{varind}.type = 0;
                    D.datadescriptor{varind}.source = 'image';
                else
                    D.datadescriptor{varind}.type = 0;
                    D.datadescriptor{varind}.source = 'matrix';
                end
                if isfield(IO,'desc_data') && ~isempty(IO.desc_data) && ~strcmp(char(IO.desc_data),'?')
                    D.datadescriptor{varind}.desc = char(IO.desc_data);
                elseif ~isfield(D.datadescriptor{varind},'desc') || isempty(D.datadescriptor{varind}.desc)
                    D.datadescriptor{varind}.desc = sprintf('Incomplete DataIO import %d', varind);
                end
                if ~isfield(D.datadescriptor{varind},'desc_label')
                    D.datadescriptor{varind}.desc_label = [];
                end
            end
            existingPreview = struct();
            haveExistingPreview = isfield(D.datadescriptor{varind},'input_settings') && isstruct(D.datadescriptor{varind}.input_settings) && ...
                isfield(D.datadescriptor{varind}.input_settings,'preview') && isstruct(D.datadescriptor{varind}.input_settings.preview);
            if haveExistingPreview
                existingPreview = D.datadescriptor{varind}.input_settings.preview;
            end
            IO.modalityInfo = NMDataIOUI.draftModalityInfo(IO, varind);
            D.datadescriptor{varind}.input_settings = IO;
            if ~isfield(D.datadescriptor{varind}.input_settings,'preview') && haveExistingPreview
                D.datadescriptor{varind}.input_settings.preview = existingPreview;
            end
            saved = true;
            NM = NMDataIOUI.setInspectionTargetContainer(NM, target, D);
            message = sprintf('Unfinished import settings saved for modality %d.', varind);
        end

        function tf = hasMeaningfulDraft(IO)
            % HASMEANINGFULDRAFT  Test whether a draft IO contract contains restorable content.
            %
            %   tf = NMDataIOUI.hasMeaningfulDraft(IO) checks source, variable, file, role, and
            %   metadata fields to avoid persisting empty browser defaults as draft settings.
            tf = false;
            if ~isstruct(IO), return; end
            ds = ''; st = '';
            if isfield(IO,'datasource'), ds = lower(char(string(IO.datasource))); end
            if isfield(IO,'sourceType'), st = lower(char(string(IO.sourceType))); end
            if strcmp(st,'connectivity') || isfield(IO,'connectivitySpec') || ...
                    (isfield(IO,'sourceFamily') && strcmpi(char(string(IO.sourceFamily)), 'connectivity'))
                if isfield(IO,'connectivitySpec') && isstruct(IO.connectivitySpec)
                    cf = {'files','classFileLists','data','edgeMatrix','table','atlasFile','atlasLabelFile', ...
                        'caseIds','auxiliarySourceType','auxiliaryAlignmentMode','auxiliaryVariableRoles','auxiliaryTableFiles','weightingFiles','weightingMatrices'};
                    for k = 1:numel(cf)
                        if isfield(IO.connectivitySpec, cf{k}) && NMDataIOUI.valueIsMeaningful(IO.connectivitySpec.(cf{k}))
                            tf = true;
                            return;
                        end
                    end
                end
                if isfield(IO,'desc_data') && NMDataIOUI.valueIsMeaningful(IO.desc_data)
                    tf = true;
                    return;
                end
            end
            if strcmp(st,'roi') || isfield(IO,'roiSpec') || ...
                    (isfield(IO,'sourceFamily') && strcmpi(char(string(IO.sourceFamily)),'roi'))
                if isfield(IO,'roiSpec') && isstruct(IO.roiSpec)
                    rf = {'files','vectorFiles','classFileLists','dataVariable','tableVariable','tableFile','caseIDsVariable','fileCaseIDsVariable','matrixCaseIDsVariable','caseColumn', ...
                        'featureColumns','roiSidecarFile','roiIDColumn','roiNameColumn','roiHemisphereColumn','roiXColumn','roiYColumn','roiZColumn', ...
                        'atlasFile','lhAnnotationFile','rhAnnotationFile','lhSurfaceGeometryFile','rhSurfaceGeometryFile','cat12Atlas','cat12Measure','covariateNames', ...
                        'auxiliarySourceType','auxiliaryAlignmentMode','auxiliaryVariableRoles','auxiliaryTableFiles', ...
                        'uiGlobalModeSelection','globalMode','globalUserSourceType','globalAlignmentMode','globalVariableRoles','globalTableFiles','globalName','globnorm','weightingFiles'};
                    for k = 1:numel(rf)
                        if isfield(IO.roiSpec, rf{k}) && NMDataIOUI.valueIsMeaningful(IO.roiSpec.(rf{k}))
                            tf = true;
                            return;
                        end
                    end
                end
                if isfield(IO,'desc_data') && NMDataIOUI.valueIsMeaningful(IO.desc_data)
                    tf = true;
                    return;
                end
            end
            if any(strcmp(st, {'image-list','surface-list'})) || any(strcmp(ds, {'nifti','spm','image','surf'})) || isfield(IO,'imageFiles') || isfield(IO,'maskFile')
                imageFields = {'imageFiles','imageFilesSpec','PP','maskFile','brainmask','imageCaseIDSpec','explicitCaseIDs', ...
                    'auxiliarySourceType','auxiliaryAlignmentMode','auxiliaryVariableRoles','auxiliaryTableFiles', ...
                    'globalUserSourceType','globalAlignmentMode','globalVariableRoles','globalTableFiles', ...
                    'surfaceTemplate','surfaceHemisphere','surfaceGeometryFile','surfaceDisplayMeshFile','surfaceInflatedGeometryFile', ...
                    'surfaceRoiLHScalarFiles','surfaceRoiLHAnnotFiles','surfaceRoiRHScalarFiles','surfaceRoiRHAnnotFiles', ...
                    'surfaceRoiScalarFiles','surfaceRoiAnnotFiles'};
                for i = 1:numel(imageFields)
                    if isfield(IO, imageFields{i}) && NMDataIOUI.valueIsMeaningful(IO.(imageFields{i}))
                        tf = true;
                        return;
                    end
                end
                if isfield(IO,'imageGroupSizes') && ~isempty(IO.imageGroupSizes) && any(double(IO.imageGroupSizes(:)) > 0)
                    tf = true;
                    return;
                end
                if isfield(IO,'groupSizes') && ~isempty(IO.groupSizes) && any(double(IO.groupSizes(:)) > 0)
                    tf = true;
                    return;
                end
            end
            fields = {'M_edit','matrix_edit','tableVariable','label_edit','case_edit','col_edit','covnames_edit','desc_data'};
            for i = 1:numel(fields)
                if isfield(IO, fields{i}) && NMDataIOUI.valueIsMeaningful(IO.(fields{i}))
                    tf = true;
                    return;
                end
            end
            listFields = {'feature_edit','covar_edit','ignore_edit'};
            for i = 1:numel(listFields)
                if isfield(IO, listFields{i}) && ~isempty(NMDataIOUI.asCell(IO.(listFields{i})))
                    tf = true;
                    return;
                end
            end
        end

        function tf = valueIsMeaningful(v)
            % VALUEISMEANINGFUL  Test whether a scalar/container value contains user content.
            %
            %   tf = NMDataIOUI.valueIsMeaningful(v) returns true for nonempty text, finite
            %   nonzero numeric/logical content, nonempty tables, or structs/cells with at least
            %   one meaningful element.
            tf = false;
            if isempty(v), return; end
            if ischar(v) || isstring(v)
                c = strtrim(char(string(v(1))));
                tf = ~isempty(c) && ~strcmp(c,'?');
            elseif iscell(v)
                vals = NMDataIOUI.asCell(v);
                tf = any(~cellfun(@(x) isempty(x) || strcmp(strtrim(char(string(x))),'?'), vals));
            elseif isnumeric(v) || islogical(v)
                tf = ~isempty(v);
            else
                tf = true;
            end
        end

        function c = asCell(v)
            % ASCELL  Convert common scalar/vector values to a cell array.
            %
            %   c = NMDataIOUI.asCell(v) normalizes string, char, numeric, logical, and cell
            %   inputs for draft-field scanning while preserving existing cell contents.
            if isempty(v)
                c = {};
            elseif iscell(v)
                c = v;
            elseif isstring(v)
                c = cellstr(v(:));
            elseif ischar(v)
                if isempty(strtrim(v)) || strcmp(strtrim(v),'?')
                    c = {};
                elseif ~isempty(strfind(v, ','))
                    c = regexp(v, '\s*,\s*', 'split');
                else
                    c = {v};
                end
            else
                c = {v};
            end
        end

        function IO = stripDraftInputSettings(IO)
            % stripDraftInputSettings  Remove resolved payloads before source metadata is enriched/persisted.
            % Keep source-defining file/header fields here; enrichInputSettingsFromIO still
            % needs them to construct the lightweight restorable import contract.
            resolvedFields = {'Y','Yw','label','t_Y','s_ID','s_label','s_featnames','covars','covnames','preview'};
            for ii = 1:numel(resolvedFields)
                if isfield(IO,resolvedFields{ii}), IO = rmfield(IO,resolvedFields{ii}); end
            end
        end

        function info = draftModalityInfo(IO, varind)
            % DRAFTMODALITYINFO  Build a lightweight modality-info summary for a draft import.
            %
            %   info = NMDataIOUI.draftModalityInfo(IO, varind) creates browser overview
            %   metadata for incomplete imports without feature matrices, including source, case
            %   count, feature count, role summaries, and draft status.
            info = NMModalityInfoTools.emptyInfo();
            info.schemaVersion = 1;
            info.createdBy = 'NMDataIOUI';
            info.createdAt = datestr(now, 30);
            info.modalityIndex = double(varind);
            ds = ''; st = '';
            if isfield(IO,'datasource'), ds = lower(char(string(IO.datasource))); end
            if isfield(IO,'sourceType'), st = lower(char(string(IO.sourceType))); end
            isSurface = strcmp(st,'surface-list') || strcmp(ds,'surf');
            isImage = isSurface || strcmp(st,'image-list') || any(strcmp(ds, {'nifti','spm','image'})) || isfield(IO,'imageFiles') || isfield(IO,'maskFile');
            if isImage
                info.datasource = ds;
                if isSurface
                    info.datasource = 'surf';
                elseif isempty(info.datasource) || strcmp(info.datasource,'image')
                    info.datasource = 'nifti';
                end
                info.source = 'image';
                info.typeCode = NaN;
                info.isImaging = ~isSurface;
                info.isSurface = isSurface;
                if isfield(IO,'imageFiles') && ~isempty(IO.imageFiles)
                    info.sourceFilesKnown = true;
                    info.nSourceFiles = double(numel(NMDataIOUI.asCell(IO.imageFiles)));
                    info.nSubjects = info.nSourceFiles;
                    info.nRawSubjects = info.nSourceFiles;
                elseif isfield(IO,'imageFilesSpec') && ~isempty(IO.imageFilesSpec)
                    info.sourceFilesKnown = true;
                    info.nSourceFiles = double(numel(NMDataIOUI.asCell(IO.imageFilesSpec)));
                    info.nSubjects = info.nSourceFiles;
                    info.nRawSubjects = info.nSourceFiles;
                end
                if isfield(IO,'maskFile') && NMDataIOUI.valueIsMeaningful(IO.maskFile)
                    info.maskAvailable = true;
                    info.maskPath = char(string(IO.maskFile));
                    [~,bn,ext] = fileparts(info.maskPath);
                    if strcmp(ext,'.gz')
                        [~,bn2,ext2] = fileparts(bn);
                        bn = [bn2 ext2 ext];
                    else
                        bn = [bn ext];
                    end
                    info.maskBasename = bn;
                end
            else
                info.datasource = 'matrix';
                info.source = 'matrix';
                info.typeCode = 0;
                info.isImaging = false;
                info.isSurface = false;
            end
            info.storageMode = 'unknown';
            if isfield(IO,'desc_data') && ~isempty(IO.desc_data) && ~strcmp(char(IO.desc_data),'?')
                info.label = char(IO.desc_data);
                info.description = info.label;
            else
                info.label = sprintf('Incomplete DataIO import %d', varind);
                info.description = info.label;
            end
            info.missingnessKnown = false;
            info = NMModalityInfoTools.setMissingnessUnknown(info);
            info.metadataCompleteness = 'partial';
            info.completenessScore = 0.25;
            if isequal(info.isImaging, true)
                info.diagnostics = {'This imaging modality import is incomplete; image feature data have not been added yet. Resume the import to complete it.'};
            else
                info.diagnostics = {'This modality import is incomplete; feature data have not been added yet. Resume the import to complete it.'};
            end
        end

        function idx = findRestorableDraftInputSettingsIndex(NM)
            % FINDRESTORABLEDRAFTINPUTSETTINGSINDEX  Find the latest restorable draft descriptor.
            %
            %   idx = NMDataIOUI.findRestorableDraftInputSettingsIndex(NM) scans descriptors from
            %   newest to oldest and returns the first uncommitted draft input_settings index.
            idx = NaN;
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor)
                return;
            end
            for ii = numel(NM.datadescriptor):-1:1
                if numel(NM.datadescriptor) < ii || ~isstruct(NM.datadescriptor{ii}) || ...
                        ~isfield(NM.datadescriptor{ii},'input_settings') || ~isstruct(NM.datadescriptor{ii}.input_settings)
                    continue;
                end
                IO = NM.datadescriptor{ii}.input_settings;
                if NMDataIOUI.isRestorableDraftInputSettings(NM, IO, ii)
                    idx = double(ii);
                    return;
                end
            end
        end

        function tf = isRestorableDraftInputSettings(NM, IO, varind)
            % ISRESTORABLEDRAFTINPUTSETTINGS  Validate whether draft input settings can be restored.
            %
            %   tf = NMDataIOUI.isRestorableDraftInputSettings(NM, IO, varind) requires draft
            %   status, not-completed status, no committed feature data for the target, and
            %   meaningful draft content.
            tf = false;
            if nargin < 2 || ~isstruct(IO), return; end
            isDraft = isfield(IO,'draft') && isequal(IO.draft, true);
            isCompleted = isfield(IO,'completed') && isequal(IO.completed, true);
            if ~isDraft || isCompleted
                return;
            end
            if nargin >= 3 && ~isempty(varind) && NMDataIOUI.hasCommittedFeatureData(NM, varind)
                return;
            end
            tf = true;
        end

        function tf = hasCommittedFeatureData(NM, varind)
            % HASCOMMITTEDFEATUREDATA  Test whether a modality already contains committed features.
            %
            %   tf = NMDataIOUI.hasCommittedFeatureData(NM, varind) checks NM.Y and descriptor
            %   feature-data fields to prevent draft restoration over committed modality data.
            tf = false;
            if nargin < 2 || isempty(varind) || ~isfinite(double(varind)) || double(varind) < 1
                return;
            end
            varind = round(double(varind));
            if isstruct(NM) && isfield(NM,'Y') && iscell(NM.Y) && numel(NM.Y) >= varind && ~isempty(NM.Y{varind})
                tf = true;
                return;
            end
            if isstruct(NM) && isfield(NM,'datadescriptor') && iscell(NM.datadescriptor) && numel(NM.datadescriptor) >= varind && ...
                    isstruct(NM.datadescriptor{varind}) && isfield(NM.datadescriptor{varind},'input_settings') && ...
                    isstruct(NM.datadescriptor{varind}.input_settings)
                info = struct();
                if isfield(NM.datadescriptor{varind}.input_settings,'modalityInfo') && isstruct(NM.datadescriptor{varind}.input_settings.modalityInfo)
                    info = NM.datadescriptor{varind}.input_settings.modalityInfo;
                end
                if isfield(info,'storageMode') && any(strcmpi(char(string(info.storageMode)), {'memory','external'}))
                    if isfield(info,'nFeatures') && isnumeric(info.nFeatures) && isfinite(info.nFeatures) && info.nFeatures > 0
                        tf = true;
                    end
                end
            end
        end

        function tf = hasExplicitImportTarget(state)
            % hasExplicitImportTarget  Test whether import state names a concrete target modality.
            %
            % tf = NMDataIOUI.hasExplicitImportTarget(state) requires importTarget.mode and a
            % finite positive varind. It is used before writing draft or inspection artifacts.
            %
            % state.importTarget: identifies whether the DataIO operation targets training, OOCV/application data, or a specific container.
            tf = false;
            if nargin < 1 || ~isstruct(state) || ~isfield(state,'importTarget') || ~isstruct(state.importTarget)
                return;
            end
            tgt = state.importTarget;
            if ~isfield(tgt,'mode') || isempty(tgt.mode) || ~isfield(tgt,'varind') || isempty(tgt.varind)
                return;
            end
            v = double(tgt.varind);
            tf = isfinite(v) && v >= 1 && any(strcmpi(char(string(tgt.mode)), {'add','replace','resume'}));
        end

        function n = committedModalityCount(NM)
            % COMMITTEDMODALITYCOUNT  Count committed modality slots in NM.Y.
            %
            %   n = NMDataIOUI.committedModalityCount(NM) returns numel(NM.Y) for struct NM
            %   containers with cell-array feature data, otherwise zero.
            n = 0;
            if isstruct(NM) && isfield(NM,'Y') && iscell(NM.Y)
                n = numel(NM.Y);
            end
        end

        function state = readSessionState(tmpDir)
            % READSESSIONSTATE  Read persisted semantic DataIO input from the session-wide NM2 STATE file.
            %
            % The returned object is the DataIO section (matrixImport plus page-local input state),
            % never a second current-config authority.
            state = struct();
            if nargin < 1 || isempty(tmpDir) || exist(tmpDir,'dir') ~= 7, return; end
            state = NMUIStateTools.readDataIO(tmpDir);
        end

        function [NM, ok] = loadSessionNM(NM0, tmpDir)
            % LOADSESSIONNM  Load the MATLAB-side session NM cache for a browser session.
            %
            %   [NM, ok] = NMDataIOUI.loadSessionNM(NM0, tmpDir) first checks the persistent
            %   in-process store and then the MAT session file fallback. ok indicates whether a
            %   session copy was recovered.
            NM = NM0;
            ok = false;
            key = NMDataIOUI.sessionKey(tmpDir);
            if ~isempty(key)
                [hit, storedNM] = NMDataIOUI.sessionNMStore('get', key);
                if hit && isstruct(storedNM)
                    NM = NMAnalysisManagerTools.reconcileOOCVAnalysisUse(storedNM);
                    NMDataIOUI.sessionNMStore('set', key, NM);
                    ok = true;
                    return;
                end
            end

            % Compatibility fallback for sessions created by older browser builds.
            % New sessions use the MATLAB-side store and do not write the NM
            % structure to the temporary web directory.
            if nargin < 2 || isempty(tmpDir) || exist(tmpDir,'dir') ~= 7, return; end
            fp = fullfile(tmpDir, 'dataio_committed_NM.mat');
            if exist(fp,'file') ~= 2, return; end
            try
                S = load(fp, 'NM');
                if isfield(S,'NM') && isstruct(S.NM)
                    NM = NMAnalysisManagerTools.reconcileOOCVAnalysisUse(S.NM);
                    ok = true;
                    if ~isempty(key)
                        NMDataIOUI.sessionNMStore('set', key, NM);
                    end
                end
            catch ME
                warning('NMDataIOUI:loadSessionNM', 'Could not load legacy DataIO session NM from disk: %s (%s)', ME.message, ME.identifier);
                NM = NM0;
                ok = false;
            end
        end

        function saveSessionNM(NM, tmpDir)
            % SAVESESSIONNM  Store NM in the MATLAB-side browser session cache.
            %
            %   NMDataIOUI.saveSessionNM(NM, tmpDir) associates NM with the normalized session
            %   key derived from tmpDir. The persistent store is bounded by sessionNMStore.
            key = NMDataIOUI.sessionKey(tmpDir);
            if isempty(key), return; end
            NMDataIOUI.sessionNMStore('set', key, NM);
        end

        function clearSessionNM(tmpDir)
            % CLEARSESSIONNM  Remove a browser session NM from the in-process cache.
            %
            %   NMDataIOUI.clearSessionNM(tmpDir) deletes the persistent session entry for the
            %   normalized tmpDir key when such a key can be derived.
            key = NMDataIOUI.sessionKey(tmpDir);
            if isempty(key), return; end
            NMDataIOUI.sessionNMStore('remove', key);
        end

        function key = sessionKey(tmpDir)
            % SESSIONKEY  Normalize a temporary directory path into a session-cache key.
            %
            %   key = NMDataIOUI.sessionKey(tmpDir) returns a char path with forward slashes, or
            %   an empty key when tmpDir is missing.
            key = '';
            if nargin < 1 || isempty(tmpDir), return; end
            key = char(string(tmpDir));
            key = strrep(key, '\', '/');
        end

        function [hit, value] = sessionNMStore(action, key, value)
            % SESSIONNMSTORE  Maintain the bounded persistent NM session cache.
            %
            %   [hit, value] = NMDataIOUI.sessionNMStore(action, key, value) implements get,
            %   set, and remove operations for browser-session NM copies. Side effect: updates a
            %   persistent containers.Map and evicts old entries when the cache grows.
            persistent store order
            if isempty(store)
                store = containers.Map('KeyType','char','ValueType','any');
                order = {};
            end
            if nargin < 3, value = []; end
            hit = false;
            switch lower(char(action))
                case 'get'
                    if ~isempty(key) && isKey(store, key)
                        value = store(key);
                        hit = true;
                    end
                case 'set'
                    if isempty(key), return; end
                    store(key) = value;
                    order(strcmp(order, key)) = [];
                    order{end+1} = key;
                    maxEntries = 8;
                    while numel(order) > maxEntries
                        oldKey = order{1};
                        order(1) = [];
                        if isKey(store, oldKey), remove(store, oldKey); end
                    end
                case 'remove'
                    if ~isempty(key) && isKey(store, key), remove(store, key); end
                    order(strcmp(order, key)) = [];
                case 'clear'
                    store = containers.Map('KeyType','char','ValueType','any');
                    order = {};
                otherwise
                    error('NMDataIOUI:badSessionNMStoreAction', 'Unknown DataIO NM session-store action: %s', char(action));
            end
        end

        function tmpDir = pathsTmpDir(pathsOrWebDir)
            % PATHSTMPDIR  Resolve the browser session temporary directory from paths input.
            %
            %   tmpDir = NMDataIOUI.pathsTmpDir(pathsOrWebDir) accepts an export paths struct or
            %   web/root directory path and returns the detected tmp directory, or empty string.
            tmpDir = '';
            if isstruct(pathsOrWebDir) && isfield(pathsOrWebDir,'tmpDir')
                tmpDir = pathsOrWebDir.tmpDir;
            elseif ischar(pathsOrWebDir) || isstring(pathsOrWebDir)
                p = char(pathsOrWebDir);
                if exist(fullfile(p,'tmp'),'dir') == 7
                    tmpDir = fullfile(p,'tmp');
                elseif exist(p,'dir') == 7
                    tmpDir = p;
                end
            end
        end

        function copyAssets(webDir)
            % COPYASSETS  Copy DataIO browser UI assets into the exported web directory.
            %
            %   NMDataIOUI.copyAssets(webDir) copies required JavaScript and CSS assets from the
            %   UI source directory. Public compatibility is retained for existing export code;
            %   this batch does not centralize asset-copy logic.
            srcDir = fileparts(mfilename('fullpath'));
            assets = {'NMDataIOUI_main.js','NMDataIOUI.css','NMResultsViewerPrimitives.js','NMImageSliceViewer.js','NMImageSliceViewer.css','NMModuleIconSet.js','NMModuleNavigationRail.js','NMModuleNavigationRail.css','NMModal.js','NMModal.css','NMRuntimeProgressViewer.js','NMRuntimeProgressViewer.css'};
            for i = 1:numel(assets)
                src = fullfile(srcDir, assets{i});
                if exist(src,'file') == 2
                    copyfile(src, fullfile(webDir, assets{i}), 'f');
                end
            end
            helpSourceDir = fullfile(fileparts(srcDir),'docs','dataio','help');
            helpTargetDir = fullfile(webDir,'help');
            if exist(helpTargetDir,'dir') ~= 7, mkdir(helpTargetDir); end
            helpCatalogue = NMDataIOStateTools.sourceTypeCatalogue();
            helpFiles = [{'dataio.html'} {helpCatalogue.helpFile}];
            for i = 1:numel(helpFiles)
                src = fullfile(helpSourceDir, helpFiles{i});
                if exist(src,'file') ~= 2
                    error('NMDataIOUI:missingHelpFile','DataIO help file is missing: %s',src);
                end
                copyfile(src, fullfile(helpTargetDir, helpFiles{i}), 'f');
            end
        end

        function txt = htmlTextFromJson(stateJson)
            % HTMLTEXTFROMJSON  Embed serialized state into the DataIO HTML shell.
            %
            %   txt = NMDataIOUI.htmlTextFromJson(stateJson) returns the complete browser entry
            %   HTML string with initial state, app-context attributes, and the DataIO script/CSS
            %   references. Public compatibility is retained; no template refactor is performed.
            jsState = NMPreprocUI.jsonTextForScript(stateJson);
            dataIOMode = 'training_import';
            try
                st0 = jsondecode(stateJson);
                if isstruct(st0) && isfield(st0,'dataIOMode') && ~isempty(st0.dataIOMode)
                    dataIOMode = char(string(st0.dataIOMode));
                end
            catch
                dataIOMode = 'training_import';
            end
            isOOCVMode = any(strcmp(dataIOMode, {'oocv_data_manager','application','application_mode','oocv','oocv_manager'}));
            trainingPanelStyle = '';
            oocvPanelStyle = '';
            if isOOCVMode
                trainingPanelStyle = ' style="display:none"';
            else
                oocvPanelStyle = ' style="display:none"';
            end
            sourceTypeCatalogue = NMDataIOStateTools.sourceTypeCatalogue();
            sourceTypeOptions = cell(1,numel(sourceTypeCatalogue));
            for sourceTypeIndex = 1:numel(sourceTypeCatalogue)
                sourceTypeOptions{sourceTypeIndex} = sprintf('<option value="%s">%s</option>', ...
                    sourceTypeCatalogue(sourceTypeIndex).id,sourceTypeCatalogue(sourceTypeIndex).label);
            end
            tabularSourceTypeMask = ismember({sourceTypeCatalogue.id},{'workspace','matfile','tablevar','tablefile','database'});
            sourceTypeOptionsHtml = ['<optgroup label="Tabular / matrix data">' strjoin(sourceTypeOptions(tabularSourceTypeMask),'') '</optgroup>' ...
                '<optgroup label="Imaging / spatial data">' strjoin(sourceTypeOptions(~tabularSourceTypeMask),'') '</optgroup>'];
            nl = newline;
            L = { ...
'<!doctype html>'
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
'<title>NeuroMiner DataIO</title>'
'<link rel="stylesheet" href="NMModuleNavigationRail.css">'
'<link rel="stylesheet" href="NMImageSliceViewer.css">'
'<link rel="stylesheet" href="NMDataIOUI.css">'
['<style>' NMUIMessageTools.css() '</style>']
'</head><body class="dataioOverviewActive nmHasNavRail">'
'<header><div><div class="crumb">Data import / modality overview</div><div class="title">NeuroMiner DataIO</div></div><div class="headerActions"><button id="finish" class="primary" type="button">Finish / close</button></div></header>'
'<main class="wrap">'
'<nav class="tabs hidden" id="dataioTabs" aria-hidden="true"><button class="tab active" data-tab="overview" id="overviewTab">Overview</button><button class="tab" data-tab="matrixImport" id="matrixImportTab">Import task</button><button class="tab" data-tab="diagnostics" id="diagnosticsTab">Diagnostics</button></nav>'
'<section class="tabPage active" id="tab_overview">'
'<section class="summaryGrid" id="summaryGrid"></section>'
['<section class="panel" id="trainingManagementPanel"' trainingPanelStyle '><div class="panelHead"><div><div class="panelTitleRow"><h1 id="trainingManagementTitle">Training modality management</h1><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="training-management" aria-label="Help: Training modality management" title="Help: Training modality management">?</button></div><p class="muted" id="trainingManagementHelp">Select a modality row, then choose an operation. Scientific modality-changing actions are available only before training import is finalized; storage and resource relinking remain available afterward.</p></div></div><div class="buttonRow"><button id="addModality" type="button">Add modality</button><button id="replaceModality" type="button" disabled>Modify selected</button><button id="resumeModality" type="button" disabled>Resume selected</button><button id="deleteModality" type="button" disabled>Delete selected</button><button id="deleteAllModalities" type="button" disabled>Delete all</button><button id="manageCovariates" type="button" disabled>Manage covariates...</button><button id="finalizeTrainingImport" class="primary" type="button" disabled>Finalize training data import</button><button id="externalizeModality" type="button" disabled>Move selected to external storage</button><button id="relinkModality" type="button" disabled>Reconnect external file</button><button id="relinkResources" type="button" disabled>Relink resources...</button><button id="reimportModality" type="button" disabled>Load selected back into NM2</button></div></section>']
['<section class="panel" id="oocvManagerPanel"' oocvPanelStyle '><div class="panelHead"><div><div class="panelTitleRow"><h1>OOCV / application data manager</h1><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="oocv-management" aria-label="Help: OOCV data manager" title="Help: OOCV data manager">?</button></div><p class="muted">Manage independent OOCV/application datasets. Each dataset may contain any subset of the NM data modalities; choose the modality when starting an import or storage action.</p></div></div><div class="formGrid oocvCreateGrid"><label>OOCV dataset name/description<input id="oocv_desc" placeholder="OOCV/application dataset"></label><label class="checkLabel oocvLabelCheck"><span>Labels available for evaluation</span><input id="oocv_labels_known" type="checkbox"></label></div><div class="buttonRow oocvButtonRow"><button id="createOOCVContainer" type="button">Create OOCV dataset</button><button id="deleteOOCVContainer" type="button">Delete selected OOCV dataset</button><button id="configureOOCVGroups" type="button">Configure study groups...</button><button id="importOOCVModality" class="primary" type="button">Import modality...</button><button id="showOOCVDiagnostics" class="primary" type="button">Show modality diagnostics...</button><button id="externalizeOOCVModality" type="button">Move modality to external storage...</button><button id="relinkOOCVModality" type="button">Reconnect external modality file...</button><button id="reimportOOCVModality" type="button">Load modality back into NM2...</button></div><div class="tableWrap"><table id="oocvTable"><thead><tr><th>#</th><th>Description</th><th>Labels</th><th>Cases</th><th>Study groups</th><th>Present modalities</th><th>Missing modalities</th><th>Readiness</th></tr></thead><tbody></tbody></table></div><div id="oocvDetails" class="details muted">Select an OOCV/application dataset.</div></section>']
['<section class="panel" id="oocvModalityPanel"' oocvPanelStyle '><div class="panelHead"><div><div class="panelTitleRow"><h1>Selected OOCV dataset modalities</h1><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="oocv-modality" aria-label="Help: OOCV modalities" title="Help: OOCV modalities">?</button></div><p class="muted">Select a modality row, then import, maintain, or inspect it.</p></div><div class="buttonRow panelActionRow"><button id="modifyOOCVModality" type="button" disabled>Modify selected</button><button id="showOOCVModalityDiagnostics" type="button">Show diagnostics</button><button id="exportOOCVQCSidecar" type="button" disabled>Export QC data</button></div></div><div class="tableWrap"><table id="oocvModalityTable"><thead><tr><th>Modality</th><th>Status</th><th>Storage</th><th>Cases</th><th>Features</th><th>Cases added as missing</th><th>Needs early-fusion imputation</th><th>Distribution shift</th><th>Link</th></tr></thead><tbody></tbody></table></div><div id="oocvModalityDetails" class="details muted compactSelectionLine">Select an OOCV/application dataset modality.</div></section>']
['<section class="panel" id="trainingModalityOverviewPanel"' trainingPanelStyle '><div class="panelHead"><div><div class="panelTitleRow"><h1>Modalities</h1><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="modality-overview" aria-label="Help: Modality overview" title="Help: Modality overview">?</button></div><p class="muted">Overview focuses on data usability: case count, feature count, missing data, and feature QC results.</p></div></div><div id="message" class="message">Ready.</div><div class="tableWrap"><table id="modalityTable"><thead><tr><th>#</th><th>Name</th><th>Source</th><th>Storage</th><th>Cases<br><span class="muted">with data / after matching</span></th><th>Features</th><th>Missing cases</th><th>Missing values</th><th>All-NaN features</th><th>Constant features</th><th>Feature mean range</th><th>Feature SD range</th><th>Status</th><th>Recipe</th></tr></thead><tbody></tbody></table></div><div class="buttonRow"><button id="exportAllDataIORecipe" type="button" disabled>Export full import recipe</button><button id="exportSelectedQCSidecar" type="button" disabled>Export selected QC data</button><button id="exportAllQCSidecars" type="button" disabled>Export all QC data</button></div></section>']
['<section class="panel" id="trainingModalityDetailsPanel"' trainingPanelStyle '><div class="panelHead"><div><div class="panelTitleRow"><h1>Selected training modality</h1><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="modality-details" aria-label="Help: Selected modality" title="Help: Selected modality">?</button></div><p id="details" class="muted compactSelectionLine">Select a modality row to inspect diagnostics.</p></div><div class="buttonRow panelActionRow"><button id="showTrainingModalityDiagnostics" type="button">Show diagnostics</button></div></div></section>']
'</section>'
'<section class="tabPage taskModalPage" id="tab_matrixImport">'
'<section class="panel taskModalBox"><div class="panelHead taskModalHead"><div><div class="panelTitleRow"><h1 id="importModalTitle">Data import task</h1><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="import-task" aria-label="Help: Data import task" title="Help: Data import task">?</button></div><p class="muted">Choose the data source, assign Case IDs, features, labels and covariates as needed, then Preview or Commit the modality. Preview includes diagnostics and QC.</p></div><div class="buttonRow panelActionRow"><button id="openItemSelector" type="button">Select cases / features...</button><button id="openTaskDiagnostics" class="primary" type="button" disabled>View preview diagnostics</button><button id="returnToOverviewFromImport" type="button">Return to overview</button></div></div><div class="formGrid sourceGrid">'
['<label class="wideField">Source type<select id="di_source_type">' sourceTypeOptionsHtml '</select></label>']
'<input id="di_groupmode" type="hidden" value="1">'
'<label id="taskFrameworkField">Learning/task framework<select id="di_modeflag"><option value="classification">Classification</option><option value="regression">Regression</option></select></label>'
'<label>Description<input id="di_desc" placeholder="e.g. Clinical baseline variables"></label>'
'<div class="sourcePanel" id="matFileSourcePanel"><div class="panelTitleRow"><h2>MAT-file source</h2><button class="panelHelpButton" type="button" data-help-scope="provenance" data-help-topic="source" aria-label="Help: MAT-file source" title="Help: MAT-file source">?</button></div><label class="wideField">MAT files<textarea id="di_medit" rows="4" placeholder="One .mat file per line"></textarea></label><div class="buttonRow"><button id="pickMatrixFile" type="button">Add MAT-file(s)...</button><button id="clearMatrixFiles" type="button">Clear MAT files</button></div><p class="muted">Variables may be assigned within or across MAT files. With Case-ID matching, each selected data variable is paired with its Case-ID variable. Explicit row order is available only when the selected variables have compatible row counts.</p></div>'
'<div class="sourcePanel" id="tableVariableSourcePanel"><div class="panelTitleRow"><h2>MATLAB table sources</h2><button class="panelHelpButton" type="button" data-help-scope="provenance" data-help-topic="source" aria-label="Help: MATLAB table sources" title="Help: MATLAB table sources">?</button></div><p class="muted">Select one or more workspace tables. Their columns use the same assignment, row filtering, Case-ID matching, Preview and Commit steps as table files.</p><div class="roleGrid"><div class="roleBox"><label>Available table variables<select id="di_table_var_source" multiple size="8"></select></label><div class="roleButtons"><button id="addTableVariable" type="button">Add selected table(s)</button></div></div><div class="roleBox"><label>Selected tables<select id="di_tablevar_select" multiple size="8"></select></label><div class="roleButtons"><button id="returnTableVariable" type="button">Remove selected table(s)</button><button id="refreshTableVariables" class="primary" type="button">Refresh table sources</button></div></div></div></div>'
'<div class="sourcePanel" id="tableFileSourcePanel"><div class="panelTitleRow"><h2>Text/spreadsheet table sources</h2><button class="panelHelpButton" type="button" data-help-scope="provenance" data-help-topic="source" aria-label="Help: Table-file sources" title="Help: Table-file sources">?</button></div><div class="tableFilePickerLayout"><label>Table files<textarea id="di_table_file" rows="4" placeholder="One CSV/TSV/TXT/XLS/XLSX file per line"></textarea></label><div class="tableFileButtonStack"><button id="pickTableFile" type="button">Add table file(s)...</button><button id="clearTableFiles" type="button">Clear table files</button><button id="refreshTableFiles" class="primary" type="button" disabled>Refresh data sources</button></div></div><div class="tableFileOptionRow"><label>Delimiter<select id="di_delimit"><option value="tab">tab</option><option value="comma">comma</option><option value="semicolon">semicolon</option><option value="pipe">pipe</option><option value="whitespace">whitespace</option></select></label><label>Header row<input id="di_header_row" type="number" min="1" placeholder="auto"><span class="hint">Leave empty to detect the header row separately for each table.</span></label></div></div>'
'<div class="sourcePanel databasePanel" id="databaseSourcePanel"><div class="panelTitleRow"><h2>Database connector</h2><button class="panelHelpButton" type="button" data-help-scope="provenance" data-help-topic="source" aria-label="Help: Database connector" title="Help: Database connector">?</button></div><div class="grid2"><label>Connector<select id="di_db_connector"><option value="sqlite_file">SQLite file</option><option value="odbc_dsn">ODBC DSN</option><option value="jdbc_url" disabled>JDBC URL (not implemented)</option><option value="postgresql">PostgreSQL</option><option value="mysql">MySQL / MariaDB</option></select></label><label id="di_db_file_label">Local database file<div class="inlineInput"><input id="di_db_file" placeholder="path to .db / .sqlite file"><button id="pickDatabaseFile" type="button">Pick DB</button></div></label><label id="di_db_url_label">Database URL / DSN<input id="di_db_url" placeholder="server URI / host / DSN without credentials"></label><label>Username<input id="di_db_user" placeholder="optional"></label><label>Password (session only)<input id="di_db_pass" type="password" placeholder="optional; never persisted"></label><label id="di_db_database_label">Database<div class="inlineInput"><select id="di_db_database"><option value="">—</option></select><button id="listDatabaseNamespaces" type="button">List databases</button></div></label><label id="di_db_schema_label">Schema<div class="inlineInput"><select id="di_db_schema"><option value="">—</option></select><button id="listDatabaseSchemas" type="button">List schemas</button></div></label></div><label class="checkLabel"><input id="di_db_use_query" type="checkbox"> Use custom SQL query</label><label id="di_db_query_label" class="wideField">SQL query<textarea id="di_db_query" rows="5" placeholder="SELECT case_id, label, feat_001, feat_002 FROM my_view WHERE ..."></textarea></label></div>'
'<div class="sourcePanel sharedFileSourcePanel" id="sharedFileSourcePanel"><div class="panelTitleRow"><h2 id="sharedFileSourceTitle">Subject data source</h2><button class="panelHelpButton" type="button" data-help-scope="provenance" data-help-topic="source" aria-label="Help: subject data source" title="Help: subject data source">?</button></div><p class="muted" id="sharedFileSourceIntro">Select the source representation used for this modality.</p><div class="grid2"><label id="sharedSourceFormatField">Input format<select id="di_shared_source_format"></select></label><label id="sharedLabelModeField">Label definition<select id="di_shared_label_mode"><option value="legacy_groups">Auto-label from class-specific file lists</option><option value="metadata">Use explicit labels</option></select></label></div><div id="sharedSubjectFileControls"><div id="sharedAutoLabelPanel" class="imageLabelPanel"><div class="panelSubhead"><h3 id="sharedAutoLabelTitle">Auto-label classification file lists</h3><p class="muted" id="sharedAutoLabelIntro">Define the class names and add the subject files for each class. NeuroMiner uses these file lists to create the training labels.</p></div><label class="smallField">Number of classes<input id="di_shared_class_count" type="number" min="1" max="20" value="2"></label><div id="sharedClassNames" class="imageClassNames"></div><div id="sharedClassTabs" class="imageClassTabs"></div><div class="imageFilePickerRow"><label class="wideField"><span id="sharedClassFilesLabel">Files for selected class</span><textarea id="di_shared_class_files" rows="8" placeholder="One subject file per line for the selected class."></textarea></label><div class="imageListButtons"><button id="addSharedFilesToActiveClass" type="button">Add files...</button><button id="removeSharedFilesFromActiveClass" type="button">Remove selected / last</button><button id="moveSharedFileUpActiveClass" type="button">Move up</button><button id="moveSharedFileDownActiveClass" type="button">Move down</button><button id="clearSharedClassFiles" type="button">Clear class</button></div></div><div id="sharedClassCoverage" class="hint"></div></div><div id="sharedVectorFilePanel" class="imageLabelPanel"><div class="panelSubhead"><h3 id="sharedVectorFileTitle">Subject file list</h3><p class="muted" id="sharedVectorFileIntro">Use one subject-file list. Labels are supplied explicitly through the label and covariate section below when required.</p></div><div class="imageFilePickerRow"><label class="wideField"><span id="sharedVectorFilesLabel">Subject files</span><textarea id="di_shared_files" rows="8" placeholder="One subject file per line."></textarea></label><div class="imageListButtons"><button id="addSharedFilesToVectorList" type="button">Add files...</button><button id="removeSharedFilesFromVectorList" type="button">Remove selected / last</button><button id="moveSharedFileUpVectorList" type="button">Move up</button><button id="moveSharedFileDownVectorList" type="button">Move down</button><button id="clearSharedVectorFiles" type="button">Clear list</button></div></div></div></div></div>'
['<div class="sourcePanel connectivityPanel" id="connectivitySourcePanel"><div class="panelTitleRow"><h2>Connectivity matrix source</h2><button class="panelHelpButton" type="button" data-help-scope="provenance" data-help-topic="source" aria-label="Help: Connectivity source" title="Help: Connectivity source">?</button></div><p class="muted">Select the connectivity data source. Each subject should provide one square connectivity matrix or one vector of ROI-to-ROI edges. NeuroMiner imports the selected edges as features and keeps ROI and edge labels for inspection.</p><div class="grid2"><label id="connDataVarField">Connectivity workspace variable<select id="di_conn_data_var" data-workspace-role="connectivity"></select></label><label id="connTableVarField">Connectivity table variable<select id="di_conn_table_var" data-workspace-role="table"></select></label><label id="connTableCaseColumnField">Case-ID column<select id="di_conn_table_case_column"><option value="">Inspect table first</option></select></label><div id="connTableCaseIDStatus" class="hint">Table row names are inspected first. A case-ID column is requested only when row names are empty.</div><div id="connTableEdgeColumnsField" class="exprControl"><label>Edge column indices<input id="di_conn_table_edge_columns" placeholder="e.g. 3:13205 or workspace vector"></label><button id="applyConnTableEdgeColumns" type="button">Apply</button><button id="helpConnTableEdgeColumns" type="button" class="exprHelpBtn" title="Numeric expression help">?</button><div id="connTableEdgeColumnsStatus" class="hint">Only needed when the table has no ROI description file. Otherwise NM2 identifies edge columns from ROI-pair names or from the expected number of edges.</div></div><label id="connSubjectDimField">Subject dimension<input id="di_conn_subject_dim" type="number" min="1" max="3" value="1"></label><label id="connNodesField">Number of nodes<input id="di_conn_n_nodes" type="number" min="2" placeholder="required for vectorized/table if not inferable"></label><label>Matrix type<select id="di_conn_matrix_type"><option value="undirected">Undirected / symmetric</option><option value="directed">Directed / asymmetric</option></select></label><label>Triangle<select id="di_conn_triangle"><option value="upper">Upper triangle</option><option value="lower">Lower triangle</option></select></label><label class="checkLabel"><input id="di_conn_include_diag" type="checkbox"> Include diagonal</label><label>Symmetry tolerance<input id="di_conn_sym_tol" type="number" step="any" value="1e-8"></label></div><div id="connMatVariablePanel" class="matVariablePanel" style="display:none"><label>Matrix variable inside MAT files<select id="di_conn_mat_variable"><option value="">Select matrix variable</option></select></label><div id="connMatVariableStatus" class="hint">MAT variable disambiguation is only shown when needed.</div></div><div class="panelSubhead"><h3>ROI information and node locations</h3><p class="muted">The ROI description file defines node IDs, names and matrix row order. If it contains MNI coordinates, NM2 uses them for spatial display. A labelled atlas image is needed only when one or more node coordinates are unavailable.</p></div><div class="grid2"><label class="wideField">ROI description file<div class="inlineInput"><input id="di_conn_atlas_label_file" placeholder="CSV/TSV/TXT file with node IDs, names and optional MNI coordinates"><button id="pickConnAtlasLabelFile" type="button">Pick ROI file</button></div></label><label id="connAtlasFileField" class="wideField">Labelled atlas fallback<div class="inlineInput"><input id="di_conn_atlas_file" placeholder="optional discrete NIfTI/MGZ label image" disabled><button id="pickConnAtlasFile" type="button" disabled>Pick atlas</button></div></label><label>Delimiter<select id="di_conn_atlas_label_delimiter"><option value="auto">auto</option><option value="comma">comma</option><option value="tab">tab</option><option value="semicolon">semicolon</option><option value="pipe">pipe</option><option value="whitespace">whitespace</option></select></label><label>Header<select id="di_conn_atlas_label_header"><option value="auto">auto</option><option value="yes">yes</option><option value="no">no</option></select></label><label>ID column<select id="di_conn_atlas_id_column"><option value="">auto</option></select></label><label>Name column<select id="di_conn_atlas_name_column"><option value="">auto</option></select></label><label>MNI X column<select id="di_conn_atlas_x_column"><option value="">auto</option></select></label><label>MNI Y column<select id="di_conn_atlas_y_column"><option value="">auto</option></select></label><label>MNI Z column<select id="di_conn_atlas_z_column"><option value="">auto</option></select></label></div><div class="buttonRow"><button id="inspectConnAtlasDescriptor" type="button">Inspect ROI file</button></div><div id="connAtlasDescriptorStatus" class="hint">Select and inspect the ROI description file. The atlas image remains unnecessary when all MNI coordinates are valid.</div><div id="connAtlasDescriptorPreview" class="details muted"></div><div id="connSubspacePanel" class="connectivitySubspacePanel"><div class="panelSubhead"><h3>Connectivity node selector</h3><p class="muted">Optional: restrict the import to selected ROI-to-ROI connections. Choose source and target ROI lists; only connections between these lists will be imported.</p></div><input id="di_conn_subspace_enable" type="hidden" value="false"><input id="di_conn_subspace_mode" type="hidden" value="between"><textarea id="di_conn_subspace_seed_nodes" class="hiddenControl"></textarea><textarea id="di_conn_subspace_set_a" class="hiddenControl"></textarea><textarea id="di_conn_subspace_set_b" class="hiddenControl"></textarea><input id="di_conn_subspace_metadata_column" type="hidden"><input id="di_conn_subspace_metadata_values" type="hidden"><input id="di_conn_subspace_metadata_edge_mode" type="hidden" value="involving"><div class="buttonRow"><button id="openConnSubspaceSelector" type="button">Open node selector...</button><button id="resetConnSubspaceSelector" type="button">Use full edge space</button></div><div id="connSubspaceStatus" class="hint">Full node set selected: all connectivity edges will be imported.</div></div><div id="connSubspaceModal" class="modalBackdrop" style="display:none"><div class="connectivitySelectorModal"><div class="modalHeader"><div><h2>Connectivity node selector</h2><p class="muted">Start with all ROIs, then adjust the source and target lists to keep only the ROI pairs needed for this modality. Hover over the preview matrix to inspect an edge and its group mean connection strength.</p></div><button id="closeConnSubspaceSelector" type="button" class="smallButton">Close</button></div><div id="connSelectorStatus" class="hint">Load connectivity data to edit the node selector.</div><div class="connSelectorGrid"><section class="connSelectorNodePanel"><div class="panelSubhead"><h3>Available nodes</h3><p class="muted">Filter by text or ROI metadata, then add matching nodes to source or target.</p></div><div class="grid2"><label>Search<input id="connSelectorSearch" placeholder="ROI name or ID"></label><label>Metadata column<select id="connSelectorMetadataColumn"><option value="">Any column</option></select></label><label>Metadata value<select id="connSelectorMetadataValue"><option value="">Any value</option></select></label></div><select id="connSelectorAvailableNodes" size="12" multiple></select><div class="buttonRow"><button id="connSelectorAddSelectedSource" type="button">Add selected to source</button><button id="connSelectorAddFilteredSource" type="button">Add filtered to source</button></div><div class="buttonRow"><button id="connSelectorAddSelectedTarget" type="button">Add selected to target</button><button id="connSelectorAddFilteredTarget" type="button">Add filtered to target</button></div></section><section class="connSelectorListPanel"><h3>Source nodes</h3><select id="connSelectorSourceNodes" size="8" multiple></select><div class="buttonRow"><button id="connSelectorRemoveSource" type="button">Remove selected from source</button><button id="connSelectorAllSource" type="button">Reset source to all</button></div><div class="buttonRow"><button id="connSelectorCopySourceSelectedToTarget" type="button" title="Copy selected source nodes into the target list">↓ selected to target</button><button id="connSelectorCopySourceAllToTarget" type="button" title="Copy all source nodes into the target list">↓↓ all to target</button></div><h3>Target nodes</h3><select id="connSelectorTargetNodes" size="8" multiple></select><div class="buttonRow"><button id="connSelectorRemoveTarget" type="button">Remove selected from target</button><button id="connSelectorAllTarget" type="button">Reset target to all</button></div><div class="buttonRow"><button id="connSelectorCopyTargetSelectedToSource" type="button" title="Copy selected target nodes into the source list">↑ selected to source</button><button id="connSelectorCopyTargetAllToSource" type="button" title="Copy all target nodes into the source list">↑↑ all to source</button></div></section><section class="connSelectorMatrixPanel"><h3>Current connectivity preview</h3><canvas id="connSelectorMatrix" width="520" height="420"></canvas><div id="connSelectorHover" class="connSelectorHover">Hover over the matrix to inspect an ROI-by-ROI edge.</div><div id="connSelectorMatrixSummary" class="hint"></div></section></div><div class="modalFooter"><button id="applyConnSubspaceSelector" type="button">Apply node selector</button><button id="cancelConnSubspaceSelector" type="button">Cancel</button></div></div></div><div id="connCaseIDPanel"><div class="panelSubhead"><h3>Case IDs</h3><p class="muted">These controls identify the cases in the connectivity modality. MATLAB table inputs use their row names, or a selected table column when row names are absent. Labels and covariates are assigned separately below.</p></div><div class="grid2"><label id="connCaseModeField">Case-ID mode<select id="di_conn_case_mode"><option value="filename">Filename-derived case IDs</option><option value="explicit">Explicit case-ID variable</option></select></label><label id="connExplicitCaseIdsField">Case-ID variable<select id="di_conn_case_ids" data-workspace-role="caseids"></select></label></div></div><details id="connWeightingPanel" class="connectivityOptionalPanel"><summary>Optional weighting / ranking maps</summary><p class="muted">Optional: add edge weighting or ranking maps for feature selection. Leave this section empty if no external connectivity map should be used.</p><div class="grid2"><label>Weighting workspace variable<select id="di_conn_weighting_var" data-workspace-role="connectivity"></select></label><label>Weighting map names<input id="di_conn_weighting_names" placeholder="map_001, map_002"></label><label>Square-map node order<select id="di_conn_weighting_node_order"><option value="training">Declared training node order (risky; allowed)</option><option value="metadata">Use ROI metadata when available</option></select></label><label>Vectorized-map edge mode<select id="di_conn_weighting_edge_mode"><option value="auto">auto</option><option value="training_order">Declared training feature order</option><option value="edge_index">edge index</option><option value="edge_names">edge names</option></select></label></div><label class="wideField">Weighting matrix files<textarea id="di_conn_weighting_files" rows="4" placeholder="Optional MAT/CSV square weighting matrices, one per line"></textarea></label><div class="buttonRow"><button id="addConnWeightingFiles" type="button">Add weighting files...</button><button id="clearConnWeightingFiles" type="button">Clear weighting files</button></div><div id="connWeightingMatVariablePanel" class="matVariablePanel" style="display:none"><label>Weighting variable inside MAT files<select id="di_conn_weighting_mat_variable"><option value="">Select weighting variable</option></select></label><div id="connWeightingMatVariableStatus" class="hint">Weighting MAT variable disambiguation is only shown when needed.</div></div></details></div>']
'<div class="sourcePanel roiSourcePanel" id="roiSourcePanel"><div class="panelTitleRow"><h2>ROI data source</h2><button class="panelHelpButton" type="button" data-help-scope="provenance" data-help-topic="source" aria-label="Help: ROI source" title="Help: ROI source">?</button></div><p class="muted">Import parcel-wise ROI measurements as one ROI modality. ROI identity must be explicit and every ROI must be verified against a labelled volumetric atlas or hemisphere-specific surface annotation.</p><div class="grid2"><label id="roiDataVarField">ROI matrix variable<select id="di_roi_data_var"></select></label><label id="roiTableVarField">ROI table variable<select id="di_roi_table_var"></select></label><label id="roiTableFileField" class="wideField">ROI table file<div class="inlineInput"><input id="di_roi_table_file" placeholder="CSV/TSV/XLSX table"><button id="pickROITableFile" type="button">Pick table</button></div></label><label id="roiCaseColumnField">Case-ID column<input id="di_roi_case_column" placeholder="exact table column name"></label><label id="roiFeatureColumnsField" class="wideField">ROI feature columns<input id="di_roi_feature_columns" placeholder="comma-separated column names or indices"></label></div><div id="roiCAT12Panel"><div class="imageCaseLabelRow"><div class="imageCaseIdStack"><label>Case-ID mode<select id="di_roi_case_mode"><option value="legacy_spm">Filename-derived case IDs</option><option value="explicit">Explicit case IDs</option></select></label><label id="roiExplicitCaseIdsField">Explicit case-ID variable<select id="di_roi_case_ids" data-workspace-role="caseids"></select></label></div></div><div class="buttonRow"><button id="inspectROICAT12" type="button">Inspect first file</button></div><div class="grid2"><label>CAT12 atlas family<select id="di_roi_cat12_atlas"><option value="">Inspect first file</option></select></label><label>CAT12 measurement<select id="di_roi_cat12_measure"><option value="">Select atlas first</option></select></label></div><div id="roiCAT12Status" class="hint">Choose files, then inspect the first CAT12 file to select its atlas family and measurement explicitly.</div></div><div id="roiSidecarPanel"><div class="panelSubhead"><h3>ROI description file</h3><p class="muted">Required for tabular ROI input. The ROI-description-file row order must match the ROI data-column order. ROI IDs and names are matched exactly; NM2 does not guess matches from similar anatomical names.</p></div><label class="wideField">ROI description file<div class="inlineInput"><input id="di_roi_sidecar_file" placeholder="CSV/TSV/TXT file describing ROI IDs and names"><button id="pickROISidecar" type="button">Pick ROI file</button></div></label><div class="grid2"><label>ROI ID column<input id="di_roi_id_column" placeholder="required"></label><label>ROI name column<input id="di_roi_name_column" placeholder="required"></label><label>Hemisphere column<input id="di_roi_hemi_column" placeholder="required for surface"></label><label>MNI X column<input id="di_roi_x_column" placeholder="optional"></label><label>MNI Y column<input id="di_roi_y_column" placeholder="optional"></label><label>MNI Z column<input id="di_roi_z_column" placeholder="optional"></label></div></div><div class="panelSubhead"><h3>Mandatory spatial reference</h3><p class="muted">The selected ROI reference determines which spatial viewers are available. Volumetric atlases enable 2-D/3-D volume adapters; surface annotations enable the surface adapter.</p></div><div class="grid2"><label id="roiSpatialKindField">Spatial reference<select id="di_roi_spatial_kind"><option value="volumetric_atlas">Volumetric labelled atlas</option><option value="surface_annotation">Surface annotation</option></select></label><label id="roiAtlasFileField" class="wideField">Labelled atlas image<div class="inlineInput"><input id="di_roi_atlas_file" placeholder="NIfTI/MGZ labelled atlas"><button id="pickROIAtlasFile" type="button">Pick atlas</button></div></label><label id="roiLHAnnotationField" class="wideField">Left annotation<div class="inlineInput"><input id="di_roi_lh_annotation" placeholder="LH .annot"><button id="pickROILHAnnotation" type="button">Pick LH annotation</button></div></label><label id="roiLHSurfaceGeometryField" class="wideField">Left surface display mesh<div class="inlineInput"><input id="di_roi_lh_surface_geometry" placeholder="LH surface matching annotation vertices"><button id="pickROILHSurfaceGeometry" type="button">Pick LH mesh</button></div></label><label id="roiRHAnnotationField" class="wideField">Right annotation<div class="inlineInput"><input id="di_roi_rh_annotation" placeholder="RH .annot"><button id="pickROIRHAnnotation" type="button">Pick RH annotation</button></div></label><label id="roiRHSurfaceGeometryField" class="wideField">Right surface display mesh<div class="inlineInput"><input id="di_roi_rh_surface_geometry" placeholder="RH surface matching annotation vertices"><button id="pickROIRHSurfaceGeometry" type="button">Pick RH mesh</button></div></label></div><div class="grid2"><label id="roiMatrixCaseIDsField">ROI matrix case-ID variable<select id="di_roi_matrix_case_ids" data-workspace-role="caseids"></select></label></div><div id="roiWeightingPanel" class="imageWeightingControls wideField"><div class="panelSubhead"><h3>Weighting / ranking ROI files</h3><p class="muted">Optional ROI-level weighting files must already use the same parcel identity as the subject ROI data. NM2 never reslices a NIfTI or surface scalar map to create ROI weights. Each table contains one row per ROI with exact columns <code>roi_id</code> and <code>weight</code>; surface ROI files additionally require <code>hemisphere</code> (<code>lh</code>/<code>rh</code>). Optional <code>roi_name</code> is verified but is not used for matching.</p></div><label class="wideField">ROI weighting/ranking files<textarea id="di_roi_weighting_files" rows="3" placeholder="One CSV/TSV/XLSX ROI weighting table per line"></textarea></label><div class="buttonRow"><button id="addROIWeightingFiles" type="button">Add ROI weighting files...</button><button id="removeROIWeightingFile" type="button">Remove selected / last</button><button id="clearROIWeightingFiles" type="button">Clear weighting files</button></div><div id="roiWeightingStatus" class="hint">Preview and Commit require each weighting file to contain exactly the same ROI IDs as the modality. NM2 matches rows by ROI identity, not by row position alone.</div></div></div>'
'<div class="sourcePanel imageSourcePanel" id="imageSourcePanel"><div class="panelTitleRow"><h2>Spatial image / surface source</h2><button class="panelHelpButton" type="button" data-help-scope="provenance" data-help-topic="source" aria-label="Help: Spatial image / surface source" title="Help: Spatial image / surface source">?</button></div><p class="muted" id="imageSourceIntro">Select NIfTI images. Volumetric imports require a brainmask or atlas. Case IDs can be derived from filenames or supplied explicitly.</p><div class="grid2"><label id="imageSpaceDefField" class="wideField">Brainmask / space-defining image<div class="inlineInput"><input id="di_image_mask" placeholder="brainmask or atlas .nii"><button id="pickImageMask" type="button">Pick space</button></div></label><div id="surfaceFeatureSpacePanel" class="surfaceFeatureSpacePanel"><div class="panelSubhead"><h3>Surface feature space</h3><p class="muted">For vertexwise import, all surface scalar files must share the same template or vertex order. For native-space subject surfaces, use ROI collapse with matching annotation files.</p></div><div class="surfaceFeatureGrid"><label>Surface import mode<select id="di_surface_space_mode"><option value="vertex_template">Vertexwise: common template mesh</option><option value="roi_native">ROI collapse: native subject surfaces + annotations</option></select></label><label>Template / mesh space<select id="di_surface_template"><option value="unknown">Unknown / verify by vertex count</option><option value="fsaverage">fsaverage</option><option value="fsaverage6">fsaverage6</option><option value="fsaverage5">fsaverage5</option><option value="cat12_template">CAT12 template / resampled 32k surface</option><option value="custom">Custom shared template</option></select></label><label>Hemisphere<select id="di_surface_hemi"><option value="auto">Auto / infer from filenames</option><option value="left">Left hemisphere</option><option value="right">Right hemisphere</option><option value="bilateral">Bilateral / concatenated</option></select></label><label class="surfaceGeometryField">Native / template surface geometry (required for vertexwise import)<div class="inlineInput"><input id="di_surface_geometry_file" placeholder="authoritative native/template mesh for QC and Results Viewer"><button id="pickSurfaceGeometryFile" type="button">Pick native mesh</button></div></label><label class="surfaceGeometryField">Inflated surface template (optional)<div class="inlineInput"><input id="di_surface_inflated_geometry_file" placeholder="optional corresponding inflated mesh"><button id="pickSurfaceInflatedGeometryFile" type="button">Pick inflated mesh</button></div></label></div><div id="surfaceRoiNativePanel" class="surfaceRoiNativePanel"><div class="panelSubhead"><h3>Native-space surface ROI collapse</h3><p class="muted">Add scalar and annotation files in the same subject order. For bilateral imports, left- and right-hemisphere lists must contain the same subjects in the same order. The import collapses each native surface to ROI features. For spatial Feature-QC, select one reference mesh per used hemisphere whose vertex order matches the first annotation in that hemisphere.</p></div><label>Collapse method<select id="di_surface_roi_method"><option value="mean">Mean</option><option value="median">Median</option></select></label><div class="surfaceRoiGrid"><label>LH scalar files<textarea id="di_surface_roi_lh_scalars" rows="5" placeholder="One LH subject scalar file per line"></textarea></label><label>LH annotation files<textarea id="di_surface_roi_lh_annots" rows="5" placeholder="One LH .annot file per line, same order"></textarea></label><label class="wideField">LH QC reference mesh<div class="inlineInput"><input id="di_surface_roi_lh_geometry" placeholder="mesh matching first LH annotation"><button id="pickSurfaceRoiLHGeometryFile" type="button">Pick LH mesh</button></div></label><label>RH scalar files<textarea id="di_surface_roi_rh_scalars" rows="5" placeholder="Optional RH scalar files, same subject order"></textarea></label><label>RH annotation files<textarea id="di_surface_roi_rh_annots" rows="5" placeholder="Optional RH .annot files, same order"></textarea></label><label class="wideField">RH QC reference mesh<div class="inlineInput"><input id="di_surface_roi_rh_geometry" placeholder="mesh matching first RH annotation"><button id="pickSurfaceRoiRHGeometryFile" type="button">Pick RH mesh</button></div></label></div></div><div class="hint">Scalar import uses the selected surface data vectors only. For vertexwise import, supply a non-inflated native/template mesh. DataIO validates its vertex count and retains the geometry for visualization. An optional inflated mesh is accepted only after exact indexed-face correspondence has been verified.</div></div><div class="imageCaseLabelRow"><div class="imageCaseIdStack"><label>Case-ID mode<select id="di_image_case_mode"><option value="legacy_spm">Filename-derived case IDs</option><option value="explicit">Explicit case IDs</option></select></label><label id="imageExplicitCaseIdsField">Explicit case-ID variable<select id="di_image_case_ids" data-workspace-role="caseids"></select></label></div></div></div></div>'
'<div class="rolePanel" id="variableRolePanel"><div class="panelTitleRow"><h2 id="variableRoleTitle">Assign data columns</h2><button class="panelHelpButton" type="button" data-help-scope="provenance" data-help-topic="alignment" aria-label="Help: Case-ID matching and alignment" title="Help: Case-ID matching and alignment">?</button></div><p class="muted">Assign feature, label and covariate inputs, then choose how cases are matched: one shared Case-ID key, a separate key for each input, or explicit row order. Similar column names may suggest Case-ID keys, but NM2 does not match cases until you select them.</p><label id="variableAlignmentField">Alignment<select id="di_variable_alignment"><option value="key_per_block">Key per block</option><option value="shared_key">Shared key</option><option value="row_order">Explicit row order</option></select><span id="variableAlignmentHint" class="hint">Each selected input has its own ordered Case-ID key columns.</span></label><label id="caseAxisPolicyField">First-modality case policy<select id="di_case_axis_policy"><option value="complete_case">Cases present in all selected inputs</option><option value="target_anchored">Use cases defined by the labels</option><option value="feature_union">Use all cases present in any feature input</option></select><span id="caseAxisPolicyHint" class="hint">Used only when this import creates the Case-ID list for a new training or OOCV dataset.</span></label><div class="rowOrderCaseBar" id="variableSharedKeyBox"><label>Shared Case-ID component(s)<div class="roleListScroll"><select id="di_var_shared_key" multiple size="3"></select></div><span id="sharedKeyOrderHint" class="hint">Select the Case-ID components in the order NM2 should combine them.</span></label><div class="sharedKeyActionColumn"><div class="roleButtons"><button id="applySharedKey" type="button">Apply shared key</button></div><div id="appliedSharedKeyStatus" class="appliedSharedKeyStatus" aria-live="polite" hidden></div></div></div><div class="rowOrderCaseBar" id="variableRowOrderCaseBox"><label>Row-order PSN / Case-ID variable<div class="roleListScroll"><select id="di_var_case_select" size="2"></select></div></label><div class="roleButtons"><button id="addIdVariable" type="button">Add from source variables</button><button id="returnIdVariable" type="button">Remove</button></div></div><div class="roleGrid variableRoleGrid" id="variableRoleGrid">'
'<div class="roleBox" id="tableObjectRoleBox"><label>Available tables / sheets<div class="roleListScroll tabularObjectListScroll"><select id="di_sheet_select" multiple size="5"><option value="">Refresh the source to list available tables or sheets</option></select></div></label><button id="addTabularObject" type="button" class="tabularObjectMoveButton">Add selected ↓</button><button id="addAllTabularObjects" type="button" class="tabularObjectMoveButton">Add all ⇊</button><label>Included tables<div class="roleListScroll tabularObjectListScroll"><select id="di_sheet_included" size="5"></select></div></label><button id="removeTabularObject" type="button" class="tabularObjectMoveButton" disabled>↑ Remove selected</button><button id="removeAllTabularObjects" type="button" class="tabularObjectMoveButton" disabled>⇈ Remove all</button><input id="di_sheet" type="hidden"><span class="hint">Ctrl/Shift-click to select multiple available tables. Included tables remain single-select for inspecting and assigning their columns.</span><div class="tabularFilterActionRow"><button id="openTabularFilterModal" type="button" class="tabularFilterButton">Apply / edit row filters...</button><button id="removeAllTabularFilters" type="button" class="tabularFilterButton" disabled>Remove all filters</button></div><div id="tabularFilterSummary" class="hint tabularFilterSummary">No row filters applied.</div></div>'
'<div class="roleBox variableSourceBox"><label><span id="sourceVariablesLabel">Source variables</span><div class="roleListScroll"><select id="di_var_source" multiple size="12"></select></div></label><div class="roleButtons sourceRoleButtons"><button id="listSourceVariables" type="button">Refresh source</button><button id="resetVariableRoles" type="button">Reset assignments</button></div></div>'
'<div class="roleBox" id="variableLabelRoleBox"><label><span id="variableLabelRoleLabel">Label input(s)</span><div class="roleListScroll"><select id="di_var_label_select" multiple size="6"></select></div></label><label class="variableBlockCaseField">Matching PSN / Case-ID<select id="di_var_label_case" multiple size="3"></select></label><div class="roleButtons"><button id="addLabelVariable" type="button">Add</button><button id="returnLabelVariable" type="button">Remove</button></div></div>'
'<div class="roleBox" id="variableFeatureRoleBox"><label id="oocvFeatureMappingModeField" hidden>Feature mapping<select id="di_oocv_feature_mapping_mode"><option value="automatic">Automatic by name</option><option value="manual">Manual expert mapping</option></select></label><label><span id="variableFeatureRoleLabel">Feature input(s)</span><div id="oocvFeatureMappingStatus" class="hint" hidden></div><div class="roleListScroll"><select id="di_var_feature_select" multiple size="6"></select></div></label><label class="variableBlockCaseField">Matching PSN / Case-ID<select id="di_var_feature_case" multiple size="3"></select></label><div class="roleButtons"><button id="addFeatureVariable" type="button">Add</button><button id="returnFeatureVariable" type="button">Remove</button></div></div>'
'<div class="roleBox" id="variableFeatureNameRoleBox"><label>Feature-name variable<div class="roleListScroll"><select id="di_var_featnames_select" multiple size="6"></select></div></label><label class="variableFeatureNameTargetField">For feature block<select id="di_var_featnames_feature"><option value="">Select feature block</option></select></label><div class="roleButtons"><button id="addFeatNamesVariable" type="button">Add</button><button id="returnFeatNamesVariable" type="button">Remove</button></div></div>'
'<div class="roleBox" id="variableCovariateRoleBox"><label><span id="variableCovariateRoleLabel">Covariate input(s)</span><div class="roleListScroll"><select id="di_var_covars_select" multiple size="6"></select></div></label><label class="variableBlockCaseField">Matching PSN / Case-ID<select id="di_var_covars_case" multiple size="3"></select></label><div class="roleButtons"><button id="addCovarVariable" type="button">Add</button><button id="returnCovarVariable" type="button">Remove</button></div></div>'
'<div class="roleBox" id="variableCovariateNameRoleBox"><label>Covariate-name variable<div class="roleListScroll"><select id="di_var_covarnames_select" size="6"></select></div></label><div class="roleButtons"><button id="addCovarNamesVariable" type="button">Add</button><button id="returnCovarNamesVariable" type="button">Remove</button></div><label class="compactRoleField">Or enter names<input id="di_var_covarnames_manual" placeholder="age, sex, site"></label><div class="roleButtons"><button id="loadCovariateNamesFile" type="button">Load names from file...</button></div><input id="di_var_covarnames_file" type="file" accept=".txt,.csv,.tsv" class="hidden"></div>'
'</div></div>'
'<input id="di_case" type="hidden"><input id="di_label" type="hidden"><input id="di_feat" type="hidden"><input id="di_covars" type="hidden"><input id="di_ignore" type="hidden">'
'<div class="rolePanel imageMetadataPanel" id="imageMetadataPanel"><div class="panelTitleRow"><h2 id="imageMetadataPanelTitle">Labels, covariates and globals</h2><button id="imageMetadataHelpButton" class="panelHelpButton" type="button" data-help-scope="provenance" data-help-topic="labels" aria-label="Help: Labels, covariates and globals" title="Help: Labels, covariates and globals">?</button></div><p class="muted" id="imageMetadataIntro">Provide labels and covariates from the MATLAB workspace or a CSV/spreadsheet and align them to the modality cases. Configure global values separately where supported.</p><div class="imageMetadataRows"><section class="imageMetadataSection imageAuxiliarySection"><div class="imageMetadataSectionTitle"><h3 id="imageAuxiliarySectionTitle">Labels and covariates</h3></div><div class="imageControlRow imageAuxSourceRow"><label class="imageAuxSourceControl">Source<select id="di_image_aux_source"><option value="none">None</option><option value="workspace">from MATLAB workspace</option><option value="tablefile">from CSV/spreadsheet</option></select></label><label class="imageAuxAlignmentControl">Alignment<select id="di_image_metadata_alignment"><option value="case_id">Case-ID matching (recommended)</option><option value="row_order">Explicit row-order mode</option></select></label></div><div id="imageAuxWorkspacePanel" class="imageAuxSubpanel"><div class="imageControlRow imageLabelRow"><label class="imageLabelValueControl">Label variable<select id="di_image_labels" data-workspace-role="label"></select></label><label class="imageCaseIdControl imageLabelCaseIdControl">Label case-ID variable<select id="di_image_label_case_ids" data-workspace-role="caseids"></select></label></div><div id="imageRegressionLabelNames" class="imageControlRow imageRegressionLabelNames"></div><div class="imageControlRow imageCovariateRow"><label>Covariate variable<select id="di_image_covariates" data-workspace-role="covariate"></select></label><label>Covariate-name variable<select id="di_image_covariate_names_var" data-workspace-role="covnames"></select></label><label class="imageCaseIdControl imageCovariateCaseIdControl">Covariate case-ID variable<select id="di_image_covariate_case_ids" data-workspace-role="caseids"></select></label></div><div id="imageCovariateNamesRow" class="imageControlRow imageCovariateNamesRow"><label>Or enter covariate names<input id="di_image_covariate_names" placeholder="age, sex, site"></label><div><button id="di_image_covariate_names_load" type="button">Load names from file...</button><input id="di_image_covariate_names_file" type="file" accept=".txt,.csv,.tsv" class="hidden"></div></div></div><div id="imageAuxFilePanel" class="imageAuxSubpanel"><div class="imageFileSourceGrid"><label class="imageFilePathField">CSV/spreadsheet file<input id="di_image_aux_file" placeholder="Select CSV, TSV, TXT, XLS or XLSX"></label><div class="imageAuxButtons"><button id="di_image_aux_pick" type="button">Browse</button><button id="di_image_aux_probe" type="button">Read columns</button></div><label>Table / sheet<select id="di_image_aux_object"></select></label></div><div class="imageAlignmentBlock imageAuxKeyControl"><div class="imageMetadataSubhead">Case-ID matching</div><div class="imageRoleAssignmentGrid imageKeyAssignmentGrid"><label>Available columns<select id="di_image_aux_key_columns" multiple size="6"></select></label><div class="roleButtons imageAssignmentButtons"><button id="di_image_aux_key_add" type="button">Add →</button><button id="di_image_aux_key_remove" type="button">← Remove</button></div><label>Selected Case-ID column(s)<select id="di_image_aux_key_assigned" multiple size="6"></select></label></div></div><div id="imageAuxRowOrderNote" class="imageRowOrderNote">Explicit row order assumes that the selected table has exactly the same number of rows as the modality and that each row refers to the same case in the same order. It is the user responsibility to ensure this correspondence.</div><div class="imageAuxFileLabelControl imageRoleBlock"><div class="imageMetadataSubhead">Labels</div><label>Label column(s)<select id="di_image_aux_label_columns" multiple size="5"></select></label></div><div class="imageRoleBlock"><div class="imageMetadataSubhead">Covariates</div><div class="imageRoleAssignmentGrid"><label>Available columns<select id="di_image_aux_covariate_columns" multiple size="6"></select></label><div class="roleButtons imageAssignmentButtons"><button id="di_image_aux_covariate_add" type="button">Add →</button><button id="di_image_aux_covariate_remove" type="button">← Remove</button></div><label>Assigned covariates<select id="di_image_aux_covariate_assigned" multiple size="6"></select></label></div></div></div></section><section id="imageGlobalSection" class="imageMetadataSection imageGlobalSection"><div class="imageMetadataSectionTitle"><h3>Global value</h3><span>Labels, covariates and global values</span></div><div class="imageControlRow imageGlobalRow"><label>Global mode<select id="di_image_global_mode"><option value="none">None</option><option value="proportional">Proportional scaling</option><option value="ancova">ANCOVA covariate</option></select></label><label class="imageGlobalControl">Global source<select id="di_image_global_source"><option value="user">User-defined</option><option value="derived">Computed during read-in via spm_global</option><option value="surface_mean" hidden disabled>Mean of scalar values</option></select></label></div><div class="imageControlRow imageGlobalUserSetupRow"><label class="imageGlobalControl imageGlobalUserControl">Data source<select id="di_image_global_user_source"><option value="workspace">from MATLAB workspace</option><option value="tablefile">from CSV/spreadsheet</option></select></label><label class="imageGlobalControl imageGlobalUserControl">Alignment<select id="di_image_global_alignment"><option value="case_id">Case-ID matching (recommended)</option><option value="row_order">Explicit row-order mode</option></select></label></div><div id="imageGlobalWorkspacePanel" class="imageAuxSubpanel"><div class="imageControlRow imageGlobalWorkspaceRow"><label class="imageGlobalControl imageGlobalUserControl">Global variable<select id="di_image_globals" data-workspace-role="global"></select></label><label class="imageGlobalControl imageGlobalUserControl imageCaseIdControl imageGlobalCaseIdControl">Global case-ID variable<select id="di_image_global_case_ids" data-workspace-role="caseids"></select></label></div></div><div id="imageGlobalFilePanel" class="imageAuxSubpanel"><div class="imageFileSourceGrid"><label class="imageFilePathField">CSV/spreadsheet file<input id="di_image_global_file" placeholder="Select CSV, TSV, TXT, XLS or XLSX"></label><div class="imageAuxButtons"><button id="di_image_global_pick" type="button">Browse</button><button id="di_image_global_probe" type="button">Read columns</button></div><label>Table / sheet<select id="di_image_global_object"></select></label></div><div class="imageAlignmentBlock imageGlobalKeyControl"><div class="imageMetadataSubhead">Case-ID matching</div><div class="imageRoleAssignmentGrid imageKeyAssignmentGrid"><label>Available columns<select id="di_image_global_key_columns" multiple size="6"></select></label><div class="roleButtons imageAssignmentButtons"><button id="di_image_global_key_add" type="button">Add →</button><button id="di_image_global_key_remove" type="button">← Remove</button></div><label>Selected Case-ID column(s)<select id="di_image_global_key_assigned" multiple size="6"></select></label></div></div><div id="imageGlobalRowOrderNote" class="imageRowOrderNote">Explicit row order assumes that the global source has exactly the same number of rows as the modality and that each row refers to the same case in the same order. It is the user responsibility to ensure this correspondence.</div><div class="imageRoleBlock"><div class="imageMetadataSubhead">Global assignment</div><div class="imageRoleAssignmentGrid"><label>Available columns<select id="di_image_global_column" size="6"></select></label><div class="roleButtons imageAssignmentButtons"><button id="di_image_global_add" type="button">Add →</button><button id="di_image_global_remove" type="button">← Remove</button></div><label>Assigned global<select id="di_image_global_assigned" multiple size="6"></select></label></div></div></div><div class="imageControlRow imageGlobalSettingsRow"><label class="imageGlobalControl">Global name<input id="di_image_global_name" placeholder="GlobalSignal"></label><label class="imageGlobalControl">Global multiplier<input id="di_image_globnorm" type="number" step="any" value="1"></label></div></section></div></div>'
'<input id="di_matrixvar" type="hidden">'
'<div class="rolePanel labelDefinitionPanel" id="commonLabelDefinitionPanel"><div class="panelSubhead"><div class="panelTitleRow"><h2 id="commonLabelDefinitionTitle">Label definition</h2><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="label-definition" aria-label="Help: Label definition" title="Help: Label definition">?</button></div><p class="muted" id="commonLabelDefinitionHelp">Select labels first.</p></div><label id="commonLabelNameSourceField">Compatible name variable<select id="di_common_label_names_var"><option value="">Use manual names below</option></select></label><div id="commonLabelDefinitionRows" class="labelDefinitionRows"></div></div>'
'<div class="rolePanel importOptionsPanel" id="importOptionsPanel"><div class="panelTitleRow"><h2>Import options</h2><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="import-options" aria-label="Help: Import options" title="Help: Import options">?</button></div><p class="muted">Covariate handling applies whenever covariates are imported, regardless of data source. Validation mode and text-to-missing-value conversion apply to matrix, table and database feature data.</p><div class="formGrid compactOptionsGrid"><label>Covariate handling<select id="di_covmanage"><option value="1">add to existing covariates</option><option value="2">replace existing covariates</option></select></label><label>Validation mode<select id="di_compatibility"><option value="legacy">standard import compatibility</option><option value="enhanced">enhanced diagnostics</option></select></label><label class="checkLabel"><input id="di_nan_enabled" type="checkbox"> Map text tokens to missing values</label><label>Missing-value tokens<input id="di_nan_tokens" placeholder="NA, N/A, n/a, ., -, missing"></label></div></div>'
'<div class="buttonRow importButtonRow"><button id="refreshTableCache" type="button">Reload table data</button><button id="previewMatrix" type="button">Preview</button><button id="commitMatrix" class="primary" type="button">Commit import</button><button id="cancelImportTask" type="button">Cancel import</button></div>'
'</div></section>'
'<section class="panel"><div class="panelTitleRow"><h1>Preview</h1><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="preview-qc-commit" aria-label="Help: Preview, QC and Commit" title="Help: Preview, QC and Commit">?</button></div><p class="muted">Preview is read-only and shows the rows and feature columns that would be imported with the current settings. Diagnostics and mandatory QC are computed from the same data shown by Preview. For matrix/table sources, feature inclusion is controlled by the assignment lists above.</p><div class="buttonRow"><button id="previewPrevPage" type="button">Previous page</button><button id="previewNextPage" type="button">Next page</button><button id="viewGroupQC" type="button" disabled>View group QC</button><label id="qcMetricControl" class="qcMetricControl" hidden>Preview QC column<select id="qcSubjectMetric" disabled><option value="rmsZ">RMS feature z-score</option></select></label><button id="generateQCReport" type="button" disabled title="Run Preview first.">Generate QC report</button><button id="openPersistedQCReport" type="button" disabled title="No persisted QC report reference is available.">Open QC report</button><span id="previewPageLabel" class="muted">Page 1</span></div><div id="previewSummary" class="muted">No preview yet.</div><div class="tableWrap"><table id="previewTable"><thead></thead><tbody></tbody></table></div></section>'
'</section>'
'<section class="tabPage taskModalPage" id="tab_diagnostics">'
'<section class="panel taskModalBox"><div class="panelHead taskModalHead"><div><div class="panelTitleRow"><h1 id="diagnosticsTitle">Diagnostics &amp; QC</h1><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="diagnostics" aria-label="Help: Diagnostics and QC" title="Help: Diagnostics and QC">?</button></div><p class="muted" id="diagnosticsSubtitle">Review what NM2 will import, data completeness, QC findings, row filtering, Case-ID matching and any problems that need attention.</p></div><div class="buttonRow panelActionRow"><button id="returnToImportTask" type="button">Return to import task</button><button id="returnToOverviewFromDiagnostics" type="button">Return to overview</button></div></div><div id="probeDiagnostics" class="details muted">No diagnostics selected.</div></section>'
'</section>'
'<div id="oocvGroupsModal" class="selectorOverlay hidden" aria-hidden="true"><div class="tabularFilterModalBox oocvGroupsModalBox"><div class="selectorHead"><div><b>OOCV study groups</b><div class="muted">Assign one study-group label to every case in the selected OOCV dataset. NM2 matches the group labels to the dataset Case IDs and stores one group definition for the whole dataset.</div></div><button id="closeOOCVGroupsModal" type="button">Close</button></div><div class="formGrid"><label>Source<select id="oocv_group_source"><option value="none">None</option><option value="workspace">MATLAB workspace</option><option value="tablefile">CSV / spreadsheet</option></select></label><label id="oocvGroupAlignmentField">Alignment<select id="oocv_group_alignment"><option value="case_id">Case-ID matching</option><option value="row_order">Explicit row order</option></select></label></div><div id="oocvGroupWorkspacePanel" class="formGrid"><label>Group-label variable<select id="oocv_group_workspace_variable"></select></label><label id="oocvGroupWorkspaceCaseField">Case-ID variable<select id="oocv_group_workspace_case"></select></label></div><div id="oocvGroupFilePanel"><div class="formGrid"><label class="wideField">CSV / spreadsheet file<input id="oocv_group_file" readonly></label><div class="buttonRow"><button id="pickOOCVGroupFile" type="button">Browse...</button><button id="readOOCVGroupColumns" type="button">Read columns</button></div><label>Table / sheet<select id="oocv_group_object"></select></label><label>Group-label column<select id="oocv_group_column"></select></label><label id="oocvGroupFileCaseField">Case-ID column(s)<select id="oocv_group_case_columns" multiple size="4"></select></label></div></div><div id="oocvGroupNamesPanel" class="hidden oocvGroupNamesPanel"><h3>Group labels</h3><p class="muted">NM2 converts the source group labels to numeric group IDs 1..K for analysis. Edit the displayed name for each group and optionally select a reference group.</p><div id="oocvGroupNames" class="oocvGroupNameGrid"></div><div class="oocvGroupReferenceRow"><label>Reference group<select id="oocv_group_ref"><option value="">None</option></select></label></div></div><div class="buttonRow"><button id="previewOOCVGroups" type="button">Preview group labels</button><button id="applyOOCVGroups" class="primary" type="button">Apply</button><button id="removeOOCVGroups" type="button">Remove group labels</button></div><div id="oocvGroupStatus" class="details muted">Select a source and preview the aligned group labels.</div></div></div>'
'<div id="imageViewerModal" class="selectorOverlay hidden" aria-hidden="true"><div class="imageViewerBox"><div class="selectorHead"><div><span class="panelTitleRow"><b id="ivTitle">Case QC viewer</b><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="case-qc-viewer" aria-label="Help: Case QC viewer" title="Help: Case QC viewer">?</button></span><div id="ivStatus" class="muted">Select View in the preview table or Inspect in Diagnostics &amp; QC.</div></div><button id="ivClose" type="button">Close</button></div><div id="ivRowSummary" class="imageViewerRowSummary muted">No case selected.</div><div class="imageViewerGrid"><div id="ivPrevNavRail" class="caseQCNavRail"><button id="ivPrevFlagged" class="caseQCFlaggedButton" type="button">Previous QC-flagged</button><button id="ivPrevSubject" class="imageNavButton" type="button" title="Previous case" aria-label="Previous case">&#9664;</button></div><div class="imageCanvasBox caseQCCenter"><canvas id="ivCanvas" class="hidden" width="1" height="1" aria-label="Axial image with overlay"></canvas><canvas id="ivSurfaceCanvas" class="hidden surfaceCanvas" width="900" height="700" aria-label="Rotatable cortical surface mesh with vertexwise scalar overlay"></canvas><img id="ivImage" alt="Axial image with brainmask overlay"><div class="imageSliceControls"><label>Axial slice<input id="ivSlice" type="range" min="1" max="1" value="1"></label><span id="ivSliceLabel" class="muted">Slice -/-</span></div><div id="ivMessage" class="muted imageViewerMessage">No image or surface rendered.</div><div class="imageViewerToolbar"><label class="subjectIncludeViewerToggle"><input id="ivIncludeSubject" type="checkbox" checked> Include this case in the import</label><button id="ivSurfaceReset" type="button">Reset 3D view</button><button id="ivToggleQC" type="button">Show QC map</button><label>QC map<select id="ivQCMetric"><optgroup label="Subject maps"><option value="subject_z">Subject z-score</option></optgroup><optgroup label="Group QC maps"><option value="feature_missing_rate">Group missing-rate</option><option value="feature_mean">Group mean</option><option value="feature_std">Group SD</option><option value="feature_zero_rate">Group zero-rate</option><option value="feature_outlier_rate">Group outlier-rate</option></optgroup></select></label><label>Z-threshold<input id="ivQCThreshold" type="number" min="0" step="0.1" value="3"></label><label>Mode<select id="ivQCMode"><option value="signed">signed z</option><option value="absolute">absolute z</option></select></label><label>Opacity<input id="ivQCOpacity" type="range" min="0" max="1" step="0.05" value="0.6"></label></div><div id="ivQCColorbar" class="imageViewerQCColorbar hidden" aria-hidden="true"><div class="qcLegendTitle">QC z-score overlay</div><div class="qcLegendSigned"><span id="ivQCNegMax" class="qcLegendBound">−</span><div class="qcThresholdScale"><div id="ivQCSignedGradient" class="qcGradient qcGradientSigned"></div><span id="ivQCNegThreshold" class="qcThresholdMark qcThresholdNegative">−</span><span id="ivQCPosThreshold" class="qcThresholdMark qcThresholdPositive">+</span></div><span id="ivQCPosMax" class="qcLegendBound">+</span></div><div class="qcLegendAbsolute hidden"><span class="qcLegendBound">0</span><div class="qcThresholdScale"><div id="ivQCAbsoluteGradient" class="qcGradient qcGradientAbsolute"></div><span id="ivQCAbsThreshold" class="qcThresholdMark qcThresholdAbsolute">threshold</span></div><span id="ivQCAbsMax" class="qcLegendBound">max |z|</span></div><div class="qcLegendSequential hidden"><span id="ivQCColorbarMin">-</span><div class="qcGradient qcGradientSequential"></div><span id="ivQCColorbarMax">-</span></div><div id="ivQCColorbarNote" class="qcLegendNote">Only voxels at or above the selected threshold are overlaid.</div></div><div id="ivSurfaceColorbar" class="imageViewerSurfaceColorbar hidden" aria-hidden="true"><div class="surfaceLegendTitle">Surface scalar overlay</div><div class="surfaceLegendRow"><span id="ivSurfaceColorbarMin">-</span><div class="surfaceGradient"></div><span id="ivSurfaceColorbarMax">-</span></div><div id="ivSurfaceColorbarNote" class="surfaceLegendNote">Vertex-wise scalar values for the selected surface file.</div></div></div><div id="ivNextNavRail" class="caseQCNavRail"><button id="ivNextFlagged" class="caseQCFlaggedButton" type="button">Next QC-flagged</button><button id="ivNextSubject" class="imageNavButton" type="button" title="Next case" aria-label="Next case">&#9654;</button></div></div></div></div>'
'<div id="featureProfileModal" class="selectorOverlay hidden" aria-hidden="true"><div class="featureProfileBox"><div class="selectorHead"><div><span class="panelTitleRow"><b>Case QC viewer · Tabular non-imaging data</b><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="case-qc-viewer" aria-label="Help: Case QC viewer" title="Help: Case QC viewer">?</button></span><div id="fpStatus" class="muted">Select Plot in the preview table or Inspect in Diagnostics &amp; QC.</div></div><button id="fpClose" type="button">Close</button></div><div id="fpRowSummary" class="imageViewerRowSummary muted">No case selected.</div><div class="featureProfileControls"><label>View<select id="fpPlotMode"><option value="profile">Feature profile</option><option value="histogram">Distribution histogram</option><option value="ordered">Ordered feature overview</option></select></label><label>Flag feature when |z| &ge;<input id="fpZThreshold" type="number" min="0" step="0.1" value="3"></label><label id="fpYLimitLabel">Vertical scale &plusmn;<input id="fpYLimit" type="number" min="1" step="0.5" value="6"></label></div><div id="fpCaseMetrics" class="featureProfileMetrics" aria-label="Case QC summary"></div><div class="caseQCViewerGrid"><div class="caseQCNavRail"><button id="fpPrevFlagged" class="caseQCFlaggedButton" type="button">Previous QC-flagged</button><button id="fpPrevSubject" class="imageNavButton" type="button" title="Previous case" aria-label="Previous case">&#9664;</button></div><div class="caseQCCenter"><canvas id="fpCanvas" width="1100" height="480" aria-label="Tabular feature quality-control plot"></canvas><div id="fpHover" class="featureProfileHover muted">Move the pointer over the plot to inspect its contents.</div><div id="fpMessage" class="muted featureProfileMessage">No feature-QC plot rendered.</div></div><div class="caseQCNavRail"><button id="fpNextFlagged" class="caseQCFlaggedButton" type="button">Next QC-flagged</button><button id="fpNextSubject" class="imageNavButton" type="button" title="Next case" aria-label="Next case">&#9654;</button></div></div><div class="featureProfileDetailGrid"><section class="featureProfilePanel"><h3>Most unusual features</h3><p class="muted">Largest absolute case-level z-scores. Select a feature to mark it in the ordered/profile view.</p><div id="fpTopFeatures"></div></section><section class="featureProfilePanel"><h3>Selected histogram bin</h3><p class="muted">Select a histogram bar to list up to 20 exact features from that z-score interval.</p><div id="fpHistogramDetails" class="muted">No histogram bin selected.</div></section><section class="featureProfilePanel"><h3>Find feature</h3><div class="featureProfileSearch"><input id="fpFeatureSearch" type="search" placeholder="Feature name contains..." aria-label="Feature name search"><button id="fpFeatureSearchBtn" type="button">Find</button></div><div id="fpFeatureSearchResults" class="muted">Enter part of a feature name. Results are bounded.</div></section></div><div class="featureProfileDecision"><div><b>QC decision</b><div class="muted">Plot settings and QC review do not change the imported scientific data.</div></div><label class="subjectIncludeViewerToggle"><input id="fpIncludeSubject" type="checkbox" checked> Include this case in the import</label></div></div></div>'
'<div id="connectivityQCModal" class="selectorOverlay hidden" aria-hidden="true"><div class="connectivityQCBox"><div class="selectorHead"><div><span class="panelTitleRow"><b id="cqTitle">Connectivity QC viewer</b><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="case-qc-viewer" aria-label="Help: Case QC viewer" title="Help: Case QC viewer">?</button></span><div id="cqStatus" class="muted">Run Preview to compute mandatory QC, then open the group viewer or inspect a case.</div></div><button id="cqClose" type="button">Close</button></div><div id="cqSubjectSummary" class="imageViewerRowSummary muted">Group-level matrix.</div><div class="imageViewerToolbar connectivityQCToolbar"><label>Metric<select id="cqMetric"><optgroup label="Group"><option value="group_mean">Group mean connectivity</option><option value="group_sd">Group SD</option><option value="group_missing_rate">Group missing-rate</option></optgroup><optgroup label="Subject"><option value="subject_value">Subject connectivity</option><option value="subject_z">Subject z-score vs group</option><option value="subject_abs_z">Subject |z| vs group</option><option value="subject_missing">Subject missing-edge mask</option></optgroup></select></label><label>Z-threshold<input id="cqZThreshold" type="number" min="0" step="0.1" value="3"></label></div><div class="caseQCViewerGrid connectivityQCViewerGrid"><div id="cqPrevNavRail" class="caseQCNavRail"><button id="cqPrevFlagged" class="caseQCFlaggedButton" type="button">Previous QC-flagged</button><button id="cqPrevSubject" class="imageNavButton" type="button" title="Previous case" aria-label="Previous case">&#9664;</button></div><div class="caseQCCenter"><div class="connectivityQCFigure"><div class="connectivityQCCanvasPane"><canvas id="cqMatrix" width="900" height="640" aria-label="Connectivity QC ROI-by-ROI matrix"></canvas></div><div id="cqColorbar" class="connectivityQCColorbar" aria-hidden="false"><div id="cqColorbarTitle" class="connectivityQCColorbarTitle">Connectivity</div><div class="connectivityQCColorbarScale"><span id="cqColorbarMax">+</span><div id="cqColorbarGradient" class="connectivityQCColorbarGradient signed"></div><span id="cqColorbarMid">0</span><span id="cqColorbarMin">-</span></div><div id="cqColorbarNote" class="connectivityQCColorbarNote">Blue = negative, white = zero, red = positive.</div></div></div><div id="cqHover" class="connSelectorHover">Hover over the matrix to inspect an ROI-by-ROI edge.</div><div id="cqSummary" class="muted connectivityQCSummary">No connectivity QC matrix rendered.</div></div><div id="cqNextNavRail" class="caseQCNavRail"><button id="cqNextFlagged" class="caseQCFlaggedButton" type="button">Next QC-flagged</button><button id="cqNextSubject" class="imageNavButton" type="button" title="Next case" aria-label="Next case">&#9654;</button></div></div></div></div>'

'<div id="covariateManagementModal" class="selectorOverlay hidden" aria-hidden="true"><div class="tabularFilterModalBox covariateManagementModalBox" role="dialog" aria-modal="true" aria-label="Manage covariates"><div class="selectorHead"><div><b>Manage covariates</b><div class="muted">Delete selected global covariate columns. Available only before training data import is finalized.</div></div><button id="closeCovariateManagement" type="button">Close</button></div><div class="covariateManagementToolbar"><button id="selectAllCovariates" type="button">Select all</button><span id="covariateSelectionStatus" class="muted"></span></div><div id="covariateManagementRows" class="covariateManagementRows"></div><div class="buttonRow"><button id="deleteSelectedCovariates" type="button" disabled>Delete selected</button><button id="deleteAllCovariates" type="button">Delete all</button></div></div></div>'
'<div id="resourceRelinkModal" class="selectorOverlay hidden" aria-hidden="true"><div class="tabularFilterModalBox resourceRelinkModalBox"><div class="selectorHead"><div><b>Modality resources</b><div class="muted">Inspect persisted file-backed resources for the selected modality. External feature storage is managed separately by Reconnect external file.</div></div><button id="closeResourceRelinkModal" type="button">Close</button></div><div id="resourceRelinkSummary" class="resourceRelinkSummary muted">No modality resources loaded.</div><div class="tableWrap resourceRelinkTableWrap"><table id="resourceRelinkTable"><thead><tr><th>Select</th><th>Resource</th><th>Category</th><th>File path</th><th>Status</th><th>Relinking</th></tr></thead><tbody></tbody></table></div><div id="resourceRelinkDetails" class="details muted">Select one or more resources to relink.</div><div class="buttonRow"><button id="resourceRelinkSelectMissing" type="button">Select missing that can be relinked</button><button id="resourceRelinkSelectAll" type="button">Select all that can be relinked</button><button id="resourceRelinkSelected" type="button" disabled>Relink one file...</button><button id="resourceRelinkRoot" class="primary" type="button" disabled>Relink selected from folder...</button><button id="refreshResourceRelink" type="button">Refresh status</button></div></div></div>'
'<div id="tabularFilterModal" class="selectorOverlay hidden" aria-hidden="true"><div class="tabularFilterModalBox"><div class="selectorHead"><div><span class="panelTitleRow"><b>Advanced tabular row filters</b><button class="panelHelpButton" type="button" data-help-scope="common" data-help-topic="advanced-filters" aria-label="Help: Advanced row filters" title="Help: Advanced row filters">?</button></span><div class="muted">Filter table rows before NM2 checks Case IDs and assigns features, labels or covariates. A filter column does not need to be used as a Case-ID, feature, label or covariate column.</div></div><button id="closeTabularFilterModal" type="button">Close</button></div><div class="tabularFilterTopRow"><label>Table / sheet<select id="di_tabular_filter_object"></select><span class="hint">General / cross-table shows only columns with exactly the same name in every selected table.</span></label><label>Combine rules for this table<select id="di_tabular_filter_match"><option value="all">Match all rules (AND)</option><option value="any">Match any rule (OR)</option></select></label><label class="checkLabel tabularFilterCase"><input id="di_tabular_filter_case_sensitive" type="checkbox"> Case-sensitive text comparison</label></div><div class="tabularFilterEditor"><label>Filter column<select id="di_tabular_filter_rule_column"></select></label><label>Criterion<select id="di_tabular_filter_rule_operator"></select></label><label>Value<input id="di_tabular_filter_rule_value" placeholder="Single criterion value; commas are literal"></label><div class="tabularFilterEditorButtons"><button id="addTabularFilterRule" type="button">Add rule</button><button id="replaceTabularFilterRule" type="button" disabled>Replace selected rule</button></div></div><div class="tabularFilterRuleListHead"><b>Rules for the selected table are highlighted; rules for all selected tables are listed below.</b><span id="tabularFilterRuleCount" class="muted">0 defined rules</span></div><div id="tabularFilterRuleList" class="tabularFilterRuleList"></div><div class="buttonRow"><button id="clearTabularFilter" type="button">Clear rules for this table</button><button id="applyTabularFilter" class="primary" type="button">Apply filters</button></div><p class="muted">While this window is open, NM2 keeps separate filter rules for each table. Switching tables does not discard those rules. Apply filters saves all changes made in this window; Close discards changes that have not been applied. Applied filters are saved with the import settings and restored when you Resume or Modify the modality. General / cross-table rules are applied to every selected table that contains the chosen column. Empty cells are allowed. Use “is missing” / “is not missing” when you want to filter by missing values. “in list” accepts comma-, semicolon-, or line-separated values.</p></div></div>'
'<div id="dataIOProgressModal" data-nm-message-skip class="selectorOverlay hidden" aria-hidden="true"><div class="progressBox"><div class="selectorHead"><div><b id="progressTitle">DataIO operation running</b><div id="progressSubtitle" class="muted">Please wait.</div></div><div id="progressPercent" class="progressPercent" aria-live="polite"></div></div><div class="progressBody"><div class="progressTrack"><div id="progressBar" class="progressBar indeterminate" role="progressbar" aria-valuemin="0" aria-valuemax="100"></div></div><div id="progressDetails" class="muted progressDetails">MATLAB is processing the request.</div></div></div></div>'
'<div id="itemSelectorModal" class="selectorOverlay hidden" aria-hidden="true"><div class="itemSelectorBox"><div class="selectorHead"><div><b>NM Matrix Inspector</b><div id="isStatus" class="muted">No data loaded.</div></div><button id="isClose" type="button">Close</button></div><div class="itemSelectorGrid"><section class="isPanel inspectorPanel"><h2>Matrix Inspector</h2><div class="isInspectorLayout"><canvas id="isFeatCanvas" width="390" height="145"></canvas><canvas id="isMatCanvas" width="390" height="285"></canvas><canvas id="isCaseCanvas" width="160" height="285"></canvas></div><div class="isControls"><div class="isMeasureBlock"><label class="isMeasureControl">Measure<select id="isMeasure"><option value="mean">mean</option><option value="median">median</option><option value="variance">variance</option><option value="iqr">interquartile range</option><option value="identical">identical</option><option value="nanpct">%(nan)</option><option value="kurtosis">kurtosis</option><option value="skewness">skewness</option><option value="corr">cross-correlation</option></select></label><button id="isScale" type="button" data-active="0">Scale</button></div><div class="isFilterBlock"><label>Feature filter</label><div class="isFilterRow"><button id="isFeatOp" type="button">&gt;=</button><input id="isFeatThr" type="text" placeholder="threshold" title="Feature filter threshold"></div><button id="isFeatFilter" class="wideFilterButton" type="button">Filter features</button></div><div class="isFilterBlock"><label>Case filter</label><div class="isFilterRow"><button id="isCaseOp" type="button">&gt;=</button><input id="isCaseThr" type="text" placeholder="threshold" title="Case filter threshold"></div><button id="isCaseFilter" class="wideFilterButton" type="button">Filter cases</button></div><button id="isReset" type="button">Reset filters</button></div><div id="isHover" class="muted hoverLine"></div></section><section class="isPanel manualPanel"><h2>Manual feature/case selection</h2><div class="isListGrid"><div><b>Feature pool</b><select id="isFeatPool" multiple size="10"></select></div><div class="isMoveBtns"><button id="isFeatAdd" type="button">&gt;</button><button id="isFeatRemove" type="button">&lt;</button><button id="isFeatAddAll" type="button">&gt;&gt;</button><button id="isFeatRemoveAll" type="button">&lt;&lt;</button></div><div><b>Features to import</b><select id="isFeatSelected" multiple size="10"></select></div><div><b>Cases pool</b><select id="isCasePool" multiple size="10"></select></div><div class="isMoveBtns"><button id="isCaseAdd" type="button">&gt;</button><button id="isCaseRemove" type="button">&lt;</button><button id="isCaseAddAll" type="button">&gt;&gt;</button><button id="isCaseRemoveAll" type="button">&lt;&lt;</button></div><div><b>Cases to import</b><select id="isCaseSelected" multiple size="10"></select></div></div><div class="buttonRow"><button id="isApply" class="primary" type="button">OK / Apply selection</button></div></section></div></div></div>'
'<div id="modalityContextMenu" class="contextMenu" role="menu" aria-hidden="true"><button data-action="replace" type="button">Modify / overwrite modality</button><button data-action="resume" type="button">Resume import</button><button data-action="delete" type="button">Delete modality</button><button data-action="externalize" type="button">Move to external storage</button><button data-action="relink" type="button">Reconnect external file</button><button data-action="resources" type="button">Relink resources...</button><button data-action="reimport" type="button">Load external data back into NM2</button><button data-action="recipe" type="button">Export import recipe</button><button data-action="qcSidecar" type="button">Export QC data</button></div>'
'<div id="oocvContextMenu" class="contextMenu" role="menu" aria-hidden="true"><button data-action="rename" type="button">Rename dataset</button><button data-action="import" type="button">Import modality...</button><button data-action="delete" type="button">Delete dataset</button></div>'
'<div id="oocvModalityContextMenu" class="contextMenu" role="menu" aria-hidden="true"><button data-action="import" type="button">Import modality</button><button data-action="replace" type="button">Replace modality</button><button data-action="externalize" type="button">Move modality to external storage</button><button data-action="relink" type="button">Reconnect external modality file</button><button data-action="reimport" type="button">Load modality back into NM2</button><button data-action="qcSidecar" type="button">Export QC data</button></div>'
'</main>'
'<aside id="dataIOHelpDrawer" class="dataIOHelpDrawer" aria-hidden="true" aria-label="DataIO context help"><div class="dataIOHelpHead"><div><div class="dataIOHelpEyebrow">Context help</div><div id="dataIOHelpTitle" class="dataIOHelpTitle">DataIO help</div></div><button id="closeDataIOHelp" class="dataIOHelpClose" type="button">Close</button></div><iframe id="dataIOHelpFrame" class="dataIOHelpFrame" title="DataIO context help"></iframe></aside>'
'<script>window.NM_DATAIO_STATE=__NM_DATAIO_STATE__;</script>'
'<script>window.NM_MODULE_NAV_CONTEXT = {currentModule:"data_manager"};</script>'
['<script>' NMUIMessageTools.script() '</script>']
'<script src="NMModuleIconSet.js"></script>'
'<script src="NMModuleNavigationRail.js"></script>'
'<script src="NMResultsViewerPrimitives.js"></script>'
'<script src="NMImageSliceViewer.js"></script>'
'<script src="NMDataIOUI_main.js"></script>'
'</body></html>'};
            txt = strjoin(L, nl);
            txt = strrep(txt, '__NM_DATAIO_STATE__', jsState);
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the DataIO UI text-writer entry point.
            %
            %   NMDataIOUI.writeTextFile(path,txt) delegates browser shell file output to
            %   NMSerializationTools while retaining the public compatibility wrapper and
            %   NMDataIOUI:writeFile diagnostic identifier.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMDataIOUI:writeFile', 'Could not write %s.', 'fwrite-input-char');
        end
    end

    methods (Static, Access = private)
        function summary = covariateSummaryFromNM(NM)
            % covariateSummaryFromNM  Summarize workspace-level NM covariate missingness for DataIO overview warnings.
            %
            % NM -> summary. This method reads NM.covars and NM.covnames without
            % mutating the scientific structure. Covariate NaNs do not block
            % modality import, but the returned warning remains visible because
            % downstream operations may require explicit imputation or
            % complete-case handling.
            summary = struct('available', false, 'nCases', 0, 'nCovariates', 0, ...
                'hasNaN', false, 'nNaN', 0, 'nCasesWithNaN', 0, ...
                'nCovariatesWithNaN', 0, 'affectedCovariateIndices', [], ...
                'affectedCovariateNames', {{}}, 'names', {{}}, 'message', 'No numeric NM covariates are available.');
            if ~isstruct(NM) || ~isfield(NM,'covars') || isempty(NM.covars) || ...
                    ~(isnumeric(NM.covars) || islogical(NM.covars)) || ~ismatrix(NM.covars)
                return;
            end
            C = double(NM.covars);
            nanMask = isnan(C);
            affectedIndices = find(any(nanMask, 1));
            names = {};
            if isfield(NM,'covnames') && ~isempty(NM.covnames)
                names = NMDataIOUI.localAsCellstr(NM.covnames);
            end
            summary.names = names(:)';
            if numel(names) < size(C,2)
                for k = (numel(names)+1):size(C,2)
                    names{k,1} = sprintf('Covariate_%03d', k); %#ok<AGROW>
                end
            end
            names = names(:);
            summary.available = true;
            summary.nCases = double(size(C,1));
            summary.nCovariates = double(size(C,2));
            summary.hasNaN = any(nanMask(:));
            summary.nNaN = double(nnz(nanMask));
            summary.nCasesWithNaN = double(nnz(any(nanMask, 2)));
            summary.nCovariatesWithNaN = double(numel(affectedIndices));
            summary.affectedCovariateIndices = double(affectedIndices(:)');
            summary.affectedCovariateNames = names(affectedIndices)';
            if summary.hasNaN
                summary.message = sprintf(['NM.covars contains %g NaN value(s) across %g case(s) and %g covariate(s). ', ...
                    'Modality import is allowed, but downstream operations using these covariates require explicit imputation or complete-case handling.'], ...
                    summary.nNaN, summary.nCasesWithNaN, summary.nCovariatesWithNaN);
            else
                summary.message = sprintf('NM.covars is complete: %g case(s), %g covariate(s), no NaN values.', ...
                    summary.nCases, summary.nCovariates);
            end
        end

        function v = localFieldOr(S, name, defaultValue)
            if nargin < 3, defaultValue = []; end
            if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
                v = S.(name);
            else
                v = defaultValue;
            end
        end

        function v = localNumericVector(v)
            if isempty(v), v = []; return; end
            if ischar(v) || isstring(v) || iscell(v)
                v = str2double(NMDataIOUI.localAsCellstr(v));
            end
            v = double(v(:)');
        end

        function c = localAsCellstr(v)
            if isempty(v), c = {}; return; end
            if isstring(v)
                c = cellstr(v(:));
            elseif ischar(v)
                c = cellstr(v);
            elseif iscell(v)
                c = cell(size(v));
                for i = 1:numel(v)
                    if isempty(v{i})
                        c{i} = '';
                    else
                        c{i} = NMDataIOUI.localAsChar(v{i});
                    end
                end
                c = c(:);
            elseif isnumeric(v) || islogical(v)
                c = cellstr(num2str(v(:)));
            else
                c = cellstr(string(v(:)));
            end
            for i = 1:numel(c)
                c{i} = strtrim(char(c{i}));
            end
        end

        function s = localAsChar(v)
            if isempty(v), s = ''; return; end
            if ischar(v)
                s = v;
            elseif isstring(v)
                s = char(v(1));
            elseif isnumeric(v) || islogical(v)
                if isscalar(v), s = num2str(v); else, s = char(string(v)); end
            elseif iscell(v) && numel(v) == 1
                s = NMDataIOUI.localAsChar(v{1});
            else
                s = char(string(v));
            end
            s = strtrim(s);
        end

        function out = localTableColumnText(col)
            if iscellstr(col)
                out = col(:)';
            elseif iscell(col)
                out = cell(size(col(:)'));
                for i = 1:numel(col), out{i} = NMDataIOUI.localAsChar(col{i}); end
            elseif isstring(col) || iscategorical(col)
                out = cellstr(string(col(:)))';
            elseif isnumeric(col) || islogical(col)
                out = arrayfun(@(x)sprintf('%.15g', double(x)), col(:)', 'UniformOutput', false);
            else
                out = cellstr(string(col(:)))';
            end
        end

        function tf = localLogicalScalar(v)
            if isempty(v)
                tf = false;
            elseif ischar(v) || (isstring(v) && isscalar(v))
                s = lower(strtrim(char(string(v))));
                tf = any(strcmp(s, {'1','true','yes','on'}));
            else
                tf = logical(v(1));
            end
        end
    end
end

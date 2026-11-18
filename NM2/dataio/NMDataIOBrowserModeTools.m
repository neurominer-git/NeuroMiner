classdef NMDataIOBrowserModeTools
% NMDataIOBrowserModeTools
% -------------------------------------------------------------------------
% Purpose / authority:
%   Browser-facing non-visual state transitions for DataIO mode handling and OOCV/application
%   container management. The browser renders these states but does not own their legality.
%
% Owned rules:
%   - explicit training import finalization;
%   - training-data maintenance/application-mode separation;
%   - OOCV data-container creation/deletion/import-target preparation.
%
% Invariant:
%   OOCV containers may be incomplete at DataIO level; the selected trained analysis determines
%   modality requirements when model application is executed.
% -------------------------------------------------------------------------

    methods (Static)
        function defs = defsState(NM)
            % defsState  Read DataIO lock/finalization flags from NM.defs into a stable state struct.
            %
            % NM -> defs.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            defs = struct('import_finished', false, 'analyses_locked', false);
            if isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs)
                if isfield(NM.defs,'import_finished') && ~isempty(NM.defs.import_finished)
                    defs.import_finished = logical(NM.defs.import_finished);
                end
                if isfield(NM.defs,'analyses_locked') && ~isempty(NM.defs.analyses_locked)
                    defs.analyses_locked = logical(NM.defs.analyses_locked);
                end
            end
        end

        function mode = dataIOModeFromDefs(defs)
            % dataIOModeFromDefs  Classify the current DataIO browser mode from finalized/import-lock flags.
            %
            % Defs -> mode.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 1 || ~isstruct(defs)
                defs = struct('import_finished', false, 'analyses_locked', false);
            end
            if ~isfield(defs,'import_finished') || ~logical(defs.import_finished)
                mode = 'training_import';
            elseif isfield(defs,'analyses_locked') && logical(defs.analyses_locked)
                mode = 'oocv_data_manager';
            else
                mode = 'training_data_manager';
            end
        end

        function permissions = permissionsFromMode(mode, defs)
            % permissionsFromMode  Return UI/API edit permissions implied by the current DataIO mode.
            %
            % Mode, defs -> permissions.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2, defs = struct(); end %#ok<INUSD>
            mode = char(string(mode));
            permissions = struct();
            permissions.canModifyTrainingModalities = strcmp(mode, 'training_import');
            permissions.canFinalizeTrainingImport = strcmp(mode, 'training_import');
            permissions.canMaintainTrainingStorage = any(strcmp(mode, {'training_import','training_data_manager'}));
            permissions.canManageOOCV = strcmp(mode, 'oocv_data_manager');
            permissions.canImportOOCV = permissions.canManageOOCV;
        end

        function msg = modeMessage(mode)
            % modeMessage  Return the explanatory message shown for the current DataIO browser mode.
            %
            % Mode -> msg.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            switch char(string(mode))
                case 'training_import'
                    msg = ['Ready. Training-data import is open. Add, replace, delete, filter, and database/table/workspace import actions remain available until the user finalizes the training data import stage.'];
                case 'training_data_manager'
                    msg = ['Training-data import is finalized. Training modalities are structurally locked; DataIO is limited to diagnostics, externalization/internalization, and relinking.'];
                case 'oocv_data_manager'
                    msg = ['Application mode. Training data are locked; DataIO manages OOCV/application datasets only.'];
                otherwise
                    msg = 'Ready.';
            end
        end

        function state = oocvManagerState(NM)
            % oocvManagerState  Build the OOCV/application container overview used by the browser manager.
            %
            % NM -> state.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            state = struct();
            state.containerField = 'OOCV';
            state.nTrainingModalities = NMDataIOImportTargetTools.nTrainingModalities(NM);
            state.containers = struct('index', {}, 'description', {}, 'labelsKnown', {}, 'nCases', {}, ...
                'analysisUsed', {}, 'canModify', {}, 'canDelete', {}, 'deleteMessage', {}, ...
                'grouping', {}, 'presentModalities', {}, 'incompleteModalities', {}, 'missingModalities', {}, 'nFeatures', {}, 'nExternalized', {}, ...
                'modalities', {}, 'ready', {}, 'message', {}, 'readiness', {});
            if ~isstruct(NM) || ~isfield(NM,'OOCV') || isempty(NM.OOCV) || ~iscell(NM.OOCV)
                state.nContainers = 0;
                state.activeIndex = [];
                return;
            end
            for i = 1:numel(NM.OOCV)
                D = NM.OOCV{i};
                if isempty(D) || ~isstruct(D), continue; end
                c = struct();
                c.index = i;
                if isfield(D,'desc') && ~isempty(D.desc), c.description = char(string(D.desc)); else, c.description = sprintf('OOCV/application dataset %d', i); end
                if isfield(D,'labels_known') && ~isempty(D.labels_known), c.labelsKnown = logical(D.labels_known); else, c.labelsKnown = []; end
                if isfield(D,'cases') && ~isempty(D.cases), c.nCases = numel(D.cases); else, c.nCases = []; end
                lifecycle = NMDataIOBrowserModeTools.oocvLifecycleState(NM, i);
                c.analysisUsed = lifecycle.analysisUsed;
                c.canModify = lifecycle.canModify;
                c.canDelete = lifecycle.canDelete;
                c.deleteMessage = lifecycle.deleteMessage;
                c.grouping = NMDataIOBrowserModeTools.oocvGroupingState(D);
                modalityRows = NMDataIOBrowserModeTools.oocvModalityRows(NM, D, state.nTrainingModalities);
                presentRows = modalityRows([modalityRows.present]);
                present = [presentRows.index];
                incomplete = [modalityRows(strcmpi({modalityRows.status}, 'incomplete')).index];
                featureCounts = [presentRows.nFeatures];
                nFeatures = sum(featureCounts(isfinite(featureCounts)));
                nExternalized = nnz(strcmpi({presentRows.storageMode}, 'external'));
                c.presentModalities = present;
                c.incompleteModalities = incomplete;
                c.nFeatures = nFeatures;
                c.nExternalized = nExternalized;
                c.modalities = modalityRows;
                trainingModalities = 1:max(0,state.nTrainingModalities);
                c.missingModalities = setdiff(trainingModalities, [present incomplete]);
                target = struct('scope','oocv','containerField','OOCV','containerIndex',i,'varind',1);
                % DataIO validates only committed modalities. Analysis-specific modality completeness is enforced by NMRunTools.oocvReadiness.
                if isempty(present)
                    c.ready = false;
                    if ~isempty(incomplete)
                        c.message = sprintf('OOCV/application dataset has unfinished modality import(s): %s.', ...
                            NMDataIOOOCVReadinessTools.joinNumeric(incomplete));
                    else
                        c.message = 'OOCV/application dataset has no completed modalities.';
                    end
                    c.readiness = struct();
                else
                    try
                        [readyReport, messages] = NMDataIOOOCVReadinessTools.validate(NM, target, present);
                        c.ready = logical(readyReport.ready) && isempty(incomplete);
                        strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'OOCV/application dataset has not been checked yet.');
                        if logical(readyReport.ready) && ~isempty(incomplete)
                            c.message = sprintf('Completed OOCV modalities are compatible, but unfinished modality import(s) remain: %s.', ...
                                NMDataIOOOCVReadinessTools.joinNumeric(incomplete));
                        else
                            c.message = strip.text;
                        end
                        c.readiness = readyReport;
                    catch ME
                        c.ready = false;
                        c.message = sprintf('Could not check the OOCV/application dataset: %s (%s)', ME.message, ME.identifier);
                        c.readiness = struct();
                    end
                end
                state.containers(end+1) = c; %#ok<AGROW>
            end
            state.nContainers = numel(state.containers);
            if state.nContainers > 0, state.activeIndex = state.containers(1).index; else, state.activeIndex = []; end
        end

        function rows = oocvModalityRows(NM, D, nTrainingModalities)
            % oocvModalityRows  Summarize OOCV modalities relative to training modalities for the manager table.
            %
            % Consumes NM, D, nTrainingModalities; returns rows.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            if nargin < 3 || isempty(nTrainingModalities)
                nTrainingModalities = NMDataIOImportTargetTools.nTrainingModalities(NM);
            end
            nTrainingModalities = max(0, round(double(nTrainingModalities)));
            rows = struct('index', {}, 'title', {}, 'present', {}, 'status', {}, 'storageMode', {}, ...
                'nCases', {}, 'nFeatures', {}, 'expectedFeatures', {}, 'externalFileExists', {}, ...
                'externalBasename', {}, 'missingCasesFilledWithNaN', {}, 'nMissingCasesFilledWithNaN', {}, ...
                'requiresEarlyFusionImputation', {}, 'hasQC', {}, 'hasQCReport', {}, 'hasQCViewerCache', {}, ...
                'hasQCSidecar', {}, 'qcCacheStatus', {}, 'qcCacheDurability', {}, 'qcSidecarFile', {}, 'qcSidecarRoot', {}, ...
                'distributionShiftStatus', {}, 'distributionShiftSummary', {}, 'qcSummary', {}, 'referenceShift', {}, 'message', {}, 'diagnostics', {});
            for v = 1:nTrainingModalities
                r = struct();
                r.index = v;
                trainingInfo = NMModalityInfoTools.fromNM(NM, v, struct('ScanInMemory', false, 'MaxScanElements', 0));
                r.title = trainingInfo.label;
                r.present = false;
                r.status = 'missing';
                r.storageMode = 'missing';
                r.nCases = NaN;
                r.nFeatures = NaN;
                trainingAxis = NMModalityInfoTools.preprocContextInfo(NM, v);
                r.expectedFeatures = trainingAxis.nFeatures;
                r.externalFileExists = [];
                r.externalBasename = '';
                r.missingCasesFilledWithNaN = false;
                r.nMissingCasesFilledWithNaN = 0;
                r.requiresEarlyFusionImputation = false;
                r.hasQC = false;
                r.hasQCReport = false;
                r.hasQCViewerCache = false;
                r.hasQCSidecar = false;
                r.qcCacheStatus = '';
                r.qcCacheDurability = '';
                r.qcSidecarFile = '';
                r.qcSidecarRoot = '';
                r.distributionShiftStatus = '';
                r.distributionShiftSummary = '';
                r.qcSummary = struct();
                r.referenceShift = struct();
                r.message = 'Missing in this OOCV/application dataset.';
                r.diagnostics = {};
                if isstruct(D) && isfield(D,'Y') && iscell(D.Y) && numel(D.Y) >= v && ~isempty(D.Y{v})
                    r.present = true;
                    Yv = D.Y{v};
                    directNCases = NaN;
                    directNFeatures = NaN;
                    if isnumeric(Yv) || islogical(Yv)
                        directNCases = double(size(Yv,1));
                        if ismatrix(Yv)
                            directNFeatures = double(size(Yv,2));
                        else
                            szYv = size(Yv);
                            directNFeatures = double(prod(szYv(2:end)));
                        end
                    end
                    try
                        info = NMModalityInfoTools.fromNM(D, v, struct('ScanInMemory', true, 'MaxScanElements', 1e7));
                    catch ME
                        info = struct();
                        r.diagnostics = {sprintf('Could not summarize OOCV modality %d: %s (%s)', v, ME.message, ME.identifier)};
                    end
                    if isfield(info,'storageMode') && ~isempty(info.storageMode), r.storageMode = char(string(info.storageMode)); end
                    if strcmpi(r.storageMode,'memory')
                        r.status = 'present';
                    elseif strcmpi(r.storageMode,'external')
                        r.status = 'external';
                    else
                        r.status = 'present';
                    end
                    if isfield(info,'nSubjects') && isnumeric(info.nSubjects) && isscalar(info.nSubjects) && isfinite(double(info.nSubjects))
                        r.nCases = double(info.nSubjects);
                    elseif isfinite(directNCases)
                        r.nCases = directNCases;
                    elseif isfield(D,'cases') && ~isempty(D.cases)
                        try, r.nCases = double(numel(D.cases)); catch, end
                    end
                    if isfield(info,'nFeatures') && isnumeric(info.nFeatures) && isscalar(info.nFeatures) && isfinite(double(info.nFeatures))
                        r.nFeatures = double(info.nFeatures);
                    elseif isfinite(directNFeatures)
                        r.nFeatures = directNFeatures;
                    end
                    if isfield(info,'externalFileExists'), r.externalFileExists = info.externalFileExists; end
                    if isfield(info,'externalBasename') && ~isempty(info.externalBasename), r.externalBasename = char(string(info.externalBasename)); end
                    if isfield(info,'missingCasesFilledWithNaN') && ~isempty(info.missingCasesFilledWithNaN), r.missingCasesFilledWithNaN = logical(info.missingCasesFilledWithNaN); end
                    if isfield(info,'nMissingCasesFilledWithNaN') && isnumeric(info.nMissingCasesFilledWithNaN), r.nMissingCasesFilledWithNaN = double(info.nMissingCasesFilledWithNaN); end
                    if isfield(info,'requiresEarlyFusionImputation') && ~isempty(info.requiresEarlyFusionImputation), r.requiresEarlyFusionImputation = logical(info.requiresEarlyFusionImputation); end
                    if isfield(info,'diagnostics') && iscell(info.diagnostics), r.diagnostics = [r.diagnostics(:); info.diagnostics(:)]'; end
                    if r.requiresEarlyFusionImputation
                        r.message = 'Present; cases missing from this modality were added with missing values. Early-fusion application requires imputation.';
                    elseif strcmpi(r.storageMode,'external') && isequal(r.externalFileExists, false)
                        r.message = 'External link is unresolved.';
                    elseif strcmpi(r.storageMode,'external')
                        r.message = 'Present as external link.';
                    else
                        r.message = 'Present in memory.';
                    end
                elseif isstruct(D) && isfield(D,'datadescriptor') && iscell(D.datadescriptor) && numel(D.datadescriptor) >= v && ...
                        isstruct(D.datadescriptor{v}) && isfield(D.datadescriptor{v},'input_settings') && isstruct(D.datadescriptor{v}.input_settings)
                    input = D.datadescriptor{v}.input_settings;
                    isDraft = isfield(input,'draft') && isequal(input.draft,true);
                    isCompleted = isfield(input,'completed') && isequal(input.completed,true);
                    if isDraft && ~isCompleted
                        r.status = 'incomplete';
                        r.storageMode = 'unknown';
                        r.message = 'Incomplete OOCV/application import; resume to continue.';
                        try
                            info = NMModalityInfoTools.fromNM(D, v, struct('ScanInMemory', false, 'MaxScanElements', 0));
                            if isfield(info,'nSubjects') && isnumeric(info.nSubjects) && isscalar(info.nSubjects) && isfinite(double(info.nSubjects)), r.nCases = double(info.nSubjects); end
                            if isfield(info,'nFeatures') && isnumeric(info.nFeatures) && isscalar(info.nFeatures) && isfinite(double(info.nFeatures)), r.nFeatures = double(info.nFeatures); end
                            if isfield(info,'diagnostics') && iscell(info.diagnostics), r.diagnostics = [r.diagnostics(:); info.diagnostics(:)]'; end
                        catch ME
                            r.diagnostics = [r.diagnostics(:); {sprintf('Could not summarize incomplete OOCV modality %d: %s (%s)', v, ME.message, ME.identifier)}];
                        end
                    end
                end
                r = NMDataIOBrowserModeTools.attachOOCVQCArtifactSummary(NM, D, r, v);
                rows(end+1) = r; %#ok<AGROW>
            end
        end

        function r = attachOOCVQCArtifactSummary(NM, D, r, varind)
            % attachOOCVQCArtifactSummary  Attach derived metadata to a DataIO payload without altering source data values.
            %
            % Consumes D, r, varind; returns r.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % Cache contents are an acceleration/rehydration artifact, not a new source of truth.
            if ~isstruct(D) || ~isfield(D,'datadescriptor') || ~iscell(D.datadescriptor) || numel(D.datadescriptor) < varind
                return;
            end
            dd = D.datadescriptor{varind};
            if ~isstruct(dd) || ~isfield(dd,'QC') || ~isstruct(dd.QC)
                return;
            end
            r.hasQC = isfield(dd.QC,'payload') && isstruct(dd.QC.payload) && ~isempty(fieldnames(dd.QC.payload));
            r.hasQCReport = isfield(dd.QC,'report') && isstruct(dd.QC.report) && ~isempty(fieldnames(dd.QC.report));
            if ~r.hasQC, return; end
            q = dd.QC.payload;
            r.qcSummary = struct('method',NMDataIOBrowserModeTools.localText(q.method), ...
                'scoreName',NMDataIOBrowserModeTools.localText(q.scoreName), ...
                'featureSpace',NMDataIOBrowserModeTools.localText(q.featureSpace), ...
                'nSubjects',q.nSubjects, 'nFeatures',q.nFeatures, 'nValidFeatures',q.nValidFeatures, ...
                'subjectStats',struct(),'featureStats',struct(),'caseCompleteness',struct());
            if isfield(q,'subjectStats') && isstruct(q.subjectStats) && isfield(q.subjectStats,'summary') && isstruct(q.subjectStats.summary)
                r.qcSummary.subjectStats = q.subjectStats.summary;
            end
            % The QC producer owns the case-indexed vector at the top level;
            % subjectStats contains summary metadata, not a second vector authority.
            missingRate = double(q.missingFeatureRateBySubject(:));
            if ~isempty(missingRate)
                finiteRate = isfinite(missingRate);
                r.qcSummary.caseCompleteness = struct('nCompleteCases',double(nnz(finiteRate & missingRate == 0)), ...
                    'nPartialMissingCases',double(nnz(finiteRate & missingRate > 0 & missingRate < 1)), ...
                    'nAllMissingCases',double(nnz(finiteRate & missingRate >= 1)));
            end
            if isfield(q,'featureStats') && isstruct(q.featureStats) && isfield(q.featureStats,'summary') && isstruct(q.featureStats.summary)
                r.qcSummary.featureStats = q.featureStats.summary;
            end
            if isfield(q,'referenceShift') && isstruct(q.referenceShift) && ~isempty(fieldnames(q.referenceShift))
                trainQC = struct();
                if isstruct(NM) && isfield(NM,'datadescriptor') && iscell(NM.datadescriptor) && numel(NM.datadescriptor) >= varind && ...
                        isstruct(NM.datadescriptor{varind}) && isfield(NM.datadescriptor{varind},'QC') && isstruct(NM.datadescriptor{varind}.QC) && ...
                        isfield(NM.datadescriptor{varind}.QC,'payload') && isstruct(NM.datadescriptor{varind}.QC.payload)
                    trainQC = NM.datadescriptor{varind}.QC.payload;
                end
                rs = NMDataIOFeatureQCTools.referenceShiftForBrowser(q.referenceShift, trainQC, q);
                r.referenceShift = rs;
                r.distributionShiftStatus = NMDataIOBrowserModeTools.localText(rs.status);
                flagNames = {'mean','variance','missingness','outlier burden'};
                flags = flagNames(logical([rs.meanFlag rs.varianceFlag rs.missingnessFlag rs.outliernessFlag]));
                if isempty(flags)
                    r.distributionShiftSummary = 'No substantial discrepancy detected.';
                else
                    r.distributionShiftSummary = sprintf('Training/OOCV discrepancy: %s.', strjoin(flags, ', '));
                end
            end
            if isfield(q,'viewerOverlay') && isstruct(q.viewerOverlay)
                vo = q.viewerOverlay;
                token = NMDataIOBrowserModeTools.localText(NMDataIOBrowserModeTools.fieldOr(vo,'cacheToken', NMDataIOBrowserModeTools.fieldOr(vo,'persistedCacheToken','')));
                cacheFile = NMDataIOBrowserModeTools.localText(NMDataIOBrowserModeTools.fieldOr(vo,'persistedCacheFile', NMDataIOBrowserModeTools.fieldOr(vo,'sidecarAbsPath','')));
                r.hasQCViewerCache = ~isempty(token) || ~isempty(cacheFile);
                r.hasQCSidecar = ~isempty(cacheFile) && exist(cacheFile,'file') == 2;
                r.qcSidecarFile = cacheFile;
                r.qcSidecarRoot = NMDataIOBrowserModeTools.localText(NMDataIOBrowserModeTools.fieldOr(vo,'sidecarRoot',''));
                r.qcCacheStatus = NMDataIOBrowserModeTools.localText(NMDataIOBrowserModeTools.fieldOr(vo,'cacheStatus',''));
                r.qcCacheDurability = NMDataIOBrowserModeTools.localText(NMDataIOBrowserModeTools.fieldOr(vo,'cacheDurability',''));
            end
        end

        function v = fieldOr(s, field, defaultValue)
            % fieldOr  Read a struct field with a caller-specific default when the field is absent or empty.
            %
            % Consumes s, field, defaultValue; returns v.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            v = defaultValue;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field)), v = s.(field); end
        end

        function txt = localText(v)
            % localText  Convert browser-mode metadata values into compact diagnostic/display text.
            %
            % V -> txt.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            txt = '';
            if isempty(v), return; end
            if ischar(v), txt = strtrim(v); return; end
            if isstring(v) && isscalar(v), txt = strtrim(char(v)); return; end
            if isnumeric(v) || islogical(v), txt = strtrim(num2str(double(v(1)))); return; end
            try, txt = strtrim(char(string(v))); catch, txt = ''; end
        end

        function [NM, messages] = finalizeTrainingImport(NM)
            % finalizeTrainingImport  Mark training import as finalized while leaving application-mode activation to the main app.
            %
            % Consumes NM; returns NM, messages.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % Callers must use the returned NM value as the authoritative mutated container; diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 1 || isempty(NM), NM = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            if NMDataIOBrowserModeTools.committedModalityCount(NM) < 1
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'finalizeTrainingImport', ...
                    'Training data import cannot be finalized because no training modality has been completed. Import and Commit at least one modality first.', 1, 'red*')];
                return;
            end
            if ~isfield(NM,'defs') || ~isstruct(NM.defs), NM.defs = struct(); end
            if isfield(NM.defs,'import_finished') && ~isempty(NM.defs.import_finished) && logical(NM.defs.import_finished)
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'finalizeTrainingImport', ...
                    'Training data import is already finalized. Existing NM.id and locked training modalities were preserved.', 0, 'green*')];
                return;
            end
            if exist('genID','file') ~= 2
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'finalizeTrainingImport', ...
                    'Cannot finalize training data import because genID.m is not available on the MATLAB path.', 1, 'red*')];
                return;
            end
            try
                nmID = genID;
            catch ME
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'finalizeTrainingImport', ...
                    sprintf('Cannot finalize training data import because genID failed: %s: %s', ME.identifier, ME.message), 1, 'red*')];
                return;
            end
            if ~(ischar(nmID) || (isstring(nmID) && isscalar(nmID))) || strlength(string(nmID)) == 0
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'finalizeTrainingImport', ...
                    'Cannot finalize training data import because genID returned an empty or non-scalar identifier.', 1, 'red*')];
                return;
            end
            NM.id = char(string(nmID));
            NM.defs.import_finished = true;
            if ~isfield(NM.defs,'analyses_locked') || isempty(NM.defs.analyses_locked)
                NM.defs.analyses_locked = false;
            end
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'finalizeTrainingImport', ...
                sprintf('Training data import finalized and NM.id was set to %s. Training modality-changing actions are now disabled; storage maintenance and diagnostics remain available.', NM.id), 0, 'green*')];
        end

        function [NM, target, messages] = createOOCVContainer(NM, spec)
            % createOOCVContainer  Create a new OOCV/application container with validated metadata and empty modality slots.
            %
            % Consumes NM, spec; returns NM, target, messages.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Callers must use the returned NM value as the authoritative mutated container; diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            defs = NMDataIOBrowserModeTools.defsState(NM);
            if ~defs.import_finished || ~defs.analyses_locked
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'createOOCVContainer', ...
                    'OOCV/application datasets can only be managed after NM2 has entered application mode.', 1, 'red*')];
            end
            if NMDataIOImportTargetTools.nTrainingModalities(NM) < 1
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'createOOCVContainer', ...
                    'OOCV/application datasets require finalized training data.', 1, 'red*')];
            end
            if NMDataIOMessageTools.hasFatal(messages)
                target = struct('scope','oocv','containerField','OOCV','containerIndex',1,'varind',1);
                return;
            end
            idx = NMDataIOBrowserModeTools.nextOOCVIndex(NM, spec);
            labelsKnown = NMDataIOBrowserModeTools.specLogical(spec, {'labelsKnown','labels_known'}, false);
            desc = NMDataIOBrowserModeTools.specChar(spec, {'description','desc'}, sprintf('OOCV/application dataset %d', idx));
            target = struct('scope','oocv','containerField','OOCV','containerIndex',idx,'varind',1, ...
                'labels_known',labelsKnown,'description',desc);
            [NM, target, initMessages] = NMDataIOImportTargetTools.ensureContainer(NM, target);
            messages = [messages; initMessages];
            if ~NMDataIOMessageTools.hasFatal(messages)
                NM.OOCV{idx}.desc = desc;
                NM.OOCV{idx}.labels_known = labelsKnown;
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'createOOCVContainer', ...
                    sprintf('Created OOCV/application dataset %d.', idx), 0, 'green*')];
            end
        end

        function [NM, messages] = deleteOOCVContainer(NM, idx)
            % deleteOOCVContainer  Remove an OOCV/application container after validating the requested index.
            %
            % Consumes NM, idx; returns NM, messages.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % Callers must use the returned NM value as the authoritative mutated container; diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            idx = max(1, round(double(idx)));
            defs = NMDataIOBrowserModeTools.defsState(NM);
            if ~defs.import_finished || ~defs.analyses_locked
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'deleteOOCVContainer', ...
                    'OOCV/application datasets can only be deleted in application mode.', 1, 'red*')];
                return;
            end
            if ~isfield(NM,'OOCV') || ~iscell(NM.OOCV) || numel(NM.OOCV) < idx || isempty(NM.OOCV{idx})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'deleteOOCVContainer', ...
                    sprintf('OOCV/application dataset %d does not exist.', idx), 1, 'red*')];
                return;
            end
            lifecycle = NMDataIOBrowserModeTools.oocvLifecycleState(NM, idx);
            if ~lifecycle.canDelete
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'deleteOOCVContainer', ...
                    lifecycle.deleteMessage, 1, 'red*')];
                return;
            end
            NM = NMOOCVApplicationPreprocTools.removeOOCVIndex(NM, idx);
            NM.OOCV(idx) = [];
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'deleteOOCVContainer', ...
                sprintf('Deleted OOCV/application dataset %d.', idx), 0, 'green*')];
        end

        function [NM, messages] = setOOCVLabelsKnown(NM, idx, labelsKnown)
            % setOOCVLabelsKnown  Update whether ground-truth labels are available for one OOCV/application container.
            %
            % NM, idx, labelsKnown -> NM, messages.
            % NM.OOCV{idx}.labels_known is the canonical authority consumed by OOCV import preparation and readiness.
            messages = NMDataIOMessageTools.emptyMessages();
            idx = max(1, round(double(idx)));
            defs = NMDataIOBrowserModeTools.defsState(NM);
            if ~defs.import_finished || ~defs.analyses_locked
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'setOOCVLabelsKnown', ...
                    'OOCV/application label availability can only be changed in application mode.', 1, 'red*')];
                return;
            end
            if ~isfield(NM,'OOCV') || ~iscell(NM.OOCV) || numel(NM.OOCV) < idx || isempty(NM.OOCV{idx}) || ~isstruct(NM.OOCV{idx})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'setOOCVLabelsKnown', ...
                    sprintf('OOCV/application dataset %d does not exist.', idx), 1, 'red*')];
                return;
            end
            if NMAnalysisManagerTools.oocvAnalysisUsed(NM, idx)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'setOOCVLabelsKnown', ...
                    sprintf('OOCV/application dataset %d cannot be modified because it is referenced by retained analysis results.', idx), 1, 'red*')];
                return;
            end
            labelsKnown = logical(labelsKnown);
            if ~isscalar(labelsKnown)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'setOOCVLabelsKnown', ...
                    'OOCV labels_known must be a scalar logical value.', 1, 'red*')];
                return;
            end
            if ~labelsKnown && isfield(NM.OOCV{idx},'label') && ~isempty(NM.OOCV{idx}.label)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'setOOCVLabelsKnown', ...
                    'This OOCV dataset already contains imported labels, so labels cannot be marked unavailable.', 1, 'red*')];
                return;
            end
            NM.OOCV{idx}.labels_known = labelsKnown;
            if labelsKnown
                txt = sprintf('OOCV/application dataset %d now requires compatible ground-truth labels.', idx);
            else
                txt = sprintf('OOCV/application dataset %d is configured for prediction/application without ground-truth labels.', idx);
            end
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'setOOCVLabelsKnown', txt, 0, 'green*')];
        end

        function [NM, grouping, messages] = configureOOCVGroups(NM, idx, spec, commit)
            % configureOOCVGroups  Materialize one OOCV subgroup vector on the established container Case-ID axis.
            % Reuses the generic auxiliary covariate reader/alignment authority; subgroup semantics are applied only after alignment.
            if nargin < 3 || isempty(spec), spec = struct(); end
            if nargin < 4 || isempty(commit), commit = false; end
            messages = NMDataIOMessageTools.emptyMessages();
            grouping = struct('configured',false,'nGroups',0,'sourceValues',[],'groupCounts',[],'groupNames',{{}},'refGroup',[],'refGroupName','','inputSettings',struct());
            idx = max(1, round(double(idx)));
            defs = NMDataIOBrowserModeTools.defsState(NM);
            if ~defs.import_finished || ~defs.analyses_locked
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'oocv.groups', ...
                    'OOCV subgroup definitions can only be changed in application mode.', 1, 'red*')];
                return;
            end
            if ~isfield(NM,'OOCV') || ~iscell(NM.OOCV) || numel(NM.OOCV) < idx || isempty(NM.OOCV{idx}) || ~isstruct(NM.OOCV{idx})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'oocv.groups', ...
                    sprintf('OOCV/application dataset %d does not exist.', idx), 1, 'red*')];
                return;
            end
            D = NM.OOCV{idx};
            if commit && NMAnalysisManagerTools.oocvAnalysisUsed(NM, idx)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'oocv.groups', ...
                    sprintf('OOCV/application dataset %d cannot be modified because it is referenced by retained analysis results.', idx), 1, 'red*')];
                return;
            end
            clearRequested = NMDataIOBrowserModeTools.specLogical(spec, {'clear'}, false) || strcmpi(NMDataIOBrowserModeTools.specChar(spec, {'sourceType'}, ''), 'none');
            if clearRequested
                if commit
                    for f = {'groups','grpnames','refgroup','group_input_settings'}
                        if isfield(D,f{1}), D = rmfield(D,f{1}); end
                    end
                    NM.OOCV{idx} = D;
                end
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'oocv.groups', ...
                    sprintf('OOCV/application dataset %d subgroup definition is empty.', idx), 0, 'green*')];
                return;
            end
            if ~isfield(D,'cases') || isempty(D.cases)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'oocv.groups', ...
                    'Import the first OOCV modality before defining study groups so that the OOCV Case IDs are available.', 1, 'red*')];
                return;
            end
            sourceType = lower(NMDataIOBrowserModeTools.specChar(spec, {'sourceType'}, 'workspace'));
            if ~ismember(sourceType, {'workspace','tablefile'})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'oocv.groups', ...
                    'OOCV study groups support MATLAB workspace or CSV/spreadsheet sources.', 1, 'red*')];
                return;
            end
            IO = NMDataIOStateTools.defaultIO(NM, 1);
            IO.sourceType = sourceType;
            IO.groupmode = NMDataIOStateTools.groupmodeFromSourceType(sourceType, 1);
            IO.modeflag = 'regression';
            IO.metadataAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode( ...
                NMDataIOBrowserModeTools.specChar(spec, {'alignmentMode','metadataAlignmentMode'}, 'case_id'));
            if isfield(spec,'variableRoles') && isstruct(spec.variableRoles), IO.variableRoles = spec.variableRoles; end
            if isfield(spec,'tableFiles'), IO.tableFiles = spec.tableFiles; end
            if isfield(spec,'sheets'), IO.sheets = spec.sheets; end
            if isfield(spec,'sheet'), IO.sheet = spec.sheet; end
            [IO, roleMessages] = NMDataIOImportTools.materializeVariableRolePayload(IO, D.cases);
            messages = [messages; roleMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            g = NMDataIOBrowserModeTools.fieldOr(IO,'covars',[]);
            if ~(isnumeric(g) || islogical(g)) || size(g,2) ~= 1 || size(g,1) ~= numel(D.cases)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'oocv.groups', ...
                    'Assign exactly one numeric group-label vector with one value for every OOCV case.', 1, 'red*')];
                return;
            end
            g = double(g(:,1));
            if any(~isfinite(g))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'oocv.groups', ...
                    'OOCV study-group labels must be finite for every case; missing group membership is not supported.', 1, 'red*')];
                return;
            end
            sourceValues = unique(g,'sorted');
            if numel(sourceValues) < 2
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'oocv.groups', ...
                    'OOCV subgroup stratification requires at least two distinct group labels.', 1, 'red*')];
                return;
            end
            groupIDs = zeros(size(g));
            for k = 1:numel(sourceValues), groupIDs(g == sourceValues(k)) = k; end
            rawGroupNames = NMDataIOBrowserModeTools.fieldOr(spec,'groupNames', ...
                NMDataIOBrowserModeTools.fieldOr(spec,'grpnames',{}));
            if ischar(rawGroupNames)
                groupNames = {strtrim(rawGroupNames)};
            elseif isstring(rawGroupNames)
                groupNames = cellstr(strtrim(rawGroupNames(:)))';
            elseif iscell(rawGroupNames)
                groupNames = cellfun(@(x)strtrim(char(string(x))), rawGroupNames(:)', 'UniformOutput', false);
            elseif isempty(rawGroupNames)
                groupNames = {};
            else
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'oocv.groups', ...
                    'Group names must be text values.', 1, 'red*')];
                return;
            end
            if isempty(groupNames)
                groupNames = arrayfun(@(x)sprintf('Group %g',x), sourceValues, 'UniformOutput', false);
            end
            if numel(groupNames) ~= numel(sourceValues) || any(cellfun(@isempty, groupNames))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'oocv.groups', ...
                    sprintf('Provide exactly %d non-empty group name(s), one for each distinct group label.', numel(sourceValues)), 1, 'red*')];
                return;
            end
            refGroup = NMDataIOBrowserModeTools.specNumber(spec, {'refGroup','refgroup'}, []);
            if ~isempty(refGroup)
                refGroup = round(double(refGroup));
                if ~isscalar(refGroup) || ~ismember(refGroup, 1:numel(sourceValues))
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'oocv.groups', ...
                        'Select one of the defined OOCV study groups as the reference group.', 1, 'red*')];
                    return;
                end
            end
            inputSettings = struct('sourceType',sourceType,'alignmentMode',IO.metadataAlignmentMode, ...
                'variableRoles',IO.variableRoles,'tableFiles',{NMDataIOBrowserModeTools.fieldOr(IO,'tableFiles',{})}, ...
                'sheets',{NMDataIOBrowserModeTools.fieldOr(IO,'sheets',{})},'sourceValues',sourceValues(:)', ...
                'groupNames',{groupNames(:)'},'refGroup',refGroup);
            groupCounts = arrayfun(@(k)nnz(groupIDs == k), 1:numel(sourceValues));
            grouping = struct('configured',true,'nGroups',numel(sourceValues),'sourceValues',sourceValues(:)','groupCounts',groupCounts, ...
                'groupNames',{groupNames(:)'},'refGroup',refGroup,'refGroupName','','inputSettings',inputSettings);
            if ~isempty(refGroup), grouping.refGroupName = groupNames{refGroup}; end
            if commit
                D.groups = groupIDs;
                D.grpnames = groupNames(:)';
                if isempty(refGroup)
                    if isfield(D,'refgroup'), D = rmfield(D,'refgroup'); end
                else
                    D.refgroup = refGroup;
                end
                D.group_input_settings = inputSettings;
                NM.OOCV{idx} = D;
            end
            if commit, actionText = 'Stored'; else, actionText = 'Previewed'; end
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'oocv.groups', ...
                sprintf('%s OOCV study-group definition with %d groups aligned to %d cases.', ...
                actionText, numel(sourceValues), numel(groupIDs)), 0, 'green*')];
        end

        function lifecycle = oocvLifecycleState(NM, idx)
            % oocvLifecycleState  Project persisted analysis ownership into OOCV mutation/deletion capabilities.
            idx = max(1, round(double(idx)));
            lifecycle = struct('analysisUsed',NMAnalysisManagerTools.oocvAnalysisUsed(NM,idx), ...
                'canModify',false,'canDelete',false,'deleteMessage','');
            lifecycle.canModify = ~lifecycle.analysisUsed;
            higherUsed = false;
            if isstruct(NM) && isfield(NM,'OOCV') && iscell(NM.OOCV)
                for j = idx+1:numel(NM.OOCV)
                    if ~isempty(NM.OOCV{j}) && isstruct(NM.OOCV{j}) && NMAnalysisManagerTools.oocvAnalysisUsed(NM,j)
                        higherUsed = true;
                        break;
                    end
                end
            end
            lifecycle.canDelete = ~lifecycle.analysisUsed && ~higherUsed;
            if lifecycle.analysisUsed
                lifecycle.deleteMessage = sprintf('OOCV/application dataset %d cannot be deleted because it is referenced by retained analysis results.',idx);
            elseif higherUsed
                lifecycle.deleteMessage = sprintf('OOCV/application dataset %d cannot be deleted because doing so would renumber a later dataset referenced by retained analysis results.',idx);
            end
        end

        function grouping = oocvGroupingState(D)
            grouping = struct('configured',false,'nGroups',0,'sourceValues',[],'groupCounts',[],'groupNames',{{}},'refGroup',[],'refGroupName','','inputSettings',struct());
            if ~isstruct(D) || ~isfield(D,'groups') || isempty(D.groups), return; end
            if islogical(D.groups) && size(D.groups,2) > 1
                [~,g] = max(D.groups,[],2);
                g = double(g(:));
            else
                g = double(D.groups(:));
            end
            if numel(g) < 1 || any(~isfinite(g)), return; end
            ids = unique(g,'sorted');
            grouping.configured = true;
            grouping.nGroups = numel(ids);
            grouping.sourceValues = ids(:)';
            grouping.groupCounts = arrayfun(@(x)nnz(g == x), ids);
            if isfield(D,'grpnames') && numel(D.grpnames) == numel(ids)
                grouping.groupNames = cellstr(string(D.grpnames(:)'));
            else
                grouping.groupNames = arrayfun(@(x)sprintf('Group %g',x), ids, 'UniformOutput', false);
            end
            if isfield(D,'refgroup') && isscalar(D.refgroup) && any(g == double(D.refgroup))
                grouping.refGroup = double(D.refgroup);
                if grouping.refGroup >= 1 && grouping.refGroup <= numel(grouping.groupNames), grouping.refGroupName = grouping.groupNames{grouping.refGroup}; end
            end
            if isfield(D,'group_input_settings') && isstruct(D.group_input_settings)
                grouping.inputSettings = D.group_input_settings;
                if isfield(D.group_input_settings,'sourceValues') && numel(D.group_input_settings.sourceValues) == numel(ids)
                    grouping.sourceValues = double(D.group_input_settings.sourceValues(:)');
                end
            end
        end

        function [NM, messages] = renameOOCVContainer(NM, idx, newDesc)
            % renameOOCVContainer  Update the description of an existing OOCV/application container.
            %
            % Consumes NM, idx, newDesc; returns NM, messages.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % Callers must use the returned NM value as the authoritative mutated container; diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            idx = max(1, round(double(idx)));
            defs = NMDataIOBrowserModeTools.defsState(NM);
            if ~defs.import_finished || ~defs.analyses_locked
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'renameOOCVContainer', ...
                    'OOCV/application datasets can only be renamed in application mode.', 1, 'red*')];
                return;
            end
            if ~isfield(NM,'OOCV') || ~iscell(NM.OOCV) || numel(NM.OOCV) < idx || isempty(NM.OOCV{idx}) || ~isstruct(NM.OOCV{idx})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'renameOOCVContainer', ...
                    sprintf('OOCV/application dataset %d does not exist.', idx), 1, 'red*')];
                return;
            end
            newDesc = strtrim(char(string(newDesc)));
            if isempty(newDesc)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'renameOOCVContainer', ...
                    'A non-empty OOCV/application dataset name is required.', 1, 'red*')];
                return;
            end
            NM.OOCV{idx}.desc = newDesc;
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'renameOOCVContainer', ...
                sprintf('Renamed OOCV/application dataset %d to "%s".', idx, newDesc), 0, 'green*')];
        end

        function [importState, messages] = prepareOOCVImportState(NM, containerIndex, varind, spec)
            % prepareOOCVImportState  Create an import state for adding/replacing/resuming a modality inside an OOCV container.
            %
            % Consumes NM, containerIndex, varind, spec; returns importState, messages.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 4 || isempty(spec), spec = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            defs = NMDataIOBrowserModeTools.defsState(NM);
            if ~defs.import_finished || ~defs.analyses_locked
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareOOCVImportState', ...
                    'OOCV/application import is only available in application mode.', 1, 'red*')];
            end
            if isnan(containerIndex) || containerIndex < 1, containerIndex = 1; end
            if isnan(varind) || varind < 1, varind = 1; end
            if NMDataIOImportTargetTools.nTrainingModalities(NM) < varind
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareOOCVImportState', ...
                    sprintf('Data modality %d does not exist. OOCV import must map to an existing NM modality feature space.', varind), 1, 'red*')];
            end
            target = struct('scope','oocv','containerField','OOCV','containerIndex',containerIndex,'varind',varind);
            messages = [messages; NMDataIOImportTargetTools.validateForImport(NM, target)];
            [D, containerMessages] = NMDataIOImportTargetTools.getContainer(NM, target);
            messages = [messages; containerMessages];
            if NMDataIOMessageTools.hasFatal(messages)
                importState = struct();
                return;
            end
            if isfield(D,'labels_known') && ~isempty(D.labels_known), labelsKnown = logical(D.labels_known); else, labelsKnown = false; end
            target.labels_known = labelsKnown;
            target.description = char(string(D.desc));
            hasCommitted = isfield(D,'Y') && iscell(D.Y) && numel(D.Y) >= varind && ~isempty(D.Y{varind});
            hasDraft = false;
            importState = struct();
            savedSettings = struct();
            if isfield(D,'datadescriptor') && iscell(D.datadescriptor) && numel(D.datadescriptor) >= varind && ...
                    isstruct(D.datadescriptor{varind}) && isfield(D.datadescriptor{varind},'input_settings') && isstruct(D.datadescriptor{varind}.input_settings)
                savedSettings = D.datadescriptor{varind}.input_settings;
                hasDraft = isfield(savedSettings,'draft') && isequal(savedSettings.draft,true) && ...
                    (~isfield(savedSettings,'completed') || ~isequal(savedSettings.completed,true));
            end
            hasSavedSettings = ~isempty(fieldnames(savedSettings));
            if hasDraft || (hasCommitted && hasSavedSettings)
                try
                    importState = NMDataIOStateTools.ioToState(savedSettings);
                catch ME
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareOOCVImportState.resume', ...
                        sprintf('Could not restore the saved OOCV import state for dataset %d modality %d. %s (%s)', containerIndex, varind, ME.message, ME.identifier), 1, 'red*')];
                    importState = struct();
                    return;
                end
            end
            if hasCommitted
                target.mode = 'replace';
            elseif hasDraft
                target.mode = 'resume';
            else
                target.mode = 'add';
            end
            if ~hasDraft && (~hasCommitted || ~hasSavedSettings)
                importState = NMDataIOStateTools.defaultMatrixState(NM, varind);
            end
            importState.importTarget = target;
            importState.varind = varind;
            importState.oocvflag = true;
            importState.labels_known = labelsKnown;
            importState.oocvLabelsPresent = labelsKnown && isfield(D,'label') && ~isempty(D.label);
            importState.draftDirty = false;
            [importState, scientificMessages] = NMDataIOBrowserModeTools.applyOOCVScientificContract(NM, varind, importState);
            messages = [messages; scientificMessages];
            if NMDataIOMessageTools.hasFatal(messages)
                importState = struct();
                return;
            end
            if isfield(importState,'matrix') && isstruct(importState.matrix)
                importState.matrix.sourceType = importState.sourceType;
            end

            if hasDraft
                taskText = 'Resumed';
            elseif hasCommitted
                taskText = 'Prepared replacement for';
            else
                taskText = 'Prepared';
            end
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'prepareOOCVImportState', ...
                sprintf('%s OOCV/application import for dataset %d, modality %d. The imported data must match the trained model''s feature definition. You may select the OOCV data source independently.', taskText, containerIndex, varind), 0, 'green*')];
        end

        function [state, messages] = applyOOCVScientificContract(NM, varind, state)
            % applyOOCVScientificContract  Project the training modality's scientific contract into OOCV DataIO state.
            %
            % Purpose:
            %   Keep training/OOCV scientific parity at the DataIO state boundary while leaving
            %   the concrete OOCV subject-data representation independently selectable.
            %
            % Authority and flow:
            %   Existing training datadescriptor/input_settings, canonical ROI provenance and
            %   canonical connectivity provenance are the authorities. This method only projects
            %   those facts into browser state and a transient presentation policy; it does not
            %   create or persist a second provenance object. The projection is reapplied to both
            %   fresh and resumed OOCV imports so stale draft controls cannot redefine training
            %   scientific settings.
            %
            % Scientific/state contract:
            %   Spatial/ROI/connectivity identity, training weighting policy and global-correction
            %   semantics are fixed by training. OOCV data files/tables/workspace variables and
            %   subject-specific globals remain OOCV inputs. Weighting/ranking definitions and
            %   connectivity subspace selection are training-side model-space settings and are not
            %   re-specified for OOCV data.
            %
            % Materialization and performance:
            %   No files are read. No XML, atlas, annotation, mesh, voxel or vertex data are
            %   scanned. No feature-scale arrays are created. Safe on the OOCV import preparation
            %   path; downstream source materialization remains owned by the existing DataIO tools.
            %
            % Failure semantics:
            %   Missing/invalid canonical training ROI or connectivity provenance yields an
            %   explicit blocking DataIO diagnostic. No scientific setting is guessed.
            messages = NMDataIOMessageTools.emptyMessages();
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || numel(NM.datadescriptor) < varind || ...
                    ~isstruct(NM.datadescriptor{varind})
                return;
            end
            dd = NM.datadescriptor{varind};
            input = struct();
            if isfield(dd,'input_settings') && isstruct(dd.input_settings), input = dd.input_settings; end
            policy = struct('active',true,'family','matrix','lockDescription',true,'lockSourceFamily',false,'sourceType','', ...
                'lockSpatialIdentity',false,'lockROISidecar',false,'lockCAT12Selection',false, ...
                'lockConnectivityIdentity',false,'lockGlobalCorrection',false,'requireGlobalVariable',false, ...
                'hideWeighting',false,'hideConnectivitySubspace',false);
            if isfield(dd,'desc') && ~isempty(dd.desc), state.desc_data = char(string(dd.desc)); end

            if NMDataIOROIProvenanceTools.declaredInDescriptor(dd)
                nColumns = [];
                if isfield(NM,'Y') && iscell(NM.Y) && numel(NM.Y) >= varind && ~isempty(NM.Y{varind})
                    nColumns = size(NM.Y{varind},2);
                end
                roiProvenance = NMDataIOROIProvenanceTools.normalizeDescriptor(dd, nColumns);
                if ~roiProvenance.ok
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareOOCVImportState.roiProvenance', ...
                        sprintf('Training modality %d contains ROI data, but its saved ROI definition is invalid: %s', varind, roiProvenance.message), 1, 'red*')];
                    return;
                end
                policy.family = 'roi';
                policy.lockSourceFamily = true;
                policy.sourceType = 'roi';
                policy.lockSpatialIdentity = true;
                policy.hideWeighting = true;
                if ~isfield(state,'roi') || ~isstruct(state.roi), state.roi = struct(); end
                if ~isfield(state.roi,'sourceFormat') || isempty(state.roi.sourceFormat), state.roi.sourceFormat = 'workspace_matrix'; end
                if ~isfield(state.roi,'auxiliaryAlignmentMode') || isempty(state.roi.auxiliaryAlignmentMode), state.roi.auxiliaryAlignmentMode = 'case_id'; end
                if ~isfield(state.roi,'labelMode') || isempty(state.roi.labelMode), state.roi.labelMode = 'metadata'; end
                if ~isfield(state.roi,'caseIDMode') || isempty(state.roi.caseIDMode), state.roi.caseIDMode = 'explicit'; end
                state.sourceType = 'roi'; state.datasource = 'matrix'; state.groupmode = 1;

                if isfield(roiProvenance,'spatialReferences') && numel(roiProvenance.spatialReferences) == 1
                    ref = roiProvenance.spatialReferences(1);
                    kind = '';
                    if isfield(ref,'kind') && ~isempty(ref.kind), kind = char(string(ref.kind)); end
                    if any(strcmp(kind, {'volumetric_atlas','surface_annotation'}))
                        state.roi.spatialKind = kind;
                        state.roi.uiSpatialKindSelection = kind;
                    end
                    if strcmp(kind,'volumetric_atlas') && isfield(ref,'sourceFiles') && iscell(ref.sourceFiles) && numel(ref.sourceFiles) == 1 && ~isempty(ref.sourceFiles{1})
                        state.roi.atlasFile = char(string(ref.sourceFiles{1}));
                    elseif strcmp(kind,'surface_annotation')
                        if isfield(ref,'annotationFilesByHemisphere') && isstruct(ref.annotationFilesByHemisphere)
                            byHemi = ref.annotationFilesByHemisphere;
                            if isfield(byHemi,'lh') && iscell(byHemi.lh) && numel(byHemi.lh) == 1 && ~isempty(byHemi.lh{1}), state.roi.lhAnnotationFile = char(string(byHemi.lh{1})); end
                            if isfield(byHemi,'rh') && iscell(byHemi.rh) && numel(byHemi.rh) == 1 && ~isempty(byHemi.rh{1}), state.roi.rhAnnotationFile = char(string(byHemi.rh{1})); end
                        end
                        if isfield(ref,'surfaceGeometryFilesByHemisphere') && isstruct(ref.surfaceGeometryFilesByHemisphere)
                            byHemi = ref.surfaceGeometryFilesByHemisphere;
                            if isfield(byHemi,'lh') && iscell(byHemi.lh) && numel(byHemi.lh) == 1 && ~isempty(byHemi.lh{1}), state.roi.lhSurfaceGeometryFile = char(string(byHemi.lh{1})); end
                            if isfield(byHemi,'rh') && iscell(byHemi.rh) && numel(byHemi.rh) == 1 && ~isempty(byHemi.rh{1}), state.roi.rhSurfaceGeometryFile = char(string(byHemi.rh{1})); end
                        end
                    end
                end

                trainROISpec = struct();
                if isfield(input,'roiSpec') && isstruct(input.roiSpec), trainROISpec = input.roiSpec; end
                sidecarFields = {'roiSidecarFile','roiIDColumn','roiNameColumn','roiHemisphereColumn','roiXColumn','roiYColumn','roiZColumn'};
                for ii = 1:numel(sidecarFields)
                    name = sidecarFields{ii};
                    if isfield(trainROISpec,name) && ~isempty(trainROISpec.(name)), state.roi.(name) = trainROISpec.(name); end
                end
                policy.lockROISidecar = isfield(trainROISpec,'roiSidecarFile') && ~isempty(trainROISpec.roiSidecarFile);
                catFields = {'cat12Atlas','cat12Measure'};
                for ii = 1:numel(catFields)
                    name = catFields{ii};
                    if isfield(trainROISpec,name) && ~isempty(trainROISpec.(name)), state.roi.(name) = trainROISpec.(name); end
                end
                policy.lockCAT12Selection = isfield(trainROISpec,'cat12Atlas') && ~isempty(trainROISpec.cat12Atlas) && ...
                    isfield(trainROISpec,'cat12Measure') && ~isempty(trainROISpec.cat12Measure);
                state.roi.weightingFiles = {};

                correctionMode = 'none';
                correctionName = '';
                correctionMultiplier = [];
                if isfield(dd,'globalVolumeCorrection') && isstruct(dd.globalVolumeCorrection) && isscalar(dd.globalVolumeCorrection)
                    correction = dd.globalVolumeCorrection;
                    if isfield(correction,'mode') && ~isempty(correction.mode), correctionMode = char(string(correction.mode)); end
                    if isfield(correction,'globalName') && ~isempty(correction.globalName), correctionName = char(string(correction.globalName)); end
                    if isfield(correction,'globalMultiplier') && isnumeric(correction.globalMultiplier) && isscalar(correction.globalMultiplier) && isfinite(correction.globalMultiplier)
                        correctionMultiplier = double(correction.globalMultiplier);
                    end
                elseif isfield(trainROISpec,'globalMode') || isfield(trainROISpec,'uiGlobalModeSelection')
                    correctionMode = NMDataIOBrowserModeTools.specChar(trainROISpec, {'globalMode','uiGlobalModeSelection'}, 'none');
                    correctionName = NMDataIOBrowserModeTools.specChar(trainROISpec, {'globalName'}, '');
                    if isfield(trainROISpec,'globnorm') && isnumeric(trainROISpec.globnorm) && isscalar(trainROISpec.globnorm) && isfinite(trainROISpec.globnorm)
                        correctionMultiplier = double(trainROISpec.globnorm);
                    end
                else
                    correctionMode = NMDataIOBrowserModeTools.specChar(input, {'globalMode','uiGlobalModeSelection'}, 'none');
                    correctionName = NMDataIOBrowserModeTools.specChar(input, {'globalName'}, '');
                    if isfield(input,'globnorm') && isnumeric(input.globnorm) && isscalar(input.globnorm) && isfinite(input.globnorm)
                        correctionMultiplier = double(input.globnorm);
                    end
                end
                state.roi.uiGlobalModeSelection = correctionMode;
                state.roi.globalMode = correctionMode;
                correctionSource = NMDataIOBrowserModeTools.specChar(trainROISpec, {'globalSource'}, 'user');
                state.roi.globalSource = correctionSource;
                if ~isempty(correctionName), state.roi.globalName = correctionName; end
                if ~isempty(correctionMultiplier), state.roi.globnorm = correctionMultiplier; end
                if isfield(state.roi,'spatialKind') && strcmp(char(string(state.roi.spatialKind)),'volumetric_atlas')
                    policy.lockGlobalCorrection = true;
                    policy.requireGlobalVariable = ~strcmpi(correctionMode,'none') && strcmpi(correctionSource,'user');
                end
                state.oocvScientificPolicy = policy;
                return;
            end

            if isfield(dd,'source') && strcmpi(char(string(dd.source)), 'connectivity')
                if ~isfield(dd,'connectivity') || ~isstruct(dd.connectivity) || ...
                        ~isfield(dd.connectivity,'nodeIDs') || isempty(dd.connectivity.nodeIDs) || ...
                        ~isfield(dd.connectivity,'edgeIndex') || isempty(dd.connectivity.edgeIndex)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareOOCVImportState.connectivityProvenance', ...
                        sprintf('Training connectivity modality %d is missing the node IDs or edge definition required for OOCV matching.', varind), 1, 'red*')];
                    return;
                end
                policy.family = 'connectivity';
                policy.lockSourceFamily = true;
                policy.sourceType = 'connectivity';
                policy.lockConnectivityIdentity = true;
                policy.hideWeighting = true;
                policy.hideConnectivitySubspace = true;
                provenance = dd.connectivity;
                state.sourceType = 'connectivity'; state.datasource = 'matrix'; state.groupmode = 1;
                if ~isfield(state,'connectivity') || ~isstruct(state.connectivity), state.connectivity = struct(); end
                fixedFields = {'nNodes','matrixType','triangle','includeDiagonal','symmetryTolerance','atlasFile','atlasLabelFile', ...
                    'atlasLabelDelimiter','atlasLabelHasHeader','atlasLabelIDColumn','atlasLabelNameColumn','atlasLabelXColumn','atlasLabelYColumn', ...
                    'atlasLabelZColumn','nodeCoordinateSpace','nodeCoordinateUnits'};
                for ii = 1:numel(fixedFields)
                    name = fixedFields{ii};
                    if isfield(provenance,name) && ~isempty(provenance.(name)), state.connectivity.(name) = provenance.(name); end
                end
                state.connectivity.weightingMatrices = '';
                state.connectivity.weightingFiles = {};
                state.connectivity.weightingNames = {};
                state.connectivity.weightingMatVariable = '';
                state.connectivity.subspace = struct('enabled',false);
                state.oocvScientificPolicy = policy;
                return;
            end

            src = '';
            if isfield(input,'datasource') && ~isempty(input.datasource), src = lower(char(string(input.datasource))); end
            if isempty(src) && isfield(dd,'source') && ~isempty(dd.source), src = lower(char(string(dd.source))); end
            isSurface = strcmp(src,'surf') || (isfield(dd,'surfaceRoiCollapse') && logical(dd.surfaceRoiCollapse));
            isSpatialImage = any(strcmp(src, {'nifti','spm','image'})) || ...
                (isfield(input,'spaceDefType') && ~isempty(input.spaceDefType)) || ...
                (isfield(dd,'atlasCollapse') && logical(dd.atlasCollapse)) || ...
                (isfield(dd,'type') && isnumeric(dd.type) && any(double(dd.type(:)) == 2) && ~isSurface);
            if isSurface || isSpatialImage
                freshImageState = ~isfield(state,'image') || ~isstruct(state.image);
                if freshImageState
                    state.image = struct('imageFiles',{{}},'caseIds',{{}},'weightingFiles',{{}}, ...
                        'auxiliarySourceType','workspace','auxiliaryAlignmentMode','case_id', ...
                        'auxiliaryVariableRoles',struct(),'auxiliaryTableFiles',{{}}, ...
                        'globalUserSourceType','workspace','globalAlignmentMode','case_id', ...
                        'globalVariableRoles',struct(),'globalTableFiles',{{}}, ...
                        'labelMode','metadata','caseIDMode','explicit');
                end
                if isSurface
                    policy.family = 'surface'; policy.sourceType = 'surface-list';
                    state.sourceType = 'surface-list'; state.datasource = 'surf'; state.groupmode = -2;
                else
                    policy.family = 'volume'; policy.sourceType = 'image-list';
                    state.sourceType = 'image-list'; state.datasource = 'nifti'; state.groupmode = -2;
                end
                policy.lockSourceFamily = true;
                policy.lockSpatialIdentity = true;
                policy.hideWeighting = true;
                fixedFields = {'Thresh','threshop','threshval','threshlabels','maskFile','spaceDefType','atlasImportMode','atlasCollapseMethod','excludeSubjectZeros', ...
                    'atlasLabelNames','atlasLabelFile','atlasLabelDelimiter','atlasLabelHasHeader','atlasLabelIDColumn','atlasLabelNameColumn', ...
                    'surfaceImportMode','surfaceTemplate','surfaceHemisphere','surfaceGeometryFile','surfaceInflatedGeometryFile', ...
                    'surfaceGeometryIdentity','surfaceInflatedGeometryIdentity','surfaceTopologyIdentity','surfaceVertexOrderIdentity', ...
                    'surfaceInflatedValidated','surfaceGeometryContract','surfaceRoiCollapseMethod'};
                for ii = 1:numel(fixedFields)
                    name = fixedFields{ii};
                    if isfield(input,name) && ~isempty(input.(name)), state.image.(name) = input.(name); end
                end
                state.image.weightingFiles = {};
                globalMode = NMDataIOBrowserModeTools.specChar(input, {'uiGlobalModeSelection','globalMode'}, 'none');
                globalSource = NMDataIOBrowserModeTools.specChar(input, {'globalSource'}, 'user');
                state.image.uiGlobalModeSelection = globalMode;
                state.image.globalMode = globalMode;
                state.image.globalSource = globalSource;
                if isfield(input,'globalName') && ~isempty(input.globalName), state.image.globalName = input.globalName; end
                if isfield(input,'globnorm') && isnumeric(input.globnorm) && isscalar(input.globnorm) && isfinite(input.globnorm), state.image.globnorm = double(input.globnorm); end
                policy.lockGlobalCorrection = true;
                policy.requireGlobalVariable = ~strcmpi(globalMode,'none') && strcmpi(globalSource,'user');
                state.oocvScientificPolicy = policy;
                return;
            end

            state.oocvScientificPolicy = policy;
        end

        function n = committedModalityCount(NM)
            % committedModalityCount  Count committed training modalities available for browser/OOCV operations.
            %
            % NM -> n.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % Read-only count derived from NM.Y; it does not inspect payload matrices or mutate NM.
            n = 0;
            if isstruct(NM) && isfield(NM,'Y') && iscell(NM.Y)
                n = numel(NM.Y);
            end
        end

        function idx = nextOOCVIndex(NM, spec)
            % nextOOCVIndex  Resolve the next OOCV/application container index for creation or append workflows.
            %
            % NM, spec -> idx.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            idx = NMDataIOBrowserModeTools.specNumber(spec, {'containerIndex','oocvIndex','oocvind'}, NaN);
            if ~isnan(idx)
                idx = max(1, round(idx));
                return;
            end
            idx = 1;
            if isstruct(NM) && isfield(NM,'OOCV') && iscell(NM.OOCV)
                idx = numel(NM.OOCV) + 1;
            end
        end

        function v = specNumber(spec, names, defaultValue)
            % specNumber  Read the first numeric OOCV/browser specification field from a list of aliases.
            %
            % Consumes spec, names, defaultValue; returns v.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            v = defaultValue;
            if nargin < 1 || ~isstruct(spec), return; end
            for i = 1:numel(names)
                if isfield(spec,names{i}) && ~isempty(spec.(names{i}))
                    raw = spec.(names{i});
                    if isnumeric(raw) || islogical(raw)
                        v = double(raw(1));
                    else
                        v = str2double(char(string(raw)));
                    end
                    return;
                end
            end
        end

        function v = specLogical(spec, names, defaultValue)
            % specLogical  Read and normalize a logical OOCV/browser specification field from aliases.
            %
            % Consumes spec, names, defaultValue; returns v.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            v = logical(defaultValue);
            if nargin < 1 || ~isstruct(spec), return; end
            for i = 1:numel(names)
                if isfield(spec,names{i}) && ~isempty(spec.(names{i}))
                    raw = spec.(names{i});
                    if ischar(raw) || isa(raw,'string')
                        t = lower(strtrim(char(string(raw))));
                        v = any(strcmp(t, {'true','1','yes','y','known','on'}));
                    elseif isnumeric(raw) || islogical(raw)
                        v = logical(raw(1));
                    end
                    return;
                end
            end
        end

        function v = specChar(spec, names, defaultValue)
            % specChar  Read and normalize a text OOCV/browser specification field from aliases.
            %
            % Consumes spec, names, defaultValue; returns v.
            % It controls which DataIO browser actions are legal after training import finalization or inside OOCV management.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            v = char(string(defaultValue));
            if nargin < 1 || ~isstruct(spec), return; end
            for i = 1:numel(names)
                if isfield(spec,names{i}) && ~isempty(spec.(names{i}))
                    v = char(string(spec.(names{i})));
                    return;
                end
            end
        end
    end
end

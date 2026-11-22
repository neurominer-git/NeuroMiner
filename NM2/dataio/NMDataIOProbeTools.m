classdef NMDataIOProbeTools
% NMDataIOProbeTools
% -------------------------------------------------------------------------
% Purpose:
%   Non-committing matrix/table probe adapter used by browser/API services to expose readiness and
%   diagnostics without transferring a modality into NM.
%
% Authority and side effects:
%   The probe reuses established CheckTabFile/CheckLabel semantics where applicable. It does not
%   call TransferModality2NM and is not a competing Preview/materialization authority. Invalid input
%   is returned as explicit DataIO diagnostics.
% -------------------------------------------------------------------------

    methods (Static)
        function out = matrixProbe(NM, state, opts)
            % matrixProbe  Run the matrix/table probe path and return diagnostics without committing data.
            %
            % Consumes NM, state, opts; returns out.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            %
            % opts.NaString: defines the text token interpreted as missing data during table/matrix import.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            na = NMDataIOProbeTools.opt(opts, 'NaString', '?');
            source = 'matrixProbe';
            out = NMDataIOProbeTools.emptyProbeOut();
            out.stateEcho = state;

            try
                IO = NMDataIOStateTools.stateToIO(state, NM);
                out.ioSummary = NMDataIOProbeTools.ioSummary(IO);
            catch ME
                messages = NMDataIOMessageTools.fromException(ME, source);
                out = NMDataIOProbeTools.finish(out, messages, []);
                return;
            end

            if ~strcmpi(char(IO.datasource), 'matrix')
                messages = NMDataIOMessageTools.make('danger', true, source, ...
                    sprintf('Matrix/table input checking requires a matrix/table data source; received ''%s''.', char(IO.datasource)), 1, 'red*');
                out = NMDataIOProbeTools.finish(out, messages, IO);
                return;
            end

            % Resolved payloads and modern workspace/MAT source-block states must use
            % the same preparation authority as Preview/Commit. Legacy CheckTabFile
            % does not understand variableRoles, per-block Case-ID provenance, or
            % manual/text-file covariate-name lists.
            if (exist('NMDataIOImportTools','class') == 8 || exist('NMDataIOImportTools','file') == 2) && ...
                    (NMDataIOImportTools.hasResolvedMatrixPayload(IO) || NMDataIOImportTools.hasVariableRoleMaterialization(IO))
                [IO, messages] = NMDataIOImportTools.prepareMatrixIO(NM, state, struct('RequireReady', false));
                if ~NMDataIOMessageTools.hasFatal(messages)
                    [IO, alignMessages] = NMDataIOImportTools.applyReferenceCaseAlignmentIfNeeded(NM, IO, 'probe');
                    messages = [messages; alignMessages];
                end
                probe = NMDataIOProbeTools.matrixSummaryFromIO(IO, struct());
                if isstruct(IO) && isfield(IO,'importReport') && isstruct(IO.importReport)
                    probe.importReport = IO.importReport;
                end
                out = NMDataIOProbeTools.finish(out, messages, IO, probe);
                return;
            end

            if isfield(IO,'groupmode') && ismember(double(IO.groupmode), [3 4 5 6]) && ...
                    (exist('NMDataIOTableReadTools','class') == 8 || exist('NMDataIOTableReadTools','file') == 2) && ...
                    (exist('NMDataIOTableRoleTools','class') == 8 || exist('NMDataIOTableRoleTools','file') == 2)
                if exist('NMDataIOImportTools','class') ~= 8 && exist('NMDataIOImportTools','file') ~= 2
                    messages = NMDataIOMessageTools.make('danger', true, source, ...
                        'NMDataIOImportTools.m is required for table-source probing.', 1, 'red*');
                    out = NMDataIOProbeTools.finish(out, messages, IO);
                    return;
                end
                [IO, messages] = NMDataIOImportTools.prepareMatrixIO(NM, state, struct('RequireReady', false));
                if ~NMDataIOMessageTools.hasFatal(messages)
                    [IO, alignMessages] = NMDataIOImportTools.applyReferenceCaseAlignmentIfNeeded(NM, IO, 'probe');
                    messages = [messages; alignMessages];
                end
                probe = NMDataIOProbeTools.matrixSummaryFromIO(IO, struct());
                if isstruct(IO) && isfield(IO,'importReport') && isstruct(IO.importReport)
                    probe.importReport = IO.importReport;
                end
                out = NMDataIOProbeTools.finish(out, messages, IO, probe);
                return;
            end

            if exist('CheckTabFile','file') ~= 2
                messages = NMDataIOMessageTools.make('danger', true, source, ...
                    'Legacy CheckTabFile.m is not on the MATLAB path. Add the legacy DataIO/data_import directory before using browser matrix probing.', 1, 'red*');
                out = NMDataIOProbeTools.finish(out, messages, IO);
                return;
            end

            mess = [];
            summaries = struct('matrix', na, 'label', na, 'caseId', na, 'featureNames', na);
            try
                [summaries.matrix, mess, IO] = CheckTabFile(IO, 'check_matrix', na, mess);
                if ~CheckReadyStatus(mess)
                    if NMDataIOProbeTools.shouldCheck(IO, 'label_edit', na) && (~isfield(IO,'oocvflag') || ~IO.oocvflag || IO.labels_known)
                        [summaries.label, mess, IO] = CheckTabFile(IO, 'check_label', na, mess);
                    end
                    if ~CheckReadyStatus(mess) && NMDataIOProbeTools.shouldCheck(IO, 'case_edit', na)
                        [summaries.caseId, mess, IO] = CheckTabFile(IO, 'check_ID', na, mess);
                    end
                    if ~CheckReadyStatus(mess) && NMDataIOProbeTools.shouldCheck(IO, 'col_edit', na) && ismember(IO.groupmode, [1 2])
                        [summaries.featureNames, mess, IO] = CheckTabFile(IO, 'check_featnames', na, mess);
                    end
                end
            catch ME
                messages = NMDataIOMessageTools.fromException(ME, 'CheckTabFile');
                out = NMDataIOProbeTools.finish(out, messages, IO);
                return;
            end

            messages = NMDataIOMessageTools.fromLegacyMess(mess, 'CheckTabFile');
            if ~NMDataIOMessageTools.hasFatal(messages) && ...
                    (exist('NMDataIOImportTools','class') == 8 || exist('NMDataIOImportTools','file') == 2)
                [IO, alignMessages] = NMDataIOImportTools.applyReferenceCaseAlignmentIfNeeded(NM, IO, 'probe');
                messages = [messages; alignMessages];
            end
            probe = NMDataIOProbeTools.matrixSummaryFromIO(IO, summaries);
            if isstruct(IO) && isfield(IO,'importReport') && isstruct(IO.importReport)
                probe.importReport = IO.importReport;
            end
            out = NMDataIOProbeTools.finish(out, messages, IO, probe);
        end


        function out = tableHeaderProbe(NM, state, opts)
            % tableHeaderProbe  Probe table headers and candidate role columns without reading the full payload.
            %
            % Consumes NM, state, opts; returns out.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            if nargin < 1 || isempty(NM), NM = struct(); end %#ok<NASGU>
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            out = NMDataIOProbeTools.emptyProbeOut();
            out.operation = 'tableHeaderProbe';
            doProfile = NMDataIOProfileTools.enabled([], [], opts);
            tTotal = tic;
            try
                tState = tic;
                IO = NMDataIOStateTools.stateToIO(state, NM);
                stateSeconds = toc(tState);
                NMDataIOProfileTools.log(doProfile, 'tableHeaderProbe stateToIO: %.3fs', stateSeconds);
                if ~ismember(double(IO.groupmode), [3 4 5 6])
                    IO = NMDataIOProbeTools.repairHeaderProbeIOFromState(IO, state);
                end
                out.ioSummary = NMDataIOProbeTools.ioSummary(IO);
                if ~ismember(double(IO.groupmode), [3 4 5 6])
                    msg = NMDataIOMessageTools.make('warn', false, 'tableHeaderProbe', ...
                        sprintf('Header/column probing is only available for MATLAB table, text-file, spreadsheet, and database imports; received source type ''%s'' / groupmode %g.', ...
                        char(NMDataIOProbeTools.fieldOr(IO,'sourceType','unknown')), double(NMDataIOProbeTools.fieldOr(IO,'groupmode',NaN))), 2, 'SystemCommands');
                    out = NMDataIOProbeTools.finish(out, msg, IO, struct());
                    out.header = struct('ok', false, 'columns', {{}}, 'sheets', {{}});
                    return;
                end
                if exist('NMDataIOTableReadTools','class') ~= 8 && exist('NMDataIOTableReadTools','file') ~= 2
                    msg = NMDataIOMessageTools.make('danger', true, 'tableHeaderProbe', ...
                        'NMDataIOTableReadTools.m is not on the MATLAB path.', 1, 'red*');
                    out = NMDataIOProbeTools.finish(out, msg, IO, struct());
                    return;
                end
                tHeaders = tic;
                h = NMDataIOTableReadTools.probeHeaders(IO, opts);
                correspondenceMessages = NMDataIOMessageTools.emptyMessages();
                if h.ok && logical(NMDataIOProbeTools.fieldOr(IO,'oocvflag',false))
                    [IO, correspondence, correspondenceMessages] = NMDataIOProbeTools.applyOOCVFeatureCorrespondence(NM, IO, NMDataIOProbeTools.fieldOr(h,'sourceVariables',struct([])));
                    h.oocvFeatureCorrespondence = correspondence;
                end
                headerSeconds = toc(tHeaders);
                NMDataIOProfileTools.log(doProfile, 'tableHeaderProbe probeHeaders: %.3fs', headerSeconds);
                if h.ok
                    level = 'ok'; flag = 0; fmt = 'green*'; blocking = false;
                else
                    level = 'danger'; flag = 1; fmt = 'red*'; blocking = true;
                end
                msg = NMDataIOMessageTools.make(level, blocking, 'tableHeaderProbe', h.message, flag, fmt);
                msg = [msg; correspondenceMessages];
                probe = struct();
                probe.tableColumns = h.columns;
                probe.rawTableColumns = h.rawColumns;
                probe.sheets = h.sheets;
                probe.selectedSheets = NMDataIOProbeTools.fieldOr(h,'selectedSheets',{});
                probe.sheet = h.sheet;
                probe.headerRow = h.headerRow;
                probe.headerRows = NMDataIOProbeTools.fieldOr(h,'headerRows',[]);
                probe.columnSources = NMDataIOProbeTools.fieldOr(h,'columnSources',{});
                probe.duplicateColumns = NMDataIOProbeTools.fieldOr(h,'duplicateColumns',{});
                probe.commonColumns = NMDataIOProbeTools.fieldOr(h,'commonColumns',{});
                probe.headerRowAutoDetected = h.headerRowAutoDetected;
                probe.nColumns = h.nColumns;
                probe.diagnostics = h.diagnostics;
                if isfield(h,'oocvFeatureCorrespondence'), probe.oocvFeatureCorrespondence = h.oocvFeatureCorrespondence; end
                out = NMDataIOProbeTools.finish(out, msg, IO, probe);
                out.header = h;
                perf = NMDataIOProbeTools.fieldOr(h,'performance',struct());
                perf.stateToIOSeconds = double(stateSeconds);
                perf.probeHeadersSeconds = double(headerSeconds);
                perf.tableHeaderProbeSeconds = double(toc(tTotal));
                out.performance = perf;
                out.header.performance = perf;
                NMDataIOProfileTools.log(doProfile, 'tableHeaderProbe TOTAL: %.3fs', perf.tableHeaderProbeSeconds);
                out.statePatch = NMDataIOStateTools.ioToState(NMDataIOProbeTools.stripTransientIO(IO));
                if isfield(out.statePatch,'matrix')
                    out.statePatch.matrix.sheet = h.sheet;
                    out.statePatch.matrix.sheets = NMDataIOProbeTools.fieldOr(h,'selectedSheets',{});
                    out.statePatch.matrix.headerRow = h.headerRow;
                    out.statePatch.matrix.headerAutoDetect = h.headerRowAutoDetected;
                end
            catch ME
                out = NMDataIOProbeTools.finish(out, NMDataIOMessageTools.fromException(ME, 'tableHeaderProbe'), []);
            end
        end

        function IO = repairHeaderProbeIOFromState(IO, state)
            % repairHeaderProbeIOFromState  Restore IO fields that are not represented directly in a header-probe result.
            %
            % IO, state -> IO.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            %
            % state.groupmode: carries the groupmode value between browser/API state and legacy NeuroMiner structures.
            % state.M_edit: carries the m edit value between browser/API state and legacy NeuroMiner structures.
            % state.matrix: carries the matrix value between browser/API state and legacy NeuroMiner structures.
            % state.sourceType: records the concrete input-source type selected by the user or API.
            if nargin < 1 || ~isstruct(IO), IO = struct(); end
            if nargin < 2 || ~isstruct(state), return; end
            m = struct();
            if isfield(state,'matrix') && isstruct(state.matrix), m = state.matrix; end
            sourceType = '';
            if isfield(m,'sourceType') && ~isempty(m.sourceType)
                sourceType = char(string(m.sourceType));
            elseif isfield(state,'sourceType') && ~isempty(state.sourceType)
                sourceType = char(string(state.sourceType));
            end
            fallback = NMDataIOProbeTools.fieldOr(state, 'groupmode', NMDataIOProbeTools.fieldOr(IO,'groupmode',1));
            normalized = NMDataIOStateTools.normalizeSourceType(sourceType, fallback);
            if ~ismember(normalized, {'tablefile','tablevar','database'})
                file = NMDataIOProbeTools.fieldOr(m, 'M_edit', NMDataIOProbeTools.fieldOr(state, 'M_edit', ''));
                ext = lower(char(string(file)));
                if endsWith(ext, {'.xls','.xlsx','.xlsm','.csv','.tsv','.txt','.dat'})
                    normalized = 'tablefile';
                end
            end
            switch normalized
                case 'tablefile'
                    file = NMDataIOProbeTools.fieldOr(m, 'M_edit', NMDataIOProbeTools.fieldOr(state, 'M_edit', '?'));
                    IO.sourceType = 'tablefile';
                    IO.M_edit = char(string(file));
                    f = lower(IO.M_edit);
                    if endsWith(f, {'.xls','.xlsx','.xlsm'})
                        IO.groupmode = 4;
                    else
                        IO.groupmode = 3;
                    end
                    IO.delimit = NMDataIOProbeTools.fieldOr(m, 'delimit', NMDataIOProbeTools.fieldOr(IO,'delimit','tab'));
                    IO.sheet = NMDataIOProbeTools.fieldOr(m, 'sheet', NMDataIOProbeTools.fieldOr(IO,'sheet','?'));
                    IO.sheets = NMDataIOProbeTools.fieldOr(m, 'sheets', NMDataIOProbeTools.fieldOr(IO,'sheets',{}));
                    IO.headerRow = NMDataIOProbeTools.fieldOr(m, 'headerRow', NMDataIOProbeTools.fieldOr(IO,'headerRow',[]));
                    IO.headerAutoDetect = NMDataIOProbeTools.fieldOr(m, 'headerAutoDetect', NMDataIOProbeTools.fieldOr(IO,'headerAutoDetect',true));
                case 'tablevar'
                    tableVar = NMDataIOProbeTools.fieldOr(m, 'tableVariable', NMDataIOProbeTools.fieldOr(m, 'M_edit', NMDataIOProbeTools.fieldOr(IO,'tableVariable','?')));
                    IO.sourceType = 'tablevar';
                    IO.groupmode = 5;
                    IO.M_edit = char(string(tableVar));
                    IO.tableVariable = char(string(tableVar));
                case 'database'
                    IO.sourceType = 'database';
                    IO.groupmode = 6;
                    fields = {'databaseConnector','databaseUrl','databaseFile','databaseUser','databasePassword','databaseName','databaseSchema','databaseTable','databaseUseQuery','databaseQuery'};
                    for f = 1:numel(fields)
                        if isfield(m, fields{f})
                            IO.(fields{f}) = m.(fields{f});
                        end
                    end
            end
        end

        function out = validateMatrixState(NM, state, opts)
            % validateMatrixState  Validate matrix/table browser state before preview or commit actions are enabled.
            %
            % Consumes NM, state, opts; returns out.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            if nargin < 1 || isempty(NM), NM = struct(); end %#ok<NASGU>
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end %#ok<NASGU>
            messages = NMDataIOMessageTools.emptyMessages();
            try
                IO = NMDataIOStateTools.stateToIO(state, NM);
                na = '?';
                k = 0;
                if ~strcmpi(char(IO.datasource), 'matrix')
                    k = k + 1; messages(k,1) = NMDataIOMessageTools.make('danger', true, 'validateMatrixState', 'Matrix import state must use datasource=''matrix''.', 1, 'red*'); %#ok<AGROW>
                end
                gm = IO.groupmode;
                if ~ismember(gm, [1 2 3 4 5 6])
                    k = k + 1; messages(k,1) = NMDataIOMessageTools.make('danger', true, 'validateMatrixState', 'Unsupported matrix groupmode.', 1, 'red*'); %#ok<AGROW>
                end
                if ismember(gm, [1 3 4]) && strcmp(IO.M_edit, na)
                    k = k + 1; messages(k,1) = NMDataIOMessageTools.make('danger', true, 'validateMatrixState', 'Predictor matrix/table source is not defined.', 1, 'red*'); %#ok<AGROW>
                end
                if gm == 2 && (strcmp(IO.M_edit, na) || strcmp(IO.matrix_edit, na))
                    k = k + 1; messages(k,1) = NMDataIOMessageTools.make('danger', true, 'validateMatrixState', 'MAT-file path and matrix variable must both be defined.', 1, 'red*'); %#ok<AGROW>
                end
                if strcmp(char(IO.case_edit), na)
                    k = k + 1; messages(k,1) = NMDataIOMessageTools.make('warn', false, 'validateMatrixState', 'Case-ID variable/column is not defined yet.', 2, 'SystemCommands'); %#ok<AGROW>
                end
                if (~isfield(IO,'oocvflag') || ~IO.oocvflag || IO.labels_known) && NMDataIOProbeTools.isUnknown(IO.label_edit, na)
                    k = k + 1; messages(k,1) = NMDataIOMessageTools.make('warn', false, 'validateMatrixState', 'Label variable/column is not defined yet.', 2, 'SystemCommands'); %#ok<AGROW>
                end
                if isempty(messages)
                    messages = NMDataIOMessageTools.make('ok', false, 'validateMatrixState', 'Matrix import state contains the minimum source fields for probing.', 0, 'green*');
                end
                out = NMDataIOProbeTools.emptyProbeOut();
                out.ioSummary = NMDataIOProbeTools.ioSummary(IO);
                out = NMDataIOProbeTools.finish(out, messages, IO, struct());
            catch ME
                out = NMDataIOProbeTools.emptyProbeOut();
                out = NMDataIOProbeTools.finish(out, NMDataIOMessageTools.fromException(ME, 'validateMatrixState'), []);
            end
        end


        function out = sourceVariableProbe(NM, state, opts)
            % sourceVariableProbe  Inspect workspace/MAT-file variables that could serve as matrix/table payloads.
            %
            % Workspace variables are listed from the base workspace authority. MAT-file
            % variables retain file provenance so identically named variables from different
            % files remain independently assignable in the DataIO role panel.
            if nargin < 1 || isempty(NM), NM = struct(); end %#ok<INUSD>
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end %#ok<INUSD>
            out = NMDataIOProbeTools.emptyProbeOut();
            out.operation = 'sourceVariableProbe';
            try
                IO = NMDataIOStateTools.stateToIO(state, NM);
                out.ioSummary = NMDataIOProbeTools.ioSummary(IO);
                vars = struct('id', {}, 'name', {}, 'class', {}, 'size', {}, 'isTable', {}, 'isNumeric', {}, 'sourceType', {}, 'sourcePath', {}, 'sourceLabel', {});
                switch double(IO.groupmode)
                    case {1,5,-2}
                        catalog = NMWorkspaceTools.catalog('base', struct());
                        for i = 1:numel(catalog)
                            if iscell(catalog), w = catalog{i}; else, w = catalog(i); end
                            vars(end+1,1) = NMDataIOProbeTools.catalogVariableInfo(w); %#ok<AGROW>
                        end
                    case 2
                        files = NMDataIOProbeTools.matSourceFiles(IO);
                        if isempty(files)
                            msg = NMDataIOMessageTools.make('danger', true, 'sourceVariableProbe', 'Add at least one existing MAT-file before listing variables.', 1, 'red*');
                            out = NMDataIOProbeTools.finish(out, msg, IO, struct());
                            return;
                        end
                        for f = 1:numel(files)
                            filePath = files{f};
                            if exist(filePath,'file') ~= 2
                                error('NMDataIOProbeTools:matFileNotFound', 'MAT-file does not exist: %s', filePath);
                            end
                            W = whos('-file', filePath);
                            [~, base, ext] = fileparts(filePath);
                            label = [base ext];
                            for i = 1:numel(W)
                                stableId = sprintf('mat:%d:%s', f, W(i).name);
                                vars(end+1,1) = NMDataIOProbeTools.variableInfo(W(i), 'matfile', filePath, label, stableId); %#ok<AGROW>
                            end
                        end
                    otherwise
                        msg = NMDataIOMessageTools.make('warn', false, 'sourceVariableProbe', 'Variable listing is only available for workspace, MAT-file, MATLAB table, and imaging-list metadata sources.', 2, 'SystemCommands');
                        out = NMDataIOProbeTools.finish(out, msg, IO, struct());
                        return;
                end
                if double(IO.groupmode) == 5
                    vars = vars(arrayfun(@(v) v.isTable, vars));
                end
                probe = struct('variables', vars, 'nVariables', numel(vars));
                msg = NMDataIOMessageTools.make('ok', false, 'sourceVariableProbe', sprintf('Detected %g source variable(s).', numel(vars)), 0, 'green*');
                out = NMDataIOProbeTools.finish(out, msg, IO, probe);
                out.variables = vars;
            catch ME
                out = NMDataIOProbeTools.finish(out, NMDataIOMessageTools.fromException(ME, 'sourceVariableProbe'), []);
            end
        end

        function out = labelDefinitionProbe(NM, state, opts)
            % labelDefinitionProbe  Resolve only the selected labels/targets for Group/Label-name UI definition.
            %
            % Retrieval order is intentionally narrow: reuse the retained Preview materialization
            % for the same scientific identity; on Resume reuse unchanged persisted text-label
            % semantics; otherwise project only the selected tabular label columns. Label-map and
            % regression-name semantics remain owned by the established transfer authorities.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end %#ok<INUSD>
            out = struct('ok',false,'blocking',false,'message','','warning','','mode','','needsDefinition',false, ...
                'numericClassification',false,'count',0,'sourceCodes',{{}},'intrinsicNames',{{}},'nTargets',0,'nMissingLabels',0, ...
                'intrinsicNamesFromSource',false,'reusedMaterialization',false,'reusedPersistedSemantics',false,'selectiveSourceRead',false);
            try
                IO = NMDataIOStateTools.stateToIO(state, NM);
                mode = lower(strtrim(char(string(NMDataIOProbeTools.fieldOr(IO,'modeflag','classification')))));
                out.mode = mode;
                refs = {};
                if isfield(IO,'variableRoles')
                    refs = NMDataIOImportTools.variableRoleRefs(IO, 'labels');
                end
                if strcmp(mode,'classification') && numel(refs) > 1
                    error('NMDataIOProbeTools:classificationMultiLabel', 'Classification accepts exactly one label input.');
                end

                % Tier 1: Preview already owns a materialization of this exact scientific state.
                raws = {};
                identityState = NMDataIOImportTools.materializationIdentityState(NM,state);
                [cacheHit, cacheEntry] = NMDataIOMaterializationCache.get('matrix', identityState, '', NMDataIOUI.sessionKey(NMDataIOProbeTools.fieldOr(opts,'tmpDir','')));
                if cacheHit && isstruct(cacheEntry) && isfield(cacheEntry,'IO') && isstruct(cacheEntry.IO)
                    cachedIO = cacheEntry.IO;
                    if strcmp(mode,'classification')
                        classMap = NMDataIOLabelStatsTools.normalizeClassificationMap( ...
                            NMDataIOProbeTools.fieldOr(cachedIO,'classificationLabelMap',struct()));
                        if ~isempty(fieldnames(classMap))
                            out.reusedMaterialization = true;
                            out.numericClassification = strcmp(classMap.sourceKind,'numeric');
                            out.needsDefinition = out.numericClassification;
                            out.count = numel(classMap.canonicalIds);
                            if out.numericClassification
                                out.sourceCodes = cellstr(string(classMap.sourceValues(:)));
                                out.intrinsicNames = out.sourceCodes;
                            else
                                out.intrinsicNames = classMap.groupNames(:)';
                            end
                            if isfield(cachedIO,'label') && isnumeric(cachedIO.label)
                                out.nMissingLabels = double(nnz(isnan(cachedIO.label(:))));
                                if out.nMissingLabels > 0
                                    out.warning = sprintf('Classification labels contain %g missing value(s). These labels remain missing and must be handled before model training.', out.nMissingLabels);
                                end
                            end
                            out.ok = true;
                            out.message = sprintf('Reused the retained Preview label definition (%g class(es)).', out.count);
                            if ~isempty(out.warning), out.message = sprintf('%s %s', out.message, out.warning); end
                            return;
                        end
                    elseif isfield(cachedIO,'label') && ~isempty(cachedIO.label)
                        cachedLabels = cachedIO.label;
                        tabularRefs = ~isempty(refs) && all(cellfun(@(r) NMDataIOImportTools.isCanonicalTabularColumnRef(r), refs));
                        if tabularRefs && size(cachedLabels,2) == numel(refs)
                            raws = cell(numel(refs),1);
                            for i = 1:numel(refs), raws{i} = cachedLabels(:,i); end
                        else
                            raws = {cachedLabels};
                        end
                        out.reusedMaterialization = true;
                    end
                end

                % Tier 2: Resume may reuse persisted text semantics only when the selected label
                % source identity and column are unchanged. Numeric mappings still require the
                % normal definition UI and are not silently treated as text.
                if isempty(raws) && strcmp(mode,'classification') && ~isempty(refs)
                    target = NMDataIOImportTargetTools.normalize(NM,IO,NMDataIOProbeTools.fieldOr(IO,'varind',[]));
                    if strcmpi(char(string(target.mode)),'resume')
                        [D,targetMessages] = NMDataIOImportTargetTools.getContainer(NM,target);
                        if ~NMDataIOMessageTools.hasFatal(targetMessages) && isstruct(D) && isfield(D,'datadescriptor') && ...
                                iscell(D.datadescriptor) && numel(D.datadescriptor) >= target.varind && ...
                                isstruct(D.datadescriptor{target.varind}) && isfield(D.datadescriptor{target.varind},'input_settings') && ...
                                isstruct(D.datadescriptor{target.varind}.input_settings)
                            persistedIO = D.datadescriptor{target.varind}.input_settings;
                            classMap = NMDataIOLabelStatsTools.normalizeClassificationMap( ...
                                NMDataIOProbeTools.fieldOr(persistedIO,'classificationLabelMap',struct()));
                            persistedRefs = NMDataIOImportTools.variableRoleRefs(persistedIO,'labels');
                            sameRefs = numel(persistedRefs) == numel(refs);
                            for i = 1:min(numel(persistedRefs),numel(refs))
                                currentColumn = char(string(NMDataIOProbeTools.fieldOr(refs{i},'columnName',NMDataIOImportTools.variableRefName(refs{i}))));
                                persistedColumn = char(string(NMDataIOProbeTools.fieldOr(persistedRefs{i},'columnName',NMDataIOImportTools.variableRefName(persistedRefs{i}))));
                                sameRefs = sameRefs && strcmp(currentColumn,persistedColumn) && ...
                                    strcmp(NMDataIOStateTools.variableRefSourceIdentity(refs{i},IO), ...
                                           NMDataIOStateTools.variableRefSourceIdentity(persistedRefs{i},persistedIO));
                            end
                            if sameRefs && ~isempty(fieldnames(classMap)) && strcmp(classMap.sourceKind,'text')
                                out.reusedPersistedSemantics = true;
                                out.numericClassification = false;
                                out.needsDefinition = false;
                                out.count = numel(classMap.canonicalIds);
                                out.intrinsicNames = classMap.groupNames(:)';
                                out.ok = true;
                                out.message = sprintf('Reused unchanged persisted text-label semantics (%g class(es)).', out.count);
                                return;
                            end
                        end
                    end
                end

                % Tier 3: selective source retrieval. Canonical tabular refs are grouped by
                % source object so multiple regression targets from one table are projected in
                % one source operation and returned in assignment order.
                if isempty(raws) && ~isempty(refs)
                    raws = cell(numel(refs),1);
                    tabular = cellfun(@(r) NMDataIOImportTools.isCanonicalTabularColumnRef(r), refs);
                    if any(tabular)
                        [projectedValues,~,~] = NMDataIOTableReadTools.readSourceRefsProjected(IO, refs(tabular));
                        raws(tabular) = projectedValues;
                        out.selectiveSourceRead = true;
                    end
                    for i = find(~tabular(:))'
                        raws{i} = NMDataIOImportTools.resolveVariableRef(IO, refs{i});
                    end
                    for i = 1:numel(refs)
                        raws{i} = NMDataIOImportTools.rowVariable(raws{i}, NMDataIOImportTools.variableRefName(refs{i}));
                        if contains(mode,'reg') && NMDataIOImportTools.isCanonicalTabularColumnRef(refs{i})
                            [raws{i}, numericReport] = NMDataIOTableRoleTools.numericSourceColumn(IO, raws{i}, 'Regression target');
                            if ~numericReport.ok
                                error('NMDataIOProbeTools:regressionLabelType', ...
                                    'Regression label input %s contains values that cannot be converted to numeric targets.', ...
                                    NMDataIOImportTools.variableRefName(refs{i}));
                            end
                        end
                    end
                elseif isempty(raws) && ismember(double(IO.groupmode), [3 4 5])
                    % Legacy single-table state retained for compatibility. Modern browser/API
                    % tabular states carry canonical variableRoles and use the selective path above.
                    T = NMDataIOTableReadTools.readTableFromIO(IO);
                    roles = NMDataIOTableRoleTools.resolveRoles(T, IO);
                    if strcmp(mode,'classification') && numel(roles.labelColumns) > 1
                        error('NMDataIOProbeTools:classificationMultiLabel', 'Classification accepts exactly one label column.');
                    end
                    for i = 1:numel(roles.labelColumns)
                        raws{end+1,1} = T.(roles.labelColumns{i}); %#ok<AGROW>
                    end
                end
                if isempty(raws)
                    out.ok = true; out.message = 'No explicit label source is assigned.'; return;
                end

                if contains(mode,'reg')
                    nTargets = 0;
                    scalarTargetRefs = ~isempty(refs) && numel(raws) == numel(refs);
                    for i = 1:numel(raws)
                        raw = raws{i};
                        if ~(isnumeric(raw) || islogical(raw)) || ~isreal(raw)
                            error('NMDataIOProbeTools:regressionLabelType', 'Regression label sources must be real numeric/logical arrays.');
                        end
                        if any(isinf(double(raw(:))))
                            error('NMDataIOProbeTools:regressionLabelInf', 'Regression labels may contain NaN but not +/-Inf.');
                        end
                        nCols = 1;
                        if ~isvector(raw), nCols = size(raw,2); end
                        nTargets = nTargets + nCols;
                        scalarTargetRefs = scalarTargetRefs && nCols == 1;
                    end
                    out.count = nTargets; out.nTargets = nTargets;
                    sourceNamed = scalarTargetRefs && all(cellfun(@(r) NMDataIOImportTools.isCanonicalTabularColumnRef(r), refs));
                    if sourceNamed
                        names = cellfun(@(r) char(string(NMDataIOProbeTools.fieldOr(r,'columnName',NMDataIOImportTools.variableRefName(r)))), refs, 'UniformOutput', false);
                        if any(cellfun(@isempty,names))
                            error('NMDataIOProbeTools:regressionLabelName','Selected tabular regression targets must retain their source column names.');
                        end
                        out.needsDefinition = false;
                        out.intrinsicNames = names(:)';
                        out.intrinsicNamesFromSource = true;
                    else
                        out.needsDefinition = true;
                        out.intrinsicNames = arrayfun(@(i) sprintf('Label_%03d',i),1:nTargets,'UniformOutput',false);
                    end
                else
                    raw = raws{1};
                    if isnumeric(raw) || islogical(raw)
                        if ~isreal(raw) || ~isvector(raw), error('NMDataIOProbeTools:classificationLabelShape','Classification requires one real label value per subject.'); end
                        values = double(raw(:));
                        if any(isinf(values)), error('NMDataIOProbeTools:classificationLabelInf','Classification labels may contain NaN but not +/-Inf.'); end
                        missing = isnan(values);
                        codes = unique(values(~missing));
                        out.nMissingLabels = double(nnz(missing));
                        if out.nMissingLabels > 0
                            out.warning = sprintf('Classification labels contain %g missing value(s). These labels remain missing and must be handled before model training.', out.nMissingLabels);
                        end
                        out.numericClassification = true; out.needsDefinition = true; out.count = numel(codes);
                        out.sourceCodes = cellstr(string(codes(:)));
                        out.intrinsicNames = out.sourceCodes;
                    else
                        [~, names, mess] = NMDataIOLabelStatsTools.normalizeForTransfer(raw,'classification',{},'labelDefinitionProbe');
                        if NMDataIOMessageTools.hasFatal(mess)
                            error('NMDataIOProbeTools:classificationLabelInvalid','Selected classification labels are invalid.');
                        end
                        out.numericClassification = false; out.needsDefinition = false; out.count = numel(names);
                        out.intrinsicNames = names;
                    end
                end
                out.ok = true;
                if contains(mode,'reg'), kindText = 'regression label-name'; else, kindText = 'group-name'; end
                if out.count == 1, suffix = 'y'; else, suffix = 'ies'; end
                out.message = sprintf('Resolved %g %s definition entr%s.', out.count, kindText, suffix);
                if ~isempty(out.warning), out.message = sprintf('%s %s', out.message, out.warning); end
            catch ME
                out.ok = false; out.blocking = true; out.message = ME.message; out.identifier = ME.identifier;
            end
        end

        function files = matSourceFiles(IO)
            files = {};
            if isstruct(IO) && isfield(IO,'matFiles') && ~isempty(IO.matFiles)
                raw = IO.matFiles;
                if ischar(raw), files = {raw};
                elseif isstring(raw), files = cellstr(raw(:));
                elseif iscell(raw), files = cellfun(@(x) char(string(x)), raw(:), 'UniformOutput', false);
                end
            end
            if isempty(files) && isstruct(IO) && isfield(IO,'M_edit') && ~NMDataIOProbeTools.isUnknown(IO.M_edit,'?')
                raw = char(string(IO.M_edit));
                lines = regexp(raw, '\r?\n', 'split');
                files = lines(~cellfun(@isempty, strtrim(lines)));
            end
            files = unique(files(:)', 'stable');
        end

        function v = catalogVariableInfo(w)
            v = struct();
            v.id = char(string(w.name));
            v.name = char(string(w.name));
            v.class = char(string(w.class));
            v.size = w.size;
            v.isTable = strcmp(v.class, 'table');
            v.isNumeric = isfield(w,'isNumeric') && logical(w.isNumeric);
            v.sourceType = 'workspace';
            v.sourcePath = '';
            v.sourceLabel = 'MATLAB workspace';
        end

        function v = variableInfo(W, sourceType, sourcePath, sourceLabel, id)
            v = struct();
            v.id = char(string(id));
            v.name = W.name;
            v.class = W.class;
            v.size = W.size;
            v.isTable = strcmp(W.class, 'table');
            v.isNumeric = any(strcmp(W.class, {'double','single','logical','uint8','uint16','uint32','uint64','int8','int16','int32','int64'}));
            v.sourceType = sourceType;
            v.sourcePath = sourcePath;
            v.sourceLabel = sourceLabel;
        end

        function [IO, report, messages] = applyOOCVFeatureCorrespondence(NM, IO, sourceVariables)
            % applyOOCVFeatureCorrespondence  Project included tabular headers onto the trained OOCV feature axis.
            %
            % Automatic mode derives exact-name correspondence. Manual expert mode preserves
            % explicit targetFeatureIndex assignments and reconciles their source refs against
            % the live included-column inventory without guessing replacements.
            messages = NMDataIOMessageTools.emptyMessages();
            report = struct('enabled',false,'mode','automatic','targetNames',{{}},'targetStatus',{{}},'targetSourceIds',{{}}, ...
                'targetSourceLabels',{{}},'missingColumns',{{}},'ambiguousColumns',{{}},'extraColumns',{{}}, ...
                'unresolvedTargetIndices',[],'ambiguousTargetIndices',[],'invalidTargetIndices',[],'duplicateSourceIds',{{}});
            if ~logical(NMDataIOProbeTools.fieldOr(IO,'oocvflag',false)) || ...
                    ~ismember(double(NMDataIOProbeTools.fieldOr(IO,'groupmode',1)),[3 4 5 6])
                return;
            end
            importTarget = NMDataIOImportTargetTools.normalize(NM, NMDataIOProbeTools.fieldOr(IO,'importTarget',struct()), NMDataIOProbeTools.fieldOr(IO,'varind',1));
            targetNames = NMDataIOImportTools.trainingFeatureNames(NM, importTarget.varind);
            if isempty(targetNames), return; end
            mappingMode = lower(strtrim(char(string(NMDataIOProbeTools.fieldOr(IO,'featureMappingMode','automatic')))));
            if ~strcmp(mappingMode,'manual'), mappingMode = 'automatic'; end
            refs = NMDataIOStateTools.roleRefCell(sourceVariables);
            roles = NMDataIOProbeTools.fieldOr(IO,'variableRoles',struct());
            excluded = NMDataIOProbeTools.nonFeatureRoleRefIds(roles);
            candidates = {}; sourceNames = {}; sourceIds = {};
            for i = 1:numel(refs)
                ref = refs{i};
                rid = NMDataIOProbeTools.sourceRefId(ref);
                if ~isempty(rid) && any(strcmp(excluded,rid)), continue; end
                candidates{end+1,1} = ref; %#ok<AGROW>
                sourceNames{end+1} = NMDataIOProbeTools.sourceRefColumnName(ref); %#ok<AGROW>
                sourceIds{end+1} = rid; %#ok<AGROW>
            end
            oldFeatures = {};
            if isstruct(roles) && isfield(roles,'features'), oldFeatures = NMDataIOStateTools.roleRefCell(roles.features); end
            if strcmp(mappingMode,'manual')
                nTarget = numel(targetNames);
                assignments = repmat({{}},1,nTarget);
                assignmentLive = repmat({false(1,0)},1,nTarget);
                assignedSourceIds = {};
                invalidAssignments = {};
                for i = 1:numel(oldFeatures)
                    prior = oldFeatures{i};
                    ti = double(NMDataIOProbeTools.fieldOr(prior,'targetFeatureIndex',NaN));
                    rid = NMDataIOProbeTools.sourceRefId(prior);
                    if ~isfinite(ti) || ti < 1 || ti > nTarget || ti ~= round(ti) || isempty(rid)
                        invalidAssignments{end+1} = rid; %#ok<AGROW>
                        continue;
                    end
                    live = NMDataIOProbeTools.refById(candidates,rid);
                    if isempty(live)
                        ref = prior; isLive = false;
                    else
                        ref = live; isLive = true;
                        if isfield(prior,'caseKeyRefs') && ~isempty(prior.caseKeyRefs), ref.caseKeyRefs = prior.caseKeyRefs; end
                    end
                    ref.targetFeatureIndex = ti;
                    assignments{ti}{end+1,1} = ref; %#ok<AGROW>
                    assignmentLive{ti}(end+1) = isLive; %#ok<AGROW>
                    assignedSourceIds{end+1} = rid; %#ok<AGROW>
                end
                duplicateSourceIds = {};
                uniqueAssigned = unique(assignedSourceIds,'stable');
                for i = 1:numel(uniqueAssigned)
                    if sum(strcmp(assignedSourceIds,uniqueAssigned{i})) > 1, duplicateSourceIds{end+1} = uniqueAssigned{i}; end %#ok<AGROW>
                end
                report.enabled = true;
                report.mode = 'manual';
                report.targetNames = targetNames;
                report.targetStatus = repmat({'missing'},1,nTarget);
                report.targetSourceIds = cell(1,nTarget);
                report.targetSourceLabels = cell(1,nTarget);
                report.duplicateSourceIds = duplicateSourceIds;
                featureRefs = {};
                usedLiveSourceIds = {};
                for t = 1:nTarget
                    items = assignments{t};
                    liveFlags = assignmentLive{t};
                    ids = cell(1,numel(items)); labels = cell(1,numel(items));
                    for j = 1:numel(items)
                        ids{j} = NMDataIOProbeTools.sourceRefId(items{j});
                        labels{j} = NMDataIOProbeTools.sourceRefLabel(items{j});
                        featureRefs{end+1,1} = items{j}; %#ok<AGROW>
                        if liveFlags(j), usedLiveSourceIds{end+1} = ids{j}; end %#ok<AGROW>
                    end
                    report.targetSourceIds{t} = ids;
                    report.targetSourceLabels{t} = labels;
                    if isempty(items)
                        report.targetStatus{t} = 'missing';
                    elseif numel(items) > 1 || any(ismember(ids,duplicateSourceIds))
                        report.targetStatus{t} = 'ambiguous';
                    elseif ~all(liveFlags)
                        report.targetStatus{t} = 'invalid';
                    else
                        report.targetStatus{t} = 'matched';
                    end
                end
                report.missingColumns = targetNames(strcmp(report.targetStatus,'missing'));
                report.ambiguousColumns = targetNames(strcmp(report.targetStatus,'ambiguous'));
                report.unresolvedTargetIndices = find(strcmp(report.targetStatus,'missing'));
                report.ambiguousTargetIndices = find(strcmp(report.targetStatus,'ambiguous'));
                report.invalidTargetIndices = find(strcmp(report.targetStatus,'invalid'));
                report.extraColumns = sourceNames(~ismember(sourceIds,usedLiveSourceIds));
                if ~isempty(invalidAssignments), report.invalidAssignments = invalidAssignments; end
                if ~isstruct(roles), roles = struct(); end
                roles.features = featureRefs;
                IO.variableRoles = roles;
                if ~isempty(report.missingColumns)
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureCorrespondence', ...
                        sprintf('%g training feature(s) are currently unassigned in manual mapping: %s. They will be retained as missing targets and require OOCV-level feature imputation before model application.', ...
                        numel(report.missingColumns), strjoin(report.missingColumns(1:min(end,8)), ', ')), 2, 'SystemCommands')];
                end
                if ~isempty(report.ambiguousColumns) || ~isempty(report.duplicateSourceIds)
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureCorrespondence', ...
                        'Manual OOCV feature correspondence contains duplicate target/source assignments. Clear the conflicting assignment before Preview/Commit.', 2, 'SystemCommands')];
                end
                if ~isempty(report.invalidTargetIndices) || ~isempty(invalidAssignments)
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureCorrespondence', ...
                        'One or more saved manual feature assignments cannot be resolved against the current included source columns. Repair or clear the invalid assignment before Preview/Commit.', 2, 'SystemCommands')];
                end
                return;
            end

            report = NMDataIOTableRoleTools.featureCorrespondence(sourceNames, targetNames);
            report.targetSourceIds = cell(1,numel(targetNames));
            report.targetSourceLabels = cell(1,numel(targetNames));
            report.invalidTargetIndices = [];
            report.duplicateSourceIds = {};
            featureRefs = {};
            for t = 1:numel(targetNames)
                hits = report.targetSourceIndices{t};
                ids = cell(1,numel(hits)); labels = cell(1,numel(hits));
                for j = 1:numel(hits)
                    ref = candidates{hits(j)};
                    rid = NMDataIOProbeTools.sourceRefId(ref);
                    ref.targetFeatureIndex = t;
                    prior = NMDataIOProbeTools.refById(oldFeatures,rid);
                    if ~isempty(prior) && isfield(prior,'caseKeyRefs') && ~isempty(prior.caseKeyRefs)
                        ref.caseKeyRefs = prior.caseKeyRefs;
                    end
                    featureRefs{end+1,1} = ref; %#ok<AGROW>
                    ids{j} = rid;
                    labels{j} = NMDataIOProbeTools.sourceRefLabel(ref);
                end
                report.targetSourceIds{t} = ids;
                report.targetSourceLabels{t} = labels;
            end
            if ~isstruct(roles), roles = struct(); end
            roles.features = featureRefs;
            IO.variableRoles = roles;
            if ~isempty(report.missingColumns)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureCorrespondence', ...
                    sprintf('%g training feature(s) are currently unassigned: %s. They will be retained as missing targets and require OOCV-level feature imputation before model application.', ...
                    numel(report.missingColumns), strjoin(report.missingColumns(1:min(end,8)), ', ')), 2, 'SystemCommands')];
            end
            if ~isempty(report.ambiguousColumns)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureCorrespondence', ...
                    sprintf('Automatic OOCV feature correspondence is ambiguous for: %s. Preview/Commit will remain blocked until each target has at most one included source column.', ...
                    strjoin(report.ambiguousColumns(1:min(end,8)), ', ')), 2, 'SystemCommands')];
            end
            if ~isempty(report.extraColumns)
                messages = [messages; NMDataIOMessageTools.make('info', false, 'featureCorrespondence', ...
                    sprintf('%g included source column(s) do not belong to the trained feature axis and will be ignored.', numel(report.extraColumns)), 0, 'blue')];
            end
        end

        function ids = nonFeatureRoleRefIds(roles)
            ids = {};
            if ~isstruct(roles), return; end
            names = {'caseId','labels','covariates','covariateNames','featureNames'};
            for r = 1:numel(names)
                if ~isfield(roles,names{r}), continue; end
                refs = NMDataIOStateTools.roleRefCell(roles.(names{r}));
                for i = 1:numel(refs)
                    rid = NMDataIOProbeTools.sourceRefId(refs{i});
                    if ~isempty(rid), ids{end+1} = rid; end %#ok<AGROW>
                    if isstruct(refs{i}) && isfield(refs{i},'caseKeyRefs')
                        keys = NMDataIOStateTools.roleRefCell(refs{i}.caseKeyRefs);
                        for k = 1:numel(keys)
                            kid = NMDataIOProbeTools.sourceRefId(keys{k});
                            if ~isempty(kid), ids{end+1} = kid; end %#ok<AGROW>
                        end
                    end
                end
            end
            if isfield(roles,'features')
                refs = NMDataIOStateTools.roleRefCell(roles.features);
                for i = 1:numel(refs)
                    if isstruct(refs{i}) && isfield(refs{i},'caseKeyRefs')
                        keys = NMDataIOStateTools.roleRefCell(refs{i}.caseKeyRefs);
                        for k = 1:numel(keys)
                            kid = NMDataIOProbeTools.sourceRefId(keys{k});
                            if ~isempty(kid), ids{end+1} = kid; end %#ok<AGROW>
                        end
                    end
                end
            end
            ids = unique(ids,'stable');
        end

        function ref = refById(refs, rid)
            ref = [];
            for i = 1:numel(refs)
                if strcmp(NMDataIOProbeTools.sourceRefId(refs{i}),rid), ref = refs{i}; return; end
            end
        end

        function id = sourceRefId(ref)
            id = '';
            if ~isstruct(ref), return; end
            if isfield(ref,'id') && ~isempty(ref.id), id = char(string(ref.id));
            elseif isfield(ref,'name') && ~isempty(ref.name), id = char(string(ref.name));
            end
        end

        function name = sourceRefColumnName(ref)
            name = '';
            if ~isstruct(ref), return; end
            if isfield(ref,'columnName') && ~isempty(ref.columnName), name = char(string(ref.columnName));
            elseif isfield(ref,'name') && ~isempty(ref.name), name = char(string(ref.name));
            end
        end

        function label = sourceRefLabel(ref)
            label = NMDataIOProbeTools.sourceRefColumnName(ref);
            if ~isstruct(ref), return; end
            source = '';
            if isfield(ref,'sourceLabel') && ~isempty(ref.sourceLabel), source = char(string(ref.sourceLabel));
            elseif isfield(ref,'sourceObject') && ~isempty(ref.sourceObject), source = char(string(ref.sourceObject));
            elseif isfield(ref,'sourceName') && ~isempty(ref.sourceName), source = char(string(ref.sourceName));
            end
            if ~isempty(source), label = sprintf('%s [%s]',label,source); end
        end

        function out = emptyProbeOut()
            % emptyProbeOut  Create the fixed-schema probe output returned by DataIO validation services.
            %
            % No required inputs -> out.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            out = struct();
            out.ok = false;
            out.readyToImport = false;
            out.blocking = true;
            out.message = '';
            out.strip = NMDataIOMessageTools.highestPriorityStrip([], 'Not checked.');
            out.messages = NMDataIOMessageTools.emptyMessages();
            out.summary = NMDataIOMessageTools.summarize(out.messages);
            out.probe = struct();
            out.ioSummary = struct();
            out.stateEcho = struct();
        end

        function out = finish(out, messages, IO, probe)
            % finish  Finalize a probe output by attaching messages, IO state, and summary payloads.
            %
            % Consumes out, messages, IO, probe; returns out.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 4 || isempty(probe)
                if nargin >= 3 && isstruct(IO) && ~isempty(IO)
                    probe = NMDataIOProbeTools.matrixSummaryFromIO(IO, struct());
                else
                    probe = struct();
                end
            end
            strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Matrix/table input check completed.');
            out.messages = NMDataIOMessageTools.forDiagnosticsPanel(messages);
            out.summary = NMDataIOMessageTools.summarize(messages);
            out.strip = strip;
            out.message = strip.text;
            out.blocking = strip.blocking;
            out.readyToImport = ~strip.blocking;
            out.ok = ~strip.blocking;
            out.probe = probe;
            if nargin >= 3 && isstruct(IO) && ~isempty(IO)
                out.ioSummary = NMDataIOProbeTools.ioSummary(IO);
                out.statePatch = NMDataIOStateTools.ioToState(NMDataIOProbeTools.stripTransientIO(IO));
            end
        end

        function probe = matrixSummaryFromIO(IO, summaries)
            % matrixSummaryFromIO  Build a compact matrix-source summary from IO and feature-stat reports.
            %
            % IO, summaries -> probe.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 2 || isempty(summaries), summaries = struct(); end
            probe = struct();
            probe.datasource = NMDataIOProbeTools.fieldOr(IO,'datasource','matrix');
            probe.groupmode = NMDataIOProbeTools.fieldOr(IO,'groupmode',NaN);
            probe.groupmodeName = NMDataIOStateTools.groupmodeName(probe.groupmode);
            probe.matrixSummary = NMDataIOProbeTools.fieldOr(summaries,'matrix','');
            probe.labelSummary = NMDataIOProbeTools.fieldOr(summaries,'label','');
            probe.caseIdSummary = NMDataIOProbeTools.fieldOr(summaries,'caseId','');
            probe.featureNamesSummary = NMDataIOProbeTools.fieldOr(summaries,'featureNames','');
            probe.nSubjectsRaw = NaN;
            probe.nFeaturesRaw = NaN;
            probe.nSelectedSubjects = NaN;
            probe.nSelectedFeatures = NaN;
            probe.hasNaN = [];
            probe.nNaN = NaN;
            probe.nanFraction = NaN;
            probe.hasInf = [];
            probe.nInf = NaN;
            probe.hasNonFinite = [];
            probe.nNonFinite = NaN;
            probe.nonFiniteFraction = NaN;
            probe.previewAvailable = false;
            vm = NMDataIOProbeTools.fieldOr(IO,'variableMaterialization',struct());
            probe.numericSourceIssues = NMDataIOProbeTools.fieldOr(vm,'numericSourceIssues',[]);

            if ismember(double(probe.groupmode), [3 4 5 6]) && ...
                    ~NMDataIOImportTools.hasResolvedMatrixPayload(IO)
                h = NMDataIOTableReadTools.probeHeaders(IO, struct('MaxRows',30));
                if h.ok
                    probe.tableColumns = h.columns;
                    probe.rawTableColumns = h.rawColumns;
                    probe.sheets = h.sheets;
                    probe.selectedSheets = NMDataIOProbeTools.fieldOr(h,'selectedSheets',{});
                    probe.sheet = h.sheet;
                    probe.headerRow = h.headerRow;
                    probe.headerRows = NMDataIOProbeTools.fieldOr(h,'headerRows',[]);
                    probe.columnSources = NMDataIOProbeTools.fieldOr(h,'columnSources',{});
                    probe.commonColumns = NMDataIOProbeTools.fieldOr(h,'commonColumns',{});
                else
                    probe.tableHeaderProbeMessage = h.message;
                end
            end

            [M, ok, importReport] = NMDataIOProbeTools.featureMatrixForSummary(IO);
            if ~isempty(importReport)
                probe.importReport = importReport;
                if isstruct(importReport) && isfield(importReport,'columnRoles')
                    roles = importReport.columnRoles;
                    if isfield(roles,'allColumns'), probe.tableColumns = roles.allColumns; end
                    if isfield(roles,'features') && ~isempty(roles.features)
                        nF = numel(roles.features);
                        showN = min(nF, 8);
                        previewNames = strjoin(roles.features(1:showN), ', ');
                        if nF > showN, previewNames = [previewNames ', ...']; end
                        probe.featureNamesSummary = sprintf('Table headers: %g feature column(s): %s', nF, previewNames);
                    end
                end
            end
            if ok
                probe.previewAvailable = true;
                probe.nSubjectsRaw = size(M,1);
                probe.nFeaturesRaw = size(M,2);
                if isnumeric(M) || islogical(M)
                    stats = NMDataIOProbeTools.probeFeatureStats(M, 1e7);
                    probe.featureStats = stats;
                    if stats.computed
                        probe.hasNaN = stats.hasNaN;
                        probe.nNaN = stats.nNaN;
                        probe.nanFraction = stats.nanFraction;
                        probe.hasInf = stats.hasInf;
                        probe.nInf = stats.nInf;
                        probe.hasNonFinite = stats.hasNonFinite;
                        probe.nNonFinite = stats.nNonFinite;
                        probe.nonFiniteFraction = stats.nonFiniteFraction;
                    end
                end
            elseif isfield(IO,'t_Y') && ~isempty(IO.t_Y)
                probe.nSubjectsRaw = size(IO.t_Y,1);
                probe.nFeaturesRaw = size(IO.t_Y,2);
            end

            if isfield(IO,'selCases') && ~isempty(IO.selCases)
                probe.nSelectedSubjects = sum(logical(IO.selCases));
            elseif isfinite(probe.nSubjectsRaw)
                probe.nSelectedSubjects = probe.nSubjectsRaw;
            end
            if isfield(IO,'selFeats') && ~isempty(IO.selFeats)
                probe.nSelectedFeatures = sum(logical(IO.selFeats));
            elseif isfinite(probe.nFeaturesRaw)
                probe.nSelectedFeatures = probe.nFeaturesRaw;
            end
        end

        function stats = probeFeatureStats(M, maxElements)
            % probeFeatureStats  Compute bounded descriptive statistics for an explicit DataIO probe.
            if nargin < 2 || isempty(maxElements), maxElements = 1e7; end
            nCases = double(size(M,1));
            nFeatures = double(size(M,2));
            if double(numel(M)) > double(maxElements)
                stats = NMDataIOFeatureStatsTools.skippedStats(nCases, nFeatures, ...
                    sprintf('Quick QC was skipped because the selected data contain more than %g numeric values.', double(maxElements)), ...
                    double(maxElements), class(M));
                return;
            end
            stats = NMDataIOFeatureStatsTools.computeFromMatrix(M, struct('MaxFeatureStatsChunkElements', 5e6));
        end

        function [M, ok, importReport] = featureMatrixForSummary(IO)
            % featureMatrixForSummary  Extract a numeric matrix suitable for feature-summary checks from IO.
            %
            % Consumes IO; returns M, ok, importReport.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            M = [];
            ok = false;
            importReport = [];
            if ~isstruct(IO), return; end
            try
                if isfield(IO,'importReport') && isstruct(IO.importReport)
                    importReport = IO.importReport;
                end
                if isfield(IO,'Y') && ~isempty(IO.Y)
                    M = IO.Y;
                    if istable(M), M = table2array(M); end
                    ok = ismatrix(M);
                    return;
                end
                if ~isfield(IO,'t_Y') || isempty(IO.t_Y), return; end
                if istable(IO.t_Y)
                    if exist('NMDataIOTableRoleTools','class') == 8 || exist('NMDataIOTableRoleTools','file') == 2
                        mess = [];
                        [M, ~, importReport2, mess] = NMDataIOTableRoleTools.featureMatrixForCheck(IO, IO.t_Y, mess); %#ok<ASGLU>
                        if exist('CheckReadyStatus','file') == 2 && CheckReadyStatus(mess)
                            M = [];
                        end
                        if isstruct(importReport2)
                            importReport = importReport2;
                        end
                    else
                        names = IO.t_Y.Properties.VariableNames;
                        col_cases = strcmp(names, char(IO.case_edit));
                        col_label = NMDataIOProbeTools.labelColumns(names, IO.label_edit);
                        T = IO.t_Y(:, ~col_cases & ~col_label);
                        M = table2array(T);
                    end
                else
                    M = IO.t_Y;
                end
                if ismatrix(M)
                    ok = true;
                end
            catch ME
                M = [];
                ok = false;
                importReport = struct('summaryError', ME.message, 'summaryErrorIdentifier', ME.identifier);
            end
        end

        function cols = labelColumns(names, label_edit)
            % labelColumns  Map selected label-role names onto table column indices.
            %
            % Names, label_edit -> cols.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            cols = false(size(names));
            if isempty(label_edit), return; end
            if ischar(label_edit) || isa(label_edit,'string')
                labels = cellstr(label_edit);
            elseif iscell(label_edit)
                labels = label_edit;
            else
                labels = {};
            end
            for i = 1:numel(labels)
                cols = cols | strcmp(names, labels{i});
            end
        end

        function tf = shouldCheck(IO, fieldName, na)
            % shouldCheck  Decide whether an optional role/source field should participate in validation.
            %
            % Consumes IO, fieldName, na; returns tf.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            tf = isfield(IO,fieldName) && ~NMDataIOProbeTools.isUnknown(IO.(fieldName), na);
        end

        function tf = isUnknown(v, na)
            % isUnknown  Apply the local DataIO unknown/empty sentinel test.
            %
            % V, na -> tf.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2, na = '?'; end
            if isempty(v), tf = true; return; end
            if ischar(v) || isa(v,'string')
                tf = any(strcmp(cellstr(v), na));
            elseif iscell(v)
                tf = any(cellfun(@(x) isempty(x) || strcmp(char(string(x)), na), v));
            else
                tf = false;
            end
        end

        function s = ioSummary(IO)
            % ioSummary  Build a compact source summary for diagnostics and UI display.
            %
            % IO -> s.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            s = struct();
            if nargin < 1 || isempty(IO), return; end
            fields = {'varind','datasource','groupmode','modeflag','labels_known','oocvflag', ...
                'M_edit','matrix_edit','label_edit','case_edit','col_edit','covnames_edit','covar_edit','ignore_edit','feature_edit','delimit','sheet','headerRow','headerAutoDetect','desc_data'};
            for i = 1:numel(fields)
                if isfield(IO,fields{i})
                    s.(fields{i}) = IO.(fields{i});
                end
            end
            if isfield(IO,'t_Y') && ~isempty(IO.t_Y)
                s.tYClass = class(IO.t_Y);
                s.tYSize = size(IO.t_Y);
            end
        end

        function IO2 = stripTransientIO(IO)
            % stripTransientIO  Remove heavy/transient IO fields before returning probe state to UI/API callers.
            %
            % IO -> IO2.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % Cache contents are an acceleration/rehydration artifact, not a new source of truth.
            IO2 = IO;
            heavy = {'t_Y','Y','s_label','s_ID','s_featnames','label','covars','covnames','P','PP','V','VV','Vm','Vmvol', ...
                'sourceBlockReferenceCases','dataioPreparedCacheKey','dataioPreparedCacheHit','dataioAlignedCacheKey','dataioAlignedCacheHit'};
            for i = 1:numel(heavy)
                if isfield(IO2, heavy{i})
                    IO2 = rmfield(IO2, heavy{i});
                end
            end
        end

        function v = opt(opts, name, defaultValue)
            % opt  Read an option field with a caller-specific default without changing option semantics.
            %
            % Consumes opts, name, defaultValue; returns v.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isstruct(opts) && isfield(opts,name) && ~isempty(opts.(name))
                v = opts.(name);
            else
                v = defaultValue;
            end
        end

        function v = fieldOr(s, name, defaultValue)
            % fieldOr  Read a struct field with a caller-specific default when the field is absent or empty.
            %
            % Consumes s, name, defaultValue; returns v.
            % It belongs to the non-mutating probe layer that decides whether preview/commit controls can be enabled.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
                v = s.(name);
            else
                v = defaultValue;
            end
        end
    end
end

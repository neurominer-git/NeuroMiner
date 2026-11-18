classdef NMDataIOTableReadTools
% NMDataIOTableReadTools
% -------------------------------------------------------------------------
% Small compatibility helper for tabular text/spreadsheet import in the
% browser DataIO path.  It centralizes sheet/header-row handling without
% changing legacy behavior when IO.headerRow / IO.headerAutoDetect are absent.
% Legacy CheckTabFile.m and ReadTabular.m call this helper opportunistically.
% -------------------------------------------------------------------------

    methods (Static)
        function T = readTableFromIO(IO)
            % readTableFromIO  Read a text, spreadsheet, database, or cached table source described by IO.
            %
            % Consumes IO; returns T.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % May inspect or update the MATLAB workspace according to the source mode; throws on invalid preconditions instead of returning an ambiguous partial result; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            if ~isstruct(IO) || ~isfield(IO,'groupmode')
                error('NMDataIOTableReadTools:invalidIO', 'IO.groupmode is required.');
            end

            % Browser DataIO services are stateless at the HTTP/JSON layer,
            % but the MATLAB process remains alive.  Preserve the legacy
            % IN.t_Y principle by caching parsed file/database tables in
            % MATLAB memory and reusing them across preview, item-selector
            % and commit calls as long as the source fingerprint is unchanged.
            cacheKey = NMDataIOTableReadTools.tableCacheKey(IO);
            if ~isempty(cacheKey)
                [hit, T] = NMDataIOTableReadTools.tableCache('get', cacheKey);
                if hit
                    return;
                end
            end

            projectedColumns = NMDataIOTableReadTools.sourceProjectionColumns(IO);
            switch double(IO.groupmode)
                case 3
                    T = NMDataIOTableReadTools.readTextTable(IO);
                case 4
                    T = NMDataIOTableReadTools.readSpreadsheetTable(IO);
                case 5
                    tableVar = NMDataIOTableReadTools.fieldOr(IO,'M_edit','?');
                    if NMDataIOTableReadTools.isUnknown(tableVar)
                        tableVar = NMDataIOTableReadTools.fieldOr(IO,'tableVariable','?');
                    end
                    T = evalin('base', char(tableVar));
                    if ~istable(T)
                        error('NMDataIOTableReadTools:notTableVariable', 'Workspace variable ''%s'' is not a MATLAB table.', char(tableVar));
                    end
                    if ~isempty(projectedColumns)
                        T = NMDataIOTableReadTools.projectTableColumns(T, projectedColumns, char(tableVar));
                    end
                case 6
                    if exist('NMDataIODatabaseTools','class') ~= 8 && exist('NMDataIODatabaseTools','file') ~= 2
                        error('NMDataIOTableReadTools:noDatabaseTools', 'NMDataIODatabaseTools.m is required for database imports.');
                    end
                    dbOpts = struct();
                    selectedColumns = NMDataIOTableReadTools.fieldOr(IO,'databaseSelectedColumns',{});
                    if ~isempty(projectedColumns), selectedColumns = projectedColumns; end
                    useQuery = logical(NMDataIOTableReadTools.fieldOr(IO,'databaseUseQuery',false));
                    if ~isempty(selectedColumns) && ~useQuery
                        dbOpts.Columns = selectedColumns;
                    end
                    T = NMDataIODatabaseTools.readResultTable(IO, dbOpts);
                    if useQuery && ~isempty(projectedColumns)
                        T = NMDataIOTableReadTools.projectTableColumns(T, projectedColumns, 'custom SQL result');
                    end
                otherwise
                    error('NMDataIOTableReadTools:unsupportedGroupmode', 'Only text/spreadsheet/table-variable/database groupmodes are supported.');
            end

            if ~isempty(cacheKey)
                NMDataIOTableReadTools.tableCache('set', cacheKey, T);
            end
        end

        function out = probeWideNumericFile(fileName, caseColumn)
            % probeWideNumericFile  Probe a file-backed wide numeric table without materializing feature columns as a MATLAB table.
            %
            % fileName, caseColumn -> out.
            % This generic tabular primitive preserves source headers and MATLAB
            % import-type inference, while reading only the Case-ID column. The
            % caller may then select scientifically relevant numeric variables
            % before materializing them through readWideNumericColumns.
            fileName = char(string(fileName));
            caseColumn = char(string(caseColumn));
            if exist(fileName,'file') ~= 2
                error('NMDataIOTableReadTools:wideNumericMissingFile', ...
                    'Wide numeric table file does not exist: %s', fileName);
            end
            if isempty(strtrim(caseColumn)) || strcmp(strtrim(caseColumn),'?')
                error('NMDataIOTableReadTools:wideNumericMissingCaseColumn', ...
                    'Wide numeric table import requires an explicit case-ID column name.');
            end

            importOpts = detectImportOptions(fileName, 'VariableNamingRule','preserve');
            variableNames = cellstr(string(importOpts.VariableNames));
            caseIndex = find(strcmp(variableNames, caseColumn), 1);
            if isempty(caseIndex)
                error('NMDataIOTableReadTools:wideNumericCaseColumnMissing', ...
                    'Case-ID column ''%s'' was not found in %s.', caseColumn, fileName);
            end

            variableTypes = cellstr(string(importOpts.VariableTypes));
            numericTypes = {'double','single','logical','int8','uint8','int16','uint16','int32','uint32','int64','uint64'};
            variableTypesLower = cellstr(lower(string(variableTypes)));
            numericMask = ismember(variableTypesLower, numericTypes);

            caseOpts = importOpts;
            caseOpts.SelectedVariableNames = {caseColumn};
            caseOpts = setvartype(caseOpts, caseColumn, 'string');
            caseTable = readtable(fileName, caseOpts);
            if width(caseTable) ~= 1
                error('NMDataIOTableReadTools:wideNumericCaseColumnRead', ...
                    'Expected one Case-ID column from %s; read %g columns.', fileName, width(caseTable));
            end
            caseIDs = cellstr(string(caseTable{:,1}));
            caseIDs = caseIDs(:);

            out = struct('fileName',fileName, 'variableNames',{variableNames}, ...
                'variableTypes',{variableTypes}, 'numericMask',logical(numericMask), ...
                'caseIDs',{caseIDs}, 'caseColumn',caseColumn, 'caseColumnIndex',caseIndex, ...
                'nRows',double(numel(caseIDs)), 'importOptions',importOpts);
        end

        function data = readWideNumericColumns(probe, columnNames)
            % readWideNumericColumns  Materialize selected numeric variables from a probed wide file directly into a matrix.
            %
            % probe, columnNames -> data. The probe must come from
            % probeWideNumericFile. No MATLAB table with one variable per
            % feature is created for the selected numeric payload.
            if ~isstruct(probe) || ~isscalar(probe) || ~isfield(probe,'importOptions') || ...
                    ~isfield(probe,'fileName') || ~isfield(probe,'variableNames') || ...
                    ~isfield(probe,'numericMask') || ~isfield(probe,'nRows')
                error('NMDataIOTableReadTools:badWideNumericProbe', ...
                    'Wide numeric column materialization requires the probeWideNumericFile result.');
            end
            columnNames = cellstr(string(columnNames));
            columnNames = columnNames(:)';
            if isempty(columnNames)
                data = zeros(double(probe.nRows),0);
                return;
            end
            [tf, loc] = ismember(columnNames, probe.variableNames);
            if ~all(tf)
                missing = columnNames(~tf);
                error('NMDataIOTableReadTools:wideNumericColumnMissing', ...
                    'Requested wide numeric column(s) are absent from %s: %s.', ...
                    probe.fileName, strjoin(missing, ', '));
            end
            numericMask = logical(probe.numericMask(:)');
            if numel(numericMask) ~= numel(probe.variableNames)
                error('NMDataIOTableReadTools:wideNumericSchemaMismatch', ...
                    'Wide-table probe has %g variable names but %g numeric-type flags.', ...
                    numel(probe.variableNames), numel(numericMask));
            end
            if ~all(numericMask(loc))
                bad = columnNames(~numericMask(loc));
                error('NMDataIOTableReadTools:wideNumericColumnType', ...
                    'Requested wide-table column(s) are not numeric according to source type inference: %s.', ...
                    strjoin(bad, ', '));
            end

            % readmatrix requires one homogeneous selected type. The probe has
            % already established which requested variables are numeric, so use
            % a numeric-only materialization pass over the detected source schema
            % and select the requested edge columns afterward by their original
            % source positions. Text Case-ID/metadata cells become NaN in this
            % pass and are ignored; Case IDs were materialized separately above.
            numericOpts = probe.importOptions;
            numericOpts.SelectedVariableNames = probe.variableNames;
            numericOpts = setvartype(numericOpts, probe.variableNames, 'double');
            dataAll = readmatrix(probe.fileName, numericOpts);
            if ~isnumeric(dataAll)
                error('NMDataIOTableReadTools:wideNumericPayloadType', ...
                    'Numeric payload from %s did not materialize as a numeric matrix.', probe.fileName);
            end
            if size(dataAll,2) ~= numel(probe.variableNames)
                error('NMDataIOTableReadTools:wideNumericSourceWidth', ...
                    ['Numeric payload from %s has %g columns, but header metadata contain %g. ', ...
                     'NM2 cannot preserve source-column identity safely.'], ...
                    probe.fileName, size(dataAll,2), numel(probe.variableNames));
            end
            data = dataAll(:,loc);
            nRows = double(probe.nRows);
            nCols = numel(columnNames);
            if numel(data) == nRows*nCols && ~isequal(size(data), [nRows nCols])
                data = reshape(data, nRows, nCols);
            end
            if size(data,1) ~= nRows || size(data,2) ~= nCols
                error('NMDataIOTableReadTools:wideNumericPayloadShape', ...
                    ['Selected numeric payload from %s has size %gx%g, but Case-ID/header metadata ', ...
                     'require %gx%g.'], probe.fileName, size(data,1), size(data,2), nRows, nCols);
            end
            data = double(data);
        end

        function out = probeHeaders(IO, opts)
            % probeHeaders  Probe table headers without committing data to NM.
            %
            % Table-file sources are discovered as independent worksheet/file objects.
            % Scientific cross-object alignment is never performed in this reader.
            if nargin < 2 || isempty(opts), opts = struct(); end
            out = struct();
            out.ok = false;
            out.message = '';
            out.sheets = {};
            out.selectedSheets = {};
            out.sheet = NMDataIOTableReadTools.fieldOr(IO,'sheet','?');
            out.headerRow = NMDataIOTableReadTools.headerRow(IO, []);
            out.headerRows = [];
            out.headerRowAutoDetected = false;
            out.columns = {};
            out.rawColumns = {};
            out.internalColumns = {};
            out.columnSources = {};
            out.duplicateColumns = {};
            out.commonColumns = {};
            out.nColumns = 0;
            out.nPreviewRows = 0;
            out.diagnostics = {};
            out.performance = struct();
            out.sourceVariables = struct('id',{},'name',{},'sourceType',{},'sourcePath',{},'sourceObject',{},'sourceName',{},'sourceLabel',{},'columnName',{},'class',{},'size',{},'headerRow',{},'delimit',{},'groupmode',{});

            sourceType = lower(strtrim(char(string(NMDataIOTableReadTools.fieldOr(IO,'sourceType','')))));
            if strcmp(sourceType,'tablefile')
                out = NMDataIOTableReadTools.probeTableFileSources(IO, opts, out);
                return;
            elseif strcmp(sourceType,'tablevar')
                out = NMDataIOTableReadTools.probeTableVariableSources(IO, opts, out);
                return;
            end

            tableSource = NMDataIOTableReadTools.fieldOr(IO,'M_edit','?');
            if isfield(IO,'groupmode') && double(IO.groupmode) == 5 && NMDataIOTableReadTools.isUnknown(tableSource)
                tableSource = NMDataIOTableReadTools.fieldOr(IO,'tableVariable','?');
            end
            if isfield(IO,'groupmode') && double(IO.groupmode) == 6
                try
                    if exist('NMDataIODatabaseTools','class') ~= 8 && exist('NMDataIODatabaseTools','file') ~= 2
                        error('NMDataIOTableReadTools:noDatabaseTools', 'NMDataIODatabaseTools.m is required for database imports.');
                    end
                    dbHeader = NMDataIODatabaseTools.probeHeaders(IO, opts);
                    out = dbHeader;
                    return;
                catch ME
                    out.ok = false;
                    out.message = ME.message;
                    out.identifier = ME.identifier;
                    return;
                end
            end
            if NMDataIOTableReadTools.isUnknown(tableSource)
                out.message = 'No table file/source has been selected.';
                return;
            end
            if isfield(IO,'groupmode') && double(IO.groupmode) ~= 5 && exist(char(tableSource),'file') ~= 2
                out.message = sprintf('Table source does not exist: %s', char(tableSource));
                return;
            end

            try
                if double(IO.groupmode) == 5
                    T = evalin('base', char(tableSource));
                    if ~istable(T)
                        error('NMDataIOTableReadTools:notTableVariable', 'Workspace variable ''%s'' is not a MATLAB table.', char(tableSource));
                    end
                    out.rawColumns = NMDataIOTableReadTools.originalColumnNames(T);
                    out.columns = out.rawColumns;
                    out.internalColumns = T.Properties.VariableNames;
                    out.nColumns = numel(out.columns);
                    out.nPreviewRows = min(height(T), NMDataIOTableReadTools.opt(opts,'MaxRows',30));
                    out.headerRow = [];
                    out.headerRows = [];
                    out.headerRowAutoDetected = false;
                    out.ok = out.nColumns > 0;
                    out.message = sprintf('Detected %g column(s) in MATLAB table variable ''%s''.', out.nColumns, char(tableSource));
                    return;
                end

                if double(IO.groupmode) == 4
                    out.sheets = NMDataIOTableReadTools.spreadsheetSheets(char(IO.M_edit));
                    selectedSheets = NMDataIOTableReadTools.selectedSpreadsheetSheets(IO, out.sheets);
                    out.selectedSheets = selectedSheets;
                    out.sheet = selectedSheets{1};
                    requestedHeaderRow = NMDataIOTableReadTools.headerRow(IO, []);
                    maxRows = NMDataIOTableReadTools.opt(opts,'MaxRows',30);

                    if numel(selectedSheets) > 1
                        error('NMDataIOTableReadTools:multiSheetRequiresSourceBlocks', ...
                            'Each selected spreadsheet worksheet must be added as a separate input table/sheet.');
                    end
                end

                if double(IO.groupmode) == 4
                    meta = NMDataIOTableReadTools.probeSpreadsheetSheet(IO, out.sheet, NMDataIOTableReadTools.opt(opts,'MaxRows',30), out.headerRow);
                    out.nPreviewRows = meta.nPreviewRows;
                    out.headerRow = meta.headerRow;
                    out.headerRowAutoDetected = meta.autoDetected;
                    if meta.autoDetected
                        out.diagnostics{end+1,1} = sprintf('Auto-detected header row %g (score %.3g).', out.headerRow, meta.score);
                    end
                    rawNames = meta.rawNames;
                else
                    raw = NMDataIOTableReadTools.readRawTopRows(IO, out.sheet, NMDataIOTableReadTools.opt(opts,'MaxRows',30));
                    out.nPreviewRows = size(raw,1);
                    if isempty(out.headerRow)
                        [out.headerRow, scoreInfo] = NMDataIOTableReadTools.detectHeaderRow(raw);
                        out.headerRowAutoDetected = true;
                        out.diagnostics{end+1,1} = sprintf('Auto-detected header row %g (score %.3g).', out.headerRow, scoreInfo.score);
                    end
                    if isempty(out.headerRow) || out.headerRow < 1 || out.headerRow > size(raw,1)
                        out.message = 'Could not determine a valid header row.';
                        return;
                    end
                    rawNames = NMDataIOTableReadTools.rowToCellstr(raw(out.headerRow,:));
                end
                out.rawColumns = rawNames;
                out.columns = rawNames;
                out.internalColumns = NMDataIOTableReadTools.makeMatlabTableNames(rawNames);
                if double(IO.groupmode) == 4 && ~NMDataIOTableReadTools.isUnknown(out.sheet)
                    out.selectedSheets = {char(out.sheet)};
                    out.headerRows = out.headerRow;
                end
                out.nColumns = numel(out.columns);
                out.ok = out.nColumns > 0;
                if out.ok
                    out.message = sprintf('Detected %g table header column(s) from row %g.', out.nColumns, out.headerRow);
                else
                    out.message = 'No table columns detected.';
                end
            catch ME
                out.ok = false;
                out.message = ME.message;
                out.identifier = ME.identifier;
            end
        end

        function out = probeTableFileSources(IO, opts, out)
            % probeTableFileSources  Enumerate table objects and read headers only for included objects.
            doProfile = NMDataIOProfileTools.enabled([], [], opts);
            tTotal = tic;
            performance = struct('schemaVersion',2,'totalSeconds',0,'sourceListSeconds',0, ...
                'fileCount',0,'sheetCount',0,'sourceVariableBuildSeconds',0, ...
                'ooxmlPackageReads',0,'ooxmlSharedStringsParses',0,'ooxmlSheetsRead',0, ...
                'ooxmlWorksheetCharacters',0,'ooxmlWorksheetEntryBytes',0, ...
                'sourceFingerprintSeconds',0,'sourceFingerprintReads',0,'ooxmlHeaderPreparationSeconds',0, ...
                'initialMetadataBuildSeconds',0,'residualSeconds',0, ...
                'sheetEnumeration',repmat(struct('file','','seconds',0,'cacheHit',false,'method','','nSheets',0),0,1), ...
                'sheetHeaders',repmat(struct('file','','sheet','','seconds',0,'cacheHit',false, ...
                    'widthSeconds',0,'widthCacheHit',false,'headerReadSeconds',0,'detectHeaderSeconds',0, ...
                    'nameNormalizationSeconds',0,'nColumns',0),0,1));
            tSourceList = tic;
            files = NMDataIOTableReadTools.tableSourceFiles(IO);
            performance.sourceListSeconds = toc(tSourceList);
            performance.fileCount = double(numel(files));
            if isempty(files)
                performance.totalSeconds = toc(tTotal); out.performance = performance;
                out.ok = false; out.message = 'No table file/source has been selected.'; return;
            end
            requested = NMDataIOTableReadTools.sheetList(NMDataIOTableReadTools.fieldOr(IO,'sheets',{}));
            maxRows = NMDataIOTableReadTools.opt(opts,'MaxRows',30);
            requestedHeaderRow = NMDataIOTableReadTools.headerRow(IO, []);
            headerReadRows = maxRows;
            if ~isempty(requestedHeaderRow), headerReadRows = max(headerReadRows,requestedHeaderRow); end
            allObjects = {}; objectSpecs = struct('token',{},'file',{},'object',{},'groupmode',{},'fingerprint',{});
            for f = 1:numel(files)
                file = files{f};
                tFingerprint = tic;
                fileInfo = dir(file);
                performance.sourceFingerprintSeconds = performance.sourceFingerprintSeconds + toc(tFingerprint);
                performance.sourceFingerprintReads = performance.sourceFingerprintReads + 1;
                if isempty(fileInfo) || logical(fileInfo(1).isdir)
                    error('NMDataIOTableReadTools:tableSourceNotFound','Table source does not exist: %s',file);
                end
                fingerprint = NMDataIOTableReadTools.spreadsheetMetadataFingerprint(file,fileInfo(1));
                gm = NMDataIOTableReadTools.tableFileGroupmode(file);
                if gm == 4
                    requestedNames = {};
                    prefix = [file '::'];
                    for ri = 1:numel(requested)
                        item = requested{ri};
                        if strncmp(item,prefix,numel(prefix))
                            requestedNames{end+1} = item(numel(prefix)+1:end); %#ok<AGROW>
                        elseif numel(files)==1 && ~contains(item,'::')
                            requestedNames{end+1} = item; %#ok<AGROW>
                        end
                    end
                    requestedNames = unique(requestedNames,'stable');
                    if NMDataIOOOXMLMetadataTools.isSupported(file)
                        sheetKey = NMDataIOTableReadTools.spreadsheetMetadataKey(file,'sheets','','',fingerprint);
                        [sheetHit,sh] = NMDataIOTableReadTools.spreadsheetMetadataCache('get',sheetKey);
                        namesToRead = requestedNames;
                        if sheetHit && ~isempty(namesToRead)
                            missingMetadata = false(size(namesToRead));
                            extra = sprintf('maxRows=%g|headerRow=%s',double(maxRows),NMDataIOTableReadTools.cacheValue(requestedHeaderRow));
                            for mi = 1:numel(namesToRead)
                                metaKey = NMDataIOTableReadTools.spreadsheetMetadataKey(file,'header',namesToRead{mi},extra,fingerprint);
                                [metaHit,~] = NMDataIOTableReadTools.spreadsheetMetadataCache('get',metaKey);
                                missingMetadata(mi) = ~metaHit;
                            end
                            namesToRead = namesToRead(missingMetadata);
                        end
                        ooxmlPerf = [];
                        rawToRead = {};
                        if ~sheetHit
                            if isempty(namesToRead)
                                [index,ooxmlPerf] = NMDataIOOOXMLMetadataTools.workbookIndex(file);
                            else
                                [index,rawToRead,ooxmlPerf] = NMDataIOOOXMLMetadataTools.workbookHeaders(file,headerReadRows,namesToRead);
                            end
                            sh = {index.name};
                            NMDataIOTableReadTools.spreadsheetMetadataCache('set',sheetKey,sh);
                            indexKey = NMDataIOTableReadTools.spreadsheetMetadataKey(file,'ooxmlWorkbook','','',fingerprint);
                            NMDataIOTableReadTools.spreadsheetMetadataCache('set',indexKey,index);
                        elseif ~isempty(namesToRead)
                            [index,rawToRead,ooxmlPerf] = NMDataIOOOXMLMetadataTools.workbookHeaders(file,headerReadRows,namesToRead);
                            indexKey = NMDataIOTableReadTools.spreadsheetMetadataKey(file,'ooxmlWorkbook','','',fingerprint);
                            NMDataIOTableReadTools.spreadsheetMetadataCache('set',indexKey,index);
                        end
                        if ~isempty(requestedNames)
                            missingRequested = requestedNames(~ismember(requestedNames,sh));
                            if ~isempty(missingRequested)
                                error('NMDataIOTableReadTools:unknownTableObject','Selected worksheet object(s) not found in %s: %s',file,strjoin(missingRequested,', '));
                            end
                        end
                        packageIndexSeconds = 0;
                        if ~isempty(ooxmlPerf)
                            performance.ooxmlPackageReads = performance.ooxmlPackageReads + double(ooxmlPerf.packageOpens);
                            performance.ooxmlSharedStringsParses = performance.ooxmlSharedStringsParses + double(ooxmlPerf.sharedStringsParses);
                            performance.ooxmlSheetsRead = performance.ooxmlSheetsRead + double(ooxmlPerf.nSheetsRead);
                            performance.ooxmlWorksheetCharacters = performance.ooxmlWorksheetCharacters + sum(double(ooxmlPerf.worksheetCharacters));
                            finiteEntryBytes = double(ooxmlPerf.worksheetEntryBytes); finiteEntryBytes = finiteEntryBytes(isfinite(finiteEntryBytes));
                            performance.ooxmlWorksheetEntryBytes = performance.ooxmlWorksheetEntryBytes + sum(finiteEntryBytes);
                            performance.ooxmlHeaderPreparationSeconds = performance.ooxmlHeaderPreparationSeconds + ...
                                sum(double(ooxmlPerf.worksheetSeconds)) + double(ooxmlPerf.sharedStringsSeconds) + ...
                                double(ooxmlPerf.packageCloseSeconds) + double(ooxmlPerf.overheadSeconds);
                            packageIndexSeconds = double(ooxmlPerf.packageOpenSeconds) + double(ooxmlPerf.indexSeconds);
                            NMDataIOProfileTools.log(doProfile, ...
                                ['  ooxml package %g/%g total=%.3fs open=%.3fs index=%.3fs worksheets=%.3fs ', ...
                                 'shared=%.3fs close=%.3fs overhead=%.3fs bounded-chars=%g entry-bytes=%g'], ...
                                f,numel(files),double(ooxmlPerf.seconds),double(ooxmlPerf.packageOpenSeconds),double(ooxmlPerf.indexSeconds), ...
                                sum(double(ooxmlPerf.worksheetSeconds)),double(ooxmlPerf.sharedStringsSeconds),double(ooxmlPerf.packageCloseSeconds), ...
                                double(ooxmlPerf.overheadSeconds),sum(double(ooxmlPerf.worksheetCharacters)),sum(finiteEntryBytes));
                        end
                        if ~isempty(namesToRead)
                            sharedShare = 0;
                            if ~isempty(ooxmlPerf), sharedShare = double(ooxmlPerf.sharedStringsSeconds) / max(1,numel(namesToRead)); end
                            tInitialMetadata = tic;
                            for j = 1:numel(namesToRead)
                                localIO = IO; localIO.M_edit = file; localIO.groupmode = 4;
                                readPerf = struct('widthSeconds',0,'widthCacheHit',false,'headerReadSeconds',sharedShare);
                                if ~isempty(ooxmlPerf), readPerf.headerReadSeconds = double(ooxmlPerf.worksheetSeconds(j)) + sharedShare; end
                                NMDataIOTableReadTools.spreadsheetMetaFromRaw( ...
                                    localIO,namesToRead{j},rawToRead{j},maxRows,requestedHeaderRow,readPerf,fingerprint);
                            end
                            initialMetadataSeconds = toc(tInitialMetadata);
                            performance.initialMetadataBuildSeconds = performance.initialMetadataBuildSeconds + initialMetadataSeconds;
                            NMDataIOProfileTools.log(doProfile, ...
                                '  table-header workbook %g/%g initial metadata build: %.3fs (selected sheets=%g)', ...
                                f,numel(files),double(initialMetadataSeconds),numel(namesToRead));
                        end
                        sheetMethod='cache'; if ~isempty(ooxmlPerf), sheetMethod='ooxml'; end
                        sheetPerf = struct('seconds',packageIndexSeconds,'cacheHit',logical(sheetHit),'method',sheetMethod);
                    else
                        [sh, sheetPerf] = NMDataIOTableReadTools.spreadsheetSheets(file);
                    end
                    performance.sheetCount = performance.sheetCount + double(numel(sh));
                    performance.sheetEnumeration(end+1,1) = struct('file',file,'seconds',double(sheetPerf.seconds), ...
                        'cacheHit',logical(sheetPerf.cacheHit),'method',char(sheetPerf.method),'nSheets',double(numel(sh))); %#ok<AGROW>
                    NMDataIOProfileTools.log(doProfile, 'table-header workbook %g/%g sheet enumeration: %.3fs (%s, cache=%d, sheets=%g) %s', ...
                        f, numel(files), double(sheetPerf.seconds), char(sheetPerf.method), logical(sheetPerf.cacheHit), numel(sh), file);
                    for j = 1:numel(sh)
                        token = NMDataIOTableReadTools.tableObjectToken(file, sh{j});
                        objectSpecs(end+1) = struct('token',token,'file',file,'object',sh{j},'groupmode',4,'fingerprint',fingerprint); %#ok<AGROW>
                        allObjects{end+1} = token; %#ok<AGROW>
                    end
                else
                    token = NMDataIOTableReadTools.tableObjectToken(file,'');
                    objectSpecs(end+1) = struct('token',token,'file',file,'object','','groupmode',3,'fingerprint',fingerprint); %#ok<AGROW>
                    allObjects{end+1} = token; %#ok<AGROW>
                end
            end
            selected = requested;
            if numel(files)==1 && NMDataIOTableReadTools.tableFileGroupmode(files{1})==4
                for i=1:numel(selected)
                    if ~ismember(selected{i},allObjects)
                        candidate=NMDataIOTableReadTools.tableObjectToken(files{1},selected{i});
                        if ismember(candidate,allObjects), selected{i}=candidate; end
                    end
                end
            end
            missing = selected(~ismember(selected,allObjects));
            if ~isempty(missing)
                error('NMDataIOTableReadTools:unknownTableObject','Selected table object(s) not found: %s',strjoin(missing,', '));
            end
            selected = unique(selected,'stable');
            vars = out.sourceVariables; previewRows=0; headerRows=[];
            for oi=1:numel(objectSpecs)
                spec=objectSpecs(oi);
                if ~ismember(spec.token,selected), continue; end
                localIO=IO; localIO.M_edit=spec.file; localIO.groupmode=spec.groupmode; localIO.sourceType='tablefile'; localIO.sheets={}; localIO.sheet='?';
                localIO.delimit=NMDataIOTableReadTools.tableFileDelimiter(spec.file,NMDataIOTableReadTools.fieldOr(IO,'delimit','tab'));
                requestedHeaderRow = NMDataIOTableReadTools.headerRow(IO, []);
                if spec.groupmode==4
                    localIO.sheet=spec.object; localIO.sheets={spec.object};
                    tSheetHeader = tic;
                    meta=NMDataIOTableReadTools.probeSpreadsheetSheet(localIO,spec.object,maxRows,requestedHeaderRow,spec.fingerprint);
                    sheetHeaderSeconds = toc(tSheetHeader);
                    mp = NMDataIOTableReadTools.fieldOr(meta,'performance',struct());
                    performance.sheetHeaders(end+1,1) = struct('file',spec.file,'sheet',spec.object, ...
                        'seconds',double(sheetHeaderSeconds),'cacheHit',logical(NMDataIOTableReadTools.fieldOr(mp,'cacheHit',false)), ...
                        'widthSeconds',double(NMDataIOTableReadTools.fieldOr(mp,'widthSeconds',0)), ...
                        'widthCacheHit',logical(NMDataIOTableReadTools.fieldOr(mp,'widthCacheHit',false)), ...
                        'headerReadSeconds',double(NMDataIOTableReadTools.fieldOr(mp,'headerReadSeconds',0)), ...
                        'detectHeaderSeconds',double(NMDataIOTableReadTools.fieldOr(mp,'detectHeaderSeconds',0)), ...
                        'nameNormalizationSeconds',double(NMDataIOTableReadTools.fieldOr(mp,'nameNormalizationSeconds',0)), ...
                        'nColumns',double(numel(meta.rawNames))); %#ok<AGROW>
                    NMDataIOProfileTools.log(doProfile, ...
                        'table-header selected sheet %g: %.3fs (cache=%d, read=%.3fs, detect=%.3fs, names=%.3fs, cols=%g) %s :: %s', ...
                        numel(performance.sheetHeaders),double(sheetHeaderSeconds),logical(NMDataIOTableReadTools.fieldOr(mp,'cacheHit',false)), ...
                        double(NMDataIOTableReadTools.fieldOr(mp,'headerReadSeconds',0)),double(NMDataIOTableReadTools.fieldOr(mp,'detectHeaderSeconds',0)), ...
                        double(NMDataIOTableReadTools.fieldOr(mp,'nameNormalizationSeconds',0)),numel(meta.rawNames),spec.file,spec.object);
                    localIO.headerRow=meta.headerRow; localIO.headerAutoDetect=false;
                    names=meta.rawNames; nRows=NaN;
                    previewRows=max(previewRows,meta.nPreviewRows); headerRows(end+1)=localIO.headerRow; %#ok<AGROW>
                else
                    raw=NMDataIOTableReadTools.readDelimitedTopRows(spec.file,localIO.delimit,maxRows);
                    hr=requestedHeaderRow;
                    if isempty(hr), [hr,~]=NMDataIOTableReadTools.detectHeaderRow(raw); end
                    if isempty(hr), hr=1; end
                    localIO.headerRow=hr; localIO.headerAutoDetect=false;
                    T=NMDataIOTableReadTools.readTableFromIO(localIO);
                    [~,fileName,ext]=fileparts(spec.file); objectLabel=[fileName ext];
                    filterRef=struct('sourceType','tablefile','sourcePath',spec.file,'sourceObject',spec.object,'sourceName','', 'sourceLabel',objectLabel);
                    [T,~,filterReport]=NMDataIOTableReadTools.applySourceObjectFilter(IO,T,filterRef);
                    names=NMDataIOTableReadTools.originalColumnNames(T); nRows=height(T);
                    if filterReport.applied
                        out.diagnostics{end+1,1}=sprintf('Applied row filter to %s: %g -> %g row(s).',objectLabel,filterReport.nInput,filterReport.nOutput); %#ok<AGROW>
                    end
                    previewRows=max(previewRows,min(nRows,maxRows)); headerRows(end+1)=localIO.headerRow; %#ok<AGROW>
                end
                [~,fileName,ext]=fileparts(spec.file); objectLabel=[fileName ext]; if ~isempty(spec.object), objectLabel=[objectLabel ' :: ' spec.object]; end
                tVarBuild = tic;
                for c=1:numel(names)
                    nm=names{c}; id=['tablefile|' spec.file '|' spec.object '|' nm];
                    if spec.groupmode==4, cls=''; sz=[]; else, col=T{:,c}; cls=class(col); sz=[nRows 1]; end
                    vars(end+1)=struct('id',id,'name',nm,'sourceType','tablefile','sourcePath',spec.file,'sourceObject',spec.object,'sourceName','', ... %#ok<AGROW>
                        'sourceLabel',objectLabel,'columnName',nm,'class',cls,'size',sz,'headerRow',localIO.headerRow, ...
                        'delimit',char(string(localIO.delimit)),'groupmode',spec.groupmode);
                end
                performance.sourceVariableBuildSeconds = performance.sourceVariableBuildSeconds + toc(tVarBuild);
            end
            out.sheets=allObjects; out.selectedSheets=selected; if isempty(selected), out.sheet='?'; else, out.sheet=selected{1}; end
            out.headerRows=headerRows; if numel(headerRows)==1, out.headerRow=headerRows(1); else, out.headerRow=[]; end
            out.headerRowAutoDetected=isempty(NMDataIOTableReadTools.headerRow(IO, [])); out.nPreviewRows=previewRows;
            out.sourceVariables=vars; out.nColumns=numel(vars);
            out.columns={vars.name}; out.rawColumns=out.columns; out.internalColumns=out.columns; out.columnSources={vars.sourceLabel};
            performance.totalSeconds = toc(tTotal);
            accountedSeconds = double(performance.sourceListSeconds) + double(performance.sourceFingerprintSeconds) + ...
                sum([performance.sheetEnumeration.seconds]) + double(performance.ooxmlHeaderPreparationSeconds) + ...
                double(performance.initialMetadataBuildSeconds) + sum([performance.sheetHeaders.seconds]) + ...
                double(performance.sourceVariableBuildSeconds);
            performance.residualSeconds = max(0,double(performance.totalSeconds)-accountedSeconds);
            out.performance = performance;
            NMDataIOProfileTools.log(doProfile, ...
                ['table-header inventory TOTAL: %.3fs (files=%g, sheets=%g, selected=%g, source-list=%.3fs, fingerprints=%.3fs, ', ...
                 'sheet-enumeration=%.3fs, ooxml-header-prep=%.3fs, initial-metadata=%.3fs, sheet-headers=%.3fs, ', ...
                 'source-variable-build=%.3fs, residual=%.3fs)'], ...
                double(performance.totalSeconds), double(performance.fileCount), double(performance.sheetCount), numel(selected), ...
                double(performance.sourceListSeconds), double(performance.sourceFingerprintSeconds), ...
                sum([performance.sheetEnumeration.seconds]), double(performance.ooxmlHeaderPreparationSeconds), ...
                double(performance.initialMetadataBuildSeconds), sum([performance.sheetHeaders.seconds]), ...
                double(performance.sourceVariableBuildSeconds), double(performance.residualSeconds));
            out.ok=~isempty(allObjects); out.message=sprintf('Detected %g table object(s) from %g file(s); %g object(s) included with %g available column(s).',numel(allObjects),numel(files),numel(selected),numel(vars));
        end

        function out = probeTableVariableSources(IO, opts, out)
            % probeTableVariableSources  Discover selected MATLAB table variables as independent tabular source objects.
            names = NMDataIOTableReadTools.fieldOr(IO,'tableVariables',{});
            if ischar(names) || isstring(names), names = cellstr(string(names(:))); end
            if isempty(names)
                one = NMDataIOTableReadTools.fieldOr(IO,'tableVariable','?');
                if ~NMDataIOTableReadTools.isUnknown(one), names = {char(string(one))}; end
            end
            names = cellfun(@(x) strtrim(char(string(x))),names(:)','UniformOutput',false);
            names = unique(names(~cellfun(@isempty,names)),'stable');
            if isempty(names), out.ok=false; out.message='No MATLAB table variable has been selected.'; return; end
            requested = NMDataIOTableReadTools.sheetList(NMDataIOTableReadTools.fieldOr(IO,'sheets',{}));
            selected = requested;
            missing = selected(~ismember(selected,names));
            if ~isempty(missing), error('NMDataIOTableReadTools:unknownTableObject','Selected MATLAB table object(s) not found: %s',strjoin(missing,', ')); end
            varRecords = cell(0,1); selectedVarIdx=[]; previewRows=0;
            for oi=1:numel(names)
                tableName=names{oi}; isSelected=ismember(tableName,selected);
                if ~isSelected, continue; end
                T=NMWorkspaceTools.resolve(tableName,'base');
                if ~istable(T), error('NMDataIOTableReadTools:notTableVariable','Workspace variable ''%s'' is not a MATLAB table.',tableName); end
                filterRef=struct('sourceType','tablevar','sourcePath','','sourceObject','','sourceName',tableName,'sourceLabel',tableName);
                [T,~,filterReport]=NMDataIOTableReadTools.applySourceObjectFilter(IO,T,filterRef);
                columns=NMDataIOTableReadTools.originalColumnNames(T); nRows=height(T);
                if filterReport.applied, out.diagnostics{end+1,1}=sprintf('Applied row filter to %s: %g -> %g row(s).',tableName,filterReport.nInput,filterReport.nOutput); end %#ok<AGROW>
                if isSelected, previewRows=max(previewRows,min(nRows,NMDataIOTableReadTools.opt(opts,'MaxRows',30))); end
                firstVar=numel(varRecords)+1;
                for c=1:numel(columns)
                    nm=columns{c}; col=T{:,c};
                    varRecords{end+1,1}=struct('id',['tablevar|' tableName '|' nm],'name',nm,'sourceType','tablevar','sourcePath','','sourceObject','','sourceName',tableName, ... %#ok<AGROW>
                        'sourceLabel',tableName,'columnName',nm,'class',class(col),'size',[nRows 1],'headerRow',[], ...
                        'delimit','','groupmode',5);
                end
                selectedVarIdx=[selectedVarIdx firstVar:numel(varRecords)]; %#ok<AGROW>
            end
            if isempty(varRecords), vars=out.sourceVariables; else, vars=vertcat(varRecords{:}); end
            out.sheets=names; out.selectedSheets=selected; if isempty(selected), out.sheet='?'; else, out.sheet=selected{1}; end
            out.headerRow=[]; out.headerRows=[]; out.headerRowAutoDetected=false; out.nPreviewRows=previewRows;
            out.sourceVariables=vars; selectedVars=vars(selectedVarIdx); out.nColumns=numel(selectedVars);
            out.columns={selectedVars.name}; out.rawColumns=out.columns; out.internalColumns=out.columns; out.columnSources={selectedVars.sourceLabel};
            if isempty(selectedVars), out.commonColumns={}; else
                common=unique({selectedVars(strcmp({selectedVars.sourceLabel},selected{1})).name},'stable');
                for i=2:numel(selected), local={selectedVars(strcmp({selectedVars.sourceLabel},selected{i})).name}; common=common(ismember(common,local)); end
                out.commonColumns=common;
            end
            out.ok=~isempty(names); out.message=sprintf('Detected %g MATLAB table object(s); %g object(s) included with %g available column source(s).',numel(names),numel(selected),numel(vars));
        end

        function sourceObjects = materializeSourceObjects(IO, refs, progressTask)
            % materializeSourceObjects  Read/filter each selected tabular source object once for one materialization.
            %
            % The returned bundle is transient and local to the current materialization. It
            % is not a cache authority: source identity and scientific invalidation remain
            % owned by the persisted DataIO state/materialization cache.
            if nargin < 2 || isempty(refs), refs = {}; end
            if nargin < 3 || isempty(progressTask), progressTask = NMProgressTools.emptyTaskForLocalUse(); end
            doProfile = NMDataIOProfileTools.enabled([], [], struct());
            refs = NMDataIOStateTools.roleRefCell(refs);
            sourceObjects = struct('sourceIdentity',{},'table',{},'sourceRows',{}, ...
                'filterReport',{},'objectLabel',{},'readIO',{});
            sourceIdentities = {};
            sourceRefs = {};
            for i = 1:numel(refs)
                ref = refs{i};
                st = lower(char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceType',''))));
                if ~(ismember(st,{'tablefile','tablevar'}) || strcmp(st,'database')), continue; end
                identity = NMDataIOStateTools.variableRefSourceIdentity(ref, IO);
                if ~any(strcmp(sourceIdentities,identity))
                    sourceIdentities{end+1,1} = identity; %#ok<AGROW>
                    sourceRefs{end+1,1} = ref; %#ok<AGROW>
                end
            end
            nObjects = numel(sourceRefs);
            if nObjects < 1, return; end
            progressTask = NMProgressTools.phase(progressTask, 'tabular_source_objects', 1, 45, ...
                sprintf('Reading selected table 1 of %g.',nObjects));
            for i = 1:nObjects
                ref = sourceRefs{i};
                label = char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceLabel',sourceIdentities{i})));
                progressTask = NMProgressTools.step(progressTask, i-1, nObjects, ...
                    sprintf('Reading table %g of %g: %s',i,nObjects,label), true);
                NMDataIOTableReadTools.yieldProgressPoller();
                tRead = tic;
                [T, sourceRows, filterReport, objectLabel, readIO] = NMDataIOTableReadTools.readSourceObject(IO, ref);
                readSeconds = toc(tRead);
                NMDataIOProfileTools.log(doProfile, 'tabular source object %g/%g read: %.3fs (rows=%g, cols=%g) %s', ...
                    i, nObjects, readSeconds, height(T), width(T), label);
                sourceObjects(end+1,1) = struct('sourceIdentity',sourceIdentities{i},'table',T, ... %#ok<AGROW>
                    'sourceRows',sourceRows,'filterReport',filterReport,'objectLabel',objectLabel,'readIO',readIO);
                progressTask = NMProgressTools.step(progressTask, i, nObjects, ...
                    sprintf('Read table %g of %g in %.1f s: %s',i,nObjects,readSeconds,label), true);
                NMDataIOTableReadTools.yieldProgressPoller();
            end
        end

        function yieldProgressPoller()
            % yieldProgressPoller  Let the browser-side progress poller observe a forced source-read update without executing UI callbacks.
            drawnow limitrate nocallbacks
        end

        function [values, sourceRows, filterReports] = readSourceRefsProjected(IO, refs)
            % readSourceRefsProjected  Read selected canonical tabular columns once per source object for lightweight probes.
            refs = NMDataIOStateTools.roleRefCell(refs);
            nRefs = numel(refs);
            values = cell(nRefs,1); sourceRows = cell(nRefs,1); filterReports = cell(nRefs,1);
            if nRefs < 1, return; end
            identities = cell(nRefs,1);
            for i = 1:nRefs
                st = lower(char(string(NMDataIOTableReadTools.fieldOr(refs{i},'sourceType',''))));
                if ~ismember(st, {'tablefile','tablevar','database'})
                    error('NMDataIOTableReadTools:projectedSourceType', ...
                        'Selective tabular projection is not defined for source type ''%s''.', st);
                end
                identities{i} = NMDataIOStateTools.variableRefSourceIdentity(refs{i}, IO);
            end
            done = false(nRefs,1);
            for i = 1:nRefs
                if done(i), continue; end
                idx = find(strcmp(identities, identities{i}));
                columns = cellfun(@(r) char(string(NMDataIOTableReadTools.fieldOr(r,'columnName', ...
                    NMDataIOTableReadTools.fieldOr(r,'name','')))), refs(idx), 'UniformOutput', false);
                if any(cellfun(@isempty,columns))
                    error('NMDataIOTableReadTools:sourceRefColumn', 'Projected source references require explicit column names.');
                end
                [T, rows, report, objectLabel, localIO] = NMDataIOTableReadTools.readSourceObject(IO, refs{i}, columns);
                names = NMDataIOTableReadTools.originalColumnNames(T);
                for j = 1:numel(idx)
                    k = idx(j); colName = columns{j};
                    hit = find(strcmp(names,colName));
                    if numel(hit) ~= 1
                        sourcePath = char(string(NMDataIOTableReadTools.fieldOr(refs{k},'sourcePath','')));
                        sourceObject = char(string(NMDataIOTableReadTools.fieldOr(refs{k},'sourceObject','')));
                        resolvedDelimiter = char(string(NMDataIOTableReadTools.fieldOr(localIO,'delimit','')));
                        resolvedGroupmode = double(NMDataIOTableReadTools.fieldOr(localIO,'groupmode',NaN));
                        resolvedHeaderRow = double(NMDataIOTableReadTools.headerRow(localIO,NaN));
                        error('NMDataIOTableReadTools:sourceRefColumn', ...
                            ['Column ''%s'' must occur exactly once. Matches=%d. Source=%s. ', ...
                             'Path="%s"; object="%s"; groupmode=%g; headerRow=%g; delimiter="%s".'], ...
                            colName,numel(hit),objectLabel,sourcePath,sourceObject,resolvedGroupmode, ...
                            resolvedHeaderRow,resolvedDelimiter);
                    end
                    values{k} = T{:,hit}; sourceRows{k} = rows; filterReports{k} = report;
                end
                done(idx) = true;
            end
        end

        function [value, sourceRows, filterReport] = readSourceRef(IO, ref, sourceObjects)
            % readSourceRef  Materialize one canonical tabular column after the generic source-object row filter.
            if nargin < 3, sourceObjects = struct([]); end
            st=lower(char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceType',''))));
            colName=char(string(NMDataIOTableReadTools.fieldOr(ref,'columnName',NMDataIOTableReadTools.fieldOr(ref,'name',''))));
            localIO = struct();
            if ~isempty(sourceObjects) && (ismember(st,{'tablefile','tablevar'}) || strcmp(st,'database'))
                identity = NMDataIOStateTools.variableRefSourceIdentity(ref, IO);
                idx = find(strcmp({sourceObjects.sourceIdentity},identity));
                if numel(idx) ~= 1
                    error('NMDataIOTableReadTools:sourceObjectBundleMissing', ...
                        'The current materialization did not retain exactly one source object for %s.', identity);
                end
                record = sourceObjects(idx);
                T = record.table;
                sourceRows = record.sourceRows;
                filterReport = record.filterReport;
                objectLabel = record.objectLabel;
                localIO = record.readIO;
            else
                [T, sourceRows, filterReport, objectLabel, localIO] = NMDataIOTableReadTools.readSourceObject(IO, ref);
            end
            names=NMDataIOTableReadTools.originalColumnNames(T);
            hit=find(strcmp(names,colName));
            if numel(hit)~=1
                internalNames=T.Properties.VariableNames(:)';
                parsedNames=strjoin(names,', ');
                internalText=strjoin(internalNames,', ');
                sourcePath=char(string(NMDataIOTableReadTools.fieldOr(ref,'sourcePath','')));
                sourceObject=char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceObject','')));
                resolvedDelimiter=char(string(NMDataIOTableReadTools.fieldOr(localIO,'delimit','')));
                resolvedGroupmode=double(NMDataIOTableReadTools.fieldOr(localIO,'groupmode',NaN));
                resolvedHeaderRow=double(NMDataIOTableReadTools.headerRow(localIO,NaN));
                error('NMDataIOTableReadTools:sourceRefColumn', ...
                    ['Column ''%s'' must occur exactly once. Matches=%d. Source=%s. ', ...
                     'Path="%s"; object="%s"; groupmode=%g; headerRow=%g; delimiter="%s"; ', ...
                     'parsed columns=[%s]; internal columns=[%s].'], ...
                    colName,numel(hit),objectLabel,sourcePath,sourceObject,resolvedGroupmode, ...
                    resolvedHeaderRow,resolvedDelimiter,parsedNames,internalText);
            end
            value=T{:,hit};
        end

        function [T, sourceRows, filterReport, objectLabel, localIO] = readSourceObject(IO, ref, projectedColumns)
            % readSourceObject  Read and filter one canonical tabular provenance object.
            if nargin < 3, projectedColumns = {}; end
            projectedColumns = NMDataIOTableReadTools.sourceProjectionForRef(IO, ref, projectedColumns);
            st=lower(char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceType',''))));
            localIO = struct();
            if strcmp(st,'tablevar')
                tableName=char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceName','')));
                if isempty(tableName), error('NMDataIOTableReadTools:sourceRefName','MATLAB-table source reference has no source table name.'); end
                T=NMWorkspaceTools.resolve(tableName,'base');
                if ~istable(T), error('NMDataIOTableReadTools:notTableVariable','Workspace variable ''%s'' is not a MATLAB table.',tableName); end
                objectLabel=tableName;
                if ~isempty(projectedColumns), T=NMDataIOTableReadTools.projectTableColumns(T,projectedColumns,objectLabel); end
            elseif strcmp(st,'database')
                objectName=char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceObject','')));
                if isempty(objectName), error('NMDataIOTableReadTools:sourceRefObject','Database source reference has no table/view object.'); end
                localIO=IO; localIO.sourceType='database'; localIO.groupmode=6;
                if strcmp(objectName,'__custom_query__')
                    if ~logical(NMDataIOTableReadTools.fieldOr(IO,'databaseUseQuery',false))
                        error('NMDataIOTableReadTools:staleDatabaseQueryRef','Custom-query source reference is stale because expert SQL mode is not active.');
                    end
                    if ~isempty(projectedColumns), localIO.sourceProjectionColumns=projectedColumns; end
                else
                    localIO.databaseUseQuery=false;
                    localIO.databaseTable=objectName;
                    if isempty(projectedColumns)
                        localIO.databaseSelectedColumns=NMDataIOTableReadTools.databaseRequiredColumns(IO,ref);
                    else
                        localIO.databaseSelectedColumns=projectedColumns;
                        localIO.sourceProjectionColumns=projectedColumns;
                    end
                end
                T=NMDataIOTableReadTools.readTableFromIO(localIO);
                objectLabel=char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceLabel',objectName)));
            else
                if ~isstruct(ref) || ~isfield(ref,'sourcePath') || isempty(ref.sourcePath)
                    error('NMDataIOTableReadTools:sourceRefPath','Table-file source reference has no source path.');
                end
                localIO=IO; localIO.sourceType='tablefile'; localIO.M_edit=char(string(ref.sourcePath));
                localIO.groupmode=double(NMDataIOTableReadTools.fieldOr(ref,'groupmode',NMDataIOTableReadTools.tableFileGroupmode(localIO.M_edit)));
                localIO.headerRow=NMDataIOTableReadTools.fieldOr(ref,'headerRow',1); localIO.headerAutoDetect=false;
                localIO.delimit=NMDataIOTableReadTools.fieldOr(ref,'delimit',NMDataIOTableReadTools.tableFileDelimiter(localIO.M_edit,NMDataIOTableReadTools.fieldOr(IO,'delimit','tab')));
                if localIO.groupmode==4
                    obj=char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceObject','')));
                    if isempty(obj), error('NMDataIOTableReadTools:sourceRefObject','Spreadsheet source reference has no worksheet object.'); end
                    localIO.sheet=obj; localIO.sheets={obj};
                end
                if ~isempty(projectedColumns), localIO.sourceProjectionColumns=projectedColumns; end
                T=NMDataIOTableReadTools.readTableFromIO(localIO);
                objectLabel=NMDataIOTableReadTools.tableObjectToken(localIO.M_edit,NMDataIOTableReadTools.fieldOr(ref,'sourceObject',''));
            end
            [T, sourceRows, filterReport] = NMDataIOTableReadTools.applySourceObjectFilter(IO, T, ref);
        end

        function columns = sourceProjectionForRef(IO, ref, columns)
            % sourceProjectionForRef  Add only row-filter columns required to preserve projected-source row semantics.
            columns = cellstr(string(columns)); columns = columns(:)';
            columns = columns(~cellfun(@isempty,columns));
            if isempty(columns), return; end
            spec = NMDataIOTableReadTools.filterForSourceRef(IO, ref);
            if ~isempty(spec)
                rules = NMDataIOTableReadTools.filterRules(spec);
                for i = 1:numel(rules)
                    name = char(string(NMDataIOTableReadTools.fieldOr(rules(i),'column','')));
                    if ~isempty(name), columns{end+1} = name; end %#ok<AGROW>
                end
            end
            columns = unique(columns,'stable');
        end

        function columns = sourceProjectionColumns(IO)
            % sourceProjectionColumns  Normalize an optional lightweight source-column projection.
            columns = NMDataIOTableReadTools.fieldOr(IO,'sourceProjectionColumns',{});
            if ischar(columns) || isstring(columns), columns = cellstr(string(columns)); end
            if ~iscell(columns), columns = {}; return; end
            columns = cellfun(@(x) strtrim(char(string(x))), columns(:)', 'UniformOutput', false);
            columns = columns(~cellfun(@isempty,columns));
            columns = unique(columns,'stable');
        end

        function T = projectTableColumns(T, columns, context)
            % projectTableColumns  Project a MATLAB table by exact original column names without changing source naming semantics.
            if nargin < 3 || isempty(context), context = 'table source'; end
            columns = cellstr(string(columns)); columns = columns(:)';
            if isempty(columns), return; end
            names = NMDataIOTableReadTools.originalColumnNames(T);
            hits = zeros(1,numel(columns));
            for i = 1:numel(columns)
                idx = find(strcmp(names,columns{i}));
                if numel(idx) ~= 1
                    error('NMDataIOTableReadTools:sourceRefColumn', ...
                        'Column ''%s'' must occur exactly once in %s. Matches=%d.', columns{i}, char(context), numel(idx));
                end
                hits(i) = idx;
            end
            T = T(:,hits);
            T = NMDataIOTableReadTools.attachOriginalColumnNames(T, columns);
        end

        function [T, sourceRows, report] = applySourceObjectFilter(IO, T, ref)
            % applySourceObjectFilter  Apply one persisted tabular source-object filter before key/role materialisation.
            sourceRows = (1:height(T))';
            sourceLabel = char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceLabel','')));
            if isempty(sourceLabel)
                sourceLabel = NMDataIOTableReadTools.tableObjectToken( ...
                    NMDataIOTableReadTools.fieldOr(ref,'sourcePath',''), NMDataIOTableReadTools.fieldOr(ref,'sourceObject',''));
            end
            report = struct('schemaVersion',1,'applied',false,'sourceType',char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceType',''))), ...
                'sourcePath',char(string(NMDataIOTableReadTools.fieldOr(ref,'sourcePath',''))), ...
                'sourceObject',char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceObject',''))), ...
                'sourceName',char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceName',''))), ...
                'sourceLabel',sourceLabel,'nInput',height(T),'nOutput',height(T),'match','all','caseSensitive',false,'rules',struct([]));
            spec = NMDataIOTableReadTools.filterForSourceRef(IO, ref);
            if isempty(spec), return; end
            [T, sourceRows, ruleReport] = NMDataIOTableReadTools.applyTabularRowFilter(T, spec, sourceLabel);
            report.applied = true;
            report.nOutput = height(T);
            report.match = ruleReport.match;
            report.caseSensitive = ruleReport.caseSensitive;
            report.rules = ruleReport.rules;
        end

        function [T, sourceRows, report] = applyTabularRowFilter(T, spec, sourceLabel)
            % applyTabularRowFilter  Generic deterministic row filtering for any MATLAB table provenance.
            if ~istable(T), error('NMDataIOTableReadTools:filterTableType','Tabular row filtering requires a MATLAB table.'); end
            if nargin < 3 || isempty(sourceLabel), sourceLabel = 'table / sheet'; end
            nInput = height(T);
            sourceRows = (1:nInput)';
            report = struct('schemaVersion',1,'sourceLabel',char(sourceLabel),'nInput',nInput,'nOutput',nInput, ...
                'match','all','caseSensitive',false,'rules',struct([]));
            if isempty(spec) || ~isstruct(spec), return; end
            rules = NMDataIOTableReadTools.filterRules(spec);
            if isempty(rules), return; end
            matchMode = lower(strtrim(char(string(NMDataIOTableReadTools.fieldOr(spec,'match','all')))));
            if ~ismember(matchMode,{'all','any'})
                error('NMDataIOTableReadTools:filterMatchMode','Unsupported row-filter match mode ''%s'' for %s.',matchMode,sourceLabel);
            end
            caseSensitive = logical(NMDataIOTableReadTools.fieldOr(spec,'caseSensitive',false));
            report.match = matchMode;
            report.caseSensitive = caseSensitive;
            if strcmp(matchMode,'all'), keep = true(nInput,1); else, keep = false(nInput,1); end
            names = NMDataIOTableReadTools.originalColumnNames(T);
            ruleReports = repmat(struct('index',0,'column','','operator','','value','','scope','object','scopeId','', ...
                'nMatched',0,'nRetainedAfterRule',0),numel(rules),1);
            for r = 1:numel(rules)
                rule = rules(r);
                column = char(string(NMDataIOTableReadTools.fieldOr(rule,'column','')));
                op = lower(strtrim(char(string(NMDataIOTableReadTools.fieldOr(rule,'operator','eq')))));
                value = char(string(NMDataIOTableReadTools.fieldOr(rule,'value','')));
                hit = find(strcmp(names,column));
                if numel(hit) ~= 1
                    error('NMDataIOTableReadTools:filterColumn','Filter column ''%s'' must occur exactly once in %s.',column,sourceLabel);
                end
                ruleMask = NMDataIOTableReadTools.evaluateFilterRule(T{:,hit}, op, value, caseSensitive, sourceLabel, column);
                if strcmp(matchMode,'all'), keep = keep & ruleMask; else, keep = keep | ruleMask; end
                ruleReports(r) = struct('index',r,'column',column,'operator',op,'value',value, ...
                    'scope',char(string(NMDataIOTableReadTools.fieldOr(rule,'scope','object'))), ...
                    'scopeId',char(string(NMDataIOTableReadTools.fieldOr(rule,'scopeId',''))), ...
                    'nMatched',nnz(ruleMask),'nRetainedAfterRule',nnz(keep));
            end
            sourceRows = sourceRows(keep);
            T = T(keep,:);
            report.nOutput = height(T);
            report.rules = ruleReports;
        end

        function spec = filterForSourceRef(IO, ref)
            % filterForSourceRef  Resolve the single generic filter specification for one provenance object.
            spec = [];
            filters = NMDataIOTableReadTools.fieldOr(IO,'tabularFilters',struct([]));
            if isempty(filters), return; end
            if iscell(filters)
                try, filters = [filters{:}]; catch, error('NMDataIOTableReadTools:filterContract','The saved row-filter settings are invalid.'); end
            end
            if ~isstruct(filters), error('NMDataIOTableReadTools:filterContract','The saved row-filter settings are invalid.'); end
            sourceIdentity = NMDataIOStateTools.variableRefSourceIdentity(ref, IO);
            hits = false(numel(filters),1);
            for i = 1:numel(filters)
                hits(i) = strcmp(NMDataIOStateTools.variableRefSourceIdentity(filters(i), IO), sourceIdentity);
            end
            idx = find(hits);
            if numel(idx) > 1
                error('NMDataIOTableReadTools:duplicateFilter','More than one row-filter definition exists for the same table / sheet.');
            elseif numel(idx) == 1
                spec = filters(idx);
            end
        end

        function columns = databaseRequiredColumns(IO, ref)
            % databaseRequiredColumns  Collect the exact columns needed from one database source object.
            %
            % Scientific assignment and filtering remain generic. This helper only translates the
            % already-authoritative generic role/filter references into one selective retrieval
            % projection so repeated column materialisation can reuse the table cache.
            objectName = char(string(NMDataIOTableReadTools.fieldOr(ref,'sourceObject','')));
            if isempty(objectName)
                error('NMDataIOTableReadTools:sourceRefObject','Database source reference has no table/view object.');
            end
            columns = {};
            roles = NMDataIOTableReadTools.fieldOr(IO,'variableRoles',struct());
            roleNames = {'caseId','labels','features','featureNames','covariates','covariateNames','globals'};
            for r = 1:numel(roleNames)
                if ~isstruct(roles) || ~isfield(roles,roleNames{r}), continue; end
                refs = NMDataIOStateTools.roleRefCell(roles.(roleNames{r}));
                for i = 1:numel(refs)
                    one = refs{i};
                    if strcmpi(char(string(NMDataIOTableReadTools.fieldOr(one,'sourceType',''))),'database') && ...
                            strcmp(char(string(NMDataIOTableReadTools.fieldOr(one,'sourceObject',''))),objectName)
                        nm = char(string(NMDataIOTableReadTools.fieldOr(one,'columnName',NMDataIOTableReadTools.fieldOr(one,'name',''))));
                        if ~isempty(nm), columns{end+1} = nm; end %#ok<AGROW>
                    end
                    if isstruct(one) && isfield(one,'caseKeyRefs') && ~isempty(one.caseKeyRefs)
                        keyRefs = NMDataIOStateTools.roleRefCell(one.caseKeyRefs);
                        for k = 1:numel(keyRefs)
                            keyRef = keyRefs{k};
                            if strcmpi(char(string(NMDataIOTableReadTools.fieldOr(keyRef,'sourceType',''))),'database') && ...
                                    strcmp(char(string(NMDataIOTableReadTools.fieldOr(keyRef,'sourceObject',''))),objectName)
                                nm = char(string(NMDataIOTableReadTools.fieldOr(keyRef,'columnName',NMDataIOTableReadTools.fieldOr(keyRef,'name',''))));
                                if ~isempty(nm), columns{end+1} = nm; end %#ok<AGROW>
                            end
                        end
                    end
                end
            end
            filterSpec = NMDataIOTableReadTools.filterForSourceRef(IO, ref);
            if ~isempty(filterSpec)
                rules = NMDataIOTableReadTools.filterRules(filterSpec);
                for i = 1:numel(rules)
                    nm = char(string(NMDataIOTableReadTools.fieldOr(rules(i),'column','')));
                    if ~isempty(nm), columns{end+1} = nm; end %#ok<AGROW>
                end
            end
            currentName = char(string(NMDataIOTableReadTools.fieldOr(ref,'columnName',NMDataIOTableReadTools.fieldOr(ref,'name',''))));
            if ~isempty(currentName), columns{end+1} = currentName; end %#ok<AGROW>
            columns = unique(columns,'stable');
        end

        function files = tableSourceFiles(IO)
            files=NMDataIOTableReadTools.fieldOr(IO,'tableFiles',{});
            if ischar(files) || isstring(files), files=cellstr(string(files(:))); end
            if isempty(files)
                raw=NMDataIOTableReadTools.fieldOr(IO,'M_edit','?');
                if ~NMDataIOTableReadTools.isUnknown(raw)
                    files=regexp(char(string(raw)),'\r?\n','split');
                end
            end
            files=cellfun(@(x) strtrim(char(string(x))),files(:)','UniformOutput',false); files=files(~cellfun(@isempty,files)); files=unique(files,'stable');
        end

        function gm = tableFileGroupmode(path)
            [~,~,ext]=fileparts(char(path)); ext=lower(ext);
            if ismember(ext,{'.xls','.xlsx','.xlsm','.xlsb','.ods'}), gm=4; else, gm=3; end
        end

        function delim = tableFileDelimiter(path, defaultDelimiter)
            % tableFileDelimiter  Resolve intrinsic CSV/TSV delimiters while retaining the configured delimiter for generic text.
            if nargin < 2 || isempty(defaultDelimiter), defaultDelimiter='tab'; end
            file = char(path);
            [~,~,ext]=fileparts(file); ext=lower(ext);
            if strcmp(ext,'.csv')
                fid=fopen(file,'r');
                if fid < 0
                    error('NMDataIOTableReadTools:fileOpenFailed', ...
                        'Could not open CSV source while detecting its delimiter: %s', file);
                end
                c=onCleanup(@() fclose(fid)); %#ok<NASGU>
                header='';
                while isempty(header)
                    line=fgetl(fid);
                    if ~ischar(line), break; end
                    if ~isempty(strtrim(line)), header=line; end
                end
                if isempty(header)
                    error('NMDataIOTableReadTools:emptyTextTable', ...
                        'CSV source is empty: %s', file);
                end
                counts=[count(header,','), count(header,';'), count(header,sprintf('\t'))];
                maxCount=max(counts);
                if maxCount == 0
                    delim='comma';
                    return;
                end
                if nnz(counts==maxCount) ~= 1
                    error('NMDataIOTableReadTools:csvDelimiter', ...
                        ['CSV delimiter could not be resolved uniquely for %s. ', ...
                         'Header delimiter counts: comma=%d, semicolon=%d, tab=%d.'], ...
                        file,counts(1),counts(2),counts(3));
                end
                names={'comma','semicolon','tab'};
                delim=names{find(counts==maxCount,1)};
            elseif strcmp(ext,'.tsv')
                delim='tab';
            else
                delim=char(string(defaultDelimiter));
            end
        end

        function token = tableObjectToken(path, object)
            token=[char(path) '::' char(string(object))];
        end

        function [sheets, perf] = spreadsheetSheets(path)
            % spreadsheetSheets  Return sheet names from a spreadsheet source for UI selection and probes.
            tTotal = tic;
            perf = struct('seconds',0,'cacheHit',false,'method','');
            key = NMDataIOTableReadTools.spreadsheetMetadataKey(path, 'sheets', '', '');
            [hit, sheets] = NMDataIOTableReadTools.spreadsheetMetadataCache('get', key);
            if hit
                perf.seconds = toc(tTotal); perf.cacheHit = true; perf.method = 'cache';
                return;
            end
            if NMDataIOOOXMLMetadataTools.isSupported(path)
                index = NMDataIOOOXMLMetadataTools.workbookIndex(path);
                sheets = {index.name};
                indexKey = NMDataIOTableReadTools.spreadsheetMetadataKey(path, 'ooxmlWorkbook', '', '');
                NMDataIOTableReadTools.spreadsheetMetadataCache('set', indexKey, index);
                method = 'ooxml';
            else
                [~,~,ext] = fileparts(char(path));
                if strcmpi(ext,'.xls')
                    [status, sheets] = xlsfinfo(path);
                    if isempty(status) || isempty(sheets)
                        error('NMDataIOTableReadTools:xlsSheetDiscovery', 'Could not enumerate worksheets in legacy XLS workbook %s.', char(path));
                    end
                    method = 'xlsfinfo';
                else
                    names = sheetnames(path);
                    if isstring(names), sheets = cellstr(names(:)');
                    elseif iscell(names), sheets = cellfun(@(x) char(string(x)), names(:)', 'UniformOutput', false);
                    else, sheets = cellstr(string(names(:))); end
                    if isempty(sheets), error('NMDataIOTableReadTools:sheetDiscoveryEmpty', 'No worksheets were found in spreadsheet source %s.', char(path)); end
                    method = 'sheetnames';
                end
            end
            NMDataIOTableReadTools.spreadsheetMetadataCache('set', key, sheets);
            perf.seconds = toc(tTotal); perf.cacheHit = false; perf.method = method;
        end

        function meta = probeSpreadsheetSheet(IO, sheet, maxRows, requestedHeaderRow, fingerprint)
            % probeSpreadsheetSheet  Resolve one worksheet header once per workbook fingerprint.
            if nargin < 3 || isempty(maxRows), maxRows = 30; end
            if nargin < 4, requestedHeaderRow = []; end
            if nargin < 5, fingerprint = ''; end
            tTotal = tic; file = char(IO.M_edit);
            extra = sprintf('maxRows=%g|headerRow=%s',double(maxRows),NMDataIOTableReadTools.cacheValue(requestedHeaderRow));
            key = NMDataIOTableReadTools.spreadsheetMetadataKey(file,'header',char(sheet),extra,fingerprint);
            [hit,meta] = NMDataIOTableReadTools.spreadsheetMetadataCache('get',key);
            if hit
                meta.performance = struct('cacheHit',true,'totalSeconds',toc(tTotal),'widthSeconds',0, ...
                    'widthCacheHit',true,'headerReadSeconds',0,'detectHeaderSeconds',0,'nameNormalizationSeconds',0);
                return;
            end
            readRows=maxRows; if ~isempty(requestedHeaderRow), readRows=max(readRows,requestedHeaderRow); end
            [raw,readPerf]=NMDataIOTableReadTools.readRawTopRows(IO,sheet,readRows);
            meta=NMDataIOTableReadTools.spreadsheetMetaFromRaw(IO,sheet,raw,maxRows,requestedHeaderRow,readPerf,fingerprint);
            meta.performance.totalSeconds=toc(tTotal);
        end

        function meta = spreadsheetMetaFromRaw(IO, sheet, raw, maxRows, requestedHeaderRow, readPerf, fingerprint)
            % spreadsheetMetaFromRaw  Build/cache the canonical header result from bounded raw rows.
            if nargin < 7, fingerprint = ''; end
            headerRow=requestedHeaderRow; autoDetected=isempty(headerRow); score=NaN; tDetect=tic;
            if autoDetected, [headerRow,scoreInfo]=NMDataIOTableReadTools.detectHeaderRow(raw); score=scoreInfo.score; end
            detectSeconds=toc(tDetect);
            if isempty(headerRow)||headerRow<1||headerRow>size(raw,1), error('NMDataIOTableReadTools:badHeaderRow', ...
                    'Could not determine a valid header row for sheet ''%s''.',char(sheet)); end
            tNames=tic; rawNames=NMDataIOTableReadTools.rowToCellstr(raw(headerRow,:)); nameSeconds=toc(tNames);
            meta=struct('rawNames',{rawNames},'headerRow',headerRow,'nPreviewRows',size(raw,1),'autoDetected',autoDetected,'score',score);
            extra=sprintf('maxRows=%g|headerRow=%s',double(maxRows),NMDataIOTableReadTools.cacheValue(requestedHeaderRow));
            key=NMDataIOTableReadTools.spreadsheetMetadataKey(char(IO.M_edit),'header',char(sheet),extra,fingerprint);
            NMDataIOTableReadTools.spreadsheetMetadataCache('set',key,meta);
            meta.performance=struct('cacheHit',false,'totalSeconds',0, ...
                'widthSeconds',double(NMDataIOTableReadTools.fieldOr(readPerf,'widthSeconds',0)), ...
                'widthCacheHit',logical(NMDataIOTableReadTools.fieldOr(readPerf,'widthCacheHit',false)), ...
                'headerReadSeconds',double(NMDataIOTableReadTools.fieldOr(readPerf,'headerReadSeconds',0)), ...
                'detectHeaderSeconds',double(detectSeconds),'nameNormalizationSeconds',double(nameSeconds));
        end

        function key = spreadsheetMetadataKey(path, kind, sheet, extra, fingerprint)
            % spreadsheetMetadataKey  Build one cache key from a workbook fingerprint.
            % A caller that already fingerprinted the source supplies that value so
            % OneDrive/network metadata are not re-queried for every sheet/cache field.
            if nargin < 5 || isempty(fingerprint)
                d = dir(path);
                if isempty(d) || logical(d(1).isdir)
                    key = '';
                    return;
                end
                fingerprint = NMDataIOTableReadTools.spreadsheetMetadataFingerprint(path,d(1));
            end
            key = sprintf('%s|%s|sheet=%s|%s', ...
                char(kind), char(fingerprint), char(sheet), char(extra));
        end

        function fingerprint = spreadsheetMetadataFingerprint(path, fileInfo)
            % spreadsheetMetadataFingerprint  Canonical identity for spreadsheet metadata caches.
            if nargin < 2 || isempty(fileInfo)
                fileInfo = dir(path);
            end
            if isempty(fileInfo) || logical(fileInfo(1).isdir)
                fingerprint = '';
                return;
            end
            fingerprint = sprintf('file=%s|bytes=%.0f|datenum=%.17g', ...
                char(path), double(fileInfo(1).bytes), double(fileInfo(1).datenum));
        end

        function [hit, value] = spreadsheetMetadataCache(action, key, value)
            % spreadsheetMetadataCache  Cache small workbook/sheet metadata across browser probes.
            persistent cache order
            if isempty(cache)
                cache = containers.Map('KeyType','char','ValueType','any');
                order = {};
            end
            if nargin < 3, value = []; end
            hit = false;
            switch lower(char(action))
                case 'get'
                    if ~isempty(key) && isKey(cache, key)
                        value = cache(key);
                        hit = true;
                    end
                case 'set'
                    if isempty(key), return; end
                    cache(key) = value;
                    order(strcmp(order, key)) = [];
                    order{end+1} = key;
                    while numel(order) > 256
                        oldKey = order{1};
                        order(1) = [];
                        if isKey(cache, oldKey), remove(cache, oldKey); end
                    end
                case 'clear'
                    cache = containers.Map('KeyType','char','ValueType','any');
                    order = {};
                otherwise
                    error('NMDataIOTableReadTools:badSpreadsheetMetadataCacheAction', 'Unknown spreadsheet metadata operation: %s', char(action));
            end
        end

        function T = readTextTable(IO)
            % readTextTable  Read a delimited text table while preserving original header names.
            %
            % IO -> T.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % Throws on invalid preconditions instead of returning an ambiguous partial result; diagnostics are returned as structured messages for explicit UI/API handling.
            file = char(IO.M_edit);
            delim = NMDataIOTableReadTools.fieldOr(IO,'delimit','tab');
            headerRow = NMDataIOTableReadTools.headerRow(IO, []);
            if isempty(headerRow) && isfield(IO,'headerAutoDetect') && isequal(IO.headerAutoDetect,true)
                h = NMDataIOTableReadTools.probeHeaders(IO, struct('MaxRows',30));
                if h.ok, headerRow = h.headerRow; end
            end
            if isempty(headerRow), headerRow = 1; end
            projectedColumns = NMDataIOTableReadTools.sourceProjectionColumns(IO);
            if ~isempty(projectedColumns)
                T = NMDataIOTableReadTools.readDelimitedProjectedTable(file, delim, headerRow, projectedColumns);
                return;
            end

            % Delimited text imports are intentionally read as raw cells and
            % converted later by NMDataIOTableRoleTools.  readtable may
            % silently coerce non-numeric tokens in otherwise numeric columns
            % to NaN.  That is unsafe for DataIO diagnostics because true
            % missing cells and illegal tokens such as 'bad_cell' must remain
            % distinguishable until the role-specific NaN-mapper/numeric
            % validation stage.
            raw = NMDataIOTableReadTools.readDelimitedTopRows(file, delim, Inf);
            if isempty(raw)
                error('NMDataIOTableReadTools:emptyTextTable', 'Text table source is empty: %s', file);
            end
            if headerRow < 1 || headerRow > size(raw,1)
                error('NMDataIOTableReadTools:badHeaderRow', 'Header row %g is outside the readable text-table range.', headerRow);
            end
            rawNames = NMDataIOTableReadTools.rowToCellstr(raw(headerRow,:));
            nCols = numel(rawNames);
            if size(raw,2) > nCols
                extraNames = arrayfun(@(i) sprintf('Var%g', i), nCols+1:size(raw,2), 'UniformOutput', false);
                rawNames = [rawNames extraNames];
                nCols = numel(rawNames);
            end
            data = raw(headerRow+1:end, 1:nCols);
            T = NMDataIOTableReadTools.cell2tablePreserveHeaders(data, rawNames);
        end

        function T = readSpreadsheetTable(IO)
            % readSpreadsheetTable  Read exactly one worksheet object.
            % Multi-object scientific alignment is owned by generic source blocks;
            % this reader deliberately does not merge worksheets.
            file = char(IO.M_edit);
            workbookSheets = NMDataIOTableReadTools.spreadsheetSheets(file);
            sheets = NMDataIOTableReadTools.selectedSpreadsheetSheets(IO, workbookSheets);
            if numel(sheets) ~= 1
                error('NMDataIOTableReadTools:multiSheetRequiresSourceBlocks', ...
                    'NM2 cannot automatically merge multiple worksheets side-by-side. Add each worksheet separately and use Case-ID matching.');
            end
            sheet = sheets{1};
            headerRow = NMDataIOTableReadTools.headerRow(IO, []);
            if isempty(headerRow) && isfield(IO,'headerAutoDetect') && isequal(IO.headerAutoDetect,true)
                meta = NMDataIOTableReadTools.probeSpreadsheetSheet(IO, sheet, 30, []);
                headerRow = meta.headerRow;
            end
            if isempty(headerRow), headerRow = 1; end
            projectedColumns = NMDataIOTableReadTools.sourceProjectionColumns(IO);
            if ~isempty(projectedColumns)
                T = NMDataIOTableReadTools.readSpreadsheetProjectedTable(IO, sheet, headerRow, projectedColumns);
                return;
            end
            nCols = NMDataIOTableReadTools.spreadsheetColumnCount(file, sheet, max(30,headerRow));
            if nCols < 1
                error('NMDataIOTableReadTools:emptySpreadsheetHeader', ...
                    'No spreadsheet columns were detected in worksheet ''%s''.', char(sheet));
            end
            lastColumn = NMDataIOTableReadTools.spreadsheetColumnName(nCols);
            T = NMDataIOTableReadTools.readtableWithHeaderRow(file, headerRow, ...
                'Sheet', char(sheet), 'Range', sprintf('A:%s',lastColumn));
        end

        function T = readDelimitedProjectedTable(file, delim, headerRow, columns)
            % readDelimitedProjectedTable  Read only selected delimited-text columns while preserving raw cell tokens.
            fid = fopen(file,'r');
            if fid < 0
                error('NMDataIOTableReadTools:fileOpenFailed','Could not open table source: %s',file);
            end
            c = onCleanup(@() fclose(fid)); %#ok<NASGU>
            rowIndex = 0; hits = []; rawNames = {}; nDataRows = 0; capacity = 1024;
            data = cell(capacity,numel(columns));
            while true
                line = fgetl(fid);
                if ~ischar(line), break; end
                rowIndex = rowIndex + 1;
                parts = NMDataIOTableReadTools.splitDelimitedLine(line,delim);
                if rowIndex == headerRow
                    rawNames = parts;
                    hits = zeros(1,numel(columns));
                    for j = 1:numel(columns)
                        idx = find(strcmp(rawNames,columns{j}));
                        if numel(idx) ~= 1
                            error('NMDataIOTableReadTools:sourceRefColumn', ...
                                'Column ''%s'' must occur exactly once in %s. Matches=%d.',columns{j},file,numel(idx));
                        end
                        hits(j) = idx;
                    end
                elseif rowIndex > headerRow
                    if isempty(hits)
                        error('NMDataIOTableReadTools:badHeaderRow','Header row %g is outside the readable text-table range.',headerRow);
                    end
                    nDataRows = nDataRows + 1;
                    if nDataRows > capacity
                        capacity = capacity * 2;
                        data{capacity,numel(columns)} = [];
                    end
                    for j = 1:numel(hits)
                        if hits(j) <= numel(parts), data{nDataRows,j} = parts{hits(j)}; else, data{nDataRows,j} = ''; end
                    end
                end
            end
            if isempty(rawNames)
                error('NMDataIOTableReadTools:badHeaderRow','Header row %g is outside the readable text-table range.',headerRow);
            end
            data = data(1:nDataRows,:);
            T = NMDataIOTableReadTools.cell2tablePreserveHeaders(data,columns);
        end

        function T = readSpreadsheetProjectedTable(IO, sheet, headerRow, columns)
            % readSpreadsheetProjectedTable  Read only selected worksheet columns and retain source-column order.
            file = char(IO.M_edit);
            meta = NMDataIOTableReadTools.probeSpreadsheetSheet(IO,sheet,max(30,headerRow),headerRow);
            names = meta.rawNames;
            hits = zeros(1,numel(columns));
            for j = 1:numel(columns)
                idx = find(strcmp(names,columns{j}));
                if numel(idx) ~= 1
                    error('NMDataIOTableReadTools:sourceRefColumn', ...
                        'Column ''%s'' must occur exactly once in worksheet ''%s''. Matches=%d.',columns{j},char(sheet),numel(idx));
                end
                hits(j) = idx;
            end
            sortedHits = sort(unique(hits));
            runStart = [1 find(diff(sortedHits)>1)+1];
            runEnd = [runStart(2:end)-1 numel(sortedHits)];
            columnData = cell(1,numel(columns));
            maxRows = 0;
            for r = 1:numel(runStart)
                cols = sortedHits(runStart(r):runEnd(r));
                firstCol = NMDataIOTableReadTools.spreadsheetColumnName(cols(1));
                lastCol = NMDataIOTableReadTools.spreadsheetColumnName(cols(end));
                raw = readcell(file,'Sheet',char(sheet),'Range',sprintf('%s:%s',firstCol,lastCol));
                if size(raw,1) < headerRow
                    error('NMDataIOTableReadTools:badHeaderRow','Header row %g is outside the readable worksheet range.',headerRow);
                end
                block = raw(headerRow+1:end,:);
                maxRows = max(maxRows,size(block,1));
                for j = 1:numel(columns)
                    local = find(cols==hits(j),1);
                    if ~isempty(local), columnData{j} = block(:,local); end
                end
            end
            data = cell(maxRows,numel(columns));
            for j = 1:numel(columns)
                col = columnData{j};
                if isempty(col), col = cell(0,1); end
                data(1:numel(col),j) = col(:);
            end
            T = NMDataIOTableReadTools.cell2tablePreserveHeaders(data,columns);
        end

        function sheets = selectedSpreadsheetSheets(IO, workbookSheets)
            % selectedSpreadsheetSheets  Resolve selected sheet names in workbook order.
            if nargin < 2 || isempty(workbookSheets)
                workbookSheets = NMDataIOTableReadTools.spreadsheetSheets(char(IO.M_edit));
            end
            requested = NMDataIOTableReadTools.fieldOr(IO,'sheets',{});
            requested = NMDataIOTableReadTools.sheetList(requested);
            if isempty(requested)
                one = NMDataIOTableReadTools.fieldOr(IO,'sheet','?');
                if ~NMDataIOTableReadTools.isUnknown(one), requested = {char(string(one))}; end
            end
            if isempty(requested)
                sheets = workbookSheets(1);
                return;
            end
            requested = unique(requested, 'stable');
            missing = requested(~ismember(requested, workbookSheets));
            if ~isempty(missing)
                error('NMDataIOTableReadTools:unknownSpreadsheetSheet', 'Selected spreadsheet sheet(s) not found in workbook: %s.', strjoin(missing, ', '));
            end
            sheets = workbookSheets(ismember(workbookSheets, requested));
            if isempty(sheets)
                error('NMDataIOTableReadTools:noSpreadsheetSheetSelected', 'Select at least one spreadsheet sheet.');
            end
        end

        function sheets = sheetList(v)
            % sheetList  Normalize sheet-selection state to a row cell array of names.
            if isempty(v)
                sheets = {};
            elseif iscell(v)
                sheets = cellfun(@(x) char(string(x)), v(:)', 'UniformOutput', false);
            elseif isstring(v)
                sheets = cellstr(v(:)');
            elseif ischar(v)
                sheets = {v};
            else
                sheets = {char(string(v))};
            end
            sheets = sheets(~cellfun(@(x) isempty(strtrim(x)) || strcmp(strtrim(x),'?'), sheets));
        end

        function [nCols, perf] = spreadsheetColumnCount(file, sheet, maxRows)
            % spreadsheetColumnCount  Determine occupied header width without full XLSX/XLSM import.
            if nargin < 3 || isempty(maxRows), maxRows = 30; end
            tTotal = tic; perf = struct('seconds',0,'cacheHit',false);
            key = NMDataIOTableReadTools.spreadsheetMetadataKey(file, 'width', char(sheet), sprintf('maxRows=%g',double(maxRows)));
            [hit, nCols] = NMDataIOTableReadTools.spreadsheetMetadataCache('get', key);
            if hit, perf.seconds = toc(tTotal); perf.cacheHit = true; return; end
            if NMDataIOOOXMLMetadataTools.isSupported(file)
                index = NMDataIOTableReadTools.ooxmlWorkbookIndexCached(file);
                target = NMDataIOTableReadTools.ooxmlWorksheetTarget(index, sheet, file);
                [raw,~] = NMDataIOOOXMLMetadataTools.topRows(file, target, maxRows);
                nCols = double(size(raw,2));
            else
                opts = detectImportOptions(file, 'Sheet', char(sheet), ...
                    'Range', sprintf('1:%d',max(1,ceil(double(maxRows)))), 'VariableNamingRule','preserve');
                nCols = double(numel(opts.VariableNames));
            end
            NMDataIOTableReadTools.spreadsheetMetadataCache('set', key, nCols);
            perf.seconds = toc(tTotal);
        end

        function index = ooxmlWorkbookIndexCached(file)
            key = NMDataIOTableReadTools.spreadsheetMetadataKey(file, 'ooxmlWorkbook', '', '');
            [hit,index] = NMDataIOTableReadTools.spreadsheetMetadataCache('get', key);
            if ~hit
                index = NMDataIOOOXMLMetadataTools.workbookIndex(file);
                NMDataIOTableReadTools.spreadsheetMetadataCache('set', key, index);
            end
        end

        function target = ooxmlWorksheetTarget(index, sheet, file)
            hit = find(strcmp({index.name},char(string(sheet))),1);
            if isempty(hit)
                error('NMDataIOTableReadTools:unknownSpreadsheetSheet', 'Worksheet ''%s'' was not found in workbook %s.', char(string(sheet)), char(file));
            end
            target = index(hit).target;
        end

        function name = spreadsheetColumnName(index)
            % spreadsheetColumnName  Convert a one-based spreadsheet column index to A1 letters.
            index = double(index);
            if ~isscalar(index) || ~isfinite(index) || index < 1 || index ~= round(index)
                error('NMDataIOTableReadTools:spreadsheetColumnIndex', ...
                    'Spreadsheet column index must be a positive integer.');
            end
            chars = '';
            while index > 0
                r = mod(index-1,26);
                chars = [char(double('A')+r) chars]; %#ok<AGROW>
                index = floor((index-1)/26);
            end
            name = chars;
        end

        function T = readtableWithHeaderRow(file, headerRow, varargin)
            % readtableWithHeaderRow  Read spreadsheet-like sources without letting MATLAB interpret.
            %
            % user headers as table variable names. Long PRS/genetic headers
            % can exceed namelengthmax; DataIO therefore keeps original
            % headers in metadata and uses internal aliases only if needed.
            C = [];
            try
                C = readcell(file, varargin{:});
            catch
                Tall = readtable(file, varargin{:}, 'ReadVariableNames', false);
                C = table2cell(Tall);
            end
            if headerRow < 1 || headerRow > size(C,1)
                error('NMDataIOTableReadTools:badHeaderRow', 'Header row %g is outside the readable table range.', headerRow);
            end
            rawNames = NMDataIOTableReadTools.rowToCellstr(C(headerRow,:));
            data = C(headerRow+1:end,:);
            T = NMDataIOTableReadTools.cell2tablePreserveHeaders(data, rawNames);
        end

        function [raw, perf] = readRawTopRows(IO, sheet, maxRows)
            % readRawTopRows  Read the top rows of a tabular source for header-row detection and preview.
            %
            % Consumes IO, sheet, maxRows; returns raw.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 3 || isempty(maxRows), maxRows = 30; end
            perf = struct('widthSeconds',0,'widthCacheHit',false,'headerReadSeconds',0);
            switch double(IO.groupmode)
                case 3
                    % Do not use readtable here.  Header probing must also
                    % work when the first few lines are free-text metadata
                    % rows with fewer delimiters than the real header row.
                    % readtable may then infer the wrong width or fail before
                    % we can inspect the candidate header rows.
                    file = char(IO.M_edit);
                    delim = NMDataIOTableReadTools.fieldOr(IO,'delimit','tab');
                    raw = NMDataIOTableReadTools.readDelimitedTopRows(file, delim, maxRows);
                    return;
                case 4
                    file = char(IO.M_edit);
                    if nargin < 2 || isempty(sheet) || NMDataIOTableReadTools.isUnknown(sheet)
                        sheets = NMDataIOTableReadTools.spreadsheetSheets(file); sheet = sheets{1};
                    end
                    if NMDataIOOOXMLMetadataTools.isSupported(file)
                        index = NMDataIOTableReadTools.ooxmlWorkbookIndexCached(file);
                        target = NMDataIOTableReadTools.ooxmlWorksheetTarget(index, sheet, file);
                        [raw,ooxmlPerf] = NMDataIOOOXMLMetadataTools.topRows(file, target, maxRows);
                        perf.headerReadSeconds = double(ooxmlPerf.seconds);
                        widthKey = NMDataIOTableReadTools.spreadsheetMetadataKey(file, 'width', char(sheet), sprintf('maxRows=%g',double(maxRows)));
                        NMDataIOTableReadTools.spreadsheetMetadataCache('set', widthKey, double(size(raw,2)));
                        return;
                    end
                    [nCols, widthPerf] = NMDataIOTableReadTools.spreadsheetColumnCount(file, sheet, maxRows);
                    perf.widthSeconds = double(widthPerf.seconds); perf.widthCacheHit = logical(widthPerf.cacheHit);
                    if nCols < 1, raw = cell(0,0); return; end
                    lastColumn = NMDataIOTableReadTools.spreadsheetColumnName(nCols);
                    rowRange = sprintf('A1:%s%d', lastColumn, max(1,ceil(double(maxRows))));
                    tHeaderRead = tic; C = readcell(file, 'Sheet', char(sheet), 'Range', rowRange);
                    perf.headerReadSeconds = toc(tHeaderRead);
                    raw = C(1:min(maxRows,size(C,1)), 1:min(nCols,size(C,2)));
                    return;
                otherwise
                    raw = cell(0,0);
                    return;
            end
            C = table2cell(T);
            raw = C(1:min(maxRows,size(C,1)), :);
        end

        function raw = readDelimitedTopRows(file, delim, maxRows)
            % readDelimitedTopRows  Read top rows from a delimited text file without constructing a full table.
            %
            % Consumes file, delim, maxRows; returns raw.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % Performs explicit file-system IO; throws on invalid preconditions instead of returning an ambiguous partial result.
            if nargin < 3 || isempty(maxRows), maxRows = 30; end
            fid = fopen(file, 'r');
            if fid < 0
                error('NMDataIOTableReadTools:fileOpenFailed', 'Could not open table source: %s', file);
            end
            rows = cell(0,1);
            c = onCleanup(@() fclose(fid)); %#ok<NASGU>
            while numel(rows) < maxRows
                line = fgetl(fid);
                if ~ischar(line), break; end
                rows{end+1,1} = NMDataIOTableReadTools.splitDelimitedLine(line, delim); %#ok<AGROW>
            end
            raw = NMDataIOTableReadTools.padCellRows(rows);
        end

        function parts = splitDelimitedLine(line, delim)
            % splitDelimitedLine  Split one delimited text line while preserving empty fields.
            %
            % Line, delim -> parts.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2 || isempty(delim), delim = 'tab'; end
            if ~isempty(line)
                if double(line(1)) == 65279
                    line = line(2:end);
                elseif numel(line) >= 3 && isequal(double(line(1:3)),[239 187 191])
                    line = line(4:end);
                end
            end
            d = char(delim);
            switch lower(strtrim(d))
                case {'tab','\t'}
                    sep = sprintf('\t');
                case {'comma',','}
                    sep = ',';
                case {'semicolon',';'}
                    sep = ';';
                case {'space',' '}
                    parts = regexp(strtrim(line), '\s+', 'split');
                    parts = parts(:)';
                    return;
                otherwise
                    sep = d;
            end
            parts = regexp(line, regexptranslate('escape', sep), 'split');
            parts = cellfun(@strtrim, parts, 'UniformOutput', false);
            parts = parts(:)';
        end

        function raw = padCellRows(rows)
            % padCellRows  Pad ragged raw table rows to a rectangular cell array.
            %
            % Rows -> raw.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(rows)
                raw = cell(0,0);
                return;
            end
            n = 0;
            for i = 1:numel(rows)
                n = max(n, numel(rows{i}));
            end
            raw = cell(numel(rows), n);
            raw(:) = {''};
            for i = 1:numel(rows)
                r = rows{i};
                if isempty(r), continue; end
                raw(i,1:numel(r)) = r;
            end
        end

        function [row, info] = detectHeaderRow(raw)
            % detectHeaderRow  Infer the most plausible header row from raw preview rows.
            %
            % Raw -> row, info.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            info = struct('score', -Inf, 'scores', []);
            row = [];
            if isempty(raw), return; end
            nRows = size(raw,1);
            scores = -Inf(nRows,1);
            for r = 1:nRows
                vals = NMDataIOTableReadTools.rowToCellstr(raw(r,:));
                nonEmpty = ~cellfun(@isempty, vals);
                if ~any(nonEmpty), scores(r) = -Inf; continue; end
                vals2 = vals(nonEmpty);
                uniqueFrac = numel(unique(vals2)) / max(1,numel(vals2));
                textFrac = mean(isnan(str2double(vals2)));
                nextNumeric = 0;
                if r < nRows
                    nxt = NMDataIOTableReadTools.rowToCellstr(raw(r+1,:)); nxt = nxt(nonEmpty);
                    if ~isempty(nxt), nextNumeric = mean(~isnan(str2double(nxt))); end
                end
                scores(r) = 0.45*mean(nonEmpty) + 0.30*uniqueFrac + 0.15*textFrac + 0.10*nextNumeric;
            end
            [mx, row] = max(scores);
            if ~isfinite(mx), row = 1; mx = 0; end
            info.score = mx;
            info.scores = scores;
        end

        function row = headerRow(IO, defaultValue)
            % headerRow  Return the configured or default header-row index for an IO source.
            %
            % IO, defaultValue -> row.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2, defaultValue = []; end
            row = defaultValue;
            candidates = {'headerRow','tableHeaderRow','variableNamesLine'};
            for i = 1:numel(candidates)
                if isfield(IO,candidates{i}) && ~isempty(IO.(candidates{i}))
                    x = IO.(candidates{i});
                    if isnumeric(x)
                        row = double(x(1)); return;
                    end
                    y = str2double(char(string(x)));
                    if isfinite(y) && y > 0, row = y; return; end
                end
            end
            if isfield(IO,'headerAutoDetect') && isequal(IO.headerAutoDetect,true)
                row = [];
            end
        end

        function names = makeMatlabTableNames(rawNames)
            % makeMatlabTableNames  Convert raw column labels into valid unique MATLAB table variable names.
            %
            % RawNames -> names.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            rawNames = NMDataIOTableReadTools.rowToCellstr(rawNames);
            if NMDataIOTableReadTools.needsInternalAliases(rawNames)
                names = NMDataIOTableReadTools.internalColumnAliases(numel(rawNames));
                return;
            end
            names = rawNames(:)';
        end

        function T = cell2tablePreserveHeaders(data, originalNames)
            % cell2tablePreserveHeaders  Construct a MATLAB table while retaining original source headers in metadata.
            %
            % Data, originalNames -> T.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            originalNames = NMDataIOTableReadTools.rowToCellstr(originalNames);
            nCols = size(data,2);
            if numel(originalNames) < nCols
                extraNames = arrayfun(@(i) sprintf('Var%g', i), numel(originalNames)+1:nCols, 'UniformOutput', false);
                originalNames = [originalNames extraNames];
            elseif numel(originalNames) > nCols
                originalNames = originalNames(1:nCols);
            end
            internalNames = NMDataIOTableReadTools.makeMatlabTableNames(originalNames);
            T = cell2table(data, 'VariableNames', internalNames);
            T = NMDataIOTableReadTools.attachOriginalColumnNames(T, originalNames);
        end

        function T = attachOriginalColumnNames(T, originalNames)
            % attachOriginalColumnNames  Attach original database/table column names to a MATLAB table after aliasing.
            %
            % T, originalNames -> T.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            originalNames = NMDataIOTableReadTools.rowToCellstr(originalNames);
            nCols = width(T);
            if numel(originalNames) ~= nCols
                originalNames = NMDataIOTableReadTools.padOrTrimNames(originalNames, nCols);
            end
            T.Properties.VariableDescriptions = originalNames(:)';
            map = struct();
            map.schemaVersion = 1;
            map.internalNames = T.Properties.VariableNames(:)';
            map.originalNames = originalNames(:)';
            map.usesInternalAliases = ~isequal(map.internalNames, map.originalNames);
            ud = T.Properties.UserData;
            if ~isstruct(ud), ud = struct(); end
            ud.NMDataIOColumnMap = map;
            T.Properties.UserData = ud;
        end

        function key = tableCacheKey(IO)
            % tableCacheKey  Compute the cache key identifying a prepared table source and role-relevant options.
            %
            % IO -> key.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % Cache contents are an acceleration/rehydration artifact, not a new source of truth.
            key = '';
            if ~isstruct(IO) || ~isfield(IO,'groupmode'), return; end
            gm = double(IO.groupmode);
            if ~ismember(gm, [3 4 6]), return; end
            parts = {sprintf('groupmode=%g', gm)};
            projectedColumns = NMDataIOTableReadTools.sourceProjectionColumns(IO);
            if ~isempty(projectedColumns)
                parts{end+1} = ['projection=' NMDataIOTableReadTools.cacheValue(projectedColumns)]; %#ok<AGROW>
            end
            switch gm
                case {3,4}
                    file = NMDataIOTableReadTools.fieldOr(IO,'M_edit','?');
                    if NMDataIOTableReadTools.isUnknown(file), return; end
                    file = char(file);
                    d = dir(file);
                    if isempty(d), return; end
                    parts{end+1} = ['file=' file]; %#ok<AGROW>
                    parts{end+1} = sprintf('bytes=%.0f', double(d(1).bytes)); %#ok<AGROW>
                    parts{end+1} = sprintf('datenum=%.17g', double(d(1).datenum)); %#ok<AGROW>
                    parts{end+1} = ['headerRow=' NMDataIOTableReadTools.cacheValue(NMDataIOTableReadTools.headerRow(IO, []))]; %#ok<AGROW>
                    parts{end+1} = ['headerAutoDetect=' NMDataIOTableReadTools.cacheValue(NMDataIOTableReadTools.fieldOr(IO,'headerAutoDetect',false))]; %#ok<AGROW>
                    if gm == 3
                        parts{end+1} = ['delimit=' char(string(NMDataIOTableReadTools.fieldOr(IO,'delimit','tab')))]; %#ok<AGROW>
                    else
                        parts{end+1} = ['sheet=' char(string(NMDataIOTableReadTools.fieldOr(IO,'sheet','?')))]; %#ok<AGROW>
                        parts{end+1} = ['sheets=' NMDataIOTableReadTools.cacheValue(NMDataIOTableReadTools.fieldOr(IO,'sheets',{}))]; %#ok<AGROW>
                    end
                case 6
                    NMDataIODatabaseTools.connectionInfo(IO); % Reject embedded credentials before constructing retained cache identity.
                    % Database reads can be just as expensive as file reads;
                    % include all connection/query fields that define the result.
                    fields = {'databaseConnector','databaseUrl','databaseFile','databaseUser','databaseName','databaseSchema','databaseTable','databaseUseQuery','databaseQuery','databaseSelectedColumns'};
                    for f = 1:numel(fields)
                        parts{end+1} = [fields{f} '=' NMDataIOTableReadTools.cacheValue(NMDataIOTableReadTools.fieldOr(IO, fields{f}, ''))]; %#ok<AGROW>
                    end
                    dbFile = NMDataIOTableReadTools.fieldOr(IO,'databaseFile','');
                    if ~NMDataIOTableReadTools.isUnknown(dbFile) && exist(char(dbFile),'file') == 2
                        d = dir(char(dbFile));
                        if ~isempty(d)
                            parts{end+1} = sprintf('dbbytes=%.0f', double(d(1).bytes)); %#ok<AGROW>
                            parts{end+1} = sprintf('dbdatenum=%.17g', double(d(1).datenum)); %#ok<AGROW>
                        end
                    end
            end
            key = strjoin(parts, '|');
        end

        function [hit, T] = tableCache(action, key, T)
            % tableCache  Read, write, or clear the in-memory table cache used by repeated probes/commits.
            %
            % Consumes action, key, T; returns hit, T.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % Throws on invalid preconditions instead of returning an ambiguous partial result; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            persistent cache order
            if isempty(cache)
                cache = containers.Map('KeyType','char','ValueType','any');
                order = {};
            end
            if nargin < 3, T = []; end
            hit = false;
            switch lower(char(action))
                case 'get'
                    if ~isempty(key) && isKey(cache, key)
                        T = cache(key);
                        hit = true;
                    end
                case 'set'
                    if isempty(key), return; end
                    cache(key) = T;
                    order(strcmp(order, key)) = [];
                    order{end+1} = key;
                    maxEntries = 4;
                    while numel(order) > maxEntries
                        oldKey = order{1};
                        order(1) = [];
                        if isKey(cache, oldKey)
                            remove(cache, oldKey);
                        end
                    end
                case 'clear'
                    cache = containers.Map('KeyType','char','ValueType','any');
                    order = {};
                otherwise
                    error('NMDataIOTableReadTools:badCacheAction', 'Unknown table-data operation: %s', char(action));
            end
        end

        function clearCache()
            % clearCache  Clear the tabular-source cache after source or role settings change.
            %
            % No required inputs -> no explicit output.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % Cache contents are an acceleration/rehydration artifact, not a new source of truth.
            NMDataIOTableReadTools.tableCache('clear', '');
            NMDataIOTableReadTools.spreadsheetMetadataCache('clear', '');
        end

        function txt = cacheValue(v)
            % cacheValue  Convert cache-key components into stable text tokens.
            %
            % V -> txt.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % Cache contents are an acceleration/rehydration artifact, not a new source of truth.
            if isempty(v)
                txt = '';
            elseif ischar(v)
                txt = v;
            elseif isstring(v)
                txt = char(strjoin(v(:)', ','));
            elseif isnumeric(v) || islogical(v)
                txt = mat2str(v);
            elseif iscell(v)
                c = cell(size(v));
                for i = 1:numel(v)
                    c{i} = NMDataIOTableReadTools.cacheValue(v{i});
                end
                txt = strjoin(c(:)', ',');
            else
                try
                    txt = char(string(v));
                catch
                    txt = class(v);
                end
            end
        end

        function names = originalColumnNames(T)
            % originalColumnNames  Recover original database/table column names from table properties.
            %
            % T -> names.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            names = {};
            if ~istable(T), return; end
            ud = T.Properties.UserData;
            if isstruct(ud) && isfield(ud,'NMDataIOColumnMap') && isstruct(ud.NMDataIOColumnMap) && ...
                    isfield(ud.NMDataIOColumnMap,'originalNames') && numel(ud.NMDataIOColumnMap.originalNames) == width(T)
                names = NMDataIOTableReadTools.rowToCellstr(ud.NMDataIOColumnMap.originalNames);
                return;
            end
            d = T.Properties.VariableDescriptions;
            if numel(d) == width(T) && any(~cellfun(@isempty, NMDataIOTableReadTools.rowToCellstr(d)))
                names = NMDataIOTableReadTools.rowToCellstr(d);
                return;
            end
            names = T.Properties.VariableNames(:)';
        end

        function report = columnNameReport(T)
            % columnNameReport  Report how original headers map onto MATLAB-safe table variable names.
            %
            % T -> report.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            report = struct('hasOriginalNames',false,'usesInternalAliases',false, ...
                'internalNames',{{}},'originalNames',{{}},'nColumns',0);
            if ~istable(T), return; end
            report.internalNames = T.Properties.VariableNames(:)';
            report.originalNames = NMDataIOTableReadTools.originalColumnNames(T);
            report.nColumns = width(T);
            report.hasOriginalNames = numel(report.originalNames) == report.nColumns;
            report.usesInternalAliases = report.hasOriginalNames && ~isequal(report.internalNames, report.originalNames);
        end

        function tf = needsInternalAliases(rawNames)
            % needsInternalAliases  Detect whether raw headers require internal MATLAB-safe aliases.
            %
            % RawNames -> tf.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            rawNames = NMDataIOTableReadTools.rowToCellstr(rawNames);
            for i = 1:numel(rawNames)
                if isempty(rawNames{i}), rawNames{i} = sprintf('Var%g', i); end
            end
            if numel(unique(rawNames, 'stable')) ~= numel(rawNames)
                tf = true; return;
            end
            for i = 1:numel(rawNames)
                nm = rawNames{i};
                if numel(nm) > namelengthmax || isempty(nm) || ~isvarname(nm)
                    tf = true; return;
                end
            end
            tf = false;
        end

        function names = internalColumnAliases(n)
            % internalColumnAliases  Create deterministic internal aliases for unnamed or invalid table columns.
            %
            % N -> names.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            names = arrayfun(@(i) sprintf('NMCol_%06d', i), 1:n, 'UniformOutput', false);
        end

        function names = padOrTrimNames(names, n)
            % padOrTrimNames  Match a name vector length to the number of table columns.
            %
            % Names, n -> names.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            names = NMDataIOTableReadTools.rowToCellstr(names);
            if numel(names) < n
                extra = arrayfun(@(i) sprintf('Var%g', i), numel(names)+1:n, 'UniformOutput', false);
                names = [names extra];
            elseif numel(names) > n
                names = names(1:n);
            end
            for i = 1:numel(names)
                if isempty(names{i}), names{i} = sprintf('Var%g', i); end
            end
            names = names(:)';
        end

        function c = rowToCellstr(row)
            % rowToCellstr  Convert a raw table-preview row into text cells for header detection.
            %
            % Row -> c.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if istable(row), row = table2cell(row); end
            if isstring(row), row = cellstr(row); end
            if ischar(row), c = cellstr(row); c = c(:)'; return; end
            if ~iscell(row), row = num2cell(row); end
            c = cell(size(row));
            for i = 1:numel(row)
                x = row{i};
                if isempty(x)
                    c{i} = '';
                elseif ischar(x)
                    c{i} = strtrim(x);
                elseif isa(x,'string')
                    if isempty(x), c{i} = ''; else, c{i} = strtrim(char(x(1))); end
                elseif isnumeric(x) || islogical(x)
                    if isempty(x) || (isnumeric(x) && isnan(x(1)))
                        c{i} = '';
                    else
                        c{i} = strtrim(num2str(x(1)));
                    end
                else
                    try
                        c{i} = strtrim(char(string(x)));
                    catch
                        c{i} = '';
                    end
                end
            end
            c = c(:)';
        end

        function rules = filterRules(spec)
            % filterRules  Normalize one row-filter rule collection without changing rule order.
            rules = NMDataIOTableReadTools.fieldOr(spec,'rules',struct([]));
            if isempty(rules), rules = struct([]); return; end
            if iscell(rules)
                try, rules = [rules{:}]; catch, error('NMDataIOTableReadTools:filterRules','Row-filter rules must be a struct array.'); end
            end
            if ~isstruct(rules), error('NMDataIOTableReadTools:filterRules','Row-filter rules must be a struct array.'); end
            rules = rules(:)';
        end

        function mask = evaluateFilterRule(col, op, criterion, caseSensitive, sourceLabel, column)
            % evaluateFilterRule  Evaluate one deterministic filter predicate while preserving missingness semantics.
            n = numel(col);
            missing = NMDataIOTableReadTools.filterMissingMask(col);
            switch op
                case 'is_missing'
                    mask = missing;
                    return;
                case 'not_missing'
                    mask = ~missing;
                    return;
            end
            if ismember(op,{'lt','le','gt','ge'})
                [values, ok] = NMDataIOTableReadTools.filterNumericValues(col, missing);
                target = str2double(strtrim(criterion));
                if ~ok || ~isfinite(target)
                    error('NMDataIOTableReadTools:filterNumericCriterion', ...
                        'Filter %s.%s uses operator %s but the column/criterion is not numeric.',sourceLabel,column,op);
                end
                switch op
                    case 'lt', mask = values < target;
                    case 'le', mask = values <= target;
                    case 'gt', mask = values > target;
                    otherwise, mask = values >= target;
                end
                mask(missing) = false;
                return;
            end
            if isnumeric(col) || islogical(col)
                target = str2double(strtrim(criterion));
                numericCriterion = isfinite(target);
            else
                target = NaN;
                numericCriterion = false;
            end
            if ismember(op,{'eq','ne'}) && numericCriterion
                values = double(col(:));
                mask = values == target;
                mask(missing) = false;
                if strcmp(op,'ne'), mask = ~mask & ~missing; end
                return;
            end
            values = NMDataIOTableReadTools.filterTextValues(col);
            if ~caseSensitive
                values = lower(values);
                criterionCmp = lower(string(criterion));
            else
                criterionCmp = string(criterion);
            end
            switch op
                case 'eq'
                    mask = values == criterionCmp;
                case 'ne'
                    mask = values ~= criterionCmp;
                case 'contains'
                    mask = contains(values,criterionCmp);
                case 'not_contains'
                    mask = ~contains(values,criterionCmp);
                case {'in','not_in'}
                    tokens = regexp(char(criterion),'[,;\n]','split');
                    tokens = strtrim(tokens); tokens = tokens(~cellfun(@isempty,tokens));
                    tokenStrings = string(tokens);
                    if ~caseSensitive, tokenStrings = lower(tokenStrings); end
                    mask = ismember(values,tokenStrings);
                    if strcmp(op,'not_in'), mask = ~mask; end
                otherwise
                    error('NMDataIOTableReadTools:filterOperator','Unsupported row-filter operator ''%s'' for %s.%s.',op,sourceLabel,column);
            end
            mask = logical(mask(:));
            mask(missing) = false;
        end

        function missing = filterMissingMask(col)
            % filterMissingMask  Identify intrinsic tabular missing values independently of user token mapping.
            if isnumeric(col)
                missing = isnan(col(:));
            elseif islogical(col)
                missing = false(numel(col),1);
            elseif isstring(col)
                x = col(:); missing = ismissing(x) | strlength(x)==0;
            elseif iscategorical(col) || isdatetime(col) || isduration(col)
                missing = ismissing(col(:));
            elseif iscell(col)
                missing = false(numel(col),1);
                for i = 1:numel(col)
                    x = col{i};
                    if isempty(x)
                        missing(i)=true;
                    elseif isnumeric(x)
                        missing(i)=isscalar(x) && isnan(x);
                    elseif isstring(x)
                        missing(i)=isempty(x) || ismissing(x(1)) || strlength(x(1))==0;
                    elseif ischar(x)
                        missing(i)=isempty(x);
                    else
                        try, q=ismissing(x); missing(i)=all(q(:)); catch, missing(i)=false; end
                    end
                end
            else
                try, missing = ismissing(col(:)); catch, missing = false(numel(col),1); end
            end
            missing = logical(missing(:));
        end

        function [values, ok] = filterNumericValues(col, missing)
            % filterNumericValues  Convert non-missing filter values to finite numeric values for ordered comparisons.
            if isnumeric(col) || islogical(col)
                values = double(col(:));
                ok = all(isfinite(values(~missing)));
                return;
            end
            txt = NMDataIOTableReadTools.filterTextValues(col);
            values = str2double(txt);
            ok = all(isfinite(values(~missing)));
        end

        function values = filterTextValues(col)
            % filterTextValues  Convert heterogeneous tabular values to one string value per row.
            if isstring(col)
                values = col(:);
            elseif ischar(col)
                values = string(cellstr(col));
            elseif isnumeric(col) || islogical(col) || iscategorical(col) || isdatetime(col) || isduration(col)
                values = string(col(:));
            elseif iscell(col)
                values = strings(numel(col),1);
                for i = 1:numel(col)
                    x = col{i};
                    if isempty(x)
                        values(i) = "";
                    elseif ischar(x)
                        values(i) = string(x);
                    elseif isstring(x)
                        values(i) = x(1);
                    elseif isnumeric(x) || islogical(x)
                        if isscalar(x), values(i)=string(x); else, values(i)=string(mat2str(x)); end
                    else
                        try, values(i)=string(x); catch, values(i)=string(class(x)); end
                    end
                end
            else
                try, values = string(col(:)); catch, error('NMDataIOTableReadTools:filterColumnType','Unsupported filter-column class: %s.',class(col)); end
            end
            values = values(:);
        end

        function tf = isUnknown(v)
            % isUnknown  Apply the local DataIO unknown/empty sentinel test.
            %
            % V -> tf.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(v), tf = true; return; end
            if ischar(v) || isa(v,'string')
                tf = strcmp(char(string(v)), '?') || isempty(strtrim(char(string(v))));
            else
                tf = false;
            end
        end

        function v = fieldOr(s, name, defaultValue)
            % fieldOr  Read a struct field with a caller-specific default when the field is absent or empty.
            %
            % Consumes s, name, defaultValue; returns v.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
                v = s.(name);
            else
                v = defaultValue;
            end
        end

        function v = opt(opts, name, defaultValue)
            % opt  Read an option field with a caller-specific default without changing option semantics.
            %
            % Consumes opts, name, defaultValue; returns v.
            % It is used before role resolution so original headers, internal aliases, and cached table content remain synchronized.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isstruct(opts) && isfield(opts,name) && ~isempty(opts.(name))
                v = opts.(name);
            else
                v = defaultValue;
            end
        end
    end
end

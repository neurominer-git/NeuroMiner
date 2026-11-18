classdef NMDataIODatabaseTools
% NMDataIODatabaseTools
% -------------------------------------------------------------------------
% Purpose / authority:
%   Database retrieval and type-conversion boundary for DataIO.
%
% Connector capability is reported only for execution paths implemented here. SQLite may use
% MATLAB's sqlite interface; server databases use implemented DB-API adapters through MATLAB's
% built-in Python interface. Typed Python values are converted once at this connector boundary.
%
% Scientific invariant:
%   Database-specific code ends after discovery/retrieval/type conversion. Filtering, scientific
%   roles, keys, alignment, label mapping, Preview/QC and Commit are generic tabular DataIO.
%   Credentials and live namespace catalogues are transient session state and are never persisted.
% -------------------------------------------------------------------------

    methods (Static)
        function caps = capabilities(opts)
            % capabilities  Report whether database functionality is available for the requested connector options.
            %
            % Opts -> caps.
            % It abstracts database-specific access so the remaining DataIO code can operate on MATLAB tables.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 1 || isempty(opts), opts = struct(); end %#ok<INUSD>
            caps = struct();
            caps.generatedAt = datestr(now,30);
            caps.matlab = NMDataIODatabaseTools.matlabCapabilities();
            caps.python = NMDataIODatabaseTools.pythonCapabilities();
            caps.connectors = NMDataIODatabaseTools.connectorCapabilities(caps);
            caps.ok = false;
            f = fieldnames(caps.connectors);
            for i = 1:numel(f)
                caps.ok = caps.ok || caps.connectors.(f{i}).available;
            end
            caps.blocking = ~caps.ok;
            if caps.ok
                caps.message = NMDataIODatabaseTools.capabilityMessage(caps);
            else
                caps.message = ['Database import is unavailable. Enable MATLAB SQLite support for SQLite files ' ...
                    'or configure Python with an implemented DB-API adapter for the selected server connector.'];
            end
        end

        function out = listNamespaces(IO, kind, opts)
            % listNamespaces  Discover connector-native database or schema namespaces.
            %
            % Only connector metadata is inspected here. Scientific row filtering, matching and
            % reconciliation remain downstream generic tabular responsibilities.
            if nargin < 2 || isempty(kind), kind = 'database'; end
            if nargin < 3 || isempty(opts), opts = struct(); end %#ok<INUSD>
            info = NMDataIODatabaseTools.connectionInfo(IO);
            support = NMDataIODatabaseTools.supportForConnector(info.connector);
            NMDataIODatabaseTools.assertSupported(info, support);
            kind = lower(strtrim(char(string(kind))));
            key = NMDataIODatabaseTools.connectorKey(info.connector);
            switch kind
                case 'database'
                    if ~ismember(key, {'mysql','postgresql'})
                        error('NMDataIODatabaseTools:databaseDiscoveryUnsupported', ...
                            'Connector ''%s'' does not expose a separate database-selection hierarchy.', info.connector);
                    end
                    T = NMDataIODatabaseTools.pythonDatabaseOperation(info, support, 'list_databases', '');
                case 'schema'
                    if ~strcmp(key, 'postgresql')
                        error('NMDataIODatabaseTools:schemaDiscoveryUnsupported', ...
                            'Connector ''%s'' does not expose a separate schema-selection hierarchy.', info.connector);
                    end
                    if NMDataIODatabaseTools.isUnknown(info.database)
                        error('NMDataIODatabaseTools:missingDatabase', 'Select a PostgreSQL database before discovering schemas.');
                    end
                    T = NMDataIODatabaseTools.pythonDatabaseOperation(info, support, 'list_schemas', '');
                otherwise
                    error('NMDataIODatabaseTools:invalidNamespaceKind', 'Unknown database selection level ''%s''.', kind);
            end
            names = NMDataIODatabaseTools.asCellstr(NMDataIODatabaseTools.tableColumn(T,'name'));
            out = struct('ok', true, 'connector', info.connector, 'backend', support.backend, ...
                'kind', kind, 'names', {names}, 'entries', {{}});
            for i = 1:numel(names)
                out.entries{end+1,1} = struct('name', names{i}, 'type', kind); %#ok<AGROW>
            end
        end

        function out = listTables(IO, opts)
            % listTables  List table/view objects using connector metadata rather than row retrieval.
            %
            % IO, opts -> out.
            % It abstracts database-specific access so the remaining DataIO code can operate on MATLAB tables.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2 || isempty(opts), opts = struct(); end %#ok<INUSD>
            info = NMDataIODatabaseTools.connectionInfo(IO);
            support = NMDataIODatabaseTools.supportForConnector(info.connector);
            NMDataIODatabaseTools.assertSupported(info, support);
            key = NMDataIODatabaseTools.connectorKey(info.connector);
            if strcmp(key,'mysql') && NMDataIODatabaseTools.isUnknown(info.database)
                error('NMDataIODatabaseTools:missingDatabase', 'Select a MySQL/MariaDB database before listing tables/views.');
            elseif strcmp(key,'postgresql')
                if NMDataIODatabaseTools.isUnknown(info.database)
                    error('NMDataIODatabaseTools:missingDatabase', 'Select a PostgreSQL database before listing tables/views.');
                end
                if NMDataIODatabaseTools.isUnknown(info.schema)
                    error('NMDataIODatabaseTools:missingSchema', 'Select a PostgreSQL schema before listing tables/views.');
                end
            end
            if strcmp(support.backend, 'matlab_sqlite')
                T = NMDataIODatabaseTools.sqliteFetchMatlab(info.file, NMDataIODatabaseTools.listingSQL('sqlite_file'));
            else
                T = NMDataIODatabaseTools.pythonDatabaseOperation(info, support, 'list_tables', '');
            end
            out = struct('ok', true, 'connector', info.connector, 'backend', support.backend, ...
                'databaseFile', info.file, 'database', info.database, 'schema', info.schema, ...
                'tables', {{}}, 'views', {{}}, 'entries', {{}});
            if isempty(T), return; end
            names = NMDataIODatabaseTools.asCellstr(NMDataIODatabaseTools.tableColumn(T,'name'));
            types = lower(NMDataIODatabaseTools.asCellstr(NMDataIODatabaseTools.tableColumn(T,'type')));
            for i = 1:numel(names)
                out.entries{end+1,1} = struct('name', names{i}, 'type', types{i}); %#ok<AGROW>
                if strcmp(types{i}, 'view')
                    out.views{end+1,1} = names{i}; %#ok<AGROW>
                else
                    out.tables{end+1,1} = names{i}; %#ok<AGROW>
                end
            end
        end

        function out = listColumns(IO, opts)
            % listColumns  Return canonical database column/type/key metadata without reading scientific rows.
            if nargin < 2 || isempty(opts), opts = struct(); end
            info = NMDataIODatabaseTools.connectionInfo(IO);
            support = NMDataIODatabaseTools.supportForConnector(info.connector);
            NMDataIODatabaseTools.assertSupported(info, support);
            if NMDataIODatabaseTools.isUnknown(info.table)
                error('NMDataIODatabaseTools:missingTable', 'Select a database table/view before discovering columns.');
            end
            key = NMDataIODatabaseTools.connectorKey(info.connector);
            if strcmp(key,'mysql') && NMDataIODatabaseTools.isUnknown(info.database)
                error('NMDataIODatabaseTools:missingDatabase', 'Select a MySQL/MariaDB database before discovering columns.');
            elseif strcmp(key,'postgresql') && (NMDataIODatabaseTools.isUnknown(info.database) || NMDataIODatabaseTools.isUnknown(info.schema))
                error('NMDataIODatabaseTools:missingNamespace', 'Select both PostgreSQL database and schema before discovering columns.');
            end
            rowCount = NaN;
            includeRowCount = logical(NMDataIODatabaseTools.opt(opts,'IncludeRowCount',false));
            if strcmp(support.backend, 'matlab_sqlite')
                % SQLite column metadata is resolved by the helper through PRAGMA table_info; no scientific rows are read.
                [T, keyRows] = NMDataIODatabaseTools.sqliteObjectMetadataMatlab(info);
            else
                describeOperation = 'describe_columns';
                if includeRowCount, describeOperation = 'describe_object'; end
                [T, description] = NMDataIODatabaseTools.pythonDatabaseOperation(info, support, describeOperation, '');
                keyRows = description.keyRows;
                if includeRowCount, rowCount = description.rowCount; end
            end
            out = NMDataIODatabaseTools.buildColumnMetadata(info, support, T, keyRows, rowCount);
        end

        function nRows = countRows(IO)
            % countRows  Return the exact row count for one ordinary database table/view without materializing rows.
            info = NMDataIODatabaseTools.connectionInfo(IO);
            support = NMDataIODatabaseTools.supportForConnector(info.connector);
            NMDataIODatabaseTools.assertSupported(info, support);
            if info.useQuery
                error('NMDataIODatabaseTools:queryRowCountUnsupported', ...
                    'Exact source-object row counts are defined for ordinary database tables/views, not expert custom SQL results.');
            end
            if NMDataIODatabaseTools.isUnknown(info.table)
                error('NMDataIODatabaseTools:missingTable', 'Select a database table/view before requesting its exact row count.');
            end
            if strcmp(support.backend, 'matlab_sqlite')
                ident = NMDataIODatabaseTools.quoteIdentifier(info.table, 'sqlite_file');
                T = NMDataIODatabaseTools.sqliteFetchMatlab(info.file, sprintf('SELECT COUNT(*) AS row_count FROM %s', ident));
            else
                T = NMDataIODatabaseTools.pythonDatabaseOperation(info, support, 'count_rows', '');
            end
            raw = NMDataIODatabaseTools.tableColumn(T, 'row_count');
            nRows = NMDataIODatabaseTools.scalarNumber(raw, 1, NaN);
            if ~(isscalar(nRows) && isfinite(nRows) && nRows >= 0 && nRows == round(nRows))
                error('NMDataIODatabaseTools:invalidRowCount', ...
                    'Database table/view %s returned an invalid exact row count.', info.table);
            end
            nRows = double(nRows);
        end

        function h = probeHeaders(IO, opts)
            % probeHeaders  Discover canonical database source objects and columns without reading scientific rows.
            %
            % Ordinary database tables/views are exposed as independent tabular source objects so the
            % generic role/filter/alignment machinery operates unchanged. Expert custom SQL remains one
            % explicit result object because its result-set schema is already defined by the query.
            if nargin < 2 || isempty(opts), opts = struct(); end %#ok<INUSD>
            h = struct('ok', false, 'message', '', 'sheets', {{}}, 'selectedSheets', {{}}, 'sheet', '', ...
                'headerRow', [], 'headerRows', [], 'headerRowAutoDetected', false, 'columns', {{}}, ...
                'rawColumns', {{}}, 'internalColumns', {{}}, 'columnSources', {{}}, 'commonColumns', {{}}, ...
                'nColumns', 0, 'nPreviewRows', 0, 'diagnostics', {{}}, ...
                'sourceVariables', struct('id',{},'name',{},'sourceType',{},'sourcePath',{},'sourceObject',{},'sourceName',{},'sourceLabel',{},'columnName',{},'class',{},'size',{},'headerRow',{},'delimit',{},'groupmode',{}), ...
                'columnMetadata', {{}}, 'keyMetadata', struct('primary',{{}},'unique',{{}},'foreign',{{}}), ...
                'sourceIdentity', struct(), 'sourceObjectMetadata', {{}}, 'performance', struct());
            try
                info = NMDataIODatabaseTools.connectionInfo(IO);
                if info.useQuery
                    support = NMDataIODatabaseTools.supportForConnector(info.connector);
                    NMDataIODatabaseTools.assertSupported(info, support);
                    sql = NMDataIODatabaseTools.queryFromIO(IO);
                    NMDataIODatabaseTools.assertReadOnlyQuery(sql);
                    sql = NMDataIODatabaseTools.zeroRowQuery(sql);
                    if strcmp(support.backend, 'matlab_sqlite')
                        T = NMDataIODatabaseTools.sqliteFetchMatlab(info.file, sql);
                    else
                        T = NMDataIODatabaseTools.pythonDatabaseOperation(info, support, 'fetch', sql);
                    end
                    names = NMDataIODatabaseTools.originalColumnNames(T);
                    sourcePath = info.file;
                    if isempty(sourcePath), sourcePath = info.url; end
                    sourceRecords = cell(numel(names),1);
                    for c = 1:numel(names)
                        nm = names{c};
                        id = sprintf('database|query|%s|%s', sourcePath, nm);
                        sourceRecords{c} = struct('id',id,'name',nm,'sourceType','database','sourcePath',sourcePath, ...
                            'sourceObject','__custom_query__','sourceName','','sourceLabel','custom SQL query','columnName',nm, ...
                            'class','unknown','size',[0 1],'headerRow',[],'delimit','','groupmode',6);
                    end
                    if ~isempty(sourceRecords), h.sourceVariables = vertcat(sourceRecords{:}); end
                    h.sheets = {'__custom_query__'};
                    h.selectedSheets = h.sheets;
                    h.sheet = h.sheets{1};
                    h.rawColumns = names;
                    h.columns = names;
                    h.internalColumns = T.Properties.VariableNames;
                    h.columnSources = repmat({'custom SQL query'},1,numel(names));
                    h.commonColumns = names;
                    h.message = sprintf('Detected %g custom-query result column(s) without retrieving result rows.', numel(names));
                else
                    [catalogue, cataloguePerformance] = NMDataIODatabaseTools.catalogueMetadata(IO);
                    allObjects = cellfun(@(x) char(string(x.table)), catalogue, 'UniformOutput', false);
                    requested = NMDataIODatabaseTools.asCellstr(NMDataIODatabaseTools.pick(IO, {'sheets'}, {}));
                    requested = requested(~cellfun(@(x) isempty(strtrim(x)) || strcmp(strtrim(x),'?'), requested));
                    selected = requested;
                    missing = selected(~ismember(selected,allObjects));
                    if ~isempty(missing)
                        error('NMDataIODatabaseTools:unknownTableObject', ...
                            'Selected database table/view object(s) not found: %s', strjoin(missing, ', '));
                    end
                    selected = unique(selected,'stable');
                    sourcePath = info.file;
                    if isempty(sourcePath), sourcePath = info.url; end
                    sourceRecords = cell(0,1);
                    selectedIndices = [];
                    objectMetadata = cell(0,1);
                    selectedMetadataCaptured = false;
                    for oi = 1:numel(allObjects)
                        objectName = allObjects{oi};
                        meta = catalogue{oi};
                        nRows = double(NMDataIODatabaseTools.opt(meta,'rowCount',NaN));
                        if ~(isscalar(nRows) && isfinite(nRows) && nRows >= 0 && nRows == round(nRows))
                            error('NMDataIODatabaseTools:invalidRowCount', ...
                                'Database table/view %s returned an invalid exact row count during catalogue discovery.', objectName);
                        end
                        objectMetadata{end+1,1} = struct('name',objectName,'objectType',meta.objectType, ... %#ok<AGROW>
                            'identity',meta.identity,'columns',{meta.columns},'columnMetadata',{meta.entries},'keyMetadata',meta.keyMetadata,'rowCount',nRows);
                        firstIndex = numel(sourceRecords) + 1;
                        for c = 1:numel(meta.entries)
                            entry = meta.entries{c};
                            nm = char(string(entry.name));
                            id = sprintf('database|%s|%s|%s|%s|%s|%s', info.connector, sourcePath, info.database, info.schema, objectName, nm);
                            sourceRecords{end+1,1} = struct('id',id,'name',nm,'sourceType','database','sourcePath',sourcePath, ... %#ok<AGROW>
                                'sourceObject',objectName,'sourceName','','sourceLabel',objectName,'columnName',nm, ...
                                'class',char(string(entry.matlabType)),'size',[nRows 1],'headerRow',[],'delimit','','groupmode',6);
                        end
                        if ismember(objectName,selected)
                            selectedIndices = [selectedIndices firstIndex:numel(sourceRecords)]; %#ok<AGROW>
                            if ~selectedMetadataCaptured
                                h.columnMetadata = meta.entries;
                                h.keyMetadata = meta.keyMetadata;
                                h.sourceIdentity = meta.identity;
                                selectedMetadataCaptured = true;
                            end
                        end
                    end
                    if ~isempty(sourceRecords), vars = vertcat(sourceRecords{:}); else, vars = h.sourceVariables; end
                    h.sourceVariables = vars;
                    h.sheets = allObjects;
                    h.selectedSheets = selected;
                    if ~isempty(selected), h.sheet = selected{1}; end
                    h.sourceObjectMetadata = objectMetadata;
                    h.performance = cataloguePerformance;
                    selectedVars = vars(selectedIndices);
                    h.columns = {selectedVars.name};
                    h.rawColumns = h.columns;
                    h.internalColumns = h.columns;
                    h.columnSources = {selectedVars.sourceLabel};
                    if isempty(selected)
                        h.commonColumns = {};
                    else
                        common = {vars(strcmp({vars.sourceObject},selected{1})).name};
                        common = unique(common,'stable');
                        for i = 2:numel(selected)
                            local = {vars(strcmp({vars.sourceObject},selected{i})).name};
                            common = common(ismember(common,local));
                        end
                        h.commonColumns = common;
                    end
                    h.message = sprintf('Detected %g column source(s) across %g database table/view object(s); %g object(s) selected for browsing.', ...
                        numel(vars), numel(allObjects), numel(selected));
                end
                h.nColumns = numel(h.columns);
                h.nPreviewRows = 0;
                h.ok = ~isempty(h.sourceVariables);
            catch ME
                h.ok = false;
                h.message = ME.message;
                h.identifier = ME.identifier;
            end
        end

        function T = readResultTable(IO, opts)
            % readResultTable  Retrieve a database result using canonical metadata and selective normal-table projection.
            %
            % opts.Columns: exact database column names for normal table/view retrieval. Empty means all catalogue columns.
            % opts.MaxRows: positive finite row cap for preview/diagnostic retrieval; Inf means no cap.
            if nargin < 2 || isempty(opts), opts = struct(); end
            info = NMDataIODatabaseTools.connectionInfo(IO);
            support = NMDataIODatabaseTools.supportForConnector(info.connector);
            NMDataIODatabaseTools.assertSupported(info, support);
            maxRows = NMDataIODatabaseTools.opt(opts, 'MaxRows', Inf);
            if ~(isscalar(maxRows) && isnumeric(maxRows) && isreal(maxRows) && (isinf(maxRows) || (isfinite(maxRows) && maxRows > 0)))
                error('NMDataIODatabaseTools:invalidMaxRows', 'MaxRows must be a positive finite scalar or Inf.');
            end
            if info.useQuery
                if isfield(opts,'Columns') && ~isempty(opts.Columns)
                    error('NMDataIODatabaseTools:customQuerySelectiveColumns', ...
                        'Selective Columns are defined for ordinary table/view retrieval, not expert custom SQL results.');
                end
                sql = NMDataIODatabaseTools.queryFromIO(IO);
                NMDataIODatabaseTools.assertReadOnlyQuery(sql);
                if strcmp(support.backend, 'matlab_sqlite')
                    if isfinite(maxRows), sql = NMDataIODatabaseTools.limitQuery(sql, maxRows); end
                    T = NMDataIODatabaseTools.sqliteFetchMatlab(info.file, sql);
                else
                    opOpts = struct('MaxRows', maxRows);
                    T = NMDataIODatabaseTools.pythonDatabaseOperation(info, support, 'fetch', sql, opOpts);
                end
                if ~istable(T)
                    error('NMDataIODatabaseTools:notTable', 'Database query did not return a MATLAB table. Returned class: %s.', class(T));
                end
                T = NMDataIODatabaseTools.attachOriginalColumnNames(T, NMDataIODatabaseTools.originalColumnNames(T));
                return;
            end

            meta = NMDataIODatabaseTools.listColumns(IO, struct());
            requested = NMDataIODatabaseTools.opt(opts, 'Columns', {});
            selected = NMDataIODatabaseTools.selectColumnMetadata(meta, requested);
            unsupportedBinary = cellfun(@(x) strcmp(x.matlabType,'unsupported_binary'), selected);
            if any(unsupportedBinary)
                blocked = cellfun(@(x) x.name, selected(unsupportedBinary), 'UniformOutput', false);
                error('NMDataIODatabaseTools:binaryRetrievalUnsupported', ...
                    'Database binary column(s) cannot currently be imported without data loss: %s.', strjoin(blocked, ', '));
            end
            columnNames = cellfun(@(x) x.name, selected, 'UniformOutput', false);
            transportTextColumns = cellfun(@(x) strcmp(x.matlabType,'string'), selected);
            textColumns = columnNames(transportTextColumns);
            if strcmp(support.backend, 'matlab_sqlite')
                sql = NMDataIODatabaseTools.tableSelectSQL(info, columnNames, maxRows, textColumns);
                T = NMDataIODatabaseTools.sqliteFetchMatlab(info.file, sql);
            else
                matlabTypes = cellfun(@(x) char(string(x.matlabType)), selected, 'UniformOutput', false);
                opOpts = struct('Columns', {columnNames}, 'TextColumns', {textColumns}, ...
                    'MatlabTypes', {matlabTypes}, 'MaxRows', maxRows);
                T = NMDataIODatabaseTools.pythonDatabaseOperation(info, support, 'fetch_table', '', opOpts);
            end
            if ~istable(T)
                error('NMDataIODatabaseTools:notTable', 'Database retrieval did not return a MATLAB table. Returned class: %s.', class(T));
            end
            T = NMDataIODatabaseTools.attachOriginalColumnNames(T, columnNames);
            T = NMDataIODatabaseTools.coerceResultTypes(T, selected);
        end

        function names = originalColumnNames(T)
            % originalColumnNames  Recover original database/table column names from table properties.
            %
            % T -> names.
            % It abstracts database-specific access so the remaining DataIO code can operate on MATLAB tables.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if exist('NMDataIOTableReadTools','class') == 8 || exist('NMDataIOTableReadTools','file') == 2
                names = NMDataIOTableReadTools.originalColumnNames(T);
            else
                names = T.Properties.VariableNames(:)';
            end
        end

        function T = attachOriginalColumnNames(T, originalNames)
            % attachOriginalColumnNames  Attach original database/table column names to a MATLAB table after aliasing.
            %
            % T, originalNames -> T.
            % It abstracts database-specific access so the remaining DataIO code can operate on MATLAB tables.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if exist('NMDataIOTableReadTools','class') == 8 || exist('NMDataIOTableReadTools','file') == 2
                T = NMDataIOTableReadTools.attachOriginalColumnNames(T, originalNames);
            else
                originalNames = NMDataIODatabaseTools.asCellstr(originalNames);
                T.Properties.VariableDescriptions = originalNames(:)';
            end
        end

        function info = connectionInfo(IO)
            % connectionInfo  Build the transient database connection description used for one connector operation.
            %
            % IO -> info.
            % It abstracts database-specific access so the remaining DataIO code can operate on MATLAB tables.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 1 || isempty(IO), IO = struct(); end
            info = struct();
            info.connector = lower(strtrim(NMDataIODatabaseTools.toChar(NMDataIODatabaseTools.pick(IO, {'databaseConnector','connector','databaseType'}, 'sqlite_file'))));
            if isempty(info.connector) || strcmp(info.connector,'?'), info.connector = 'sqlite_file'; end
            info.connector = NMDataIODatabaseTools.connectorKey(info.connector);
            info.file = NMDataIODatabaseTools.toChar(NMDataIODatabaseTools.pick(IO, {'databaseFile','dbFile'}, ''));
            info.url = NMDataIODatabaseTools.toChar(NMDataIODatabaseTools.pick(IO, {'databaseUrl','dbUrl','jdbcUrl'}, ''));
            info.user = NMDataIODatabaseTools.toChar(NMDataIODatabaseTools.pick(IO, {'databaseUser','dbUser'}, ''));
            info.password = NMDataIODatabaseTools.toChar(NMDataIODatabaseTools.pick(IO, {'databasePassword','dbPassword'}, ''));
            if NMDataIODatabaseTools.isUnknown(info.user), info.user = ''; end
            if NMDataIODatabaseTools.isUnknown(info.password), info.password = ''; end
            info.database = NMDataIODatabaseTools.toChar(NMDataIODatabaseTools.pick(IO, {'databaseName','database','dbName'}, ''));
            info.schema = NMDataIODatabaseTools.toChar(NMDataIODatabaseTools.pick(IO, {'databaseSchema','schema','dbSchema'}, ''));
            if NMDataIODatabaseTools.isUnknown(info.database), info.database = ''; end
            if NMDataIODatabaseTools.isUnknown(info.schema), info.schema = ''; end
            switch info.connector
                case 'sqlite_file'
                    info.database = '';
                    info.schema = '';
                case 'mysql'
                    info.schema = '';
                case {'odbc_dsn','jdbc_url'}
                    info.database = '';
                    info.schema = '';
            end
            info.table = NMDataIODatabaseTools.toChar(NMDataIODatabaseTools.pick(IO, {'databaseTable','dbTable'}, ''));
            info.useQuery = logical(NMDataIODatabaseTools.pick(IO, {'databaseUseQuery','dbUseQuery'}, false));
            info.query = NMDataIODatabaseTools.toChar(NMDataIODatabaseTools.pick(IO, {'databaseQuery','sqlQuery','query'}, ''));
            if NMDataIODatabaseTools.isUnknown(info.file) && ~NMDataIODatabaseTools.isUnknown(info.url) && startsWith(lower(info.url), 'sqlite:')
                info.file = regexprep(info.url, '^sqlite:(//)?', '');
            end
            NMDataIODatabaseTools.assertCredentialSeparation(info);
        end

        function sql = queryFromIO(IO)
            % queryFromIO  Derive explicit read-only SQL for a database-backed DataIO source.
            info = NMDataIODatabaseTools.connectionInfo(IO);
            if info.useQuery
                sql = NMDataIODatabaseTools.stripTrailingSemicolon(strtrim(info.query));
                if NMDataIODatabaseTools.isUnknown(sql)
                    error('NMDataIODatabaseTools:missingQuery', 'Custom SQL query is enabled but the SQL query field is empty.');
                end
            else
                if NMDataIODatabaseTools.isUnknown(info.table)
                    error('NMDataIODatabaseTools:missingTable', 'Select a database table/view or enable a custom SQL query.');
                end
                meta = NMDataIODatabaseTools.listColumns(IO, struct());
                sql = NMDataIODatabaseTools.tableSelectSQL(info, meta.columns, Inf);
            end
        end

        function desc = queryDescription(IO)
            % queryDescription  Return a compact human-readable description of the database source query/table.
            %
            % IO -> desc.
            % It abstracts database-specific access so the remaining DataIO code can operate on MATLAB tables.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            info = NMDataIODatabaseTools.connectionInfo(IO);
            if info.useQuery
                desc = 'custom SQL query';
            else
                desc = sprintf('table/view ''%s''', info.table);
            end
        end
    end

    methods (Static, Access = private)
        function caps = matlabCapabilities()
            caps = struct();
            caps.sqlite = exist('sqlite','file') == 2 || exist('sqlite','class') == 8;
            caps.databaseFunction = exist('database','file') == 2;
            caps.databaseToolboxLicense = false;
            try
                caps.databaseToolboxLicense = license('test','database_toolbox');
            catch ME %#ok<NASGU>
            end
        end

        function caps = pythonCapabilities()
            % pythonCapabilities  Inspect the Python environment used by MATLAB's built-in Python interface.
            caps = struct();
            caps.available = false;
            caps.executable = '';
            caps.modules = struct('sqlite3',false,'psycopg',false,'psycopg2',false, ...
                'pymysql',false,'mysql_connector',false,'MySQLdb',false,'mariadb',false, ...
                'pyodbc',false);
            try
                env = pyenv;
                caps.executable = char(string(env.Executable));
                py.importlib.import_module('sys');
                caps.available = true;
            catch ME
                caps.message = sprintf('MATLAB Python interface is unavailable: %s', ME.message);
                return;
            end
            caps.moduleDiagnostics = struct();
            mods = {'sqlite3','psycopg','psycopg2','pymysql','mysql.connector','MySQLdb','mariadb','pyodbc'};
            for i = 1:numel(mods)
                field = strrep(mods{i},'.','_');
                [caps.modules.(field), caps.moduleDiagnostics.(field)] = NMDataIODatabaseTools.pythonHasModule(mods{i});
            end
        end

        function conns = connectorCapabilities(caps)
            conns = struct();
            if caps.python.available
                pythonUnavailable = '';
            else
                pythonUnavailable = NMDataIODatabaseTools.pick(caps.python, {'message'}, ...
                    'MATLAB Python interface is unavailable.');
            end
            sqliteReason = '';
            if ~(caps.matlab.sqlite || caps.python.modules.sqlite3), sqliteReason = pythonUnavailable; end
            postgresReason = pythonUnavailable;
            if caps.python.available
                postgresReason = 'Install psycopg/psycopg2 in the Python environment configured in MATLAB.';
            end
            mysqlReason = pythonUnavailable;
            if caps.python.available
                mysqlReason = 'Install pymysql, mysql.connector, MySQLdb, or mariadb in the Python environment configured in MATLAB.';
            end
            odbcReason = pythonUnavailable;
            if caps.python.available, odbcReason = 'Install pyodbc in the Python environment configured in MATLAB.'; end
            conns.sqlite_file = NMDataIODatabaseTools.connectorStatus(caps.matlab.sqlite || caps.python.modules.sqlite3, ...
                NMDataIODatabaseTools.backendName(caps,'sqlite_file'), 'SQLite file', sqliteReason);
            conns.postgresql = NMDataIODatabaseTools.connectorStatus(caps.python.modules.psycopg || caps.python.modules.psycopg2, ...
                NMDataIODatabaseTools.backendName(caps,'postgresql'), 'PostgreSQL', postgresReason);
            conns.mysql = NMDataIODatabaseTools.connectorStatus(caps.python.modules.pymysql || caps.python.modules.mysql_connector || caps.python.modules.MySQLdb || caps.python.modules.mariadb, ...
                NMDataIODatabaseTools.backendName(caps,'mysql'), 'MySQL / MariaDB', mysqlReason);
            conns.odbc_dsn = NMDataIODatabaseTools.connectorStatus(caps.python.modules.pyodbc, ...
                NMDataIODatabaseTools.backendName(caps,'odbc_dsn'), 'ODBC DSN', odbcReason);
            conns.jdbc_url = NMDataIODatabaseTools.connectorStatus(false, 'unavailable', 'JDBC URL', ...
                'JDBC execution is not implemented by the current database connector and is intentionally disabled.');
            conns.sqlite_file.hierarchy = {'object'};
            conns.mysql.hierarchy = {'database','object'};
            conns.postgresql.hierarchy = {'database','schema','object'};
            conns.odbc_dsn.hierarchy = {'object'};
            conns.jdbc_url.hierarchy = {};
        end

        function s = connectorStatus(available, backend, label, reason)
            if nargin < 4, reason = ''; end
            s = struct('available', logical(available), 'backend', backend, 'label', label, 'reason', reason);
        end

        function b = backendName(caps, connector)
            b = 'unavailable';
            switch connector
                case 'sqlite_file'
                    if caps.matlab.sqlite, b = 'matlab_sqlite'; elseif caps.python.modules.sqlite3, b = 'python_sqlite3'; end
                case 'postgresql'
                    if caps.python.modules.psycopg, b = 'python_psycopg'; elseif caps.python.modules.psycopg2, b = 'python_psycopg2'; end
                case 'mysql'
                    if caps.python.modules.pymysql, b = 'python_pymysql'; elseif caps.python.modules.mysql_connector, b = 'python_mysql_connector'; elseif caps.python.modules.MySQLdb, b = 'python_MySQLdb'; elseif caps.python.modules.mariadb, b = 'python_mariadb'; end
                case 'odbc_dsn'
                    if caps.python.modules.pyodbc, b = 'python_pyodbc'; end
                case 'jdbc_url'
                    b = 'unavailable';
            end
        end

        function msg = capabilityMessage(caps)
            parts = {};
            names = fieldnames(caps.connectors);
            for i = 1:numel(names)
                s = caps.connectors.(names{i});
                if s.available
                    parts{end+1} = sprintf('%s via %s', s.label, strrep(s.backend,'_',' ')); %#ok<AGROW>
                end
            end
            msg = ['Database import capability detected: ' strjoin(parts, '; ') '.'];
        end

        function support = supportForConnector(connector)
            caps = NMDataIODatabaseTools.capabilities();
            key = NMDataIODatabaseTools.connectorKey(connector);
            if isfield(caps.connectors, key)
                support = caps.connectors.(key);
            else
                support = struct('available',false,'backend','unavailable','label',connector,'reason','Unknown database connector.');
            end
        end

        function key = connectorKey(connector)
            c = lower(strtrim(char(string(connector))));
            switch c
                case {'sqlite','sqlite_file','sqlitefile'}, key = 'sqlite_file';
                case {'postgres','postgresql'}, key = 'postgresql';
                case {'mysql','mariadb','mysql_mariadb'}, key = 'mysql';
                case {'odbc','odbc_dsn','dsn'}, key = 'odbc_dsn';
                case {'jdbc','jdbc_url'}, key = 'jdbc_url';
                otherwise, key = c;
            end
        end

        function assertSupported(info, support)
            key = NMDataIODatabaseTools.connectorKey(info.connector);
            if ~support.available
                reason = NMDataIODatabaseTools.pick(support, {'reason'}, 'No supported database connection method is available in this MATLAB installation.');
                error('NMDataIODatabaseTools:connectorUnavailable', 'Database connector ''%s'' is unavailable. %s', info.connector, reason);
            end
            if strcmp(key,'sqlite_file')
                if NMDataIODatabaseTools.isUnknown(info.file)
                    error('NMDataIODatabaseTools:missingSQLiteFile', 'Select a SQLite database file before probing or importing.');
                end
                if exist(info.file,'file') ~= 2
                    error('NMDataIODatabaseTools:sqliteFileMissing', 'SQLite database file does not exist: %s', info.file);
                end
            elseif NMDataIODatabaseTools.isUnknown(info.url)
                error('NMDataIODatabaseTools:missingConnectionString', 'Enter a database URL / DSN / connection string for connector ''%s''.', info.connector);
            end
        end

        function assertCredentialSeparation(info)
            url = strtrim(char(string(info.url)));
            if ~isempty(regexp(url, '^[A-Za-z][A-Za-z0-9+.-]*://[^/@]*:[^/@]*@', 'once'))
                error('NMDataIODatabaseTools:embeddedCredential', ...
                    'Do not embed database passwords in the connection URL. Use the transient Password field instead.');
            end
            if ~isempty(regexpi(url, '(^|;)\s*(pwd|password)\s*=', 'once'))
                error('NMDataIODatabaseTools:embeddedCredential', ...
                    'Do not embed ODBC passwords in the DSN/connection string. Use the transient Password field instead.');
            end
        end

        function T = sqliteFetchMatlab(dbFile, sql)
            conn = sqlite(dbFile, 'readonly');
            cleaner = onCleanup(@() NMDataIODatabaseTools.closeConnection(conn)); %#ok<NASGU>
            T = fetch(conn, sql);
        end

        function [T, detail] = pythonDatabaseOperation(info, support, operation, sql, opOpts)
            % pythonDatabaseOperation  Execute one DB-API operation through MATLAB's native Python interface.
            %
            % Result rows remain typed Python objects until MATLAB converts them at this single boundary.
            % No CSV/JSON result serialization, temporary connector subprocess, or type re-inference is used.
            if nargin < 5 || isempty(opOpts), opOpts = struct(); end
            detail = struct();
            if ~startsWith(support.backend,'python_')
                error('NMDataIODatabaseTools:pythonBackendContract', ...
                    'The selected database connection method (%s) is not available through the configured MATLAB-Python connection. Check the MATLAB Python configuration or choose another supported connector.', support.backend);
            end
            columns = NMDataIODatabaseTools.pythonStringListInput( ...
                NMDataIODatabaseTools.opt(opOpts, 'Columns', {}));
            textColumns = NMDataIODatabaseTools.pythonStringListInput( ...
                NMDataIODatabaseTools.opt(opOpts, 'TextColumns', {}));
            matlabTypes = NMDataIODatabaseTools.asCellstr(NMDataIODatabaseTools.opt(opOpts, 'MatlabTypes', {}));
            maxRows = NMDataIODatabaseTools.opt(opOpts, 'MaxRows', Inf);
            adapterPath = fullfile(fileparts(which('NMDataIODatabaseTools')), 'nm_dataio_database_adapter.py');
            if exist(adapterPath,'file') ~= 2
                error('NMDataIODatabaseTools:pythonAdapterMissing', ...
                    'Database Python adapter is missing: %s', adapterPath);
            end
            try
                result = pyrunfile(adapterPath, "result", ...
                    operation=string(operation), ...
                    connector=string(NMDataIODatabaseTools.connectorKey(info.connector)), ...
                    database_file=string(info.file), url=string(info.url), user=string(info.user), ...
                    password=string(info.password), database=string(info.database), schema=string(info.schema), ...
                    table_name=string(info.table), sql=string(sql), columns=columns, ...
                    text_columns=textColumns, max_rows=double(maxRows));
            catch ME
                msg = ME.message;
                if ~isempty(info.password), msg = strrep(msg, info.password, '<redacted>'); end
                error('NMDataIODatabaseTools:pythonDatabaseError', ...
                    'Database connection through MATLAB''s Python interface failed: %s', msg);
            end
            if strcmp(operation,'describe_catalogue')
                records = cell(result);
                catalogue = cell(numel(records),1);
                for i = 1:numel(records)
                    parts = cell(records{i});
                    if numel(parts) ~= 5
                        error('NMDataIODatabaseTools:pythonResultContract', ...
                            'The database connector returned an unexpected catalogue-description result structure.');
                    end
                    localInfo = info;
                    localInfo.table = char(string(parts{1}));
                    columnRows = NMDataIODatabaseTools.pythonResultTable(parts{3});
                    keyRows = NMDataIODatabaseTools.pythonResultTable(parts{4});
                    rowCount = double(parts{5});
                    catalogue{i} = NMDataIODatabaseTools.buildColumnMetadata(localInfo, support, columnRows, keyRows, rowCount);
                    catalogue{i}.objectType = char(string(parts{2}));
                    catalogue{i}.identity.objectType = catalogue{i}.objectType;
                end
                T = table();
                detail.catalogue = catalogue;
                detail.connectionCount = 1;
                return;
            elseif any(strcmp(operation,{'describe_columns','describe_object'}))
                parts = cell(result);
                expectedParts = 2 + strcmp(operation,'describe_object');
                if numel(parts) ~= expectedParts
                    error('NMDataIODatabaseTools:pythonResultContract', ...
                        'The database connector returned an unexpected object-description result structure.');
                end
                T = NMDataIODatabaseTools.pythonResultTable(parts{1});
                detail.keyRows = NMDataIODatabaseTools.pythonResultTable(parts{2});
                if strcmp(operation,'describe_object'), detail.rowCount = double(parts{3}); end
            else
                T = NMDataIODatabaseTools.pythonResultTable(result, matlabTypes);
            end
        end

        function T = pythonResultTable(result, matlabTypes)
            % pythonResultTable  Convert native Python rows column-wise at the MATLAB boundary.
            %
            % Ordinary table retrieval supplies the already resolved database type contract,
            % avoiding an interpreted MATLAB function call for every result value. Metadata and
            % expert-query results, which are small or lack a catalogue type contract, retain the
            % generic scalar converter as a conservative fallback.
            if nargin < 2 || isempty(matlabTypes), matlabTypes = {}; end
            parts = cell(result);
            if numel(parts) ~= 2
                error('NMDataIODatabaseTools:pythonResultContract', ...
                    'The database connector returned an unexpected result structure.');
            end
            names = NMDataIODatabaseTools.pythonStringList(parts{1});
            pyRows = cell(parts{2});
            nRows = numel(pyRows); nColumns = numel(names);
            data = cell(nRows,nColumns);
            if nRows > 0
                rowCells = cellfun(@(row) reshape(cell(row),1,[]), pyRows, 'UniformOutput', false);
                rowWidths = cellfun(@numel,rowCells);
                badRow = find(rowWidths ~= nColumns,1,'first');
                if ~isempty(badRow)
                    error('NMDataIODatabaseTools:pythonResultContract', ...
                        'The database connector returned a row with %g value(s), but %g columns were expected.', rowWidths(badRow), nColumns);
                end
                data = vertcat(rowCells{:});
                if ~isempty(matlabTypes) && numel(matlabTypes) ~= nColumns
                    error('NMDataIODatabaseTools:pythonResultContract', ...
                        'The database result has %g column(s), but %g resolved MATLAB type hint(s) were supplied.', nColumns, numel(matlabTypes));
                end
                for c = 1:nColumns
                    hint = '';
                    if ~isempty(matlabTypes), hint = matlabTypes{c}; end
                    data(:,c) = NMDataIODatabaseTools.pythonColumnToMatlab(data(:,c), hint);
                end
            end
            if exist('NMDataIOTableReadTools','class') == 8 || exist('NMDataIOTableReadTools','file') == 2
                T = NMDataIOTableReadTools.cell2tablePreserveHeaders(data, names);
            else
                internalNames = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(names));
                T = cell2table(data, 'VariableNames', internalNames);
            end
        end

        function out = pythonColumnToMatlab(raw, matlabType)
            % pythonColumnToMatlab  Convert one typed DB-API result column without a nested row/column loop.
            if nargin < 2, matlabType = ''; end
            raw = raw(:); out = cell(size(raw));
            if isempty(raw), return; end
            missing = cellfun(@(v) isempty(v) || isa(v,'py.NoneType'), raw);
            present = find(~missing);
            if isempty(present), return; end
            kind = lower(strtrim(char(string(matlabType))));
            switch kind
                case {'double','logical'}
                    try
                        values = cellfun(@double,raw(present));
                    catch
                        out(present) = cellfun(@(v) NMDataIODatabaseTools.pythonScalarToMatlab(v), ...
                            raw(present),'UniformOutput',false);
                        return;
                    end
                    if strcmp(kind,'logical'), values = logical(values); end
                    out(present) = num2cell(values(:));
                case 'string'
                    try
                        out(present) = cellfun(@char,raw(present),'UniformOutput',false);
                    catch
                        out(present) = cellfun(@(v) NMDataIODatabaseTools.pythonScalarToMatlab(v), ...
                            raw(present),'UniformOutput',false);
                    end
                otherwise
                    out(present) = cellfun(@(v) NMDataIODatabaseTools.pythonScalarToMatlab(v), ...
                        raw(present),'UniformOutput',false);
            end
        end

        function out = pythonStringListInput(value)
            % pythonStringListInput  Build an explicit Python list for pyrunfile sequence arguments.
            values = NMDataIODatabaseTools.asCellstr(value);
            out = py.list();
            for i = 1:numel(values)
                out.append(py.str(values{i}));
            end
        end

        function names = pythonStringList(value)
            items = cell(value);
            names = cell(numel(items),1);
            for i = 1:numel(items)
                item = NMDataIODatabaseTools.pythonScalarToMatlab(items{i});
                if ~((isstring(item) && isscalar(item)) || (ischar(item) && isrow(item)))
                    error('NMDataIODatabaseTools:pythonResultContract', ...
                        'The database connector returned an invalid column name (%s).', class(items{i}));
                end
                names{i} = char(item);
            end
            names = names(:)';
        end

        function value = pythonScalarToMatlab(sourceValue)
            % pythonScalarToMatlab  Normalize one DB-API scalar at the MATLAB/Python boundary.
            % MATLAB may already have converted Python float/bool/datetime values before they
            % reach this method. Native MATLAB scalar forms and remaining py.* objects are both
            % accepted here so downstream tabular code sees one deterministic representation.
            nativeScalar = (isa(sourceValue,'double') && isscalar(sourceValue) && isreal(sourceValue)) || ...
                (islogical(sourceValue) && isscalar(sourceValue)) || (isstring(sourceValue) && isscalar(sourceValue)) || ...
                (ischar(sourceValue) && isrow(sourceValue)) || (isdatetime(sourceValue) && isscalar(sourceValue)) || ...
                (isduration(sourceValue) && isscalar(sourceValue));
            if nativeScalar
                value = sourceValue;
            elseif isa(sourceValue,'py.NoneType')
                value = [];
            elseif isa(sourceValue,'py.bool')
                value = logical(sourceValue);
            elseif isa(sourceValue,'py.int')
                text = char(sourceValue);
                candidate = str2double(text);
                if isfinite(candidate) && abs(candidate) <= flintmax
                    value = candidate;
                else
                    value = text; % Preserve integers that cannot be represented exactly as MATLAB double.
                end
            elseif isa(sourceValue,'py.float')
                value = double(sourceValue);
            elseif isa(sourceValue,'py.str')
                value = char(sourceValue);
            elseif isa(sourceValue,'py.decimal.Decimal')
                value = char(sourceValue); % Preserve decimal representation until the database type contract is applied.
            elseif isa(sourceValue,'py.datetime.datetime')
                value = datetime(sourceValue);
            elseif isa(sourceValue,'py.datetime.date')
                value = datetime(char(sourceValue),'InputFormat','yyyy-MM-dd');
            elseif isa(sourceValue,'py.datetime.time')
                value = duration(double(sourceValue.hour), double(sourceValue.minute), ...
                    double(sourceValue.second) + double(sourceValue.microsecond)/1e6);
            elseif isa(sourceValue,'py.datetime.timedelta')
                value = seconds(double(sourceValue.total_seconds()));
            elseif isa(sourceValue,'py.bytes') || isa(sourceValue,'py.memoryview')
                error('NMDataIODatabaseTools:pythonBinaryUnsupported', ...
                    'The database returned a binary value of type %s, which NM2 cannot currently import without data loss.', class(sourceValue));
            else
                error('NMDataIODatabaseTools:pythonScalarType', ...
                    'The database returned an unsupported value type (%s).', class(sourceValue));
            end
        end

        function [tf, diagnostic] = pythonHasModule(moduleName)
            % pythonHasModule  Test one module in the Python environment bound to MATLAB.
            tf = false; diagnostic = '';
            try
                py.importlib.import_module(moduleName);
                tf = true;
            catch ME
                diagnostic = ME.message;
                if isempty(diagnostic)
                    diagnostic = sprintf('Python module %s is unavailable without an interpreter diagnostic.', moduleName);
                end
            end
        end

        function [catalogue, performance] = catalogueMetadata(IO)
            % catalogueMetadata  Resolve the complete ordinary-object catalogue through one database connection.
            info = NMDataIODatabaseTools.connectionInfo(IO);
            support = NMDataIODatabaseTools.supportForConnector(info.connector);
            NMDataIODatabaseTools.assertSupported(info, support);
            key = NMDataIODatabaseTools.connectorKey(info.connector);
            if strcmp(key,'mysql') && NMDataIODatabaseTools.isUnknown(info.database)
                error('NMDataIODatabaseTools:missingDatabase', ...
                    'Select a MySQL/MariaDB database before discovering the table/view catalogue.');
            elseif strcmp(key,'postgresql') && ...
                    (NMDataIODatabaseTools.isUnknown(info.database) || NMDataIODatabaseTools.isUnknown(info.schema))
                error('NMDataIODatabaseTools:missingNamespace', ...
                    'Select both PostgreSQL database and schema before discovering the table/view catalogue.');
            end
            if info.useQuery
                error('NMDataIODatabaseTools:catalogueForCustomQuery', ...
                    'Catalogue metadata is defined for ordinary database table/view imports, not custom SQL results.');
            end
            if strcmp(support.backend,'matlab_sqlite')
                catalogue = NMDataIODatabaseTools.sqliteCatalogueMetadataMatlab(info, support);
            else
                [~, description] = NMDataIODatabaseTools.pythonDatabaseOperation(info, support, 'describe_catalogue', '');
                catalogue = description.catalogue;
            end
            performance = struct('catalogueConnectionCount',1, ...
                'catalogueObjectCount',numel(catalogue),'exactRowCounts',true,'mode','single_connection_catalogue');
        end

        function catalogue = sqliteCatalogueMetadataMatlab(info, support)
            conn = sqlite(info.file, 'readonly');
            cleaner = onCleanup(@() NMDataIODatabaseTools.closeConnection(conn)); %#ok<NASGU>
            listing = fetch(conn, NMDataIODatabaseTools.listingSQL('sqlite_file'));
            names = NMDataIODatabaseTools.asCellstr(NMDataIODatabaseTools.tableColumn(listing,'name'));
            catalogue = cell(numel(names),1);
            for i = 1:numel(names)
                localInfo = info;
                localInfo.table = names{i};
                [T, keyRows] = NMDataIODatabaseTools.sqliteObjectMetadataFromConnection(conn, localInfo);
                ident = NMDataIODatabaseTools.quoteIdentifier(names{i}, 'sqlite_file');
                countTable = fetch(conn, sprintf('SELECT COUNT(*) AS row_count FROM %s', ident));
                rowCount = NMDataIODatabaseTools.scalarNumber(NMDataIODatabaseTools.tableColumn(countTable,'row_count'),1,NaN);
                if ~(isscalar(rowCount) && isfinite(rowCount) && rowCount >= 0 && rowCount == round(rowCount))
                    error('NMDataIODatabaseTools:invalidRowCount', ...
                        'Database table/view %s returned an invalid exact row count during catalogue discovery.', names{i});
                end
                catalogue{i} = NMDataIODatabaseTools.buildColumnMetadata(localInfo, support, T, keyRows, double(rowCount));
            end
        end

        function [T, keyRows] = sqliteObjectMetadataMatlab(info)
            conn = sqlite(info.file, 'readonly');
            cleaner = onCleanup(@() NMDataIODatabaseTools.closeConnection(conn)); %#ok<NASGU>
            [T, keyRows] = NMDataIODatabaseTools.sqliteObjectMetadataFromConnection(conn, info);
        end

        function [T, keyRows] = sqliteObjectMetadataFromConnection(conn, info)
            ident = NMDataIODatabaseTools.quoteIdentifier(info.table, 'sqlite_file');
            raw = fetch(conn, sprintf('PRAGMA table_info(%s)', ident));
            names = NMDataIODatabaseTools.asCellstr(NMDataIODatabaseTools.tableColumn(raw,'name'));
            nativeTypes = NMDataIODatabaseTools.asCellstr(NMDataIODatabaseTools.tableColumn(raw,'type'));
            cid = NMDataIODatabaseTools.tableColumn(raw,'cid');
            notNull = NMDataIODatabaseTools.tableColumn(raw,'notnull');
            pk = NMDataIODatabaseTools.tableColumn(raw,'pk');
            n = numel(names);
            ordinal = zeros(n,1); nullable = true(n,1); numericPrecision = nan(n,1);
            numericScale = nan(n,1); datetimePrecision = nan(n,1);
            baseTypes = cell(n,1); objectTypes = repmat({'table'},n,1);
            objectQuery = sprintf('SELECT type FROM sqlite_master WHERE name=''%s'' AND type IN (''table'',''view'')', strrep(info.table,'''',''''''));
            objectTable = fetch(conn, objectQuery);
            objectTypeCol = NMDataIODatabaseTools.tableColumn(objectTable,'type');
            objectType = NMDataIODatabaseTools.scalarText(objectTypeCol, 1, 'table');
            objectTypes(:) = {objectType};
            for i = 1:n
                ordinal(i) = NMDataIODatabaseTools.scalarNumber(cid,i,i-1) + 1;
                nullable(i) = ~(NMDataIODatabaseTools.scalarLogical(notNull,i,false) || NMDataIODatabaseTools.scalarNumber(pk,i,0) > 0);
                [baseTypes{i}, numericPrecision(i), numericScale(i)] = NMDataIODatabaseTools.declaredTypeParts(nativeTypes{i});
            end
            native_type = nativeTypes(:); base_type = baseTypes(:); object_type = objectTypes(:); %#ok<NASGU>
            numeric_precision = numericPrecision; numeric_scale = numericScale; datetime_precision = datetimePrecision; %#ok<NASGU>
            T = table(names(:), ordinal, native_type, base_type, nullable, numeric_precision, numeric_scale, datetime_precision, object_type, ...
                'VariableNames', {'name','ordinal','native_type','base_type','nullable','numeric_precision','numeric_scale','datetime_precision','object_type'});

            rows = cell(0,9);
            pkPairs = cell(0,2);
            for i = 1:n
                p = NMDataIODatabaseTools.scalarNumber(pk,i,0);
                if p > 0, pkPairs(end+1,:) = {p,names{i}}; end %#ok<AGROW>
            end
            if ~isempty(pkPairs)
                [~,order] = sort(cell2mat(pkPairs(:,1)));
                for j = 1:numel(order)
                    r = order(j); rows(end+1,:) = {'primary','sqlite_pk','',j,pkPairs{r,2},'','','',''}; %#ok<AGROW>
                end
            end
            indexes = fetch(conn, sprintf('PRAGMA index_list(%s)', ident));
            idxNames = NMDataIODatabaseTools.asCellstr(NMDataIODatabaseTools.tableColumn(indexes,'name'));
            idxUnique = NMDataIODatabaseTools.tableColumn(indexes,'unique');
            idxOrigin = NMDataIODatabaseTools.tableColumn(indexes,'origin');
            for i = 1:numel(idxNames)
                if ~NMDataIODatabaseTools.scalarLogical(idxUnique,i,false), continue; end
                if strcmpi(NMDataIODatabaseTools.scalarText(idxOrigin,i,''),'pk'), continue; end
                idxIdent = NMDataIODatabaseTools.quoteIdentifier(idxNames{i}, 'sqlite_file');
                cols = fetch(conn, sprintf('PRAGMA index_info(%s)', idxIdent));
                colNames = NMDataIODatabaseTools.asCellstr(NMDataIODatabaseTools.tableColumn(cols,'name'));
                seq = NMDataIODatabaseTools.tableColumn(cols,'seqno');
                for j = 1:numel(colNames)
                    ord = NMDataIODatabaseTools.scalarNumber(seq,j,j-1)+1;
                    rows(end+1,:) = {'unique',['sqlite_unique:' idxNames{i}],idxNames{i},ord,colNames{j},'','','',''}; %#ok<AGROW>
                end
            end
            foreign = fetch(conn, sprintf('PRAGMA foreign_key_list(%s)', ident));
            fkId = NMDataIODatabaseTools.tableColumn(foreign,'id');
            fkSeq = NMDataIODatabaseTools.tableColumn(foreign,'seq');
            fkTable = NMDataIODatabaseTools.tableColumn(foreign,'table');
            fkFrom = NMDataIODatabaseTools.tableColumn(foreign,'from');
            fkTo = NMDataIODatabaseTools.tableColumn(foreign,'to');
            nFk = numel(NMDataIODatabaseTools.asCellstr(fkFrom));
            for i = 1:nFk
                sourceId = sprintf('sqlite_fk:%g', NMDataIODatabaseTools.scalarNumber(fkId,i,i));
                rows(end+1,:) = {'foreign',sourceId,'',NMDataIODatabaseTools.scalarNumber(fkSeq,i,i-1)+1, ...
                    NMDataIODatabaseTools.scalarText(fkFrom,i,''),'','',NMDataIODatabaseTools.scalarText(fkTable,i,''),NMDataIODatabaseTools.scalarText(fkTo,i,'')}; %#ok<AGROW>
            end
            keyRows = cell2table(rows, 'VariableNames', {'kind','constraint_id','constraint_name','ordinal','column_name','ref_database','ref_schema','ref_table','ref_column'});
        end

        function meta = canonicalKeyMetadata(T)
            meta = struct('primary',{{}},'unique',{{}},'foreign',{{}});
            if isempty(T) || height(T) == 0, return; end
            kindCol = NMDataIODatabaseTools.tableColumn(T,'kind');
            idCol = NMDataIODatabaseTools.tableColumn(T,'constraint_id');
            nameCol = NMDataIODatabaseTools.tableColumn(T,'constraint_name');
            ordCol = NMDataIODatabaseTools.tableColumn(T,'ordinal');
            colCol = NMDataIODatabaseTools.tableColumn(T,'column_name');
            refDbCol = NMDataIODatabaseTools.tableColumn(T,'ref_database');
            refSchemaCol = NMDataIODatabaseTools.tableColumn(T,'ref_schema');
            refTableCol = NMDataIODatabaseTools.tableColumn(T,'ref_table');
            refColumnCol = NMDataIODatabaseTools.tableColumn(T,'ref_column');
            records = cell(0,1);
            ids = cell(0,1);
            for i = 1:height(T)
                kind = lower(NMDataIODatabaseTools.scalarText(kindCol,i,''));
                if ~ismember(kind,{'primary','unique','foreign'}), continue; end
                sourceId = NMDataIODatabaseTools.scalarText(idCol,i,'');
                if isempty(sourceId), sourceId = sprintf('row:%g',i); end
                idx = find(strcmp(ids,[kind '|' sourceId]),1);
                if isempty(idx)
                    rec = struct('kind',kind,'name',NMDataIODatabaseTools.scalarText(nameCol,i,''), ...
                        'columns',{{}},'referencedDatabase',NMDataIODatabaseTools.scalarText(refDbCol,i,''), ...
                        'referencedSchema',NMDataIODatabaseTools.scalarText(refSchemaCol,i,''), ...
                        'referencedTable',NMDataIODatabaseTools.scalarText(refTableCol,i,''), ...
                        'referencedColumns',{{}});
                    records{end+1,1} = rec; %#ok<AGROW>
                    ids{end+1,1} = [kind '|' sourceId]; %#ok<AGROW>
                    idx = numel(records);
                end
                rec = records{idx};
                ord = max(1,round(NMDataIODatabaseTools.scalarNumber(ordCol,i,numel(rec.columns)+1)));
                while numel(rec.columns) < ord, rec.columns{end+1} = ''; end
                rec.columns{ord} = NMDataIODatabaseTools.scalarText(colCol,i,'');
                if strcmp(kind,'foreign')
                    while numel(rec.referencedColumns) < ord, rec.referencedColumns{end+1} = ''; end
                    rec.referencedColumns{ord} = NMDataIODatabaseTools.scalarText(refColumnCol,i,'');
                end
                records{idx} = rec;
            end
            for i = 1:numel(records)
                rec = records{i};
                rec.columns = rec.columns(~cellfun(@isempty,rec.columns));
                rec.referencedColumns = rec.referencedColumns(~cellfun(@isempty,rec.referencedColumns));
                meta.(rec.kind){end+1,1} = rec;
            end
        end

        function [isPrimary, isUnique, foreignRefs] = columnKeyMembership(meta, columnName)
            isPrimary = false; isUnique = false; foreignRefs = {};
            for i = 1:numel(meta.primary)
                if any(strcmp(meta.primary{i}.columns,columnName)), isPrimary = true; end
            end
            for i = 1:numel(meta.unique)
                if any(strcmp(meta.unique{i}.columns,columnName)), isUnique = true; end
            end
            for i = 1:numel(meta.foreign)
                rec = meta.foreign{i};
                idx = find(strcmp(rec.columns,columnName),1);
                if isempty(idx), continue; end
                refCol = '';
                if numel(rec.referencedColumns) >= idx, refCol = rec.referencedColumns{idx}; end
                foreignRefs{end+1,1} = struct('constraintName',rec.name, ...
                    'referencedDatabase',rec.referencedDatabase,'referencedSchema',rec.referencedSchema, ...
                    'referencedTable',rec.referencedTable,'referencedColumn',refCol); %#ok<AGROW>
            end
        end

        function out = buildColumnMetadata(info, support, T, keyRows, rowCount)
            % buildColumnMetadata  Convert connector-native metadata rows into the canonical DataIO column contract.
            if nargin < 5 || isempty(rowCount), rowCount = NaN; end
            key = NMDataIODatabaseTools.connectorKey(info.connector);
            names = NMDataIODatabaseTools.asCellstr(NMDataIODatabaseTools.tableColumn(T,'name'));
            objectTypeCol = NMDataIODatabaseTools.tableColumn(T,'object_type');
            objectType = NMDataIODatabaseTools.scalarText(objectTypeCol, 1, 'table');
            keyMetadata = NMDataIODatabaseTools.canonicalKeyMetadata(keyRows);
            identity = struct('connector', key, 'databaseFile', info.file, 'database', info.database, ...
                'schema', info.schema, 'object', info.table, 'objectType', objectType);
            out = struct('ok', true, 'connector', info.connector, 'backend', support.backend, ...
                'databaseFile', info.file, 'database', info.database, 'schema', info.schema, ...
                'table', info.table, 'objectType', objectType, 'identity', identity, ...
                'columns', {names}, 'entries', {{}}, 'keyMetadata', keyMetadata, 'rowCount', double(rowCount));
            ord = NMDataIODatabaseTools.tableColumn(T,'ordinal');
            native = NMDataIODatabaseTools.tableColumn(T,'native_type');
            base = NMDataIODatabaseTools.tableColumn(T,'base_type');
            nullable = NMDataIODatabaseTools.tableColumn(T,'nullable');
            precision = NMDataIODatabaseTools.tableColumn(T,'numeric_precision');
            scale = NMDataIODatabaseTools.tableColumn(T,'numeric_scale');
            dtPrecision = NMDataIODatabaseTools.tableColumn(T,'datetime_precision');
            for i = 1:numel(names)
                ordinal = NMDataIODatabaseTools.scalarNumber(ord, i, i);
                nativeType = NMDataIODatabaseTools.scalarText(native, i, '');
                baseType = NMDataIODatabaseTools.scalarText(base, i, nativeType);
                isNullable = NMDataIODatabaseTools.scalarLogical(nullable, i, true);
                numericPrecision = NMDataIODatabaseTools.scalarNumber(precision, i, NaN);
                numericScale = NMDataIODatabaseTools.scalarNumber(scale, i, NaN);
                datetimePrecision = NMDataIODatabaseTools.scalarNumber(dtPrecision, i, NaN);
                [matlabType, category] = NMDataIODatabaseTools.databaseTypeContract(key, nativeType, baseType, isNullable, numericPrecision);
                [isPrimary, isUnique, foreignRefs] = NMDataIODatabaseTools.columnKeyMembership(keyMetadata, names{i});
                out.entries{end+1,1} = struct('name', names{i}, 'ordinal', ordinal); %#ok<AGROW>
                out.entries{end}.nativeType = nativeType;
                out.entries{end}.baseType = baseType;
                out.entries{end}.matlabType = matlabType;
                out.entries{end}.category = category;
                out.entries{end}.nullable = isNullable;
                out.entries{end}.numericPrecision = numericPrecision;
                out.entries{end}.numericScale = numericScale;
                out.entries{end}.datetimePrecision = datetimePrecision;
                out.entries{end}.primaryKey = isPrimary;
                out.entries{end}.uniqueKey = isUnique;
                out.entries{end}.foreignKeys = foreignRefs;
            end
        end

        function [matlabType, category] = databaseTypeContract(connector, nativeType, baseType, nullable, numericPrecision)
            if nargin < 5, numericPrecision = NaN; end
            c = lower(char(string(connector))); native = lower(strtrim(char(string(nativeType))));
            base = lower(strtrim(char(string(baseType))));
            if isempty(base), [base,~,~] = NMDataIODatabaseTools.declaredTypeParts(native); end
            logicalType = ismember(base,{'bool','boolean'}) || (strcmp(base,'tinyint') && ~isempty(regexp(native,'tinyint\s*\(\s*1\s*\)','once')));
            exactNumericType = ismember(base,{'bigint','int8','bigserial'}) || ...
                (ismember(base,{'decimal','numeric','number'}) && isfinite(numericPrecision) && numericPrecision > 15);
            numericType = logicalType || exactNumericType || ismember(base,{'tinyint','smallint','mediumint','int','integer','int2','int4', ...
                'serial','smallserial','decimal','numeric','number','real','double','double precision','float','float4','float8','money'});
            datetimeType = ismember(base,{'date','datetime','timestamp','timestamptz','timestamp without time zone','timestamp with time zone','time','timetz'});
            binaryType = ismember(base,{'blob','binary','varbinary','bytea','image','bit','bit varying','varbit'});
            if strcmp(c,'sqlite_file')
                upperNative = upper(native);
                logicalType = logicalType || contains(upperNative,'BOOL');
                exactNumericType = exactNumericType || (~logicalType && contains(upperNative,'INT'));
                numericType = numericType || exactNumericType || contains(upperNative,'REAL') || contains(upperNative,'FLOA') || contains(upperNative,'DOUB') || contains(upperNative,'NUM') || contains(upperNative,'DEC');
                datetimeType = datetimeType || contains(upperNative,'DATE') || contains(upperNative,'TIME');
                binaryType = binaryType || contains(upperNative,'BLOB');
            end
            if logicalType
                category = 'logical';
                if nullable, matlabType = 'double'; else, matlabType = 'logical'; end
            elseif exactNumericType
                category = 'exact_numeric'; matlabType = 'string';
            elseif numericType
                category = 'numeric'; matlabType = 'double';
            elseif datetimeType
                category = 'datetime'; matlabType = 'datetime';
            elseif binaryType
                category = 'binary'; matlabType = 'unsupported_binary';
            elseif ismember(base,{'char','character','varchar','character varying','nvarchar','nchar','text','tinytext','mediumtext','longtext','uuid','json','jsonb','xml','enum','set','inet','cidr','macaddr'}) || contains(native,'char') || contains(native,'text')
                category = 'text'; matlabType = 'string';
            else
                category = 'other'; matlabType = 'string';
            end
        end

        function selected = selectColumnMetadata(meta, requested)
            if nargin < 2 || isempty(requested)
                selected = meta.entries;
                return;
            end
            requested = NMDataIODatabaseTools.asCellstr(requested);
            if numel(unique(requested,'stable')) ~= numel(requested)
                error('NMDataIODatabaseTools:duplicateColumns', 'Selective database retrieval contains duplicate column names.');
            end
            selected = cell(numel(requested),1);
            for i = 1:numel(requested)
                idx = find(strcmp(meta.columns, requested{i}),1);
                if isempty(idx)
                    error('NMDataIODatabaseTools:unknownColumn', ...
                        'Database column ''%s'' is not present in catalogue metadata for %s.', requested{i}, meta.table);
                end
                selected{i} = meta.entries{idx};
            end
        end

        function sql = tableSelectSQL(info, columns, maxRows, textColumns)
            if nargin < 4, textColumns = {}; end
            columns = NMDataIODatabaseTools.asCellstr(columns);
            if isempty(columns)
                error('NMDataIODatabaseTools:noColumns', 'Database table/view retrieval requires at least one explicit catalogue column.');
            end
            key = NMDataIODatabaseTools.connectorKey(info.connector);
            quoted = cellfun(@(x) NMDataIODatabaseTools.quoteIdentifier(x,key), columns, 'UniformOutput', false);
            projection = quoted;
            if strcmp(key,'sqlite_file') && ~isempty(textColumns)
                for i = 1:numel(columns)
                    if any(strcmp(textColumns,columns{i}))
                        projection{i} = sprintf('CAST(%s AS TEXT) AS %s',quoted{i},quoted{i});
                    end
                end
            end
            sql = sprintf('SELECT %s FROM %s', strjoin(projection, ', '), NMDataIODatabaseTools.qualifiedObjectName(info));
            if isfinite(maxRows)
                if ismember(key,{'sqlite_file','mysql','postgresql'})
                    sql = sprintf('%s LIMIT %d', sql, max(1,round(double(maxRows))));
                else
                    error('NMDataIODatabaseTools:rowLimitUnsupported', ...
                        'Database connector ''%s'' does not support the requested Preview row limit.', info.connector);
                end
            end
        end

        function q = qualifiedObjectName(info)
            key = NMDataIODatabaseTools.connectorKey(info.connector);
            switch key
                case 'mysql'
                    parts = {info.database, info.table};
                case 'postgresql'
                    parts = {info.schema, info.table};
                case 'odbc_dsn'
                    raw = char(string(info.table));
                    pos = find(raw=='.',1,'last');
                    if isempty(pos), parts = {raw}; else, parts = {raw(1:pos-1),raw(pos+1:end)}; end
                otherwise
                    parts = {info.table};
            end
            parts = parts(~cellfun(@(x) NMDataIODatabaseTools.isUnknown(x),parts));
            quoted = cellfun(@(x) NMDataIODatabaseTools.quoteIdentifier(x,key), parts, 'UniformOutput', false);
            q = strjoin(quoted,'.');
        end

        function T = coerceResultTypes(T, selected)
            if width(T) ~= numel(selected)
                error('NMDataIODatabaseTools:columnCountMismatch', ...
                    'Database retrieval returned %g column(s), but %g metadata column(s) were requested.', width(T), numel(selected));
            end
            vars = T.Properties.VariableNames;
            for i = 1:numel(selected)
                meta = selected{i}; raw = T.(vars{i});
                switch meta.matlabType
                    case 'double'
                        T.(vars{i}) = NMDataIODatabaseTools.toDoubleColumn(raw, meta.name);
                    case 'logical'
                        x = NMDataIODatabaseTools.toDoubleColumn(raw, meta.name);
                        if any(isnan(x))
                            error('NMDataIODatabaseTools:nonNullableLogicalMissing', ...
                                'Non-nullable logical database column ''%s'' returned a missing value.', meta.name);
                        end
                        T.(vars{i}) = logical(x);
                    case 'datetime'
                        T.(vars{i}) = NMDataIODatabaseTools.toDatetimeColumn(raw, meta.name);
                    case 'string'
                        T.(vars{i}) = NMDataIODatabaseTools.toStringColumn(raw);
                    case 'unsupported_binary'
                        error('NMDataIODatabaseTools:binaryRetrievalUnsupported', ...
                            'Database binary column ''%s'' cannot currently be imported without data loss. Deselect it or use a numeric, logical, date/time, or text column.', meta.name);
                    otherwise
                        error('NMDataIODatabaseTools:unknownMatlabType', 'The database column uses an unsupported MATLAB data type (%s).', meta.matlabType);
                end
            end
        end

        function x = toDoubleColumn(raw, columnName)
            if isnumeric(raw) || islogical(raw), x = double(raw); return; end
            if iscategorical(raw), raw = string(raw); end
            if ischar(raw), raw = cellstr(raw); end
            if isstring(raw)
                txt = raw(:); x = str2double(txt);
                missing = ismissing(txt) | strlength(strtrim(txt))==0;
                bad = isnan(x) & ~missing & ~strcmpi(strtrim(txt),'nan');
            elseif iscell(raw)
                x = nan(numel(raw),1); bad = false(numel(raw),1);
                for i = 1:numel(raw)
                    v = raw{i};
                    if isempty(v), continue; end
                    if isnumeric(v) || islogical(v)
                        if isscalar(v), x(i)=double(v); else, bad(i)=true; end
                    else
                        txt = strtrim(char(string(v)));
                        if isempty(txt) || any(strcmpi(txt,{'nan','null','none'})), continue; end
                        x(i) = str2double(txt); bad(i) = isnan(x(i));
                    end
                end
            else
                error('NMDataIODatabaseTools:numericConversionType', ...
                    'Database column ''%s'' cannot be converted from MATLAB class %s to double.', columnName, class(raw));
            end
            if any(bad)
                error('NMDataIODatabaseTools:numericConversion', ...
                    'Database column ''%s'' contains value(s) incompatible with its numeric database type.', columnName);
            end
            x = reshape(x,[],1);
        end

        function x = toStringColumn(raw)
            if isstring(raw), x = raw(:); return; end
            if ischar(raw), x = string(cellstr(raw)); return; end
            if iscell(raw)
                x = strings(numel(raw),1);
                x(:) = missing;
                for i = 1:numel(raw)
                    value = raw{i};
                    if isempty(value), continue; end
                    x(i) = string(value);
                end
                return;
            end
            x = string(raw(:));
        end

        function x = toDatetimeColumn(raw, columnName)
            if isdatetime(raw), x = raw; return; end
            try
                if iscell(raw)
                    x = NaT(numel(raw),1);
                    for i = 1:numel(raw)
                        value = raw{i};
                        if isempty(value), continue; end
                        if isdatetime(value)
                            x(i) = value;
                        else
                            x(i) = datetime(string(value));
                        end
                    end
                else
                    txt = string(raw);
                    txt(strlength(strtrim(txt))==0) = missing;
                    x = datetime(txt);
                end
            catch ME
                error('NMDataIODatabaseTools:datetimeConversion', ...
                    'Database column ''%s'' could not be converted to MATLAB datetime: %s', columnName, ME.message);
            end
        end

        function [base, precision, scale] = declaredTypeParts(nativeType)
            text = strtrim(char(string(nativeType))); precision = NaN; scale = NaN;
            tok = regexp(lower(text),'^[a-z0-9_ ]+','match','once');
            if isempty(tok), base = lower(text); else, base = strtrim(tok); end
            m = regexp(text,'\((\d+)\s*(?:,\s*(\d+))?\)','tokens','once');
            if ~isempty(m)
                precision = str2double(m{1});
                if numel(m)>1 && ~isempty(m{2}), scale = str2double(m{2}); end
            end
        end

        function s = scalarText(x, i, defaultValue)
            if nargin < 3, defaultValue = ''; end
            s = defaultValue;
            if isempty(x) || numel(x)<i, return; end
            if iscell(x)
                v = x{i};
            elseif ischar(x)
                if isrow(x)
                    if i ~= 1, return; end
                    v = x;
                else
                    v = x(i,:);
                end
            else
                v = x(i);
            end
            if isempty(v), return; end
            if isnumeric(v) && isscalar(v) && isnan(v), return; end
            if ~(ischar(v) || isstring(v) || isnumeric(v) || islogical(v) || iscategorical(v))
                error('NMDataIODatabaseTools:metadataScalarType', ...
                    'Database metadata text value has unsupported MATLAB class %s.', class(v));
            end
            s = char(string(v));
        end

        function n = scalarNumber(x, i, defaultValue)
            if nargin < 3, defaultValue = NaN; end
            n = defaultValue;
            if isempty(x) || numel(x)<i, return; end
            if iscell(x), v=x{i}; else, v=x(i); end
            if isempty(v), return; end
            if isnumeric(v) && isscalar(v) && isnan(v), return; end
            if isnumeric(v) || islogical(v)
                candidate = double(v);
            elseif ischar(v) || isstring(v) || iscategorical(v)
                candidate = str2double(char(string(v)));
            else
                error('NMDataIODatabaseTools:metadataScalarType', ...
                    'Database metadata numeric value has unsupported MATLAB class %s.', class(v));
            end
            if isscalar(candidate) && ~isnan(candidate), n=candidate; end
        end

        function tf = scalarLogical(x, i, defaultValue)
            if nargin < 3, defaultValue = false; end
            tf = defaultValue;
            if isempty(x) || numel(x)<i, return; end
            if iscell(x), v=x{i}; else, v=x(i); end
            if isempty(v), return; end
            if isnumeric(v) && isscalar(v) && isnan(v), return; end
            if islogical(v), tf=logical(v); return; end
            if isnumeric(v), tf=logical(v~=0); return; end
            if ~(ischar(v) || isstring(v) || iscategorical(v))
                error('NMDataIODatabaseTools:metadataScalarType', ...
                    'Database metadata logical value has unsupported MATLAB class %s.', class(v));
            end
            text=lower(strtrim(char(string(v))));
            if ismember(text,{'1','true','yes','y'})
                tf=true;
            elseif ismember(text,{'0','false','no','n'})
                tf=false;
            elseif ~isempty(text)
                error('NMDataIODatabaseTools:metadataLogicalValue', ...
                    'Database metadata logical value ''%s'' is not recognized.', text);
            end
        end

        function sql = listingSQL(connector)
            if strcmp(connector,'sqlite_file')
                sql = ['SELECT name, type FROM sqlite_master WHERE type IN (''table'',''view'') ' ...
                    'AND name NOT LIKE ''sqlite_%'' ORDER BY type, name'];
            else
                sql = '';
            end
        end

        function closeConnection(conn)
            try
                close(conn);
            catch ME %#ok<NASGU>
            end
        end

        function sql = limitQuery(sql, maxRows)
            sql = NMDataIODatabaseTools.stripTrailingSemicolon(sql);
            if ~isempty(regexp(sql, '\blimit\s+\d+\b', 'once'))
                return;
            end
            sql = sprintf('SELECT * FROM (%s) AS nm_dataio_query LIMIT %d', sql, max(1,round(double(maxRows))));
        end

        function sql = zeroRowQuery(sql)
            sql = NMDataIODatabaseTools.stripTrailingSemicolon(sql);
            sql = sprintf('SELECT * FROM (%s) AS nm_dataio_query WHERE 1=0', sql);
        end

        function assertReadOnlyQuery(sql)
            s = lower(strtrim(sql));
            if startsWith(s,'select') || startsWith(s,'with')
                return;
            end
            error('NMDataIODatabaseTools:nonReadOnlySQL', 'Only SELECT/WITH SQL queries are allowed in the DataIO database connector.');
        end

        function q = quoteIdentifier(name, connector)
            if nargin < 2 || isempty(connector), connector = 'sqlite_file'; end
            name = char(string(name));
            if isempty(name)
                error('NMDataIODatabaseTools:emptyIdentifier', 'Database identifiers must not be empty.');
            end
            key = NMDataIODatabaseTools.connectorKey(connector);
            if strcmp(key,'mysql')
                q = ['`' strrep(name,'`','``') '`'];
            elseif strcmp(key,'odbc_dsn')
                error('NMDataIODatabaseTools:odbcIdentifierQuoting', ...
                    'ODBC identifier quoting is driver-specific and is resolved by the Python execution adapter.');
            else
                q = ['"' strrep(name,'"','""') '"'];
            end
        end

        function s = stripTrailingSemicolon(s)
            s = strtrim(char(string(s)));
            while ~isempty(s) && s(end)==';'
                s = strtrim(s(1:end-1));
            end
        end

        function c = tableColumn(T, name)
            vars = T.Properties.VariableNames;
            idx = find(strcmpi(vars,name),1);
            if isempty(idx)
                c = {};
            else
                c = T.(vars{idx});
            end
        end

        function c = asCellstr(x)
            if isempty(x)
                c = {};
                return;
            end
            if iscell(x)
                c = cellfun(@(v) char(string(v)), x(:), 'UniformOutput', false);
            elseif isstring(x) || ischar(x)
                c = cellstr(x);
            else
                c = arrayfun(@(v) char(string(v)), x(:), 'UniformOutput', false);
            end
        end

        function v = pick(S, names, defaultValue)
            v = defaultValue;
            if ~isstruct(S)
                return;
            end
            for i = 1:numel(names)
                if isfield(S,names{i}) && ~isempty(S.(names{i}))
                    v = S.(names{i});
                    return;
                end
            end
        end

        function s = toChar(v)
            if isempty(v)
                s = '';
            elseif iscell(v)
                if isempty(v)
                    s = '';
                else
                    s = char(string(v{1}));
                end
            else
                s = char(string(v));
            end
        end

        function tf = isUnknown(v)
            if isempty(v)
                tf = true;
                return;
            end
            s = strtrim(char(string(v)));
            tf = isempty(s) || strcmp(s,'?') || strcmp(s,'—');
        end

        function v = opt(S, name, defaultValue)
            v = defaultValue;
            if isstruct(S) && isfield(S,name) && ~isempty(S.(name))
                v = S.(name);
            end
        end

    end
end

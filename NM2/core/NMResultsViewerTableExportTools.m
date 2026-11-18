classdef NMResultsViewerTableExportTools
% NMResultsViewerTableExportTools
% -------------------------------------------------------------------------
% Sole format-specific table writer behind generic artifacts and reports.
% -------------------------------------------------------------------------

    methods (Static)
        function out = writeArtifact(artifact, exportSpec)
            % WRITEARTIFACT  Write a validated table artifact as CSV/TSV/XLSX.
            fmt = lower(strtrim(NMSerializationTools.textField(exportSpec,'format','')));
            if ~ismember(fmt, {'csv','tsv','xlsx'})
                out = struct('ok',false,'message','Table artifact export requires CSV, TSV, or XLSX format.', ...
                    'format',fmt,'path',''); return;
            end
            outDir = NMSerializationTools.textField(exportSpec,'outputDirectory','');
            if isempty(outDir) || exist(outDir, 'dir') ~= 7
                out = struct('ok',false,'message','No valid export directory was provided by the browser path dialog.', ...
                    'format',fmt,'path','');
                return;
            end
            columns = NMResultsViewerTableExportTools.structField(artifact,'columns',struct([]));
            rows = NMResultsViewerTableExportTools.structField(artifact,'rows',struct([]));
            tables = NMResultsViewerTableExportTools.structField(artifact,'tables',struct([]));
            if isempty(tables) && (isempty(columns) || isempty(rows))
                out = struct('ok',false,'message','Table artifact contains no schema-labelled data rows.', ...
                    'format',fmt,'path',''); return;
            end
            tableKind = NMSerializationTools.sanitizeToken(NMSerializationTools.textField(artifact,'representationId','table'),'plot');
            resultKind = NMSerializationTools.sanitizeToken(NMSerializationTools.textField(exportSpec,'resultKind','results'),'plot');
            analysisIndex = NMSerializationTools.textField(exportSpec,'analysisIndex','0');
            analysisText = NMSerializationTools.sanitizeToken(['A' regexprep(analysisIndex, '^A', '')],'plot');
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            defaultBase = sprintf('NM_%s_%s_%s_%s', analysisText, resultKind, tableKind, stamp);
            outPath = NMSerializationTools.uniqueOutputPath(outDir, defaultBase, fmt);
            tableReq = struct('tables',tables);
            tableList = NMResultsViewerTableExportTools.normalizedTableList(tableReq, columns, rows);
            blocks = cell(1,numel(tableList));
            for i=1:numel(tableList)
                blocks{i}=struct('SheetName',tableList(i).sheetName,'FileToken',tableList(i).sheetName, ...
                    'Cells',{NMResultsViewerTableExportTools.rowsToCell(tableList(i).columns,tableList(i).rows)});
            end
            meta = NMResultsViewerTableExportTools.structField(artifact,'metadataRows',struct([]));
            metaCell = NMResultsViewerTableExportTools.metadataToCell(meta);
            paths = NMResultsViewerTableExportTools.writeCellTables(blocks,fmt,outDir,defaultBase,outPath,metaCell,meta);
            if numel(paths) == 1
                msg = sprintf('Results Viewer table exported to %s.', paths{1});
                primaryPath = paths{1};
            else
                msg = sprintf('Results Viewer table export wrote %d files to %s.', numel(paths), outDir);
                primaryPath = outDir;
            end
            out = struct('ok',true,'message',msg,'format',fmt,'path',primaryPath,'paths',{paths});
        end

        function value = structField(s, name, fallback)
            value = fallback;
            if isstruct(s) && isfield(s,name), value=s.(name); end
        end

        function paths = writeCellTables(blocks, fmt, outDir, baseName, outPath, metaCell, metaJson)
            % WRITECELLTABLES  Sole CSV/TSV/XLSX serialization boundary.
            paths=cell(1,0);
            if strcmp(fmt,'xlsx')
                if isempty(blocks), blocks={struct('SheetName','Summary','FileToken','summary','Cells',{{'No tables'}})}; end
                if ~isempty(metaCell)
                    blocks{end+1}=struct('SheetName','Metadata','FileToken','metadata','Cells',{metaCell});
                end
                for i=1:numel(blocks)
                    sheet=NMResultsViewerTableExportTools.xlsxSheetName(blocks{i}.SheetName,i);
                    if exist('writecell','file')==2, writecell(blocks{i}.Cells,outPath,'Sheet',sheet); else, xlswrite(outPath,blocks{i}.Cells,sheet); end %#ok<XLSWT>
                end
                paths{end+1}=outPath;
                return;
            end
            delimiter=','; if strcmp(fmt,'tsv'), delimiter=sprintf('\t'); end
            for i=1:numel(blocks)
                token=NMSerializationTools.sanitizeToken(blocks{i}.FileToken,'plot');
                pth=NMSerializationTools.uniqueOutputPath(outDir,[baseName '_' token],fmt);
                NMSerializationTools.writeDelimited(pth,blocks{i}.Cells,delimiter);
                paths{end+1}=pth; %#ok<AGROW>
            end
            metaPath=NMSerializationTools.uniqueOutputPath(outDir,[baseName '_metadata'],'json');
            NMSerializationTools.writeTextUtf8(metaPath,jsonencode(metaJson));
            paths{end+1}=metaPath;
        end

        function tableList = normalizedTableList(tableReq, columns, rows)
            % Purpose: Normalize one or more browser table payloads into a scalar-descriptor list for the generic Results Viewer table writer.
            % Syntax: tableList = NMResultsViewerTableExportTools.normalizedTableList(tableReq,columns,rows)
            % Inputs: tableReq may contain a struct array of explicit tables; columns is the fallback column-schema struct array; rows is the fallback row struct array.
            % Outputs: Row-vector struct array whose elements each contain one sheetName/title plus the complete columns and rows arrays as scalar field values.
            % Authority and flow: This is the sole structural-normalization boundary immediately before rowsToCell/writeCellTables; it does not interpret scientific values or choose export format.
            % Scientific/state contract: Column and row arrays are opaque schema-labelled table data already produced by the owning Results Viewer artefact; their independent shapes must be preserved exactly.
            % Invariants: Every table descriptor is scalar. columns and rows are stored as whole field values and are never dimension-expanded against one another by MATLAB struct construction.
            % Materialization and performance: O(T) descriptor construction only; table arrays are referenced/copied by ordinary MATLAB value semantics and no feature-scale scientific materialization is introduced.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; safe at the explicit export boundary.
            % Failure semantics: Invalid explicit table entries are skipped as before; if none remain, the supplied fallback columns/rows form exactly one Data descriptor. Downstream schema validation remains in rowsToCell.
            % Side effects: None.
            % Consumers and dependencies: writeArtifact and the generic CSV/TSV/XLSX serialization path.
            tmpl = struct('sheetName','','title','','columns',struct([]),'rows',struct([]));
            tableList = repmat(tmpl, 1, 0);
            if isfield(tableReq,'tables') && isstruct(tableReq.tables) && ~isempty(tableReq.tables)
                for i = 1:numel(tableReq.tables)
                    T = tableReq.tables(i);
                    if ~isfield(T,'columns') || ~isfield(T,'rows') || isempty(T.columns) || isempty(T.rows), continue; end
                    sheet = sprintf('Table%d', i);
                    if isfield(T,'sheetName') && ~isempty(T.sheetName), sheet = NMSerializationTools.scalarText(T.sheetName, sheet); end
                    title = sheet;
                    if isfield(T,'title') && ~isempty(T.title), title = NMSerializationTools.scalarText(T.title, title); end
                    tableList(end+1) = struct('sheetName',sheet,'title',title,'columns',{T.columns},'rows',{T.rows}); %#ok<AGROW>
                end
            end
            if isempty(tableList)
                tableList = struct('sheetName','Data','title','Data','columns',{columns},'rows',{rows});
            end
        end

        function C = rowsToCell(columns, rows)
            % ROWSTOCELL  Convert labelled row structs into a headered cell matrix.
            %
            %   C = NMResultsViewerTableExportTools.rowsToCell(columns, rows)
            %   uses the browser column schema to order fields and to create the
            %   first header row. Missing row fields are exported as empty cells.
            nCol = numel(columns);
            nRow = numel(rows);
            C = cell(nRow + 1, nCol);
            keys = cell(1, nCol);
            for c = 1:nCol
                if ~isfield(columns(c),'key') || isempty(columns(c).key)
                    error('NMResultsViewerTableExportTools:badColumnSchema', 'Column %d has no key.', c);
                end
                keys{c} = char(string(columns(c).key));
                if isfield(columns(c),'label') && ~isempty(columns(c).label)
                    C{1,c} = char(string(columns(c).label));
                else
                    C{1,c} = keys{c};
                end
            end
            for r = 1:nRow
                for c = 1:nCol
                    if isfield(rows(r), keys{c})
                        C{r+1,c} = NMSerializationTools.cellScalar(rows(r).(keys{c}));
                    else
                        C{r+1,c} = '';
                    end
                end
            end
        end

        function C = metadataToCell(meta)
            % METADATATOCELL  Convert metadata structs to key/value cell rows.
            %
            %   C = NMResultsViewerTableExportTools.metadataToCell(meta) converts
            %   browser-supplied metadata into a two-column cell array for XLSX
            %   metadata sheets or JSON sidecar generation.
            if ~isstruct(meta) || isempty(meta)
                C = cell(0,2);
                return;
            end
            C = cell(numel(meta), 2);
            for i = 1:numel(meta)
                if isfield(meta(i),'key') && ~isempty(meta(i).key)
                    C{i,1} = char(string(meta(i).key));
                else
                    C{i,1} = sprintf('Metadata %d', i);
                end
                if isfield(meta(i),'value')
                    C{i,2} = NMSerializationTools.cellScalar(meta(i).value);
                else
                    C{i,2} = '';
                end
            end
        end

        function sheet = xlsxSheetName(name, idx)
            % XLSXSHEETNAME  Sanitize an Excel worksheet name.
            %
            %   sheet = NMResultsViewerTableExportTools.xlsxSheetName(name, idx)
            %   removes Excel-forbidden characters, applies a fallback Table<idx>
            %   name, and truncates to Excel's 31-character sheet-name limit.
            sheet = NMSerializationTools.scalarText(name, sprintf('Table%d', idx));
            sheet = regexprep(sheet, '[:\\/?*\[\]]', '_');
            sheet = strtrim(sheet);
            if isempty(sheet), sheet = sprintf('Table%d', idx); end
            if numel(sheet) > 31, sheet = sheet(1:31); end
        end
    end
end

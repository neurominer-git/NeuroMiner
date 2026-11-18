classdef NMDataIOOOXMLMetadataTools
% NMDataIOOOXMLMetadataTools
% -------------------------------------------------------------------------
% Source-intrinsic XLSX/XLSM metadata adapter for DataIO.
% Uses one java.util.zip package handle per request only as the archive
% transport. XML interpretation remains MATLAB-side; no Java XML parser or
% token callback path participates in worksheet/header discovery.
% Worksheet streams are consumed only through the requested leading rows and
% are closed immediately after that bounded window has been obtained.
% -------------------------------------------------------------------------

    methods (Static)
        function tf = isSupported(path)
            [~,~,ext] = fileparts(char(path));
            tf = ismember(lower(ext), {'.xlsx','.xlsm'});
        end

        function [index, perf] = workbookIndex(path)
            [index,~,perf] = NMDataIOOOXMLMetadataTools.readPackage(char(path),0,{});
        end

        function [index, rawBySheet, perf] = workbookHeaders(path, maxRows, sheetNames)
            % WORKBOOKHEADERS  Read bounded headers only for the requested worksheets.
            if nargin < 2 || isempty(maxRows), maxRows = 30; end
            if nargin < 3, sheetNames = {}; end
            [index,rawBySheet,perf] = NMDataIOOOXMLMetadataTools.readPackage( ...
                char(path),max(1,ceil(double(maxRows))),sheetNames);
        end

        function [raw, perf] = topRows(path, worksheetTarget, maxRows)
            % TOPROWS  Read bounded leading rows from one worksheet package target.
            if nargin < 3 || isempty(maxRows), maxRows = 30; end
            [~,rows,perf] = NMDataIOOOXMLMetadataTools.readPackage( ...
                char(path),max(1,ceil(double(maxRows))),{char(worksheetTarget)});
            raw = rows{1};
            perf.nColumns = double(size(raw,2));
            perf.nRows = double(size(raw,1));
        end
    end

    methods (Static, Access=private)
        function [index, raws, perf] = readPackage(path, maxRows, targets)
            if ~NMDataIOOOXMLMetadataTools.isSupported(path)
                error('NMDataIOOOXMLMetadataTools:notOOXML', ...
                    'OOXML metadata access requires an XLSX/XLSM workbook: %s',path);
            end
            if exist(path,'file') ~= 2
                error('NMDataIOOOXMLMetadataTools:fileNotFound','OOXML workbook does not exist: %s',path);
            end

            tTotal = tic;
            tOpen = tic;
            try
                archiveFile = javaObject('java.io.File',path);
                archive = javaObject('java.util.zip.ZipFile',archiveFile);
            catch ME
                error('NMDataIOOOXMLMetadataTools:packageOpenFailed', ...
                    'Could not open OOXML workbook %s: %s (%s)',path,ME.message,ME.identifier);
            end
            packageOpenSeconds = toc(tOpen);
            cleanupArchive = onCleanup(@() archive.close());

            tIndex = tic;
            index = NMDataIOOOXMLMetadataTools.indexFromArchive(archive,path);
            indexSeconds = toc(tIndex);

            worksheetSeconds = zeros(1,0);
            worksheetCharacters = zeros(1,0);
            worksheetEntryBytes = zeros(1,0);
            sharedSeconds = 0;
            sharedParses = 0;
            sharedCharacters = 0;
            sharedEntryBytes = 0;
            if maxRows < 1
                raws = {};
            else
                if isempty(targets)
                    targets = {index.target};
                else
                    requestedTargets = cell(1,numel(targets));
                    indexNames = {index.name}; indexTargets = {index.target};
                    for ti = 1:numel(targets)
                        target = char(string(targets{ti}));
                        hit = find(strcmp(indexNames,target));
                        if numel(hit) == 1
                            requestedTargets{ti} = index(hit).target;
                        elseif any(strcmp(indexTargets,target))
                            requestedTargets{ti} = target;
                        else
                            error('NMDataIOOOXMLMetadataTools:unknownWorksheet', ...
                                'Worksheet ''%s'' was not found in OOXML workbook %s.',target,path);
                        end
                    end
                    targets = requestedTargets;
                end
                raws = cell(1,numel(targets));
                unresolved = cell(1,numel(targets));
                worksheetSeconds = zeros(1,numel(targets));
                worksheetCharacters = zeros(1,numel(targets));
                worksheetEntryBytes = zeros(1,numel(targets));
                for i = 1:numel(targets)
                    tSheet = tic;
                    [raws{i},unresolved{i},sheetPerf] = NMDataIOOOXMLMetadataTools.readTopRowsFromArchive( ...
                        archive,targets{i},maxRows,path);
                    worksheetSeconds(i) = toc(tSheet);
                    worksheetCharacters(i) = double(sheetPerf.charactersConsumed);
                    worksheetEntryBytes(i) = double(sheetPerf.entryBytes);
                end
                tShared = tic;
                [raws,sharedParses,sharedPerf] = NMDataIOOOXMLMetadataTools.resolveSharedStrings( ...
                    archive,raws,unresolved,path);
                sharedSeconds = toc(tShared);
                sharedCharacters = double(sharedPerf.charactersRead);
                sharedEntryBytes = double(sharedPerf.entryBytes);
            end

            tClose = tic;
            archive.close();
            packageCloseSeconds = toc(tClose);
            clear cleanupArchive

            totalSeconds=toc(tTotal);
            accountedSeconds=double(packageOpenSeconds)+double(indexSeconds)+sum(double(worksheetSeconds))+ ...
                double(sharedSeconds)+double(packageCloseSeconds);
            overheadSeconds=max(0,double(totalSeconds)-accountedSeconds);
            perf = struct('seconds',double(totalSeconds),'method','ooxml-stream','packageOpens',1, ...
                'packageOpenSeconds',double(packageOpenSeconds),'indexSeconds',double(indexSeconds), ...
                'worksheetSeconds',worksheetSeconds,'worksheetCharacters',worksheetCharacters, ...
                'worksheetEntryBytes',worksheetEntryBytes, ...
                'sharedStringsSeconds',double(sharedSeconds), ...
                'sharedStringsCharacters',double(sharedCharacters), ...
                'sharedStringsEntryBytes',double(sharedEntryBytes), ...
                'packageCloseSeconds',double(packageCloseSeconds),'overheadSeconds',double(overheadSeconds), ...
                'sharedStringsParses',double(sharedParses),'nSheetsRead',double(numel(raws)));
        end

        function index = indexFromArchive(archive, path)
            workbookXml = NMDataIOOOXMLMetadataTools.readEntryText(archive,'xl/workbook.xml',path);
            relsXml = NMDataIOOOXMLMetadataTools.readEntryText(archive,'xl/_rels/workbook.xml.rels',path);
            sheets = regexp(workbookXml,'<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?sheet(?:\s[^>]*)?/>','match');
            rels = regexp(relsXml,'<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?Relationship(?:\s[^>]*)?/>','match');
            if isempty(sheets), error('NMDataIOOOXMLMetadataTools:noWorksheets', ...
                    'No worksheet objects were found in OOXML workbook %s.',path); end
            relIds = cell(1,numel(rels)); relTargets = cell(1,numel(rels));
            for i = 1:numel(rels)
                relIds{i} = NMDataIOOOXMLMetadataTools.xmlAttribute(rels{i},'Id');
                relTargets{i} = NMDataIOOOXMLMetadataTools.xmlAttribute(rels{i},'Target');
            end
            index = repmat(struct('name','','target',''),1,numel(sheets));
            for i = 1:numel(sheets)
                rid = NMDataIOOOXMLMetadataTools.xmlAttribute(sheets{i},'id'); hit = find(strcmp(relIds,rid));
                if numel(hit) ~= 1 || isempty(relTargets{hit})
                    error('NMDataIOOOXMLMetadataTools:worksheetRelationship', ...
                        'Could not resolve worksheet relationship %s in %s.',rid,path);
                end
                index(i).name = NMDataIOOOXMLMetadataTools.xmlDecode( ...
                    NMDataIOOOXMLMetadataTools.xmlAttribute(sheets{i},'name'));
                index(i).target = NMDataIOOOXMLMetadataTools.normalizeTarget('xl/workbook.xml',relTargets{hit});
            end
        end

        function [raw, unresolved, perf] = readTopRowsFromArchive(archive, target, maxRows, path)
            % READTOPROWSFROMARCHIVE  Bounded leading-row read for one worksheet part.
            %
            % Phase 1 bounds the stream: one package read per row, interpreting
            % only the row number needed to stop at the requested window.
            % Phase 2 interprets the accumulated window with a fixed number of
            % whole-window regular expressions and vectorised conversions, so
            % cost scales with the number of MATLAB operations rather than with
            % the number of worksheet cells.
            [entry,entryBytes] = NMDataIOOOXMLMetadataTools.packageEntry(archive,target,path);
            stream = archive.getInputStream(entry);
            scanner = javaObject('java.util.Scanner',stream,'UTF-8');
            cleanupScanner = onCleanup(@() scanner.close());

            rowPattern = ['(?s)<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?row(?:\s[^>]*)?' ...
                '(?:/>|>.*?</(?:[A-Za-z_][A-Za-z0-9_.-]*:)?row\s*>)'];
            rowXml=cell(1,maxRows); rowNumbers=zeros(1,maxRows);
            nRows=0; previousRow=0; charactersConsumed=0;
            while nRows < maxRows
                rowMatch = scanner.findWithinHorizon(rowPattern,0);
                if isempty(rowMatch), break; end
                xml = char(rowMatch);
                % Counted before the window test: findWithinHorizon has already
                % physically consumed this row, including the overshoot row that
                % ends the window. S32 uses this as a bounded-read metric.
                charactersConsumed=charactersConsumed+numel(xml);
                rowTag = regexp(xml,'^<[^>]+>','match','once');
                rowText = NMDataIOOOXMLMetadataTools.xmlAttribute(rowTag,'r');
                if isempty(rowText), rowNumber=previousRow+1; else, rowNumber=str2double(rowText); end
                if ~isfinite(rowNumber) || rowNumber<1, rowNumber=previousRow+1; end
                previousRow=rowNumber;
                if rowNumber>maxRows, break; end
                nRows=nRows+1; rowXml{nRows}=xml; rowNumbers(nRows)=rowNumber;
            end
            scanner.close();
            clear cleanupScanner

            perf=struct('charactersConsumed',double(charactersConsumed),'entryBytes',double(entryBytes));
            unresolved=struct('rows',zeros(0,1),'cols',zeros(0,1),'indices',zeros(0,1));
            if nRows==0, raw=cell(0,0); return; end

            rowXml=rowXml(1:nRows); rowNumbers=rowNumbers(1:nRows); window=[rowXml{:}];
            lengths=cellfun('length',rowXml); rowOffsets=cumsum([1 lengths(1:end-1)]);
            maxRow=max(rowNumbers);
            % Explicit XML tag boundary: MATLAB regexp \b denotes backspace, not a word boundary.
            cellStart=regexp(window,'<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?c(?=\s|/?>)','start');
            if isempty(cellStart), raw=cell(maxRow,0); return; end
            nCells=numel(cellStart); cellRow=rowNumbers(discretize(cellStart,[rowOffsets inf]));

            % Every present r attribute is captured and then validated: a present
            % but uninterpretable reference must fail rather than fall through to
            % the implicit-column path, which would be a permissive fallback.
            columns=zeros(1,nCells);
            [refTokens,refStart]=regexp(window, ...
                '<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?c(?=\s|/?>)[^>]*?\sr="([^"]*)"','tokens','start');
            if ~isempty(refTokens)
                [~,refCell]=ismember(refStart,cellStart); refs=vertcat(refTokens{:}); refs=refs(:,1);
                letters=regexp(refs,'^[A-Za-z]+','match','once'); invalid=cellfun('isempty',letters);
                if any(invalid), error('NMDataIOOOXMLMetadataTools:cellReference', ...
                        'Invalid spreadsheet cell reference: %s',refs{find(invalid,1)}); end
                columns(refCell)=NMDataIOOOXMLMetadataTools.columnIndices(letters);
            end
            for i=find(columns==0)
                if i>1 && cellRow(i)==cellRow(i-1), columns(i)=columns(i-1)+1; else, columns(i)=1; end
            end
            maxCol=max(columns); cellTypes=repmat({''},1,nCells);
            [typeTokens,typeStart]=regexp(window, ...
                '<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?c(?=\s|/?>)[^>]*?\st="([A-Za-z]+)"','tokens','start');
            if ~isempty(typeTokens)
                [~,typeCell]=ismember(typeStart,cellStart); types=vertcat(typeTokens{:});
                cellTypes(typeCell)=types(:,1);
            end
            cellText=repmat({''},1,nCells);
            [valueTokens,valueStart]=regexp(window, ...
                '(?s)<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?v(?:\s[^>]*)?>(.*?)</(?:[A-Za-z_][A-Za-z0-9_.-]*:)?v\s*>', ...
                'tokens','start');
            if ~isempty(valueTokens)
                valueCell=discretize(valueStart,[cellStart inf]); valueText=vertcat(valueTokens{:});
                cellText(valueCell)=valueText(:,1);
            end
            isShared=strcmp(cellTypes,'s'); isInline=strcmp(cellTypes,'inlineStr');
            if any(isInline)
                [inlineTokens,inlineStart]=regexp(window, ...
                    '(?s)<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?t(?:\s[^>]*)?>(.*?)</(?:[A-Za-z_][A-Za-z0-9_.-]*:)?t\s*>', ...
                    'tokens','start');
                if ~isempty(inlineTokens)
                    inlineCell=discretize(inlineStart,[cellStart inf]); keep=isInline(inlineCell);
                    inlineCell=inlineCell(keep); inlineTokens=inlineTokens(keep); cellText(isInline)={''};
                    if ~isempty(inlineCell)
                        % One <t> per cell is the ordinary case and assigns vectorised;
                        % only genuine multi-run rich text accumulates.
                        runs=vertcat(inlineTokens{:}); runs=runs(:,1);
                        occurrences=accumarray(inlineCell(:),1,[nCells 1]);
                        singleRun=(occurrences(inlineCell)==1);
                        cellText(inlineCell(singleRun))=runs(singleRun);
                        for k=find(~singleRun(:))'
                            cellText{inlineCell(k)}=[cellText{inlineCell(k)} runs{k}];
                        end
                    end
                end
            end

            sharedIndices=str2double(cellText(isShared));
            if any(~isfinite(sharedIndices) | sharedIndices<0 | sharedIndices~=round(sharedIndices))
                error('NMDataIOOOXMLMetadataTools:sharedStringIndex', ...
                    'Worksheet %s contains an invalid shared-string index.',char(target));
            end
            unresolved=struct('rows',cellRow(isShared)','cols',columns(isShared)', ...
                'indices',sharedIndices(:));

            values=cell(1,nCells);
            isBoolean=strcmp(cellTypes,'b');
            isTextual=ismember(cellTypes,{'str','d','e'});
            isDefault=~(isShared|isInline|isBoolean|isTextual);
            if any(isBoolean)
                values(isBoolean)=num2cell(logical(str2double(cellText(isBoolean))));
            end
            if any(isTextual)
                values(isTextual)=NMDataIOOOXMLMetadataTools.xmlDecodeMany(cellText(isTextual));
            end
            if any(isInline)
                values(isInline)=NMDataIOOOXMLMetadataTools.xmlDecodeMany(cellText(isInline));
            end
            if any(isDefault)
                text=cellText(isDefault);
                numbers=str2double(text);
                trimmed=strtrim(text);
                blank=cellfun('isempty',trimmed);
                asText=isnan(numbers) & ~blank & ~strcmpi(trimmed,'nan');
                resolved=num2cell(numbers);
                resolved(blank)={''};
                if any(asText)
                    resolved(asText)=NMDataIOOOXMLMetadataTools.xmlDecodeMany(text(asText));
                end
                values(isDefault)=resolved;
            end

            raw=cell(maxRow,maxCol);
            placed=~isShared;
            if any(placed)
                raw(sub2ind([maxRow maxCol],cellRow(placed),columns(placed)))=values(placed);
            end
        end

        function indices = columnIndices(letters)
            % COLUMNINDICES  Vectorised A1 column letters to one-based indices.
            %
            % Grouped by letter count so each group converts as a char matrix;
            % Excel caps worksheets at 16384 columns, so there are at most three
            % groups regardless of worksheet width.
            indices=zeros(1,numel(letters));
            lengths=cellfun('length',letters);
            for width=unique(lengths(:))'
                selected=(lengths==width);
                block=upper(char(letters(selected)));
                accumulated=zeros(nnz(selected),1);
                for k=1:width
                    accumulated=accumulated*26+(double(block(:,k))-double('A')+1);
                end
                indices(selected)=accumulated;
            end
        end

        function values = xmlDecodeMany(values)
            % XMLDECODEMANY  Decode only the entries that carry XML entities.
            if isempty(values), return; end
            % The scalar reader stripped CDATA whether or not entities were
            % present, so selecting on '&' alone would silently retain CDATA
            % wrappers in cells that carry no entity.
            encoded=find(contains(values,'&') | contains(values,'<![CDATA['));
            for i=encoded(:)'
                values{i}=NMDataIOOOXMLMetadataTools.xmlDecode(values{i});
            end
        end

        function [raws, parseCount, perf] = resolveSharedStrings(archive, raws, unresolved, path)
            indices=zeros(0,1);
            for i=1:numel(unresolved), if ~isempty(unresolved{i}.indices), indices=[indices;unresolved{i}.indices(:)]; end; end %#ok<AGROW>
            parseCount=0; perf=struct('charactersRead',0,'entryBytes',0);
            if isempty(indices), return; end
            uniqueIndices=unique(double(indices),'sorted');
            [values,sharedPerf]=NMDataIOOOXMLMetadataTools.sharedStringsFromArchive(archive,uniqueIndices,path);
            perf=sharedPerf; parseCount=1;
            for i=1:numel(raws)
                u=unresolved{i}; if isempty(u.indices), continue; end
                [found,loc]=ismember(double(u.indices(:)),uniqueIndices);
                if ~all(found), error('NMDataIOOOXMLMetadataTools:sharedStringMissing', ...
                        'Workbook %s does not contain all shared strings referenced by a worksheet.',path); end
                for j=1:numel(loc), raws{i}{u.rows(j),u.cols(j)}=values{loc(j)}; end
            end
        end

        function [values, perf] = sharedStringsFromArchive(archive, targetIndices, path)
            entryName='xl/sharedStrings.xml';
            [entry,entryBytes]=NMDataIOOOXMLMetadataTools.packageEntry(archive,entryName,path,false);
            if isempty(entry)
                error('NMDataIOOOXMLMetadataTools:sharedStringsMissing', ...
                    'Workbook %s references shared strings but xl/sharedStrings.xml is absent.',path);
            end
            xml=NMDataIOOOXMLMetadataTools.readEntryText(archive,entryName,path);
            starts=regexp(xml,'<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?si(?:\s|>)','start');
            targetIndices=double(targetIndices(:)); values=cell(numel(targetIndices),1);
            for i=1:numel(targetIndices)
                k=targetIndices(i)+1;
                if k<1 || k>numel(starts), error('NMDataIOOOXMLMetadataTools:sharedStringMissing', ...
                        'Workbook %s does not contain shared-string index %g.',path,targetIndices(i)); end
                if k<numel(starts), stop=starts(k+1)-1; else, stop=numel(xml); end
                values{i}=strjoin(NMDataIOOOXMLMetadataTools.elementTexts(xml(starts(k):stop),'t'),'');
            end
            perf=struct('charactersRead',double(numel(xml)),'entryBytes',double(entryBytes));
        end

        function text = readEntryText(archive, entryName, path)
            [entry,~]=NMDataIOOOXMLMetadataTools.packageEntry(archive,entryName,path);
            stream=archive.getInputStream(entry);
            scanner=javaObject('java.util.Scanner',stream,'UTF-8');
            cleanupScanner=onCleanup(@() scanner.close());
            scanner.useDelimiter('\A');
            if scanner.hasNext(), text=char(scanner.next()); else, text=''; end
            scanner.close();
            clear cleanupScanner
        end

        function [entry, entryBytes] = packageEntry(archive, entryName, path, required)
            if nargin < 4, required=true; end
            normalized=strrep(char(entryName),'\','/');
            entry=archive.getEntry(normalized);
            if isempty(entry)
                entryBytes=0;
                if required
                    error('NMDataIOOOXMLMetadataTools:entryMissing', ...
                        'OOXML workbook %s is missing package entry %s.',path,normalized);
                end
                return;
            end
            entryBytes=double(entry.getSize());
            if entryBytes < 0, entryBytes=NaN; end
        end

        function values = elementTexts(xml, localName)
            name=regexptranslate('escape',localName);
            pattern=['(?s)<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?' name '(?:\s[^>]*)?>(.*?)</(?:[A-Za-z_][A-Za-z0-9_.-]*:)?' name '\s*>'];
            tokens=regexp(xml,pattern,'tokens'); values=cell(1,numel(tokens));
            for i=1:numel(tokens), values{i}=NMDataIOOOXMLMetadataTools.xmlDecode(tokens{i}{1}); end
        end

        function value = xmlAttribute(tag, localName)
            pattern=['(?:^|\s)(?:[A-Za-z_][A-Za-z0-9_.-]*:)?' regexptranslate('escape',localName) '\s*=\s*"([^"]*)"'];
            token=regexp(tag,pattern,'tokens','once'); if isempty(token), value=''; else, value=token{1}; end
        end

        function value = xmlDecode(value)
            value=regexprep(value,'<!\[CDATA\[(.*?)\]\]>','$1'); value=strrep(value,'&amp;','&'); value=strrep(value,'&quot;','"');
            value=strrep(value,'&apos;',''''); value=strrep(value,'&lt;','<'); value=strrep(value,'&gt;','>');
        end

        function target = normalizeTarget(baseEntry, relativeTarget)
            target=strrep(char(relativeTarget),'\','/'); if startsWith(target,'/'), target=target(2:end); return; end
            base=regexp(char(baseEntry),'/','split'); parts=[base(1:end-1) regexp(target,'/','split')]; stack={};
            for i=1:numel(parts)
                part=parts{i}; if isempty(part)||strcmp(part,'.'), continue; end
                if strcmp(part,'..'), if isempty(stack), error('NMDataIOOOXMLMetadataTools:relationshipTarget', ...
                            'Invalid OOXML relationship target: %s',relativeTarget); end; stack(end)=[];
                else, stack{end+1}=part; end %#ok<AGROW>
            end
            target=strjoin(stack,'/');
        end

    end
end

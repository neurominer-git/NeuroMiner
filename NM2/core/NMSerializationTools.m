classdef NMSerializationTools
% NMSerializationTools
% -------------------------------------------------------------------------
% Generic scalar coercion, token sanitisation and lightweight file-writing
% utilities shared by browser-backed NM modules. These methods intentionally
% avoid module-specific Results Viewer semantics so their help text can be
% reused later by documentation/RAG extraction.
% -------------------------------------------------------------------------

    methods (Static)

        function [val, message] = interpretNumericExpression(expr, kind)
            % INTERPRETNUMERICEXPRESSION  Interpret a constrained UI numeric expression.
            %
            %   [val,message] = NMSerializationTools.interpretNumericExpression(expr,kind)
            %   validates and evaluates numeric-vector expressions used by browser
            %   controls. Supported syntax is intentionally limited to numeric
            %   literals, MATLAB-style ranges, powers, linspace/logspace and a
            %   small allow-list of numeric functions. Assignment, strings,
            %   command syntax and arbitrary identifiers are rejected before eval.
            %
            %   kind may be 'numeric_vector' or 'number'. The method is shared by
            %   browser bridge fallbacks so individual UI modules do not maintain
            %   separate MATLAB eval validation logic.
            if nargin < 1 || isempty(expr), expr = ''; end
            if nargin < 2 || isempty(kind), kind = 'numeric_vector'; end
            expr = strtrim(char(string(expr)));
            kind = lower(strtrim(char(string(kind))));
            if isempty(expr)
                if strcmp(kind,'number')
                    val = NaN;
                else
                    val = [];
                end
                message = 'Empty numeric expression.';
                return;
            end
            if numel(expr) > 1000
                error('NMSerializationTools:exprTooLong', 'Expression is too long.');
            end
            NMSerializationTools.validateNumericExpression(expr);
            val = eval(expr); %#ok<EVLDIR> % Restricted by validateNumericExpression above.
            if ~(isnumeric(val) || islogical(val))
                error('NMSerializationTools:exprNonNumeric', 'Expression did not evaluate to a numeric value.');
            end
            if ~isreal(val)
                error('NMSerializationTools:exprComplex', 'Complex results are not supported for UI numeric fields.');
            end
            if numel(val) > 5000
                error('NMSerializationTools:exprTooManyValues', 'Expression expands to too many values (%d).', numel(val));
            end
            val = double(val(:))';
            if strcmp(kind,'number')
                if numel(val) ~= 1
                    error('NMSerializationTools:exprNotScalar', 'Expected one numeric value, got %d.', numel(val));
                end
                val = val(1);
            end
            message = 'Expression interpreted by MATLAB.';
        end

        function validateNumericExpression(expr)
            % VALIDATENUMERICEXPRESSION  Validate restricted browser numeric-expression syntax.
            %
            %   NMSerializationTools.validateNumericExpression(expr) rejects
            %   characters and identifiers outside the shared UI numeric-expression
            %   contract before MATLAB evaluation is attempted. This method is not
            %   a general MATLAB parser and must only be used for scalar/vector
            %   browser control inputs.
            expr = char(expr);
            if ~isempty(regexp(expr, '[{}@%=''"\\`]', 'once')) || contains(expr, ';')
                error('NMSerializationTools:unsafeExpression', 'Expression contains unsupported or unsafe characters.');
            end
            if contains(expr, '=') || contains(expr, '!')
                error('NMSerializationTools:unsafeExpression', 'Assignment and command syntax are not supported.');
            end
            ids = regexp(expr, '[A-Za-z_]\w*', 'match');
            allowed = {'inf','nan','pi','eps','linspace','logspace','unique','sort','fliplr','round','floor','ceil','abs','sqrt','exp','log','log10','double','single','e'};
            for i = 1:numel(ids)
                if ~any(strcmpi(ids{i}, allowed))
                    error('NMSerializationTools:unsafeIdentifier', 'Identifier/function is not allowed in UI expressions: %s', ids{i});
                end
            end
            if ~isempty(regexp(expr, '[^0-9A-Za-z_\.\+\-\*\/\^\:\,\[\]\(\)\s]', 'once'))
                error('NMSerializationTools:unsafeExpression', 'Expression contains unsupported characters.');
            end
        end

        function [labels, message] = interpretTextLabelsExpression(expr, maxLabels)
            % INTERPRETTEXTLABELSEXPRESSION  Resolve constrained UI text-label expressions.
            %
            %   [labels,message] = NMSerializationTools.interpretTextLabelsExpression(expr,maxLabels)
            %   resolves alternative feature-name inputs used by browser controls.
            %   The accepted MATLAB-side workspace form is deliberately narrow: a
            %   single base-workspace variable name containing a cellstr/string/char
            %   vector. Quoted cell-array literals are parsed in the browser before
            %   reaching this fallback. No arbitrary MATLAB expression is evaluated.
            if nargin < 1 || isempty(expr), expr = ''; end
            if nargin < 2 || isempty(maxLabels), maxLabels = 5000; end
            expr = strtrim(char(string(expr)));
            maxLabels = max(1, min(50000, round(double(maxLabels))));
            if isempty(expr)
                labels = cell(1,0);
                message = 'Empty label expression.';
                return;
            end
            if numel(expr) > 1000
                error('NMSerializationTools:labelExprTooLong', 'Label expression is too long.');
            end
            if isempty(regexp(expr, '^[A-Za-z_]\w*$', 'once'))
                error('NMSerializationTools:labelExprUnsupported', 'Only a base-workspace variable name is accepted by the MATLAB label fallback. Use quoted cell literals or line text for direct labels.');
            end
            existsFlag = evalin('base', sprintf('exist(''%s'',''var'')', expr));
            if existsFlag ~= 1
                error('NMSerializationTools:labelVariableMissing', 'The alternative-label variable ''%s'' was not found in the MATLAB base workspace.', expr);
            end
            val = evalin('base', expr);
            labels = NMSerializationTools.normalizeTextLabelVector(val, maxLabels);
            message = sprintf('Resolved %d alternative label(s) from MATLAB workspace variable %s.', numel(labels), expr);
        end

        function labels = normalizeTextLabelVector(val, maxLabels)
            % NORMALIZETEXTLABELVECTOR  Normalize cell/string/char label vectors to a row cellstr.
            %
            %   labels = NMSerializationTools.normalizeTextLabelVector(val,maxLabels)
            %   validates user-facing label vectors at the bridge boundary. It is
            %   intentionally text-only and is shared by report and browser services.
            if nargin < 2 || isempty(maxLabels), maxLabels = 5000; end
            maxLabels = max(1, min(50000, round(double(maxLabels))));
            if isstring(val)
                labels = cellstr(val(:))';
            elseif iscellstr(val) %#ok<ISCLSTR>
                labels = val(:)';
            elseif iscell(val)
                try
                    labels = cellfun(@(x) char(string(x)), val(:)', 'UniformOutput', false);
                catch ME
                    error('NMSerializationTools:labelCellInvalid', 'Cell label vector contains non-text values: %s', ME.message);
                end
            elseif ischar(val)
                if size(val,1) <= 1
                    labels = {strtrim(val)};
                else
                    labels = cellstr(val);
                    labels = labels(:)';
                end
            else
                error('NMSerializationTools:labelTypeInvalid', 'Alternative feature labels must be a cell array of strings, a string vector, or a character array.');
            end
            labels = labels(:)';
            labels = cellfun(@(x) char(string(x)), labels, 'UniformOutput', false);
            labels = labels(~cellfun(@(x) isempty(strtrim(x)), labels));
            if numel(labels) > maxLabels
                error('NMSerializationTools:labelTooManyValues', 'Alternative label expression expands to too many labels (%d).', numel(labels));
            end
        end

        function txt = textField(s, field, fallback)
            % TEXTFIELD  Read a named scalar field from a struct as text.
            %
            %   txt = NMSerializationTools.textField(s, field, fallback)
            %   returns fallback unless s is a struct containing a non-empty
            %   field. Numeric scalar values are converted with num2str; char,
            %   string and other scalar-like values are converted to char text.
            %   This is intended for browser-service payload fields where JSON
            %   decoding can yield chars, strings, numerics, or logicals.
            if nargin < 3, fallback = ''; end
            txt = fallback;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                txt = NMSerializationTools.scalarText(s.(field), fallback);
            end
        end

        function val = numericField(s, field, fallback)
            % NUMERICFIELD  Read a named scalar field from a struct as double.
            %
            %   val = NMSerializationTools.numericField(s, field, fallback)
            %   returns fallback unless s contains a non-empty field. Numeric
            %   scalar values are returned as double; other scalar-like values
            %   are converted via str2double. Invalid text therefore becomes
            %   NaN, following MATLAB str2double semantics.
            if nargin < 3, fallback = NaN; end
            val = fallback;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                v = s.(field);
                if isnumeric(v) && isscalar(v)
                    val = double(v);
                else
                    val = str2double(char(string(v)));
                end
            end
        end

        function txt = scalarText(x, fallback)
            % SCALARTEXT  Convert a scalar-like MATLAB value to display text.
            %
            %   txt = NMSerializationTools.scalarText(x, fallback) normalises
            %   empty, char, scalar string, numeric scalar and logical scalar
            %   values into char text. Empty or missing values return fallback.
            %   This helper is used for filenames, table metadata and simple
            %   browser-service options, not for large arrays.
            if nargin < 2, fallback = ''; end
            txt = fallback;
            if isempty(x), return; end
            if ischar(x)
                txt = x;
            elseif isstring(x) && isscalar(x)
                if ~ismissing(x), txt = char(x); end
            elseif isnumeric(x) && isscalar(x)
                txt = num2str(x);
            elseif islogical(x) && isscalar(x)
                txt = char(string(x));
            else
                txt = char(string(x));
            end
        end

        function v = cellScalar(x)
            % CELLSCALAR  Convert a scalar-like value for cell-array export.
            %
            %   v = NMSerializationTools.cellScalar(x) returns a value suitable
            %   for CSV/TSV/XLSX cell output. Numeric and logical scalars keep
            %   their native type; text remains text; unsupported values are
            %   converted through string when possible and otherwise replaced
            %   by '<unserializable>'.
            if isempty(x)
                v = '';
            elseif isnumeric(x) && isscalar(x)
                v = double(x);
            elseif islogical(x) && isscalar(x)
                v = logical(x);
            elseif ischar(x)
                v = x;
            elseif isstring(x) && isscalar(x)
                if ismissing(x), v = ''; else, v = char(x); end
            else
                try
                    v = char(string(x));
                catch
                    v = '<unserializable>';
                end
            end
        end

        function tok = sanitizeToken(txt, fallback)
            % SANITIZETOKEN  Convert arbitrary text into a safe filename token.
            %
            %   tok = NMSerializationTools.sanitizeToken(txt, fallback) keeps
            %   ASCII letters, digits, underscores and hyphens, collapses other
            %   character runs to a single underscore and trims surrounding
            %   underscores. The fallback is used if the token becomes empty.
            if nargin < 2 || isempty(fallback), fallback = 'token'; end
            tok = regexprep(char(string(txt)), '[^A-Za-z0-9_-]+', '_');
            tok = regexprep(tok, '_+', '_');
            tok = regexprep(tok, '^_+|_+$', '');
            if isempty(tok), tok = fallback; end
        end

        function outPath = uniqueOutputPath(outDir, baseName, ext)
            % UNIQUEOUTPUTPATH  Build a non-overwriting output path.
            %
            %   outPath = NMSerializationTools.uniqueOutputPath(outDir,
            %   baseName, ext) sanitises the base name and extension, returns
            %   baseName.ext if unused, and otherwise appends _002..._999.
            %   It errors if no unique filename can be constructed.
            ext = lower(strtrim(char(ext)));
            if startsWith(ext,'.'), ext = ext(2:end); end
            baseName = NMSerializationTools.sanitizeToken(baseName, 'plot');
            outPath = fullfile(outDir, [baseName '.' ext]);
            if exist(outPath, 'file') ~= 2, return; end
            for k = 2:999
                cand = fullfile(outDir, sprintf('%s_%03d.%s', baseName, k, ext));
                if exist(cand, 'file') ~= 2
                    outPath = cand;
                    return;
                end
            end
            error('NMSerializationTools:uniqueNameFailed', 'Could not create a unique export filename in %s.', outDir);
        end

        function [bytes, mime] = decodeDataUrl(dataUrl)
            % DECODEDATAURL  Decode a browser data: URL containing base64 bytes.
            %
            %   [bytes, mime] = NMSerializationTools.decodeDataUrl(dataUrl)
            %   extracts the MIME type and decodes the base64 payload. It first
            %   uses matlab.net.base64decode and falls back to Apache Commons
            %   Base64 for older MATLAB/JVM configurations.
            txt = char(string(dataUrl));
            mime = '';
            tok = regexp(txt, '^data:([^;]+);base64,', 'tokens', 'once');
            if ~isempty(tok), mime = tok{1}; end
            txt = regexprep(txt, '^data:[^;]+;base64,', '', 'ignorecase');
            txt = regexprep(txt, '\s+', '');
            bytes = [];
            if isempty(txt), return; end
            try
                bytes = matlab.net.base64decode(txt);
            catch
                try
                    decoder = org.apache.commons.codec.binary.Base64();
                    bytes = typecast(decoder.decode(uint8(txt)), 'uint8');
                catch ME
                    error('NMSerializationTools:Base64DecodeFailed', 'Base64 decoding failed: %s', ME.message);
                end
            end
            bytes = uint8(bytes(:));
        end

        function writeTextFile(path, txt, errorId, errorMessage, writer)
            % writeTextFile  Write legacy NM text artifacts through one compatibility-preserving helper.
            %
            %   NMSerializationTools.writeTextFile(path,txt,errorId,errorMessage,writer) centralizes
            %   the repeated fopen(path,'w') text-output pattern used by browser UI, DataIO and
            %   runtime-page wrappers. The helper preserves the historical caller-specific error
            %   identifiers and MATLAB default text-file encoding; UTF-8-specific exports should use
            %   writeTextUtf8 instead.
            %
            %   errorId: MATLAB error identifier raised when the target file cannot be opened.
            %   errorMessage: sprintf-compatible message template; path is passed as the first value.
            %   writer: optional writer style. Use 'fwrite-input-char' for fwrite(fid,txt,'char'),
            %   'fwrite-char' for fwrite(fid,char(txt)), or 'fprintf-s' for fprintf(fid,'%s',txt).
            if nargin < 3 || isempty(errorId), errorId = 'NMSerializationTools:writeFailed'; end
            if nargin < 4 || isempty(errorMessage), errorMessage = 'Could not write %s.'; end
            if nargin < 5 || isempty(writer), writer = 'fwrite-input-char'; end
            fid = fopen(path, 'w');
            if fid < 0
                error(errorId, errorMessage, path);
            end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            writer = char(string(writer));
            switch writer
                case 'fprintf-s'
                    fprintf(fid, '%s', txt);
                case 'fwrite-char'
                    fwrite(fid, char(txt));
                otherwise
                    fwrite(fid, txt, 'char');
            end
        end

        function writeTextUtf8(path, txt)
            % WRITETEXTUTF8  Write text to disk using UTF-8 encoding.
            %
            %   NMSerializationTools.writeTextUtf8(path, txt) opens path for
            %   text output, writes txt as char data, and closes the file via
            %   onCleanup. File-open failures raise an explicit error.
            fid = fopen(path, 'w', 'n', 'UTF-8');
            if fid < 0, error('NMSerializationTools:writeFailed', 'Could not open %s for writing.', path); end
            cleaner = onCleanup(@()fclose(fid)); %#ok<NASGU>
            fwrite(fid, char(string(txt)), 'char');
        end

        function writeBytes(path, bytes)
            % WRITEBYTES  Write a uint8 byte vector to disk.
            %
            %   NMSerializationTools.writeBytes(path, bytes) writes raw bytes
            %   without text encoding or newline transformation. File-open
            %   failures raise an explicit error.
            fid = fopen(path, 'W');
            if fid < 0, error('NMSerializationTools:writeFailed', 'Could not open %s for writing.', path); end
            cleaner = onCleanup(@()fclose(fid)); %#ok<NASGU>
            fwrite(fid, bytes, 'uint8');
        end

        function writeDelimited(path, C, delimiter)
            % WRITEDELIMITED  Write a cell matrix as UTF-8 CSV/TSV-like text.
            %
            %   NMSerializationTools.writeDelimited(path, C, delimiter) writes
            %   each row of C using delimiter. Cells are escaped through
            %   escapeDelimited so quotes, delimiters and embedded newlines are
            %   represented safely.
            fid = fopen(path, 'w', 'n', 'UTF-8');
            if fid < 0, error('NMSerializationTools:writeFailed', 'Could not open %s for writing.', path); end
            cleaner = onCleanup(@()fclose(fid)); %#ok<NASGU>
            for r = 1:size(C,1)
                parts = cell(1,size(C,2));
                for c = 1:size(C,2)
                    parts{c} = NMSerializationTools.escapeDelimited(C{r,c}, delimiter);
                end
                fprintf(fid, '%s\n', strjoin(parts, delimiter));
            end
        end

        function txt = escapeDelimited(v, delimiter)
            % ESCAPEDELIMITED  Escape a scalar value for delimited-text output.
            %
            %   txt = NMSerializationTools.escapeDelimited(v, delimiter)
            %   converts numeric/logical/text values to one field string. Text
            %   containing quotes, newlines or the delimiter is quoted and
            %   embedded quotes are doubled according to CSV conventions.
            if isnumeric(v) && isscalar(v)
                if isnan(v), txt = ''; else, txt = num2str(v, 15); end
                return;
            end
            if islogical(v) && isscalar(v)
                txt = char(string(v));
                return;
            end
            txt = char(string(v));
            txt = strrep(txt, sprintf('\r\n'), sprintf('\n'));
            txt = strrep(txt, sprintf('\r'), sprintf('\n'));
            needsQuote = contains(txt, '"') || contains(txt, sprintf('\n')) || contains(txt, delimiter);
            txt = strrep(txt, '"', '""');
            if needsQuote
                txt = ['"' txt '"'];
            end
        end
    end
end

classdef NMUIErrorTools
% NMUIErrorTools
% -------------------------------------------------------------------------
% Small shared formatter for MATLAB errors sent to browser UI pages.
% The browser message strip must show enough stack context to identify the
% failing MATLAB source.  Keep this independent of DataIO-specific diagnostics
% so every browser service can use the same error contract.
% -------------------------------------------------------------------------

    methods (Static)
        function out = exceptionStruct(ME, operation, prefix, minFrames)
            % exceptionStruct  Convert a MATLAB exception into a browser diagnostic struct.
            %
            % Captures identifier, message and a bounded stack trace for service responses. This is the
            % preferred UI boundary for caught errors because it preserves actionable diagnostics.

            if nargin < 2 || isempty(operation), operation = ''; end
            if nargin < 3 || isempty(prefix), prefix = 'Operation failed.'; end
            if nargin < 4 || isempty(minFrames), minFrames = 2; end
            prefix = char(string(prefix));
            op = char(string(operation));
            msg = NMUIErrorTools.messageWithStack(ME, prefix, minFrames);
            out = struct();
            out.ok = false;
            out.blocking = true;
            out.operation = op;
            out.message = msg;
            out.error = ME.message;
            out.identifier = ME.identifier;
            out.stackText = NMUIErrorTools.stackText(ME, minFrames);
            out.stack = NMUIErrorTools.stackStruct(ME);
            out.diagnostic = NMUIErrorTools.diagnosticText(ME);
            out.strip = struct('severity','danger','text',msg);
        end

        function msg = messageWithStack(ME, prefix, minFrames)
            % messageWithStack  Combine an exception message with selected stack frames.
            %
            % Builds concise text for message strips while retaining enough source context for
            % maintainers. The minFrames argument controls diagnostic depth.

            if nargin < 2 || isempty(prefix), prefix = 'Operation failed.'; end
            if nargin < 3 || isempty(minFrames), minFrames = 2; end
            base = sprintf('%s %s', char(string(prefix)), ME.message);
            if ~isempty(ME.identifier)
                base = sprintf('%s (%s)', base, ME.identifier);
            end
            st = NMUIErrorTools.stackText(ME, minFrames);
            if isempty(st)
                msg = base;
            else
                msg = sprintf('%s\n%s', base, st);
            end
        end

        function txt = stackText(ME, minFrames)
            % stackText  Format selected MATLAB stack frames as text.
            %
            % Extracts source file, function and line information from an exception stack for
            % browser-visible diagnostics. It does not suppress the originating error.

            if nargin < 2 || isempty(minFrames), minFrames = 2; end
            txt = '';
            st = ME.stack;
            if isempty(st)
                txt = 'MATLAB stack: unavailable.';
                return;
            end
            n = min(max(double(minFrames), 2), numel(st));
            lines = cell(1, n + 1);
            lines{1} = sprintf('MATLAB stack, top %d frame(s):', n);
            for i = 1:n
                file = st(i).file;
                name = st(i).name;
                line = st(i).line;
                if ~isempty(file)
                    lines{i+1} = sprintf('  %d. %s, line %g (%s)', i, name, line, file);
                else
                    lines{i+1} = sprintf('  %d. %s, line %g', i, name, line);
                end
            end
            txt = strjoin(lines, newline);
        end

        function s = stackStruct(ME)
            % stackStruct  Convert a MATLAB exception stack into a struct array.
            %
            % Creates a JSON-friendly stack representation used by service responses and logs. The output
            % schema is stable for browser consumers.

            s = struct('file',{},'name',{},'line',{});
            st = ME.stack;
            if isempty(st), return; end
            s = repmat(struct('file','','name','','line',NaN), 1, numel(st));
            for i = 1:numel(st)
                s(i).file = st(i).file;
                s(i).name = st(i).name;
                s(i).line = double(st(i).line);
            end
        end

        function txt = diagnosticText(ME)
            % diagnosticText  Return a compact diagnostic string for an exception.
            %
            % Formats identifier, message and first stack location for logs or fallback UI messages where
            % a full diagnostic struct is unnecessary.

            txt = getReport(ME, 'extended', 'hyperlinks', 'off');
        end
    end
end

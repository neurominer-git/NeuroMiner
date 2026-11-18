classdef NMDataIOMessageTools
% NMDataIOMessageTools
% -------------------------------------------------------------------------
% Adapter between the legacy DataIO message structure and the shared
% browser message-strip/diagnostics vocabulary.
%
% Legacy DataIO helpers produce arrays with fields:
%   mess(i).format   e.g. 'red*', 'green*', 'blue', 'SystemCommands'
%   mess(i).flag     1 = blocking/fatal, 2 = warning, 0 = information/status
%   mess(i).text     message body
%
% Browser/API code should consume normalized messages with fields:
%   level            'danger' | 'warn' | 'info' | 'ok'
%   blocking         logical
%   source           producer/helper name
%   text             sanitized text
%   legacyFlag       original flag
%   legacyFormat     original format
% -------------------------------------------------------------------------

    methods (Static)
        function messages = fromLegacyMess(mess, source)
            % fromLegacyMess  Convert legacy NeuroMiner message cells into structured DataIO diagnostics.
            %
            % Mess, source -> messages.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 2 || isempty(source), source = 'legacyDataIO'; end
            if isempty(mess)
                messages = NMDataIOMessageTools.emptyMessages();
                return;
            end
            if ~isstruct(mess)
                messages = NMDataIOMessageTools.make('warn', false, source, ...
                    sprintf('Legacy DataIO returned a non-struct message object of class %s.', class(mess)), NaN, class(mess));
                return;
            end

            messages = NMDataIOMessageTools.emptyMessages();
            k = 0;
            for i = 1:numel(mess)
                if ~isfield(mess, 'text') || isempty(mess(i).text)
                    continue;
                end
                k = k + 1;
                flag = NMDataIOMessageTools.getField(mess(i), 'flag', NaN);
                fmt  = NMDataIOMessageTools.getField(mess(i), 'format', '');
                txt  = NMDataIOMessageTools.cleanText(mess(i).text);
                [level, blocking] = NMDataIOMessageTools.levelFromLegacy(flag, fmt, txt);
                messages(k,1) = NMDataIOMessageTools.make(level, blocking, source, txt, flag, fmt); %#ok<AGROW>
                messages(k,1).index = i;
            end
            if k == 0
                messages = NMDataIOMessageTools.emptyMessages();
            end
        end

        function messages = fromException(ME, source)
            % fromException  Convert a MATLAB exception into a structured fatal DataIO diagnostic.
            %
            % ME, source -> messages.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 2 || isempty(source), source = 'DataIO'; end
            % One MATLAB exception formatter; this adapter only maps its text to
            % the established DataIO severity/diagnostics schema.
            txt = NMUIErrorTools.messageWithStack(ME, source, 3);
            messages = NMDataIOMessageTools.make('danger', true, source, NMDataIOMessageTools.cleanText(txt), 1, 'red*');
        end

        function tf = hasFatal(messages)
            % hasFatal  Return whether any structured DataIO diagnostic blocks preview or commit.
            %
            % Messages -> tf.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            tf = false;
            if isempty(messages), return; end
            if ~isstruct(messages), return; end
            if isfield(messages,'blocking')
                try
                    tf = any([messages.blocking]);
                catch
                    tf = false;
                end
            end
        end

        function strip = highestPriorityStrip(messages, defaultText)
            % highestPriorityStrip  Select the message-strip text/level that should represent a diagnostic list in the UI.
            %
            % Messages, defaultText -> strip.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 2 || isempty(defaultText), defaultText = 'Ready.'; end
            strip = struct('level', 'info', 'text', char(defaultText), 'blocking', false, ...
                'count', 0, 'nDanger', 0, 'nWarn', 0, 'nOk', 0, 'nInfo', 0, 'nBlocking', 0);
            if isempty(messages) || ~isstruct(messages)
                return;
            end
            levels = {messages.level};
            strip.count = numel(messages);
            strip.nDanger = sum(strcmp(levels,'danger'));
            strip.nWarn   = sum(strcmp(levels,'warn'));
            strip.nOk     = sum(strcmp(levels,'ok'));
            strip.nInfo   = sum(strcmp(levels,'info'));
            if isfield(messages,'blocking')
                try
                    strip.nBlocking = sum([messages.blocking]);
                catch
                    strip.nBlocking = 0;
                end
            end
            strip.blocking = strip.nBlocking > 0;

            if strip.nDanger > 0
                idx = find(strcmp(levels,'danger'),1,'first');
                strip.level = 'danger';
                if strip.nBlocking > 0
                    strip.text = sprintf('Import cannot continue because %g issue(s) need attention. First issue: %s', strip.nBlocking, messages(idx).text);
                else
                    strip.text = sprintf('DataIO error: %s', messages(idx).text);
                end
            elseif strip.nWarn > 0
                idx = find(strcmp(levels,'warn'),1,'first');
                strip.level = 'warn';
                strip.text = sprintf('Import can continue, but %g warning(s) need review. First warning: %s', strip.nWarn, messages(idx).text);
            elseif strip.nOk > 0
                idx = find(strcmp(levels,'ok'),1,'last');
                strip.level = 'ok';
                strip.text = messages(idx).text;
            elseif strip.nInfo > 0
                idx = find(strcmp(levels,'info'),1,'last');
                strip.level = 'info';
                strip.text = messages(idx).text;
            end
            if strip.count > 1
                strip.text = sprintf('%s\n(%g message(s) available; open Diagnostics for details.)', strip.text, strip.count);
            end
        end

        function panel = forDiagnosticsPanel(messages)
            % forDiagnosticsPanel  Convert structured messages into rows suitable for the diagnostics panel.
            %
            % Messages -> panel.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if isempty(messages) || ~isstruct(messages)
                panel = NMDataIOMessageTools.emptyMessages();
                return;
            end
            panel = messages;
        end

        function s = summarize(messages)
            % summarize  Build compact counts and representative text from a diagnostic-message array.
            %
            % Messages -> s.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'No DataIO diagnostics.');
            s = struct();
            s.count = strip.count;
            s.blocking = strip.blocking;
            s.nDanger = strip.nDanger;
            s.nWarn = strip.nWarn;
            s.nOk = strip.nOk;
            s.nInfo = strip.nInfo;
            s.strip = strip;
        end

        function msg = make(level, blocking, source, text, legacyFlag, legacyFormat)
            % make  Construct one normalized DataIO diagnostic message record.
            %
            % Consumes level, blocking, source, text, legacyFlag, legacyFormat; returns msg.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 1 || isempty(level), level = 'info'; end
            if nargin < 2 || isempty(blocking), blocking = false; end
            if nargin < 3 || isempty(source), source = ''; end
            if nargin < 4 || isempty(text), text = ''; end
            if nargin < 5, legacyFlag = NaN; end
            if nargin < 6, legacyFormat = ''; end
            msg = struct();
            msg.level = NMDataIOMessageTools.normalizeLevel(level);
            msg.blocking = logical(blocking);
            msg.source = char(source);
            msg.text = NMDataIOMessageTools.cleanText(text);
            msg.legacyFlag = legacyFlag;
            msg.legacyFormat = char(string(legacyFormat));
            msg.index = NaN;
        end

        function messages = emptyMessages()
            % emptyMessages  Return the canonical empty diagnostic-message array.
            %
            % No required inputs -> messages.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            messages = repmat(struct('level','','blocking',false,'source','','text','', ...
                'legacyFlag',NaN,'legacyFormat','','index',NaN),0,1);
        end

        function [level, blocking] = levelFromLegacy(flag, fmt, txt)
            % levelFromLegacy  Translate legacy message flags/formats into severity and blocking status.
            %
            % Consumes flag, fmt, txt; returns level, blocking.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if isempty(flag), flag = NaN; end
            if islogical(flag), flag = double(flag); end
            fmt = lower(char(string(fmt)));
            lowTxt = lower(char(string(txt)));
            blocking = false;

            if isnumeric(flag) && isfinite(flag) && flag == 1
                level = 'danger';
                blocking = true;
                return;
            end
            if isnumeric(flag) && isfinite(flag) && flag == 2
                level = 'warn';
                return;
            end
            if contains(lowTxt, 'error') && (contains(fmt,'red') || startsWith(strtrim(lowTxt),'error'))
                level = 'danger';
                blocking = true;
                return;
            end
            if contains(lowTxt, 'warning') || contains(fmt, 'systemcommands')
                if contains(lowTxt, 'error:')
                    level = 'danger';
                    blocking = true;
                else
                    level = 'warn';
                end
                return;
            end
            % Legacy DataIO uses blue as informational/status formatting even
            % when the message text contains phrases such as "tests passed".
            % Therefore explicit blue formatting must take precedence over
            % text-based success heuristics.
            if contains(fmt, 'blue')
                level = 'info';
                return;
            end
            if contains(fmt, 'green') || startsWith(strtrim(lowTxt), ':-d') || contains(lowTxt, 'tests passed')
                level = 'ok';
                return;
            end
            if isnumeric(flag) && isfinite(flag) && flag == 0
                level = 'info';
                return;
            end
            level = 'info';
        end

        function level = normalizeLevel(level)
            % normalizeLevel  Normalize caller input into the canonical representation used by the DataIO flow.
            %
            % Level -> level.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            level = lower(char(string(level)));
            switch level
                case {'danger','error'}
                    level = 'danger';
                case {'warn','warning'}
                    level = 'warn';
                case {'ok','success'}
                    level = 'ok';
                otherwise
                    level = 'info';
            end
        end

        function txt = cleanText(txt)
            % cleanText  Normalize diagnostic message text before UI/API rendering.
            %
            % Txt -> txt.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isa(txt,'string'), txt = char(txt); end
            if isnumeric(txt), txt = num2str(txt); end
            if iscell(txt), txt = strjoin(cellfun(@char, txt, 'UniformOutput', false), newline); end
            txt = char(txt);
            txt = strrep(txt, sprintf('\r\n'), newline);
            txt = strrep(txt, sprintf('\r'), newline);
            txt = regexprep(txt, '\\', '/');
            txt = strtrim(txt);
        end

        function v = getField(s, name, defaultValue)
            % getField  Read a struct field with a caller-specific default for message/metadata normalization.
            %
            % Consumes s, name, defaultValue; returns v.
            % It ensures legacy, exception, and service messages share one severity/blocking contract for UI and API callers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isstruct(s) && isfield(s, name)
                v = s.(name);
            else
                v = defaultValue;
            end
        end
    end
end

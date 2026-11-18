classdef NMDataIOProfileTools
% NMDataIOProfileTools
% -------------------------------------------------------------------------
% Lightweight, centrally gated timing diagnostics for DataIO browser service
% calls. Disabled by default and governed by the application-wide UI profiler:
%   setenv('NM_UI_PROFILE','1')
% Optional request/option ProfileEnabled flags remain supported for focused tests.
% -------------------------------------------------------------------------

    methods (Static)
        function tf = enabled(req, ctx, opts)
            % enabled  Return whether DataIO profiling is enabled for the requested operation/context.
            %
            % Consumes req, ctx, opts; returns tf.
            % It is diagnostic instrumentation only and must not affect DataIO behavior when disabled.
            % Reads only explicit request/option flags and the application-wide NM_UI_PROFILE environment switch.
            tf = false;
            if nargin >= 3 && isstruct(opts)
                tf = NMDataIOProfileTools.scalarFlag(opts, {'ProfileEnabled','profileEnabled','Profile','profile'});
                if tf, return; end
            end
            if nargin >= 1 && isstruct(req)
                tf = NMDataIOProfileTools.scalarFlag(req, {'ProfileEnabled','profileEnabled','dataioProfile','DataIOProfile','profile'});
                if tf, return; end
            end
            if nargin >= 2 && isstruct(ctx)
                tf = NMDataIOProfileTools.scalarFlag(ctx, {'ProfileEnabled','profileEnabled','dataioProfile','DataIOProfile','profile'});
                if tf, return; end
            end
            try
                ev = getenv('NM_UI_PROFILE');
                if ~isempty(ev)
                    tf = NMDataIOProfileTools.asLogical(ev);
                end
            catch
                tf = false;
            end
        end

        function log(enabled, varargin)
            % log  Emit a timestamped DataIO profiling line when profiling is enabled.
            %
            % Enabled, varargin -> no explicit output.
            % It is diagnostic instrumentation only and must not affect DataIO behavior when disabled.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 1 || ~enabled, return; end
            try
                fprintf('[nm-prof] ');
                fprintf(varargin{:});
                if isempty(varargin) || isempty(varargin{1}) || varargin{1}(end) ~= sprintf('\n')
                    fprintf('\n');
                end
            catch
                % Profiling must never affect DataIO execution.
            end
        end

        function label = opLabel(op)
            % opLabel  Normalize profiling operation identifiers into stable display labels.
            %
            % Op -> label.
            % It is diagnostic instrumentation only and must not affect DataIO behavior when disabled.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 1 || isempty(op)
                label = 'unknown';
            else
                label = char(string(op));
            end
        end

        function s = nmSizeSummary(NM)
            % nmSizeSummary  Return a compact size summary for major NM containers during profiling.
            %
            % NM -> s.
            % It is diagnostic instrumentation only and must not affect DataIO behavior when disabled.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            s = 'NM size unavailable';
            try
                if ~isstruct(NM)
                    s = class(NM);
                    return;
                end
                nMods = 0;
                yTxt = '';
                if isfield(NM,'Y') && iscell(NM.Y)
                    nMods = numel(NM.Y);
                    parts = cell(1,nMods);
                    for i = 1:nMods
                        if isempty(NM.Y{i})
                            parts{i} = sprintf('#%d empty', i);
                        else
                            sz = size(NM.Y{i});
                            if numel(sz) < 2, sz(2) = 1; end
                            parts{i} = sprintf('#%d %dx%d %s', i, sz(1), sz(2), class(NM.Y{i}));
                        end
                    end
                    yTxt = strjoin(parts, '; ');
                end
                nCases = NaN;
                if isfield(NM,'cases') && iscell(NM.cases)
                    nCases = numel(NM.cases);
                elseif isfield(NM,'cases')
                    nCases = numel(NM.cases);
                end
                s = sprintf('modalities=%d, cases=%g, Y={%s}', nMods, double(nCases), yTxt);
            catch
                s = 'NM size summary failed';
            end
        end
    end

    methods (Static, Access = private)
        function tf = scalarFlag(S, names)
            tf = false;
            for i = 1:numel(names)
                if isfield(S, names{i}) && ~isempty(S.(names{i}))
                    tf = NMDataIOProfileTools.asLogical(S.(names{i}));
                    if tf, return; end
                end
            end
        end

        function tf = asLogical(v)
            tf = false;
            if islogical(v) || isnumeric(v)
                tf = isscalar(v) && logical(v);
            elseif ischar(v) || isstring(v)
                txt = lower(strtrim(char(string(v))));
                tf = ismember(txt, {'1','true','on','yes','y','profile'});
            end
        end
    end
end

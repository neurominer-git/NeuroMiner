classdef NMUIBridgeTools
% NMUIBridgeTools
% -------------------------------------------------------------------------
% Process-local registry and lifecycle control for NeuroMiner browser bridges.
% Registry state is user-private and MATLAB-process scoped so Ctrl+C cleanup
% cannot target another user's or another MATLAB process's bridge session.
% -------------------------------------------------------------------------

    methods (Static)
        function registerActiveBridge(webDir, tmpDir, port, runId, entryHtml)
            % registerActiveBridge  Record one bridge owned by the current MATLAB process.
            if nargin < 5, entryHtml = ''; end
            ident = NMUISessionTools.userIdentity();
            rec = struct('webDir',char(string(webDir)), 'tmpDir',char(string(tmpDir)), ...
                'port',double(port), 'runId',char(string(runId)), ...
                'entryHtml',char(string(entryHtml)), 'registeredAt',datestr(now, 30), ...
                'user',char(string(ident.user)), 'uid',char(string(ident.uid)), ...
                'matlabPid',double(ident.pid));
            if isempty(rec.runId)
                error('NMUIBridgeTools:missingRunId','An active bridge cannot be registered without its runId.');
            end
            entries = NMUIBridgeTools.readRegistry();
            keep = true(1, numel(entries));
            for i = 1:numel(entries)
                keep(i) = ~(strcmpi(char(string(entries(i).tmpDir)), rec.tmpDir) || ...
                    strcmp(char(string(entries(i).runId)), rec.runId));
            end
            entries = entries(keep);
            entries(end+1) = rec; %#ok<AGROW>
            NMUIBridgeTools.writeRegistry(entries);
        end

        function unregisterActiveBridge(tmpDir, port, runId)
            % unregisterActiveBridge  Remove only the matching bridge owned by this MATLAB process.
            entries = NMUIBridgeTools.readRegistry();
            if isempty(entries), return; end
            tmpDir = char(string(tmpDir));
            runIdValue = '';
            if nargin >= 3 && ~isempty(runId), runIdValue = char(string(runId)); end
            keep = true(1, numel(entries));
            for i = 1:numel(entries)
                sameRun = ~isempty(runIdValue) && strcmp(char(string(entries(i).runId)), runIdValue);
                sameTmp = ~isempty(tmpDir) && strcmpi(char(string(entries(i).tmpDir)), tmpDir);
                if sameRun || (isempty(runIdValue) && sameTmp)
                    keep(i) = false;
                end
            end
            if nargin >= 2 && ~isempty(port) && isempty(runIdValue) && all(keep)
                % Port-only unregistering is intentionally forbidden: a recycled port
                % is not a bridge identity and must never select another session.
                warning('NMUIBridgeTools:portOnlyUnregisterIgnored', ...
                    'Bridge unregister did not find tmpDir %s; port %g was not used as an identity.', tmpDir, double(port));
            end
            NMUIBridgeTools.writeRegistry(entries(keep));
        end

        function report = killActiveBridges(message)
            % killActiveBridges  Shut down bridges registered by the current MATLAB process only.
            if nargin < 1 || isempty(message)
                message = 'NeuroMiner was interrupted from the MATLAB command window. The browser bridge is shutting down.';
            end
            entries = NMUIBridgeTools.readRegistry();
            report = struct('ok',true,'message','No active NeuroMiner UI bridge was registered.','n',0,'details',struct([]));
            if isempty(entries), return; end
            details = repmat(struct('port',NaN,'tmpDir','','runId','','notified',false,'httpMessage','','flagWritten',false), 1, numel(entries));
            for i = 1:numel(entries)
                details(i).port = double(entries(i).port);
                details(i).tmpDir = char(string(entries(i).tmpDir));
                details(i).runId = char(string(entries(i).runId));
                payload = struct('ok',false,'killed',true,'severity','danger', ...
                    'message',char(string(message)), 'time',datestr(now, 31), ...
                    'runId',details(i).runId);
                details(i).flagWritten = NMUIBridgeTools.writeKillFlag(details(i).tmpDir, payload);
                details(i).notified = details(i).flagWritten;
                if details(i).flagWritten
                    details(i).httpMessage = 'runId-bound filesystem control signal written';
                else
                    details(i).httpMessage = 'bridge session directory is unavailable';
                end
            end
            report.message = sprintf('Requested shutdown for %d registered NeuroMiner UI bridge(s) owned by this MATLAB process.', numel(entries));
            report.n = numel(entries);
            report.details = details;
            NMUIBridgeTools.writeRegistry(NMUIBridgeTools.emptyRegistry());
        end

        function tf = writeKillFlag(tmpDir, payload)
            % writeKillFlag  Persist one runId-bound filesystem kill request.
            tf = false;
            if isempty(tmpDir) || exist(tmpDir,'dir') ~= 7, return; end
            if ~isstruct(payload) || ~isfield(payload,'runId') || isempty(payload.runId)
                error('NMUIBridgeTools:killFlagMissingRunId','Bridge kill flags must be bound to a runId.');
            end
            fp = fullfile(char(string(tmpDir)), 'ui_kill.json');
            txt = jsonencode(payload);
            tmp = [fp '.tmp_' strrep(char(java.util.UUID.randomUUID()),'-','')];
            fid = fopen(tmp, 'w');
            if fid < 0
                error('NMUIBridgeTools:killFlagWriteFailed','Could not open bridge kill flag for writing: %s', tmp);
            end
            try
                fwrite(fid, txt, 'char');
                fclose(fid);
            catch ME
                fclose(fid);
                if exist(tmp,'file') == 2, delete(tmp); end
                rethrow(ME);
            end
            [ok,msg] = movefile(tmp, fp, 'f');
            if ~ok
                if exist(tmp,'file') == 2, delete(tmp); end
                error('NMUIBridgeTools:killFlagReplaceFailed','Could not atomically replace bridge kill flag %s: %s', fp, msg);
            end
            tf = true;
        end

        function token = authorizeControllerReopen(tmpDir, runId, previousClientId)
            % authorizeControllerReopen  One-use authorization for MATLAB-approved controller replacement.
            token = strrep(char(java.util.UUID.randomUUID()), '-', '');
            record = struct('runId',runId, 'previousClientId',previousClientId, 'token',token);
            fp = fullfile(tmpDir, 'ui_reopen.json');
            tmp = [fp '.tmp_' token];
            fid = fopen(tmp,'w');
            if fid < 0
                error('NMUIBridgeTools:reopenWriteFailed','Cannot create controller-reopen authorization: %s',tmp);
            end
            try
                fwrite(fid,jsonencode(record),'char');
                fclose(fid);
            catch ME
                fclose(fid);
                delete(tmp);
                rethrow(ME);
            end
            [ok,msg] = movefile(tmp,fp,'f');
            if ~ok
                delete(tmp);
                error('NMUIBridgeTools:reopenReplaceFailed','Cannot authorize controller reopen: %s',msg);
            end
        end

        function entries = readRegistry()
            % readRegistry  Load the current user's current-MATLAB-process bridge registry.
            entries = NMUIBridgeTools.emptyRegistry();
            fp = NMUIBridgeTools.registryPath();
            if exist(fp,'file') ~= 2, return; end
            raw = NMConfigTools.decodeJson(fileread(fp));
            if isstruct(raw) && isfield(raw,'entries')
                entries = NMConfigTools.charifyStrings(raw.entries);
            elseif isstruct(raw)
                entries = NMConfigTools.charifyStrings(raw);
            else
                error('NMUIBridgeTools:invalidRegistry','Bridge registry is not a JSON object: %s', fp);
            end
            if isempty(entries), entries = NMUIBridgeTools.emptyRegistry(); end
        end

        function writeRegistry(entries)
            % writeRegistry  Persist the process-local bridge registry in the user-private NM2 root.
            fp = NMUIBridgeTools.registryPath();
            payload = struct('entries', entries, 'updatedAt', datestr(now, 31));
            txt = jsonencode(payload);
            tmp = [fp '.tmp_' strrep(char(java.util.UUID.randomUUID()),'-','')];
            fid = fopen(tmp, 'w');
            if fid < 0
                error('NMUIBridgeTools:registryWriteFailed','Could not write bridge registry temporary file: %s', tmp);
            end
            try
                fwrite(fid, txt, 'char');
                fclose(fid);
            catch ME
                fclose(fid);
                if exist(tmp,'file') == 2, delete(tmp); end
                rethrow(ME);
            end
            [ok,msg] = movefile(tmp, fp, 'f');
            if ~ok
                if exist(tmp,'file') == 2, delete(tmp); end
                error('NMUIBridgeTools:registryReplaceFailed','Could not atomically replace bridge registry %s: %s', fp, msg);
            end
        end

        function fp = registryPath()
            % registryPath  Return the user-private, MATLAB-process-specific registry path.
            ident = NMUISessionTools.userIdentity();
            root = NMUISessionTools.privateTempRoot('bridge_registry');
            fp = fullfile(root, sprintf('nm_active_ui_bridges_pid_%d.json', round(ident.pid)));
        end

        function s = urlEncode(x)
            % urlEncode  Percent-encode bridge query-string values.
            s = char(string(x));
            try
                s = char(java.net.URLEncoder.encode(s, 'UTF-8'));
            catch
                s = strrep(s, ' ', '%20');
                s = strrep(s, newline, '%0A');
            end
        end
    end

    methods (Static, Access = private)
        function entries = emptyRegistry()
            entries = struct('webDir',{},'tmpDir',{},'port',{},'runId',{}, ...
                'entryHtml',{},'registeredAt',{},'user',{},'uid',{},'matlabPid',{});
        end
    end
end

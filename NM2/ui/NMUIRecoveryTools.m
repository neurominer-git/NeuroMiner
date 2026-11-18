classdef NMUIRecoveryTools
% NMUIRecoveryTools
% -------------------------------------------------------------------------
% Deterministic browser-draft lifecycle/recovery support for NM2 UI sessions.
%
% Authority split
%   recovery_manifest.json : lifecycle/ownership/compatibility metadata only.
%   ui_draft_*.json        : sole browser recovery payload and route authority.
%
% Browser drafts never replace NM scientific/runtime authorities. Recovery
% restores browser state and page adapters reconcile canonical state through
% the page's existing persistence/materialization path.
% -------------------------------------------------------------------------

    methods (Static)
        function id = matlabSessionId()
            persistent sessionId
            if isempty(sessionId)
                sessionId = strrep(char(java.util.UUID.randomUUID()),'-','');
            end
            id = sessionId;
        end

        function ctx = recoveryContext(NM)
            ctx = struct('schemaVersion',1,'kind','structural','nmId','','fingerprint','');
            if isstruct(NM) && isfield(NM,'id') && ~isempty(NM.id)
                idText = NMUIRecoveryTools.scalarText(NM.id);
                if ~isempty(idText)
                    ctx.kind = 'nm-id';
                    ctx.nmId = idText;
                    ctx.fingerprint = NMUIRecoveryTools.sha256(['nm-id:' idText]);
                    return;
                end
            end
            projection = struct();
            projection.nModalities = NMUIRecoveryTools.modalityCount(NM);
            projection.modalitySizes = NMUIRecoveryTools.modalitySizes(NM);
            projection.labelSize = NMUIRecoveryTools.fieldSize(NM,'label');
            projection.covarSize = NMUIRecoveryTools.fieldSize(NM,'covars');
            projection.nAnalyses = NMUIRecoveryTools.analysisCount(NM);
            projection.hasDefs = isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs);
            ctx.fingerprint = NMUIRecoveryTools.sha256(jsonencode(projection));
        end

        function manifest = initialize(tmpDir, NM, initialPage)
            if nargin < 3 || isempty(initialPage), initialPage = 'landing'; end
            ident = NMUISessionTools.userIdentity();
            manifest = struct();
            manifest.schemaVersion = 2;
            manifest.lifecycleState = 'active';
            manifest.createdAt = datestr(now,31);
            manifest.updatedAt = manifest.createdAt;
            manifest.reconciledAt = '';
            manifest.cleanupReason = '';
            manifest.matlabSessionId = NMUIRecoveryTools.matlabSessionId();
            manifest.nmInstanceId = strrep(char(java.util.UUID.randomUUID()),'-','');
            manifest.matlabPid = double(ident.pid);
            manifest.user = char(string(ident.user));
            manifest.uid = char(string(ident.uid));
            manifest.runId = '';
            manifest.port = NaN;
            manifest.sessionDir = char(string(tmpDir));
            manifest.initialPage = char(string(initialPage));
            manifest.context = NMUIRecoveryTools.recoveryContext(NM);
            NMUIRecoveryTools.writeManifest(tmpDir, manifest);
        end

        function quiesceOrphanBridges(root)
            if nargin < 1 || isempty(root)
                error('NMUIRecoveryTools:missingRecoveryRoot', ...
                    'Recovery discovery requires the resolved NM2 session root.');
            end
            webRoot = fullfile(char(string(root)),'web');
            if exist(webRoot,'dir') ~= 7, return; end
            dirs = dir(fullfile(webRoot,'session_*'));
            currentIdent = NMUISessionTools.userIdentity();
            currentSession = NMUIRecoveryTools.matlabSessionId();
            for i = 1:numel(dirs)
                if ~dirs(i).isdir, continue; end
                tmpDir = fullfile(webRoot,dirs(i).name,'tmp');
                m = NMUIRecoveryTools.readManifest(tmpDir);
                if isempty(m), continue; end
                state = lower(NMUIRecoveryTools.fieldText(m,'lifecycleState'));
                if strcmp(state,'unfinished')
                    if NMUIRecoveryTools.bridgeResponds(m)
                        NMUIRecoveryTools.quiesceSourceBridge(struct('tmpDir',tmpDir,'manifest',m));
                    end
                elseif strcmp(state,'active') && NMUIRecoveryTools.ownerIsOrphan(m,currentIdent,currentSession)
                    NMUIRecoveryTools.quiesceSourceBridge(struct('tmpDir',tmpDir,'manifest',m));
                    NMUIRecoveryTools.markUnfinished(tmpDir,'matlab-owner-lost');
                end
            end
        end

        function markUnfinished(tmpDir, reason)
            if nargin < 2 || isempty(reason), reason = 'unfinished'; end
            m = NMUIRecoveryTools.readManifest(tmpDir);
            if isempty(m), return; end
            m.lifecycleState = 'unfinished';
            m.cleanupReason = char(string(reason));
            m.updatedAt = datestr(now,31);
            NMUIRecoveryTools.writeManifest(tmpDir,m);
        end

        function markReconciled(tmpDir, reason)
            if nargin < 2 || isempty(reason), reason = 'clean-finish'; end
            m = NMUIRecoveryTools.readManifest(tmpDir);
            if isempty(m), return; end
            m.lifecycleState = 'reconciled';
            m.cleanupReason = char(string(reason));
            m.reconciledAt = datestr(now,31);
            m.updatedAt = m.reconciledAt;
            NMUIRecoveryTools.writeManifest(tmpDir,m);
            NMUIRecoveryTools.deleteDrafts(tmpDir);
        end

        function markDiscarded(candidate)
            if isempty(candidate) || ~isstruct(candidate) || ~isfield(candidate,'tmpDir')
                return;
            end
            NMUIRecoveryTools.consumePendingThrough(candidate,'discard');
        end

        function candidate = latestCandidate(NM, root)
            candidate = struct([]);
            if nargin < 2 || isempty(root)
                error('NMUIRecoveryTools:missingRecoveryRoot', ...
                    'Recovery discovery requires the resolved NM2 session root.');
            end
            webRoot = fullfile(char(string(root)),'web');
            if exist(webRoot,'dir') ~= 7, return; end
            dirs = dir(fullfile(webRoot,'session_*'));
            currentContext = NMUIRecoveryTools.recoveryContext(NM);
            bestRevision = -Inf;
            for i = 1:numel(dirs)
                if ~dirs(i).isdir, continue; end
                tmpDir = fullfile(webRoot,dirs(i).name,'tmp');
                m = NMUIRecoveryTools.readManifest(tmpDir);
                if isempty(m) || ~strcmpi(NMUIRecoveryTools.fieldText(m,'lifecycleState'),'unfinished')
                    continue;
                end
                if ~isfield(m,'context') || ~NMUIRecoveryTools.contextCompatible(currentContext,m.context)
                    continue;
                end
                [draft,stamp,fileName,revision] = NMUIRecoveryTools.latestTopLevelDraft(tmpDir);
                if isempty(draft) || revision <= bestRevision, continue; end
                candidate = struct('tmpDir',tmpDir,'manifest',m,'draft',draft, ...
                    'draftFile',fileName,'draftRevision',revision,'stamp',stamp, ...
                    'root',char(string(root)));
                bestRevision = revision;
            end
        end

        function action = prompt(candidate)
            action = 'none';
            if isempty(candidate), return; end
            route = NMUIRecoveryTools.routeLabel(candidate);
            when = datestr(candidate.stamp,31);
            msg = sprintf(['An unfinished NM2 browser session was found.\n\n', ...
                'Last saved: %s\nLast page: %s\n\n', ...
                'Recovery restores the browser draft through the existing page persistence and MATLAB materialization paths.'], ...
                when, route);
            if usejava('desktop') && exist('questdlg','file') == 2
                choice = questdlg(msg,'NM2 unfinished session','Recover','Discard','Not now','Recover');
                if strcmp(choice,'Recover'), action='recover';
                elseif strcmp(choice,'Discard'), action='discard';
                else, action='later';
                end
                return;
            end
            fprintf('\n[nm] %s\n',msg);
            while ~any(strcmp(action,{'recover','discard','later'}))
                reply = lower(strtrim(input('Recover [R], discard [D], or not now [N]? ','s')));
                if any(strcmp(reply,{'r','recover'})), action='recover'; end
                if any(strcmp(reply,{'d','discard'})), action='discard'; end
                if any(strcmp(reply,{'n','no','later'})), action='later'; end
            end
        end

        function transferDrafts(candidate, newTmpDir)
            if isempty(candidate) || ~isstruct(candidate) || ~isfield(candidate,'tmpDir')
                error('NMUIRecoveryTools:invalidCandidate', ...
                    'Recovery candidate is missing its source session directory.');
            end
            src = char(string(candidate.tmpDir));
            NMUIRecoveryTools.quiesceSourceBridge(candidate);
            files = dir(fullfile(src,'ui_draft_*.json'));
            if isempty(files)
                error('NMUIRecoveryTools:noDrafts', ...
                    'The selected recovery session contains no UI draft files.');
            end
            for i = 1:numel(files)
                source = fullfile(src,files(i).name);
                target = fullfile(newTmpDir,files(i).name);
                [ok,msg] = copyfile(source,target,'f');
                if ~ok
                    error('NMUIRecoveryTools:draftCopyFailed', ...
                        'Could not copy recovery draft %s: %s',files(i).name,msg);
                end
            end
            % Recovery is a terminal decision for the selected checkpoint and
            % older compatible pending checkpoints. The fresh session now owns
            % the copied draft set; no recovery chain is maintained.
            NMUIRecoveryTools.consumePendingThrough(candidate,'recover');
        end

        function page = recoveryPage(candidate)
            page = '';
            if isempty(candidate) || ~isstruct(candidate) || ~isfield(candidate,'draft'), return; end
            path = NMUIRecoveryTools.draftRoutePath(candidate.draft);
            [~,name,ext] = fileparts(lower(path));
            switch [name ext]
                case 'nm_train_template_menu.html', page='template';
                case 'nm_dataio_overview.html', page='dataio';
                case 'nm_analysis_manager.html', page='analysis_manager';
                case 'nm_preprocess_runner.html', page='preprocess_runner';
                case 'nm_ml_train_runner.html', page='ml_train_runner';
                case 'nm_vis_runner.html', page='vis_runner';
                case 'nm_mli_runner.html', page='mli_runner';
                case 'nm_model_export_runner.html', page='model_export_runner';
                case 'nm_oocv_runner.html', page='oocv_runner';
                case 'nm_results_viewer_alpha.html', page='results_viewer_alpha';
                case 'nm_workbench.html', page='workbench';
            end
        end

        function module = recoveryModule(candidate)
            module = '';
            if isempty(candidate) || ~isstruct(candidate) || ~isfield(candidate,'draft'), return; end
            d = candidate.draft;
            if isstruct(d) && isfield(d,'module') && ~isempty(d.module)
                module = char(string(d.module));
            elseif isstruct(d) && isfield(d,'route') && isstruct(d.route) && ...
                    isfield(d.route,'module') && ~isempty(d.route.module)
                module = char(string(d.route.module));
            end
        end

        function m = readManifest(tmpDir)
            m = [];
            fp = fullfile(char(string(tmpDir)),'recovery_manifest.json');
            if exist(fp,'file') ~= 2, return; end
            raw = NMConfigTools.charifyStrings(NMConfigTools.decodeJson(fileread(fp)));
            if ~isstruct(raw) || ~isscalar(raw)
                error('NMUIRecoveryTools:invalidManifest', ...
                    'Recovery manifest is not one JSON object: %s',fp);
            end
            m = raw;
        end

        function writeManifest(tmpDir,m)
            fp = fullfile(char(string(tmpDir)),'recovery_manifest.json');
            NMUIRecoveryTools.atomicJson(fp,m);
        end
    end

    methods (Static, Access = private)
        function consumePendingThrough(candidate, resolution)
            root = char(string(candidate.root));
            webRoot = fullfile(root,'web');
            if exist(webRoot,'dir') ~= 7, return; end
            selectedContext = candidate.manifest.context;
            selectedRevision = double(candidate.draftRevision);
            dirs = dir(fullfile(webRoot,'session_*'));
            for i = 1:numel(dirs)
                if ~dirs(i).isdir, continue; end
                tmpDir = fullfile(webRoot,dirs(i).name,'tmp');
                m = NMUIRecoveryTools.readManifest(tmpDir);
                if isempty(m) || ~strcmpi(NMUIRecoveryTools.fieldText(m,'lifecycleState'),'unfinished')
                    continue;
                end
                if ~isfield(m,'context') || ~NMUIRecoveryTools.contextCompatible(selectedContext,m.context)
                    continue;
                end
                [draft,~,~,revision] = NMUIRecoveryTools.latestTopLevelDraft(tmpDir);
                if isempty(draft) || revision > selectedRevision, continue; end
                if strcmp(resolution,'recover') && strcmp(char(java.io.File(tmpDir).getCanonicalPath()), ...
                        char(java.io.File(candidate.tmpDir).getCanonicalPath()))
                    m.lifecycleState = 'reconciled';
                    m.cleanupReason = 'recovered-into-new-session';
                    m.reconciledAt = datestr(now,31);
                else
                    m.lifecycleState = 'discarded';
                    if strcmp(resolution,'recover')
                        m.cleanupReason = 'older-pending-resolved-by-recovery';
                    else
                        m.cleanupReason = 'user-discarded-recovery';
                    end
                end
                m.updatedAt = datestr(now,31);
                NMUIRecoveryTools.writeManifest(tmpDir,m);
                NMUIRecoveryTools.deleteDrafts(tmpDir);
            end
        end

        function [draft,stamp,fileName,revision] = latestTopLevelDraft(tmpDir)
            draft = [];
            stamp = -Inf;
            fileName = '';
            revision = -Inf;
            files = dir(fullfile(char(string(tmpDir)),'ui_draft_*.json'));
            if isempty(files), return; end
            for i = 1:numel(files)
                f = files(i);
                fp = fullfile(f.folder,f.name);
                raw = NMConfigTools.charifyStrings(NMConfigTools.decodeJson(fileread(fp)));
                if ~isstruct(raw) || ~isscalar(raw), continue; end
                if isfield(raw,'embedded') && logical(raw.embedded), continue; end
                if isempty(NMUIRecoveryTools.draftRoutePath(raw)), continue; end
                if ~isfield(raw,'draftRevision') || ~isnumeric(raw.draftRevision) || ...
                        ~isscalar(raw.draftRevision) || ~isfinite(double(raw.draftRevision)) || ...
                        double(raw.draftRevision) <= 0
                    error('NMUIRecoveryTools:invalidDraftRevision', ...
                        'Recovery draft is missing a valid monotonic draftRevision: %s',fp);
                end
                currentRevision = double(raw.draftRevision);
                if currentRevision <= revision, continue; end
                draft = raw;
                stamp = f.datenum;
                fileName = f.name;
                revision = currentRevision;
            end
        end

        function path = draftRoutePath(draft)
            path = '';
            if ~isstruct(draft) || ~isfield(draft,'route') || ~isstruct(draft.route), return; end
            if isfield(draft.route,'path') && ~isempty(draft.route.path)
                path = char(string(draft.route.path));
            end
        end

        function tf = contextCompatible(a,b)
            tf = false;
            if ~isstruct(a) || ~isstruct(b), return; end
            ak = NMUIRecoveryTools.fieldText(a,'kind');
            bk = NMUIRecoveryTools.fieldText(b,'kind');
            af = NMUIRecoveryTools.fieldText(a,'fingerprint');
            bf = NMUIRecoveryTools.fieldText(b,'fingerprint');
            tf = ~isempty(ak) && strcmp(ak,bk) && ~isempty(af) && strcmp(af,bf);
        end

        function tf = ownerIsOrphan(m,currentIdent,currentSession)
            tf = false;
            pid = NaN;
            if isfield(m,'matlabPid') && isnumeric(m.matlabPid) && isscalar(m.matlabPid)
                pid = double(m.matlabPid);
            end
            if ~isfinite(pid) || pid <= 0, return; end
            ownerSession = NMUIRecoveryTools.fieldText(m,'matlabSessionId');
            if round(pid) == round(currentIdent.pid)
                tf = isempty(ownerSession) || ~strcmp(ownerSession,currentSession);
                return;
            end
            tf = ~NMUIRecoveryTools.processAlive(pid);
        end

        function tf = processAlive(pid)
            tf = false;
            if ~isfinite(pid) || pid <= 0, return; end
            if isunix
                [status,~] = system(sprintf('kill -0 %d >/dev/null 2>&1',round(pid)));
                tf = status == 0;
            elseif ispc
                [status,out] = system(sprintf('tasklist /FI "PID eq %d" /NH',round(pid)));
                tf = status == 0 && contains(out,num2str(round(pid)));
            end
        end

        function label = routeLabel(candidate)
            label = 'unknown page';
            if isempty(candidate) || ~isstruct(candidate) || ~isfield(candidate,'draft'), return; end
            d = candidate.draft;
            path = NMUIRecoveryTools.draftRoutePath(d);
            module = NMUIRecoveryTools.recoveryModule(candidate);
            if ~isempty(path), label = path; end
            if ~isempty(module), label = sprintf('%s [%s]',label,module); end
            if isfield(d,'view') && isstruct(d.view)
                nested = '';
                if isfield(d.view,'activeEditor') && ~isempty(d.view.activeEditor)
                    nested = char(string(d.view.activeEditor));
                elseif isfield(d.view,'activeTab') && ~isempty(d.view.activeTab) && ...
                        ~strcmp(char(string(d.view.activeTab)),'overview')
                    nested = char(string(d.view.activeTab));
                end
                if ~isempty(nested), label = sprintf('%s -> %s',label,nested); end
            end
        end

        function quiesceSourceBridge(candidate)
            if ~isfield(candidate,'manifest') || ~isstruct(candidate.manifest), return; end
            m = candidate.manifest;
            runId = NMUIRecoveryTools.fieldText(m,'runId');
            if isempty(runId), return; end
            bridgeWasAlive = NMUIRecoveryTools.bridgeResponds(m);
            payload = struct('ok',false,'killed',true,'severity','info', ...
                'message','NM2 is reclaiming an unfinished browser session for explicit recovery.', ...
                'reason','recovery-reclaim','unfinished',true, ...
                'time',datestr(now,31),'runId',runId);
            NMUIBridgeTools.writeKillFlag(char(string(candidate.tmpDir)),payload);
            if ~bridgeWasAlive, return; end
            deadline = tic;
            while toc(deadline) < 4.0
                pause(0.1);
                if ~NMUIRecoveryTools.bridgeResponds(m), return; end
            end
            error('NMUIRecoveryTools:sourceBridgeStillActive', ...
                'The unfinished NM2 bridge did not stop before recovery. Recovery was not applied.');
        end

        function tf = bridgeResponds(m)
            tf = false;
            runId = NMUIRecoveryTools.fieldText(m,'runId');
            port = NaN;
            if isfield(m,'port') && isnumeric(m.port) && isscalar(m.port), port = double(m.port); end
            if isempty(runId) || ~isfinite(port) || port < 1 || port > 65535, return; end
            url = sprintf('http://127.0.0.1:%d/api/diag?runid=%s', ...
                round(port),NMUIBridgeTools.urlEncode(runId));
            opts = weboptions('Timeout',0.35,'ContentType','json');
            try
                out = webread(url,opts);
                tf = isstruct(out) && isfield(out,'runid') && strcmp(char(string(out.runid)),runId);
            catch
                tf = false;
            end
        end

        function deleteDrafts(tmpDir)
            files = dir(fullfile(char(string(tmpDir)),'ui_draft_*.json'));
            for i = 1:numel(files)
                delete(fullfile(files(i).folder,files(i).name));
            end
        end

        function atomicJson(fp,obj)
            txt = jsonencode(obj);
            tmp = [fp '.tmp_' strrep(char(java.util.UUID.randomUUID()),'-','')];
            fid = fopen(tmp,'w');
            if fid < 0
                error('NMUIRecoveryTools:writeFailed', ...
                    'Could not open recovery metadata for writing: %s',tmp);
            end
            try
                fwrite(fid,txt,'char');
                fclose(fid);
            catch ME
                fclose(fid);
                if exist(tmp,'file') == 2, delete(tmp); end
                rethrow(ME);
            end
            [ok,msg] = movefile(tmp,fp,'f');
            if ~ok
                if exist(tmp,'file') == 2, delete(tmp); end
                error('NMUIRecoveryTools:replaceFailed', ...
                    'Could not atomically replace recovery metadata %s: %s',fp,msg);
            end
        end

        function s = scalarText(x)
            s = '';
            if ischar(x) || (isstring(x) && isscalar(x))
                s = strtrim(char(string(x)));
            elseif (isnumeric(x) || islogical(x)) && isscalar(x) && isfinite(double(x))
                s = sprintf('%.17g',double(x));
            end
        end

        function n = modalityCount(NM)
            n = 0;
            if ~isstruct(NM) || ~isfield(NM,'Y') || isempty(NM.Y), return; end
            if iscell(NM.Y), n = numel(NM.Y); else, n = 1; end
        end

        function sizes = modalitySizes(NM)
            sizes = {};
            if ~isstruct(NM) || ~isfield(NM,'Y') || isempty(NM.Y), return; end
            y = NM.Y; if ~iscell(y), y = {y}; end
            sizes = cell(1,numel(y));
            for i = 1:numel(y), sizes{i} = size(y{i}); end
        end

        function s = fieldSize(NM,field)
            s = [];
            if isstruct(NM) && isfield(NM,field) && ~isempty(NM.(field)), s = size(NM.(field)); end
        end

        function n = analysisCount(NM)
            n = 0;
            if ~isstruct(NM) || ~isfield(NM,'analysis') || isempty(NM.analysis), return; end
            n = numel(NM.analysis);
        end

        function out = sha256(txt)
            md = java.security.MessageDigest.getInstance('SHA-256');
            md.update(uint8(unicode2native(char(txt),'UTF-8')));
            bytes = typecast(md.digest(),'uint8');
            out = lower(reshape(dec2hex(bytes,2).',1,[]));
        end

        function s = fieldText(x,field)
            s = '';
            if isstruct(x) && isfield(x,field) && ~isempty(x.(field)), s = char(string(x.(field))); end
        end
    end
end

classdef NMUIStateTools
% NMUIStateTools
% -------------------------------------------------------------------------
% Session-wide persisted browser/UI state for NM2.
%
% One nm2_state.json file exists per isolated browser session directory.
% The file is authoritative only for user-entered/uncommitted UI state and
% navigation. Scientific/runtime state remains authoritative in MATLAB/NM.
% -------------------------------------------------------------------------

    methods (Static)
        function fp = statePath(tmpDir)
            fp = fullfile(char(string(tmpDir)), 'nm2_state.json');
        end

        function state = initialize(tmpDir, NM, initialPage)
            if nargin < 3 || isempty(initialPage), initialPage = 'landing'; end
            if nargin < 1 || isempty(tmpDir) || exist(tmpDir,'dir') ~= 7
                error('NMUIStateTools:missingSessionDir','NM2 UI state requires an existing session tmp directory.');
            end
            fp = NMUIStateTools.statePath(tmpDir);
            if exist(fp,'file') == 2
                % An active session keeps one stable UI-state identity while its
                % MATLAB NM may legitimately evolve through commits. Compatibility
                % is checked when an abandoned session is discovered for recovery,
                % not every time a child page re-enters the shared session.
                state = NMUIStateTools.read(tmpDir);
                return;
            end
            ident = NMUISessionTools.userIdentity();
            [webDir, sessionId] = fileparts(fileparts(char(string(tmpDir)))); %#ok<ASGLU>
            state = struct();
            state.schemaVersion = 1;
            state.sessionId = sessionId;
            state.createdAt = datestr(now,31);
            state.updatedAt = state.createdAt;
            state.owner = struct('user',char(string(ident.user)), 'uid',char(string(ident.uid)), ...
                'matlabPid',double(ident.pid));
            state.context = NMUIStateTools.recoveryContext(NM);
            state.navigation = struct('revision',0,'state',struct('page',char(string(initialPage)), ...
                'path','','pageTarget','','moduleKey','','subview',''));
            state.sections = struct( ...
                'dataIO',struct('revision',0,'state',struct()), ...
                'configurator',struct('revision',0,'slotRevisions',struct(), ...
                    'state',struct('menu',struct(),'children',struct())), ...
                'runners',struct('revision',0,'slotRevisions',struct(),'state',struct()));
            state.transport = struct('runId','','port',NaN,'pid',0);
            NMUIStateTools.write(tmpDir,state);
        end

        function state = read(tmpDir)
            state = struct();
            fp = NMUIStateTools.statePath(tmpDir);
            if exist(fp,'file') ~= 2, return; end
            raw = NMConfigTools.decodeJson(fileread(fp));
            state = NMConfigTools.charifyStrings(raw);
            if ~isstruct(state) || ~isscalar(state)
                error('NMUIStateTools:invalidState','NM2 UI state is not one JSON object: %s',fp);
            end
        end

        function write(tmpDir,state)
            if nargin < 2 || ~isstruct(state) || ~isscalar(state)
                error('NMUIStateTools:invalidWrite','NM2 UI state write requires one scalar struct.');
            end
            state.updatedAt = datestr(now,31);
            fp = NMUIStateTools.statePath(tmpDir);
            NMUIStateTools.atomicJson(fp,state);
        end

        function dataState = readDataIO(tmpDir)
            dataState = struct();
            state = NMUIStateTools.read(tmpDir);
            if isempty(fieldnames(state)) || ~isfield(state,'sections') || ~isstruct(state.sections) || ...
                    ~isfield(state.sections,'dataIO') || ~isstruct(state.sections.dataIO)
                return;
            end
            sec = state.sections.dataIO;
            if isfield(sec,'state') && isstruct(sec.state), dataState = sec.state; end
        end

        function cfg = readConfigurator(tmpDir)
            cfg = struct('menu',struct(),'children',struct());
            state = NMUIStateTools.read(tmpDir);
            if isempty(fieldnames(state)) || ~isfield(state,'sections') || ~isstruct(state.sections) || ...
                    ~isfield(state.sections,'configurator') || ~isstruct(state.sections.configurator)
                return;
            end
            sec = state.sections.configurator;
            if isfield(sec,'state') && isstruct(sec.state)
                if isfield(sec.state,'menu') && isstruct(sec.state.menu), cfg.menu = sec.state.menu; end
                if isfield(sec.state,'children') && isstruct(sec.state.children), cfg.children = sec.state.children; end
            end
        end

        function menu = readConfiguratorMenu(tmpDir)
            cfg = NMUIStateTools.readConfigurator(tmpDir);
            menu = cfg.menu;
        end

        function child = readConfiguratorChild(tmpDir, module)
            child = NMUIStateTools.configuratorChild(NMUIStateTools.readConfigurator(tmpDir), module);
        end

        function child = configuratorChild(cfg, module)
            % configuratorChild  Resolve one child slot from an already read configurator section.
            % Lets callers that need several slots read nm2_state.json once.
            child = struct();
            module = NMUIStateTools.configuratorModule(module, false);
            if isfield(cfg.children,module) && isstruct(cfg.children.(module))
                child = cfg.children.(module);
            end
        end

        function writeConfiguratorMenu(tmpDir, menu)
            if ~isstruct(menu) || ~isscalar(menu)
                error('NMUIStateTools:invalidConfiguratorMenu','Configurator menu STATE requires one scalar struct.');
            end
            state = NMUIStateTools.ensureConfiguratorSection(tmpDir);
            state.sections.configurator.state.menu = menu;
            state = NMUIStateTools.bumpConfiguratorRevision(state,'menu');
            NMUIStateTools.write(tmpDir,state);
        end

        function writeConfiguratorChild(tmpDir, module, child)
            module = NMUIStateTools.configuratorModule(module, false);
            if ~isstruct(child) || ~isscalar(child)
                error('NMUIStateTools:invalidConfiguratorChild','Configurator child STATE requires one scalar struct.');
            end
            state = NMUIStateTools.ensureConfiguratorSection(tmpDir);
            state.sections.configurator.state.children.(module) = child;
            state = NMUIStateTools.bumpConfiguratorRevision(state,module);
            NMUIStateTools.write(tmpDir,state);
        end

        function clearConfiguratorChildren(tmpDir)
            state = NMUIStateTools.ensureConfiguratorSection(tmpDir);
            state.sections.configurator.state.children = struct();
            state.sections.configurator.slotRevisions = rmfieldSafe(state.sections.configurator.slotRevisions, ...
                setdiff(fieldnames(state.sections.configurator.slotRevisions),{'menu'}));
            state.sections.configurator.revision = double(state.sections.configurator.revision) + 1;
            NMUIStateTools.write(tmpDir,state);

            function s = rmfieldSafe(s,names)
                if isempty(names), return; end
                s = rmfield(s,names);
            end
        end

        function refreshContext(tmpDir, NM)
            % refreshContext  Align retained UI-state compatibility metadata with the NM returned on an intentional unfinished quit.
            state = NMUIStateTools.read(tmpDir);
            if isempty(fieldnames(state)), return; end
            state.context = NMUIStateTools.recoveryContext(NM);
            ident = NMUISessionTools.userIdentity();
            if ~isfield(state,'owner') || ~isstruct(state.owner), state.owner = struct(); end
            state.owner.user = char(string(ident.user));
            state.owner.uid = char(string(ident.uid));
            state.owner.matlabPid = double(ident.pid);
            NMUIStateTools.write(tmpDir,state);
        end

        function remove(tmpDir)
            fp = NMUIStateTools.statePath(tmpDir);
            if exist(fp,'file') == 2, delete(fp); end
        end

        function candidates = findRecoverable(NM, rootDir)
            candidates = struct('sessionId',{},'webDir',{},'tmpDir',{},'state',{},'savedAt',{});
            if nargin < 2 || isempty(rootDir), return; end
            webRoot = fullfile(char(string(rootDir)),'web');
            if exist(webRoot,'dir') ~= 7, return; end
            expected = NMUIStateTools.recoveryContext(NM);
            dirs = dir(fullfile(webRoot,'session_*'));
            for i = 1:numel(dirs)
                if ~dirs(i).isdir, continue; end
                webDir = fullfile(webRoot,dirs(i).name);
                tmpDir = fullfile(webDir,'tmp');
                fp = NMUIStateTools.statePath(tmpDir);
                if exist(fp,'file') ~= 2, continue; end
                try
                    state = NMUIStateTools.read(tmpDir);
                    active = NMUIStateTools.sessionIsActive(state);
                catch ME
                    warning('NMUIStateTools:invalidCandidate','Ignoring invalid NM2 UI state %s: %s (%s)',fp,ME.message,ME.identifier);
                    continue;
                end
                if ~isfield(state,'context') || ~NMUIStateTools.contextCompatible(expected,state.context), continue; end
                if active, continue; end
                savedAt = NMUIStateTools.fileStamp(fp);
                candidates(end+1) = struct('sessionId',dirs(i).name,'webDir',webDir,'tmpDir',tmpDir, ... %#ok<AGROW>
                    'state',state,'savedAt',savedAt);
            end
            if numel(candidates) > 1
                [~,order] = sort([candidates.savedAt],'descend');
                candidates = candidates(order);
            end
        end

        function [action, candidate] = prompt(candidates)
            action = 'none'; candidate = struct([]);
            if isempty(candidates), return; end
            idx = 1;
            if numel(candidates) > 1
                labels = cell(1,numel(candidates));
                for i = 1:numel(candidates)
                    labels{i} = NMUIStateTools.candidateLabel(candidates(i));
                end
                if usejava('desktop')
                    dlg = dialog('Name','NM2 session recovery', 'WindowStyle','modal', ...
                        'Position',[100 100 740 330], 'Resize','off');
                    dlg.CloseRequestFcn = @(~,~)uiresume(dlg);
                    movegui(dlg,'center');
                    uicontrol(dlg,'Style','text','Position',[20 270 700 48], ...
                        'String',{'Select an unfinished NM2 session:', ...
                        'Restore reopens its saved UI state; Dismiss deletes its recovery state.'}, ...
                        'HorizontalAlignment','left','FontSize',10);
                    sessionList = uicontrol(dlg,'Style','listbox', ...
                        'Position',[20 72 700 194], 'String',labels,'Value',1, ...
                        'Tag','NM2RecoverySessionList','FontSize',10);
                    uicontrol(dlg,'Style','pushbutton', 'String','Restore selected', ...
                        'Position',[335 20 125 34], 'Callback',@(~,~)decide('recover'));
                    uicontrol(dlg,'Style','pushbutton', 'String','Dismiss selected', ...
                        'Position',[470 20 125 34], 'Callback',@(~,~)decide('dismiss'));
                    uicontrol(dlg,'Style','pushbutton', 'String','Cancel', ...
                        'Position',[605 20 115 34], 'Callback',@(~,~)uiresume(dlg));
                    uiwait(dlg);
                    delete(dlg);
                    return;
                end
                fprintf('\n[nm] Compatible unfinished NM2 sessions:\n');
                for i = 1:numel(labels), fprintf('  %d) %s\n',i,labels{i}); end
                while true
                    reply = strtrim(input(sprintf('Select session [1-%d], or Enter to cancel: ',numel(labels)),'s'));
                    if isempty(reply), return; end
                    n = str2double(reply);
                    if ismember(n,1:numel(labels)), idx = n; break; end
                end
            end
            candidate = candidates(idx);
            message = sprintf(['An unfinished NM2 UI session is available.\n\n%s\n\n', ...
                'Restore reopens the recorded UI using its persisted user-entered state. ', ...
                'Dismiss deletes this recovery state.'], NMUIStateTools.candidateLabel(candidate));
            if usejava('desktop')
                choice = questdlg(message,'NM2 session recovery','Restore','Dismiss','Restore');
                if strcmp(choice,'Restore'), action='recover'; elseif strcmp(choice,'Dismiss'), action='dismiss'; end
                return;
            end
            fprintf('\n[nm] %s\n',message);
            while isempty(action) || strcmp(action,'none')
                reply = lower(strtrim(input('Restore [R] or dismiss [D]? ','s')));
                if any(strcmp(reply,{'r','restore','recover'})), action='recover'; end
                if any(strcmp(reply,{'d','dismiss','discard'})), action='dismiss'; end
            end

            function decide(choice)
                action = choice;
                candidate = candidates(sessionList.Value);
                uiresume(dlg);
            end
        end

        function quiesce(candidate, requireExit)
            % quiesce  Stop the bridge recorded for one session directory.
            %
            % requireExit=true (Restore, launcher exit): the directory will be reused or released, so
            % return only when the published bridge process no longer exists; otherwise raise an error.
            % requireExit=false (Dismiss): the directory is never reused, so request the stop and return.
            % A state with an empty transport.runId never had a bridge: Python publishes run id and
            % process id in one write.
            state = NMUIStateTools.read(candidate.tmpDir);
            runId = NMUIStateTools.transportRunId(state);
            if ~strcmp(runId, NMUIStateTools.transportRunId(candidate.state))
                error('NMUIStateTools:sessionChanged', 'The recovery session changed ownership during selection.');
            end
            if isempty(runId), return; end
            % The stop request goes out before any liveness query, so it is sent on every path.
            NMUIBridgeTools.writeKillFlag(candidate.tmpDir, struct('ok',false,'killed',true, ...
                'severity','info','reason','state-recovery-reclaim','runId',runId));
            if ~requireExit, return; end
            pid = state.transport.pid;
            deadline = tic;
            while NMUIStateTools.processAlive(pid)
                if toc(deadline) >= 6.0
                    error('NMUIStateTools:bridgeStillActive', ...
                        ['Process %d recorded for this NM2 session is still running, so its directory cannot be reused. ', ...
                         'Retry, or choose Dismiss to discard the unfinished session.'], pid);
                end
                pause(0.1);
            end
        end

        function page = recoveryPage(state, fallback)
            if nargin < 2 || isempty(fallback), fallback = 'landing'; end
            page = char(string(fallback));
            if ~isstruct(state) || ~isfield(state,'navigation') || ~isstruct(state.navigation) || ...
                    ~isfield(state.navigation,'state') || ~isstruct(state.navigation.state)
                return;
            end
            nav = state.navigation.state;
            path = '';
            if isfield(nav,'path') && ~isempty(nav.path), path = lower(char(string(nav.path))); end
            if isempty(path) && isfield(nav,'page') && ~isempty(nav.page), path = lower(char(string(nav.page))); end
            if contains(path,'dataio'), page='dataio';
            elseif contains(path,'train_template') || contains(path,'template'), page='template';
            elseif contains(path,'analysis_manager'), page='analysis_manager';
            elseif contains(path,'preprocess_runner'), page='preprocess';
            elseif contains(path,'ml_train_runner'), page='mltrain';
            elseif contains(path,'vis_runner'), page='visualization';
            elseif contains(path,'mli_runner'), page='mli';
            elseif contains(path,'model_export_runner'), page='model_export';
            elseif contains(path,'oocv_runner'), page='oocv';
            elseif contains(path,'workbench'), page='landing';
            end
        end

        function moduleKey = recoveryModuleKey(state)
            moduleKey = '';
            if ~isstruct(state), return; end
            if isfield(state,'navigation') && isstruct(state.navigation) && ...
                    isfield(state.navigation,'state') && isstruct(state.navigation.state)
                nav = state.navigation.state;
                if isfield(nav,'moduleKey') && ~isempty(nav.moduleKey)
                    moduleKey = char(string(nav.moduleKey));
                end
            end
            if ~isempty(moduleKey), return; end
            if isfield(state,'sections') && isstruct(state.sections) && ...
                    isfield(state.sections,'dataIO') && isstruct(state.sections.dataIO) && ...
                    isfield(state.sections.dataIO,'state') && isstruct(state.sections.dataIO.state) && ...
                    isfield(state.sections.dataIO.state,'scope') && ~isempty(state.sections.dataIO.state.scope)
                scope = lower(char(string(state.sections.dataIO.state.scope)));
                if strcmp(scope,'oocv'), moduleKey = 'oocv_dataio';
                elseif strcmp(scope,'training'), moduleKey = 'dataio'; end
            end
        end

        function tf = recoveryReturnToWorkbench(state)
            tf = false;
            if ~isstruct(state) || ~isfield(state,'navigation') || ~isstruct(state.navigation) || ...
                    ~isfield(state.navigation,'state') || ~isstruct(state.navigation.state), return; end
            nav = state.navigation.state;
            if isfield(nav,'returnToWorkbench') && ~isempty(nav.returnToWorkbench)
                tf = logical(nav.returnToWorkbench);
            end
        end

        function page = recoveryReturnPage(state)
            page = 'nm_workbench.html';
            if ~isstruct(state) || ~isfield(state,'navigation') || ~isstruct(state.navigation) || ...
                    ~isfield(state.navigation,'state') || ~isstruct(state.navigation.state), return; end
            nav = state.navigation.state;
            if isfield(nav,'returnPage') && ~isempty(nav.returnPage)
                page = char(string(nav.returnPage));
            end
        end
    end

    methods (Static, Access = private)
        function state = ensureConfiguratorSection(tmpDir)
            state = NMUIStateTools.read(tmpDir);
            if isempty(fieldnames(state))
                error('NMUIStateTools:missingState','NM2 UI STATE does not exist in %s.',tmpDir);
            end
            if ~isfield(state,'sections') || ~isstruct(state.sections), state.sections = struct(); end
            if ~isfield(state.sections,'configurator') || ~isstruct(state.sections.configurator)
                state.sections.configurator = struct('revision',0,'slotRevisions',struct(), ...
                    'state',struct('menu',struct(),'children',struct()));
            end
            sec = state.sections.configurator;
            if ~isfield(sec,'revision') || isempty(sec.revision), sec.revision = 0; end
            if ~isfield(sec,'slotRevisions') || ~isstruct(sec.slotRevisions), sec.slotRevisions = struct(); end
            if ~isfield(sec,'state') || ~isstruct(sec.state), sec.state = struct(); end
            if ~isfield(sec.state,'menu') || ~isstruct(sec.state.menu), sec.state.menu = struct(); end
            if ~isfield(sec.state,'children') || ~isstruct(sec.state.children), sec.state.children = struct(); end
            state.sections.configurator = sec;
        end

        function state = bumpConfiguratorRevision(state,module)
            module = NMUIStateTools.configuratorModule(module, true);
            sec = state.sections.configurator;
            rev = double(sec.revision) + 1;
            sec.revision = rev;
            sec.slotRevisions.(module) = rev;
            state.sections.configurator = sec;
        end

        function module = configuratorModule(module, allowMenu)
            module = char(string(module));
            if nargin < 2, allowMenu = true; end
            ok = (~isempty(allowMenu) && allowMenu && strcmp(module,'menu')) || ...
                strcmp(module,'preproc_stacking') || strcmp(module,'ml_global') || ...
                ~isempty(regexp(module,'^preproc_var[1-9][0-9]*$','once')) || ...
                ~isempty(regexp(module,'^ml_var[1-9][0-9]*$','once'));
            if ~ok
                error('NMUIStateTools:invalidConfiguratorModule','Invalid configurator STATE module: %s',module);
            end
        end

        function label = candidateLabel(candidate)
            route = 'unknown page';
            if isfield(candidate,'state') && isstruct(candidate.state) && isfield(candidate.state,'navigation') && ...
                    isstruct(candidate.state.navigation) && isfield(candidate.state.navigation,'state') && isstruct(candidate.state.navigation.state)
                nav = candidate.state.navigation.state;
                if isfield(nav,'pageTarget') && ~isempty(nav.pageTarget), route = char(string(nav.pageTarget));
                elseif isfield(nav,'path') && ~isempty(nav.path), route = char(string(nav.path)); end
                if isfield(nav,'subview') && ~isempty(nav.subview), route = sprintf('%s -> %s',route,char(string(nav.subview))); end
            end
            stamp = datestr(candidate.savedAt,31);
            label = sprintf('%s | %s | %s',candidate.sessionId,stamp,route);
        end

        function tf = sessionIsActive(state)
            ident = NMUISessionTools.userIdentity();
            pid = double(state.owner.matlabPid);
            tf = pid ~= ident.pid && NMUIStateTools.processAlive(pid);
        end
    end

    methods (Static)

        function runId = transportRunId(state)
            runId = '';
            if isstruct(state) && isfield(state,'transport') && isstruct(state.transport) && ...
                    isfield(state.transport,'runId') && ~isempty(state.transport.runId)
                runId = char(string(state.transport.runId));
            end
        end

        function tf = processAlive(pid)
            % True while an operating-system process with this PID exists. Windows is queried in-process:
            % a child command such as tasklist returned status -1 inside the exit handler after Ctrl+C.
            tf = false;
            if ~isfinite(pid) || pid <= 0, return; end
            if isunix
                [status,out] = system(sprintf('ps -p %d',round(pid)));
                if status > 1
                    error('NMUIStateTools:processQueryFailed','Could not query process %d (status %d): %s',round(pid),status,strtrim(out));
                end
                tf = status == 0;
                return;
            end
            processes = System.Diagnostics.Process.GetProcesses();
            for i = 1:processes.Length
                tf = tf || double(processes(i).Id) == round(pid);
            end
        end
    end

    methods (Static, Access = private)

        function t = fileStamp(fp)
            d = dir(fp);
            if isempty(d), t = now; else, t = d.datenum; end
        end

        function ctx = recoveryContext(NM)
            ctx = struct('schemaVersion',1,'kind','structural','nmId','','fingerprint','');
            if isstruct(NM) && isfield(NM,'id') && ~isempty(NM.id)
                idText = NMUIStateTools.scalarText(NM.id);
                if ~isempty(idText)
                    ctx.kind = 'nm-id'; ctx.nmId = idText;
                    ctx.fingerprint = NMUIStateTools.sha256(['nm-id:' idText]);
                    return;
                end
            end
            projection = struct();
            projection.nModalities = NMUIStateTools.modalityCount(NM);
            projection.modalitySizes = NMUIStateTools.modalitySizes(NM);
            projection.labelSize = NMUIStateTools.fieldSize(NM,'label');
            projection.covarSize = NMUIStateTools.fieldSize(NM,'covars');
            projection.nAnalyses = NMUIStateTools.analysisCount(NM);
            projection.hasDefs = isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs);
            ctx.fingerprint = NMUIStateTools.sha256(jsonencode(projection));
        end

        function tf = contextCompatible(a,b)
            tf = false;
            if ~isstruct(a) || ~isstruct(b), return; end
            ak = NMUIStateTools.fieldText(a,'kind'); bk = NMUIStateTools.fieldText(b,'kind');
            af = NMUIStateTools.fieldText(a,'fingerprint'); bf = NMUIStateTools.fieldText(b,'fingerprint');
            tf = ~isempty(ak) && strcmp(ak,bk) && ~isempty(af) && strcmp(af,bf);
        end

        function s = scalarText(x)
            s = '';
            if ischar(x) || (isstring(x) && isscalar(x)), s = strtrim(char(string(x)));
            elseif (isnumeric(x) || islogical(x)) && isscalar(x) && isfinite(double(x)), s = sprintf('%.17g',double(x)); end
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
            if isstruct(NM) && isfield(NM,'analysis') && ~isempty(NM.analysis), n = numel(NM.analysis); end
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

        function atomicJson(fp,obj)
            txt = jsonencode(obj);
            tmp = [fp '.tmp_' strrep(char(java.util.UUID.randomUUID()),'-','')];
            fid = fopen(tmp,'w');
            if fid < 0, error('NMUIStateTools:writeFailed','Could not write NM2 UI state temporary file: %s',tmp); end
            try
                fwrite(fid,txt,'char'); fclose(fid);
            catch ME
                fclose(fid); if exist(tmp,'file') == 2, delete(tmp); end; rethrow(ME);
            end
            [ok,msg] = movefile(tmp,fp,'f');
            if ~ok
                if exist(tmp,'file') == 2, delete(tmp); end
                error('NMUIStateTools:replaceFailed','Could not atomically replace NM2 UI state %s: %s',fp,msg);
            end
        end
    end
end

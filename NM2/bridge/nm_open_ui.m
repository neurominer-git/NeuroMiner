function [state, sessionResult] = nm_open_ui(webDir, port, htmlEntry, matlabServiceHandler, uiTarget, sessionOptions)
% nm_open_ui  Launch one NM2 UI transport over the shared local bridge.
%
% This is the single transport-routing authority. Browser HTTP and embedded
% uihtml relay sessions share the same Python bridge, MATLAB service dispatcher,
% session state and application pages. Code downstream from this boundary must
% not branch on the selected rendering transport.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 1 || isempty(webDir), webDir = pwd; end
automaticPort = nargin < 2 || isempty(port);
if automaticPort, port = NaN; end
if nargin < 3 || isempty(htmlEntry), htmlEntry = 'nm_preproc_pipeline_ui.html'; end
if nargin < 4, matlabServiceHandler = []; end
if nargin < 5 || isempty(uiTarget), uiTarget = 'browser-default'; end
if nargin < 6 || isempty(sessionOptions), sessionOptions = struct(); end
if ~isstruct(sessionOptions) || ~isscalar(sessionOptions)
    error('nm_open_ui:invalidSessionOptions','UI bridge session options must be one scalar struct.');
end
headless = local_option_logical(sessionOptions, 'Headless', false);
uiTarget = local_normalize_ui_target(uiTarget);
htmlRelay = strcmp(uiTarget, 'html-relay');
if headless && htmlRelay
    error('nm_open_ui:headlessHtmlRelayUnsupported', ...
        'Headless UI execution cannot use html-relay. Select browser-edge, browser-chrome or browser-firefox.');
end
browserTarget = uiTarget;
browserExecutable = '';
if ~htmlRelay
    if headless && strcmp(browserTarget, 'browser-default')
        error('nm_open_ui:headlessBrowserTargetRequired', ...
            'Headless UI execution requires an explicit browser target: browser-edge, browser-chrome or browser-firefox.');
    end
    try
        browserExecutable = local_resolve_browser_executable(browserTarget);
    catch ME
        if headless, rethrow(ME); end
        local_throw_browser_transport_failure(ME);
    end
end
state = [];
sessionResult = struct('cleanupReason','','unfinished',false,'tmpDir','','runId','','port',NaN);
doProfile = local_profile_enabled();
tBridgeTotal = tic;
local_profile_log(doProfile, '[nm-prof] bridge open ENTER (entry=%s, requestedPort=%s)\n', char(htmlEntry), local_port_label(port, automaticPort));

t = tic;
webDir = char(java.io.File(webDir).getCanonicalPath());
tmpDir = char(java.io.File(fullfile(webDir,'tmp')).getCanonicalPath());
if ~exist(tmpDir,'dir'), mkdir(tmpDir); end
local_profile_log(doProfile, '[nm-prof]   bridge dirs/canonical:    %.3fs\n', toc(t));

flagPath = fullfile(tmpDir,'close.flag');
if exist(flagPath,'file'), delete(flagPath); end
currentPath = fullfile(tmpDir,'current_config.json');
% current_config.json is the authoritative live UI state and must not be
% deleted here; NMPreprocUI.export created it as the initial state.
t = tic;
nm_ui_bridge_cleanup_requests(tmpDir);
local_profile_log(doProfile, '[nm-prof]   bridge request cleanup:  %.3fs\n', toc(t));

t = tic;
scriptPath = char(java.io.File(fullfile(webDir,'python','nm_bridge_server.py')).getCanonicalPath());
htmlEntry = char(htmlEntry);
if contains(htmlEntry, filesep) || contains(htmlEntry, '/') || contains(htmlEntry, '\\')
    htmlPath = char(java.io.File(htmlEntry).getCanonicalPath());
    [htmlDir, htmlFile, htmlExt] = fileparts(htmlPath);
    if ~strcmpi(char(java.io.File(htmlDir).getCanonicalPath()), webDir)
        error('nm_open_ui:htmlOutsideWebDir', ...
            'The UI HTML entry point must be located inside webDir. Entry: %s; webDir: %s', htmlPath, webDir);
    end
    htmlEntry = [htmlFile htmlExt];
else
    htmlPath = char(java.io.File(fullfile(webDir, htmlEntry)).getCanonicalPath());
end
if ~exist(fileparts(scriptPath),'dir'), mkdir(fileparts(scriptPath)); end
% Always rewrite the bridge server from the MATLAB template.  The bridge is
% generated into a temporary web directory and must not keep stale endpoint
% code after UI lifecycle patches.
nm_ui_bridge_write_server(scriptPath);
if ~exist(htmlPath,'file'), error('UI HTML not found: %s', htmlPath); end
local_profile_log(doProfile, '[nm-prof]   bridge script/html prep: %.3fs\n', toc(t));

t = tic;
pycmd = local_python_exec();
local_profile_log(doProfile, '[nm-prof]   bridge python detect:    %.3fs (%s)\n', toc(t), pycmd);
portCandidates = local_port_candidates(port, automaticPort);
started = false;
lastMsg = '';
lastLogPath = '';
occupiedCount = 0;
tPortScan = tic;
for k = 1:numel(portCandidates)
    candPort = portCandidates(k);

    % Probe binding availability without asking an existing bridge to reveal
    % its tmp directory or runId. Authentication begins only after our bridge
    % has successfully started.
    tProbe = tic;
    [occupied, occMsg] = local_probe_port(candPort);
    local_profile_log(doProfile, '[nm-prof]   bridge probe port %d:    %.3fs (%s)\n', double(candPort), toc(tProbe), ternaryText(occupied, 'occupied', 'free'));
    if occupied
        occupiedCount = occupiedCount + 1;
        lastMsg = occMsg;
        fprintf('[nm] Port %d is already occupied (%s). Trying next port if available.\n', candPort, occMsg);
        continue;
    end

    runId = strrep(char(java.util.UUID.randomUUID()),'-','');
    logPath = fullfile(tmpDir, sprintf('bridge_%s_p%d.log', runId, candPort));
    lastLogPath = logPath;
    if exist(logPath,'file'), delete(logPath); end

    cmd = sprintf('%s "%s" --dir "%s" --web "%s" --port %d --runid "%s"', ...
        pycmd, scriptPath, tmpDir, webDir, candPort, runId);
    fprintf('[nm] Launching preprocessing UI bridge: %s\n', cmd);

    % The launcher owns this attempt from before its launch, through Ctrl+C and every error.
    bridgeCleanup = onCleanup(@() local_stop_owned_bridge(tmpDir, runId, candPort)); %#ok<NASGU>
    tLaunch = tic;
    [launchOk, launchMsg] = local_start_background(cmd, logPath);
    local_profile_log(doProfile, '[nm-prof]   bridge python spawn:    %.3fs (port=%d)\n', toc(tLaunch), double(candPort));
    if ~launchOk
        lastMsg = sprintf('bridge launch command failed: %s', launchMsg);
        fprintf('[nm] Port %d launch failed (%s). Trying next port if available.\n', candPort, launchMsg);
        continue;
    end

    tWait = tic;
    [ok, msg, bridgePid] = local_wait_bridge(candPort, tmpDir, runId, 8.0);
    local_profile_log(doProfile, '[nm-prof]   bridge health wait:     %.3fs (port=%d, ok=%d, msg=%s)\n', toc(tWait), double(candPort), double(ok), msg);
    if ok
        port = candPort;
        started = true;
        break;
    end
    % Never start a second producer beside a live one: an attempt that cannot be stopped ends startup here.
    local_stop_owned_bridge(tmpDir, runId, candPort);
    lastMsg = msg;
    fprintf('[nm] Port %d did not provide the expected bridge (%s). Trying next port if available.\n', candPort, msg);
end

local_profile_log(doProfile, '[nm-prof]   bridge port scan total: %.3fs (occupied=%d, selected=%s)\n', toc(tPortScan), double(occupiedCount), local_port_label(port, false));
if occupiedCount >= 3
    local_profile_log(doProfile, '[nm-prof]   bridge stale-port warning: %d occupied NM bridge port(s) were skipped. Close stale browser windows or Python bridge processes if startup remains slow.\n', double(occupiedCount));
end

if ~started
    if ~headless && ~htmlRelay
        fileUrl = sprintf('file:///%s', strrep(htmlPath,'\','/'));
        local_open_browser(fileUrl, browserTarget, browserExecutable);
    end
    error('nm_open_ui:noBridge', ...
        ['The UI bridge did not start or did not point to the current tmp directory/run id. ', ...
         'Last status: %s. Last bridge log: %s'], lastMsg, lastLogPath);
end

if strcmp(htmlEntry, 'nm_preproc_pipeline_ui.html')
    url = sprintf('http://127.0.0.1:%d/ui?port=%d&runid=%s', port, port, runId);
else
    url = sprintf('http://127.0.0.1:%d/%s?port=%d&runid=%s', port, htmlEntry, port, runId);
end
if isfield(sessionOptions,'InitialQuery') && isstruct(sessionOptions.InitialQuery) && isscalar(sessionOptions.InitialQuery)
    q = sessionOptions.InitialQuery;
    names = fieldnames(q);
    for iq = 1:numel(names)
        value = q.(names{iq});
        if isempty(value), continue; end
        url = sprintf('%s&%s=%s',url,NMUIBridgeTools.urlEncode(names{iq}),NMUIBridgeTools.urlEncode(char(string(value))));
    end
end
if doProfile
    url = sprintf('%s&profile=1', url);
end
t = tic;
ownedBrowserCleanup = [];
ownedBrowserProcess = [];
ownedBrowserProfile = '';
ownedBrowserLog = '';
htmlRelaySession = [];
htmlRelayCleanup = [];
if htmlRelay
    htmlRelaySession = local_open_html_relay(webDir, tmpDir, htmlEntry, url, port, runId);
    htmlRelayCleanup = onCleanup(@() local_close_html_relay(htmlRelaySession)); %#ok<NASGU>
elseif headless
    [ownedBrowserProcess, ownedBrowserProfile, ownedBrowserLog] = local_open_headless_browser(url, browserTarget, browserExecutable, tmpDir, runId);
    ownedBrowserCleanup = onCleanup(@() local_stop_owned_browser(ownedBrowserProcess, ownedBrowserProfile, ...
        'nm_open_ui:headlessProfileCleanupFailed', 'The automatic browser process')); %#ok<NASGU>
else
    try
        if strcmp(browserTarget, 'browser-default')
            local_open_browser(url, browserTarget, browserExecutable);
        else
            [ownedBrowserProcess, ownedBrowserProfile, ownedBrowserLog] = local_open_app_browser(url, browserTarget, browserExecutable, tmpDir, runId);
            ownedBrowserCleanup = onCleanup(@() local_stop_owned_browser(ownedBrowserProcess, ownedBrowserProfile, ...
                'nm_open_ui:appBrowserProfileCleanupFailed', 'The NM2 app browser process')); %#ok<NASGU>
        end
    catch ME
        local_throw_browser_transport_failure(ME);
    end
end
local_profile_log(doProfile, '[nm-prof]   UI transport open:       %.3fs (%s)\n', toc(t), uiTarget);
NMUIBridgeTools.registerActiveBridge(webDir, tmpDir, port, runId, htmlEntry);
ident = NMUISessionTools.userIdentity();
uidLabel = ident.uid; if isempty(uidLabel), uidLabel = 'n/a'; end
fprintf('[nm] UI session user=%s uid=%s matlabPid=%d runId=%s session=%s port=%d transport=%s\n', ...
    ident.user, uidLabel, round(ident.pid), runId, tmpDir, port, uiTarget);
local_profile_log(doProfile, '[nm-prof] bridge startup to UI:      %.3fs\n', toc(tBridgeTotal));
if headless
    fprintf('[nm] Waiting for headless browser task to finish.\n');
elseif htmlRelay
    fprintf('[nm] Waiting for html-relay UI to finish. Current configuration is maintained on disk. Press Finish / close module in the NM2 window.\n');
else
    fprintf('[nm] Waiting for browser UI to finish. Current configuration is maintained on disk. Press Finish / close module in the browser window.\n');
end
poll = local_poll_settings();
fastPollRemaining = 0;
clientEverAttached = false;
disconnectTimer = [];
reopenPendingTimer = [];
disconnectGraceSec = local_disconnect_grace_seconds();
reopenAttachGraceSec = local_reopen_attach_grace_seconds();
attachTimer = tic;
attachTimeoutSec = local_browser_attach_timeout_seconds();
bridgeCheckTimer = tic;
bridgeMisses = 0;
cleanupReason = ternaryText(htmlRelay, 'html-relay-finish', 'browser-finish');
tUiWait = tic;
while ~exist(flagPath,'file')
    if headless && ~logical(ownedBrowserProcess.isAlive())
        status = double(ownedBrowserProcess.exitValue());
        detail = '';
        if exist(ownedBrowserLog,'file') == 2, detail = strtrim(fileread(ownedBrowserLog)); end
        fprintf('[nm] UI cleanup reason=headless-browser-exited runId=%s port=%d\n', runId, port);
        error('nm_open_ui:headlessBrowserExited', ...
            'The automatic headless browser process exited with status %d before UI completion: %s',status,detail);
    end

    pendingBefore = local_count_pending_bridge_requests(tmpDir);
    if htmlRelay, pendingBefore = pendingBefore + local_count_pending_html_relay(tmpDir); end
    nHandled = nm_ui_bridge_dispatch_requests(tmpDir, matlabServiceHandler);
    if htmlRelay && nHandled > 0
        % Service-produced imaging packages are immutable supporting resources.
        % Mirror only packages not yet published to uihtml; page/navigation
        % materialization remains owned by local_sync_html_relay_web.
        tRelayAssets = tic;
        nRelayAssets = local_sync_html_relay_imaging_assets(webDir, htmlRelaySession.relayDir);
        local_profile_log(doProfile, ...
            '[nm-prof]   html-relay imaging asset sync: %.3fs (packages=%d)\n', ...
            toc(tRelayAssets),double(nRelayAssets));
    end
    nRelay = 0;
    if htmlRelay
        nRelay = local_html_relay_flush_responses(htmlRelaySession.html, tmpDir);
    end
    pendingAfter = local_count_pending_bridge_requests(tmpDir);
    if htmlRelay, pendingAfter = pendingAfter + local_count_pending_html_relay(tmpDir); end
    if pendingBefore > 0 || nHandled > 0 || nRelay > 0 || pendingAfter > 0
        fastPollRemaining = poll.activeBurst;
    elseif fastPollRemaining > 0
        fastPollRemaining = fastPollRemaining - 1;
    end

    if htmlRelay && local_html_relay_close_requested(htmlRelaySession.figure)
        action = local_html_relay_close_action();
        if strcmp(action,'quit')
            if local_finish_html_relay_close(port, runId, htmlRelaySession.clientId, tmpDir)
                cleanupReason = 'html-relay-disconnect-quit';
                break;
            end
            warning('nm_open_ui:htmlRelayCloseBusy', ...
                'The NM2 html-relay window cannot close while a MATLAB runtime job is active. The window has been restored.');
        end
        setappdata(htmlRelaySession.figure,'NMRelayCloseRequested',false);
        htmlRelaySession.figure.Visible = 'on';
    end

    if toc(bridgeCheckTimer) >= 1.0
        [bridgeAlive, bridgeState] = local_bridge_alive(port, runId);
        if bridgeAlive
            bridgeMisses = 0;
            if ~headless && ~htmlRelay
                clientState = bridgeState.client;
                if ~isempty(clientState) && isfield(clientState,'attached') && logical(clientState.attached)
                    clientEverAttached = true;
                    disconnectTimer = [];
                    reopenPendingTimer = [];
                elseif ~isempty(clientState)
                    % A fast close can transition opening -> detached between MATLAB polls,
                    % so detached itself proves that a browser controller existed.
                    if isfield(clientState,'state') && strcmpi(char(string(clientState.state)), 'detached')
                        clientEverAttached = true;
                    end
                    waitingForReopen = ~isempty(reopenPendingTimer) && toc(reopenPendingTimer) < reopenAttachGraceSec;
                    if waitingForReopen
                        disconnectTimer = [];
                    else
                        if ~isempty(reopenPendingTimer), reopenPendingTimer = []; end
                        if clientEverAttached && isempty(disconnectTimer), disconnectTimer = tic; end
                    end
                    if ~waitingForReopen && clientEverAttached && ~isempty(disconnectTimer) && toc(disconnectTimer) >= disconnectGraceSec
                        action = local_browser_disconnect_action(clientState);
                        if strcmp(action,'reopen')
                            reopenUrl = local_reopen_url(port, runId, clientState, doProfile, tmpDir);
                            fprintf('[nm] Reopening disconnected NM2 browser controller for runId=%s.\n', runId);
                            if strcmp(browserTarget, 'browser-default')
                                local_open_browser(reopenUrl, browserTarget, browserExecutable);
                            else
                                if ~isempty(ownedBrowserCleanup)
                                    clear ownedBrowserCleanup;
                                    ownedBrowserCleanup = [];
                                end
                                [ownedBrowserProcess, ownedBrowserProfile, ownedBrowserLog] = local_open_app_browser( ...
                                    reopenUrl, browserTarget, browserExecutable, tmpDir, runId);
                                ownedBrowserCleanup = onCleanup(@() local_stop_owned_browser(ownedBrowserProcess, ownedBrowserProfile, ...
                                    'nm_open_ui:appBrowserProfileCleanupFailed', 'The NM2 app browser process')); %#ok<NASGU>
                            end
                            disconnectTimer = [];
                            reopenPendingTimer = tic;
                        else
                            if local_finish_disconnected_browser(port, runId, clientState, tmpDir)
                                cleanupReason = 'browser-disconnect-quit';
                                break;
                            end
                            warning('nm_open_ui:disconnectQuitBusy', ...
                                'The browser is disconnected, but the bridge cannot close while a MATLAB runtime job is active. Reopen the browser to observe the running task.');
                            disconnectTimer = [];
                        end
                    end
                end
                if ~clientEverAttached && toc(attachTimer) >= attachTimeoutSec
                    reason = sprintf(['The browser transport opened but did not attach to the NM2 bridge within %.1f seconds. ', ...
                        'Run "nm ui html-relay" to use the embedded HTML relay transport.'], attachTimeoutSec);
                    error('nm_open_ui:browserTransportFailed','%s',reason);
                end
            end
        else
            bridgeMisses = bridgeMisses + 1;
            % html-relay needs no connection to the bridge: an unanswered health poll ends the session only if its process is gone.
            if bridgeMisses >= 2 && ~(htmlRelay && NMUIStateTools.processAlive(bridgePid))
                fprintf('[nm] UI cleanup reason=bridge-unreachable runId=%s port=%d\n', runId, port);
                error('nm_open_ui:bridgeUnreachable', ...
                    'The NM2 Python bridge for runId %s is no longer reachable on port %d. Current disk-backed UI state remains in %s.', runId, port, tmpDir);
            end
        end
        bridgeCheckTimer = tic;
    end

    if fastPollRemaining > 0
        pause(poll.activeSec);
    else
        pause(poll.idleSec);
    end
end
local_profile_log(doProfile, '[nm-prof] UI session duration:         %.3fs (%s)\n', toc(tUiWait), uiTarget);
completionState = struct();
if exist(flagPath,'file') == 2
    completionState = NMConfigTools.charifyStrings(NMConfigTools.decodeJson(fileread(flagPath)));
end

t = tic;
if exist(currentPath,'file')
    state = NMConfigTools.charifyStrings(NMConfigTools.decodeJson(fileread(currentPath)));
else
    launchPath = fullfile(tmpDir,'param.json');
    if exist(launchPath,'file')
        state = NMConfigTools.charifyStrings(NMConfigTools.decodeJson(fileread(launchPath)));
    elseif exist(fullfile(tmpDir,'nm2_state.json'),'file') == 2
        state = struct();
    else
        warning('nm_open_ui:noCurrentConfig','No current_config.json or param.json found; returning empty state.');
    end
end
if isstruct(completionState) && isfield(completionState,'reportExecutionResult') && isstruct(completionState.reportExecutionResult)
    if ~isstruct(state), state = struct(); end
    state.reportExecutionResult = completionState.reportExecutionResult;
end
fprintf('[nm] UI cleanup reason=%s runId=%s session=%s port=%d\n', cleanupReason, runId, tmpDir, port);
sessionResult = struct('cleanupReason',cleanupReason, ...
    'unfinished',any(strcmp(cleanupReason, {'browser-disconnect-quit','html-relay-disconnect-quit'})), ...
    'tmpDir',tmpDir,'runId',runId,'port',double(port));
local_profile_log(doProfile, '[nm-prof]   bridge final state read: %.3fs\n', toc(t));
local_profile_log(doProfile, '[nm-prof] bridge open TOTAL:         %.3fs\n', toc(tBridgeTotal));
end

function local_stop_owned_bridge(tmpDir, runId, port)
% local_stop_owned_bridge  Stop the bridge launched for runId; release its registration only after its process exited.
% NMUIStateTools.quiesce raises an error while the published PID is alive, which retains the registration.
state = NMUIStateTools.read(tmpDir);
if strcmp(NMUIStateTools.transportRunId(state), runId)
    NMUIStateTools.quiesce(struct('tmpDir',tmpDir,'state',state), true);
else
    % Nothing was published for this run: leave a run-bound stop request for a process that may still be starting.
    NMUIBridgeTools.writeKillFlag(tmpDir, struct('ok',false,'killed',true, ...
        'severity','info','reason','matlab-owner-exit','runId',runId));
end
NMUIBridgeTools.unregisterActiveBridge(tmpDir, port, runId);
end

function session = local_open_html_relay(webDir, tmpDir, htmlEntry, bridgeUrl, port, runId)
% local_open_html_relay  Open the embedded R2023+ HTML renderer for the shared bridge.
if exist('uifigure','file') ~= 2 || exist('uihtml','file') ~= 2
    error('nm_open_ui:htmlRelayUnavailable', ...
        'The html-relay transport requires uifigure/uihtml support in MATLAB R2023 or newer.');
end
bootstrapPath = fullfile(fileparts(mfilename('fullpath')), 'NMHTMLRelayBootstrap.js');
if exist(bootstrapPath,'file') ~= 2
    error('nm_open_ui:htmlRelayBootstrapMissing', ...
        'The html-relay bootstrap is missing: %s', bootstrapPath);
end
clientId = strrep(char(java.util.UUID.randomUUID()),'-','');
authUrl = local_url_add_query(bridgeUrl, 'clientid', clientId);
try
    webread(authUrl, weboptions('Timeout',8));
catch ME
    error('nm_open_ui:htmlRelayClientRegistrationFailed', ...
        'The html-relay could not register with the local NM2 bridge: %s', ME.message);
end
relayDir = fullfile(tmpDir,'html_relay');
if exist(relayDir,'dir') == 7, rmdir(relayDir,'s'); end
mkdir(relayDir);
local_sync_html_relay_web(webDir, relayDir, port);
initialPath = local_relay_source_path(webDir, htmlEntry, htmlEntry);
initialRelative = local_relative_path(webDir, initialPath);
relayHtml = fullfile(relayDir, initialRelative);
local_materialize_relay_html(initialPath, relayHtml, port, local_url_target(authUrl), bootstrapPath, true, 1.0, local_relay_resource_root(initialRelative));
isOnline = matlab.internal.environment.context.isMATLABOnline;
fig = uifigure('Name','NeuroMiner 2.0','Units','pixels','Visible','on');
setappdata(fig,'NMRelayCloseRequested',false);
grid = uigridlayout(fig,[1 1]);
grid.Padding = [0 0 0 0];
h = uihtml(grid);
h.HTMLEventReceivedFcn = @(src,event) local_html_relay_event(src,event,webDir,relayDir,tmpDir,htmlEntry,port,runId,clientId);
setappdata(h,'NMRelayZoom',1.0);
local_profile_log(local_profile_enabled(), '[nm-prof relay] HTMLSource assign START page=%s port=%d runId=%s\n',htmlEntry,port,runId);
h.HTMLSource = relayHtml;
local_profile_log(local_profile_enabled(), '[nm-prof relay] HTMLSource assigned page=%s port=%d runId=%s\n',htmlEntry,port,runId);
local_wait_html_relay_ready(h, fig, port, runId);
fig.CloseRequestFcn = @(src,~) local_mark_html_relay_close(src,h);
if ~isOnline
    fig.WindowState = 'maximized';
end
drawnow;
local_profile_log(local_profile_enabled(), '[nm-prof relay] D MATLAB geometry acknowledgement SEND page=%s online=%d\n',htmlEntry,double(isOnline));
sendEventToHTMLSource(h,'NMRelayGeometryApplied',isOnline);
local_profile_log(local_profile_enabled(), '[nm-prof relay] D MATLAB geometry acknowledgement RETURNED page=%s\n',htmlEntry);
session = struct('figure',fig,'html',h,'relayDir',relayDir,'clientId',clientId);
end

function local_wait_html_relay_ready(html, fig, port, runId)
% local_wait_html_relay_ready  Require a positive uihtml<->MATLAB event handshake before exposing NM2.
timeoutSec = 8;
t = tic;
while toc(t) < timeoutSec
    drawnow;
    if ~isempty(html) && isvalid(html) && isappdata(html,'NMRelayDisplayGeometry')
        display = getappdata(html,'NMRelayDisplayGeometry');
        fig.Position = [1 1 floor(display(1)) floor(display(2))];
        local_profile_log(local_profile_enabled(), '[nm-prof relay] D handshake COMPLETE %.3fs geometry=%.0fx%.0f\n',toc(t),display(1),display(2));
        return
    end
    pause(0.05);
end
[bridgeAlive,~] = local_bridge_alive(port,runId);
local_profile_log(local_profile_enabled(), '[nm-prof relay] D handshake TIMEOUT %.3fs bridgeAlive=%d\n',toc(t),double(bridgeAlive));
if ~isempty(fig) && isvalid(fig)
    delete(fig);
end
error('nm_open_ui:htmlRelayHandshakeTimeout', ...
    ['NM2 uihtml attachment timed out after %.1f s (phase=await NMRelayReady; bridge=%s; port=%d; runId=%s). ' ...
     'No positive event reached MATLAB; this alone cannot distinguish a missing browser setup call from a detached event channel.'], ...
    timeoutSec,ternaryText(bridgeAlive,'reachable','unreachable'),port,runId);
end

function local_close_html_relay(session)
% local_close_html_relay  Close only the embedded renderer owned by this session.
if ~isstruct(session) || ~isfield(session,'figure') || isempty(session.figure), return; end
try
    if isvalid(session.figure)
        session.figure.CloseRequestFcn = [];
        delete(session.figure);
    end
catch ME
    warning('nm_open_ui:htmlRelayCloseCleanupFailed', ...
        'The embedded NM2 html-relay renderer could not be closed cleanly: %s', ME.message);
end
end

function local_mark_html_relay_close(fig, html)
% local_mark_html_relay_close  Snapshot page-exit state and defer the close decision to the session loop.
if isempty(fig) || ~isvalid(fig), return; end
if ~isempty(html) && isvalid(html)
    try
        sendEventToHTMLSource(html,'NMRelayLifecycle','pagehide');
    catch ME
        warning('nm_open_ui:htmlRelayLifecycleSignalFailed', ...
            'The html-relay could not signal page-exit state persistence: %s', ME.message);
    end
end
setappdata(fig,'NMRelayCloseRequested',true);
fig.Visible = 'off';
end

function tf = local_html_relay_close_requested(fig)
% local_html_relay_close_requested  Read the renderer-close signal owned by the relay figure.
tf = logical(getappdata(fig,'NMRelayCloseRequested'));
end

function action = local_html_relay_close_action()
% local_html_relay_close_action  Ask whether a closed relay renderer should reopen or end NM.
message = sprintf(['The embedded NM2 HTML window was closed.\n\n', ...
    'Current disk-backed configuration has been preserved.']);
action = '';
if usejava('desktop') && exist('questdlg','file') == 2
    choice = questdlg(message, 'NM2 HTML relay closed', 'Reopen window', 'Quit NM', 'Reopen window');
    if strcmp(choice,'Quit NM'), action = 'quit'; else, action = 'reopen'; end
    return
end
fprintf('\n[nm] %s\n', message);
while isempty(action)
    reply = lower(strtrim(input('Reopen NM2 window [R] or quit NM [Q]? ', 's')));
    if any(strcmp(reply, {'r','reopen'})), action = 'reopen'; end
    if any(strcmp(reply, {'q','quit'})), action = 'quit'; end
end
end

function tf = local_finish_html_relay_close(port, runId, clientId, tmpDir)
% local_finish_html_relay_close  End an explicitly confirmed relay-window session when no MATLAB job is active.
tf = false;
baseUrl = sprintf('http://127.0.0.1:%d', port);
auth = sprintf('runid=%s&clientid=%s', NMUIBridgeTools.urlEncode(runId), NMUIBridgeTools.urlEncode(clientId));
active = local_get_json(sprintf('%s/api/matlabjob/active?%s', baseUrl, auth));
if isstruct(active) && isfield(active,'found') && logical(active.found)
    return
end
payload = struct('ok',false,'killed',true,'severity','info', ...
    'message','NM2 html-relay session ended after the embedded UI window was closed.', ...
    'reason','html-relay-disconnect-quit','unfinished',true, ...
    'time',datestr(now,31),'runId',runId);
NMUIBridgeTools.writeKillFlag(tmpDir, payload);
tf = true;
end

function local_html_relay_event(src, event, webDir, relayDir, tmpDir, htmlEntry, port, runId, clientId)
% local_html_relay_event  Convert one uihtml event into the existing bridge transport contract.
name = char(string(event.HTMLEventName));
data = event.HTMLEventData;
if strcmp(name,'NMRelayReady')
    local_profile_log(local_profile_enabled(), '[nm-prof relay] D NMRelayReady callback ENTER sessionEntry=%s port=%d runId=%s\n',htmlEntry,port,runId);
end
try
    switch name
        case 'NMRelayReady'
            if ~isstruct(data) || ~isscalar(data) || ~isfield(data,'marker') || ...
                    ~strcmp(char(string(data.marker)),'NM2_HTML_RELAY_V1')
                error('nm_open_ui:invalidHtmlRelayReady','html-relay ready event is malformed.');
            end
            validateattributes(data.availWidth,{'numeric'},{'scalar','finite','positive'});
            validateattributes(data.availHeight,{'numeric'},{'scalar','finite','positive'});
            if isappdata(src,'NMRelayDisplayGeometry')
                sendEventToHTMLSource(src,'NMRelayGeometryApplied',false);
            end
            setappdata(src,'NMRelayDisplayGeometry',[double(data.availWidth) double(data.availHeight)]);
            local_profile_log(local_profile_enabled(), '[nm-prof relay] D NMRelayReady geometry ACCEPTED %.0fx%.0f\n',double(data.availWidth),double(data.availHeight));
            local_profile_log(local_profile_enabled(),'[nm-prof relay] ready received port=%d runId=%s page=%s\n',port,runId,htmlEntry);
        case 'NMRelayViewportClip'
            fig = ancestor(src,'figure');
            pos = fig.Position;
            validateattributes(data,{'numeric'},{'scalar','finite','>',2,'<',pos(4)/2});
            clip = floor(double(data));
            fig.Position = [pos(1) pos(2)+clip pos(3) pos(4)-clip];
            fprintf('[nm] html-relay visible-height correction: %d px (%.0f -> %.0f px).\n',clip,pos(4),pos(4)-clip);
            drawnow;
            sendEventToHTMLSource(src,'NMRelayGeometryApplied',false);
        case 'NMRelayZoom'
            if ~isstruct(data) || ~isscalar(data) || ~isfield(data,'zoom') || ...
                    ~isnumeric(data.zoom) || ~isscalar(data.zoom) || ~isfinite(data.zoom) || ...
                    data.zoom < 0.5 || data.zoom > 2.0
                error('nm_open_ui:invalidHtmlRelayZoom','html-relay zoom event is malformed.');
            end
            setappdata(src,'NMRelayZoom',double(data.zoom));
        case 'NMRelayRequest'
            if ~isstruct(data) || ~isscalar(data) || ~isfield(data,'id')
                error('nm_open_ui:invalidHtmlRelayRequest','html-relay request event is malformed.');
            end
            token = char(string(data.id));
            if isempty(regexp(token,'^[A-Za-z0-9_-]+$','once')) %#ok<RGXP1>
                error('nm_open_ui:invalidHtmlRelayRequestId','html-relay request id contains unsupported characters.');
            end
            requestPath = fullfile(tmpDir, ['htmlrelay_req_' token '.json']);
            if exist(requestPath,'file') == 2 || exist([requestPath '.working'],'file') == 2
                error('nm_open_ui:duplicateHtmlRelayRequest','Duplicate html-relay request id: %s',token);
            end
            local_atomic_json(requestPath, data);
            local_profile_log(local_profile_enabled(),'[nm-prof relay] request queued id=%s port=%d\n',token,port);
        case 'NMRelayNavigate'
            if ~isstruct(data) || ~isscalar(data) || ~isfield(data,'target')
                error('nm_open_ui:invalidHtmlRelayNavigation','html-relay navigation event is malformed.');
            end
            local_profile_log(local_profile_enabled(), '[nm-prof relay] NAVIGATION request received port=%d\n',port);
            local_html_relay_navigate(src, char(string(data.target)), webDir, relayDir, htmlEntry, port, runId, clientId);
        otherwise
            error('nm_open_ui:unknownHtmlRelayEvent','Unsupported html-relay event: %s',name);
    end
catch ME
    if strcmp(name,'NMRelayReady')
        local_profile_log(local_profile_enabled(), '[nm-prof relay] D NMRelayReady callback ERROR %s\n',ME.message);
    end
    if strcmp(name,'NMRelayRequest') && isstruct(data) && isfield(data,'id')
        reply = struct('id',char(string(data.id)),'status',0,'statusText','', ...
            'headers',{{}},'bodyBase64','','error',NMUIErrorTools.messageWithStack(ME,'Relay request failed.',3));
        try
            sendEventToHTMLSource(src,'NMRelayResponse',reply);
        catch sendME
            warning('nm_open_ui:htmlRelayErrorResponseFailed', ...
                'The html-relay request failed and its error response could not be delivered: %s', sendME.message);
        end
        return
    end
    rethrow(ME)
end
end

function local_html_relay_navigate(html, target, webDir, relayDir, htmlEntry, port, runId, clientId)
% local_html_relay_navigate  Materialize one existing NM2 page and replace the uihtml document.
if isempty(target), error('nm_open_ui:emptyHtmlRelayNavigation','html-relay navigation target is empty.'); end
local_sync_html_relay_web(webDir, relayDir, port);
sourcePath = local_relay_source_path(webDir, target, htmlEntry);
relative = local_relative_path(webDir, sourcePath);
relayPath = fullfile(relayDir, relative);
bootstrapPath = fullfile(fileparts(mfilename('fullpath')), 'NMHTMLRelayBootstrap.js');
bridgeTarget = local_bridge_target_url(port, runId, clientId, target);
try
    webread(bridgeTarget, weboptions('Timeout',8));
catch ME
    error('nm_open_ui:htmlRelayNavigationRegistrationFailed', ...
        'The local bridge rejected html-relay navigation to %s: %s', target, ME.message);
end
zoom = getappdata(html,'NMRelayZoom');
local_materialize_relay_html(sourcePath, relayPath, port, local_url_target(bridgeTarget), bootstrapPath, true, zoom, local_relay_resource_root(relative));
local_profile_log(local_profile_enabled(), '[nm-prof relay] NAVIGATION HTMLSource assign START target=%s port=%d\n',target,port);
html.HTMLSource = relayPath;
local_profile_log(local_profile_enabled(), '[nm-prof relay] NAVIGATION HTMLSource assigned target=%s port=%d\n',target,port);
end

function n = local_html_relay_flush_responses(html, tmpDir)
% local_html_relay_flush_responses  Deliver completed relay responses into the active uihtml document.
% Python publishes complete responses atomically; this MATLAB poller is their sole consumer.
% Do not add a second claim/rename phase to an already published response.
files = dir(fullfile(tmpDir,'htmlrelay_rsp_*.json'));
n = 0;
for i = 1:numel(files)
    path = fullfile(files(i).folder,files(i).name);
    [responseText, openError] = nm_ui_bridge_read_text(path);
    if isempty(openError)
        response = NMConfigTools.charifyStrings(NMConfigTools.decodeJson(responseText));
    else
        warning('nm_open_ui:htmlRelayResponseUnreadable', '%s', openError);
        response = struct('id',files(i).name(numel('htmlrelay_rsp_')+1:end-5),'status',0,'statusText','', ...
            'headers',{{}},'bodyBase64','','error',openError);
    end
    if isempty(html) || ~isvalid(html)
        error('nm_open_ui:htmlRelayRendererClosed','html-relay response completed after its renderer was destroyed.');
    end
    sendEventToHTMLSource(html,'NMRelayResponse',response);
    if ~isempty(dir(path)), delete(path); end
    local_profile_log(local_profile_enabled(),'[nm-prof relay] response submitted id=%s status=%d\n',response.id,double(response.status));
    n = n + 1;
end
end

function n = local_count_pending_html_relay(tmpDir)
% local_count_pending_html_relay  Count transport files so the session poller remains responsive under relay traffic.
n = numel(dir(fullfile(tmpDir,'htmlrelay_req_*.json'))) + ...
    numel(dir(fullfile(tmpDir,'htmlrelay_req_*.json.working'))) + ...
    numel(dir(fullfile(tmpDir,'htmlrelay_rsp_*.json')));
end

function local_sync_html_relay_web(webDir, relayDir, port)
% local_sync_html_relay_web  Mirror generated web assets without changing their application code.
if exist(relayDir,'dir') ~= 7, mkdir(relayDir); end
bootstrapPath = fullfile(fileparts(mfilename('fullpath')), 'NMHTMLRelayBootstrap.js');
entries = dir(fullfile(webDir,'**','*'));
rootPrefix = [webDir filesep];
for i = 1:numel(entries)
    entry = entries(i);
    if entry.isdir, continue; end
    src = fullfile(entry.folder,entry.name);
    if ~startsWith(src,rootPrefix), continue; end
    rel = src(numel(rootPrefix)+1:end);
    parts = regexp(rel, regexptranslate('escape',filesep), 'split');
    if isempty(parts) || any(strcmp(parts{1},{'tmp','python'})), continue; end
    dst = fullfile(relayDir,rel);
    parent = fileparts(dst); if exist(parent,'dir') ~= 7, mkdir(parent); end
    dstInfo = dir(dst);
    isHtml = endsWith(entry.name,'.html','IgnoreCase',true);
    if isHtml
        % Relay HTML contains an injected transport bootstrap, so its byte count
        % intentionally differs from the source. Source modification time is
        % therefore the deterministic refresh criterion for HTML pages.
        needsCopy = isempty(dstInfo) || entry.datenum > dstInfo(1).datenum + 1e-8;
    else
        needsCopy = isempty(dstInfo) || dstInfo(1).bytes ~= entry.bytes || entry.datenum > dstInfo(1).datenum + 1e-8;
    end
    if ~needsCopy, continue; end
    if isHtml
        local_materialize_relay_html(src,dst,port,'',bootstrapPath,false,1.0,local_relay_resource_root(rel));
    else
        [ok,msg] = copyfile(src,dst,'f');
        if ~ok, error('nm_open_ui:htmlRelayAssetCopyFailed','Could not mirror %s: %s',src,msg); end
    end
end
end

function nCopied = local_sync_html_relay_imaging_assets(webDir, relayDir)
% local_sync_html_relay_imaging_assets  Publish newly materialized immutable imaging packages only.
sourceRoot = fullfile(webDir,'results_imaging_cache');
nCopied = 0;
% nm2-allow: html-relay supporting-resource filesystem boundary.
if exist(sourceRoot,'dir') ~= 7, return; end
destinationRoot = fullfile(relayDir,'results_imaging_cache');
% nm2-allow: html-relay supporting-resource filesystem boundary.
if exist(destinationRoot,'dir') ~= 7, mkdir(destinationRoot); end
packages = dir(sourceRoot);
for ii = 1:numel(packages)
    package = packages(ii);
    if ~package.isdir || strcmp(package.name,'.') || strcmp(package.name,'..'), continue; end
    destination = fullfile(destinationRoot,package.name);
    % nm2-allow: immutable uihtml supporting-resource package publication boundary.
    if exist(destination,'dir') == 7, continue; end
    source = fullfile(package.folder,package.name);
    [ok,msg] = copyfile(source,destination);
    if ~ok
        error('nm_open_ui:htmlRelayImagingAssetCopyFailed', ...
            'Could not publish imaging asset package %s: %s',source,msg);
    end
    nCopied = nCopied + 1;
end
end

function local_materialize_relay_html(sourcePath, relayPath, port, initialTarget, bootstrapPath, isRoot, zoom, resourceRoot)
% local_materialize_relay_html  Inject only the transport adapter into an otherwise unchanged NM2 HTML page.
txt = fileread(sourcePath);
bootstrap = fileread(bootstrapPath);
config = jsonencode(struct('port',double(port),'initialTarget',char(initialTarget),'root',logical(isRoot),'zoom',double(zoom),'resourceRoot',resourceRoot));
setupTrace = '';
diagnostic = '';
if isRoot && local_profile_enabled()
    diagnostic = sprintf('<script>%s</script>\n',fileread(fullfile(fileparts(mfilename('fullpath')),'NMHTMLRelayDiagnostic.js')));
    setupTrace = 'window.NMRelayTrace("B uihtml setup invoked");';
end
setup = ['function setup(htmlComponent){' setupTrace ...
    'if(typeof window.NMHTMLRelaySetup!=="function"){' ...
    'throw new Error("NM2 html-relay bootstrap did not initialize.");}' ...
    'window.NMHTMLRelaySetup(htmlComponent);}'];
injection = sprintf('<script>window.NM_HTML_RELAY_CONFIG=%s;%s</script>\n%s<script>%s</script>\n',config,setup,diagnostic,bootstrap);
[~,headEnd] = regexp(lower(txt),'<head[^>]*>','once');
if isempty(headEnd)
    out = [injection txt];
else
    out = [txt(1:headEnd) newline injection txt(headEnd+1:end)];
end
parent = fileparts(relayPath); if exist(parent,'dir') ~= 7, mkdir(parent); end
fid = fopen(relayPath,'w','n','UTF-8');
if fid < 0, error('nm_open_ui:htmlRelayHtmlWriteFailed','Could not write relay HTML: %s',relayPath); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',out);
end

function resourceRoot = local_relay_resource_root(relativePath)
% local_relay_resource_root  Prefix from one materialized HTML page back to the relay root.
parent = fileparts(relativePath);
if isempty(parent)
    resourceRoot = '';
    return
end
parts = regexp(parent, regexptranslate('escape',filesep), 'split');
resourceRoot = repmat('../',1,numel(parts));
end

function path = local_relay_source_path(webDir, target, htmlEntry)
% local_relay_source_path  Resolve a relay navigation target strictly inside webDir.
pathPart = regexp(char(target),'^[^?#]*','match','once');
if isempty(pathPart) || strcmp(pathPart,'/') || strcmp(pathPart,'/ui') || strcmp(pathPart,'ui')
    pathPart = htmlEntry;
end
pathPart = strrep(pathPart,'/',filesep);
while startsWith(pathPart,filesep), pathPart = pathPart(2:end); end
candidate = char(java.io.File(fullfile(webDir,pathPart)).getCanonicalPath());
root = char(java.io.File(webDir).getCanonicalPath());
if ~strcmp(candidate,root) && ~startsWith(candidate,[root filesep])
    error('nm_open_ui:htmlRelayNavigationOutsideWebDir','html-relay navigation escapes webDir: %s',target);
end
if exist(candidate,'file') ~= 2
    error('nm_open_ui:htmlRelayNavigationMissing','html-relay navigation target does not exist: %s',candidate);
end
path = candidate;
end

function relative = local_relative_path(root, path)
% local_relative_path  Return a canonical child path relative to its canonical root.
root = char(java.io.File(root).getCanonicalPath());
path = char(java.io.File(path).getCanonicalPath());
if ~startsWith(path,[root filesep])
    error('nm_open_ui:htmlRelayPathOutsideWebDir','Relay source is not inside webDir: %s',path);
end
relative = path(numel(root)+2:end);
end

function target = local_url_target(url)
% local_url_target  Extract path/query from one bridge URL without changing its application parameters.
token = regexp(char(url),'^https?://[^/]+(.*)$','tokens','once');
if isempty(token) || isempty(token{1}), target = '/'; else, target = token{1}; end
end

function url = local_url_add_query(url, name, value)
% local_url_add_query  Append one URL-encoded query parameter.
sep = '?'; if contains(url,'?'), sep = '&'; end
url = sprintf('%s%s%s=%s',url,sep,NMUIBridgeTools.urlEncode(name),NMUIBridgeTools.urlEncode(value));
end

function url = local_bridge_target_url(port, runId, clientId, target)
% local_bridge_target_url  Build the authenticated localhost URL used only to register relay navigation.
if startsWith(target,'http://') || startsWith(target,'https://')
    token = regexp(target,'^https?://[^/]+(.*)$','tokens','once');
    if isempty(token), target = '/'; else, target = token{1}; end
end
if ~startsWith(target,'/'), target = ['/' target]; end
url = sprintf('http://127.0.0.1:%d%s',port,target);
url = local_url_add_query(url,'runid',runId);
url = local_url_add_query(url,'clientid',clientId);
end

function local_atomic_json(path, value)
% local_atomic_json  Publish one relay request atomically for the Python relay worker.
tmp = [path '.tmp_' strrep(char(java.util.UUID.randomUUID()),'-','')];
txt = jsonencode(value);
fid = fopen(tmp,'w','n','UTF-8');
if fid < 0, error('nm_open_ui:htmlRelayRequestWriteFailed','Could not write relay request: %s',tmp); end
fprintf(fid,'%s',txt);
fclose(fid);
[ok,msg] = movefile(tmp,path,'f');
if ~ok
    if exist(tmp,'file') == 2, delete(tmp); end
    error('nm_open_ui:htmlRelayRequestPublishFailed','Could not publish relay request: %s',msg);
end
end

function sec = local_browser_attach_timeout_seconds()
% local_browser_attach_timeout_seconds  Bound browser startup so unsupported environments fail with an actionable route.
sec = local_env_ms('NM_UI_ATTACH_TIMEOUT_MS',15000,3000,60000) / 1000;
end

function local_throw_browser_transport_failure(cause)
% local_throw_browser_transport_failure  Preserve browser failure diagnostics and name the explicit alternative transport.
ME = MException('nm_open_ui:browserTransportFailed', ...
    ['The NM2 browser transport failed: %s\n', ...
     'Run "nm ui html-relay" to use the embedded HTML relay transport.'], cause.message);
ME = addCause(ME,cause);
throw(ME);
end

function tf = local_option_logical(options, fieldName, defaultValue)
% local_option_logical  Read one strict scalar logical bridge-session option.
tf = logical(defaultValue);
if ~isstruct(options) || ~isfield(options,fieldName) || isempty(options.(fieldName)), return; end
value = options.(fieldName);
if ~(islogical(value) || isnumeric(value)) || ~isscalar(value)
    error('nm_open_ui:invalidSessionLogicalOption', ...
        'UI bridge session option %s must be a scalar logical/numeric value.', fieldName);
end
tf = logical(value);
end

function [process, profileDir, logPath] = local_open_headless_browser(url, target, executable, tmpDir, runId)
% local_open_headless_browser  Start one isolated browser process owned by this bridge session.
if isempty(executable)
    error('nm_open_ui:browserUnavailable','No executable was resolved for headless browser target %s.',target);
end
profileDir = fullfile(tmpDir, ['headless_browser_' runId]);
if exist(profileDir,'dir') == 7, rmdir(profileDir,'s'); end
mkdir(profileDir);
logPath = fullfile(tmpDir, ['headless_browser_' runId '.log']);
if exist(logPath,'file') == 2, delete(logPath); end
switch target
    case {'browser-edge','browser-chrome'}
        arguments = {executable, '--headless=new', '--disable-extensions', ...
            '--disable-background-networking', '--disable-default-apps', '--disable-sync', ...
            '--metrics-recording-only', '--mute-audio', '--no-first-run', ...
            '--no-default-browser-check', '--enable-webgl', '--ignore-gpu-blocklist', ...
            '--window-size=1280,900', ['--user-data-dir=' profileDir]};
        if isunix && ~ismac, arguments{end+1} = '--disable-dev-shm-usage'; end %#ok<AGROW>
        arguments{end+1} = url;
    case 'browser-firefox'
        arguments = {executable, '-headless', '-no-remote', '-profile', profileDir, url};
    otherwise
        error('nm_open_ui:invalidBrowserTarget','Unsupported headless browser target: %s',target);
end
process = local_start_owned_browser_process(arguments, logPath, ...
    'nm_open_ui:headlessBrowserLaunchFailed', sprintf('Headless %s', target));
fprintf('[nm] Headless %s process started for automatic UI execution.\n',target);
end

function [process, profileDir, logPath] = local_open_app_browser(url, target, executable, tmpDir, runId)
% local_open_app_browser  Start one isolated interactive NM2 application window owned by this bridge session.
if isempty(executable)
    error('nm_open_ui:browserUnavailable','No executable was resolved for browser target %s.',target);
end
profileDir = fullfile(tmpDir, ['app_browser_' runId]);
if exist(profileDir,'dir') == 7, rmdir(profileDir,'s'); end
mkdir(profileDir);
logPath = fullfile(tmpDir, ['app_browser_' runId '.log']);
if exist(logPath,'file') == 2, delete(logPath); end
switch target
    case {'browser-edge','browser-chrome'}
        arguments = {executable, ['--app=' url], ['--user-data-dir=' profileDir], ...
            '--no-first-run', '--no-default-browser-check', '--disable-background-mode', ...
            '--start-maximized'};
    case 'browser-firefox'
        if ispc
            arguments = {executable, '-no-remote', '-profile', profileDir, ...
                '-taskbar-tab', ['nm2' runId], '-new-window', url};
        else
            % Firefox Web Apps are not exposed as a stable application-window
            % command on all platforms. Keep the explicit Firefox target
            % isolated and single-window rather than forcing kiosk mode.
            arguments = {executable, '-no-remote', '-profile', profileDir, '-new-window', url};
        end
    otherwise
        error('nm_open_ui:invalidBrowserTarget','Unsupported app browser target: %s',target);
end
process = local_start_owned_browser_process(arguments, logPath, ...
    'nm_open_ui:appBrowserLaunchFailed', sprintf('%s app window', target));
fprintf('[nm] %s application window started in an isolated browser profile.\n',target);
end

function process = local_start_owned_browser_process(arguments, logPath, errorId, label)
% local_start_owned_browser_process  Start one browser process from an exact argument vector and verify that it remains alive.
javaArgs = javaArray('java.lang.String',numel(arguments));
for ii = 1:numel(arguments)
    javaArgs(ii) = javaObject('java.lang.String',arguments{ii});
end
builder = javaObject('java.lang.ProcessBuilder',javaArgs);
builder.redirectErrorStream(true);
builder.redirectOutput(javaObject('java.io.File',logPath));
process = builder.start();
pause(0.15);
if ~logical(process.isAlive())
    status = double(process.exitValue());
    detail = '';
    if exist(logPath,'file') == 2, detail = strtrim(fileread(logPath)); end
    error(errorId, '%s exited during startup with status %d: %s', label, status, detail);
end
end

function local_stop_owned_browser(process, profileDir, warningId, label)
% local_stop_owned_browser  Terminate an owned browser process and remove its isolated profile.
if ~isempty(process)
    if logical(process.isAlive())
        process.destroy();
        pause(0.15);
    end
    if logical(process.isAlive())
        process.destroyForcibly();
        pause(0.15);
    end
end
if ~isempty(profileDir) && exist(profileDir,'dir') == 7
    [ok,msg] = rmdir(profileDir,'s');
    if ~ok
        warning(warningId, '%s ended but its temporary profile could not be removed: %s', label, msg);
    end
end
end

function tf = local_finish_disconnected_browser(port, runId, clientState, tmpDir)
% local_finish_disconnected_browser  End a detached browser session through the private bridge-control channel.
tf = false;
if ~isstruct(clientState) || ~isfield(clientState,'clientId') || isempty(clientState.clientId)
    error('nm_open_ui:missingDisconnectedClientId','Detached browser state has no client identity.');
end
clientId = char(string(clientState.clientId));
baseUrl = sprintf('http://127.0.0.1:%d', port);
auth = sprintf('runid=%s&clientid=%s', NMUIBridgeTools.urlEncode(runId), NMUIBridgeTools.urlEncode(clientId));
active = local_get_json(sprintf('%s/api/matlabjob/active?%s', baseUrl, auth));
if isstruct(active) && isfield(active,'found') && logical(active.found)
    return
end
payload = struct('ok',false,'killed',true,'severity','info', ...
    'message','NM2 browser session ended after the controlling browser disconnected.', ...
    'reason','browser-disconnect-quit','unfinished',true, ...
    'time',datestr(now,31),'runId',runId);
NMUIBridgeTools.writeKillFlag(tmpDir, payload);
tf = true;
end

function action = local_browser_disconnect_action(clientState)
% local_browser_disconnect_action  Ask the MATLAB user whether to reopen or quit a detached browser controller.
page = '';
reason = 'browser connection closed';
if isstruct(clientState)
    if isfield(clientState,'pageTarget') && ~isempty(clientState.pageTarget), page = char(string(clientState.pageTarget)); end
    if isfield(clientState,'reason') && ~isempty(clientState.reason), reason = char(string(clientState.reason)); end
end
message = sprintf(['The browser controlling this NM2 session is no longer connected.\n\n', ...
    'Page: %s\nReason: %s\n\nCurrent disk-backed configuration has been preserved.'], page, reason);
action = '';
if usejava('desktop') && exist('questdlg','file') == 2
    choice = questdlg(message, 'NM2 browser disconnected', 'Reopen browser', 'Quit NM', 'Reopen browser');
    if strcmp(choice,'Quit NM'), action = 'quit'; else, action = 'reopen'; end
    return
end
fprintf('\n[nm] %s\n', message);
while isempty(action)
    reply = lower(strtrim(input('Reopen browser [R] or quit NM [Q]? ', 's')));
    if any(strcmp(reply, {'r','reopen'})), action = 'reopen'; end
    if any(strcmp(reply, {'q','quit'})), action = 'quit'; end
end
end

function sec = local_disconnect_grace_seconds()
% local_disconnect_grace_seconds  Short grace for same-tab internal navigation after a transport detach event.
sec = local_env_ms('NM_UI_DISCONNECT_GRACE_MS', 900, 250, 5000) / 1000;
end

function sec = local_reopen_attach_grace_seconds()
% local_reopen_attach_grace_seconds  Allow a newly launched replacement browser to attach before asking again.
sec = local_env_ms('NM_UI_REOPEN_ATTACH_GRACE_MS', 8000, 1000, 30000) / 1000;
end

function url = local_reopen_url(port, runId, clientState, doProfile, tmpDir)
% local_reopen_url  Reopen the last authenticated NM2 page with a fresh active browser-client identity.
if ~isstruct(clientState) || ~isfield(clientState,'clientId') || isempty(clientState.clientId)
    error('nm_open_ui:missingReopenClientId','Cannot reopen a browser session without the previous browser client id.');
end
target = '/ui';
if isfield(clientState,'pageTarget') && ~isempty(clientState.pageTarget)
    target = char(string(clientState.pageTarget));
elseif isfield(clientState,'page') && ~isempty(clientState.page)
    target = char(string(clientState.page));
end
if ~startsWith(target,'/'), target = ['/' target]; end
sep = '?'; if contains(target,'?'), sep = '&'; end
if ~contains(target,'port=')
    target = sprintf('%s%sport=%d', target, sep, port);
    sep = '&';
end
reopenToken = NMUIBridgeTools.authorizeControllerReopen(tmpDir, runId, clientState.clientId);
url = sprintf('http://127.0.0.1:%d%s%srunid=%s&reopen=1&previousclientid=%s&reopentoken=%s', ...
    port, target, sep, NMUIBridgeTools.urlEncode(runId), ...
    NMUIBridgeTools.urlEncode(clientState.clientId), NMUIBridgeTools.urlEncode(reopenToken));
if doProfile && ~contains(url,'profile=1')
    url = sprintf('%s&profile=1', url);
end
end

function [tf, diag] = local_bridge_alive(port, runId)
% local_bridge_alive  Verify the active bridge and return its live controller snapshot.
% The existing health poll is the sole source of controller liveness. No file
% is read: a failed checkpoint publication cannot imply browser loss. Transport
% failures retain the caller's two-miss bridge-unreachable handling; no stale
% controller snapshot is used on a failed poll. Other callers may omit diag.
tf = false;
diag = [];
try
    diag = local_get_json(sprintf('http://127.0.0.1:%d/api/diag?runid=%s', ...
        port, NMUIBridgeTools.urlEncode(runId)));
    tf = isstruct(diag) && isfield(diag,'runid') && strcmp(char(string(diag.runid)), char(string(runId)));
catch
    tf = false;
end
end

function tf = local_profile_enabled()
% local_profile_enabled  Perform the local profile enabled step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

tf = any(strcmpi(strtrim(getenv('NM_UI_PROFILE')), {'1','true','on','yes'}));
end

function local_profile_log(enabled, varargin)
% local_profile_log  Perform the local profile log step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

if ~enabled, return; end
try
    fprintf(varargin{:});
catch
end
end

function poll = local_poll_settings()
% local_poll_settings  Perform the local poll settings step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

idleMs = local_env_ms('NM_UI_POLL_IDLE_MS', 200, 20, 2000);
activeMs = local_env_ms('NM_UI_POLL_ACTIVE_MS', 10, 5, 500);
activeBurst = local_env_ms('NM_UI_POLL_BURST_COUNT', 50, 1, 500);
poll = struct('idleSec',idleMs/1000, 'activeSec',activeMs/1000, 'activeBurst',round(activeBurst));
end

function v = local_env_ms(name, defaultValue, minValue, maxValue)
% local_env_ms  Perform the local env ms step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

v = defaultValue;
try
    raw = strtrim(getenv(name));
    if ~isempty(raw)
        x = str2double(raw);
        if isfinite(x) && x > 0, v = x; end
    end
catch
    v = defaultValue;
end
v = max(minValue, min(maxValue, v));
end

function n = local_count_pending_bridge_requests(tmpDir)
% local_count_pending_bridge_requests  Perform the local count pending bridge requests step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

n = 0;
try
    if nargin < 1 || isempty(tmpDir) || exist(tmpDir,'dir') ~= 7, return; end
    d = dir(fullfile(tmpDir,'*_request_*.json'));
    if ~isempty(d), n = numel(d); end
catch
    n = 0;
end
end

function txt = ternaryText(cond, a, b)
% ternaryText  Perform the ternary Text step in the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if cond, txt = a; else, txt = b; end
end

function target = local_normalize_ui_target(value)
% local_normalize_ui_target  Validate the one startup vocabulary routed by this authority.
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error('nm_open_ui:invalidUITarget', ...
        'UI target must be a character vector or scalar string.');
end
target = lower(strtrim(char(value)));
allowed = {'browser-default','browser-edge','browser-chrome','browser-firefox','html-relay'};
if ~any(strcmp(target, allowed))
    error('nm_open_ui:invalidUITarget', ...
        'Unsupported UI target: %s', target);
end
end

function executable = local_resolve_browser_executable(target)
% local_resolve_browser_executable  Resolve an explicitly requested browser before starting the bridge.
if strcmp(target, 'browser-default')
    executable = '';
    return
end

[candidates, pathNames] = local_browser_candidates(target);
for i = 1:numel(candidates)
    candidate = candidates{i};
    if ~isempty(candidate) && exist(candidate, 'file') == 2
        executable = candidate;
        return
    end
end
for i = 1:numel(pathNames)
    executable = local_find_executable_on_path(pathNames{i});
    if ~isempty(executable), return; end
end
error('nm_open_ui:browserUnavailable', ...
    'The requested browser target %s is not installed or is not discoverable.', target);
end

function [candidates, pathNames] = local_browser_candidates(target)
% local_browser_candidates  Return exact platform candidates for one canonical target.
candidates = {};
pathNames = {};
if ispc
    programFiles = getenv('ProgramFiles');
    programFilesX86 = getenv('ProgramFiles(x86)');
    localAppData = getenv('LOCALAPPDATA');
    switch target
        case 'browser-edge'
            candidates = local_windows_browser_candidates( ...
                {programFiles,programFilesX86,localAppData}, ...
                {'Microsoft','Edge','Application','msedge.exe'});
            pathNames = {'msedge.exe'};
        case 'browser-chrome'
            candidates = local_windows_browser_candidates( ...
                {programFiles,programFilesX86,localAppData}, ...
                {'Google','Chrome','Application','chrome.exe'});
            pathNames = {'chrome.exe'};
        case 'browser-firefox'
            candidates = local_windows_browser_candidates( ...
                {programFiles,programFilesX86,localAppData}, ...
                {'Mozilla Firefox','firefox.exe'});
            pathNames = {'firefox.exe'};
    end
elseif ismac
    homeDir = char(java.lang.System.getProperty('user.home'));
    switch target
        case 'browser-edge'
            candidates = { ...
                '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge', ...
                fullfile(homeDir,'Applications','Microsoft Edge.app','Contents','MacOS','Microsoft Edge')};
            pathNames = {'microsoft-edge'};
        case 'browser-chrome'
            candidates = { ...
                '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', ...
                fullfile(homeDir,'Applications','Google Chrome.app','Contents','MacOS','Google Chrome')};
            pathNames = {'google-chrome'};
        case 'browser-firefox'
            candidates = { ...
                '/Applications/Firefox.app/Contents/MacOS/firefox', ...
                fullfile(homeDir,'Applications','Firefox.app','Contents','MacOS','firefox')};
            pathNames = {'firefox'};
    end
else
    switch target
        case 'browser-edge'
            pathNames = {'microsoft-edge','microsoft-edge-stable'};
        case 'browser-chrome'
            pathNames = {'google-chrome','google-chrome-stable','chromium','chromium-browser'};
        case 'browser-firefox'
            pathNames = {'firefox'};
    end
end
end

function candidates = local_windows_browser_candidates(roots, suffixParts)
% local_windows_browser_candidates  Build absolute candidates only from defined Windows roots.
candidates = {};
for i = 1:numel(roots)
    root = roots{i};
    if isempty(root), continue; end
    candidates{end+1} = fullfile(root, suffixParts{:}); %#ok<AGROW>
end
end

function executable = local_find_executable_on_path(name)
% local_find_executable_on_path  Resolve one executable name from the platform PATH.
executable = '';
if ispc
    command = sprintf('where.exe "%s"', name);
else
    command = sprintf('command -v "%s"', name);
end
[status, output] = system(command);
if status ~= 0, return; end
lines = regexp(strtrim(output), '\r?\n', 'split');
for i = 1:numel(lines)
    candidate = strtrim(lines{i});
    if ~isempty(candidate) && exist(candidate, 'file') == 2
        executable = candidate;
        return
    end
end
end

function local_open_browser(url, target, executable)
% local_open_browser  Open one URL through the canonical browser-launch authority.
if strcmp(target, 'browser-default')
    web(url, '-browser');
    return
end
if isempty(executable)
    error('nm_open_ui:browserUnavailable', ...
        'No executable was resolved for browser target %s.', target);
end
if contains(executable, '"') || contains(url, '"')
    error('nm_open_ui:invalidBrowserLaunchArgument', ...
        'Browser executable and URL must not contain double-quote characters.');
end
fprintf('[nm] Opening %s: %s\n', target, executable);
if ispc
    command = sprintf('cmd /c start "" "%s" "%s"', executable, url);
else
    command = sprintf('"%s" "%s" >/dev/null 2>&1 &', executable, url);
end
[status, output] = system(command);
if status ~= 0
    error('nm_open_ui:browserLaunchFailed', ...
        'Launching %s failed with status %d: %s', target, status, strtrim(output));
end
end

function pycmd = local_python_exec()
% local_python_exec  Perform the local python exec step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

candidates = {};
lastMsg = '';
try
    envCmd = strtrim(getenv('NM_PYTHON_EXEC'));
    if ~isempty(envCmd)
        candidates{end+1} = envCmd; %#ok<AGROW>
    end
catch ME
    lastMsg = sprintf('NM_PYTHON_EXEC check failed: %s', ME.message);
end
try
    pe = pyenv;
    if ~isempty(pe.Executable)
        candidates{end+1} = sprintf('"%s"', char(pe.Executable)); %#ok<AGROW>
    end
catch ME
    if isempty(lastMsg), lastMsg = sprintf('MATLAB pyenv check failed: %s', ME.message); end
end
if ispc
    candidates = [candidates, {'"python"', 'py -3'}]; %#ok<AGROW>
else
    candidates = [candidates, {'"python3"', '"python"'}]; %#ok<AGROW>
end
for i = 1:numel(candidates)
    cand = strtrim(candidates{i});
    if isempty(cand), continue; end
    checkCmd = sprintf('%s -c "import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)"', cand);
    [st,out] = system(checkCmd);
    if st == 0
        pycmd = cand;
        return;
    end
    out = strtrim(out);
    if isempty(out), out = sprintf('status %d', st); end
    lastMsg = sprintf('%s -> %s', cand, out);
end
if isempty(lastMsg), lastMsg = 'no candidate command was available'; end
error('nm_open_ui:noPython', ...
    ['No Python 3 executable could be resolved for the NeuroMiner UI bridge. ', ...
     'Checked NM_PYTHON_EXEC, MATLAB pyenv, and standard platform launchers. ', ...
     'Set NM_PYTHON_EXEC to a valid Python 3 executable or configure MATLAB pyenv. Last check: %s'], lastMsg);
end

function [ok, msg] = local_start_background(cmd, logPath)
% local_start_background  Perform the local start background step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

ok = false; msg = '';
if ispc
    shellCmd = sprintf('cmd /c start "" /B %s 1>> "%s" 2>&1', cmd, logPath);
else
    shellCmd = sprintf('%s >> "%s" 2>&1 &', cmd, logPath);
end
[st,out] = system(shellCmd);
if st ~= 0
    msg = strtrim(out);
    if isempty(msg), msg = sprintf('system returned status %d', st); end
    return;
end
ok = true;
end

function candidates = local_port_candidates(requestedPort, automaticPort)
% local_port_candidates  Build candidate ports without changing MATLAB's scientific random stream.
if automaticPort
    firstPort = 49152; span = 16384; nWanted = 64;
    randomSource = java.security.SecureRandom();
    candidates = zeros(1,nWanted); n = 0;
    while n < nWanted
        cand = firstPort + double(randomSource.nextInt(int32(span)));
        if n == 0 || ~any(candidates(1:n) == cand)
            n = n + 1; candidates(n) = cand;
        end
    end
    return
end
requestedPort = double(requestedPort);
if ~isscalar(requestedPort) || ~isfinite(requestedPort) || requestedPort < 1 || requestedPort > 65535 || requestedPort ~= round(requestedPort)
    error('nm_open_ui:invalidPort','UI bridge port must be an integer from 1 to 65535.');
end
candidates = requestedPort:min(65535, requestedPort + 19);
end

function [occupied, msg] = local_probe_port(port)
% local_probe_port  Test loopback bind availability without querying another process for session metadata.
occupied = true; msg = 'port unavailable';
server = [];
try
    server = java.net.ServerSocket();
    cleaner = onCleanup(@() local_close_server_socket(server)); %#ok<NASGU>
    server.setReuseAddress(false);
    server.bind(java.net.InetSocketAddress('127.0.0.1', int32(port)));
    occupied = false; msg = 'available';
catch ME
    msg = strtrim(ME.message);
    if isempty(msg), msg = 'loopback bind failed'; end
end
end

function local_close_server_socket(server)
% local_close_server_socket  Close a temporary Java bind probe.
if ~isempty(server)
    try server.close(); catch, end
end
end

function label = local_port_label(port, automaticPort)
% local_port_label  Format automatic versus explicit bridge-port diagnostics.
if automaticPort || isempty(port) || ~isfinite(double(port))
    label = 'automatic';
else
    label = sprintf('%d', round(double(port)));
end
end

function [ok, msg, pid] = local_wait_bridge(port, expectedTmpDir, expectedRunId, timeoutSec)
% local_wait_bridge  Perform the local wait bridge step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

ok = false; msg = 'timeout'; pid = NaN; t0 = tic;
expectedTmpDir = char(java.io.File(expectedTmpDir).getCanonicalPath());
while toc(t0) < timeoutSec
    try
        diag = local_get_json(sprintf('http://127.0.0.1:%d/api/diag?runid=%s', port, NMUIBridgeTools.urlEncode(expectedRunId)));
        if isstruct(diag) && isfield(diag,'tmp')
            gotTmp = char(java.io.File(char(diag.tmp)).getCanonicalPath());
            if ~strcmpi(gotTmp, expectedTmpDir)
                msg = sprintf('port in use by different bridge tmp=%s', gotTmp);
                return;
            end
            if ~isfield(diag,'runid') || ~strcmp(char(diag.runid), expectedRunId)
                if isfield(diag,'runid')
                    msg = sprintf('port in use by stale bridge runid=%s', char(diag.runid));
                else
                    msg = 'port in use by stale bridge without run id';
                end
                return;
            end
            try
                caps = local_get_json(sprintf('http://127.0.0.1:%d/api/capabilities?runid=%s', port, NMUIBridgeTools.urlEncode(expectedRunId)));
                if isstruct(caps) && isfield(caps,'pickpath') && logical(caps.pickpath)
                    ok = true; msg = 'ok'; pid = diag.pid; return;
                else
                    msg = 'bridge lacks pickpath capability';
                    return;
                end
            catch ME2
                msg = sprintf('bridge without /api/capabilities (%s)', ME2.message);
                return;
            end
        else
            msg = 'diag endpoint returned no tmp field';
        end
    catch ME
        msg = ME.message;
    end
    pause(0.05);
end
end

function data = local_get_json(url)
% local_get_json  Read a struct field with an explicit fallback while preserving caller-provided values.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

try
    opts = weboptions('Timeout', 1);
    data = webread(url, opts);
    return;
catch
end
u = java.net.URL(url);
c = u.openConnection(); c.setConnectTimeout(700); c.setReadTimeout(700);
is = java.io.InputStreamReader(c.getInputStream(), 'UTF-8');
br = java.io.BufferedReader(is);
buf = java.lang.StringBuilder();
line = br.readLine();
while ~isempty(line)
    buf.append(line); %#ok<JAPIMATH>
    line = br.readLine();
end
br.close();
data = NMConfigTools.decodeJson(char(buf.toString()));
end

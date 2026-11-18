function [state, sessionResult] = nm_open_ui_http(webDir, port, htmlEntry, matlabServiceHandler, browserTarget, sessionOptions)
% nm_open_ui_http  Start the local HTTP browser bridge and return UI state after Finish/Close.
% Controller liveness comes from the bridge's in-memory state via its existing
% health poll. UI draft persistence remains separate from browser connectivity.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 1 || isempty(webDir), webDir = pwd; end
automaticPort = nargin < 2 || isempty(port);
if automaticPort, port = NaN; end
if nargin < 3 || isempty(htmlEntry), htmlEntry = 'nm_preproc_pipeline_ui.html'; end
if nargin < 4, matlabServiceHandler = []; end
if nargin < 5 || isempty(browserTarget), browserTarget = 'browser-default'; end
if nargin < 6 || isempty(sessionOptions), sessionOptions = struct(); end
if ~isstruct(sessionOptions) || ~isscalar(sessionOptions)
    error('nm_open_ui_http:invalidSessionOptions','UI bridge session options must be one scalar struct.');
end
headless = local_option_logical(sessionOptions, 'Headless', false);
browserTarget = local_normalize_browser_target(browserTarget);
if headless && strcmp(browserTarget, 'browser-default')
    error('nm_open_ui_http:headlessBrowserTargetRequired', ...
        'Headless UI execution requires an explicit browser target: browser-edge, browser-chrome or browser-firefox.');
end
browserExecutable = local_resolve_browser_executable(browserTarget);
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
        error('nm_open_ui_http:htmlOutsideWebDir', ...
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
runId = char(java.util.UUID.randomUUID());
runId = strrep(runId,'-','');
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

    logPath = fullfile(tmpDir, sprintf('bridge_%s_p%d.log', runId, candPort));
    lastLogPath = logPath;
    if exist(logPath,'file'), delete(logPath); end

    cmd = sprintf('%s "%s" --dir "%s" --web "%s" --port %d --runid "%s"', ...
        pycmd, scriptPath, tmpDir, webDir, candPort, runId);
    fprintf('[nm] Launching preprocessing UI bridge: %s\n', cmd);

    tLaunch = tic;
    [launchOk, launchMsg] = local_start_background(cmd, logPath);
    local_profile_log(doProfile, '[nm-prof]   bridge python spawn:    %.3fs (port=%d)\n', toc(tLaunch), double(candPort));
    if ~launchOk
        lastMsg = sprintf('bridge launch command failed: %s', launchMsg);
        fprintf('[nm] Port %d launch failed (%s). Trying next port if available.\n', candPort, launchMsg);
        continue;
    end

    tWait = tic;
    [ok, msg] = local_wait_bridge(candPort, tmpDir, runId, 8.0);
    local_profile_log(doProfile, '[nm-prof]   bridge health wait:     %.3fs (port=%d, ok=%d, msg=%s)\n', toc(tWait), double(candPort), double(ok), msg);
    if ok
        port = candPort;
        started = true;
        break;
    end
    lastMsg = msg;
    fprintf('[nm] Port %d did not provide the expected bridge (%s). Trying next port if available.\n', candPort, msg);
    pause(0.3);
end

local_profile_log(doProfile, '[nm-prof]   bridge port scan total: %.3fs (occupied=%d, selected=%s)\n', toc(tPortScan), double(occupiedCount), local_port_label(port, false));
if occupiedCount >= 3
    local_profile_log(doProfile, '[nm-prof]   bridge stale-port warning: %d occupied NM bridge port(s) were skipped. Close stale browser windows or Python bridge processes if startup remains slow.\n', double(occupiedCount));
end

if ~started
    if ~headless
        fileUrl = sprintf('file:///%s', strrep(htmlPath,'\','/'));
        local_open_browser(fileUrl, browserTarget, browserExecutable);
    end
    error('nm_open_ui_http:noBridge', ...
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
if headless
    [ownedBrowserProcess, ownedBrowserProfile, ownedBrowserLog] = local_open_headless_browser(url, browserTarget, browserExecutable, tmpDir, runId);
    ownedBrowserCleanup = onCleanup(@() local_stop_owned_browser(ownedBrowserProcess, ownedBrowserProfile, ...
        'nm_open_ui_http:headlessProfileCleanupFailed', 'The automatic browser process')); %#ok<NASGU>
elseif strcmp(browserTarget, 'browser-default')
    local_open_browser(url, browserTarget, browserExecutable);
else
    [ownedBrowserProcess, ownedBrowserProfile, ownedBrowserLog] = local_open_app_browser(url, browserTarget, browserExecutable, tmpDir, runId);
    ownedBrowserCleanup = onCleanup(@() local_stop_owned_browser(ownedBrowserProcess, ownedBrowserProfile, ...
        'nm_open_ui_http:appBrowserProfileCleanupFailed', 'The NM2 app browser process')); %#ok<NASGU>
end
local_profile_log(doProfile, '[nm-prof]   bridge browser open:     %.3fs\n', toc(t));
NMUIBridgeTools.registerActiveBridge(webDir, tmpDir, port, runId, htmlEntry);
ident = NMUISessionTools.userIdentity();
uidLabel = ident.uid; if isempty(uidLabel), uidLabel = 'n/a'; end
fprintf('[nm] UI session user=%s uid=%s matlabPid=%d runId=%s session=%s port=%d\n', ...
    ident.user, uidLabel, round(ident.pid), runId, tmpDir, port);
local_profile_log(doProfile, '[nm-prof] bridge startup to browser: %.3fs\n', toc(tBridgeTotal));
if headless
    fprintf('[nm] Waiting for headless browser task to finish.\n');
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
bridgeCheckTimer = tic;
bridgeMisses = 0;
cleanupReason = 'browser-finish';
tUiWait = tic;
while ~exist(flagPath,'file')
    if headless && ~logical(ownedBrowserProcess.isAlive())
        status = double(ownedBrowserProcess.exitValue());
        detail = '';
        if exist(ownedBrowserLog,'file') == 2, detail = strtrim(fileread(ownedBrowserLog)); end
        NMUIBridgeTools.writeKillFlag(tmpDir, struct('ok',false,'killed',true,'severity','danger', ...
            'message','The automatic headless browser process exited before report execution completed.', ...
            'time',datestr(now,31),'runId',runId));
        fprintf('[nm] UI cleanup reason=headless-browser-exited runId=%s port=%d\n', runId, port);
        error('nm_open_ui_http:headlessBrowserExited', ...
            'The automatic headless browser process exited with status %d before UI completion: %s',status,detail);
    end

    pendingBefore = local_count_pending_bridge_requests(tmpDir);
    nHandled = nm_ui_bridge_dispatch_requests(tmpDir, matlabServiceHandler);
    pendingAfter = local_count_pending_bridge_requests(tmpDir);
    if pendingBefore > 0 || nHandled > 0 || pendingAfter > 0
        fastPollRemaining = poll.activeBurst;
    elseif fastPollRemaining > 0
        fastPollRemaining = fastPollRemaining - 1;
    end

    if toc(bridgeCheckTimer) >= 1.0
        [bridgeAlive, bridgeState] = local_bridge_alive(port, runId);
        if bridgeAlive
            bridgeMisses = 0;
            if ~headless
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
                                    'nm_open_ui_http:appBrowserProfileCleanupFailed', 'The NM2 app browser process')); %#ok<NASGU>
                            end
                            disconnectTimer = [];
                            reopenPendingTimer = tic;
                        else
                            if local_finish_disconnected_browser(port, runId, clientState, tmpDir)
                                cleanupReason = 'browser-disconnect-quit';
                                break;
                            end
                            warning('nm_open_ui_http:disconnectQuitBusy', ...
                                'The browser is disconnected, but the bridge cannot close while a MATLAB runtime job is active. Reopen the browser to observe the running task.');
                            disconnectTimer = [];
                        end
                    end
                end
            end
        else
            bridgeMisses = bridgeMisses + 1;
            if bridgeMisses >= 2
                fprintf('[nm] UI cleanup reason=bridge-unreachable runId=%s port=%d\n', runId, port);
                error('nm_open_ui_http:bridgeUnreachable', ...
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
local_profile_log(doProfile, '[nm-prof] bridge browser session duration: %.3fs\n', toc(tUiWait));
if strcmp(cleanupReason,'browser-disconnect-quit')
    deadline = tic;
    while toc(deadline) < 3.5 && local_bridge_alive(port, runId), pause(0.1); end
end

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
        warning('nm_open_ui_http:noCurrentConfig','No current_config.json or param.json found; returning empty state.');
    end
end
if isstruct(completionState) && isfield(completionState,'reportExecutionResult') && isstruct(completionState.reportExecutionResult)
    if ~isstruct(state), state = struct(); end
    state.reportExecutionResult = completionState.reportExecutionResult;
end
nm_ui_bridge_cleanup_requests(tmpDir);
NMUIBridgeTools.unregisterActiveBridge(tmpDir, port, runId);
fprintf('[nm] UI cleanup reason=%s runId=%s session=%s port=%d\n', cleanupReason, runId, tmpDir, port);
sessionResult = struct('cleanupReason',cleanupReason, ...
    'unfinished',strcmp(cleanupReason,'browser-disconnect-quit'), ...
    'tmpDir',tmpDir,'runId',runId,'port',double(port));
local_profile_log(doProfile, '[nm-prof]   bridge final state read: %.3fs\n', toc(t));
local_profile_log(doProfile, '[nm-prof] bridge open TOTAL:         %.3fs\n', toc(tBridgeTotal));
end

function tf = local_option_logical(options, fieldName, defaultValue)
% local_option_logical  Read one strict scalar logical bridge-session option.
tf = logical(defaultValue);
if ~isstruct(options) || ~isfield(options,fieldName) || isempty(options.(fieldName)), return; end
value = options.(fieldName);
if ~(islogical(value) || isnumeric(value)) || ~isscalar(value)
    error('nm_open_ui_http:invalidSessionLogicalOption', ...
        'UI bridge session option %s must be a scalar logical/numeric value.', fieldName);
end
tf = logical(value);
end

function [process, profileDir, logPath] = local_open_headless_browser(url, target, executable, tmpDir, runId)
% local_open_headless_browser  Start one isolated browser process owned by this bridge session.
if isempty(executable)
    error('nm_open_ui_http:browserUnavailable','No executable was resolved for headless browser target %s.',target);
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
        error('nm_open_ui_http:invalidBrowserTarget','Unsupported headless browser target: %s',target);
end
process = local_start_owned_browser_process(arguments, logPath, ...
    'nm_open_ui_http:headlessBrowserLaunchFailed', sprintf('Headless %s', target));
fprintf('[nm] Headless %s process started for automatic UI execution.\n',target);
end

function [process, profileDir, logPath] = local_open_app_browser(url, target, executable, tmpDir, runId)
% local_open_app_browser  Start one isolated interactive NM2 application window owned by this bridge session.
if isempty(executable)
    error('nm_open_ui_http:browserUnavailable','No executable was resolved for browser target %s.',target);
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
        error('nm_open_ui_http:invalidBrowserTarget','Unsupported app browser target: %s',target);
end
process = local_start_owned_browser_process(arguments, logPath, ...
    'nm_open_ui_http:appBrowserLaunchFailed', sprintf('%s app window', target));
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
    error('nm_open_ui_http:missingDisconnectedClientId','Detached browser state has no client identity.');
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
    error('nm_open_ui_http:missingReopenClientId','Cannot reopen a browser session without the previous browser client id.');
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

tf = false;
try
    env = getenv('NM_UI_PROFILE');
    if ~isempty(env)
        tf = any(strcmpi(strtrim(env), {'1','true','on','yes'}));
    end
catch
    tf = false;
end
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

function target = local_normalize_browser_target(value)
% local_normalize_browser_target  Validate the canonical browser-target vocabulary.
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error('nm_open_ui_http:invalidBrowserTarget', ...
        'Browser target must be a character vector or scalar string.');
end
target = lower(strtrim(char(value)));
allowed = {'browser-default','browser-edge','browser-chrome','browser-firefox'};
if ~any(strcmp(target, allowed))
    error('nm_open_ui_http:invalidBrowserTarget', ...
        'Unsupported browser target: %s', target);
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
error('nm_open_ui_http:browserUnavailable', ...
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
    error('nm_open_ui_http:browserUnavailable', ...
        'No executable was resolved for browser target %s.', target);
end
if contains(executable, '"') || contains(url, '"')
    error('nm_open_ui_http:invalidBrowserLaunchArgument', ...
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
    error('nm_open_ui_http:browserLaunchFailed', ...
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
error('nm_open_ui_http:noPython', ...
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
    error('nm_open_ui_http:invalidPort','UI bridge port must be an integer from 1 to 65535.');
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

function [ok, msg] = local_wait_bridge(port, expectedTmpDir, expectedRunId, timeoutSec)
% local_wait_bridge  Perform the local wait bridge step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

ok = false; msg = 'timeout'; t0 = tic;
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
                    ok = true; msg = 'ok'; return;
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

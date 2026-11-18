classdef NMUISessionTools
% NMUISessionTools
% -------------------------------------------------------------------------
% Shared browser-session directory resolver for NeuroMiner UI pages.
%
% Standalone pages keep their previous one-session-per-export layout.  The
% app/workbench page can pass a shared web/tmp directory through ctx so child
% pages are written into the active bridge session instead of opening a new
% browser bridge.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = resolve(outDir, ctx, defaultRoot)
            % resolve  Resolve session, web, tmp and python directories for a UI export.
            %
            % Normalizes output paths, creates the directory structure used by NM browser pages and
            % returns both filesystem and web-root locations. This is the common session bootstrap for UI
            % exporters.
            %
            % ctx.NMAppSharedSession: exposes the nmapp shared session execution-context value to preprocessing/runtime code.
            % ctx.NMAppTmpDir: exposes the nmapp tmp dir execution-context value to preprocessing/runtime code.
            % ctx.NMAppWebDir: exposes the nmapp web dir execution-context value to preprocessing/runtime code.

            shared = isstruct(ctx) && isfield(ctx,'NMAppSharedSession') && ... % nm2-allow: NMAppUI shared-session context is optional at the session-bootstrap ingress; standalone exports omit these workbench fields.
                logical(ctx.NMAppSharedSession) && isfield(ctx,'NMAppWebDir') && ... % nm2-allow: NMAppUI shared-session context is optional at the session-bootstrap ingress; standalone exports omit these workbench fields.
                isfield(ctx,'NMAppTmpDir') && ~isempty(ctx.NMAppWebDir) && ... % nm2-allow: NMAppUI shared-session context is optional at the session-bootstrap ingress; standalone exports omit these workbench fields.
                ~isempty(ctx.NMAppTmpDir);

            if shared
                webDir = char(string(ctx.NMAppWebDir)); % nm2-allow: NMAppUI shared-session context is optional at the session-bootstrap ingress; standalone exports omit these workbench fields.
                tmpDir = char(string(ctx.NMAppTmpDir)); % nm2-allow: NMAppUI shared-session context is optional at the session-bootstrap ingress; standalone exports omit these workbench fields.
                webRoot = fileparts(webDir);
                rootDir = fileparts(webRoot);
                if isempty(rootDir), rootDir = outDir; end
            else
                rootDir = NMUISessionTools.sessionRoot(outDir, defaultRoot);
                outDir = rootDir;
                webRoot = fullfile(rootDir,'web');
                sessionTag = ['session_' strrep(char(java.util.UUID.randomUUID()),'-','_')];
                webDir = fullfile(webRoot, sessionTag);
                tmpDir = fullfile(webDir,'tmp');
            end

            pyDir = fullfile(webDir,'python');
            NMUISessionTools.ensureDir(rootDir);
            NMUISessionTools.ensureDir(webRoot);
            NMUISessionTools.ensureDir(webDir);
            NMUISessionTools.ensureDir(pyDir);
            NMUISessionTools.ensureDir(tmpDir);
            sessionDirs = {rootDir, webRoot, webDir, pyDir, tmpDir};
            for iDir = 1:numel(sessionDirs)
                if NMUISessionTools.isTempPath(sessionDirs{iDir})
                    NMUISessionTools.securePrivateDir(sessionDirs{iDir});
                end
            end

            paths = struct('root', rootDir, 'webRoot', webRoot, 'webDir', webDir, ...
                'pyDir', pyDir, 'tmpDir', tmpDir, 'shared', shared);
        end


        function rootDir = sessionRoot(outDir, defaultRoot)
            % sessionRoot  Resolve the root containing isolated browser session directories.
            defaultOutDir = fullfile(tempdir, defaultRoot);
            if isempty(outDir) || strcmpi(NMUISessionTools.canonicalPath(outDir), NMUISessionTools.canonicalPath(defaultOutDir))
                rootDir = NMUISessionTools.privateTempRoot(defaultRoot);
            else
                rootDir = char(string(outDir)); % nm2-allow: NMUISessionTools.sessionRoot accepts caller-supplied path text at the public standalone exporter boundary.
            end
        end

        function rootDir = privateTempRoot(defaultRoot)
            % privateTempRoot  Resolve one user-private NM2 temporary root.
            %
            % Default browser-session roots must not be shared between OS users on multi-user/HPC
            % hosts. Explicit caller-provided output directories are not rewritten by this helper.
            ident = NMUISessionTools.userIdentity();
            userToken = regexprep(lower(ident.user), '[^a-zA-Z0-9_.-]', '_');
            if isempty(userToken)
                error('NMUISessionTools:invalidUserIdentity','The operating-system user name cannot be converted into a private NM2 session-root token.');
            end
            if ~isempty(ident.uid)
                userToken = sprintf('%s_%s', userToken, regexprep(ident.uid, '[^0-9]', ''));
            end
            userRoot = fullfile(tempdir, ['nm2_' userToken]);
            NMUISessionTools.ensureDir(userRoot);
            NMUISessionTools.securePrivateDir(userRoot);
            rootDir = fullfile(userRoot, defaultRoot);
            NMUISessionTools.ensureDir(rootDir);
            NMUISessionTools.securePrivateDir(rootDir);
        end

        function rootDir = privateProcessTempRoot(cacheName)
            % Share decompressed files across browser sessions in one MATLAB
            % process, never across processes that may be writing concurrently.
            persistent processRoot
            if isempty(processRoot)
                userRoot = NMUISessionTools.privateTempRoot('dataio_materialization');
                processTag = ['process_' strrep(char(java.util.UUID.randomUUID()),'-','_')];
                processRoot = fullfile(userRoot, processTag);
                NMUISessionTools.ensureDir(processRoot);
                NMUISessionTools.securePrivateDir(processRoot);
            end
            rootDir = fullfile(processRoot, cacheName);
            if exist(rootDir,'dir') ~= 7
                NMUISessionTools.ensureDir(rootDir);
                NMUISessionTools.securePrivateDir(rootDir);
            end
        end

        function cleanupMaterializationStage(stageDir)
            % Stage may already have been renamed to its published cache path.
            if exist(stageDir,'dir') == 7
                [ok,msg] = rmdir(stageDir,'s');
                if ~ok
                    warning('NMUISessionTools:materializationStageCleanupFailed', ...
                        'Could not remove temporary scientific staging directory %s: %s', stageDir, msg);
                end
            end
        end

        function ident = userIdentity()
            % userIdentity  Return OS user, numeric UID where available, and MATLAB PID for lifecycle diagnostics.
            userName = strtrim(char(java.lang.System.getProperty('user.name')));
            if isempty(userName)
                error('NMUISessionTools:missingUserIdentity','The operating-system user name is unavailable; NM2 cannot create a user-private UI session root.');
            end
            uid = '';
            if isunix
                [status, out] = system('id -u');
                uid = strtrim(out);
                if status ~= 0 || isempty(regexp(uid, '^\d+$', 'once'))
                    error('NMUISessionTools:missingNumericUid','NM2 could not resolve the numeric operating-system UID required for multi-user UI-session isolation.');
                end
            end
            pid = double(feature('getpid'));
            if ~isfinite(pid) || pid <= 0
                error('NMUISessionTools:missingMatlabPid','NM2 could not resolve the current MATLAB process identifier.');
            end
            ident = struct('user',userName,'uid',uid,'pid',pid);
        end

        function ctx2 = childContext(ctx, webDir, tmpDir, page)
            % childContext  Build app context for a child UI page.
            %
            % Carries shared web/tmp directories, page identity and navigation flags from the app shell
            % to a child page so it can export into the same bridge session.

            ctx2 = ctx;
            ctx2.NMAppSharedSession = true;
            ctx2.NMAppWebDir = webDir;
            ctx2.NMAppTmpDir = tmpDir;
            ctx2.NMAppCaller = 'workbench';
            ctx2.NMAppReturnPage = 'nm_workbench.html';
            ctx2.NMAppChildPage = page;
        end

        function tf = keepSessionAfterImport(ctx)
            % keepSessionAfterImport  Decide whether session files should survive importUpdated.
            %
            % Reads context flags used by app-shell child pages to keep temporary state while the parent
            % session remains active. Standalone sessions normally clean up.
            %
            % ctx.NMAppKeepSessionAfterImport: exposes the nmapp keep session after import execution-context value to preprocessing/runtime code.

            tf = isstruct(ctx) && isfield(ctx,'NMAppKeepSessionAfterImport') && ... % nm2-allow: NMAppUI navigation context optionally writes NMAppKeepSessionAfterImport; shared-session lifecycle must preserve its absence.
                logical(ctx.NMAppKeepSessionAfterImport);
        end

        function tf = fastChildOpen(ctx)
            % fastChildOpen  Report whether a child page should open with bootstrap state.
            %
            % Reads context flags that allow rapid browser navigation before full MATLAB-side state
            % resolution. Child pages subsequently refresh through service calls.
            %
            % ctx.NMAppFastChildOpen: exposes the nmapp fast child open execution-context value to preprocessing/runtime code.

            tf = isstruct(ctx) && isfield(ctx,'NMAppFastChildOpen') && ... % nm2-allow: NMAppUI navigation context optionally writes NMAppFastChildOpen; standalone browser exporters omit this switch.
                ~isempty(ctx.NMAppFastChildOpen) && logical(ctx.NMAppFastChildOpen);
        end

        function ctx2 = attachAppContextToState(ctx, state, page)
            % attachAppContextToState  Attach navigation/session metadata to browser state.
            %
            % Adds page identity and app-context flags to state structs returned by UI exporters and
            % service refreshes. The method keeps navigation metadata separate from domain configuration.
            %
            % ctx.NMAppCaller: exposes the nmapp caller execution-context value to preprocessing/runtime code.

            ctx2 = state;
            if isstruct(ctx) && isfield(ctx,'NMAppCaller') && strcmp(char(string(ctx.NMAppCaller)), 'workbench') % nm2-allow: NMAppUI writes optional NMAppCaller and return-page navigation context; page values originate at the browser-navigation boundary.
                ctx2.appContext = struct('caller','workbench', ...
                    'returnToWorkbench', true, ...
                    'returnPage', NMUISessionTools.ctxChar(ctx, 'NMAppReturnPage', 'nm_workbench.html'), ...
                    'page', char(string(page)), ... % nm2-allow: NMAppUI writes optional NMAppCaller and return-page navigation context; page values originate at the browser-navigation boundary.
                    'fastChildOpen', NMUISessionTools.fastChildOpen(ctx));
            end
        end
    end

    methods (Static, Access = private)
        function ensureDir(d)
            if ~isempty(d) && ~exist(d,'dir'), mkdir(d); end % nm2-allow: NMUISessionTools.ensureDir inspects and creates actual filesystem session directories selected by the caller.
        end

        function p = canonicalPath(p)
            p = char(java.io.File(char(string(p))).getCanonicalPath()); % nm2-allow: NMUISessionTools.canonicalPath canonicalizes filesystem paths at the temporary-directory security boundary.
        end

        function tf = isTempPath(d)
            candidate = NMUISessionTools.canonicalPath(d);
            tempRoot = NMUISessionTools.canonicalPath(tempdir);
            if endsWith(tempRoot, filesep), tempRoot = tempRoot(1:end-1); end
            tf = strcmpi(candidate, tempRoot) || startsWith(lower(candidate), [lower(tempRoot) lower(filesep)]);
        end

        function securePrivateDir(d)
            % securePrivateDir  Restrict default temporary session roots to the owning OS user on Unix.
            if isempty(d) || exist(d,'dir') ~= 7 % nm2-allow: NMUISessionTools.securePrivateDir enforces the real filesystem existence and OS owner-permission boundary.
                error('NMUISessionTools:missingPrivateDir','Cannot secure missing NM2 session directory: %s', d);
            end
            if ~isunix, return; end
            f = java.io.File(d);
            ok = logical(f.setReadable(false,false));
            ok = logical(f.setWritable(false,false)) && ok;
            ok = logical(f.setExecutable(false,false)) && ok;
            ok = logical(f.setReadable(true,true)) && ok;
            ok = logical(f.setWritable(true,true)) && ok;
            ok = logical(f.setExecutable(true,true)) && ok;
            if ~ok
                error('NMUISessionTools:privateDirPermissions','NM2 could not restrict temporary UI session directory permissions to the owning user: %s', d);
            end
        end

        function v = ctxChar(ctx, field, default)
            v = default;
            if isstruct(ctx) && isfield(ctx, field) && ~isempty(ctx.(field)) % nm2-allow: NMUISessionTools.ctxChar reads optional NMAppUI context values from the public navigation ingress.
                v = char(string(ctx.(field))); % nm2-allow: NMUISessionTools.ctxChar reads optional NMAppUI context values from the public navigation ingress.
            end
        end
    end
end

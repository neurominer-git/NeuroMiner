classdef NMProgressTools
% NMProgressTools
% -------------------------------------------------------------------------
% Lightweight file-backed progress side channel for long browser-launched
% NeuroMiner operations.  MATLAB writes small JSON status files into the UI
% bridge temporary directory; the Python bridge serves those files directly
% so the browser can update progress while MATLAB remains busy.
% -------------------------------------------------------------------------

    methods (Static)
        function task = start(tmpDir, taskId, title, message)
            % start  Create and publish a file-backed progress task.
            %
            % Initializes a progress JSON record under the browser bridge temporary directory and writes the first status message. Empty tmpDir/taskId produces a disabled local task instead of failing the caller.
            if nargin < 1, tmpDir = ''; end
            if nargin < 2, taskId = ''; end
            if nargin < 3 || isempty(title), title = 'NeuroMiner operation'; end
            if nargin < 4 || isempty(message), message = 'Starting.'; end
            task = NMProgressTools.emptyTask();
            task.taskId = NMProgressTools.safeToken(taskId);
            task.tmpDir = NMProgressTools.asChar(tmpDir);
            if isempty(task.tmpDir) || isempty(task.taskId)
                return;
            end
            progressDir = fullfile(task.tmpDir, 'progress');
            if exist(progressDir, 'dir') ~= 7
                [ok, ~] = mkdir(progressDir);
                if ~ok, return; end
            end
            task.file = fullfile(progressDir, [task.taskId '.json']);
            task.enabled = true;
            task.title = NMProgressTools.asChar(title);
            task.phase = '';
            task.phaseStart = 0;
            task.phaseEnd = 100;
            task.minIntervalSeconds = 0.15;
            task.lastWriteDatenum = 0;
            task.indeterminate = false;
            task = NMProgressTools.write(task, 0, message, false, false, false, true);
        end

        function task = fromOptions(opts, title, message)
            % fromOptions  Construct a progress task from runtime options.
            %
            % Extracts tmpDir/taskId-style fields from an options struct and delegates to start. Runtime wrappers use this to attach progress reporting without knowing bridge internals.
            %
            % opts.progressTaskId: configures optional progress task id behavior for this call.
            % opts.ProgressTaskId: configures optional progress task id behavior for this call.
            % opts.tmpDir: sets the temporary directory for generated scripts or runtime sidecar files.
            if nargin < 1 || isempty(opts) || ~isstruct(opts), opts = struct(); end
            if nargin < 2 || isempty(title), title = 'NeuroMiner operation'; end
            if nargin < 3 || isempty(message), message = 'Starting.'; end
            tmpDir = NMProgressTools.fieldOr(opts, 'tmpDir', '');
            taskId = NMProgressTools.fieldOr(opts, 'ProgressTaskId', NMProgressTools.fieldOr(opts, 'progressTaskId', ''));
            task = NMProgressTools.start(tmpDir, taskId, title, message);
        end

        function task = setIndeterminate(task, message, phaseName)
            % setIndeterminate  Publish progress when no authoritative percentage is available.
            if nargin < 2 || isempty(message), message = 'Operation in progress.'; end
            if nargin < 3, phaseName = ''; end
            if ~NMProgressTools.isEnabled(task), return; end
            task.indeterminate = true;
            if ~isempty(phaseName), task.phase = NMProgressTools.asChar(phaseName); end
            task = NMProgressTools.write(task, task.phaseStart, message, false, false, false, true);
        end

        function task = phase(task, phaseName, phaseStart, phaseEnd, message)
            % phase  Map a named subphase into a bounded percentage interval.
            %
            % Stores phase metadata on the task so subsequent step calls can report local progress within an overall operation. The updated task is written to the JSON side channel when enabled.
            if nargin < 5, message = ''; end
            if ~NMProgressTools.isEnabled(task), return; end
            phaseStart = NMProgressTools.boundPercent(phaseStart);
            phaseEnd = NMProgressTools.boundPercent(phaseEnd);
            if phaseEnd < phaseStart
                tmp = phaseStart; phaseStart = phaseEnd; phaseEnd = tmp;
            end
            task.indeterminate = false;
            task.phase = NMProgressTools.asChar(phaseName);
            task.phaseStart = phaseStart;
            task.phaseEnd = phaseEnd;
            task = NMProgressTools.write(task, phaseStart, message, false, false, false, true);
        end

        function task = step(task, current, total, message, force)
            % step  Update progress from an integer step count within the current phase.
            %
            % Converts current/total into an overall percentage, throttles repeated writes unless forced, and publishes the updated message to the progress JSON file.
            if nargin < 4, message = ''; end
            if nargin < 5 || isempty(force), force = false; end
            if ~NMProgressTools.isEnabled(task), return; end
            current = double(current);
            total = double(total);
            if ~isfinite(current), current = 0; end
            if ~isfinite(total) || total <= 0, total = 1; end
            frac = min(1, max(0, current ./ total));
            pct = task.phaseStart + (task.phaseEnd - task.phaseStart) .* frac;
            task.indeterminate = false;
            task.current = current;
            task.total = total;
            task = NMProgressTools.write(task, pct, message, false, false, false, logical(force));
        end

        function task = update(task, percent, message)
            % update  Publish an explicit progress percentage and message.
            %
            % Writes a compact JSON status payload for enabled browser tasks. The method is a low-level writer used by start, phase, step, finish and fail.
            if nargin < 3, message = ''; end
            if ~NMProgressTools.isEnabled(task), return; end
            task.indeterminate = false;
            task = NMProgressTools.write(task, percent, message, false, false, false, false);
        end

        function task = finish(task, message)
            % finish  Mark a progress task as completed.
            %
            % Writes a final 100 percent success message to the JSON side channel and returns the updated task struct. Disabled local tasks are returned unchanged except for local fields.
            if nargin < 2 || isempty(message), message = 'Finished.'; end
            if ~NMProgressTools.isEnabled(task), return; end
            task.indeterminate = false;
            task = NMProgressTools.write(task, 100, message, true, false, false, true);
        end

        function task = fail(task, source, ME)
            % fail  Mark a progress task as failed with diagnostic context.
            %
            % Publishes a failure payload containing the source and exception message so the browser can surface errors rather than silently losing long-running task failures.
            if ~NMProgressTools.isEnabled(task), return; end
            if nargin < 2 || isempty(source), source = 'NMProgressTools'; end
            if nargin < 3 || isempty(ME)
                msg = 'Operation failed.';
                identifier = '';
            else
                identifier = NMProgressTools.asChar(ME.identifier);
                msg = NMProgressTools.asChar(ME.message);
            end
            if ~isempty(identifier)
                msg = sprintf('%s: %s', identifier, msg);
            end
            task.errorSource = NMProgressTools.asChar(source);
            task.errorMessage = msg;
            task.indeterminate = false;
            task = NMProgressTools.write(task, NaN, msg, true, true, false, true);
        end

        function tf = isEnabled(task)
            % isEnabled  Test whether a progress task has a writable bridge target.
            %
            % Returns true only when tmpDir, taskId and progress path are available. Callers use it before attempting side-channel progress writes.
            tf = isstruct(task) && isfield(task, 'enabled') && isequal(task.enabled, true) && ...
                isfield(task, 'file') && ~isempty(task.file);
        end

        function task = emptyTaskForLocalUse()
            % emptyTaskForLocalUse  Return the disabled progress-task schema for local callers.
            %
            % Provides a fixed struct for code paths that should run without browser progress reporting. This avoids dynamic struct growth in runtime helpers.
            task = NMProgressTools.emptyTask();
        end

        function publishToHTMLSource(progressFile, txt)
            % Publish the authoritative progress JSON as an uihtml supporting resource.
            tmpDir = fileparts(fileparts(progressFile));
            relayDir = fullfile(tmpDir,'html_relay');
            % nm2-allow: optional external HTMLSource directory is created by the embedded relay.
            if exist(relayDir,'dir') ~= 7, return; end
            resourceDir = fullfile(relayDir,'progress');
            % nm2-allow: the HTMLSource supporting-resource directory is external filesystem state.
            if exist(resourceDir,'dir') ~= 7
                [ok,msg] = mkdir(resourceDir);
                if ~ok
                    warning('NMProgressTools:ResourceDirectoryFailed', ...
                        'Could not create HTMLSource progress directory %s: %s',resourceDir,msg);
                    return;
                end
            end
            [~,name,ext] = fileparts(progressFile);
            resourceFile = fullfile(resourceDir,[name ext]);
            try
                fid = fopen(resourceFile,'w');
                if fid < 0
                    error('NMProgressTools:ResourceOpenFailed', ...
                        'Could not open HTMLSource resource %s.', resourceFile);
                end
                cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
                fwrite(fid,txt,'char');
                clear cleaner;
            catch ME
                warning('NMProgressTools:ResourcePublishFailed', ...
                    'HTMLSource progress resource could not be published: %s',ME.message);
            end
        end
    end

    methods (Static, Access = private)
        function task = emptyTask()
            task = struct('enabled',false,'taskId','','tmpDir','','file','', ...
                'title','','phase','','phaseStart',0,'phaseEnd',100, ...
                'current',NaN,'total',NaN,'indeterminate',false,'lastWriteDatenum',0, ...
                'minIntervalSeconds',0.15,'lastResourceWriteDatenum',0,'errorSource','','errorMessage','');
        end

        function task = write(task, percent, message, done, failed, cancelled, force)
            if ~NMProgressTools.isEnabled(task), return; end
            nowDn = now;
            elapsedSeconds = (nowDn - task.lastWriteDatenum) .* 86400;
            if ~force && isfinite(elapsedSeconds) && elapsedSeconds < task.minIntervalSeconds
                return;
            end
            if ~isfinite(percent)
                percent = task.phaseStart;
            end
            percent = NMProgressTools.boundPercent(percent);
            payload = struct();
            payload.ok = ~failed;
            payload.active = ~(done || failed || cancelled);
            payload.done = logical(done);
            payload.failed = logical(failed);
            payload.cancelled = logical(cancelled);
            payload.percent = double(percent);
            payload.indeterminate = logical(task.indeterminate);
            payload.title = task.title;
            payload.message = NMProgressTools.asChar(message);
            payload.phase = task.phase;
            payload.current = double(task.current);
            payload.total = double(task.total);
            payload.updatedAtDatenum = double(nowDn);
            payload.taskId = task.taskId;
            if failed
                payload.errorSource = task.errorSource;
                payload.errorMessage = task.errorMessage;
            end
            try
                txt = jsonencode(payload);
                % Use direct overwrite rather than an atomic replace.  On Windows,
                % frequent browser polling can temporarily hold a read handle on
                % the existing JSON file; replacing that file may block the
                % MATLAB import before it reaches the actual DataIO work.  A
                % progress file is advisory only, so a transient partial/missed
                % read is preferable to risking a stalled import.  The browser
                % polling path already ignores malformed/temporarily unavailable
                % progress payloads and retries on the next poll.
                fid = fopen(task.file, 'w');
                if fid < 0, return; end
                cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
                fwrite(fid, txt, 'char');
                clear cleanupObj;
                task.lastWriteDatenum = nowDn;
            catch
                % Progress reporting must never break the underlying import.
            end
            % Mirror at a bounded rate even if a caller forces every file write.
            if task.lastWriteDatenum == nowDn && ...
                    (done || failed || cancelled || ...
                    (nowDn-task.lastResourceWriteDatenum)*86400 >= task.minIntervalSeconds)
                NMProgressTools.publishToHTMLSource(task.file,txt);
                task.lastResourceWriteDatenum = nowDn;
            end
        end

        function pct = boundPercent(pct)
            pct = double(pct);
            if ~isfinite(pct), pct = 0; end
            pct = max(0, min(100, pct));
        end

        function tok = safeToken(x)
            tok = NMProgressTools.asChar(x);
            tok = regexprep(tok, '[^A-Za-z0-9_-]', '');
            if numel(tok) > 128, tok = tok(1:128); end
        end

        function y = asChar(x)
            if nargin < 1 || isempty(x), y = ''; return; end
            if ischar(x), y = x; return; end
            if isstring(x), y = char(x); return; end
            try
                y = char(string(x));
            catch
                y = '';
            end
        end

        function v = fieldOr(s, f, d)
            if nargin < 3, d = []; end
            v = d;
            if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
                v = s.(f);
            end
        end
    end
end

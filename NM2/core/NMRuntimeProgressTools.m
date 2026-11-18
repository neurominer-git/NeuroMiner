classdef NMRuntimeProgressTools
% NMRuntimeProgressTools
% -------------------------------------------------------------------------
% Browser-runtime progress helpers for legacy NeuroMiner runners.
%
% The class deliberately writes compact JSON payloads only.  It does not
% call browser endpoints or MATLAB graphics.  Modified legacy runtime helpers
% may call writeLegacyCV2BarChart when the global UI context declares a
% browser-backed progress task.
% -------------------------------------------------------------------------

    methods (Static)
        function ui = browserRuntimeContext(tmpDir, taskId, opts)
            % browserRuntimeContext  Build the global browser-progress context used by legacy runners.
            %
            % Creates a fixed UI context containing bridge paths, source labels and enabled state. Modified legacy runtime functions can read this context to publish progress without depending on browser classes directly.
            %
            % opts.chartEnabled: configures optional chart enabled behavior for this call.
            % opts.chartMinIntervalSeconds: configures optional chart min interval seconds behavior for this call.
            % opts.profile: configures optional profile behavior for this call.
            % opts.profileEveryN: configures optional profile every n behavior for this call.
            % opts.progressLowerTitle: configures optional progress lower title behavior for this call.
            % opts.progressTitle: configures optional progress title behavior for this call.
            % opts.source: configures optional source behavior for this call.
            % opts.suppressNativeViewer: configures optional suppress native viewer behavior for this call.
            if nargin < 1, tmpDir = ''; end
            if nargin < 2, taskId = ''; end
            if nargin < 3 || isempty(opts), opts = struct(); end
            ui = NMRuntimeProgressTools.emptyUI();
            ui.mode = 'browser';
            ui.appUI = true;
            ui.bridgeEnabled = true;
            ui.source = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(opts,'source','ml_train_runner'));
            ui.tmpDir = NMRuntimeProgressTools.asChar(tmpDir);
            ui.progressTaskId = NMRuntimeProgressTools.safeToken(taskId);
            if isempty(ui.tmpDir) || isempty(ui.progressTaskId)
                ui.enabled = false;
                return;
            end
            progressDir = fullfile(ui.tmpDir, 'progress');
            if exist(progressDir, 'dir') ~= 7
                [ok, ~] = mkdir(progressDir);
                if ~ok
                    ui.enabled = false;
                    return;
                end
            end
            ui.progressFile = fullfile(progressDir, [ui.progressTaskId '.json']);
            ui.enabled = true;
            ui.chartEnabled = logical(NMRuntimeProgressTools.fieldOr(opts,'chartEnabled',true));
            ui.consoleEnabled = logical(NMRuntimeProgressTools.fieldOr(opts,'consoleEnabled',false));
            ui.suppressNativeViewer = logical(NMRuntimeProgressTools.fieldOr(opts,'suppressNativeViewer',true));
            ui.chartMinIntervalSeconds = double(NMRuntimeProgressTools.fieldOr(opts,'chartMinIntervalSeconds',0));
            if ~isfinite(ui.chartMinIntervalSeconds) || ui.chartMinIntervalSeconds < 0
                ui.chartMinIntervalSeconds = 0;
            end
            ui.progressTitle = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(opts,'progressTitle',ui.progressTitle));
            ui.progressLowerTitle = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(opts,'progressLowerTitle',ui.progressLowerTitle));
            ui.profile = logical(NMRuntimeProgressTools.fieldOr(opts,'profile',NMRuntimeProgressTools.profileEnabled()));
            ui.profileEveryN = max(1, round(double(NMRuntimeProgressTools.fieldOr(opts,'profileEveryN',25))));
            ui.lastChartWriteDatenum = 0;
            ui.writeCount = 0;
            ui.skipCount = 0;
        end

        function ui = emptyUI()
            % emptyUI  Return the disabled runtime-progress UI context schema.
            %
            % Provides all fields expected by progress writers with safe defaults. This prevents dynamic struct growth and lets runtime code run outside the browser bridge.
            ui = struct('enabled',false,'mode','','appUI',false,'bridgeEnabled',false, ...
                'devMode',false,'source','','tmpDir','','progressTaskId','', ...
                'progressFile','','chartEnabled',false,'consoleEnabled',false,'suppressNativeViewer',true, ...
                'chartMinIntervalSeconds',0,'progressTitle','NM Training Progress Viewer', ...
                'progressLowerTitle','Optimization progress','profile',false,'profileEveryN',25, ...
                'lastChartWriteDatenum',0,'writeCount',0,'skipCount',0, ...
                'progressWriteFailureWarned',false, 'optimizerActive',false, ...
                'stageAvailable',false,'stageLabel','','stageIndex',NaN,'stageTotal',NaN, ...
                'stagePercent',NaN,'stageMessage','','stageCompleted',false);
        end

        function ui = appUIContext(enabled, opts)
            % appUIContext  Standard app-wide UI context. The global UI variable should hold.
            %
            % this structured state rather than a scalar true/false flag.
            %
            % opts.devMode: configures optional dev mode behavior for this call.
            % opts.source: configures optional source behavior for this call.
            if nargin < 1 || isempty(enabled), enabled = false; end
            if nargin < 2 || isempty(opts), opts = struct(); end
            ui = NMRuntimeProgressTools.emptyUI();
            ui.enabled = logical(enabled);
            ui.appUI = logical(enabled);
            ui.bridgeEnabled = logical(enabled);
            if ui.appUI
                ui.mode = 'browser';
                ui.source = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(opts,'source','workbench'));
            else
                ui.mode = 'cli';
                ui.source = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(opts,'source','legacy_cli'));
            end
            if isfield(opts,'devMode'), ui.devMode = logical(opts.devMode); end
        end

        function policy = legacyCV2DisplayPolicy(batchFlag)
            % legacyCV2DisplayPolicy  Centralized legacy progress-viewer branching. Modified legacy.
            %
            % helpers should call this once instead of scattering global/UI
            % checks across the optimizer code.
            global UI
            if nargin < 1, batchFlag = []; end
            isBatchRuntime = NMRuntimeProgressTools.asLogicalScalar(batchFlag, false, 'BATCH');
            isBrowserProgress = NMRuntimeProgressTools.isBrowserUI(UI) && ...
                isfield(UI,'chartEnabled') && logical(UI.chartEnabled);
            suppressNative = isBrowserProgress && isfield(UI,'suppressNativeViewer') && ...
                logical(UI.suppressNativeViewer);
            policy = struct();
            policy.batch = isBatchRuntime;
            policy.browser = isBrowserProgress;
            policy.suppressNative = suppressNative;
            policy.native = ~isBatchRuntime && ~suppressNative;
        end

        function start(ui, title, message)
            % start  Publish the beginning of a browser runtime operation.
            %
            % Writes the initial runtime progress payload through the active UI context. It is a convenience layer over the file-backed progress writer used by legacy-compatible runners.
            if nargin < 2 || isempty(title), title = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(ui,'progressTitle','NM Training Progress Viewer')); end
            if nargin < 3 || isempty(message), message = 'Preparing CV2 partition processing.'; end
            if ~NMRuntimeProgressTools.isBrowserUI(ui), return; end
            payload = NMRuntimeProgressTools.basePayload(ui, 0, title, message, true);
            payload.overall = NMRuntimeProgressTools.defaultOverallProgress(0, message);
            payload.chart = struct('kind','legacy_cv2_bar_chart','available',false, ...
                'message','Optimizer inactive for the current CV2 partition.');
            NMRuntimeProgressTools.writeJson(ui.progressFile, payload);
        end

        function ui = setStage(ui, label, current, total, completed)
            % setStage  Publish the active step of a multi-stage runtime plan.
            %
            % The stage row is orchestration metadata only. It identifies which
            % runtime action is active while CV2 and module-specific progress
            % remain authoritative in their existing payload sections.
            if nargin < 2 || isempty(label), label = 'Runtime stage'; end
            if nargin < 3 || isempty(current), current = 1; end
            if nargin < 4 || isempty(total), total = 1; end
            if nargin < 5 || isempty(completed), completed = false; end
            current = double(current);
            total = double(total);
            if ~isscalar(current) || ~isscalar(total) || ~isfinite(current) || ~isfinite(total) || ...
                    current < 1 || total < 1 || current > total || current ~= round(current) || total ~= round(total)
                error('NMRuntimeProgressTools:invalidStageCoordinate', ...
                    'Runtime stage coordinates must be finite positive integers with current <= total.');
            end
            label = NMRuntimeProgressTools.asChar(label);
            ui.stageAvailable = true;
            ui.stageLabel = label;
            ui.stageIndex = current;
            ui.stageTotal = total;
            completedStages = current - double(~logical(completed));
            ui.stagePercent = 100 .* completedStages ./ total;
            ui.stageMessage = sprintf('%s [ %d / %d steps ]', label, round(current), round(total));
            ui.stageCompleted = logical(completed);
            if ~NMRuntimeProgressTools.isBrowserUI(ui), return; end
            payload = NMRuntimeProgressTools.basePayload(ui, 0, ...
                NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(ui,'progressTitle','NM Runtime Progress Viewer')), ...
                ui.stageMessage, true);
            payload.overall = NMRuntimeProgressTools.defaultOverallProgress(0, ...
                sprintf('Waiting for CV2 progress from %s.', label));
            if logical(completed)
                chartMessage = sprintf('%s completed.', label);
                chartPercent = 100;
                chartIndeterminate = false;
            else
                chartMessage = sprintf('%s is running.', label);
                chartPercent = 0;
                chartIndeterminate = true;
            end
            payload.chart = struct('kind','generic_progress','available',true, ...
                'optimizerActive',false,'title',[label ' progress'], ...
                'message',chartMessage,'progressText',chartMessage,'parameterText','', ...
                'phase',label,'percent',chartPercent,'indeterminate',chartIndeterminate);
            NMRuntimeProgressTools.writeJson(ui.progressFile, payload);
        end

        function finish(ui, message, title)
            % finish  Publish successful completion of a browser runtime operation.
            %
            % Writes the final completion status and optional title/message through the active UI context so the browser can close or update progress displays.
            if nargin < 2 || isempty(message), message = 'Runtime finished.'; end
            if nargin < 3 || isempty(title), title = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(ui,'progressTitle','NM Runtime Progress Viewer')); end
            if ~NMRuntimeProgressTools.isBrowserUI(ui), return; end
            payload = NMRuntimeProgressTools.basePayload(ui, 100, title, message, false);
            payload.overall = NMRuntimeProgressTools.defaultOverallProgress(100, message);
            payload.done = true;
            payload.active = false;
            NMRuntimeProgressTools.writeJson(ui.progressFile, payload);
        end

        function fail(ui, source, ME)
            % fail  Publish a terminal progress state; the service result owns the exception.
            if ~NMRuntimeProgressTools.isBrowserUI(ui), return; end
            if nargin < 2 || isempty(source), source = 'ML training progress'; end
            msg = 'Runtime failed; see the parent runner for the error report.';
            payload = NMRuntimeProgressTools.basePayload(ui, NaN, source, msg, false);
            payload.ok = false;
            payload.failed = true;
            payload.active = false;
            payload.done = true;
            payload.errorSource = NMRuntimeProgressTools.asChar(source);
            payload.errorMessage = msg;
            NMRuntimeProgressTools.writeJson(ui.progressFile, payload);
        end

        function writeLegacyCV2BarChart(D, multiflag, cvpos)
            % writeLegacyCV2BarChart  Publish legacy CV2 progress as browser-readable JSON.
            %
            % Converts legacy permutation/fold progress data into the compact bar-chart payload used by the browser runtime progress panel. The method does not draw MATLAB graphics.
            global UI
            if nargin < 3, cvpos = []; end
            if ~NMRuntimeProgressTools.isBrowserUI(UI) || ~isfield(UI,'chartEnabled') || ~logical(UI.chartEnabled)
                return;
            end
            nowDn = now;
            elapsed = (nowDn - double(NMRuntimeProgressTools.fieldOr(UI,'lastChartWriteDatenum',0))) .* 86400;
            minInterval = double(NMRuntimeProgressTools.fieldOr(UI,'chartMinIntervalSeconds',0));
            if isfinite(elapsed) && elapsed < minInterval
                UI.skipCount = double(NMRuntimeProgressTools.fieldOr(UI,'skipCount',0)) + 1;
                return;
            end
            tTotal = tic;
            tBuild = tic;
            payload = NMRuntimeProgressTools.legacyChartPayload(UI, D, multiflag, nowDn, cvpos);
            buildSeconds = toc(tBuild);
            tEncode = tic;
            txt = jsonencode(payload);
            encodeSeconds = toc(tEncode);
            tWrite = tic;
            NMRuntimeProgressTools.writeText(UI.progressFile, txt);
            writeSeconds = toc(tWrite);
            totalSeconds = toc(tTotal);
            UI.lastChartWriteDatenum = nowDn;
            UI.writeCount = double(NMRuntimeProgressTools.fieldOr(UI,'writeCount',0)) + 1;
            if logical(NMRuntimeProgressTools.fieldOr(UI,'profile',false))
                everyN = max(1, round(double(NMRuntimeProgressTools.fieldOr(UI,'profileEveryN',25))));
                if UI.writeCount == 1 || mod(UI.writeCount, everyN) == 0
                    fprintf('[nm-prof] cv2-browser-progress write=%d skipped=%d build=%.4fs encode=%.4fs write=%.4fs total=%.4fs bytes=%d interval=%.3fs\n', ...
                        UI.writeCount, double(NMRuntimeProgressTools.fieldOr(UI,'skipCount',0)), ...
                        buildSeconds, encodeSeconds, writeSeconds, totalSeconds, numel(txt), minInterval);
                end
            end
        end

        function writeLegacyCV2BarChartSafe(D, multiflag, cvpos)
            % writeLegacyCV2BarChartSafe  Browser progress must not corrupt optimizer results. Failures are.
            %
            % reported once and progress emission is disabled for the current run.
            if nargin < 3, cvpos = []; end
            try
                NMRuntimeProgressTools.writeLegacyCV2BarChart(D, multiflag, cvpos);
            catch ME
                global UI
                if isstruct(UI)
                    alreadyWarned = isfield(UI,'progressWriteFailureWarned') && logical(UI.progressWriteFailureWarned);
                    UI.chartEnabled = false;
                    UI.progressWriteFailureWarned = true;
                else
                    alreadyWarned = false;
                end
                if ~alreadyWarned
                    warning('NMRuntimeProgressTools:browserProgressWriteFailed', ...
                        'Browser CV2 progress reporting was disabled after a write failure: %s', ME.message);
                end
            end
        end

        function writeLegacyModuleProgress(title, message, percent, cvpos, phase)
            % writeLegacyModuleProgress  Publish a legacy module progress update.
            %
            % Writes title, message, percentage, CV position and phase into the runtime progress side channel when a browser context is active.
            global UI
            if nargin < 1 || isempty(title)
                title = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(UI,'progressLowerTitle','Runtime progress'));
            end
            if nargin < 2 || isempty(message), message = 'Runtime operation is in progress.'; end
            if nargin < 3 || isempty(percent), percent = 0; end
            if nargin < 4, cvpos = []; end
            if nargin < 5 || isempty(phase), phase = ''; end
            if ~NMRuntimeProgressTools.isBrowserUI(UI) || ~isfield(UI,'chartEnabled') || ~logical(UI.chartEnabled)
                return;
            end
            if strcmp(UI.source,'mli_runner') && ~strcmp(title,UI.progressLowerTitle), return; end
            nowDn = now;
            elapsed = (nowDn - double(NMRuntimeProgressTools.fieldOr(UI,'lastChartWriteDatenum',0))) .* 86400;
            minInterval = double(NMRuntimeProgressTools.fieldOr(UI,'chartMinIntervalSeconds',0));
            if isfinite(elapsed) && elapsed < minInterval
                UI.skipCount = double(NMRuntimeProgressTools.fieldOr(UI,'skipCount',0)) + 1;
                return;
            end
            pct = double(percent);
            if ~isfinite(pct), pct = 0; end
            pct = max(0, min(100, pct));
            overall = NMRuntimeProgressTools.cv2OverallProgress(NMRuntimeProgressTools.asChar(message), cvpos);
            progressTitle = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(UI,'progressTitle','NM Runtime Progress Viewer'));
            payload = NMRuntimeProgressTools.basePayload(UI, double(overall.percent), progressTitle, overall.message, true);
            payload.updatedAtDatenum = double(nowDn);
            payload.overall = overall;
            chart = struct();
            chart.kind = 'legacy_module_progress';
            chart.available = true;
            chart.optimizerActive = false;
            chart.title = NMRuntimeProgressTools.asChar(title);
            chart.message = NMRuntimeProgressTools.asChar(message);
            chart.progressText = NMRuntimeProgressTools.asChar(message);
            chart.parameterText = '';
            chart.phase = NMRuntimeProgressTools.asChar(phase);
            chart.percent = pct;
            payload.chart = chart;
            NMRuntimeProgressTools.writeText(UI.progressFile, jsonencode(payload));
            UI.lastChartWriteDatenum = nowDn;
            UI.writeCount = double(NMRuntimeProgressTools.fieldOr(UI,'writeCount',0)) + 1;
        end

        function writeLegacyModuleProgressSafe(title, message, percent, cvpos, phase)
            % writeLegacyModuleProgressSafe  Publish module progress without allowing progress errors to break runtime code.
            %
            % Wraps writeLegacyModuleProgress for legacy call sites where progress reporting must be best-effort. Any failure is intentionally contained to avoid masking the real training/runtime operation.
            if nargin < 5, phase = ''; end
            try
                NMRuntimeProgressTools.writeLegacyModuleProgress(title, message, percent, cvpos, phase);
            catch ME
                global UI
                if isstruct(UI)
                    alreadyWarned = isfield(UI,'progressWriteFailureWarned') && logical(UI.progressWriteFailureWarned);
                    UI.chartEnabled = false;
                    UI.progressWriteFailureWarned = true;
                else
                    alreadyWarned = false;
                end
                if ~alreadyWarned
                    warning('NMRuntimeProgressTools:browserModuleProgressWriteFailed', ...
                        'Browser runtime progress reporting was disabled after a write failure: %s', ME.message);
                end
            end
        end

        function writeGenericProgress(title, message, percent, phase, indeterminate)
            % writeGenericProgress  Publish deterministic browser progress for non-CV2 runtime tasks.
            %
            % This method writes a generic file-backed progress payload through the active global UI context. It is used by browser tools such as the Results Viewer Report Builder where the task has a deterministic component sequence rather than legacy CV2 permutation/fold coordinates.
            global UI
            if nargin < 1 || isempty(title), title = 'Runtime progress'; end
            if nargin < 2 || isempty(message), message = 'Runtime operation is in progress.'; end
            if nargin < 3 || isempty(percent), percent = 0; end
            if nargin < 4 || isempty(phase), phase = ''; end
            if nargin < 5 || isempty(indeterminate), indeterminate = false; end
            if ~NMRuntimeProgressTools.isBrowserUI(UI) || ~isfield(UI,'chartEnabled') || ~logical(UI.chartEnabled)
                return;
            end
            pct = double(percent);
            if ~isfinite(pct), pct = 0; end
            pct = max(0, min(100, pct));
            progressTitle = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(UI,'progressTitle','NM Runtime Progress Viewer'));
            msg = NMRuntimeProgressTools.asChar(message);
            payload = NMRuntimeProgressTools.basePayload(UI, pct, progressTitle, msg, true);
            payload.phase = NMRuntimeProgressTools.asChar(phase);
            overall = NMRuntimeProgressTools.defaultOverallProgress(pct, msg);
            overall.available = true;
            overall.title = progressTitle;
            payload.overall = overall;
            chart = struct();
            chart.kind = 'generic_progress';
            chart.available = true;
            chart.optimizerActive = false;
            chart.title = NMRuntimeProgressTools.asChar(title);
            chart.message = msg;
            chart.progressText = msg;
            chart.parameterText = '';
            chart.phase = NMRuntimeProgressTools.asChar(phase);
            chart.percent = pct;
            chart.indeterminate = logical(indeterminate);
            payload.chart = chart;
            NMRuntimeProgressTools.writeText(UI.progressFile, jsonencode(payload));
            UI.lastChartWriteDatenum = now;
            UI.writeCount = double(NMRuntimeProgressTools.fieldOr(UI,'writeCount',0)) + 1;
            if logical(NMRuntimeProgressTools.fieldOr(UI,'consoleEnabled',false))
                fprintf('[nm report] %3.0f%% %s\n', pct, msg);
            end
        end

        function writeGenericProgressSafe(title, message, percent, phase, indeterminate)
            % writeGenericProgressSafe  Publish generic browser progress without masking the primary task.
            %
            % Progress reporting is advisory. If the side-channel write fails, this method disables further chart emission for the current UI context and reports one MATLAB warning instead of silently swallowing the failure.
            if nargin < 4, phase = ''; end
            if nargin < 5 || isempty(indeterminate), indeterminate = false; end
            try
                NMRuntimeProgressTools.writeGenericProgress(title, message, percent, phase, indeterminate);
            catch ME
                global UI
                if isstruct(UI)
                    alreadyWarned = isfield(UI,'progressWriteFailureWarned') && logical(UI.progressWriteFailureWarned);
                    UI.chartEnabled = false;
                    UI.progressWriteFailureWarned = true;
                else
                    alreadyWarned = false;
                end
                if ~alreadyWarned
                    warning('NMRuntimeProgressTools:browserGenericProgressWriteFailed', ...
                        'Browser generic progress reporting was disabled after a write failure: %s', ME.message);
                end
            end
        end

        function writeOOCVProgress(Results, modefl, multiflag, nsubgroups, nclass, ylm, ylb, cvpos, title, labelMode)
            % writeOOCVProgress  Publish live OOCV application progress and performance history.
            %
            % The legacy OOCV backend owns the scientific Results fields. This
            % method only serializes their already-computed progress projection
            % for the browser; it does not recompute OOCV performance.
            global UI
            if nargin < 10 || isempty(labelMode), labelMode = false; end
            if nargin < 9 || isempty(title), title = 'OOCV application progress'; end
            if nargin < 8, cvpos = []; end
            if nargin < 7, ylb = ''; end
            if nargin < 6, ylm = []; end
            if nargin < 5 || isempty(nclass), nclass = 1; end
            if nargin < 4 || isempty(nsubgroups), nsubgroups = 1; end
            if nargin < 3 || isempty(multiflag), multiflag = false; end
            if nargin < 2 || isempty(modefl), modefl = ''; end
            if nargin < 1 || isempty(Results) || ~isstruct(Results), Results = struct(); end
            if ~NMRuntimeProgressTools.isBrowserUI(UI) || ~isfield(UI,'chartEnabled') || ~logical(UI.chartEnabled)
                return;
            end
            nowDn = now;
            elapsed = (nowDn - double(NMRuntimeProgressTools.fieldOr(UI,'lastChartWriteDatenum',0))) .* 86400;
            minInterval = double(NMRuntimeProgressTools.fieldOr(UI,'chartMinIntervalSeconds',0));
            if isfinite(elapsed) && elapsed < minInterval
                UI.skipCount = double(NMRuntimeProgressTools.fieldOr(UI,'skipCount',0)) + 1;
                return;
            end
            overall = NMRuntimeProgressTools.cv2OverallProgress('Processing OOCV application data.', cvpos);
            progressTitle = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(UI,'progressTitle','NM OOCV Application Progress'));
            payload = NMRuntimeProgressTools.basePayload(UI, double(overall.percent), progressTitle, overall.message, true);
            payload.updatedAtDatenum = double(nowDn);
            payload.overall = overall;
            chart = struct();
            chart.kind = 'oocv_progress';
            chart.available = true;
            chart.title = NMRuntimeProgressTools.asChar(title);
            chart.message = overall.message;
            chart.progressText = overall.message;
            chart.phase = 'OOCV model application';
            chart.percent = double(overall.percent);
            chart.performanceAvailable = logical(labelMode);
            chart.performanceMessage = '';
            chart.mode = NMRuntimeProgressTools.asChar(modefl);
            chart.multiflag = logical(multiflag);
            chart.yLimits = NMRuntimeProgressTools.numericRow(ylm);
            chart.yLabel = NMRuntimeProgressTools.asChar(ylb);
            chart.groups = repmat(struct('name','','overall',struct('series',struct([])), ...
                'current',struct('series',struct([]))),1,0);
            if chart.performanceAvailable
                chart.groups = NMRuntimeProgressTools.oocvProgressGroups(Results, modefl, multiflag, nsubgroups, nclass);
                if isempty(chart.groups)
                    chart.performanceAvailable = false;
                    chart.performanceMessage = 'No OOCV performance series are available yet.';
                end
            else
                chart.performanceMessage = 'Prediction-only OOCV dataset: performance traces are unavailable because labels are not supplied.';
            end
            payload.chart = chart;
            NMRuntimeProgressTools.writeText(UI.progressFile, jsonencode(payload));
            UI.lastChartWriteDatenum = nowDn;
            UI.writeCount = double(NMRuntimeProgressTools.fieldOr(UI,'writeCount',0)) + 1;
        end

        function writeOOCVProgressSafe(Results, modefl, multiflag, nsubgroups, nclass, ylm, ylb, cvpos, title, labelMode)
            % writeOOCVProgressSafe  Best-effort OOCV progress publication.
            try
                NMRuntimeProgressTools.writeOOCVProgress(Results, modefl, multiflag, nsubgroups, nclass, ylm, ylb, cvpos, title, labelMode);
            catch ME
                global UI
                if isstruct(UI)
                    alreadyWarned = isfield(UI,'progressWriteFailureWarned') && logical(UI.progressWriteFailureWarned);
                    UI.chartEnabled = false;
                    UI.progressWriteFailureWarned = true;
                else
                    alreadyWarned = false;
                end
                if ~alreadyWarned
                    warning('NMRuntimeProgressTools:browserOOCVProgressWriteFailed', ...
                        'Browser OOCV progress reporting was disabled after a write failure: %s', ME.message);
                end
            end
        end

        function tf = profileEnabled()
            % profileEnabled  Check whether runtime progress profiling diagnostics are enabled.
            %
            % Reads the relevant environment/runtime flag used by progress instrumentation. It is read-only and does not start MATLAB profiling by itself.
            raw = getenv('NM_UI_PROFILE');
            tf = any(strcmpi(strtrim(raw), {'1','true','yes','on'}));
        end
    end

    methods (Static, Access = private)
        function tf = asLogicalScalar(x, defaultValue, name)
            if nargin < 2, defaultValue = false; end
            if nargin < 3, name = 'logical flag'; end
            if isempty(x)
                tf = logical(defaultValue);
                return;
            end
            if ~(islogical(x) || isnumeric(x)) || ~isscalar(x)
                error('NMRuntimeProgressTools:invalidLogicalFlag', ...
                    '%s must be empty or a scalar logical/numeric value.', name);
            end
            tf = logical(x);
        end

        function tf = isBrowserUI(ui)
            tf = isstruct(ui) && isfield(ui,'enabled') && logical(ui.enabled) && ...
                isfield(ui,'mode') && strcmpi(NMRuntimeProgressTools.asChar(ui.mode), 'browser') && ...
                isfield(ui,'progressFile') && ~isempty(ui.progressFile);
        end

        function payload = basePayload(ui, percent, title, message, active)
            if nargin < 4, message = ''; end
            if nargin < 5, active = true; end
            if ~isfinite(double(percent)), percent = 0; end
            percent = max(0, min(100, double(percent)));
            payload = struct();
            payload.ok = true;
            payload.active = logical(active);
            payload.done = ~logical(active);
            payload.failed = false;
            payload.cancelled = false;
            payload.percent = percent;
            payload.title = NMRuntimeProgressTools.asChar(title);
            payload.message = NMRuntimeProgressTools.asChar(message);
            payload.phase = 'ml_training_cv2_grid';
            payload.current = NaN;
            payload.total = NaN;
            payload.updatedAtDatenum = double(now);
            payload.taskId = NMRuntimeProgressTools.asChar(ui.progressTaskId);
            payload.source = NMRuntimeProgressTools.asChar(ui.source);
            payload.stage = NMRuntimeProgressTools.stagePayload(ui);
        end

        function stage = stagePayload(ui)
            stage = struct('available',false,'label','','current',NaN,'total',NaN, ...
                'percent',NaN,'message','','completed',false);
            if ~isstruct(ui) || ~isfield(ui,'stageAvailable') || ~logical(ui.stageAvailable)
                return;
            end
            stage.available = true;
            stage.label = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(ui,'stageLabel',''));
            stage.current = double(NMRuntimeProgressTools.fieldOr(ui,'stageIndex',NaN));
            stage.total = double(NMRuntimeProgressTools.fieldOr(ui,'stageTotal',NaN));
            stage.percent = double(NMRuntimeProgressTools.fieldOr(ui,'stagePercent',NaN));
            stage.message = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(ui,'stageMessage',''));
            stage.completed = logical(NMRuntimeProgressTools.fieldOr(ui,'stageCompleted',false));
        end

        function payload = legacyChartPayload(ui, D, multiflag, nowDn, cvpos)
            if nargin < 5, cvpos = []; end
            innerPct = double(NMRuntimeProgressTools.fieldOr(D,'pltperc',0));
            if ~isfinite(innerPct), innerPct = 0; end
            innerPct = max(0, min(100, innerPct));
            title = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(D,'binwintitle','NM Training Progress Viewer'));
            [progressText, parameterText] = NMRuntimeProgressTools.parameterText(D);
            overall = NMRuntimeProgressTools.cv2OverallProgress(progressText, cvpos);
            payload = NMRuntimeProgressTools.basePayload(ui, double(overall.percent), title, overall.message, true);
            payload.updatedAtDatenum = double(nowDn);
            payload.overall = overall;
            chart = struct();
            chart.kind = 'legacy_cv2_bar_chart';
            chart.available = true;
            chart.optimizerActive = true;
            chart.multiflag = logical(multiflag);
            chart.nclass = double(NMRuntimeProgressTools.fieldOr(D,'nclass',1));
            chart.progressText = progressText;
            chart.parameterText = parameterText;
            chart.percent = innerPct;
            chart.title = 'Optimization progress';
            chart.axes = NMRuntimeProgressTools.axisList(NMRuntimeProgressTools.fieldOr(D,'ax',{}));
            chart.multiAxes = NMRuntimeProgressTools.axisList(NMRuntimeProgressTools.fieldOr(D,'m_ax',{}));
            chart.hasMultiPanels = ~isempty(chart.multiAxes);
            payload.chart = chart;
        end

        function axesOut = axisList(ax)
            if isempty(ax), axesOut = struct([]); return; end
            if isstruct(ax)
                axc = num2cell(ax);
            elseif iscell(ax)
                axc = ax;
            else
                axesOut = struct([]); return;
            end
            template = NMRuntimeProgressTools.emptyAxis();
            axesOut = repmat(template, 1, 0);
            for i = 1:numel(axc)
                A = axc{i};
                if ~isstruct(A), continue; end
                B = template;
                B.title = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(A,'title',''));
                B.ylabel = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(A,'ylb',''));
                B.ylim = NMRuntimeProgressTools.numericRow(NMRuntimeProgressTools.fieldOr(A,'ylm',[NaN NaN]));
                B.position = NMRuntimeProgressTools.numericRow(NMRuntimeProgressTools.fieldOr(A,'position',[0 0 1 1]));
                B.values = NMRuntimeProgressTools.numericMatrix(NMRuntimeProgressTools.fieldOr(A,'val_y',[]));
                B.valueSize = double(size(B.values));
                B.errors = NMRuntimeProgressTools.numericMatrix(NMRuntimeProgressTools.fieldOr(A,'std_y',zeros(size(B.values))));
                B.errorSize = double(size(B.errors));
                B.labels = NMRuntimeProgressTools.stringCell(NMRuntimeProgressTools.fieldOr(A,'label',{}));
                B.legend = NMRuntimeProgressTools.stringCell(NMRuntimeProgressTools.fieldOr(A,'lg',{}));
                B.faceColor = NMRuntimeProgressTools.colorSpec(NMRuntimeProgressTools.fieldOr(A,'fc',''));
                axesOut(end+1) = B; %#ok<AGROW>
            end
        end

        function A = emptyAxis()
            A = struct('title','','ylabel','','ylim',[],'position',[], ...
                'values',[],'valueSize',[0 0],'errors',[],'errorSize',[0 0], ...
                'labels',{{}},'legend',{{}},'faceColor','');
        end

        function [progressText, parameterText] = parameterText(D)
            base = NMRuntimeProgressTools.asChar(NMRuntimeProgressTools.fieldOr(D,'s',''));
            progressText = base;
            parameterText = '';
            try
                Pdesc = D.Pdesc;
                P = D.P;
                if iscell(Pdesc) && ~isempty(Pdesc) && iscell(Pdesc{1}) && ~isempty(Pdesc{1}) && ...
                        iscell(P) && ~isempty(P)
                    parts = cell(1, numel(Pdesc{1}));
                    for j = 1:numel(Pdesc{1})
                        parVal = P{1}(j);
                        if iscell(parVal), parVal = parVal{1}; end
                        if isnumeric(parVal), parTxt = num2str(parVal, '%g'); else, parTxt = NMRuntimeProgressTools.asChar(parVal); end
                        parts{j} = sprintf('%s = %s', NMRuntimeProgressTools.asChar(Pdesc{1}{j}), parTxt);
                    end
                    parameterText = strjoin(parts, ', ');
                end
            catch
                progressText = base;
                parameterText = '';
            end
        end

        function overall = defaultOverallProgress(percent, message)
            if nargin < 1 || isempty(percent), percent = 0; end
            if nargin < 2 || isempty(message), message = ''; end
            percent = max(0, min(100, double(percent)));
            overall = struct('available',false, 'percent',percent, 'processed',NaN, 'total',NaN, ...
                'currentPartition','', 'currentPermutation',NaN, 'currentFold',NaN, ...
                'message',NMRuntimeProgressTools.asChar(message));
        end

        function overall = cv2OverallProgress(defaultMessage, cvpos)
            if nargin < 1, defaultMessage = ''; end
            if nargin < 2, cvpos = []; end
            overall = NMRuntimeProgressTools.defaultOverallProgress(0, defaultMessage);
            if ~isstruct(cvpos)
                return;
            end
            G = [];
            if isfield(cvpos,'GridAct') && ~isempty(cvpos.GridAct)
                G = logical(cvpos.GridAct);
            end
            % Legacy cvpos fields map to the traditional NM2 CV2 coordinate
            % [f,d]: f is the CV2 permutation counter and d the CV2 outer-fold
            % counter. Runtime traversal is f-major with d advancing fastest.
            f = NMRuntimeProgressTools.numericScalarField(cvpos, 'CV2p', NaN);
            d = NMRuntimeProgressTools.numericScalarField(cvpos, 'CV2f', NaN);
            if isempty(G)
                overall.available = false;
                if isfinite(f) && isfinite(d)
                    overall.currentPermutation = f;
                    overall.currentFold = d;
                    overall.currentPartition = sprintf('CV2: [%d,%d]', round(f), round(d));
                    overall.message = sprintf('Processing CV2 partition [%d,%d].', round(f), round(d));
                end
                return;
            end
            total = nnz(G);
            processed = 0;
            validCoordinate = isfinite(f) && isfinite(d) && f >= 1 && d >= 1 && ...
                round(f) <= size(G,1) && round(d) <= size(G,2);
            if validCoordinate
                fi = round(f);
                di = round(d);
                if G(fi,di)
                    processed = nnz(G(1:fi-1,:)) + nnz(G(fi,1:di));
                end
            end
            pct = 0;
            if total > 0 && processed > 0, pct = 100 * processed / total; end
            overall.available = total > 0;
            overall.percent = max(0, min(100, pct));
            overall.processed = processed;
            overall.total = total;
            overall.currentPermutation = f;
            overall.currentFold = d;
            if validCoordinate
                overall.currentPartition = sprintf('CV2: [%d,%d]', round(f), round(d));
                if processed > 0
                    overall.message = sprintf('Processing CV2 partition [%d,%d] (%d/%d selected partitions).', ...
                        round(f), round(d), processed, total);
                else
                    overall.message = sprintf('CV2 partition [%d,%d] is not selected (%d selected partitions).', ...
                        round(f), round(d), total);
                end
            elseif total > 0
                overall.message = sprintf('Processing selected CV2 partitions (0/%d).', total);
            end
        end

        function groups = oocvProgressGroups(Results, modefl, multiflag, nsubgroups, nclass)
            groups = repmat(struct('name','','overall',struct('series',struct([])), ...
                'current',struct('series',struct([]))),1,0);
            ng = max(1, round(double(nsubgroups)));
            nc = max(1, round(double(nclass)));
            for g = 1:ng
                S = Results;
                name = 'All cases';
                if ng > 1 && isfield(Results,'Group') && iscell(Results.Group) && numel(Results.Group) >= g && isstruct(Results.Group{g})
                    S = Results.Group{g};
                    if isfield(S,'GroupName') && ~isempty(S.GroupName), name = NMRuntimeProgressTools.asChar(S.GroupName); else, name = sprintf('Group %d', g); end
                elseif isfield(S,'GroupName') && ~isempty(S.GroupName)
                    name = NMRuntimeProgressTools.asChar(S.GroupName);
                end
                overallSeries = repmat(struct('label','','classIndex',1,'kind','','values',[]),1,0);
                currentSeries = repmat(struct('label','','classIndex',1,'kind','','values',[]),1,0);
                if strcmpi(NMRuntimeProgressTools.asChar(modefl),'classification')
                    for c = 1:nc
                        v = NMRuntimeProgressTools.matrixRowField(S,'BinCV2Performance_Targets_History',c);
                        if ~isempty(v), overallSeries(end+1) = NMRuntimeProgressTools.oocvSeries(sprintf('Class %d target',c),c,'target',v); end %#ok<AGROW>
                        v = NMRuntimeProgressTools.matrixRowField(S,'BinCV2Performance_DecisionValues_History',c);
                        if ~isempty(v), overallSeries(end+1) = NMRuntimeProgressTools.oocvSeries(sprintf('Class %d score',c),c,'score',v); end %#ok<AGROW>
                        v = NMRuntimeProgressTools.matrixRowField(S,'BinCV2Performance_Targets',c);
                        if ~isempty(v), currentSeries(end+1) = NMRuntimeProgressTools.oocvSeries(sprintf('Class %d target',c),c,'target',v); end %#ok<AGROW>
                        v = NMRuntimeProgressTools.matrixRowField(S,'BinCV2Performance_DecisionValues',c);
                        if ~isempty(v), currentSeries(end+1) = NMRuntimeProgressTools.oocvSeries(sprintf('Class %d score',c),c,'score',v); end %#ok<AGROW>
                    end
                    if logical(multiflag)
                        v = NMRuntimeProgressTools.matrixRowField(Results,'MultiCV2Performance_History',1);
                        if ~isempty(v), overallSeries(end+1) = NMRuntimeProgressTools.oocvSeries('Multiclass performance',nc+1,'multiclass',v); end %#ok<AGROW>
                        v = NMRuntimeProgressTools.matrixRowField(Results,'MultiCV2PerformanceLL',1);
                        if ~isempty(v), currentSeries(end+1) = NMRuntimeProgressTools.oocvSeries('Multiclass performance',nc+1,'multiclass',v); end %#ok<AGROW>
                    end
                else
                    v = NMRuntimeProgressTools.matrixRowField(S,'CV2Performance_PredictedValues_History',1);
                    if ~isempty(v), overallSeries(end+1) = NMRuntimeProgressTools.oocvSeries('Predictor performance',1,'score',v); end %#ok<AGROW>
                    v = NMRuntimeProgressTools.matrixRowField(S,'CV2Performance_PredictedValues',1);
                    if ~isempty(v), currentSeries(end+1) = NMRuntimeProgressTools.oocvSeries('Predictor performance',1,'score',v); end %#ok<AGROW>
                end
                if ~isempty(overallSeries) || ~isempty(currentSeries)
                    groups(end+1) = struct('name',name,'overall',struct('series',overallSeries), ...
                        'current',struct('series',currentSeries)); %#ok<AGROW>
                end
            end
        end

        function s = oocvSeries(label, classIndex, kind, values)
            s = struct('label',NMRuntimeProgressTools.asChar(label), ...
                'classIndex',double(classIndex), 'kind',NMRuntimeProgressTools.asChar(kind), ...
                'values',NMRuntimeProgressTools.numericRow(values));
        end

        function row = matrixRowField(S, fieldName, rowIndex)
            row = [];
            if ~isstruct(S) || ~isfield(S,fieldName) || isempty(S.(fieldName)), return; end
            M = NMRuntimeProgressTools.numericMatrix(S.(fieldName));
            if isempty(M), return; end
            if isvector(M)
                if rowIndex == 1, row = M(:)'; end
                return;
            end
            if rowIndex >= 1 && rowIndex <= size(M,1)
                row = M(rowIndex,:);
            end
        end

        function v = numericScalarField(s, f, d)
            v = d;
            if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
                try
                    tmp = double(s.(f));
                    if isscalar(tmp) && isfinite(tmp), v = tmp; end
                catch
                    v = d;
                end
            end
        end

        function m = numericMatrix(x)
            if isempty(x), m = []; return; end
            if iscell(x)
                try, x = cell2mat(x); catch, m = []; return; end
            end
            if ~isnumeric(x) && ~islogical(x), m = []; return; end
            m = double(x);
            m(~isfinite(m)) = NaN;
        end

        function r = numericRow(x)
            r = NMRuntimeProgressTools.numericMatrix(x);
            r = r(:)';
        end

        function c = stringCell(x)
            c = {};
            if isempty(x), return; end
            if ischar(x) || isstring(x)
                c = cellstr(string(x));
            elseif iscell(x)
                c = cell(size(x));
                for i = 1:numel(x)
                    c{i} = NMRuntimeProgressTools.asChar(x{i});
                end
                c = c(:)';
            end
        end

        function c = colorSpec(x)
            if isnumeric(x) && numel(x) >= 3
                vals = double(x(:)');
                vals = vals(1:3);
                vals(~isfinite(vals)) = 0;
                vals = max(0, min(1, vals));
                c = sprintf('rgb(%d,%d,%d)', round(vals(1)*255), round(vals(2)*255), round(vals(3)*255));
            else
                c = NMRuntimeProgressTools.asChar(x);
            end
        end

        function writeJson(path, payload)
            NMRuntimeProgressTools.writeText(path, jsonencode(payload));
        end

        function writeText(path, txt)
            try
                [folder, ~, ~] = fileparts(path);
                if isempty(folder), folder = pwd; end
                if exist(folder, 'dir') ~= 7, return; end
                % Direct overwrite is intentional. On Windows, replacing an
                % existing file while the Python bridge has a read handle can
                % fail or briefly deny the reader. A progress payload is an
                % advisory side channel; transient partial reads are retried by
                % the bridge/browser and must never interrupt the runtime.
                fid = fopen(path, 'w');
                if fid < 0, return; end
                cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
                fwrite(fid, txt, 'char');
                clear cleaner;
                NMProgressTools.publishToHTMLSource(path,txt);
            catch
                % Progress output is advisory and must not break training.
            end
        end

        function tok = safeToken(x)
            tok = NMRuntimeProgressTools.asChar(x);
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

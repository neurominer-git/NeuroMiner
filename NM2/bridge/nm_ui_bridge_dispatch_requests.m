function nHandled = nm_ui_bridge_dispatch_requests(tmpDir, matlabServiceHandler)
% nm_ui_bridge_dispatch_requests  Dispatch pending browser-bridge request files to MATLAB-side service handlers.
%
% Authority and flow
%   Dispatches ordinary synchronous bridge requests and durable matlabjob requests. Long-running
%   jobs reuse the same MATLAB service handler but publish status/result through session files so
%   their computation lifetime is not coupled to an HTTP request timeout.
%
% Materialization and performance
%   Request/status files are compact. Synchronous responses and terminal job results are encoded once
%   through the existing response-mode authority; no feature-scale polling payload is created here.
%
% Failure semantics
%   Request transport/decode failures and result publication failures remain explicit. A durable job
%   publishes failed terminal status when its MATLAB operation or result publication fails.

nHandled = 0;
if nargin < 1 || isempty(tmpDir) || ~exist(tmpDir,'dir'), return; end
if nargin < 2, matlabServiceHandler = []; end
d = dir(fullfile(tmpDir,'*_request_*.json'));

for i = 1:numel(d)
    reqPath = fullfile(tmpDir, d(i).name);
    [service, resultPath] = local_parse_request_name(tmpDir, d(i).name);
    if isempty(service), continue; end

    tRequestRead = tic;
    try
        [requestText, openError] = nm_ui_bridge_read_text(reqPath);
        if ~isempty(openError), error('nm_ui_bridge_dispatch_requests:requestUnreadable', '%s', openError); end
        req = NMConfigTools.decodeJson(requestText);
        requestReadSeconds = toc(tRequestRead);
    catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
        local_write_json(resultPath, NMUIErrorTools.exceptionStruct(ME, '', 'Reading or decoding browser-bridge request failed.'));
        local_delete_quiet(reqPath);
        nHandled = nHandled + 1;
        continue;
    end
    tDelete = tic;
    local_delete_quiet(reqPath);
    requestDeleteSeconds = toc(tDelete);
    doProfile = local_profile_enabled(req);
    profileId = local_req_char(req, 'profileId', local_req_char(req, 'id', '-'));
    tRequest = tic;
    if doProfile
        fprintf('[nm-prof rid=%s] bridge inbound pythonRead=%.3fs pythonDecode=%.3fs pythonInboundTotal=%.3fs MATLABFileReadDecode=%.3fs requestDelete=%.3fs\n', ...
            profileId, ...
            local_req_numeric(req,'_nmProfileInboundReadSeconds',0), ...
            local_req_numeric(req,'_nmProfileInboundDecodeSeconds',0), ...
            local_req_numeric(req,'_nmProfileInboundTotalSeconds',0), ...
            requestReadSeconds, requestDeleteSeconds);
    end

    if strcmpi(service, 'matlabjob')
        local_dispatch_matlabjob(req, tmpDir, matlabServiceHandler, doProfile);
        if doProfile
            fprintf('[nm-prof] bridge runtime job op=%s total=%.3fs requestBytes=%d\n', ...
                local_req_char(req,'operation',''), toc(tRequest), double(d(i).bytes));
        end
        nHandled = nHandled + 1;
        continue;
    end

    tService = tic;
    try
        switch lower(service)
            case 'pickpath'
                out = nm_ui_bridge_handle_pickpath(req);
            case 'matlabservice'
                out = local_handle_matlabservice(req, tmpDir, matlabServiceHandler);
            otherwise
                out = struct('error', sprintf('Unknown UI bridge request service: %s', service));
        end
    catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
        out = NMUIErrorTools.exceptionStruct(ME, '', sprintf('Handling UI bridge request service %s failed.', service));
    end
    serviceSeconds = toc(tService);
    tWrite = tic;
    responseMode = local_response_write_mode(service, req);
    writeProfile = local_write_json(resultPath, out, doProfile, responseMode);
    writeSeconds = toc(tWrite);
    resultBytes = 0;
    try
        info = dir(resultPath);
        if ~isempty(info), resultBytes = double(info(1).bytes); end
    catch
        resultBytes = 0;
    end
    if doProfile
        fprintf('[nm-prof rid=%s] bridge request service=%s op=%s dispatch=%.3fs write=%.3fs total=%.3fs requestBytes=%d resultBytes=%d\n', ...
            profileId, service, local_req_char(req,'operation',local_req_char(req,'action','')), serviceSeconds, writeSeconds, toc(tRequest), double(d(i).bytes), resultBytes);
        fprintf('[nm-prof rid=%s]   bridge response phases mode=%s assert=%.3fs sanitize=%.3fs encode=%.3fs fwrite=%.3fs commit=%.3fs fallback=%d\n', ...
            profileId, writeProfile.mode, ...
            writeProfile.assertSeconds, writeProfile.sanitizeSeconds, writeProfile.encodeSeconds, ...
            writeProfile.fileWriteSeconds, writeProfile.commitSeconds, double(writeProfile.fallbackUsed));
    end
    nHandled = nHandled + 1;
end
end


function local_dispatch_matlabjob(req, tmpDir, matlabServiceHandler, doProfile)
% local_dispatch_matlabjob  Execute one durable browser-submitted MATLAB runtime job.
%
% Purpose
%   Run a long MATLAB service operation after the Python bridge has already
%   acknowledged submission. Job status and the final service result are
%   published atomically to session files that the Python bridge serves
%   directly, so computation duration is independent of HTTP request lifetime.
%
% Authority and flow
%   The Python bridge owns job admission and queued state. This function owns
%   MATLAB execution plus running/final state publication. The existing
%   matlabServiceHandler remains the operation authority; durable jobs do not
%   introduce a second implementation of the requested operation.
%
% Invariants
%   - The job id is supplied explicitly by the bridge and is safe for use as
%     one session-local filename token.
%   - Status becomes running before the MATLAB operation starts.
%   - The final result is committed before terminal status advertises
%     resultAvailable=true.
%   - No wall-clock timeout is applied at this boundary.
%
% Materialization and performance
%   Status writes are compact O(1) JSON. The final result is encoded exactly
%   once using the same response-mode authority as synchronous matlabservice.
%   No scientific payload is duplicated during the running phase.
%
% Failure semantics
%   Operation failures are represented by the normal MATLAB service error
%   response and a failed terminal job state. Result/status publication errors
%   remain explicit bridge failures rather than being silently ignored.

jobId = local_req_char(req, 'jobId', '');
if isempty(jobId) || isempty(regexp(jobId, '^[A-Za-z0-9_-]+$', 'once')) %#ok<RGXP1>
    error('nm_ui_bridge_dispatch_requests:invalidRuntimeJobId', ...
        'MATLAB runtime job id must contain only letters, numbers, underscore or hyphen.');
end
operation = local_req_char(req, 'operation', '');
runId = local_req_char(req, 'runId', '');
progressTaskId = local_req_char(req, 'progressTaskId', '');
submittedAtEpoch = local_req_numeric(req, 'submittedAtEpoch', NaN);
statusPath = fullfile(tmpDir, sprintf('matlabjob_status_%s.json', jobId));
resultPath = fullfile(tmpDir, sprintf('matlabjob_result_%s.json', jobId));

running = local_runtime_job_status(jobId, runId, operation, progressTaskId, ...
    'running', true, false, false, false, submittedAtEpoch, ...
    'MATLAB runtime job is running.');
running.startedAtDatenum = double(now);

try
    local_write_json(statusPath, running, doProfile, 'guarded');
    tService = tic;
    out = local_handle_matlabservice(req, tmpDir, matlabServiceHandler);
    serviceSeconds = toc(tService);
    responseMode = local_response_write_mode('matlabservice', req);
    resultProfile = local_write_json(resultPath, out, doProfile, responseMode);
    failed = isstruct(out) && isfield(out,'ok') && ~isempty(out.ok) && ~logical(out.ok(1));
    if failed
        finalState = 'failed';
        finalMessage = local_out_message(out, sprintf('MATLAB runtime job %s failed.', operation));
    else
        finalState = 'completed';
        finalMessage = local_out_message(out, sprintf('MATLAB runtime job %s completed.', operation));
    end
    terminal = local_runtime_job_status(jobId, runId, operation, progressTaskId, ...
        finalState, false, true, failed, false, submittedAtEpoch, finalMessage);
    terminal.startedAtDatenum = running.startedAtDatenum;
    terminal.finishedAtDatenum = double(now);
    terminal.resultAvailable = true;
    local_write_json(statusPath, terminal, doProfile, 'guarded');
    if failed, fprintf(2, '%s\n', finalMessage); end
    if doProfile
        fprintf('[nm-prof]   runtime job service=%s dispatch=%.3fs resultEncode=%.3fs resultWrite=%.3fs resultCommit=%.3fs\n', ...
            operation, serviceSeconds, resultProfile.encodeSeconds, ...
            resultProfile.fileWriteSeconds, resultProfile.commitSeconds);
    end
catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
    failedOut = NMUIErrorTools.exceptionStruct(ME, '', sprintf('MATLAB runtime job %s failed.', operation));
    resultAvailable = false;
    try
        local_write_json(resultPath, failedOut, doProfile, 'guarded');
        resultAvailable = true;
    catch
        resultAvailable = false;
    end
    terminal = local_runtime_job_status(jobId, runId, operation, progressTaskId, ...
        'failed', false, true, true, false, submittedAtEpoch, failedOut.message);
    terminal.startedAtDatenum = running.startedAtDatenum;
    terminal.finishedAtDatenum = double(now);
    terminal.resultAvailable = resultAvailable;
    local_write_json(statusPath, terminal, doProfile, 'guarded');
    fprintf(2, '%s\n', failedOut.message);
end
end

function status = local_runtime_job_status(jobId, runId, operation, progressTaskId, state, active, done, failed, cancelled, submittedAtEpoch, message)
% local_runtime_job_status  Build the compact authoritative status record for one MATLAB runtime job.
status = struct();
status.ok = ~logical(failed);
status.jobId = jobId;
status.runId = runId;
status.operation = operation;
status.progressTaskId = progressTaskId;
status.state = state;
status.active = logical(active);
status.done = logical(done);
status.failed = logical(failed);
status.cancelled = logical(cancelled);
status.resultAvailable = false;
status.submittedAtEpoch = double(submittedAtEpoch);
status.message = message;
end

function value = local_req_numeric(req, field, defaultValue)
% local_req_numeric  Read one finite scalar numeric request field.
value = defaultValue;
if ~isstruct(req) || ~isfield(req,field) || isempty(req.(field)), return; end
candidate = double(req.(field));
if isscalar(candidate) && isfinite(candidate), value = candidate; end
end

function message = local_out_message(out, fallback)
% local_out_message  Read one user-facing service message without changing operation semantics.
message = fallback;
if ~isstruct(out), return; end
if isfield(out,'message') && ~isempty(out.message)
    message = char(string(out.message));
elseif isfield(out,'error') && ~isempty(out.error)
    message = char(string(out.error));
end
end

function [service, resultPath] = local_parse_request_name(tmpDir, name)
% local_parse_request_name  Parse request name options into a fixed scaffold/bridge structure.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

service = '';
resultPath = '';
tok = regexp(name, '^([A-Za-z0-9_]+)_request_([A-Za-z0-9_-]+)\.json$', 'tokens', 'once');
if isempty(tok), return; end
service = tok{1};
resultPath = fullfile(tmpDir, sprintf('%s_result_%s.json', service, tok{2}));
end


function out = local_handle_matlabservice(req, tmpDir, matlabServiceHandler)
% local_handle_matlabservice  Handle the matlabservice request inside the local bridge/scaffold workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.
%
% req.config: field consumed from req to preserve the caller's configured UI/API/scaffold state.
% req.context: field consumed from req to preserve the caller's configured UI/API/scaffold state.
% req.cv: field consumed from req to preserve the caller's configured UI/API/scaffold state.
% req.equalized: field consumed from req to preserve the caller's configured UI/API/scaffold state.

op = local_req_char(req, 'operation', '');
if isempty(op), op = local_req_char(req, 'action', ''); end
try
    if ~isempty(matlabServiceHandler)
        [handled, customOut] = matlabServiceHandler(req, tmpDir);
        if handled
            out = customOut;
            return;
        end
    end
    switch lower(op)
        case 'quit_preference_get'
            out = struct('ok',true,'skipConfirmation',logical(getpref('NeuroMiner2','SkipQuitConfirmation',false)));
        case 'quit_preference_set'
            setpref('NeuroMiner2','SkipQuitConfirmation',true);
            out = struct('ok',true);
        case 'rankfeat_import_external_file'
            if exist('NMRankFeatModule','class') ~= 8
                error('nm_ui_bridge_dispatch_requests:noRankModule', 'NMRankFeatModule is not on the MATLAB path.');
            end
            cfg = struct(); ctx = struct();
            if isfield(req,'config') && isstruct(req.config), cfg = req.config; end
            if isfield(req,'context') && isstruct(req.context), ctx = req.context; end
            if exist('NMConfigTools','class') == 8
                cfg = NMConfigTools.charifyStrings(cfg);
                ctx = NMConfigTools.charifyStrings(ctx);
            end
            mod = NMRankFeatModule();
            out = mod.importExternalRankingForUI(cfg, ctx, tmpDir);
        case 'preproc_export_matrix_scaffold'
            if exist('nm_preproc_generate_matrix_scaffold_code','file') ~= 2
                error('nm_ui_bridge_dispatch_requests:noScaffoldExporter', 'nm_preproc_generate_matrix_scaffold_code.m is not on the MATLAB path.');
            end
            cfgFile = fullfile(tmpDir, 'current_config.json');
            exportRoot = local_req_char(req, 'exportRoot', '');
            if isempty(exportRoot)
                exportRoot = local_default_matrix_export_root();
            end
            if ~exist(exportRoot, 'dir')
                mkdir(exportRoot);
            end
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            outDir = local_unique_dir(fullfile(exportRoot, ['nm_preproc_matrix_scaffold_' stamp]));
            out = nm_preproc_generate_matrix_scaffold_code(cfgFile, outDir);
            out.exportRoot = exportRoot;
        case 'interpret_expression'
            out = local_handle_interpret_expression(req);
        case 'resolve_label_expression'
            out = local_handle_resolve_label_expression(req);
        case 'cv_plot_regression_histogram'
            if exist('NMCVPartitionTools','class') ~= 8
                error('nm_ui_bridge_dispatch_requests:noCVTools', 'NMCVPartitionTools is not on the MATLAB path.');
            end
            cvState = struct();
            if isfield(req,'cv') && isstruct(req.cv), cvState = req.cv; end
            if exist('NMConfigTools','class') == 8
                cvState = NMConfigTools.charifyStrings(cvState);
            end
            eq = false;
            if isfield(req,'equalized') && ~isempty(req.equalized), eq = logical(req.equalized); end
            out = NMCVPartitionTools.plotRegressionHistogramFromState(fullfile(tmpDir,'cv_plot_context.mat'), cvState, eq);
        otherwise
            error('nm_ui_bridge_dispatch_requests:unknownOperation', 'Unknown MATLAB UI service operation: %s', op);
    end
catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
    out = NMUIErrorTools.exceptionStruct(ME, '', sprintf('MATLAB UI service operation %s failed.', op));
end
end



function out = local_handle_interpret_expression(req)
% local_handle_interpret_expression  Handle the interpret expression request inside the local bridge/scaffold workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

expr = strtrim(local_req_char(req, 'expression', ''));
kind = lower(strtrim(local_req_char(req, 'kind', 'numeric_vector')));
try
    if isempty(expr)
        if strcmp(kind,'number')
            out = struct('ok',true,'value',NaN,'message','Empty numeric expression.');
        else
            out = struct('ok',true,'value',[],'message','Empty numeric expression.');
        end
        return;
    end
    [val, msg] = NMSerializationTools.interpretNumericExpression(expr, kind);
    out = struct('ok',true,'value',val,'message',msg);
catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
    out = NMUIErrorTools.exceptionStruct(ME, '', 'Interpreting the numeric expression failed.');
end
end

function out = local_handle_resolve_label_expression(req)
% local_handle_resolve_label_expression  Resolve safe workspace text-label expressions for browser controls.
%
% It sits at the MATLAB/browser boundary and returns concrete labels so the
% browser/report state can remain explicit without re-evaluating the workspace.

expr = strtrim(local_req_char(req, 'expression', ''));
try
    if isempty(expr)
        out = struct('ok',true,'value',{{}},'message','Empty label expression.');
        return;
    end
    [labels, msg] = NMSerializationTools.interpretTextLabelsExpression(expr, 5000);
    out = struct('ok',true,'value',{labels},'message',msg);
catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
    out = NMUIErrorTools.exceptionStruct(ME, '', 'Resolving the text-label expression failed.');
end
end

function v = local_req_char(req, field, default)
% local_req_char  Perform the local req char step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

v = default;
if isstruct(req) && isfield(req, field) && ~isempty(req.(field))
    try
        v = char(req.(field));
    catch
        v = default;
    end
end
end

function root = local_default_matrix_export_root()
% local_default_matrix_export_root  Perform the local default matrix export root step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

root = fullfile(pwd, 'NM_preproc_exports');
try
    if ~exist(root, 'dir'), mkdir(root); end
catch
    up = userpath;
    if ischar(up) || isstring(up)
        up = char(up);
        if contains(up, pathsep), up = extractBefore(up, pathsep); end
        if ~isempty(up)
            root = fullfile(up, 'NM_preproc_exports');
            try
                if ~exist(root, 'dir'), mkdir(root); end
                return;
            catch
            end
        end
    end
    root = fullfile(tempdir, 'NM_preproc_exports');
    if ~exist(root, 'dir'), mkdir(root); end
end
end

function outDir = local_unique_dir(baseDir)
% local_unique_dir  Perform the local unique dir step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

outDir = baseDir;
if ~exist(outDir, 'dir'), return; end
for k = 2:999
    cand = sprintf('%s_%03d', baseDir, k);
    if ~exist(cand, 'dir')
        outDir = cand;
        return;
    end
end
outDir = [baseDir '_' char(java.util.UUID.randomUUID())];
end

function mode = local_response_write_mode(service, req)
% local_response_write_mode  Select an authoritative bridge response encoder.
%
% Results Viewer content payloads are already materialized browser contracts:
% their large numeric/row collections are the intended response rather than
% raw NM state. Re-running the generic recursive heavy-array sanitizer over
% those contracts adds seconds of traversal without improving safety. Only an
% explicit read-only Results Viewer content allowlist and the fixed-schema
% Report Builder response may use direct JSON paths; all other services retain
% the generic guarded encoder.

% The selection is derived from the MATLAB service/operation pair, never from
% a browser-provided fast-path flag. This prevents unrelated requests from
% opting themselves out of the established serialization filter.

mode = 'guarded';
if ~strcmpi(char(string(service)), 'matlabservice') || ~isstruct(req)
    return;
end
op = lower(strtrim(local_req_char(req, 'operation', local_req_char(req, 'action', ''))));
contentOps = { ...
    'results_viewer_alpha_refresh', ...
    'results_viewer_alpha_state', ...
    'results_viewer_alpha_payload', ...
    'results_viewer_alpha_fractionated_decision', ...
    'results_viewer_alpha_fractionated_clusters', ...
    'results_viewer_alpha_classification', ...
    'results_viewer_alpha_connectivity_representation', ...
    'results_viewer_alpha_vector_options', ...
    'results_viewer_alpha_subject_feature_qc', ...
    'results_viewer_alpha_action', ...
    'results_viewer_alpha_probability', ...
    'results_viewer_alpha_calibration', ...
    'results_viewer_alpha_dca'};
reportOps = {'results_viewer_report_build'};
if any(strcmp(op, contentOps))
    mode = 'results-viewer-content';
elseif any(strcmp(op, reportOps))
    mode = 'results-viewer-report';
end
end

function stats = local_write_json(path, value, doProfile, mode)
% local_write_json  Encode and atomically write one browser-bridge response.
%
% When the shared NM profiling switch is active, this helper separates raw-NM
% assertion, heavy-array sanitization, JSON encoding, file writing and atomic
% commit timings. Results Viewer content and Report Builder contracts use
% dedicated direct-JSON paths after fixed-depth raw-NM assertions. A
% contract/encoder failure is returned
% as an explicit bridge error rather than being hidden by a permissive
% transformation. Other responses preserve the established generic filtered
% encoder and its legacy bare-JSON compatibility fallback.

if nargin < 3, doProfile = false; end
if nargin < 4 || isempty(mode), mode = 'guarded'; end
stats = struct('assertSeconds',0,'sanitizeSeconds',0,'encodeSeconds',0, ...
    'fileWriteSeconds',0,'commitSeconds',0,'fallbackUsed',false, ...
    'mode',char(string(mode)));
try
    if strcmp(stats.mode, 'results-viewer-content')
        [payload, stats] = local_encode_results_viewer_content(value, stats);
    elseif strcmp(stats.mode, 'results-viewer-report')
        [payload, stats] = local_encode_results_viewer_report(value, stats);
    else
        try
            if doProfile
                [payload, stats] = local_encode_guarded_profiled(value, stats);
            else
                payload = NMConfigTools.encodeJson(value, 'bridge_result');
            end
        catch
            % Preserve the pre-C15d generic bridge compatibility behavior.
            % The Results Viewer fast path does not use this fallback.
            stats.fallbackUsed = true;
            t = tic;
            payload = jsonencode(value);
            stats.encodeSeconds = stats.encodeSeconds + toc(t);
        end
    end
catch ME % nm2-allow: NMUIErrorTools exception report preserves the stack and diagnostic in service output
    stats.fallbackUsed = true;
    stats.mode = 'error-response';
    t = tic;
    payload = jsonencode(NMUIErrorTools.exceptionStruct(ME, '', 'Encoding the MATLAB UI service response failed.'));
    stats.encodeSeconds = stats.encodeSeconds + toc(t);
end
[outDir,~,~] = fileparts(path);
if isempty(outDir), outDir = pwd; end
tmpPath = [tempname(outDir) '.json.tmp'];
fid = fopen(tmpPath,'w');
if fid < 0
    error('nm_ui_bridge_dispatch_requests:openResultFile', ...
        'Could not open browser-bridge result file for writing: %s.', tmpPath);
end
t = tic;
try
    count = fwrite(fid, payload, 'char');
    fclose(fid);
    if count ~= numel(payload)
        error('nm_ui_bridge_dispatch_requests:incompleteResultWrite', ...
            'Browser-bridge result write was incomplete (%d of %d bytes): %s.', count, numel(payload), tmpPath);
    end
    stats.fileWriteSeconds = toc(t);
catch ME
    stats.fileWriteSeconds = toc(t);
    try fclose(fid); catch, end %#ok<CTCH>
    local_delete_quiet(tmpPath);
    rethrow(ME);
end
t = tic;
local_commit_json_result(tmpPath, path);
stats.commitSeconds = toc(t);
end

function local_commit_json_result(tmpPath, path)
% local_commit_json_result  Atomically publish one browser-bridge result across transient Windows file contention.
%
% Result publication is a mandatory bridge operation.  Retry only transient
% move failures at this filesystem boundary; do not fall back to non-atomic
% copy semantics or silently continue without a published result.
maxAttempts = 20;
retryPauseSeconds = 0.05;
lastMessage = '';
for attempt = 1:maxAttempts
    [ok, message] = movefile(tmpPath, path, 'f');
    if ok, return; end
    lastMessage = char(string(message));
    if attempt < maxAttempts, pause(retryPauseSeconds); end
end
local_delete_quiet(tmpPath);
error('nm_ui_bridge_dispatch_requests:commitResultFile', ...
    'Could not atomically publish browser-bridge result after %d attempts: %s', maxAttempts, lastMessage);
end

function [payload, stats] = local_encode_results_viewer_content(value, stats)
% local_encode_results_viewer_content  Encode a validated Results Viewer contract directly.
%
% The Results Viewer service constructs fixed-schema browser payloads whose
% large arrays/tables are intentionally transferred. The raw-NM assertion is
% retained, but the generic recursive stripHeavyArrays traversal is skipped.
% A direct-encoding failure is a contract violation. It propagates to
% local_write_json, which emits the normal structured bridge error response;
% the violation is therefore visible to the browser message path and profiling
% instead of being silently transformed into a different payload.

t = tic;
local_assert_results_viewer_content(value);
stats.assertSeconds = toc(t);
t = tic;
payload = jsonencode(value);
stats.encodeSeconds = toc(t);
end

function [payload, stats] = local_encode_results_viewer_report(value, stats)
% local_encode_results_viewer_report  Encode a validated Report Builder contract directly.
%
% Report Builder responses are read-only, fixed-schema products assembled by
% NMResultsViewerReportTools.buildReport. Their large component tables and
% plot payloads are intentional browser content. Re-running stripHeavyArrays
% over those products is both semantically unnecessary and prohibitively
% expensive. This encoder preserves explicit raw-NM boundary assertions and
% lets JSON encoding failures surface through the normal bridge error path.

t = tic;
local_assert_results_viewer_report(value);
stats.assertSeconds = toc(t);
t = tic;
payload = jsonencode(value);
stats.encodeSeconds = toc(t);
end

function local_assert_results_viewer_report(value)
% local_assert_results_viewer_report  Guard authoritative Report Builder response boundaries.
%
% The guard intentionally inspects only fixed-depth report containers. It
% does not recursively traverse component row arrays, which would recreate
% the sanitizer bottleneck. Each report component and its authoritative
% payload/table containers is checked independently for direct raw-NM
% leakage before direct JSON encoding.

NMConfigTools.assertNoRawNM(value, 'bridge_result.results_viewer_report');
if ~isstruct(value) || ~isscalar(value)
    error('nm_ui_bridge_dispatch_requests:invalidResultsViewerReport', ...
        'Results Viewer report response must be a scalar struct, not %s.', class(value));
end
if (isfield(value,'ok') && ~isempty(value.ok) && ~logical(value.ok(1))) || isfield(value,'error')
    return;
end
if ~isfield(value,'report') || ~isstruct(value.report) || ~isscalar(value.report)
    error('nm_ui_bridge_dispatch_requests:invalidResultsViewerReport', ...
        'Results Viewer report response must contain one scalar report or report-summary struct.');
end
report = value.report;
NMConfigTools.assertNoRawNM(report, 'bridge_result.results_viewer_report.report');
reportKind = '';
if isfield(report,'Kind') && ~isempty(report.Kind)
    reportKind = lower(strtrim(char(string(report.Kind))));
end
isSummary = strcmp(reportKind,'nm_results_viewer_report_summary');
isFullReport = strcmp(reportKind,'nm_results_viewer_report') || ...
    (isempty(reportKind) && isfield(report,'Components'));
if ~isSummary && ~isFullReport
    error('nm_ui_bridge_dispatch_requests:invalidResultsViewerReport', ...
        'Results Viewer report response Kind must identify a report or compact report summary.');
end
reportFields = {'Context','Layout','Metadata'};
for ii = 1:numel(reportFields)
    fieldName = reportFields{ii};
    if isfield(report,fieldName) && ~isempty(report.(fieldName))
        NMConfigTools.assertNoRawNM(report.(fieldName), ...
            ['bridge_result.results_viewer_report.report.' fieldName]);
    end
end
if ~isfield(report,'Components') || isempty(report.Components)
    return;
end
if ~isstruct(report.Components)
    error('nm_ui_bridge_dispatch_requests:invalidResultsViewerReport', ...
        'Results Viewer report Components must be a struct array.');
end
if isSummary
    componentFields = {'Instance','TableNames'};
else
    componentFields = {'Payload','PlotPayload','Tables','SidecarTables','Metadata','Options','Layout','Instance'};
end
for componentIndex = 1:numel(report.Components)
    component = report.Components(componentIndex);
    componentLabel = sprintf('bridge_result.results_viewer_report.report.Components(%d)', componentIndex);
    NMConfigTools.assertNoRawNM(component, componentLabel);
    for fieldIndex = 1:numel(componentFields)
        fieldName = componentFields{fieldIndex};
        if isfield(component,fieldName) && ~isempty(component.(fieldName))
            NMConfigTools.assertNoRawNM(component.(fieldName), [componentLabel '.' fieldName]);
        end
    end
end
end

function local_assert_results_viewer_content(value)
% local_assert_results_viewer_content  Guard the shallow Results Viewer response contract.
%
% The fast path deliberately avoids a recursive transformation over thousands
% of plot rows. It still checks every authoritative container at which a raw
% NM workspace could enter the response: the response itself, state, the
% state's payload, and a standalone payload. These checks are constant-depth
% and therefore do not recreate the sanitizer bottleneck.

NMConfigTools.assertNoRawNM(value, 'bridge_result.results_viewer_content');
if ~isstruct(value) || ~isscalar(value)
    error('nm_ui_bridge_dispatch_requests:invalidResultsViewerContent', ...
        'Results Viewer bridge content must be a scalar response struct, not %s.', class(value));
end
if isfield(value,'state') && ~isempty(value.state)
    NMConfigTools.assertNoRawNM(value.state, 'bridge_result.results_viewer_content.state');
    if isstruct(value.state) && isscalar(value.state) && isfield(value.state,'payload') && ~isempty(value.state.payload)
        NMConfigTools.assertNoRawNM(value.state.payload, 'bridge_result.results_viewer_content.state.payload');
    end
end
if isfield(value,'payload') && ~isempty(value.payload)
    NMConfigTools.assertNoRawNM(value.payload, 'bridge_result.results_viewer_content.payload');
end
end

function [payload, stats] = local_encode_guarded_profiled(value, stats)
% local_encode_guarded_profiled  Run the established guarded bridge serializer with timings.

if stats.assertSeconds == 0
    t = tic;
    NMConfigTools.assertNoRawNM(value, 'bridge_result');
    stats.assertSeconds = toc(t);
end
t = tic;
filtered = NMConfigTools.stripHeavyArrays(value, 'bridge_result');
stats.sanitizeSeconds = stats.sanitizeSeconds + toc(t);
t = tic;
try
    payload = jsonencode(filtered);
catch
    stats.fallbackUsed = true;
    payload = jsonencode(NMConfigTools.jsonSafe(filtered));
end
stats.encodeSeconds = stats.encodeSeconds + toc(t);
end

function tf = local_profile_enabled(req)
% local_profile_enabled  Return the shared NM UI profiling switch for bridge requests.
%
% Reuses NM_UI_PROFILE and optional request flags without changing service behavior.
tf = false;
try
    env = getenv('NM_UI_PROFILE');
    if ~isempty(env)
        tf = any(strcmpi(strtrim(env), {'1','true','on','yes'}));
    end
catch
    tf = false;
end
try
    if nargin >= 1 && isstruct(req)
        if isfield(req,'profile')
            tf = logical(req.profile);
        elseif isfield(req,'profileEnabled')
            tf = logical(req.profileEnabled);
        elseif isfield(req,'nmProfile')
            tf = logical(req.nmProfile);
        end
    end
catch
end
end

function local_delete_quiet(fp)
% local_delete_quiet  Perform the local delete quiet step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

try
    warnState = warning('off','all');
    cleaner = onCleanup(@() warning(warnState)); %#ok<NASGU>
    if exist(fp,'file'), delete(fp); end
catch
end
end

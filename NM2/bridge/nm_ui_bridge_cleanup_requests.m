function nm_ui_bridge_cleanup_requests(tmpDir)
% nm_ui_bridge_cleanup_requests  Remove stale bridge transport/job files at UI-session boundaries.
%
% Authority and flow
%   Clears request/response files and terminal durable-job status/result files only when a bridge
%   session is being opened or closed. Runtime jobs remain untouched while the active session runs.
%
% Failure semantics
%   Cleanup is best-effort because stale transport artifacts must not prevent opening or closing a UI.

if nargin < 1 || isempty(tmpDir) || ~exist(tmpDir,'dir'), return; end
patterns = {'*_request_*.json','*_result_*.json','matlabjob_status_*.json','matlabjob_result_*.json', ...
    'htmlrelay_req_*.json','htmlrelay_req_*.json.working','htmlrelay_rsp_*.json','htmlrelay_rsp_*.json.claimed'};
for p = 1:numel(patterns)
    d = dir(fullfile(tmpDir, patterns{p}));
    for i = 1:numel(d)
        local_delete_quiet(fullfile(tmpDir, d(i).name));
    end
end
end

function local_delete_quiet(fp)
% local_delete_quiet  Perform the local delete quiet step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

try
    if exist(fp,'file'), delete(fp); end
catch
end
end

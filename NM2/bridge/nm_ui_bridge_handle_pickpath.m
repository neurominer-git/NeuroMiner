function out = nm_ui_bridge_handle_pickpath(req)
% nm_ui_bridge_handle_pickpath  Handle a browser pick-path request by invoking the native path-selection bridge.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

[paths, info] = local_pick_path(req);
out = struct('paths', {paths});
if isstruct(info)
    out.dialogBackend = info.backend;
    if isfield(info,'diagnostic') && ~isempty(info.diagnostic)
        out.diagnostic = info.diagnostic;
    end
end
end

function [paths, info] = local_pick_path(req)
% local_pick_path  Perform the local pick path step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

kind = local_get_req_str(req,'kind','file');
multiple = local_get_req_bool(req,'multiple',false);
initial = local_get_req_str(req,'initial','');
filter = local_get_req_str(req,'filter','');
titleText = local_get_req_str(req,'title','');
dialogBackend = lower(strtrim(local_get_req_str(req,'dialogBackend','auto')));
if isempty(dialogBackend) || strcmp(dialogBackend,'native')
    dialogBackend = 'auto';
end

if exist(initial,'dir')
    initialDir = initial;
elseif ~isempty(initial) && exist(fileparts(initial),'dir')
    initialDir = fileparts(initial);
else
    initialDir = pwd;
end

isDir = any(strcmpi(kind, {'dir','directory','folder'}));
isSave = any(strcmpi(kind, {'save','savefile','save_file','output'}));
[~, initialName, initialExt] = fileparts(initial); defaultName = [initialName initialExt];
if ~strcmp(dialogBackend,'matlab') && local_native_dialog_enabled()
    nativeMode = 'file';
    if isDir
        nativeMode = 'dir';
    elseif isSave
        nativeMode = 'save';
    elseif multiple
        nativeMode = 'files';
    end
    if isempty(titleText)
        titleText = 'Select file';
        if isDir
            titleText = 'Select directory';
        elseif multiple
            titleText = 'Select file(s)';
        end
    end
    try
        [paths, nativeInfo] = nm_native_path_dialog(nativeMode, ...
            'Title', titleText, 'StartDir', initialDir, 'Filter', filter, 'DefaultName', defaultName);
        info = nativeInfo;
        return;
    catch ME
        if strcmp(dialogBackend,'native_only')
            rethrow(ME);
        end
        warning('nm_ui_bridge_handle_pickpath:NativeDialogFallback', ...
            'Native path dialog failed (%s: %s). Falling back to MATLAB uigetfile/uigetdir.', ...
            ME.identifier, ME.message);
        info = struct('backend','matlab_uiget_fallback', ...
            'diagnostic',sprintf('%s: %s', ME.identifier, ME.message));
    end
else
    info = struct('backend','matlab_uiget');
end

if isDir
    drawnow;
    if isempty(titleText), titleText = 'Select directory'; end
    p = uigetdir(initialDir, titleText);
    if isequal(p,0), paths = {}; else, paths = {char(p)}; end
    return;
end

filterSpec = local_filter_spec(filter);
if isSave
    drawnow;
    if isempty(titleText), titleText = 'Save file as'; end
    if isempty(defaultName), defaultName = 'output.dat'; end
    [fn,pn] = uiputfile(filterSpec,titleText,fullfile(initialDir,defaultName));
    if isequal(fn,0), paths = {}; else, paths = {fullfile(pn,fn)}; end
    return;
end
drawnow;
if multiple
    if isempty(titleText), titleText = 'Select file(s)'; end
    [fn, pn] = uigetfile(filterSpec, titleText, initialDir, 'MultiSelect', 'on');
else
    if isempty(titleText), titleText = 'Select file'; end
    [fn, pn] = uigetfile(filterSpec, titleText, initialDir, 'MultiSelect', 'off');
end

if isequal(fn,0)
    paths = {};
elseif iscell(fn)
    paths = cellfun(@(x) fullfile(pn,x), fn, 'UniformOutput', false);
else
    paths = {fullfile(pn,fn)};
end
end

function tf = local_native_dialog_enabled()
% local_native_dialog_enabled  Perform the local native dialog enabled step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

val = getenv('NM_NATIVE_FILE_DIALOG');
if isempty(val)
    tf = true;
else
    tf = ~any(strcmpi(strtrim(val), {'0','false','off','no','matlab'}));
end
end

function v = local_get_req_str(req, name, default)
% local_get_req_str  Read a struct field with an explicit fallback while preserving caller-provided values.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

if isstruct(req) && isfield(req,name) && ~isempty(req.(name))
    v = char(req.(name));
else
    v = default;
end
end

function tf = local_get_req_bool(req, name, default)
% local_get_req_bool  Read a struct field with an explicit fallback while preserving caller-provided values.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

tf = default;
if isstruct(req) && isfield(req,name) && ~isempty(req.(name))
    val = req.(name);
    if islogical(val), tf = logical(val); return; end
    if isnumeric(val), tf = val ~= 0; return; end
    tf = any(strcmpi(char(val), {'1','true','yes','on'}));
end
end

function fs = local_filter_spec(filter)
% local_filter_spec  Perform the local filter spec step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

filter = strtrim(char(filter));
if isempty(filter)
    fs = {'*.*','All files'};
    return;
end
parts = regexp(filter,'[;,]','split');
parts = parts(~cellfun(@isempty,parts));
for i = 1:numel(parts)
    parts{i} = strtrim(parts{i});
    if ~startsWith(parts{i},'*') && startsWith(parts{i},'.')
        parts{i} = ['*' parts{i}];
    end
end
pat = strjoin(parts,';');
fs = {pat, pat; '*.*', 'All files'};
end

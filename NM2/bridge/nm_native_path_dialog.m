function [paths, info] = nm_native_path_dialog(mode, varargin)
% nm_native_path_dialog  Open a native MATLAB file/folder picker for browser-bridge requests that need trusted local path selection.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

p = inputParser;
addRequired(p, 'mode', @(x) ischar(x) || isstring(x));
addParameter(p, 'Title', 'Select path', @(x) ischar(x) || isstring(x));
addParameter(p, 'StartDir', pwd, @(x) ischar(x) || isstring(x));
addParameter(p, 'Filter', '*.*', @(x) ischar(x) || isstring(x));
addParameter(p, 'DefaultName', '', @(x) ischar(x) || isstring(x));
parse(p, mode, varargin{:});

mode = lower(strtrim(char(p.Results.mode)));
titleText = char(p.Results.Title);
startDir = char(p.Results.StartDir);
filter = char(p.Results.Filter);
defaultName = char(p.Results.DefaultName);
if isempty(startDir) || exist(startDir, 'dir') ~= 7
    startDir = pwd;
end

if any(strcmp(mode, {'dir','directory','folder'}))
    [paths, info] = local_select_folder(titleText, startDir);
elseif any(strcmp(mode, {'file','files'}))
    [paths, info] = local_select_files(titleText, startDir, filter, strcmp(mode, 'files'));
elseif any(strcmp(mode, {'save','savefile','output'}))
    [paths, info] = local_select_save_file(titleText, startDir, filter, defaultName);
else
    error('nm_native_path_dialog:BadMode', 'Unknown native path dialog mode "%s".', mode);
end
end

function [paths, info] = local_select_files(titleText, startDir, filter, multiple)
% local_select_files  Perform the local select files step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

if ispc
    [paths, info] = local_select_files_windows(titleText, startDir, filter, multiple);
elseif ismac
    [paths, info] = local_select_files_macos(titleText, startDir, multiple);
elseif isunix
    [paths, info] = local_select_files_linux(titleText, startDir, filter, multiple);
else
    error('nm_native_path_dialog:UnsupportedPlatform', 'Unsupported platform for native file dialog.');
end
end

function [paths, info] = local_select_folder(titleText, startDir)
% local_select_folder  Perform the local select folder step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

if ispc
    [paths, info] = local_select_folder_windows(titleText, startDir);
elseif ismac
    [paths, info] = local_select_folder_macos(titleText, startDir);
elseif isunix
    [paths, info] = local_select_folder_linux(titleText, startDir);
else
    error('nm_native_path_dialog:UnsupportedPlatform', 'Unsupported platform for native folder dialog.');
end
end

function [paths, info] = local_select_save_file(titleText, startDir, filter, defaultName)
% local_select_save_file  Open an operating-system save-file dialog without creating the file.
if isempty(defaultName)
    defaultName = 'output.dat';
end
if ispc
    psFile = [tempname '.ps1'];
    cleanup = onCleanup(@() local_delete_if_exists(psFile)); %#ok<NASGU>
    script = sprintf([ ...
        'Add-Type -AssemblyName System.Windows.Forms\n', ...
        'Add-Type -AssemblyName System.Drawing\n', ...
        '$owner = New-Object System.Windows.Forms.Form\n', ...
        '$owner.TopMost = $true\n', ...
        '$owner.StartPosition = ''CenterScreen''\n', ...
        '$owner.Size = New-Object System.Drawing.Size(1,1)\n', ...
        '$owner.ShowInTaskbar = $false\n', ...
        '$owner.Opacity = 0\n', ...
        '$dlg = New-Object System.Windows.Forms.SaveFileDialog\n', ...
        '$dlg.Title = "%s"\n', ...
        '$dlg.InitialDirectory = "%s"\n', ...
        '$dlg.FileName = "%s"\n', ...
        '$dlg.Filter = "%s"\n', ...
        '$dlg.OverwritePrompt = $true\n', ...
        '$dlg.RestoreDirectory = $true\n', ...
        '$owner.Show()\n', ...
        '$owner.Activate()\n', ...
        '$result = $dlg.ShowDialog($owner)\n', ...
        '$owner.Close()\n', ...
        'if ($result -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $dlg.FileName }\n'], ...
        local_escape_powershell_string(titleText), ...
        local_escape_powershell_string(startDir), ...
        local_escape_powershell_string(defaultName), ...
        local_escape_powershell_string(local_windows_filter(filter)));
    local_write_text_file(psFile, script);
    [status, out] = system(sprintf('powershell -NoProfile -ExecutionPolicy Bypass -File "%s"', psFile));
    if status ~= 0
        error('nm_native_path_dialog:PowerShellFailed', ...
            'PowerShell save dialog failed: %s', strtrim(out));
    end
    paths = local_output_to_paths(out);
    info = struct('backend','windows_powershell_savefile','cancelled',isempty(paths));
elseif ismac
    script = sprintf('POSIX path of (choose file name with prompt "%s" default location POSIX file "%s" default name "%s")', ...
        local_escape_applescript_string(titleText), ...
        local_escape_applescript_string(startDir), ...
        local_escape_applescript_string(defaultName));
    [status, out] = system(['osascript -e ' local_shell_quote(script)]);
    if status ~= 0
        if contains(lower(out),'user canceled') || contains(lower(out),'user cancelled')
            paths = {};
            info = struct('backend','macos_osascript_savefile','cancelled',true);
            return;
        end
        error('nm_native_path_dialog:OSAScriptFailed', ...
            'macOS save dialog failed: %s', strtrim(out));
    end
    paths = local_output_to_paths(out);
    info = struct('backend','macos_osascript_savefile','cancelled',isempty(paths));
elseif isunix
    initialPath = fullfile(startDir, defaultName);
    if local_has_command('zenity')
        cmd = sprintf('zenity --file-selection --save --confirm-overwrite --title=%s --filename=%s %s', ...
            local_shell_quote(titleText), local_shell_quote(initialPath), ...
            local_zenity_file_filters(filter));
        backend = 'linux_zenity_savefile';
    elseif local_has_command('kdialog')
        cmd = sprintf('kdialog --getsavefilename %s', local_shell_quote(initialPath));
        backend = 'linux_kdialog_savefile';
    elseif local_has_command('yad')
        cmd = sprintf('yad --file-selection --save --confirm-overwrite --title=%s --filename=%s', ...
            local_shell_quote(titleText), local_shell_quote(initialPath));
        backend = 'linux_yad_savefile';
    else
        error('nm_native_path_dialog:NoLinuxDialogTool', ...
            'No native Linux save dialog found.');
    end
    [status, out, errorText] = local_linux_dialog_exec(cmd);
    if local_linux_dialog_cancelled(status, out, errorText, backend)
        paths = {};
        info = struct('backend',backend,'cancelled',true);
        return;
    end
    paths = local_output_to_paths(out);
    info = struct('backend',backend,'cancelled',isempty(paths));
else
    error('nm_native_path_dialog:UnsupportedPlatform', ...
        'Unsupported platform for native save dialog.');
end
end

function [paths, info] = local_select_files_windows(titleText, startDir, filter, multiple)
% local_select_files_windows  Perform the local select files windows step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

psFile = [tempname '.ps1'];
cleanup = onCleanup(@() local_delete_if_exists(psFile));
filterText = local_windows_filter(filter);
if multiple, multiText = '$true'; else, multiText = '$false'; end
script = sprintf([ ...
    'Add-Type -AssemblyName System.Windows.Forms\n', ...
    'Add-Type -AssemblyName System.Drawing\n', ...
    '$owner = New-Object System.Windows.Forms.Form\n', ...
    '$owner.TopMost = $true\n', ...
    '$owner.StartPosition = ''CenterScreen''\n', ...
    '$owner.Size = New-Object System.Drawing.Size(1,1)\n', ...
    '$owner.ShowInTaskbar = $false\n', ...
    '$owner.Opacity = 0\n', ...
    '$dlg = New-Object System.Windows.Forms.OpenFileDialog\n', ...
    '$dlg.Title = "%s"\n', ...
    '$dlg.InitialDirectory = "%s"\n', ...
    '$dlg.Filter = "%s"\n', ...
    '$dlg.Multiselect = %s\n', ...
    '$dlg.RestoreDirectory = $true\n', ...
    '$owner.Show()\n', ...
    '$owner.Activate()\n', ...
    '$result = $dlg.ShowDialog($owner)\n', ...
    '$owner.Close()\n', ...
    'if ($result -eq [System.Windows.Forms.DialogResult]::OK) {\n', ...
    '  $dlg.FileNames | ForEach-Object { Write-Output $_ }\n', ...
    '}\n'], ...
    local_escape_powershell_string(titleText), local_escape_powershell_string(startDir), ...
    local_escape_powershell_string(filterText), multiText);
local_write_text_file(psFile, script);
cmd = sprintf('powershell -NoProfile -ExecutionPolicy Bypass -File "%s"', psFile);
[status, out] = system(cmd);
if status ~= 0
    error('nm_native_path_dialog:PowerShellFailed', 'PowerShell file dialog failed: %s', strtrim(out));
end
paths = local_output_to_paths(out);
info = struct('backend','windows_powershell_winforms','cancelled',isempty(paths));
end

function [paths, info] = local_select_folder_windows(titleText, startDir)
% local_select_folder_windows  Perform the local select folder windows step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

psFile = [tempname '.ps1'];
cleanup = onCleanup(@() local_delete_if_exists(psFile));
script = sprintf([ ...
    'Add-Type -AssemblyName System.Windows.Forms\n', ...
    'Add-Type -AssemblyName System.Drawing\n', ...
    '$owner = New-Object System.Windows.Forms.Form\n', ...
    '$owner.TopMost = $true\n', ...
    '$owner.StartPosition = ''CenterScreen''\n', ...
    '$owner.Size = New-Object System.Drawing.Size(1,1)\n', ...
    '$owner.ShowInTaskbar = $false\n', ...
    '$owner.Opacity = 0\n', ...
    '$dlg = New-Object System.Windows.Forms.FolderBrowserDialog\n', ...
    '$dlg.Description = "%s"\n', ...
    '$dlg.SelectedPath = "%s"\n', ...
    '$dlg.ShowNewFolderButton = $true\n', ...
    '$owner.Show()\n', ...
    '$owner.Activate()\n', ...
    '$result = $dlg.ShowDialog($owner)\n', ...
    '$owner.Close()\n', ...
    'if ($result -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $dlg.SelectedPath }\n'], ...
    local_escape_powershell_string(titleText), local_escape_powershell_string(startDir));
local_write_text_file(psFile, script);
cmd = sprintf('powershell -NoProfile -ExecutionPolicy Bypass -File "%s"', psFile);
[status, out] = system(cmd);
if status ~= 0
    error('nm_native_path_dialog:PowerShellFailed', 'PowerShell folder dialog failed: %s', strtrim(out));
end
paths = local_output_to_paths(out);
info = struct('backend','windows_powershell_winforms','cancelled',isempty(paths));
end

function [paths, info] = local_select_files_macos(titleText, startDir, multiple)
% local_select_files_macos  Perform the local select files macos step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

if multiple
    multiClause = ' with multiple selections allowed';
else
    multiClause = '';
end
script = sprintf([ ...
    'set chosenFiles to choose file with prompt "%s" default location POSIX file "%s"%s\n', ...
    'if class of chosenFiles is list then\n', ...
    '  repeat with f in chosenFiles\n', ...
    '    POSIX path of f\n', ...
    '  end repeat\n', ...
    'else\n', ...
    '  POSIX path of chosenFiles\n', ...
    'end if\n'], ...
    local_escape_applescript_string(titleText), local_escape_applescript_string(startDir), multiClause);
[status, out] = system(['osascript -e ' local_shell_quote(script)]);
if status ~= 0
    if contains(lower(out), 'user canceled') || contains(lower(out), 'user cancelled')
        paths = {};
        info = struct('backend','macos_osascript','cancelled',true);
        return;
    end
    error('nm_native_path_dialog:OSAScriptFailed', 'macOS file dialog failed: %s', strtrim(out));
end
paths = local_output_to_paths(out);
info = struct('backend','macos_osascript','cancelled',isempty(paths));
end

function [paths, info] = local_select_folder_macos(titleText, startDir)
% local_select_folder_macos  Perform the local select folder macos step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

script = sprintf('POSIX path of (choose folder with prompt "%s" default location POSIX file "%s")', ...
    local_escape_applescript_string(titleText), local_escape_applescript_string(startDir));
[status, out] = system(['osascript -e ' local_shell_quote(script)]);
if status ~= 0
    if contains(lower(out), 'user canceled') || contains(lower(out), 'user cancelled')
        paths = {};
        info = struct('backend','macos_osascript','cancelled',true);
        return;
    end
    error('nm_native_path_dialog:OSAScriptFailed', 'macOS folder dialog failed: %s', strtrim(out));
end
paths = local_output_to_paths(out);
info = struct('backend','macos_osascript','cancelled',isempty(paths));
end

function [paths, info] = local_select_files_linux(titleText, startDir, filter, multiple)
% local_select_files_linux  Perform the local select files linux step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

if local_has_command('zenity')
    if multiple
        multiArg = '--multiple --separator=''/''';
        % Use a sentinel unlikely to occur in a path, then split below.
        sep = '|||NMSEP|||';
        multiArg = ['--multiple --separator=' local_shell_quote(sep)];
    else
        multiArg = '';
        sep = '';
    end
    patternArgs = local_zenity_file_filters(filter);
    cmd = sprintf('zenity --file-selection %s --title=%s --filename=%s %s', ...
        multiArg, local_shell_quote(titleText), local_shell_quote([startDir filesep]), patternArgs);
    [status, out, errorText] = local_linux_dialog_exec(cmd);
    if local_linux_dialog_cancelled(status, out, errorText, 'linux_zenity')
        paths = {};
        info = struct('backend','linux_zenity','cancelled',true);
        return;
    end
    if multiple && ~isempty(sep)
        paths = regexp(strtrim(out), regexptranslate('escape', sep), 'split');
        paths = paths(~cellfun(@isempty, paths));
    else
        paths = local_output_to_paths(out);
    end
    info = struct('backend','linux_zenity','cancelled',isempty(paths));
    return;
end
if local_has_command('kdialog')
    if multiple
        cmd = sprintf('kdialog --multiple --separate-output --getopenfilename %s', local_shell_quote(startDir));
    else
        cmd = sprintf('kdialog --getopenfilename %s', local_shell_quote(startDir));
    end
    [status, out, errorText] = local_linux_dialog_exec(cmd);
    if local_linux_dialog_cancelled(status, out, errorText, 'linux_kdialog')
        paths = {};
        info = struct('backend','linux_kdialog','cancelled',true);
        return;
    end
    paths = local_output_to_paths(out);
    info = struct('backend','linux_kdialog','cancelled',isempty(paths));
    return;
end
if local_has_command('yad')
    if multiple
        multiArg = '--multiple --separator='; sep = '|||NMSEP|||';
        multiArg = [multiArg local_shell_quote(sep)];
    else
        multiArg = ''; sep = '';
    end
    cmd = sprintf('yad --file-selection %s --title=%s --filename=%s', ...
        multiArg, local_shell_quote(titleText), local_shell_quote([startDir filesep]));
    [status, out, errorText] = local_linux_dialog_exec(cmd);
    if local_linux_dialog_cancelled(status, out, errorText, 'linux_yad')
        paths = {};
        info = struct('backend','linux_yad','cancelled',true);
        return;
    end
    if multiple && ~isempty(sep)
        paths = regexp(strtrim(out), regexptranslate('escape', sep), 'split');
        paths = paths(~cellfun(@isempty, paths));
    else
        paths = local_output_to_paths(out);
    end
    info = struct('backend','linux_yad','cancelled',isempty(paths));
    return;
end
error('nm_native_path_dialog:NoLinuxDialogTool', 'No native Linux file dialog found. Install zenity, kdialog, or yad, or use MATLAB fallback/manual path entry.');
end

function [paths, info] = local_select_folder_linux(titleText, startDir)
% local_select_folder_linux  Perform the local select folder linux step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

if local_has_command('zenity')
    cmd = sprintf('zenity --file-selection --directory --title=%s --filename=%s', ...
        local_shell_quote(titleText), local_shell_quote([startDir filesep]));
    [status, out, errorText] = local_linux_dialog_exec(cmd);
    if local_linux_dialog_cancelled(status, out, errorText, 'linux_zenity')
        paths = {};
        info = struct('backend','linux_zenity','cancelled',true);
        return;
    end
    paths = local_output_to_paths(out);
    info = struct('backend','linux_zenity','cancelled',isempty(paths));
    return;
end
if local_has_command('kdialog')
    cmd = sprintf('kdialog --getexistingdirectory %s', local_shell_quote(startDir));
    [status, out, errorText] = local_linux_dialog_exec(cmd);
    if local_linux_dialog_cancelled(status, out, errorText, 'linux_kdialog')
        paths = {};
        info = struct('backend','linux_kdialog','cancelled',true);
        return;
    end
    paths = local_output_to_paths(out);
    info = struct('backend','linux_kdialog','cancelled',isempty(paths));
    return;
end
if local_has_command('yad')
    cmd = sprintf('yad --file-selection --directory --title=%s --filename=%s', ...
        local_shell_quote(titleText), local_shell_quote([startDir filesep]));
    [status, out, errorText] = local_linux_dialog_exec(cmd);
    if local_linux_dialog_cancelled(status, out, errorText, 'linux_yad')
        paths = {};
        info = struct('backend','linux_yad','cancelled',true);
        return;
    end
    paths = local_output_to_paths(out);
    info = struct('backend','linux_yad','cancelled',isempty(paths));
    return;
end
error('nm_native_path_dialog:NoLinuxDialogTool', 'No native Linux folder dialog found. Install zenity, kdialog, or yad, or use MATLAB fallback/manual path entry.');
end


function [status, out, errorText] = local_linux_dialog_exec(cmd)
% Keep diagnostic stderr separate from a successful selected-path stdout.
errorFile = [tempname '.txt'];
cleanup = onCleanup(@() local_delete_if_exists(errorFile)); %#ok<NASGU>
[status, out] = system([cmd ' 2>' local_shell_quote(errorFile)]);
errorText = fileread(errorFile);
end

function cancelled = local_linux_dialog_cancelled(status, out, errorText, backend)
% Native cancellation has exit status 1 and no diagnostic output.
if status == 0
    cancelled = false;
elseif status == 1 && isempty(strtrim(out)) && isempty(strtrim(errorText))
    cancelled = true;
else
    error('nm_native_path_dialog:LinuxDialogFailed', ...
        '%s exited with status %d: %s', backend, status, strtrim(errorText));
end
end

function tf = local_has_command(name)
% local_has_command  Perform the local has command step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

[status, ~] = system(['command -v ' local_shell_quote(name) ' >/dev/null 2>&1']);
tf = status == 0;
end

function s = local_windows_filter(filter)
% local_windows_filter  Perform the local windows filter step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

parts = local_filter_parts(filter);
if isempty(parts)
    s = 'All files (*.*)|*.*';
else
    pat = strjoin(parts, ';');
    s = sprintf('Matching files (%s)|%s|All files (*.*)|*.*', pat, pat);
end
end

function args = local_zenity_file_filters(filter)
% local_zenity_file_filters  Perform the local zenity file filters step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

parts = local_filter_parts(filter);
if isempty(parts)
    args = '';
    return;
end
pat = strjoin(parts, ' ');
args = sprintf('--file-filter=%s --file-filter=%s', ...
    local_shell_quote(['Matching files | ' pat]), local_shell_quote('All files | *'));
end

function parts = local_filter_parts(filter)
% local_filter_parts  Perform the local filter parts step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

filter = strtrim(char(filter));
if isempty(filter) || strcmp(filter, '*.*')
    parts = {};
    return;
end
parts = regexp(filter, '[;,]', 'split');
parts = parts(~cellfun(@isempty, parts));
for i = 1:numel(parts)
    parts{i} = strtrim(parts{i});
    if startsWith(parts{i}, '.')
        parts{i} = ['*' parts{i}];
    elseif ~contains(parts{i}, '*') && ~contains(parts{i}, '?')
        parts{i} = ['*.' parts{i}];
    end
end
end

function paths = local_output_to_paths(out)
% local_output_to_paths  Perform the local output to paths step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

if isempty(strtrim(out))
    paths = {};
    return;
end
paths = regexp(strtrim(out), '\r\n|\n|\r', 'split');
paths = paths(~cellfun(@isempty, paths));
end

function s = local_shell_quote(s)
% local_shell_quote  Perform the local shell quote step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

s = char(s);
if ispc
    s = ['"' strrep(s, '"', '\"') '"'];
else
    s = ['''' strrep(s, '''', '''"''"''') ''''];
end
end

function s = local_escape_powershell_string(s)
% local_escape_powershell_string  Perform the local escape powershell string step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

s = char(s);
s = strrep(s, '`', '``');
s = strrep(s, '"', '`"');
end

function s = local_escape_applescript_string(s)
% local_escape_applescript_string  Perform the local escape applescript string step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

s = char(s);
s = strrep(s, '\', '\\');
s = strrep(s, '"', '\"');
end

function local_write_text_file(fn, txt)
% local_write_text_file  Perform the local write text file step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

fid = fopen(fn, 'w');
if fid < 0
    error('nm_native_path_dialog:WriteFailed', 'Could not write temporary native dialog script: %s', fn);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', txt);
end

function local_delete_if_exists(fn)
% local_delete_if_exists  Perform the local delete if exists step used by the surrounding bridge workflow.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.

if exist(fn, 'file') == 2
    delete(fn);
end
end

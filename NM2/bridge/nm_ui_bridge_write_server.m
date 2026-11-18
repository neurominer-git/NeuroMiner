function nm_ui_bridge_write_server(path)
% nm_ui_bridge_write_server  Write the generated Python bridge server script to disk for the current UI session.
%
% It sits at the MATLAB/browser boundary and keeps local file-system or HTTP bridge behavior separate from NM data-structure mutation.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 1 || isempty(path)
    error('nm_ui_bridge_write_server:missingPath','A target Python-file path is required.');
end
parent = fileparts(path);
if ~isempty(parent) && ~exist(parent,'dir'), mkdir(parent); end
txt = nm_ui_bridge_python_template();
fid = fopen(path,'w');
if fid < 0, error('nm_ui_bridge_write_server:writeFailed','Could not write %s.', path); end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, txt, 'char');
end

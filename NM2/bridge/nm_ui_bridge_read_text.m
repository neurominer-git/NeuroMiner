function [txt, openError] = nm_ui_bridge_read_text(path)
% Read an atomically published UTF-8 transport file with bounded Windows open tolerance.
tStart = tic;
[fid, message] = fopen(path, 'r');
while fid < 0 && ~isempty(dir(path)) && toc(tStart) < 1
    pause(0.05);
    [fid, message] = fopen(path, 'r');
end
if fid < 0
    txt = '';
    openError = sprintf('Could not open %s: %s', path, message);
    return
end
txt = native2unicode(fread(fid, [1 Inf], '*uint8'), 'UTF-8');
fclose(fid);
openError = '';
end

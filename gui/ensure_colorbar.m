function [handles, cb] = ensure_colorbar(handles, ax, tagname, fieldname)
% create or reuse a colorbar for 'ax'

if isfield(handles, fieldname) 
    cb = handles.(fieldname);
    if ~ishandle(cb)
        cb = colorbar(ax);  % attaches to ax
        set(cb,'Tag',tagname);
        handles.(fieldname) = cb;
    else
        if ~strcmp(get(cb,'Visible'),'on'), set(cb,'Visible','on'); end
    end
    if get(cb,'Axes') ~= ax, set(cb,'Axes',ax); end
else
    cb = colorbar(ax);  % attaches to ax
    set(cb,'Tag',tagname);
    handles.(fieldname) = cb;
end

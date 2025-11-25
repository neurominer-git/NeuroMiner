function handles = hide_or_delete_colorbar(handles, fieldname)
if isfield(handles, fieldname) 
    try delete(handles.(fieldname)); catch, set(handles.(fieldname),'Visible','off'); end
    handles = rmfield(handles, fieldname);
else
    % fallback: find by Tag
    cb = findobj(gcf,'Type','colorbar','Tag',fieldname);
    if ~isempty(cb), try delete(cb); catch, set(cb,'Visible','off'); end, end
end
end
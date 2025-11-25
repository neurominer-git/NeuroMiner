function safe_cla(ax)
if nargin>=1 && ishghandle(ax) && strcmp(get(ax,'Type'),'axes')
    cla(ax);
end
end

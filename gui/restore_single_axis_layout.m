function handles = restore_single_axis_layout(handles, reducewidth)
% Restore axes17 to its original width and hide/delete axes17b.

if isfield(handles, 'axes17_origPos') && ~isempty(handles.axes17_origPos)
    ax1 = handles.axes17;
    oldUnits1 = get(ax1, 'Units'); set(ax1, 'Units', 'normalized');
    pos = handles.axes17_origPos;
    if reducewidth
        pos(3) = pos(3)*0.9;
    end
    set(ax1, 'Position', pos);
    set(ax1, 'Units', oldUnits1);
end

if isfield(handles, 'axes17b') && ishandle(handles.axes17b) && strcmp(get(handles.axes17b,'Type'),'axes')
    % Either hide or delete; choose one. Here: delete to avoid future cla/handle issues.
    delete(handles.axes17b);
    handles = rmfield(handles, 'axes17b');
end
end

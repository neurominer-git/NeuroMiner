function [handles, ax1, ax2] = ensure_two_axes_layout(handles)
% Shrink axes17 and create/reuse axes17b next to it (same width).

ax1 = handles.axes17;

% remember original position once
if ~isfield(handles,'axes17_origPos') || isempty(handles.axes17_origPos)
    handles.axes17_origPos = get(ax1,'Position');
end

orig = handles.axes17_origPos;  % <- ALWAYS base on original
w_new = orig(3)*0.4;         
gap   = orig(3)*0.15;          % gap
x2    = orig(1) + w_new + gap;

set(ax1,'Position',[orig(1) orig(2) w_new orig(4)]);

ax2 = [];
parent = ancestor(ax1,'uipanel'); if isempty(parent), parent = ancestor(ax1,'figure'); end
if isfield(handles,'axes17b'), ax2 = handles.axes17b; end

if isempty(ax2) || ~ishandle(ax2)
    ax2 = axes('Parent',parent,'Units','normalized',...
               'Position',[x2 orig(2) w_new orig(4)], ...
               'Tag','axes17b');
else
    set(ax2,'Units','normalized','Position',[x2 orig(2) w_new orig(4)], ...
            'Visible','on');
end

% IMPORTANT: store and persist
handles.axes17b = ax2;
handles.twoAxesMode = true;     % flag for later
guidata(handles.figure1, handles);

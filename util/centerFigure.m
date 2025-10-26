function centerFigure(fh, widthRatio, heightRatio, monitorIdx)
% centerFigure Center and resize a figure/UIFigure by user‑defined ratios
%
%   centerFigure(fh, w, h)              – primary monitor
%   centerFigure(fh, w, h, monitorIdx)  – specific monitor (1‑based)
%
%   • fh           figure handle (gcf, app.UIFigure, etc.)
%   • widthRatio   0–1 : fraction of monitor width   (e.g., 0.33  → ⅓)
%   • heightRatio  0–1 : fraction of monitor height  (e.g., 0.75  → ¾)
%   • monitorIdx   integer (row in get(0,'MonitorPositions')); defaults to 1
%
%   Example
%       f = uifigure('Name','Custom size');
%       centerFigure(f, 0.4, 0.6);           % 40 % wide × 60 % tall, centred
%
%   See also: get(0,'MonitorPositions')

    arguments
        fh                 {mustBeFigureHandle}
        widthRatio  (1,1)  {mustBeInRange(widthRatio,  0, 1, "exclusive")}
        heightRatio (1,1)  {mustBeInRange(heightRatio, 0, 1, "exclusive")}
        monitorIdx  (1,1)  {mustBeInteger, mustBePositive} = 1
    end

    %----------------------------------------------------------------------
    mp = get(0,'MonitorPositions');
    if monitorIdx > size(mp,1)
        error("centerFigure:MonitorIndex", ...
              "monitorIdx=%d exceeds number of connected monitors (%d).", ...
              monitorIdx, size(mp,1));
    end
    scr = mp(monitorIdx,:);         % [left bottom width height]

    scrW = scr(3);  scrH = scr(4);
    figW = scrW * widthRatio;
    figH = scrH * heightRatio;

    left   = scr(1) + (scrW - figW)/2;
    bottom = scr(2) + (scrH - figH)/2;

    % Apply
    set(fh, 'Units','pixels', 'Position',[left bottom figW figH]);
end

% --- local validation helpers -------------------------------------------
function mustBeFigureHandle(h)
    if ~ishandle(h) || ~strcmp(get(h,'Type'),'figure')
        error("centerFigure:NotFigureHandle","Input must be a figure handle.");
    end
end

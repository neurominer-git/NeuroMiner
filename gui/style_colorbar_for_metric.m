function style_colorbar_for_metric(cb, ystyle)
if isempty(cb) || ~ishghandle(cb), return; end
% Use metric Y scale as color scale:
try
    ax = cb.Axes;
    if ~isempty(ax) && ishghandle(ax)
        clim(ax, ystyle.YLim);
    end
catch
end
% Ticks and label
set(cb,'Ticks', ystyle.YTick, 'TickLabels', ystyle.YTickLabel);
title(cb, ystyle.PerfLabel, 'Interpreter','none');
end

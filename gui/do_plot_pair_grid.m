function do_plot_pair_grid(ax, M, levA, levB, useSurf, titlestr, labelA, labelB, ystyle)
axes(ax);
if useSurf
    [XA, YB] = meshgrid(1:numel(levA), 1:numel(levB));
    contourf(XA, YB, M); shading interp; grid on; %view(45,35);
    set(ax,'XLim',[0.5 numel(levA)+0.5],'YLim',[0.5 numel(levB)+0.5]);
else
    imagesc(ax, M); axis(ax,'tight'); axis(ax,'ij');
end
colormap(ax, parula); colorbar('peer', ax);
clim(ystyle.YLim);
ax.XTick = 1:numel(levA); ax.YTick = 1:numel(levB);
ax.XTickLabel = num2str(levA(:));
ax.YTickLabel = num2str(levB(:));
title(ax, titlestr);
xlabel(ax, labelA);
ylabel(ax, labelB);

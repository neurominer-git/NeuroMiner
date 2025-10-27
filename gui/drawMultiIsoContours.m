function hBkg = drawMultiIsoContours(S, ax, view, sliceIdx, maxLevels, lineColor, lineWidth)
% DRAWMULTIISOCONTOURS  Draw up to maxLevels iso‐contours at all histogram minima
    if nargin<5, maxLevels=5; end
    if nargin<6, lineColor='w'; end
    if nargin<7, lineWidth=0.3; end

    % 1) extract slice in correct orientation
    switch view
      case 'axial'
        A = squeeze(S(:,:,sliceIdx));
      case 'sagittal'
        tmp = squeeze(S(sliceIdx,:,:))';  A = flipud(tmp);
      case 'coronal'
        tmp = squeeze(S(:,sliceIdx,:))';  A = flipud(tmp);
      otherwise
        error('Unknown view "%s"',view);
    end

    % 2) flatten & histogram
    vals = A(:);
    edges = linspace(min(vals), max(vals), 300);
    h     = histcounts(vals, edges);
    % smooth the histogram lightly
    w  = ones(1,7)/7;
    hs = conv(h,w,'same');

    % 3) find *all* local minima
    idxMin = find( ...
       hs(2:end-1)<hs(1:end-2) & ...
       hs(2:end-1)<hs(3:end) ) + 1;
    if isempty(idxMin), return; end

    % 4) sort them by depth and pick the top maxLevels
    depths = hs(idxMin);
    [~,ord]=sort(depths,'ascend');
    sel   = idxMin(ord(1:min(maxLevels,numel(ord))));
    levels= sort(edges(sel));

    % 5) draw each contour
    hold(ax,'on');
    for L = levels
      [~, hBkg] = contour(ax, A, [L L], 'Color',lineColor, 'LineWidth',lineWidth);
    end
    hold(ax,'off');
end
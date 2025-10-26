function hBkg = drawTissueIsoContours(S, ax, view, sliceIdx, nBins, lineColor, lineWidth)
%DRAWTISSUEISOCONTOURS  Overlay CSF/GM & GM/WM iso‐contours on a slice
%
%   drawTissueIsoContours(S, ax, view, sliceIdx, nBins, lineColor, lineWidth)
%
% Inputs:
%   S         - 3D structural volume (numeric array)
%   ax        - handle of the axes to draw into
%   view      - 'axial' | 'sagittal' | 'coronal'
%   sliceIdx  - slice index in structural space
%   nBins     - (optional) # histogram bins (default=200)
%   lineColor - (optional) color for contours (default='w')
%   lineWidth - (optional) line width (default=0.5)
%
% This computes the two deepest minima in a smoothed histogram of S
% (i.e. the two “valleys” between CSF↔GM and GM↔WM) and then draws
% continuous contour lines at those levels.

    if nargin<5 || isempty(nBins),     nBins = 200;   end
    if nargin<6 || isempty(lineColor), lineColor = 'w'; end
    if nargin<7 || isempty(lineWidth), lineWidth = 0.5;end

    %% 1) Compute global histogram & smooth it
    vals = S(:);
    mn   = min(vals);  mx = max(vals);
    edges = linspace(mn,mx,nBins+1);
    h     = histcounts(vals,edges);
    % simple moving‐average smooth
    k = 6;                                % smoothing window
    w = ones(1,k)/k;
    hsm = conv(h,w,'same');

    %% 2) Find local minima in the smoothed histogram
    idxMin = find(...
      hsm(2:end-1)<hsm(1:end-2) & ...
      hsm(2:end-1)<hsm(3:end) ) + 1;
    if numel(idxMin)<2
      warning('Couldn''t find two histogram valleys; skipping iso-contours.');
      return;
    end
    % pick the two deepest minima
    [~, order] = sort(hsm(idxMin), 'ascend');
    sel        = idxMin(order(1:2));
    valleys    = sort(edges(sel));  % two intensity levels

    %% 3) Extract & orient the slice
    switch lower(view)
      case 'axial'
        A = squeeze(S(:,:,sliceIdx));
      case 'sagittal'
        tmp = squeeze(S(sliceIdx,:,:))';
        A   = flipud(tmp);
      case 'coronal'
        tmp = squeeze(S(:,sliceIdx,:))';
        A   = flipud(tmp);
      otherwise
        error('Unknown view ''%s''',view);
    end

    %% 4) Overlay contours
    hold(ax,'on');
    [~,hBkg] = contour(ax, A, valleys, ...
        'LineColor', lineColor, ...
        'LineWidth', lineWidth);
    hold(ax,'off');
end

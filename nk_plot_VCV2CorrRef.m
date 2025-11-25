function nk_plot_VCV2CorrRef(VCV2WCORRREF, h, VERBOSE, figTitle)
% nk_plot_VCV2CorrRef  Show/update CV2 correlation matrix and per-ref contributions.
% Usage:
%   nk_plot_VCV2CorrRef(I2.VCV2WCORRREF, h, VERBOSE)
%   nk_plot_VCV2CorrRef(I2.VCV2CORRREF,  h, VERBOSE)   % if you use that name
%
% Inputs
%   VCV2WCORRREF : cell {h} -> either [nRef x nFolds] matrix (early fusion)
%                                or 1×nM cell of [nRef x nFolds] (intermediate)
%   h            : dichotomizer index (1-based)
%   VERBOSE      : logical; if false, function returns immediately
%   figTitle     : optional custom title string
%
% Behavior
%   - Left: imagesc of correlation per ref×fold (NaNs shown as gaps)
%   - Right: line plot of #folds with finite correlation per ref
%   - If the figure already exists (by Tag), only the data are updated.

    if nargin < 3 || isempty(VERBOSE) || ~VERBOSE, return; end
    if nargin < 2 || isempty(h), h = 1; end

    % -------- fetch matrix for dichotomizer h --------
    if isempty(VCV2WCORRREF) || numel(VCV2WCORRREF) < h || isempty(VCV2WCORRREF{h})
        return
    end
    Mh = VCV2WCORRREF{h};

    % Allow both early and intermediate fusion containers
    if iscell(Mh)
        % average across modalities (NaN-safe)
        M = local_nanmean_across_mod(Mh);
    else
        M = Mh;
    end
    if isempty(M), return; end

    % Sanity to double; keep NaNs
    M = double(M);

    % Contributions = number of CV2 folds with finite corr per ref row
    contrib = sum(isfinite(M), 2)*100./size(M,2);           % [nRef x 1]
    meancorr = nm_nanmean(M,2);
    nRef    = size(M,1);
    xref    = 1:nRef;

    % -------- create or reuse figure --------
    figTag = sprintf('NM_VCV2CorrRef_h%d', h);
    fig    = findobj(0, 'Type','figure', 'Tag', figTag);

    if isempty(fig) || ~ishandle(fig)
        % Create new figure
        figName = sprintf('VCV2WCORRREF — dichotomizer h=%d', h);
        if nargin >= 4 && ~isempty(figTitle), figName = figTitle; end

        fig = figure('Name', figName, 'Tag', figTag);
        t = tiledlayout(fig, 1, 2, 'TileSpacing','compact', 'Padding','compact');

        % --- Left: correlation image ---
        ax1 = nexttile(t, 1);
        img = imagesc(ax1, M);
        set(img, 'Tag', 'imgCorr');
        axis(ax1, 'ij');
        colormap(ax1, parula);
        cb = colorbar(ax1); 
        xlabel(ax1, '# Models (so far)');
        ylabel(ax1, 'Ref component');
        title(ax1, 'Correlation per ref × fold (auto-correlations removed)');
        clim(ax1, [0 1]); % correlations are [0..1] after abs/pearson; adjust if needed
        ylim([0.5 nRef+0.5])
        % --- Right: contributions and mean correlation line ---
        ax2 = nexttile(t, 2);
        yyaxis left
        ln  = plot(ax2, xref, contrib, 'o-', 'LineWidth', 1.25, 'MarkerSize', 4);
        set(ln, 'Tag', 'lineContrib');
        grid(ax2, 'on');
        xlabel(ax2, 'Ref component');
        ylabel(ax2, 'Contributing to models [%]');
        yyaxis right
        lo  = plot(ax2, xref, meancorr, 'x-', 'LineWidth', 1.25, 'MarkerSize', 4, 'Color', 'g');
        set(lo, 'Tag', 'lineCorr');
        ylabel(ax2, 'Mean correlation [%]');
        title(ax2, 'Contributions & Correlations per ref');
        ax2.YAxis(1).Color = ln.Color;
        ax2.YAxis(2).Color = lo.Color;
    else
        % Reuse and update
        img = findobj(fig, 'Type','image', 'Tag','imgCorr');
        ln  = findobj(fig, 'Type','line',  'Tag','lineContrib');
        lo  = findobj(fig, 'Type','line',  'Tag','lineCorr');
        % Update image
        if ~isempty(img) && isgraphics(img, 'image')
            set(img, 'CData', M);
            ax_img = ancestor(img, 'axes');
            if ~isempty(ax_img) && isgraphics(ax_img, 'axes')
                clim(ax_img, [0 1]); % keep scale stable; adjust if your S range differs
            end
            xlim(ax_img,[1 size(M,2)]);
            ylim(ax_img,[0.5 nRef+0.5]);
        end

        % Update contributions & mean correlations
        if ~isempty(ln) && ~isempty(lo) && isgraphics(ln, 'line')  && isgraphics(lo, 'line')
            set(ln, 'XData', xref, 'YData', contrib);
            set(lo, 'XData', xref, 'YData', meancorr);
            ax_ln = ancestor(ln, 'axes');
            if ~isempty(ax_ln) && isgraphics(ax_ln, 'axes')
                ax_ln.XLim=ax_img.YLim;
            end
        end
        % Optional: update figure name
        if nargin >= 4 && ~isempty(figTitle)
            set(fig, 'Name', figTitle);
        end
    end
    drawnow;
end

% ---------- helpers ----------
function M = local_nanmean_across_mod(Mcells)
% Average matrices (nRef x nFolds) across modalities, NaN-safe.
    valid = ~cellfun(@isempty, Mcells);
    Mcells = Mcells(valid);
    if isempty(Mcells)
        M = [];
        return
    end
    M = Mcells{1};
    for k = 2:numel(Mcells)
        Mk = Mcells{k};
        if isempty(Mk), continue; end
        % pad to common size if needed
        r = max(size(M,1), size(Mk,1));
        c = max(size(M,2), size(Mk,2));
        Mpad  = nan(r,c); Mpad(1:size(M,1),  1:size(M,2))  = M;
        Mkpad = nan(r,c); Mkpad(1:size(Mk,1),1:size(Mk,2)) = Mk;
        % NaN-safe mean of the two
        M = local_nanmean_pair(Mpad, Mkpad);
    end
end

function C = local_nanmean_pair(A, B)
% NaN-safe mean of two same-sized matrices (faster than cat+nanmean for 2 inputs)
    C = A;                       % start with A
    maskA = ~isnan(A); maskB = ~isnan(B);
    both  = maskA & maskB;
    onlyB = ~maskA & maskB;

    C(both)  = 0.5*(A(both) + B(both));
    C(onlyB) = B(onlyB);
    % where only A is valid, C already has A
end

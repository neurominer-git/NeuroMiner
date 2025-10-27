function rfe_plot_wrapper_trace(Hist, AD, varargin)
% Backward-compatible trace plotter: safely adds any missing plot objects
% to existing figures created by older versions (no focus stealing).

% -------- args --------
p = inputParser;
p.addParameter('FigureName','NM Wrapper Trace', @(s)ischar(s) || isstring(s));
p.addParameter('SimToLast', [], @(x)isnumeric(x));
p.addParameter('Position', [], @(x)isnumeric(x) && numel(x)==4);
p.parse(varargin{:});
figName = char(p.Results.FigureName);
s_last  = p.Results.SimToLast;
pos     = p.Results.Position;

figTag     = 'AdapWrapTracer';
handlesKey = 'TraceHandles';

% -------- find or create figure (no figure(...) to avoid focus) --------
hFig = findobj(0, 'Type','figure', 'Tag', figTag);
if isempty(hFig) || ~ishandle(hFig(1))
    % fresh figure
    if isempty(pos)
        hFig = figure('Name',figName,'Tag',figTag, 'NumberTitle','off','Color','w', ...
                      'Position',[60 60 1200 750], 'Visible','on');
    else
        hFig = figure('Name',figName,'Tag',figTag, 'NumberTitle','off','Color','w', ...
                      'Position',pos, 'Visible','on');
    end
    t = tiledlayout(hFig,2,2,'Padding','compact','TileSpacing','compact');

    ax1 = nexttile(t,1); hold(ax1,'on'); grid(ax1,'on'); box(ax1,'off');
    l_obj  = plot(ax1, NaN, NaN, 'LineWidth',2, 'DisplayName','best objective');
    l_gain = plot(ax1, NaN, NaN, 'LineWidth',1.5, 'LineStyle',':', 'DisplayName','cum. gain'); % NEW
    yyaxis(ax1,'right');
    l_nsel = plot(ax1, NaN, NaN, 'LineWidth',1.8, 'LineStyle','--', 'DisplayName','#features');
    yyaxis(ax1,'left'); ylabel(ax1,'objective / gain'); yyaxis(ax1,'right'); ylabel(ax1,'#features');
    xlabel(ax1,'accept step'); title(ax1,'Best objective and #selected'); legend(ax1,'Location','best');
    l_stop1 = plot(ax1, [NaN NaN], [NaN NaN], 'r--', 'DisplayName','stop'); % NEW

    ax2 = nexttile(t,2); hold(ax2,'on'); grid(ax2,'on'); box(ax2,'off');
    l_lam = plot(ax2, NaN, NaN, 'LineWidth',2, 'DisplayName','\lambda_{eff}');
    yyaxis(ax2,'right');
    l_mpr = plot(ax2, NaN, NaN, 'LineWidth',1.8, 'DisplayName','max m''');
    l_tau = plot(ax2, NaN, NaN, 'LineWidth',1.5, 'LineStyle','--', 'DisplayName','\tau');
    ylabel(ax2,'max m'' / \tau'); yyaxis(ax2,'left'); ylabel(ax2,'\lambda_{eff}');
    xlabel(ax2,'accept step'); title(ax2,'Penalty and natural stop signals'); legend(ax2,'Location','best');
    l_stop2 = plot(ax2, [NaN NaN], [NaN NaN], 'r--', 'HandleVisibility','off'); % NEW

    ax3 = nexttile(t,3); hold(ax3,'on'); grid(ax3,'on'); box(ax3,'off');
    l_phi  = plot(ax3, NaN, NaN, 'LineWidth',2, 'DisplayName','\phi(s)');
    l_cL   = plot(ax3, [NaN NaN], [NaN NaN], 'k--', 'HandleVisibility','off');
    l_cR   = plot(ax3, [NaN NaN], [NaN NaN], 'k--', 'HandleVisibility','off');
    l_dens = plot(ax3, NaN, NaN, 'LineWidth',1.5, 'LineStyle',':', 'DisplayName','sim density (scaled)');
    xlabel(ax3,'similarity s'); ylabel(ax3,'\phi(s)'); title(ax3,'Penalty and similarity density'); legend(ax3,'Location','best');

    ax4 = nexttile(t,4);
    im_rv = imagesc(ax4, NaN); axis(ax4,'tight'); colorbar(ax4); set(ax4,'YDir','normal');
    hold(ax4,'on');  
    sc_sel = scatter(ax4, NaN, NaN, 12, 'w', 'filled', 'MarkerEdgeColor','k', 'LineWidth',0.25);
    title(ax4,'r-vector snapshots'); xlabel(ax4,'snapshot (accept step)'); ylabel(ax4,'feature index');
    title(ax4,'r-vector snapshots'); xlabel(ax4,'snapshot (accept step)'); ylabel(ax4,'feature index');


    H = struct('t',t,'ax1',ax1,'ax2',ax2,'ax3',ax3,'ax4',ax4, ...
               'l_obj',l_obj,'l_gain',l_gain,'l_nsel',l_nsel, ...
               'l_lam',l_lam,'l_mpr',l_mpr,'l_tau',l_tau, ...
               'l_phi',l_phi,'l_cL',l_cL,'l_cR',l_cR,'l_dens',l_dens, ...
               'l_stop1',l_stop1,'l_stop2',l_stop2,'im_rv',im_rv, 'sc_sel',sc_sel);
    setappdata(hFig, handlesKey, H);
else
    hFig = hFig(1);
    H = getappdata(hFig, handlesKey);
    if isempty(H) || ~isstruct(H)
        % very old figure; rebuild once
        clf(hFig,'reset'); set(hFig,'Name',figName,'Tag',figTag,'Color','w');
        setappdata(hFig, handlesKey, struct()); % fall through to create-missing below
        H = getappdata(hFig, handlesKey);
    end

    % --- Ensure all axes exist (created by first version) ---
    if ~isfield(H,'t') || ~ishandle(H.t)
        t = tiledlayout(hFig,2,2,'Padding','compact','TileSpacing','compact');
        H.t = t;
        % if axes missing, (re)create
        H.ax1 = nexttile(t,1); hold(H.ax1,'on'); grid(H.ax1,'on'); box(H.ax1,'off');
        H.ax2 = nexttile(t,2); hold(H.ax2,'on'); grid(H.ax2,'on'); box(H.ax2,'off');
        H.ax3 = nexttile(t,3); hold(H.ax3,'on'); grid(H.ax3,'on'); box(H.ax3,'off');
        H.ax4 = nexttile(t,4);                       % heatmap axis
        setappdata(hFig, handlesKey, H);
    end

    % --- Ensure lines/images exist (create if missing) ---
    H.l_obj   = ensureLine(H, 'l_obj',   H.ax1, {'LineWidth',2,  'DisplayName','best objective'});
    H.l_gain  = ensureLine(H, 'l_gain',  H.ax1, {'LineWidth',1.5,'LineStyle',':','DisplayName','cum. gain'}); % NEW
    yyaxis(H.ax1,'right');
    H.l_nsel  = ensureLine(H, 'l_nsel',  H.ax1, {'LineWidth',1.8,'LineStyle','--','DisplayName','#features'});
    yyaxis(H.ax1,'left');
    H.l_stop1 = ensureStopLine(H, 'l_stop1', H.ax1); % NEW

    H.l_lam   = ensureLine(H, 'l_lam',   H.ax2, {'LineWidth',2,  'DisplayName','\lambda_{eff}'});
    yyaxis(H.ax2,'right');
    H.l_mpr   = ensureLine(H, 'l_mpr',   H.ax2, {'LineWidth',1.8,'DisplayName','max m'''});
    H.l_tau   = ensureLine(H, 'l_tau',   H.ax2, {'LineWidth',1.5,'LineStyle','--','DisplayName','\tau'});
    yyaxis(H.ax2,'left');
    H.l_stop2 = ensureStopLine(H, 'l_stop2', H.ax2); % NEW

    H.l_phi   = ensureLine(H, 'l_phi',   H.ax3, {'LineWidth',2,  'DisplayName','\phi(s)'});
    H.l_cL    = ensureLineXY(H,'l_cL',   H.ax3, 'k--');
    H.l_cR    = ensureLineXY(H,'l_cR',   H.ax3, 'k--');
    H.l_dens  = ensureLine(H, 'l_dens',  H.ax3, {'LineWidth',1.5,'LineStyle',':','DisplayName','sim density (scaled)'});

    if ~isfield(H,'im_rv') || ~ishandle(H.im_rv)
        axes(H.ax4); cla(H.ax4);
        H.im_rv = imagesc(H.ax4, NaN); axis(H.ax4,'tight'); colorbar(H.ax4); set(H.ax4,'YDir','normal');
        title(H.ax4,'r-vector snapshots'); xlabel(H.ax4,'snapshot (accept step)'); ylabel(H.ax4,'feature index');
    end
    if ~isfield(H,'sc_sel') || ~ishandle(H.sc_sel)
        hold(H.ax4,'on');
        H.sc_sel = scatter(H.ax4, NaN, NaN, 12, 'w', 'filled', 'MarkerEdgeColor','k', 'LineWidth',0.25);
    end
setappdata(hFig, handlesKey, H);

    setappdata(hFig, handlesKey, H);
end

% -------- Tile (1): objective, #features, cumulative gain, stop --------
set(H.l_obj, 'XData', Hist.it, 'YData', Hist.optparam);
if isfield(Hist,'gain_step') && ~isempty(Hist.gain_step)
    cg = cumsum(Hist.gain_step); xs = 1:numel(cg);
    set(H.l_gain, 'XData', xs, 'YData', cg, 'Visible','on');
else
    set(H.l_gain, 'XData', NaN, 'YData', NaN, 'Visible','off');
end
yyaxis(H.ax1,'right'); set(H.l_nsel, 'XData', Hist.it, 'YData', Hist.n_selected);
yyaxis(H.ax1,'left');  xlabel(H.ax1,'accept step'); title(H.ax1,'Best objective and #selected');

if isfield(Hist,'stopped') && Hist.stopped && isfield(Hist,'stop_it') && ~isempty(Hist.stop_it)
    yl = get(H.ax1,'YLim'); set(H.l_stop1,'XData',[Hist.stop_it Hist.stop_it], 'YData', yl, 'Visible','on');
else
    set(H.l_stop1,'XData',[NaN NaN], 'YData',[NaN NaN], 'Visible','off');
end

% -------- Tile (2): lambda, m', tau, stop --------
set(H.l_lam,'XData',Hist.it,'YData',Hist.lambda_eff);
yyaxis(H.ax2,'right');
set(H.l_mpr,'XData',Hist.it,'YData',Hist.max_mprime);
set(H.l_tau,'XData',Hist.it,'YData',Hist.tau_used);
yyaxis(H.ax2,'left'); xlabel(H.ax2,'accept step'); title(H.ax2,'Penalty and natural stop signals');
if isfield(Hist,'stopped') && Hist.stopped && isfield(Hist,'stop_it') && ~isempty(Hist.stop_it)
    yl2 = get(H.ax2,'YLim'); set(H.l_stop2,'XData',[Hist.stop_it Hist.stop_it], 'YData', yl2, 'Visible','on');
else
    set(H.l_stop2,'XData',[NaN NaN], 'YData',[NaN NaN], 'Visible','off');
end

% -------- Tile (3): penalty & density --------
if ~isempty(AD) && isfield(AD,'c')
    sgrid = linspace(0,1,600);
    phi   = rfe_redundancy_penalty(sgrid, AD.c, AD.w, AD.beta_well, AD.beta_hi, AD.sigma_lo, AD.sigma_hi);
    set(H.l_phi,'XData',sgrid,'YData',phi);
    yl = [min(phi) max(phi)]; if yl(1)==yl(2), yl = yl + [-1 1]*1e-6; end
    set(H.ax3,'YLim',yl);
    set(H.l_cL,'XData',[AD.c-AD.w AD.c-AD.w],'YData',yl);
    set(H.l_cR,'XData',[AD.c+AD.w AD.c+AD.w],'YData',yl);

    if ~isempty(s_last)
        s_last = max(0, min(1, s_last(:)));
        try
            [f,x] = ksdensity(s_last, 'Support',[0,1], 'BoundaryCorrection','reflection');
            scale = max(abs(phi)); if ~isfinite(scale) || scale<=0, scale = 1; end
            set(H.l_dens,'XData',x,'YData',scale*f/max(f),'Visible','on');
        catch
            edges  = linspace(0,1,21); counts = histcounts(s_last, edges, 'Normalization','pdf');
            xc     = (edges(1:end-1)+edges(2:end))/2;
            mxc    = max(counts); if mxc==0, mxc=1; end
            scale  = max(abs(phi)); if ~isfinite(scale) || scale<=0, scale = 1; end
            set(H.l_dens,'XData',xc,'YData',scale*counts/mxc,'Visible','on');
        end
    else
        set(H.l_dens,'XData',NaN,'YData',NaN,'Visible','off');
    end
else
    set(H.l_phi,'XData',NaN,'YData',NaN);
    set(H.l_cL, 'XData',[NaN NaN],'YData',[NaN NaN]);
    set(H.l_cR, 'XData',[NaN NaN],'YData',[NaN NaN]);
    set(H.l_dens,'XData',NaN,'YData',NaN,'Visible','off');
end

% -------- Tile (4): r-vector snapshots + selection dots --------
if ~isempty(Hist.rvec_snap)
    % heatmap
    M = padcat_cols(Hist.rvec_snap{:});
    set(H.im_rv, 'CData', M); axis(H.ax4,'tight'); set(H.ax4,'YDir','normal');

    % x tick labels with snapshot indices if available
    if isfield(Hist,'rvec_snap_it') && ~isempty(Hist.rvec_snap_it)
        xticks(H.ax4, 1:numel(Hist.rvec_snap_it));
        xticklabels(H.ax4, Hist.rvec_snap_it);
    end

    % ---- WHITE DOTS overlay ----
    xs = []; ys = [];
    if isfield(Hist,'rvec_snap_it') && ~isempty(Hist.rvec_snap_it) && isfield(Hist,'sel_local')
        % build dots cumulatively up to each snapshot accept-step
        for j = 1:numel(Hist.rvec_snap_it)
            itj = Hist.rvec_snap_it(j);
            % collect selections up to snapshot j
            sel_upto = [Hist.sel_local{1:min(itj, numel(Hist.sel_local))}];
            if ~isempty(sel_upto)
                xs = [xs; j * ones(numel(sel_upto),1)];
                ys = [ys; sel_upto(:)];
            end
        end
    elseif isfield(Hist,'rvec_snap_it') && isfield(Hist,'sel_idx') && isfield(Hist,'FullInd')
        % fallback mapping from global IDs
        FI = Hist.FullInd(:);
        for j = 1:numel(Hist.rvec_snap_it)
            itj = Hist.rvec_snap_it(j);
            sel_cells = Hist.sel_idx(1:min(itj, numel(Hist.sel_idx)));
            sel_all   = [sel_cells{:}];
            if ~isempty(sel_all)
                [tf, loc] = ismember(sel_all(:), FI);
                loc = loc(tf & loc>0);
                if ~isempty(loc)
                    xs = [xs; j * ones(numel(loc),1)];
                    ys = [ys; loc(:)];
                end
            end
        end
    end
    if isempty(xs)
        set(H.sc_sel, 'XData', NaN, 'YData', NaN, 'Visible','off');
    else
        set(H.sc_sel, 'XData', xs,  'YData', ys,  'Visible','on');
    end
else
    set(H.im_rv, 'CData', NaN);
    set(H.sc_sel,'XData', NaN, 'YData', NaN, 'Visible','off');
end

drawnow limitrate nocallbacks;

end

% ---------- helpers ----------
function h = ensureLine(H, fld, ax, args)
    if ~isfield(H,fld) || ~ishandle(H.(fld))
        h = plot(ax, NaN, NaN, args{:});
        H.(fld) = h; setappdata(ancestor(ax,'figure'), 'TraceHandles', H);
    else
        h = H.(fld);
    end
end

function h = ensureLineXY(H, fld, ax, style)
    if ~isfield(H,fld) || ~ishandle(H.(fld))
        h = plot(ax, [NaN NaN], [NaN NaN], style, 'HandleVisibility','off');
        H.(fld) = h; setappdata(ancestor(ax,'figure'), 'TraceHandles', H);
    else
        h = H.(fld);
    end
end

function h = ensureStopLine(H, fld, ax)
    if ~isfield(H,fld) || ~ishandle(H.(fld))
        h = plot(ax, [NaN NaN], [NaN NaN], 'r--', 'HandleVisibility','off');
        H.(fld) = h; setappdata(ancestor(ax,'figure'), 'TraceHandles', H);
    else
        h = H.(fld);
    end
end

function M = padcat_cols(varargin)
    L = cellfun(@numel, varargin); n = max([1, L]);
    M = NaN(n, numel(varargin));
    for i=1:numel(varargin), v = varargin{i}; v = v(:); M(1:numel(v), i) = v; end
end

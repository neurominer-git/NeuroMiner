function D = nk_PrintCV2BarChart(D, multiflag)
% Minimal refactor: cache handles in figure appdata and only update data.

WinTag = 'PrintCVBarsBin';

% --- figure (create or find) ---
h = findobj(0,'Type','figure','Tag',WinTag);
if isempty(h) || ~ishandle(h)
    h = figure('Name', D.binwintitle, ...
        'NumberTitle','off', 'Tag', WinTag, ...
        'MenuBar','none', 'Position', D.figuresz, 'Color',[0.9 0.9 0.9]);
else
    set(h,'Name', D.binwintitle);
end

% --- Screen size adjustment for MATLAB Online ---
sz = get(0, 'ScreenSize');
isMatlabOnline = strcmp(getenv('MW_DDUX_APP_NAME'), 'MATLAB_ONLINE');

if isMatlabOnline
    % Manually set a fixed size and center the window.
    manual_width = 1200;
    manual_height = 800;
    pos_x = max( (sz(3) - manual_width) / 2, 1);
    pos_y = max( (sz(4) - manual_height) / 2, 1);
    fig_pos = [pos_x, pos_y, manual_width, manual_height];
    
    set(h, 'Units', 'pixels', 'Position', fig_pos);
end
% For desktop MATLAB, the default D.figuresz or existing position is used.
% --- handle cache in appdata ---
H = getappdata(h,'CV2Handles');
if isempty(H), H = struct(); end

%% === Top progress bar (create once, then update) ===
if ~isfield(H,'prog_ax') || ~ishandle(H.prog_ax)
    H.prog_ax = axes('Parent', h, 'Position', [0.1 0.95 0.85 0.025], ...
        'Tag', 'CurrParam', 'Visible','on', 'YTick', [], 'Box','on');
end
if ~isfield(H,'prog_bar') || ~ishandle(H.prog_bar)
    H.prog_bar = barh(H.prog_ax, 1, 0, 'FaceColor','b', 'EdgeColor','none');
    xlim(H.prog_ax,[0 100]); ylim(H.prog_ax,[0.5 1.5]); set(H.prog_ax,'YTick',[]);
end
% Build label text (unchanged from your code, simplified)
if ~isempty(D.Pdesc{1})
    tx = sprintf('%s\nParams: ', D.s);
    txi = '';
    for j = 1:numel(D.Pdesc{1})
        ParVal = D.P{1}(j);
        if iscell(ParVal), ParVal = ParVal{1}; end
        if isnumeric(ParVal), ParVal = num2str(ParVal,'%g'); end
        txi = [txi sprintf('%s = %s, ', D.Pdesc{1}{j}, ParVal)]; %#ok<AGROW>
    end
    if ~isempty(txi), tx = [tx txi(1:end-2)]; else, tx = D.s; end
else
    tx = D.s;
end
% Update progress bar
xlabel(H.prog_ax, tx);
pct = max(0,min(100, double(D.pltperc)));
set(H.prog_bar, 'YData', pct, 'XData', 1);

% --- lock Y limits for all axes in this figure ---
set(findall(h, 'type', 'axes'), 'YLimMode', 'manual');

%% === Main bar panels ===
H = ensureAndUpdatePanels(h, H, D.ax, D.nclass, 'ax');

%% === Multi panels (optional) ===
if multiflag && isfield(D,'m_ax') && ~isempty(D.m_ax)
    H = ensureAndUpdatePanels(h, H, D.m_ax, D.nclass, 'm_ax');
    ylim(H.m_ax{1}.ax,[0 100]);
end

% --- stash and return (D stays without handles) ---
setappdata(h,'CV2Handles', H);
drawnow
end

% -------------------------------------------------------------------------
function H = ensureAndUpdatePanels(hFig, H, AxSpec, nclass, key)
if ~isfield(H,key) || ~iscell(H.(key))
    H.(key) = cell(1, numel(AxSpec));
end

for p = 1:numel(AxSpec)
    A = AxSpec{p};
    if p > numel(H.(key)) || isempty(H.(key){p})
        H.(key){p} = struct();
    end
    HP = H.(key){p};

    % axes (create once)
    if ~isfield(HP,'ax') || ~ishandle(HP.ax)
        ax = findobj(hFig,'Type','axes','Tag',A.title);
        if isempty(ax), HP.ax = axes('Parent', hFig, 'Position', A.position, 'Tag', A.title);
        else,           HP.ax = ax(1);
        end
        ylabel(HP.ax, A.ylb); title(HP.ax, A.title);
        if isempty(A.ylm)
            vals = A.val_y(:); vals = vals(isfinite(vals));
            if isempty(vals), ylm=[0 1]; else, ylm=[min(vals) max(vals)]; end
            if ylm(1)==ylm(2), ylm=ylm+[-0.5 0.5]; end
        else
            ylm = A.ylm;
        end
    end

    % graphics (create once)
    needCreate = ~isfield(HP,'h_bar') || any(~ishandle(HP.h_bar)) || ...
                 ~isfield(HP,'err_bar')|| any(~ishandle(HP.err_bar));
    if needCreate
        % fresh draw once
        [HP.h_bar, HP.err_bar] = barwitherr(A.std_y, A.val_y, 'Parent', HP.ax);
        
        if nclass==1 && isfield(A,'fc') && ~isempty(A.fc)
            set(HP.h_bar, 'FaceColor', A.fc);
        end
        set(HP.h_bar, 'EdgeColor','none');
        % legend unchanged (kept minimal)
        if isfield(A,'lg') && ~isempty(A.lg) && nclass>1
            hl = legend(HP.ax, A.lg); legend(HP.ax,'boxoff'); set(hl,'FontSize',8);
            HP.legend = hl;
        end
        set(HP.ax,'FontWeight','demi','FontSize',9); box(HP.ax,'on');
        xmax = size(A.val_y,1);
        if nclass>1
            if size(A.val_y,1)==2
                xmax=1;
            elseif size(A.val_y,1) == 1
                xmax=numel(A.val_y);
            end
        end
        xlim(HP.ax, [0.5, xmax+0.5]); ylim(HP.ax,  A.ylm);
        set(HP.ax,'XTick',1:numel(A.label),'XTickLabel',A.label,'XTickLabelRotation', 0);
        title(HP.ax, A.title); ylabel(HP.ax, A.ylb);
    else
        % update only: bars then errorbars
        if numel(HP.h_bar)>1
            n_bar = numel(HP.h_bar);
            for n=1:n_bar
                set(HP.h_bar(n), 'YData', A.val_y(:,n));
            end
        else
            n_bar=1;
            set(HP.h_bar, 'YData', A.val_y);
        end
        for n=1:n_bar
            set(HP.err_bar(n), 'YData', A.val_y(:,n));
            if any(isprop(HP.err_bar(n),'YNegativeDelta')) && any(isprop(HP.err_bar(n),'YPositiveDelta'))
                set(HP.err_bar(n), 'YNegativeDelta', A.std_y(:,n), 'YPositiveDelta', A.std_y(:,n));
            else
                if isprop(HP.err_bar(n),'LData'), set(HP.err_bar(n),'LData', A.std_y(:,n)); end
                if isprop(HP.err_bar(n),'UData'), set(HP.err_bar(n),'UData', A.std_y(:,n)); end
            end
        end
        % Keep axes tidy (labels/titles as you already re-apply after updates)
        set(HP.ax,'FontWeight','demi','FontSize',9); box(HP.ax,'on');
        set(HP.ax,'XTick',1:numel(A.label),'XTickLabel',A.label,'XTickLabelRotation', 0);
        xmax = size(A.val_y,1);
        if nclass>1
            if size(A.val_y,1)==2
                xmax=1;
            elseif size(A.val_y,1) == 1
                xmax=numel(A.val_y);
            end
        end
        xlim(HP.ax, [0.5, xmax+0.5]); ylim(HP.ax, A.ylm);
        title(HP.ax, A.title); ylabel(HP.ax, A.ylb);
    end

    H.(key){p} = HP;
end
end

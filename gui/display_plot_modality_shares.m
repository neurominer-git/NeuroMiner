function display_plot_modality_shares(handles, varargin)
%DISPLAY_PLOT_MODALITY_SHARES  Interactive plot for L2n share reports.
% Views (from ReportFinal):
%   1) Modality-wise      -> Report{h}.modality
%   2) Component-wise     -> Report{h}.components  (early) / Report{h}.components{m} (intermediate)
%   3) Component-wise     -> (mean)
%   4) Component-wise     -> mean r (CV2)
%   5) Component-wise     -> mean -log10(p) (CV2)
%   6) Component×Modality -> Report{h}.comp_by_mod
%
% In intermediate fusion:
%   - R.modality holds cross-modality shares
%   - R.components is a cell array over DR-based modalities (subset of all modalities)
%
% Usage:
%   display_plot_modality_shares(handles, h)
%   display_plot_modality_shares(handles, h, 'TopK', 20)

%% Parse options
p = inputParser;
p.addParameter('TopK', 15, @(x)isnumeric(x) && isscalar(x) && x>=1);
p.parse(varargin{:});
TopK = p.Results.TopK;

%% Fetch report
if ~isfield(handles, 'visdata') || ~isfield(handles.visdata{1}, 'Report') 
    errordlg('No report data available. Generate it first.','No report data');
    return;
end
R = handles.visdata{1}.Report{handles.curclass};

%%% NEW: detect intermediate fusion (components is cell array of per-DR-modality structs)
isIntermediate = isfield(R,'components') && iscell(R.components) && ~isempty(R.components);

%%% CHANGED: compwise availability now considers both early (struct) and intermediate (cell)
if ~isfield(R,'components')
    compwise = false;
elseif isIntermediate
    compwise = true;
else
    compwise = isstruct(R.components) && ~isempty(fieldnames(R.components));
end

%% Build figure and UI controls
f = figure('Name','NM Global Modality Stats Viewer', 'NumberTitle','off', 'Color','w', ...
           'Units','normalized','Position',[0.15 0.15 0.7 0.7]);

% Axes area
ax = axes('Parent', f, 'Units','normalized', 'Position', [0.08 0.14 0.62 0.74]); %#ok<NASGU>

% Table area
uitableHandle = uitable('Parent', f, 'Units','normalized', ...
    'Position',[0.72 0.14 0.26 0.74], ...
    'Data',{}, 'ColumnName',{}, 'RowName',{}, 'Visible','off');

% View selector
if ~compwise
    viewNames = {'Modality-wise (median ± 95% CI)'};
    compflag = 'off';
else
    viewNames = { ...
       'Modality-wise (median ± 95% CI)', ...
       'Component-wise L2 shares (Median Top-K)', ...
       'Component-wise L2 shares (Mean Top-K)', ...
       'Component-wise mean r (CV2) ± 95% CI (Top-K)', ...
       'Component-wise mean p (CV2) ± 95% CI (Top-K)', ...
       'Component × Modality (median share)'};
    compflag = 'on';
end

popupView = uicontrol('Style','popupmenu', 'String',viewNames, ...
    'Units','normalized', 'Position',[0.02 0.93 0.42 0.055], ... %%% CHANGED (width to make room for modality popup)
    'FontSize',10, 'BackgroundColor',[0.95 0.95 0.95], 'Enable', compflag);

% Export button
btnExport = uicontrol('Style','pushbutton','String','Export current view…', ...
    'Units','normalized','Position',[0.82 0.93 0.16 0.055], ...
    'FontSize',10,'BackgroundColor',[0.9 0.95 1]);

% Settings button (only useful when components exist)
if compwise
    btnSettings = uicontrol('Style','pushbutton','String','⚙ Settings…', ...
        'Units','normalized','Position',[0.64 0.93 0.16 0.055], ...
        'FontSize',10,'BackgroundColor',[0.95 0.95 0.95]);
    btnSettings.Callback = @(src,evt) showSettingsDialog(f);
end

popupMod = [];
drModNames = {};
if isIntermediate
    drModNames = getDRModNames(R);          % names for DR-based subset
    if isempty(drModNames), drModNames = compose("Mod%02d", 1:numel(R.components)); end
    popupMod = uicontrol('Style','popupmenu','String',drModNames, ...
        'Units','normalized','Position',[0.46 0.93 0.16 0.055], ...
        'FontSize',10,'BackgroundColor',[0.95 0.95 0.95], 'Enable','on');
end

% Store state in figure appdata
S = struct();
S.compwise = compwise;
S.isIntermediate = isIntermediate;     %%% NEW
S.R       = R;
S.TopK    = TopK;
S.handles = handles;
S.modSel  = 1;                         %%% NEW default selected DR modality
S.drModNames = drModNames;             %%% NEW
setappdata(f, 'state', S);

% Hook callbacks
popupView.Callback = @(src,evt) redrawCurrent(f, popupView, uitableHandle);  
btnExport.Callback = @(src,evt) exportCurrent(f, popupView);                              

if isIntermediate
    popupMod.Callback = @(src,evt) onModChanged(f, popupView, uitableHandle, popupMod);   %%% NEW
end

% Initial draw
redrawCurrent(f, popupView, uitableHandle); 

movegui(f,'onscreen'); drawnow; figure(f);
end % main function

%% =======================================================================
function onModChanged(figHandle, popupView, uitableHandle, popupMod)
% Update selected modality and redraw
S = getappdata(figHandle,'state');
if ~isempty(popupMod) && isvalid(popupMod)
    S.modSel = max(1, min(popupMod.Value, numel(S.drModNames)));
    setappdata(figHandle,'state',S);
end
redrawCurrent(figHandle, popupView, uitableHandle);
end

%% =======================================================================
function redrawCurrent(figHandle, popupView, uitableHandle)
ax = gca;
cla(ax, 'reset');           % reset axes state & clear callbacks
set(ax, 'Visible','on');    % ensure axes are visible again
axis(ax, 'on');             % (re-)enable axes drawing
S = getappdata(figHandle, 'state');
R = S.R;
set(ax, 'YLimMode','auto', 'CLimMode','auto');
viewIdx = popupView.Value;

switch viewIdx
    case 1
        % ===================== Modality-wise ============================
        M = R.modality;
        if isempty(M) || ~isfield(M,'median') || isempty(M.median)
            showNoData(ax, uitableHandle, 'No modality-wise data'); return;
        end

        med  = M.median(:);
        names= M.names(:);
        nM   = numel(med);

        haveCI = isfield(M,'lo95') && isfield(M,'hi95') && numel(M.lo95)==nM && numel(M.hi95)==nM;
        if haveCI
            lo95 = M.lo95(:); hi95 = M.hi95(:);
        end
        
        bar(ax, med, 'FaceAlpha', 0.9); hold(ax,'on');
        if haveCI
            x = 1:nM; y = med;
            neg = max(0, y - lo95);
            pos = max(0, hi95 - y);
            errorbar(ax, x, y, neg, pos, 'k', 'LineStyle','none', 'LineWidth', 1.0);
        else
            y = med;
        end

        T = table(names, med, 'VariableNames',{'Modality','MedianShare'});
        if isfield(M,'mean') && numel(M.mean)==nM, T.MeanShare = M.mean(:); end
        if haveCI, T.CI_lo95 = lo95; T.CI_hi95 = hi95; end
        if isfield(M,'coverage') && size(M.coverage,1)==nM
            T.CoverageHits = M.coverage(:,1); T.CoverageTotal= M.coverage(:,2);
        end
        if isfield(S,'colorbar'), S.colorbar.Visible='off'; end
        S.current.table   = T;
        S.current.matrix  = table2cell(T);
        S.current.headers = T.Properties.VariableNames;
        S.current.name    = sprintf('ModalityShares');
        setappdata(figHandle,'state',S);
        if strcmp(get(uitableHandle,'Visible'),'off')
            set(ax,'Position',[0.08 0.14 0.86 0.74]);
        else
            set(ax,'Position',[0.08 0.14 0.62 0.74]);
        end
        ax.XAxis.TickLabels = names;
        ax.YAxis.Label.String = 'Modality importance (L_p share)';
        if exist('lo95','var') && exist('hi95','var') && ~isempty(lo95) && ~isempty(hi95)
            set_lim_share(ax, y, lo95, hi95);
        else
            set_lim_share(ax, med);
        end

    case {2,3,4,5}
        % ===================== Component-wise (early or intermediate) ===
        set(uitableHandle,'Visible','on');
        ax = gca; set(ax,'Position',[0.08 0.14 0.62 0.74]);

        %%% NEW: select component container (struct vs cell{modIdx})
        if S.isIntermediate
            % guard against out-of-range modSel
            modIdx = max(1, min(S.modSel, numel(R.components)));
            C = R.components{modIdx};
            modLabel = sprintf(' — %s', safePick(S.drModNames, modIdx));
        else
            C = R.components;
            modLabel = '';
        end

        if isempty(C) || ~isstruct(C) || ~isfield(C,'median_share') || isempty(C.median_share)
           showNoData(ax, uitableHandle, 'No component-wise data'); return;
        end

        names = C.names(:);
        % Median/mean shares may be missing for some views; handle per-case below.

        switch viewIdx
            case {2,3}
                med   = C.median_share(:);
                meanV = C.mean_share(:);
                nRef  = numel(med);
                ord   = getOrder(C, med);
                K     = min(getappdata(figHandle,'state').TopK, nRef);
                pick  = ord(1:K);

                switch viewIdx
                    case 2
                        vals = med(pick);
                        tit = sprintf('Component-wise L_p shares (Top-%d by median)%s', K, modLabel);
                        ylab = 'L2 share (median)';
                    case 3
                        vals = meanV(pick);
                        tit = sprintf('Component-wise L_p shares (Top-%d by mean)%s', K, modLabel);
                        ylab = 'L2 share (mean)';
                end

                bar(ax, vals, 'FaceAlpha', 0.9);
                set(ax, 'XTick', 1:K, 'XTickLabel', names(pick), 'XTickLabelRotation', 30);
                ylabel(ax, ylab); title(ax, tit);
                ax.YGrid='on'; ax.Box='on'; ax.FontSize=11;
                set_lim_share(ax, vals);

                % Side table
                T = table(names(pick), med(pick), meanV(pick), 'VariableNames',{'Component','MedianShare','MeanShare'});
                if isfield(C,'mean_p_cv2'),  T.MeanP_CV2  = safePickVec(C.mean_p_cv2, pick);  end
                if isfield(C,'mean_r_cv2'),  T.MeanR_CV2  = safePickVec(C.mean_r_cv2, pick);  end
                if all(isfield(C, {'present_cv2','denom_cv2'}))
                    pres = safePickVec(C.present_cv2, pick); den = safePickVec(C.denom_cv2, pick);
                    T.Presence = arrayfun(@(a,b) sprintf('%d/%d', a, max(1,b)), pres, den, 'uni',0);
                end
                if isfield(C,'coverage_cv1') && size(C.coverage_cv1,1) >= numel(med)
                    T.CV1Covg = arrayfun(@(a,b) sprintf('%d/%d', a, b), ...
                                  C.coverage_cv1(pick,1), C.coverage_cv1(pick,2), 'uni',0);
                end
                if isfield(S,'colorbar'), S.colorbar.Visible='off'; end

                set(uitableHandle, 'Data', table2cell(T), 'ColumnName', T.Properties.VariableNames, ...
                    'RowName',[], 'Visible','on', 'ColumnEditable', false(1, width(T)));

                S.current.table   = T;
                S.current.matrix  = table2cell(T);
                S.current.headers = T.Properties.VariableNames;
                if S.isIntermediate
                    S.current.name = sprintf('ComponentShares_%s_Top%d', sanitizeName(modLabel(4:end)), K);
                else
                    S.current.name = sprintf('ComponentShares_h%03d_Top%d', R.meta.h, K);
                end
                setappdata(figHandle,'state',S);

            case 4 % r (CV2)
                if ~isfield(C,'mean_r_cv2') || isempty(C.mean_r_cv2)
                      showNoData(ax, uitableHandle, 'No component-wise CV2 correlation data'); return;
                end
                names = C.names(:);
                rmean = C.mean_r_cv2(:);
                rlo   = getfield_ifexists(C,'mean_r_lo95');
                rhi   = getfield_ifexists(C,'mean_r_hi95');

                nRef  = numel(rmean);
                ord   = getOrder(C, safeGet(C,'median_share', rmean));
                K     = min(getappdata(figHandle,'state').TopK, nRef);
                pick  = ord(1:K);

                bar(ax, rmean(pick), 'FaceAlpha', 0.9); hold(ax,'on');
                if ~isempty(rlo) && ~isempty(rhi) && numel(rlo)>=nRef && numel(rhi)>=nRef
                    x = 1:K; y = rmean(pick);
                    neg = max(0, y - rlo(pick)); pos = max(0, rhi(pick) - y);
                    errorbar(ax, x, y, neg, pos, 'k', 'LineStyle','none', 'LineWidth', 1.0);
                end
                set(ax, 'XTick', 1:K, 'XTickLabel', names(pick), 'XTickLabelRotation', 30);
                ylabel(ax, 'mean r (CV2)'); title(ax, sprintf('Component-wise mean correlation (Top-%d)%s', K, modLabel));
                ax.YGrid='on'; ax.Box='on'; ax.FontSize=11;
                if ~isempty(rlo) && ~isempty(rhi)
                    set_lim_corr(ax, rmean(pick), rlo(pick), rhi(pick));
                else
                    set_lim_corr(ax, rmean(pick));
                end

                T = table(names(pick), rmean(pick), 'VariableNames',{'Component','MeanR_CV2'});
                if ~isempty(rlo) && ~isempty(rhi)
                    T.MeanR_lo95 = rlo(pick); T.MeanR_hi95 = rhi(pick);
                end
                if all(isfield(C, {'present_cv2','denom_cv2'}))
                    T.Presence = arrayfun(@(a,b) sprintf('%d/%d', a, max(1,b)), C.present_cv2(pick), C.denom_cv2(pick), 'uni',0);
                end
                set(uitableHandle,'Data', table2cell(T), 'ColumnName', T.Properties.VariableNames, 'RowName',[], 'Visible','on');
                if isfield(S,'colorbar'), S.colorbar.Visible='off'; end
                set(ax,'Position',[0.08 0.14 0.62 0.74]);

                S.current.table   = T;
                S.current.matrix  = table2cell(T);
                S.current.headers = T.Properties.VariableNames;
                baseName = sprintf('Component_MeanR_CV2_Top%d', K);
                if S.isIntermediate, baseName = [baseName '_' sanitizeName(modLabel(4:end))]; end
                S.current.name    = baseName;
                setappdata(figHandle,'state',S);

            case 5 % -log10(p) (CV2)
                if ~isfield(C,'mean_p_cv2') || isempty(C.mean_p_cv2)
                    showNoData(ax, uitableHandle, 'No component-wise CV2 p-value data'); return;
                end
                names = C.names(:);
                pmean = C.mean_p_cv2(:);
                plo   = getfield_ifexists(C,'mean_p_lo95');
                phi   = getfield_ifexists(C,'mean_p_hi95');

                nRef  = numel(pmean);
                ord   = getOrder(C, safeGet(C,'median_share', pmean));
                K     = min(getappdata(figHandle,'state').TopK, nRef);
                pick  = ord(1:K);

                bar(ax, pmean(pick), 'FaceAlpha', 0.9); hold(ax,'on');
                if ~isempty(plo) && ~isempty(phi) && numel(plo)>=nRef && numel(phi)>=nRef
                    x = 1:K; y = pmean(pick);
                    neg = max(0, y - plo(pick)); pos = max(0, phi(pick) - y);
                    errorbar(ax, x, y, neg, pos, 'k', 'LineStyle','none', 'LineWidth', 1.0);
                end
                set(ax, 'XTick', 1:K, 'XTickLabel', names(pick), 'XTickLabelRotation', 30);
                ylabel(ax, 'mean -log10(p) (CV2)'); title(ax, sprintf('Component-wise mean p (Top-%d)%s', K, modLabel));
                ax.YGrid='on'; ax.Box='on'; ax.FontSize=11;
                if ~isempty(plo) && ~isempty(phi)
                    set_lim_logp(ax, pmean(pick), plo(pick), phi(pick));
                else
                    set_lim_logp(ax, pmean(pick));
                end

                T = table(names(pick), pmean(pick), 'VariableNames',{'Component','MeanP_CV2'});
                if ~isempty(plo) && ~isempty(phi)
                    T.MeanP_lo95 = plo(pick); T.MeanP_hi95 = phi(pick);
                end
                if all(isfield(C, {'present_cv2','denom_cv2'}))
                    T.Presence = arrayfun(@(a,b) sprintf('%d/%d', a, max(1,b)), C.present_cv2(pick), C.denom_cv2(pick), 'uni',0);
                end
                set(uitableHandle,'Data', table2cell(T), 'ColumnName', T.Properties.VariableNames, 'RowName',[], 'Visible','on');
                if isfield(S,'colorbar'), S.colorbar.Visible='off'; end
                set(ax,'Position',[0.08 0.14 0.62 0.74]);

                S.current.table   = T;
                S.current.matrix  = table2cell(T);
                S.current.headers = T.Properties.VariableNames;
                baseName = sprintf('Component_MeanP_CV2_Top%d', K);
                if S.isIntermediate, baseName = [baseName '_' sanitizeName(modLabel(4:end))]; end
                S.current.name    = baseName;
                setappdata(figHandle,'state',S);
        end

    case 6
        % ===================== Component × Modality =====================
        CM = R.comp_by_mod;
        if isempty(CM) || ~isfield(CM,'median_share') || isempty(CM.median_share)
            showNoData(ax, uitableHandle, 'No component×modality data'); return;
        end
    
        M = CM.median_share;
        compNames = CM.names_comp(:);
        modNames  = CM.names_mod(:);
    
        imagesc(M, 'Parent', ax); axis(ax,'tight');
        colormap(ax, parula);
        if isfield(S,'colorbar')
            S.colorbar.Visible='off'; 
        else
            S.colorbar=colorbar('peer', ax);
        end
        set(ax, 'XTick', 1:numel(modNames), 'XTickLabel', modNames, 'XTickLabelRotation', 30);
        set(ax, 'YTick', 1:numel(compNames), 'YTickLabel', compNames);
        xlabel(ax,'Modality'); ylabel(ax,'Component');
        title(ax, sprintf('Component × Modality median share'));
        set(ax,'Position',[0.18 0.14 0.60 0.74]);

        cmax = max(M(:), [], 'omitnan');
        if isfinite(cmax) && cmax > 0
            clim(ax, [0 min(1, cmax*1.02)]);
        else
            clim(ax, [0 1]);
        end
    
        set(uitableHandle,'Visible','off');
    
        T = array2table(M, 'VariableNames', matlab.lang.makeValidName(modNames), ...
                           'RowNames', compNames);
        S.current.table   = T;
        S.current.matrix  = M;
        S.current.headers = [{'Component'}, modNames(:)'];
        S.current.name    = sprintf('CompByMod_median_h%03d', R.meta.h);
        setappdata(figHandle,'state',S);
end
end

function showNoData(ax, uitableHandle, msg)
    % Keep axes visible so later views don’t inherit 'axis off'
    cla(ax); set(ax, 'Visible','on'); axis(ax,'on');
    set(uitableHandle,'Visible','off');
    % draw a centered note without killing the axes
    xlim(ax, [0 1]); ylim(ax, [0 1]);
    text(0.5, 0.5, msg, 'Parent', ax, ...
        'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
        'FontAngle','italic', 'Color', [0.2 0.2 0.2]);
    ax.XTick = []; ax.YTick = []; box(ax,'on');
end

%% =======================================================================
function exportCurrent(figHandle, popupView) 
S = getappdata(figHandle, 'state');
if ~isfield(S,'current') || isempty(S.current)
    warndlg('Nothing to export yet.','Export');
    return;
end
defaultExt  = ternary(ispc, '.xlsx', '.csv');
defaultName = [S.current.name, defaultExt];

[fn, fp, ~] = uiputfile( ...
    {'*.xlsx','Excel Workbook (*.xlsx)'; '*.csv','CSV (comma delimited) (*.csv)'}, ...
    'Export current view', defaultName);

if isequal(fn,0), return; end
fullpath = fullfile(fp,fn);
[~,~,ext] = fileparts(fullpath);
ext = lower(ext);

try
    T = ensureTable(S.current.table);
    settingsTable = [];
    if isfield(S.R,'meta') && isfield(S.R.meta,'settings') && ~isempty(S.R.meta.settings)
        settingsTable = settings_as_table(S.R.meta.settings);
    end
    switch ext
        case '.xlsx'
            writetable(T, fullpath, 'WriteRowNames', hasRowNames(T), 'Sheet','Data');
            if ~isempty(settingsTable)
                writetable(settingsTable, fullpath, 'WriteRowNames', false, 'Sheet','Settings');
            end
        case '.csv'
            writetable(T, fullpath, 'WriteRowNames', hasRowNames(T), 'FileType','text','Delimiter',',');
            if ~isempty(settingsTable)
                [fp0,fn0] = fileparts(fullpath);
                fullpath2 = fullfile(fp0, [fn0 '_settings.csv']);
                writetable(settingsTable, fullpath2, 'WriteRowNames', false, 'FileType','text','Delimiter',',');
            end
        otherwise
            fullpath = [fullpath, '.csv'];
            writetable(T, fullpath, 'WriteRowNames', hasRowNames(T), 'FileType','text','Delimiter',',');
    end

    msgbox(sprintf('Exported to:\n%s', fullpath), 'Export successful','help');

catch ME
    errordlg(sprintf('Export failed:\n%s', ME.message), 'Export error');
end
end

function y = ternary(cond, a, b)
if cond, y = a; else, y = b; end
end

%% ---------- helpers ----------
function tf = hasRowNames(T)
try
    tf = ~isempty(T.Properties.RowNames);
catch
    tf = false;
end
end

function T = ensureTable(Tin)
if istable(Tin)
    T = Tin;
else
    if iscell(Tin)
        T = cell2table(Tin);
    else
        T = array2table(Tin);
    end
end
end

function set_lim_share(ax, y, lo, hi)
    if nargin < 3 || isempty(lo) || isempty(hi)
        ymax = max(y, [], 'omitnan');
    else
        ymax = max(hi, [], 'omitnan');
    end
    if ~isfinite(ymax) || ymax <= 0, ymax = 0.02; end
    ylim(ax, [0, min(1, ymax*1.05)]);
    xlim(ax, [0.5, numel(y)+0.5]);
    ax.YAxis.TickValuesMode = 'auto';
    ax.YAxis.TickLabelsMode= 'auto';
end

function set_lim_corr(ax, y, lo, hi)
    yall = y(:);
    if nargin >= 3 && ~isempty(lo) && ~isempty(hi)
        yall = [yall; lo(:); hi(:)];
    end
    yall = yall(isfinite(yall));
    if isempty(yall), ylim(ax, [-1 1]); return; end
    ymin = min(yall); ymax = max(yall);
    pad  = 0.05 * max(1e-6, ymax - ymin);
    ylim(ax, [max(-1, ymin - pad), min(1, ymax + pad)]);
    xlim(ax, [0.5, numel(y)+0.5]);
    ax.YAxis.TickValuesMode = 'auto';
    ax.YAxis.TickLabelsMode= 'auto';
end

function set_lim_logp(ax, y, lo, hi)
    yall = y(:);
    if nargin >= 3 && ~isempty(lo) && ~isempty(hi)
        yall = [yall; lo(:); hi(:)];
    end
    yall = yall(isfinite(yall));
    if isempty(yall), ylim(ax,[0 1]); return; end
    ymax = max(yall);
    if ~isfinite(ymax) || ymax <= 0, ymax = 0.02; end
    pad  = 0.05 * max(1e-6, ymax);
    ylim(ax, [0, ymax + pad]);
    xlim(ax, [0.5, numel(y)+0.5]);
    ax.YAxis.TickValuesMode = 'auto';
    ax.YAxis.TickLabelsMode= 'auto';
end

function T = settings_as_table(Sin)
nameMap = struct( ...
  'backprojection_method',       {{'Backprojection method', 'How component weights are projected back to feature space'}}, ...
  'similarity_alignment_method', {{'Similarity metric (alignment)', 'Metric used when aligning components (e.g., correlation type)'}}, ...
  'similarity_pruning_cutoff',   {{'Similarity cutoff', 'Minimum similarity to keep a component during alignment'}}, ...
  'presence_pruning_cutoff',     {{'Presence cutoff', 'Minimum presence (e.g., across folds) to retain a component'}} );

params = fieldnames(Sin);
P = strings(numel(params),1);
V = strings(numel(params),1);
D = strings(numel(params),1);

for i = 1:numel(params)
    fn  = params{i};
    val = Sin.(fn);

    if isfield(nameMap, fn)
        c  = nameMap.(fn);
        nm = c{1};
        ds = c{2};
    else
        nm = fn;
        ds = "";
    end

    P(i) = string(nm);
    V(i) = stringifyValue(val);
    D(i) = string(ds);
end

T = table(P, V, D, 'VariableNames', {'Parameter','Value','Description'});
end

function s = stringifyValue(v)
if isstring(v) || ischar(v)
    s = string(v);
elseif islogical(v) && isscalar(v)
    s = string(v);
elseif isnumeric(v) && isscalar(v)
    s = string(num2str(v, '%g'));
elseif isnumeric(v) && ~isscalar(v)
    sz = size(v);
    head = num2str(v(1:min(numel(v),5)),' %g'); head = strtrim(head);
    s = sprintf('[%s] %s', strjoin(string(sz),'×'), head);
elseif iscellstr(v) || (iscell(v) && all(cellfun(@ischar,v)))
    s = "{" + strjoin(string(v), ", ") + "}";
else
    try
        s = string(jsonencode(v));
    catch
        s = "<unprintable>";
    end
end
end

function [C, colnames] = table_to_uitable_data(T)
C = table2cell(T);
for r = 1:size(C,1)
    for c = 1:size(C,2)
        v = C{r,c};
        if isstring(v)
            C{r,c} = char(v);
        elseif ischar(v)
            % ok
        elseif isnumeric(v) || islogical(v)
            if isscalar(v)
            else
                C{r,c} = char(strjoin(string(v(:).'), ' '));
            end
        elseif isdatetime(v)
            C{r,c} = datestr(v);
        elseif iscell(v)
            try
                C{r,c} = char(strjoin(string(v), ', '));
            catch
                C{r,c} = '<cell>';
            end
        else
            try
                C{r,c} = char(jsonencode(v));
            catch
                C{r,c} = '<unprintable>';
            end
        end
    end
end
colnames = cellstr(T.Properties.VariableNames);
end

%%% --------------------- utilities for intermediate fusion ---------------------
function names = getDRModNames(R)
% Try to map component cells to modality names. Prefer explicit list if present.
if isfield(R,'components_mod_names') && ~isempty(R.components_mod_names)
    names = cellstr(string(R.components_mod_names));
    return;
end
% Fallback: if R.modality.names exists, assume DR-based modalities keep order in a subset list
if isfield(R,'modality') && isfield(R.modality,'names') && ~isempty(R.modality.names)
    Mnames = cellstr(string(R.modality.names));
    % If counts match exactly, assume 1:1 order
    if numel(Mnames) == numel(R.components)
        names = Mnames;
        return;
    end
end
% Last resort: numbered
names = compose("Mod%02d", 1:numel(R.components));
end

function v = getfield_ifexists(S, fn)
if isfield(S, fn), v = S.(fn)(:); else, v = []; end
end

function out = safeGet(S, fn, defaultV)
if isfield(S, fn) && ~isempty(S.(fn))
    out = S.(fn)(:);
else
    out = defaultV(:);
end
end

function ord = getOrder(C, fallbackVec)
if isfield(C,'order_by_median') && ~isempty(C.order_by_median)
    ord = C.order_by_median(:);
else
    [~,ord] = sort(fallbackVec(:),'descend','MissingPlacement','last');
end
end

function s = safePick(cellOrArray, idx)
% pick idx from cellstr/strings or numeric arrays safely
try
    if iscell(cellOrArray)
        s = cellOrArray{idx};
    elseif isstring(cellOrArray)
        s = char(cellOrArray(idx));
    else
        s = cellOrArray(idx);
    end
catch
    s = '';
end
if isstring(s), s = char(s); end
end

function v = safePickVec(vIn, pick)
try
    v = vIn(pick);
catch
    v = nan(numel(pick),1);
end
end

function nm = sanitizeName(s)
if isempty(s), nm = 'mod'; return; end
nm = regexprep(s, '[^\w\-]+', '_');
end

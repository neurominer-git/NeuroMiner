function [handles, contfl] = display_SubParam(handles, caller, useSurf)
if nargin<3 || isempty(useSurf), useSurf=false; end

curclass = handles.popupmenu1.Value;
if strcmp(handles.popupmenu1.String{curclass},'Multi-group classifier'), curclass=1; end
[handles, ctx] = get_modelperf_context(handles);   % <— unified metric info

selVal   = handles.selSubParam.Value;
selLabel = handles.selSubParam.String{selVal};
rows     = handles.selSubParam.String;
pm       = handles.PairwiseMap;

% If the separator row is selected, bail gracefully (or move selection)
if ischar(rows), rows = cellstr(rows); end
if strcmp(rows{selVal}, '— pairwise —')
    % e.g., bump to next row if exists, else back to 1
    if selVal < numel(rows), handles.selSubParam.Value = selVal + 1; else, handles.selSubParam.Value = 1; end
    selVal = handles.selSubParam.Value;
end

% Robust pairwise detection
isPairwise = isfield(handles,'PairwiseMap') && ...
             ~isempty(handles.PairwiseMap) && ...
             selVal<=numel(handles.PairwiseMap.pairwiseMask) && ...
             handles.PairwiseMap.pairwiseMask(selVal);

if ~isPairwise

    % Ensure we are back to a single-axes layout
    if handles.twoAxesMode 
        handles = restore_single_axis_layout(handles, false);
        reset_axes_for_singleparam(handles.axes17);  
        handles = hide_or_delete_colorbar(handles, 'cbar17');
        handles = hide_or_delete_colorbar(handles, 'cbar17b');
    end
    % ---- single-param branch (unchanged) ----
    param = char(strsplit(selLabel,'_'));
    Pind = contains(handles.ModelParamsDesc{curclass}, deblank(param(1,:)));
    if size(param,1)>1
        fPind = find(Pind);
        Pind = false(1,numel(Pind));
        if numel(fPind)>1
            if contains(param(2,:),'{'), idx = extractNumber(param(2,:));
            else,                        idx = str2double(deblank(param(2,:)));
            end
            Pind(fPind(idx)) = true;
        else
            Pind(fPind) = true;
        end
    end
    contfl = true;
    if ~any(Pind)
        if exist('caller','var') && ~isempty(caller), return; else, handles = display_modelperf(handles); end
    else
        if size(handles.currmeas,2)>1
            [mPerf, sdPerf, Params, bars] = extract_subparam_performance(handles.ModelParams{curclass}, handles.currmeas, Pind, [], 1, handles.axes17);
        else
            [mPerf, sdPerf, Params, bars] = extract_subparam_performance(handles.ModelParams, handles.currmeas, Pind, curclass, 1, handles.axes17);
        end
        % Build label strings from Params (numeric or cell)
        if iscell(Params)
            lbls = cellfun(@(x)char(string(x)), Params, 'UniformOutput', false);
        elseif isnumeric(Params)
            lbls = arrayfun(@(x)sprintf('%g',x), Params, 'UniformOutput', false);
        else
            lbls = cellstr(string(Params));
        end
       
        handles.axes17.XLabel.String = sprintf('Parameter subspace selection: %s', selLabel);
        if size(handles.currmeas,2)>1
            bars(1).FaceColor='b'; bars(2).FaceColor='r';
            handles.legend_modelperf.String = {'CV1 performance','CV2 performance'};
            handles.legend_modelperf.Visible='on';
            lbs = lbls{1};
        else
            bars(1).FaceColor=rgb('green'); handles.legend_modelperf.Visible='off';
            lbs = lbls;
        end
        contfl=false;
        assignin('base','nm_viewer_data_mean',mPerf);
        assignin('base','nm_viewer_data_sd',sdPerf);
        % Flatten the mean performance into a vector for scaling
        if iscell(mPerf), v = cell2mat(mPerf(:)); else, v = mPerf(:); end
        [handles, ystyle] = get_metric_axis_style(handles, ctx, v);
        
        apply_yaxis_style(handles.axes17, ystyle);
        handles.axes17.XLabel.String = sprintf('Parameter subspace selection: %s', selLabel);
    end
    apply_categorical_xticks(handles.axes17, lbs, 'MaxTicks', 30);
    handles.axes17.Legend.Visible = 'on';
    handles.axes17.Title.Visible = 'on';
    handles.axes17.YAxis.Label.String = ctx.ylb;
    handles.Axes17.Legend.String = ctx.lgstr;
    handles.twoAxesMode = false;

else
    % Layout: shrink axes17 and create axes17b
    [handles, ax1, ax2] = ensure_two_axes_layout(handles);

    P = handles.ModelParams{curclass};
    if size(handles.currmeas,2)>1
        % CV1 on ax1, CV2 on ax2
         idxPair = [];
        if isfield(pm,'byDropdown') && selVal <= numel(pm.byDropdown)
            idxPair = pm.byDropdown{selVal};
        end
        if isempty(idxPair) || numel(idxPair) ~= 2
            warning('Pairwise selection has no valid [colA colB] mapping.'); 
            return
        end
    
        [M1, ~, levA, levB] = extract_pairwise_grid(P, handles.currmeas(:,1), idxPair);
        [M2, ~, ~,    ~   ] = extract_pairwise_grid(P, handles.currmeas(:,2), idxPair);
    
        safe_cla(ax1); safe_cla(ax2);

        % Build a representative data vector for the metric scale (use both CV1/CV2 if present)
        vv = [M1(:); M2(:)];
        [handles, ystyle] = get_metric_axis_style(handles, ctx, vv);

        nmPairNames = handles.PairwiseMap.nameByDropdown{selVal};
        labelA = nmPairNames{1}; labelB = nmPairNames{2};
    
        do_plot_pair_grid(ax1, M1, levA, levB, useSurf, 'CV1', labelA, labelB, ystyle);
        do_plot_pair_grid(ax2, M2, levA, levB, useSurf, 'CV2', labelA, labelB, ystyle);
        
        handles.legend_modelperf.String  = {'CV1 map','CV2 map'};
        handles.legend_modelperf.Visible = 'on';
    else
        % Single measure -> use ax1 only, but keep ax2 around if you prefer; here we hide/delete it for clarity
        if isfield(pm,'byDropdown') && selVal <= numel(pm.byDropdown)
            idxPair = pm.byDropdown{selVal};
        end
        handles = restore_single_axis_layout(handles, true);
        [M, ~, levA, levB] = extract_pairwise_grid(P, handles.currmeas, idxPair);
        safe_cla(handles.axes17);

        v = M(:);
        [handles, ystyle] = get_metric_axis_style(handles, ctx, v);

        nmPairNames = handles.PairwiseMap.nameByDropdown{selVal};
        labelA = nmPairNames{1}; labelB = nmPairNames{2};
        do_plot_pair_grid(handles.axes17, M, levA, levB, useSurf, '', labelA, labelB, ystyle);
        handles.legend_modelperf.Visible = 'off';
    end

    [handles, cb1] = ensure_colorbar(handles, ax1, 'cbar17',  'cbar17');
    style_colorbar_for_metric(cb1, ystyle);

    if handles.twoAxesMode
        [handles, cb2] = ensure_colorbar(handles, ax2, 'cbar17b', 'cbar17b');
        style_colorbar_for_metric(cb2, ystyle);
    end
    % Formatting
    [handles, ~] = ensure_colorbar(handles, ax2, 'cbar17b',  'cbar17b');
    apply_categorical_xticks(handles.axes17, levA, 'MaxTicks', 10);
    apply_categorical_xticks(handles.axes17b, levA, 'MaxTicks', 10);
    handles.axes17.Legend.Visible = 'off';
    handles.axes17.XLabel.String = labelA;
    handles.axes17b.XLabel.String = labelA;
    handles.axes17b.XAxis.FontSize = handles.axes17.XAxis.FontSize;
    handles.axes17b.YAxis.FontSize = handles.axes17.YAxis.FontSize;
    handles.cbar17.FontSize = 10; 
    handles.cbar17b.FontSize = 10; 
    handles.axes17.Title.FontSize = 12; handles.axes17.Title.FontWeight = 'bold';
    handles.axes17b.Title.FontSize = 12; handles.axes17b.Title.FontWeight = 'bold';
    contfl = false;
    guidata(handles.figure1, handles);
end
% =========================================================================
% =                        VISUALIZATION PLOT                             =
% =========================================================================
function handles = display_visual(handles)
global st
st.ParentFig    = handles.figure1;
varind          = handles.curmodal;
measind         = handles.selVisMeas.Value;
meas            = handles.selVisMeas.String;
load_selPager(handles)
pageind         = handles.selPager.Value;
page            = handles.selPager.String;
pagemanual      = handles.txtPager.String;
sortfl          = handles.popupSortFeat.Value;
filterfl        = handles.tglVisMeas2.Value;
filterthr       = handles.txtThrVisMeas2.String;

handles.spiderPlotButton.Visible = "on";

axes(handles.axes33); cla; hold on
set(handles.axes33,'TickLabelInterpreter','none')

CorrMatStr = {'Correlation matrix', 'Correlation matrix (P value)','Correlation matrix (P value, FDR)'};
NetworkCorrMatStr = {'Network plot correlation matrix', 'Network plot correlation matrix (P value)', 'Network plot correlation matrix (P value, FDR)'};

% figure handle
hFig = handles.figure1;

% read colors (prefer handles, else appdata, else defaults)
if isfield(handles,'posBarColor') && ~isempty(handles.posBarColor)
    posColor = handles.posBarColor;
else
    posColor = getappdata(hFig,'posBarColor');
    if isempty(posColor), posColor = [0.85 0.15 0.15]; setappdata(hFig,'posBarColor',posColor); end
end
if isfield(handles,'negBarColor') && ~isempty(handles.negBarColor)
    negColor = handles.negBarColor;
else
    negColor = getappdata(hFig,'negBarColor');
    if isempty(negColor), negColor = [0.15 0.35 0.85]; setappdata(hFig,'negBarColor',negColor); end
end

v = handles.visdata{varind,handles.curlabel};
switch v.params.visflag
    case {1,2}
        featind = 1:v.params.nfeats;
    otherwise
        try
            if ~isempty(pagemanual) 
                featind = eval(pagemanual);
            else
                featind = eval(page{pageind});
            end
        catch
            featind = 1:v.params.nfeats;
        end
end

x = 0.5: numel(featind);
curclass = get(handles.popupmenu1,'Value');

if strcmp(handles.popupmenu1.String{curclass},'Multi-group classifier')
    multiflag = true;
else
    multiflag = false;
end

if measind>numel(meas)
    measind=numel(meas);
    handles.selVisMeas.Value=measind;
end

if strcmp(handles.selComponent.Visible,'on') && strcmp(handles.selComponent.Enable,'on')
    selC = handles.selComponent.Value-1;
else
    selC = 1;
end
if ~selC, selC=1; end

switch meas{measind} 
    case 'Model P value histogram'
        fl = 'off';
        fl2 = 'off'; 
        flhist = 'on';
    otherwise
        if isfield(v,'PermModel_Crit_Global_Multi') && multiflag
            fl = 'off';
        else
            fl = 'on';
        end
        flhist = 'on';
        if any(strcmp(meas{measind}, CorrMatStr))
            fl2 = 'on';
            load_selVisMeas2(handles)
        else
            if any(strcmp(meas{measind}, NetworkCorrMatStr))
                fl2 = 'on';
                load_selVisMeas2(handles)
            else
                fl2 = 'off';
            end
        end
end

switch v.params.visflag
    case 1
        handles.selPager.Enable = "off";
        handles.txtPager.Enable = "off";
        handles.tglSortFeat.Enable = "off";
        handles.cmdExportFeats.Enable = "off";
        handles.selVisMeas2.Enable = "off";
        handles.txtThrVisMeas2.Enable = "off";
        handles.tglVisMeas2.Enable = "off";
        handles.txtAlterFeats.Enable = "off";
        handles.cmdExportFeatFig.Enable = "off";
        handles.spiderPlotButton.Visible = "on";
        handles.btnPosColor.Visible = "off";
        handles.btnNegColor.Visible = "off";
    otherwise
        handles.selPager.Enable = fl;
        handles.txtPager.Enable = fl;
        handles.tglSortFeat.Enable = fl;
        handles.cmdExportFeats.Enable = fl;
        handles.selVisMeas2.Enable = fl2;
        handles.txtThrVisMeas2.Enable = fl2;
        handles.tglVisMeas2.Enable = fl2;
        handles.txtAlterFeats.Enable = fl;
        handles.btnPosColor.Visible = fl;
        handles.btnNegColor.Visible = fl;
        handles.cmdExportFeatFig.Enable = flhist;
        vlineval = [];
        if strcmp(fl,'on')
            if ~isempty(pagemanual) 
                handles.selPager.Enable = 'off';
            else
                handles.selPager.Enable = 'on';
            end
        end
        handles.spiderPlotButton.Visible = "off";
end

switch meas{measind}
    
    case 'Feature weights [Overall Mean (StErr)]'
        [y, se, miny, maxy, vlineval] = MEAN(v, curclass, multiflag);
    case 'Feature weights [CV2 Mean (StErr)]'
        [y, se, miny, maxy, vlineval] = MEAN_CV2(v, curclass, multiflag);
    case {'CVR of feature weights [Overall Mean]', 'CVR (SD-based) of feature weights [Overall Mean]', 'CVR (SEM-based) of feature weights [Overall Mean]'}
        [y, miny, maxy, vlineval] = CVRatio(v, curclass, multiflag);
        if miny>0, miny=0; end
    case {'CVR of feature weights [CV2 Mean]', 'CVR (SD-based) of feature weights [CV2 Mean]', 'CVR (SEM-based) of feature weights [CV2 Mean]'}
        [y, miny, maxy, vlineval] = CVRatio_CV2(v, curclass, multiflag);
        if miny>0, miny=0; end
    case 'Feature selection probability [Overall Mean]'
        [y, miny, maxy, vlineval] = FeatProb(v, curclass, multiflag);
    case 'Probability of feature reliability (95%-CI) [CV2 Mean]'
        [y, miny, maxy, vlineval] = Prob_CV2(v, curclass, multiflag);
    case 'Sign-based consistency'
        [y, miny, maxy, vlineval] = SignBased_CV2(v, curclass, multiflag);
        if miny>0, miny=0; end
    case 'Sign-based consistency (Z score)'
        [y, miny, maxy, vlineval] = SignBased_CV2_z(v, curclass, multiflag);
        if miny>0, miny=0; end
    case 'Sign-based consistency -log10(P value)'
        [y, miny, maxy, vlineval] = SignBased_CV2_p_uncorr(v, curclass, multiflag);
        if miny>0, miny=0; end
    case 'Sign-based consistency -log10(P value, FDR)'
        [y, miny, maxy, vlineval] = SignBased_CV2_p_fdr(v, curclass, multiflag);
        if miny>0, miny=0; end
    case 'Spearman correlation [CV2 Mean]'
        [y, miny, maxy, vlineval] = Spearman_CV2(v, curclass, multiflag);
    case 'Pearson correlation [CV2 Mean]'
        [y, miny, maxy, vlineval] = Pearson_CV2(v, curclass, multiflag);
    case 'Spearman correlation -log10(P value) [CV2 Mean]'
        [y, se, miny, maxy, vlineval] = Spearman_CV2_p_uncorr(v, curclass, multiflag);
    case 'Pearson correlation -log10(P value) [CV2 Mean]'
       [y, se, miny, maxy, vlineval] = Pearson_CV2_p_uncorr(v, curclass, multiflag);
    case 'Spearman correlation -log10(P value, FDR) [CV2 Mean]'
       [y, miny, maxy, vlineval] = Spearman_CV2_p_fdr(v, curclass, multiflag);
    case 'Pearson correlation -log10(P value, FDR) [CV2 Mean]'
       [y, miny, maxy, vlineval] = Pearson_CV2_p_fdr(v, curclass, multiflag);
    case 'Permutation-based Z Score [CV2 Mean]'
       [y, miny, maxy, vlineval] = PermZ_CV2(v, curclass, multiflag);
    case 'Permutation-based -log10(P value) [CV2 Mean]'
       [y, miny, maxy, vlineval] = PermProb_CV2(v, curclass, multiflag);
    case 'Permutation-based -log10(P value, FDR) [CV2 Mean]'
       [y, miny, maxy, vlineval] = PermProb_CV2_FDR(v, curclass, multiflag);
    case 'Analytical -log10(P Value) for Linear SVM [CV2 Mean]'
       [y, miny, maxy, vlineval] = Analytical_p(v, curclass, multiflag);
    case 'Analytical -log10(P Value, FDR) for Linear SVM [CV2 Mean]'
        [y, miny, maxy, vlineval] = Analyitcal_p_fdr(v, curclass, multiflag);
    case 'Correlation matrix'
        y = v.CorrMat_CV2{curclass};
        miny = min(y); maxy = max(y);
    case 'Correlation matrix (P value)'
        y = v.CorrMat_CV2_p_uncorr{curclass};
        miny = min(y); maxy = max(y);
    case 'Correlation matrix (P value, FDR)'
        y = v.CorrMat_CV2_p_fdr{curclass};
        miny = min(y); maxy = max(y);
    case 'Network plot correlation matrix'
        y = v.CorrMat_CV2{curclass};
        miny = min(y); maxy = max(y);
    case 'Network plot correlation matrix (P value)'
        y = v.CorrMat_CV2_p_uncorr{curclass};
        miny = min(y); maxy = max(y);
    case 'Network plot correlation matrix (P value, FDR)'
        y = v.CorrMat_CV2_p_fdr{curclass};
        miny = min(y); maxy = max(y);
    case {'Model P value histogram', 'Model P value histogram [Multi-group]'}
        if multiflag
            y = nm_nanmean(v.PermModel_Crit_Global); 
            vp = nm_nanmean(v.ObsModel_Eval_Global);
            ve = nm_nanmean(v.PermModel_Eval_Global);
        else         
            y = v.PermModel_Crit_Global; 
            vp = v.ObsModel_Eval_Global;
            ve = v.PermModel_Eval_Global;
        end
        perms = length(v.PermModel_Eval_Global(1,:));
        cl_face = rgb('SkyBlue');
        cl_edge = rgb('DeepSkyBlue');

    otherwise
        if contains(meas{measind},'Generalization analysis')
            % Define the regular expression pattern
            pattern = '\[#(\d+)\]';

            % Use regular expression to find matches in the string
            match = regexp(meas{measind}, pattern, 'tokens', 'once');

            % Check if a match is found
            if ~isempty(match)
                % Convert the matched string to a number
                LabelNum = str2double(match{1});
                y = v.ExtraL(LabelNum).VCV2MPERM_EVALFUNC_GLOBAL( curclass,:); 
                vp = v.ExtraL(LabelNum).VCV2MORIG_EVALFUNC_GLOBAL(curclass);
                ve = v.ExtraL(LabelNum).VCV2MPERM_GLOBAL(curclass,:);
                meas{measind} = 'Model P value histogram';
                perms = length(y);
                cl_face = rgb('Khaki');
                cl_edge = rgb('DarkKhaki');
            end

        end
end
        
if multiflag && isfield(v,'PermModel_Crit_Global_Multi')
    if measind == 1
         y = v.PermModel_Crit_Global_Multi; 
         vp = v.ObsModel_Eval_Global_Multi;
         ve = v.PermModel_Eval_Global_Multi;
    else
         y = v.PermModel_Crit_Global_Multi_Bin(measind-1,:); 
         vp = v.ObsModel_Eval_Global_Multi_Bin(measind-1);
         ve = v.PermModel_Eval_Global_Multi_Bin(measind-1,:);
    end
    perms = length(v.PermModel_Eval_Global_Multi);
    meas{measind} = 'Model P value histogram';
end

if ~strcmp(meas{measind}, 'Model P value histogram')
    y(~isfinite(y))=0;
    if width(y)>1 
        % Multiple components used
        % y = y(:,handles.selComponent.Value);
    end
end

switch meas{measind}

    case CorrMatStr
         set(handles.pn3DView,'Visible','off'); set(handles.axes33,'Visible','on'); cla; hold on
         feats = v.params.features; 
         if ~isempty(handles.txtAlterFeats.String)
            altfeatsvar = handles.txtAlterFeats.String;
            feats = evalin('base',altfeatsvar);
         end
         if filterfl
             FltMetr = handles.selVisMeas2.String{handles.selVisMeas2.Value};
             switch FltMetr
                 case {'CVR of feature weights [Overall Mean]', 'CVR (SD-based) of feature weights [Overall Mean]', 'CVR (SEM-based) of feature weights [Overall Mean]'}
                     [ythr,~,~,vlineval] = CVRatio(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String='-2 2'; 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case {'CVR of feature weights [CV2 Mean]', 'CVR (SD-based) of feature weights [CV2 Mean]', 'CVR (SEM-based) of feature weights [CV2 Mean]'}
                     [ythr,~,~,vlineval] = CVRatio_CV2(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String='-2 2'; 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Feature selection probability [Overall Mean]'
                     [ythr,~,~,vlineval] = FeatProb(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String='0.5'; 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Probability of feature reliability (95%-CI) [CV2 Mean]'
                     [ythr,~,~,vlineval] = Prob_CV2(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String='-0.5 0.5'; 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Sign-based consistency -log10(P value)'
                     [ythr,~,~,vlineval] = SignBased_CV2_p_uncorr(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String=num2str(-log10(0.05),'%1.2f'); 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Sign-based consistency -log10(P value, FDR)'
                     [ythr,~,~,vlineval] = SignBased_CV2_p_fdr(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String=num2str(-log10(0.05),'%1.2f'); 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Analytical -log10(P Value) for Linear SVM [CV2 Mean]'
                     [ythr,~,~,vlineval] = Analytical_p(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String=num2str(-log10(0.05),'%1.2f'); 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Analytical -log10(P Value, FDR) for Linear SVM [CV2 Mean]'
                     [ythr,~,~,vlineval] = Analyitcal_p_fdr(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String=num2str(-log10(0.05),'%1.2f'); 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
             end
            % New (filter on): sort by the chosen metric ythr
             sI = get_sort_index(ythr(:), sortfl);
             y = y(sI,sI);
             feats = feats(sI);
             y = y(featind,featind);
             feats = feats(featind);
             if numel(filterthr)>1
                Ix2 = (ythr >= min(filterthr) | ythr <= max(filterthr))';
             else 
                Ix2 = (abs(ythr)>= filterthr)'; 
             end
             Ix2 = Ix2(sI); Ix2 = Ix2(featind);
             Ix = any(y) & Ix2;
         else
             % New (filter on): sort by the chosen metric
             sI = get_sort_index(mean(y), sortfl);
             y = y(sI,sI);
             feats = feats(sI);
             y = y(featind,featind);
             feats = feats(featind);
             Ix = any(y);
         end
         y = y(Ix,Ix);
         feats = feats(Ix);
         nF = numel(feats);
         if nF<50, FS = 10; elseif nF<100, FS = 7; elseif nF < 150, FS = 5; else, FS = 0; end
         yy = y; 
         try
             if strcmp(meas{measind}, CorrMatStr{1})
                     yy(itril(size(yy))) = -1.1;
                     imagesc( yy ); cbar = colorbar('Visible','on');
                     clabel = 'Correlation coefficient';
                     handles.axes33.Colormap = customcolormap([0 0.48 0.99 1],[rgb('Red'); rgb('White'); rgb('Blue'); rgb('LightGray'); ]);
                     handles.axes33.CLim = [-1.1 1];
                     cbar.Limits = [-1 1];
             else
                     yy(itril(size(yy))) = 0;
                     imagesc( yy ); cbar = colorbar('Visible','on');
                     if strcmp(meas{measind}, CorrMatStr{3})
                         clabel = 'P value (FDR-corrected)';
                     else
                        clabel = 'P value (uncorrected)';
                     end
                     handles.axes33.Colormap =  customcolormap([0 0.25 0.50 0.75 .99 1],[rgb('Red'); rgb('Yellow'); rgb('Cyan'); rgb('Blue'); rgb('DarkViolet'); rgb('LightGray'); ]);
                     handles.axes33.CLim = [ -log10(0.05) max(yy(:))] ;
                     cbar.Limits = [-log10(0.05) handles.axes33.CLim(end)];
             end
             cbar.Label.String=clabel; cbar.Label.FontWeight='bold';

             if FS>0
                handles.axes33.XAxis.FontSize = FS; 
                handles.axes33.YAxis.FontSize = FS; 
                handles.axes33.XTick = 1:sum(Ix); handles.axes33.XTickLabel = feats; handles.axes33.XTickLabelRotation=45;
                handles.axes33.YTick = 1:sum(Ix); handles.axes33.YTickLabel = feats; 
                handles.axes33.XAxis.Label.FontSize = FS;
                handles.axes33.YAxis.Label.FontSize = FS;
             else
                handles.axes33.XTickMode = 'auto';
                handles.axes33.XLimMode = 'auto';
                handles.axes33.XTickLabelMode = 'auto';
                handles.axes33.XTickLabelRotation=0;
                handles.axes33.YTickMode = 'auto';
                handles.axes33.YLimMode = 'auto';
                handles.axes33.YTickLabelMode = 'auto';
                handles.axes33.XAxis.FontSize = 10;
                handles.axes33.YAxis.FontSize = 10;
                handles.axes33.XAxis.Label.FontSize = 10;
                handles.axes33.YAxis.Label.FontSize = 10;
             end

             handles.axes33.XLim = [0.5 sum(Ix)+0.5]; 
             handles.axes33.YLim = [0.5 sum(Ix)+0.5];
             handles.axes33.XAxis.Label.String = 'Features';
         catch ERR
             errordlg(sprintf('Matrix cannot be displayed!\n%s', ERR.message));
         end
         
    case 'Model P value histogram'
         cb = findobj(handles.axes33.Parent, 'Type', 'ColorBar', 'Axes', handles.axes33);
         delete(cb)
         yh = y(handles.curclass,:);
         n         = numel(yh);
         sigma     = nm_nanstd(yh);
         iqrValue  = prctile(yh,75) - prctile(yh,25);
         hs        = 0.9 * min(sigma, iqrValue/1.34) * n^(-1/5);   % Silverman’s rule
         binWidth  = 2 * iqrValue / n^(1/3);                       % Freedman–Diaconis
         handles.pn3DView.Visible = 'off'; 
         handles.axes33.Visible = 'on'; cla; 
         hold on;
         % grab the old position so we don’t clobber bottom & height
         pos = handles.axes33.Position;     
        
         % center horizontally & make half‑width
         pos(1) = (1 - 0.5)/2;    % = 0.25
         pos(3) = 0.5;
        
         % write it back
         handles.axes33.Position = pos;

         ah = histogram(handles.axes33, yh, ...
                            'Normalization','probability', ...
                            'BinWidth', binWidth, ...
                            'EdgeColor','none', ...
                            'FaceColor',cl_face); 
         maxah= nm_nanmax(ah.Values); ylim([0 (maxah + maxah*0.2)]); 
         [f, xi] = ksdensity(yh, ...
                                'Function','pdf', ...
                                'Bandwidth', hs, ...
                                'NumPoints', 200 );
         plot(handles.axes33, xi, ...
                scaledata(f,[],0, maxah), ...
                'Color', cl_edge, ...
                'LineWidth',2);
         handles.axes33.YTick = 0:maxah/10:(maxah+maxah*0.2);
         yticklabels(handles.axes33,'auto')
         [~,xlb]=nk_GetScaleYAxisLabel(handles.NM.analysis{handles.curranal}.params.TrainParam.SVM);
         rg = range(yh)*0.15; xl = [ min(yh)-rg max(yh)+rg ]; if vp>=xl(2), xl(2) = vp + rg; elseif vp<=xl(1), xl(1) = vp +rg; end
         xlim(xl); 
         xlabel(['Optimization criterion: ' xlb]);
         ylabel('Probability');
         hold on;
         Pval = sum(ve)/size(ve,2);
         vph = vp(handles.curclass); 
         if vph > xl(end), xlim([xl(1) vph+0.05*vph]); end
         xp = [ vph vph ]; yp = [ 0 maxah + maxah*0.2 ];
         if Pval ~= 0
            Pvalstr = sprintf('OOT %s=%1.2f\nOOT Significance: P=%g', xlb, vph, Pval);
         else
            Pvalstr = sprintf('OOT %s=%1.2f\nOOT Significance: P<%g', xlb, vph, 1/perms);
         end
         if exist("vp_cv2","var")
            xp_cv2 = [ vp_cv2 vp_cv2 ];
            patch('Faces', [1 2 3 4], 'Vertices', ...
                [ [ vp_cv2-vp_ci_cv2(1) 0 ]; [ vp_cv2-vp_ci_cv2(1) maxah ] ; [vp_cv2+vp_ci_cv2(1) maxah] ; [vp_cv2+vp_ci_cv2(1) 0 ] ], ...
                'FaceColor', rgb('LightSalmon'), 'EdgeColor', 'none', 'FaceAlpha', 0.3 );
            line( xp_cv2, yp ,'LineWidth',1,'Color',rgb('LightSalmon') );
            Pvalstr_cv2 = sprintf('Mean CV2 %s=%1.2f\nMean CV2 Significance: P=%g', xlb, vp_cv2, ve_cv2);
         end
         line(xp, yp ,'LineWidth',2,'Color','r');
         if exist("vp_cv2","var")
             legend({'Binned null distribution', 'Fitted null distribution', sprintf('95%%-CI Mean %s',xlb), Pvalstr_cv2, Pvalstr }, 'Location', 'northwest');
         else
            legend({'Binned null distribution', 'Fitted null distribution', Pvalstr}, 'Location', 'northwest');
         end

    case NetworkCorrMatStr

         set(handles.pn3DView,'Visible','off'); 
         % grab the old position so we don’t clobber bottom & height
         pos = handles.axes33.Position;     
        
         % center horizontally & make half‑width
         pos(1) = (1 - 0.5)/2;    % = 0.25
         pos(3) = 0.5;
        
         % write it back
         handles.axes33.Position = pos;
         set(handles.axes33,'Visible','on'); cla; hold on
         feats = v.params.features; 
         if ~isempty(handles.txtAlterFeats.String)
            altfeatsvar = handles.txtAlterFeats.String;
            feats = evalin('base',altfeatsvar);
         end
       
         if filterfl
             FltMetr = handles.selVisMeas2.String{handles.selVisMeas2.Value};
             switch FltMetr
                 case {'CVR of feature weights [Overall Mean]', 'CVR (SD-based) of feature weights [Overall Mean]', 'CVR (SEM-based) of feature weights [Overall Mean]'}
                     [ythr,~,~,vlineval] = CVRatio(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String='-2 2'; 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Feature selection probability [Overall Mean]'
                     [ythr,~,~,vlineval] = FeatProb(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String='0.5'; 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Probability of feature reliability (95%-CI) [CV2 Mean]'
                     [ythr,~,~,vlineval] = Prob_CV2(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String='-0.5 0.5'; 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Sign-based consistency -log10(P value)'
                     [ythr,~,~,vlineval] = SignBased_CV2_p_uncorr(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String=num2str(-log10(0.05),'%1.2f'); 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Sign-based consistency -log10(P value, FDR)'
                     [ythr,~,~,vlineval] = SignBased_CV2_p_fdr(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String=num2str(-log10(0.05),'%1.2f'); 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Analytical -log10(P Value) for Linear SVM [CV2 Mean]'
                     [ythr,~,~,vlineval] = Analytical_p(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String=num2str(-log10(0.05),'%1.2f'); 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
                 case 'Analytical -log10(P Value, FDR) for Linear SVM [CV2 Mean]'
                     [ythr,~,~,vlineval] = Analyitcal_p_fdr(v,curclass,multiflag);
                     if isempty(filterthr)
                         handles.txtThrVisMeas2.String=num2str(-log10(0.05),'%1.2f'); 
                         filterthr = vlineval;
                     else
                         filterthr = str2double(filterthr);
                     end
             end
             % New (filter on): sort by the chosen metric ythr
             sI = get_sort_index(ythr(:), sortfl);
             y = y(sI,sI);
             feats = feats(sI);
             y = y(featind,featind);
             feats = feats(featind);
             %y.diag
             if numel(filterthr)>1
                Ix2 = (ythr >= min(filterthr) | ythr <= max(filterthr))';
             else 
                Ix2 = (abs(ythr)>= filterthr)'; 
             end
             Ix2 = Ix2(sI); Ix2 = Ix2(featind);
             Ix = any(y) & Ix2;
         else
             % New (filter on): sort by the chosen metric 
             sI = get_sort_index(mean(y), sortfl);
             y = y(sI,sI);
             feats = feats(sI);
             y = y(featind,featind);
             feats = feats(featind);
             Ix = any(y);
         end
         y = y(Ix,Ix);
         feats = feats(Ix);
         yy = y; 
       
        % Safety & niceties
         yy = double(yy);
         yy(~isfinite(yy)) = 0;                     % drop NaN/Inf edges
         yy(1:size(yy,1)+1:numel(yy)) = 0;         % remove self-loops
         % Tweak these to taste
         K_PER_NODE = 5;      % up to 5 strongest connections per node
         MAX_GLOBAL = 250;    % and at most 250 edges overall
         GAMMA      = 0.8;    % edge color contrast (0.6–1.0 is nice)

         cla reset;

         switch meas{measind}
            case NetworkCorrMatStr{1}  % signed correlation matrix
               [~, handles.pgy] = nm_plot_feature_network(yy, feats, posColor, negColor, ...
                'Polarity','bi', ...
                'Title','Feature network (correlations)', ...
                'ColorbarLabel','Correlation (signed)', ...
                'KPerNode',K_PER_NODE, 'MaxGlobal',MAX_GLOBAL, 'Gamma',GAMMA);

            case NetworkCorrMatStr{2}  % -log10 p-values
              [~, handles.pgy] = nm_plot_feature_network(yy, feats, posColor, negColor, ...
                'Polarity','uni', ...
                'Title','Feature network (-log_{10} p)', ...
                'ColorbarLabel','-log_{10}(p)', ...
                'KPerNode',K_PER_NODE, 'MaxGlobal',MAX_GLOBAL);


            case NetworkCorrMatStr{3}  % FDR p-values (
               [~, handles.pgy] = nm_plot_feature_network(yy, feats, posColor, negColor, ...
                    'Polarity','uni', ...
                    'Title','Feature network (-log_{10} q, FDR)', ...
                    'ColorbarLabel','-log_{10}(q)', ...
                    'KPerNode',K_PER_NODE, 'MaxGlobal',MAX_GLOBAL);
         end
         
    otherwise 
        cb = findobj(handles.axes33.Parent, 'Type', 'ColorBar', 'Axes', handles.axes33);
        delete(cb)
        ind = get_sort_index(y(:,selC), sortfl);     % sort by y according to drop-down
        y   = y(ind,selC);  y = y(featind);
        % enable/disable color pickers based on sign content
        btnPos = findobj(hFig,'Tag','btnPosColor');
        btnNeg = findobj(hFig,'Tag','btnNegColor');
        if ~isempty(btnPos), set(btnPos,'Enable', ternary(any(y>0),'on','off'), 'BackgroundColor', posColor); end
        if ~isempty(btnNeg), set(btnNeg,'Enable', ternary(any(y<0),'on','off'), 'BackgroundColor', negColor); end
        if exist('se','var'), se = se(ind); se = se(featind); end

        switch v.params.visflag
            case {0, 3, 4, 5}
                set(handles.pn3DView,'Visible','off'); set(handles.axes33,'Visible','on'); 
                cla
                colorbar('Visible','off')
                handles.axes33.XLimMode = 'auto';
                handles.axes33.XTickLabelMode = 'auto';
                handles.axes33.XTickLabelRotation=0;
                hold on
                % Build a significance mask using existing vlineval logic
                if ~isempty(vlineval)
                    y2 = y; 
                    if numel(vlineval)>1
                        y2(y>vlineval(1) & y<vlineval(2)) = NaN; 
                    else
                        y2(y < vlineval) = NaN; 
                    end
                    sigMask = isfinite(y2);   % true = highlighted bar
                else
                    sigMask = true(size(y));
                end
                
                if sortfl == 6 || sortfl == 7, absFlag = true; else, absFlag = false; end

                % Value-scaled, sign-aware colored bars (red=pos, blue=neg)
                % pass colors into plotter
                plot_scaled_barh(handles.axes33, x, y, ...
                    'SigMask', sigMask, 'absFlag', absFlag, ...
                    'PosColor', posColor, 'NegColor', negColor);

                if exist('se','var')
                    if absFlag
                        ydraw = abs(y);
                    else
                        ydraw = y;
                    end
                    h = herrorbar(ydraw, x, se, se,'ko');
                    set(h,'MarkerSize',0.001);
                end

                if ~isempty(vlineval) 
                    for o=1:numel(vlineval)
                        xline(vlineval(o),'LineWidth',1.5, 'Color', 'red');
                    end
                end
                xlabel(meas{measind},'FontWeight','bold');
                ylabel('Features','FontWeight','bold');
                set(gca,'YTick',x);
                if ~isempty(handles.txtAlterFeats.String)
                    altfeatsvar = handles.txtAlterFeats.String;
                    tfeats = evalin('base',altfeatsvar);
                    if isempty(tfeats)
                        warndlg(sprintf('Could not find the alternative feature vector ''%s'' in the MATLAB workspace!', altfeatsvar))
                        feats = v.params.features;
                    elseif numel(tfeats)~= numel(v.params.features)
                        warndlg(sprintf('The alternative feature vector doesn not have same feature number (n=%g) as the original vector (n=%g)',numel(tfeats),numel(v.params.features))) 
                        feats = v.params.features;
                    elseif ~iscellstr(tfeats) && ~isstring(tfeats)
                        warndlg('The alternative feature vector must be a cell array of strings!'); 
                        feats = v.params.features;
                    else
                        feats = tfeats;
                    end
                else
                    feats = v.params.features;
                end
                
                feats = feats(ind); 
                feats = feats(featind);
                if ~isempty(vlineval)
                    Ix = isnan(y2);
                    featsI = strcat('\color{gray}',feats(Ix));
                    feats(Ix) = featsI;
                end
                if isstring(feats(1))
                    feats = cellfun(@(x) char(strjoin(x, ',')), feats, 'UniformOutput', false);
                end
                feats = regexprep(feats,'_', '\\_');
                handles.axes33.YTickLabel = feats;
                handles.axes33.TickLabelInterpreter = 'tex';
                handles.axes33.YLim = [ x(1)-0.5 x(end)+0.5 ];
                if any(~isfinite([miny maxy]))
                    miny = min(y(isfinite(y))); maxy = max(y(isfinite(y)));
                    warning(sprintf('non-numeric values detect in feature weights (%s)',meas{measind}))
                end

                % --- X-axis limits: include error bars and a small padding ---
                % When absFlag is true, start at 0 and go to max(|y| + se) + pad.
                % Otherwise, span [min(y - se), max(y + se)] with symmetric padding.
                % 1) Gather vectors (handle missing se, NaNs robustly)
                yv  = y(:);
                if exist('se','var') && ~isempty(se)
                    sev = se(:);
                else
                    sev = zeros(size(yv));
                end
                
                % 2) Compute limits
                % --- X-axis limits: include error bars and a small padding on BOTH sides ---
                if absFlag
                    % Absolute view: draw bars at |y| but allow a small negative left margin
                    % so error bars close to zero remain visible.
                    yabs       = abs(yv);
                    rightEdge  = max(yabs + sev, [], 'omitnan');  if ~isfinite(rightEdge), rightEdge = 0; end
                    leftExtent = min(yabs - sev, [], 'omitnan');  if ~isfinite(leftExtent), leftExtent = 0; end
                    % span computed from the range we need to show (may include negative leftExtent)
                    span = max(rightEdge - min(0,leftExtent), eps);
                    pad  = 0.02 * span;                           % ~2% padding
                    left = min(0, leftExtent) - pad;              % allow slight negative to show errorbar caps
                    right = rightEdge + pad;
                    handles.axes33.XLim = [left, right];
                else
                    % Signed view: include both tails with padding
                    left  = min(yv - sev, [], 'omitnan');  if ~isfinite(left),  left  = 0; end
                    right = max(yv + sev, [], 'omitnan');  if ~isfinite(right), right = 0; end
                    span  = max(right - left, eps);
                    pad   = 0.02 * span;
                    handles.axes33.XLim = [left - pad, right + pad];
                end

                handles.axes33.XTickMode='auto';
                if numel(ind) ~= numel(handles.visdata_table(handles.curmodal,handles.curlabel).tbl.ind)
                    act = 'create';
                else
                    act = 'reorder';
                end
                
                ax = handles.axes33;
                ax.Position(2) = .075;

                % 2) Read current inner‐pos & tick‐label insets
                pos = ax.Position;    % [x y w h] of the bar‐area
                ti  = ax.TightInset;  % [L B R T] margins for labels & ticks
                
                % 3) User parameters
                pad       = 0.01;     % 1% padding from container edges
                minInnerW = 0.6;      % never let bar‐area go below 60% of the container
                
                % 4) Decide the inner‐width (w)
                %    — at least minInnerW, never expand beyond current pos(3)
                w = max(minInnerW, pos(3));
                
                % 5) Center the combined box [labels + bars] in [0,1]:
                outerW = w + ti(1) + ti(3);                 % total needed width
                x      = (1 - outerW)/2 + ti(1);           % left‐edge of the bar‐area
                
                pos(3) = w;    % set width
                pos(1) = x;    % set left‐edge
                
                % 6) If the left‐hand labels still overflow, bump right
                if pos(1) < ti(1) + pad
                    pos(1) = ti(1) + pad;
                end
                
                % 7) **Final clamp on the right** so nothing exceeds container
                rightEdge = pos(1) + pos(3) + ti(3);
                if rightEdge > 1 - pad
                    % shrink width so that rightEdge == 1 - pad
                    pos(3) = (1 - pad) - ti(3) - pos(1);
                end
                
                % 8) Write it back
                ax.Position = pos;

                handles.visdata_table(handles.curmodal, handles.curlabel) = create_visdata_tables(v, handles.visdata_table(handles.curmodal, handles.curlabel), ind, act);

            case {1,2}
                % Neuroimaging data view!
                [~,~,ext] = fileparts(v.params.brainmask);
                ext = regexprep(ext,',1','');
                switch ext
                    case '.nii'
                        handles.pn3DView.Visible='on'; handles.axes33.Visible='off'; 
                        nk_WriteVol(y,'temp',2,v.params.brainmask,v.params.badcoords, ...
                            handles.NM.datadescriptor{v.params.varind}.threshval, ...
                            char(handles.NM.datadescriptor{v.params.varind}.threshop));
                        if ~isfield(handles,'niiViewer') || isempty(handles.niiViewer)
                            % first time: create everything and keep the handle
                            handles.niiViewer = overlay_nifti_gui(handles.NM.defs.atlas_path, 'temp.nii', handles.pn3DView, 0.5);
                        else
                            % just update the stats image
                            handles.niiViewer.update('temp.nii');
                        end
                    case {'.mgh','.mgz'}
                    case '.gii'
                        handles.pn3DView.Visible='on'; handles.axes33.Visible='off'; handles.axes27.Visible='off'; handles.axes28.Visible='off';
                        s = GIIread(v.params.brainmask);
                        save(gifti(struct('vertices',double(s.vertices),'faces',double(s.faces),'cdata',y)),'temp.gii');
                        cat_surf_render('Disp','temp.gii');
                end
        end
        legend('off');
end

guidata(handles.figure1, handles);
end

function [y, miny, maxy, vlineval] = CVRatio(v, curclass, multiflag)

if iscell(v.CVRatio)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.CVRatio,[],2),2);
    else
        y = v.CVRatio{curclass}; 
    end
else
    y = v.CVRatio; 
end
vlineval = [-2 2];
miny = min(y); maxy = max(y);
end

function [y, miny, maxy, vlineval] = CVRatio_CV2(v, curclass, multiflag)

if iscell(v.CVRatio_CV2)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.CVRatio_CV2,[],2),2);
    else
        y = v.CVRatio_CV2{curclass};  
    end
else
    y = v.CVRatio_CV2;
end
vlineval = [-2 2];
miny = min(y); maxy = max(y);
end
function [y, miny, maxy, vlineval] = FeatProb(v, curclass, multiflag)

if iscell(v.FeatProb)
    if multiflag
        y = nm_nanmean(v.FeatProb{1},2);
    else
        y = v.FeatProb{1}(:,curclass);  
    end   
else
    y = v.FeatProb;
end
vlineval = 0.5;
miny = 0; maxy = max(y);
end
function [y, miny, maxy, vlineval] = Prob_CV2(v, curclass, multiflag)

if iscell(v.Prob_CV2)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.Prob_CV2,[],2),2);
    else
        y = v.Prob_CV2{curclass};  
    end
else
    y = v.Prob_CV2;
end
vlineval = [-0.5 0.5];
miny = -1; maxy = 1;
end
function [y, miny, maxy, vlineval] = SignBased_CV2(v, curclass, multiflag)

if iscell(v.SignBased_CV2)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.SignedBased_CV2,[],2),2);
    else
        y = v.SignBased_CV2{curclass};
    end
else
    y = v.SignBased_CV2;
end
vlineval= [];
miny = 0; maxy = 1;
end
function [y, miny, maxy, vlineval] = SignBased_CV2_z(v, curclass, multiflag)
if iscell(v.SignBased_CV2_z)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.SignBased_CV2_z,[],2),2);
    else
        y = v.SignBased_CV2_z{curclass};
    end
else
    y = v.SignBased_CV2_z;
end
vlineval= [-2 2];
miny = min(y(:)); maxy = max(y(:));
end
function [y, miny, maxy, vlineval] = SignBased_CV2_p_uncorr(v, curclass, multiflag)

if iscell(v.SignBased_CV2_p_uncorr)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.SignBased_CV2_p_uncorr,[],2),2);
    else
        y = v.SignBased_CV2_p_uncorr{curclass};
    end
else
    y = v.SignBased_CV2_p_uncorr;
end 
miny = 0; maxy = max(y(:));
vlineval = -log10(0.05);
end
function [y, miny, maxy, vlineval] = SignBased_CV2_p_fdr(v, curclass, multiflag)

if iscell(v.SignBased_CV2_p_fdr)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.SignBased_CV2_p_fdr,[],2),2);
    else
        y = v.SignBased_CV2_p_fdr{curclass};
    end
else
    y = v.SignBased_CV2_p_fdr;
end
miny = 0; maxy = max(y(:));
vlineval = -log10(0.05);
end
function [y, miny, maxy, vlineval] = Spearman_CV2(v, curclass, multiflag)

if iscell(v.Spearman_CV2)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.Spearman_CV2,[],2),2);
    else
        y = v.Spearman_CV2{curclass};
    end
else
    y = v.Spearman_CV2;
end
miny = min(y(:)); maxy = max(y(:));
vlineval= [];
end
function [y, miny, maxy, vlineval] = Pearson_CV2(v, curclass, multiflag)

if iscell(v.Pearson_CV2)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.Pearson_CV2,[],2),2);
    else
        y = v.Pearson_CV2{curclass};
    end
else
    y = v.Pearson_CV2;
end
miny = min(y(:)); maxy = max(y(:));
vlineval= [];
end
function [y, se, miny, maxy, vlineval] = Spearman_CV2_p_uncorr(v, curclass, multiflag)

if iscell(v.Spearman_CV2_p_uncorr)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.Spearman_CV2_p_uncorr,[],2),2);
        if isfield (v,'Spearman_CV2_p_uncorr_STD')
            se = nm_nanmean(sqrt(nk_cellcat(v.Spearman_CV2_p_uncorr_STD,[],2)),2);
        end
    else
        y = v.Spearman_CV2_p_uncorr{curclass}; 
        if isfield (v,'Spearman_CV2_p_uncorr_STD')
            se = sqrt(v.Spearman_CV2_p_uncorr_STD{curclass});
        end
    end
else
    y = v.Spearman_CV2_p_uncorr;
    if isfield (v,'Spearman_CV2_p_uncorr_STD')
        se = sqrt(v.Spearman_CV2_p_uncorr_STD);
    end
end
miny = 0; maxy = max(y(:));
vlineval = -log10(0.05);
end
function [y, se, miny, maxy, vlineval] = Pearson_CV2_p_uncorr(v, curclass, multiflag)

if iscell(v.Pearson_CV2_p_uncorr)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.Pearson_CV2_p_uncorr,[],2),2);
        if isfield (v,'Pearson_CV2_p_uncorr_STD')
            se = nm_nanmean(sqrt(nk_cellcat(v.Pearson_CV2_p_uncorr_STD,[],2)),2);
        end
    else
        y = v.Pearson_CV2_p_uncorr{curclass};  
        if isfield (v,'Pearson_CV2_p_uncorr_STD')
            se = sqrt(v.Pearson_CV2_p_uncorr_STD{curclass});
        end
    end
else
    y = v.Pearson_CV2_p_uncorr;
    if isfield (v,'Pearson_CV2_p_uncorr_STD')
        se = sqrt(v.Pearson_CV2_p_uncorr_STD);
    end
end
miny = 0; maxy = max(y(:));
vlineval = -log10(0.05);
end
function [y, miny, maxy, vlineval] = Spearman_CV2_p_fdr(v, curclass, multiflag)
if iscell(v.Spearman_CV2_p_fdr)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.Spearman_CV2_p_fdr,[],2),2);
    else
        y = v.Spearman_CV2_p_fdr{curclass}; 
    end
else
    y = v.Spearman_CV2_p_fdr;
end
miny = 0; maxy = max(y(:));
vlineval = -log10(0.05);
end
function [y, miny, maxy, vlineval] = Pearson_CV2_p_fdr(v, curclass, multiflag)
if iscell(v.Pearson_CV2_p_fdr)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.Pearson_CV2_p_fdr,[],2),2);
    else
        y = v.Pearson_CV2_p_fdr{curclass};  
    end
else
    y = v.Pearson_CV2_p_fdr;
end
miny = 0; maxy = max(y(:));
vlineval = -log10(0.05);
end
function [y, miny, maxy, vlineval] = PermZ_CV2(v, curclass, multiflag)
if iscell(v.PermZ_CV2)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.PermZ_CV2,[],2),2);
    else
        y = v.PermZ_CV2{curclass};  
    end
else
    y = v.PermZ_CV2;
end
miny = min(y(:)); maxy = max(y(:));
vlineval = [];
end
function [y, miny, maxy, vlineval] = PermProb_CV2(v, curclass, multiflag)
if iscell(v.PermProb_CV2)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.PermProb_CV2,[],2),2);
    else
        y = v.PermProb_CV2{curclass};  
    end
else
    y = v.PermProb_CV2;
end
miny = 0; maxy = max(y(:));
vlineval = -log10(0.05);
end
function [y, miny, maxy, vlineval] = PermProb_CV2_FDR(v, curclass, multiflag)
if iscell(v.PermProb_CV2_FDR)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.PermProb_CV2_FDR,[],2),2);
    else
        y = v.PermProb_CV2_FDR{curclass};  
    end
else
    y = v.PermProb_CV2_FDR;
end
miny = 0; maxy = max(y(:));
vlineval = -log10(0.05);
end
function [y, miny, maxy, vlineval] = Analytical_p(v, curclass, multiflag)
if iscell(v.Analytical_p)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.Analytical_p,[],2),2);
    else
        y = v.Analytical_p{curclass};  
    end
else
    y = v.Analytical_p;
end
miny = 0; maxy = max(y(:));
vlineval = -log10(0.05);
end
function [y, miny, maxy, vlineval] = Analyitcal_p_fdr(v, curclass, multiflag)
if iscell(v.Analyitcal_p_fdr)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.Analyitcal_p_fdr,[],2),2);
    else
        y = v.Analyitcal_p_fdr{curclass};  
    end
else
    y = v.Analyitcal_p_fdr;
end
miny = 0; maxy = max(y(:));
vlineval = -log10(0.05);
end
function [y, se, miny, maxy, vlineval] = MEAN(v, curclass, multiflag)
if iscell(v.MEAN)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.MEAN,[],2),2);
        se = nm_nanmean(nk_cellcat(v.SE,[],2),2);
    else
        y = v.MEAN{curclass}; se = v.SE{curclass}; 
    end
else
    y = v.MEAN; se = v.SE; 
end
miny = min(y(:)); maxy = max(y(:));
vlineval = [];
end
function [y, se, miny, maxy, vlineval] = MEAN_CV2(v, curclass, multiflag)
if iscell(v.MEAN_CV2)
    if multiflag
        y = nm_nanmean(nk_cellcat(v.MEAN_CV2,[],2),2);
        se = nm_nanmean(nk_cellcat(v.SE_CV2,[],2),2);
    else
        y = v.MEAN_CV2{curclass}; se = v.SE_CV2{curclass}; 
    end
else
    y = v.MEAN_CV2; se = v.SE_CV2; 
end
miny = min(y(:)); maxy = max(y(:));
vlineval = [];
end
% you keep doing:
%   feats = feats(ind);
%   feats = feats(featind);
% This helper builds `ind` so that feats(featind) shows exactly what you want.

function ind = get_sort_index(vec, mode, featind)
% vec   : column or row vector of weights
% mode  : 1..7 as specified
% featind : positions for cutout (e.g., 1:41). If empty, we assume 1:K where K = numel(vec)

    vec = vec(:);
    n   = numel(vec);
    if nargin < 3 || isempty(featind)
        featind = 1:n;
    end
    % clamp cutout to valid range and compute the largest position we must support
    featind = featind(featind>=1 & featind<=n);
    if isempty(featind), ind = (1:n).'; return; end
    Kmax = max(featind);

    % push non-finites to the end, preserve their relative order
    finiteMask = isfinite(vec);
    idxF = find(finiteMask);
    idxNF = find(~finiteMask);

    % --- base orders ---
    switch mode
        case 1 % original
            base = (1:n).';
            % selected set for “relevance” is N/A; just return
            ind = base;
            return

        case 2 % ascending by value (neg -> pos)
            [~, o] = sort(vec(idxF), 'ascend');     base = [idxF(o); idxNF];

        case 3 % descending by value (pos -> neg)
            [~, o] = sort(vec(idxF), 'descend');    base = [idxF(o); idxNF];

        case {4,6} % absolute ascending (low -> high magnitude)
            [~, o] = sort(abs(vec(idxF)), 'ascend'); base = [idxF(o); idxNF];

        case {5,7} % absolute descending (high -> low magnitude)
            [~, o] = sort(abs(vec(idxF)), 'descend'); base = [idxF(o); idxNF];

        otherwise
            base = (1:n).';
    end

    % --- choose the “relevant” Kmax items per the scenario semantics ---
    switch mode
        case 2 % ascending: we want extremes first (most negative & most positive),
               % but final DISPLAY must remain monotonically ascending.
               % Strategy: take ends toward center until Kmax, then sort that slice ascending.
            ends = interleave_ends(1:n);                % positions in 'base'
            pick_pos = ends(1:Kmax);
            pick_idx = base(pick_pos);                  % original-row indices
            % re-order the picked set to be truly ascending for display
            [~, o2] = sort(vec(pick_idx), 'ascend');
            front = pick_idx(o2);
            rest  = setdiff(base, front, 'stable');
            ind   = [front; rest];

        case 3 % descending: same logic, but final order descending
            ends = interleave_ends(1:n);
            pick_pos = ends(1:Kmax);
            pick_idx = base(pick_pos);
            [~, o2] = sort(vec(pick_idx), 'descend');
            front = pick_idx(o2);
            rest  = setdiff(base, front, 'stable');
            ind   = [front; rest];

        case {4,6} % abs ascending: base is low->high | we STILL want most relevant in cutout
                   % i.e., take from the HIGH end (largest magnitudes) but keep abs-ascending order
            pick_pos = (n-Kmax+1):n;                    % last Kmax positions in base
            pick_idx = base(pick_pos);
            % keep their base order (abs-ascending within the chosen high-magnitude slice)
            front = pick_idx(:);
            rest  = setdiff(base, front, 'stable');
            ind   = [front; rest];

        case {5,7} % abs descending: base already high->low; take first Kmax
            pick_pos = 1:Kmax;
            pick_idx = base(pick_pos);
            front = pick_idx(:);                        % already in desired order
            rest  = setdiff(base, front, 'stable');
            ind   = [front; rest];

        otherwise
            ind = base;
    end
end
% helper: returns [1, n, 2, n-1, 3, n-2, ...] for positions 1..n
function out = interleave_ends(k)
    i = 1; j = numel(k); t = zeros(j,1);
    c = 1;
    while i <= j
        t(c) = k(i); c=c+1; i=i+1;
        if i <= j
            t(c) = k(j); c=c+1; j=j-1;
        end
    end
    out = t;
end
function hb = plot_scaled_barh(ax, pos, y, varargin)
% plot_scaled_barh  Horizontal bar chart with per-bar color scaling by value.
%   Red/Blue colors are user-selectable; intensity scales with |y|.
%   'SigMask' dims non-significant bars to light gray.
%
%   hb = plot_scaled_barh(ax, pos, y, 'SigMask', mask, 'absFlag', tf, ...
%                         'PosColor', [r g b], 'NegColor', [r g b])

    p = inputParser;
    addParameter(p, 'SigMask', true(size(y)), @(m) islogical(m) && numel(m)==numel(y));
    addParameter(p, 'absFlag', false, @(x) isscalar(x) && (islogical(x)||isnumeric(x)));
    addParameter(p, 'PosColor', [0.85 0.15 0.15], @(c) isnumeric(c)&&numel(c)==3);
    addParameter(p, 'NegColor', [0.15 0.35 0.85], @(c) isnumeric(c)&&numel(c)==3);
    parse(p, varargin{:});
    sigMask  = p.Results.SigMask(:);
    absFlag  = logical(p.Results.absFlag);
    posColor = p.Results.PosColor(:)';   % row vec
    negColor = p.Results.NegColor(:)';

    y   = y(:);
    pos = pos(:);

    maxAbs = max(abs(y));
    if isempty(maxAbs) || maxAbs==0
        colors = repmat([0.85 0.85 0.85], numel(y), 1);
    else
        alpha  = abs(y) ./ maxAbs;           % 0..1
        white  = [1 1 1];
        colors = zeros(numel(y),3);
        posIdx = y >= 0;
        colors(posIdx,:)  = white + (posColor - white) .* alpha(posIdx);
        colors(~posIdx,:) = white + (negColor - white) .* alpha(~posIdx);
    end

    if any(~sigMask)
        colors(~sigMask,:) = repmat([0.85 0.85 0.85], sum(~sigMask), 1);
    end

    yDraw = y; if absFlag, yDraw = abs(y); end
    hb = barh(ax, pos, yDraw, 'BarWidth',0.9, ...
        'FaceColor','flat','EdgeColor','none','LineWidth',1);
    hb.CData = colors;
end

function out = ternary(cond, a, b)
% TERNARY  Conditional selection like a ? b : c
%   out = ternary(cond, a, b)
%   - If COND is a logical scalar: returns A if true, else B.
%   - If COND is a logical array: returns elementwise A/B.
%     A or B may be scalars and will be expanded to size(COND).

    if ~islogical(cond)
        error('ternary: cond must be logical.');
    end

    if isscalar(cond)
        if cond, out = a; else, out = b; end
        return;
    end

    % Array case
    sz = size(cond);
    if isscalar(a), a = repmat(a, sz); end
    if isscalar(b), b = repmat(b, sz); end
    if ~isequal(size(a), sz) || ~isequal(size(b), sz)
        error('ternary: sizes of A and B must match COND (or be scalar).');
    end

    out = b;
    out(cond) = a(cond);
end

function [G, pgy, out] = nm_plot_feature_network(M, feats, posColor, negColor, varargin)
%NM_PLOT_FEATURE_NETWORK  Render a feature network from an input metric matrix.
%
% [G,pgy,out] = nm_plot_feature_network(M, feats, posColor, negColor, ...)
%
% Inputs
%   M         : square matrix of edge metrics
%               - Bipolar (signed): correlations in [-1,1]
%               - Unipolar        : magnitudes (e.g., -log10(p) or -log10(q)) >= 0
%   feats     : cellstr or string vector of node labels (length = size(M,1))
%   posColor  : [1x3] RGB for positive edges / high magnitudes
%   negColor  : [1x3] RGB for negative edges (only used in bipolar mode)
%
% Name-Value options (all optional)
%   'Polarity'       : 'auto' | 'bi' | 'uni'   (default 'auto'; auto -> bi if min(M)<0)
%   'Title'          : char title for axes     (default auto by polarity)
%   'ColorbarLabel'  : char label for colorbar (default auto by polarity)
%   'Axes'           : target axes handle      (default = gca)
%   'KPerNode'       : top-k edges per node kept in sparsifier (default 5)
%   'MaxGlobal'      : global cap on edges kept (default 250)
%   'Gamma'          : contrast exponent for color mapping (default 0.8)
%   'Neutral'        : [1x3] RGB center color  (default [0.98 0.98 0.98])
%   'MaxLabels'      : # node labels to show   (default heuristic)
%   'LabelCap'       : max chars before ellipsis (default 38)
%   'WrapAt'         : wrap length per line    (default 18)
%
% Outputs
%   G     : graph object
%   pgy   : GraphPlot handle
%   out   : struct with fields (W, topIdx, deg, keptMatrix, polarity, p99)
%
% Dependencies (helpers in your path or same file):
%   nm_sparsify_topk, nm_top_nodes_by_strength, nm_wrap_ellipsis
%
% Example uses:
%   % Correlation (signed / bipolar)
%   nm_plot_feature_network(R, feats, posColor, negColor, 'Polarity','bi', ...
%                           'Title','Feature network (correlations)', ...
%                           'ColorbarLabel','Correlation (signed)');
%
%   % -log10(p) (unipolar)
%   nm_plot_feature_network(Plog, feats, posColor, negColor, 'Polarity','uni', ...
%                           'Title','Feature network (-log_{10} p)', ...
%                           'ColorbarLabel','-log_{10}(p)');

    % -------- Parse inputs
    p = inputParser;
    addParameter(p,'Polarity','auto');
    addParameter(p,'Title','');
    addParameter(p,'ColorbarLabel','');
    addParameter(p,'Axes',[]);
    addParameter(p,'KPerNode',5);
    addParameter(p,'MaxGlobal',250);
    addParameter(p,'Gamma',0.8);
    addParameter(p,'Neutral',[0.98 0.98 0.98]);
    addParameter(p,'MaxLabels',[]);
    addParameter(p,'LabelCap',20);
    addParameter(p,'WrapAt',18);
    parse(p,varargin{:});
    o = p.Results;

    if isstring(feats), feats = cellstr(feats); end
    feats = feats(:);

    A = double(M);
    A(~isfinite(A)) = 0;
    n = size(A,1);
    if size(A,2) ~= n
        error('nm_plot_feature_network:MatrixNotSquare','M must be square.');
    end
    % Symmetrise and zero diagonal
    A = (A + A.')/2;
    A(1:n+1:end) = 0;

    % Determine polarity
    if strcmpi(o.Polarity,'auto')
        polarity = 'uni';
        if any(A(:) < 0), polarity = 'bi'; end
    else
        polarity = lower(o.Polarity);
    end

    % Defaults for titles/labels
    if isempty(o.Title)
        if strcmp(polarity,'bi'), o.Title = 'Feature network (correlations)'; 
        else, o.Title = 'Feature network'; end
    end
    if isempty(o.ColorbarLabel)
        if strcmp(polarity,'bi'), o.ColorbarLabel = 'Correlation (signed)';
        else, o.ColorbarLabel = 'Magnitude'; end
    end

    % Sparsify to keep it readable
    [Akeep, ~] = nm_sparsify_topk(A, o.KPerNode, o.MaxGlobal);

    % Build graph
    G = graph(Akeep ~= 0);
    if numnodes(G) ~= n
        error('nm_plot_feature_network:GraphBuild','Unexpected node count.');
    end
    E = G.Edges.EndNodes;
    m = size(E,1);
    if m == 0
        ax = ensureAxes(o.Axes);
        axes(ax); cla(ax);
        title(ax, [o.Title ' (no edges kept)']);
        pgy = [];
        out = struct('W',[], 'topIdx',[], 'deg',[], 'keptMatrix',Akeep, ...
                     'polarity',polarity, 'p99',[]);
        return;
    end

    % Edge weights vector aligned to G.Edges
    W = arrayfun(@(k) Akeep(E(k,1), E(k,2)), 1:m).';
    G.Edges.Weight = W;

    % Target axes & plot
    ax = ensureAxes(o.Axes);
    axes(ax); 
    pgy = plot(G, 'Layout','force', 'UseGravity',true, 'Iterations',80);
    axis(ax,'off');
    %title(ax, o.Title, 'FontWeight','bold');

    % Node size by degree
    deg = degree(G);
    pgy.MarkerSize = 4 + 6*rescale(deg,0,1);

    % Label selection (top-K by strength)
    nN = numnodes(G);
    if isempty(o.MaxLabels)
        Klabels = min(40, max(12, round(280/sqrt(nN))));
    else
        Klabels = max(0, o.MaxLabels);
    end
    topIdx = nm_top_nodes_by_strength(G, W, Klabels);

    shortLabs = repmat({''}, nN, 1);
    shortLabs(topIdx) = nm_wrap_ellipsis(feats(topIdx), o.LabelCap, o.WrapAt);
    shortLabs = cellfun(@char, shortLabs, 'UniformOutput', false);
    pgy.NodeLabel = shortLabs;
    pgy.NodeLabelColor = [0.1 0.1 0.1];
    pgy.NodeFontSize   = 9;
    pgy.NodeColor      = [0.15 0.15 0.15];

    % Datatips (full labels + node index)
    enableDatatips(ax, pgy, feats);

    % Edge styling by polarity
    p99Var = [];   % holds the 99th-percentile scale for unipolar plots

    switch polarity
        case 'bi'   % bipolar signed (e.g., correlations)
            signedMag = sign(W) .* abs(W).^o.Gamma;  % in [-1,1]
            pgy.EdgeCData = signedMag;
            pgy.EdgeColor = 'flat';
            clim(ax,[-1 1]);

            % Diverging colormap: negColor -> neutral -> posColor
            N  = 256; n2 = N/2;
            neutral = o.Neutral;
            negGrad = [linspace(negColor(1),neutral(1),n2)', ...
                       linspace(negColor(2),neutral(2),n2)', ...
                       linspace(negColor(3),neutral(3),n2)'];
            posGrad = [linspace(neutral(1),posColor(1),n2)', ...
                       linspace(neutral(2),posColor(2),n2)', ...
                       linspace(neutral(3),posColor(3),n2)'];
            colormap(ax,[negGrad; posGrad]);

            pgy.LineWidth = 0.5 + 4*abs(W);
            pgy.EdgeAlpha = 0.6;

        case 'uni'  % unipolar magnitude (e.g., -log10 p / q)
            mag = max(0, W);                 % ensure nonnegative
            p99 = max(eps, prctile(mag, 99));
            p99Var = p99;
            pgy.EdgeCData = mag;
            pgy.EdgeColor = 'flat';
            clim(ax,[0 p99]);

            % Neutral -> posColor ramp
            N  = 256; neutral = o.Neutral;
            posGrad = [linspace(neutral(1),posColor(1),N)', ...
                       linspace(neutral(2),posColor(2),N)', ...
                       linspace(neutral(3),posColor(3),N)'];
            colormap(ax, posGrad);

            pgy.LineWidth = 0.5 + 3.5*min(1, mag./p99);
            pgy.EdgeAlpha = 0.6;
    end

    % Colorbar on the left (westoutside)
    cb = colorbar(ax,'Location','westoutside');
    ylabel(cb, o.ColorbarLabel);
    cb.FontSize = 10;

    % Outputs
    out = struct('W',W, 'topIdx',topIdx, 'deg',deg, ...
             'keptMatrix',Akeep, 'polarity',polarity, ...
             'p99', p99Var);
end

% ---------- helpers (local) ----------
function ax = ensureAxes(ax)
    if isempty(ax) || ~isvalid(ax), ax = gca; end
end

function enableDatatips(ax, pgy, feats)
% Robust datatip setup for GraphPlot across MATLAB versions (no .Graph needed)

    % Ensure features vector matches node count
    nN = numel(pgy.XData);                % # nodes from plot data
    if isstring(feats), feats = cellstr(feats); end
    feats = feats(:);
    if numel(feats) ~= nN
        % pad/truncate defensively
        F = repmat({''}, nN, 1);
        F(1:min(nN,numel(feats))) = feats(1:min(nN,numel(feats)));
        feats = F;
    end

    % Make the plot pickable (required for datatips in some versions)
    set(pgy, 'HitTest','on', 'PickableParts','all');

    % Turn on datatip interaction
    fig = ancestor(ax,'figure');
    if ~isa(ax,'matlab.ui.control.UIAxes')
        dcm = datacursormode(fig);
        dcm.Enable = 'on';
    else
        ax.Interactions = [datatipInteraction panInteraction zoomInteraction];
    end

    % Define the datatip template (replace in one shot)
    try
        dt = pgy.DataTipTemplate;
        r1 = dataTipTextRow('Feature', feats);          % full label
        r2 = dataTipTextRow('Node', (1:nN)');           % node index
        dt.DataTipRows = [r1 r2];
    catch
        % Older MATLAB without DataTipTemplate/dataTipTextRow:
        % gently skip custom template; datatips will still show default info.
    end
end

function z = iif(cond, a, b)
    if cond, z = a; else, z = b; end
end

function [Ysym, keepMask] = nm_sparsify_topk(A, kPerNode, maxGlobal)
%NM_SPARSIFY_TOPK  Keep strongest edges for readability in graph plots.
%
%   [Ysym, keepMask] = nm_sparsify_topk(A, kPerNode, maxGlobal)
%
%   Inputs
%     A          : square numeric matrix (adjacency/weights). Diagonal is ignored.
%     kPerNode   : keep up to k strongest (by absolute value) incident edges per node.
%     maxGlobal  : also keep the top |weight| edges globally (union with per-node set).
%
%   Outputs
%     Ysym       : symmetric matrix with only the selected edges; diagonal = 0.
%     keepMask   : logical mask over the edge list from triu(A,1) indicating kept edges.
%
%   Notes
%     - NaN/Inf are treated as 0 (dropped).
%     - If kPerNode or maxGlobal is empty/Inf/<=0, that criterion is ignored.
%     - Returns a dense matrix to match typical code paths that expect full.
%
%   Example
%     [Ysym, keep] = nm_sparsify_topk(corrMat, 5, 250);

    arguments
        A {mustBeNumeric, mustBeNonempty}
        kPerNode (1,1) double = 5
        maxGlobal (1,1) double = 250
    end

    % Sanity & cleanup
    A = double(A);
    A(~isfinite(A)) = 0;
    n = size(A,1);
    if size(A,2) ~= n
        error('nm_sparsify_topk:InputNotSquare', 'A must be square.');
    end

    % Zero diagonal and use upper triangle edge list
    A(1:n+1:end) = 0;
    [ii, jj, vv] = find(triu(A, 1));
    m = numel(vv);
    keepMask = false(m,1);

    if m == 0
        Ysym = zeros(n);
        return;
    end

    % Normalize parameters
    usePerNode  = ~(isempty(kPerNode)  || ~isfinite(kPerNode)  || kPerNode  <= 0);
    useGlobal   = ~(isempty(maxGlobal) || ~isfinite(maxGlobal) || maxGlobal <= 0);

    % --- Per-node top-k by |weight|
    if usePerNode
        absV = abs(vv);
        % Build adjacency incidence lists once
        for u = 1:n
            idxU = (ii == u) | (jj == u);
            if any(idxU)
                inds = find(idxU);
                % sort by magnitude desc and keep top-k
                [~, ord] = sort(absV(inds), 'descend');
                k = min(kPerNode, numel(inds));
                keepMask(inds(ord(1:k))) = true;
            end
        end
    end

    % --- Global cap (union)
    if useGlobal
        [~, ordAll] = sort(abs(vv), 'descend');
        keepMask(ordAll(1:min(maxGlobal, m))) = true;
    end

    % Construct symmetric sparsified matrix
    As = sparse(ii(keepMask), jj(keepMask), vv(keepMask), n, n);
    Ysym = As + As.';        % symmetric, zero diagonal preserved
    Ysym = full(Ysym);       % return full to play nicely with downstream code
end

function S = nm_wrap_ellipsis(strs, maxChars, wrapAt)
% Return a cell array of CHAR labels, truncated and softly wrapped with '\n'.
    if isstring(strs), strs = cellstr(strs); end
    if ischar(strs),   strs = cellstr(strs); end
    S = cell(size(strs));
    for i = 1:numel(strs)
        s = char(strs{i});
        if numel(s) > maxChars
            s = [s(1:maxChars-3) '...'];
        end
        if wrapAt > 0 && numel(s) > wrapAt
            out = '';
            k = 1;
            while k <= numel(s)
                j = min(k+wrapAt-1, numel(s));
                seg = s(k:j);
                sp  = find(seg==' ', 1, 'last');
                if ~isempty(sp) && (k+sp-1) < j
                    j = k+sp-1;
                end
                out = [out s(k:j) newline]; %#ok<AGROW>
                k = j+1;
            end
            s = strtrim(out);
        end
        S{i} = s;
    end
end

function idx = nm_top_nodes_by_strength(G, edgeWeight, K)
% Top-K nodes by sum of |edge weights| on incident edges.
% edgeWeight can be:
%   (a) vector: length == height(G.Edges)
%   (b) square matrix: symmetric weights, diag ignored

    n  = numnodes(G);
    E  = G.Edges.EndNodes;               % [m x 2]
    m  = size(E,1);

    % --- get edge weights aligned to G.Edges rows
    if isvector(edgeWeight) && numel(edgeWeight) == m
        w = edgeWeight(:);
    elseif ismatrix(edgeWeight) && size(edgeWeight,1) == size(edgeWeight,2)
        M = double(edgeWeight);
        M(~isfinite(M)) = 0;
        % pull weights per edge (i,j) from the matrix
        w = arrayfun(@(r) M(E(r,1), E(r,2)), 1:m).';
    elseif ismember('Weight', G.Edges.Properties.VariableNames)
        % fallback: use any Weight column already on the graph
        w = G.Edges.Weight(:);
    else
        % last resort: unweighted
        w = ones(m,1);
    end

    w(~isfinite(w)) = 0;
    w = abs(w);

    % --- node strength = sum of incident |weights|
    score = accumarray(E(:), repmat(w,2,1), [n 1], @sum, 0);

    % --- top-K nodes
    [~,ord] = sort(score,'descend');
    idx = ord(1:min(K,numel(ord)));
end

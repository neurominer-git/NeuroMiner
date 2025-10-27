function handles = load_selVisMeasDropDown(handles)
% Build the measurement dropdown for the current modality (no repopulation on click)

% Multi-group branch unchanged
isMulti = strcmp(handles.popupmenu1.String{handles.popupmenu1.Value}, 'Multi-group classifier');

if ~isMulti
    if handles.curmodal <= size(handles.visdata,1)
        v = handles.visdata{handles.curmodal, handles.curlabel};
        L = {};

        if isfield(v,'CVRnorm')
            CVRnorm_opts = {'(SD-based) ', '(SEM-based) '};
            CVRnormStr   = CVRnorm_opts{v.CVRnorm};
        else
            CVRnormStr   = '';
        end

        if isfield(v,'MEAN'),                   L{end+1} = 'Feature weights [Overall Mean (StErr)]';                       end
        if isfield(v,'MEAN_CV2'),               L{end+1} = 'Feature weights [CV2 Mean (StErr)]';                           end
        if isfield(v,'CVRatio'),                L{end+1} = sprintf('CVR %sof feature weights [Overall Mean]', CVRnormStr); end
        if isfield(v,'FeatProb'),               L{end+1} = 'Feature selection probability [Overall Mean]';                  end
        if isfield(v,'Prob_CV2'),               L{end+1} = 'Probability of feature reliability (95%-CI) [CV2 Mean]';       end
        if isfield(v,'SignBased_CV2'),          L{end+1} = 'Sign-based consistency';                                        end
        if isfield(v,'SignBased_CV2_z'),        L{end+1} = 'Sign-based consistency (Z score)';                              end
        if isfield(v,'SignBased_CV2_p_uncorr'), L{end+1} = 'Sign-based consistency -log10(P value)';                        end
        if isfield(v,'SignBased_CV2_p_fdr'),    L{end+1} = 'Sign-based consistency -log10(P value, FDR)';                   end
        if isfield(v,'Spearman_CV2'),           L{end+1} = 'Spearman correlation [CV2 Mean]';                               end
        if isfield(v,'Pearson_CV2'),            L{end+1} = 'Pearson correlation [CV2 Mean]';                                end
        if isfield(v,'Spearman_CV2_p_uncorr'),  L{end+1} = 'Spearman correlation -log10(P value) [CV2 Mean]';               end
        if isfield(v,'Pearson_CV2_p_uncorr'),   L{end+1} = 'Pearson correlation -log10(P value) [CV2 Mean]';                end
        if isfield(v,'Spearman_CV2_p_fdr'),     L{end+1} = 'Spearman correlation -log10(P value, FDR) [CV2 Mean]';          end
        if isfield(v,'Pearson_CV2_p_fdr'),      L{end+1} = 'Pearson correlation -log10(P value, FDR) [CV2 Mean]';           end
        if isfield(v,'PermProb_CV2'),           L{end+1} = 'Permutation-based -log10(P value) [CV2 Mean]';                  end
        if isfield(v,'PermProb_CV2_FDR'),       L{end+1} = 'Permutation-based -log10(P value, FDR) [CV2 Mean]';             end
        if isfield(v,'PermZ_CV2'),              L{end+1} = 'Permutation-based Z Score [CV2 Mean]';                          end
        if isfield(v,'Analytical_p'),           L{end+1} = 'Analytical -log10(P Value) for Linear SVM [CV2 Mean]';          end
        if isfield(v,'Analyitcal_p_fdr'),       L{end+1} = 'Analytical -log10(P Value, FDR) for Linear SVM [CV2 Mean]';     end
        if isfield(v,'PermModel_Eval_Global'),  L{end+1} = 'Model P value histogram';                                       end
        if isfield(v,'ExtraL')
            for i = 1:numel(v.ExtraL)
                L{end+1} = sprintf('Generalization analysis for extra label ''%s'' [#%g]', v.ExtraL(i).LABEL_NAME, i);
            end
        end
        if isfield(v,'CorrMat_CV2'),               L{end+1} = 'Correlation matrix';                                         end
        if isfield(v,'CorrMat_CV2_p_uncorr'),      L{end+1} = 'Correlation matrix (P value)';                               end
        if isfield(v,'CorrMat_CV2_p_fdr'),         L{end+1} = 'Correlation matrix (P value, FDR)';                          end
        if isfield(v,'CorrMat_CV2'),               L{end+1} = 'Network plot correlation matrix';                             end
        if isfield(v,'CorrMat_CV2_p_uncorr'),      L{end+1} = 'Network plot correlation matrix (P value)';                   end
        if isfield(v,'CorrMat_CV2_p_fdr'),         L{end+1} = 'Network plot correlation matrix (P value, FDR)';              end

        handles.selVisMeas.String = L;
        VisOnFl = 'on';  VisElFl = 'on';
    else
        VisOnFl = 'off'; VisElFl = 'off';
        handles.curmodal = size(handles.visdata,1);
    end

else
    % multi-group branch
    v = handles.visdata{handles.curmodal,handles.curlabel};
    if isfield(v,'ObsModel_Eval_Global_Multi')
        handles.selVisMeas.Enable = 'on';
        L = {'Model P value histogram [Multi-group]'};
        for i = 1:numel(v.ObsModel_Eval_Global_Multi_Bin)
            L{end+1} = sprintf('Model P value histogram [Class %s vs. Rest]', handles.NM.groupnames{i});
        end
        handles.selVisMeas.String = L;
        VisOnFl = 'on';  VisElFl = 'off';
    else
        VisOnFl = 'on';  VisElFl = 'on';
    end
end

% Enable/disable related controls
handles.selVisMeas.Enable = VisOnFl;
switch handles.params.TrainParam.FUSION.flag
    case 3
        handles.selModality.Enable = 'off';
    otherwise
        handles.selModality.Enable = VisElFl;
end
handles.selPager.Enable       = VisElFl;
handles.tglSortFeat.Enable    = VisElFl;
handles.cmdExportFeats.Enable = VisElFl;

end
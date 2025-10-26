function handles = sel_onevsone(handles, hObject)

rowind = get(hObject,'Value');

switch rowind
    case 1
        %% Display ROC
        [handles.hroc, handles.hroc_random] = display_roc(handles, handles.MultiClass.onevsall_labels, handles.MultiClass.onevsall_scores);
        %% Display Cobweb
        [handles.hspider, handles.MultiClass.misclass_confusion, handles.MultiClass.spideraxes] = nk_PlotCobWeb(handles.MultiClass.confusion_matrix, handles.NM.groupnames, handles.axes5);
        cla(handles.axes4);title(handles.axes4,{''});
        cla(handles.axes3);title(handles.axes3,{''});
        handles.selOneVsAll_Info.Visible = 'on';
        handles.txtPretestProb.Visible = 'off';
        handles.cmdExportPies.Visible = 'off';
        handles.cmdExportCobWeb.Visible = 'on';
        handles.cmdMetricExport.Visible = 'off';
        handles.tblPerf.Visible = 'off';
        handles.one_vs_rest = false;
        set([handles.tglSort, handles.tglClrSwp, handles.cmdPerfDCA, handles.cmdCalib], Enable='off');
        
    otherwise
       
        if isfield(handles,'hspider'),handles.hspider.Title.Visible='off'; end
        handles.cmdExportPies.Visible = 'on';
        handles.cmdMetricExport.Visible = 'on';
        handles.cmdExportCobWeb.Visible = 'off';
        handles.tblPerf.Visible = 'on';
        
        %% Display ROC
        legend off 
        [handles.hroc, handles.hroc_random] = display_roc(handles, handles.MultiClass.onevsall_labels(:,rowind-1), handles.MultiClass.onevsall_scores(:,rowind-1));
        
        %% Display contingency info
        handles.h_contiginfo = display_contigmat(handles);
        
        %% Display pie charts
        [handles.h1pie, handles.h2pie] = display_piecharts(handles);
        handles.one_vs_rest = true;
        set([handles.tglSort, handles.tglClrSwp, handles.cmdPerfDCA, handles.cmdCalib], Enable='on');
end
%% Display confusion matrix
handles.h_contig = display_contigplot(handles);
drawnow;
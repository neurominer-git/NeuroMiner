function set_visibility(handles)

if ~handles.NM.analysis{handles.curranal}.status || (sum(handles.MLparams.NumParamCombs) <= handles.nclass && ~isfield(handles,'visdata'))
    vis = 'off';
else
    vis = 'on';
end

set(handles.pnModelPerf,'Visible',vis);
set(handles.selModelMeasures,'Enable',vis);

switch handles.modeflag
    case 'classification'
         set(handles.popupmenu1,'Enable','on')
         set(handles.txtBinarize,'Enable','off');
         set(handles.selOneVsAll_Info,'Enable','off');
         set(handles.pnBinary,'Title','Classification performance');
         set(handles.tglSort,'Enable','on');
         set(handles.txtPretestProb,'Enable','on');
         set(handles.tglClrSwp,'Enable','on');
         if ~isfield(handles,'params') || (isfield(handles,'params') && handles.params.probflag)
            handles.tglP.Enable = 'off';
            handles.tglP.Value = 0;
         else
            handles.tglP.Enable = 'on';
         end
         set(handles.tglPercRank,'Enable','on');
         set(handles.cmdCalib,'Enable','on');
         set(handles.cmdPerfDCA,'Enable','on');

    case 'regression'
         set(handles.popupmenu1,'Enable','off')
         set(handles.txtBinarize,'Enable','on');
         set(handles.selOneVsAll_Info,'Enable','off');
         set(handles.pnBinary,'Title','Regression performance');
         set(handles.txtPretestProb,'Enable','off');
         set(handles.tglSort,'Enable','off');
         set(handles.tglClrSwp,'Enable','off');
         set(handles.tglP,'Enable','off');
         set(handles.tglPercRank,'Enable','off');
         set(handles.cmdCalib,'Enable','off');
         set(handles.cmdPerfDCA,'Enable','off');
end

if handles.multilabel
    set(handles.selLabel,'Enable','on');
else
    set(handles.selLabel,'Enable','off');
end

% Save DATA in Figure1 handles
guidata(handles.figure1,handles)
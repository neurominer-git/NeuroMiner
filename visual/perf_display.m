function handles = perf_display(handles)

% Set current analysis
analind = get(handles.selAnalysis,'Value');

% Set one-vs-rest flag for multi-class analyses, if any
handles.one_vs_rest = false;

if analind > numel(handles.NM.analysis), analind = 1; handles.selAnalysis.Value = 1; end
if isempty(analind), analind = 1; end
if ~isfield(handles,'modeflag')
    % set alternative label
    if isfield(handles.NM.analysis{1,analind}.params,'label')
        handles.label = handles.NM.analysis{1,analind}.params.label.label;
        handles.modeflag = handles.NM.analysis{1,analind}.params.label.modeflag;
    else
        handles.label = handles.NM.label;
        handles.modeflag = handles.NM.modeflag;
    end
end
if ~isfield(handles,'curranal')
    handles.curranal = 1; 
end

handles.prevanal = handles.curranal;
handles.curranal = analind;

if ~handles.NM.analysis{analind}.status || ~isfield(handles.NM.analysis{analind},'GDdims')
    set_visibility(handles)
    set_panel_visibility(handles,'off');
    return; 
end

% Set current modality
% Set multi-modal flag
if numel(handles.NM.analysis{analind}.GDdims)>1
    handles.multi_modal = 1;
    set(handles.selModal,'Enable','on')
    load_modal(handles, handles.NM.analysis{analind}.GDdims);
    if isfield(handles.NM.analysis{analind},'META')
       popuplist = handles.selModal.String;
       popuplist{end+1}='Bagged predictor';
       handles.selModal.String = popuplist;
    end
else
    handles.multi_modal = 0;
    set(handles.selModal,'Enable','off')  
end

if isfield(handles,'multilabel') && handles.multilabel
    if isfield(handles.NM.analysis{analind}.params.TrainParam,'MULTILABEL')
        if isfield(handles,'curlabel') && handles.curlabel > numel(handles.NM.analysis{handles.curranal}.params.TrainParam.MULTILABEL.sel)
            handles.selLabel.Value = 1;
        end
        handles.selLabel.String = handles.NM.labelnames(handles.NM.analysis{handles.curranal}.params.TrainParam.MULTILABEL.sel);
        handles.curlabel = handles.NM.analysis{handles.curranal}.params.TrainParam.MULTILABEL.sel(get(handles.selLabel,'Value'));
    else
        handles.selLabel.String = handles.NM.labelnames;
        handles.curlabel= get(handles.selLabel,'Value');
    end
end

[handles, visdata] = switch_analysis(handles);

if strcmp(handles.modeflag,'regression')
    handles.txtBinarize.String = '';
end

if isfield(handles,'MLIapp') && ~isfield(handles.NM.analysis{analind},'MLI') && ~isempty(handles.MLIapp) && handles.MLIapp~=0
    handles.MLIapp.delete;
    handles = rmfield(handles,'MLIapp');
elseif isfield(handles,'MLIapp') && handles.MLIapp~=0 && isfield(handles.NM.analysis{analind},'MLI') && ishandle(handles.MLIapp)
    updateFcn(handles.MLIapp,handles);
end

%% This is the part where control contents are adapted
handles.lbStartup.String = 'Customize menus ...';
% Set the visibilities of the panels
set_panel_visibility(handles,'on')
% Set the visibility of controls according to whether we deal with a
% classification or regression analysis
set_visibility(handles)
% Set the drop down list of the classification plot selector
load_selYAxis(handles)
% Set the drop down list of the model selector
load_popupmenu1(handles)
% Set the drop down list of the NM result view selector (classification plot panel,
% optimization view panel, visualization view panel, etc)
load_selModelMeasures(handles)
% Set drop down list of the parameter selector in the optimization view
% panel
load_selSubParams(handles)

% Define the contents of the visualization view panel controls
if ~isempty(visdata)
    % Set the drop-down of the CV2 feature metrics.
    load_ModalityDropDown(handles);
    % Set the drop-down list of the component selector (for
    % dimensionality-reduction based analyses)
    if ~isfield(handles,'curclass'), handles.curclass = 1; end
    load_selComponents(handles.selComponent, visdata{handles.curmodal}, handles.curclass);
    % Set the feature pager drop-down list
    load_selPager(handles); 
else
    handles.selModelMeasures.Value = 1;
end

if isfield(handles,'MultiClass'), load_selOneVsAll_Info(handles); end
handles = display_main(handles);






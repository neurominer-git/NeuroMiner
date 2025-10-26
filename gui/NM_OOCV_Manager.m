function varargout = NM_OOCV_Manager(varargin)
% NM_OOCV_MANAGER MATLAB code for NM_OOCV_Manager.fig
%      NM_OOCV_MANAGER by itself, creates a new NM_OOCV_MANAGER or raises the
%      existing singleton*.
%
%      H = NM_OOCV_MANAGER returns the handle to a new NM_OOCV_MANAGER or the handle to
%      the existing singleton*.
%
%      NM_OOCV_MANAGER('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in NM_OOCV_MANAGER.M with the given input arguments.
%
%      NM_OOCV_MANAGER('Property','Value',...) creates a new NM_OOCV_MANAGER or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before NM_OOCV_Manager_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to NM_OOCV_Manager_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES
% Edit the above text to modify the response to help NM_OOCV_Manager
% Last Modified by GUIDE v2.5 26-May-2025 11:40:51
% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @NM_OOCV_Manager_OpeningFcn, ...
                   'gui_OutputFcn',  @NM_OOCV_Manager_OutputFcn, ...
                   'gui_LayoutFcn',  @NM_OOCV_Manager_LayoutFcn, ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end
if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT
% --- Executes just before NM_OOCV_Manager is made visible.
function NM_OOCV_Manager_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to NM_OOCV_Manager (see VARARGIN)
% Choose default command line output for NM_OOCV_Manager
handles.output = [];
% Update handles structure
guidata(hObject, handles);
% Insert custom Title and Text if specified by the user
% Hint: when choosing keywords, be sure they are not easily confused
% with existing figure properties.  See the output of set(figure) for
% a list of figure properties.
if(nargin > 3)
    for index = 1:2:(nargin-3)
        if nargin-3==index, break, end
        switch lower(varargin{index})
             case 'title'
                set(hObject, 'Name', varargin{index+1});
             case 'list'
                 if ~isempty(varargin{index+1})
                    for i=1:numel(varargin{index+1})
                        handles.Data.Items{i} = varargin{index+1}{i};
                    end
                 else
                    handles.Data.Items=[];
                 end
                 guidata(handles.figure1,handles);
                 print_dataitems(handles)
              case 'mode'
                 switch varargin{index+1}
                     case 'select'
                         bt_str = 'Select dataset'; vis_str = 'off';
                         set(handles.lstData,'Position',[0.034 0.05 0.93 0.82]);
                         handles.mode = 0;
                     case 'modify'
                         bt_str = 'Add/Modify Data in Dataset'; vis_str = 'on';
                         set(handles.lstData,'Position',[0.034 0.17 0.93 0.70]);
                         handles.mode = 1;
                 end
                 set(handles.cmdSelect,'String',bt_str);
                 set(handles.cmdDelete,'Visible',vis_str);
                 set(handles.txtNewData,'Visible',vis_str);
                 set(handles.cmdCreateNew,'Visible',vis_str);
                 set(handles.chkLabelKnown,'Visible',vis_str);
                 set(handles.chkCalibrationDataAvail,'Visible',vis_str);
                 set(handles.cmdSave,'Visible',vis_str);
            case 'multiselection'
                switch varargin{index+1}
                    case 0
                        set(handles.lstData,'Max', 1,'Min',0);
                    case 1
                        set(handles.lstData,'Max', numel(handles.Data.Items),'Min',0);
                end
        end
    end
end
% Determine the position of the dialog - centered on the callback figure
% if available, else, centered on the screen

% Store original units and position
OldUnits = get(hObject, 'Units');
set(hObject, 'Units', 'pixels');

% --- Screen size adjustment for MATLAB Online ---
isMatlabOnline = strcmp(getenv('MW_DDUX_APP_NAME'), 'MATLAB_ONLINE');

if isMatlabOnline
    ScreenUnits = get(0, 'Units');
    set(0, 'Units', 'pixels');
    sz = get(0, 'ScreenSize'); % Get screen size in pixels
    set(0, 'Units', ScreenUnits);
    
    % Manually set a fixed size and center the window.
    manual_width = 1200;
    manual_height = 800;
    
    % Ensure the window is not larger than the screen
    manual_width = min(manual_width, sz(3) - 20);
    manual_height = min(manual_height, sz(4) - 40);
    
    pos_x = max( (sz(3) - manual_width) / 2, 1);
    pos_y = max( (sz(4) - manual_height) / 2, 1);
    fig_pos = [pos_x, pos_y, manual_width, manual_height];
    
    set(hObject, 'Position', fig_pos);
else
    % --- Original Desktop Logic ---
    % Get default figure position
    FigPos = get(0, 'DefaultFigurePosition');
    OldPos = get(hObject, 'Position'); % Keep for consistency
    
    % Get screen size in pixels
    if isempty(gcbf)
        ScreenUnits = get(0, 'Units');
        set(0, 'Units', 'pixels');
        ScreenSize = get(0, 'ScreenSize');  % [left bottom width height]
        set(0, 'Units', ScreenUnits);
        
        % Desired width and height: 2/3 of width, 1/3 of height
        FigWidth = round(2/3 * ScreenSize(3));
        FigHeight = round(1/3 * ScreenSize(4));
        
        % Center horizontally and place vertically around 2/3 up the screen
        FigPos(1) = (ScreenSize(3) - FigWidth) / 2;
        FigPos(2) = (ScreenSize(4) - FigHeight) / 2;
    else
        GCBFOldUnits = get(gcbf, 'Units');
        set(gcbf, 'Units', 'pixels');
        GCBFPos = get(gcbf, 'Position');
        set(gcbf, 'Units', GCBFOldUnits);
        
        FigWidth = round(2/3 * GCBFPos(3));
        FigHeight = round(1/3 * GCBFPos(4));
        
        FigPos(1:2) = [(GCBFPos(1) + GCBFPos(3)/2 - FigWidth/2), ...
                       (GCBFPos(2) + GCBFPos(4)/2 - FigHeight/2)];
    end
    % Set width and height
    FigPos(3:4) = [FigWidth, FigHeight];
    % Apply the new position
    set(hObject, 'Position', FigPos);
end

% Restore original units
set(hObject, 'Units', OldUnits);
% Make the GUI modal
set(handles.figure1,'WindowStyle','modal')
% UIWAIT makes NM_OOCV_Manager wait for user response (see UIRESUME)
uiwait(handles.figure1);
% --- Outputs from this function are returned to the command line.
function varargout = NM_OOCV_Manager_OutputFcn(hObject, eventdata, handles)
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% Get default command line output from handles structure
varargout{1} = handles.output;
% The figure can be deleted now
delete(handles.figure1);
% --- Executes on button press in cmdSelect.
function cmdSelect_Callback(hObject, eventdata, handles)
% hObject    handle to cmdSelect (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.Data.SelItem = get(handles.lstData,'Value');
handles.output = handles.Data;
handles.output.exit = true;
% Update handles structure
guidata(hObject, handles);
% Use UIRESUME instead of delete because the OutputFcn needs
% to get the updated handles structure.
uiresume(handles.figure1);
% --- Executes on button press in pushbutton2.
function pushbutton2_Callback(hObject, eventdata, handles)
% hObject    handle to pushbutton2 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.output = handles.Data;
handles.output.exit = true;
% Update handles structure
guidata(hObject, handles);
% Use UIRESUME instead of delete because the OutputFcn needs
% to get the updated handles structure.
uiresume(handles.figure1);
% --- Executes when user attempts to close figure1.
function figure1_CloseRequestFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
if isequal(get(hObject, 'waitstatus'), 'waiting')
    % The GUI is still in UIWAIT, us UIRESUME
    uiresume(hObject);
else
    % The GUI is no longer waiting, just close it
    delete(hObject);
end
handles.output = handles.Data;
handles.output.exit = true;
% Update handles structure
guidata(hObject, handles);
% --- Executes on key press over figure1 with no controls selected.
function figure1_KeyPressFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% Check for "enter" or "escape"
if isequal(get(hObject,'CurrentKey'),'escape')
    % User said no by hitting escape
    handles.output = 'No';
    
    % Update handles structure
    guidata(hObject, handles);
    
    uiresume(handles.figure1);
end
    
if isequal(get(hObject,'CurrentKey'),'return')
    uiresume(handles.figure1);
end
% --- Executes on selection change in lstData.
function lstData_Callback(hObject, eventdata, handles)
% hObject    handle to lstData (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% Hints: contents = cellstr(get(hObject,'String')) returns lstData contents as cell array
%        contents{get(hObject,'Value')} returns selected item from lstData
% --- Executes during object creation, after setting all properties.
function lstData_CreateFcn(hObject, eventdata, handles)
% hObject    handle to lstData (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
% Hint: listbox controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end
function txtNewData_Callback(hObject, eventdata, handles)
% hObject    handle to txtNewData (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% Hints: get(hObject,'String') returns contents of txtNewData as text
%        str2double(get(hObject,'String')) returns contents of txtNewData as a double
% --- Executes during object creation, after setting all properties.
function txtNewData_CreateFcn(hObject, eventdata, handles)
% hObject    handle to txtNewData (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end
% --- Executes on button press in cmdCreateNew.
function cmdCreateNew_Callback(hObject, eventdata, handles)
% hObject    handle to cmdCreateNew (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
if isfield(handles.Data,'Items'), l = numel(handles.Data.Items)+1; else l=1; end
handles.Data.Items{l} = struct('desc', get(handles.txtNewData,'String'), ...
                                'date',datestr(now), ...
                                'n_subjects_all',0, ...
                                'labels_known', get(handles.chkLabelKnown,'Value'), ...
                                'os', sprintf('%s', system_dependent('getos')));
if isfield(handles.Data,'NewItemIndex'), lx = numel(handles.Data.NewItemIndex)+1; else lx = 1; end
handles.Data.NewItemIndex(lx) = l;
print_dataitems(handles)
guidata(handles.figure1,handles);
% --- Executes on button press in cmdDelete.
function cmdDelete_Callback(hObject, eventdata, handles)
% hObject    handle to cmdDelete (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
selItem = get(handles.lstData,'Value');
lstItems = get(handles.lstData,'String');
delfl = questdlg(sprintf('Are you sure you want to delete dataset:\n%s',lstItems{selItem}));
if strcmp(delfl,'Yes')
%     handles.Data.Items(selItem) = [];
%     if isfield(handles.Data,'NewItems')
%         ind = find(handles.Data.NewItems, selItem);
%         handles.Data.NewItems(ind)=[];
%     end
    handles.output.delete = selItem;
    guidata(handles.figure1,handles);
    uiresume(handles.figure1)
%     % Update handles structure
%     guidata(hObject, handles);
%
%     print_dataitems(handles,selItem-1);
end
function toggle_controls(handles)
if ~isfield(handles,'Data') || ~isfield(handles.Data,'Items') || isempty(handles.Data.Items);
    tglstr = 'off';
else
    tglstr = 'on';
end
set(handles.cmdSelect,'Enable',tglstr);
set(handles.cmdSave,'Enable',tglstr);
set(handles.cmdDelete,'Enable',tglstr);
set(handles.lstData,'Enable',tglstr);
function print_dataitems(handles, value)
if ~exist('value','var') || isempty(value), value = numel(handles.Data.Items); end
if ~isempty(handles.Data.Items)
    for i=1:numel(handles.Data.Items)
        if isfield(handles.Data.Items{i},'labels_known')
            if handles.Data.Items{i}.labels_known
                lbknown_str = '; labels known: yes';
            else
                lbknown_str = '; labels known: no';
            end
        else
            lbknown_str = '';
        end
        if ~isfield(handles.Data.Items{i},'n_subjects_all')
            n_subjects_all=0;
        else
            n_subjects_all= handles.Data.Items{i}.n_subjects_all;
        end
        datastr{i} = sprintf('[%3i] %s (%g cases); date: %s%s',i,handles.Data.Items{i}.desc,n_subjects_all,handles.Data.Items{i}.date, lbknown_str);
    end
    set(handles.lstData, 'String', datastr);
    handles.lstData.Value=value;
else
    set(handles.lstData, 'String', 'NO DATA AVALABLE');
    handles.lstData.Value=1;
end
 toggle_controls(handles)
% --- Executes on button press in cmdSave.
function cmdSave_Callback(hObject, eventdata, handles)
% hObject    handle to cmdSave (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
selItem = get(handles.lstData,'Value');
%lstItems = get(handles.lstData,'String');
OOCV = handles.Data.Items{selItem};
filename = 'NM_OOCV_';
uisave('OOCV',filename);
% --- Executes on button press in chkLabelKnown.
function chkLabelKnown_Callback(hObject, eventdata, handles)
% hObject    handle to chkLabelKnown (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% Hint: get(hObject,'Value') returns toggle state of chkLabelKnown
% --- Executes on button press in chkCalibrationDataAvail.
function chkCalibrationDataAvail_Callback(hObject, eventdata, handles)
% hObject    handle to chkCalibrationDataAvail (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% Hint: get(hObject,'Value') returns toggle state of chkCalibrationDataAvail
% --------------------------------------------------------------------
function uiLoadData_ClickedCallback(hObject, eventdata, handles)
% hObject    handle to uiLoadData (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% --------------------------------------------------------------------
function uiNewData_ClickedCallback(hObject, eventdata, handles)
% hObject    handle to uiNewData (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% --- Executes on button press in cmdLoad.
function cmdLoad_Callback(hObject, eventdata, handles)
% hObject    handle to cmdLoad (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
n = numel(handles.Data.Items);
[filename,pathname] = uigetfile('*.mat','Load Independent Test Data','MultiSelect','on');
if iscell(filename)
    nF = numel(filename);
else
    nF=1;
end
if filename
    for i=1:nF
        if iscell(filename)
            pth = fullfile(pathname,filename{i});
            load(pth)
        else
            pth = fullfile(pathname,filename);
            load(pth)
        end
        handles.Data.Items{n+i} = OOCV;
    end
end
handles.Data.load=true;
guidata(handles.figure1,handles);
print_dataitems(handles)
function h1 = NM_OOCV_Manager_LayoutFcn(policy)
% policy - create a new figure or use a singleton. 'new' or 'reuse'.
persistent hsingleton;
if strcmpi(policy, 'reuse') && ~isempty(hsingleton) && ishandle(hsingleton)
    h1 = hsingleton; return;
end
load NM_OOCV_Manager.mat
% ---------- Figure ----------
appdata = [];
appdata.GUIDEOptions = struct( ...
    'active_h', [], 'taginfo', struct('figure',2,'pushbutton',8,'axes',2,'text',2, ...
    'listbox',2,'edit',2,'checkbox',3,'uitoolbar',2,'uipushtool',5,'uitoggletool',2), ...
    'override',1,'release',13,'resize','none','accessibility','callback','mfile',1, ...
    'callbacks',1,'singleton',1,'syscolorfig',1,'blocking',0, ...
    'lastSavedFile','C:\Users\nikol\OneDrive - LMU Klinikum AöR\Software\NeuroMiner_Current\gui\NM_OOCV_Manager.m', ...
    'lastFilename','D:\NeuroMiner_Elessar\gui\NM_OOCV_Manager.fig');
appdata.lastValidTag = 'figure1';
appdata.GUIDELayoutEditor = mat{1};
h1 = figure( ...
    'Units','pixels', ...                 % <- use pixels for the window itself
    'Position',[100 100 900 560], ...     % reasonable default size
    'Color',get(0,'defaultfigureColor'), ...
    'MenuBar','none','ToolBar','none','Name','NM_OOCV_Manager', ...
    'NumberTitle','off','HandleVisibility','callback', ...
    'Tag','figure1','Resize','on', ...    % allow resize; children use normalized grid
    'CloseRequestFcn',@(hObject,eventdata)NM_OOCV_Manager('figure1_CloseRequestFcn',hObject,eventdata,guidata(hObject)), ...
    'KeyPressFcn',@(hObject,eventdata)NM_OOCV_Manager('figure1_KeyPressFcn',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, blanks(0), appdata} );
% after creating h1:
set(h1,'Resize','on');
addlistener(h1,'SizeChanged',@(~,~) ...
    set(h1,'Position',max(get(h1,'Position'), [100 100 820 520])));
% ---------- Grid helper (12x12 with margins) ----------
gridCols = 12; gridRows = 12;
outerMargin = 0.03;   % was 0.02  -> more breathing room
gutter      = 0.012;  % was 0.008 -> avoids edge collisions
cellW = (1 - 2*outerMargin - (gridCols-1)*gutter) / gridCols;
cellH = (1 - 2*outerMargin - (gridRows-1)*gutter) / gridRows;
slot = @(c,r,w,h) [ ...
    outerMargin + (c-1)*(cellW+gutter), ...
    1 - outerMargin - r*cellH - (r-1)*gutter - (h-1)*(cellH+gutter), ...
    w*cellW + (w-1)*gutter, ...
    h*cellH + (h-1)*gutter];
% Add a tiny padding to every control to avoid border overlap on Windows
pad = 0.004;
safe = @(p) [p(1)+pad, p(2)+pad, max(p(3)-2*pad,1e-3), max(p(4)-2*pad,1e-3)];
% Top bar layout plan (row 1–2), content (rows 3–10), bottom controls (rows 11–12)
% ---------- Controls ----------
% Select Dataset (left, top)
h2 = uicontrol('Parent',h1,'Units','normalized','Style','pushbutton','Tag','cmdSelect', ...
    'String','Select Dataset','FontWeight','bold','BackgroundColor',[0.94 0.94 0.94], ...
    'Position',slot(1,1,3,2), ...
    'Callback',@(hObject,eventdata)NM_OOCV_Manager('cmdSelect_Callback',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, blanks(0), []} );
% Load / Save / Delete (center-top trio)
h7 = uicontrol('Parent',h1,'Units','normalized','Style','pushbutton','Tag','cmdLoad', ...
    'String','Load','FontWeight','bold','BackgroundColor',[0.94 0.94 0.94], ...
    'Position',slot(5,1,1.8,2), ...
    'Callback',@(hObject,eventdata)NM_OOCV_Manager('cmdLoad_Callback',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, blanks(0), []} );
h8 = uicontrol('Parent',h1,'Units','normalized','Style','pushbutton','Tag','cmdSave', ...
    'String','Save','FontWeight','bold','BackgroundColor',[0.94 0.94 0.94], ...
    'Position',slot(6.9,1,1.8,2), ...
    'Callback',@(hObject,eventdata)NM_OOCV_Manager('cmdSave_Callback',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, blanks(0), []} );
h6 = uicontrol('Parent',h1,'Units','normalized','Style','pushbutton','Tag','cmdDelete', ...
    'String','Delete','FontWeight','bold','BackgroundColor',[0.94 0.94 0.94], ...
    'Position',slot(8.8,1,1.8,2), ...
    'Callback',@(hObject,eventdata)NM_OOCV_Manager('cmdDelete_Callback',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, blanks(0), []} );
% Exit (right, top)
h3 = uicontrol('Parent',h1,'Units','normalized','Style','pushbutton','Tag','pushbutton2', ...
    'String','Exit','FontWeight','bold','BackgroundColor',[0.94 0.94 0.94], ...
    'TooltipString','Exit Independent Test Data Manager', ...
    'Position',slot(11,1,2,2), ...
    'Callback',@(hObject,eventdata)NM_OOCV_Manager('pushbutton2_Callback',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, blanks(0), []} );
set(h2,'Position',safe(slot(1,1,3,2)));
set(h7,'Position',safe(slot(5,1,1.8,2)));
set(h8,'Position',safe(slot(6.9,1,1.8,2)));
set(h6,'Position',safe(slot(8.8,1,1.8,2)));
set(h3,'Position',safe(slot(11,1,2,2)));
% Data list (center) — shrink height slightly to avoid bottom overlap
posList = slot(1,3,12,7.7);     % was h=8
h4 = uicontrol('Parent',h1,'Units','normalized','Style','listbox','Tag','lstData', ...
    'String',{'LMU dataset','UBS dataset','UKK dataset'}, 'Value',1, 'FontSize',9, ...
    'BackgroundColor',[0.804 0.878 0.969], 'TooltipString','Select analyses to operate on', ...
    'Position',safe(posList), ...
    'Callback',@(hObject,eventdata)NM_OOCV_Manager('lstData_Callback',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, @(hObject,eventdata)NM_OOCV_Manager('lstData_CreateFcn',hObject,eventdata,guidata(hObject)), []} );
% New data edit (bottom-left) — a bit narrower so it won't touch the checks
h5 = uicontrol('Parent',h1,'Units','normalized','Style','edit','Tag','txtNewData', ...
    'String','', 'FontSize',10, 'BackgroundColor',[0.8 1 1], ...
    'TooltipString','Enter new dataset description here', ...
    'Position',safe(slot(1,11,7.0,2)));
% Checkboxes in two stacked half-rows so their borders never hit the edit box
h9 = uicontrol('Parent',h1,'Units','normalized','Style','checkbox','Tag','chkLabelKnown', ...
    'String','Target labels known', ...
    'Position',safe(slot(8.2,11.3,2.8,0.9)), ...  % fractional rows to add separation
    'BackgroundColor',[0.94 0.94 0.94], ...
    'Callback',@(hObject,eventdata)NM_OOCV_Manager('chkLabelKnown_Callback',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, [], []});
h10 = uicontrol('Parent',h1,'Units','normalized','Style','checkbox','Tag','chkCalibrationDataAvail', ...
    'String','Calibration data available','Enable','off', ...
    'Position',safe(slot(8.2,12.1,3.4,0.9)), ...
    'BackgroundColor',[0.94 0.94 0.94], ...
    'Callback',@(hObject,eventdata)NM_OOCV_Manager('chkCalibrationDataAvail_Callback',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, [], []});
% Create New (bottom-right) — pulled slightly left and up to clear the frame
h11 = uicontrol('Parent',h1,'Units','normalized','Style','pushbutton','Tag','cmdCreateNew', ...
    'String','Create New ...','FontWeight','bold','BackgroundColor',[0.678 0.922 1], ...
    'Position',safe(slot(11,11.1,2,1.9)), ...
    'Callback',@(hObject,eventdata)NM_OOCV_Manager('cmdCreateNew_Callback',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, [], []});
% lock units to pixels for sane control heights
set([h2 h3 h4 h5 h6 h7 h8 h9 h10 h11],'Units','pixels');
% initial layout
NM_OOCV_Manager_doLayout(h1);
% keep it tidy on window resize (no nested functions)
set(h1,'ResizeFcn',@(src,evt) NM_OOCV_Manager_doLayout(src));
% ---------- (Optional) Toolbar ----------
h12 = uitoolbar('Parent',h1,'Visible','off','Tag','uiIndepToolbar', ...
    'CreateFcn', {@local_CreateFcn, blanks(0), []});
h13 = uipushtool('Parent',h12,'Tag','uiNewData','Tooltip','Create new independent test data item', ...
    'CData',mat{2}, ...
    'ClickedCallback',@(hObject,eventdata)NM_OOCV_Manager('uiNewData_ClickedCallback',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, blanks(0), []} );
h14 = uipushtool('Parent',h12,'Tag','uiImportData','Tooltip','Import Data to selected item', ...
    'CData',mat{3}, 'ClickedCallback','%default', ...
    'CreateFcn', {@local_CreateFcn, blanks(0), []} );
h15 = uipushtool('Parent',h12,'Tag','uiLoadData','Tooltip','Open independent test data', ...
    'BusyAction','cancel','Interruptible','off','CData',mat{4}, ...
    'ClickedCallback',@(hObject,eventdata)NM_OOCV_Manager('uiLoadData_ClickedCallback',hObject,eventdata,guidata(hObject)), ...
    'CreateFcn', {@local_CreateFcn, blanks(0), []} );
h16 = uipushtool('Parent',h12,'Tag','uiSaveData','Tooltip','Save Figure', ...
    'BusyAction','cancel','Interruptible','off','CData',mat{5}, ...
    'ClickedCallback','%default', ...
    'CreateFcn', {@local_CreateFcn, blanks(0), []} );
h17 = uitoggletool('Parent',h12,'Tag','uiInspectPredictions','Tooltip','Inspect findings', ...
    'CData',mat{6}, 'ClickedCallback','%default', ...
    'CreateFcn', {@local_CreateFcn, blanks(0), []} );
hsingleton = h1;
function NM_OOCV_Manager_doLayout(fig)
% Fixed-height, responsive layout for NM_OOCV_Manager.
% Safe to call anytime: exits quietly until all required controls exist.
if ~ishandle(fig) || ~strcmp(get(fig,'Type'),'figure'), return; end
% ---- collect handles by tag (returns [] if not found) ----
getT = @(t) findobj(fig,'Type','uicontrol','Tag',t,'-depth',1);
H.cmdSelect   = getT('cmdSelect');
H.btnExit     = getT('pushbutton2');
H.lstData     = getT('lstData');
H.txtNewData  = getT('txtNewData');
H.cmdDelete   = getT('cmdDelete');
H.cmdLoad     = getT('cmdLoad');
H.cmdSave     = getT('cmdSave');
H.chkKnown    = getT('chkLabelKnown');
H.chkCalib    = getT('chkCalibrationDataAvail');
H.btnCreate   = getT('cmdCreateNew');
% If any required control is missing, bail out (during early construction)
required = {'cmdSelect','btnExit','lstData','txtNewData','cmdDelete','cmdLoad','cmdSave','chkKnown','chkCalib','btnCreate'};
for k = 1:numel(required)
    h = H.(required{k});
    if isempty(h) || ~ishandle(h), return; end
end
% H is your input struct of handles
% e.g., H.button = uicontrol(...); H.text = uicontrol(...);

if verLessThan('matlab', '9.14')
    % --- Code for versions BEFORE R2023a ---
    % 'struct2array' does not exist, use the workaround
    try
        % Convert struct fields to a cell array, then to a table, then to an array
        handlesArray = table2array(struct2table(H));
        set(handlesArray, 'Units', 'pixels');
    catch ME
        warning('Failed to convert struct to array for setting units: %s', ME.message);
    end
else
    % --- Code for R2023a and NEWER ---
    % 'struct2array' is available
    set(struct2array(H), 'Units', 'pixels');
end
% ---- figure size ----
fp = getpixelposition(fig);  W = fp(3); Hh = fp(4);
% ---- metrics (pixels) ----
Mt   = 16;   % top/side margin
Mb   = 12;   % bottom margin
G    = 10;   % gutter
btnH = 32;   % pushbutton height
editH= 28;   % edit height
chkH = 22;   % checkbox height
topBand    = btnH + Mt;
bottomBand = max([btnH, editH, chkH]) + Mb + 8;
% Standard widths
wSelect = 220;  wStd = 120;  wExit = 120;
btnW    = 180;  % "Create New ..."
chkW1   = 200;  % "Target labels known"
chkW2   = 250;  % "Calibration data available"
% ---- TOP BAR ----
yTop = Hh - Mt - btnH;
set(H.cmdSelect,'Position',[Mt, yTop, wSelect, btnH]);
x = Mt + wSelect + 3*G;
set(H.cmdLoad,'Position',[x, yTop, wStd, btnH]);   x = x + wStd + G;
set(H.cmdSave,'Position',[x, yTop, wStd, btnH]);   x = x + wStd + G;
set(H.cmdDelete,'Position',[x, yTop, wStd, btnH]);
set(H.btnExit,'Position',[W - Mt - wExit, yTop, wExit, btnH]);
% ---- CENTER LISTBOX ----
yList = Mb + bottomBand;
hList = max(Hh - topBand - bottomBand - Mt - Mb, 120);
set(H.lstData,'Position',[Mt, yList, W - 2*Mt, hList]);
% ---- BOTTOM CONTROLS (aligned) ----
xEdit = Mt; yEdit = Mb;
editW = W - (Mt + G + chkW1 + G + chkW2 + G + btnW + Mt);
editW = max(editW, 220);
set(H.txtNewData,'Position',[xEdit, yEdit, editW, editH]);
yChk = Mb + floor((btnH - chkH)/2);  % common baseline
xChk1 = xEdit + editW + G;
set(H.chkKnown,'Position',[xChk1, yChk, chkW1, chkH]);
xChk2 = xChk1 + chkW1 + G;
set(H.chkCalib,'Position',[xChk2, yChk, chkW2, chkH]);
set(H.btnCreate,'Position',[W - Mt - btnW, Mb, btnW, btnH]);
% --- Set application data first then calling the CreateFcn.
function local_CreateFcn(hObject, eventdata, createfcn, appdata)
if ~isempty(appdata)
   names = fieldnames(appdata);
   for i=1:length(names)
       name = char(names(i));
       setappdata(hObject, name, getfield(appdata,name));
   end
end
if ~isempty(createfcn)
   if isa(createfcn,'function_handle')
       createfcn(hObject, eventdata);
   else
       eval(createfcn);
   end
end
% --- Handles default GUIDE GUI creation and callback dispatch
function varargout = gui_mainfcn(gui_State, varargin)
gui_StateFields =  {'gui_Name'
    'gui_Singleton'
    'gui_OpeningFcn'
    'gui_OutputFcn'
    'gui_LayoutFcn'
    'gui_Callback'};
gui_Mfile = '';
for i=1:length(gui_StateFields)
    if ~isfield(gui_State, gui_StateFields{i})
        error(message('MATLAB:guide:StateFieldNotFound', gui_StateFields{ i }, gui_Mfile));
    elseif isequal(gui_StateFields{i}, 'gui_Name')
        gui_Mfile = [gui_State.(gui_StateFields{i}), '.m'];
    end
end
numargin = length(varargin);
if numargin == 0
    % NM_OOCV_MANAGER
    % create the GUI only if we are not in the process of loading it
    % already
    gui_Create = true;
elseif local_isInvokeActiveXCallback(gui_State, varargin{:})
    % NM_OOCV_MANAGER(ACTIVEX,...)
    vin{1} = gui_State.gui_Name;
    vin{2} = [get(varargin{1}.Peer, 'Tag'), '_', varargin{end}];
    vin{3} = varargin{1};
    vin{4} = varargin{end-1};
    vin{5} = guidata(varargin{1}.Peer);
    feval(vin{:});
    return;
elseif local_isInvokeHGCallback(gui_State, varargin{:})
    % NM_OOCV_MANAGER('CALLBACK',hObject,eventData,handles,...)
    gui_Create = false;
else
    % NM_OOCV_MANAGER(...)
    % create the GUI and hand varargin to the openingfcn
    gui_Create = true;
end
if ~gui_Create
    % In design time, we need to mark all components possibly created in
    % the coming callback evaluation as non-serializable. This way, they
    % will not be brought into GUIDE and not be saved in the figure file
    % when running/saving the GUI from GUIDE.
    designEval = false;
    if (numargin>1 && ishghandle(varargin{2}))
        fig = varargin{2};
        while ~isempty(fig) && ~ishghandle(fig,'figure')
            fig = get(fig,'parent');
        end
        
        designEval = isappdata(0,'CreatingGUIDEFigure') || (isscalar(fig)&&isprop(fig,'GUIDEFigure'));
    end
        
    if designEval
        beforeChildren = findall(fig);
    end
    
    % evaluate the callback now
    varargin{1} = gui_State.gui_Callback;
    if nargout
        [varargout{1:nargout}] = feval(varargin{:});
    else
        feval(varargin{:});
    end
    
    % Set serializable of objects created in the above callback to off in
    % design time. Need to check whether figure handle is still valid in
    % case the figure is deleted during the callback dispatching.
    if designEval && ishghandle(fig)
        set(setdiff(findall(fig),beforeChildren), 'Serializable','off');
    end
else
    if gui_State.gui_Singleton
        gui_SingletonOpt = 'reuse';
    else
        gui_SingletonOpt = 'new';
    end
    % Check user passing 'visible' P/V pair first so that its value can be
    % used by oepnfig to prevent flickering
    gui_Visible = 'auto';
    gui_VisibleInput = '';
    for index=1:2:length(varargin)
        if length(varargin) == index || ~ischar(varargin{index})
            break;
        end
        % Recognize 'visible' P/V pair
        len1 = min(length('visible'),length(varargin{index}));
        len2 = min(length('off'),length(varargin{index+1}));
        if ischar(varargin{index+1}) && strncmpi(varargin{index},'visible',len1) && len2 > 1
            if strncmpi(varargin{index+1},'off',len2)
                gui_Visible = 'invisible';
                gui_VisibleInput = 'off';
            elseif strncmpi(varargin{index+1},'on',len2)
                gui_Visible = 'visible';
                gui_VisibleInput = 'on';
            end
        end
    end
    
    % Open fig file with stored settings.  Note: This executes all component
    % specific CreateFunctions with an empty HANDLES structure.
    
    % Do feval on layout code in m-file if it exists
    gui_Exported = ~isempty(gui_State.gui_LayoutFcn);
    % this application data is used to indicate the running mode of a GUIDE
    % GUI to distinguish it from the design mode of the GUI in GUIDE. it is
    % only used by actxproxy at this time.
    setappdata(0,genvarname(['OpenGuiWhenRunning_', gui_State.gui_Name]),1);
    if gui_Exported
        gui_hFigure = feval(gui_State.gui_LayoutFcn, gui_SingletonOpt);
        % make figure invisible here so that the visibility of figure is
        % consistent in OpeningFcn in the exported GUI case
        if isempty(gui_VisibleInput)
            gui_VisibleInput = get(gui_hFigure,'Visible');
        end
        set(gui_hFigure,'Visible','off')
        % openfig (called by local_openfig below) does this for guis without
        % the LayoutFcn. Be sure to do it here so guis show up on screen.
        movegui(gui_hFigure,'onscreen');
    else
        gui_hFigure = local_openfig(gui_State.gui_Name, gui_SingletonOpt, gui_Visible);
        % If the figure has InGUIInitialization it was not completely created
        % on the last pass.  Delete this handle and try again.
        if isappdata(gui_hFigure, 'InGUIInitialization')
            delete(gui_hFigure);
            gui_hFigure = local_openfig(gui_State.gui_Name, gui_SingletonOpt, gui_Visible);
        end
    end
    if isappdata(0, genvarname(['OpenGuiWhenRunning_', gui_State.gui_Name]))
        rmappdata(0,genvarname(['OpenGuiWhenRunning_', gui_State.gui_Name]));
    end
    % Set flag to indicate starting GUI initialization
    setappdata(gui_hFigure,'InGUIInitialization',1);
    % Fetch GUIDE Application options
    gui_Options = getappdata(gui_hFigure,'GUIDEOptions');
    % Singleton setting in the GUI MATLAB code file takes priority if different
    gui_Options.singleton = gui_State.gui_Singleton;
    if ~isappdata(gui_hFigure,'GUIOnScreen')
        % Adjust background color
        if gui_Options.syscolorfig
            set(gui_hFigure,'Color', get(0,'DefaultUicontrolBackgroundColor'));
        end
        % Generate HANDLES structure and store with GUIDATA. If there is
        % user set GUI data already, keep that also.
        data = guidata(gui_hFigure);
        handles = guihandles(gui_hFigure);
        if ~isempty(handles)
            if isempty(data)
                data = handles;
            else
                names = fieldnames(handles);
                for k=1:length(names)
                    data.(char(names(k)))=handles.(char(names(k)));
                end
            end
        end
        guidata(gui_hFigure, data);
    end
    % Apply input P/V pairs other than 'visible'
    for index=1:2:length(varargin)
        if length(varargin) == index || ~ischar(varargin{index})
            break;
        end
        len1 = min(length('visible'),length(varargin{index}));
        if ~strncmpi(varargin{index},'visible',len1)
            try set(gui_hFigure, varargin{index}, varargin{index+1}), catch break, end
        end
    end
    % If handle visibility is set to 'callback', turn it on until finished
    % with OpeningFcn
    gui_HandleVisibility = get(gui_hFigure,'HandleVisibility');
    if strcmp(gui_HandleVisibility, 'callback')
        set(gui_hFigure,'HandleVisibility', 'on');
    end
    feval(gui_State.gui_OpeningFcn, gui_hFigure, [], guidata(gui_hFigure), varargin{:});
    if isscalar(gui_hFigure) && ishghandle(gui_hFigure)
        % Handle the default callbacks of predefined toolbar tools in this
        % GUI, if any
        guidemfile('restoreToolbarToolPredefinedCallback',gui_hFigure);
        
        % Update handle visibility
        set(gui_hFigure,'HandleVisibility', gui_HandleVisibility);
        % Call openfig again to pick up the saved visibility or apply the
        % one passed in from the P/V pairs
        if ~gui_Exported
            gui_hFigure = local_openfig(gui_State.gui_Name, 'reuse',gui_Visible);
        elseif ~isempty(gui_VisibleInput)
            set(gui_hFigure,'Visible',gui_VisibleInput);
        end
        if strcmpi(get(gui_hFigure, 'Visible'), 'on')
            figure(gui_hFigure);
            
            if gui_Options.singleton
                setappdata(gui_hFigure,'GUIOnScreen', 1);
            end
        end
        % Done with GUI initialization
        if isappdata(gui_hFigure,'InGUIInitialization')
            rmappdata(gui_hFigure,'InGUIInitialization');
        end
        % If handle visibility is set to 'callback', turn it on until
        % finished with OutputFcn
        gui_HandleVisibility = get(gui_hFigure,'HandleVisibility');
        if strcmp(gui_HandleVisibility, 'callback')
            set(gui_hFigure,'HandleVisibility', 'on');
        end
        gui_Handles = guidata(gui_hFigure);
    else
        gui_Handles = [];
    end
    if nargout
        [varargout{1:nargout}] = feval(gui_State.gui_OutputFcn, gui_hFigure, [], gui_Handles);
    else
        feval(gui_State.gui_OutputFcn, gui_hFigure, [], gui_Handles);
    end
    if isscalar(gui_hFigure) && ishghandle(gui_hFigure)
        set(gui_hFigure,'HandleVisibility', gui_HandleVisibility);
    end
end
function gui_hFigure = local_openfig(name, singleton, visible)
% openfig with three arguments was new from R13. Try to call that first, if
% failed, try the old openfig.
if nargin('openfig') == 2
    % OPENFIG did not accept 3rd input argument until R13,
    % toggle default figure visible to prevent the figure
    % from showing up too soon.
    gui_OldDefaultVisible = get(0,'defaultFigureVisible');
    set(0,'defaultFigureVisible','off');
    gui_hFigure = matlab.hg.internal.openfigLegacy(name, singleton);
    set(0,'defaultFigureVisible',gui_OldDefaultVisible);
else
    % Call version of openfig that accepts 'auto' option"
    gui_hFigure = matlab.hg.internal.openfigLegacy(name, singleton, visible);
%     %workaround for CreateFcn not called to create ActiveX
%         peers=findobj(findall(allchild(gui_hFigure)),'type','uicontrol','style','text');
%         for i=1:length(peers)
%             if isappdata(peers(i),'Control')
%                 actxproxy(peers(i));
%             end
%         end
end
function result = local_isInvokeActiveXCallback(gui_State, varargin)
try
    result = ispc && iscom(varargin{1}) ...
             && isequal(varargin{1},gcbo);
catch
    result = false;
end
function result = local_isInvokeHGCallback(gui_State, varargin)
try
    fhandle = functions(gui_State.gui_Callback);
    result = ~isempty(findstr(gui_State.gui_Name,fhandle.file)) || ...
             (ischar(varargin{1}) ...
             && isequal(ishghandle(varargin{2}), 1) ...
             && (~isempty(strfind(varargin{1},[get(varargin{2}, 'Tag'), '_'])) || ...
                ~isempty(strfind(varargin{1}, '_CreateFcn'))) );
catch
    result = false;
end

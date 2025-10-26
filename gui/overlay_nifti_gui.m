function viewer = overlay_nifti_gui(structFile, statFile, parent, alphaVal)
% OVERLAY_NIFTI_GUI  Interactive overlay of structural image and statistical map
%   overlay_nifti_gui(structFile, statFile, alphaVal)
%   structFile: path to structural NIfTI (.nii)
%   statFile:   path to statistical NIfTI (.nii)
%   parent:     handle to graphics object (optional)
%   alphaVal:   initial overlay transparency [0-1]

%% A) Shared state declarations

% --- FAST PATCH: tiny state + debounce + cache folder ---
st = struct();
st.globalStructRange = [];
st.cmCache = struct('key','','cmDiv',[],'cmJet',[]);
redrawTimer = [];
    function requestRedraw()
    % Skip until UI is ready
    if ~isappdata(parent,'uiReady') || ~getappdata(parent,'uiReady')
        return;
    end

    % Create the timer once (reusable)
    if isempty(redrawTimer) || ~isvalid(redrawTimer)
        redrawTimer = timer( ...
            'ExecutionMode','singleShot', ...
            'StartDelay',0.03, ...
            'TimerFcn', @(~,~) safeRedraw(parent) );
    end

    % Debounce: if it’s running or queued, stop safely, then (re)start
    if isvalid(redrawTimer)
        try stop(redrawTimer); catch, end
        start(redrawTimer);
    end
end

function safeRedraw(parent)
    if ~isappdata(parent,'uiReady') || ~getappdata(parent,'uiReady'), return; end
    try
        redraw();
    catch ME
        warning('overlay_nifti_gui:RedrawError', ...
                'Redraw error (suppressed): %s', ME.message);
    end
end

% Load Icons
cacheDir = fullfile(tempdir, 'nmnifti_cache'); if ~exist(cacheDir,'dir'), mkdir(cacheDir); end
iconsDir = fullfile(fileparts(which('overlay_nifti_gui')),'icons');
imgZoomIn = loadIconWithBackground(fullfile(iconsDir,'uiZoomOut_image.png'), [240 240 240], [24 24]);
imgZoomOut = loadIconWithBackground(fullfile(iconsDir,'uiZoomIn_image.png'), [240 240 240], [24 24]);
imgSave3D = loadIconWithBackground(fullfile(iconsDir,'uiSave3D_image.png'), [240 240 240], [24 24]);
imgLoad3D = loadIconWithBackground(fullfile(iconsDir,'uiLoad3D_image.png'), [240 240 240], [24 24]);
imgHome3D = loadIconWithBackground(fullfile(iconsDir,'uiHome_image.png'), [240 240 240], [24 24]);
S=[];
Tmin = []; Tmax = [];
hasNeg = false; hasPos = false;
thrNeg = []; thrPos = [];
negColor = [0 0 1];   % defaults
midColor = [1 1 1];
posColor = [1 0 0];
Vs = []; ST = []; dims = [];
Vt = []; T = []; AtlasOrig=[]; VatOrig = [];
lut=[]; 
xBtn=[];
maxSlices = []; sliceIdx = [];
isoOn = false;   
h3DAx = [];
hRot = [];
depthMM = 0;
alpha3D = 0.6;    % default 3D brain opacity (0..1)

trigBrainRebuild = false;
trigVolRebuild = false;
trigSurfRebuild = false;

%% B) Handle inputs & parent container
if nargin<4, alphaVal=0.5; end
brightnessVal = 1;

% If no valid parent was passed in, make our own figure and use it as parent
% if it really exists AND is a graphics handle—otherwise create our own.
if nargin<3 || isempty(parent) || ~isgraphics(parent)
    parent = figure( ...
      'Name','NIfTI Overlay', ...
      'NumberTitle','off', ...
      'Units','normalized', ...
      'Position',[.1 .1 .8 .8], ...
      'MenuBar','none', ...
      'ToolBar','none');
end

% mark UI not ready yet
setappdata(parent,'uiReady', false);

% Find the containing figure
hFig = ancestor(parent,'figure');
set(hFig,'DeleteFcn', @(~,~) tryDeleteTimer());

function tryDeleteTimer()
    if ~isempty(redrawTimer) && isvalid(redrawTimer)
        stop(redrawTimer); delete(redrawTimer);
    end
end

%   Common for image-style slices: X → 'normal', Y → 'reverse' (matrix row down).
%   If you want neurological (L on left), often X → 'reverse'.
axisLock = struct('XDir','normal', 'YDir','reverse');  % <- adjust if you prefer
setappdata(parent, 'axisLock', axisLock);

% Store its existing WBMFcn so we can put it back later
origWBM = hFig.WindowButtonMotionFcn;
% Save it in the panel’s AppData (or in a nested variable)
setappdata(parent,'OrigWBMFcn',origWBM);

%% C) **Load & initialize the very first stats map**  
% This block used to live in updateStatsImage, but we pull it out
% so that Tmin/Tmax/etc. exist when we do the UI layout that
% references them (e.g. positioning the mid‐color button).

%%%%%%%%%%%%%%%%%%%%%%%%%% 2D AXES & CONTROLS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% default diverging colors
negColor = [0 0 1];   % blue
midColor = [1 1 1];   % white
posColor = [1 0 0];   % red

% Slider colors
sliBkgCl = [.8 .8 .8];
sliFrCl = [.6 .6 .6];

% 4) State and slice counts
viewmode = 'axial';

% 5) Layout positions
pos.axial    = [0.12 0.20 0.70 0.7];
pos.sagittal = [0.12 0.20 0.77 0.7];
pos.coronal  = [0.12 0.20 0.80 0.7];
pos.cbar     = [0.91 0.20 0.025 0.7];
baseY    = 0.20; 
baseH    = 0.7;

% State & handle vars
silOn    = false;
silB     = 0;           % silhouette brightness 0..1
crossOn  = false;
hCrossX  = []; hCrossY  = [];  % crosshair lines

% Vertical spacing & base position
x0 = 0.025;  w0 = 0.125;
y1 = 0.55;  h1 = 0.04;   % toggle height
dy = 0.05;  % gap

hAx = axes('Parent',parent,'Units','normalized','Position',pos.axial);
set(hAx,'XTick',[],'YTick',[],'Box','on');

%%% COLORBAR CONTROLS %%%
hCbar = axes('Parent',parent,'Units','normalized','Position',pos.cbar);
set(hCbar,'XTick',[],'YTick',[]);

% get colorbar position
cbPos = get(hCbar,'Position');  % [x y width height]
btnW  = 0.02;
btnH  = 0.02;
gap   = 0.005;
xBtn  = cbPos(1) + cbPos(3) + gap;

hRegLabel = uicontrol(parent, 'Style','text', 'Units','normalized', 'Position',[0.025 0.60 0.125 0.10], 'String','Region: (click on the image)', 'HorizontalAlignment','left', 'BackgroundColor', sliBkgCl);

% Position grid: assume hRegLabel sits at [x0 y0 w0 h0].
rlPos = get(hRegLabel,'Position');

%% Change structural image 
% === STRUCTURAL IMAGE CONTROL ===
if exist(structFile,'dir')
    structDir = structFile;
    D = dir(fullfile(structDir,'*_struct.nii'));
    names = {D.name};
    % append browse option
    names{end+1} = 'Browse...';
    % build popup
    hStructPopup = uicontrol(parent, 'Style','popupmenu', 'String', names, 'Units','normalized', 'Position',[rlPos(1) 0.18 rlPos(3) 0.06], ...
      'Callback',@onStructSelect);
    % pre‐load the first one
    structFile = fullfile(structDir, names{1});
else
    structDir = [];
    % single‐file mode: keep your existing pushbutton
    hStructBtn = uicontrol(parent,'Style','pushbutton', 'String','Select structural image', 'Units','normalized', 'Position',[rlPos(1) 0.2 rlPos(3) 0.04], ...
      'Callback',@onLoadStruct);
end

onLoadStruct([],[],structFile);

% NEG button (at bottom)
yNeg = cbPos(2);
hNegBtn = uicontrol(parent,'Style','pushbutton','Units','normalized', 'Position',[xBtn yNeg btnW btnH], 'BackgroundColor',negColor, 'TooltipString','Pick negative color', ...
  'Callback',@onNegColor);
% MID (zero) button
hMidBtn = uicontrol(parent,'Style','pushbutton','Units','normalized', ...
    'Position',[xBtn cbPos(2) btnW btnH], 'BackgroundColor',midColor, 'TooltipString','Pick zero/center color', 'Callback',@onMidColor);
% POS button (at top)
yPos = cbPos(2) + cbPos(4) - btnH;
hPosBtn = uicontrol(parent,'Style','pushbutton','Units','normalized', 'Position',[xBtn yPos btnW btnH], 'BackgroundColor',posColor, 'TooltipString','Pick positive color', ...
  'Callback',@onPosColor);

%%% SLICE viewmode CONTROLS %%%
isMulti = false;

% — Multi-slice toggle, to the left of the orientation buttons —
hMulti = uicontrol(parent, 'Style','togglebutton', 'String','Multi-slice', 'Units','normalized', 'Position',[0.025 0.94 0.125 0.05], 'Callback',@onMultiToggle);

% Compute a base‐x that sits 0.10 units to the left of your slice‐view axes:
axPos = pos.(viewmode);           % [x y width height]
xBase = axPos(1) - 0.11;

% Compute a y‐position just below the Multi-slice toggle:
% hMulti.Position = [x y w h], with y = bottom edge of that button
yBase = hMulti.Position(2) - 0.07;

% Now create each grid control at [xBase, yBase] offsets:
hRowLabel = uicontrol(parent, 'Style','text', 'Units','normalized', 'Position',[xBase, yBase, 0.06, 0.03], 'String','Rows:', 'Enable','off');
hRowPop = uicontrol(parent, 'Style','popupmenu', 'Units','normalized', 'Position',[xBase+0.06, yBase, 0.06, 0.03], 'String',{'1','2','3','4','5'}, 'Value',2, 'Enable','off', ...
    'Callback',@onSliceParamChange);
hColLabel = uicontrol(parent,'Style','text', 'Units','normalized', 'Position',[xBase, yBase-0.04, 0.06, 0.03], 'String','Cols:', 'Enable','off');
hColPop = uicontrol(parent, 'Style','popupmenu', 'Units','normalized', 'Position',[xBase+0.06,  yBase-0.04, 0.06, 0.03], 'String',{'1','2','3','4','5'}, 'Value',2, 'Enable','off', ...
    'Callback',@onSliceParamChange);
hStartLabel = uicontrol(parent, 'Style','text', 'Units','normalized', 'Position',[xBase, yBase-0.08, 0.06, 0.03], 'String','Start:', 'Enable','off');
hStartEdit = uicontrol(parent, 'Style','edit', 'Units','normalized', 'Position',[xBase+0.06, yBase-0.08, 0.06, 0.03], 'String','1', 'Enable','off', ...
    'Callback',@onSliceParamChange);
hEndLabel = uicontrol(parent, 'Style','text', 'Units','normalized', 'Position',[xBase, yBase-0.12, 0.06, 0.03], 'String','End:', 'Enable','off');
hEndEdit = uicontrol(parent, 'Style','edit', 'Units','normalized', 'Position',[xBase+0.06,  yBase-0.12, 0.06, 0.03], 'String',sprintf('%d',maxSlices.(viewmode)), 'Enable','off', ...
    'Callback',@onSliceParamChange);

%%% viewmode TOGGLES %%%
bg = uibuttongroup(parent, ...
    'Units','normalized', ...
    'Position',[0.2 0.94 0.6 0.05], ...  
    'SelectionChangedFcn',@onViewChange);
uicontrol(bg,'Style','togglebutton','String','Axial',    'Units','normalized','Position',[0.01 0.1 0.24 0.8]);
uicontrol(bg,'Style','togglebutton','String','Sagittal', 'Units','normalized','Position',[0.2575 0.1 0.24 0.8]);
uicontrol(bg,'Style','togglebutton','String','Coronal',  'Units','normalized','Position',[0.503 0.1 0.24 0.8]);
uicontrol(bg,'Style','togglebutton','String','3D-View',  'Units','normalized','Position',[0.75 0.1 0.24 0.8]);
btnAx = findobj(bg.Children,'-property','String','-and','String','Axial');
if ~isempty(btnAx), bg.SelectedObject = btnAx(1); end

% Slice slider + label
hSliceLabel = uicontrol('Parent',parent,'Style','text','Units','normalized', 'Position',[0.435 0.145 0.15 0.03],'String',sprintf('Slice: %d / %d',sliceIdx, maxSlices.(viewmode)));
hSlice = uicontrol('Parent',parent,'Style','slider','Units','normalized', 'Position',[0.16 0.12 0.70 0.03],'Min',1,'Max',maxSlices.(viewmode), 'BackgroundColor', sliBkgCl, 'ForegroundColor', sliFrCl, 'Value',sliceIdx,'SliderStep',[1/(maxSlices.(viewmode)-1) 0.1], ...
    'Callback',@onSliceChange);

% Get the slice slider’s normalized position
spos = get(hSlice, 'Position');   % [x y w h]

%%%%%%%%%%%%%%%%%%%%%% 3D AXES & LIGHTING CONTROLS %%%%%%%%%%%%%%%%%%%%%%%%
% Shrink the original position of the 2D axes object
axPos = pos.axial;
shrinkFactor = 0.9;  % 90% of original size
centerX = axPos(1) + axPos(3)/2;
centerY = axPos(2) + axPos(4)/2;
newW = axPos(3) * shrinkFactor;
newH = axPos(4) * shrinkFactor;
newX = centerX - newW/2 + .025;
newY = centerY - newH/2 ;

h3DAx = axes('Parent', parent, ...
    'Units','normalized', ...
    'Position', [newX newY newW newH], ...
    'Visible','off', ...
    'Box','off', ...
    'Tag','NM-3D-Axes');

pbaspect(h3DAx, [1 1 1]);
h3DAx.ActivePositionProperty = 'position';

% Make sure figure can do lighting
set(ancestor(h3DAx,'figure'),'Renderer','opengl');

% --- Light direction controls (start hidden) ---
hLightAzLbl = uicontrol(parent,'Style','text','Units','normalized',...
    'String','Light Az','Visible','off');
hLightAz    = uicontrol(parent,'Style','slider','Units','normalized',...
    'Min',-180,'Max',180,'Value',45,'Visible','off','Callback',@onLightChange);

hLightElLbl = uicontrol(parent,'Style','text','Units','normalized',...
    'String','Light El','Visible','off');
hLightEl    = uicontrol(parent,'Style','slider','Units','normalized',...
    'Min',-90,'Max',90,'Value',30,'Visible','off','Callback',@onLightChange);

% --- 3D alpha control (start hidden) ---
h3DAlphaLbl = uicontrol(parent,'Style','text','Units','pixels', ...
    'String','3D Alpha','Visible','off');
h3DAlpha    = uicontrol(parent,'Style','slider','Units','pixels', ...
    'Min',0,'Max',1,'Value',alpha3D,'Visible','off', ...
    'Callback',@on3DAlphaChange);

% Create a "Record 360°" button in your GUI
hBtnRecord = uicontrol(parent, 'Style','pushbutton', ...
    'String','Record 360°', 'Units','pixel', 'Visible', 'off', ...
    'Callback', @(~,~) onRecordRotationLive(parent));

% Volume or Surface projection
hOverlayMode = uicontrol(parent,'Style','checkbox', ...
    'String','Volumetric Overlay', 'Visible', 'off', ...
    'Value',0, ...
    'Callback',@(src,evt) ensure3DScene());

% Zoom 3D controls
hZoomIn = uicontrol(parent, ...
    'Style', 'pushbutton', ...
    'Visible', 'off', ...
    'CData', imgZoomIn, ...
    'String', ' ', ...
    'TooltipString', 'Zoom In', ...
    'Callback', @onZoomIn);

hZoomOut = uicontrol(parent, ...
    'Style', 'pushbutton', ...
    'Visible', 'off', ...
    'CData', imgZoomOut, ...
    'String', ' ', ...
    'TooltipString', 'Zoom Out', ...
    'Callback', @onZoomOut);

% 3D scene helper function (Home, Save, Load)
hHome3D = uicontrol(parent, ...
    'Style', 'pushbutton', ...
    'String', ' ', ...
    'CData', imgHome3D,...
    'Units', 'pixels', ...
    'Visible', 'off', ...
    'TooltipString', 'Reset current 3D view & rendering settings to defaults', ...
    'Callback', @onReset3DSettings);

% --- Save 3D Settings button (place alongside your other 3D controls) ---
hSave3D = uicontrol(parent, ...
    'Style', 'pushbutton', ...
    'String', ' ', ...
    'CData', imgSave3D,...
    'Units', 'pixels', ...
    'Visible', 'off', ...
    'TooltipString', 'Save current 3D view & rendering settings to file', ...
    'Callback', @onSave3DSettings);

% --- Load 3D Settings button ---
hLoad3D = uicontrol(parent, ...
    'Style', 'pushbutton', ...
    'String', ' ', ...
    'CData', imgLoad3D,...
    'Units', 'pixels', ...
    'Visible', 'off', ...
    'TooltipString', 'Load a previously saved 3D view & rendering setup', ...
    'Callback', @onLoad3DSettings);

%set(ancestor(parent,'figure'),'SizeChangedFcn',@(~,~)position3DControls());

% create lights once
setupWorldLights();  

% Row where the 3D controls live (same y as hSlice)
ctrlY  = spos(2);  
ctrlH  = 0.03;
txtH   = 0.02;

% Azimuth
hAzimTxt    = uicontrol(parent,'Style','text','Units','normalized', ...
                'Position',[.10 ctrlY+ctrlH .10 txtH], ...
                'String','Azimuth: 0°','Visible','off');
hAzimSlider = uicontrol(parent,'Style','slider','Units','normalized', ...
                'Position',[.10 ctrlY .10 ctrlH], ...
                'Min',0,'Max',360,'Value',0, ...
                'Visible','off','Callback',@onAzimChange);
% Elevation
hElevTxt    = uicontrol(parent,'Style','text','Units','normalized', ...
                'Position',[.22 ctrlY+ctrlH .10 txtH], ...
                'String','Elevation: 0°','Visible','off');
hElevSlider = uicontrol(parent,'Style','slider','Units','normalized', ...
                'Position',[.22 ctrlY .10 ctrlH], ...
                'Min',-90,'Max',90,'Value',0, ...
                'Visible','off','Callback',@onElevChange);

% Depth (mm)
hDepthTxt    = uicontrol(parent,'Style','text','Units','normalized', ...
                'Position',[.34 ctrlY+ctrlH .10 txtH], ...
                'String','Depth: 0','Visible','off');
hDepthSlider = uicontrol(parent,'Style','slider','Units','normalized', ...
                'Position',[.34 ctrlY .10 ctrlH], ...
                'Min',0,'Max',10,'Value',0, ...
                'Visible','off','Callback',@onDepthChange);

% Background‐color picker
hBGBtn = uicontrol(parent,'Style','pushbutton','Units','normalized', ...
                'Position',[.46 ctrlY .08 ctrlH], ...
                'String','BG Color','Visible','off', ...
                'Callback',@onBGColor);

% AmbientStrength
hAmbientTxt    = uicontrol(parent,'Style','text','Units','normalized', ...
                'Position',[.56 ctrlY+ctrlH .08 txtH], ...
                'String','Ambient','Visible','off');
hAmbientSlider = uicontrol(parent,'Style','slider','Units','normalized', ...
                'Position',[.56 ctrlY .08 ctrlH], ...
                'Min',0,'Max',1,'Value',0.4, ...
                'Visible','off','Callback',@onAmbientChange);

% DiffuseStrength
hDiffuseTxt    = uicontrol(parent,'Style','text','Units','normalized', ...
                'Position',[.66 ctrlY+ctrlH .08 txtH], ...
                'String','Diffuse','Visible','off');
hDiffuseSlider = uicontrol(parent,'Style','slider','Units','normalized', ...
                'Position',[.66 ctrlY .08 ctrlH], ...
                'Min',0,'Max',1,'Value',0.6, ...
                'Visible','off','Callback',@onDiffuseChange);

% SpecularStrength
hSpecTxt    = uicontrol(parent,'Style','text','Units','normalized', ...
                'Position',[.76 ctrlY+ctrlH .08 txtH], ...
                'String','SpecStr','Visible','off');
hSpecSlider = uicontrol(parent,'Style','slider','Units','normalized', ...
                'Position',[.76 ctrlY .08 ctrlH], ...
                'Min',0,'Max',1,'Value',0.3, ...
                'Visible','off','Callback',@onSpecChange);

% SpecularExponent
hSpecExpTxt    = uicontrol(parent,'Style','text','Units','normalized', ...
                'Position',[.86 ctrlY+ctrlH .08 txtH], ...
                'String','SpecExp','Visible','off');
hSpecExpSlider = uicontrol(parent,'Style','slider','Units','normalized', ...
                'Position',[.86 ctrlY .08 ctrlH], ...
                'Min',1,'Max',50,'Value',10, ...
                'Visible','off','Callback',@onSpecExpChange);

% Use its X and W to center the main axes
hAx.Position = [spos(1), baseY, spos(3)-0.05, baseH];
hAx.ButtonDownFcn =  @onSliceClick;
hAx.NextPlot = 'replacechildren';  % keep callbacks when we draw

% Brightness and Alpha side-by-side
hBrightValue = uicontrol('Parent',parent,'Style','text','Units','normalized', 'Position',[0.10 0.065 0.06 0.03],'String','Brightness');
hBrightSlider = uicontrol('Parent',parent,'Style','slider','Units','normalized', 'Position',[0.16 0.07 0.28 0.03],'Min',0,'Max',2, 'BackgroundColor', sliBkgCl, 'ForegroundColor', sliFrCl, 'Value',brightnessVal, ...
    'Callback',@onBrightChange);
hBrightLabel = uicontrol('Parent',parent,'Style','text','Units','normalized', 'Position',[0.44 0.065 0.03 0.03],'String',sprintf('%.2f',brightnessVal));
hAlphaValue = uicontrol('Parent',parent,'Style','text','Units','normalized', 'Position',[0.52 0.065 0.05 0.03],'String','Alpha value');
hAlphaSlider = uicontrol('Parent',parent,'Style','slider','Units','normalized', 'BackgroundColor', sliBkgCl, 'ForegroundColor', sliFrCl, 'Position',[0.58 0.07 0.28 0.03],'Min',0,'Max',1,'Value',alphaVal, ...
    'Callback',@onAlphaChange);
hAlphaLabel = uicontrol('Parent',parent,'Style','text','Units','normalized', 'Position',[0.86 0.065 0.03 0.03],'String',sprintf('%.2f',alphaVal));

% === ATLAS IMAGE CONTROL ===
if ~isempty(structDir)
    A = dir(fullfile(structDir,'*_atlas.nii'));
    atlasNames = {A.name};
    % prepend “no atlas” and append browse
    atlasNames = ['<none>', atlasNames, {'Browse...'}];
    hAtlasPopup = uicontrol(parent, ...
      'Style','popupmenu', ...
      'String', atlasNames, ...
      'Units','normalized', ...
      'Position',[rlPos(1) rlPos(2)-0.005 rlPos(3) 0.06], ...
      'Callback',@onLoadAtlas);
    % start with “no atlas”
    atlasFile = '';
else
    % single‐file atlas: keep your existing pushbutton
    hAtlasBtn = uicontrol(parent,'Style','pushbutton', ...
      'String','Select atlas', ...
      'Units','normalized', ...
      'Position',[rlPos(1) rlPos(2) rlPos(3) 0.04], ...
      'Callback',@onLoadAtlas);
    atlasFile = '';
end

% Shift the region‐info label up a bit so they don’t overlap:
set(hRegLabel,'Position',[rlPos(1) rlPos(2)+0.03 rlPos(3) rlPos(4)]);

% 1) Silhouette toggle
hSilToggle = uicontrol(parent, 'Style','checkbox', 'Enable', 'off', ...
  'String','Show ROI silhouette','Units','normalized', ...
  'Position',[x0, y1, w0, h1], 'Value',0, ...
  'Callback',@onSilToggle);

% 2) Silhouette color slider
hSilColorTxt = uicontrol(parent,'Style','text', ...
  'String','Silhouette brightness','Units','normalized', ...
  'Position',[x0, y1-dy, w0*0.5, h1], 'Enable','off');
hSilColor    = uicontrol(parent,'Style','slider', ...
  'Min',0,'Max',1,'Value',0,'Units','normalized', ...
  'Position',[x0+w0*0.5, y1-dy, w0*0.5, h1], ...
  'Enable','off', 'Callback',@onSilColor);

% 3) Crosshair toggle
hCrossToggle = uicontrol(parent, 'Style','checkbox', ...
  'String','Crosshair','Units','normalized', ...
  'Position',[x0, y1-2*dy, w0, h1], 'Value',0, ...
  'Callback',@onCrossToggle);

% 4) Export ROI table
hExportBtn = uicontrol(parent,'Style','pushbutton', 'Enable', 'off', ...
  'String','Export ROI table','Units','normalized', ...
  'Position',[x0, y1-3*dy, w0, h1], ...
  'Callback',@onExportROI);

% Place an edit box & label just above it
hFilterLbl = uicontrol(parent,'Style','text', 'Enable', 'off', ...
  'Units','normalized','String','Min %voxels:', ...
  'Position',[rlPos(1), y1-4*dy - 0.008, rlPos(3)/2, 0.04]);

hMinPct = uicontrol(parent,'Style','edit',  'Enable', 'off', ...
  'Units','normalized','String','0', ...
  'Position',[rlPos(1)+rlPos(3)/2, y1 - 4*dy, rlPos(3)/2, 0.04], ...
  'TooltipString','Only include ROIs with at least this % of voxels will pass threshold for the inclusion into ROI table.');

%% Contour plot
hIsoToggle = uicontrol(parent, ...
    'Style','checkbox', ...
    'String','Contours', ...
    'Units','normalized', ...
    'TooltipString', 'Display only contours of structural image', ...
    'Position',[rlPos(1) 0.25 rlPos(3)/2 0.04], ...
    'Value',false, ...
    'Callback',@onIsoToggle);

hIsoEdit = uicontrol(parent,'Style','edit', 'Enable', 'off', ...
  'Units','normalized','String','50', ...
  'Position',[rlPos(1)+rlPos(3)/2 0.25 rlPos(3)/2 0.04], ...
  'TooltipString','Define # of bins to detect contours [range depends on image: 25-200]', ...
  'Callback', @onIsoEdit);

%%% BOTTOM CONTROLS %%%

%% Negative threshold
hNegLabel = uicontrol('Parent',parent, 'Style','text','Units','normalized', 'Visible', 'off', ...
    'Position',[0.18 0.017 0.10 0.03],'String','Negative Threshold');

% capture label position
lblPos = get(hNegLabel,'Position');  % [x y w h]
x0     = lblPos(1);
wLbl   = lblPos(3);
y0     = lblPos(2);

% spacing and control sizes
gap      = 0.005;
editW    = 0.06;
spinW    = 0.017;
spinH    = 0.015;
sliderW  = 0.05;
ctrlH    = lblPos(4) - 0.005;  % slightly smaller than label height

% 1) Edit‐box just right of label
xEdit = x0 + wLbl + gap;
hNegEdit = uicontrol(parent, ...
    'Style','edit', ...
    'Units','normalized', ...
    'Visible','off', ...
    'Position',[xEdit, y0 + 0.005, editW, ctrlH], ...
    'String',sprintf('%.2f',thrNeg), ...
    'Callback',@onNegEdit);

% 2) Up/down spinners immediately to the right of the edit‐box
xSpin = xEdit + editW + gap;
hNegUp = uicontrol(parent, ...
    'Style','pushbutton', ...
    'String','▲', ...
    'Units','normalized', ...
    'Visible','off', ...
    'FontSize', 6, ...
    'Position',[xSpin, y0 + 0.009 + (ctrlH-spinH), spinW, spinH], ...
    'Callback',@onNegStepUp);
hNegDn = uicontrol(parent, ...
    'Style','pushbutton', ...
    'String','▼', ...
    'Units','normalized', ...
    'Visible','off', ...
    'FontSize', 6, ...
    'Position',[xSpin, y0 + 0.005, spinW, spinH], ...
    'Callback',@onNegStepDown);

% 3) Slider immediately to the right of the spinners
xSlider = xSpin + spinW + gap;
hNegSlider = uicontrol(parent, ...
    'Style','slider', ...
    'Units','normalized', ...
    'Visible','off', ...
    'Position',[xSlider, y0 + 0.005, sliderW, ctrlH], ...
    'Min',Tmin, 'Max',0, 'Value',thrNeg, ...
    'Callback',@onNegChange);

%% Positive threshold
%% --- Positive threshold controls ---
hPosLabel = uicontrol(parent, ...
    'Style','text', ...
    'Units','normalized', ...
    'Visible','off', ...
    'Position',[0.6, 0.0165, editW+0.025, 0.03], ...
    'String','Positive Threshold');

lblPos = get(hPosLabel,'Position');  % [x y w h]
x0     = lblPos(1);
wLbl   = lblPos(3);
y0     = lblPos(2);

% 1) Edit‐box
xEdit = x0 + wLbl + gap;
hPosEdit = uicontrol(parent, ...
    'Style','edit', ...
    'Units','normalized', ...
    'Visible','off', ...
    'Position',[xEdit, y0+0.005, editW, ctrlH], ...
    'String',sprintf('%.2f',thrPos), ...
    'Callback',@onPosEdit);

% 2) Spinner arrows
xSpin = xEdit + editW + gap;
hPosUp = uicontrol(parent, ...
    'Style','pushbutton', ...
    'String','▲', ...
    'Units','normalized', ...
    'Visible','off', ...
    'FontSize', 6, ...
    'Position',[xSpin, y0+0.009+(ctrlH-spinH), spinW, spinH], ...
    'Callback',@onPosStepUp);
hPosDn = uicontrol(parent, ...
    'Style','pushbutton', ...
    'String','▼', ...
    'Units','normalized', ...
    'Visible','off', ...
    'FontSize', 6, ...
    'Position',[xSpin, y0+0.005, spinW, spinH], ...
    'Callback',@onPosStepDown);

% 3) Slider
xSlider = xSpin + spinW + gap;
hPosSlider = uicontrol(parent, ...
    'Style','slider', ...
    'Units','normalized', ...
    'Visible','off', ...
    'Position',[xSlider, y0+0.005, sliderW, ctrlH], ...
    'Min',0, 'Max',Tmax, 'Value',thrPos, ...
    'Callback',@onPosChange);

% Single threshold
if hasPos
    thr = thrPos; mn=0; mx=Tmax;
else
    thr = thrNeg; mn=Tmin; mx=0;
end

%% --- Single‐threshold controls (unipolar) ---
hThrLabel = uicontrol(parent, ...
    'Style','text', ...
    'Units','normalized', ...
    'Visible','off', ...
    'Position',[0.375, 0.017, editW-0.02, 0.03], ...
    'String','Threshold');

lblPos = get(hThrLabel,'Position');
x0     = lblPos(1);
wLbl   = lblPos(3);
y0     = lblPos(2);

% 1) Edit‐box
xEdit = x0 + wLbl + gap;
hThrEdit = uicontrol(parent, ...
    'Style','edit', ...
    'Units','normalized', ...
    'Visible','off', ...
    'Position',[xEdit, y0+0.005,  editW,    ctrlH], ...
    'String',sprintf('%.2f',thr), ...
    'Callback',@onThrEdit);

% 2) Spinner arrows
xSpin = xEdit + editW + gap;
hThrUp = uicontrol(parent, ...
    'Style','pushbutton', ...
    'String','▲', ...
    'Units','normalized', ...
    'Visible','off', ...
    'Position',[xSpin, y0+0.009+(ctrlH-spinH), spinW, spinH], ...
    'Callback',@onThrStepUp);
hThrDn = uicontrol(parent, ...
    'Style','pushbutton', ...
    'String','▼', ...
    'Units','normalized', ...
    'Visible','off', ...
    'Position',[xSpin, y0+0.005, spinW, spinH], ...
    'Callback',@onThrStepDown);

% 3) Slider
xSlider = xSpin + spinW + gap;
hThrSlider = uicontrol(parent, ...
    'Style','slider', ...
    'Units','normalized', ...
    'Visible','off', ...
    'Position',[xSlider,    y0+0.005, sliderW, ctrlH], ...
    'Min',mn, 'Max',mx, 'Value',thr, ...
    'Callback',@onThrChange);

if hasNeg && hasPos
    set([hNegLabel, hNegEdit,hNegSlider,hNegUp, hNegDn, hPosLabel, hPosEdit, hPosSlider, hPosUp, hPosDn],'Enable','on','Visible','on')
else
    set([hThrLabel, hThrEdit, hThrSlider, hThrUp, hThrDn],'Enable','on','Visible','on')
end

spos = get(hSlice,'Position');
set(hAx, 'Position', [spos(1), baseY, spos(3), baseH]);

setappdata(parent,'uiReady', true);
requestRedraw();   % first draw now that UI exists

updateStatsImage(statFile);
viewer.update = @updateStatsImage;

%% ────── After all your UI setup, add this nested updater ──────
function updateStatsImage(statFile)

    % 1) Reslice into structural space if needed
    [d,fn,ext] = fileparts(statFile);
    if startsWith(fn,'r'), fn = extractAfter(fn,1); end
    rStat = fullfile(d, ['r' fn ext]);
    spm_reslice({structFile; fullfile(d,[fn ext])}, struct('interp',1,'which',1,'mean',0));

    % 2) Reload the volume
    Vt  = spm_vol(rStat);
    T  = spm_read_vols(Vt);
    Tmin = min(T(:));  Tmax = max(T(:));
    hasNeg = Tmin < 0;
    hasPos = Tmax > 0;

    % 3) Compute new thresholds
    if hasNeg && hasPos
        thrNeg = prctile(T(T<0),10);
        thrPos = prctile(T(T>0),90);
    elseif hasPos
        thrPos = prctile(T(:),90);
        thrNeg = 0;
    else
        thrNeg = prctile(T(:),10);
        thrPos = 0;
    end

    if ~(hasNeg && hasPos)
        thr = hasPos * thrPos + hasNeg * thrNeg;
    end

    % 4) Update threshold controls
    if hasNeg && hasPos
        % enable both negative & positive controls
        set([hNegEdit,hNegSlider],'Enable','on', 'Visible', 'on', ...
            'Min', Tmin, 'Max', 0, 'Value', thrNeg, 'String',sprintf('%.2f',thrNeg));
        set([hPosEdit,hPosSlider],'Enable','on', 'Visible', 'on', ...
            'Min', 0, 'Max', Tmax, 'Value', thrPos, 'String',sprintf('%.2f',thrPos));
        % hide the single Thr controls if you had them
        set([hNegLabel, hNegUp, hNegDn, hPosLabel, hPosUp, hPosDn, hMidBtn],'Enable','on','Visible','on');
        set([hThrLabel, hThrEdit, hThrSlider,hThrUp, hThrDn],'Enable','off','Visible','off');
        yMid = cbPos(2) + ((0 - Tmin)/(Tmax - Tmin))*cbPos(4) - btnH/2;
        set(hMidBtn, 'Position', [xBtn yMid btnW btnH])
    else
        % disable the unused slider
        set([hNegLabel, hNegEdit, hNegSlider,hPosLabel, hPosEdit, hPosSlider, hNegUp, hNegDn, hPosUp, hPosDn, hMidBtn],'Enable','off','Visible','off');
        % show single‐polarity controls
        set([hThrLabel, hThrUp, hThrDn],'Enable','on','Visible','on');
        set([hThrEdit, hThrSlider],'Enable','on','Visible','on', ...
            'Min', min(T(:)), 'Max', max(T(:)), 'Value', hasPos*thrPos + ~hasPos*thrNeg, ...
            'String',sprintf('%.2f',hasPos*thrPos + ~hasPos*thrNeg));
    end

    % 5) Update alpha/colorbar polarity buttons
    set(hNegBtn,'Enable',tern(hasNeg,'on','off'));
    set(hMidBtn,'Enable',tern(hasNeg&&hasPos,'on','off'));
    set(hPosBtn,'Enable',tern(hasPos,'on','off'));

    % Invalidate 3D cache on data changes
    if isappdata(parent,'hPatch3D')
        hp = getappdata(parent,'hPatch3D');
        if isgraphics(hp), delete(hp); end
        rmappdata(parent,'hPatch3D');
    end
    if isappdata(parent,'hVol3D')
        hp = getappdata(parent,'hVol3D');
        if isgraphics(hp), delete(hp); end
        rmappdata(parent,'hVol3D');
    end
    
    % 6) Finally trigger a redraw with the new T, thresholds, etc.
    trigSurfRebuild = true;
    trigVolRebuild = true;
    requestRedraw();
end

function s = tern(tf, a, b)
    if tf, s = a; else, s = b; end
end

function onNegStepUp(~,~)
    ss = get(hNegSlider,'SliderStep');
    stepVal = ss(1)*(get(hNegSlider,'Max') - get(hNegSlider,'Min'));
    newVal = min(get(hNegSlider,'Value') + stepVal, 0);
    set(hNegSlider,'Value',newVal);
    onNegChange(hNegSlider,[]);
end

function onNegStepDown(~,~)
    ss = get(hNegSlider,'SliderStep');
    stepVal = ss(1)*(get(hNegSlider,'Max') - get(hNegSlider,'Min'));
    newVal = max(get(hNegSlider,'Value') - stepVal, get(hNegSlider,'Min'));
    set(hNegSlider,'Value',newVal);
    onNegChange(hNegSlider,[]);
end

function onPosStepUp(~,~)
    ss = get(hPosSlider,'SliderStep');
    stepVal = ss(1)*(get(hPosSlider,'Max') - get(hPosSlider,'Min'));
    newVal = min(get(hPosSlider,'Value') + stepVal, get(hPosSlider,'Max'));
    set(hPosSlider,'Value',newVal);
    onPosChange(hPosSlider,[]);
end

function onPosStepDown(~,~)
    ss = get(hPosSlider,'SliderStep');
    stepVal = ss(1)*(get(hPosSlider,'Max') - get(hPosSlider,'Min'));
    newVal = max(get(hPosSlider,'Value') - stepVal, 0);
    set(hPosSlider,'Value',newVal);
    onPosChange(hPosSlider,[]);
end

function onThrStepUp(~,~)
    ss = get(hThrSlider,'SliderStep');
    stepVal = ss(1)*(get(hThrSlider,'Max') - get(hThrSlider,'Min'));
    newVal = min(get(hThrSlider,'Value') + stepVal, get(hThrSlider,'Max'));
    set(hThrSlider,'Value',newVal);
    onThrChange(hThrSlider,[]);
end

function onThrStepDown(~,~)
    ss = get(hThrSlider,'SliderStep');
    stepVal = ss(1)*(get(hThrSlider,'Max') - get(hThrSlider,'Min'));
    newVal = max(get(hThrSlider,'Value') - stepVal, get(hThrSlider,'Min'));
    set(hThrSlider,'Value',newVal);
    onThrChange(hThrSlider,[]);
end

function onAzimChange(src,~)
    az = src.Value;
    set(hAzimTxt,'String',sprintf('Azimuth: %d°',round(az)));
    if strcmp(viewmode,'3d-view')
        [~, el] = view(h3DAx);   % get current elev
        view(h3DAx, az, el);
    end
end

function onElevChange(src,~)
    el = src.Value;
    set(hElevTxt,'String',sprintf('Elevation: %d°',round(el)));
    if strcmp(viewmode,'3d-view')
        [az, ~] = view(h3DAx);   % get current azim
        view(h3DAx, az, el);
    end
end

function onDepthChange(src,~)
    depthMM = src.Value;
    set(hDepthTxt,'String',sprintf('Depth: %.1f',depthMM));
    update3DColors();
end

function onBGColor(~,~)
    c = uisetcolor(get(h3DAx,'Color'),'Select background');
    if ~isequal(c,0)
        set(h3DAx,'Color',c);
    end
end

function onLightChange(~,~)
    if ~isgraphics(h3DAx,'axes'), return; end
    L = getappdata(h3DAx,'worldLights');
    az = get(hLightAz,'Value');
    el = get(hLightEl,'Value');
    lightangle(L.key,  az,  el);
end

function onZoomIn(~, ~)
    camzoom(h3DAx, 1.1);  % Zoom in by 10%
end

function onZoomOut(~, ~)
    camzoom(h3DAx, 0.9);  % Zoom out by 10%
end

function on3DAlphaChange(src, ~)
    alpha3D = max(0, min(1, src.Value));
    update3DColors();
end

function onAmbientChange(src,~)
    v = src.Value;
    hPatch3D  = getappdata(parent,'hPatchBase3D');
    set(hAmbientTxt,'String',sprintf('Ambient: %.2f',v));
    set(hPatch3D,'AmbientStrength',v);
end

function onDiffuseChange(src,~)
    v = src.Value;
    hPatch3D  = getappdata(parent,'hPatchBase3D');
    set(hDiffuseTxt,'String',sprintf('Diffuse: %.2f',v));
    set(hPatch3D,'DiffuseStrength',v);
end

function onSpecChange(src,~)
    v = src.Value;
    hPatch3D  = getappdata(parent,'hPatchBase3D');
    set(hSpecTxt,'String',sprintf('SpecStr: %.2f',v));
    set(hPatch3D,'SpecularStrength',v);
end

function onSpecExpChange(src,~)
    v = src.Value;
    hPatch3D  = getappdata(parent,'hPatchBase3D');
    set(hSpecExpTxt,'String',sprintf('SpecExp: %.0f',v));
    set(hPatch3D,'SpecularExponent',v);
end

function onSave3DSettings(~, ~)
    try
        % --- Basic guards ---
        if ~isgraphics(h3DAx, 'axes')
            errordlg('3D axes not available. Switch to 3D view first.','Save 3D Settings');
            return;
        end

        % --- Camera / View ---
        [az, el] = view(h3DAx);
        settings3D.view.az        = az;
        settings3D.view.el        = el;
        settings3D.view.campos    = campos(h3DAx);
        settings3D.view.camtarget = camtarget(h3DAx);
        settings3D.view.camup     = camup(h3DAx);
        settings3D.view.camva     = camva(h3DAx);
        settings3D.view.camproj   = camproj(h3DAx);   % 'perspective' or 'orthographic'

        % --- Axes / Background ---
        settings3D.axes.color     = get(h3DAx, 'Color');

        % --- Threshold sliders (neg/pos/global thr) ---
        % (These handles exist in your code snippet.)
        settings3D.thresholds.neg = get(hNegSlider, 'Value');
        settings3D.thresholds.pos = get(hPosSlider, 'Value');
        settings3D.thresholds.thr = get(hThrSlider, 'Value');

        % --- Depth slider (optional; only if you have a handle) ---
        if exist('hDepthSlider','var') && isgraphics(hDepthSlider)
            settings3D.depthMM = get(hDepthSlider,'Value');
        else
            settings3D.depthMM = [];
        end

        % --- Light controls (optional; pulled from your handles if present) ---
        if exist('hLightAz','var') && isgraphics(hLightAz)
            settings3D.light.az = get(hLightAz,'Value');
        else
            settings3D.light.az = [];
        end
        if exist('hLightEl','var') && isgraphics(hLightEl)
            settings3D.light.el = get(hLightEl,'Value');
        else
            settings3D.light.el = [];
        end
        if exist('h3DAlpha','var') && isgraphics(h3DAlpha)
            settings3D.light.alpha = get(h3DAlpha,'Value');
        else
            settings3D.light.alpha = [];
        end

        % --- Material (base brain patch) ---
        % You store this in appdata(parent,'hPatchBase3D') in your code.
        hPatchBase = getappdata(parent, 'hPatchBase3D');
        if isgraphics(hPatchBase,'patch')
            settings3D.material.AmbientStrength  = get(hPatchBase,'AmbientStrength');
            settings3D.material.DiffuseStrength  = get(hPatchBase,'DiffuseStrength');
            settings3D.material.SpecularStrength = get(hPatchBase,'SpecularStrength');
            settings3D.material.SpecularExponent = get(hPatchBase,'SpecularExponent');
        else
            settings3D.material = struct();
        end

        % --- Overlay transparency hint (best-effort; optional) ---
        % Try to locate an overlay patch and capture a simple alpha setting.
        hov = findobj(h3DAx, 'Type','patch', '-regexp', 'Tag', 'overlay|patchOverlay');
        if ~isempty(hov)
            hov = hov(1);
            settings3D.overlay.FaceAlpha   = get(hov,'FaceAlpha');   % may be 'interp' or numeric
            settings3D.overlay.AlphaData   = [];                     % too large to save routinely
            settings3D.overlay.AlphaMethod = get(hov,'FaceAlpha');   % duplicate for clarity
        else
            settings3D.overlay = struct();
        end
        settings3D.overlay.alpha = alphaVal;

        % --- Rotate/Pan/Zoom states aren’t required; camera props capture the view ---

        % --- Meta ---
        settings3D.timestamp = datestr(now, 30); % yyyymmddTHHMMSS
        settings3D.version   = 1;

        % --- Choose file and save ---
        [fn, fp] = uiputfile({'*.mat','MAT-file (*.mat)'}, 'Save 3D Settings As...', 'nm3d_settings.mat');
        if isequal(fn,0), return; end
        file = fullfile(fp, fn);
        save(file, 'settings3D');
        msgbox(sprintf('3D settings saved:\n%s', file), 'Save 3D Settings', 'help');

    catch ME
        errordlg(sprintf('Failed to save 3D settings:\n\n%s', ME.message), 'Save 3D Settings');
    end
end

function onLoad3DSettings(~, ~)
    try
        [fn, fp] = uigetfile({'*.mat','MAT-file (*.mat)'}, 'Load 3D Settings');
        if isequal(fn,0), return; end
        file = fullfile(fp, fn);
        L = load(file, 'settings3D');
        if ~isfield(L, 'settings3D') || ~isstruct(L.settings3D)
            errordlg('Selected file does not contain a valid settings struct settings3D.','Load 3D Settings');
            return;
        end
        settings3D = L.settings3D;

        % --- Axes guard ---
        if ~isgraphics(h3DAx,'axes')
            errordlg('3D axes not available. Switch to 3D view first.','Load 3D Settings');
            return;
        end

        % ===== 1) CAMERA / VIEW =====
        if isfield(settings3D,'view')
            if isfield(settings3D.view,'camproj'), camproj(h3DAx, settings3D.view.camproj); end
            if isfield(settings3D.view,'campos'),  campos(h3DAx,  settings3D.view.campos);  end
            if isfield(settings3D.view,'camtarget'), camtarget(h3DAx, settings3D.view.camtarget); end
            if isfield(settings3D.view,'camup'),    camup(h3DAx,    settings3D.view.camup);    end
            if isfield(settings3D.view,'camva'),    camva(h3DAx,    settings3D.view.camva);    end
            % Also apply az/el if present (keeps UI sliders in sync later)
            if isfield(settings3D.view,'az') && isfield(settings3D.view,'el')
                view(h3DAx, settings3D.view.az, settings3D.view.el);
            end
        end

        % ===== 2) AXES / BACKGROUND =====
        if isfield(settings3D,'axes') && isfield(settings3D.axes,'color')
            set(h3DAx,'Color', settings3D.axes.color);
        end

        % ===== 3) THRESHOLD SLIDERS =====
        if isfield(settings3D,'thresholds')
            if isfield(settings3D.thresholds,'neg') && isgraphics(hNegSlider)
                set(hNegSlider, 'Value', settings3D.thresholds.neg);
                onNegChange(hNegSlider, []);
            end
            if isfield(settings3D.thresholds,'pos') && isgraphics(hPosSlider)
                set(hPosSlider, 'Value', settings3D.thresholds.pos);
                onPosChange(hPosSlider, []);
            end
            if isfield(settings3D.thresholds,'thr') && isgraphics(hThrSlider)
                set(hThrSlider, 'Value', settings3D.thresholds.thr);
                onThrChange(hThrSlider, []);
            end
        end

        % ===== 4) DEPTH SLIDER =====
        if isfield(settings3D,'depthMM') && exist('hDepthSlider','var') && isgraphics(hDepthSlider)
            set(hDepthSlider,'Value', settings3D.depthMM);
            onDepthChange(hDepthSlider, []);
        end

        % ===== 5) LIGHTING CONTROLS =====
        if isfield(settings3D,'light')
            if isfield(settings3D.light,'az') && exist('hLightAz','var') && isgraphics(hLightAz)
                set(hLightAz,'Value', settings3D.light.az);
            end
            if isfield(settings3D.light,'el') && exist('hLightEl','var') && isgraphics(hLightEl)
                set(hLightEl,'Value', settings3D.light.el);
            end
            if isfield(settings3D.light,'alpha3D') && exist('h3DAlpha','var') && isgraphics(h3DAlpha)
                alpha3D = settings3D.light.alpha;
            end
            % Recompute light from sliders
            onLightChange([], []);
        end
                

        % ===== 6) MATERIAL (BRAIN SURFACE) =====
        hPatchBase = getappdata(parent,'hPatchBase3D');
        if isgraphics(hPatchBase,'patch') && isfield(S,'material')
            if isfield(settings3D.material,'AmbientStrength')
                set(hPatchBase,'AmbientStrength', settings3D.material.AmbientStrength);
                if isgraphics(hAmbientTxt), set(hAmbientTxt,'String',sprintf('Ambient: %.2f',settings3D.material.AmbientStrength)); end
            end
            if isfield(settings3D.material,'DiffuseStrength')
                set(hPatchBase,'DiffuseStrength', settings3D.material.DiffuseStrength);
                if isgraphics(hDiffuseTxt), set(hDiffuseTxt,'String',sprintf('Diffuse: %.2f',settings3D.material.DiffuseStrength)); end
            end
            if isfield(settings3D.material,'SpecularStrength')
                set(hPatchBase,'SpecularStrength', settings3D.material.SpecularStrength);
                if isgraphics(hSpecTxt), set(hSpecTxt,'String',sprintf('SpecStr: %.2f',settings3D.material.SpecularStrength)); end
            end
            if isfield(settings3D.material,'SpecularExponent')
                set(hPatchBase,'SpecularExponent', settings3D.material.SpecularExponent);
                if isgraphics(hSpecExpTxt), set(hSpecExpTxt,'String',sprintf('SpecExp: %.0f',settings3D.material.SpecularExponent)); end
            end
        end

        % ===== 7) UPDATE UI SLIDERS FOR AZ/EL (if you have them) =====
        % If you keep separate sliders for azimuth/elevation, sync them:
        if isfield(settings3D,'view')
            if exist('hAzim','var') && isgraphics(hAzim) && isfield(settings3D.view,'az')
                set(hAzim,'Value', settings3D.view.az);
                onAzimChange(hAzim, []);
            end
            if exist('hElev','var') && isgraphics(hElev) && isfield(settings3D.view,'el')
                set(hElev,'Value', settings3D.view.el);
                onElevChange(hElev, []);
            end
        end

        % ===== 8) OVERLAY ALPHA (best-effort) =====
        if isfield(settings3D,'overlay') && isfield(settings3D.overlay,'FaceAlpha')
            hov = findobj(h3DAx, 'Type','patch', '-regexp', 'Tag', 'overlay|patchOverlay');
            if ~isempty(hov)
                alphaVal = settings3D.overlay.alpha;
                set(hov(1),'FaceAlpha', settings3D.overlay.FaceAlpha);
                % Recoloring routine if needed
                if exist('update3DColors','file') || exist('update3DColors','builtin')
                    update3DColors();
                end
            end
        end

        drawnow;
        msgbox(sprintf('3D settings loaded from:\n%s', file), 'Load 3D Settings', 'help');

    catch ME
        errordlg(sprintf('Failed to load 3D settings:\n\n%s', ME.message), 'Load 3D Settings');
    end
end

function onReset3DSettings(~, ~)
    try
        if ~isgraphics(h3DAx,'axes')
            errordlg('3D axes not available. Switch to 3D view first.', 'Reset 3D Settings');
            return;
        end

        defs3D = defaults3D();

        % ===== Camera / View =====
        camproj(h3DAx, defs3D.view.camproj);
        view(h3DAx, defs3D.view.az, defs3D.view.el);    % sets az/el first
        camva(h3DAx, defs3D.view.camva);           % then FOV
        % (campos/camtarget/camup are left as-is so the brain stays centered)

        % Sync az/el sliders if you have them
        if exist('hAzim','var') && isgraphics(hAzim)
            set(hAzim,'Value', defs3D.view.az);
            onAzimChange(hAzim,[]);
        end
        if exist('hElev','var') && isgraphics(hElev)
            set(hElev,'Value', defs3D.view.el);
            onElevChange(hElev,[]);
        end

        % ===== Background =====
        set(h3DAx,'Color', defs3D.axes.color);

        % ===== Threshold sliders =====
        if isgraphics(hNegSlider)
            set(hNegSlider,'Value', defs3D.thresholds.neg);
            onNegChange(hNegSlider,[]);
        end
        if isgraphics(hPosSlider)
            set(hPosSlider,'Value', defs3D.thresholds.pos);
            onPosChange(hPosSlider,[]);
        end
        if isgraphics(hThrSlider)
            set(hThrSlider,'Value', defs3D.thresholds.thr);
            onThrChange(hThrSlider,[]);
        end

        % ===== Depth =====
        if exist('hDepthSlider','var') && isgraphics(hDepthSlider)
            set(hDepthSlider,'Value', defs3D.depthMM);
            onDepthChange(hDepthSlider,[]);
        end

        % ===== Lighting (set slider values, then apply via onLightChange) =====
        if exist('hLightAz','var') && isgraphics(hLightAz)
            set(hLightAz,'Value', defs3D.light.az);
        end
        if exist('hLightEl','var') && isgraphics(hLightEl)
            set(hLightEl,'Value', defs3D.light.el);
        end
        if exist('h3DAlpha','var') && isgraphics(h3DAlpha)
            set(h3DAlpha,'Value', defs3D.light.alpha); alpha3D = defs3D.light.alpha;
        end
        onLightChange([],[]);

        % ===== Material (brain surface) =====
        hPatchBase = getappdata(parent,'hPatchBase3D');
        if isgraphics(hPatchBase,'patch')
            set(hPatchBase, ...
                'AmbientStrength',  defs3D.material.AmbientStrength, ...
                'DiffuseStrength',  defs3D.material.DiffuseStrength, ...
                'SpecularStrength', defs3D.material.SpecularStrength, ...
                'SpecularExponent', defs3D.material.SpecularExponent);
            % Keep your text readouts in sync if present
            if exist('hAmbientTxt','var') && isgraphics(hAmbientTxt)
                set(hAmbientTxt,'String',sprintf('Ambient: %.2f',defs3D.material.AmbientStrength));
            end
            if exist('hDiffuseTxt','var') && isgraphics(hDiffuseTxt)
                set(hDiffuseTxt,'String',sprintf('Diffuse: %.2f',defs3D.material.DiffuseStrength));
            end
            if exist('hSpecTxt','var') && isgraphics(hSpecTxt)
                set(hSpecTxt,'String',sprintf('SpecStr: %.2f',defs3D.material.SpecularStrength));
            end
            if exist('hSpecExpTxt','var') && isgraphics(hSpecExpTxt)
                set(hSpecExpTxt,'String',sprintf('SpecExp: %.0f',defs3D.material.SpecularExponent));
            end
        end

        set(hAlphaValue, 'Value', defs3D.overlay.alpha); alphaVal = defs3D.overlay.alpha;

        % Recompute overlay colors if your pipeline requires it
        if exist('update3DColors','file') || exist('update3DColors','builtin')
            update3DColors();
        end

        drawnow;

    catch ME
        errordlg(sprintf('Failed to reset 3D settings:\n\n%s', ME.message), 'Reset 3D Settings');
    end
end

function defs3D = defaults3D()

    % Camera/view defaults
    defs3D.view.az      = -90;          % azimuth (left view)
    defs3D.view.el      =  20;          % elevation
    defs3D.view.camproj = 'perspective';
    defs3D.view.camva   = 10;           % camera view angle (deg)

    % Background
    defs3D.axes.color   = [1 1 1];      % white

    % Thresholds (adjust to your typical ranges)
    defs3D.thresholds.neg = -2.0;
    defs3D.thresholds.pos =  2.0;
    defs3D.thresholds.thr =  0.0;

    % Depth (mm) if you use it
    defs3D.depthMM = 0;

    % Lighting controls (sliders set these; onLightChange will apply)
    defs3D.light.az =  45;
    defs3D.light.el =  30;
    defs3D.light.alpha = 0.7;

    % Brain surface material
    defs3D.material.AmbientStrength  = 0.30;
    defs3D.material.DiffuseStrength  = 0.70;
    defs3D.material.SpecularStrength = 0.20;
    defs3D.material.SpecularExponent = 25;
    
    % Stats image parameters
    defs3D.overlay.alpha = 0.5;

end


function position3DControls()
 
    if ~isgraphics(h3DAx,'axes'), return; end

    % Get absolute pixel box of the axes (accounts for parent layout)
    axPix = getpixelposition(h3DAx, true);   % [x y w h] in screen pixels

    % Control sizes (pixels)
    w   = 110;        % column width
    h   = 15;         % row height
    gap = 6;          % vertical spacing
    mX  = 12;         % margin left of axes

    % Left of axes, stacked downward from top-left corner
    x = max(0, axPix(1) +120 - w - mX);
    yTop = axPix(2) + axPix(4) - 40;

    set(hLightAzLbl, 'Units','pixels', 'Position',[x, yTop-1*h,          w, h], 'Visible','on');
    set(hLightAz,    'Units','pixels', 'Position',[x, yTop-2*h-gap,      w, h], 'Visible','on');
    set(hLightElLbl, 'Units','pixels', 'Position',[x, yTop-3*h-2*gap,    w, h], 'Visible','on');
    set(hLightEl,    'Units','pixels', 'Position',[x, yTop-4*h-3*gap,    w, h], 'Visible','on');
    set(h3DAlphaLbl, 'Units','pixels', 'Position',[x, yTop-5*h-4*gap,    w, h], 'Visible','on');
    set(h3DAlpha,    'Units','pixels', 'Position',[x, yTop-6*h-5*gap,    w, h], 'Visible','on');
    set(hBtnRecord,  'Units','pixels', 'Position',[x, yTop-7*h-6*gap-5,    w, h], 'Visible','on');
    set(hOverlayMode,'Units','pixels', 'Position',[x, yTop-8*h-7*gap-10,    w, h], 'Visible','on');
    set(hZoomIn,     'Units','pixels', 'Position',[x+30, yTop-9*h-8*gap-25, 28, 28], 'Visible','on')
    set(hZoomOut,    'Units','pixels', 'Position',[x+60, yTop-9*h-8*gap-25, 28, 28], 'Visible','on');
    set(hHome3D,     'Units','pixels', 'Position',[x+15, yTop-10*h-9*gap-35, 28, 28], 'Visible','on');
    set(hSave3D,     'Units','pixels', 'Position',[x+45, yTop-10*h-9*gap-35, 28, 28], 'Visible','on')
    set(hLoad3D,     'Units','pixels', 'Position',[x+75, yTop-10*h-9*gap-35, 28, 28], 'Visible','on');

end

function setupWorldLights()
    if ~isgraphics(h3DAx,'axes'), return; end
    set(ancestor(h3DAx,'figure'),'Renderer','opengl');

    % Try reuse
    L = getappdata(h3DAx,'worldLights');
    ok = isstruct(L) && all(isgraphics([L.key L.fill L.rim]));
    if ~ok
        delete(findobj(h3DAx,'Type','light'));
        L.key  = light('Parent',h3DAx,'Style','infinite','Color',[1 1 1]);
        L.fill = light('Parent',h3DAx,'Style','infinite','Color',[0.6 0.6 0.6]);
        L.rim  = light('Parent',h3DAx,'Style','infinite','Color',[0.6 0.6 0.8]);
        setappdata(h3DAx,'worldLights',L);
    end

    % Use slider values if available
    az = get(hLightAz,'Value');
    el = get(hLightEl,'Value');
    lightangle(L.key,  az,  el);
    lightangle(L.fill, -60, 10);
    lightangle(L.rim,  180,  0);
end

function onRotate3D(~,~)
    % Keep sliders in sync with current view
    if exist('h3DAx','var') && isgraphics(h3DAx,'axes')
        [az, el] = view(h3DAx);
        set(hAzimSlider,'Value', mod(az,360));
        set(hAzimTxt,'String', sprintf('Azimuth: %.0f°', mod(az,360)));
        set(hElevSlider,'Value', max(min(el,90),-90));
        set(hElevTxt,'String', sprintf('Elevation: %.0f°', el));
        update3Dcolors();
    end
end

function onStructSelect(src,~)
    idx   = src.Value;
    names = src.String;
    if idx < numel(names)
        % one of the *_struct.nii files
        structFile = fullfile(structDir, names{idx});
        onLoadStruct([],[], structFile);
    else
        % “Browse…” selected
        onLoadStruct();  % opens dialog
    end
end

% function [fig, innerSquare] = lockSquareCanvas(ax3D, ST)
%     %--- fixed limits with pad (avoid clipping while rotating)
%     [Nx, Ny, Nz] = size(ST);
%     pad = 0.12 * max([Nx Ny Nz]);                % 12% pad; tweak if needed
%     xlim(ax3D,[1-pad, Nx+pad]);
%     ylim(ax3D,[1-pad, Ny+pad]);
%     zlim(ax3D,[1-pad, Nz+pad]);
%     set(ax3D,'XLimMode','manual','YLimMode','manual','ZLimMode','manual');
% 
%     %--- stable camera + geometry
%     set(ax3D,'Projection','orthographic', ...
%              'CameraViewAngleMode','manual', ...
%              'CameraPositionMode','manual', ...
%              'CameraTargetMode','manual', ...
%              'CameraUpVectorMode','manual', ...
%              'DataAspectRatioMode','manual', ...
%              'PlotBoxAspectRatioMode','manual', ...
%              'ActivePositionProperty','position');
%     daspect(ax3D,[1 1 1]); 
%     pbaspect(ax3D,[1 1 1]); 
%     axis(ax3D,'vis3d');           % freeze view-angle on any resize
%     axis(ax3D,'off');
% 
%     %--- figure/axes in integer pixels
%     fig = ancestor(ax3D,'figure');
%     set(fig,'Units','pixels','Resize','off','GraphicsSmoothing','off');
%     set(ax3D,'Units','pixels');
% 
%     % Get current axes rectangle in figure coords
%     outer = getpixelposition(ax3D, true);        % [x y w h] (pixels, possibly non-integer)
% 
%     % Build a centered **square** inner plot box
%     side  = floor(min(outer(3), outer(4)));
%     x0    = round(outer(1) + (outer(3)-side)/2);
%     y0    = round(outer(2) + (outer(4)-side)/2);
%     innerSquare = [x0 y0 side side];
% 
%     % Tell MATLAB to honor the InnerPosition as the plot box
%     ax3D.PositionConstraint = 'innerposition';
%     ax3D.InnerPosition      = innerSquare;
% 
%     drawnow;  % commit geometry
% end

function onLoadStruct(src,~,newStructFile)
    
    % If a path was passed in, use it; otherwise pop up the file picker
    if nargin>=3 && ~isempty(newStructFile)
        structFileSel = newStructFile;
    else
        [file,path] = uigetfile( ...
            {'*.nii;*.hdr','NIfTI files (*.nii,*.hdr)';'*.*','All Files'}, ...
            'Select structural image');
        if isequal(file,0)
            return;  % user cancelled
        end
        structFileSel = fullfile(path,file);
    end

    % make sure structFileSel is an absolute, existing path ---
    if ~isfile(structFileSel)
        [sd,sf,se] = fileparts(structFileSel);
        if isempty(sd)
            structFileSel = fullfile(pwd, [sf se]);  % resolve bare name like "temp.nii"
        else
            structFileSel = fullfile(sd, [sf se]);   % normalize any relative pieces
        end
    end
    assert(exist(structFileSel,'file')==2, 'Structural not found: %s', structFileSel);

    % Now reload the structural volume
    Vs      = spm_vol(structFileSel);
    ST       = spm_read_vols(Vs);
    smin = min(ST(:)); smax = max(ST(:)); st.globalStructRange = [smin smax];
    dims    = Vs.dim;            % update global dims

    % Update your slice‐slider limits
    maxSlices.axial    = dims(3);
    maxSlices.sagittal = dims(1);
    maxSlices.coronal  = dims(2);
    if ~strcmp(viewmode,'3d-view')
        if exist("hSlice",'var')
            set(hSlice, ...
                'Min',1, ...
                'Max',maxSlices.(viewmode), ...
                'Value',ceil(maxSlices.(viewmode)/2), ...
                'SliderStep',[1/(maxSlices.(viewmode)-1) .1]);   
        end
        sliceIdx = ceil(dims(3)/2);
    end

    % Re‐reslice your stat map to match the NEW anatomy (absolute paths!)
    [d,fn,ext] = fileparts(statFile);
    if startsWith(fn,'r'), fn = extractAfter(fn,1); end
    statPath   = fullfile(d, [fn ext]);
    assert(exist(statPath,'file')==2, 'Stat map not found: %s', statPath);

    % First row = reference (new structural), second = moving (stat map)
    P = char(structFileSel, statPath);

    % Flags: no mean image, write only resliced moving image with 'r' prefix
    flags = struct('interp',1,'which',1,'mean',0,'mask',0,'prefix','r');

    try
        spm_reslice(P, flags);
    catch ME
        warning('spm_reslice failed.\nref: %s\nmov: %s\nerr: %s', strtrim(P(1,:)), strtrim(P(2,:)), ME.message);
        rethrow(ME);
    end

    rStat = fullfile(d, ['r' fn ext]);

    Vt   = spm_vol(rStat);
    T0   = spm_read_vols(Vt);
    T    = T0 * Vt.pinfo(1) + Vt.pinfo(2);
    T    = cast(T, spm2matlabclass(Vt.dt(1)));
    Tmin = min(T(:));  Tmax = max(T(:));
    hasNeg = Tmin<0;   hasPos = Tmax>0;

    % reset thresholds if you like, or leave them
    if hasNeg && hasPos
      thrNeg = prctile(T(T<0),10);
      thrPos = prctile(T(T>0),90);
    elseif hasPos
      thrNeg = 0;
      thrPos = prctile(T(:),90);
    else
      thrNeg = prctile(T(:),10);
      thrPos = 0;
    end

    rngT = Tmax - Tmin;
    if ~isfinite(rngT) || rngT == 0, rngT = 1; end
    epsR  = max(1e-6, 1e-6 * max(1, abs(Tmax)));
    
    % Clamp into valid range
    if hasPos
        if ~isfinite(thrPos) || isempty(thrPos), thrPos = Tmin + 0.9*rngT; end
        thrPos = min(max(thrPos, Tmin + epsR), Tmax - epsR);
    end
    if hasNeg
        if ~isfinite(thrNeg) || isempty(thrNeg), thrNeg = Tmin + 0.1*rngT; end
        thrNeg = min(max(thrNeg, Tmin + epsR), Tmax - epsR);
    end
    
    % Enforce strict increase for bipolar window
    if hasPos && hasNeg
        gap = max(epsR, 1e-3 * rngT);        % tiny positive gap
        if ~(thrNeg < thrPos - gap)
            % center around 0 if possible, otherwise around mid‑range
            c = 0;
            if c <= Tmin || c >= Tmax, c = (Tmin + Tmax)/2; end
            thrNeg = c - gap/2;
            thrPos = c + gap/2;
            % keep inside data range
            thrNeg = max(thrNeg, Tmin + epsR);
            thrPos = min(thrPos, Tmax - epsR);
            if thrNeg >= thrPos, thrNeg = thrPos - epsR; end
        end
    end

    % Invalidate 3D cache on data changes
    if isappdata(parent,'hPatch3DBase')
        hp = getappdata(parent,'hPatch3DBase');
        if isgraphics(hp), delete(hp); end
        rmappdata(parent,'hPatch3DBase');
    end
    if isappdata(parent,'hPatch3D')
        hp = getappdata(parent,'hPatch3D');
        if isgraphics(hp), delete(hp); end
        rmappdata(parent,'hPatch3D');
    end
    if isappdata(parent,'hVol3D')
        hp = getappdata(parent,'hVol3D');
        if isgraphics(hp), delete(hp); end
        rmappdata(parent,'hVol3D');
    end
    if isappdata(parent,'meshSpace'), rmappdata(parent,'meshSpace'); end
    if isappdata(parent,'brainMask'), rmappdata(parent,'brainMask'); end
    if isappdata(parent,'Scl'), rmappdata(parent,'Scl'); end
    if isappdata(parent,'fv3D'), rmappdata(parent,'fv3D'); end
    if isappdata(parent,'vnorm_struct'), rmappdata(parent,'vnorm_struct'); end
    setappdata(parent,'Vs_hdr',Vs)

    % Finally redraw everything
    trigBrainRebuild = true;
    trigSurfRebuild = true;
    trigVolRebuild = true;

    requestRedraw();

end

% Callback definitions
function onLoadAtlas(~,~, atlasFile)

    % Prompt for NIfTI atlas
    if isempty(atlasFile) || ~exist(atlasFile,'file')
        [fn,pn] = uigetfile({'*.nii;*.nii.gz','NIfTI atlas files'}, 'Select Atlas');
        if isequal(fn,0), return; end
        % Full path
        atlasFile = fullfile(pn,fn);
    end

    % Load atlas volume
    try
        
        % 1) Build a filename r<atlas>.nii next to the atlas
        VatOrig = spm_vol(atlasFile);  
        AtlasOrig = spm_read_vols(VatOrig).*VatOrig.pinfo(1) + VatOrig.pinfo(2);

        % Try to load a LUT file <name>_LUT.txt next to atlas
        lutFile = findAtlasLUT(atlasFile);
        if ~isempty(lutFile)
            lut = readAtlasLUTAuto(lutFile);
        else
            warning('No LUT found for %s', atlasFile);
            lut = containers.Map('KeyType','double','ValueType','char');
        end

        % Give user feedback
        set(hRegLabel,'String','Region: (click on image)');
        set([hSilToggle, hSilColor, hSilColorTxt], 'Enable', 'on');
        set([hExportBtn, hFilterLbl hMinPct], 'Enable', 'on');

    catch ME
        errordlg(['Failed to load atlas:' ME.message],'Atlas Error');
        return;
    end

    % Make atlas + LUT available to 3D callbacks
    setappdata(parent,'VatOrig',   VatOrig);
    setappdata(parent,'AtlasOrig', AtlasOrig);
    setappdata(parent,'roiLUT',    lut);

    % Force a redraw so clicks will now use the new Vat & lut
    requestRedraw();
end

function onSilToggle(src,~)
    silOn = logical(src.Value);
    if silOn
        state = 'on';
    else
        state = 'off';
    end
    set([hSilColor,hSilColorTxt], 'Enable', state);
    requestRedraw();
end

function onSilColor(src,~)
    silB = src.Value; 
    requestRedraw();
end

function onIsoToggle(src,~)
    isoOn = logical(src.Value);
    if isoOn, hIsoEdit.Enable = 'on'; else, hIsoEdit.Enable = 'off'; end 
    requestRedraw();
end

function onIsoEdit(src,~)
    requestRedraw();
end

function onCrossToggle(src,~)
    crossOn = logical(src.Value);
    % find the containing figure (since src.Parent might be a panel)
    hFig = ancestor(src, 'figure');
    if crossOn
        hFig.WindowButtonMotionFcn = @onMouseMove;
    else
        % restore the original motion callback
        hFig.WindowButtonMotionFcn = getappdata(parent,'OrigWBMFcn');
        delete([hCrossX,hCrossY]);
        hCrossX=[]; hCrossY=[];
    end
end

function onMouseMove(~,~)
    if ~crossOn, return; end

    % Only respond when pointer is over our slice axes
    hObj = hittest(hFig);
    ax   = ancestor(hObj,'axes');
    if ax~=hAx, return; end

    % Get pointer position in data units
    cp  = hAx.CurrentPoint;
    col = cp(1,1);
    row = cp(1,2);

    % Use the axes limits instead of A size
    xL = get(hAx,'XLim');    % [minX maxX]
    yL = get(hAx,'YLim');    % [minY maxY]
    if col < xL(1) || col > xL(2) || row < yL(1) || row > yL(2)
        return;
    end

    % Remove previous crosshairs
    delete([hCrossX,hCrossY]);

    % Draw new blue crosshair spanning the full axes
    hCrossX = line(hAx, xL, [row row], 'Color','b', 'HitTest','off');
    hCrossY = line(hAx, [col col], yL, 'Color','b', 'HitTest','off');
end

function onExportROI(~,~)
    
    minPct = str2double(get(hMinPct,'String'));
    if isnan(minPct) || minPct<0, minPct = 0; end

    % Flatten all structural‐space voxels
    [I,J,K]     = ndgrid(1:dims(1),1:dims(2),1:dims(3));
    ijkAll      = [I(:)'; J(:)'; K(:)'];     % 3×N

    % Map to atlas codes
    codesAll    = struct2atlas(ijkAll, Vs, VatOrig, AtlasOrig);  % N×1

    % Flatten stats volume
    Tvec        = T(:);   % N×1

    % Unique nonzero ROIs
    roiCodes    = unique(codesAll(codesAll>0));
    nROI        = numel(roiCodes);

    % Prepare results container
    varNames = {'ROIcode','Name', 'totalVox', 'nPos','nNeg','pctPos','pctNeg','meanStat','stdStat'};
    rows     = cell(nROI, numel(varNames));
    
    u=1; uu=1;
    while u <= nROI
        c      = roiCodes(u);
        mask   = (codesAll == c);
        total  = nnz(mask);           % total voxels in ROI
        vals   = Tvec(mask);          % all stat‐values in ROI

        % counts
        if hasNeg && hasPos
            nPos = nnz(vals >= thrPos);
            nNeg = nnz(vals <= thrNeg);
        elseif hasPos
            nPos = nnz(vals >= thr);
            nNeg = NaN;
        else
            nPos = NaN;
            nNeg = nnz(vals <= thr);
        end

        nStat = sum([nPos nNeg],'omitnan');

        % percentage of ROI voxels that pass threshold
        pctStat = nStat / total * 100;

        % prune if below user cutoff
        if pctStat < minPct || pctStat == 0
            u=u+1;
            continue;
        end

        % percentages
        pctPos = nPos / total * 100;
        pctNeg = nNeg / total * 100;

        % mean & SD of the raw stat‐values
        meanStat = mean(vals);
        stdStat  = std(vals);

        % lookup ROI name
        if lut.isKey(c)
            name = lut(c);
        else
            name = sprintf('ID%d',c);
        end

        % store row
        rows{uu,1} = c;
        rows{uu,2} = name;
        rows{uu,3} = total;
        rows{uu,4} = nPos;
        rows{uu,5} = nNeg;
        rows{uu,6} = pctPos;
        rows{uu,7} = pctNeg;
        rows{uu,8} = meanStat;
        rows{uu,9} = stdStat;
        u=u+1;
        uu=uu+1;
    end

    % Build table
    Ttbl = cell2table(rows,'VariableNames',varNames);

    % Save to .xlsx or .csv
    [fn,fp,fi] = uiputfile({'*.xlsx';'*.csv'},'Save ROI analysis');
    if isequal(fn,0), return; end
    fname = fullfile(fp,fn);
    writetable(Ttbl, fname);
   
    msgbox(['Saved ROI analysis to ' fname], 'Export Complete');
end


function onSliceClick(~,~)

    [i, j, k] = get_ijk4click();
    if isempty(i) || isempty(j) || isempty(k), return; end
    
    if crossOn
        hCrossX.Color = 'r';
        hCrossY.Color = 'r';
    end

    ijk = [i; j; k];
    code = struct2atlas(ijk, Vs, VatOrig, AtlasOrig);
    
    % look up name
    if lut.isKey(code)
      name = lut(code);
    else
      name = sprintf('Code %d',code);
    end
    hRegLabel.String = sprintf('%s (code=%d) at voxel [%d %d %d]', name, code, i, j, k);

end

function onViewChange(~, evt)
    
    % Callback for Axial/Sagittal/Coronal toggle
    
    % 1) Update the view
    viewmode = lower(evt.NewValue.String);
    is3D = strcmp(viewmode,'3d-view');

    if is3D
        vistog = 'on';   
       % hide 2D, show 3D
        set(hAx,'Visible','off'); set(get(hAx,'Children'),'Visible','off');
        set(hSlice,'Visible','off'); set(hSliceLabel,'Visible','off');
        ensure3DScene();
    else
        vistog = 'off';
        
        % hide 3D axes (keep it alive)
        hide3DScene();

        % 2) Reposition the main single‐slice axes
        spos = get(hSlice,'Position');
        set(hAx, 'Position', [spos(1), baseY, spos(3), baseH],'Visible','on');
        set(hAx.Children, 'Visible','on');
        % 3) Compute the new maximum for this orientation
        mx = maxSlices.(viewmode);
    
        % 4) ALWAYS reset the multi-slice range
        %    Start = 1; End = mx
        set(hStartEdit, 'String', '1');
        set(hEndEdit,   'String', num2str(mx));
    
        % 5) If we’re in single-slice mode, also reset the slider there
        if ~isMulti
            idx = ceil(mx/2);
            set(hSlice, ...
                'Min',        1, ...
                'Max',        mx, ...
                'Value',      idx, ...
                'SliderStep', [1/(mx-1) 0.1], ...
                'Enable',     'on', ...
                'Visible',    'on');
            set(hSliceLabel, ...
                'String', sprintf('Slice: %d / %d', idx, mx), ...
                'Enable', 'on', ...
                'Visible','on');
        end
        
    end
    all3D = [hAzimTxt,hAzimSlider, hElevTxt,hElevSlider, ...
             hDepthTxt,hDepthSlider, hBGBtn, ...
             hAmbientTxt,hAmbientSlider, ...
             hDiffuseTxt,hDiffuseSlider, ...
             hSpecTxt,hSpecSlider, ...
             hSpecExpTxt,hSpecExpSlider];

    set(all3D, 'Visible', vistog);
    redraw

end

function buildBrainMesh()
    
    if ~isgraphics(h3DAx,'axes'), return; end
    old = getappdata(parent,'hPatchBase3D');
    if isgraphics(old,'patch'), delete(old); end

    % ---------- 1) Isosurface in VOXELS (base surface) ----------
    Scl = double(ST); Scl(~isfinite(Scl)) = 0;
    smin = min(Scl(:)); smax = max(Scl(:));
    pctList = [50 40 60 30 70 20 80];
    fv = struct('faces',[],'vertices',[]);
    for p = pctList
        isoVal = smin + (p/100)*(smax - smin);
        fvt = isosurface(Scl, isoVal);
        if ~isempty(fvt.vertices), fv = fvt; break; end
    end
    if isempty(fv.vertices)
        warning('3D: no isosurface found.');
        return;
    end
        % ---------- 2) Base glass brain ----------
    hPatchBase3D = patch('Parent',h3DAx, ...
        'Faces', fv.faces, 'Vertices', fv.vertices, ...
        'FaceColor', [0.85 0.85 0.85], ...
        'EdgeColor','none', ...
        'FaceLighting','gouraud', ...
        'BackFaceLighting','reverselit', ...
        'FaceAlpha', alpha3D, ...
        'Visible','on');

    % ---------- 3) Vertex normals in voxel space ----------
    vnorm = get(hPatchBase3D,'VertexNormals');
    if isempty(vnorm)
        hTmp = patch('Faces',fv.faces,'Vertices',fv.vertices,'Visible','off','Parent',h3DAx);
        try, isonormals(Scl,hTmp); vnorm = get(hTmp,'VertexNormals'); catch, vnorm = []; end
        delete(hTmp);
    end
    if isempty(vnorm), vnorm = zeros(size(fv.vertices)); vnorm(:,3) = 1; end
    nv = sqrt(sum(vnorm.^2,2)); nv(nv==0)=1;
    vnorm = vnorm ./ nv;

    % ---------- Cache for later ----------
    setappdata(parent,'fv3D',fv);
    setappdata(parent,'Scl',Scl);
    setappdata(parent,'hPatchBase3D',hPatchBase3D);
    setappdata(parent,'vnorm_struct',vnorm);
    setappdata(parent,'meshSpace','vox');

    axis(h3DAx,'vis3d');
    try, daspect(h3DAx,[1 1 1]); end
    trigBrainRebuild = false;

end

function buildSurfaceMesh()

    if ~isgraphics(h3DAx,'axes'), return; end
    old = getappdata(parent,'hPatch3D');
    if isgraphics(old,'patch'), delete(old); end

    fv = getappdata(parent,'fv3D');
    vnorm = getappdata(parent,'vnorm_struct');
  
    eps_vox = 0.3;
    overlayVerts = fv.vertices + eps_vox * vnorm;
    hPatch3D = patch('Parent',h3DAx, ...
        'Faces', fv.faces, 'Vertices', overlayVerts, ...
        'FaceColor','interp', ...
        'EdgeColor','none', ...
        'FaceLighting','gouraud', ...
        'BackFaceLighting','reverselit', ...
        'FaceAlpha','interp', ...
        'AlphaDataMapping','none', ...
        'Visible','on');

    setappdata(parent,'hPatch3D',hPatch3D);
    % 
    % % ---------- 5) Draw order & camera ----------
    try, set(h3DAx,'SortMethod','depth'); end
    uistack(hPatch3D,'top');
    ctr = mean(fv.vertices,1);
    set(h3DAx,'CameraTarget',ctr,'CameraTargetMode','manual');
    set(h3DAx,'CameraUpVector',[0 0 1],'CameraUpVectorMode','manual');

    trigSurfRebuild = false;
    
end

function buildVolumetricMesh()

    % --- Assumes the following variables are in scope (nested function) ---
    % ST        : template brain volume (from spm_read_vols)
    % T        : statistical volume (same space as ST)
    % h3DAx    : handle to 3D axes
    % hasNeg, hasPos : booleans for bipolar/unipolar
    % hNegEdit, hPosEdit, hThrEdit : uicontrol handles for thresholds
    
    % ---------------------------
    % 1) Decide thresholds
    % ---------------------------
    if hasNeg && hasPos
        thrNeg = str2double(get(hNegEdit,'String'));
        thrPos = str2double(get(hPosEdit,'String'));
    else
        thrPos = str2double(get(hThrEdit,'String'));
        thrNeg = [];
    end

    % ---------------------------
    % 2) Build masks
    % ---------------------------
    % template mask to constrain overlay inside brain
    Scl = getappdata(parent,'Scl');
    old = getappdata(parent,'hVol3D');
    if isgraphics(old,'patch'), delete(old); end

    brainMask = getappdata(parent,'brainMask');
    if isempty(brainMask)
        % Soft mask: no erosion to preserve near-surface clusters
        smin = min(Scl(:)); smax = max(Scl(:));
        iso  = smin + 0.18 * (smax - smin);  % generous brain iso
        brainMask = smooth3(Scl > iso, 'box', 1) > 0.45;
        setappdata(parent,'brainMask',brainMask);
    end

    % stats masks
    Tc = T; Tc(~brainMask) = NaN;
    posMask = false(size(T));
    negMask = false(size(T));

    if ~isempty(thrPos) && isfinite(thrPos)
        posMask = (T >= thrPos) & brainMask;
    end
    if ~isempty(thrNeg) && isfinite(thrNeg)
        negMask = (T <= thrNeg) & brainMask;
    end

    % light fill/close to connect bumps
    posMask = imfill3d_fast(posMask, 1, 1, 0.50, 0, 0);
    negMask = imfill3d_fast(negMask, 1, 1, 0.50, 0, 0);

    % ---------------------------
    % 4) Build meshes & patches
    % ---------------------------
    hVol3D = [];
    
    if any(posMask(:))
        fvP = isosurface(posMask, 0.5);
        if ~isempty(fvP.vertices)
            hPos = patch('Parent', h3DAx, ...
                'Faces', fvP.faces, ...
                'Vertices', fvP.vertices, ...
                'FaceColor', [1 0 0], ...
                'EdgeColor', 'none', ...
                'FaceAlpha', 0.5, ...
                'SpecularStrength', 0.1);
            hVol3D = [hVol3D hPos];
        end
    end

    if any(negMask(:))
        fvN = isosurface(negMask, 0.5);
        if ~isempty(fvN.vertices)
            hNeg = patch('Parent', h3DAx, ...
                'Faces', fvN.faces, ...
                'Vertices', fvN.vertices, ...
                'FaceColor', [0 0 1], ...
                'EdgeColor', 'none', ...
                'FaceAlpha', 0.5, ...
                'SpecularStrength', 0.1);
            hVol3D = [hVol3D hNeg];
        end
    end
    if numel(hVol3D)>1
        vertsAll = {};
        facesAll = {};
        vOffset = 0;
        for k = 1:numel(hVol3D)
            vertsAll{end+1} = get(hVol3D(k),'Vertices'); 
            facesAll{end+1} = get(hVol3D(k),'Faces') + vOffset; 
            vOffset = vOffset + size(vertsAll{k},1);
        end
        mergedFV.faces    = vertcat(facesAll{:});
        mergedFV.vertices = vertcat(vertsAll{:});
        hMerged = patch('Parent', h3DAx, ...
            'Faces', mergedFV.faces, ...
            'Vertices', mergedFV.vertices, ...
            'FaceColor', [1 1 1]*0.8, ... % placeholder color (will be replaced by update3DColors)
            'EdgeColor', 'none', ...
            'FaceAlpha', 0.5, ...
            'SpecularStrength', 0.1);
        delete(hVol3D(ishandle(hVol3D)));
        hVol3D = hMerged;
    end
    if isempty(hVol3D)
        setappdata(parent,'hVol3D',[]);
        return
    else
        setappdata(parent,'hVol3D',hVol3D);
    end

    trigVolRebuild = false;
end

function B = imfill3d_fast(Bin, r, nClose, majThr, sWin, sThr)
% IMFILL3D_FAST  Fast, toolbox‑free 3‑D "connect & smooth" (no flood fill).
%   B = imfill3d_fast(Bin, r, nClose, majThr, sWin, sThr)
%   Bin    : logical 3‑D mask
%   r      : closing radius (voxels). default = 1  (3x3x3)
%   nClose : # of closing passes.    default = 2
%   majThr : majority threshold (0..1 of neighbors). default = 0.55
%   sWin   : smooth3 box window (odd). default = 3
%   sThr   : threshold after smoothing. default = 0.5
%
% Notes:
%  - This *does not* do cavity filling; it just connects bumps and rounds edges.
%  - For typical fMRI clusters, r=1..2 and nClose=1..2 are plenty.
%  - Keep things cropped to a bounding box before calling for best speed.

    if nargin<2 || isempty(r),       r = 1;     end
    if nargin<3 || isempty(nClose),  nClose = 2;end
    if nargin<4 || isempty(majThr),  majThr = 0.55; end
    if nargin<5 || isempty(sWin),    sWin = 3;  end
    if nargin<6 || isempty(sThr),    sThr = 0.5; end

    B = logical(Bin);

    % --- nClose passes of 3‑D closing (dilate then erode) ---
    k = ones(2*r+1, 2*r+1, 2*r+1, 'double');
    fullVal = numel(k);
    for p = 1:nClose
        % dilate
        C = convn(double(B), k, 'same');
        B = C > 0;
        % erode
        C = convn(double(B), k, 'same');
        B = C >= fullVal;
    end

    % --- Majority filter in 3‑D (connect stragglers; cheap) ---
    C = convn(double(B), ones(3,3,3), 'same'); % 3×3×3 neighborhood
    B = C >= ceil(27*majThr);

    % --- Light smoothing (base MATLAB) ---
    if sWin >= 3
        B = smooth3(B, 'box', sWin) > sThr;
    end
end

function ensure3DScene()

    if ~isgraphics(h3DAx,'axes'), return; end
    set(h3DAx,'Visible','on');

    % Early-out if a rotation is in progress (avoid rebuilds on mouse-up)   
    if isappdata(h3DAx,'isRotating') && getappdata(h3DAx,'isRotating')
        % Queue a rebuild request to be executed on rotate post-callback
        setappdata(h3DAx,'pendingUpdate', true);
        return;
    end

    % 1) Renderer setup
    L = getappdata(h3DAx,'worldLights');
    rigOK = isstruct(L) && all(isfield(L,{'key','fill','rim'})) && ...
            all(isgraphics([L.key L.fill L.rim]));
    if ~rigOK
        setupWorldLights();
        L = getappdata(h3DAx,'worldLights');
    end
    if isstruct(L)
        set([L.key L.fill L.rim], 'Visible','on', 'Parent', h3DAx);
        az = 45; el = 30;
        if isgraphics(hLightAz), az = get(hLightAz,'Value'); end
        if isgraphics(hLightEl), el = get(hLightEl,'Value'); end
        lightangle(L.key, az, el);
    end
    lighting(h3DAx,'gouraud');
    material(h3DAx,'dull');

    % 2) Overlay mode check
    overlayMode = 0; % default
    if exist('hOverlayMode','var') && isgraphics(hOverlayMode)
        overlayMode = get(hOverlayMode,'Value'); % 0 = cortical, 1 = volumetric
    end

    % Fetch anything we might already have
    hBase = getappdata(parent,'hPatchBase3D');   % glass brain
    hProj = getappdata(parent,'hPatch3D');       % cortical projection overlay
    hVol  = getappdata(parent,'hVol3D');         % volumetric overlay (can be [hPos hNeg])
    
    if isempty(hBase) || ~any(isgraphics(hProj)) || trigBrainRebuild
        buildBrainMesh()
    end

    if overlayMode == 0
        % ===== Cortical projection mode =====
        if isempty(hProj) || ~any(isgraphics(hProj)) || trigSurfRebuild
            buildSurfaceMesh();                       % must set hPatchBase3D & hPatch3D in appdata
        end
        % show projection + base, hide volumetric
        setVisible(hVol,  'off');
        setVisible(hProj, 'on');
        setVisible(hBase, 'on');                 % set to 'off' if you want projection-only
    
    else
        % ===== Volumetric mesh mode =====
        if isempty(hVol) || ~any(isgraphics(hVol)) || trigVolRebuild
            buildVolumetricMesh();        % returns [] or an array of patches
        end
    
        % show volume + base; hide surface overlay; 
        setVisible(hProj, 'off');
        setVisible(hBase, 'on');                 % change to 'off' for volume-only
        setVisible(hVol,  'on');
    end

   % 3) First-time framing / camera (install safe rotate3d once)
    if ~isappdata(parent,'didFrame3D')
        daspect(h3DAx,[1 1 1]);
        axis(h3DAx,'vis3d');
        axis(h3DAx,'off');
        if exist('hAzimSlider','var') && isgraphics(hAzimSlider)
            view(h3DAx, hAzimSlider.Value, hElevSlider.Value);
        else
            view(h3DAx, 45, 20);
        end
    
        % Install safe rotate3d on the FIGURE, not the axes
        hFig = ancestor(h3DAx,'figure');
        hRotate = rotate3d(hFig);
        hRotate.Enable = 'on';
        hRotate.ActionPreCallback  = @(obj,evd) onRotatePreSafe(obj, evd);
        hRotate.ActionPostCallback = @(obj,evd) onRotatePostSafe(obj, evd);
    
        % Stash handles in guidata (keyed on h3DAx)
        S = guidata(h3DAx);
        if isempty(S), S = struct; end
        S.hFig    = hFig;
        S.h3DAx   = h3DAx;
        S.hRotate = hRotate;
        guidata(h3DAx, S);
    
        setappdata(parent,'didFrame3D',true);
    end

    % 4) Update colors
    update3DColors();

    % 5) Dock light controls
    position3DControls(); 
    set([hLightAzLbl, hLightAz, hLightElLbl, hLightEl, ...
         h3DAlphaLbl,h3DAlpha, hBtnRecord, hOverlayMode, ...
         hZoomIn, hZoomOut, hSave3D, hLoad3D, hHome3D], 'Visible', 'on');
    
end

function onRotatePreSafe(~, evd)
    ax = getValidAxes(evd);
    if isempty(ax), return; end
    setappdata(ax, 'isRotating', true);
end

function onRotatePostSafe(~, evd)
    ax = getValidAxes(evd);
    if isempty(ax), return; end

    % Clear rotation flag immediately so subsequent calls aren't trapped
    if isappdata(ax,'isRotating'), setappdata(ax,'isRotating',false); end

    persistent inPost;
    if ~isempty(inPost) && inPost, return; end
    inPost = true;

    try
        S = guidata(ax);
        if isempty(S) || ~isfield(S,'h3DAx') || ~ishandle(S.h3DAx) || ~isequal(ax,S.h3DAx)
            inPost = false; 
            return;
        end

        % Run only if something asked for a refresh during rotation
        if isappdata(ax,'pendingUpdate') && getappdata(ax,'pendingUpdate')
            rmappdata(ax,'pendingUpdate');
            % Do your deferred/lightweight redraw (don’t block UI)
            requestDeferredRedraw(S);
            % If you prefer to force only the overlay update, call that here instead.
            % refreshStatsOverlay(S);
        end

    catch ME
        warning('overlay_nifti_gui:RotatePostError', ...
            'Rotate post-callback failed: %s', getReport(ME,'basic','hyperlinks','off'));
    end

    inPost = false;
end

function ax = getValidAxes(evd)
    ax = [];
    if nargin<1 || isempty(evd) || ~isfield(evd,'Axes'), return; end
    a = evd.Axes;
    if ~isempty(a) && ishghandle(a) && isgraphics(a,'axes'), ax = a; end
end

function requestDeferredRedraw(S)
    % Coalesce multiple requests
    if isfield(S,'pendingRedraw') && S.pendingRedraw, return; end
    S.pendingRedraw = true; guidata(S.h3DAx, S);

    % Let rotate3d finish teardown first
    drawnow limitrate
    t = timer('StartDelay', 0.015, 'TimerFcn', @(~,~) doRedrawSafely(S.h3DAx));
    % Ensure timer dies on figure close
    t.ExecutionMode = 'singleShot';
    if isfield(S,'hFig') && ishghandle(S.hFig)
        t.TimerFcn = @(~,~) doRedrawSafely(S.h3DAx);
        t.StopFcn  = @(~,~) delete(t);
    end
    start(t);
end

function doRedrawSafely(hAx)
    if ~ishandle(hAx) || ~isvalid(hAx), return; end
    S = guidata(hAx);
    if isempty(S), return; end
    S.pendingRedraw = false; guidata(hAx, S);

    % IMPORTANT: call a lightweight update that does NOT delete axes/patches
    % If your current path is ensure3DScene(), call it — now that rotation ended.
    try
        ensure3DScene(); % safe now; early-out if rotating
    catch ME
        warning('overlay_nifti_gui:DeferredRedrawError', ...
            'Deferred redraw failed: %s', getReport(ME,'basic','hyperlinks','off'));
    end
end

function setVisible(h, vis)
    if isempty(h), return; end
    h = h(isgraphics(h));           % keep only live handles (works for arrays)
    if isempty(h), return; end
    set(h, 'Visible', vis);
end

function hide3DScene()

    if ~isgraphics(h3DAx,'axes'), return; end
    % Hide patches/surfaces/images etc., but keep lights ON
    ch = get(h3DAx,'Children');
    isLight = arrayfun(@(h) strcmp(get(h,'Type'),'light'), ch);
    set(ch(~isLight), 'Visible','off');
    set([hLightAzLbl, hLightAz, hLightElLbl, hLightEl, ...
        h3DAlphaLbl, h3DAlpha, hBtnRecord, hOverlayMode, ...
        hZoomIn, hZoomOut, hSave3D, hLoad3D, hHome3D], 'Visible', 'off')
    set(h3DAx,'Visible','off');   % hides axes box, not lights

end

function onSliceChange(src, ~)
    sliceIdx = round(get(src,'Value'));
    set(hSliceLabel,'String',sprintf('Slice: %d / %d', sliceIdx, maxSlices.(viewmode)));
    requestRedraw();
end

function onBrightChange(src, ~)
    brightnessVal = get(src,'Value');
    set(hBrightLabel,'String',sprintf('%.2f', brightnessVal));
    requestRedraw();
end

function onAlphaChange(src, ~)
    alphaVal = get(src,'Value');
    set(hAlphaLabel,'String',sprintf('%.2f', alphaVal));
    requestRedraw();
end

function onNegChange(src, ~)
    thrNeg = get(src,'Value');
    set(hNegEdit,'String',sprintf('%.2f', thrNeg));
    trigVolRebuild = true;
    requestRedraw();
end

function onNegEdit(src, ~)
    v = str2double(get(src,'String'));
    if isnan(v) || v < Tmin || v > 0
        warndlg(sprintf('Enter value in [%.2f, 0]', Tmin));
        v = prctile(T(T<0), 10);
    end
    thrNeg = min(max(v, Tmin), 0);
    set(hNegSlider,'Value', thrNeg);
    requestRedraw();
end

function onPosChange(src, ~)
    thrPos = get(src,'Value');
    set(hPosEdit,'String',sprintf('%.2f', thrPos));
    trigVolRebuild = true;
    requestRedraw();
end

function onPosEdit(src, ~)
    v = str2double(get(src,'String'));
    if isnan(v) || v < 0 || v > Tmax
        warndlg(sprintf('Enter value in [0, %.2f]', Tmax));
        v = prctile(T(T>0), 90);
    end
    thrPos = min(max(v, 0), Tmax);
    set(hPosSlider,'Value', thrPos);
    requestRedraw();
end

function onThrChange(src, ~)
    thr = get(src,'Value');
    set(hThrEdit,'String',sprintf('%.2f', thr));
    trigVolRebuild = true;
    requestRedraw();
end

function onThrEdit(src, ~)
    v = str2double(get(src,'String'));
    mn = hasPos * 0 + hasNeg * Tmin;
    mx = hasPos * Tmax + hasNeg * 0;
    if isnan(v) || v < mn || v > mx
        warndlg(sprintf('Enter value in [%.2f, %.2f]', mn, mx));
        v = hasPos * prctile(T(:), 90) + hasNeg * prctile(T(:), 10);
    end
    thr = min(max(v, mn), mx);
    set(hThrSlider,'Value', thr);
    requestRedraw();
end

function onNegColor(~,~)
    c = uisetcolor(negColor,'Select negative colormap end');
    if numel(c)==3
      negColor = c;
      set(hNegBtn,'BackgroundColor',c);
      requestRedraw();
      drawnow;
    end
end

function onMidColor(~,~)
    c = uisetcolor(midColor,'Select zero colormap midpoint');
    if numel(c)==3
      midColor = c;
      set(hMidBtn,'BackgroundColor',c);
      requestRedraw();
      drawnow;
    end
end

function onPosColor(~,~)
    c = uisetcolor(posColor,'Select positive colormap end');
    if numel(c)==3
      posColor = c;
      set(hPosBtn,'BackgroundColor',c);
      requestRedraw();
      drawnow;
    end
end

function onMultiToggle(src,~)
    % called when the user toggles Multi‐slice on/off
    isMulti = get(src,'Value')==1;

    % Enable/disable the grid‐size controls
    if isMulti
        set(hRowLabel,  'Enable','on');
        set(hRowPop,    'Enable','on');
        set(hColLabel,  'Enable','on');
        set(hColPop,    'Enable','on');
        set(hStartLabel,'Enable','on');
        set(hStartEdit, 'Enable','on');
        set(hEndLabel,  'Enable','on');
        set(hEndEdit,   'Enable','on');
    else
        set(hRowLabel,  'Enable','off');
        set(hRowPop,    'Enable','off');
        set(hColLabel,  'Enable','off');
        set(hColPop,    'Enable','off');
        set(hStartLabel,'Enable','off');
        set(hStartEdit, 'Enable','off');
        set(hEndLabel,  'Enable','off');
        set(hEndEdit,   'Enable','off');
    end

    % Enable/disable the single‐slice slider and its label
    if isMulti
        set(hSlice,      'Enable','off');
        set(hSliceLabel, 'Enable','off');
    else
        set(hSlice,      'Enable','on');
        set(hSliceLabel, 'Enable','on');
    end

    requestRedraw();
end

function onSliceParamChange(~,~)
    % clamp start/end to valid range
    s = clamp(str2double(hStartEdit.String), 1, maxSlices.(viewmode));
    e = clamp(str2double(hEndEdit.String),   1, maxSlices.(viewmode));
    if s>e, s=e; end
    hStartEdit.String = num2str(s);
    hEndEdit.String   = num2str(e);
    requestRedraw();
end

function y = clamp(x, lo, hi)
    if isnan(x), x = lo; end
    y = min(max(x, lo), hi);
end

function onPickROI3D(h,evt,parent)
    ax = ancestor(h,'axes');
    [i,j,k,space_used] = get_ijk4click3D(evt, ax, parent);
    if isempty(i), return; end

    % Reuse your existing atlas mapping + LUT (same as 2D)
    Vs        = getappdata(parent,'Vs_hdr');
    VatOrig   = getappdata(parent,'VatOrig');
    AtlasOrig = getappdata(parent,'AtlasOrig');
    lut       = getappdata(parent,'roiLUT');
    if isempty(Vs) || isempty(VatOrig) || isempty(AtlasOrig) || isempty(lut), return; end

    code = struct2atlas([i;j;k], Vs, VatOrig, AtlasOrig);

    if isKey(lut, code), name = lut(code); else, name = sprintf('Code %d', code); end

    % Place a small popup at the click location
    % (use IntersectionPoint if available; else CurrentPoint)
    if isstruct(evt) && isfield(evt,'IntersectionPoint') && ~isempty(evt.IntersectionPoint)
        ip = evt.IntersectionPoint(:);
    else
        cp = get(ax,'CurrentPoint'); ip = cp(1,:).';
    end
    delete(findobj(ax,'Tag','roiPopup3D'));
    text(ax, ip(1), ip(2), ip(3), sprintf('ROI: %s (code=%d)', name, code), ...
        'Color',[1 1 1], 'BackgroundColor',[0 0 0 0.45], 'Margin',4, ...
        'FontSize',10, 'Tag','roiPopup3D');

    if exist('hRegLabel','var') && isgraphics(hRegLabel)
        hRegLabel.String = sprintf('%s (code=%d) at voxel [%d %d %d] (%s)', ...
                                   name, code, i, j, k, space_used);
    end
end

function onRecordRotationLive(parent)
%ONRECORDROTATIONLIVE Create stage window, record brain rotation to video
% with custom settings dialog, dropdowns, file chooser, and degrees/frame.

    % --- Settings dialog (modal so it stays on top) ---
    dlg = uifigure('Name','Rotation Video Settings', ...
                   'Position',[100 100 580 440], ...
                   'Resize','off', ...
                   'WindowStyle','modal');

    % Defaults
    params.filename     = '';
    params.fps          = 30;
    params.rotRange     = 360;
    params.rotDir       = 'cw';
    params.elevChange   = 0;
    params.loopMode     = 'forward';
    params.bgColor      = [0 0 0];
    params.degPerFrame  = 1;     % keep numeric; 1°/frame default
    params.resLabel     = '1080p (1920×1080)';
    params.width        = 1920;  % pixels
    params.height       = 1080;  % pixels
    params.okPressed    = false;

    % ---- File chooser ----
    uilabel(dlg,'Position',[20 388 110 22],'Text','Save video as:');
    lblFile = uilabel(dlg,'Position',[280 388 260 22], ...
        'Text','(none selected)','FontSize',9,'Tooltip','Selected file path');
    uibutton(dlg,'push','Text','Choose file...','Position',[180 388 90 22], ...
        'ButtonPushedFcn',@(~,~) chooseFile());

    % ---- FPS ----
    uilabel(dlg,'Position',[20 350 150 22],'Text','Frames per second:');
    fpsField = uieditfield(dlg,'numeric','Limits',[1 Inf], ...
        'Value',params.fps,'Position',[180 350 80 22]);

    % ---- Rotation range ----
    uilabel(dlg,'Position',[20 320 150 22],'Text','Rotation range (°):');
    rangeField = uieditfield(dlg,'numeric','Limits',[0 Inf], ...
        'Value',params.rotRange,'Position',[180 320 80 22]);

    % ---- Degrees per frame ----
    uilabel(dlg,'Position',[20 290 150 22],'Text','Degrees per frame:');
    degFrameField = uieditfield(dlg,'numeric','Value', params.degPerFrame, ...
        'Position',[180 290 80 22], ...
        'Tooltip','Leave as a small positive number (e.g., 1).');

    % ---- Rotation direction ----
    uilabel(dlg,'Position',[20 260 150 22],'Text','Rotation direction:');
    dirDrop = uidropdown(dlg,'Items',{'cw','ccw'},'Value',params.rotDir, ...
        'Position',[180 260 80 22]);

    % ---- Elevation change ----
    uilabel(dlg,'Position',[20 230 180 22],'Text','Elevation change (°):');
    elevField = uieditfield(dlg,'numeric','Value',params.elevChange, ...
        'Position',[180 230 80 22]);

    % ---- Loop mode ----
    uilabel(dlg,'Position',[20 200 150 22],'Text','Loop mode:');
    loopDrop = uidropdown(dlg,'Items',{'forward','reverse','yo-yo'}, ...
        'Value',params.loopMode,'Position',[180 200 100 22]);

    % ---- Background color + swatch ----
    uilabel(dlg,'Position',[20 170 150 22],'Text','Background color:');
    uibutton(dlg,'push','Text','Pick color...','Position',[180 170 100 22], ...
        'ButtonPushedFcn',@(~,~) chooseColor());
    colorSwatch = uipanel(dlg,'Position',[290 170 40 22], ...
        'BackgroundColor',params.bgColor,'BorderType','line');

    % ---- Video resolution ----
    uilabel(dlg,'Position',[20 135 150 22],'Text','Video resolution:');
    resDrop = uidropdown(dlg, ...
        'Items',{'720p (1280×720)','1080p (1920×1080)', ...
                 '1440p (2560×1440)','4K UHD (3840×2160)','Custom...'}, ...
        'Value',params.resLabel, ...
        'Position',[180 135 160 22], ...
        'ValueChangedFcn',@onResChanged);

    % Custom width/height (enabled only if Custom selected)
    uilabel(dlg,'Position',[350 135 40 22],'Text','W:');
    wField = uieditfield(dlg,'numeric','Limits',[2 Inf], ...
        'Value',params.width,'Position',[375 135 60 22],'Enable','off');
    uilabel(dlg,'Position',[440 135 40 22],'Text','H:');
    hField = uieditfield(dlg,'numeric','Limits',[2 Inf], ...
        'Value',params.height,'Position',[465 135 60 22],'Enable','off');

    % ---- OK / Cancel ----
    uibutton(dlg,'push','Text','OK','Position',[200 30 80 32], ...
        'ButtonPushedFcn',@(~,~) onOK());
    uibutton(dlg,'push','Text','Cancel','Position',[300 30 80 32], ...
        'ButtonPushedFcn',@(~,~) delete(dlg));

    % Wait for dialog to close
    uiwait(dlg);

    % If cancelled
    if ~params.okPressed
        disp('User cancelled video creation.');
        return;
    end

    % --- Get monitor info ---
    monitors = get(0, 'MonitorPositions');  % N×4 array
    targetMon = monitors(1,:);  % choose monitor index here (1 = primary)
    monLeft   = targetMon(1);
    monBottom = targetMon(2);
    monWidth  = targetMon(3);
    monHeight = targetMon(4);

    % --- Clamp to fit monitor ---
    params.width  = min(params.width,  monWidth);
    params.height = min(params.height, monHeight);

    % Ensure even numbers for codecs
    params.width  = params.width  - mod(params.width, 2);
    params.height = params.height - mod(params.height, 2);

    % === PATCH: create a larger figure with an inset axes so rect is always inside ===
    FRAME_MARGIN = 3;  % small inset prevents future getframe rect warnings
    figW = params.width  + 2*FRAME_MARGIN;
    figH = params.height + 2*FRAME_MARGIN;

    % Center on target monitor
    posX = monLeft + floor((monWidth  - figW) / 2);
    posY = monBottom + floor((monHeight - figH) / 2);

    % === Stage figure & axes ===
    stageFig = figure('Name','Rotation Stage', ...
                  'Color', params.bgColor, ...
                  'Units','pixels', ...
                  'Position',[posX posY figW figH], ...
                  'Resize','off', 'MenuBar','none','ToolBar','none','DockControls','off');      % help avoid 1px jitter

    stageAx = axes('Parent', stageFig, ...
               'Units','pixels', ...
               'Position',[FRAME_MARGIN+1, FRAME_MARGIN+1, params.width, params.height], ...
               'Visible','off', 'ActivePositionProperty','position');

    axis(stageAx,'off'); axis(stageAx,'vis3d');

    % Copy from main GUI
    mainAx = findobj(parent, 'Type', 'axes');
    if isempty(mainAx)
        error('No main 3D axes found.');
    end
    copyobj(allchild(mainAx(1)), stageAx);

    % Start view (right side)
    view(stageAx, 90, 0);
    axis(stageAx,'manual');
    set(stageAx,'XLimMode','manual','YLimMode','manual','ZLimMode','manual', ...
                'CameraPositionMode','manual','CameraTargetMode','manual', ...
                'CameraUpVectorMode','manual','CameraViewAngleMode','manual');
    camproj(stageAx,'perspective');

    % One-time color update
    update3DColors(stageAx);

    % Rotation params
    dAz = params.degPerFrame;
    if isempty(dAz) || ~isfinite(dAz) || dAz == 0
        dAz = 1;  % sensible fallback
    end
    if isempty(dAz) || ~isfinite(dAz) || dAz == 0
        dAz = 1;
    end
    nFrames = max(1, round(params.rotRange / max(eps, abs(dAz))));
    if strcmp(params.rotDir, 'cw')
        dAz = -dAz;
    end
    dEl = params.elevChange / nFrames;

    % Remove any extra axes that might have been created accidentally
    axAll = findobj(stageFig,'Type','axes');
    axAll(axAll==stageAx) = [];
    delete(axAll);

    drawnow;  % ensure layout settled

    % === PATCH: fixed, safe capture rect strictly inside the figure ===
    axRect = [FRAME_MARGIN+1, FRAME_MARGIN+1, params.width, params.height];

    % --- Prime frame and set up VideoWriter AFTER knowing true size ---
    firstFrame = getframe(stageFig, axRect);      % no warnings now or later
    [h0, w0, ~] = size(firstFrame.cdata);
    % Enforce even dimensions (should already be even, keep guard)
    w0 = w0 - mod(w0,2);
    h0 = h0 - mod(h0,2);
    if w0 < 2 || h0 < 2
        error('Frame size too small: %dx%d', h0, w0);
    end
    firstFrame.cdata = firstFrame.cdata(1:h0, 1:w0, :);

    [~,~,ext] = fileparts(params.filename);
    switch lower(ext)
        case '.mp4'
            vw = VideoWriter(params.filename, 'MPEG-4');
            vw.FrameRate = max(1, min(60, round(params.fps)));
        case '.avi'
            vw = VideoWriter(params.filename, 'Motion JPEG AVI');
            vw.FrameRate = max(1, round(params.fps));
        otherwise
            error('Unsupported extension: %s', ext);
    end
    open(vw);
    writeVideo(vw, firstFrame);   % prime

    % --- Rotation helper using the SAME rect every time ---
    function recordSweep(azStep, elStep, numFrames)
        for k = 1:numFrames
            camorbit(stageAx, azStep, elStep, 'camera');
            drawnow limitrate nocallbacks
            f = getframe(stageFig, axRect);       % fixed-size, safe rect
            % Guard (should be redundant now, but harmless):
            f.cdata = f.cdata(1:h0, 1:w0, :);
            writeVideo(vw, f);
        end
    end

    % Loop mode handling
    switch params.loopMode
        case 'forward'
            recordSweep(dAz, dEl, nFrames);
        case 'reverse'
            recordSweep(-dAz, -dEl, nFrames);
        case 'yo-yo'
            recordSweep(dAz, dEl, nFrames);
            recordSweep(-dAz, -dEl, nFrames);
        otherwise
            recordSweep(dAz, dEl, nFrames);
    end

    close(vw);
    delete(stageFig);

    % Clean up ghost zero-byte AVI (MATLAB quirk)
    if strcmpi(ext,'.mp4')
        [folder, base] = fileparts(params.filename);
        ghostAvi = fullfile(folder, [base '.avi']);
        if exist(ghostAvi,'file')
            d = dir(ghostAvi);
            if d.bytes == 0
                try, delete(ghostAvi); end
            end
        end
    end

    fprintf('Rotation video saved to: %s\n', params.filename);

    % --- Nested functions for dialog actions ---
    function chooseFile()
        % Let user pick MP4 or AVI
        [f, p, idx] = uiputfile( ...
            {'*.mp4','MPEG-4 Video (*.mp4)'; '*.avi','AVI Video (*.avi)'}, ...
            'Save Video As', 'rotation_stage.mp4');

        if isequal(f,0), return; end

        [~,name,ext0] = fileparts(f);
        if isempty(ext0)
            ext0 = ternary(idx==1, '.mp4', '.avi');
        elseif ~any(strcmpi(ext0,{'.mp4','.avi'}))
            ext0 = ternary(idx==1, '.mp4', '.avi');
        end
        params.filename = fullfile(p, [name ext0]);

        % Update label
        show = [name ext0];
        if numel(show) > 30, show = ['…' show(end-28:end)]; end
        lblFile.Text = show;
        lblFile.Tooltip = params.filename;
    end

    function chooseColor()
        c = uisetcolor(params.bgColor, 'Pick Background Color');
        if length(c) == 3
            params.bgColor = c;
            colorSwatch.BackgroundColor = c;  % live update swatch
        end
    end

    function onResChanged(~,~)
        params.resLabel = resDrop.Value;
        switch params.resLabel
            case '720p (1280×720)'
                params.width = 1280; params.height = 720;
                wField.Value = params.width; hField.Value = params.height;
                wField.Enable = 'off'; hField.Enable = 'off';
            case '1080p (1920×1080)'
                params.width = 1920; params.height = 1080;
                wField.Value = params.width; hField.Value = params.height;
                wField.Enable = 'off'; hField.Enable = 'off';
            case '1440p (2560×1440)'
                params.width = 2560; params.height = 1440;
                wField.Value = params.width; hField.Value = params.height;
                wField.Enable = 'off'; hField.Enable = 'off';
            case '4K UHD (3840×2160)'
                params.width = 3840; params.height = 2160;
                wField.Value = params.width; hField.Value = params.height;
                wField.Enable = 'off'; hField.Enable = 'off';
            case 'Custom...'
                wField.Enable = 'on'; hField.Enable = 'on';
            otherwise
                params.width = 1920; params.height = 1080;
                wField.Value = params.width; hField.Value = params.height;
                wField.Enable = 'off'; hField.Enable = 'off';
        end
    end

    function onOK()
        if isempty(params.filename)
            uialert(dlg, 'Please choose a file to save the video.', 'Missing file');
            return;
        end
        params.fps          = fpsField.Value;
        params.rotRange     = rangeField.Value;
        params.degPerFrame  = degFrameField.Value;
        params.rotDir       = dirDrop.Value;
        params.elevChange   = elevField.Value;
        params.loopMode     = loopDrop.Value;
        params.okPressed    = true;
        delete(dlg);
    end

    % small utility
    function y = ternary(cond, a, b)
        if cond, y = a; else, y = b; end
    end
end


% Main redraw routine
function redraw()

    try

        %% ─── Recompute global colormaps up front ───────────────
        N = 256; cmJet = []; cmDiv = [];
        if hasNeg && hasPos
            % bipolar ramp: negColor → midColor → posColor
            nNeg = round(abs(Tmin)/(Tmax - Tmin)*N);
            nPos = N - nNeg;
            cmNeg = [ ...
              linspace(negColor(1), midColor(1), nNeg)' , ...
              linspace(negColor(2), midColor(2), nNeg)' , ...
              linspace(negColor(3), midColor(3), nNeg)' ];
            cmPos = [ ...
              linspace(midColor(1), posColor(1), nPos)' , ...
              linspace(midColor(2), posColor(2), nPos)' , ...
              linspace(midColor(3), posColor(3), nPos)' ];
            cmDiv = [cmNeg; cmPos];        % 256×3 diverging map
        else
            cmJet = jet(N);               % 256×3 jet map
        end

        % Single vs. multi-slice choice
        if isMulti
        
            % get grid params
            rows   = str2double(hRowPop.String{hRowPop.Value});
            cols   = str2double(hColPop.String{hColPop.Value});
            s0     = str2double(hStartEdit.String);
            e0     = str2double(hEndEdit.String);
            slices = round(linspace(s0, e0, rows*cols));
        
            % precompute one slice size
            % renderSingleSlice now returns an RGB image instead of drawing to axes
            % e.g. [rgbSlice] = renderSingleSliceImage(si, cmDiv, cmJet, N);
            tmpRGB = renderSingleSliceImage(slices(1), cmDiv, cmJet, N);
            [sliceH, sliceW, ~] = size(tmpRGB);
        
            % build the big mosaic
            mosaic = zeros(sliceH*rows, sliceW*cols, 3, 'like', tmpRGB);
            for k = 1:rows*cols
                r = floor((k-1)/cols);
                c = mod(k-1, cols);
                rgbSlice = renderSingleSliceImage(slices(k), cmDiv, cmJet, N);
                rr = (r*sliceH + 1) : (r+1)*sliceH;
                cc = (c*sliceW + 1) : (c+1)*sliceW;
                mosaic(rr,cc,:) = rgbSlice;
            end
        
            % draw it into the single axes
            cla(hAx);
            hImg = image(mosaic, 'Parent', hAx);
            set(hImg,'HitTest','off','PickableParts', 'none'); % let clicks pass through
            axis(hAx,'image');
            set(hAx,'XTick',[],'YTick',[]);
        else
            % ── Single‐slice: just redraw your main axes ─────
            % Single-slice mode: remove tiles & show main axes
            % going back to single
            switch viewmode
                case '3d-view'
                    % NEW: build-once & recolor; no draw3D anymore
                    ensure3DScene();              % creates light/mesh once, frames first time
                case {'axial','sagittal','coronal'}
                    renderSingleSlice(hAx, sliceIdx, cmDiv, cmJet, N);
                    set(hSliceLabel,'String',sprintf('Slice: %d / %d',sliceIdx,maxSlices.(viewmode)));
                    set(hAx,'XTick',[],'YTick',[]);
                    if silOn && strcmp(hSilToggle.Enable,'on')
                        % compute boundary mask B for this slice
                        B = computeROIBoundaryOnTheFly(AtlasOrig, Vs, VatOrig, viewmode, sliceIdx);
                        % overlay contour in shade silB
                        hold(hAx,'on');
                        hSilC = contour(hAx, B, [0.5 0.5], 'k','LineWidth', 0.4, 'EdgeColor', [silB silB silB]);
                    end
                    hold(hAx,'off');
            end
        end
        
        % Enforce axis orientation (stops surprise flips)
        if isappdata(parent,'axisLock')
            lock = getappdata(parent,'axisLock');
            if isgraphics(hAx)
                set(hAx, 'XDir', lock.XDir, 'YDir', lock.YDir);
            end
        end

        % ── 5) In either case, redraw the colorbar ─────────
        drawColorbar(cmDiv, cmJet);
        hAx.ButtonDownFcn =  @onSliceClick;
        drawnow()
        
    catch ME
        warning(['Redraw error: ' ME.message]);
    end
       
end

function update3DColors(ax)

    % Default to main 3D axes if none provided
    if nargin < 1 || isempty(ax)
        ax = h3DAx;
    end
    if ~ishghandle(ax,'axes'); return; end

    % --- handles & cached geometry ---
    fv           = getappdata(parent,'fv3D');
    vnorm_vox    = getappdata(parent,'vnorm_struct');
    hPatch3D     = getappdata(parent,'hPatch3D');
    hPatchBase3D = getappdata(parent,'hPatchBase3D');
    hVol3D       = getappdata(parent,'hVol3D');
    overlayMode  = hOverlayMode.Value;
    
    % Rebuild if missing or triggered
    if isempty(fv) || isempty(vnorm_vox) || trigBrainRebuild
        buildBrainMesh()
    end
    if overlayMode == 0 && (isempty(hPatch3D) || ~isgraphics(hPatch3D,'patch') || trigSurfRebuild )
        buildSurfaceMesh()
    elseif overlayMode == 1 && (isempty(hVol3D) || ~any(isgraphics(hVol3D,'patch')) || trigVolRebuild)
        buildVolumetricMesh()
    end

    % --- capture camera (harmless) ---
    cp = ax.CameraPosition; ct = ax.CameraTarget;
    cu = ax.CameraUpVector; cva = ax.CameraViewAngle;

    % --- choose vertices/faces based on mode ---
    if overlayMode == 0
        % SURFACE MODE
        nV = size(fv.vertices,1);
        if size(vnorm_vox,1) ~= nV
            vnorm_vox = zeros(nV,3); vnorm_vox(:,3) = 1;
        end
        eps_vox = 0.25; % outward offset
        verts_draw = fv.vertices + eps_vox * vnorm_vox;
        verts = fv.vertices;
        faces = fv.faces;
        targetPatches = hPatch3D;
        NormVals = vnorm_vox;
    else
        % VOLUME MODE
        targetPatches = hVol3D(isgraphics(hVol3D,'patch'));
        if isempty(targetPatches), return; end
        verts = targetPatches.Vertices;
        faces = targetPatches.Faces;
        nV    = size(verts,1);
        % --- sample stat values ---
        NormVals = zeros(nV,3); 
    end

    statV = sampleStatOnVertices_vox(verts, NormVals, Vs, Vt, T, ax, depthMM);

    % --- determine positive/negative presence ---
    hasPos = any(statV > 0);
    hasNeg = any(statV < 0);

    % --- Colormap setup ---
    N = 256;
    cmJet = jet(N);
    if hasPos && hasNeg
        nNeg = round(abs(thrNeg)/(thrPos - thrNeg) * N);
        nNeg = max(1, min(N-1, nNeg));
        nPos = N - nNeg;
        cmNeg = [linspace(negColor(1), midColor(1), nNeg)' , ...
                 linspace(negColor(2), midColor(2), nNeg)' , ...
                 linspace(negColor(3), midColor(3), nNeg)'];
        cmPos = [linspace(midColor(1), posColor(1), nPos)' , ...
                 linspace(midColor(2), posColor(2), nPos)' , ...
                 linspace(midColor(3), posColor(3), nPos)'];
        cmDiv = [cmNeg; cmPos];
    end

    % --- Clamp scalar values for mapping ---
    if hasPos && hasNeg
        Cvals = min(max(statV, thrNeg), thrPos);
    elseif hasPos
        Cvals = min(max(statV, thrPos), Tmax);
    elseif hasNeg
        Cvals = min(max(statV, Tmin),  thrNeg);
    else
        Cvals = zeros(size(statV));
    end

    % --- Alpha weights ---
    softK   = 0.15;
    bandPos = softK * max(Tmax - thrPos, eps);
    bandNeg = softK * max(thrNeg - Tmin, eps);
    wPos = zeros(size(statV));
    wNeg = zeros(size(statV));
    if hasPos, wPos = max(0, (statV - thrPos) / bandPos); end
    if hasNeg, wNeg = max(0, (thrNeg - statV) / bandNeg); end
    w = min(1, max(wPos, wNeg));

    % --- Color mapping ---
    if hasPos && hasNeg
        bnorm  = (Cvals - thrNeg) / max(thrPos - thrNeg, eps);
        bnorm  = min(max(bnorm,0),1);
        colors = cmDiv(round(bnorm*(N-1))+1,:);
    elseif hasPos
        denom  = max(Tmax - thrPos, eps);
        bnorm  = (Cvals - thrPos) / denom;
        bnorm  = min(max(bnorm,0),1);
        colors = cmJet(round(bnorm*(N-1))+1,:);
    elseif hasNeg
        denom  = max(thrNeg - Tmin, eps);
        bnorm  = (thrNeg - Cvals) / denom;
        bnorm  = min(max(bnorm,0),1);
        colors = cmJet(round(bnorm*(N-1))+1,:);
    else
        colors = repmat(0.8, [nV,3]);
    end

    % === Apply per mode ===
    if overlayMode == 0
        
        % --- SURFACE MODE: keep z-conflict avoidance ---
        facesKeep = max(w(fv.faces), [], 2) > 0.05;
        if ~any(facesKeep)
            set(targetPatches,'Visible','off');
            if isgraphics(hPatchBase3D,'patch'), set(hPatchBase3D,'FaceAlpha',alpha3D); end
            return;
        end

        fvSig      = compactFV(fv, verts_draw, facesKeep);
        w_sig      = w(fvSig.new2old);
        colors_sig = colors(fvSig.new2old, :);
        gamma      = 0.9;
        alpha_sig  = max((w_sig.^gamma) * alphaVal, 0.01);

        set(targetPatches, ...
            'Faces',fvSig.faces, 'Vertices',fvSig.vertices, ...
            'FaceVertexCData',colors_sig, ...
            'FaceVertexAlphaData',alpha_sig, ...
            'FaceColor','interp','EdgeColor','none', ...
            'Visible', 'on', ...
            'FaceAlpha','interp','AlphaDataMapping','none', ...
            'FaceLighting','none');

    else
        % --- VOLUME MODE: apply directly per patch ---
        alpha_sig = max((w.^0.9) * alphaVal, 0.01);
        set(targetPatches, ...
            'Faces',faces,'Vertices',verts, ...
            'FaceVertexCData',colors, ...
            'FaceVertexAlphaData',alpha_sig, ...
            'FaceColor','interp','EdgeColor','none', ...
            'Visible', 'on', ...
            'FaceAlpha','interp','AlphaDataMapping','none', ...
            'FaceLighting','none');
    end

    % --- Lighting & camera restore ---
    set(ax,'SortMethod','depth');
    try
        hTmp = patch('Faces',get(targetPatches,'Faces'),'Vertices',get(targetPatches,'Vertices'), ...
                     'Visible','off','Parent',ax);
        isonormals(double(ST), hTmp);
        vN = get(hTmp,'VertexNormals'); delete(hTmp);
        nv = sqrt(sum(vN.^2,2)); nv(nv==0)=1; vN = vN./nv;
        set(targetPatches, ...
            'VertexNormals',vN, ...
            'FaceLighting','gouraud', ...
            'BackFaceLighting','reverselit', ...
            'AmbientStrength', hAmbientSlider.Value, ...
            'DiffuseStrength', hDiffuseSlider.Value, ...
            'SpecularStrength', hSpecularSlider.Value);
    catch
        set(targetPatches,'FaceLighting','none');
    end

    if isgraphics(hPatchBase3D,'patch')
        set(hPatchBase3D,'FaceAlpha',alpha3D);
    end
    if ishold(ax)
        ax.CameraPosition   = cp;
        ax.CameraTarget     = ct;
        ax.CameraUpVector   = cu;
        ax.CameraViewAngle  = cva;
    end
    axis(ax,'off');
    drawnow;
end

% Plot multi-slice view in given axis orientation
function rgb = renderSingleSliceImage(si, cmDiv, cmJet, N)
    
    % Extract & orient A,B
    [A, B] = extract_reorient_vols(si);

    % normalize & apply brightness
    A = (A - min(A(:))) / (max(A(:)) - min(A(:)));
    A = max(min(A * brightnessVal,1),0);

    % build mask
    if hasNeg && hasPos
        mask = (B <= thrNeg) | (B >= thrPos);
    elseif hasPos
        mask = (B >= thr);
    else
        mask = (B <= thr);
    end

    % global color lookup
    bnorm = (B - Tmin) / (Tmax - Tmin);
    bnorm = min(max(bnorm,0),1);
    idx   = round(bnorm*(N-1)) + 1;

    if hasNeg && hasPos
        C = reshape(cmDiv(idx,:), [size(B),3]);
    else
        C = reshape(cmJet(idx,:), [size(B),3]);
    end

    % composite: only where mask==1 do we blend in C
    rgb = repmat(A,1,1,3);        % start with grayscale background
    alphaMat = mask * alphaVal;   % 1×1→0 or αVal
    for ch=1:3
        bg = rgb(:,:,ch);
        fg = C(:,:,ch);
        % new = bg*(1 - α*mask) + fg*(α*mask)
        rgb(:,:,ch) = bg .* (1 - alphaMat) + fg .* alphaMat;
    end
end

% ─── helper to draw one slice into given axes ─────────────────
function renderSingleSlice(ax, si, cmDiv, cmJet, N)
% RENDERSINGLESLICE  Draws one slice with brightness and overlay in axes 'ax'
%   si        = slice index
%   cmDiv     = 256×3 diverging colormap (or [])
%   cmJet     = 256×3 jet colormap (or [])
%   N         = number of colors (256)

    % 1) Extract & orient
    [A, B] = extract_reorient_vols(si);
    
    % 2) Normalize & apply brightness
    A = (A - min(A(:))) / (max(A(:)) - min(A(:)));
    A = max(min(A * brightnessVal,1),0);

    % 3) Build alpha mask from thresholds
    if hasNeg && hasPos
        mask = (B <= thrNeg) | (B >= thrPos);
    elseif hasPos
        mask = (B >= thr);
    else
        mask = (B <= thr);
    end

    % 4) Map entire B into fixed colormap
    bnorm = (B - Tmin) / (Tmax - Tmin);
    bnorm = min(max(bnorm,0),1);
    idx   = round(bnorm * (N-1)) + 1;  % indices in 1…N

    if hasNeg && hasPos
        C = reshape(cmDiv(idx,:), [size(B), 3]);
    else
        C = reshape(cmJet(idx,:), [size(B), 3]);
    end

    % 5) Draw background + overlay
    cla(ax);
    if isoOn
        B = computeStructuralBoundarySlice(ST, viewmode, si);
        hBkg = imagesc(A,'Parent',ax);
        set(hBkg,'HitTest','off','PickableParts','none');
        hold(ax,'on');
        contour(ax,B,[0.5 0.5],'k','LineWidth',0.8);
        hold(ax,'off');
    else
        hBkg = imagesc(A, 'Parent', ax);
    end
    set(hBkg,'HitTest','off', 'PickableParts', 'none');
    colormap(ax, 'gray');
    clim(ax, [0 1]);        % lock brightness scale
    hold(ax,'on');
    hO = imagesc(C, 'Parent', ax);
    set(hO, 'AlphaData', mask * alphaVal);
    set(hO,'HitTest','off','PickableParts', 'none');
    hold(ax,'off');

    % 6) Aspect & clean up
    if strcmp(viewmode,'axial') || strcmp(viewmode,'sagittal')
        axis(ax,'image');
    else
        axis(ax,'square');
    end
    set(ax,'XTick',[],'YTick',[]);
end

function drawColorbar(cmDiv, cmJet)
    % Clear out old content
    cla(hCbar);
    % Select map & tick values
    if hasNeg && hasPos
        map = cmDiv;                              % 256×3 diverging
        y   = [Tmin; thrNeg; 0; thrPos; Tmax];    % five ticks
    else
        map = cmJet;                              % 256×3 jet
        if hasPos
            y = [0; thr; Tmax];
        else
            y = [Tmin; thr; 0];
        end
    end

    % Draw the strip
    % Use imagesc where X runs from 0→1, Y covers the data range
    imagesc([0 1], [y(1) y(end)], permute(map,[1 3 2]), 'Parent', hCbar);
    % Force that axes to use its own colormap
    colormap(hCbar, map);
    % Lock axes limits and ticks
    set(hCbar, ...
        'YDir','normal', ...
        'XLim',[0 1], ...
        'YLim',[y(1) y(end)], ...
        'XTick',[], ...
        'YTick', y, ...
        'YTickLabel', arrayfun(@(v)sprintf('%.2f',v), y, 'Uniform',false));

    hold(hCbar,'on');
    % Grey‐out below negative threshold (if bipolar)
    if hasNeg && hasPos
       patch(hCbar,[0 1 1 0],[thrNeg thrNeg thrPos thrPos],[0.7 0.7 0.7], ...
        'FaceAlpha',0.6,'EdgeColor','none','Clipping','off');
    else
        % Single polarity: grey out the unused half
        if hasPos
            % grey below zero
            patch(hCbar, [0 1 1 0], [y(1) 0 0 y(1)], [0.7 0.7 0.7], ...
                  'FaceAlpha',0.4,'EdgeColor','none','Clipping','off');
        else
            % grey above zero
            patch(hCbar, [0 1 1 0], [0 y(end) y(end) 0], [0.7 0.7 0.7], ...
                  'FaceAlpha',0.4,'EdgeColor','none','Clipping','off');
        end
    end

    % ensure no x‐ticks
    set(hCbar,'XTick',[]);

set(hCbar,'ButtonDownFcn',@onCbarClick);
function onCbarClick(ax,~)
    cp = get(ax,'CurrentPoint'); val = cp(1,2);
    if hasNeg && hasPos
        if val < 0
            thrNeg = max(min(val,0),Tmin); set(hNegSlider,'Value',thrNeg); set(hNegEdit,'String',sprintf('%.2f',thrNeg));
        else
            thrPos = min(max(val,0),Tmax); set(hPosSlider,'Value',thrPos); set(hPosEdit,'String',sprintf('%.2f',thrPos));
        end
    else
        mn = hasNeg*Tmin + hasPos*0; mx = hasPos*Tmax + hasNeg*0;
        thr = min(max(val,mn),mx); set(hThrSlider,'Value',thr); set(hThrEdit,'String',sprintf('%.2f',thr));
    end
    requestRedraw();
end

    hold(hCbar,'off');
end

function [i, j, k] = get_ijk4click()
    
    i = []; j = []; k = [];
    pt  = hAx.CurrentPoint; % 2×3 – first row is the click
    row = round(pt(1,2)); 
    col = round(pt(1,1));
    
    if row<1||col<1, return; end
    
    % map pixel → voxel (exactly as before)
    switch viewmode
      case 'axial'
        i = row;       j = col;       k = sliceIdx;
      case 'sagittal'
        i = sliceIdx;  j = col;       k = dims(3)-row+1;
      case 'coronal'
        i = col;       j = sliceIdx;  k = dims(3)-row+1;
    end

end

function [i,j,k,space_used] = get_ijk4click3D(evt, hAx, parent)
% Convert a 3D click to structural voxel indices (i,j,k).
% Works whether the intersection point is in world-mm or voxel space.
%
% Returns space_used = 'mm' or 'vox' to show which interpretation was chosen.

    i=[]; j=[]; k=[]; space_used = '';

    % 1) Get a 3D point from the event (fallback to axes CurrentPoint)
    if isstruct(evt) && isfield(evt,'IntersectionPoint') && ~isempty(evt.IntersectionPoint)
        ip = evt.IntersectionPoint(:);       % 3x1
    else
        cp = get(hAx,'CurrentPoint');        % 2x3
        ip = cp(1,:).';
    end
    if isempty(ip), return; end

    % 2) Fetch Vs header (structural)
    Vs = getappdata(parent,'Vs_hdr');
    if isempty(Vs) || ~isfield(Vs,'mat') || ~isfield(Vs,'dim'), return; end
    dim = double(Vs.dim(:))';               % [Ni Nj Nk]

    % 3) Try both hypotheses and choose the plausible one
    % H1: ip is world mm
    vox_mm = Vs.mat \ [ip;1];               % (x,y,z) voxel (0-based)
    ijk_mm = [vox_mm(2)+1, vox_mm(1)+1, vox_mm(3)+1];

    % H2: ip is already voxels
    ijk_vox = [ip(2)+1, ip(1)+1, ip(3)+1];

    % “Out-of-bounds” score before clamping
    oob1 = sum(ijk_mm  < 1 | ijk_mm  > dim+0.5);
    oob2 = sum(ijk_vox < 1 | ijk_vox > dim+0.5);

    if oob1 <= oob2
        ijk = ijk_mm;   space_used = 'mm';
    else
        ijk = ijk_vox;  space_used = 'vox';
    end

    % 4) Round & clamp
    ijk = round(ijk);
    ijk = max([1 1 1], min(dim, ijk));
    i = ijk(1); j = ijk(2); k = ijk(3);
end

function [A, B] = extract_reorient_vols(si)
    
    % Extract & orient A,B
    switch viewmode
        case 'axial'
            A = squeeze(ST(:,:,si)); B = squeeze(T(:,:,si));
        case 'sagittal'
            A = flipud(squeeze(ST(si,:,:))');  B = flipud(squeeze(T(si,:,:))');
        case 'coronal'
            A = flipud(squeeze(ST(:,si,:))');  B = flipud(squeeze(T(:,si,:))');
    end
end

function codes = struct2atlas(ijkStruct, Vs, VatOrig, AtlasOrig)
% STRUCT2ATLAS   Map structural‐voxel(s) → atlas label code(s)
%
%   codes = struct2atlas(ijkStruct, Vs, VatOrig, AtlasOrig)
%
%   ijkStruct  : 3×N array of 1-based [i;j;k] structural voxel indices
%   Vs         : spm_vol struct of the structural image
%   VatOrig    : spm_vol struct of the original atlas image
%   AtlasOrig  : 3D array of integer labels from spm_read_vols(VatOrig)
%
%   codes : N×1 vector of integer ROI codes (0 if out of bounds)

    % ensure size = 3×N
    assert(size(ijkStruct,1)==3,'ijk-struct must be 3×N');
    N = size(ijkStruct,2);

    % build homogeneous structural coords (0-based)
    voxStr0 = [ double(ijkStruct(1,:))-1; ...
                double(ijkStruct(2,:))-1; ...
                double(ijkStruct(3,:))-1; ...
                ones(1,N)              ];   % 4×N

    % map structural → atlas  (0-based floats)
    voxAtl0_h = VatOrig.mat \ (Vs.mat * voxStr0);  % 4×N

    % round & shift → 1-based atlas voxels
    ijkAtl = round(voxAtl0_h(1:3,:)) + 1;          % 3×N

    % bounds‐check
    ok = ijkAtl(1,:)>=1 & ijkAtl(1,:)<=VatOrig.dim(1) & ...
         ijkAtl(2,:)>=1 & ijkAtl(2,:)<=VatOrig.dim(2) & ...
         ijkAtl(3,:)>=1 & ijkAtl(3,:)<=VatOrig.dim(3);

    % preallocate
    codes = zeros(N,1);

    % linear indices of valid points
    lin = sub2ind(VatOrig.dim, ...
                 ijkAtl(1,ok), ijkAtl(2,ok), ijkAtl(3,ok));

    % sample
    vals = AtlasOrig(lin);
    codes(ok) = round(vals);
end

function B = computeROIBoundaryOnTheFly(AtlasOrig, Vs, VatOrig, viewmode, sliceIdx)
    %COMPUTEROIBOUNDARYONTHEFLY  2D boundary mask for a single atlas slice  
    %   B = computeROIBoundaryOnTheFly(AtlasOrig, Vs, VatOrig, viewmode, sliceIdx)
    %   - AtlasOrig : 3D label array (original atlas, no reslice file)
    %   - Vs        : spm_vol struct of your structural reference
    %   - VatOrig   : spm_vol struct of the same original atlas
    %   - viewmode      : 'axial' | 'sagittal' | 'coronal'
    %   - sliceIdx  : slice number *in structural space* along that viewmode
    %
    %   Returns logical B(rows,cols) == true wherever two neighboring pixels
    %   belong to different ROI labels.
    
    %% 0) dimensions
    dims = Vs.dim;     % [nx ny nz]
    
    %% 1) Build (i,j,k) grid of structural‐voxel coords for this slice
    switch viewmode
      case 'axial'
        % slice through Z -> matrix is [nx × ny]
        [cG,rG] = meshgrid(1:dims(2), 1:dims(1));
        i = rG(:);
        j = cG(:);
        k = sliceIdx * ones(size(i));
    
      case 'sagittal'
        % slice through X -> matrix is [nz × ny]
        [cG,rG] = meshgrid(1:dims(2), 1:dims(3));
        i = sliceIdx * ones(size(rG(:)));
        j = cG(:);
        k = dims(3) - rG(:) + 1;
    
      case 'coronal'
        % slice through Y -> matrix is [nz × nx]
        [cG,rG] = meshgrid(1:dims(1), 1:dims(3));
        i = cG(:);
        j = sliceIdx * ones(size(rG(:)));
        k = dims(3) - rG(:) + 1;
    
      otherwise
        error('Unknown viewmode "%s"', viewmode);
    end
    n = numel(i);
    nrows = size(rG,1);
    ncols = size(cG,2);
    
    %% 2) Map each structural voxel -> atlas voxel (0-based -> 1-based)
    % 2a) 0-based homogeneous structural coords (4×n)
    voxStr0 = [ double(i(:)') - 1; ...
                double(j(:)') - 1; ...
                double(k(:)') - 1; ...
                ones(1,n)           ];
    
    % 2b) structural-voxel0 -> atlas-voxel0 (4×n)
    voxAtl0_h = VatOrig.mat \ (Vs.mat * voxStr0);
    
    % 2c) round & shift to 1-based atlas‐voxel indices (3×n)
    ijkAtl = round(voxAtl0_h(1:3,:)) + 1;
    
    % 2d) bounds‐check
    valid = ...
        ijkAtl(1,:)>=1 & ijkAtl(1,:)<=VatOrig.dim(1) & ...
        ijkAtl(2,:)>=1 & ijkAtl(2,:)<=VatOrig.dim(2) & ...
        ijkAtl(3,:)>=1 & ijkAtl(3,:)<=VatOrig.dim(3);
    
    % 2e) sample labels (out-of‐bounds → 0)
    codeGrid = zeros(n,1);
    idxV = find(valid);
    lin   = sub2ind(VatOrig.dim, ...
                    ijkAtl(1,idxV), ijkAtl(2,idxV), ijkAtl(3,idxV));
    codeGrid(idxV) = AtlasOrig(lin);
    
    %% 3) reshape back into 2D label map
    labelMap = reshape(codeGrid, nrows, ncols);
    
    %% 4) detect 4‐connected boundaries
    B = false(nrows,ncols);
    B = B | (labelMap ~= circshift(labelMap, [ 1,  0]));  % north
    B = B | (labelMap ~= circshift(labelMap, [-1,  0]));  % south
    B = B | (labelMap ~= circshift(labelMap, [ 0,  1]));  % east
    B = B | (labelMap ~= circshift(labelMap, [ 0, -1]));  % west
    
    % remove wrap-around artifacts
    B(1,   :) = false;
    B(end, :) = false;
    B(:,   1) = false;
    B(:, end) = false;

    B = bwmorph(B, 'thin', Inf);

end

function B = computeStructuralBoundarySlice(ST, viewmode, sliceIdx)
% COMPUTESTRUCTURALBOUNDARYSLICENOIP   Canny-style edges without IP toolbox
%   B = computeStructuralBoundarySliceNoIP(ST, viewmode, sliceIdx)
%   ST        : 3D structural volume
%   viewmode     : 'axial' | 'sagittal' | 'coronal'
%   sliceIdx : slice index in structural (voxel) space
%
%   Returns B as a 2D logical mask of edge pixels.

    %% 1) extract & orient slice
    switch viewmode
      case 'axial'
        A = squeeze(ST(:,:,sliceIdx));
      case 'sagittal'
        tmp = squeeze(ST(sliceIdx,:,:))';
        A   = flipud(tmp);
      case 'coronal'
        tmp = squeeze(ST(:,sliceIdx,:))';
        A   = flipud(tmp);
      otherwise
        error('Unknown viewmode "%s"',viewmode);
    end

    %% 2) normalize to [0,1]
    A = A - min(A(:));
    A = A ./ max(A(:));

    %% 3) Gaussian smoothing (separable)
    sigma = 1;                     % ↑ more smoothing
    r     = ceil(2*sigma);
    x     = -r:r;
    G     = exp(-(x.^2)/(2*sigma^2));
    G     = G/sum(G);
    A_sm  = conv2(G', 1, A, 'same');
    A_sm  = conv2(1, G , A_sm, 'same');

    %% 4) compute gradients with Sobel kernels
    sobelX = [1 0 -1; 2 0 -2; 1 0 -1];
    sobelY = sobelX';
    Ix = conv2(A_sm, sobelX, 'same');
    Iy = conv2(A_sm, sobelY, 'same');
    Mag   = hypot(Ix, Iy);
    Theta = atan2(Iy, Ix) * (180/pi);
    Theta(Theta<0) = Theta(Theta<0) + 180;

    %% 5) non‐maximum suppression
    [nr,nc] = size(Mag);
    NMS = zeros(nr,nc);
    for r0 = 2:nr-1
      for c0 = 2:nc-1
        ang = Theta(r0,c0);
        m   = Mag(r0,c0);
        % find neighbors along gradient direction
        if (ang < 22.5) || (ang >=157.5)
          m1 = Mag(r0, c0-1); m2 = Mag(r0, c0+1);
        elseif (ang < 67.5)
          m1 = Mag(r0-1, c0+1); m2 = Mag(r0+1, c0-1);
        elseif (ang <112.5)
          m1 = Mag(r0-1, c0); m2 = Mag(r0+1, c0);
        else
          m1 = Mag(r0-1, c0-1); m2 = Mag(r0+1, c0+1);
        end
        if m>=m1 && m>=m2
          NMS(r0,c0) = m;
        end
      end
    end

    %% 6) double threshold & hysteresis
    highTFrac = 0.3;              % ↓ keep more edges
    lowTFrac  = 0.2;               % relative to high
    highT = max(NMS(:)) * highTFrac;
    lowT  = highT    * lowTFrac;
    strong = NMS >= highT;
    weak   = NMS >= lowT  & NMS < highT;
    B      = strong;

    % hysteresis: any weak connected to strong becomes strong
    prevCount = 0;
    while true
      % dilate current strong to neighbors
      dil = conv2(double(B), ones(3), 'same') > 0;
      new = weak & dil;
      B( new ) = true;
      weak(new) = false;
      if nnz(B)==prevCount, break; end
      prevCount = nnz(B);
    end

    %% 7) thin down any 2‐pixel edges
    B = bwmorph(B,'bridge');       % connect 1-pixel gaps
    B = bwmorph(B,'close',1);
    B = bwmorph(B,'thin',Inf);

    %% Done
end

function lut = readAtlasLUTAuto(lutFile)
% READATLASLUTAUTO  Read a multi-column LUT file with unknown delimiter/header
%   lut = readAtlasLUTAuto(lutFile)
%   Returns a containers.Map mapping integer codes → region names.

    %% 1) Peek first nonempty line to detect delimiter & header
    fid = fopen(lutFile,'r');
    assert(fid~=-1, 'Cannot open %s', lutFile);
    firstLine = '';
    while true
        t = fgetl(fid);
        if ~ischar(t), break; end
        if ~isempty(strtrim(t))
            firstLine = t;
            break;
        end
    end
    fclose(fid);
    assert(~isempty(firstLine), 'LUT file %s is empty', lutFile);

    % possible delimiters
    candidates = {'\t', ',', ';', ' '};
    counts     = cellfun(@(d) numel(strfind(firstLine,d)), candidates);
    [~, idxD]  = max(counts);
    delim      = candidates{idxD};

    % split and test numeric‐ness
    tokens = strsplit(firstLine, delim);
    isNum  = cellfun(@(s) ~isnan(str2double(s)), tokens);
    headerPresent = ~all(isNum);

    %% 2) Read into a table
    if headerPresent
        opts = detectImportOptions(lutFile, 'Delimiter', delim);
        %opts = setvaropts(opts, opts.VariableNames, 'WhitespaceRule','preserve');
        tbl  = readtable(lutFile, opts);
    else
        % no header: let readtable generate Var1,Var2,...
        tbl = readtable(lutFile, ...
                       'Delimiter',delim, ...
                       'ReadVariableNames',false);
        % rename to generic names
        nVar = width(tbl);
        tbl.Properties.VariableNames = strcat("Var", string(1:nVar));
    end

    %% 3) Identify code (numeric) vs name (text) columns
    vf = varfun(@(x) isnumeric(x), tbl, 'OutputFormat','uniform');
    codeVars = tbl.Properties.VariableNames(vf);
    if isempty(codeVars)
        error('No numeric column found for ROI codes.');
    end
    codeVar = codeVars{1};  % pick the first numeric column

    % text‐type columns
    tf = varfun(@(x) isstring(x) || iscellstr(x), tbl, 'OutputFormat','uniform');
    nameVars = tbl.Properties.VariableNames(tf);
    if isempty(nameVars)
        error('No text column found for ROI names.');
    end

    %% 4) If multiple name columns, ask user which one to use
    if numel(nameVars)>1
        [sel,ok] = listdlg( ...
          'PromptString','Select the ROI‐name column:', ...
          'ListString',nameVars, ...
          'SelectionMode','single' );
        if ~ok
            error('No ROI‐name column selected.');
        end
        nameVar = nameVars{sel};
    else
        nameVar = nameVars{1};
    end

    %% 5) Extract codes & names, build the map
    codes = tbl.(codeVar);
    names = tbl.(nameVar);
    % convert names to cell array of char
    if isstring(names)
        names = cellstr(names);
    elseif iscell(names) && isnumeric(names{1})
        % fallback if read incorrectly
        names = cellfun(@num2str, num2cell(names), 'Uni',false);
    end

    lut = containers.Map(double(codes), names);
end


function mclass = spm2matlabclass(dtcode)
    % Map SPM dt code to MATLAB class name
    switch dtcode
        case 2,  mclass='uint8';
        case 4,  mclass='int16';
        case 8,  mclass='int32';
        case 16, mclass='single';
        case 64, mclass='double';
        case 256,mclass='int8';
        case 512,mclass='uint16';
        case 768,mclass='uint32';
        otherwise,mclass='double';
    end
end

end

function lutFile = findAtlasLUT(atlasFile)
    [pn,name,~] = fileparts(atlasFile);
    cands = { ...
        fullfile(pn,[name '_LUT.txt']), ...   % our new pattern
        fullfile(pn,[name '.txt']), ...
        fullfile(pn,[name '.tsv']), ...
        fullfile(pn,[name '.csv']), ...
        fullfile(pn,[name '.nii.txt']) ...    % old pattern some users had
    };
    lutFile = '';
    for k=1:numel(cands)
        if exist(cands{k},'file'), lutFile = cands{k}; return; end
    end
end

function statV = sampleStatOnVertices_vox(overlayVerts, vnorm_vox, Vs, Vt, T, ~, depthMM, forceSrc)
% overlayVerts: [nV x 3] vertices in voxel coords of either Vs or Vt (x,y,z order)
% vnorm_vox:    [nV x 3] unit normals in the *same voxel space* as overlayVerts (outward)
% Vs, Vt:       SPM VOL structs
% T:            target volume data in Vt voxel grid
% depthMM:      inward depth in mm
% forceSrc:     optional 'Vs' or 'Vt' to skip auto-detection

    if nargin < 8, forceSrc = ''; end

    nV = size(overlayVerts,1);
    onesV = ones(nV,1);

    % ---------- decide the source space of overlayVerts ----------
    if strcmpi(forceSrc,'Vs')
        src = 'Vs';
    elseif strcmpi(forceSrc,'Vt')
        src = 'Vt';
    else
        % fractions of verts inside each grid (x~cols=dim(2), y~rows=dim(1), z~dim(3))
        inVt = mean( overlayVerts(:,1)>=0 & overlayVerts(:,1)<=Vt.dim(2)-1 & ...
                     overlayVerts(:,2)>=0 & overlayVerts(:,2)<=Vt.dim(1)-1 & ...
                     overlayVerts(:,3)>=0 & overlayVerts(:,3)<=Vt.dim(3)-1 );
        inVs = mean( overlayVerts(:,1)>=0 & overlayVerts(:,1)<=Vs.dim(2)-1 & ...
                     overlayVerts(:,2)>=0 & overlayVerts(:,2)<=Vs.dim(1)-1 & ...
                     overlayVerts(:,3)>=0 & overlayVerts(:,3)<=Vs.dim(3)-1 );
        src = iff(inVs > inVt, 'Vs', 'Vt');  % pick the better match
    end

    % helpers to swap [x y z] -> [I J K] (SPM expects [row col slice] = [y x z])
    swapXYZ_to_IJK = @(XYZ)[XYZ(:,2) XYZ(:,1) XYZ(:,3)];

    % ---------- positions & normals in *mm* from the true source space ----------
    if src == "Vs"
        % voxel->mm using Vs, with 1-based indices
        IJK_src = swapXYZ_to_IJK(overlayVerts) + 1;
        Xmm     = (Vs.mat * [IJK_src, onesV].').';  Xmm = Xmm(:,1:3);

        A_src   = Vs.mat(1:3,1:3);
        n_voxIJ = swapXYZ_to_IJK(vnorm_vox);
        n_mm    = (A_src * n_voxIJ.').';           % linear part only
    else % 'Vt'
        IJK_src = swapXYZ_to_IJK(overlayVerts) + 1;
        Xmm     = (Vt.mat * [IJK_src, onesV].').';  Xmm = Xmm(:,1:3);

        A_src   = Vt.mat(1:3,1:3);
        n_voxIJ = swapXYZ_to_IJK(vnorm_vox);
        n_mm    = (A_src * n_voxIJ.').';
    end

    % normalize mm-normals and flip inward
    nn = sqrt(sum(n_mm.^2,2)); nn(nn==0)=1;
    inward_mm = -n_mm ./ nn;

    % ---------- surface sample at depth 0 (already on Vt grid or needs mapping) ----------
    if src == "Vs"
        % map mm -> target voxel coordinates
        IJK_t = (Vt.mat \ [Xmm, onesV].').';  IJK_t = IJK_t(:,1:3);
    else
        % already expressed in Vt voxels
        IJK_t = IJK_src;
    end

    % round & clamp
    Ii = min(max(round(IJK_t(:,1)),1), Vt.dim(1));
    Ji = min(max(round(IJK_t(:,2)),1), Vt.dim(2));
    Ki = min(max(round(IJK_t(:,3)),1), Vt.dim(3));
    idx0  = sub2ind(Vt.dim, Ii, Ji, Ki);
    vals0 = double(T(idx0));

    % polarity mode
    hasPos = any(vals0 > 0); hasNeg = any(vals0 < 0);
    if     hasNeg && hasPos, mode = 1;
    elseif hasPos,             mode = 2;
    elseif hasNeg,             mode = 3;
    else,                      mode = 0;
    end
    acc = vals0;

    % ---------- inward multi-step in *mm* (view-independent) ----------
    if depthMM > 0
        nSteps = 6;
        for s = 2:nSteps
            dt      = (s-1) * (depthMM / (nSteps-1));
            Xstepmm = Xmm + inward_mm .* dt;
            IJK_t   = (Vt.mat \ [Xstepmm, onesV].').';  % mm -> target vox
            Ii = min(max(round(IJK_t(:,1)),1), Vt.dim(1));
            Ji = min(max(round(IJK_t(:,2)),1), Vt.dim(2));
            Ki = min(max(round(IJK_t(:,3)),1), Vt.dim(3));
            idxS  = sub2ind(Vt.dim, Ii, Ji, Ki);
            valsS = double(T(idxS));

            m = ~isnan(valsS);
            switch mode
                case 1 % mixed: greater |value|
                    take = false(nV,1);
                    take(m) = abs(valsS(m)) > abs(acc(m));
                    acc(take) = valsS(take);
                case 2 % positives only
                    acc(m) = max(acc(m), valsS(m));
                case 3 % negatives only
                    acc(m) = min(acc(m), valsS(m));
            end
        end
    end

    statV = acc;
end

function y = iff(cond, a, b)
if cond
    y=a; 
else 
    y=b; 
end
end

function fvOut = compactFV(fvIn, vertsNew, faceMask)
% compactFV  Keep only selected faces and reindex vertices.
%
% Inputs
%   fvIn.faces   : (F x 3) int32/double
%   fvIn.vertices: (V x 3)
%   vertsNew     : (V x 3) new vertex positions to use in the output
%                  (e.g., offset overlay vertices). If empty, uses fvIn.vertices.
%   faceMask     : (F x 1) logical, faces to keep
%
% Output
%   fvOut.faces   : (Fk x 3) reindexed faces
%   fvOut.vertices: (Vk x 3) compacted vertices
%   fvOut.old2new : (V x 1) int, 0 where unused; otherwise new index
%   fvOut.new2old : (Vk x 1) int, original vertex index for each new vertex

    % --- sanity checks ---
    if nargin < 3 || isempty(faceMask)
        faceMask = true(size(fvIn.faces,1),1);
    end
    if nargin < 2 || isempty(vertsNew)
        vertsNew = fvIn.vertices;
    end
    if size(fvIn.faces,2) ~= 3
        error('compactFV: faces must be (F x 3).');
    end
    if size(fvIn.vertices,2) ~= 3 || size(vertsNew,2) ~= 3
        error('compactFV: vertices must be (V x 3).');
    end
    if size(fvIn.vertices,1) ~= size(vertsNew,1)
        error('compactFV: vertsNew must have same V as fvIn.vertices.');
    end

    F = fvIn.faces(faceMask, :);     % faces to keep
    if isempty(F)
        fvOut.faces = zeros(0,3);
        fvOut.vertices = zeros(0,3);
        fvOut.old2new = zeros(size(fvIn.vertices,1),1);
        fvOut.new2old = zeros(0,1);
        return;
    end

    used = unique(F(:));             % vertex indices used by kept faces
    Vk = numel(used);

    old2new = zeros(size(fvIn.vertices,1),1);
    old2new(used) = 1:Vk;

    % remap faces to compact index space
    fvOut.faces = old2new(F);

    % compacted vertex array (use provided new positions)
    fvOut.vertices = vertsNew(used, :);

    % maps
    fvOut.old2new = old2new;      % length V, 0 where vertex was unused
    fvOut.new2old = used(:);      % length Vk, original vertex index for each new one
end

function icon = loadIconWithBackground(pngPath, bgColor, targetSize)
    % bgColor should be [R G B], e.g., [255 255 255] or [240 240 240]
    if nargin < 2
        bgColor = [240 240 240];  % light gray default
    end

    [img, ~, alpha] = imread(pngPath);

    % If no alpha, use image as is
    if isempty(alpha)
        icon = img;
    else
        % Flatten with background
        img = im2double(img);
        alpha = im2double(alpha);
        bg = reshape(bgColor / 255, 1, 1, 3);
        icon = bsxfun(@times, img, alpha) + bsxfun(@times, bg, 1 - alpha);
        icon = im2uint8(icon);
    end

    % Resize to fit button if needed
    if nargin > 2 && ~isempty(targetSize)
        icon = imresize(icon, targetSize);
    end
end